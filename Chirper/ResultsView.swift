import SwiftUI
import AVFoundation
import Combine
import UIKit

struct ResultsView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @State private var selectedSpecies: SpeciesSummary?
    @State private var shareURLs: [URL] = []
    @State private var isPresentingShareSheet = false
    @State private var isExportingAll = false
    @State private var isShowingExportOptions = false
    @State private var isPreparingExports = true
    @State private var playingSpecies: String? = nil
    @StateObject private var speciesPlayer = SpeciesClipsPlayer()
    @State private var playbackTask: Task<Void, Never>? = nil
    @State private var isSelectionMode = false
    @State private var selectedSpeciesSet: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            header
            
            listSection
            
            Spacer()
            
            VStack(spacing: 20) {
                exportAllButton
                cancelButton
            }
            .padding(.top, 16)
        }
        .padding(.horizontal, 16)
        .padding(.top, 24)
        .padding(.bottom, 24)
        .sheet(item: $selectedSpecies, onDismiss: {
            // Stop all audio when sheet is dismissed
            DispatchQueue.main.async {
                playbackTask?.cancel()
                playbackTask = nil
                NotificationCenter.default.post(name: NSNotification.Name("StopAllAudio"), object: nil)
                playingSpecies = nil
                speciesPlayer.stop()
            }
        }) { species in
            SpeciesDetailView(species: species.species)
                .environmentObject(viewModel)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .onChange(of: selectedSpecies) { oldValue, newValue in
            // Stop all audio when sheet is opened or dismissed
            DispatchQueue.main.async {
                playbackTask?.cancel()
                playbackTask = nil
                NotificationCenter.default.post(name: NSNotification.Name("StopAllAudio"), object: nil)
                playingSpecies = nil
                speciesPlayer.stop()
            }
        }
        .onAppear {
            prepareAllExports()
        }
        .sheet(isPresented: $isPresentingShareSheet, onDismiss: {
            ExportService.cleanupTempFiles(urls: shareURLs)
            shareURLs.removeAll()
        }) {
            ShareSheet(activityItems: shareURLs)
        }
        .sheet(isPresented: $isShowingExportOptions) {
            exportOptionsSheet
        }
    }
    
    private func prepareAllExports() {
        // Mark as preparing initially
        isPreparingExports = true
        
        // Small delay to ensure UI updates, then mark as ready
        // (For Export All, we prepare on-demand when user clicks, so we can mark ready quickly)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            isPreparingExports = false
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            HStack {
                HStack(spacing: 8) {
                    if isSelectionMode {
                        Text("\(selectedSpeciesSet.count) selected")
                            .font(.title3.bold())
                            .foregroundColor(.black)
                            .lineLimit(1)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.title2)
                        
                        Text("Extracted \(totalClipCount) chirp\(totalClipCount == 1 ? "" : "s")")
                            .font(.title3.bold())
                            .foregroundColor(.black)
                            .lineLimit(1)
                    }
                }
                
                Spacer()
                
                if isSelectionMode {
                    GlassCancelButton {
                        isSelectionMode = false
                        selectedSpeciesSet.removeAll()
                    }
                } else {
                    Button {
                        viewModel.resetToImport()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.black)
                            .frame(width: 32, height: 32)
                            .background(Color.white)
                            .clipShape(Circle())
                    }
                }
            }

            if viewModel.usingMock {
                GlassBanner(text: "Using mock detections (BirdNET unavailable).")
                    .padding(.top, 8)
            }
        }
        .padding(.bottom, 16)
    }

    @ViewBuilder
    private var exportAllButton: some View {
        if isPreparingExports || isExportingAll {
            Button {
                // Disabled
            } label: {
                HStack(spacing: 8) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    Text(isExportingAll ? "Exporting..." : "Processing export")
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
            .opacity(1.0)
        } else {
            Button {
                if isSelectionMode {
                    isShowingExportOptions = true
                } else {
                    isShowingExportOptions = true
                }
            } label: {
                if isSelectionMode {
                    let selectedCount = selectedSpeciesSet.reduce(0) { total, species in
                        total + (viewModel.speciesSegments[species]?.count ?? 0)
                    }
                    Text("Export selected (\(selectedCount))")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(selectedSpeciesSet.isEmpty ? Color.black.opacity(0.3) : Color.black)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else {
                    Text("Export all (\(totalClipCount))")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.black)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            .buttonStyle(.plain)
            .disabled(isSelectionMode ? selectedSpeciesSet.isEmpty : viewModel.speciesSegments.isEmpty)
            .opacity((isSelectionMode ? selectedSpeciesSet.isEmpty : viewModel.speciesSegments.isEmpty) ? 0.5 : 1.0)
        }
    }
    
    private var cancelButton: some View {
        Button {
            if isSelectionMode {
                isSelectionMode = false
                selectedSpeciesSet.removeAll()
            } else {
                viewModel.resetToImport()
            }
        } label: {
            Text(isSelectionMode ? "Cancel" : "Import another audio")
                .font(.body)
                .foregroundColor(.gray)
        }
    }
    
    private var exportOptionsSheet: some View {
        NavigationView {
            VStack(spacing: 20) {
                Picker("", selection: Binding(
                    get: { viewModel.exportMode },
                    set: { viewModel.exportMode = $0 }
                )) {
                    Text("Per Species").tag(ExportMode.perSpecies)
                    Text("Per Call").tag(ExportMode.perCall)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)
                .padding(.top, 20)
                
                if isExportingAll {
                    Button {
                        // Disabled
                    } label: {
                        HStack(spacing: 8) {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            Text("Exporting...")
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
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                } else {
                    let count: Int = {
                        if isSelectionMode {
                            return viewModel.exportMode == .perSpecies 
                                ? selectedSpeciesSet.count 
                                : selectedSpeciesSet.reduce(0) { total, species in
                                    total + (viewModel.speciesSegments[species]?.count ?? 0)
                                }
                        } else {
                            return viewModel.exportMode == .perSpecies 
                                ? filteredSpeciesSummaries.count 
                                : totalClipCount
                        }
                    }()
                    
                    Button {
                        isShowingExportOptions = false
                        if isSelectionMode {
                            exportSelected()
                        } else {
                            exportAll()
                        }
                    } label: {
                        Text("Confirm export \(isSelectionMode ? "selected" : "all") (\(count))")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Color.black)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            }
            .navigationTitle("Export Options")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.height(180)])
    }
    
    private var filteredSpeciesSummaries: [SpeciesSummary] {
        viewModel.speciesSummaries.filter { $0.maxConfidence > 0.75 }
    }
    
    private var totalClipCount: Int {
        filteredSpeciesSummaries.reduce(0) { $0 + $1.clipCount }
    }

    private var listSection: some View {
        Group {
            if filteredSpeciesSummaries.isEmpty {
                GlassCard {
                    Text("No species above the current confidence threshold. Try lowering it or using a different recording.")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .padding(16)
                }
                .padding(.top, 16)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(filteredSpeciesSummaries) { summary in
                            if isSelectionMode {
                                Button {
                                    // Hard haptic feedback when selecting/deselecting
                                    let impactFeedback = UIImpactFeedbackGenerator(style: .heavy)
                                    impactFeedback.impactOccurred()
                                    
                                    if selectedSpeciesSet.contains(summary.species) {
                                        // If this is the only selected item, exit selection mode
                                        if selectedSpeciesSet.count == 1 {
                                            isSelectionMode = false
                                            selectedSpeciesSet.removeAll()
                                        } else {
                                            selectedSpeciesSet.remove(summary.species)
                                        }
                                    } else {
                                        selectedSpeciesSet.insert(summary.species)
                                    }
                                } label: {
                                    speciesRowContent(summary)
                                }
                                .buttonStyle(.plain)
                            } else {
                                speciesRowContent(summary)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        if !isSelectionMode {
                                            selectedSpecies = summary
                                        }
                                    }
                                    .highPriorityGesture(
                                        LongPressGesture(minimumDuration: 0.5)
                                            .onEnded { _ in
                                                // Stop any playing audio
                                                playbackTask?.cancel()
                                                playbackTask = nil
                                                playingSpecies = nil
                                                speciesPlayer.stop()
                                                
                                                // Hard haptic feedback when entering selection mode
                                                let impactFeedback = UIImpactFeedbackGenerator(style: .heavy)
                                                impactFeedback.impactOccurred()
                                                
                                                isSelectionMode = true
                                                selectedSpeciesSet.insert(summary.species)
                                            }
                                    )
                            }
                        }
                    }
                    .padding(.top, 16)
                    .padding(.bottom, 8)
                }
            }
        }
    }

    private func speciesRowContent(_ summary: SpeciesSummary) -> some View {
        let (commonName, scientificName) = parseSpeciesName(summary.species)
        let isSelected = selectedSpeciesSet.contains(summary.species)
        let opacity = isSelectionMode && !isSelected ? 0.5 : 1.0
        
        return ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    .white.opacity(0.3),
                                    .white.opacity(0.05)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
            
            HStack(spacing: 12) {
                // Bird image with play button
                BirdImageViewWithPlayButton(
                    species: summary.species,
                    isPlaying: playingSpecies == summary.species && !isSelectionMode,
                    onPlay: {
                        if !isSelectionMode {
                            if playingSpecies == summary.species {
                                // Pause current species
                                playbackTask?.cancel()
                                playbackTask = nil
                                playingSpecies = nil
                                speciesPlayer.stop()
                            } else {
                                // Stop any currently playing species first
                                playbackTask?.cancel()
                                playbackTask = nil
                                playingSpecies = nil
                                speciesPlayer.stop()
                                
                                // Start the new species immediately
                                playingSpecies = summary.species
                                playbackTask = Task {
                                    await playAllClipsForSpecies(summary.species)
                                }
                            }
                        }
                    }
                )
                .environmentObject(viewModel)
                .allowsHitTesting(!isSelectionMode)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(commonName)
                        .font(.headline.bold())
                        .foregroundColor(.black)
                    
                    Text(scientificName)
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                
                Spacer()
                
                HStack(spacing: 4) {
                    if isSelectionMode {
                        if selectedSpeciesSet.contains(summary.species) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title3)
                                .foregroundColor(.black)
                        } else {
                            Image(systemName: "circle")
                                .font(.title3)
                                .foregroundColor(.gray)
                        }
                    } else {
                        Text("\(summary.clipCount) clip\(summary.clipCount == 1 ? "" : "s")")
                            .font(.subheadline.bold())
                            .foregroundColor(.gray)
                        
                        Image(systemName: "chevron.right")
                            .font(.caption.bold())
                            .foregroundColor(.gray)
                    }
                }
            }
            .padding(12)
        }
        .opacity(opacity)
    }
    
    private func parseSpeciesName(_ species: String) -> (commonName: String, scientificName: String) {
        // Format is typically "ScientificName_CommonName" or just "CommonName"
        if let underscoreIndex = species.lastIndex(of: "_") {
            let scientificName = String(species[..<underscoreIndex])
            let commonName = String(species[species.index(after: underscoreIndex)...])
            return (commonName, scientificName)
        } else {
            // If no underscore, treat entire string as common name
            return (species, "")
        }
    }

    private func recomputeSegments() {
        guard let buffer = viewModel.audioBuffer else { return }
        let sampleRate = viewModel.sampleRate
        let audioDuration = AudioProcessingService.duration(of: buffer)
        let threshold = viewModel.confidenceThreshold
        let paddingSeconds = viewModel.paddingMs / 1000.0

        let newSegments = AudioProcessingService.segments(
            from: viewModel.detections,
            audioDuration: audioDuration,
            sampleRate: sampleRate,
            confidenceThreshold: threshold,
            paddingSeconds: paddingSeconds,
            mergeGapSeconds: 0.25,
            minClipSeconds: 0.30
        )

        viewModel.speciesSegments = newSegments
    }

    private func exportAll() {
        guard let buffer = viewModel.audioBuffer else { return }
        let segments = viewModel.speciesSegments
        let mode = viewModel.exportMode

        isExportingAll = true

        Task {
            do {
                let urls: [URL]
                switch mode {
                case .perSpecies:
                    urls = try ExportService.exportPerSpecies(
                        speciesSegments: segments,
                        from: buffer,
                        sampleRate: viewModel.sampleRate,
                        recordingDate: viewModel.recordingDate
                    )
                case .perCall:
                    urls = try ExportService.exportPerCall(
                        speciesSegments: segments,
                        from: buffer,
                        sampleRate: viewModel.sampleRate,
                        recordingDate: viewModel.recordingDate
                    )
                }

                // Verify all files exist and are valid before showing share sheet
                let validURLs = urls.filter { url in
                    guard FileManager.default.fileExists(atPath: url.path),
                          FileManager.default.isReadableFile(atPath: url.path),
                          let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                          let fileSize = attributes[.size] as? Int64, fileSize > 0 else {
                        return false
                    }
                    return true
                }
                
                // Small delay to ensure files are fully written and accessible
                try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
                
                await MainActor.run {
                    if !validURLs.isEmpty {
                        shareURLs = validURLs
                        isPresentingShareSheet = true
                    }
                    isExportingAll = false
                }
            } catch {
                await MainActor.run {
                    isExportingAll = false
                }
            }
        }
    }
    
    private func exportSelected() {
        guard let buffer = viewModel.audioBuffer else { return }
        // Filter segments to only include selected species
        let filteredSegments = viewModel.speciesSegments.filter { selectedSpeciesSet.contains($0.key) }
        let mode = viewModel.exportMode

        isExportingAll = true

        Task {
            do {
                let urls: [URL]
                switch mode {
                case .perSpecies:
                    urls = try ExportService.exportPerSpecies(
                        speciesSegments: filteredSegments,
                        from: buffer,
                        sampleRate: viewModel.sampleRate,
                        recordingDate: viewModel.recordingDate
                    )
                case .perCall:
                    urls = try ExportService.exportPerCall(
                        speciesSegments: filteredSegments,
                        from: buffer,
                        sampleRate: viewModel.sampleRate,
                        recordingDate: viewModel.recordingDate
                    )
                }

                // Verify all files exist and are valid before showing share sheet
                let validURLs = urls.filter { url in
                    guard FileManager.default.fileExists(atPath: url.path),
                          FileManager.default.isReadableFile(atPath: url.path),
                          let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                          let fileSize = attributes[.size] as? Int64, fileSize > 0 else {
                        return false
                    }
                    return true
                }
                
                // Small delay to ensure files are fully written and accessible
                try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
                
                await MainActor.run {
                    if !validURLs.isEmpty {
                        shareURLs = validURLs
                        isPresentingShareSheet = true
                        // Exit selection mode after export
                        isSelectionMode = false
                        selectedSpeciesSet.removeAll()
                    }
                    isExportingAll = false
                }
            } catch {
                await MainActor.run {
                    isExportingAll = false
                }
            }
        }
    }
    
    private func playAllClipsForSpecies(_ species: String) async {
        guard let buffer = viewModel.audioBuffer,
              let segments = viewModel.speciesSegments[species],
              !segments.isEmpty else {
            await MainActor.run {
                if playingSpecies == species {
                    playingSpecies = nil
                }
            }
            return
        }
        
        // Check if task was cancelled
        try? Task.checkCancellation()
        
        let sampleRate = viewModel.sampleRate
        let sortedSegments = segments.sorted { $0.startSample < $1.startSample }
        let trimValues = viewModel.trimValues[species] ?? [:]
        
        await MainActor.run {
            speciesPlayer.stop()
        }
        
        for (index, segment) in sortedSegments.enumerated() {
            // Check if task was cancelled
            try? Task.checkCancellation()
            
            // Check if we should stop (user paused or opened sheet)
            let shouldContinue = await MainActor.run { playingSpecies == species }
            if !shouldContinue {
                break
            }
            
            do {
                // Get trim values for this segment index
                let trim = trimValues[index] ?? TrimValues()
                
                let clipBuffer = try AudioProcessingService.extractSegment(
                    segment: segment,
                    from: buffer,
                    sampleRate: sampleRate,
                    trimStart: trim.trimStart,
                    trimEnd: trim.trimEnd
                )
                
                var clipFinished = false
                await MainActor.run {
                    do {
                        try speciesPlayer.load(buffer: clipBuffer, sampleRate: sampleRate)
                        speciesPlayer.onFinish = {
                            clipFinished = true
                        }
                        speciesPlayer.play()
                    } catch {
                        clipFinished = true
                    }
                }
                
                // Wait for clip to finish
                while !clipFinished {
                    // Check if task was cancelled
                    try? Task.checkCancellation()
                    
                    let stillPlaying = await MainActor.run { speciesPlayer.isPlaying }
                    if !stillPlaying {
                        clipFinished = true
                    } else {
                        // Check if we should stop
                        let shouldContinue = await MainActor.run { playingSpecies == species }
                        if !shouldContinue {
                            await MainActor.run {
                                speciesPlayer.stop()
                            }
                            break
                        }
                    }
                    try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                }
            } catch {
                break
            }
        }
        
        await MainActor.run {
            if playingSpecies == species {
                playingSpecies = nil
            }
            speciesPlayer.stop()
        }
    }
}

// MARK: - Species Clips Player

final class SpeciesClipsPlayer: ObservableObject {
    private var player: AVAudioPlayer?
    private var timer: Timer?
    private var delegate: SpeciesClipsPlayerDelegate?
    var onFinish: (() -> Void)?
    
    @Published var isPlaying: Bool = false
    
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
        delegate = SpeciesClipsPlayerDelegate { [weak self] in
            DispatchQueue.main.async {
                self?.stop()
                onFinishCallback?()
            }
        }
        player?.delegate = delegate
    }
    
    func play() {
        player?.play()
        isPlaying = true
        startTimer()
    }
    
    func stop() {
        player?.stop()
        player?.delegate = nil
        player = nil
        delegate = nil
        timer?.invalidate()
        timer = nil
        isPlaying = false
    }
    
    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self, let player = self.player else { return }
            if !player.isPlaying && self.isPlaying {
                self.stop()
            }
        }
    }
}

class SpeciesClipsPlayerDelegate: NSObject, AVAudioPlayerDelegate {
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

// MARK: - Bird Image View with Play Button

struct BirdImageViewWithPlayButton: View {
    let species: String
    let isPlaying: Bool
    let onPlay: () -> Void
    
    @EnvironmentObject var viewModel: AppViewModel
    @State private var image: UIImage?
    
    var body: some View {
        ZStack {
            Group {
                if let image = image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: "bird.fill")
                        .font(.title2)
                        .foregroundColor(.black.opacity(0.7))
                }
            }
            .frame(width: 70, height: 70)
            .background(Color.gray.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            
            // Play button overlay - centered
            Button {
                onPlay()
            } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .offset(x: isPlaying ? 0 : 1) // Slight offset for play icon to look centered
                    .shadow(color: .black.opacity(0.4), radius: 2, x: 0, y: 1)
            }
        }
        .id(species) // Prevent view recreation when isPlaying changes
        .onAppear {
            loadImageIfNeeded()
        }
        .onChange(of: species) { oldValue, newValue in
            loadImageIfNeeded()
        }
    }
    
    private func loadImageIfNeeded() {
        // Check cache synchronously first
        if image == nil {
            // Try to get from cache immediately
            if let cachedImage = BirdImageService.shared.getCachedImageSync(for: species) {
                image = cachedImage
            } else {
                // Load asynchronously if not in cache
                Task {
                    let loadedImage = await BirdImageService.shared.fetchImage(for: species)
                    await MainActor.run {
                        if image == nil { // Only set if still nil (prevent race condition)
                            image = loadedImage
                        }
                    }
                }
            }
        }
    }
}


