//
//  FlashTransmitter.swift
//  FlashSignal
//

import AVFoundation

class FlashTransmitter: ObservableObject {
    // MARK: - Properties
    private let device: AVCaptureDevice?

    private let stabilizationPattern = [true, true, true, true, false, false]
    private let startPattern = [true, false, true, false, true, false, true, false]  // 10101010
    private let bitDuration: Double = 0.1  // 100ms per bit

    private let touchLevel: Float = 0.5

    @Published var isFlashOn: Bool = false

    // MARK: - initialization
    init() {
        self.device = AVCaptureDevice.default(for: .video)
    }

    // MARK: - Send Data
    public func send(data: [Bool]) {
        guard let device = device, device.hasTorch else {
            print("Device does not have a torch.")
            return
        }

        let encodedData = encode(data)

        let sendData = stabilizationPattern + startPattern + encodedData

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try device.lockForConfiguration()

                var currentIndex = 0
                var lastBit: Bool? = nil  // 前回のビット状態を保持

                let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .userInitiated))
                timer.setEventHandler { [weak self] in
                    guard let self = self else { return }

                    if currentIndex < sendData.count {
                        let bit = sendData[currentIndex]

                        // 前回状態と異なる場合のみトーチ操作
                        if bit != lastBit {
                            do {
                                if bit {
                                    try device.setTorchModeOn(level: touchLevel)
                                } else {
                                    device.torchMode = .off
                                }
                            } catch {
                                print("Error while setting torch: \(error)")
                            }
                            lastBit = bit
                            self.changeFlashState(newState: bit)
                        }

                        currentIndex += 1
                    } else {
                        // 全ビット送信完了
                        device.torchMode = .off
                        device.unlockForConfiguration()
                        timer.cancel()
                        self.changeFlashState(newState: false)
                        print("Frame sent successfully.")
                    }
                }

                timer.schedule(deadline: .now(), repeating: self.bitDuration)
                timer.activate()

            } catch {
                print("Torch could not be used: \(error)")
            }
        }
    }

    // MARK: - Public Methods
    public func makeHexSendData(hex: String) -> [Bool] {
        var encodedBits: [Bool] = []

        if hex.count != 6 {
            return encodedBits
        }

        guard let decimal = Int(hex, radix: 16) else {
            return encodedBits
        }

        let binary = String(decimal, radix: 2)
        let binaryArray = Array(binary)

        let paddingCount = 24 - binaryArray.count

        for _ in 0..<paddingCount {
            encodedBits.append(false)
        }

        for bit in binaryArray {
            encodedBits.append(bit == "1")
        }

        return encodedBits
    }

    private func changeFlashState(newState: Bool) {
        DispatchQueue.main.async {
            self.isFlashOn = newState
        }
    }

    private func encode(_ rowBits: [Bool]) -> [Bool] {
        var encodedBits: [Bool] = Array(repeating: false, count: 29)
        let parityPositions: Set<Int> = [1,2,4,8,16]
        var dataIndex = 0
        for bitPos in 1...29 {
            if parityPositions.contains(bitPos) {
                encodedBits[bitPos - 1] = false
            } else {
                encodedBits[bitPos - 1] = rowBits[dataIndex]
                dataIndex += 1
            }
        }

        // パリティ計算
        for p in parityPositions {
            var parity = false
            for i in 1...29 {
                if (i & p) != 0 {
                    parity = parity != encodedBits[i - 1]
                }
            }
            encodedBits[p - 1] = parity
        }

        return encodedBits
    }
}
