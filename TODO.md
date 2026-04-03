# TODO

## Issue 151: Remote SSH (Living Execution)
- [x] `cmux ssh` creates remote workspace metadata and does not require `--name`
- [x] Remote daemon bootstrap/upload/start path with `cmuxd-remote serve --stdio`
- [x] Reconnect/disconnect controls (CLI/API/context menu) + improved error surfacing
- [x] Retry count/time surfaced in remote daemon/probe error details
- [ ] Remove automatic remote service port mirroring (`ssh -L` from detected remote listening ports)
- [ ] Add transport-scoped proxy broker (SOCKS5 + HTTP CONNECT) for remote traffic
- [ ] Extend `cmuxd-remote` RPC beyond `hello/ping` with proxy stream methods (`proxy.open|close`)
- [ ] Auto-wire WKWebView in remote workspaces to proxy via `WKWebsiteDataStore.proxyConfigurations`
- [ ] Add browser proxy e2e tests (remote egress IP, websocket, reconnect continuity)
- [ ] Implement PTY resize coordinator with tmux semantics (`smallest screen wins`)
- [ ] Add resize tests for multi-attachment sessions (attach/detach/reconnect transitions)

## Command Palette
- [ ] Add cmd+shift+p palette with all commands (upstream ctrl-k/cmd-p shipped in PR #139; verify keybinding)

## Feature Requests
- [ ] Warm pool of Claude Code instances mapped to a keyboard shortcut

## Claude Code Integration
- [ ] Add "Install Claude Code integration" menu item in menubar
  - Opens a new terminal
  - Shows user the diff to their config file (claude.json, opencode config, codex config, etc.)
  - Prompts user to type 'y' to confirm
  - Implement as part of `cmux` CLI, menubar just triggers the CLI command

## Additional Integrations
- [ ] Codex integration
- [ ] OpenCode integration

## Browser
- [ ] Per-WKWebView proxy observability/inspection once remote proxy path is shipped (URL, method, headers, body, status, timing)

## Bugs
- [x] **P0** Terminal title updates are suppressed when workspace is not focused (PR #147)
- [ ] Sidebar tab reorder can get stuck in dragging state (dimmed tab + blue drop indicator line visible) after drag ends
- [ ] Drag-and-drop files/images into terminal shows URL instead of file path (Ghostty supports dropping files as paths)
- [ ] After opening a browser tab, up/down arrow keys (and possibly other keyboard shortcuts) stop working in the terminal
- [ ] Notification marked unread doesn't get pushed to the top of the list
- [ ] Browser cmd+shift+H ring flashes only once (should flash twice like other shortcuts)

## Refactoring
- [ ] **P0** Remove all index-based APIs in favor of short ID refs (surface:N, pane:N, workspace:N, window:N)
- [ ] **P0** CLI commands should be workspace-relative using CMUX_WORKSPACE_ID env var (not focused workspace) so agents in background workspaces don't affect the user's active workspace. Affected: send, send-key, send-panel, send-key-panel, new-split, new-pane, new-surface, close-surface, list-panes, list-pane-surfaces, list-panels, focus-pane, focus-panel, surface-health

## UI/UX Improvements
- [ ] Show loading indicator in terminal while it's loading
- [ ] Add question mark icon to learn shortcuts
- [ ] Notification popover: each button item should show outline outside when focused/hovered
- [ ] Notification popover: add right-click context menu to mark as read/unread
- [ ] Right-click tab should allow renaming that workspace
- [ ] Cmd+click should open links in cmux (browser panel) instead of external browser
- [ ] "Waiting for input" notification should include custom terminal title if set
- [ ] Close button for current/active tab should always be visible (not just on hover)
- [ ] Add browser icon to the left of the plus button in the tab bar
