import AuthenticationServices
import Bonsplit
import CryptoKit
import WebKit
import YubiKit

/// Coordinates WebAuthn/FIDO2 ceremonies between the JS bridge and
/// either Apple's AuthenticationServices framework (when the app has
/// the required entitlements) or Yubico's YubiKit for direct USB HID
/// communication with security keys (works in any build).
///
/// One coordinator per WKWebView. Handles both registration (create)
/// and assertion (get) flows using hardware security keys (YubiKey)
/// and platform authenticators (Touch ID / passkeys).
@MainActor
final class WebAuthnCoordinator: NSObject {

    // MARK: - State

    private enum State {
        case idle
        case authenticating(replyHandler: @MainActor (Any?, String?) -> Void)
    }

    private var state: State = .idle
    private weak var webView: WKWebView?
    private var authorizationController: ASAuthorizationController?

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
        authorizationController?.cancel()
        authorizationController = nil
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

    // MARK: - Registration (create) via YubiKit CTAP2

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

        let rpID = (options["rp"] as? [String: Any])?["id"] as? String
            ?? webView?.url?.host ?? ""
        let rpName = (options["rp"] as? [String: Any])?["name"] as? String ?? rpID

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

        // Build clientDataHash (SHA-256 of clientDataJSON constructed by JS bridge)
        let clientDataJSON = buildClientDataJSON(type: "webauthn.create", challenge: challengeB64, origin: origin)
        let clientDataHash = Data(SHA256.hash(data: clientDataJSON))

        // Parse algorithms
        var algorithms: [COSE.Algorithm] = []
        if let credParams = options["pubKeyCredParams"] as? [[String: Any]] {
            algorithms = credParams.compactMap { param in
                guard let alg = param["alg"] as? Int else { return nil }
                return COSE.Algorithm(rawValue: alg)
            }
        }
        if algorithms.isEmpty {
            algorithms = [.es256, .rs256]
        }

        // Parse options
        let authSel = options["authenticatorSelection"] as? [String: Any]
        let rk = authSel?["residentKey"] as? String == "required"
            || authSel?["requireResidentKey"] as? Bool == true

        let params = CTAP2.MakeCredential.Parameters(
            clientDataHash: clientDataHash,
            rp: .init(id: rpID, name: rpName),
            user: .init(id: userIDData, name: userName, displayName: displayName),
            pubKeyCredParams: algorithms,
            excludeList: nil,
            extensions: [],
            rk: rk
        )

        #if DEBUG
        dlog("webauthn.ctap2.create rpID=\(rpID) user=\(userName) algorithms=\(algorithms)")
        #endif

        state = .authenticating(replyHandler: replyHandler)
        Task { @MainActor in
            await performCTAP2MakeCredential(params: params, replyHandler: replyHandler)
        }
    }

    // MARK: - Assertion (get) via YubiKit CTAP2

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

        // Build clientDataHash
        let clientDataJSON = buildClientDataJSON(type: "webauthn.get", challenge: challengeB64, origin: origin)
        let clientDataHash = Data(SHA256.hash(data: clientDataJSON))

        // Parse allowCredentials
        var allowList: [WebAuthn.PublicKeyCredential.Descriptor]? = nil
        if let allowCredentials = options["allowCredentials"] as? [[String: Any]] {
            allowList = allowCredentials.compactMap { cred in
                guard let idB64 = cred["id"] as? String,
                      let idData = Data(base64urlEncoded: idB64)
                else { return nil }
                return WebAuthn.PublicKeyCredential.Descriptor(
                    id: idData,
                    type: .publicKey
                )
            }
        }

        let params = CTAP2.GetAssertion.Parameters(
            rpId: rpID,
            clientDataHash: clientDataHash,
            allowList: allowList,
            extensions: []
        )

        #if DEBUG
        dlog("webauthn.ctap2.get rpID=\(rpID) allowList=\(allowList?.count ?? 0)")
        #endif

        state = .authenticating(replyHandler: replyHandler)
        Task { @MainActor in
            await performCTAP2GetAssertion(params: params, replyHandler: replyHandler)
        }
    }

    // MARK: - CTAP2 Direct USB HID

    private func performCTAP2MakeCredential(
        params: CTAP2.MakeCredential.Parameters,
        replyHandler: @escaping @MainActor (Any?, String?) -> Void
    ) async {
        do {
            #if DEBUG
            dlog("webauthn.ctap2.create connecting to YubiKey via USB HID...")
            #endif
            let connection = try await HIDFIDOConnection()
            let session = try await CTAP2.Session(connection: connection)

            #if DEBUG
            dlog("webauthn.ctap2.create session established, performing makeCredential...")
            #endif

            var response: CTAP2.MakeCredential.Response?
            for try await status in await session.makeCredential(parameters: params) {
                switch status {
                case .waitingForTouch:
                    #if DEBUG
                    dlog("webauthn.ctap2.create waiting for touch...")
                    #endif
                case .finished(let result):
                    response = result
                }
            }

            guard let result = response else {
                state = .idle
                replyHandler(["error": "No response from authenticator.", "name": "NotAllowedError"], nil)
                return
            }

            #if DEBUG
            dlog("webauthn.ctap2.create SUCCESS credentialID=\(result.authenticatorData.attestedCredential?.credentialId.base64urlEncodedString() ?? "nil")")
            #endif

            state = .idle
            replyHandler([
                "credentialID": result.authenticatorData.attestedCredential?.credentialId.base64urlEncodedString() ?? "",
                "attestationObject": result.rawAttestationObject.base64urlEncodedString(),
                "authenticatorAttachment": "cross-platform",
                "transports": ["usb"],
                "type": "registration"
            ], nil)
        } catch {
            #if DEBUG
            dlog("webauthn.ctap2.create FAILED: \(error)")
            #endif
            state = .idle
            replyHandler(["error": error.localizedDescription, "name": "NotAllowedError"], nil)
        }
    }

    private func performCTAP2GetAssertion(
        params: CTAP2.GetAssertion.Parameters,
        replyHandler: @escaping @MainActor (Any?, String?) -> Void
    ) async {
        do {
            #if DEBUG
            dlog("webauthn.ctap2.get connecting to YubiKey via USB HID...")
            #endif
            let connection = try await HIDFIDOConnection()
            let session = try await CTAP2.Session(connection: connection)

            #if DEBUG
            dlog("webauthn.ctap2.get session established, performing getAssertion...")
            #endif

            var response: CTAP2.GetAssertion.Response?
            for try await status in await session.getAssertion(parameters: params) {
                switch status {
                case .waitingForTouch:
                    #if DEBUG
                    dlog("webauthn.ctap2.get waiting for touch...")
                    #endif
                case .finished(let result):
                    response = result
                }
            }

            guard let result = response else {
                state = .idle
                replyHandler(["error": "No response from authenticator.", "name": "NotAllowedError"], nil)
                return
            }

            #if DEBUG
            dlog("webauthn.ctap2.get SUCCESS credentialID=\(result.credential?.id.base64urlEncodedString() ?? "nil")")
            #endif

            state = .idle
            replyHandler([
                "credentialID": result.credential?.id.base64urlEncodedString() ?? "",
                "authenticatorData": result.authData.base64urlEncodedString(),
                "signature": result.signature.base64urlEncodedString(),
                "userHandle": result.user?.id.base64urlEncodedString() ?? "",
                "authenticatorAttachment": "cross-platform",
                "type": "assertion"
            ], nil)
        } catch {
            #if DEBUG
            dlog("webauthn.ctap2.get FAILED: \(error)")
            #endif
            state = .idle
            replyHandler(["error": error.localizedDescription, "name": "NotAllowedError"], nil)
        }
    }

    // MARK: - Client Data JSON

    private func buildClientDataJSON(type: String, challenge: String, origin: String) -> Data {
        let json = """
        {"type":"\(type)","challenge":"\(challenge)","origin":"\(origin)","crossOrigin":false}
        """
        return Data(json.utf8)
    }

    // MARK: - Request Configuration

    private func configureSecurityKeyRegistrationRequest(
        _ request: ASAuthorizationSecurityKeyPublicKeyCredentialRegistrationRequest,
        options: [String: Any]
    ) {
        if let credParams = options["pubKeyCredParams"] as? [[String: Any]] {
            request.credentialParameters = credParams.compactMap { param in
                guard let alg = param["alg"] as? Int else { return nil }
                return ASAuthorizationPublicKeyCredentialParameters(
                    algorithm: ASCOSEAlgorithmIdentifier(rawValue: alg)
                )
            }
        }

        if let excludeCreds = options["excludeCredentials"] as? [[String: Any]] {
            request.excludedCredentials = excludeCreds.compactMap { cred in
                guard let idB64 = cred["id"] as? String,
                      let idData = Data(base64urlEncoded: idB64)
                else { return nil }
                let transports = parseTransports(cred["transports"] as? [String])
                return ASAuthorizationSecurityKeyPublicKeyCredentialDescriptor(
                    credentialID: idData,
                    transports: transports
                )
            }
        }

        if let authSel = options["authenticatorSelection"] as? [String: Any] {
            if let residentKey = authSel["residentKey"] as? String {
                request.residentKeyPreference = parseResidentKeyPreference(residentKey)
            }
            if let userVerification = authSel["userVerification"] as? String {
                request.userVerificationPreference = parseUserVerificationPreference(userVerification)
            }
        }

        if let attestation = options["attestation"] as? String {
            request.attestationPreference = parseAttestationPreference(attestation)
        }
    }

    private func configureSecurityKeyAssertionRequest(
        _ request: ASAuthorizationSecurityKeyPublicKeyCredentialAssertionRequest,
        options: [String: Any]
    ) {
        if let allowCredentials = options["allowCredentials"] as? [[String: Any]] {
            request.allowedCredentials = allowCredentials.compactMap { cred in
                guard let idB64 = cred["id"] as? String,
                      let idData = Data(base64urlEncoded: idB64)
                else { return nil }
                let transports = parseTransports(cred["transports"] as? [String])
                return ASAuthorizationSecurityKeyPublicKeyCredentialDescriptor(
                    credentialID: idData,
                    transports: transports
                )
            }
        }

        if let userVerification = options["userVerification"] as? String {
            request.userVerificationPreference = parseUserVerificationPreference(userVerification)
        }
    }

    // MARK: - Authorization Controller

    private func performAuthorization(
        with requests: [ASAuthorizationRequest],
        replyHandler: @escaping @MainActor (Any?, String?) -> Void
    ) {
        let controller = ASAuthorizationController(authorizationRequests: requests)
        controller.delegate = self
        controller.presentationContextProvider = self
        self.authorizationController = controller
        self.state = .authenticating(replyHandler: replyHandler)
        #if DEBUG
        dlog("webauthn.performRequests state=authenticating requestTypes=\(requests.map { type(of: $0) })")
        #endif
        controller.performRequests()
    }

    // MARK: - Enum Parsing

    private func parseTransports(_ transports: [String]?) -> [ASAuthorizationSecurityKeyPublicKeyCredentialDescriptor.Transport] {
        guard let transports else { return ASAuthorizationSecurityKeyPublicKeyCredentialDescriptor.Transport.allSupported }
        var result: [ASAuthorizationSecurityKeyPublicKeyCredentialDescriptor.Transport] = []
        for t in transports {
            switch t {
            case "usb": result.append(.usb)
            case "nfc": result.append(.nfc)
            case "ble": result.append(.bluetooth)
            default: break
            }
        }
        return result.isEmpty ? ASAuthorizationSecurityKeyPublicKeyCredentialDescriptor.Transport.allSupported : result
    }

    private func parseResidentKeyPreference(_ value: String) -> ASAuthorizationPublicKeyCredentialResidentKeyPreference {
        switch value {
        case "required": return .required
        case "preferred": return .preferred
        case "discouraged": return .discouraged
        default: return .preferred
        }
    }

    private func parseUserVerificationPreference(_ value: String) -> ASAuthorizationPublicKeyCredentialUserVerificationPreference {
        switch value {
        case "required": return .required
        case "preferred": return .preferred
        case "discouraged": return .discouraged
        default: return .preferred
        }
    }

    private func parseAttestationPreference(_ value: String) -> ASAuthorizationPublicKeyCredentialAttestationKind {
        switch value {
        case "direct": return .direct
        case "indirect": return .indirect
        case "enterprise": return .enterprise
        default: return .none
        }
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

// MARK: - ASAuthorizationControllerDelegate

extension WebAuthnCoordinator: ASAuthorizationControllerDelegate {

    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        Task { @MainActor in
            self.handleAuthorizationCompletion(authorization)
        }
    }

    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        Task { @MainActor in
            self.handleAuthorizationError(error)
        }
    }

    private func handleAuthorizationCompletion(_ authorization: ASAuthorization) {
        guard case .authenticating(let replyHandler) = state else {
            #if DEBUG
            dlog("webauthn.authComplete IGNORED state=idle (no pending request)")
            #endif
            return
        }
        state = .idle
        authorizationController = nil
        #if DEBUG
        dlog("webauthn.authComplete credentialType=\(type(of: authorization.credential))")
        #endif

        switch authorization.credential {
        case let cred as ASAuthorizationSecurityKeyPublicKeyCredentialRegistration:
            replyHandler([
                "credentialID": cred.credentialID.base64urlEncodedString(),
                "attestationObject": cred.rawAttestationObject?.base64urlEncodedString() ?? "",
                "authenticatorAttachment": "cross-platform",
                "transports": ["usb"],
                "type": "registration"
            ], nil)

        case let cred as ASAuthorizationSecurityKeyPublicKeyCredentialAssertion:
            replyHandler([
                "credentialID": cred.credentialID.base64urlEncodedString(),
                "authenticatorData": cred.rawAuthenticatorData.base64urlEncodedString(),
                "signature": cred.signature.base64urlEncodedString(),
                "userHandle": cred.userID.base64urlEncodedString(),
                "authenticatorAttachment": "cross-platform",
                "type": "assertion"
            ], nil)

        case let cred as ASAuthorizationPlatformPublicKeyCredentialRegistration:
            replyHandler([
                "credentialID": cred.credentialID.base64urlEncodedString(),
                "attestationObject": cred.rawAttestationObject?.base64urlEncodedString() ?? "",
                "authenticatorAttachment": "platform",
                "type": "registration"
            ], nil)

        case let cred as ASAuthorizationPlatformPublicKeyCredentialAssertion:
            replyHandler([
                "credentialID": cred.credentialID.base64urlEncodedString(),
                "authenticatorData": cred.rawAuthenticatorData.base64urlEncodedString(),
                "signature": cred.signature.base64urlEncodedString(),
                "userHandle": cred.userID.base64urlEncodedString(),
                "authenticatorAttachment": "platform",
                "type": "assertion"
            ], nil)

        default:
            replyHandler(
                ["error": "Unsupported credential type.", "name": "NotSupportedError"],
                nil
            )
        }
    }

    private func handleAuthorizationError(_ error: Error) {
        guard case .authenticating(let replyHandler) = state else {
            #if DEBUG
            dlog("webauthn.authError IGNORED state=idle error=\(error)")
            #endif
            return
        }
        state = .idle
        authorizationController = nil
        #if DEBUG
        dlog("webauthn.authError error=\(error) code=\((error as? ASAuthorizationError)?.code.rawValue ?? -1)")
        #endif

        let errorName: String
        if let asError = error as? ASAuthorizationError {
            switch asError.code {
            case .canceled:
                errorName = "NotAllowedError"
            case .failed:
                errorName = "NotAllowedError"
            case .invalidResponse:
                errorName = "InvalidStateError"
            case .notHandled:
                errorName = "NotSupportedError"
            case .notInteractive:
                errorName = "NotAllowedError"
            case .unknown, .matchedExcludedCredential:
                errorName = "InvalidStateError"
            @unknown default:
                errorName = "UnknownError"
            }
        } else {
            errorName = "UnknownError"
        }

        replyHandler(["error": error.localizedDescription, "name": errorName], nil)
    }
}

// MARK: - ASAuthorizationControllerPresentationContextProviding

extension WebAuthnCoordinator: ASAuthorizationControllerPresentationContextProviding {

    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        // AuthenticationServices calls this on the main thread. Using DispatchQueue.main.sync
        // from the main thread deadlocks (BUG IN CLIENT OF LIBDISPATCH). Use
        // MainActor.assumeIsolated since we know we're already on main.
        if Thread.isMainThread {
            return MainActor.assumeIsolated {
                let w = webView?.window ?? NSApp.keyWindow ?? NSApp.mainWindow ?? ASPresentationAnchor()
                #if DEBUG
                dlog("webauthn.presentationAnchor window=\(w) isMainThread=true webView.window=\(String(describing: webView?.window))")
                #endif
                return w
            }
        }
        return DispatchQueue.main.sync {
            let w = webView?.window ?? NSApp.keyWindow ?? NSApp.mainWindow ?? ASPresentationAnchor()
            #if DEBUG
            dlog("webauthn.presentationAnchor window=\(w) isMainThread=false")
            #endif
            return w
        }
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
