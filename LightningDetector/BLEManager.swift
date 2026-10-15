import CoreBluetooth
import Combine
import Foundation

struct StrikeEvent: Identifiable {
    let id = UUID()
    let timestamp: Date
    let intensity: String
}

class BLEManager: NSObject, ObservableObject {

    // MARK: - Published State
    @Published var isScanning = false
    @Published var discoveredDevices: [CBPeripheral] = []
    @Published var connectedDevice: CBPeripheral?
    @Published var lightningStatus: LightningStatus = .safe
    @Published var connectionState: ConnectionState = .disconnected
    
    // NEW: Flashy Features State
    @Published var currentRSSI: Int = 0
    @Published var strikeHistory: [StrikeEvent] = []

    // MARK: - GATT UUIDs
    static let serviceUUID     = CBUUID(string: "4FAFC201-1FB5-459E-8FCC-C5C9C331914B")
    static let statusCharUUID  = CBUUID(string: "BEB5483E-36E1-4688-B7F5-EA07361B26A8")

    // MARK: - CoreBluetooth
    private var centralManager: CBCentralManager!
    private var statusCharacteristic: CBCharacteristic?
    private var rssiTimer: Timer?

    enum ConnectionState {
        case disconnected, scanning, connecting, connected
    }

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    func startScan() {
        guard centralManager.state == .poweredOn else { return }
        discoveredDevices.removeAll()
        isScanning = true
        connectionState = .scanning
        centralManager.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }

    func stopScan() {
        centralManager.stopScan()
        isScanning = false
    }

    func connect(_ peripheral: CBPeripheral) {
        stopScan()
        connectionState = .connecting
        centralManager.connect(peripheral)
    }

    func disconnect() {
        rssiTimer?.invalidate()
        if isMockMode {
            isMockMode = false
            connectionState = .disconnected
            lightningStatus = .safe
            strikeHistory.removeAll()
            return
        }
        guard let device = connectedDevice else { return }
        centralManager.cancelPeripheralConnection(device)
    }
    
    // MARK: - RSSI Polling
    func startRSSIPolling() {
        rssiTimer?.invalidate()
        rssiTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if self.isMockMode {
                self.currentRSSI = Int.random(in: -70...(-45))
            } else if self.connectionState == .connected {
                self.connectedDevice?.readRSSI()
            }
        }
    }

    // MARK: - Mock / Demo
    @Published var isMockMode = false

    func enterMockMode() {
        isMockMode = true
        connectionState = .connected
        lightningStatus = .safe
        strikeHistory.removeAll()
        startRSSIPolling()
    }

    func toggleMockStatus() {
        let isNowDetected = !lightningStatus.isDetected
        lightningStatus = LightningStatus(isDetected: isNowDetected, timestamp: .now)
        
        if isNowDetected {
            let intensity = ["High", "Critical", "Moderate"].randomElement()!
            strikeHistory.insert(StrikeEvent(timestamp: .now, intensity: intensity), at: 0)
        }
    }
}

// MARK: - CBCentralManagerDelegate
extension BLEManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn && connectionState == .scanning {
            startScan()
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let deviceName = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? ""
        if deviceName.contains("Lightning") {
            if !discoveredDevices.contains(where: { $0.identifier == peripheral.identifier }) {
                discoveredDevices.append(peripheral)
            }
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectedDevice = peripheral
        connectionState = .connected
        peripheral.delegate = self
        peripheral.discoverServices([BLEManager.serviceUUID])
        startRSSIPolling()
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        connectedDevice = nil
        statusCharacteristic = nil
        connectionState = .disconnected
        lightningStatus = .safe
        rssiTimer?.invalidate()
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        connectionState = .disconnected
    }
}

// MARK: - CBPeripheralDelegate
extension BLEManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services where service.uuid == BLEManager.serviceUUID {
            peripheral.discoverCharacteristics([BLEManager.statusCharUUID], for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        for char in characteristics where char.uuid == BLEManager.statusCharUUID {
            statusCharacteristic = char
            peripheral.setNotifyValue(true, for: char)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == BLEManager.statusCharUUID,
              let data = characteristic.value,
              let byte = data.first else { return }

        DispatchQueue.main.async {
            let isDetected = byte == 0x01
            self.lightningStatus = LightningStatus(isDetected: isDetected, timestamp: .now)
            
            if isDetected {
                self.strikeHistory.insert(StrikeEvent(timestamp: .now, intensity: "Hardware Trigger"), at: 0)
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        DispatchQueue.main.async {
            self.currentRSSI = RSSI.intValue
        }
    }
}
