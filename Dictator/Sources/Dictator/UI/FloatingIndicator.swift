import AppKit
import SwiftUI
import Combine

/// Floating indicator view that shows recording duration
struct FloatingIndicatorView: View {
    @ObservedObject var recordingService: RecordingService
    @State private var elapsedTime: TimeInterval = 0
    @State private var timer: Timer?
    @State private var recordingStartTime: Date?

    var body: some View {
        HStack(spacing: 0) {
            // Pulsing red dot - left aligned
            Circle()
                .fill(Color.red)
                .frame(width: 6, height: 6)
                .modifier(PulsingModifier())

            Spacer(minLength: 5)

            // Timer - right aligned, truncates from right if too long
            Text(formatTime(elapsedTime))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.white)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(width: 60)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.75))
        )
        .overlay(
            Capsule()
                .strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5)
        )
        .onAppear {
            startTimer()
        }
        .onDisappear {
            stopTimer()
        }
    }

    private func startTimer() {
        recordingStartTime = Date()
        elapsedTime = 0
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            if let start = recordingStartTime {
                elapsedTime = Date().timeIntervalSince(start)
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        let tenths = Int((time * 10).truncatingRemainder(dividingBy: 10))

        if minutes > 0 {
            return String(format: "%d:%02d.%d", minutes, seconds, tenths)
        } else {
            return String(format: "%d.%d", seconds, tenths)
        }
    }
}

/// Pulsing animation modifier for the recording dot
struct PulsingModifier: ViewModifier {
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPulsing ? 1.2 : 1.0)
            .opacity(isPulsing ? 0.7 : 1.0)
            .animation(
                Animation.easeInOut(duration: 0.8)
                    .repeatForever(autoreverses: true),
                value: isPulsing
            )
            .onAppear {
                isPulsing = true
            }
    }
}

/// Controller for the floating indicator window
@MainActor
final class FloatingIndicatorController {
    private var panel: NSPanel?
    private var hostingView: NSHostingView<FloatingIndicatorView>?
    private var recordingService: RecordingService?
    private var cancellables = Set<AnyCancellable>()

    /// Flag to track if hide animation is in progress
    private var isHideAnimationInProgress = false

    func setup(recordingService: RecordingService) {
        self.recordingService = recordingService

        // Observe recording state changes
        recordingService.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                switch state {
                case .starting, .recording:
                    // Show badge during startup (async setup) and recording
                    self?.show()
                default:
                    self?.hide()
                }
            }
            .store(in: &cancellables)
    }

    private func createPanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 30),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false

        return panel
    }

    private func show() {
        guard let recordingService = recordingService else { return }

        // If hide animation is in progress, cancel it and reuse the panel
        if isHideAnimationInProgress, let existingPanel = panel {
            print("[FloatingIndicator] Cancelling hide animation - reusing panel")
            isHideAnimationInProgress = false
            // Cancel animation by setting final value immediately
            existingPanel.animator().alphaValue = 1
            existingPanel.alphaValue = 1
            return
        }

        // If panel already exists and visible, nothing to do
        if panel != nil {
            return
        }

        let panel = createPanel()
        self.panel = panel

        let indicatorView = FloatingIndicatorView(recordingService: recordingService)
        let hostingView = NSHostingView(rootView: indicatorView)
        hostingView.frame = panel.contentView?.bounds ?? .zero
        hostingView.autoresizingMask = [.width, .height]

        panel.contentView = hostingView
        self.hostingView = hostingView

        // Size to fit content
        hostingView.layoutSubtreeIfNeeded()
        let fittingSize = hostingView.fittingSize
        panel.setContentSize(fittingSize)

        // Position above dock (centered horizontally)
        // visibleFrame excludes the dock and menu bar, so we position just above it
        if let screen = NSScreen.main {
            let visibleFrame = screen.visibleFrame
            let x = visibleFrame.midX - fittingSize.width / 2
            // Position 20px above the dock (visibleFrame.minY is where the dock ends)
            let y = visibleFrame.minY + 20
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        // Fade in
        panel.alphaValue = 0
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
    }

    private func hide() {
        guard let panel = panel else { return }

        // If already hiding, don't start another animation
        if isHideAnimationInProgress {
            return
        }

        isHideAnimationInProgress = true

        // Fade out
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self = self else { return }

            // Only complete the hide if animation wasn't cancelled
            if self.isHideAnimationInProgress {
                panel.orderOut(nil)
                self.panel = nil
                self.hostingView = nil
                self.isHideAnimationInProgress = false
            }
        })
    }
}
