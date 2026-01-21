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
