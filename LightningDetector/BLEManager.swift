import CoreBluetooth
import Combine

class BLEManager: NSObject, ObservableObject {

    // MARK: - Published State
    @Published var isScanning = false
    @Published var discoveredDevices: [CBPeripheral] = []
    @Published var connectedDevice: CBPeripheral?
    @Published var lightningStatus: LightningStatus = .safe
    @Published var connectionState: ConnectionState = .disconnected

    // MARK: - GATT UUIDs
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
        guard centralManager.state == .poweredOn else {
            print("Cannot scan: Bluetooth is not powered on.")
            return
        }
        discoveredDevices.removeAll()
        isScanning = true
        connectionState = .scanning
        
        print("Started scanning...")
        // Passing 'nil' bypasses the strict iOS UUID filter. We will manually filter below.
        centralManager.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }

    func stopScan() {
        centralManager.stopScan()
        isScanning = false
        print("Stopped scanning.")
    }

    func connect(_ peripheral: CBPeripheral) {
        stopScan()
        connectionState = .connecting
        print("Connecting to \(peripheral.name ?? "Unknown")...")
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
        print("Central Manager State: \(central.state.rawValue)")
        if central.state == .poweredOn && connectionState == .scanning {
            startScan()
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        
        // Extract the name from the peripheral object OR the advertisement packet
        let deviceName = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? ""
        
        // Only add it to our UI if it is our detector
        if deviceName.contains("Lightning") {
            print("⚡ FOUND DETECTOR! RSSI: \(RSSI)")
            print("Advertisement Data: \(advertisementData)")
            
            // Prevent duplicates
            if !discoveredDevices.contains(where: { $0.identifier == peripheral.identifier }) {
                discoveredDevices.append(peripheral)
            }
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("Successfully connected!")
        connectedDevice = peripheral
        connectionState = .connected
        peripheral.delegate = self
        // Discover our specific service
        peripheral.discoverServices([BLEManager.serviceUUID])
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        print("Disconnected.")
        connectedDevice = nil
        statusCharacteristic = nil
        connectionState = .disconnected
        lightningStatus = .safe
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        print("Failed to connect.")
        connectionState = .disconnected
    }
}

// MARK: - CBPeripheralDelegate
extension BLEManager: CBPeripheralDelegate {

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services where service.uuid == BLEManager.serviceUUID {
            print("Discovered Lightning Service!")
            peripheral.discoverCharacteristics([BLEManager.statusCharUUID], for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        for char in characteristics where char.uuid == BLEManager.statusCharUUID {
            print("Discovered Status Characteristic! Subscribing to notifications...")
            statusCharacteristic = char
            peripheral.setNotifyValue(true, for: char)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == BLEManager.statusCharUUID,
              let data = characteristic.value,
              let byte = data.first else { return }

        print("Received BLE Update: \(byte == 0x01 ? "LIGHTNING DETECTED" : "ALL CLEAR")")
        
        DispatchQueue.main.async {
            self.lightningStatus = LightningStatus(isDetected: byte == 0x01, timestamp: .now)
        }
    }
}
