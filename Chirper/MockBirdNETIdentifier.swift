import Foundation
import AVFoundation

final class MockBirdNETIdentifier: BirdIdentifier {
    func detect(
        audioBuffer: AVAudioPCMBuffer,
        sampleRate: Double,
        progress: @escaping (Int, Int, String) -> Void
    ) async throws -> [Detection] {
        let duration = Double(audioBuffer.frameLength) / sampleRate
        let windowSeconds = 3.0
        let stepSeconds = 0.8

        let totalWindows = Int(max(1, (duration - windowSeconds) / stepSeconds)) + 1
        var detections: [Detection] = []

        let speciesPool = ["Northern Cardinal", "American Robin", "Black-capped Chickadee"]
        for i in 0..<totalWindows {
            try Task.checkCancellation()
            let start = Double(i) * stepSeconds
            let end = min(start + windowSeconds, duration)
            if end <= start { continue }

            let species = speciesPool[i % speciesPool.count]
            let confidence = 0.3 + 0.1 * Double(i % 5)

            if confidence >= 0.25 {
                detections.append(
                    Detection(
                        species: species,
                        start: start,
                        end: end,
                        confidence: confidence
                    )
                )
            }

            progress(i + 1, totalWindows, "Analyzing with BirdNET (mock)…")
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        return detections
    }
}


