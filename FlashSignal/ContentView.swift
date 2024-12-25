//
//  ContentView.swift
//  FlashSignal
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView{
            TransmitterView()
                .tabItem {
                    Image(systemName: "paperplane")
                    Text("送信")
                }
            ReceiverView()
                .tabItem {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                    Text("受信")
                }
        }
    }
}

#Preview {
    ContentView()
}
