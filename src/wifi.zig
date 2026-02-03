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
