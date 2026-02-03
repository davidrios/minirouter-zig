const std = @import("std");

pub fn getWanIp(allocator: std.mem.Allocator) ![]const u8 {
    // Check if DNS is working first? The original script does.
    // We can just try the request.
    
    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    // Use a small buffer for the IP response
    // var buf: [1024]u8 = undefined; // Declared later
    
    const uri = try std.Uri.parse("https://share.us.davidrios.dev/myip");

    var buf: [4096]u8 = undefined;
    var writer = std.io.Writer.fixed(&buf);

    const res = try client.fetch(.{
        .location = .{ .uri = uri },
        .response_writer = &writer,
    });

    if (res.status != .ok) {
        return error.HttpRequestFailed;
    }

    return try allocator.dupe(u8, std.io.Writer.buffered(&writer));
}

pub fn checkDns(allocator: std.mem.Allocator, hostname: []const u8) bool {
    // Simple getaddrinfo check
    const list = std.net.getAddressList(allocator, hostname, 0) catch return false;
    defer list.deinit();
    return list.addrs.len > 0;
}
