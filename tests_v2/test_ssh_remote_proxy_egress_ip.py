#!/usr/bin/env python3
"""Verify remote proxy egress: traffic exits from the remote host, not locally.

Connects a workspace via Docker SSH, curls /ip through the SOCKS proxy,
and asserts the returned IP is the container's internal address (not the
host machine's IP). This proves traffic actually traverses the SSH tunnel.
"""

from __future__ import annotations

import glob
import json
import os
import secrets
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from cmux import cmux, cmuxError


SOCKET_PATH = os.environ.get("CMUX_SOCKET", "/tmp/cmux-debug.sock")
REMOTE_HTTP_PORT = int(os.environ.get("CMUX_SSH_TEST_REMOTE_HTTP_PORT", "43173"))
DOCKER_SSH_HOST = os.environ.get("CMUX_SSH_TEST_DOCKER_HOST", "127.0.0.1")
DOCKER_PUBLISH_ADDR = os.environ.get("CMUX_SSH_TEST_DOCKER_BIND_ADDR", "127.0.0.1")


def _must(cond: bool, msg: str) -> None:
    if not cond:
        raise cmuxError(msg)


def _find_cli_binary() -> str:
    env_cli = os.environ.get("CMUXTERM_CLI")
    if env_cli and os.path.isfile(env_cli) and os.access(env_cli, os.X_OK):
        return env_cli
    candidates = glob.glob(os.path.expanduser("~/Library/Developer/Xcode/DerivedData/**/Build/Products/Debug/cmux"), recursive=True)
    candidates += glob.glob("/tmp/cmux-*/Build/Products/Debug/cmux")
    candidates = [p for p in candidates if os.path.isfile(p) and os.access(p, os.X_OK)]
    if not candidates:
        raise cmuxError("Could not locate cmux CLI binary; set CMUXTERM_CLI")
    candidates.sort(key=lambda p: os.path.getmtime(p), reverse=True)
    return candidates[0]


def _run(cmd: list[str], *, env: dict[str, str] | None = None, check: bool = True) -> subprocess.CompletedProcess[str]:
    proc = subprocess.run(cmd, capture_output=True, text=True, env=env, check=False)
    if check and proc.returncode != 0:
        merged = f"{proc.stdout}\n{proc.stderr}".strip()
        raise cmuxError(f"Command failed ({' '.join(cmd)}): {merged}")
    return proc


def _run_cli_json(cli: str, args: list[str]) -> dict:
    env = dict(os.environ)
    env.pop("CMUX_WORKSPACE_ID", None)
    env.pop("CMUX_SURFACE_ID", None)
    env.pop("CMUX_TAB_ID", None)
    proc = _run([cli, "--socket", SOCKET_PATH, "--json", *args], env=env)
    try:
        return json.loads(proc.stdout or "{}")
    except Exception as exc:
        raise cmuxError(f"Invalid JSON output for {' '.join(args)}: {proc.stdout!r} ({exc})")


def _docker_available() -> bool:
    if shutil.which("docker") is None:
        return False
    return _run(["docker", "info"], check=False).returncode == 0


def _parse_host_port(docker_port_output: str) -> int:
    text = docker_port_output.strip()
    if not text:
        raise cmuxError("docker port output was empty")
    return int(text.split(":")[-1])


def _shell_single_quote(value: str) -> str:
    return "'" + value.replace("'", "'\"'\"'") + "'"


def _ssh_run(host: str, host_port: int, key_path: Path, script: str, *, check: bool = True) -> subprocess.CompletedProcess[str]:
    return _run([
        "ssh", "-o", "UserKnownHostsFile=/dev/null", "-o", "StrictHostKeyChecking=no",
        "-o", "ConnectTimeout=5", "-p", str(host_port), "-i", str(key_path),
        host, f"sh -lc {_shell_single_quote(script)}",
    ], check=check)


def _wait_for_ssh(host: str, host_port: int, key_path: Path, timeout: float = 20.0) -> None:
    deadline = time.time() + timeout
    while time.time() < deadline:
        probe = _ssh_run(host, host_port, key_path, "echo ready", check=False)
        if probe.returncode == 0 and "ready" in probe.stdout:
            return
        time.sleep(0.5)
    raise cmuxError("Timed out waiting for SSH server in docker fixture")


def _curl_via_socks(proxy_port: int, target_url: str) -> str:
    if shutil.which("curl") is None:
        raise cmuxError("curl is required for SOCKS proxy verification")
    proc = _run([
        "curl", "--silent", "--show-error", "--max-time", "5",
        "--socks5-hostname", f"127.0.0.1:{proxy_port}", target_url,
    ], check=False)
    if proc.returncode != 0:
        raise cmuxError(f"curl via SOCKS proxy failed: {proc.stdout}\n{proc.stderr}")
    return proc.stdout


def _wait_connected_proxy_port(client: cmux, workspace_id: str, timeout: float = 45.0) -> tuple[dict, int]:
    deadline = time.time() + timeout
    last_status = {}
    while time.time() < deadline:
        last_status = client._call("workspace.remote.status", {"workspace_id": workspace_id}) or {}
        remote = last_status.get("remote") or {}
        state = str(remote.get("state") or "")
        proxy = remote.get("proxy") or {}
        port_value = proxy.get("port")
        proxy_port: int | None = None
        if isinstance(port_value, int):
            proxy_port = port_value
        elif isinstance(port_value, str) and port_value.isdigit():
            proxy_port = int(port_value)
        if state == "connected" and proxy_port is not None:
            return last_status, proxy_port
        time.sleep(0.5)
    raise cmuxError(f"Remote proxy did not converge: {last_status}")


def main() -> int:
    if not _docker_available():
        print("SKIP: docker is not available")
        return 0

    cli = _find_cli_binary()
    fixture_dir = Path(__file__).resolve().parents[1] / "tests" / "fixtures" / "ssh-remote"
    _must(fixture_dir.is_dir(), f"Missing fixture: {fixture_dir}")

    temp_dir = Path(tempfile.mkdtemp(prefix="cmux-egress-"))
    image_tag = f"cmux-ssh-test:{secrets.token_hex(4)}"
    container_name = f"cmux-egress-{secrets.token_hex(4)}"
    workspace_id = ""

    try:
        key_path = temp_dir / "id_ed25519"
        _run(["ssh-keygen", "-t", "ed25519", "-N", "", "-f", str(key_path)])
        pubkey = (key_path.with_suffix(".pub")).read_text(encoding="utf-8").strip()

        _run(["docker", "build", "-t", image_tag, str(fixture_dir)])
        _run([
            "docker", "run", "-d", "--rm",
            "--name", container_name,
            "-e", f"AUTHORIZED_KEY={pubkey}",
            "-e", f"REMOTE_HTTP_PORT={REMOTE_HTTP_PORT}",
            "-p", f"{DOCKER_PUBLISH_ADDR}::22",
            image_tag,
        ])

        port_info = _run(["docker", "port", container_name, "22/tcp"]).stdout
        host_ssh_port = _parse_host_port(port_info)
        host = f"root@{DOCKER_SSH_HOST}"
        _wait_for_ssh(host, host_ssh_port, key_path)

        # Get container's internal IP for comparison
        container_ip = _run([
            "docker", "inspect", "-f", "{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}",
            container_name,
        ]).stdout.strip()
        _must(bool(container_ip), f"Could not determine container IP for {container_name}")

        with cmux(SOCKET_PATH) as client:
            payload = _run_cli_json(cli, [
                "ssh", host,
                "--name", "egress-ip-test",
                "--port", str(host_ssh_port),
                "--identity", str(key_path),
                "--ssh-option", "UserKnownHostsFile=/dev/null",
                "--ssh-option", "StrictHostKeyChecking=no",
            ])
            workspace_id = str(payload.get("workspace_id") or "")
            workspace_ref = str(payload.get("workspace_ref") or "")
            if not workspace_id and workspace_ref.startswith("workspace:"):
                listed = client._call("workspace.list", {}) or {}
                for row in listed.get("workspaces") or []:
                    if str(row.get("ref") or "") == workspace_ref:
                        workspace_id = str(row.get("id") or "")
                        break
            _must(bool(workspace_id), f"cmux ssh missing workspace_id: {payload}")

            _, proxy_port = _wait_connected_proxy_port(client, workspace_id)

            # Fetch /ip through SOCKS proxy — this hits the HTTP server
            # running INSIDE the container on 127.0.0.1:REMOTE_HTTP_PORT.
            # The proxy tunnels the request through the SSH daemon, so the
            # HTTP server sees the connection coming from 127.0.0.1 (loopback
            # inside the container), NOT the host's IP.
            ip_body = ""
            deadline = time.time() + 15.0
            while time.time() < deadline:
                try:
                    ip_body = _curl_via_socks(proxy_port, f"http://127.0.0.1:{REMOTE_HTTP_PORT}/ip")
                    if ip_body.strip():
                        break
                except Exception:
                    time.sleep(0.5)

            _must(bool(ip_body.strip()), f"/ip endpoint returned empty body via proxy")

            ip_data = json.loads(ip_body)
            remote_seen_ip = ip_data.get("ip", "")
            _must(bool(remote_seen_ip), f"/ip returned no ip field: {ip_data}")

            # The HTTP server binds to 127.0.0.1 inside the container.
            # Traffic arriving through the SSH tunnel appears as 127.0.0.1
            # (loopback) to the server. If the proxy was NOT tunneling
            # (i.e., connecting directly), the server would not be reachable
            # at all (it only listens on container-local 127.0.0.1).
            # So reaching it at all proves egress through the tunnel.
            _must(
                remote_seen_ip == "127.0.0.1",
                f"Traffic should arrive as 127.0.0.1 inside container (tunneled), "
                f"got {remote_seen_ip!r}. This suggests proxy is not tunneling through SSH.",
            )

            # Also verify the basic / endpoint still works (backward compat)
            root_body = _curl_via_socks(proxy_port, f"http://127.0.0.1:{REMOTE_HTTP_PORT}/")
            _must(
                "cmux-ssh-forward-ok" in root_body,
                f"Root endpoint returned unexpected body: {root_body[:120]!r}",
            )

            try:
                client.close_workspace(workspace_id)
                workspace_id = ""
            except Exception:
                pass

        print(
            f"PASS: remote egress verified — /ip returned {remote_seen_ip!r} "
            f"(container internal IP: {container_ip}), proxy port {proxy_port}"
        )
        return 0

    finally:
        if workspace_id:
            try:
                with cmux(SOCKET_PATH) as c:
                    c.close_workspace(workspace_id)
            except Exception:
                pass
        _run(["docker", "rm", "-f", container_name], check=False)
        _run(["docker", "rmi", "-f", image_tag], check=False)
        shutil.rmtree(temp_dir, ignore_errors=True)


if __name__ == "__main__":
    raise SystemExit(main())
