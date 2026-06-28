const std = @import("std");

fn checkTool(gpa: std.mem.Allocator, io: std.Io, name: []const u8, version_out: []u8) struct { ok: bool, version_len: usize } {
    const argv = [_][]const u8{ name, "--version" };
    const result = std.process.run(gpa, io, .{
        .argv = &argv,
        .stdout_limit = std.Io.Limit.limited(512),
        .stderr_limit = std.Io.Limit.limited(256),
    }) catch return .{ .ok = false, .version_len = 0 };
    defer gpa.free(result.stdout);
    defer gpa.free(result.stderr);

    const ok = switch (result.term) {
        .exited => |c| c == 0,
        else => false,
    };
    if (!ok) return .{ .ok = false, .version_len = 0 };

    // First non-empty line of stdout
    const raw = std.mem.trim(u8, result.stdout, " \t\r\n");
    const first = if (std.mem.indexOfScalar(u8, raw, '\n')) |nl| raw[0..nl] else raw;
    const copy_len = @min(first.len, version_out.len);
    @memcpy(version_out[0..copy_len], first[0..copy_len]);
    return .{ .ok = true, .version_len = copy_len };
}

pub fn run(
    gpa: std.mem.Allocator,
    io: std.Io,
    plugins_dir: []const u8,
    out: *std.Io.Writer,
) !bool {
    var all_ok = true;
    var missing_optional: usize = 0;

    try out.print("plowman doctor\n\n", .{});

    // ── External tools ────────────────────────────────────────────
    const Tool = struct { name: []const u8, why: []const u8 };
    const tools = [_]Tool{
        .{ .name = "rg", .why = "file search" },
        .{ .name = "fd", .why = "file discovery" },
        .{ .name = "jq", .why = "JSON processing" },
    };

    try out.print("Dependencies (optional — enhance output quality):\n\n", .{});
    var ver_buf: [128]u8 = undefined;
    for (tools) |tool| {
        const r = checkTool(gpa, io, tool.name, &ver_buf);
        if (r.ok) {
            try out.print("  [ok]      {s:<6}  {s}  ({s})\n", .{ tool.name, ver_buf[0..r.version_len], tool.why });
        } else {
            missing_optional += 1;
            try out.print("  [missing] {s:<6}  not found  ({s})\n", .{ tool.name, tool.why });
        }
    }

    // ── Installed plugins ─────────────────────────────────────────
    try out.print("\nPlugins:\n\n", .{});

    const dir = std.Io.Dir.openDirAbsolute(io, plugins_dir, .{ .iterate = true }) catch {
        try out.print("  (none — {s})\n", .{plugins_dir});
        try out.print("\n", .{});
        try printSummary(out, all_ok, missing_optional);
        return all_ok;
    };

    var plugin_count: usize = 0;
    var it = dir.iterate();
    while (try it.next(io)) |entry| {
        if (entry.kind != .file) continue;
        plugin_count += 1;

        // Read pointer file to get manifest path
        const pointer_path = try std.fmt.allocPrint(gpa, "{s}/{s}", .{ plugins_dir, entry.name });
        defer gpa.free(pointer_path);

        const pf = std.Io.Dir.openFileAbsolute(io, pointer_path, .{}) catch {
            try out.print("  [error]   {s}  cannot read pointer file\n", .{entry.name});
            all_ok = false;
            continue;
        };
        var rbuf: [256]u8 = undefined;
        var rdr = pf.reader(io, &rbuf);
        const raw = rdr.interface.allocRemaining(gpa, .limited(4096)) catch {
            pf.close(io);
            try out.print("  [error]   {s}  cannot read manifest path\n", .{entry.name});
            all_ok = false;
            continue;
        };
        pf.close(io);
        defer gpa.free(raw);
        const manifest_path = std.mem.trim(u8, raw, " \t\r\n");

        // Verify manifest file exists
        const mf = std.Io.Dir.openFileAbsolute(io, manifest_path, .{}) catch {
            try out.print("  [broken]  {s}  manifest not found: {s}\n", .{ entry.name, manifest_path });
            all_ok = false;
            continue;
        };
        mf.close(io);

        try out.print("  [ok]      {s}  {s}\n", .{ entry.name, manifest_path });
    }

    if (plugin_count == 0) {
        try out.print("  (none installed)\n", .{});
    }

    try out.print("\n", .{});
    try printSummary(out, all_ok, missing_optional);
    return all_ok;
}

fn printSummary(out: *std.Io.Writer, ok: bool, missing_optional: usize) !void {
    if (!ok) {
        try out.print("Some checks failed.\n", .{});
        return;
    }
    if (missing_optional > 0) {
        try out.print("Ready. Optional tools missing — install with: brew install ripgrep fd jq\n", .{});
    } else {
        try out.print("All checks passed.\n", .{});
    }
}
