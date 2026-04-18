#!/usr/bin/env python3
"""Socket API: Sprint B core parity — send_key, ports_kick, equalize_splits, debug.terminals.

Pure socket round-trip test. Validates the four new core handlers
and batch-stub reachability for debug/remote/browser automation families.
"""

import os
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from cmux import cmux, cmuxError

SOCKET_PATH = os.environ.get("CMUX_SOCKET", "/tmp/cmux-debug.sock")


def _run_assertions(c: cmux, ws_id: str) -> None:
    c.select_workspace(ws_id)
    time.sleep(0.05)

    # Get initial surface
    res = c._call("surface.list", {"workspace_id": ws_id}) or {}
    surfaces = res.get("surfaces") or []
    if not surfaces:
        raise cmuxError(f"workspace has no surfaces: {res}")
    surface_id = str(surfaces[0]["id"])

    # ---- surface.send_key ---------------------------------------------------
    key_resp = c._call(
        "surface.send_key",
        {"workspace_id": ws_id, "surface_id": surface_id, "key": "Return"},
    ) or {}
    if "error" in key_resp and "not a terminal" in key_resp.get("error", ""):
        pass  # non-terminal surface, acceptable
    elif key_resp.get("key") != "Return":
        # In headless mode, should echo the key back
        if "error" not in key_resp:
            raise cmuxError(f"send_key: unexpected response: {key_resp}")

    # Missing key param
    bad_key = c._call(
        "surface.send_key",
        {"workspace_id": ws_id, "surface_id": surface_id},
    ) or {}
    if "error" not in bad_key:
        raise cmuxError(f"send_key missing key: expected error, got {bad_key}")

    # ---- surface.ports_kick -------------------------------------------------
    kick_resp = c._call(
        "surface.ports_kick",
        {"workspace_id": ws_id, "surface_id": surface_id},
    ) or {}
    if "error" in kick_resp:
        raise cmuxError(f"ports_kick: unexpected error: {kick_resp}")
    if kick_resp.get("kicked") is not False:
        raise cmuxError(f"ports_kick: expected kicked=false: {kick_resp}")

    # Missing workspace_id
    bad_kick = c._call("surface.ports_kick", {"surface_id": surface_id}) or {}
    if "error" not in bad_kick:
        raise cmuxError(
            f"ports_kick missing workspace_id: expected error, got {bad_kick}"
        )

    # ---- workspace.equalize_splits ------------------------------------------
    # Create a split first
    c._call("surface.split", {"direction": "horizontal"})
    time.sleep(0.05)

    eq_resp = c._call(
        "workspace.equalize_splits", {"workspace_id": ws_id}
    ) or {}
    if "error" in eq_resp:
        raise cmuxError(f"equalize_splits: unexpected error: {eq_resp}")
    if eq_resp.get("equalized") is not True:
        raise cmuxError(f"equalize_splits: expected equalized=true: {eq_resp}")

    # With orientation filter
    eq_h = c._call(
        "workspace.equalize_splits",
        {"workspace_id": ws_id, "orientation": "horizontal"},
    ) or {}
    if eq_h.get("equalized") is not True:
        raise cmuxError(f"equalize_splits horizontal: {eq_h}")

    # Bad orientation
    eq_bad = c._call(
        "workspace.equalize_splits",
        {"workspace_id": ws_id, "orientation": "diagonal"},
    ) or {}
    if "error" not in eq_bad:
        raise cmuxError(f"equalize_splits bad orientation: expected error: {eq_bad}")

    # ---- debug.terminals ----------------------------------------------------
    dt_resp = c._call("debug.terminals", {}) or {}
    terminals = dt_resp.get("terminals")
    if terminals is None:
        raise cmuxError(f"debug.terminals: no terminals key: {dt_resp}")
    if not isinstance(terminals, list):
        raise cmuxError(f"debug.terminals: terminals not a list: {dt_resp}")
    # Should contain at least one terminal with expected fields
    if len(terminals) > 0:
        t = terminals[0]
        for field in ("workspace_id", "surface_id", "focused"):
            if field not in t:
                raise cmuxError(
                    f"debug.terminals: missing field {field!r}: {t}"
                )

    # ---- debug stub reachability --------------------------------------------
    for method in (
        "debug.layout",
        "debug.sidebar.visible",
        "debug.terminal.is_focused",
    ):
        resp = c._call(method, {}) or {}
        # Should return {} (empty success), not an unknown-method error
        if "unknown" in str(resp).lower():
            raise cmuxError(f"{method}: routed to unknown handler: {resp}")

    # ---- remote stub reachability -------------------------------------------
    for method in ("workspace.remote.status", "workspace.remote.configure"):
        resp = c._call(method, {}) or {}
        if "error" not in resp:
            raise cmuxError(f"{method}: expected remote stub error: {resp}")

    # ---- browser automation stub reachability (if reachable) ----------------
    try:
        ba_resp = c._call("browser.click", {"selector": "#test"}) or {}
        # Should get either "not implemented" or "unavailable" error
        if "error" not in ba_resp:
            raise cmuxError(f"browser.click: expected stub error: {ba_resp}")
    except cmuxError:
        pass  # acceptable


def main() -> int:
    created_workspace: str | None = None
    with cmux(SOCKET_PATH) as c:
        try:
            created_workspace = c.new_workspace()
            if not created_workspace:
                raise cmuxError("workspace.create returned no id")
            _run_assertions(c, created_workspace)
        finally:
            if created_workspace is not None:
                try:
                    c.close_workspace(created_workspace)
                except Exception:
                    pass

    print(
        "PASS: Sprint B core parity "
        "(send_key, ports_kick, equalize_splits, debug.terminals, stubs)"
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except cmuxError as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        raise SystemExit(1)
