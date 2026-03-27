// libctap2 — Portable CTAP2/FIDO2 over USB HID.
// C API for Swift/ObjC interop via bridging header.
//
// All functions are blocking (with timeouts) and thread-safe.
// Result data is CBOR-encoded CTAP2 responses written to caller buffers.

#ifndef CTAP2_H
#define CTAP2_H

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

// Status codes (negative = library error, positive = CTAP2 device status)
#define CTAP2_OK                    0
#define CTAP2_ERR_NO_DEVICE        -1
#define CTAP2_ERR_TIMEOUT          -2
#define CTAP2_ERR_PROTOCOL         -3
#define CTAP2_ERR_BUFFER_TOO_SMALL -4
#define CTAP2_ERR_OPEN_FAILED      -5
#define CTAP2_ERR_WRITE_FAILED     -6
#define CTAP2_ERR_READ_FAILED      -7
#define CTAP2_ERR_CBOR             -8
#define CTAP2_ERR_DEVICE           -9
#define CTAP2_ERR_PIN             -10

// Get the number of connected FIDO2 devices.
int ctap2_device_count(void);

// ─── Raw response functions ─────────────────────────────────
// These return the raw CTAP2 response (status byte + CBOR) in result_buf.
// The caller is responsible for parsing the CBOR response.

// Perform authenticatorMakeCredential.
// client_data_hash must be 32 bytes (SHA-256 of clientDataJSON).
// Returns bytes written to result_buf, or negative error code.
// result_buf contains the raw CTAP2 response (status byte + CBOR).
int ctap2_make_credential(
    const uint8_t *client_data_hash,     // 32 bytes
    const char *rp_id,                    // null-terminated
    const char *rp_name,                  // null-terminated
    const uint8_t *user_id,
    size_t user_id_len,
    const char *user_name,               // null-terminated
    const char *user_display_name,       // null-terminated
    const int32_t *alg_ids,              // COSE algorithm IDs
    size_t alg_count,
    bool resident_key,
    uint8_t *result_buf,
    size_t result_buf_len
);

// Perform authenticatorGetAssertion.
// client_data_hash must be 32 bytes.
// allow_list_ids is an array of pointers to credential IDs.
// allow_list_id_lens is an array of lengths for each credential ID.
// Returns bytes written to result_buf, or negative error code.
int ctap2_get_assertion(
    const uint8_t *client_data_hash,     // 32 bytes
    const char *rp_id,                    // null-terminated
    const uint8_t *const *allow_list_ids,
    const size_t *allow_list_id_lens,
    size_t allow_list_count,
    uint8_t *result_buf,
    size_t result_buf_len
);

// Perform authenticatorGetInfo.
// Returns bytes written to result_buf, or negative error code.
// result_buf contains the raw CTAP2 response (status byte + CBOR).
int ctap2_get_info(
    uint8_t *result_buf,
    size_t result_buf_len
);

// ─── Parsed response functions ──────────────────────────────
// These perform the CTAP2 command AND parse the CBOR response,
// returning structured fields in caller-provided output buffers.
//
// Return values:
//   CTAP2_OK (0)   = success, output fields populated
//   > 0            = CTAP2 device status byte (e.g. 0x27 = user denied)
//   < 0            = library error code (CTAP2_ERR_*)

// Combined: send makeCredential + parse response.
// Output buffers should be at least 1024 bytes for credential_id,
// and 4096 bytes for attestation_object.
int ctap2_make_credential_parsed(
    const uint8_t *client_data_hash,     // 32 bytes
    const char *rp_id,                    // null-terminated
    const char *rp_name,                  // null-terminated
    const uint8_t *user_id,
    size_t user_id_len,
    const char *user_name,               // null-terminated
    const char *user_display_name,       // null-terminated
    const int32_t *alg_ids,              // COSE algorithm IDs
    size_t alg_count,
    bool resident_key,
    // Output fields:
    uint8_t *out_credential_id,
    size_t *out_credential_id_len,
    uint8_t *out_attestation_object,
    size_t *out_attestation_object_len
);

// Combined: send getAssertion + parse response.
// Output buffers should be at least 1024 bytes each.
// allow_list_ids/allow_list_id_lens can be NULL when allow_list_count is 0.
int ctap2_get_assertion_parsed(
    const uint8_t *client_data_hash,     // 32 bytes
    const char *rp_id,                    // null-terminated
    const uint8_t *const *allow_list_ids,    // nullable
    const size_t *allow_list_id_lens,        // nullable
    size_t allow_list_count,
    // Output fields:
    uint8_t *out_credential_id,
    size_t *out_credential_id_len,
    uint8_t *out_auth_data,
    size_t *out_auth_data_len,
    uint8_t *out_signature,
    size_t *out_signature_len,
    uint8_t *out_user_handle,
    size_t *out_user_handle_len
);

// ─── Pure parsing functions ─────────────────────────────────
// Parse raw CTAP2 response bytes without any HID I/O.
// Useful when you already have the raw response from ctap2_make_credential
// or ctap2_get_assertion and want to extract structured fields.

// Parse a raw MakeCredential response (status byte + CBOR attestation object).
int ctap2_parse_make_credential_response(
    const uint8_t *response_data,
    size_t response_len,
    uint8_t *out_credential_id,
    size_t *out_credential_id_len,
    uint8_t *out_attestation_object,
    size_t *out_attestation_object_len
);

// Parse a raw GetAssertion response (status byte + CBOR).
// fallback_cred_id: credential ID to use when the response omits key 1
// (CTAP2 spec: single-entry allowList). Pass NULL/0 if no fallback.
int ctap2_parse_get_assertion_response(
    const uint8_t *response_data,
    size_t response_len,
    const uint8_t *fallback_cred_id,     // nullable
    size_t fallback_cred_id_len,
    uint8_t *out_credential_id,
    size_t *out_credential_id_len,
    uint8_t *out_auth_data,
    size_t *out_auth_data_len,
    uint8_t *out_signature,
    size_t *out_signature_len,
    uint8_t *out_user_handle,
    size_t *out_user_handle_len
);

// ─── PIN protocol functions ─────────────────────────────────
// CTAP2 Client PIN protocol v2 for YubiKeys with a PIN set.
// These implement the authenticatorClientPIN (0x06) command.

// Get PIN retry count from the authenticator.
// out_retries: receives the number of remaining PIN retries.
// Returns CTAP2_OK on success, or negative error code.
int ctap2_get_pin_retries(int *out_retries);

// Get a PIN token for authentication.
// Performs the full PIN protocol v2 handshake (key agreement + ECDH +
// PIN encryption) and returns a decrypted 32-byte PIN token.
//
// pin: null-terminated UTF-8 PIN string.
// out_pin_token: receives the 32-byte decrypted PIN token.
// out_pin_token_len: must be >= 32.
//
// Returns CTAP2_OK on success, positive CTAP2 status byte on device
// error (e.g. 0x31 = wrong PIN), or negative error code.
int ctap2_get_pin_token(
    const char *pin,
    uint8_t *out_pin_token,
    size_t out_pin_token_len
);

// ─── PIN-authenticated parsed functions ─────────────────────
// Same as the parsed functions above, but with optional PIN auth.
// Pass pin_token=NULL, pin_protocol=0 for no PIN authentication.
// Pass pin_token=<32-byte token from ctap2_get_pin_token>, pin_protocol=2
// to include pinAuth in the CTAP2 command.

int ctap2_make_credential_with_pin(
    const uint8_t *client_data_hash,     // 32 bytes
    const char *rp_id,                    // null-terminated
    const char *rp_name,                  // null-terminated
    const uint8_t *user_id,
    size_t user_id_len,
    const char *user_name,               // null-terminated
    const char *user_display_name,       // null-terminated
    const int32_t *alg_ids,              // COSE algorithm IDs
    size_t alg_count,
    bool resident_key,
    const uint8_t *pin_token,            // 32 bytes, or NULL for no PIN
    uint8_t pin_protocol,                // 0 = no PIN, 2 = PIN protocol v2
    // Output fields:
    uint8_t *out_credential_id,
    size_t *out_credential_id_len,
    uint8_t *out_attestation_object,
    size_t *out_attestation_object_len
);

int ctap2_get_assertion_with_pin(
    const uint8_t *client_data_hash,     // 32 bytes
    const char *rp_id,                    // null-terminated
    const uint8_t *const *allow_list_ids,    // nullable
    const size_t *allow_list_id_lens,        // nullable
    size_t allow_list_count,
    const uint8_t *pin_token,            // 32 bytes, or NULL for no PIN
    uint8_t pin_protocol,                // 0 = no PIN, 2 = PIN protocol v2
    // Output fields:
    uint8_t *out_credential_id,
    size_t *out_credential_id_len,
    uint8_t *out_auth_data,
    size_t *out_auth_data_len,
    uint8_t *out_signature,
    size_t *out_signature_len,
    uint8_t *out_user_handle,
    size_t *out_user_handle_len
);

// ─── Keepalive callback variants ─────────────────────────────
// Same as raw functions but with a keepalive callback invoked when
// the device sends CTAPHID_KEEPALIVE (e.g., waiting for user touch).
// Status byte values: 1 = processing, 2 = user presence needed.

typedef void (*ctap2_keepalive_callback_t)(uint8_t status);

int ctap2_make_credential_with_keepalive(
    const uint8_t *client_data_hash,
    const char *rp_id,
    const char *rp_name,
    const uint8_t *user_id,
    size_t user_id_len,
    const char *user_name,
    const char *user_display_name,
    const int32_t *alg_ids,
    size_t alg_count,
    bool resident_key,
    ctap2_keepalive_callback_t keepalive_cb,
    uint8_t *result_buf,
    size_t result_buf_len
);

int ctap2_get_assertion_with_keepalive(
    const uint8_t *client_data_hash,
    const char *rp_id,
    const uint8_t *const *allow_list_ids,
    const size_t *allow_list_id_lens,
    size_t allow_list_count,
    ctap2_keepalive_callback_t keepalive_cb,
    uint8_t *result_buf,
    size_t result_buf_len
);

// ─── Utility functions ──────────────────────────────────────

// Map a CTAP2 status byte to a human-readable error message string.
// Returns a pointer to a static null-terminated string.
const char *ctap2_status_message(uint8_t status);

// Debug: get the last IOReturn error code from HID operations.
int ctap2_debug_last_ioreturn(void);

#ifdef __cplusplus
}
#endif

#endif // CTAP2_H
