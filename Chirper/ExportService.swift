import Foundation
import AVFoundation
import SwiftUI
import UIKit

struct ExportService {
    // MARK: - High-level exports

    static func exportPerSpecies(
        speciesSegments: [String: [Segment]],
        from buffer: AVAudioPCMBuffer,
        sampleRate: Double
    ) throws -> [URL] {
        var urls: [URL] = []

        for (species, segments) in speciesSegments {
            guard !segments.isEmpty else { continue }
            let concat = try AudioProcessingService.spliceSegments(
                segments,
                from: buffer,
                sampleRate: sampleRate
            )

            let fileName = "\(species.sanitizedFilename()).wav"
            let url = try writeTempWav(
                buffer: concat,
                sampleRate: sampleRate,
                fileName: fileName
            )
            urls.append(url)
        }

        return urls
    }

    static func exportPerCall(
        speciesSegments: [String: [Segment]],
        from buffer: AVAudioPCMBuffer,
        sampleRate: Double
    ) throws -> [URL] {
        var urls: [URL] = []

        for (species, segments) in speciesSegments {
            let sorted = segments.sorted { $0.startSample < $1.startSample }
            for (idx, seg) in sorted.enumerated() {
                let subSegments = [seg]
                let concat = try AudioProcessingService.spliceSegments(
                    subSegments,
                    from: buffer,
                    sampleRate: sampleRate
                )

                let fileName = String(
                    format: "%@_call_%03d.wav",
                    species.sanitizedFilename(),
                    idx + 1
                )
                let url = try writeTempWav(
                    buffer: concat,
                    sampleRate: sampleRate,
                    fileName: fileName
                )
                urls.append(url)
            }
        }

        return urls
    }

    // MARK: - WAV writing

    static func writeTempWav(
        buffer: AVAudioPCMBuffer,
        sampleRate: Double,
        fileName: String
    ) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let url = tempDir.appendingPathComponent(fileName)

        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        )!

        let outputFile = try AVAudioFile(
            forWriting: url,
            settings: format.settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )

        try outputFile.write(from: buffer)
        return url
    }

    static func cleanupTempFiles(urls: [URL]) {
        for url in urls {
            try? FileManager.default.removeItem(at: url)
        }
    }
}

// MARK: - ShareSheet

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    var completion: (() -> Void)?

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: nil
        )
        controller.completionWithItemsHandler = { _, _, _, _ in
            completion?()
        }
        return controller
    }

    func updateUIViewController(
        _ uiViewController: UIActivityViewController,
        context: Context
    ) {}
}


