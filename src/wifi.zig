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

pub fn getSignalStrength(interface_name: []const u8) !?u8 {
    // Open a socket to perform ioctl
    const sock = c.socket(c.AF_INET, c.SOCK_DGRAM, 0);
    if (sock < 0) return error.SocketCreateFailed;
    defer _ = c.close(sock);

    var stats: c.struct_iw_statistics = std.mem.zeroes(c.struct_iw_statistics);
    var wrq: c.struct_iwreq = std.mem.zeroes(c.struct_iwreq);

    // Copy interface name to ifr_name
    if (interface_name.len >= @sizeOf(@TypeOf(wrq.ifr_ifrn.ifrn_name))) return error.InterfaceNameTooLong;
    @memcpy(wrq.ifr_ifrn.ifrn_name[0..interface_name.len], interface_name);
    wrq.ifr_ifrn.ifrn_name[interface_name.len] = 0;

    wrq.u.data.pointer = &stats;
    wrq.u.data.length = @sizeOf(c.struct_iw_statistics);
    wrq.u.data.flags = 1;

    if (c.ioctl(sock, c.SIOCGIWSTATS, &wrq) != 0) {
        return null;
    }

    var level: i32 = @intCast(stats.qual.level);

    // If the driver doesn't set the IW_QUAL_DBM flag, we use a heuristic:
    // values > 64 are almost certainly dBm (where dBm = value - 256).
    // Some drivers return positive values for quality (0-100).
    const is_dbm = (stats.qual.updated & c.IW_QUAL_DBM) != 0 or level > 64;

    if (is_dbm) {
        if (level > 0) level -= 256;
        // level is now dBm, e.g., -60
        // -100 dBm -> 0%
        // -50 dBm -> 100%
        if (level <= -100) return 0;
        if (level >= -50) return 100;
        return @intCast((level + 100) * 2);
    } else {
        // Otherwise it's a quality value, usually 0-100 or 0-70.
        // We'll assume it's roughly a percentage or at least 0-100.
        if (level < 0) return 0;
        if (level > 100) return 100;
        return @intCast(level);
    }
}
