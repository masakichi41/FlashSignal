//
//  FlashReceiver.swift
//  FlashSignal
//

import AVFoundation

class FlashReceiver: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, ObservableObject {
    // MARK: - Properties
    // camera session
    private let session = AVCaptureSession()
    private var device: AVCaptureDevice?
    private let videoDataOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "touch.session.queue")

    // data
    private let startPattern = [1,0,1,0,1,0,1,0]  // 8bit
    private let dataBitCount = 29  // 24bit + 5parity
    private let bitDuration: Double = 0.1  // 100ms per bit

    private let luminanceThreshold: CGFloat = 0.85

    // frame
    private let framesPerBit: Int = 3
    private let initialFrameCount = 30
    private var frameCount = 0

    // bit buffer
    private var startFrameBuffer: [Bool] = []
    private var isReceivingData = false
    private var startAccuracyList: [Double] = [0.0, 0.0, 0.0]
    private var dataFrameBuffer: [Bool] = []
    private var dataBitBuffer: [Bool] = []

    // status
    private var maxLuminance: CGFloat = 0.0
    @Published var progress: Double = 0.0

    // debug data
    @Published var statusText: String = "起動中..."
    @Published var fps: Double = 0.0
    @Published var processingTime: Double = 0.0
    @Published var lastReceivedData: String = ""

    private var lastFrameTime: CMTime = CMTime.invalid

    // MARK: - initialization
    override init() {
        super.init()
        sessionQueue.async {
            self.setupSession()
            self.session.startRunning()
            DispatchQueue.main.async {
                self.statusText = "読み込み中..."
            }
        }
    }

    private func setupSession() {
        session.beginConfiguration()
        session.sessionPreset = .low

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            return
        }

        self.device = device

        do {
            try device.lockForConfiguration()
            // カメラのカスタム
            if device.isExposureModeSupported(.custom) {
                // 露出時間を最小にして光を限界まで受け取らない
                let exposureDuration = device.activeFormat.minExposureDuration
                device.setExposureModeCustom(duration: exposureDuration, iso: device.iso, completionHandler: nil)
            }
            device.unlockForConfiguration()
        } catch {
            return
        }

        // カメラの入力を取得
        guard let input = try? AVCaptureDeviceInput(device: device) else {
            return
        }

        if session.canAddInput(input) {
            session.addInput(input)
        }

        // ピクセルフォーマットをYUVに変更
        videoDataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)]

        // キューの優先度を高く設定
        let videoQueue = DispatchQueue(label: "videoQueue", qos: .userInitiated)
        videoDataOutput.setSampleBufferDelegate(self, queue: videoQueue)

        if session.canAddOutput(videoDataOutput) {
            session.addOutput(videoDataOutput)
        }

        session.commitConfiguration()
    }

    // MARK: - Getter
    func getSession() -> AVCaptureSession {
        return session
    }

    func getLuminance() -> CGFloat {
        return maxLuminance
    }

    // MARK: - Capture Output
    func captureOutput(_ captureOutput: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let startTime = CFAbsoluteTimeGetCurrent()

        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        CVPixelBufferLockBaseAddress(imageBuffer, .readOnly)

        let width = CVPixelBufferGetWidth(imageBuffer)
        let height = CVPixelBufferGetHeight(imageBuffer)
        let yStride = CVPixelBufferGetBytesPerRowOfPlane(imageBuffer, 0)
        guard let yPlane = CVPixelBufferGetBaseAddressOfPlane(imageBuffer, 0) else { return }

        let squareSize = min(width, height)
        let xOffset = (width - squareSize) / 2
        let yOffset = (height - squareSize) / 2

        maxLuminance = 0.0

        for y in 0..<squareSize {
            let rowPtr = yPlane + (y + yOffset) * yStride
            for x in 0..<squareSize {
                let pixel = rowPtr.advanced(by: (x + xOffset)).assumingMemoryBound(to: UInt8.self)
                let luminance = CGFloat(pixel.pointee) / 255.0
                if luminance > maxLuminance {
                    maxLuminance = luminance
                }
            }
        }

        CVPixelBufferUnlockBaseAddress(imageBuffer, .readOnly)

        // デバッグ情報の更新
        let currentTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        updateFPS(currentTime)
        updateProcessingTime(startTime)

        // 非同期処理はここに書く
        DispatchQueue.main.async {
            self.processLuminance(self.maxLuminance)
        }
    }

    // MARK - Data Processing
    private func processLuminance(_ luminance: CGFloat) {
        frameCount += 1
        if frameCount < initialFrameCount {
            updateStatusText("初期化中...")
            return
        }

        let isBright = luminance > luminanceThreshold

        updateStatusText(isReceivingData ? "受信中..." : "スタートパターン検知前")

        if !isReceivingData {
            startFrameBuffer.append(isBright)

            // スタートパターンの検出
            let accuracy = calculateStartPatternAccuracy()

            startAccuracyList.removeFirst()
            startAccuracyList.append(accuracy)

            if startAccuracyList[0] > 0.0 {
                let maxIndex = startAccuracyList.firstIndex(of: startAccuracyList.max()!)!

                // 最も精度が高いフレームからデータを取得
                let tmpBuffer = startFrameBuffer.suffix(2 - maxIndex)
                dataFrameBuffer.append(contentsOf: tmpBuffer)
                print(startAccuracyList)
                // 初期化処理
                isReceivingData = true
                startFrameBuffer = []
                startAccuracyList = [0.0, 0.0, 0.0]


                print("スタートパターン検出")
            }
        } else {
            dataFrameBuffer.append(isBright)

            print(dataFrameBuffer)

            // 万が一データがおかしかった場合は即リセット
            if dataFrameBuffer.count > framesPerBit {
                print(dataFrameBuffer)
                dataFrameBuffer = []
                isReceivingData = false
            }

            if dataFrameBuffer.count == framesPerBit {
                let brightCount = dataFrameBuffer.filter{$0}.count
                let bitPattern = (brightCount > framesPerBit/2)

                dataBitBuffer.append(bitPattern ? true : false)
                dataFrameBuffer = []

                // progress barのステータス更新(非同期で)
                DispatchQueue.main.async {
                    self.progress = Double(self.dataBitBuffer.count) / Double(self.dataBitCount)
                }

                if dataBitBuffer.count == dataBitCount {
                    // データの取得完了
                    isReceivingData = false

                    var dataString = ""
                    for i in 0..<dataBitCount {
                        dataString += String(dataBitBuffer[i] ? 1 : 0)
                        if (i+1) % 8 == 0 {
                            dataString += " "
                        }
                    }
                    print(dataString)

                    let decodedBits = decode(dataBitBuffer)
                    print("received data: \(decodedBits)")
                    updateLastReceivedData(decodedBits)

                    dataBitBuffer = []
                }
            }
        }
    }

    private func decode(_ encodedBits: [Bool]) -> [Bool] {
        var encodedBits = encodedBits
        // パリティチェック
        let parityPositions: [Int] = [1,2,4,8,16]
        var errorPosition = 0
        for p in parityPositions {
            var parity = false
            for i in 1...29 {
                if (i & p) != 0 {
                    parity = parity != encodedBits[i - 1]
                }
            }
            // パリティがずれていれば、そのパリティビット位置をerrorPositionにXOR加算
            if parity {
                errorPosition ^= p
            }
        }

        // エラー訂正(もしerrorPositionが0でなければ、そのビットを反転)
        if errorPosition != 0 && errorPosition <= 29 {
            encodedBits[errorPosition - 1].toggle()
        }

        // 復元するデータビットを抽出
        let paritySet = Set(parityPositions)
        var decodedBits: [Bool] = []
        for i in 1...29 {
            if !paritySet.contains(i) {
                decodedBits.append(encodedBits[i - 1])
            }
        }
        print("decode: \(decodedBits)")
        return decodedBits
    }

    // startFrameBufferからスタートパターンと正答率を計算
    private func calculateStartPatternAccuracy() -> Double {
        let startFrameCount = startPattern.count * framesPerBit

        // 最初のフレームが揃うまでは待つ
        if startFrameBuffer.count < startFrameCount { return 0.0 }

        var missCount = 0

        startFrameBuffer = startFrameBuffer.suffix(startFrameCount)

        debugLog(boolArray: startFrameBuffer)

        for i in 0..<startFrameCount {
            if i % framesPerBit == 0 {
                let targetPattern = startPattern[i / framesPerBit] == 1

                let bitBuffer = Array(startFrameBuffer[i..<i+framesPerBit])
                let brightCount = bitBuffer.filter{$0}.count
                let bitPattern = (brightCount > framesPerBit/2)

                if targetPattern != bitPattern { return 0.0 }

                for bit in bitBuffer {
                    if bit != targetPattern {
                        missCount += 1
                    }
                }
            }
        }

        let accuracy = 1.0 - Double(missCount) / Double(startFrameCount)

        return accuracy
    }

    // MARK: - Debugger
    func updateFPS(_ currentTime: CMTime) {
        if lastFrameTime.isValid {
            let duration = CMTimeSubtract(currentTime, lastFrameTime)
            let fps = 1.0 / CMTimeGetSeconds(duration)
            DispatchQueue.main.async {
                self.fps = fps
            }
        }
        lastFrameTime = currentTime
    }

    func updateProcessingTime(_ startTime: CFAbsoluteTime) {
        let endTime = CFAbsoluteTimeGetCurrent()
        let processingDuration = endTime - startTime
        DispatchQueue.main.async {
            self.processingTime = processingDuration
        }
    }

    func updateStatusText(_ text: String) {
        DispatchQueue.main.async {
            self.statusText = text
        }
    }

    func updateLastReceivedData(_ data: [Bool]) {
        DispatchQueue.main.async {
            // データは2進数なので16進数に変換して表示
            let binaryString = data.map { $0 ? "1" : "0" }.joined()
            guard let decimal = Int(binaryString, radix: 2) else {
                print("Invalid data: \(data)")
                return
            }

            self.lastReceivedData = String(format: "%06X", decimal)
        }
    }

    func debugLog(boolArray: [Bool]) {
        print("bitBuffer \(frameCount): ", terminator: "")
        for i in 0..<boolArray.count {
            print(boolArray[i] ? 1 : 0, terminator: i%3 == 2 ? " " : "")
        }
        print("")
    }
}
