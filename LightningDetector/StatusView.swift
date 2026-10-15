import SwiftUI
import CoreBluetooth

struct StatusView: View {
    @ObservedObject var ble: BLEManager
    @State private var pulse = false
    @State private var flashWhite = false

    private var detected: Bool { ble.lightningStatus.isDetected }

    var body: some View {
        ZStack {
            // Background Flash Effect
            Color.black.ignoresSafeArea()
            if flashWhite {
                Color.white.ignoresSafeArea()
            }

            VStack(spacing: 0) {
                // Connection & RSSI bar
                HStack {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(.green)
                            .frame(width: 7, height: 7)
                        Text(ble.isMockMode ? "Demo Mode (\(ble.currentRSSI) dBm)" : "\(ble.connectedDevice?.name ?? "Connected") (\(ble.currentRSSI) dBm)")
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
                .padding(.top, 20)

                Spacer()

                // Status ring + icon
                ZStack {
                    Circle()
                        .fill(detected ? Color.yellow.opacity(0.15) : Color.green.opacity(0.10))
                        .frame(width: 210, height: 210)
                        .scaleEffect(pulse ? 1.15 : 1.0)
                        .animation(
                            detected
                                ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
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
                    .foregroundStyle(detected ? .yellow : .white)
                    .animation(.easeInOut, value: detected)

                Text(detected ? "Seek shelter immediately" : "No activity detected nearby")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
                
                // Live Waveform Visualizer
                WaveformView(active: detected)
                    .padding(.top, 30)
                    .padding(.bottom, 20)

                // Strike History Log
                if !ble.strikeHistory.isEmpty {
                    VStack(alignment: .leading) {
                        Text("Recent Activity")
                            .font(.caption2).bold().foregroundStyle(.secondary)
                            .padding(.bottom, 2)
                        
                        ScrollView {
                            ForEach(ble.strikeHistory.prefix(15)) { event in
                                HStack {
                                    Text(event.timestamp.formatted(date: .omitted, time: .standard))
                                        .foregroundStyle(.white)
                                    Spacer()
                                    Text(event.intensity)
                                        .bold()
                                        .foregroundStyle(event.intensity == "Critical" ? .red : .yellow)
                                }
                                .font(.caption)
                                .padding(.vertical, 4)
                                Divider().background(.gray.opacity(0.3))
                            }
                        }
                        .frame(height: 110)
                    }
                    .padding()
                    .background(Color(UIColor.darkGray).opacity(0.4))
                    .cornerRadius(16)
                    .padding(.horizontal, 20)
                }

                if ble.isMockMode {
                    Button(detected ? "Simulate All Clear" : "Simulate Lightning") {
                        ble.toggleMockStatus()
                    }
                    .font(.caption)
                    .foregroundStyle(.yellow)
                    .padding(.top, 16)
                }

                Spacer()
            }
        }
        .onAppear { pulse = detected }
        .onChange(of: detected) { _, isDetected in
            pulse = isDetected
            if isDetected {
                triggerLightningHaptics()
                triggerScreenFlash()
            }
        }
    }
    
    // MARK: - Flashy Feedback Methods
    private func triggerScreenFlash() {
        withAnimation(.easeIn(duration: 0.05)) { flashWhite = true }
        withAnimation(.easeOut(duration: 0.4).delay(0.08)) { flashWhite = false }
    }
    
    private func triggerLightningHaptics() {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.error)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            let impact = UIImpactFeedbackGenerator(style: .heavy)
            impact.impactOccurred()
        }
    }
}

// MARK: - Audio Waveform Component
struct WaveformView: View {
    let active: Bool

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<12, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2)
                    .fill(active ? Color.yellow : Color.green.opacity(0.4))
                    .frame(width: 4, height: active ? CGFloat.random(in: 25...70) : CGFloat.random(in: 8...18))
                    .animation(
                        .easeInOut(duration: 0.15)
                        .repeatForever()
                        .delay(Double(i) * 0.04),
                        value: active
                    )
            }
        }
        .frame(height: 70)
    }
}
