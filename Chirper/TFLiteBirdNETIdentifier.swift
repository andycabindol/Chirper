import Foundation
import AVFoundation
import TensorFlowLite

final class TFLiteBirdNETIdentifier: BirdIdentifier {
    private let audioInterpreter: Interpreter
    private let labels: [String]

    private let stepSeconds: Double = 0.3

    private let inputAudioIndex: Int

    // MARK: - Init

    init() throws {
        // Resolve actual BirdNET asset locations in the bundle.
        let (audioURL, metaURL, labels) = try TFLiteBirdNETIdentifier.resolveAssets()
        self.labels = labels

        var audioOptions = Interpreter.Options()
        audioOptions.threadCount = 3

        var metaOptions = Interpreter.Options()
        metaOptions.threadCount = 3

        audioInterpreter = try Interpreter(modelPath: audioURL.path, options: audioOptions)

        try audioInterpreter.allocateTensors()

        // Log basic input info (safe without invoking)
        print("=== Audio model inputs ===")
        for index in 0..<audioInterpreter.inputTensorCount {
            let t = try audioInterpreter.input(at: index)
            print("Audio input[\(index)] name=\(t.name) type=\(t.dataType) shape=\(t.shape.dimensions)")
        }

        // Assume single audio input
        inputAudioIndex = 0
    }

    // MARK: - Asset resolution

    /// Attempts to find BirdNET assets anywhere in the main bundle, so you don't
    /// have to match an exact folder name. It will work as long as the files are
    /// added to the target's Copy Bundle Resources.
    private static func resolveAssets() throws -> (audioURL: URL, metaURL: URL, labels: [String]) {
        let bundle = Bundle.main
        let allTflite = bundle.urls(forResourcesWithExtension: "tflite", subdirectory: nil) ?? []

        // Find audio-model.tflite and meta-model.tflite anywhere in bundle
        let audioURL = allTflite.first { $0.lastPathComponent == "audio-model.tflite" }
        let metaURL = allTflite.first { $0.lastPathComponent == "meta-model.tflite" }

        guard let audioURL, let metaURL else {
            throw NSError(
                domain: "Chirper",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey:
                    "Could not locate audio-model.tflite or meta-model.tflite in app bundle. " +
                    "Make sure both files are in the project and checked for Target Membership (Chirper)."]
            )
        }

        // Try to locate a suitable labels file anywhere in the bundle.
        // We accept common English variants.
        let allTxt = bundle.urls(forResourcesWithExtension: "txt", subdirectory: nil) ?? []
        let labelURL = allTxt.first {
            let name = $0.deletingPathExtension().lastPathComponent.lowercased()
            return name == "labels_en"
                || name == "labels_en_us"
                || name == "labels_en_uk"
                || name == "en_us"
                || name == "en_uk"
        }

        guard let labelURL else {
            throw NSError(
                domain: "Chirper",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey:
                    "Could not locate a BirdNET labels file (labels_en*.txt or en_us.txt) in the bundle. " +
                    "Ensure at least one English labels file is added to Copy Bundle Resources."]
            )
        }

        let labelsData = try Data(contentsOf: labelURL)
        guard let labelsString = String(data: labelsData, encoding: .utf8) else {
            throw NSError(
                domain: "Chirper",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Unable to decode labels file at \(labelURL.lastPathComponent)."]
            )
        }

        let labels = labelsString
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }

        print("BirdNET assets: audio=\(audioURL.lastPathComponent), meta=\(metaURL.lastPathComponent), labels=\(labelURL.lastPathComponent)")
        return (audioURL, metaURL, labels)
    }

    // MARK: - Detection

    func detect(
        audioBuffer: AVAudioPCMBuffer,
        sampleRate: Double,
        progress: @escaping (Int, Int, String) -> Void
    ) async throws -> [Detection] {
        let samples = AudioProcessingService.floatSamples(from: audioBuffer)
        let totalSamples = samples.count

        // Derive window length from audio model input tensor
        let audioInputTensor = try audioInterpreter.input(at: inputAudioIndex)
        let windowLengthSamples = audioInputTensor.shape.dimensions.last ?? Int(3 * sampleRate)
        let hopSamples = Int(stepSeconds * sampleRate)

        let totalWindows = max(1, (totalSamples - windowLengthSamples) / hopSamples + 1)
        var detections: [Detection] = []

        for windowIndex in 0..<totalWindows {
            try Task.checkCancellation()

            let startSample = windowIndex * hopSamples
            let endSample = min(startSample + windowLengthSamples, totalSamples)
            if endSample <= startSample { continue }

            let window = Array(samples[startSample..<endSample])
            let padded = padOrTrim(window, to: windowLengthSamples)

            // Prepare audio input tensor data
            let inputTensor = try audioInterpreter.input(at: inputAudioIndex)
            let audioData: Data
            switch inputTensor.dataType {
            case .float32:
                audioData = TensorUtils.data(from: padded)
            case .int16:
                let ints = padded.map {
                    Int16(
                        max(
                            Int16.min,
                            min(Int16.max, Int16($0 * Float(Int16.max)))
                        )
                    )
                }
                audioData = TensorUtils.data(from: ints)
            default:
                audioData = TensorUtils.data(from: padded)
            }

            try audioInterpreter.copy(audioData, toInputAt: inputAudioIndex)
            try audioInterpreter.invoke()
            let audioOutput = try audioInterpreter.output(at: 0)

            // Interpret audio model output directly as logits/probabilities.
            let probsRaw = TensorUtils.floats(from: audioOutput.data)
            let probs: [Float]

            let outShape = audioOutput.shape.dimensions
            if outShape.contains(labels.count) {
                probs = TensorUtils.softmax(probsRaw)
            } else {
                probs = TensorUtils.softmax(Array(probsRaw.prefix(labels.count)))
            }

            if let (bestIndex, bestProb) = TensorUtils.top1(probs),
               bestIndex < labels.count {
                let label = labels[bestIndex]
                let startTime = Double(startSample) / sampleRate
                let endTime = Double(min(startSample + windowLengthSamples, totalSamples)) / sampleRate
                if bestProb > 0.1 { // low threshold here; UI threshold applied later
                    let det = Detection(
                        species: label,
                        start: startTime,
                        end: endTime,
                        confidence: Double(bestProb)
                    )
                    detections.append(det)
                }
            }

            progress(windowIndex + 1, totalWindows, "Analyzing with BirdNET (TFLite)…")
        }

        return detections
    }

    private func padOrTrim(_ samples: [Float], to count: Int) -> [Float] {
        if samples.count == count { return samples }
        if samples.count > count { return Array(samples.prefix(count)) }
        return samples + Array(repeating: 0, count: count - samples.count)
    }
}


