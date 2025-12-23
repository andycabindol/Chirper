import Foundation
import AVFoundation
import SwiftUI
import Combine

enum AppScreen {
    case importScreen
    case processing
    case results
}

enum ExportMode {
    case perSpecies
    case perCall
}

struct SpeciesSummary: Identifiable, Hashable {
    let id = UUID()
    let species: String
    let maxConfidence: Double
    let averageConfidence: Double
    let clipCount: Int
}

final class AppViewModel: ObservableObject {
    // Navigation
    @Published var currentScreen: AppScreen = .importScreen

    // Audio + detections
    @Published var audioBuffer: AVAudioPCMBuffer?
    @Published var sampleRate: Double = 48_000
    @Published var detections: [Detection] = []
    @Published var speciesSegments: [String: [Segment]] = [:]
    @Published var usingMock: Bool = false
    @Published var recordingDate: Date = Date()

    // UI controls (results)
    @Published var exportMode: ExportMode = .perSpecies
    @Published var confidenceThreshold: Double = 0.25
    // Keep very small default padding; user can increase if desired.
    @Published var paddingMs: Double = 50
    
    // Trim values per species and segment index: [species: [segmentIndex: TrimValues]]
    @Published var trimValues: [String: [Int: TrimValues]] = [:]

    // Processing state
    @Published var processingMessage: String = "Preparing…"
    @Published var processingProgress: Double = 0
    @Published var currentWindowIndex: Int = 0
    @Published var totalWindows: Int = 0

    private var processingTask: Task<Void, Never>?
    private var birdIdentifier: BirdIdentifier?

    init() {
        setupIdentifier()
    }

    private func setupIdentifier() {
        // Try TFLite, fall back to mock
        do {
            let tflite = try TFLiteBirdNETIdentifier()
            birdIdentifier = tflite
            usingMock = false
        } catch {
            print("Failed to init TFLiteBirdNETIdentifier, using mock. Error: \(error)")
            birdIdentifier = MockBirdNETIdentifier()
            usingMock = true
        }
    }

    func resetToImport() {
        processingTask?.cancel()
        audioBuffer = nil
        detections = []
        speciesSegments = [:]
        trimValues = [:]
        recordingDate = Date()
        processingMessage = "Preparing…"
        processingProgress = 0
        currentWindowIndex = 0
        totalWindows = 0
        currentScreen = .importScreen
    }

    func startProcessing(url: URL) {
        currentScreen = .processing
        processingMessage = "Decoding audio…"
        processingProgress = 0

        processingTask?.cancel()
        processingTask = Task { [weak self] in
            guard let self else { return }

            do {
                // Access security-scoped resource if needed (from fileImporter / Files app)
                var didStartAccess = false
                if url.startAccessingSecurityScopedResource() {
                    didStartAccess = true
                }
                defer {
                    if didStartAccess {
                        url.stopAccessingSecurityScopedResource()
                    }
                }

                // Get recording date from file attributes or use current date
                let recordingDate: Date
                if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                   let creationDate = attributes[.creationDate] as? Date {
                    recordingDate = creationDate
                } else {
                    recordingDate = Date()
                }
                
                // A) Decode
                let decoded = try AudioProcessingService.decodeAnyAudioToPCMBuffer(url: url)
                try Task.checkCancellation()

                // B) Resample
                await MainActor.run {
                    self.processingMessage = "Resampling…"
                }
                let targetRate: Double = 48_000
                let resampled = try AudioProcessingService.resampleToTarget(
                    buffer: decoded,
                    targetSampleRate: targetRate
                )
                try Task.checkCancellation()

                let buffer = resampled
                let sampleRate = buffer.format.sampleRate

                await MainActor.run {
                    self.audioBuffer = buffer
                    self.sampleRate = sampleRate
                    self.recordingDate = recordingDate
                    self.processingMessage = "Analyzing with BirdNET (TFLite)…"
                }

                guard let identifier = self.birdIdentifier else {
                    throw NSError(domain: "Chirper", code: -1, userInfo: [NSLocalizedDescriptionKey: "No BirdIdentifier"])
                }

                let progressHandler: (Int, Int, String) -> Void = { completed, total, message in
                    Task { @MainActor in
                        self.currentWindowIndex = completed
                        self.totalWindows = total
                        self.processingMessage = message
                        if total > 0 {
                            self.processingProgress = Double(completed) / Double(total)
                        }
                    }
                }

                let detections = try await identifier.detect(
                    audioBuffer: buffer,
                    sampleRate: sampleRate,
                    progress: progressHandler
                )
                try Task.checkCancellation()

                await MainActor.run {
                    self.processingMessage = "Splicing clips…"
                }

                // C) Post-process → segments
                let threshold = self.confidenceThreshold
                let paddingSeconds = self.paddingMs / 1000.0
                let audioDuration = AudioProcessingService.duration(of: buffer)

                let speciesSegments = AudioProcessingService.segments(
                    from: detections,
                    audioDuration: audioDuration,
                    sampleRate: sampleRate,
                    confidenceThreshold: threshold,
                    paddingSeconds: paddingSeconds,
                    mergeGapSeconds: 0.25,
                    minClipSeconds: 0.30
                )

                try Task.checkCancellation()

                await MainActor.run {
                    self.detections = detections
                    self.speciesSegments = speciesSegments
                    self.processingProgress = 1.0
                    self.processingMessage = "Done"
                }
                
                // Preload bird images before showing results
                let speciesList = Array(speciesSegments.keys)
                await BirdImageService.shared.preloadImages(for: speciesList)
                
                // Small delay to ensure smooth transition
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                
                await MainActor.run {
                    self.currentScreen = .results
                }
            } catch {
                if Task.isCancelled { return }
                print("Processing failed: \(error)")
                await MainActor.run {
                    self.processingMessage = "Failed: \(error.localizedDescription)"
                    self.currentScreen = .importScreen
                }
            }
        }
    }

    func cancelProcessing() {
        processingTask?.cancel()
        resetToImport()
    }

    var speciesSummaries: [SpeciesSummary] {
        var result: [SpeciesSummary] = []
        for (species, segments) in speciesSegments {
            guard !segments.isEmpty else { continue }
            let maxConf = segments.map { $0.confidence }.max() ?? 0
            let avgConf = segments.map { $0.confidence }.reduce(0, +) / Double(segments.count)
            result.append(
                SpeciesSummary(
                    species: species,
                    maxConfidence: maxConf,
                    averageConfidence: avgConf,
                    clipCount: segments.count
                )
            )
        }
        return result.sorted { $0.maxConfidence > $1.maxConfidence }
    }
}

struct RootView: View {
    @EnvironmentObject var viewModel: AppViewModel

    var body: some View {
        ZStack {
            Color.white
                .ignoresSafeArea()

            switch viewModel.currentScreen {
            case .importScreen:
                ImportView()
            case .processing:
                ProcessingView()
            case .results:
                ResultsView()
            }
        }
    }
}


