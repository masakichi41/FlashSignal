//
//  CameraView.swift
//  FlashSignal
//

// CameraView.swift
import SwiftUI

struct CameraView: View {
    @ObservedObject var flashReceiver: FlashReceiver

    var body: some View {
        GeometryReader { geometry in
            CameraPreview(flashReceiver: flashReceiver)
                .overlay(
                    VStack {
                        Spacer()
                        HStack {
                            Text(String(format: "FPS: %.2f", flashReceiver.fps))
                                .padding(5)
                                .background(Color.black.opacity(0.5))
                                .foregroundColor(.white)
                                .cornerRadius(8)
                            Spacer()
                            Text(String(format: "Processing: %.3f s", flashReceiver.processingTime))
                                .padding(5)
                                .background(Color.black.opacity(0.5))
                                .foregroundColor(.white)
                                .cornerRadius(8)
                        }
                        .padding()
                    }
                )
        }
        .background(Color.black)
        .edgesIgnoringSafeArea(.all)
    }
}
