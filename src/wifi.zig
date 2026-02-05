const std = @import("std");
const c = @cImport({
    @cInclude("sys/socket.h");
    @cInclude("sys/ioctl.h");
    @cInclude("linux/wireless.h");
    @cInclude("unistd.h");
    @cInclude("string.h");
});

pub fn getSsid(allocator: std.mem.Allocator, interface_name: []const u8) !?[]const u8 {
    // Open a socket to perform ioctl
    const sock = c.socket(c.AF_INET, c.SOCK_DGRAM, 0);
    if (sock < 0) return error.SocketCreateFailed;
    defer _ = c.close(sock);

    var wrq: c.struct_iwreq = std.mem.zeroes(c.struct_iwreq);

    // Copy interface name to ifr_name
    if (interface_name.len >= @sizeOf(@TypeOf(wrq.ifr_ifrn.ifrn_name))) return error.InterfaceNameTooLong;
    @memcpy(wrq.ifr_ifrn.ifrn_name[0..interface_name.len], interface_name);
    wrq.ifr_ifrn.ifrn_name[interface_name.len] = 0;

    // Allocate buffer for SSID
    var ssid_buf: [33]u8 = undefined; // Max SSID len is 32 + null
    @memset(&ssid_buf, 0);

    wrq.u.essid.pointer = &ssid_buf;
    wrq.u.essid.length = ssid_buf.len;
    wrq.u.essid.flags = 0;

    if (c.ioctl(sock, c.SIOCGIWESSID, &wrq) != 0) {
        // Only return error if it's not just "not a wireless interface"
        // But for generic usage, returning null is safer if it fails
        return null;
    }

    if (wrq.u.essid.flags == 0) {
        // SSID hidden or not associated?
        // Sometimes it returns empty string
    }

    // The length returned in wrq.u.essid.length might be useful
    const len = wrq.u.essid.length;
    if (len == 0) return null;

    return try allocator.dupe(u8, ssid_buf[0..len]);
}

pub fn getSignal(interface_name: []const u8) !?u8 {
    const sock = c.socket(c.AF_INET, c.SOCK_DGRAM, 0);
    if (sock < 0) return error.SocketCreateFailed;
    defer _ = c.close(sock);

    var wrq: c.struct_iwreq = std.mem.zeroes(c.struct_iwreq);

    if (interface_name.len >= @sizeOf(@TypeOf(wrq.ifr_ifrn.ifrn_name))) return error.InterfaceNameTooLong;
    @memcpy(wrq.ifr_ifrn.ifrn_name[0..interface_name.len], interface_name);
    wrq.ifr_ifrn.ifrn_name[interface_name.len] = 0;

    // Separate buffer for stats is often used with ioctl, but for SIOCGIWSTATS
    // the iw_statistics struct is usually returned in the pointer provided in u.data?
    // Wait, the standard wireless extension API for stats is:
    // wrq.u.data.pointer = (caddr_t) &stats;
    // wrq.u.data.length = sizeof(stats);
    // wrq.u.data.flags = 1; // Clear updated flag

    var stats: c.struct_iw_statistics = undefined;

    // According to man iw_stats or usage:
    // The statistics are extracted from /proc/net/wireless but technically ioctl SIOCGIWSTATS should work too?
    // Actually SIOCGIWSTATS is deprecated in some modern drivers but simpler than parsing /proc/net/wireless for this environment.
    // Let's try ioctl first. Usage:
    // wrq.u.data.pointer = &stats; ...
    // BUT! struct_iwreq 'u' is a union. 'data' is iw_point.

    wrq.u.data.pointer = &stats;
    wrq.u.data.length = @sizeOf(c.struct_iw_statistics);
    wrq.u.data.flags = 1; // Clear flags

    if (c.ioctl(sock, c.SIOCGIWSTATS, &wrq) != 0) {
        return null; // Failed or not supported
    }

    return stats.qual.level;
}
