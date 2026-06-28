const std = @import("std");

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
