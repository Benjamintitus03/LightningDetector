import CoreBluetooth
import Combine

class BLEManager: NSObject, ObservableObject {

    // MARK: - Published State
    @Published var isScanning = false
    @Published var discoveredDevices: [CBPeripheral] = []
    @Published var connectedDevice: CBPeripheral?
    @Published var lightningStatus: LightningStatus = .safe
    @Published var connectionState: ConnectionState = .disconnected

    // MARK: - GATT UUIDs — must match ESP32 firmware
    static let serviceUUID     = CBUUID(string: "4FAFC201-1FB5-459E-8FCC-C5C9C331914B")
    static let statusCharUUID  = CBUUID(string: "BEB5483E-36E1-4688-B7F5-EA07361B26A8")

    // MARK: - CoreBluetooth
    private var centralManager: CBCentralManager!
    private var statusCharacteristic: CBCharacteristic?

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
        centralManager.scanForPeripherals(withServices: [BLEManager.serviceUUID])
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
        if isMockMode {
            isMockMode = false
            connectionState = .disconnected
            lightningStatus = .safe
            return
        }
        guard let device = connectedDevice else { return }
        centralManager.cancelPeripheralConnection(device)
    }

    // MARK: - Mock / Demo
    @Published var isMockMode = false

    func enterMockMode() {
        isMockMode = true
        connectionState = .connected
        lightningStatus = .safe
    }

    func toggleMockStatus() {
        lightningStatus = LightningStatus(isDetected: !lightningStatus.isDetected, timestamp: .now)
    }
}

// MARK: - CBCentralManagerDelegate
extension BLEManager: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn && connectionState == .scanning {
            startScan()
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard !discoveredDevices.contains(peripheral) else { return }
        discoveredDevices.append(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectedDevice = peripheral
        connectionState = .connected
        peripheral.delegate = self
        peripheral.discoverServices([BLEManager.serviceUUID])
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        connectedDevice = nil
        statusCharacteristic = nil
        connectionState = .disconnected
        lightningStatus = .safe
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
            self.lightningStatus = LightningStatus(isDetected: byte == 0x01, timestamp: .now)
        }
    }
}
