# Lightning Detector

Portable lightning detection safety device for picnickers — UCF Senior Design Group 12.

The system detects nearby lightning via a VLF radio receiver and notifies users through audible voice alerts, LEDs, and a companion iOS app over Bluetooth Low Energy.

## Team

| Name | Discipline | Responsibilities |
|---|---|---|
| Benjamin Titus | Computer Engineering | iOS app, BLE GATT profile, BLE firmware (nRF54L20-DK) |
| Beatriz Navas | Computer Engineering | Detector/emulator firmware, lightning detection algorithm |
| David Zima | Electrical Engineering | VLF RF hardware, antennas, BLE antenna/matching |
| Will Zabin | Electrical Engineering | Voice synthesizer (ISD2360), enclosure, button interface |

## System Overview

The project has two hardware units:

**Lightning Detector**
- VLF radio receiver (ferrite rod antenna, 500 kHz) detects EM emissions from lightning strikes
- AS3935 Franklin Lightning Sensor IC (ScioSense) via SPI — signal validation, disturber rejection, distance estimation up to 40 km
- ESP32 MCU — runs detection algorithm, classifies strikes (near/medium/far), estimates directional trend
- Nordic nRF54L20-DK — BLE GATT server, pushes status to iOS app
- Nuvoton ISD2360 — SPI-controlled voice playback IC for spoken alerts ("Lightning Detected", "Seek shelter")
- LED + piezo buzzer for local visual/audio alerts

**Lightning Emulator**
- PIC16F1789 MCU generates test VLF signals in the 3–30 kHz range
- Used to test the detector without waiting for actual storms
- Manual and automatic strike pattern modes

## Mobile Application

Native iOS app built with SwiftUI and CoreBluetooth, targeting iOS 17+.

### App Structure

| File | Purpose |
|---|---|
| `BLEManager.swift` | Manages the full BLE lifecycle — scanning, connecting, subscribing to notifications, decoding data |
| `LightningStatus.swift` | Data model: `isDetected` bool + `timestamp` of last update |
| `ContentView.swift` | Top-level router — shows ScanView or StatusView based on connection state |
| `ScanView.swift` | Device discovery UI — lists nearby BLE peripherals matching the service UUID |
| `StatusView.swift` | Live status display — pulsing ring, bolt/checkmark icon, relative timestamp |
| `LightningDetectorApp.swift` | App entry point |

### BLE Communication Protocol

The iOS app acts as a **BLE Central**. The nRF54L20-DK acts as a **BLE Peripheral / GATT Server**.

| Field | Value |
|---|---|
| Service UUID | `4FAFC201-1FB5-459E-8FCC-C5C9C331914B` |
| Status Characteristic UUID | `BEB5483E-36E1-4688-B7F5-EA07361B26A8` |
| Characteristic properties | Notify |
| Data format | Single byte: `0x00` = All Clear, `0x01` = Lightning Detected |

The phone subscribes to notifications on the characteristic. The Nordic chip pushes updates whenever detection state changes — no polling. The single-byte protocol is intentionally minimal and will be extended with distance and direction bytes once the detection algorithm is integrated.

### Demo Mode

Tap **Try Demo Mode** on the scan screen to simulate a connected device without hardware. Useful for UI development and testing. A toggle button appears on the status screen to switch between safe and detected states.

## BLE Firmware (nRF54L20-DK)

Built with **nRF Connect SDK (NCS)** on Zephyr RTOS. Board target: `nrf54l20dk/nrf54l20/cpuapp`.

### Status
- GATT server advertising the custom service UUID: **working**
- iOS app integration test (notification received, UI updated): **passed**
- Integration with ESP32 detection data via UART: **in progress**

### Remaining firmware work
1. UART bridge — receive detection byte from ESP32, write to BLE characteristic
2. Extend protocol to include distance category and directional trend bytes
3. Basic radio power management in idle state

## Repository Structure

```
LightningDetector/
├── LightningDetector/              # Xcode iOS app source
│   ├── BLEManager.swift
│   ├── ContentView.swift
│   ├── LightningDetectorApp.swift
│   ├── LightningStatus.swift
│   ├── ScanView.swift
│   ├── StatusView.swift
│   └── Assets.xcassets/
├── LightningDetector.xcodeproj/
├── docs/
│   └── final-report.pdf            # UCF Senior Design final report
└── README.md
```

Firmware for the nRF54L20-DK will live in a `firmware/` directory once scaffolded.

## Development Setup

### iOS App (Mac)
1. Open `LightningDetector.xcodeproj` in Xcode 15+
2. Set your Apple Developer account in Signing & Capabilities
3. Build and run on a physical iPhone (iOS 17+) — BLE requires real hardware

### BLE Firmware (Mac)
1. Install **nRF Connect for Desktop** from nordicsemi.com
2. Use the **Toolchain Manager** plugin to install NCS v2.6 or later
3. Install the **nRF Connect for VS Code** extension pack
4. Connect the nRF54L20-DK via the DEBUG USB port
5. Build targeting `nrf54l20dk/nrf54l20/cpuapp` and flash via the VS Code extension

### Testing Without Hardware
- Use **Demo Mode** in the iOS app for UI/state testing
- Use **nRF Connect for Mobile** (App Store) to browse the GATT service and manually write characteristic values

## Branching Strategy

| Branch | Purpose |
|---|---|
| `master` | Stable, demo-ready code |
| `develop` | Active development |

Merge into `master` only when a feature is tested and working.

## Engineering Specs (highlighted)

| Spec | Target |
|---|---|
| BLE Communication Range | 100 ft |
| Mobile App Response Time | < 1 second |
| Alert Latency | 100 ms |
| Detection Distance Range | ~30 miles |

## References

- AS3935 Franklin Lightning Sensor IC — ScioSense: https://www.sciosense.com/as3935-franklin-lightning-sensor-ic/
- nRF54L20 Product Page — Nordic Semiconductor: https://www.nordicsemi.com
- Nuvoton ISD2360 — ISD-DEMO2360 User Manual: https://www.nuvoton.com/resource-files/EN_ISD-DEMO2360_User_Manual.pdf
- Full project documentation: `docs/final-report.pdf`

Moving forward:
  What's left on your plate (BLE firmware)

  Step 1 — Get your Mac NCS environment set up

  This is the prerequisite for everything else. On your Mac:

  1. Download nRF Connect for Desktop from nordicsemi.com
  2. Inside it, install the Toolchain Manager plugin
  3. Use Toolchain Manager to install NCS v2.6 or v2.7
  4. Install VS Code + the nRF Connect for VS Code extension pack
  5. Plug in the nRF54L20-DK via the DEBUG USB port — it should show up in the extension's device list
  6. Open an NCS sample (e.g. zephyr/samples/bluetooth/peripheral_hr) just to confirm you can build and flash

  That's your environment smoke test. Takes about 30–45 min the first time.

  ---
  Step 2 — Scaffold the real BLE firmware project

  Once your env works, you need a proper NCS project with:
  - Your custom GATT service (correct UUIDs, notify-only characteristic)
  - UART RX to receive data from the ESP32
  - Logic: receive byte on UART → write to characteristic → BLE notification fires to iPhone

  I can write this for you — it's about 3 files (main.c, prj.conf, CMakeLists.txt). The GATT service macro in Zephyr is
  straightforward once you know the pattern.

  ---
  Step 3 — UART bridge between ESP32 and Nordic

  The ESP32 runs the lightning algorithm. When it detects a strike, it needs to tell the Nordic chip. The simplest protocol: ESP32
  sends one byte over UART (0x01 detected, 0x00 clear) → Nordic receives it → writes to BLE characteristic → iPhone gets notified.

  You'll need to coordinate with Beatriz on which ESP32 UART TX pin to use and the baud rate.

  ---
  Step 4 — Extend the protocol (later)

  When Beatriz's distance/direction algorithm is ready, you add bytes 2 and 3 to the notification without changing UUIDs. The iOS
  app already handles this gracefully since it only reads data.first right now — you just add parsing