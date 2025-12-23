//
//  ContentView.swift
//  Chirper
//
//  Created by Andy Cabindol on 12/23/25.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        ZStack {
            // Subtle background
            LinearGradient(
                gradient: Gradient(colors: [
                    Color.black.opacity(0.95),
                    Color.black.opacity(0.9)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 128) {
                // Chirper "logo" – simple, sleek wordmark for now
                Text("Chirper")
                    .font(.system(size: 42, weight: .semibold, design: .rounded))
                    .kerning(1.2)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.white, Color.green.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )

                // Tagline
                Text("Isolate bird chirps from your recordings")
                    .font(.system(size: 18, weight: .regular, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundColor(Color.white.opacity(0.7))
                    .padding(.horizontal, 32)

                // Import recording call-to-action
                Button(action: {
                    // TODO: Hook up import action
                }) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(style: StrokeStyle(lineWidth: 1.4, dash: [6, 6]))
                            .foregroundColor(Color.white.opacity(0.35))

                        Text("+ Import audio recording")
                            .font(.system(size: 17, weight: .medium, design: .rounded))
                            .foregroundColor(.white)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 120)
                }
                .padding(.top, 8)
            }
            .padding(.horizontal, 24)
        }
    }
}

#Preview {
    ContentView()
}
