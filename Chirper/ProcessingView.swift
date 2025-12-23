import SwiftUI

struct ProcessingView: View {
    @EnvironmentObject var viewModel: AppViewModel

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            GlassCard {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Processing Recording")
                        .font(.title2.bold())
                        .foregroundColor(.black)

                    Text(stepDescription)
                        .font(.subheadline)
                        .foregroundColor(.gray)

                    ProgressView(
                        value: max(0.0, min(1.0, viewModel.processingProgress))
                    )
                    .tint(.black)

                    if viewModel.totalWindows > 0 {
                        Text("Window \(viewModel.currentWindowIndex) / \(viewModel.totalWindows)")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }

                    GlassButton(title: "Cancel", systemImage: "xmark.circle") {
                        viewModel.cancelProcessing()
                    }
                }
                .padding(24)
            }
            .padding(.horizontal, 24)

            Spacer()
        }
    }

    private var stepDescription: String {
        let msg = viewModel.processingMessage
        return msg.isEmpty ? "Working…" : msg
    }
}


