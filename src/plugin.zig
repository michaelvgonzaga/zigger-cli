const std = @import("std");

// ============================================================
// Public types
// ============================================================

pub const ManifestArg = struct {
    name: []u8,
    description: []u8,
    required: bool,
    default_value: ?[]u8,

    pub fn deinit(self: *ManifestArg, gpa: std.mem.Allocator) void {
        gpa.free(self.name);
        gpa.free(self.description);
        if (self.default_value) |d| gpa.free(d);
    }
};

pub const ManifestCommand = struct {
    name: []u8,
    description: []u8,
    script_abs: []u8,
    dry_run_supported: bool,
    confirm_prompt: ?[]u8,
    args: std.ArrayList(ManifestArg),
    env_vars: std.ArrayList([]u8),

    pub fn deinit(self: *ManifestCommand, gpa: std.mem.Allocator) void {
        gpa.free(self.name);
        gpa.free(self.description);
        gpa.free(self.script_abs);
        if (self.confirm_prompt) |c| gpa.free(c);
        for (self.args.items) |*a| a.deinit(gpa);
        self.args.deinit(gpa);
        for (self.env_vars.items) |e| gpa.free(e);
        self.env_vars.deinit(gpa);
    }
};

pub const PluginManifest = struct {
    domain: []u8,
    description: []u8,
    commands: std.ArrayList(ManifestCommand),

    pub fn deinit(self: *PluginManifest, gpa: std.mem.Allocator) void {
        gpa.free(self.domain);
        gpa.free(self.description);
        for (self.commands.items) |*c| c.deinit(gpa);
        self.commands.deinit(gpa);
    }
};

// ============================================================
// YAML manifest parser
// ============================================================

const ParseState = enum { root, commands, command, args, arg, env };

fn splitKeyValue(s: []const u8) struct { key: []const u8, value: []const u8 } {
    const colon = std.mem.indexOfScalar(u8, s, ':') orelse return .{ .key = s, .value = "" };
    const key = std.mem.trim(u8, s[0..colon], " \t");
    const value = std.mem.trim(u8, s[colon + 1 ..], " \t");
    return .{ .key = key, .value = value };
}

fn parseBool(s: []const u8) bool {
    return std.mem.eql(u8, s, "true") or std.mem.eql(u8, s, "yes") or std.mem.eql(u8, s, "1");
}

pub fn parseManifest(gpa: std.mem.Allocator, content: []const u8, base_dir: []const u8) !PluginManifest {
    var out_domain: []u8 = try gpa.dupe(u8, "");
    errdefer gpa.free(out_domain);
    var out_desc: []u8 = try gpa.dupe(u8, "");
    errdefer gpa.free(out_desc);
    var commands: std.ArrayList(ManifestCommand) = .empty;
    errdefer {
        for (commands.items) |*c| c.deinit(gpa);
        commands.deinit(gpa);
    }

    // Partial command state (slices point into content — no alloc needed during parse)
    var pcmd_active = false;
    var pcmd_name: []const u8 = "";
    var pcmd_desc: []const u8 = "";
    var pcmd_script: []const u8 = "";
    var pcmd_dry_run = false;
    var pcmd_confirm: []const u8 = "";
    var pcmd_args: std.ArrayList(ManifestArg) = .empty;
    var pcmd_env: std.ArrayList([]u8) = .empty;
    errdefer {
        for (pcmd_args.items) |*a| a.deinit(gpa);
        pcmd_args.deinit(gpa);
        for (pcmd_env.items) |e| gpa.free(e);
        pcmd_env.deinit(gpa);
    }

    // Partial arg state
    var parg_active = false;
    var parg_name: []const u8 = "";
    var parg_desc: []const u8 = "";
    var parg_required = false;
    var parg_default: []const u8 = "";
    var parg_has_default = false;

    var state = ParseState.root;

    var line_iter = std.mem.splitScalar(u8, content, '\n');
    while (line_iter.next()) |raw_line| {
        const line = std.mem.trimEnd(u8, raw_line, "\r");
        const stripped = std.mem.trimStart(u8, line, " \t");
        if (stripped.len == 0 or stripped[0] == '#') continue;

        const indent = line.len - stripped.len;
        const is_list = std.mem.startsWith(u8, stripped, "- ");
        const item = if (is_list) stripped[2..] else stripped;
        const kv = splitKeyValue(item);

        // Cascade state transitions triggered by dedent
        if ((state == .arg or state == .env or state == .args) and indent <= 4) {
            // Finalize in-progress arg
            if (parg_active and state == .arg) {
                if (parg_name.len > 0) {
                    try pcmd_args.append(gpa, ManifestArg{
                        .name = try gpa.dupe(u8, parg_name),
                        .description = try gpa.dupe(u8, parg_desc),
                        .required = parg_required,
                        .default_value = if (parg_has_default) try gpa.dupe(u8, parg_default) else null,
                    });
                }
                parg_active = false;
            }
            state = if (indent <= 1) .root else .command;
        }
        if (state == .command and indent <= 1) {
            // Finalize in-progress command
            if (pcmd_active) try flushCommand(gpa, &pcmd_active, &pcmd_name, &pcmd_desc, &pcmd_script, &pcmd_dry_run, &pcmd_confirm, &pcmd_args, &pcmd_env, base_dir, &commands);
            state = .root;
        }

        switch (state) {
            .root => {
                if (indent != 0) continue;
                if (std.mem.eql(u8, kv.key, "domain") and kv.value.len > 0) {
                    gpa.free(out_domain);
                    out_domain = try gpa.dupe(u8, kv.value);
                } else if (std.mem.eql(u8, kv.key, "description") and kv.value.len > 0) {
                    gpa.free(out_desc);
                    out_desc = try gpa.dupe(u8, kv.value);
                } else if (std.mem.eql(u8, kv.key, "commands") and kv.value.len == 0) {
                    state = .commands;
                }
            },
            .commands => {
                if (indent == 2 and is_list) {
                    pcmd_active = true;
                    pcmd_name = if (std.mem.eql(u8, kv.key, "name")) kv.value else "";
                    pcmd_desc = "";
                    pcmd_script = "";
                    pcmd_dry_run = false;
                    pcmd_confirm = "";
                    state = .command;
                }
            },
            .command => {
                if (indent == 2 and is_list) {
                    // Next command — finalize current
                    if (pcmd_active) try flushCommand(gpa, &pcmd_active, &pcmd_name, &pcmd_desc, &pcmd_script, &pcmd_dry_run, &pcmd_confirm, &pcmd_args, &pcmd_env, base_dir, &commands);
                    pcmd_active = true;
                    pcmd_name = if (std.mem.eql(u8, kv.key, "name")) kv.value else "";
                    pcmd_desc = "";
                    pcmd_script = "";
                    pcmd_dry_run = false;
                    pcmd_confirm = "";
                } else if (indent == 4 and pcmd_active) {
                    if (std.mem.eql(u8, kv.key, "name")) {
                        pcmd_name = kv.value;
                    } else if (std.mem.eql(u8, kv.key, "description")) {
                        pcmd_desc = kv.value;
                    } else if (std.mem.eql(u8, kv.key, "script")) {
                        pcmd_script = kv.value;
                    } else if (std.mem.eql(u8, kv.key, "dry_run")) {
                        pcmd_dry_run = parseBool(kv.value);
                    } else if (std.mem.eql(u8, kv.key, "confirm")) {
                        pcmd_confirm = kv.value;
                    } else if (std.mem.eql(u8, kv.key, "args") and kv.value.len == 0) {
                        state = .args;
                    } else if (std.mem.eql(u8, kv.key, "env") and kv.value.len == 0) {
                        state = .env;
                    }
                }
            },
            .args => {
                if (indent == 6 and is_list) {
                    parg_active = true;
                    parg_name = if (std.mem.eql(u8, kv.key, "name")) kv.value else "";
                    parg_desc = "";
                    parg_required = false;
                    parg_default = "";
                    parg_has_default = false;
                    state = .arg;
                }
            },
            .arg => {
                if (indent == 6 and is_list) {
                    // New arg — finalize current
                    if (parg_active and parg_name.len > 0) {
                        try pcmd_args.append(gpa, ManifestArg{
                            .name = try gpa.dupe(u8, parg_name),
                            .description = try gpa.dupe(u8, parg_desc),
                            .required = parg_required,
                            .default_value = if (parg_has_default) try gpa.dupe(u8, parg_default) else null,
                        });
                    }
                    parg_active = true;
                    parg_name = if (std.mem.eql(u8, kv.key, "name")) kv.value else "";
                    parg_desc = "";
                    parg_required = false;
                    parg_default = "";
                    parg_has_default = false;
                } else if (indent == 8 and parg_active) {
                    if (std.mem.eql(u8, kv.key, "name")) {
                        parg_name = kv.value;
                    } else if (std.mem.eql(u8, kv.key, "description")) {
                        parg_desc = kv.value;
                    } else if (std.mem.eql(u8, kv.key, "required")) {
                        parg_required = parseBool(kv.value);
                    } else if (std.mem.eql(u8, kv.key, "default")) {
                        parg_default = kv.value;
                        parg_has_default = true;
                    }
                }
            },
            .env => {
                if (indent == 6 and is_list and item.len > 0) {
                    // Support both "- KEY=VALUE" and "- key: value" formats
                    const env_entry = if (kv.value.len > 0)
                        try std.fmt.allocPrint(gpa, "{s}={s}", .{ kv.key, kv.value })
                    else
                        try gpa.dupe(u8, item);
                    errdefer gpa.free(env_entry);
                    try pcmd_env.append(gpa, env_entry);
                }
            },
        }
    }

    // Finalize any in-progress items
    if (parg_active and (state == .arg) and parg_name.len > 0) {
        try pcmd_args.append(gpa, ManifestArg{
            .name = try gpa.dupe(u8, parg_name),
            .description = try gpa.dupe(u8, parg_desc),
            .required = parg_required,
            .default_value = if (parg_has_default) try gpa.dupe(u8, parg_default) else null,
        });
    }
    if (pcmd_active) {
        try flushCommand(gpa, &pcmd_active, &pcmd_name, &pcmd_desc, &pcmd_script, &pcmd_dry_run, &pcmd_confirm, &pcmd_args, &pcmd_env, base_dir, &commands);
    } else {
        // Clean up unused partial lists
        for (pcmd_args.items) |*a| a.deinit(gpa);
        pcmd_args.deinit(gpa);
        for (pcmd_env.items) |e| gpa.free(e);
        pcmd_env.deinit(gpa);
    }
    // Suppress errdefer double-free (ownership transferred)
    pcmd_args = .empty;
    pcmd_env = .empty;

    if (out_domain.len == 0) return error.MissingDomain;

    return PluginManifest{
        .domain = out_domain,
        .description = out_desc,
        .commands = commands,
    };
}

fn flushCommand(
    gpa: std.mem.Allocator,
    active: *bool,
    name: *const []const u8,
    desc: *const []const u8,
    script: *const []const u8,
    dry_run: *const bool,
    confirm: *const []const u8,
    args: *std.ArrayList(ManifestArg),
    env_vars: *std.ArrayList([]u8),
    base_dir: []const u8,
    out: *std.ArrayList(ManifestCommand),
) !void {
    defer active.* = false;
    if (name.*.len == 0 or script.*.len == 0) {
        // Discard incomplete command
        for (args.items) |*a| a.deinit(gpa);
        args.deinit(gpa);
        args.* = .empty;
        for (env_vars.items) |e| gpa.free(e);
        env_vars.deinit(gpa);
        env_vars.* = .empty;
        return;
    }

    const script_abs = if (script.*[0] == '/')
        try gpa.dupe(u8, script.*)
    else
        try std.fmt.allocPrint(gpa, "{s}/{s}", .{ base_dir, script.* });
    errdefer gpa.free(script_abs);

    const cmd_name = try gpa.dupe(u8, name.*);
    errdefer gpa.free(cmd_name);
    const cmd_desc = try gpa.dupe(u8, desc.*);
    errdefer gpa.free(cmd_desc);
    const cmd_confirm = if (confirm.*.len > 0) try gpa.dupe(u8, confirm.*) else null;
    errdefer if (cmd_confirm) |c| gpa.free(c);

    try out.append(gpa, ManifestCommand{
        .name = cmd_name,
        .description = cmd_desc,
        .script_abs = script_abs,
        .dry_run_supported = dry_run.*,
        .confirm_prompt = cmd_confirm,
        .args = args.*,
        .env_vars = env_vars.*,
    });
    args.* = .empty;
    env_vars.* = .empty;
}

// ============================================================
// Plugin installation and loading
// ============================================================

pub fn installPlugin(
    gpa: std.mem.Allocator,
    io: std.Io,
    manifest_path: []const u8,
    plugins_dir: []const u8,
) ![]u8 {
    // Resolve manifest to absolute path
    var abs_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const abs_len = try std.Io.Dir.cwd().realPathFile(io, manifest_path, &abs_buf);
    const abs_path = abs_buf[0..abs_len];

    // Extract base dir from abs_path
    const slash = std.mem.lastIndexOfScalar(u8, abs_path, '/') orelse 0;
    const base_dir = abs_path[0..slash];

    // Parse manifest to get domain name
    const manifest_file = try std.Io.Dir.openFileAbsolute(io, abs_path, .{});
    defer manifest_file.close(io);
    var rbuf: [4096]u8 = undefined;
    var rdr = manifest_file.reader(io, &rbuf);
    const content = try rdr.interface.allocRemaining(gpa, .limited(1024 * 1024));
    defer gpa.free(content);

    var manifest = try parseManifest(gpa, content, base_dir);
    defer manifest.deinit(gpa);

    // Create plugins directory (recursive)
    try std.Io.Dir.cwd().createDirPath(io, plugins_dir);

    // Write pointer file: plugins_dir/<domain>  containing the absolute manifest path
    const pointer_path = try std.fmt.allocPrint(gpa, "{s}/{s}", .{ plugins_dir, manifest.domain });
    defer gpa.free(pointer_path);

    const pf = try std.Io.Dir.createFileAbsolute(io, pointer_path, .{ .truncate = true });
    defer pf.close(io);
    var wbuf: [4096]u8 = undefined;
    var wr = pf.writerStreaming(io, &wbuf);
    try wr.interface.writeAll(abs_path);
    try wr.interface.flush();

    return try gpa.dupe(u8, manifest.domain);
}

pub fn loadPlugin(
    gpa: std.mem.Allocator,
    io: std.Io,
    domain: []const u8,
    plugins_dir: []const u8,
) !PluginManifest {
    // Read pointer file
    const pointer_path = try std.fmt.allocPrint(gpa, "{s}/{s}", .{ plugins_dir, domain });
    defer gpa.free(pointer_path);

    const pf = std.Io.Dir.openFileAbsolute(io, pointer_path, .{}) catch {
        return error.PluginNotFound;
    };
    defer pf.close(io);
    var rbuf: [256]u8 = undefined;
    var rdr = pf.reader(io, &rbuf);
    const manifest_path_raw = try rdr.interface.allocRemaining(gpa, .limited(4096));
    defer gpa.free(manifest_path_raw);
    const manifest_path = std.mem.trim(u8, manifest_path_raw, " \t\r\n");

    // Parse manifest from its original location
    const slash = std.mem.lastIndexOfScalar(u8, manifest_path, '/') orelse 0;
    const base_dir = manifest_path[0..slash];

    const mf = std.Io.Dir.openFileAbsolute(io, manifest_path, .{}) catch {
        return error.ManifestNotFound;
    };
    defer mf.close(io);
    var rbuf2: [4096]u8 = undefined;
    var rdr2 = mf.reader(io, &rbuf2);
    const content = try rdr2.interface.allocRemaining(gpa, .limited(1024 * 1024));
    defer gpa.free(content);

    return try parseManifest(gpa, content, base_dir);
}

pub fn listPlugins(
    gpa: std.mem.Allocator,
    io: std.Io,
    plugins_dir: []const u8,
    out: *std.Io.Writer,
) !void {
    const dir = std.Io.Dir.openDirAbsolute(io, plugins_dir, .{ .iterate = true }) catch {
        try out.print("No plugins installed.\n", .{});
        return;
    };

    var names: std.ArrayList([]u8) = .empty;
    defer {
        for (names.items) |n| gpa.free(n);
        names.deinit(gpa);
    }

    {
        var it = dir.iterate();
        while (try it.next(io)) |entry| {
            if (entry.kind != .file) continue;
            try names.append(gpa, try gpa.dupe(u8, entry.name));
        }
    }

    if (names.items.len == 0) {
        try out.print("No plugins installed.\n", .{});
        return;
    }

    try out.print("Installed plugins:\n\n", .{});
    for (names.items) |name| {
        try out.print("  plowman {s} <command>\n", .{name});
    }
    try out.print("\n", .{});
}

// ============================================================
// Command execution
// ============================================================

pub fn showHelp(
    manifest: *const PluginManifest,
    out: *std.Io.Writer,
) !void {
    try out.print("# {s}", .{manifest.domain});
    if (manifest.description.len > 0) {
        try out.print(" — {s}", .{manifest.description});
    }
    try out.print("\n\n", .{});
    try out.print("Commands:\n\n", .{});
    for (manifest.commands.items) |cmd| {
        if (cmd.description.len > 0) {
            try out.print("  plowman {s} {s}\n      {s}\n", .{
                manifest.domain, cmd.name, cmd.description,
            });
        } else {
            try out.print("  plowman {s} {s}\n", .{ manifest.domain, cmd.name });
        }
        for (cmd.args.items) |arg| {
            const req_str: []const u8 = if (arg.required) "(required)" else "";
            if (arg.description.len > 0) {
                try out.print("      <{s}> {s} {s}\n", .{ arg.name, arg.description, req_str });
            } else {
                try out.print("      <{s}> {s}\n", .{ arg.name, req_str });
            }
        }
        if (cmd.dry_run_supported) {
            try out.print("      --dry-run  print command without running\n", .{});
        }
        try out.print("\n", .{});
    }
}

pub fn runCommand(
    gpa: std.mem.Allocator,
    io: std.Io,
    manifest: *const PluginManifest,
    cmd_name: []const u8,
    extra_args: []const []const u8,
    dry_run: bool,
    out: *std.Io.Writer,
    err_out: *std.Io.Writer,
) !u8 {
    // Find command
    const cmd = blk: {
        for (manifest.commands.items) |*c| {
            if (std.mem.eql(u8, c.name, cmd_name)) break :blk c;
        }
        try err_out.print("error: unknown command '{s}' for plugin '{s}'\n", .{ cmd_name, manifest.domain });
        try err_out.print("run 'plowman {s} help' to see available commands\n", .{manifest.domain});
        try err_out.flush();
        return 1;
    };

    // Validate required args
    for (cmd.args.items, 0..) |arg, pos| {
        if (!arg.required) continue;
        if (pos >= extra_args.len and arg.default_value == null) {
            try err_out.print("error: missing required argument <{s}>\n", .{arg.name});
            try err_out.flush();
            return 1;
        }
    }

    // Dry run: show what would execute
    if (dry_run) {
        if (cmd.env_vars.items.len > 0) {
            for (cmd.env_vars.items) |e| try out.print("env {s} ", .{e});
        }
        try out.print("{s}", .{cmd.script_abs});
        for (extra_args) |a| try out.print(" {s}", .{a});
        try out.print("\n", .{});
        try out.flush();
        return 0;
    }

    // Confirmation prompt
    if (cmd.confirm_prompt) |prompt| {
        try err_out.print("{s} [y/N] ", .{prompt});
        try err_out.flush();

        var stdin_buf: [64]u8 = undefined;
        var stdin_r = std.Io.File.stdin().reader(io, &stdin_buf);
        const answer = (try stdin_r.interface.takeDelimiter('\n')) orelse "";
        const trimmed_answer = std.mem.trim(u8, answer, " \t\r");
        const confirmed = trimmed_answer.len > 0 and
            (trimmed_answer[0] == 'y' or trimmed_answer[0] == 'Y');

        if (!confirmed) {
            try err_out.print("Aborted.\n", .{});
            try err_out.flush();
            return 0;
        }
    }

    // Build argv: use /usr/bin/env to inject manifest env vars without needing a Map
    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(gpa);

    if (cmd.env_vars.items.len > 0) {
        try argv.append(gpa, "/usr/bin/env");
        for (cmd.env_vars.items) |e| try argv.append(gpa, e);
    }
    try argv.append(gpa, cmd.script_abs);
    for (extra_args) |a| try argv.append(gpa, a);

    var child = try std.process.spawn(io, .{
        .argv = argv.items,
        .environ_map = null,
        .stdin = .inherit,
        .stdout = .inherit,
        .stderr = .inherit,
    });

    const term = try child.wait(io);
    return switch (term) {
        .exited => |code| code,
        else => 1,
    };
}
