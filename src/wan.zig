const std = @import("std");

pub fn getWanIp(allocator: std.mem.Allocator) ![]const u8 {
    const argv = [_][]const u8{ "curl", "-s", "--max-time", "5", "https://share.us.davidrios.dev/myip" };

    var child = std.process.Child.init(&argv, allocator);
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Ignore;

    try child.spawn();

    var buf: [128]u8 = undefined;
    const bytes_read = try child.stdout.?.readAll(&buf);

    _ = try child.wait();

    if (bytes_read == 0) return error.NoOutput;

    // Trim newline
    var ip = buf[0..bytes_read];
    if (ip[ip.len - 1] == '\n') ip = ip[0 .. ip.len - 1];

    return try allocator.dupe(u8, ip);
}

pub fn checkDns(allocator: std.mem.Allocator, hostname: []const u8) bool {
    const argv = [_][]const u8{ "getent", "hosts", hostname };

    var child = std.process.Child.init(&argv, allocator);
    child.stdout_behavior = .Ignore;
    child.stderr_behavior = .Ignore;

    child.spawn() catch return false;

    const term = child.wait() catch return false;

    return switch (term) {
        .Exited => |code| code == 0,
        else => false,
    };
}
