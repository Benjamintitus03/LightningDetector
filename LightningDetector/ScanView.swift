import SwiftUI
import CoreBluetooth

struct ScanView: View {
    @ObservedObject var ble: BLEManager

    var body: some View {
        VStack(spacing: 0) {

            // Header
            VStack(spacing: 10) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(.yellow)
                Text("Lightning Detector")
                    .font(.title2.weight(.bold))
                Text("Connect to your device to begin")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 72)
            .padding(.bottom, 40)

            // Device list
            if ble.isScanning && ble.discoveredDevices.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    ProgressView()
                        .tint(.yellow)
                    Text("Looking for devices...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            } else if !ble.isScanning && ble.discoveredDevices.isEmpty {
                Spacer()
                Text("No devices found")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                List(ble.discoveredDevices, id: \.identifier) { device in
                    Button {
                        ble.connect(device)
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .foregroundStyle(.yellow)
                                .frame(width: 24)
                            Text(device.name ?? "Unknown Device")
                                .foregroundStyle(.primary)
                            Spacer()
                            if ble.connectionState == .connecting {
                                ProgressView()
                                    .tint(.yellow)
                            } else {
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.tertiary)
                                    .font(.caption)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .listStyle(.plain)
            }

            // Scan button
            Button {
                ble.isScanning ? ble.stopScan() : ble.startScan()
            } label: {
                Text(ble.isScanning ? "Stop Scanning" : "Scan for Devices")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.yellow)
                    .foregroundStyle(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 20)

            Button("Try Demo Mode") {
                ble.enterMockMode()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.bottom, 40)
        }
    }
}
