const std = @import("std");

pub fn main() !void {
    var timer = try std.time.Timer.start();
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const map = map: {
        const filename = try parseArgs(allocator);
        defer allocator.free(filename);
        break :map try getMapFromFilename(allocator, filename);
    };
    defer {
        for (map) |m| allocator.free(m);
        allocator.free(map);
    }
    const visited = visited: {
        const visited = try allocator.alloc([]DirectionMask, map.len);
        var i: usize = 0;
        errdefer for (0..i) |n| allocator.free(visited[n]);
        for (map, visited) |m, *v| {
            v.* = try allocator.alloc(DirectionMask, m.len);
            @memset(v.*, .{});
            i += 1;
        }
        break :visited visited;
    };
    defer {
        for (visited) |v| allocator.free(v);
        allocator.free(visited);
    }

    const count = findMaximum(map, visited);

    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();
    try stdout.print("{d}\n", .{count});
    try stdout.print("time: {d}ms\n", .{@divTrunc(timer.read(), std.time.ns_per_ms)});
    try bw.flush();
}

fn getMapFromFilename(allocator: std.mem.Allocator, filename: []const u8) ![]const []const u8 {
    const cwd = std.fs.cwd();
    const file = try cwd.openFile(filename, .{});
    defer file.close();
    const reader = file.reader();
    var lines = std.ArrayList([]const u8).init(allocator);
    errdefer {
        for (lines.items) |i| allocator.free(i);
        lines.deinit();
    }
    var scratch = std.ArrayList(u8).init(allocator);
    defer scratch.deinit();
    var done = false;
    while (!done) {
        reader.streamUntilDelimiter(scratch.writer(), '\n', null) catch |err| {
            if (err == error.EndOfStream) done = true else return err;
        };
        if (scratch.items.len == 0) break;
        try lines.append(try allocator.dupe(u8, scratch.items));
        scratch.clearRetainingCapacity();
    }
    return try lines.toOwnedSlice();
}

fn parseArgs(allocator: std.mem.Allocator) ![]const u8 {
    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();
    _ = args.next();
    const filename = args.next() orelse return error.FilenameNotFound;
    return try allocator.dupe(u8, filename);
}

const Direction = enum { left, right, up, down };

const DirectionMask = packed struct {
    left: bool = false,
    right: bool = false,
    up: bool = false,
    down: bool = false,
    _padding: u4 = 0,
};

fn walk(
    map: []const []const u8,
    paths: []const []DirectionMask,
    start_x: usize,
    start_y: usize,
    direction: Direction,
) void {
    var x: usize = start_x;
    var y: usize = start_y;
    var d = direction;
    var keep_going = (y < map.len) and (x < map[y].len);
    if (keep_going) {
        switch (d) {
            .left => keep_going = !paths[y][x].left,
            .right => keep_going = !paths[y][x].right,
            .up => keep_going = !paths[y][x].up,
            .down => keep_going = !paths[y][x].down,
        }
    }
    while (keep_going) {
        switch (d) {
            .left => {
                paths[y][x].left = true;
                switch (map[y][x]) {
                    '.', '-' => {
                        keep_going = x > 0;
                        if (keep_going) x -= 1;
                    },
                    '/' => {
                        y += 1;
                        d = .down;
                        keep_going = y < map.len;
                    },
                    '\\' => {
                        keep_going = y > 0;
                        d = .up;
                        if (keep_going) y -= 1;
                    },
                    '|' => {
                        walk(map, paths, x, y + 1, .down);
                        keep_going = y > 0;
                        d = .up;
                        if (keep_going) y -= 1;
                    },
                    else => unreachable,
                }
            },
            .right => {
                paths[y][x].right = true;
                switch (map[y][x]) {
                    '.', '-' => {
                        x += 1;
                        keep_going = x < map[y].len;
                    },
                    '/' => {
                        keep_going = y > 0;
                        d = .up;
                        if (keep_going) y -= 1;
                    },
                    '\\' => {
                        y += 1;
                        d = .down;
                        keep_going = y < map.len;
                    },
                    '|' => {
                        walk(map, paths, x, y + 1, .down);
                        keep_going = y > 0;
                        d = .up;
                        if (keep_going) y -= 1;
                    },
                    else => unreachable,
                }
            },
            .up => {
                paths[y][x].up = true;
                switch (map[y][x]) {
                    '.', '|' => {
                        keep_going = y > 0;
                        if (keep_going) y -= 1;
                    },
                    '/' => {
                        x += 1;
                        d = .right;
                        keep_going = x < map[y].len;
                    },
                    '\\' => {
                        keep_going = x > 0;
                        d = .left;
                        if (keep_going) x -= 1;
                    },
                    '-' => {
                        walk(map, paths, x + 1, y, .right);
                        keep_going = x > 0;
                        d = .left;
                        if (keep_going) x -= 1;
                    },
                    else => unreachable,
                }
            },
            .down => {
                paths[y][x].down = true;
                switch (map[y][x]) {
                    '.', '|' => {
                        y += 1;
                        keep_going = y < map.len;
                    },
                    '/' => {
                        keep_going = x > 0;
                        d = .left;
                        if (keep_going) x -= 1;
                    },
                    '\\' => {
                        x += 1;
                        d = .right;
                        keep_going = x < map[y].len;
                    },
                    '-' => {
                        walk(map, paths, x + 1, y, .right);
                        keep_going = x > 0;
                        d = .left;
                        if (keep_going) x -= 1;
                    },
                    else => unreachable,
                }
            },
        }
        if (keep_going) {
            switch (d) {
                .left => keep_going = !paths[y][x].left,
                .right => keep_going = !paths[y][x].right,
                .up => keep_going = !paths[y][x].up,
                .down => keep_going = !paths[y][x].down,
            }
        }
    }
}

test "findMaximum" {
    const input =
        \\.|...\....
        \\|.-.\.....
        \\.....|-...
        \\........|.
        \\..........
        \\.........\
        \\..../.\\..
        \\.-.-/..|..
        \\.|....-|.\
        \\..//.|....
    ;
    const allocator = std.testing.allocator;
    const puzzle = puzzle: {
        var tokenizer = std.mem.tokenizeScalar(u8, input, '\n');
        var list = std.ArrayList([]const u8).init(allocator);
        errdefer list.deinit();
        while (tokenizer.next()) |next| {
            try list.append(next);
        }
        break :puzzle try list.toOwnedSlice();
    };
    defer allocator.free(puzzle);
    const visited = visited: {
        const visited = try allocator.alloc([]DirectionMask, puzzle.len);
        var i: usize = 0;
        errdefer {
            for (0..i) |n| allocator.free(visited[n]);
            allocator.free(visited);
        }
        for (puzzle, visited) |p, *v| {
            v.* = try allocator.alloc(DirectionMask, p.len);
            @memset(v.*, .{});
            i += 1;
        }
        break :visited visited;
    };
    defer {
        for (visited) |v| allocator.free(v);
        allocator.free(visited);
    }
    const count = findMaximum(puzzle, visited);
    try std.testing.expectEqual(@as(usize, 51), count);
}

fn findMaximum(map: []const []const u8, visited: [][]DirectionMask) usize {
    var count: usize = 0;
    for (0..map.len) |i| {
        {
            walk(map, visited, 0, i, .right);
            const next_count = next: {
                var next_count: usize = 0;
                for (visited) |v| {
                    for (v) |b| {
                        if (b.left or b.right or b.up or b.down) next_count += 1;
                    }
                    @memset(v, .{});
                }
                break :next next_count;
            };
            count = @max(count, next_count);
        }
        {
            walk(map, visited, map[0].len - 1, i, .left);
            const next_count = next: {
                var next_count: usize = 0;
                for (visited) |v| {
                    for (v) |b| {
                        if (b.left or b.right or b.up or b.down) next_count += 1;
                    }
                    @memset(v, .{});
                }
                break :next next_count;
            };
            count = @max(count, next_count);
        }
    }
    for (0..map[0].len) |i| {
        {
            walk(map, visited, i, 0, .down);
            const next_count = next: {
                var next_count: usize = 0;
                for (visited) |v| {
                    for (v) |b| {
                        if (b.left or b.right or b.up or b.down) next_count += 1;
                    }
                    @memset(v, .{});
                }
                break :next next_count;
            };
            count = @max(count, next_count);
        }
        {
            walk(map, visited, i, map.len - 1, .up);
            const next_count = next: {
                var next_count: usize = 0;
                for (visited) |v| {
                    for (v) |b| {
                        if (b.left or b.right or b.up or b.down) next_count += 1;
                    }
                    @memset(v, .{});
                }
                break :next next_count;
            };
            count = @max(count, next_count);
        }
    }
    return count;
}
