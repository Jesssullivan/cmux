/// Keychain integration via zig-keychain (libsecret on Linux).
///
/// Provides credential storage for WebAuthn tokens, session secrets,
/// and user preferences that need secure persistence.
/// Maps to macOS Security.framework SecItem calls.
///
/// Uses the C bridge in vendor/zig-keychain/src/libsecret_bridge.c
/// since Zig cannot call C varargs functions directly.

const std = @import("std");

const log = std.log.scoped(.keychain);

/// Store a secret in the system keychain.
pub fn store(service: []const u8, account: []const u8, data: []const u8) bool {
    const result = libsecret_bridge_store(
        service.ptr,
        account.ptr,
        data.ptr,
        data.len,
    );
    if (result != 0) {
        log.warn("Failed to store secret for {s}/{s}: error {d}", .{ service, account, result });
        return false;
    }
    return true;
}

/// Look up a secret from the system keychain.
/// Returns the secret data or null if not found.
pub fn lookup(alloc: std.mem.Allocator, service: []const u8, account: []const u8) ?[]const u8 {
    var buf: [4096]u8 = undefined;
    const len = libsecret_bridge_lookup(
        service.ptr,
        account.ptr,
        &buf,
        buf.len,
    );
    if (len <= 0) return null;

    return alloc.dupe(u8, buf[0..@intCast(len)]) catch null;
}

/// Delete a secret from the system keychain.
pub fn delete(service: []const u8, account: []const u8) bool {
    const result = libsecret_bridge_delete(
        service.ptr,
        account.ptr,
    );
    return result == 0;
}

// C FFI bridge functions (from vendor/zig-keychain/src/libsecret_bridge.c)
extern fn libsecret_bridge_store(
    service: [*:0]const u8,
    account: [*:0]const u8,
    data: [*]const u8,
    data_len: usize,
) c_int;

extern fn libsecret_bridge_lookup(
    service: [*:0]const u8,
    account: [*:0]const u8,
    out_buf: [*]u8,
    out_capacity: usize,
) c_int;

extern fn libsecret_bridge_delete(
    service: [*:0]const u8,
    account: [*:0]const u8,
) c_int;
