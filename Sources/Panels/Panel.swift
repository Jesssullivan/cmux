import Foundation
import Combine
import AppKit
import SwiftUI

/// Type of panel content
public enum PanelType: String, Codable, Sendable {
    case terminal
    case browser
    case markdown
}

public enum TerminalPanelFocusIntent: Equatable {
    case surface
    case findField
}

public enum BrowserPanelFocusIntent: Equatable {
    case webView
    case addressBar
    case findField
}

public enum PanelFocusIntent: Equatable {
    case panel
    case terminal(TerminalPanelFocusIntent)
    case browser(BrowserPanelFocusIntent)
}

public enum WorkspaceAttentionFlashReason: String, Equatable, Sendable {
    case navigation
    case notificationArrival
    case notificationDismiss
    case manualUnreadDismiss
    case debug
}

enum WorkspaceAttentionFlashAccent: Equatable, Sendable {
    case notificationBlue
    case navigationTeal

    var strokeColor: NSColor {
        switch self {
        case .notificationBlue:
            return .systemBlue
        case .navigationTeal:
            return .systemTeal
        }
    }
}

struct WorkspaceAttentionFlashPresentation: Equatable, Sendable {
    let accent: WorkspaceAttentionFlashAccent
    let glowOpacity: Double
    let glowRadius: CGFloat
}

struct WorkspaceAttentionPersistentState: Equatable, Sendable {
    var unreadPanelIDs: Set<UUID> = []
    var focusedReadPanelID: UUID?
    var manualUnreadPanelIDs: Set<UUID> = []

    var indicatorPanelIDs: Set<UUID> {
        var ids = unreadPanelIDs.union(manualUnreadPanelIDs)
        if let focusedReadPanelID {
            ids.insert(focusedReadPanelID)
        }
        return ids
    }

    func hasCompetingIndicator(for panelID: UUID) -> Bool {
        indicatorPanelIDs.contains(where: { $0 != panelID })
    }
}

struct WorkspaceAttentionFlashDecision: Equatable, Sendable {
    let panelID: UUID
    let reason: WorkspaceAttentionFlashReason
    let isAllowed: Bool
}

enum WorkspaceAttentionCoordinator {
    static func flashStyle(for reason: WorkspaceAttentionFlashReason) -> WorkspaceAttentionFlashPresentation {
        switch reason {
        case .navigation:
            return WorkspaceAttentionFlashPresentation(
                accent: .navigationTeal,
                glowOpacity: 0.14,
                glowRadius: 3
            )
        case .notificationArrival, .notificationDismiss, .manualUnreadDismiss, .debug:
            return WorkspaceAttentionFlashPresentation(
                accent: .notificationBlue,
                glowOpacity: 0.6,
                glowRadius: 6
            )
        }
    }

    static func decideFlash(
        targetPanelID: UUID,
        reason: WorkspaceAttentionFlashReason,
        persistentState: WorkspaceAttentionPersistentState
    ) -> WorkspaceAttentionFlashDecision {
        let isAllowed: Bool
        switch reason {
        case .navigation:
            isAllowed = !persistentState.hasCompetingIndicator(for: targetPanelID)
        case .notificationArrival, .notificationDismiss, .manualUnreadDismiss, .debug:
            isAllowed = true
        }

        return WorkspaceAttentionFlashDecision(
            panelID: targetPanelID,
            reason: reason,
            isAllowed: isAllowed
        )
    }
}

enum FocusFlashCurve: Equatable {
    case easeIn
    case easeOut
}

enum PanelOverlayRingMetrics {
    static let inset: CGFloat = 2
    static let cornerRadius: CGFloat = 6
    static let lineWidth: CGFloat = 2.5

    static func pathRect(in bounds: CGRect) -> CGRect {
        bounds.insetBy(dx: inset, dy: inset)
    }
}

#if DEBUG
func cmuxFlashDebugID(_ id: UUID?) -> String {
    guard let id else { return "nil" }
    return String(id.uuidString.prefix(6))
}

func cmuxFlashDebugRect(_ rect: CGRect?) -> String {
    guard let rect else { return "nil" }
    return String(
        format: "%.1f,%.1f %.1fx%.1f",
        rect.origin.x,
        rect.origin.y,
        rect.size.width,
        rect.size.height
    )
}

func cmuxFlashDebugBool(_ value: Bool) -> Int {
    value ? 1 : 0
}
#endif

struct FocusFlashSegment: Equatable {
    let delay: TimeInterval
    let duration: TimeInterval
    let targetOpacity: Double
    let curve: FocusFlashCurve
}

enum FocusFlashPattern {
    static let values: [Double] = [0, 1, 0, 1, 0]
    static let keyTimes: [Double] = [0, 0.25, 0.5, 0.75, 1]
    static let duration: TimeInterval = 0.9
    static let curves: [FocusFlashCurve] = [.easeOut, .easeIn, .easeOut, .easeIn]
    static let ringInset: Double = Double(PanelOverlayRingMetrics.inset)
    static let ringCornerRadius: Double = Double(PanelOverlayRingMetrics.cornerRadius)

    static var segments: [FocusFlashSegment] {
        let stepCount = min(curves.count, values.count - 1, keyTimes.count - 1)
        return (0..<stepCount).map { index in
            let startTime = keyTimes[index]
            let endTime = keyTimes[index + 1]
            return FocusFlashSegment(
                delay: startTime * duration,
                duration: (endTime - startTime) * duration,
                targetOpacity: values[index + 1],
                curve: curves[index]
            )
        }
    }

    static func opacity(at elapsed: TimeInterval) -> Double {
        guard elapsed >= 0, elapsed <= duration else { return 0 }

        for index in 0..<segments.count {
            let startTime = keyTimes[index] * duration
            let endTime = keyTimes[index + 1] * duration
            if elapsed > endTime {
                continue
            }

            let segmentDuration = max(endTime - startTime, 0.0001)
            let rawProgress = max(0, min(1, (elapsed - startTime) / segmentDuration))
            let curvedProgress = interpolatedProgress(rawProgress, curve: curves[index])
            let startOpacity = values[index]
            let endOpacity = values[index + 1]
            return startOpacity + ((endOpacity - startOpacity) * curvedProgress)
        }

        return values.last ?? 0
    }

    private static func interpolatedProgress(_ progress: Double, curve: FocusFlashCurve) -> Double {
        switch curve {
        case .easeIn:
            return progress * progress
        case .easeOut:
            let inverse = 1 - progress
            return 1 - (inverse * inverse)
        }
    }
}

// MARK: - Shared Panel Flash Overlay (CAKeyframeAnimation)

/// AppKit view that renders a ring flash using CAKeyframeAnimation.
/// Used by BrowserPanelView and MarkdownPanelView via PanelFlashOverlayRepresentable
/// to avoid SwiftUI animation coalescing that causes only one flash instead of two.
final class PanelFlashOverlayNSView: NSView {
    private let ringLayer = CAShapeLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.masksToBounds = false
        ringLayer.fillColor = NSColor.clear.cgColor
        ringLayer.lineWidth = PanelOverlayRingMetrics.lineWidth
        ringLayer.lineJoin = .round
        ringLayer.lineCap = .round
        ringLayer.opacity = 0
        layer?.addSublayer(ringLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        ringLayer.frame = bounds
        updatePath()
    }

    private func updatePath() {
        let rect = PanelOverlayRingMetrics.pathRect(in: bounds)
        guard rect.width > 0, rect.height > 0 else { return }
        ringLayer.path = CGPath(
            roundedRect: rect,
            cornerWidth: PanelOverlayRingMetrics.cornerRadius,
            cornerHeight: PanelOverlayRingMetrics.cornerRadius,
            transform: nil
        )
    }

    func triggerFlash(reason: WorkspaceAttentionFlashReason = .navigation) {
        let style = WorkspaceAttentionCoordinator.flashStyle(for: reason)
        let strokeColor = style.accent.strokeColor.cgColor

        ringLayer.strokeColor = strokeColor
        ringLayer.shadowColor = strokeColor
        ringLayer.shadowOpacity = Float(style.glowOpacity)
        ringLayer.shadowRadius = style.glowRadius
        ringLayer.shadowOffset = .zero

        ringLayer.removeAllAnimations()
        ringLayer.opacity = 0

        let animation = CAKeyframeAnimation(keyPath: "opacity")
        animation.values = FocusFlashPattern.values.map { NSNumber(value: $0) }
        animation.keyTimes = FocusFlashPattern.keyTimes.map { NSNumber(value: $0) }
        animation.duration = FocusFlashPattern.duration
        animation.timingFunctions = FocusFlashPattern.curves.map { curve in
            switch curve {
            case .easeIn:
                return CAMediaTimingFunction(name: .easeIn)
            case .easeOut:
                return CAMediaTimingFunction(name: .easeOut)
            }
        }
        ringLayer.add(animation, forKey: "cmux.panelFlash")
    }
}

/// Wraps a pre-existing PanelFlashOverlayNSView for embedding in SwiftUI.
struct PanelFlashOverlayRepresentable: NSViewRepresentable {
    let nsView: PanelFlashOverlayNSView
    func makeNSView(context: Context) -> PanelFlashOverlayNSView { nsView }
    func updateNSView(_ nsView: PanelFlashOverlayNSView, context: Context) {}
}

/// Protocol for all panel types (terminal, browser, etc.)
@MainActor
public protocol Panel: AnyObject, Identifiable, ObservableObject where ID == UUID {
    /// Unique identifier for this panel
    var id: UUID { get }

    /// The type of panel
    var panelType: PanelType { get }

    /// Display title shown in tab bar
    var displayTitle: String { get }

    /// Optional SF Symbol icon name for the tab
    var displayIcon: String? { get }

    /// Whether the panel has unsaved changes
    var isDirty: Bool { get }

    /// Close the panel and clean up resources
    func close()

    /// Focus the panel for input
    func focus()

    /// Unfocus the panel
    func unfocus()

    /// Trigger a focus flash animation for this panel.
    func triggerFlash(reason: WorkspaceAttentionFlashReason)

    /// Capture the panel-local focus target that should be restored later.
    func captureFocusIntent(in window: NSWindow?) -> PanelFocusIntent

    /// Return the best focus target to restore when this panel becomes active again.
    func preferredFocusIntentForActivation() -> PanelFocusIntent

    /// Prime panel-local focus state before activation side effects run.
    func prepareFocusIntentForActivation(_ intent: PanelFocusIntent)

    /// Restore a previously captured focus target.
    @discardableResult
    func restoreFocusIntent(_ intent: PanelFocusIntent) -> Bool

    /// Return the semantic focus target currently owned by this panel, if any.
    func ownedFocusIntent(for responder: NSResponder, in window: NSWindow) -> PanelFocusIntent?

    /// Explicitly yield a previously owned focus target before another panel restores focus.
    @discardableResult
    func yieldFocusIntent(_ intent: PanelFocusIntent, in window: NSWindow) -> Bool
}

/// Extension providing default implementations
extension Panel {
    public var displayIcon: String? { nil }
    public var isDirty: Bool { false }

    func captureFocusIntent(in window: NSWindow?) -> PanelFocusIntent {
        _ = window
        return preferredFocusIntentForActivation()
    }

    func preferredFocusIntentForActivation() -> PanelFocusIntent {
        .panel
    }

    func prepareFocusIntentForActivation(_ intent: PanelFocusIntent) {
        _ = intent
    }

    @discardableResult
    func restoreFocusIntent(_ intent: PanelFocusIntent) -> Bool {
        guard intent == .panel else { return false }
        focus()
        return true
    }

    func ownedFocusIntent(for responder: NSResponder, in window: NSWindow) -> PanelFocusIntent? {
        _ = responder
        _ = window
        return nil
    }

    @discardableResult
    func yieldFocusIntent(_ intent: PanelFocusIntent, in window: NSWindow) -> Bool {
        _ = intent
        _ = window
        return false
    }

    func triggerFlash() {
        triggerFlash(reason: .navigation)
    }
}
