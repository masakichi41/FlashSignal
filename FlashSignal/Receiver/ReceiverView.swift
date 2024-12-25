//
//  ReceiverView.swift
//  FlashSignal
//

import SwiftUI

struct ReceiverView: View {
    @ObservedObject var flashReceiver = FlashReceiver()

    var body: some View {
        VStack {
            Text("受信画面")
                .font(.title)
                .padding(.top)
            CameraView(flashReceiver: flashReceiver)
                .padding(10)
                .aspectRatio(1, contentMode: .fit)
            Text("状態: \(flashReceiver.statusText)")
            ProgressView(value: flashReceiver.progress, total: 1.0)
                .padding()
            Text("最後の受信データ: \(flashReceiver.lastReceivedData)")
            Text("最大輝度: \(flashReceiver.getLuminance())")
                .monospaced()
            Spacer()
        }
    }
}

#Preview {
    ReceiverView()
}
