/// WebAuthn JavaScript bridge source code.
///
/// Injected at document start into browser panels to intercept
/// navigator.credentials.create/get and route through native CTAP2.
/// This JavaScript is platform-agnostic — identical on macOS and Linux.
/// Source: Sources/Panels/WebAuthnBridgeJavaScript.swift

pub const MESSAGE_HANDLER_NAME = "cmuxWebAuthn";

pub const BRIDGE_SOURCE: [*:0]const u8 =
    \\(() => {
    \\  if (window.__cmuxWebAuthnBridgeInstalled) return true;
    \\  window.__cmuxWebAuthnBridgeInstalled = true;
    \\
    \\  console.log('[cmux-webauthn] bridge installing on', window.location.origin);
    \\
    \\  function b64urlEncode(buffer) {
    \\    const bytes = new Uint8Array(buffer);
    \\    let binary = '';
    \\    for (let i = 0; i < bytes.length; i++) binary += String.fromCharCode(bytes[i]);
    \\    return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
    \\  }
    \\
    \\  function b64urlDecode(str) {
    \\    let s = str.replace(/-/g, '+').replace(/_/g, '/');
    \\    while (s.length % 4 !== 0) s += '=';
    \\    const binary = atob(s);
    \\    const bytes = new Uint8Array(binary.length);
    \\    for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
    \\    return bytes.buffer;
    \\  }
    \\
    \\  function bufferSourceToB64url(val) {
    \\    if (val instanceof ArrayBuffer) return b64urlEncode(val);
    \\    if (ArrayBuffer.isView(val)) return b64urlEncode(val.buffer.slice(val.byteOffset, val.byteOffset + val.byteLength));
    \\    return val;
    \\  }
    \\
    \\  function serializeCreateOptions(publicKey) {
    \\    const opts = {};
    \\    if (publicKey.challenge) opts.challenge = bufferSourceToB64url(publicKey.challenge);
    \\    if (publicKey.rp) opts.rp = { id: publicKey.rp.id, name: publicKey.rp.name };
    \\    if (publicKey.user) {
    \\      opts.user = {
    \\        id: bufferSourceToB64url(publicKey.user.id),
    \\        name: publicKey.user.name,
    \\        displayName: publicKey.user.displayName
    \\      };
    \\    }
    \\    if (publicKey.pubKeyCredParams) opts.pubKeyCredParams = publicKey.pubKeyCredParams;
    \\    if (publicKey.timeout != null) opts.timeout = publicKey.timeout;
    \\    if (publicKey.attestation) opts.attestation = publicKey.attestation;
    \\    if (publicKey.authenticatorSelection) opts.authenticatorSelection = publicKey.authenticatorSelection;
    \\    if (publicKey.excludeCredentials) {
    \\      opts.excludeCredentials = publicKey.excludeCredentials.map(c => ({
    \\        id: bufferSourceToB64url(c.id),
    \\        type: c.type,
    \\        transports: c.transports
    \\      }));
    \\    }
    \\    if (publicKey.extensions) opts.extensions = publicKey.extensions;
    \\    return opts;
    \\  }
    \\
    \\  function serializeGetOptions(publicKey) {
    \\    const opts = {};
    \\    if (publicKey.challenge) opts.challenge = bufferSourceToB64url(publicKey.challenge);
    \\    if (publicKey.rpId) opts.rpId = publicKey.rpId;
    \\    if (publicKey.timeout != null) opts.timeout = publicKey.timeout;
    \\    if (publicKey.userVerification) opts.userVerification = publicKey.userVerification;
    \\    if (publicKey.allowCredentials) {
    \\      opts.allowCredentials = publicKey.allowCredentials.map(c => ({
    \\        id: bufferSourceToB64url(c.id),
    \\        type: c.type,
    \\        transports: c.transports
    \\      }));
    \\    }
    \\    if (publicKey.extensions) opts.extensions = publicKey.extensions;
    \\    return opts;
    \\  }
    \\
    \\  function buildClientDataJSON(type, challenge, origin) {
    \\    const obj = { type: type, challenge: challenge, origin: origin, crossOrigin: false };
    \\    const json = JSON.stringify(obj);
    \\    const encoder = new TextEncoder();
    \\    return encoder.encode(json).buffer;
    \\  }
    \\
    \\  function buildRegistrationResponse(nativeResult, challenge, origin) {
    \\    const clientDataJSON = buildClientDataJSON('webauthn.create', challenge, origin);
    \\    const credentialId = b64urlDecode(nativeResult.credentialID);
    \\    const attestationObject = nativeResult.attestationObject ? b64urlDecode(nativeResult.attestationObject) : new ArrayBuffer(0);
    \\    var response = {
    \\      type: 'public-key',
    \\      id: nativeResult.credentialID,
    \\      rawId: credentialId,
    \\      authenticatorAttachment: nativeResult.authenticatorAttachment || 'cross-platform',
    \\      response: {
    \\        clientDataJSON: clientDataJSON,
    \\        attestationObject: attestationObject,
    \\        getTransports: function() { return nativeResult.transports || []; },
    \\        getAuthenticatorData: function() { return nativeResult.authenticatorData ? b64urlDecode(nativeResult.authenticatorData) : new ArrayBuffer(0); },
    \\        getPublicKey: function() { return null; },
    \\        getPublicKeyAlgorithm: function() { return nativeResult.publicKeyAlgorithm || -7; }
    \\      },
    \\      getClientExtensionResults: function() { return {}; },
    \\      toJSON: function() {
    \\        return { type: 'public-key', id: nativeResult.credentialID, rawId: nativeResult.credentialID,
    \\          authenticatorAttachment: this.authenticatorAttachment,
    \\          response: { clientDataJSON: b64urlEncode(clientDataJSON), attestationObject: nativeResult.attestationObject || '', transports: nativeResult.transports || [] },
    \\          clientExtensionResults: {} };
    \\      }
    \\    };
    \\    if (typeof PublicKeyCredential !== 'undefined') Object.setPrototypeOf(response, PublicKeyCredential.prototype);
    \\    return response;
    \\  }
    \\
    \\  function buildAssertionResponse(nativeResult, challenge, origin) {
    \\    const clientDataJSON = buildClientDataJSON('webauthn.get', challenge, origin);
    \\    const credentialId = b64urlDecode(nativeResult.credentialID);
    \\    const authenticatorData = nativeResult.authenticatorData ? b64urlDecode(nativeResult.authenticatorData) : new ArrayBuffer(0);
    \\    const signature = nativeResult.signature ? b64urlDecode(nativeResult.signature) : new ArrayBuffer(0);
    \\    const userHandle = (nativeResult.userHandle && nativeResult.userHandle.length > 0) ? b64urlDecode(nativeResult.userHandle) : null;
    \\    var response = {
    \\      type: 'public-key',
    \\      id: nativeResult.credentialID,
    \\      rawId: credentialId,
    \\      authenticatorAttachment: nativeResult.authenticatorAttachment || 'cross-platform',
    \\      response: { clientDataJSON: clientDataJSON, authenticatorData: authenticatorData, signature: signature, userHandle: userHandle },
    \\      getClientExtensionResults: function() { return {}; },
    \\      toJSON: function() {
    \\        return { type: 'public-key', id: nativeResult.credentialID, rawId: nativeResult.credentialID,
    \\          authenticatorAttachment: this.authenticatorAttachment,
    \\          response: { clientDataJSON: b64urlEncode(clientDataJSON), authenticatorData: nativeResult.authenticatorData || '',
    \\            signature: nativeResult.signature || '', userHandle: nativeResult.userHandle || null },
    \\          clientExtensionResults: {} };
    \\      }
    \\    };
    \\    if (typeof PublicKeyCredential !== 'undefined') Object.setPrototypeOf(response, PublicKeyCredential.prototype);
    \\    return response;
    \\  }
    \\
    \\  function mapNativeError(result) {
    \\    if (result && typeof result === 'object' && result.error) return new DOMException(result.error, result.name || 'NotAllowedError');
    \\    return new DOMException('The operation was aborted.', 'AbortError');
    \\  }
    \\
    \\  async function postToNative(payload) {
    \\    if (!window.webkit || !window.webkit.messageHandlers || !window.webkit.messageHandlers.cmuxWebAuthn) {
    \\      throw new DOMException('WebAuthn is not supported in this browser.', 'NotSupportedError');
    \\    }
    \\    const result = await window.webkit.messageHandlers.cmuxWebAuthn.postMessage(payload);
    \\    return result;
    \\  }
    \\
    \\  if (!navigator.credentials) navigator.credentials = {};
    \\  const _origCreate = navigator.credentials.create ? navigator.credentials.create.bind(navigator.credentials) : null;
    \\  const _origGet = navigator.credentials.get ? navigator.credentials.get.bind(navigator.credentials) : null;
    \\
    \\  navigator.credentials.create = async function(options) {
    \\    if (!options || !options.publicKey) {
    \\      if (_origCreate) return _origCreate(options);
    \\      throw new DOMException('PublicKeyCredential creation requires publicKey options.', 'NotSupportedError');
    \\    }
    \\    try {
    \\      const serialized = serializeCreateOptions(options.publicKey);
    \\      const origin = window.location.origin;
    \\      const result = await postToNative({ type: 'create', options: serialized, origin: origin });
    \\      if (!result || result.error) throw mapNativeError(result);
    \\      return buildRegistrationResponse(result, serialized.challenge, origin);
    \\    } catch (e) { throw e; }
    \\  };
    \\
    \\  navigator.credentials.get = async function(options) {
    \\    if (!options || !options.publicKey) {
    \\      if (_origGet) return _origGet(options);
    \\      throw new DOMException('PublicKeyCredential assertion requires publicKey options.', 'NotSupportedError');
    \\    }
    \\    try {
    \\      const serialized = serializeGetOptions(options.publicKey);
    \\      const origin = window.location.origin;
    \\      const result = await postToNative({ type: 'get', options: serialized, origin: origin });
    \\      if (!result || result.error) throw mapNativeError(result);
    \\      return buildAssertionResponse(result, serialized.challenge, origin);
    \\    } catch (e) { throw e; }
    \\  };
    \\
    \\  if (typeof PublicKeyCredential === 'undefined') {
    \\    window.PublicKeyCredential = function() { throw new TypeError('Illegal constructor'); };
    \\    window.PublicKeyCredential.prototype = {};
    \\  }
    \\  PublicKeyCredential.isUserVerifyingPlatformAuthenticatorAvailable = async function() { return false; };
    \\  PublicKeyCredential.isConditionalMediationAvailable = async function() { return false; };
    \\
    \\  console.log('[cmux-webauthn] bridge installed');
    \\  return true;
    \\})()
;
