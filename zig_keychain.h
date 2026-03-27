#ifndef ZIG_KEYCHAIN_H
#define ZIG_KEYCHAIN_H

#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ── Generic Password Operations ─────────────────────────────────────── */

/**
 * Store a generic password in the system keychain/secret store.
 *
 * @param service      Service name (e.g., "Chrome Safe Storage").
 * @param service_len  Length of service string.
 * @param account      Account name.
 * @param account_len  Length of account string.
 * @param data         Secret data to store.
 * @param data_len     Length of secret data.
 * @return             0 on success, -1 on failure.
 *
 * macOS: SecItemAdd (kSecClassGenericPassword)
 * Linux: libsecret secret_service_store_sync (org.freedesktop.secrets)
 */
int zig_keychain_store(
    const char *service, size_t service_len,
    const char *account, size_t account_len,
    const uint8_t *data, size_t data_len
);

/**
 * Look up a generic password from the system keychain/secret store.
 *
 * @param service      Service name to match.
 * @param service_len  Length of service string.
 * @param account      Account name to match.
 * @param account_len  Length of account string.
 * @param out          Output buffer for the secret data.
 * @param out_capacity Capacity of output buffer.
 * @return             Number of bytes written on success, -1 on not found, -2 on error.
 *
 * macOS: SecItemCopyMatching (kSecClassGenericPassword, kSecReturnData)
 * Linux: libsecret secret_service_lookup_sync
 */
int zig_keychain_lookup(
    const char *service, size_t service_len,
    const char *account, size_t account_len,
    uint8_t *out, size_t out_capacity
);

/**
 * Delete a generic password from the system keychain/secret store.
 *
 * @param service      Service name to match.
 * @param service_len  Length of service string.
 * @param account      Account name to match.
 * @param account_len  Length of account string.
 * @return             0 on success (including not-found), -1 on error.
 *
 * macOS: SecItemDelete
 * Linux: libsecret secret_service_clear_sync
 */
int zig_keychain_delete(
    const char *service, size_t service_len,
    const char *account, size_t account_len
);

/* zig_keychain_search is declared in the upstream header but not yet
 * implemented in the Zig FFI. Once the implementation lands, uncomment:
 *
 * int zig_keychain_search(
 *     const char *account, size_t account_len,
 *     char *out, size_t out_capacity
 * );
 */

#ifdef __cplusplus
}
#endif

#endif /* ZIG_KEYCHAIN_H */
