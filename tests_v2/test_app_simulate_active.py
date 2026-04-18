#!/usr/bin/env python3
"""Socket API: app.simulate_active is accepted as a no-op on Linux.

The macOS implementation triggers applicationDidBecomeActive on NSApp so
test harnesses can drive focus-restoration code paths. Linux has no
equivalent app-active lifecycle, so we just accept the call and return
{}, letting cross-platform tests run unmodified.

This test verifies:
  1. app.simulate_active returns an empty-object result
  2. Repeated calls remain idempotent
  3. Spurious params are accepted (forward-compat with macOS additions)
  4. A subsequent system.ping still works (the call did not poison state)
"""

import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from cmux import cmux, cmuxError

SOCKET_PATH = os.environ.get("CMUX_SOCKET", "/tmp/cmux-debug.sock")


def main() -> int:
    with cmux(SOCKET_PATH) as c:
        for attempt in range(3):
            res = c._call("app.simulate_active")
            if res != {}:
                raise cmuxError(
                    f"attempt {attempt}: expected empty-object result, got {res!r}"
                )

        # Spurious params should be ignored, not rejected
        res2 = c._call(
            "app.simulate_active",
            {"window_id": "ignored", "extra": True},
        )
        if res2 != {}:
            raise cmuxError(f"spurious-params call returned {res2!r}")

        # Daemon is still healthy after the no-op stream
        ping = c._call("system.ping")
        if not isinstance(ping, dict):
            raise cmuxError(f"system.ping after simulate_active returned {ping!r}")

    print("PASS: app.simulate_active no-op (idempotent, ignores spurious params)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
