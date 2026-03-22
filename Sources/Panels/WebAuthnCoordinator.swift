import CryptoKit
import libctap2
import WebKit

/// Error type for CTAP2 operations.
private struct CTAP2Error: Error, LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Coordinates WebAuthn/FIDO2 ceremonies between the JS bridge and
/// hardware security keys (via libctap2 over USB HID) and platform
/// authenticators (Touch ID / passkeys via AuthenticationServices).
///
/// One coordinator per WKWebView. Handles both registration (create)
/// and assertion (get) flows.
@MainActor
final class WebAuthnCoordinator: NSObject {

    // MARK: - State

    private enum State {
        case idle
        case authenticating(replyHandler: @MainActor (Any?, String?) -> Void)
    }

    private var state: State = .idle
    private weak var webView: WKWebView?

    /// Queue for blocking CTAP2 USB HID operations.
    private static let ctap2Queue = DispatchQueue(label: "com.cmuxterm.ctap2", qos: .userInitiated)

    init(webView: WKWebView) {
        self.webView = webView
        super.init()
    }

    // MARK: - Bridge Installation

    /// Registers the WebAuthn bootstrap script and message handler on the given
    /// user content controller. Call once during web view configuration, before
    /// the first navigation.
    func install(on controller: WKUserContentController) {
        // Main frame only — WebAuthn is initiated by the top-level page, and injecting
        // navigator.credentials overrides into cross-origin iframes triggers CAPTCHA
        // providers' environment tampering detection.
        controller.addUserScript(
            WKUserScript(
                source: WebAuthnBridgeJavaScript.bootstrapScriptSource,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )
        controller.addScriptMessageHandler(
            self,
            contentWorld: .page,
            name: WebAuthnBridgeJavaScript.messageHandlerName
        )
        #if DEBUG
        dlog("webauthn.install handler=\(WebAuthnBridgeJavaScript.messageHandlerName) contentWorld=page forMainFrameOnly=true")
        #endif
    }

    // MARK: - Cleanup

    /// Cancels any in-flight WebAuthn ceremony and replies with an error.
    func cancelPendingCeremony() {
        if case .authenticating(let replyHandler) = state {
            replyHandler(["error": "The operation was cancelled.", "name": "AbortError"], nil)
        }
        state = .idle
    }

    // MARK: - Origin Validation

    private func validateOrigin(_ claimed: String) -> Bool {
        guard let webViewURL = webView?.url else {
            #if DEBUG
            dlog("webauthn.validateOrigin FAIL webView.url=nil claimed=\(claimed)")
            #endif
            return false
        }
        let webViewOrigin = "\(webViewURL.scheme ?? "https")://\(webViewURL.host ?? "")"
            + (webViewURL.port.map { ":\($0)" } ?? "")
        let match = claimed == webViewOrigin
        #if DEBUG
        dlog("webauthn.validateOrigin claimed=\(claimed) computed=\(webViewOrigin) match=\(match)")
        #endif
        return match
    }

    // MARK: - Registration (create)

    private func handleCreate(
        options: [String: Any],
        origin: String,
        replyHandler: @escaping @MainActor (Any?, String?) -> Void
    ) {
        guard let challengeB64 = options["challenge"] as? String,
              let challengeData = Data(base64urlEncoded: challengeB64)
        else {
            replyHandler(["error": "Missing or invalid challenge.", "name": "TypeError"], nil)
            state = .idle
            return
        }

        let rpDict = options["rp"] as? [String: Any]
        let rpID = rpDict?["id"] as? String ?? webView?.url?.host ?? ""
        let rpName = rpDict?["name"] as? String ?? rpID

        let userDict = options["user"] as? [String: Any]
        let userIDData: Data
        if let userIDB64 = userDict?["id"] as? String,
           let decoded = Data(base64urlEncoded: userIDB64) {
            userIDData = decoded
        } else {
            userIDData = Data(UUID().uuidString.utf8)
        }
        let userName = userDict?["name"] as? String ?? ""
        let displayName = userDict?["displayName"] as? String ?? userName

        // Parse algorithm IDs from pubKeyCredParams (default to ES256 = -7)
        var algIDs: [Int32] = [-7]
        if let credParams = options["pubKeyCredParams"] as? [[String: Any]] {
            let parsed = credParams.compactMap { $0["alg"] as? Int }.map { Int32($0) }
            if !parsed.isEmpty { algIDs = parsed }
        }

        let residentKey: Bool
        if let authSel = options["authenticatorSelection"] as? [String: Any],
           let rk = authSel["residentKey"] as? String {
            residentKey = (rk == "required")
        } else {
            residentKey = false
        }

        #if DEBUG
        dlog("webauthn.create rpID=\(rpID) user=\(userName) challengeLen=\(challengeData.count)")
        #endif

        state = .authenticating(replyHandler: replyHandler)

        // Build clientDataJSON and hash it with SHA-256
        let clientDataJSON = Self.buildClientDataJSON(type: "webauthn.create", challenge: challengeB64, origin: origin)
        let clientDataHash = SHA256.hash(data: clientDataJSON)
        let hashBytes = Array(clientDataHash)

        Self.ctap2Queue.async {
            let result = self.performCTAP2MakeCredential(
                clientDataHash: hashBytes,
                rpID: rpID,
                rpName: rpName,
                userID: userIDData,
                userName: userName,
                displayName: displayName,
                algIDs: algIDs,
                residentKey: residentKey
            )
            DispatchQueue.main.async {
                self.state = .idle
                switch result {
                case .success(let response):
                    replyHandler(response, nil)
                case .failure(let error):
                    #if DEBUG
                    dlog("webauthn.ctap2.create error=\(error)")
                    #endif
                    replyHandler(["error": error.message, "name": "NotAllowedError"], nil)
                }
            }
        }
    }

    // MARK: - Assertion (get)

    private func handleGet(
        options: [String: Any],
        origin: String,
        replyHandler: @escaping @MainActor (Any?, String?) -> Void
    ) {
        guard let challengeB64 = options["challenge"] as? String,
              let challengeData = Data(base64urlEncoded: challengeB64)
        else {
            replyHandler(["error": "Missing or invalid challenge.", "name": "TypeError"], nil)
            state = .idle
            return
        }

        let rpID = options["rpId"] as? String ?? webView?.url?.host ?? ""

        // Parse allowCredentials list
        var allowListIDs: [Data] = []
        if let allowCredentials = options["allowCredentials"] as? [[String: Any]] {
            for cred in allowCredentials {
                if let idB64 = cred["id"] as? String,
                   let idData = Data(base64urlEncoded: idB64) {
                    allowListIDs.append(idData)
                }
            }
        }

        #if DEBUG
        dlog("webauthn.get rpID=\(rpID) challengeLen=\(challengeData.count) allowCredentials=\(allowListIDs.count)")
        #endif

        state = .authenticating(replyHandler: replyHandler)

        // Build clientDataJSON and hash it with SHA-256
        let clientDataJSON = Self.buildClientDataJSON(type: "webauthn.get", challenge: challengeB64, origin: origin)
        let clientDataHash = SHA256.hash(data: clientDataJSON)
        let hashBytes = Array(clientDataHash)

        Self.ctap2Queue.async {
            let result = self.performCTAP2GetAssertion(
                clientDataHash: hashBytes,
                rpID: rpID,
                allowListIDs: allowListIDs
            )
            DispatchQueue.main.async {
                self.state = .idle
                switch result {
                case .success(let response):
                    replyHandler(response, nil)
                case .failure(let error):
                    #if DEBUG
                    dlog("webauthn.ctap2.get error=\(error)")
                    #endif
                    replyHandler(["error": error.message, "name": "NotAllowedError"], nil)
                }
            }
        }
    }

    // MARK: - CTAP2 C Library Calls

    private nonisolated func performCTAP2MakeCredential(
        clientDataHash: [UInt8],
        rpID: String,
        rpName: String,
        userID: Data,
        userName: String,
        displayName: String,
        algIDs: [Int32],
        residentKey: Bool
    ) -> Result<[String: Any], CTAP2Error> {
        var resultBuf = [UInt8](repeating: 0, count: 4096)

        let written = clientDataHash.withUnsafeBufferPointer { hashPtr in
            userID.withUnsafeBytes { userIDPtr in
                algIDs.withUnsafeBufferPointer { algPtr in
                    ctap2_make_credential(
                        hashPtr.baseAddress,
                        rpID,
                        rpName,
                        userIDPtr.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        userID.count,
                        userName,
                        displayName,
                        algPtr.baseAddress,
                        algIDs.count,
                        residentKey,
                        &resultBuf,
                        resultBuf.count
                    )
                }
            }
        }

        guard written > 0 else {
            return .failure(Self.ctap2ErrorMessage(code: Int(written)))
        }

        // Raw CTAP2 response: first byte is status, rest is CBOR map
        let statusByte = resultBuf[0]
        guard statusByte == 0 else {
            return .failure(CTAP2Error(message: "CTAP2 device error: status 0x\(String(statusByte, radix: 16))"))
        }

        let cborData = Data(resultBuf[1..<Int(written)])

        // Parse CBOR map for MakeCredential response:
        //   key 0x01 = fmt (string)
        //   key 0x02 = authData (bytes)  — contains credentialID
        //   key 0x03 = attStmt (map)
        // The full attestationObject is the CBOR from byte 1 onward.
        let attestationObject = cborData
        guard let parsed = Self.parseCBORMap(cborData) else {
            return .failure(CTAP2Error(message: "Failed to parse CTAP2 MakeCredential CBOR response."))
        }

        // Extract credentialID from authData (key 0x02):
        // authData format: rpIdHash(32) + flags(1) + signCount(4) + [attestedCredData]
        // attestedCredData: aaguid(16) + credIdLen(2) + credentialId(credIdLen) + ...
        guard let authData = parsed[2] as? Data, authData.count >= 55 else {
            return .failure(CTAP2Error(message: "Invalid authenticator data in MakeCredential response."))
        }
        let credIdLen = Int(authData[53]) << 8 | Int(authData[54])
        guard authData.count >= 55 + credIdLen else {
            return .failure(CTAP2Error(message: "Authenticator data too short for credentialID."))
        }
        let credentialID = authData[55..<(55 + credIdLen)]

        return .success([
            "credentialID": Data(credentialID).base64urlEncodedString(),
            "attestationObject": attestationObject.base64urlEncodedString(),
            "authenticatorAttachment": "cross-platform",
            "transports": ["usb"],
            "type": "registration",
        ])
    }

    private nonisolated func performCTAP2GetAssertion(
        clientDataHash: [UInt8],
        rpID: String,
        allowListIDs: [Data]
    ) -> Result<[String: Any], CTAP2Error> {
        var resultBuf = [UInt8](repeating: 0, count: 4096)

        // Build the allow list arrays for the C API
        let idBuffers: [[UInt8]] = allowListIDs.map { Array($0) }
        let idLens: [Int] = idBuffers.map { $0.count }

        let written: Int32
        if allowListIDs.isEmpty {
            written = clientDataHash.withUnsafeBufferPointer { hashPtr in
                ctap2_get_assertion(
                    hashPtr.baseAddress,
                    rpID,
                    nil,
                    nil,
                    0,
                    &resultBuf,
                    resultBuf.count
                )
            }
        } else {
            // Create array of pointers to each credential ID buffer
            written = clientDataHash.withUnsafeBufferPointer { hashPtr in
                idBuffers.withUnsafeBufferPointers { idPtrs in
                    idLens.withUnsafeBufferPointer { lensPtr in
                        ctap2_get_assertion(
                            hashPtr.baseAddress,
                            rpID,
                            idPtrs.baseAddress,
                            lensPtr.baseAddress,
                            allowListIDs.count,
                            &resultBuf,
                            resultBuf.count
                        )
                    }
                }
            }
        }

        guard written > 0 else {
            return .failure(Self.ctap2ErrorMessage(code: Int(written)))
        }

        // Raw CTAP2 response: first byte is status, rest is CBOR map
        let statusByte = resultBuf[0]
        guard statusByte == 0 else {
            return .failure(CTAP2Error(message: "CTAP2 device error: status 0x\(String(statusByte, radix: 16))"))
        }

        let cborData = Data(resultBuf[1..<Int(written)])

        // Parse CBOR map for GetAssertion response:
        //   key 0x01 = credential (map with "id" bytes)
        //   key 0x02 = authData (bytes)
        //   key 0x03 = signature (bytes)
        //   key 0x04 = user (map, optional)
        guard let parsed = Self.parseCBORMap(cborData) else {
            return .failure(CTAP2Error(message: "Failed to parse CTAP2 GetAssertion CBOR response."))
        }

        // Extract credential ID from key 0x01
        let credentialID: Data
        if let credMap = parsed[1] as? [Int: Any],
           let credIDData = credMap[0] as? Data {
            // credential map: key "id" is CBOR map key for the ID bytes
            credentialID = credIDData
        } else if let credDict = parsed[1] as? [String: Any],
                  let idBytes = credDict["id"] as? Data {
            credentialID = idBytes
        } else {
            return .failure(CTAP2Error(message: "Missing credentialID in GetAssertion response."))
        }

        guard let authData = parsed[2] as? Data else {
            return .failure(CTAP2Error(message: "Missing authenticatorData in GetAssertion response."))
        }

        guard let signature = parsed[3] as? Data else {
            return .failure(CTAP2Error(message: "Missing signature in GetAssertion response."))
        }

        // User handle is optional (key 0x04)
        let userHandle: Data
        if let userMap = parsed[4] as? [Int: Any],
           let idData = userMap[0] as? Data {
            userHandle = idData
        } else if let userDict = parsed[4] as? [String: Any],
                  let idData = userDict["id"] as? Data {
            userHandle = idData
        } else {
            userHandle = Data()
        }

        return .success([
            "credentialID": credentialID.base64urlEncodedString(),
            "authenticatorData": authData.base64urlEncodedString(),
            "signature": signature.base64urlEncodedString(),
            "userHandle": userHandle.base64urlEncodedString(),
            "authenticatorAttachment": "cross-platform",
            "type": "assertion",
        ])
    }

    // MARK: - CTAP2 Helpers

    /// Build a clientDataJSON blob matching the WebAuthn spec.
    private static func buildClientDataJSON(type: String, challenge: String, origin: String) -> Data {
        // Minimal clientDataJSON per WebAuthn spec
        let json = """
        {"type":"\(type)","challenge":"\(challenge)","origin":"\(origin)","crossOrigin":false}
        """
        return Data(json.utf8)
    }

    /// Map CTAP2 error codes to human-readable strings.
    private nonisolated static func ctap2ErrorMessage(code: Int) -> CTAP2Error {
        switch Int32(code) {
        case CTAP2_ERR_NO_DEVICE:      return CTAP2Error(message: "No FIDO2 security key detected.")
        case CTAP2_ERR_TIMEOUT:        return CTAP2Error(message: "Security key operation timed out.")
        case CTAP2_ERR_PROTOCOL:       return CTAP2Error(message: "CTAP2 protocol error.")
        case CTAP2_ERR_BUFFER_TOO_SMALL: return CTAP2Error(message: "Response buffer too small.")
        case CTAP2_ERR_OPEN_FAILED:    return CTAP2Error(message: "Failed to open security key device.")
        case CTAP2_ERR_WRITE_FAILED:   return CTAP2Error(message: "Failed to write to security key. IOReturn=\(ctap2_debug_last_ioreturn())")
        case CTAP2_ERR_READ_FAILED:    return CTAP2Error(message: "Failed to read from security key.")
        case CTAP2_ERR_CBOR:           return CTAP2Error(message: "CBOR encoding/decoding error.")
        case CTAP2_ERR_DEVICE:         return CTAP2Error(message: "Security key returned an error.")
        default:                        return CTAP2Error(message: "Unknown CTAP2 error (code \(code)).")
        }
    }

    /// Minimal CBOR map parser for CTAP2 responses.
    /// Handles the top-level CBOR map with integer keys and byte-string / text-string / map values.
    /// Returns a dictionary keyed by CBOR integer keys.
    private nonisolated static func parseCBORMap(_ data: Data) -> [Int: Any]? {
        guard !data.isEmpty else { return nil }
        var result: [Int: Any] = [:]
        var offset = 0
        let bytes = Array(data)

        // First byte should be a CBOR map (major type 5)
        guard offset < bytes.count else { return nil }
        let mapHeader = bytes[offset]
        let majorType = mapHeader >> 5
        guard majorType == 5 else { return nil }
        let mapCount = Int(mapHeader & 0x1f)
        offset += 1

        for _ in 0..<mapCount {
            guard offset < bytes.count else { break }

            // Parse key (unsigned integer, major type 0)
            let key: Int
            let keyByte = bytes[offset]
            if keyByte >> 5 == 0 {
                key = Int(keyByte & 0x1f)
                offset += 1
            } else {
                // Skip entries with non-integer keys
                break
            }

            // Parse value
            guard offset < bytes.count else { break }
            let (value, newOffset) = parseCBORValue(bytes: bytes, offset: offset)
            guard let newOffset else { break }
            result[key] = value
            offset = newOffset
        }

        return result
    }

    /// Parse a single CBOR value starting at the given offset.
    /// Returns the parsed value and the new offset, or nil on failure.
    private nonisolated static func parseCBORValue(bytes: [UInt8], offset: Int) -> (Any?, Int?) {
        guard offset < bytes.count else { return (nil, nil) }
        let header = bytes[offset]
        let majorType = header >> 5
        let additional = header & 0x1f

        switch majorType {
        case 0: // Unsigned integer
            let (value, newOff) = parseCBORUInt(bytes: bytes, offset: offset)
            return (value, newOff)

        case 1: // Negative integer
            guard let (raw, newOff) = parseCBORRawUInt(bytes: bytes, offset: offset + 1, additional: additional) else {
                return (nil, nil)
            }
            return (-(Int(raw) + 1), newOff)

        case 2: // Byte string
            guard let (length, dataStart) = parseCBORRawUInt(bytes: bytes, offset: offset + 1, additional: additional) else {
                return (nil, nil)
            }
            let len = Int(length)
            guard dataStart + len <= bytes.count else { return (nil, nil) }
            return (Data(bytes[dataStart..<(dataStart + len)]), dataStart + len)

        case 3: // Text string
            guard let (length, dataStart) = parseCBORRawUInt(bytes: bytes, offset: offset + 1, additional: additional) else {
                return (nil, nil)
            }
            let len = Int(length)
            guard dataStart + len <= bytes.count else { return (nil, nil) }
            let str = String(bytes: bytes[dataStart..<(dataStart + len)], encoding: .utf8) ?? ""
            return (str, dataStart + len)

        case 4: // Array — skip by parsing each element
            guard let (count, elemStart) = parseCBORRawUInt(bytes: bytes, offset: offset + 1, additional: additional) else {
                return (nil, nil)
            }
            var off = elemStart
            for _ in 0..<Int(count) {
                let (_, nextOff) = parseCBORValue(bytes: bytes, offset: off)
                guard let nextOff else { return (nil, nil) }
                off = nextOff
            }
            return (nil, off) // We don't need array values for CTAP2 responses

        case 5: // Map
            guard let (count, elemStart) = parseCBORRawUInt(bytes: bytes, offset: offset + 1, additional: additional) else {
                return (nil, nil)
            }
            var subMap: [Int: Any] = [:]
            var off = elemStart
            for _ in 0..<Int(count) {
                // Parse key
                let (keyVal, keyOff) = parseCBORValue(bytes: bytes, offset: off)
                guard let keyOff else { return (nil, nil) }
                // Parse value
                let (valVal, valOff) = parseCBORValue(bytes: bytes, offset: keyOff)
                guard let valOff else { return (nil, nil) }
                if let intKey = keyVal as? Int {
                    subMap[intKey] = valVal
                }
                off = valOff
            }
            return (subMap, off)

        case 7: // Simple values / floats — skip
            if additional < 24 {
                return (nil, offset + 1)
            } else if additional == 24 {
                return (nil, offset + 2)
            } else if additional == 25 {
                return (nil, offset + 3)
            } else if additional == 26 {
                return (nil, offset + 5)
            } else if additional == 27 {
                return (nil, offset + 9)
            }
            return (nil, offset + 1)

        default:
            return (nil, nil)
        }
    }

    /// Parse a CBOR unsigned integer (major type 0) at offset.
    private nonisolated static func parseCBORUInt(bytes: [UInt8], offset: Int) -> (Int?, Int?) {
        guard offset < bytes.count else { return (nil, nil) }
        let additional = bytes[offset] & 0x1f
        guard let (value, newOff) = parseCBORRawUInt(bytes: bytes, offset: offset + 1, additional: additional) else {
            return (nil, nil)
        }
        return (Int(value), newOff)
    }

    /// Parse the raw unsigned integer value from CBOR additional info.
    private nonisolated static func parseCBORRawUInt(bytes: [UInt8], offset: Int, additional: UInt8) -> (UInt64, Int)? {
        if additional < 24 {
            return (UInt64(additional), offset)
        } else if additional == 24 {
            guard offset < bytes.count else { return nil }
            return (UInt64(bytes[offset]), offset + 1)
        } else if additional == 25 {
            guard offset + 1 < bytes.count else { return nil }
            let value = UInt64(bytes[offset]) << 8 | UInt64(bytes[offset + 1])
            return (value, offset + 2)
        } else if additional == 26 {
            guard offset + 3 < bytes.count else { return nil }
            let value = UInt64(bytes[offset]) << 24 | UInt64(bytes[offset + 1]) << 16
                | UInt64(bytes[offset + 2]) << 8 | UInt64(bytes[offset + 3])
            return (value, offset + 4)
        } else if additional == 27 {
            guard offset + 7 < bytes.count else { return nil }
            var value: UInt64 = 0
            for i in 0..<8 {
                value = value << 8 | UInt64(bytes[offset + i])
            }
            return (value, offset + 8)
        }
        return nil
    }
}

// MARK: - WKScriptMessageHandlerWithReply

extension WebAuthnCoordinator: WKScriptMessageHandlerWithReply {

    nonisolated func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage,
        replyHandler: @escaping (Any?, String?) -> Void
    ) {
        Task { @MainActor in
            self.handleMessageWithReply(message, replyHandler: replyHandler)
        }
    }

    private func handleMessageWithReply(
        _ message: WKScriptMessage,
        replyHandler: @escaping (Any?, String?) -> Void
    ) {
        guard let body = message.body as? [String: Any],
              let type = body["type"] as? String,
              let options = body["options"] as? [String: Any],
              let origin = body["origin"] as? String
        else {
            #if DEBUG
            dlog("webauthn.message REJECT invalid format body=\(String(describing: message.body))")
            #endif
            replyHandler(["error": "Invalid message format.", "name": "TypeError"], nil)
            return
        }

        #if DEBUG
        dlog("webauthn.message type=\(type) origin=\(origin) optionKeys=\(Array(options.keys).sorted())")
        #endif

        guard validateOrigin(origin) else {
            replyHandler(["error": "Origin mismatch.", "name": "SecurityError"], nil)
            return
        }

        guard case .idle = state else {
            #if DEBUG
            dlog("webauthn.message REJECT already authenticating")
            #endif
            replyHandler(
                ["error": "A credential operation is already in progress.", "name": "InvalidStateError"],
                nil
            )
            return
        }

        switch type {
        case "create":
            handleCreate(options: options, origin: origin, replyHandler: replyHandler)
        case "get":
            handleGet(options: options, origin: origin, replyHandler: replyHandler)
        default:
            #if DEBUG
            dlog("webauthn.message REJECT unknown type=\(type)")
            #endif
            replyHandler(["error": "Unknown WebAuthn operation type.", "name": "NotSupportedError"], nil)
        }
    }
}

// MARK: - Allow List Pointer Helper

private extension Array where Element == [UInt8] {
    /// Provides an array of UnsafePointer<UInt8> for C interop, one per element buffer.
    func withUnsafeBufferPointers<R>(_ body: (UnsafeBufferPointer<UnsafePointer<UInt8>?>) -> R) -> R {
        var pointers: [UnsafePointer<UInt8>?] = []
        // Pin each inner buffer and collect pointers.
        // This is safe because we call body synchronously before returning.
        func pin(index: Int, body innerBody: (UnsafeBufferPointer<UnsafePointer<UInt8>?>) -> R) -> R {
            if index == self.count {
                return pointers.withUnsafeBufferPointer { innerBody($0) }
            }
            return self[index].withUnsafeBufferPointer { buf in
                pointers.append(buf.baseAddress)
                return pin(index: index + 1, body: innerBody)
            }
        }
        return pin(index: 0, body: body)
    }
}

// MARK: - Base64URL Data Extension

private extension Data {

    func base64urlEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: "="))
    }

    init?(base64urlEncoded string: String) {
        var s = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while s.count % 4 != 0 { s.append("=") }
        self.init(base64Encoded: s)
    }
}
