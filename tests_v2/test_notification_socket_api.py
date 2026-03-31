#!/usr/bin/env python3
"""Socket API: notification create/list/clear and app focus override."""

import os
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from cmux import cmux, cmuxError

SOCKET_PATH = os.environ.get("CMUX_SOCKET", "/tmp/cmux-debug.sock")


def main() -> int:
    with cmux(SOCKET_PATH) as c:
        # Clear any prior state
        c.clear_notifications()
        c.set_app_focus(None)

        # Test 1: notification.create stores a notification
        c.set_app_focus(False)  # inactive — should NOT suppress
        c._call("notification.create", {"title": "test-notif"})
        time.sleep(0.05)
        items = c.list_notifications()
        if len(items) < 1:
            raise cmuxError(f"Expected >= 1 notification after create, got {len(items)}")
        if items[0].get("title") != "test-notif":
            raise cmuxError(f"Expected title 'test-notif', got {items[0]}")
        if items[0].get("is_read") is not False:
            raise cmuxError(f"Expected is_read=false, got {items[0]}")

        # Test 2: notification.clear empties the list
        c.clear_notifications()
        items = c.list_notifications()
        if len(items) != 0:
            raise cmuxError(f"Expected 0 after clear, got {len(items)}")

        # Test 3: suppress when app focused
        c.set_app_focus(True)
        c._call("notification.create", {"title": "suppressed"})
        items = c.list_notifications()
        if len(items) != 0:
            raise cmuxError(f"Expected suppression when focused, got {len(items)}")

        # Test 4: app.focus_override.set clear restores default
        c.set_app_focus(None)
        c.set_app_focus(False)
        c._call("notification.create", {"title": "after-clear"})
        items = c.list_notifications()
        if len(items) < 1:
            raise cmuxError(f"Expected notification after clearing override, got {len(items)}")

        # Cleanup
        c.clear_notifications()
        c.set_app_focus(None)

    print("PASS: notification socket API (create, list, clear, suppress)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
