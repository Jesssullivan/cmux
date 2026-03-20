import AuthenticationServices
import WebKit

/// Coordinates WebAuthn/FIDO2 ceremonies between the JS bridge and
/// Apple's AuthenticationServices framework.
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
        guard let webViewURL = webView?.url else { return false }
        let webViewOrigin = "\(webViewURL.scheme ?? "https")://\(webViewURL.host ?? "")"
            + (webViewURL.port.map { ":\($0)" } ?? "")
        return claimed == webViewOrigin
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

        let rpID = (options["rp"] as? [String: Any])?["id"] as? String
            ?? webView?.url?.host ?? ""

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

        var requests: [ASAuthorizationRequest] = []

        // Hardware security key (YubiKey, etc.)
        let securityKeyProvider = ASAuthorizationSecurityKeyPublicKeyCredentialProvider(relyingPartyIdentifier: rpID)
        let securityKeyRequest = securityKeyProvider.createCredentialRegistrationRequest(
            challenge: challengeData,
            displayName: displayName,
            name: userName,
            userID: userIDData
        )
        configureSecurityKeyRegistrationRequest(securityKeyRequest, options: options)
        requests.append(securityKeyRequest)

        // Platform authenticator (Touch ID / passkeys)
        let platformProvider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: rpID)
        let platformRequest = platformProvider.createCredentialRegistrationRequest(
            challenge: challengeData,
            name: userName,
            userID: userIDData
        )
        requests.append(platformRequest)

        performAuthorization(with: requests, replyHandler: replyHandler)
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

        var requests: [ASAuthorizationRequest] = []

        // Hardware security key assertion
        let securityKeyProvider = ASAuthorizationSecurityKeyPublicKeyCredentialProvider(relyingPartyIdentifier: rpID)
        let securityKeyRequest = securityKeyProvider.createCredentialAssertionRequest(challenge: challengeData)
        configureSecurityKeyAssertionRequest(securityKeyRequest, options: options)
        requests.append(securityKeyRequest)

        // Platform authenticator assertion
        let platformProvider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: rpID)
        let platformRequest = platformProvider.createCredentialAssertionRequest(challenge: challengeData)
        if let allowCredentials = options["allowCredentials"] as? [[String: Any]] {
            platformRequest.allowedCredentials = allowCredentials.compactMap { cred in
                guard let idB64 = cred["id"] as? String,
                      let idData = Data(base64urlEncoded: idB64)
                else { return nil }
                return ASAuthorizationPlatformPublicKeyCredentialDescriptor(credentialID: idData)
            }
        }
        requests.append(platformRequest)

        performAuthorization(with: requests, replyHandler: replyHandler)
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
            replyHandler(["error": "Invalid message format.", "name": "TypeError"], nil)
            return
        }

        guard validateOrigin(origin) else {
            replyHandler(["error": "Origin mismatch.", "name": "SecurityError"], nil)
            return
        }

        guard case .idle = state else {
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
        guard case .authenticating(let replyHandler) = state else { return }
        state = .idle
        authorizationController = nil

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
        guard case .authenticating(let replyHandler) = state else { return }
        state = .idle
        authorizationController = nil

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
        // This delegate method is called on the main thread by AuthenticationServices.
        DispatchQueue.main.sync {
            webView?.window ?? NSApp.keyWindow ?? NSApp.mainWindow ?? ASPresentationAnchor()
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
