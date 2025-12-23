import SwiftUI

struct ProcessingView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @State private var animatedProgress: Double = 0.0
    @State private var currentMessageIndex: Int = 0
    @State private var messageTimer: Timer?
    @State private var progressTimer: Timer?
    
    private let cyclingMessages = [
        "Preparing audio",
        "Identifying birds",
        "Splicing chirps"
    ]

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 24) {
                Text("Isolating your chirps....")
                    .font(.title2.bold())
                    .foregroundColor(.black)

                Text(cyclingMessages[currentMessageIndex])
                    .font(.subheadline)
                    .foregroundColor(.gray)

                VStack(spacing: 8) {
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Rectangle()
                                .fill(Color.gray.opacity(0.2))
                            
                            Rectangle()
                                .fill(Color.black)
                                .frame(width: max(0, min(geometry.size.width, geometry.size.width * animatedProgress)))
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    .frame(height: 8)
                    
                    Text("\(Int(animatedProgress * 100))%")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)

            Spacer()

            Button {
                viewModel.cancelProcessing()
            } label: {
                Text("Cancel")
                    .font(.body)
                    .foregroundColor(.gray)
            }
            .padding(.bottom, 24)
        }
        .padding(.horizontal, 24)
        .onAppear {
            startAnimations()
        }
        .onDisappear {
            stopAnimations()
        }
        .onChange(of: viewModel.processingProgress) { oldValue, newValue in
            // When processing completes, animate from 80% to 100%
            if newValue >= 1.0 && animatedProgress < 1.0 {
                withAnimation(.linear(duration: 0.5)) {
                    animatedProgress = 1.0
                }
            }
        }
    }
    
    private func startAnimations() {
        // Start cycling messages every 2 seconds
        messageTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            Task { @MainActor in
                withAnimation(.easeInOut(duration: 0.3)) {
                    currentMessageIndex = (currentMessageIndex + 1) % cyclingMessages.count
                }
            }
        }
        
        // Reset progress to 0 and animate from 0% to 80% over 2 seconds
        animatedProgress = 0.0
        DispatchQueue.main.async {
            withAnimation(.linear(duration: 2.0)) {
                self.animatedProgress = 0.8
            }
        }
    }
    
    private func stopAnimations() {
        messageTimer?.invalidate()
        messageTimer = nil
        progressTimer?.invalidate()
        progressTimer = nil
    }
}


