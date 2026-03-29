/// cmux configuration parser.
///
/// Parses cmux.json config files (global and local) defining workspace
/// commands with layout templates. Supports inotify-based file watching
/// for hot-reload on Linux.
///
/// Schema matches macOS CmuxConfig.swift exactly for cross-platform compat.

const std = @import("std");
const posix = std.posix;

const Allocator = std.mem.Allocator;

// ── Schema Types ──────────────────────────────────────────────────

pub const Config = struct {
    commands: []CommandDef,

    pub fn deinit(self: *Config, alloc: Allocator) void {
        for (self.commands) |*cmd| cmd.deinit(alloc);
        alloc.free(self.commands);
    }
};

pub const Restart = enum {
    recreate,
    ignore,
    confirm,
};

pub const SurfaceType = enum {
    terminal,
    browser,
};

pub const SplitDirection = enum {
    horizontal,
    vertical,
};

pub const SurfaceDef = struct {
    type: SurfaceType,
    name: ?[]const u8 = null,
    command: ?[]const u8 = null,
    cwd: ?[]const u8 = null,
    url: ?[]const u8 = null,
    focus: ?bool = null,

    pub fn deinit(self: *SurfaceDef, alloc: Allocator) void {
        if (self.name) |v| alloc.free(v);
        if (self.command) |v| alloc.free(v);
        if (self.cwd) |v| alloc.free(v);
        if (self.url) |v| alloc.free(v);
    }
};

pub const LayoutNode = union(enum) {
    pane: PaneDef,
    split: SplitDef,

    pub fn deinit(self: *LayoutNode, alloc: Allocator) void {
        switch (self.*) {
            .pane => |*p| {
                for (p.surfaces) |*s| s.deinit(alloc);
                alloc.free(p.surfaces);
            },
            .split => |*s| {
                s.children[0].deinit(alloc);
                s.children[1].deinit(alloc);
                alloc.free(s.children);
            },
        }
    }
};

pub const PaneDef = struct {
    surfaces: []SurfaceDef,
};

pub const SplitDef = struct {
    direction: SplitDirection,
    split: f64 = 0.5,
    children: []LayoutNode,
};

pub const WorkspaceDef = struct {
    name: ?[]const u8 = null,
    cwd: ?[]const u8 = null,
    color: ?[]const u8 = null,
    layout: ?LayoutNode = null,

    pub fn deinit(self: *WorkspaceDef, alloc: Allocator) void {
        if (self.name) |v| alloc.free(v);
        if (self.cwd) |v| alloc.free(v);
        if (self.color) |v| alloc.free(v);
        if (self.layout) |*l| l.deinit(alloc);
    }
};

pub const CommandDef = struct {
    name: []const u8,
    description: ?[]const u8 = null,
    keywords: ?[][]const u8 = null,
    restart: ?Restart = null,
    workspace: ?WorkspaceDef = null,
    command: ?[]const u8 = null,

    pub fn deinit(self: *CommandDef, alloc: Allocator) void {
        alloc.free(self.name);
        if (self.description) |v| alloc.free(v);
        if (self.keywords) |kws| {
            for (kws) |kw| alloc.free(kw);
            alloc.free(kws);
        }
        if (self.workspace) |*w| w.deinit(alloc);
        if (self.command) |v| alloc.free(v);
    }
};

// ── Parsing ──────────────────────────────────────────────────────

pub const ParseError = error{
    InvalidJson,
    MissingCommands,
    BlankName,
    WorkspaceCommandXor,
    InvalidColor,
    InvalidSplitChildren,
    EmptySurfaces,
} || Allocator.Error;

/// Parse a cmux.json config from a byte slice.
pub fn parse(alloc: Allocator, json_bytes: []const u8) ParseError!Config {
    const parsed = std.json.parseFromSlice(
        std.json.Value,
        alloc,
        json_bytes,
        .{},
    ) catch return error.InvalidJson;
    defer parsed.deinit();

    const root = parsed.value;
    if (root != .object) return error.InvalidJson;

    const commands_val = root.object.get("commands") orelse return error.MissingCommands;
    if (commands_val != .array) return error.MissingCommands;

    var commands: std.ArrayList(CommandDef) = .empty;
    errdefer {
        for (commands.items) |*cmd| cmd.deinit(alloc);
        commands.deinit(alloc);
    }

    for (commands_val.array.items) |cmd_val| {
        const cmd = try parseCommand(alloc, cmd_val);
        try commands.append(alloc, cmd);
    }

    return .{ .commands = try commands.toOwnedSlice(alloc) };
}

fn parseCommand(alloc: Allocator, val: std.json.Value) ParseError!CommandDef {
    if (val != .object) return error.InvalidJson;
    const obj = val.object;

    const name = try dupeString(alloc, obj.get("name") orelse return error.BlankName);
    errdefer alloc.free(name);

    if (std.mem.trim(u8, name, " \t\n\r").len == 0) return error.BlankName;

    const has_workspace = obj.contains("workspace");
    const has_command = obj.contains("command");
    if (has_workspace == has_command) return error.WorkspaceCommandXor;

    var cmd = CommandDef{ .name = name };

    if (obj.get("description")) |v| cmd.description = try dupeStringOpt(alloc, v);
    if (obj.get("restart")) |v| {
        if (v == .string) {
            if (std.mem.eql(u8, v.string, "recreate")) cmd.restart = .recreate
            else if (std.mem.eql(u8, v.string, "ignore")) cmd.restart = .ignore
            else if (std.mem.eql(u8, v.string, "confirm")) cmd.restart = .confirm;
        }
    }

    if (obj.get("keywords")) |kws| {
        if (kws == .array) {
            var list: std.ArrayList([]const u8) = .empty;
            for (kws.array.items) |kw| {
                if (kw == .string) try list.append(alloc, try alloc.dupe(u8, kw.string));
            }
            cmd.keywords = try list.toOwnedSlice(alloc);
        }
    }

    if (has_workspace) {
        cmd.workspace = try parseWorkspace(alloc, obj.get("workspace").?);
    } else {
        cmd.command = try dupeStringOpt(alloc, obj.get("command").?);
    }

    return cmd;
}

fn parseWorkspace(alloc: Allocator, val: std.json.Value) ParseError!WorkspaceDef {
    if (val != .object) return error.InvalidJson;
    const obj = val.object;

    var ws = WorkspaceDef{};

    if (obj.get("name")) |v| ws.name = try dupeStringOpt(alloc, v);
    if (obj.get("cwd")) |v| ws.cwd = try dupeStringOpt(alloc, v);

    if (obj.get("color")) |v| {
        if (v == .string) {
            if (!isValidColor(v.string)) return error.InvalidColor;
            ws.color = try alloc.dupe(u8, v.string);
        }
    }

    if (obj.get("layout")) |v| ws.layout = try parseLayout(alloc, v);

    return ws;
}

fn parseLayout(alloc: Allocator, val: std.json.Value) ParseError!LayoutNode {
    if (val != .object) return error.InvalidJson;
    const obj = val.object;

    // Discriminate: "pane" key = pane node, "direction" key = split node
    if (obj.contains("pane")) {
        return .{ .pane = try parsePaneLayout(alloc, obj.get("pane").?) };
    } else if (obj.contains("direction")) {
        return .{ .split = try parseSplitLayout(alloc, obj) };
    }
    return error.InvalidJson;
}

fn parsePaneLayout(alloc: Allocator, val: std.json.Value) ParseError!PaneDef {
    if (val != .object) return error.InvalidJson;
    const surfaces_val = val.object.get("surfaces") orelse return error.EmptySurfaces;
    if (surfaces_val != .array or surfaces_val.array.items.len == 0) return error.EmptySurfaces;

    var surfaces: std.ArrayList(SurfaceDef) = .empty;
    for (surfaces_val.array.items) |s| {
        try surfaces.append(alloc, try parseSurface(alloc, s));
    }

    return .{ .surfaces = try surfaces.toOwnedSlice(alloc) };
}

fn parseSplitLayout(alloc: Allocator, obj: std.json.ObjectMap) ParseError!SplitDef {
    const dir_val = obj.get("direction") orelse return error.InvalidJson;
    if (dir_val != .string) return error.InvalidJson;

    const direction: SplitDirection = if (std.mem.eql(u8, dir_val.string, "horizontal"))
        .horizontal
    else if (std.mem.eql(u8, dir_val.string, "vertical"))
        .vertical
    else
        return error.InvalidJson;

    var split: f64 = 0.5;
    if (obj.get("split")) |v| {
        if (v == .float) split = v.float
        else if (v == .integer) split = @floatFromInt(v.integer);
    }
    split = @max(0.1, @min(0.9, split));

    const children_val = obj.get("children") orelse return error.InvalidSplitChildren;
    if (children_val != .array or children_val.array.items.len != 2) return error.InvalidSplitChildren;

    var children = try alloc.alloc(LayoutNode, 2);
    children[0] = try parseLayout(alloc, children_val.array.items[0]);
    children[1] = try parseLayout(alloc, children_val.array.items[1]);

    return .{ .direction = direction, .split = split, .children = children };
}

fn parseSurface(alloc: Allocator, val: std.json.Value) ParseError!SurfaceDef {
    if (val != .object) return error.InvalidJson;
    const obj = val.object;

    const type_val = obj.get("type") orelse return error.InvalidJson;
    if (type_val != .string) return error.InvalidJson;

    const surface_type: SurfaceType = if (std.mem.eql(u8, type_val.string, "terminal"))
        .terminal
    else if (std.mem.eql(u8, type_val.string, "browser"))
        .browser
    else
        return error.InvalidJson;

    var surface = SurfaceDef{ .type = surface_type };

    if (obj.get("name")) |v| surface.name = try dupeStringOpt(alloc, v);
    if (obj.get("command")) |v| surface.command = try dupeStringOpt(alloc, v);
    if (obj.get("cwd")) |v| surface.cwd = try dupeStringOpt(alloc, v);
    if (obj.get("url")) |v| surface.url = try dupeStringOpt(alloc, v);
    if (obj.get("focus")) |v| {
        if (v == .bool) surface.focus = v.bool;
    }

    return surface;
}

// ── Helpers ──────────────────────────────────────────────────────

fn dupeString(alloc: Allocator, val: std.json.Value) ParseError![]const u8 {
    if (val != .string) return error.InvalidJson;
    return alloc.dupe(u8, val.string);
}

fn dupeStringOpt(alloc: Allocator, val: std.json.Value) ParseError!?[]const u8 {
    if (val != .string) return null;
    return try alloc.dupe(u8, val.string);
}

fn isValidColor(s: []const u8) bool {
    if (s.len != 7 or s[0] != '#') return false;
    for (s[1..]) |ch| {
        if (!std.ascii.isHex(ch)) return false;
    }
    return true;
}

// ── File Loading ─────────────────────────────────────────────────

/// Load config from the default paths.
/// Searches for cmux.json starting from cwd walking up, then falls back
/// to ~/.config/cmux/cmux.json.
pub fn loadDefault(alloc: Allocator) ?Config {
    // Try local config (search up from cwd)
    if (findLocalConfig(alloc)) |path| {
        defer alloc.free(path);
        if (loadFile(alloc, path)) |cfg| return cfg;
    }

    // Fall back to global config
    const home = std.posix.getenv("HOME") orelse return null;
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const global_path = std.fmt.bufPrint(&buf, "{s}/.config/cmux/cmux.json", .{home}) catch return null;
    return loadFile(alloc, global_path);
}

fn loadFile(alloc: Allocator, path: []const u8) ?Config {
    const file = std.fs.openFileAbsolute(path, .{}) catch return null;
    defer file.close();

    const content = file.readToEndAlloc(alloc, 1024 * 1024) catch return null;
    defer alloc.free(content);

    return parse(alloc, content) catch null;
}

fn findLocalConfig(alloc: Allocator) ?[]const u8 {
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    var cwd = std.process.getCwd(&buf) catch return null;

    while (true) {
        var path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const path = std.fmt.bufPrint(&path_buf, "{s}/cmux.json", .{cwd}) catch return null;

        if (std.fs.accessAbsolute(path, .{})) |_| {
            return alloc.dupe(u8, path) catch null;
        } else |_| {}

        // Walk up
        const parent = std.fs.path.dirname(cwd) orelse return null;
        if (std.mem.eql(u8, parent, cwd)) return null; // reached root
        cwd = parent;
    }
}

// ── Tests ────────────────────────────────────────────────────────

test "parse minimal config" {
    const json =
        \\{"commands":[{"name":"dev","command":"npm run dev"}]}
    ;
    var cfg = try parse(std.testing.allocator, json);
    defer cfg.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), cfg.commands.len);
    try std.testing.expectEqualStrings("dev", cfg.commands[0].name);
    try std.testing.expectEqualStrings("npm run dev", cfg.commands[0].command.?);
}

test "parse workspace with layout" {
    const json =
        \\{"commands":[{"name":"split","workspace":{"name":"My WS","color":"#FF5733","layout":{"direction":"horizontal","split":0.6,"children":[{"pane":{"surfaces":[{"type":"terminal","command":"htop"}]}},{"pane":{"surfaces":[{"type":"terminal"}]}}]}}}]}
    ;
    var cfg = try parse(std.testing.allocator, json);
    defer cfg.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), cfg.commands.len);
    const ws = cfg.commands[0].workspace.?;
    try std.testing.expectEqualStrings("My WS", ws.name.?);
    try std.testing.expectEqualStrings("#FF5733", ws.color.?);
    try std.testing.expect(ws.layout.? == .split);
}

test "reject blank name" {
    const json = \\{"commands":[{"name":"  ","command":"ls"}]}
    ;
    try std.testing.expectError(error.BlankName, parse(std.testing.allocator, json));
}

test "reject workspace + command together" {
    const json = \\{"commands":[{"name":"bad","command":"ls","workspace":{"name":"x"}}]}
    ;
    try std.testing.expectError(error.WorkspaceCommandXor, parse(std.testing.allocator, json));
}

test "reject invalid color" {
    const json = \\{"commands":[{"name":"x","workspace":{"color":"red"}}]}
    ;
    try std.testing.expectError(error.InvalidColor, parse(std.testing.allocator, json));
}

test "valid color" {
    try std.testing.expect(isValidColor("#FF5733"));
    try std.testing.expect(isValidColor("#aabbcc"));
    try std.testing.expect(!isValidColor("red"));
    try std.testing.expect(!isValidColor("#FFF"));
    try std.testing.expect(!isValidColor("#GGGGGG"));
}
