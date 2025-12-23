import Foundation
import AVFoundation

protocol BirdIdentifier {
    func detect(
        audioBuffer: AVAudioPCMBuffer,
        sampleRate: Double,
        progress: @escaping (_ completed: Int, _ total: Int, _ message: String) -> Void
    ) async throws -> [Detection]
}

struct Detection {
    var species: String
    var start: TimeInterval
    var end: TimeInterval
    var confidence: Double
}

struct Segment {
    let startSample: Int
    let endSample: Int
    let confidence: Double
}


