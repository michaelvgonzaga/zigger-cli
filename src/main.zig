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

    if (args.len < 3) {
        try printUsage(err);
        std.process.exit(1);
    }

    const subcmd = args[2];
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
    } else {
        try printUsage(err);
        std.process.exit(1);
    }
}

fn printUsage(w: *std.Io.Writer) !void {
    try w.print("usage: plowman <command> [args]\n", .{});
    try w.print("commands:\n", .{});
    try w.print("  scan repo <path> [--json]     scan a repository\n", .{});
    try w.print("  scan db  <dump.sql> [--json]  analyze a SQL dump\n", .{});
    try w.print("  scan log <file> [--json]      analyze a log file\n", .{});
    try w.flush();
}
