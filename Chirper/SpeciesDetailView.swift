import SwiftUI
import AVFoundation
import Combine
import UIKit

struct ShareItem: Identifiable {
    let id = UUID()
    let urls: [URL]
}

struct TrimValues {
    var trimStart: TimeInterval = 0
    var trimEnd: TimeInterval = 0
}

final class SpeciesAudioPlayer: ObservableObject {
    @Published var isPlaying: Bool = false

    private var player: AVAudioPlayer?
    private var timer: Timer?

    var currentTime: TimeInterval {
        player?.currentTime ?? 0
    }

    var duration: TimeInterval {
        player?.duration ?? 0
    }

    func load(buffer: AVAudioPCMBuffer, sampleRate: Double) throws {
        stop()

        let url = try ExportService.writeTempWav(
            buffer: buffer,
            sampleRate: sampleRate,
            fileName: UUID().uuidString + ".wav"
        )

        player = try AVAudioPlayer(contentsOf: url)
        player?.prepareToPlay()
    }

    func playPause() {
        guard let player else { return }

        if player.isPlaying {
            player.pause()
            isPlaying = false
            timer?.invalidate()
        } else {
            player.play()
            isPlaying = true
            startTimer()
        }
    }

    func stop() {
        player?.stop()
        player = nil
        isPlaying = false
        timer?.invalidate()
        timer = nil
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self, let player = self.player else { return }
            if !player.isPlaying {
                self.isPlaying = false
                self.timer?.invalidate()
            }
            self.objectWillChange.send()
        }
    }

    deinit {
        timer?.invalidate()
    }
}

struct SpeciesDetailView: View {
    @EnvironmentObject var viewModel: AppViewModel
    let species: String

    @State private var shareURL: URL?
    @State private var shareURLs: [URL] = []
    @State private var isPresentingShare = false
    @State private var shareItem: ShareItem?
    @State private var playingClipIndex: Int? = nil
    @State private var isPreparingExport = true
    @State private var isOpeningShare = false
    @State private var preparedCombinedURL: URL?
    @State private var preparedSeparateURLs: [URL] = []
    
    private var segments: [Segment] {
        viewModel.speciesSegments[species] ?? []
    }
    
    private var commonName: String {
        parseSpeciesName(species).commonName
    }
    
    private var scientificName: String {
        parseSpeciesName(species).scientificName
    }
    
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    // Bird image (full width)
                    BirdImageFullWidthView(species: species)
                        .frame(height: 200)
                        .clipped()
                    
                    VStack(alignment: .leading, spacing: 12) {
                        // Common name (big and bold)
                        Text(commonName)
                            .font(.title.bold())
                            .foregroundColor(.black)
                        
                        // Scientific name (small and grey, regular weight)
                        Text(scientificName)
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 20)
                    
                    // Individual clips
                    VStack(spacing: 12) {
                        ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                            ClipRow(
                                segment: segment,
                                index: index,
                                isPlaying: playingClipIndex == index,
                                trimStart: Binding(
                                    get: { viewModel.trimValues[species]?[index]?.trimStart ?? 0 },
                                    set: { newValue in
                                        if viewModel.trimValues[species] == nil {
                                            viewModel.trimValues[species] = [:]
                                        }
                                        if viewModel.trimValues[species]?[index] == nil {
                                            viewModel.trimValues[species]?[index] = TrimValues()
                                        }
                                        viewModel.trimValues[species]?[index]?.trimStart = newValue
                                    }
                                ),
                                trimEnd: Binding(
                                    get: { viewModel.trimValues[species]?[index]?.trimEnd ?? 0 },
                                    set: { newValue in
                                        if viewModel.trimValues[species] == nil {
                                            viewModel.trimValues[species] = [:]
                                        }
                                        if viewModel.trimValues[species]?[index] == nil {
                                            viewModel.trimValues[species]?[index] = TrimValues()
                                        }
                                        viewModel.trimValues[species]?[index]?.trimEnd = newValue
                                    }
                                ),
                                onPlay: {
                                    if playingClipIndex == index {
                                        playingClipIndex = nil
                                    } else {
                                        // Stop any currently playing clip
                                        if let currentIndex = playingClipIndex {
                                            playingClipIndex = nil
                                        }
                                        playingClipIndex = index
                                    }
                                },
                                onFinish: {
                                    // Reset playing state when clip finishes
                                    if playingClipIndex == index {
                                        playingClipIndex = nil
                                    }
                                },
                                onTrimChanged: {
                                    // Invalidate prepared exports so they regenerate on next export
                                    preparedCombinedURL = nil
                                    preparedSeparateURLs = []
                                    isPreparingExport = true
                                    prepareExports()
                                }
                            )
                            .environmentObject(viewModel)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 80) // Space for fixed button
                }
            }
            .overlay(alignment: .bottom) {
                // Export buttons fixed at bottom
                VStack(spacing: 12) {
                    if segments.count == 1 {
                        // Single clip - just show "Export clip"
                        if isPreparingExport || preparedCombinedURL == nil {
                            Button {
                                // Disabled
                            } label: {
                                HStack(spacing: 8) {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    Text("Preparing export")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                                .background(Color.black.opacity(0.6))
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .disabled(true)
                        } else if isOpeningShare {
                            Button {
                                // Disabled
                            } label: {
                                HStack(spacing: 8) {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    Text("Loading export...")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                                .background(Color.black)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .disabled(true)
                        } else {
                            Button {
                                exportPreparedCombined()
                            } label: {
                                Text("Export clip")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 50)
                                    .background(Color.black)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    } else {
                        // Multiple clips - show both buttons
                        // Export combined clip button
                        if isPreparingExport || preparedCombinedURL == nil {
                            Button {
                                // Disabled
                            } label: {
                                HStack(spacing: 8) {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    Text("Preparing export")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                                .background(Color.black.opacity(0.6))
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .disabled(true)
                        } else if isOpeningShare {
                            Button {
                                // Disabled
                            } label: {
                                HStack(spacing: 8) {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    Text("Loading export...")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                                .background(Color.black)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .disabled(true)
                        } else {
                            Button {
                                exportPreparedCombined()
                            } label: {
                                Text("Export combined clip")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 50)
                                    .background(Color.black)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                        
                        // Export clips separately button
                        Button {
                            exportPreparedSeparately()
                        } label: {
                            if isPreparingExport || preparedSeparateURLs.isEmpty {
                                HStack(spacing: 8) {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .black))
                                    Text("Preparing export")
                                        .font(.subheadline)
                                        .foregroundColor(.black.opacity(0.6))
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                            } else {
                                Text("Export \(segments.count) clips separately")
                                    .font(.subheadline)
                                    .foregroundColor(.black)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 44)
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(isPreparingExport || preparedSeparateURLs.isEmpty)
                        .transaction { transaction in
                            transaction.animation = nil
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
                .background(
                    LinearGradient(
                        colors: [Color.white.opacity(0), Color.white],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: segments.count == 1 ? 80 : 120)
                )
            }
        }
        .onAppear {
            prepareExports()
            // Listen for stop audio notification
            NotificationCenter.default.addObserver(
                forName: NSNotification.Name("StopAllAudio"),
                object: nil,
                queue: .main
            ) { [self] _ in
                playingClipIndex = nil
            }
        }
        .onDisappear {
            // Stop all audio playback when the sheet is dismissed
            playingClipIndex = nil
            NotificationCenter.default.removeObserver(self, name: NSNotification.Name("StopAllAudio"), object: nil)
        }
        .onChange(of: playingClipIndex) { newValue in
            // When playingClipIndex is set to nil, ensure all clips stop
            if newValue == nil {
                // This will trigger onChange in ClipRow to stop the player
            }
        }
        .sheet(item: $shareItem, onDismiss: {
            // Don't cleanup files immediately - user might want to export again
            // Files will be cleaned up when the view disappears or when new exports are prepared
            shareURL = nil
            shareURLs = []
            shareItem = nil
            isOpeningShare = false
        }) { item in
            ShareSheet(activityItems: item.urls) {
                // Reset loading state when share sheet is dismissed
                isOpeningShare = false
            }
        }
    }
    
    private func prepareExports() {
        guard
            let buffer = viewModel.audioBuffer,
            let segments = viewModel.speciesSegments[species]
        else { return }

        let sampleRate = viewModel.sampleRate
        let speciesName = species
        let currentTrimValues = viewModel.trimValues[species] ?? [:] // Capture current trim values
        
        Task {
            do {
                // Prepare combined export
                let recordingDate = viewModel.recordingDate
                let combinedURL = try await Task.detached(priority: .userInitiated) {
                    // Extract trimmed segments first
                    let sortedSegments = segments.sorted { $0.startSample < $1.startSample }
                    var trimmedBuffers: [AVAudioPCMBuffer] = []
                    
                    for (index, segment) in sortedSegments.enumerated() {
                        let trim = currentTrimValues[index] ?? TrimValues()
                        let trimmedBuffer = try AudioProcessingService.extractSegment(
                            segment: segment,
                            from: buffer,
                            sampleRate: sampleRate,
                            trimStart: trim.trimStart,
                            trimEnd: trim.trimEnd
                        )
                        trimmedBuffers.append(trimmedBuffer)
                    }
                    
                    // Concatenate trimmed buffers
                    let concatenated = try AudioProcessingService.concatenateBuffers(
                        trimmedBuffers,
                        sampleRate: sampleRate
                    )
                    
                    let fileName = ExportService.generateFilename(
                        species: speciesName,
                        recordingDate: recordingDate
                    )
                    return try ExportService.writeTempWav(
                        buffer: concatenated,
                        sampleRate: sampleRate,
                        fileName: fileName
                    )
                }.value
                
                // Prepare separate exports if multiple clips
                var separateURLs: [URL] = []
                if segments.count > 1 {
                    separateURLs = try await Task.detached(priority: .userInitiated) {
                        let sortedSegments = segments.sorted { $0.startSample < $1.startSample }
                        var urls: [URL] = []
                        
                        for (index, segment) in sortedSegments.enumerated() {
                            let trim = currentTrimValues[index] ?? TrimValues()
                            let clipBuffer = try AudioProcessingService.extractSegment(
                                segment: segment,
                                from: buffer,
                                sampleRate: sampleRate,
                                trimStart: trim.trimStart,
                                trimEnd: trim.trimEnd
                            )
                            
                            let fileName = ExportService.generateFilename(
                                species: speciesName,
                                recordingDate: recordingDate,
                                clipIndex: index + 1
                            )
                            
                            let url = try ExportService.writeTempWav(
                                buffer: clipBuffer,
                                sampleRate: sampleRate,
                                fileName: fileName
                            )
                            urls.append(url)
                        }
                        return urls
                    }.value
                }
                
                // No delay needed - file is already written synchronously
                
                // Update UI on main thread - verify files exist and are readable before enabling
                await MainActor.run {
                    // Verify combined file exists and is readable before setting
                    if FileManager.default.fileExists(atPath: combinedURL.path) && FileManager.default.isReadableFile(atPath: combinedURL.path) {
                        // Check file size to ensure it's not empty
                        if let attributes = try? FileManager.default.attributesOfItem(atPath: combinedURL.path),
                           let fileSize = attributes[.size] as? Int64, fileSize > 0 {
                            self.preparedCombinedURL = combinedURL
                        }
                    }
                    
                    // Verify separate files exist if multiple clips
                    if segments.count > 1 {
                        let validURLs = separateURLs.filter { url in
                            guard FileManager.default.fileExists(atPath: url.path),
                                  FileManager.default.isReadableFile(atPath: url.path),
                                  let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                                  let fileSize = attributes[.size] as? Int64, fileSize > 0 else {
                                return false
                            }
                            return true
                        }
                        if validURLs.count == separateURLs.count {
                            self.preparedSeparateURLs = validURLs
                        }
                    }
                    
                    // Only mark as ready when the combined URL is actually set and file is valid
                    if let url = self.preparedCombinedURL, FileManager.default.fileExists(atPath: url.path) {
                        if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                           let fileSize = attributes[.size] as? Int64, fileSize > 0 {
                            self.isPreparingExport = false
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    self.isPreparingExport = false
                }
            }
        }
    }
    
    private func exportPreparedCombined() {
        // Regenerate if invalidated
        if preparedCombinedURL == nil && isPreparingExport {
            prepareExports()
            return
        }
        
        guard let url = preparedCombinedURL else {
            return
        }
        // Verify file exists, is readable, and has content before sharing
        guard FileManager.default.fileExists(atPath: url.path),
              FileManager.default.isReadableFile(atPath: url.path),
              let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let fileSize = attributes[.size] as? Int64, fileSize > 0 else {
            // File was deleted, regenerate it
            preparedCombinedURL = nil
            isPreparingExport = true
            prepareExports()
            return
        }
        
        // Set loading state immediately to show feedback
        isOpeningShare = true
        
        // Present share sheet asynchronously to avoid blocking the UI
        Task { @MainActor in
            // Small delay to ensure loading state is visible and UI can update
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            
            // Set share item which will trigger the sheet
            shareURL = url
            shareURLs = [] // Clear separate URLs to ensure we use combined
            shareItem = ShareItem(urls: [url])
        }
    }
    
    private func exportPreparedSeparately() {
        // Regenerate if invalidated
        if preparedSeparateURLs.isEmpty && isPreparingExport {
            prepareExports()
            return
        }
        
        guard !preparedSeparateURLs.isEmpty else {
            return
        }
        // Verify all files exist, are readable, and have content before sharing
        let validURLs = preparedSeparateURLs.filter { url in
            guard FileManager.default.fileExists(atPath: url.path),
                  FileManager.default.isReadableFile(atPath: url.path),
                  let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                  let fileSize = attributes[.size] as? Int64, fileSize > 0 else {
                return false
            }
            return true
        }
        guard !validURLs.isEmpty else {
            // Files were deleted, regenerate them
            preparedSeparateURLs = []
            isPreparingExport = true
            prepareExports()
            return
        }
        
        // If some files are missing, regenerate
        if validURLs.count < preparedSeparateURLs.count {
            preparedSeparateURLs = []
            isPreparingExport = true
            prepareExports()
            return
        }
        
        // Set loading state immediately to show feedback
        isOpeningShare = true
        
        // Present share sheet asynchronously to avoid blocking the UI
        Task { @MainActor in
            // Small delay to ensure loading state is visible and UI can update
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            
            shareURLs = validURLs
            shareURL = nil // Clear combined URL
            shareItem = ShareItem(urls: validURLs)
        }
    }
    
    private func parseSpeciesName(_ species: String) -> (commonName: String, scientificName: String) {
        if let underscoreIndex = species.lastIndex(of: "_") {
            let scientificName = String(species[..<underscoreIndex])
            let commonName = String(species[species.index(after: underscoreIndex)...])
            return (commonName, scientificName)
        } else {
            return (species, "")
        }
    }

struct ClipRow: View {
    let segment: Segment
    let index: Int
    let isPlaying: Bool
    @Binding var trimStart: TimeInterval
    @Binding var trimEnd: TimeInterval
    let onPlay: () -> Void
    let onFinish: () -> Void
    let onTrimChanged: () -> Void
    
    @EnvironmentObject var viewModel: AppViewModel
    @StateObject private var clipPlayer = ClipAudioPlayer()
    @State private var isLoading = false
    
    private var duration: TimeInterval {
        let sampleRate = viewModel.sampleRate
        return Double(segment.endSample - segment.startSample) / sampleRate
    }
    
    private var trimmedDuration: TimeInterval {
        max(0, duration - trimStart - trimEnd)
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Play button
            Button {
                let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                impactFeedback.impactOccurred()
                
                if isPlaying {
                    clipPlayer.stop()
                    onPlay()
                } else {
                    Task {
                        await playClip()
                        onPlay()
                    }
                }
            } label: {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .black))
                        .frame(width: 40, height: 40)
                        .background(Color.gray.opacity(0.1))
                        .clipShape(Circle())
                } else {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3)
                        .foregroundColor(.black)
                        .frame(width: 40, height: 40)
                        .background(Color.gray.opacity(0.1))
                        .clipShape(Circle())
                        .animation(nil, value: isPlaying)
                }
            }
            .disabled(isLoading)
            
            // Waveform visualization
            WaveformView(
                segment: segment,
                isPlaying: isPlaying,
                currentTime: clipPlayer.currentTime,
                duration: duration,
                trimStart: $trimStart,
                trimEnd: $trimEnd,
                onSeek: { time in
                    clipPlayer.seek(to: time)
                },
                onStop: {
                    clipPlayer.stop()
                    onPlay() // This will update the playing state
                },
                onTrimChanged: {
                    onTrimChanged()
                }
            )
            .environmentObject(viewModel)
            .frame(height: 40)
            
            Spacer()
            
            // Duration
            Text(String(format: "%.1fs", trimmedDuration))
                .font(.caption)
                .foregroundColor(.gray)
        }
        .padding(12)
        .background(Color.gray.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onChange(of: isPlaying) { playing in
            if !playing {
                clipPlayer.stop()
            }
        }
        .onAppear {
            clipPlayer.onFinish = {
                DispatchQueue.main.async {
                    onFinish() // Reset to play button
                }
            }
            // Listen for stop audio notification
            let player = clipPlayer
            NotificationCenter.default.addObserver(
                forName: NSNotification.Name("StopAllAudio"),
                object: nil,
                queue: .main
            ) { _ in
                player.stop()
            }
        }
    }
    
    private func playClip() async {
        guard let buffer = viewModel.audioBuffer else { return }
        let sampleRate = viewModel.sampleRate
        
        isLoading = true
        
        do {
            let clipBuffer = try AudioProcessingService.extractSegment(
                segment: segment,
                from: buffer,
                sampleRate: sampleRate,
                trimStart: trimStart,
                trimEnd: trimEnd
            )
            clipPlayer.onFinish = {
                DispatchQueue.main.async {
                    onFinish() // Reset to play button
                }
            }
            try clipPlayer.load(buffer: clipBuffer, sampleRate: sampleRate)
            
            // Small delay to ensure loading state is visible
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            
            await MainActor.run {
                isLoading = false
                clipPlayer.play()
            }
        } catch {
            await MainActor.run {
                isLoading = false
            }
        }
    }
    
}

final class ClipAudioPlayer: ObservableObject {
    private var player: AVAudioPlayer?
    private var timer: Timer?
    var onFinish: (() -> Void)?
    
    @Published var currentTime: TimeInterval = 0
    
    var duration: TimeInterval {
        player?.duration ?? 0
    }
    
    func load(buffer: AVAudioPCMBuffer, sampleRate: Double) throws {
        stop()
        
        let url = try ExportService.writeTempWav(
            buffer: buffer,
            sampleRate: sampleRate,
            fileName: UUID().uuidString + ".wav"
        )
        
        player = try AVAudioPlayer(contentsOf: url)
        player?.prepareToPlay()
        let onFinishCallback = self.onFinish
        player?.delegate = ClipAudioPlayerDelegate { [weak self] in
            DispatchQueue.main.async {
                self?.stop()
                onFinishCallback?()
            }
        }
    }
    
    func play() {
        player?.play()
        startTimer()
    }
    
    func stop() {
        player?.stop()
        player = nil
        timer?.invalidate()
        timer = nil
        currentTime = 0
    }
    
    func seek(to time: TimeInterval) {
        guard let player = player else { return }
        let clampedTime = max(0, min(time, player.duration))
        player.currentTime = clampedTime
        currentTime = clampedTime
    }
    
    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self = self, let player = self.player else { return }
            Task { @MainActor in
                self.currentTime = player.currentTime
                // Don't stop timer here - let the delegate handle completion
            }
        }
    }
}

class ClipAudioPlayerDelegate: NSObject, AVAudioPlayerDelegate {
    let onFinish: () -> Void
    
    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
    }
    
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async {
            self.onFinish()
        }
    }
}

struct WaveformView: View {
    let segment: Segment
    let isPlaying: Bool
    let currentTime: TimeInterval
    let duration: TimeInterval
    @Binding var trimStart: TimeInterval
    @Binding var trimEnd: TimeInterval
    let onSeek: (TimeInterval) -> Void
    let onStop: () -> Void
    let onTrimChanged: () -> Void
    
    @EnvironmentObject var viewModel: AppViewModel
    @State private var waveformData: [Float] = []
    @State private var isDragging = false
    @State private var dragTime: TimeInterval = 0
    @State private var draggingHandle: HandleType? = nil
    @State private var dragStartX: CGFloat = 0
    @State private var initialTrimStart: TimeInterval = 0
    @State private var initialTrimEnd: TimeInterval = 0
    @State private var lastHapticTime: Date = Date()
    @State private var hapticGenerator = UIImpactFeedbackGenerator(style: .medium)
    
    enum HandleType {
        case left, right
    }
    
    private var trimmedDuration: TimeInterval {
        max(0, duration - trimStart - trimEnd)
    }
    
    var body: some View {
        GeometryReader { geometry in
            // Calculate trim positions (needed for both waveform and gesture)
            let trimStartProgress = duration > 0 ? trimStart / duration : 0
            let trimEndProgress = duration > 0 ? trimEnd / duration : 0
            let trimStartX = geometry.size.width * CGFloat(trimStartProgress)
            let trimEndX = geometry.size.width * CGFloat(1.0 - trimEndProgress)
            
            ZStack(alignment: .leading) {
                if waveformData.isEmpty {
                    // Placeholder while loading
                    HStack(spacing: 2) {
                        ForEach(0..<50, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 1)
                                .fill(Color.gray.opacity(0.3))
                                .frame(width: 2, height: 4)
                        }
                    }
                } else {
                    let barCount = waveformData.count
                    let barWidth = max(1.0, geometry.size.width / CGFloat(barCount))
                    
                    // Waveform bars with opacity based on trim region
                    HStack(spacing: 1) {
                        ForEach(Array(waveformData.enumerated()), id: \.offset) { index, amplitude in
                            let barX = CGFloat(index) * barWidth
                            let isInActiveRegion = barX >= trimStartX && barX < trimEndX
                            let opacity = isInActiveRegion ? 1.0 : 0.2
                            
                            RoundedRectangle(cornerRadius: 1)
                                .fill(Color.black.opacity(opacity))
                                .frame(width: barWidth - 1)
                                .frame(height: max(2, CGFloat(abs(amplitude)) * geometry.size.height))
                        }
                    }
                    
                    // Active region - box (grey by default, blue when dragging)
                    let boxColor = draggingHandle != nil ? Color.blue : Color.gray
                    Rectangle()
                        .fill(boxColor.opacity(0.15))
                        .frame(width: trimEndX - trimStartX)
                        .frame(height: geometry.size.height)
                        .offset(x: trimStartX)
                    
                    Rectangle()
                        .stroke(boxColor.opacity(0.6), lineWidth: 2)
                        .frame(width: trimEndX - trimStartX)
                        .frame(height: geometry.size.height)
                        .offset(x: trimStartX)
                    
                    // Left trim handle (grey by default, blue when dragging)
                    let leftHandleColor = draggingHandle == .left ? Color.blue : Color.gray
                    ZStack {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(leftHandleColor)
                            .frame(width: 6)
                            .frame(height: geometry.size.height)
                        // Handle grip indicator
                        VStack(spacing: 2) {
                            ForEach(0..<3) { _ in
                                RoundedRectangle(cornerRadius: 0.5)
                                    .fill(Color.white.opacity(0.8))
                                    .frame(width: 1.5, height: 1.5)
                            }
                        }
                    }
                    .frame(width: 30, height: geometry.size.height)
                    .offset(x: trimStartX - 15)
                    .zIndex(10)
                    
                    // Right trim handle (grey by default, blue when dragging)
                    let rightHandleColor = draggingHandle == .right ? Color.blue : Color.gray
                    ZStack {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(rightHandleColor)
                            .frame(width: 6)
                            .frame(height: geometry.size.height)
                        // Handle grip indicator
                        VStack(spacing: 2) {
                            ForEach(0..<3) { _ in
                                RoundedRectangle(cornerRadius: 0.5)
                                    .fill(Color.white.opacity(0.8))
                                    .frame(width: 1.5, height: 1.5)
                            }
                        }
                    }
                    .frame(width: 30, height: geometry.size.height)
                    .offset(x: trimEndX - 15)
                    .zIndex(10)
                    
                    // Playhead indicator (show when playing or when dragging, within trimmed region)
                    if duration > 0 && trimmedDuration > 0 {
                        let displayTime = isDragging ? dragTime : currentTime
                        // currentTime is relative to trimmed audio (0 to trimmedDuration)
                        // Map it to the full waveform position
                        let trimmedProgress = displayTime / trimmedDuration
                        let playheadX = trimStartX + CGFloat(trimmedProgress) * (trimEndX - trimStartX)
                        
                        if playheadX >= trimStartX && playheadX <= trimEndX {
                            Rectangle()
                                .fill(Color.green)
                                .frame(width: 2)
                                .frame(height: geometry.size.height)
                                .offset(x: playheadX - 1)
                        }
                    }
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        // If we're already dragging a handle, continue with that handle
                        if let handle = draggingHandle {
                            // Haptic feedback - tick every 0.05 seconds while dragging
                            let currentTime = Date()
                            if currentTime.timeIntervalSince(lastHapticTime) > 0.05 {
                                hapticGenerator.impactOccurred()
                                lastHapticTime = currentTime
                            }
                            
                            switch handle {
                            case .left:
                                // Calculate new position: initial position + translation
                                let initialX = geometry.size.width * CGFloat(initialTrimStart / duration)
                                let newX = initialX + value.translation.width
                                let progress = max(0, min(1, Double(newX / geometry.size.width)))
                                let proposedTrimStart = max(0, min(duration - trimEnd, progress * duration))
                                // Check minimum duration constraint (0.7 seconds)
                                let proposedDuration = duration - proposedTrimStart - trimEnd
                                if proposedDuration >= 0.7 {
                                    trimStart = proposedTrimStart
                                }
                            case .right:
                                // Calculate new position: initial position + translation
                                let initialX = geometry.size.width * CGFloat(1.0 - initialTrimEnd / duration)
                                let newX = initialX + value.translation.width
                                let progress = max(0, min(1, Double(newX / geometry.size.width)))
                                let proposedTrimEnd = max(0, min(duration - trimStart, (1.0 - progress) * duration))
                                // Check minimum duration constraint (0.7 seconds)
                                let proposedDuration = duration - trimStart - proposedTrimEnd
                                if proposedDuration >= 0.7 {
                                    trimEnd = proposedTrimEnd
                                }
                            }
                        } else {
                            // Check if we're starting near a handle
                            let handleThreshold: CGFloat = 30
                            let isNearLeftHandle = abs(value.startLocation.x - trimStartX) < handleThreshold
                            let isNearRightHandle = abs(value.startLocation.x - trimEndX) < handleThreshold
                            
                            if isNearLeftHandle {
                                // Stop audio if playing
                                if isPlaying {
                                    onStop()
                                }
                                draggingHandle = .left
                                initialTrimStart = trimStart
                                lastHapticTime = Date()
                                hapticGenerator.prepare()
                                hapticGenerator.impactOccurred()
                                // Calculate new position: initial position + translation
                                let initialX = geometry.size.width * CGFloat(initialTrimStart / duration)
                                let newX = initialX + value.translation.width
                                let progress = max(0, min(1, Double(newX / geometry.size.width)))
                                let proposedTrimStart = max(0, min(duration - trimEnd, progress * duration))
                                // Check minimum duration constraint (0.7 seconds)
                                let proposedDuration = duration - proposedTrimStart - trimEnd
                                if proposedDuration >= 0.7 {
                                    trimStart = proposedTrimStart
                                }
                            } else if isNearRightHandle {
                                // Stop audio if playing
                                if isPlaying {
                                    onStop()
                                }
                                draggingHandle = .right
                                initialTrimEnd = trimEnd
                                lastHapticTime = Date()
                                hapticGenerator.prepare()
                                hapticGenerator.impactOccurred()
                                // Calculate new position: initial position + translation
                                let initialX = geometry.size.width * CGFloat(1.0 - initialTrimEnd / duration)
                                let newX = initialX + value.translation.width
                                let progress = max(0, min(1, Double(newX / geometry.size.width)))
                                let proposedTrimEnd = max(0, min(duration - trimStart, (1.0 - progress) * duration))
                                // Check minimum duration constraint (0.7 seconds)
                                let proposedDuration = duration - trimStart - proposedTrimEnd
                                if proposedDuration >= 0.7 {
                                    trimEnd = proposedTrimEnd
                                }
                            } else {
                                // Waveform scrubbing - only when playing
                                guard isPlaying else { return }
                                
                                isDragging = true
                                let progress = max(0, min(1, Double(value.location.x / geometry.size.width)))
                                // Map to trimmed region
                                let trimmedProgress = (progress - trimStartProgress) / (1.0 - trimStartProgress - trimEndProgress)
                                dragTime = trimmedProgress * trimmedDuration
                            }
                        }
                    }
                    .onEnded { value in
                        if draggingHandle != nil {
                            // Dragging ended - trigger export preparation
                            draggingHandle = nil
                            onTrimChanged()
                        } else if isPlaying {
                            // Waveform scrubbing
                            let progress = max(0, min(1, Double(value.location.x / geometry.size.width)))
                            // Map to trimmed region
                            let trimmedProgress = (progress - trimStartProgress) / (1.0 - trimStartProgress - trimEndProgress)
                            let seekTime = trimmedProgress * trimmedDuration
                            onSeek(seekTime)
                            isDragging = false
                        }
                    }
            )
        }
        .task {
            await generateWaveform()
        }
    }
    
    private var trimStartProgress: Double {
        duration > 0 ? trimStart / duration : 0
    }
    
    private var trimEndProgress: Double {
        duration > 0 ? trimEnd / duration : 0
    }
    
    private func generateWaveform() async {
        guard let buffer = viewModel.audioBuffer else { return }
        let sampleRate = viewModel.sampleRate
        
        do {
            let clipBuffer = try AudioProcessingService.extractSegment(
                segment: segment,
                from: buffer,
                sampleRate: sampleRate
            )
            
            let samples = AudioProcessingService.floatSamples(from: clipBuffer)
            
            // Downsample to ~100 bars for visualization
            let targetBars = 100
            let samplesPerBar = max(1, samples.count / targetBars)
            var bars: [Float] = []
            
            for i in stride(from: 0, to: samples.count, by: samplesPerBar) {
                let endIndex = min(i + samplesPerBar, samples.count)
                let chunk = samples[i..<endIndex]
                // Calculate RMS (root mean square) for this chunk
                let rms = sqrt(chunk.map { $0 * $0 }.reduce(0, +) / Float(chunk.count))
                bars.append(rms)
            }
            
            // Normalize to 0-1 range
            if let maxAmplitude = bars.max(), maxAmplitude > 0 {
                bars = bars.map { $0 / maxAmplitude }
            }
            
            await MainActor.run {
                waveformData = bars
            }
        } catch {
            // Silently fail waveform generation
        }
    }
}

}


