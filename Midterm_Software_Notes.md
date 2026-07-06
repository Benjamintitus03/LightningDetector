# Software Design Notes — Midterm Report
# Benjamin Titus — Copy these into the WIP sections of the report

---

## For Section 2.3.4 — Software (replace the "WIP" at the bottom)

The software side of the project is split into two parts: the mobile application that runs on the user's phone, and the BLE firmware that runs on the ESP32 and handles the wireless communication between the hardware and the app.

For the mobile app, we decided early on to build natively for iOS using SwiftUI and Apple's CoreBluetooth framework. The main reason for going native rather than a cross-platform tool like React Native or Flutter is that CoreBluetooth is the most reliable and well-documented way to communicate with BLE devices on an iPhone. It gives us direct access to the Bluetooth stack without any third-party library sitting between our code and the phone's hardware. Since BLE communication is the entire point of the app, that matters a lot.

The app is organized into five Swift files. BLEManager handles all the Bluetooth work — scanning for devices, connecting, subscribing to data updates from the ESP32, and pushing that data to the UI. LightningStatus is a simple data model that holds a boolean and a timestamp representing the current detector state. ContentView acts as the router, deciding whether to show the scan screen or the status screen based on whether a device is connected. ScanView is the screen the user sees first, where they can find and connect to the lightning detector. StatusView is the main screen, showing either "All Clear" or "Lightning Detected" with a visual indicator and a timestamp for the last update.

One design decision worth noting is how we handle state in the app. We use SwiftUI's built-in state management, specifically @StateObject and @ObservedObject, which lets the UI automatically update the moment BLEManager receives new data from the ESP32. There is no polling, no timers, and no manual refresh logic. The ESP32 sends a notification over BLE whenever the lightning status changes, the app receives it, and the UI updates immediately. This keeps the app's response time well within the one-second spec.

We also built a demo mode into the app specifically for development and testing. Since the hardware is still in progress, demo mode lets us simulate a connected device and toggle between safe and detected states directly on the phone. This was important for testing the UI and animations before having actual hardware to connect to.

On the BLE firmware side, the ESP32 is configured as a GATT server, which is the standard Bluetooth Low Energy communication model. It advertises a custom service with a single characteristic that the app subscribes to. When the ESP32's detection logic flags a lightning event, it writes a single byte to that characteristic — 0x01 for detected, 0x00 for clear — and the phone receives that update automatically because it has subscribed to notifications. The single-byte protocol is intentionally simple right now, which leaves room to add more data fields later, such as estimated distance or strike count, without redesigning the communication layer.

---

## For Section 3.6 — Wireless Notification: BLE Radio Selection (replace "WIP")

One of the first hardware decisions that affected the software design was the choice of the ESP32 as the main microcontroller for the detector. The ESP32 includes an integrated Bluetooth 4.2 radio that supports both Bluetooth Classic and Bluetooth Low Energy. This eliminated the need for a separate BLE module entirely, which simplified both the hardware design and the firmware considerably.

The choice of BLE over Wi-Fi or Bluetooth Classic was straightforward. Wi-Fi requires the device to join a network, which is not practical for outdoor recreational use in a park or campsite where there is no guaranteed network infrastructure. Bluetooth Classic was considered but is generally designed for streaming audio and continuous high-bandwidth connections, and it consumes more power than BLE. For our application, the ESP32 only needs to push a small status update to a phone, which is exactly the kind of thing BLE is designed for. The low power consumption also aligns with the battery life requirements we outlined in section 2.3.1.

On the iOS side, Apple's CoreBluetooth framework handles all BLE communication natively and does not require any additional libraries or App Store entitlements beyond a single privacy description in the app's Info.plist file. The app declares itself as a GATT central (the device that initiates connections and receives data) and the ESP32 acts as a GATT peripheral (the device that advertises and sends data).

The GATT profile we designed for this system uses a custom 128-bit service UUID and a single characteristic UUID. These identifiers are what the app uses to find the correct device during scanning and to subscribe to the right data once connected. Both UUIDs are defined in the iOS app and will need to be matched exactly in the ESP32 firmware. The characteristic is configured for notifications, meaning the ESP32 pushes updates to the phone rather than the phone polling the ESP32 repeatedly. This is the standard approach for real-time sensor data over BLE and keeps the BLE traffic minimal.

The 100-foot BLE communication range in our engineering specifications is a conservative estimate based on the ESP32's typical output power in an indoor or open environment. In open outdoor conditions, the actual range can be somewhat longer, but 100 feet is a reasonable working assumption for a device being used at a picnic or campsite.

---

## For Chapter 7 — System Software Design (replace "WIP")

### 7.1 Overview

The software system for the lightning detector is divided into three layers: the firmware running on the ESP32 microcontroller, the BLE communication layer that bridges the hardware and the mobile app, and the iOS mobile application itself. Benjamin Titus is responsible for the mobile app, the BLE GATT profile design, and the BLE firmware on the ESP32. Beatriz Navas is responsible for the VLF detection and signal processing firmware. Will Zabin is responsible for the voice synthesizer firmware.

### 7.2 Mobile Application Architecture

The mobile application is a native iOS app built with Swift and SwiftUI, targeting iOS 17 and later. SwiftUI was chosen because it is Apple's current UI framework and handles reactive state updates cleanly — when the BLE connection state or the lightning status changes, the UI reflects that change instantly without requiring any manual update logic.

The app is structured around five source files:

**BLEManager.swift** is the core of the application. It is a class that manages the entire Bluetooth lifecycle. When the app launches, BLEManager creates a CoreBluetooth central manager and waits for the phone's Bluetooth radio to be ready. When the user taps Scan, it begins scanning specifically for devices advertising our custom GATT service UUID, so only our lightning detector shows up in the list rather than every Bluetooth device nearby. Once the user selects a device and the connection is established, BLEManager discovers the detector's service, finds the status characteristic, and subscribes to notifications. From that point on, any time the ESP32 sends an update, BLEManager receives it, decodes the single byte, creates a new LightningStatus value with the current timestamp, and publishes it. SwiftUI automatically re-renders the status screen when that published value changes.

**LightningStatus.swift** is the data model. It holds two things: a boolean indicating whether lightning is currently detected, and a timestamp for when that update was received. The timestamp lets the status screen show something like "Updated 2 minutes ago," which helps users know the device is still actively communicating and the status is not stale.

**ContentView.swift** is the top-level router. It checks the connection state of BLEManager and either shows the scan screen or the status screen. This keeps the navigation logic simple and all in one place.

**ScanView.swift** is the first screen the user sees. It shows a list of nearby BLE devices that match our service UUID, a scan/stop button, and a small "Try Demo Mode" button at the bottom for testing without hardware.

**StatusView.swift** is the main experience. It shows a large circular indicator that pulses when lightning is detected, the status text, a subtitle, and a relative timestamp. The icon transitions between a checkmark (safe) and a bolt (detected) using SwiftUI's symbol effect transition. In demo mode, a toggle button appears below the timestamp so the developer can simulate state changes.

### 7.3 BLE Communication Protocol

The GATT profile is designed to be as simple as possible at this stage while leaving room to expand later.

- **Service UUID:** 4FAFC201-1FB5-459E-8FCC-C5C9C331914B
- **Status Characteristic UUID:** BEB5483E-36E1-4688-B7F5-EA07361B26A8
- **Characteristic properties:** Notify
- **Data format:** Single byte (0x00 = clear, 0x01 = lightning detected)

The ESP32 firmware will need to advertise this service UUID and write to the characteristic whenever the detection state changes. The iOS app will automatically receive that notification and update the UI. Because the characteristic is notify-only at this stage, the phone receives updates when the ESP32 pushes them rather than the phone requesting them on a schedule. This is more efficient and keeps the BLE traffic low.

The single-byte format is intentional. When the distance estimation and directional trend firmware from Beatriz's side is ready, we can extend the protocol to include additional bytes for distance and trend data without changing the UUID or the subscription setup on the iOS side.

### 7.4 Version Control and Repository Setup

The project repository is hosted on GitHub and is organized to support work across multiple machines. The repository contains the full Xcode project at the root level along with a README that documents the file structure, setup steps, the BLE UUIDs, and the data protocol.

The branching strategy uses two branches: master, which holds stable working code, and develop-2nd-laptop, which is the active development branch used for day-to-day changes. When a feature is ready and tested, it gets merged into master. This keeps the master branch clean in case we need to demo or hand something to the review committee.

The repository is synced through OneDrive, which allows the project to be accessed from both a Windows machine and a Mac without needing to push and pull manually for every small change. The .xcodeproj file and all Swift source files live inside a LightningDetector subdirectory matching the standard Xcode project structure. The README is at the root of the repository.

### 7.5 iOS Deployment Plan

**Current state (development):** The app is signed with a personal Apple Developer account (free tier) and is deployed directly to a physical iPhone over USB via Xcode. This is sufficient for development and testing. The free account does not allow App Store distribution but allows running on up to a handful of personal devices, which is all we need for the demo and for testing with the hardware.

**Short-term (class demo and grading):** We will continue using direct USB deployment for the demo. If we want to share the app with other team members' phones for testing, we can add their device UDIDs to the provisioning profile under the free account, or upgrade to the paid Apple Developer Program if needed.

**Production iOS deployment:** For public distribution on the App Store, the process is as follows. First, enroll in the Apple Developer Program ($99/year). Then, in Xcode, set the build configuration to Release, create an Archive of the app, and submit it through App Store Connect. Apple reviews the app (typically a few days for a first submission) and then it becomes publicly available. Before submitting to the App Store, we would want to use TestFlight, Apple's beta testing platform, to distribute the app to a small group of testers without going through the full App Store review.

**Future Android support:** The current app is SwiftUI, which only runs on Apple platforms. When Android support becomes a priority, the recommended path is to rebuild the app using Flutter, Google's cross-platform framework that supports both iOS and Android from a single codebase. The BLE protocol we have designed is not platform-specific — the same service UUID, characteristic UUID, and byte protocol will work with Android's Bluetooth LE API as well. The main work would be rewriting the UI and BLE logic in Dart (Flutter's language), but the overall structure would be very similar to what we have now. React Native is another option, but Flutter has stronger native BLE support and is generally preferred for hardware-adjacent applications.

### 7.6 Demo Mode

A demo mode was added to the app to support development and testing before the hardware is complete. Tapping "Try Demo Mode" on the scan screen bypasses the BLE scan and sets the app into a simulated connected state. In this mode, the status screen shows "Demo Mode" in the connection bar instead of a device name, and a toggle button appears that lets the developer switch between the safe and detected states manually. Disconnecting from demo mode returns the app to the scan screen as normal. This was essential for iterating on the UI and animations without needing to have the ESP32 connected and running detection firmware every time a UI change was made.

---

## For the SOFTWARE DESIGN Scope section (items 2, 3, 4 — replace "WIP")

2. Design and implementation of the iOS mobile application frontend, including the scan screen for BLE device discovery, the real-time status screen displaying safe and detected states, connection state management, and demo mode for hardware-independent testing.

3. Design of the BLE GATT communication profile, including the custom service and characteristic UUIDs, the single-byte data protocol for lightning status updates, and the CoreBluetooth central manager implementation on the iOS side.

4. Version control infrastructure including GitHub repository setup, branching strategy (master/develop), cross-platform OneDrive sync, and documentation of the BLE protocol and app setup in the project README. iOS deployment pipeline using Xcode and the Apple Developer Program, with a migration path to Android via Flutter as a future deliverable.

---

## Extra context you can use anywhere in the report

**Why not React Native or Flutter from the start?**
Both are reasonable cross-platform options, but for a project where BLE is the entire communication mechanism, going native on iOS with CoreBluetooth removes one layer of abstraction. Cross-platform BLE libraries add complexity and sometimes have platform-specific quirks. Since we knew iOS was the initial target and Android was a stretch goal, native iOS was the cleaner choice. If Android becomes a concrete requirement before the project is done, it is worth revisiting Flutter at that point.

**Why a single byte for the data protocol?**
Keeping the initial protocol at one byte makes the early firmware and app integration as simple as possible. The format is easy to parse on both ends and leaves no ambiguity. Extending it later is straightforward — we can add a second byte for distance category (near/medium/far) and a third for directional trend (approaching/retreating) when that firmware is ready, without changing anything in the existing connection or subscription setup. That way the hardware team and the software side are not blocked on each other.

**On the Git repo and collaboration:**
The repository tracks all source code for the iOS app and will eventually include the ESP32 firmware as well. Having everything in one place makes it easier for the review committee to see the full scope of what was built and for the team to coordinate. The OneDrive sync means the Mac running Xcode and the Windows development machine stay in sync without extra steps.
