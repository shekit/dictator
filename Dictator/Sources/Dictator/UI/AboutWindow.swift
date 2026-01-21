import SwiftUI

/// About window view showing app information.
struct AboutWindow: View {
    // MARK: - Properties

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 20) {
            // App Icon (using SF Symbol as placeholder)
            Image(systemName: "mic.fill")
                .font(.system(size: 80))
                .foregroundColor(.blue)
                .padding(.top, 30)

            // App Name
            Text("Dictator")
                .font(.system(size: 32, weight: .bold))

            // Version Info
            VStack(spacing: 4) {
                Text("Version \(appVersion) (Build \(buildNumber))")
                    .font(.body)
                    .foregroundColor(.secondary)
            }

            // Description
            Text("Voice-to-text dictation with LLM cleanup")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Divider()
                .padding(.horizontal, 40)

            // Technology Stack
            VStack(spacing: 8) {
                Text("Powered by")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "cpu")
                            .foregroundColor(.blue)
                        Text("FluidAudio (Parakeet STT)")
                    }
                    HStack {
                        Image(systemName: "cloud")
                            .foregroundColor(.green)
                        Text("OpenRouter API (Cloud LLM)")
                    }
                    HStack {
                        Image(systemName: "server.rack")
                            .foregroundColor(.orange)
                        Text("Ollama (Local LLM)")
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }

            Divider()
                .padding(.horizontal, 40)

            // Links
            VStack(spacing: 8) {
                Button(action: {
                    if let url = URL(string: "https://github.com/anthropics/dictator") {
                        NSWorkspace.shared.open(url)
                    }
                }) {
                    HStack {
                        Image(systemName: "link")
                        Text("GitHub Repository")
                    }
                }
                .buttonStyle(.link)

                Button(action: {
                    if let url = URL(string: "https://github.com/FluidInference/FluidAudio") {
                        NSWorkspace.shared.open(url)
                    }
                }) {
                    HStack {
                        Image(systemName: "waveform")
                        Text("FluidAudio Project")
                    }
                }
                .buttonStyle(.link)
            }

            Spacer()

            // Copyright
            Text("© 2026 Dictator Project")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.bottom, 20)
        }
        .frame(width: 400, height: 500)
    }
}

// MARK: - Preview

#Preview {
    AboutWindow()
}
