# TODO

## Issue 151: Remote SSH (Living Execution)
- [x] `cmux ssh` creates remote workspace metadata and does not require `--name`
- [x] Remote daemon bootstrap/upload/start path with `cmuxd-remote serve --stdio`
- [x] Reconnect/disconnect controls (CLI/API/context menu) + improved error surfacing
- [x] Retry count/time surfaced in remote daemon/probe error details
- [x] Remove automatic remote service port mirroring (`ssh -L` from detected remote listening ports)
- [x] Add transport-scoped proxy broker (SOCKS5 + HTTP CONNECT) for remote traffic
- [x] Extend `cmuxd-remote` RPC beyond `hello/ping` with proxy stream methods (`proxy.open|close`)
- [x] Auto-wire WKWebView in remote workspaces to proxy via `WKWebsiteDataStore.proxyConfigurations`
- [ ] Add browser proxy e2e tests (remote egress IP, websocket, reconnect continuity)
- [x] Implement PTY resize coordinator with tmux semantics (`smallest screen wins`)
- [x] Add resize tests for multi-attachment sessions (attach/detach/reconnect transitions)

## Command Palette
- [x] Add cmd+shift+p palette with all commands (implemented in cmuxApp.swift, ghostty default is super+shift+p / ctrl+shift+p)

## Feature Requests
- [x] Warm pool of Claude Code instances mapped to a keyboard shortcut (PR #177, Cmd+Shift+K)

## Claude Code Integration
- [x] Add "Install Claude Code integration" menu item in menubar (PR #175)

## Additional Integrations
- [x] Codex integration (#2103)
- [x] OpenCode integration (#2087)

## Browser
- [ ] Per-WKWebView proxy observability/inspection once remote proxy path is shipped (URL, method, headers, body, status, timing)

## Bugs
- [x] **P0** Terminal title updates are suppressed when workspace is not focused (PR #147)
- [x] Sidebar tab reorder can get stuck in dragging state (PR #172)
- [x] Drag-and-drop files/images into terminal shows URL instead of file path (PR #172)
- [x] After opening a browser tab, up/down arrow keys stop working in the terminal (PR #172)
- [x] Notification marked unread doesn't get pushed to the top of the list
- [x] Browser cmd+shift+H ring flashes only once — replaced SwiftUI animation with CAKeyframeAnimation

## Refactoring
- [x] **P0** Remove all index-based APIs in favor of short ID refs (surface:N, pane:N, workspace:N, window:N) (PR #174 + cleanup)
- [x] **P0** CLI commands should be workspace-relative using CMUX_WORKSPACE_ID env var (PR #89)

## UI/UX Improvements
- [ ] Show loading indicator in terminal while it's loading
- [x] Add question mark icon to learn shortcuts (sidebar footer help popover)
- [ ] Notification popover: each button item should show outline outside when focused/hovered
- [ ] Notification popover: add right-click context menu to mark as read/unread
- [x] Right-click tab should allow renaming that workspace (context menu already has "Rename Workspace...")
- [ ] Cmd+click should open links in cmux (browser panel) instead of external browser
- [ ] "Waiting for input" notification should include custom terminal title if set
- [ ] Close button for current/active tab should always be visible (not just on hover)
- [ ] Add browser icon to the left of the plus button in the tab bar
