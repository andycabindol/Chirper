import SwiftUI
import AVFoundation
import Combine

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

    @StateObject private var player = SpeciesAudioPlayer()
    @State private var isLoading = true
    @State private var shareURL: URL?
    @State private var isPresentingShare = false

    var body: some View {
        VStack(spacing: 20) {
            Capsule()
                .fill(Color.black.opacity(0.1))
                .frame(width: 40, height: 4)
                .padding(.top, 8)

            Text(species)
                .font(.title2.bold())
                .foregroundColor(.black)

            if isLoading {
                ProgressView("Preparing audio…")
                    .tint(.black)
            } else {
                playbackControls
            }

            Spacer()
        }
        .padding(20)
        .background(.ultraThinMaterial)
        .task {
            await prepareAudio()
        }
        .sheet(isPresented: $isPresentingShare, onDismiss: {
            if let url = shareURL {
                ExportService.cleanupTempFiles(urls: [url])
            }
            shareURL = nil
        }) {
            if let url = shareURL {
                ShareSheet(activityItems: [url])
            }
        }
    }

    private var playbackControls: some View {
        VStack(spacing: 16) {
            HStack {
                Button {
                    player.playPause()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.largeTitle)
                        .foregroundColor(.black)
                        .padding(24)
                        .background(.thinMaterial)
                        .clipShape(Circle())
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(String(format: "%.1fs / %.1fs", player.currentTime, max(0.1, player.duration)))
                        .font(.caption)
                        .foregroundColor(.gray)

                    ProgressView(
                        value: player.duration > 0 ? player.currentTime / player.duration : 0
                    )
                    .tint(.black)
                }
            }

            GlassButton(title: "Export WAV", systemImage: "square.and.arrow.up") {
                exportSpecies()
            }
        }
    }

    private func prepareAudio() async {
        guard
            let buffer = viewModel.audioBuffer,
            let segments = viewModel.speciesSegments[species]
        else {
            isLoading = false
            return
        }

        do {
            let concat = try AudioProcessingService.spliceSegments(
                segments,
                from: buffer,
                sampleRate: viewModel.sampleRate
            )
            try player.load(buffer: concat, sampleRate: viewModel.sampleRate)
        } catch {
            print("Failed to prepare species audio: \(error)")
        }
        isLoading = false
    }

    private func exportSpecies() {
        guard
            let buffer = viewModel.audioBuffer,
            let segments = viewModel.speciesSegments[species]
        else { return }

        Task {
            do {
                let concatenated = try AudioProcessingService.spliceSegments(
                    segments,
                    from: buffer,
                    sampleRate: viewModel.sampleRate
                )

                let url = try ExportService.writeTempWav(
                    buffer: concatenated,
                    sampleRate: viewModel.sampleRate,
                    fileName: "\(species.sanitizedFilename()).wav"
                )

                await MainActor.run {
                    self.shareURL = url
                    self.isPresentingShare = true
                }
            } catch {
                print("Species export failed: \(error)")
            }
        }
    }
}


