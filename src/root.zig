const std = @import("std");

pub const plugin = @import("plugin.zig");
pub const doctor = @import("doctor.zig");

pub const Framework = enum {
    nodejs,
    python,
    go,
    zig_lang,
    rust,
    ruby,
    php,
    java_maven,
    java_gradle,
    flutter,
    elixir,
    unknown,

    pub fn displayName(self: Framework) []const u8 {
        return switch (self) {
            .nodejs => "Node.js",
            .python => "Python",
            .go => "Go",
            .zig_lang => "Zig",
            .rust => "Rust",
            .ruby => "Ruby",
            .php => "PHP",
            .java_maven => "Java (Maven)",
            .java_gradle => "Java (Gradle)",
            .flutter => "Flutter/Dart",
            .elixir => "Elixir",
            .unknown => "Unknown",
        };
    }
};

pub const Dependency = struct {
    name: []u8,
    dev: bool,
};

pub const ScanResult = struct {
    path: []u8,
    framework: Framework,
    has_dockerfile: bool,
    directories: std.ArrayList([]u8),
    dependencies: std.ArrayList(Dependency),
    config_files: std.ArrayList([]u8),

    pub fn deinit(self: *ScanResult, gpa: std.mem.Allocator) void {
        gpa.free(self.path);
        for (self.directories.items) |d| gpa.free(d);
        self.directories.deinit(gpa);
        for (self.dependencies.items) |dep| gpa.free(dep.name);
        self.dependencies.deinit(gpa);
        for (self.config_files.items) |f| gpa.free(f);
        self.config_files.deinit(gpa);
    }

    pub fn writeMarkdown(self: *const ScanResult, out: *std.Io.Writer) !void {
        try out.print("# Repo Analysis: {s}\n\n", .{self.path});

        try out.print("## Overview\n\n", .{});
        try out.print("- **Framework:** {s}\n", .{self.framework.displayName()});
        if (self.has_dockerfile) {
            try out.print("- **Containerized:** Yes\n", .{});
        }
        try out.print("\n", .{});

        if (self.config_files.items.len > 0) {
            try out.print("## Config & Manifest Files\n\n", .{});
            for (self.config_files.items) |f| {
                try out.print("- `{s}`\n", .{f});
            }
            try out.print("\n", .{});
        }

        if (self.directories.items.len > 0) {
            try out.print("## Directory Structure\n\n", .{});
            try out.print("```\n", .{});
            for (self.directories.items) |d| {
                try out.print("{s}/\n", .{d});
            }
            try out.print("```\n\n", .{});
        }

        const dep_count = self.dependencies.items.len;
        if (dep_count > 0) {
            try out.print("## Dependencies ({d} total)\n\n", .{dep_count});
            var prod: usize = 0;
            var dev_count: usize = 0;
            for (self.dependencies.items) |dep| {
                if (dep.dev) dev_count += 1 else prod += 1;
            }
            if (prod > 0) {
                try out.print("### Production ({d})\n\n", .{prod});
                for (self.dependencies.items) |dep| {
                    if (!dep.dev) try out.print("- {s}\n", .{dep.name});
                }
                try out.print("\n", .{});
            }
            if (dev_count > 0) {
                try out.print("### Development ({d})\n\n", .{dev_count});
                for (self.dependencies.items) |dep| {
                    if (dep.dev) try out.print("- {s}\n", .{dep.name});
                }
                try out.print("\n", .{});
            }
        } else {
            try out.print("## Dependencies\n\nNone detected.\n\n", .{});
        }
    }

    pub fn writeJson(self: *const ScanResult, out: *std.Io.Writer) !void {
        try out.print("{{\n", .{});
        try out.print("  \"path\": \"{s}\",\n", .{self.path});
        try out.print("  \"framework\": \"{s}\",\n", .{self.framework.displayName()});
        try out.print("  \"hasDockerfile\": {s},\n", .{if (self.has_dockerfile) "true" else "false"});

        try out.print("  \"configFiles\": [", .{});
        for (self.config_files.items, 0..) |f, i| {
            if (i > 0) try out.print(", ", .{});
            try out.print("\"{s}\"", .{f});
        }
        try out.print("],\n", .{});

        try out.print("  \"directories\": [", .{});
        for (self.directories.items, 0..) |d, i| {
            if (i > 0) try out.print(", ", .{});
            try out.print("\"{s}\"", .{d});
        }
        try out.print("],\n", .{});

        try out.print("  \"dependencies\": {{\n", .{});
        try out.print("    \"production\": [", .{});
        var first = true;
        for (self.dependencies.items) |dep| {
            if (!dep.dev) {
                if (!first) try out.print(", ", .{});
                try out.print("\"{s}\"", .{dep.name});
                first = false;
            }
        }
        try out.print("],\n", .{});
        try out.print("    \"development\": [", .{});
        first = true;
        for (self.dependencies.items) |dep| {
            if (dep.dev) {
                if (!first) try out.print(", ", .{});
                try out.print("\"{s}\"", .{dep.name});
                first = false;
            }
        }
        try out.print("]\n", .{});
        try out.print("  }}\n", .{});
        try out.print("}}\n", .{});
    }
};

const FRAMEWORK_INDICATORS = [_]struct { file: []const u8, fw: Framework }{
    .{ .file = "package.json", .fw = .nodejs },
    .{ .file = "go.mod", .fw = .go },
    .{ .file = "build.zig", .fw = .zig_lang },
    .{ .file = "Cargo.toml", .fw = .rust },
    .{ .file = "pyproject.toml", .fw = .python },
    .{ .file = "requirements.txt", .fw = .python },
    .{ .file = "setup.py", .fw = .python },
    .{ .file = "Gemfile", .fw = .ruby },
    .{ .file = "composer.json", .fw = .php },
    .{ .file = "pom.xml", .fw = .java_maven },
    .{ .file = "build.gradle", .fw = .java_gradle },
    .{ .file = "pubspec.yaml", .fw = .flutter },
    .{ .file = "mix.exs", .fw = .elixir },
};

const KNOWN_CONFIG_FILES = [_][]const u8{
    "package.json",    "package-lock.json", "yarn.lock",          "pnpm-lock.yaml",
    "pyproject.toml",  "requirements.txt",  "setup.py",           "setup.cfg",
    "go.mod",          "go.sum",
    "build.zig",       "build.zig.zon",
    "Cargo.toml",      "Cargo.lock",
    "Gemfile",         "Gemfile.lock",
    "composer.json",   "composer.lock",
    "pom.xml",         "build.gradle",      "build.gradle.kts",
    "pubspec.yaml",    "mix.exs",
    "Dockerfile",      "docker-compose.yml", "docker-compose.yaml",
    ".env.example",    ".env.sample",
    "tsconfig.json",   "jsconfig.json",
    ".eslintrc.json",  ".eslintrc.js",
    ".prettierrc",     ".prettierrc.json",
    "Makefile",        "justfile",           "Taskfile.yml",
    "netlify.toml",    "vercel.json",
};

const SKIP_DIRS = [_][]const u8{
    "node_modules", ".git",     "vendor",   "__pycache__",
    ".next",        "dist",     "target",   "zig-out",
    ".zig-cache",   ".cache",   "coverage", ".venv",
    "venv",         ".tox",     "tmp",      "temp",
};

fn shouldSkipDir(name: []const u8) bool {
    for (SKIP_DIRS) |s| {
        if (std.mem.eql(u8, name, s)) return true;
    }
    return false;
}

pub fn scanRepo(gpa: std.mem.Allocator, io: std.Io, path: []const u8) !ScanResult {
    const stored_path = try gpa.dupe(u8, path);
    errdefer gpa.free(stored_path);

    var dir = try std.Io.Dir.openDirAbsolute(io, stored_path, .{ .iterate = true });
    defer dir.close(io);

    var result = ScanResult{
        .path = stored_path,
        .framework = .unknown,
        .has_dockerfile = false,
        .directories = .empty,
        .dependencies = .empty,
        .config_files = .empty,
    };
    errdefer {
        for (result.directories.items) |d| gpa.free(d);
        result.directories.deinit(gpa);
        for (result.dependencies.items) |dep| gpa.free(dep.name);
        result.dependencies.deinit(gpa);
        for (result.config_files.items) |f| gpa.free(f);
        result.config_files.deinit(gpa);
    }

    // Scan root: detect framework + collect config files
    {
        var it = dir.iterate();
        while (try it.next(io)) |entry| {
            if (entry.kind != .file) continue;

            if (result.framework == .unknown) {
                for (FRAMEWORK_INDICATORS) |ind| {
                    if (std.mem.eql(u8, entry.name, ind.file)) {
                        result.framework = ind.fw;
                        break;
                    }
                }
            }

            if (std.mem.eql(u8, entry.name, "Dockerfile")) {
                result.has_dockerfile = true;
            }

            for (KNOWN_CONFIG_FILES) |known| {
                if (std.mem.eql(u8, entry.name, known)) {
                    try result.config_files.append(gpa, try gpa.dupe(u8, entry.name));
                    break;
                }
            }
        }
    }

    try walkDirs(gpa, io, dir, "", 0, &result);
    try extractDeps(gpa, io, dir, result.framework, &result);

    return result;
}

fn walkDirs(gpa: std.mem.Allocator, io: std.Io, dir: std.Io.Dir, rel_prefix: []const u8, depth: u8, result: *ScanResult) !void {
    if (depth >= 3) return;

    var names: std.ArrayList([]u8) = .empty;
    defer {
        for (names.items) |n| gpa.free(n);
        names.deinit(gpa);
    }

    {
        var it = dir.iterate();
        while (try it.next(io)) |entry| {
            if (entry.kind != .directory) continue;
            if (shouldSkipDir(entry.name)) continue;
            try names.append(gpa, try gpa.dupe(u8, entry.name));
        }
    }

    for (names.items) |name| {
        {
            const rel_path = if (rel_prefix.len == 0)
                try gpa.dupe(u8, name)
            else
                try std.fmt.allocPrint(gpa, "{s}/{s}", .{ rel_prefix, name });
            errdefer gpa.free(rel_path);
            try result.directories.append(gpa, rel_path);
        }

        const stored = result.directories.items[result.directories.items.len - 1];
        var sub = dir.openDir(io, name, .{ .iterate = true }) catch continue;
        defer sub.close(io);
        try walkDirs(gpa, io, sub, stored, depth + 1, result);
    }
}

fn extractDeps(gpa: std.mem.Allocator, io: std.Io, dir: std.Io.Dir, framework: Framework, result: *ScanResult) !void {
    switch (framework) {
        .nodejs => try extractNodeDeps(gpa, io, dir, result),
        .python => try extractPythonDeps(gpa, io, dir, result),
        .go => try extractGoDeps(gpa, io, dir, result),
        .rust => try extractRustDeps(gpa, io, dir, result),
        .ruby => try extractRubyDeps(gpa, io, dir, result),
        else => {},
    }
}

fn readFileAlloc(gpa: std.mem.Allocator, io: std.Io, dir: std.Io.Dir, name: []const u8) !?[]u8 {
    const file = dir.openFile(io, name, .{}) catch return null;
    defer file.close(io);
    var read_buf: [4096]u8 = undefined;
    var r = file.reader(io, &read_buf);
    return try r.interface.allocRemaining(gpa, .limited(10 * 1024 * 1024));
}

fn extractNodeDeps(gpa: std.mem.Allocator, io: std.Io, dir: std.Io.Dir, result: *ScanResult) !void {
    const content = (try readFileAlloc(gpa, io, dir, "package.json")) orelse return;
    defer gpa.free(content);

    const parsed = std.json.parseFromSlice(std.json.Value, gpa, content, .{}) catch return;
    defer parsed.deinit();

    if (parsed.value != .object) return;

    const dep_kinds = [_]struct { key: []const u8, dev: bool }{
        .{ .key = "dependencies", .dev = false },
        .{ .key = "devDependencies", .dev = true },
    };
    for (dep_kinds) |kind| {
        const deps = parsed.value.object.get(kind.key) orelse continue;
        if (deps != .object) continue;
        var it = deps.object.iterator();
        while (it.next()) |entry| {
            const name = try gpa.dupe(u8, entry.key_ptr.*);
            try result.dependencies.append(gpa, .{ .name = name, .dev = kind.dev });
        }
    }
}

fn extractPythonDeps(gpa: std.mem.Allocator, io: std.Io, dir: std.Io.Dir, result: *ScanResult) !void {
    const content = (try readFileAlloc(gpa, io, dir, "requirements.txt")) orelse return;
    defer gpa.free(content);

    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0 or trimmed[0] == '#') continue;
        const end = for (trimmed, 0..) |c, i| {
            if (c == '>' or c == '<' or c == '=' or c == '!' or c == '[' or c == ';') break i;
        } else trimmed.len;
        const name = std.mem.trimEnd(u8, trimmed[0..end], " \t");
        if (name.len == 0) continue;
        try result.dependencies.append(gpa, .{ .name = try gpa.dupe(u8, name), .dev = false });
    }
}

fn extractGoDeps(gpa: std.mem.Allocator, io: std.Io, dir: std.Io.Dir, result: *ScanResult) !void {
    const content = (try readFileAlloc(gpa, io, dir, "go.mod")) orelse return;
    defer gpa.free(content);

    var in_require = false;
    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (std.mem.startsWith(u8, trimmed, "require (")) {
            in_require = true;
            continue;
        }
        if (in_require and std.mem.eql(u8, trimmed, ")")) {
            in_require = false;
            continue;
        }
        const dep_line: []const u8 = if (std.mem.startsWith(u8, trimmed, "require "))
            trimmed["require ".len..]
        else if (in_require)
            trimmed
        else
            continue;

        const space = std.mem.indexOfScalar(u8, dep_line, ' ') orelse dep_line.len;
        const name = std.mem.trim(u8, dep_line[0..space], " \t");
        if (name.len == 0 or std.mem.startsWith(u8, name, "//")) continue;
        try result.dependencies.append(gpa, .{ .name = try gpa.dupe(u8, name), .dev = false });
    }
}

fn extractRustDeps(gpa: std.mem.Allocator, io: std.Io, dir: std.Io.Dir, result: *ScanResult) !void {
    const content = (try readFileAlloc(gpa, io, dir, "Cargo.toml")) orelse return;
    defer gpa.free(content);

    var in_deps = false;
    var in_dev = false;
    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (std.mem.eql(u8, trimmed, "[dependencies]")) {
            in_deps = true;
            in_dev = false;
            continue;
        }
        if (std.mem.eql(u8, trimmed, "[dev-dependencies]")) {
            in_deps = false;
            in_dev = true;
            continue;
        }
        if (trimmed.len > 0 and trimmed[0] == '[') {
            in_deps = false;
            in_dev = false;
            continue;
        }
        if (!(in_deps or in_dev)) continue;
        if (trimmed.len == 0 or trimmed[0] == '#') continue;
        const eq = std.mem.indexOfScalar(u8, trimmed, '=') orelse continue;
        const name = std.mem.trim(u8, trimmed[0..eq], " \t\"");
        if (name.len == 0) continue;
        try result.dependencies.append(gpa, .{ .name = try gpa.dupe(u8, name), .dev = in_dev });
    }
}

fn extractRubyDeps(gpa: std.mem.Allocator, io: std.Io, dir: std.Io.Dir, result: *ScanResult) !void {
    const content = (try readFileAlloc(gpa, io, dir, "Gemfile")) orelse return;
    defer gpa.free(content);

    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (!std.mem.startsWith(u8, trimmed, "gem ")) continue;
        var rest = trimmed["gem ".len..];
        if (rest.len == 0) continue;
        const quote = rest[0];
        if (quote != '\'' and quote != '"') continue;
        rest = rest[1..];
        const end = std.mem.indexOfScalar(u8, rest, quote) orelse continue;
        const name = rest[0..end];
        if (name.len == 0) continue;
        try result.dependencies.append(gpa, .{ .name = try gpa.dupe(u8, name), .dev = false });
    }
}

test "framework detection order: nodejs beats python" {
    try std.testing.expectEqual(Framework.nodejs, FRAMEWORK_INDICATORS[0].fw);
    try std.testing.expectEqual(@as([]const u8, "package.json"), FRAMEWORK_INDICATORS[0].file);
}

// ============================================================
// Shared helpers
// ============================================================

fn writeJsonStr(out: *std.Io.Writer, s: []const u8) !void {
    for (s) |c| {
        switch (c) {
            '"' => try out.writeAll("\\\""),
            '\\' => try out.writeAll("\\\\"),
            '\n' => try out.writeAll("\\n"),
            '\r' => try out.writeAll("\\r"),
            '\t' => try out.writeAll("\\t"),
            else => try out.writeByte(c),
        }
    }
}

fn fileBasename(path: []const u8) []const u8 {
    if (std.mem.lastIndexOfScalar(u8, path, '/')) |i| return path[i + 1 ..];
    return path;
}

fn startsWithCI(s: []const u8, prefix: []const u8) bool {
    if (s.len < prefix.len) return false;
    for (prefix, 0..) |p, i| {
        if (std.ascii.toLower(s[i]) != std.ascii.toLower(p)) return false;
    }
    return true;
}

// ============================================================
// DB SCANNER
// ============================================================

pub const DbDialect = enum {
    mysql,
    postgresql,
    sqlite,
    unknown,

    pub fn displayName(self: DbDialect) []const u8 {
        return switch (self) {
            .mysql => "MySQL",
            .postgresql => "PostgreSQL",
            .sqlite => "SQLite",
            .unknown => "Unknown",
        };
    }
};

pub const TableInfo = struct {
    name: []u8,
    row_estimate: u64,
    has_primary_key: bool,
    index_count: u32,
    is_cache_or_session: bool,
    is_log_or_audit: bool,

    fn deinit(self: *TableInfo, gpa: std.mem.Allocator) void {
        gpa.free(self.name);
    }
};

pub const DbScanResult = struct {
    path: []u8,
    dialect: DbDialect,
    tables: std.ArrayList(TableInfo),

    pub fn deinit(self: *DbScanResult, gpa: std.mem.Allocator) void {
        gpa.free(self.path);
        for (self.tables.items) |*t| t.deinit(gpa);
        self.tables.deinit(gpa);
    }

    pub fn writeMarkdown(self: *const DbScanResult, out: *std.Io.Writer) !void {
        try out.print("# DB Analysis: {s}\n\n", .{fileBasename(self.path)});

        var total_rows: u64 = 0;
        for (self.tables.items) |t| total_rows += t.row_estimate;

        try out.print("## Overview\n\n", .{});
        try out.print("- **Dialect:** {s}\n", .{self.dialect.displayName()});
        try out.print("- **Tables:** {d}\n", .{self.tables.items.len});
        try out.print("- **Estimated rows:** {d}\n\n", .{total_rows});

        if (self.tables.items.len > 0) {
            try out.print("## Tables (ranked by estimated size)\n\n", .{});
            try out.print("| Table | Est. Rows | Primary Key | Indexes | Flags |\n", .{});
            try out.print("|-------|-----------|-------------|---------|-------|\n", .{});
            for (self.tables.items) |t| {
                const flags: []const u8 = blk: {
                    if (t.is_cache_or_session and t.is_log_or_audit) break :blk "cache/session, log/audit";
                    if (t.is_cache_or_session) break :blk "cache/session";
                    if (t.is_log_or_audit) break :blk "log/audit";
                    break :blk "—";
                };
                try out.print("| {s} | {d} | {s} | {d} | {s} |\n", .{
                    t.name,
                    t.row_estimate,
                    if (t.has_primary_key) "yes" else "no",
                    t.index_count,
                    flags,
                });
            }
            try out.print("\n", .{});
        }

        var has_issues = false;
        for (self.tables.items) |t| {
            if (!t.has_primary_key or t.index_count == 0 or t.is_cache_or_session or t.is_log_or_audit) {
                has_issues = true;
                break;
            }
        }

        if (has_issues) {
            try out.print("## Issues\n\n", .{});
            {
                var any = false;
                for (self.tables.items) |t| {
                    if (!t.has_primary_key) { any = true; break; }
                }
                if (any) {
                    try out.print("### No primary key\n\n", .{});
                    for (self.tables.items) |t| {
                        if (!t.has_primary_key) try out.print("- `{s}` — full table scans on lookups\n", .{t.name});
                    }
                    try out.print("\n", .{});
                }
            }
            {
                var any = false;
                for (self.tables.items) |t| {
                    if (t.index_count == 0) { any = true; break; }
                }
                if (any) {
                    try out.print("### No indexes\n\n", .{});
                    for (self.tables.items) |t| {
                        if (t.index_count == 0) try out.print("- `{s}` — all queries do full table scans\n", .{t.name});
                    }
                    try out.print("\n", .{});
                }
            }
            {
                var any = false;
                for (self.tables.items) |t| {
                    if (t.is_cache_or_session) { any = true; break; }
                }
                if (any) {
                    try out.print("### Cache/session tables\n\n", .{});
                    for (self.tables.items) |t| {
                        if (t.is_cache_or_session) try out.print("- `{s}` — consider Redis or Memcached\n", .{t.name});
                    }
                    try out.print("\n", .{});
                }
            }
            {
                var any = false;
                for (self.tables.items) |t| {
                    if (t.is_log_or_audit) { any = true; break; }
                }
                if (any) {
                    try out.print("### Log/audit tables\n\n", .{});
                    for (self.tables.items) |t| {
                        if (t.is_log_or_audit) try out.print("- `{s}` — index by timestamp; archive old rows\n", .{t.name});
                    }
                    try out.print("\n", .{});
                }
            }
        }
    }

    pub fn writeJson(self: *const DbScanResult, out: *std.Io.Writer) !void {
        var total_rows: u64 = 0;
        for (self.tables.items) |t| total_rows += t.row_estimate;

        try out.print("{{\n", .{});
        try out.print("  \"path\": \"", .{});
        try writeJsonStr(out, self.path);
        try out.print("\",\n", .{});
        try out.print("  \"dialect\": \"{s}\",\n", .{self.dialect.displayName()});
        try out.print("  \"tableCount\": {d},\n", .{self.tables.items.len});
        try out.print("  \"estimatedRows\": {d},\n", .{total_rows});
        try out.print("  \"tables\": [\n", .{});
        for (self.tables.items, 0..) |t, i| {
            try out.print("    {{\"name\": \"", .{});
            try writeJsonStr(out, t.name);
            try out.print("\", \"rowEstimate\": {d}, \"hasPrimaryKey\": {s}, \"indexCount\": {d}, \"isCacheOrSession\": {s}, \"isLogOrAudit\": {s}}}", .{
                t.row_estimate,
                if (t.has_primary_key) "true" else "false",
                t.index_count,
                if (t.is_cache_or_session) "true" else "false",
                if (t.is_log_or_audit) "true" else "false",
            });
            if (i + 1 < self.tables.items.len) try out.print(",", .{});
            try out.print("\n", .{});
        }
        try out.print("  ],\n", .{});
        try out.print("  \"issues\": {{\n", .{});

        const issue_lists = [_]struct { key: []const u8, field: enum { nopk, noidx, cache, log } }{
            .{ .key = "noPrimaryKey", .field = .nopk },
            .{ .key = "noIndexes", .field = .noidx },
            .{ .key = "cacheOrSession", .field = .cache },
            .{ .key = "logOrAudit", .field = .log },
        };
        for (issue_lists, 0..) |il, li| {
            try out.print("    \"{s}\": [", .{il.key});
            var first = true;
            for (self.tables.items) |t| {
                const match = switch (il.field) {
                    .nopk => !t.has_primary_key,
                    .noidx => t.index_count == 0,
                    .cache => t.is_cache_or_session,
                    .log => t.is_log_or_audit,
                };
                if (match) {
                    if (!first) try out.print(", ", .{});
                    try out.print("\"", .{});
                    try writeJsonStr(out, t.name);
                    try out.print("\"", .{});
                    first = false;
                }
            }
            if (li + 1 < issue_lists.len) {
                try out.print("],\n", .{});
            } else {
                try out.print("]\n", .{});
            }
        }
        try out.print("  }}\n", .{});
        try out.print("}}\n", .{});
    }
};

pub fn scanDb(gpa: std.mem.Allocator, io: std.Io, path: []const u8) !DbScanResult {
    const stored_path = try gpa.dupe(u8, path);
    errdefer gpa.free(stored_path);

    const file = try std.Io.Dir.openFileAbsolute(io, path, .{});
    defer file.close(io);
    var read_buf: [4096]u8 = undefined;
    var r = file.reader(io, &read_buf);
    const content = try r.interface.allocRemaining(gpa, .limited(50 * 1024 * 1024));
    defer gpa.free(content);

    var result = DbScanResult{
        .path = stored_path,
        .dialect = .unknown,
        .tables = .empty,
    };
    var in_table = false;
    var in_copy = false;
    var current: TableInfo = undefined;
    var copy_table_idx: usize = 0;

    errdefer {
        if (in_table) gpa.free(current.name);
        for (result.tables.items) |*t| t.deinit(gpa);
        result.tables.deinit(gpa);
    }

    var lines_iter = std.mem.splitScalar(u8, content, '\n');
    while (lines_iter.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) continue;

        // Dialect hints
        if (std.mem.indexOf(u8, trimmed, "-- MySQL dump") != null or
            std.mem.indexOf(u8, trimmed, "ENGINE=InnoDB") != null or
            std.mem.indexOf(u8, trimmed, "ENGINE=MyISAM") != null)
        {
            result.dialect = .mysql;
        }
        if (result.dialect != .mysql and
            (std.mem.indexOf(u8, trimmed, "-- PostgreSQL database dump") != null or
             std.mem.indexOf(u8, trimmed, "-- Dumped from database version") != null))
        {
            result.dialect = .postgresql;
        }
        if (result.dialect == .unknown and
            (std.mem.indexOf(u8, trimmed, "PRAGMA ") != null or
             std.mem.eql(u8, trimmed, ".dump")))
        {
            result.dialect = .sqlite;
        }

        if (in_copy) {
            if (std.mem.eql(u8, trimmed, "\\.")) {
                in_copy = false;
            } else {
                result.tables.items[copy_table_idx].row_estimate += 1;
            }
            continue;
        }

        if (in_table) {
            if (std.mem.indexOf(u8, trimmed, "PRIMARY KEY") != null) current.has_primary_key = true;
            if (startsWithCI(trimmed, "KEY ") or startsWithCI(trimmed, "UNIQUE KEY") or
                startsWithCI(trimmed, "INDEX ") or startsWithCI(trimmed, "UNIQUE INDEX"))
            {
                current.index_count += 1;
            }
            if (trimmed[0] == ')') {
                in_table = false;
                classifyTable(&current);
                try result.tables.append(gpa, current);
            }
            continue;
        }

        if (startsWithCI(trimmed, "CREATE TABLE")) {
            if (extractCreateTableName(trimmed)) |raw| {
                if (raw.len > 0) {
                    if (in_table) gpa.free(current.name);
                    const name = try gpa.dupe(u8, raw);
                    in_table = true;
                    current = .{
                        .name = name,
                        .row_estimate = 0,
                        .has_primary_key = false,
                        .index_count = 0,
                        .is_cache_or_session = false,
                        .is_log_or_audit = false,
                    };
                }
            }
            continue;
        }

        if (startsWithCI(trimmed, "INSERT INTO ")) {
            if (extractInsertTableName(trimmed)) |name| {
                for (result.tables.items) |*t| {
                    if (std.mem.eql(u8, t.name, name)) { t.row_estimate += 1; break; }
                }
            }
            continue;
        }

        if (startsWithCI(trimmed, "COPY ") and std.mem.indexOf(u8, trimmed, "FROM stdin") != null) {
            if (extractCopyTableName(trimmed)) |name| {
                for (result.tables.items, 0..) |t, idx| {
                    if (std.mem.eql(u8, t.name, name)) {
                        copy_table_idx = idx;
                        in_copy = true;
                        break;
                    }
                }
            }
            continue;
        }
    }

    if (in_table) {
        gpa.free(current.name);
        in_table = false;
    }

    std.mem.sort(TableInfo, result.tables.items, {}, struct {
        fn gt(_: void, a: TableInfo, b: TableInfo) bool {
            return a.row_estimate > b.row_estimate;
        }
    }.gt);

    return result;
}

fn extractCreateTableName(line: []const u8) ?[]const u8 {
    var rest = line;
    if (!startsWithCI(rest, "CREATE TABLE")) return null;
    rest = rest["CREATE TABLE".len..];
    rest = std.mem.trimStart(u8, rest, " \t");
    if (startsWithCI(rest, "IF NOT EXISTS")) rest = rest["IF NOT EXISTS".len..];
    rest = std.mem.trimStart(u8, rest, " \t");
    if (rest.len == 0) return null;

    if (rest[0] == '`' or rest[0] == '"' or rest[0] == '\'') {
        const q = rest[0];
        rest = rest[1..];
        const end = std.mem.indexOfScalar(u8, rest, q) orelse return null;
        return if (end > 0) rest[0..end] else null;
    }

    const end = for (rest, 0..) |c, i| {
        if (c == ' ' or c == '\t' or c == '(' or c == '\n' or c == '\r') break i;
    } else rest.len;

    const name = rest[0..end];
    if (name.len == 0) return null;
    if (std.mem.lastIndexOfScalar(u8, name, '.')) |dot| {
        const tbl = name[dot + 1 ..];
        return if (tbl.len > 0) tbl else null;
    }
    return name;
}

fn extractInsertTableName(line: []const u8) ?[]const u8 {
    const prefix = "INSERT INTO ";
    if (!startsWithCI(line, prefix)) return null;
    var rest = line[prefix.len..];
    rest = std.mem.trimStart(u8, rest, " \t");
    if (rest.len == 0) return null;

    if (rest[0] == '`' or rest[0] == '"' or rest[0] == '\'') {
        const q = rest[0];
        rest = rest[1..];
        const end = std.mem.indexOfScalar(u8, rest, q) orelse return null;
        return if (end > 0) rest[0..end] else null;
    }

    const end = for (rest, 0..) |c, i| {
        if (c == ' ' or c == '\t' or c == '(' or c == ';') break i;
    } else rest.len;
    return if (end > 0) rest[0..end] else null;
}

fn extractCopyTableName(line: []const u8) ?[]const u8 {
    const prefix = "COPY ";
    if (!startsWithCI(line, prefix)) return null;
    var rest = line[prefix.len..];
    rest = std.mem.trimStart(u8, rest, " \t");
    if (rest.len == 0) return null;

    const end = for (rest, 0..) |c, i| {
        if (c == ' ' or c == '\t' or c == '(' or c == ';') break i;
    } else rest.len;

    const name = rest[0..end];
    if (name.len == 0) return null;
    if (std.mem.lastIndexOfScalar(u8, name, '.')) |dot| {
        const tbl = name[dot + 1 ..];
        return if (tbl.len > 0) tbl else null;
    }
    return name;
}

const CACHE_SESSION_MARKERS = [_][]const u8{ "session", "cache", "queue", "token", "lock" };
const LOG_AUDIT_MARKERS = [_][]const u8{ "log", "audit", "event", "history", "track" };

fn classifyTable(t: *TableInfo) void {
    var buf: [128]u8 = undefined;
    const len = @min(t.name.len, buf.len);
    for (t.name[0..len], 0..) |c, i| buf[i] = std.ascii.toLower(c);
    const lower = buf[0..len];
    for (CACHE_SESSION_MARKERS) |m| {
        if (std.mem.indexOf(u8, lower, m) != null) { t.is_cache_or_session = true; break; }
    }
    for (LOG_AUDIT_MARKERS) |m| {
        if (std.mem.indexOf(u8, lower, m) != null) { t.is_log_or_audit = true; break; }
    }
}

// ============================================================
// LOG SCANNER
// ============================================================

pub const LogSeverity = enum {
    fatal,
    err,
    warn,
    info,
    unknown,

    pub fn displayName(self: LogSeverity) []const u8 {
        return switch (self) {
            .fatal => "FATAL",
            .err => "ERROR",
            .warn => "WARN",
            .info => "INFO",
            .unknown => "UNKNOWN",
        };
    }
};

pub const LogPattern = struct {
    text: []u8,
    severity: LogSeverity,
    count: u64,

    fn deinit(self: *LogPattern, gpa: std.mem.Allocator) void {
        gpa.free(self.text);
    }
};

pub const LogScanResult = struct {
    path: []u8,
    total_lines: u64,
    error_count: u64,
    warn_count: u64,
    patterns: std.ArrayList(LogPattern),

    pub fn deinit(self: *LogScanResult, gpa: std.mem.Allocator) void {
        gpa.free(self.path);
        for (self.patterns.items) |*p| p.deinit(gpa);
        self.patterns.deinit(gpa);
    }

    pub fn writeMarkdown(self: *const LogScanResult, out: *std.Io.Writer) !void {
        try out.print("# Log Analysis: {s}\n\n", .{fileBasename(self.path)});
        try out.print("## Overview\n\n", .{});
        try out.print("- **Total lines:** {d}\n", .{self.total_lines});
        try out.print("- **Errors:** {d}\n", .{self.error_count});
        try out.print("- **Warnings:** {d}\n\n", .{self.warn_count});

        if (self.patterns.items.len > 0) {
            try out.print("## Top Error Patterns\n\n", .{});
            for (self.patterns.items, 0..) |p, i| {
                const max_len: usize = 120;
                const display = if (p.text.len > max_len) p.text[0..max_len] else p.text;
                try out.print("{d}. **{s}** (×{d}): {s}\n", .{
                    i + 1, p.severity.displayName(), p.count, display,
                });
            }
            try out.print("\n", .{});

            try out.print("## Recommendations\n\n", .{});
            var repeat_count: usize = 0;
            var fatal_count: u64 = 0;
            for (self.patterns.items) |p| {
                if (p.count > 1) repeat_count += 1;
                if (p.severity == .fatal) fatal_count += p.count;
            }
            if (repeat_count > 0) {
                const plural: []const u8 = if (repeat_count == 1) "" else "s";
                try out.print("- **Repeat failures:** {d} pattern{s} appear more than once — investigate root cause\n", .{
                    repeat_count, plural,
                });
            }
            if (fatal_count > 0) {
                try out.print("- **FATAL events:** {d} detected — review immediately\n", .{fatal_count});
            }
            try out.print("\n", .{});
        } else {
            try out.print("No error or warning patterns found.\n\n", .{});
        }
    }

    pub fn writeJson(self: *const LogScanResult, out: *std.Io.Writer) !void {
        try out.print("{{\n", .{});
        try out.print("  \"path\": \"", .{});
        try writeJsonStr(out, self.path);
        try out.print("\",\n", .{});
        try out.print("  \"totalLines\": {d},\n", .{self.total_lines});
        try out.print("  \"errorCount\": {d},\n", .{self.error_count});
        try out.print("  \"warnCount\": {d},\n", .{self.warn_count});
        try out.print("  \"topPatterns\": [\n", .{});
        for (self.patterns.items, 0..) |p, i| {
            try out.print("    {{\"severity\": \"{s}\", \"count\": {d}, \"pattern\": \"", .{
                p.severity.displayName(), p.count,
            });
            try writeJsonStr(out, p.text);
            try out.print("\"}}", .{});
            if (i + 1 < self.patterns.items.len) try out.print(",", .{});
            try out.print("\n", .{});
        }
        try out.print("  ]\n", .{});
        try out.print("}}\n", .{});
    }
};

pub fn scanLog(gpa: std.mem.Allocator, io: std.Io, path: []const u8) !LogScanResult {
    const stored_path = try gpa.dupe(u8, path);
    errdefer gpa.free(stored_path);

    const file = try std.Io.Dir.openFileAbsolute(io, path, .{});
    defer file.close(io);
    var read_buf: [4096]u8 = undefined;
    var r = file.reader(io, &read_buf);
    const content = try r.interface.allocRemaining(gpa, .limited(50 * 1024 * 1024));
    defer gpa.free(content);

    var total_lines: u64 = 0;
    var error_count: u64 = 0;
    var warn_count: u64 = 0;

    const NormLine = struct { text: []const u8, severity: LogSeverity };
    var norm_lines: std.ArrayList(NormLine) = .empty;
    defer norm_lines.deinit(gpa);

    var line_iter = std.mem.splitScalar(u8, content, '\n');
    while (line_iter.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) continue;
        total_lines += 1;

        const sev = detectSeverity(trimmed);
        switch (sev) {
            .fatal, .err => {
                error_count += 1;
                try norm_lines.append(gpa, .{ .text = stripTimestamp(trimmed), .severity = sev });
            },
            .warn => {
                warn_count += 1;
                try norm_lines.append(gpa, .{ .text = stripTimestamp(trimmed), .severity = sev });
            },
            .info, .unknown => {},
        }
    }

    std.mem.sort(NormLine, norm_lines.items, {}, struct {
        fn lt(_: void, a: NormLine, b: NormLine) bool {
            return std.mem.order(u8, a.text, b.text) == .lt;
        }
    }.lt);

    const PatternEntry = struct { text: []const u8, severity: LogSeverity, count: u64 };
    var groups: std.ArrayList(PatternEntry) = .empty;
    defer groups.deinit(gpa);

    {
        var i: usize = 0;
        while (i < norm_lines.items.len) {
            const cur = norm_lines.items[i];
            var j = i + 1;
            while (j < norm_lines.items.len and std.mem.eql(u8, norm_lines.items[j].text, cur.text)) {
                j += 1;
            }
            try groups.append(gpa, .{ .text = cur.text, .severity = cur.severity, .count = j - i });
            i = j;
        }
    }

    std.mem.sort(PatternEntry, groups.items, {}, struct {
        fn gt(_: void, a: PatternEntry, b: PatternEntry) bool {
            return a.count > b.count;
        }
    }.gt);

    var result = LogScanResult{
        .path = stored_path,
        .total_lines = total_lines,
        .error_count = error_count,
        .warn_count = warn_count,
        .patterns = .empty,
    };
    errdefer {
        for (result.patterns.items) |*p| p.deinit(gpa);
        result.patterns.deinit(gpa);
    }

    const top_n = @min(groups.items.len, 20);
    for (groups.items[0..top_n]) |g| {
        const text_owned = try gpa.dupe(u8, g.text);
        errdefer gpa.free(text_owned);
        try result.patterns.append(gpa, .{
            .text = text_owned,
            .severity = g.severity,
            .count = g.count,
        });
    }

    return result;
}

fn detectSeverity(line: []const u8) LogSeverity {
    // Check explicit markers first so [ERROR] PHP Fatal error: → ERROR, not FATAL
    if (containsCI(line, "[FATAL]") or containsCI(line, "FATAL:") or
        containsCI(line, "[CRITICAL]") or containsCI(line, "CRITICAL:") or
        containsCI(line, "[EMERG]") or containsCI(line, "EMERG:"))
    {
        return .fatal;
    }
    if (containsCI(line, "[ERROR]") or containsCI(line, "ERROR:") or
        containsCI(line, "Traceback") or containsCI(line, "STDERR"))
    {
        return .err;
    }
    if (containsCI(line, "[WARN]") or containsCI(line, "WARN:") or
        containsCI(line, "[WARNING]") or containsCI(line, "WARNING:"))
    {
        return .warn;
    }
    // Broader fallbacks (may match words inside messages)
    if (containsCI(line, "FATAL") or containsCI(line, "CRITICAL")) return .fatal;
    if (containsCI(line, "ERROR") or containsCI(line, "Exception") or containsCI(line, "EXCEPTION")) return .err;
    if (containsCI(line, "WARN")) return .warn;
    if (containsCI(line, "INFO") or containsCI(line, "DEBUG") or containsCI(line, "NOTICE")) return .info;
    return .unknown;
}

fn containsCI(haystack: []const u8, needle: []const u8) bool {
    if (needle.len > haystack.len) return false;
    var i: usize = 0;
    while (i + needle.len <= haystack.len) : (i += 1) {
        var match = true;
        for (needle, 0..) |nc, j| {
            if (std.ascii.toLower(haystack[i + j]) != std.ascii.toLower(nc)) {
                match = false;
                break;
            }
        }
        if (match) return true;
    }
    return false;
}

fn stripTimestamp(line: []const u8) []const u8 {
    var i: usize = 0;
    if (i < line.len and line[i] == '[') i += 1;
    if (i < line.len and std.ascii.isDigit(line[i])) {
        const ts_start = i;
        while (i < line.len) {
            const c = line[i];
            if (std.ascii.isDigit(c) or c == '/' or c == '-' or c == ':' or
                c == '.' or c == 'T' or c == 'Z' or c == '+' or c == ' ')
            {
                i += 1;
            } else break;
        }
        if (i - ts_start >= 8) {
            if (i < line.len and line[i] == ']') i += 1;
            while (i < line.len and (line[i] == ' ' or line[i] == '\t')) i += 1;
            return line[i..];
        }
    }
    return line;
}
