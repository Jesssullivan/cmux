#!/usr/bin/env python3
"""Socket API: surface.action close_left / close_right / close_others.

Verifies relative-close actions remove the correct sibling surfaces,
preserve the anchor, skip pinned panels, and return the right counts.
Runs against the Linux daemon in CMUX_NO_SURFACE headless mode.
"""

import os
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from cmux import cmux, cmuxError

SOCKET_PATH = os.environ.get("CMUX_SOCKET", "/tmp/cmux-debug.sock")


def _surface_ids(c: cmux, ws: str) -> list[str]:
    """Return ordered surface IDs for the workspace."""
    res = c._call("surface.list", {"workspace_id": ws}) or {}
    surfaces = res.get("surfaces") or []
    return [str(s["id"]) for s in surfaces]


def _add_surfaces(c: cmux, n: int) -> list[str]:
    """Split right N times and return the new surface IDs."""
    ids = []
    for _ in range(n):
        sid = c.new_split("right")
        time.sleep(0.05)
        if sid:
            ids.append(sid)
    return ids


def _close_action(c: cmux, ws: str, surface_id: str, action: str) -> dict:
    return c._call(
        "surface.action",
        {"workspace_id": ws, "surface_id": surface_id, "action": action},
    ) or {}


def main() -> int:
    ws = None
    with cmux(SOCKET_PATH) as c:
        try:
            ws = c.new_workspace()
            c.select_workspace(ws)
            time.sleep(0.1)

            # ── Setup: 5 surfaces: [s0, s1, s2, s3, s4] ──────────────
            ids_before = _surface_ids(c, ws)
            s0 = ids_before[0]
            _add_surfaces(c, 4)  # creates s1..s4
            all5 = _surface_ids(c, ws)
            if len(all5) < 5:
                raise cmuxError(f"expected >= 5 surfaces, got {len(all5)}")
            s0, s1, s2, s3, s4 = all5[0], all5[1], all5[2], all5[3], all5[4]

            # ── close_right from s2 → removes s3, s4 ─────────────────
            res = _close_action(c, ws, s2, "close_right")
            if res.get("action") != "close_right":
                raise cmuxError(f"close_right: bad action echo: {res}")
            if res.get("closed") != 2:
                raise cmuxError(f"close_right: expected closed=2, got {res}")

            remaining = _surface_ids(c, ws)
            if s3 in remaining or s4 in remaining:
                raise cmuxError(f"close_right: s3/s4 still present: {remaining}")
            if s2 not in remaining:
                raise cmuxError(f"close_right: anchor s2 removed: {remaining}")

            # Now have [s0, s1, s2]. Add 2 more for next test.
            _add_surfaces(c, 2)
            after_add = _surface_ids(c, ws)
            if len(after_add) < 5:
                raise cmuxError(f"expected >= 5 surfaces after re-add, got {len(after_add)}")
            s_a, s_b, s_c, s_d, s_e = (
                after_add[0], after_add[1], after_add[2],
                after_add[3], after_add[4],
            )

            # ── close_left from s_c → removes s_a, s_b ───────────────
            res2 = _close_action(c, ws, s_c, "close_left")
            if res2.get("action") != "close_left":
                raise cmuxError(f"close_left: bad action echo: {res2}")
            if res2.get("closed") != 2:
                raise cmuxError(f"close_left: expected closed=2, got {res2}")

            remaining2 = _surface_ids(c, ws)
            if s_a in remaining2 or s_b in remaining2:
                raise cmuxError(f"close_left: s_a/s_b still present: {remaining2}")
            if s_c not in remaining2:
                raise cmuxError(f"close_left: anchor s_c removed: {remaining2}")

            # Now have [s_c, s_d, s_e]. Test close_others from s_d.
            # ── close_others from s_d → removes s_c, s_e ─────────────
            res3 = _close_action(c, ws, s_d, "close_others")
            if res3.get("action") != "close_others":
                raise cmuxError(f"close_others: bad action echo: {res3}")
            if res3.get("closed") != 2:
                raise cmuxError(f"close_others: expected closed=2, got {res3}")

            remaining3 = _surface_ids(c, ws)
            if s_c in remaining3 or s_e in remaining3:
                raise cmuxError(f"close_others: siblings still present: {remaining3}")
            if s_d not in remaining3:
                raise cmuxError(f"close_others: anchor removed: {remaining3}")

            # ── Pinned surfaces are skipped ───────────────────────────
            # Add 2 more, pin one, then close_others should skip it.
            _add_surfaces(c, 2)
            pin_set = _surface_ids(c, ws)
            if len(pin_set) < 3:
                raise cmuxError(f"expected >= 3 surfaces for pin test, got {len(pin_set)}")

            anchor_pin = pin_set[1]  # middle
            pinned_target = pin_set[0]  # left

            # Pin the left surface
            c._call(
                "surface.action",
                {"workspace_id": ws, "surface_id": pinned_target, "action": "pin"},
            )

            res4 = _close_action(c, ws, anchor_pin, "close_others")
            if res4.get("skipped_pinned", 0) < 1:
                raise cmuxError(f"close_others should skip pinned, got {res4}")
            remaining4 = _surface_ids(c, ws)
            if pinned_target not in remaining4:
                raise cmuxError(
                    f"pinned surface {pinned_target} was closed: {remaining4}"
                )

            # ── No-op close_left at position 0 ────────────────────────
            leftmost = _surface_ids(c, ws)[0]
            res5 = _close_action(c, ws, leftmost, "close_left")
            if res5.get("closed") != 0:
                raise cmuxError(f"close_left at idx 0 should close 0: {res5}")

        finally:
            if ws is not None:
                try:
                    c.close_workspace(ws)
                except Exception:
                    pass

    print("PASS: surface.action close_left / close_right / close_others")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except cmuxError as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        raise SystemExit(1)
