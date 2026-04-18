#!/usr/bin/env python3
"""Socket API: auth.login round-trip on Linux.

The Linux build does not gate the v2 socket behind a password — there is no
keychain/credential store wired up yet. We still implement auth.login so that
the v2 protocol surface matches macOS: clients that probe the gate get a
deterministic {authenticated:true, required:false} reply instead of
method_not_found, and v1 password handshakes degrade gracefully.

This test exercises three angles:
  1. No-params call returns the canonical shape.
  2. Unknown params (password=anything) are accepted, not rejected.
  3. Repeated calls remain idempotent and never trigger an auth_required gate.
"""

import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from cmux import cmux, cmuxError

SOCKET_PATH = os.environ.get("CMUX_SOCKET", "/tmp/cmux-debug.sock")


def _assert_shape(label: str, res) -> None:
    if not isinstance(res, dict):
        raise cmuxError(f"{label}: expected dict, got {type(res).__name__}: {res!r}")
    if res.get("authenticated") is not True:
        raise cmuxError(f"{label}: expected authenticated=true, got {res!r}")
    if res.get("required") is not False:
        raise cmuxError(f"{label}: expected required=false, got {res!r}")


def main() -> int:
    with cmux(SOCKET_PATH) as c:
        # 1) No params at all — server must accept.
        res = c._call("auth.login")
        _assert_shape("auth.login (no params)", res)

        # 2) Spurious password params should not break the no-op gate.
        res = c._call("auth.login", {"password": "ignored-on-linux"})
        _assert_shape("auth.login (password param)", res)

        # 3) Re-calling auth.login is safe and idempotent — no auth_required
        #    error and shape is stable across calls.
        res = c._call("auth.login", {})
        _assert_shape("auth.login (empty params)", res)

        # 4) Other RPCs continue to work without an auth handshake — the gate
        #    must not be implicitly enabled by any of the calls above.
        ping = c._call("system.ping")
        if not isinstance(ping, dict) or ping.get("pong") is not True:
            raise cmuxError(f"system.ping after auth.login failed: {ping!r}")

    print("PASS: auth.login (no-op gate, idempotent, shape stable)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
