# Lightning Detector App

iOS app for Group 12's Senior Design project. Connects to the lightning detector hardware over Bluetooth and shows whether lightning has been detected nearby.

## What it does

- Scans for the lightning detector device over BLE
- Connects and listens for status updates from the ESP32
- Shows "All Clear" or "Lightning Detected" in real time
- Demo mode lets you test the status screen without hardware - WIP

## Files

| File | What it is |
|---|---|
| `BLEManager.swift` | Handles all Bluetooth scanning, connecting, and data receiving |
| `LightningStatus.swift` | Simple data model for the detector status |
| `ContentView.swift` | Routes between the scan screen and status screen |
| `ScanView.swift` | Screen for finding and connecting to the device |
| `StatusView.swift` | Screen that shows the live lightning status |

## Setup

1. Open `LightningDetector.xcodeproj` in Xcode
2. Plug in your iPhone and select it as the run target
3. Hit Run — Xcode will handle signing automatically with your Apple ID
4. If you get an "Untrusted Developer" error on your phone, go to **Settings → General → VPN & Device Management** and trust your Apple ID

## Demo mode

No hardware yet? Tap **Try Demo Mode** on the scan screen to simulate a connection. Once in, use the **Simulate Lightning / Simulate All Clear** button to toggle states.

## Connecting to hardware

The app looks for a BLE device broadcasting these UUIDs:

- **Service:** `4FAFC201-1FB5-459E-8FCC-C5C9C331914B`
- **Characteristic:** `BEB5483E-36E1-4688-B7F5-EA07361B26A8`

The ESP32 firmware needs to use these same UUIDs. The characteristic sends a single byte — `0x00` for safe, `0x01` for lightning detected.

## Built with

- Swift / SwiftUI
- CoreBluetooth
- Xcode 15+
- Target: iOS 17+
