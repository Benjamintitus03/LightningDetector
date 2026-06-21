import SwiftUI
import CoreBluetooth
struct StatusView: View {
    @ObservedObject var ble: BLEManager
    @State private var pulse = false

    private var detected: Bool { ble.lightningStatus.isDetected }

    var body: some View {
        VStack(spacing: 0) {

            // Connection bar
            HStack {
                HStack(spacing: 6) {
                    Circle()
                        .fill(.green)
                        .frame(width: 7, height: 7)
                    Text(ble.connectedDevice?.name ?? "Connected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Disconnect") {
                    ble.disconnect()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 60)

            Spacer()

            // Status ring + icon
            ZStack {
                Circle()
                    .fill(detected ? Color.yellow.opacity(0.12) : Color.green.opacity(0.08))
                    .frame(width: 210, height: 210)
                    .scaleEffect(pulse ? 1.12 : 1.0)
                    .animation(
                        detected
                            ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true)
                            : .default,
                        value: pulse
                    )

                Image(systemName: detected ? "bolt.fill" : "checkmark")
                    .font(.system(size: 68, weight: .medium))
                    .foregroundStyle(detected ? .yellow : .green)
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding(.bottom, 36)

            // Status label
            Text(detected ? "Lightning Detected" : "All Clear")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(detected ? .yellow : .primary)
                .animation(.easeInOut, value: detected)

            Text(detected ? "Seek shelter immediately" : "No activity detected nearby")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.top, 8)

            Text("Updated \(ble.lightningStatus.timestamp.formatted(.relative(presentation: .named)))")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.top, 20)

            Spacer()
        }
        .onAppear { pulse = detected }
        .onChange(of: detected) { pulse = $1 }
    }
}
