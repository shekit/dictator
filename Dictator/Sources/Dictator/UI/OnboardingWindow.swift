import SwiftUI
import AVFoundation

/// Onboarding window for first-time users.
struct OnboardingWindow: View {
    @State private var currentStep: Int
    @State private var apiKey: String = ""
    @Environment(\.dismiss) private var dismiss
    let onComplete: () -> Void

    init(onComplete: @escaping () -> Void) {
        self.onComplete = onComplete
        // Resume from saved step or start at 0
        let savedStep = UserDefaults.standard.integer(forKey: "currentOnboardingStep")
        _currentStep = State(initialValue: savedStep)
    }

    private let steps = [
        OnboardingStep(
            icon: "waveform",
            title: "Welcome to Dictator",
            description: "Voice-to-text dictation with AI-powered cleanup.\n\nHold fn key, speak, release, and cleaned text appears at your cursor.",
            actionTitle: "Get Started"
        ),
        OnboardingStep(
            icon: "hand.point.up.left",
            title: "Accessibility Permission",
            description: "Dictator needs Accessibility permission to inject text at your cursor.\n\nClick 'Open Settings' and enable Dictator in Privacy & Security > Accessibility.",
            actionTitle: "Open Settings",
            action: .requestAccessibility
        ),
        OnboardingStep(
            icon: "mic.fill",
            title: "Microphone Permission",
            description: "Dictator needs access to your microphone to capture your voice.\n\nClick 'Open Settings' to grant permission in System Settings.\n\nNote: The app may restart after granting permission.",
            actionTitle: "Open Settings",
            action: .requestMicrophone
        ),
        OnboardingStep(
            icon: "key.fill",
            title: "API Key (Optional)",
            description: "",
            actionTitle: "Continue",
            action: .apiKeyInput
        ),
        OnboardingStep(
            icon: "checkmark.circle.fill",
            title: "You're All Set!",
            description: "Dictator is ready to use.\n\nHold fn key to start recording.\n\nAccess settings anytime from the menu bar icon.",
            actionTitle: "Finish"
        )
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Step Content
            VStack(spacing: 20) {
                // Icon
                Image(systemName: steps[currentStep].icon)
                    .font(.system(size: 60))
                    .foregroundColor(.blue)
                    .padding(.top, 30)

                // Title
                Text(steps[currentStep].title)
                    .font(.system(size: 26, weight: .bold))

                // Description (only if not empty)
                if !steps[currentStep].description.isEmpty {
                    Text(steps[currentStep].description)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 50)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // API Key Input (only on API key step)
                if steps[currentStep].action == .apiKeyInput {
                    VStack(spacing: 8) {
                        SecureField("Enter your OpenRouter API key (or leave blank)", text: $apiKey)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 400)

                        Text("Example: sk-or-v1-...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 10)
                }

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Navigation
            VStack(spacing: 16) {
                Divider()

                HStack {
                    // Page Indicator
                    HStack(spacing: 8) {
                        ForEach(0..<steps.count, id: \.self) { index in
                            Circle()
                                .fill(index == currentStep ? Color.blue : Color.gray.opacity(0.3))
                                .frame(width: 8, height: 8)
                        }
                    }

                    Spacer()

                    // Navigation Buttons
                    if currentStep > 0 {
                        Button("Back") {
                            withAnimation {
                                currentStep -= 1
                            }
                        }
                        .buttonStyle(.bordered)
                    }

                    // Skip button for API key step
                    if steps[currentStep].action == .apiKeyInput {
                        Button("Skip") {
                            advance()
                        }
                        .buttonStyle(.bordered)
                    }

                    Button(steps[currentStep].actionTitle) {
                        handleAction()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            }
        }
        .frame(width: 600, height: 450)
    }

    private func handleAction() {
        switch steps[currentStep].action {
        case .requestMicrophone:
            requestMicrophonePermission()
            advance()
        case .requestAccessibility:
            openAccessibilitySettings()
            advance()
        case .apiKeyInput:
            saveAPIKey()
            advance()
        case .none:
            advance()
        }
    }

    private func advance() {
        if currentStep < steps.count - 1 {
            withAnimation {
                currentStep += 1
                // Save progress in case app restarts
                UserDefaults.standard.set(currentStep, forKey: "currentOnboardingStep")
            }
        } else {
            // Onboarding complete - clear progress tracking
            UserDefaults.standard.removeObject(forKey: "currentOnboardingStep")
            onComplete()
        }
    }

    private func requestMicrophonePermission() {
        // First trigger the permission request so app appears in System Settings
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            print("[Onboarding] Microphone access \(granted ? "granted" : "denied")")

            // Then open System Settings so user can see/change the permission
            DispatchQueue.main.async {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }

    private func openAccessibilitySettings() {
        // First trigger an accessibility check so app appears in System Settings
        // This call registers the app in the Accessibility list
        let _ = AXIsProcessTrusted()
        print("[Onboarding] Accessibility check triggered")

        // Then open System Settings to Privacy & Security > Accessibility
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private func saveAPIKey() {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            UserDefaults.standard.set(trimmed, forKey: "openRouterAPIKey")
            print("[Onboarding] API key saved")
        } else {
            print("[Onboarding] No API key entered, skipped")
        }
    }
}

// MARK: - Supporting Types

struct OnboardingStep {
    let icon: String
    let title: String
    let description: String
    let actionTitle: String
    let action: Action?

    init(icon: String, title: String, description: String, actionTitle: String, action: Action? = nil) {
        self.icon = icon
        self.title = title
        self.description = description
        self.actionTitle = actionTitle
        self.action = action
    }

    enum Action: Equatable {
        case requestMicrophone
        case requestAccessibility
        case apiKeyInput
    }
}

// MARK: - Preview

#Preview {
    OnboardingWindow {
        print("Onboarding complete")
    }
}
