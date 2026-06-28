const std = @import("std");
const plowman = @import("plowman");

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;
    const args = try init.minimal.args.toSlice(init.arena.allocator());

    var err_buf: [2048]u8 = undefined;
    var err_writer = std.Io.File.stderr().writerStreaming(io, &err_buf);
    const err = &err_writer.interface;

    var out_buf: [65536]u8 = undefined;
    var out_writer = std.Io.File.stdout().writerStreaming(io, &out_buf);
    const out = &out_writer.interface;

    if (args.len < 2) {
        try printUsage(err);
        std.process.exit(1);
    }

    const home = init.environ_map.get("HOME") orelse "/tmp";
    const plugins_dir = try std.fmt.allocPrint(init.arena.allocator(), "{s}/.config/plowman/plugins", .{home});

    const subcmd = if (args.len >= 3) args[2] else "";
    const json_flag = args.len >= 5 and std.mem.eql(u8, args[4], "--json");

    if (std.mem.eql(u8, args[1], "scan") and std.mem.eql(u8, subcmd, "repo")) {
        if (args.len < 4) {
            try err.print("usage: plowman scan repo <path> [--json]\n", .{});
            try err.flush();
            std.process.exit(1);
        }
        const raw_path = args[3];
        const json_output = args.len >= 5 and std.mem.eql(u8, args[4], "--json");

        var abs_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
        const path_len = std.Io.Dir.cwd().realPathFile(io, raw_path, &abs_buf) catch |e| {
            try err.print("error: cannot resolve path '{s}': {}\n", .{ raw_path, e });
            try err.flush();
            std.process.exit(1);
        };
        const path = abs_buf[0..path_len];

        var result = plowman.scanRepo(gpa, io, path) catch |e| {
            try err.print("error scanning '{s}': {}\n", .{ path, e });
            try err.flush();
            std.process.exit(1);
        };
        defer result.deinit(gpa);

        if (json_output) try result.writeJson(out) else try result.writeMarkdown(out);
        try out.flush();
    } else if (std.mem.eql(u8, args[1], "scan") and std.mem.eql(u8, subcmd, "db")) {
        if (args.len < 4) {
            try err.print("usage: plowman scan db <dump.sql> [--json]\n", .{});
            try err.flush();
            std.process.exit(1);
        }
        const raw_path = args[3];

        var abs_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
        const path_len = std.Io.Dir.cwd().realPathFile(io, raw_path, &abs_buf) catch |e| {
            try err.print("error: cannot resolve path '{s}': {}\n", .{ raw_path, e });
            try err.flush();
            std.process.exit(1);
        };
        const path = abs_buf[0..path_len];

        var result = plowman.scanDb(gpa, io, path) catch |e| {
            try err.print("error scanning '{s}': {}\n", .{ path, e });
            try err.flush();
            std.process.exit(1);
        };
        defer result.deinit(gpa);

        if (json_flag) try result.writeJson(out) else try result.writeMarkdown(out);
        try out.flush();
    } else if (std.mem.eql(u8, args[1], "scan") and std.mem.eql(u8, subcmd, "log")) {
        if (args.len < 4) {
            try err.print("usage: plowman scan log <file> [--json]\n", .{});
            try err.flush();
            std.process.exit(1);
        }
        const raw_path = args[3];

        var abs_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
        const path_len = std.Io.Dir.cwd().realPathFile(io, raw_path, &abs_buf) catch |e| {
            try err.print("error: cannot resolve path '{s}': {}\n", .{ raw_path, e });
            try err.flush();
            std.process.exit(1);
        };
        const path = abs_buf[0..path_len];

        var result = plowman.scanLog(gpa, io, path) catch |e| {
            try err.print("error scanning '{s}': {}\n", .{ path, e });
            try err.flush();
            std.process.exit(1);
        };
        defer result.deinit(gpa);

        if (json_flag) try result.writeJson(out) else try result.writeMarkdown(out);
        try out.flush();
    } else if (std.mem.eql(u8, args[1], "doctor")) {
        const ok = plowman.doctor.run(gpa, io, plugins_dir, out) catch |e| {
            try err.print("error running doctor: {}\n", .{e});
            try err.flush();
            std.process.exit(1);
        };
        try out.flush();
        if (!ok) std.process.exit(1);
    } else if (std.mem.eql(u8, args[1], "plugin")) {
        if (std.mem.eql(u8, subcmd, "install")) {
            if (args.len < 4) {
                try err.print("usage: plowman plugin install <manifest.yml>\n", .{});
                try err.flush();
                std.process.exit(1);
            }
            const manifest_path = args[3];
            const domain = plowman.plugin.installPlugin(gpa, io, manifest_path, plugins_dir) catch |e| {
                try err.print("error: cannot install plugin '{s}': {}\n", .{ manifest_path, e });
                try err.flush();
                std.process.exit(1);
            };
            defer gpa.free(domain);
            try out.print("Plugin '{s}' installed.\n", .{domain});
            try out.flush();
        } else if (std.mem.eql(u8, subcmd, "list")) {
            plowman.plugin.listPlugins(gpa, io, plugins_dir, out) catch |e| {
                try err.print("error listing plugins: {}\n", .{e});
                try err.flush();
                std.process.exit(1);
            };
            try out.flush();
        } else {
            try err.print("usage: plowman plugin install <manifest.yml>\n", .{});
            try err.print("       plowman plugin list\n", .{});
            try err.flush();
            std.process.exit(1);
        }
    } else {
        // Domain dispatch: plowman <domain> help | plowman <domain> <command> [args...] [--dry-run]
        const domain = args[1];
        if (args.len < 3) {
            try err.print("error: unknown command '{s}'\n", .{domain});
            try err.print("run 'plowman {s} help' if this is an installed plugin\n", .{domain});
            try err.flush();
            std.process.exit(1);
        }

        var manifest = plowman.plugin.loadPlugin(gpa, io, domain, plugins_dir) catch |e| switch (e) {
            error.PluginNotFound => {
                try printUsage(err);
                std.process.exit(1);
            },
            else => {
                try err.print("error loading plugin '{s}': {}\n", .{ domain, e });
                try err.flush();
                std.process.exit(1);
            },
        };
        defer manifest.deinit(gpa);

        const plugin_cmd = subcmd;

        if (std.mem.eql(u8, plugin_cmd, "help")) {
            plowman.plugin.showHelp(&manifest, out) catch |e| {
                try err.print("error: {}\n", .{e});
                try err.flush();
                std.process.exit(1);
            };
            try out.flush();
        } else {
            // Collect extra_args and check --dry-run
            var extra_args: std.ArrayList([]const u8) = .empty;
            var dry_run = false;
            for (args[3..]) |a| {
                if (std.mem.eql(u8, a, "--dry-run")) {
                    dry_run = true;
                } else {
                    try extra_args.append(init.arena.allocator(), a);
                }
            }

            const exit_code = plowman.plugin.runCommand(
                gpa,
                io,
                &manifest,
                plugin_cmd,
                extra_args.items,
                dry_run,
                out,
                err,
            ) catch |e| blk: {
                try err.print("error running command: {}\n", .{e});
                try err.flush();
                break :blk 1;
            };
            if (exit_code != 0) std.process.exit(exit_code);
        }
    }
}

fn printUsage(w: *std.Io.Writer) !void {
    try w.print("usage: plowman <command> [args]\n", .{});
    try w.print("commands:\n", .{});
    try w.print("  scan repo <path> [--json]        scan a repository\n", .{});
    try w.print("  scan db  <dump.sql> [--json]     analyze a SQL dump\n", .{});
    try w.print("  scan log <file> [--json]         analyze a log file\n", .{});
    try w.print("  plugin install <manifest.yml>    install a plugin\n", .{});
    try w.print("  plugin list                      list installed plugins\n", .{});
    try w.print("  <domain> help                    show plugin commands\n", .{});
    try w.print("  <domain> <command> [--dry-run]   run a plugin command\n", .{});
    try w.print("  doctor                           check dependencies and plugins\n", .{});
    try w.flush();
}
