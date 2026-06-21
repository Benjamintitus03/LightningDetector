import SwiftUI

struct ContentView: View {
    @StateObject private var ble = BLEManager()

    var body: some View {
        Group {
            if ble.connectionState == .connected {
                StatusView(ble: ble)
            } else {
                ScanView(ble: ble)
            }
        }
        .preferredColorScheme(.dark)
    }
}
