import SwiftUI
import AVFoundation

struct ResultsView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @State private var selectedSpecies: SpeciesSummary?
    @State private var shareURLs: [URL] = []
    @State private var isPresentingShareSheet = false
    @State private var isExportingAll = false
    @State private var isShowingExportOptions = false

    var body: some View {
        VStack(spacing: 0) {
            header
            
            listSection
            
            Spacer()
            
            VStack(spacing: 12) {
                exportAllButton
                cancelButton
            }
            .padding(.top, 16)
        }
        .padding(.horizontal, 16)
        .padding(.top, 24)
        .padding(.bottom, 24)
        .sheet(item: $selectedSpecies) { species in
            SpeciesDetailView(species: species.species)
                .environmentObject(viewModel)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
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

    private var header: some View {
        VStack(spacing: 8) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.title2)
                    
                    Text("Here are your bird clips!")
                        .font(.title2.bold())
                        .foregroundColor(.black)
                }
                
                Spacer()
                
                Button {
                    viewModel.resetToImport()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.black)
                        .frame(width: 32, height: 32)
                        .background(Color.white)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .strokeBorder(Color.black.opacity(0.1), lineWidth: 1)
                        )
                }
            }

            if viewModel.usingMock {
                GlassBanner(text: "Using mock detections (BirdNET unavailable).")
                    .padding(.top, 8)
            }
        }
        .padding(.bottom, 16)
    }

    private var exportAllButton: some View {
        Button {
            isShowingExportOptions = true
        } label: {
            Text("Export All (\(totalClipCount))")
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .disabled(viewModel.speciesSegments.isEmpty)
        .opacity(viewModel.speciesSegments.isEmpty ? 0.5 : 1.0)
    }
    
    private var cancelButton: some View {
        Button {
            viewModel.resetToImport()
        } label: {
            Text("Cancel")
                .font(.headline)
                .foregroundColor(.gray)
        }
    }
    
    private var exportOptionsSheet: some View {
        NavigationView {
            VStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Export Mode")
                        .font(.headline)
                        .foregroundColor(.black)
                    
                    Picker("", selection: Binding(
                        get: { viewModel.exportMode },
                        set: { viewModel.exportMode = $0 }
                    )) {
                        Text("Per Species").tag(ExportMode.perSpecies)
                        Text("Per Call").tag(ExportMode.perCall)
                    }
                    .pickerStyle(.segmented)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                
                Spacer()
                
                Button {
                    isShowingExportOptions = false
                    exportAll()
                } label: {
                    Text("Export")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.black)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .navigationTitle("Export Options")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.height(200)])
    }
    
    private var totalClipCount: Int {
        viewModel.speciesSummaries.reduce(0) { $0 + $1.clipCount }
    }

    private var listSection: some View {
        Group {
            if viewModel.speciesSummaries.isEmpty {
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
                        ForEach(viewModel.speciesSummaries) { summary in
                            Button {
                                selectedSpecies = summary
                            } label: {
                                speciesRow(summary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 16)
                    .padding(.bottom, 8)
                }
            }
        }
    }

    private func speciesRow(_ summary: SpeciesSummary) -> some View {
        let (commonName, scientificName) = parseSpeciesName(summary.species)
        
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
            
            HStack {
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
                    Text("\(summary.clipCount) clip\(summary.clipCount == 1 ? "" : "s")")
                        .font(.subheadline.bold())
                        .foregroundColor(.gray)
                    
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .foregroundColor(.gray)
                }
            }
            .padding(12)
        }
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
                        sampleRate: viewModel.sampleRate
                    )
                case .perCall:
                    urls = try ExportService.exportPerCall(
                        speciesSegments: segments,
                        from: buffer,
                        sampleRate: viewModel.sampleRate
                    )
                }

                await MainActor.run {
                    shareURLs = urls
                    isPresentingShareSheet = true
                    isExportingAll = false
                }
            } catch {
                print("Export failed: \(error)")
                await MainActor.run {
                    isExportingAll = false
                }
            }
        }
    }
}


