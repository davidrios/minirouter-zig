const std = @import("std");

pub fn getWanIp(allocator: std.mem.Allocator) ![]const u8 {
    // Shell out to wget to avoid linking TLS/HTTP
    const argv = &[_][]const u8{ "wget", "-qO-", "https://share.us.davidrios.dev/myip" };
    // const argv = &[_][]const u8{ "curl", "-s", "https://share.us.davidrios.dev/myip" };

    var child = std.process.Child.init(argv, allocator);
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Ignore; // Ignore stderr

    try child.spawn();

    var buf: [1024]u8 = undefined;
    const bytes_read = try child.stdout.?.readAll(&buf);

    const term = try child.wait();
    if (term != .Exited or term.Exited != 0) {
        return error.WgetFailed;
    }

    if (bytes_read == 0) return error.EmptyResponse;

    // Trim whitespace
    const trimmed = std.mem.trim(u8, buf[0..bytes_read], " \n\r\t");
    return try allocator.dupe(u8, trimmed);
}

pub fn checkDns(allocator: std.mem.Allocator, hostname: []const u8) bool {
    // Standard libc getaddrinfo check is small enough and reliable
    const list = std.net.getAddressList(allocator, hostname, 0) catch return false;
    defer list.deinit();
    return list.addrs.len > 0;
}
