//
//  TransmitterView.swift
//  FlashSignal
//

import SwiftUI

struct TransmitterView: View {
    @State private var inputText: String = ""
    @ObservedObject var flashTransmitter = FlashTransmitter()
    
    var body: some View {
        VStack {
            Circle()
                .fill(flashTransmitter.isFlashOn ? Color.yellow : Color.gray)
                .frame(width: 100, height: 100)
                .padding(30)
            TextField("16進数6桁", text: $inputText)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .monospaced()
                .frame(width: 200)
            Button(action: {
                let sendData = flashTransmitter.makeHexSendData(hex: inputText)
                if sendData.count != 24 {
                    print("Invalid data: \(sendData)")
                    return
                }
                flashTransmitter.send(data: sendData)
            }) {
                Text("送信")
                    .padding(10)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                    .frame(width: 200)
            }.frame(width: 200)
            Spacer()
        }
    }
}

#Preview {
    TransmitterView()
}
