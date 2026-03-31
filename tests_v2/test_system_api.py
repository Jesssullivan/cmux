#!/usr/bin/env python3
"""Socket API: system.ping, system.version, system.identify, system.capabilities."""

import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from cmux import cmux, cmuxError

SOCKET_PATH = os.environ.get("CMUX_SOCKET", "/tmp/cmux-debug.sock")


def main() -> int:
    with cmux(SOCKET_PATH) as c:
        # system.ping
        res = c._call("system.ping")
        if not res or res.get("pong") is not True:
            raise cmuxError(f"system.ping: expected pong=true, got {res}")

        # system.version
        ver = c._call("system.version")
        if not ver or not ver.get("version"):
            raise cmuxError(f"system.version: missing version field: {ver}")

        # system.identify
        ident = c.identify()
        if not isinstance(ident, dict):
            raise cmuxError(f"system.identify: expected dict, got {type(ident).__name__}")
        focused = ident.get("focused")
        if not isinstance(focused, dict) or "workspace_id" not in focused:
            raise cmuxError(f"system.identify: expected focused.workspace_id, got {ident}")

        # system.capabilities
        caps = c._call("system.capabilities")
        if not caps or caps.get("workspaces") is not True:
            raise cmuxError(f"system.capabilities: expected workspaces=true, got {caps}")
        if caps.get("splits") is not True:
            raise cmuxError(f"system.capabilities: expected splits=true, got {caps}")

    print("PASS: system API (ping, version, identify, capabilities)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
