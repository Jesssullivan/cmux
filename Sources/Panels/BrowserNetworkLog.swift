#if DEBUG
import Foundation

/// A captured network request/response from a WKWebView navigation.
struct BrowserNetworkEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let url: String
    let method: String
    let statusCode: Int?
    let mimeType: String?
    let responseHeaders: [String: String]
    let duration: TimeInterval?
    let isMainFrame: Bool
    let panelID: UUID?
    let workspaceID: UUID?

    var statusDescription: String {
        if let code = statusCode {
            return "\(code)"
        }
        return "—"
    }

    func toJSON() -> [String: Any] {
        var dict: [String: Any] = [
            "id": id.uuidString,
            "timestamp": ISO8601DateFormatter().string(from: timestamp),
            "url": url,
            "method": method,
            "is_main_frame": isMainFrame,
        ]
        if let code = statusCode { dict["status_code"] = code }
        if let mime = mimeType { dict["mime_type"] = mime }
        if !responseHeaders.isEmpty { dict["response_headers"] = responseHeaders }
        if let dur = duration { dict["duration_ms"] = Int(dur * 1000) }
        if let pid = panelID { dict["panel_id"] = pid.uuidString }
        if let wid = workspaceID { dict["workspace_id"] = wid.uuidString }
        return dict
    }
}

/// Thread-safe ring buffer for browser network entries.
/// Shared across all BrowserPanels; entries are tagged with panelID.
final class BrowserNetworkLog: ObservableObject {
    static let shared = BrowserNetworkLog()

    private let lock = NSLock()
    private var buffer: [BrowserNetworkEntry] = []
    private let capacity = 500

    /// Published snapshot for SwiftUI observation (updated on main thread).
    @Published private(set) var entries: [BrowserNetworkEntry] = []

    private init() {}

    func append(_ entry: BrowserNetworkEntry) {
        lock.lock()
        buffer.append(entry)
        if buffer.count > capacity {
            buffer.removeFirst(buffer.count - capacity)
        }
        let snapshot = buffer
        lock.unlock()

        DispatchQueue.main.async { [weak self] in
            self?.entries = snapshot
        }
    }

    func clear() {
        lock.lock()
        buffer.removeAll()
        lock.unlock()

        DispatchQueue.main.async { [weak self] in
            self?.entries = []
        }
    }

    /// Return entries filtered by optional panel/workspace ID.
    func list(panelID: UUID? = nil, workspaceID: UUID? = nil, limit: Int = 100) -> [BrowserNetworkEntry] {
        lock.lock()
        var result = buffer
        lock.unlock()

        if let pid = panelID {
            result = result.filter { $0.panelID == pid }
        }
        if let wid = workspaceID {
            result = result.filter { $0.workspaceID == wid }
        }
        return Array(result.suffix(limit))
    }

    /// Record start of a navigation (request side). Returns a token for timing.
    func recordRequest(
        url: String,
        method: String,
        isMainFrame: Bool,
        panelID: UUID?,
        workspaceID: UUID?
    ) -> NavigationToken {
        NavigationToken(
            startTime: Date(),
            url: url,
            method: method,
            isMainFrame: isMainFrame,
            panelID: panelID,
            workspaceID: workspaceID
        )
    }

    /// Complete a navigation with response data.
    func recordResponse(
        token: NavigationToken,
        statusCode: Int?,
        mimeType: String?,
        responseHeaders: [String: String]
    ) {
        let entry = BrowserNetworkEntry(
            timestamp: token.startTime,
            url: token.url,
            method: token.method,
            statusCode: statusCode,
            mimeType: mimeType,
            responseHeaders: responseHeaders,
            duration: Date().timeIntervalSince(token.startTime),
            isMainFrame: token.isMainFrame,
            panelID: token.panelID,
            workspaceID: token.workspaceID
        )
        append(entry)
    }

    /// Record a navigation that completed without a response callback (e.g., errors).
    func recordError(token: NavigationToken) {
        let entry = BrowserNetworkEntry(
            timestamp: token.startTime,
            url: token.url,
            method: token.method,
            statusCode: nil,
            mimeType: nil,
            responseHeaders: [:],
            duration: Date().timeIntervalSince(token.startTime),
            isMainFrame: token.isMainFrame,
            panelID: token.panelID,
            workspaceID: token.workspaceID
        )
        append(entry)
    }

    struct NavigationToken {
        let startTime: Date
        let url: String
        let method: String
        let isMainFrame: Bool
        let panelID: UUID?
        let workspaceID: UUID?
    }
}
#endif
