# Lightning Detector App
# WIP!!


iOS app to Connects to the lightning detector hardware over Bluetooth and shows whether lightning has been detected nearby.

## What it does

- Scans for the lightning detector device over BLE
- Connects and listens for status updates from the ESP32
- Shows "All Clear" or "Lightning Detected" in real time

## Files

| File | What it is |
|---|---|
| `BLEManager.swift` | Handles all Bluetooth scanning, connecting, and data receiving |
| `LightningStatus.swift` | Simpl status |
| `ContentView.swift` | Routes between the scan screen and status screen |
| `ScanView.swift` | Screen for fdevice |
| `StatusView.swift` | Screen that shows the live lightning status |



## Connecting to hardware

The app looks for a BLE device broadcasting these UUIDs:

- **Service:** `4FAFC201-1FB5-459E-8FCC-C5C9C331914B`
- **Characteristic:** `BEB5483E-3

The ESP32 firmware needs to use tristic sends a single byte — `0x00
` for safe, `0x01` for lightning detected.

## Built with

- Swift / SwiftUI
- CoreBluetooth
- Xcode 15+
- Target: iOS 17+
