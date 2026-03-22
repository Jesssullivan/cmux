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

// Status codes
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

// Get the number of connected FIDO2 devices.
int ctap2_device_count(void);

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

#ifdef __cplusplus
}
#endif

#endif // CTAP2_H
