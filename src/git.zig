const std = @import("std");

const COMMIT_MARKER = "PLOWMAN_COMMIT";
const WINDOW_DAYS: u32 = 90;
const MAX_FILES_PER_COMMIT: usize = 50;
const TOP_N: usize = 10;

// ── Public types ──────────────────────────────────────────────

pub const HotspotEntry = struct {
    path: []u8,
    commit_count: u64,

    fn deinit(self: *HotspotEntry, gpa: std.mem.Allocator) void {
        gpa.free(self.path);
    }
};

pub const CoChangePair = struct {
    path_a: []u8,
    path_b: []u8,
    count: u64,

    fn deinit(self: *CoChangePair, gpa: std.mem.Allocator) void {
        gpa.free(self.path_a);
        gpa.free(self.path_b);
    }
};

pub const StaleDir = struct {
    path: []u8,
    last_date: []u8,
    days_ago: u64,

    fn deinit(self: *StaleDir, gpa: std.mem.Allocator) void {
        gpa.free(self.path);
        gpa.free(self.last_date);
    }
};

pub const GitHistoryResult = struct {
    commit_count: u64,
    window_days: u32,
    hotspots: std.ArrayList(HotspotEntry),
    cochange_pairs: std.ArrayList(CoChangePair),
    stale_dirs: std.ArrayList(StaleDir),

    pub fn deinit(self: *GitHistoryResult, gpa: std.mem.Allocator) void {
        for (self.hotspots.items) |*h| h.deinit(gpa);
        self.hotspots.deinit(gpa);
        for (self.cochange_pairs.items) |*p| p.deinit(gpa);
        self.cochange_pairs.deinit(gpa);
        for (self.stale_dirs.items) |*s| s.deinit(gpa);
        self.stale_dirs.deinit(gpa);
    }

    pub fn writeMarkdown(self: *const GitHistoryResult, out: *std.Io.Writer) !void {
        try out.print("## Git History ({d} commits, last {d} days)\n\n", .{ self.commit_count, self.window_days });

        if (self.hotspots.items.len > 0) {
            try out.print("### Hotspots\n\n", .{});
            try out.print("| File | Commits |\n|------|--------|\n", .{});
            for (self.hotspots.items) |h| {
                try out.print("| `{s}` | {d} |\n", .{ h.path, h.commit_count });
            }
            try out.print("\n", .{});
        }

        if (self.cochange_pairs.items.len > 0) {
            try out.print("### Co-change pairs\n\n", .{});
            try out.print("| File A | File B | Co-commits |\n|--------|--------|------------|\n", .{});
            for (self.cochange_pairs.items) |p| {
                try out.print("| `{s}` | `{s}` | {d} |\n", .{ p.path_a, p.path_b, p.count });
            }
            try out.print("\n", .{});
        }

        if (self.stale_dirs.items.len > 0) {
            try out.print("### Stale modules (no commits in {d}+ days)\n\n", .{self.window_days});
            try out.print("| Directory | Last commit | Days ago |\n|-----------|-------------|----------|\n", .{});
            for (self.stale_dirs.items) |s| {
                try out.print("| `{s}` | {s} | {d} |\n", .{ s.path, s.last_date, s.days_ago });
            }
            try out.print("\n", .{});
        }
    }

    pub fn writeJson(self: *const GitHistoryResult, out: *std.Io.Writer) !void {
        try out.print("\"git_history\": {{\"commit_count\": {d}, \"window_days\": {d}", .{
            self.commit_count, self.window_days,
        });

        try out.print(", \"hotspots\": [", .{});
        for (self.hotspots.items, 0..) |h, i| {
            if (i > 0) try out.print(", ", .{});
            try out.print("{{\"path\": \"", .{});
            try writeJsonStr(out, h.path);
            try out.print("\", \"commit_count\": {d}}}", .{h.commit_count});
        }
        try out.print("]", .{});

        try out.print(", \"cochange_pairs\": [", .{});
        for (self.cochange_pairs.items, 0..) |p, i| {
            if (i > 0) try out.print(", ", .{});
            try out.print("{{\"a\": \"", .{});
            try writeJsonStr(out, p.path_a);
            try out.print("\", \"b\": \"", .{});
            try writeJsonStr(out, p.path_b);
            try out.print("\", \"count\": {d}}}", .{p.count});
        }
        try out.print("]", .{});

        try out.print(", \"stale_dirs\": [", .{});
        for (self.stale_dirs.items, 0..) |s, i| {
            if (i > 0) try out.print(", ", .{});
            try out.print("{{\"path\": \"", .{});
            try writeJsonStr(out, s.path);
            try out.print("\", \"last_date\": \"{s}\", \"days_ago\": {d}}}", .{ s.last_date, s.days_ago });
        }
        try out.print("]", .{});

        try out.print("}}", .{});
    }
};

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

// ── Scanner ───────────────────────────────────────────────────

pub fn scan(gpa: std.mem.Allocator, io: std.Io, repo_path: []const u8) ?GitHistoryResult {
    return scanInner(gpa, io, repo_path) catch null;
}

fn isGitRepo(io: std.Io, repo_path: []const u8, gpa: std.mem.Allocator) bool {
    const git_path = std.fmt.allocPrint(gpa, "{s}/.git", .{repo_path}) catch return false;
    defer gpa.free(git_path);
    const d = std.Io.Dir.openDirAbsolute(io, git_path, .{}) catch return false;
    d.close(io);
    return true;
}

fn scanInner(gpa: std.mem.Allocator, io: std.Io, repo_path: []const u8) !GitHistoryResult {
    if (!isGitRepo(io, repo_path, gpa)) return error.NotAGitRepo;

    // ── Step 1: parse git log for hotspots + co-change ───────
    const since_arg = std.fmt.allocPrint(gpa, "--since={d} days ago", .{WINDOW_DAYS}) catch
        return error.OutOfMemory;
    defer gpa.free(since_arg);

    const log_result = try std.process.run(gpa, io, .{
        .argv = &[_][]const u8{
            "git", "-C", repo_path, "log",
            since_arg, "--name-only",
            "--format=format:" ++ COMMIT_MARKER,
        },
        .stdout_limit = std.Io.Limit.limited(4 * 1024 * 1024),
        .stderr_limit = std.Io.Limit.limited(1024),
    });
    defer gpa.free(log_result.stdout);
    defer gpa.free(log_result.stderr);

    // git unavailable or not a repo
    const log_ok = switch (log_result.term) {
        .exited => |c| c == 0,
        else => false,
    };
    if (!log_ok) return error.GitFailed;

    // Intermediate tables
    var file_to_idx: std.StringHashMapUnmanaged(u32) = .empty;
    defer file_to_idx.deinit(gpa);

    var file_paths: std.ArrayList([]u8) = .empty;
    defer {
        for (file_paths.items) |p| gpa.free(p);
        file_paths.deinit(gpa);
    }
    var file_counts: std.ArrayList(u64) = .empty;
    defer file_counts.deinit(gpa);

    var pair_counts: std.AutoHashMapUnmanaged(u64, u64) = .empty;
    defer pair_counts.deinit(gpa);

    var cur_files: std.ArrayList(u32) = .empty;
    defer cur_files.deinit(gpa);

    var commit_count: u64 = 0;

    var iter = std.mem.splitScalar(u8, log_result.stdout, '\n');
    while (iter.next()) |raw| {
        const line = std.mem.trimEnd(u8, raw, "\r");

        if (std.mem.eql(u8, line, COMMIT_MARKER)) {
            try flushCoChange(gpa, cur_files.items, &pair_counts);
            commit_count += 1;
            cur_files.clearRetainingCapacity();
            continue;
        }
        if (line.len == 0) continue;

        // File path — look up or insert
        const idx: u32 = if (file_to_idx.get(line)) |i| i else blk: {
            const new_idx = @as(u32, @intCast(file_paths.items.len));
            const duped = try gpa.dupe(u8, line);
            try file_paths.append(gpa, duped);
            try file_counts.append(gpa, 0);
            try file_to_idx.put(gpa, duped, new_idx);
            break :blk new_idx;
        };
        file_counts.items[idx] += 1;
        try cur_files.append(gpa, idx);
    }
    // Flush the last commit
    try flushCoChange(gpa, cur_files.items, &pair_counts);

    // ── Step 2: build hotspot list ────────────────────────────
    var hotspot_idxs: std.ArrayList(u32) = .empty;
    defer hotspot_idxs.deinit(gpa);
    for (0..file_paths.items.len) |i| {
        try hotspot_idxs.append(gpa, @as(u32, @intCast(i)));
    }
    std.mem.sort(u32, hotspot_idxs.items, file_counts.items, struct {
        fn lt(counts: []const u64, a: u32, b: u32) bool {
            return counts[b] < counts[a];
        }
    }.lt);

    var hotspots: std.ArrayList(HotspotEntry) = .empty;
    errdefer {
        for (hotspots.items) |*h| h.deinit(gpa);
        hotspots.deinit(gpa);
    }
    const hn = @min(TOP_N, hotspot_idxs.items.len);
    for (hotspot_idxs.items[0..hn]) |idx| {
        const cnt = file_counts.items[idx];
        if (cnt == 0) continue;
        try hotspots.append(gpa, .{
            .path = try gpa.dupe(u8, file_paths.items[idx]),
            .commit_count = cnt,
        });
    }

    // ── Step 3: build co-change pair list ────────────────────
    const PairEntry = struct { key: u64, count: u64 };
    var all_pairs: std.ArrayList(PairEntry) = .empty;
    defer all_pairs.deinit(gpa);
    var pair_iter = pair_counts.iterator();
    while (pair_iter.next()) |e| {
        if (e.value_ptr.* < 2) continue;
        try all_pairs.append(gpa, .{ .key = e.key_ptr.*, .count = e.value_ptr.* });
    }
    std.mem.sort(PairEntry, all_pairs.items, {}, struct {
        fn lt(_: void, a: PairEntry, b: PairEntry) bool {
            return b.count < a.count;
        }
    }.lt);

    var cochange_pairs: std.ArrayList(CoChangePair) = .empty;
    errdefer {
        for (cochange_pairs.items) |*p| p.deinit(gpa);
        cochange_pairs.deinit(gpa);
    }
    const pn = @min(TOP_N, all_pairs.items.len);
    for (all_pairs.items[0..pn]) |pe| {
        const a_idx = @as(u32, @intCast(pe.key >> 32));
        const b_idx = @as(u32, @intCast(pe.key & 0xFFFFFFFF));
        try cochange_pairs.append(gpa, .{
            .path_a = try gpa.dupe(u8, file_paths.items[a_idx]),
            .path_b = try gpa.dupe(u8, file_paths.items[b_idx]),
            .count = pe.count,
        });
    }

    // ── Step 4: stale dirs ────────────────────────────────────
    var stale_dirs: std.ArrayList(StaleDir) = .empty;
    errdefer {
        for (stale_dirs.items) |*s| s.deinit(gpa);
        stale_dirs.deinit(gpa);
    }

    const now_ns = std.Io.Timestamp.now(io, .real).nanoseconds;
    const now_secs = @as(i64, @intCast(@divTrunc(now_ns, 1_000_000_000)));
    const threshold_secs = now_secs - @as(i64, WINDOW_DAYS) * 86400;

    // Enumerate top-level directories in the repo
    const repo_dir = std.Io.Dir.openDirAbsolute(io, repo_path, .{ .iterate = true }) catch
        return error.RepoDirUnreadable;
    defer repo_dir.close(io);

    var dir_it = repo_dir.iterate();
    while (try dir_it.next(io)) |entry| {
        if (entry.kind != .directory) continue;
        if (entry.name.len == 0 or entry.name[0] == '.') continue; // skip hidden

        const dir_arg = try std.fmt.allocPrint(gpa, "{s}/", .{entry.name});
        defer gpa.free(dir_arg);

        const dr = std.process.run(gpa, io, .{
            .argv = &[_][]const u8{
                "git", "-C", repo_path, "log", "-1",
                "--format=%ct|%cs", "--", dir_arg,
            },
            .stdout_limit = std.Io.Limit.limited(64),
            .stderr_limit = std.Io.Limit.limited(256),
        }) catch continue;
        defer gpa.free(dr.stdout);
        defer gpa.free(dr.stderr);

        const raw = std.mem.trim(u8, dr.stdout, " \t\r\n");
        if (raw.len == 0) continue;

        const sep = std.mem.indexOfScalar(u8, raw, '|') orelse continue;
        const ts = std.fmt.parseInt(i64, raw[0..sep], 10) catch continue;
        const date_str = raw[sep + 1 ..];

        if (ts >= threshold_secs) continue; // active — not stale

        const days_ago = @as(u64, @intCast(@max(0, @divTrunc(now_secs - ts, 86400))));
        try stale_dirs.append(gpa, .{
            .path = try gpa.dupe(u8, entry.name),
            .last_date = try gpa.dupe(u8, date_str),
            .days_ago = days_ago,
        });
    }

    // Sort stale dirs: most stale first
    std.mem.sort(StaleDir, stale_dirs.items, {}, struct {
        fn lt(_: void, a: StaleDir, b: StaleDir) bool {
            return b.days_ago < a.days_ago;
        }
    }.lt);

    return GitHistoryResult{
        .commit_count = commit_count,
        .window_days = WINDOW_DAYS,
        .hotspots = hotspots,
        .cochange_pairs = cochange_pairs,
        .stale_dirs = stale_dirs,
    };
}

fn flushCoChange(
    gpa: std.mem.Allocator,
    file_idxs: []const u32,
    pair_counts: *std.AutoHashMapUnmanaged(u64, u64),
) !void {
    if (file_idxs.len < 2 or file_idxs.len > MAX_FILES_PER_COMMIT) return;
    for (file_idxs, 0..) |a, i| {
        for (file_idxs[i + 1 ..]) |b| {
            const lo = @min(a, b);
            const hi = @max(a, b);
            const key: u64 = (@as(u64, lo) << 32) | @as(u64, hi);
            const e = try pair_counts.getOrPut(gpa, key);
            if (!e.found_existing) e.value_ptr.* = 0;
            e.value_ptr.* += 1;
        }
    }
}
