#include <zephyr/kernel.h>
#include <zephyr/sys/printk.h>
#include <zephyr/logging/log.h>
#include <zephyr/bluetooth/bluetooth.h>
#include <zephyr/bluetooth/hci.h>
#include <zephyr/bluetooth/conn.h>
#include <zephyr/bluetooth/uuid.h>
#include <zephyr/bluetooth/gatt.h>
#include <zephyr/audio/dmic.h>
#include <zephyr/drivers/uart.h>
#include <stdlib.h>

LOG_MODULE_REGISTER(lightning_pdm, LOG_LEVEL_INF);

/* BLE UUIDs mapped exactly to the iOS App */
#define BT_UUID_LIGHTNING_VAL \
    BT_UUID_128_ENCODE(0x4FAFC201, 0x1FB5, 0x459E, 0x8FCC, 0xC5C9C331914B)

#define BT_UUID_LIGHTNING_CHAR_VAL \
    BT_UUID_128_ENCODE(0xBEB5483E, 0x36E1, 0x4688, 0xB7F5, 0xEA07361B26A8)

static struct bt_uuid_128 lightning_svc_uuid = BT_UUID_INIT_128(BT_UUID_LIGHTNING_VAL);
static struct bt_uuid_128 lightning_char_uuid = BT_UUID_INIT_128(BT_UUID_LIGHTNING_CHAR_VAL);

static uint8_t detection_state = 0x00;
static uint8_t last_notified_state = 0xFF;
static struct bt_conn *current_conn;
static int64_t last_detection_time = 0;

static void ccc_cfg_changed(const struct bt_gatt_attr *attr, uint16_t value)
{
    ARG_UNUSED(attr);
    bool notif_enabled = (value == BT_GATT_CCC_NOTIFY);
    LOG_INF("Notifications %s", notif_enabled ? "enabled" : "disabled");
}

static ssize_t read_detection_state(struct bt_conn *conn, const struct bt_gatt_attr *attr,
                    void *buf, uint16_t len, uint16_t offset)
{
    return bt_gatt_attr_read(conn, attr, buf, len, offset, &detection_state, sizeof(detection_state));
}

BT_GATT_SERVICE_DEFINE(lightning_svc,
    BT_GATT_PRIMARY_SERVICE(&lightning_svc_uuid),
    BT_GATT_CHARACTERISTIC(&lightning_char_uuid.uuid,
                   BT_GATT_CHRC_READ | BT_GATT_CHRC_NOTIFY,
                   BT_GATT_PERM_READ,
                   read_detection_state, NULL, &detection_state),
    BT_GATT_CCC(ccc_cfg_changed, BT_GATT_PERM_READ | BT_GATT_PERM_WRITE),
);

static const struct bt_data ad[] = {
    BT_DATA_BYTES(BT_DATA_FLAGS, (BT_LE_AD_GENERAL | BT_LE_AD_NO_BREDR)),
    BT_DATA_BYTES(BT_DATA_UUID128_ALL, BT_UUID_LIGHTNING_VAL),
};

static const struct bt_data sd[] = {
    BT_DATA(BT_DATA_NAME_COMPLETE, "Lightning-Detector", 18),
};

static void connected(struct bt_conn *conn, uint8_t err)
{
    if (err) {
        LOG_ERR("Connection failed (err %u)", err);
        return;
    }
    LOG_INF("Connected to iOS App");
    current_conn = bt_conn_ref(conn);
}

static void disconnected(struct bt_conn *conn, uint8_t reason)
{
    LOG_INF("Disconnected (reason %u)", reason);
    if (current_conn) {
        bt_conn_unref(current_conn);
        current_conn = NULL;
    }

    int err = bt_le_adv_start(BT_LE_ADV_CONN_FAST_1, ad, ARRAY_SIZE(ad), sd, ARRAY_SIZE(sd));
    if (err) {
        LOG_ERR("Failed to restart advertising (err %d)", err);
    } else {
        LOG_INF("BLE advertising restarted.");
    }
}

BT_CONN_CB_DEFINE(conn_callbacks) = {
    .connected = connected,
    .disconnected = disconnected,
};

#define SAMPLE_RATE_HZ     16000
#define BLOCK_SIZE_SAMPLES 512
#define ENERGY_THRESHOLD   9000000 

K_MEM_SLAB_DEFINE_STATIC(mem_slab, BLOCK_SIZE_SAMPLES * 2 * sizeof(int16_t), 4, 4);

static void notify_detection(uint8_t state)
{
    detection_state = state;
    if (current_conn && (state != last_notified_state)) {
        bt_gatt_notify(current_conn, &lightning_svc.attrs[1], &detection_state, sizeof(detection_state));
        last_notified_state = state;
    }
}

static void reset_detection_work(struct k_work *work)
{
    LOG_INF("Resetting detection state to All Clear (0x00)");
    notify_detection(0x00);
}
K_WORK_DELAYABLE_DEFINE(reset_work, reset_detection_work);

/* Triggered by PDM Microphone acoustic processing */
static void trigger_acoustic_alert(void)
{
    int64_t now = k_uptime_get();
    if (now - last_detection_time > 3000) {
        LOG_INF("🔊 Acoustic Thunder Detected!");
        notify_detection(0x01);
        last_detection_time = now;
        k_work_reschedule(&reset_work, K_MSEC(3000));
    }
}

/* Triggered by Beatriz's board over UART */
static void trigger_hardware_lightning_alert(uint8_t state_code, const char *desc)
{
    int64_t now = k_uptime_get();
    if (state_code == 0x02 && (now - last_detection_time > 3000)) {
        LOG_INF("⚡ %s", desc);
        notify_detection(0x02);
        last_detection_time = now;
        k_work_reschedule(&reset_work, K_MSEC(3000));
    } else if (state_code == 0x00) {
        notify_detection(0x00);
    }
}

static void uart_cb(const struct device *dev, void *user_data)
{
    uint8_t c;
    if (!uart_irq_update(dev)) {
        return;
    }

    /* Read the error to unfreeze the hardware, but DO NOT return silently! */
    int err_code = uart_err_check(dev);
    if (err_code != 0) { 
        printk("⚠️ UART ERROR CODE: %d (Framing mismatch or noise)\n", err_code);
    }

    if (uart_irq_rx_ready(dev)) {
        while (uart_fifo_read(dev, &c, 1) == 1) {
            printk("HEARD FROM PIC: 0x%02X ('%c')\n", c, (c >= 32 && c <= 126) ? c : '.');
            
            if (c == 0x01 || c == 'S') {
                trigger_hardware_lightning_alert(0x02, "Lightning Strike Detected via UART!");
            } 
            else if (c == 0x00 || c == 'k') {
                trigger_hardware_lightning_alert(0x00, "System Status: CLEAR");
            }
        }
    }
}

int main(void)
{
    int err;
    const struct device *dmic_dev = DEVICE_DT_GET(DT_CHOSEN(zephyr_pdm));
    const struct device *uart_dev = DEVICE_DT_GET(DT_NODELABEL(uart30));

    LOG_INF("Starting Lightning Detector on nRF54LM20...");

    if (!device_is_ready(uart_dev)) {
        LOG_ERR("UART30 device not ready!");
        return 0;
    } else {
        LOG_INF("SUCCESS: UART30 is ready and bound to P0.04!");
    }

    uart_irq_callback_user_data_set(uart_dev, uart_cb, NULL);
    uart_irq_rx_enable(uart_dev);

    if (!device_is_ready(dmic_dev)) {
        LOG_ERR("PDM microphone device not ready");
        return 0;
    }

    err = bt_enable(NULL);
    if (err) {
        LOG_ERR("Bluetooth init failed");
        return 0;
    }

    err = bt_le_adv_start(BT_LE_ADV_CONN_FAST_1, ad, ARRAY_SIZE(ad), sd, ARRAY_SIZE(sd));
    if (err) {
        LOG_ERR("Advertising failed");
        return 0;
    }
    LOG_INF("BLE advertising active as 'Lightning-Detector'");

    struct pcm_stream_cfg stream = {
        .pcm_rate = SAMPLE_RATE_HZ,
        .pcm_width = 16,
        .block_size = BLOCK_SIZE_SAMPLES * 2 * sizeof(int16_t),
        .mem_slab = &mem_slab,
    };

    struct dmic_cfg cfg = {
        .io = {
            .min_pdm_clk_freq = 1000000,
            .max_pdm_clk_freq = 1600000,
            .min_pdm_clk_dc = 40,
            .max_pdm_clk_dc = 60,
        },
        .streams = &stream,
        .channel = {
            .req_num_streams = 1,
            .req_num_chan = 2,
            .req_chan_map_lo = dmic_build_channel_map(0, 0, PDM_CHAN_LEFT) |
                               dmic_build_channel_map(1, 0, PDM_CHAN_RIGHT),
        },
    };

    dmic_configure(dmic_dev, &cfg);
    dmic_trigger(dmic_dev, DMIC_TRIGGER_START);

    LOG_INF("Acoustic monitoring active. Threshold: %u", (uint32_t)ENERGY_THRESHOLD);

    while (1) {
        void *audio_buf = NULL;
        size_t size = 0;

        err = dmic_read(dmic_dev, 0, &audio_buf, &size, 1000);
        if (err == 0 && audio_buf != NULL) {
            int16_t *samples = (int16_t *)audio_buf;
            int count = size / sizeof(int16_t);

            int16_t peak_val = 0;
            uint64_t energy_accum = 0;

            for (int i = 0; i < count; i++) {
                int32_t val = (int32_t)samples[i];
                if (abs(val) > peak_val) {
                    peak_val = abs(val);
                }
                energy_accum += (uint64_t)(val * val);
            }

            uint32_t energy = (count > 0) ? (uint32_t)(energy_accum / count) : 0;

            if (energy > ENERGY_THRESHOLD || peak_val > 12000) {
                trigger_acoustic_alert();
            }

            k_mem_slab_free(&mem_slab, audio_buf);
        }
        k_yield();
    }

    return 0;
}