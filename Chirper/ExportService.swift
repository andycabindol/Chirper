import Foundation
import AVFoundation
import SwiftUI
import UIKit

struct ExportService {
    // MARK: - Filename generation
    
    static func generateFilename(
        species: String,
        recordingDate: Date,
        clipIndex: Int? = nil
    ) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MM-dd-yyyy"
        let dateString = dateFormatter.string(from: recordingDate)
        
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HHmmss"
        let timeString = timeFormatter.string(from: recordingDate)
        
        // Parse species name
        let (commonName, scientificName): (String, String)
        if let underscoreIndex = species.lastIndex(of: "_") {
            scientificName = String(species[..<underscoreIndex])
            commonName = String(species[species.index(after: underscoreIndex)...])
        } else {
            commonName = species
            scientificName = ""
        }
        
        // Sanitize names
        let sanitizedCommon = commonName.sanitizedFilename()
        let sanitizedScientific = scientificName.sanitizedFilename()
        
        // Build filename
        var components: [String] = [dateString, sanitizedCommon]
        if !sanitizedScientific.isEmpty {
            components.append(sanitizedScientific)
        }
        components.append(timeString)
        
        // Add clip index if provided
        if let index = clipIndex {
            components.append("\(index)")
        }
        
        return components.joined(separator: "-") + ".wav"
    }
    
    // MARK: - High-level exports

    static func exportPerSpecies(
        speciesSegments: [String: [Segment]],
        from buffer: AVAudioPCMBuffer,
        sampleRate: Double,
        recordingDate: Date
    ) throws -> [URL] {
        var urls: [URL] = []

        for (species, segments) in speciesSegments {
            guard !segments.isEmpty else { continue }
            let concat = try AudioProcessingService.spliceSegments(
                segments,
                from: buffer,
                sampleRate: sampleRate
            )

            let fileName = generateFilename(
                species: species,
                recordingDate: recordingDate
            )
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
        sampleRate: Double,
        recordingDate: Date
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

                let fileName = generateFilename(
                    species: species,
                    recordingDate: recordingDate,
                    clipIndex: idx + 1
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
        // Ensure file URLs are accessible
        let accessibleItems = activityItems.compactMap { item -> Any? in
            if let url = item as? URL {
                // For file URLs, ensure they're accessible
                // Temp directory files should be accessible, but we verify
                if url.isFileURL && FileManager.default.fileExists(atPath: url.path) {
                    return url
                }
            }
            return item
        }
        
        let controller = UIActivityViewController(
            activityItems: accessibleItems.isEmpty ? activityItems : accessibleItems,
            applicationActivities: nil
        )
        
        // Configure for better performance
        if let popover = controller.popoverPresentationController {
            // This helps avoid some LaunchServices delays on iPad
            popover.permittedArrowDirections = .any
        }
        
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


