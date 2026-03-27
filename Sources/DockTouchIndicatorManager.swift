import AppKit
import SwiftUI

/// Manages the dock tile touch indicator for FIDO2/WebAuthn operations.
/// Shows a pulsing indicator on the dock icon when the security key is
/// waiting for user touch (CTAPHID keepalive status = 2 "upneeded").
///
/// Thread safety: all methods must be called on the main thread.
@MainActor
final class DockTouchIndicatorManager {
    static let shared = DockTouchIndicatorManager()

    private var pulseTimer: Timer?
    private var isActive = false

    private init() {}

    /// Start showing the touch indicator on the dock tile.
    /// Also bounces the dock icon to attract attention.
    func start() {
        guard !isActive else { return }
        isActive = true

        #if DEBUG
        dlog("dock.touch.start")
        #endif

        // Set animated dock view
        let view = NSHostingView(rootView: DockTouchIndicatorView())
        view.frame = NSRect(x: 0, y: 0, width: 128, height: 128)
        NSApp.dockTile.contentView = view

        // Start refresh timer for animation
        pulseTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard self?.isActive == true else { return }
                NSApp.dockTile.display()
            }
        }

        NSApp.dockTile.display()

        // Bounce dock icon
        NSApp.requestUserAttention(.informationalRequest)
    }

    /// Stop the touch indicator and restore normal dock tile.
    func stop() {
        guard isActive else { return }
        isActive = false

        #if DEBUG
        dlog("dock.touch.stop")
        #endif

        pulseTimer?.invalidate()
        pulseTimer = nil
        NSApp.dockTile.contentView = nil
        NSApp.dockTile.display()
    }
}

/// Pulsing indicator view rendered on the dock tile during FIDO2 touch wait.
private struct DockTouchIndicatorView: View {
    @State private var isPulsing = false

    var body: some View {
        ZStack {
            // App icon background
            if let appIcon = NSApplication.shared.applicationIconImage {
                Image(nsImage: appIcon)
                    .resizable()
                    .scaledToFit()
            }

            // Pulsing touch indicator (top-right corner)
            VStack {
                HStack {
                    Spacer()
                    ZStack {
                        Circle()
                            .fill(Color.blue)
                            .opacity(isPulsing ? 0.3 : 0.85)

                        Circle()
                            .strokeBorder(Color.white, lineWidth: 2)
                            .opacity(isPulsing ? 0.2 : 0.6)
                            .scaleEffect(isPulsing ? 1.3 : 1.0)

                        Image(systemName: "key.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    .frame(width: 36, height: 36)
                }
                Spacer()
            }
            .padding(8)
        }
        .frame(width: 128, height: 128)
        .onAppear {
            withAnimation(
                .easeInOut(duration: 0.6)
                    .repeatForever(autoreverses: true)
            ) {
                isPulsing = true
            }
        }
    }
}
