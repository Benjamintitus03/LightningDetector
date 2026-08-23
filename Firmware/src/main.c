#include <zephyr/kernel.h>
#include <zephyr/logging/log.h>
#include <zephyr/bluetooth/bluetooth.h>
#include <zephyr/bluetooth/hci.h>
#include <zephyr/bluetooth/conn.h>
#include <zephyr/bluetooth/uuid.h>
#include <zephyr/bluetooth/gatt.h>
#include <zephyr/audio/dmic.h>
#include <arm_math.h>

LOG_MODULE_REGISTER(lightning_pdm, LOG_LEVEL_INF);

/* 128-bit Service: 4FAFC201-1FB5-459E-8FCC-C5C9C331914B */
#define BT_UUID_LIGHTNING_SVC_VAL \
	BT_UUID_128_ENCODE(0x4FAFC201, 0x1FB5, 0x459E, 0x8FCC, 0xC5C9C331914B)

/* 128-bit Characteristic: BEB5483E-36E1-4688-B7F5-EA07361B26A8 */
#define BT_UUID_LIGHTNING_STAT_VAL \
	BT_UUID_128_ENCODE(0xBEB5483E, 0x36E1, 0x4688, 0xB7F5, 0xEA07361B26A8)

static struct bt_uuid_128 lightning_svc_uuid = BT_UUID_INIT_128(BT_UUID_LIGHTNING_SVC_VAL);
static struct bt_uuid_128 lightning_stat_uuid = BT_UUID_INIT_128(BT_UUID_LIGHTNING_STAT_VAL);

static struct bt_conn *active_conn;
static bool notify_enabled;
static uint8_t current_status = 0x00; /* 0x00 = Clear, 0x01 = Detected */

/* PDM Audio Parameters */
#define SAMPLE_RATE_HZ     16000
#define BLOCK_SIZE_SAMPLES 512
#define THUNDER_RMS_THRESH 18000   /* Tunable sound pressure threshold */

static int16_t audio_buffer[BLOCK_SIZE_SAMPLES];
static const struct device *dmic_dev = DEVICE_DT_GET(DT_CHOSEN(zephyr_pdm));

static void ccc_cfg_changed(const struct bt_gatt_attr *attr, uint16_t value)
{
	notify_enabled = (value == BT_GATT_CCC_NOTIFY);
	LOG_INF("iOS Notification Subscription: %s", notify_enabled ? "ACTIVE" : "INACTIVE");
}

/* GATT Service Definition */
BT_GATT_SERVICE_DEFINE(lightning_svc,
	BT_GATT_PRIMARY_SERVICE(&lightning_svc_uuid),
	BT_GATT_CHARACTERISTIC(&lightning_stat_uuid.uuid,
			       BT_GATT_CHRC_NOTIFY,
			       BT_GATT_PERM_NONE,
			       NULL, NULL, NULL),
	BT_GATT_CCC(ccc_cfg_changed, BT_GATT_PERM_READ | BT_GATT_PERM_WRITE),
);

int send_status_notification(uint8_t status)
{
	if (!active_conn || !notify_enabled) {
		return -ENOTCONN;
	}
	current_status = status;
	LOG_INF("Transmitting status payload: 0x%02x", current_status);
	return bt_gatt_notify(active_conn, &lightning_svc.attrs[1], &current_status, sizeof(current_status));
}

static void connected(struct bt_conn *conn, uint8_t err)
{
	if (err) {
		LOG_ERR("BLE Connection error (0x%02x)", err);
		return;
	}
	active_conn = bt_conn_ref(conn);
	LOG_INF("Connected to iOS App!");
}

static void disconnected(struct bt_conn *conn, uint8_t reason)
{
	LOG_INF("Disconnected from iOS App (reason %u)", reason);
	if (active_conn) {
		bt_conn_unref(active_conn);
		active_conn = NULL;
		notify_enabled = false;
	}
}

BT_CONN_CB_DEFINE(conn_callbacks) = {
	.connected = connected,
	.disconnected = disconnected,
};

static const struct bt_data ad[] = {
	BT_DATA_BYTES(BT_DATA_FLAGS, (BT_LE_AD_GENERAL | BT_LE_AD_NO_BREDR)),
	BT_DATA_BYTES(BT_DATA_UUID128_ALL, BT_UUID_LIGHTNING_SVC_VAL),
};

static const struct bt_data sd[] = {
	BT_DATA(BT_DATA_NAME_COMPLETE, CONFIG_BT_DEVICE_NAME, sizeof(CONFIG_BT_DEVICE_NAME) - 1),
};

/* Acoustic Processing Engine */
static bool analyze_acoustic_frame(const int16_t *pcm_data, size_t num_samples)
{
	q63_t sum_squares = 0;
	for (size_t i = 0; i < num_samples; i++) {
		int32_t val = pcm_data[i];
		sum_squares += (val * val);
	}
	uint32_t rms_energy = (uint32_t)(sum_squares / num_samples);

	if (rms_energy > THUNDER_RMS_THRESH) {
		LOG_INF("Acoustic strike signature detected! RMS Energy: %u", rms_energy);
		return true;
	}
	return false;
}

int main(void)
{
	int err = bt_enable(NULL);
	if (err) {
		LOG_ERR("Bluetooth initialization failed (%d)", err);
		return err;
	}

	err = bt_le_adv_start(BT_LE_ADV_CONN, ad, ARRAY_SIZE(ad), sd, ARRAY_SIZE(sd));
	if (err) {
		LOG_ERR("Advertising failed to start (%d)", err);
		return err;
	}
	LOG_INF("BLE advertising as 'Lightning-Detector'");

	if (!device_is_ready(dmic_dev)) {
		LOG_ERR("PDM Microphone device not ready!");
		return -ENODEV;
	}

	struct dmic_cfg cfg = {
		.io = {
			.min_pdm_clk_freq = 1000000,
			.max_pdm_clk_freq = 3000000,
		},
		.streams = (struct pcm_stream_cfg[]) {
			{
				.pcm_rate = SAMPLE_RATE_HZ,
				.pcm_width = 16,
				.block_size_ms = (BLOCK_SIZE_SAMPLES * 1000) / SAMPLE_RATE_HZ,
				.mem_slab = NULL,
			},
		},
		.channel = {
			.req_num_chan = 1,
			.req_chan_map_lo = dmic_build_channel_map(0, 0, PDM_CHAN_LEFT),
		},
	};

	err = dmic_configure(dmic_dev, &cfg);
	if (err) {
		LOG_ERR("Failed to configure DMIC PDM interface (%d)", err);
		return err;
	}

	err = dmic_trigger(dmic_dev, DMIC_TRIGGER_START);
	if (err) {
		LOG_ERR("Failed to start DMIC audio streaming (%d)", err);
		return err;
	}

	LOG_INF("Acoustic monitoring active. Listening for sound events...");

	while (1) {
		err = dmic_read(dmic_dev, 0, audio_buffer, sizeof(audio_buffer), 1000);
		if (err == 0) {
			if (analyze_acoustic_frame(audio_buffer, BLOCK_SIZE_SAMPLES)) {
				/* Fire BLE alert to iPhone */
				send_status_notification(0x01);

				/* Hold detected state for 3 seconds then return to clear */
				k_sleep(K_SECONDS(3));
				send_status_notification(0x00);
			}
		}
		k_msleep(10);
	}
	return 0;
}