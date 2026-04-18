#!/usr/bin/env python3
"""Socket API: workspace.action — rename / clear_name / pin / unpin / set_color /
clear_color / move_up / move_down / move_top / close_above / close_below /
close_others / unimplemented surface / unsupported action.

Pure socket round-trip test — no GUI, no CLI binary, no platform-specific
filesystem assumptions. Designed to pass on the Linux daemon (CMUX_NO_SURFACE=1
headless) and macOS daemons that share the v2 workspace.action contract.
"""

import os
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from cmux import cmux, cmuxError

SOCKET_PATH = os.environ.get("CMUX_SOCKET", "/tmp/cmux-debug.sock")


def _ws_rows(c: cmux) -> list[dict]:
    res = c._call("workspace.list", {}) or {}
    return list(res.get("workspaces") or [])


def _ws_ids(c: cmux) -> list[str]:
    return [str(r.get("id")) for r in _ws_rows(c)]


def _find_ws(c: cmux, ws_id: str) -> dict:
    for row in _ws_rows(c):
        if str(row.get("id")) == ws_id:
            return row
    raise cmuxError(f"workspace {ws_id} not found in workspace.list")


def _action(c: cmux, ws_id: str | None, action: str, **extra) -> dict:
    params: dict = {"action": action}
    if ws_id is not None:
        params["workspace_id"] = ws_id
    params.update(extra)
    return c._call("workspace.action", params) or {}


def _pin(c: cmux, ws_id: str) -> None:
    _action(c, ws_id, "pin")


def _unpin(c: cmux, ws_id: str) -> None:
    _action(c, ws_id, "unpin")


def _safe_close(c: cmux, ws_id: str) -> None:
    try:
        c.close_workspace(ws_id)
    except cmuxError:
        pass


def main() -> int:
    created: list[str] = []
    pinned: list[str] = []  # workspaces we explicitly pinned (for cleanup)
    with cmux(SOCKET_PATH) as c:
        try:
            # ─── Snapshot baseline workspaces (so we can leave them alone) ──
            baseline_ids = _ws_ids(c)

            # ─── Property mutations on a single dedicated workspace ────────
            ws_props = c.new_workspace()
            if not ws_props:
                raise cmuxError("workspace.create returned empty id")
            created.append(ws_props)
            time.sleep(0.05)

            # rename → reflected in workspace.list
            unique_title = f"action-rename-{int(time.time() * 1000) % 100000}"
            resp = _action(c, ws_props, "rename", title=unique_title)
            if resp.get("action") != "rename" or str(resp.get("title")) != unique_title:
                raise cmuxError(f"rename: bad response: {resp}")
            if str(_find_ws(c, ws_props).get("title")) != unique_title:
                raise cmuxError("rename: not reflected in workspace.list")

            # clear_name → title falls back, must change
            resp = _action(c, ws_props, "clear_name")
            if resp.get("action") != "clear_name":
                raise cmuxError(f"clear_name: bad response: {resp}")
            if str(_find_ws(c, ws_props).get("title")) == unique_title:
                raise cmuxError("clear_name: title still matches custom value")

            # pin / unpin (response-only; workspace.list omits is_pinned)
            resp = _action(c, ws_props, "pin")
            if resp.get("action") != "pin" or resp.get("pinned") is not True:
                raise cmuxError(f"pin: bad response: {resp}")
            resp = _action(c, ws_props, "unpin")
            if resp.get("action") != "unpin" or resp.get("pinned") is not False:
                raise cmuxError(f"unpin: bad response: {resp}")

            # set_color / clear_color (response-only echo)
            resp = _action(c, ws_props, "set_color", color="#ff8800")
            if resp.get("action") != "set_color" or str(resp.get("color")) != "#ff8800":
                raise cmuxError(f"set_color: bad response: {resp}")
            resp = _action(c, ws_props, "clear_color")
            if resp.get("action") != "clear_color":
                raise cmuxError(f"clear_color: bad response: {resp}")

            # ─── Recognized-but-unimplemented actions on Linux ─────────────
            for action in ("set_description", "clear_description", "mark_read", "mark_unread"):
                params: dict = {"workspace_id": ws_props, "action": action}
                if action == "set_description":
                    params["description"] = "x"
                resp = c._call("workspace.action", params) or {}
                err = str(resp.get("error", ""))
                if "not implemented" not in err.lower():
                    raise cmuxError(f"{action}: expected 'not implemented' error, got {resp}")

            # ─── Unsupported action returns a structured error ─────────────
            resp = _action(c, ws_props, "definitely-not-a-real-action")
            if "error" not in resp:
                raise cmuxError(f"unsupported action: expected error in body, got {resp}")

            # ─── Move actions on a fresh trio ──────────────────────────────
            ws_a = c.new_workspace()
            time.sleep(0.05)
            ws_b = c.new_workspace()
            time.sleep(0.05)
            ws_c = c.new_workspace()
            time.sleep(0.05)
            created.extend([ws_a, ws_b, ws_c])

            ids_pre_move = _ws_ids(c)
            idx_b = ids_pre_move.index(ws_b)

            resp = _action(c, ws_b, "move_up")
            if resp.get("action") != "move_up":
                raise cmuxError(f"move_up: bad response: {resp}")
            ids_after_up = _ws_ids(c)
            expected_after_up = max(0, idx_b - 1)
            if ids_after_up.index(ws_b) != expected_after_up:
                raise cmuxError(
                    f"move_up: ws_b at {ids_after_up.index(ws_b)}, "
                    f"expected {expected_after_up}; ids={ids_after_up}"
                )

            idx_b_now = ids_after_up.index(ws_b)
            resp = _action(c, ws_b, "move_down")
            if resp.get("action") != "move_down":
                raise cmuxError(f"move_down: bad response: {resp}")
            ids_after_down = _ws_ids(c)
            if ids_after_down.index(ws_b) != idx_b_now + 1:
                raise cmuxError(
                    f"move_down: ws_b not advanced; ids={ids_after_down}"
                )

            resp = _action(c, ws_c, "move_top")
            if resp.get("action") != "move_top":
                raise cmuxError(f"move_top: bad response: {resp}")
            ids_after_top = _ws_ids(c)
            if ids_after_top.index(ws_c) != 0:
                raise cmuxError(
                    f"move_top: ws_c not first; ids={ids_after_top}"
                )

            # ─── Close actions ─────────────────────────────────────────────
            # Pin baselines + ws_props so close_above/below/others only kills
            # the workspaces this test creates for the close section.
            for bid in baseline_ids:
                _pin(c, bid)
                pinned.append(bid)
            _pin(c, ws_props)
            pinned.append(ws_props)

            # Drop the move-test workspaces first so the layout is predictable.
            for wid in (ws_c, ws_b, ws_a):
                _safe_close(c, wid)
                if wid in created:
                    created.remove(wid)
            time.sleep(0.05)

            # close_above: append two unpinned + an operator on top of pinned baseline
            above1 = c.new_workspace()
            time.sleep(0.05)
            above2 = c.new_workspace()
            time.sleep(0.05)
            op_above = c.new_workspace()
            time.sleep(0.05)
            created.extend([above1, above2, op_above])

            ids_pre_above = _ws_ids(c)
            op_idx = ids_pre_above.index(op_above)
            if not (
                ids_pre_above.index(above1) < op_idx
                and ids_pre_above.index(above2) < op_idx
            ):
                raise cmuxError(
                    f"close_above setup: above1/above2 not above op; ids={ids_pre_above}"
                )

            resp = _action(c, op_above, "close_above")
            if resp.get("action") != "close_above":
                raise cmuxError(f"close_above: bad response: {resp}")
            ids_after_above = _ws_ids(c)
            for closed in (above1, above2):
                if closed in ids_after_above:
                    raise cmuxError(f"close_above: {closed} still present")
                if closed in created:
                    created.remove(closed)
            if op_above not in ids_after_above:
                raise cmuxError("close_above: op disappeared")
            for protected in baseline_ids + [ws_props]:
                if protected not in ids_after_above:
                    raise cmuxError(
                        f"close_above: pinned workspace {protected} disappeared"
                    )

            # close_below: append two unpinned below the operator
            below1 = c.new_workspace()
            time.sleep(0.05)
            below2 = c.new_workspace()
            time.sleep(0.05)
            created.extend([below1, below2])

            ids_pre_below = _ws_ids(c)
            op_idx_b = ids_pre_below.index(op_above)
            if not (
                ids_pre_below.index(below1) > op_idx_b
                and ids_pre_below.index(below2) > op_idx_b
            ):
                raise cmuxError(
                    f"close_below setup: below1/below2 not below op; ids={ids_pre_below}"
                )

            resp = _action(c, op_above, "close_below")
            if resp.get("action") != "close_below":
                raise cmuxError(f"close_below: bad response: {resp}")
            ids_after_below = _ws_ids(c)
            for closed in (below1, below2):
                if closed in ids_after_below:
                    raise cmuxError(f"close_below: {closed} still present")
                if closed in created:
                    created.remove(closed)
            if op_above not in ids_after_below:
                raise cmuxError("close_below: op disappeared")

            # close_others: a few more unpinned that should all vanish
            other1 = c.new_workspace()
            time.sleep(0.05)
            other2 = c.new_workspace()
            time.sleep(0.05)
            other3 = c.new_workspace()
            time.sleep(0.05)
            created.extend([other1, other2, other3])

            resp = _action(c, op_above, "close_others")
            if resp.get("action") != "close_others":
                raise cmuxError(f"close_others: bad response: {resp}")
            ids_after_others = _ws_ids(c)
            for closed in (other1, other2, other3):
                if closed in ids_after_others:
                    raise cmuxError(f"close_others: {closed} still present")
                if closed in created:
                    created.remove(closed)
            if op_above not in ids_after_others:
                raise cmuxError("close_others: op disappeared")
            for protected in baseline_ids + [ws_props]:
                if protected not in ids_after_others:
                    raise cmuxError(
                        f"close_others: pinned workspace {protected} disappeared"
                    )

            # ─── Focused-workspace fallback (no workspace_id provided) ─────
            # Select op_above so the daemon's "current" picks it up.
            c.select_workspace(op_above)
            time.sleep(0.05)
            resp = c._call("workspace.action", {"action": "rename", "title": "fallback"}) or {}
            if resp.get("action") != "rename":
                raise cmuxError(f"focused-ws fallback: bad response: {resp}")
            if str(resp.get("workspace_id")).lower() != str(op_above).lower():
                raise cmuxError(
                    f"focused-ws fallback: rename hit wrong workspace: {resp}"
                )
            # Drop the synthetic title so cleanup leaves no traces.
            c._call(
                "workspace.action",
                {"workspace_id": op_above, "action": "clear_name"},
            )

        finally:
            # ─── Cleanup: unpin everything we pinned, then close created ──
            for wid in pinned:
                try:
                    _unpin(c, wid)
                except Exception:
                    pass
            pinned.clear()
            for wid in list(created):
                _safe_close(c, wid)
            created.clear()

    print(
        "PASS: workspace.action — rename / clear_name / pin / unpin / set_color / "
        "clear_color / move_up / move_down / move_top / close_above / close_below / "
        "close_others / unimplemented / unsupported"
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except cmuxError as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        raise SystemExit(1)
