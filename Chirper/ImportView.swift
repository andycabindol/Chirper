import SwiftUI
import UniformTypeIdentifiers

struct ImportView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @State private var showingFileImporter = false

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // Logo + tagline
            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "bird.fill")
                        .font(.system(size: 30))
                        .foregroundColor(.black)

                    Text("Chirper")
                        .font(.system(size: 42, weight: .semibold, design: .rounded))
                        .kerning(1.2)
                        .foregroundColor(.black)
                }

                Text("Isolate bird chirps from your recordings")
                    .font(.system(size: 18, weight: .regular, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundColor(Color.gray)
                    .padding(.horizontal, 32)
            }

            // Dotted import box
            Button {
                showingFileImporter = true
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(
                            style: StrokeStyle(lineWidth: 1.4, dash: [6, 6])
                        )
                        .foregroundColor(Color.gray.opacity(0.5))

                    Text("+ Import audio recording")
                        .font(.system(size: 17, weight: .medium, design: .rounded))
                        .foregroundColor(.black)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 120)
            }
            .padding(.horizontal, 24)

            Spacer()
        }
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [
                .audio,
                .mpeg4Audio,
                .mp3,
                .wav,
                .aiff,
                .midi,
                UTType(filenameExtension: "m4a")!,
                UTType(filenameExtension: "aac")!,
                UTType(filenameExtension: "caf")!
            ],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                viewModel.startProcessing(url: url)
            case .failure(let error):
                print("File import failed: \(error)")
            }
        }
    }
}


