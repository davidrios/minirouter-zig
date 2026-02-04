const std = @import("std");
const posix = std.posix;

const SIOCGIWESSID = 0x8B1B;
const IFNAMSIZ = 16;

const iw_point = extern struct {
    pointer: ?*anyopaque,
    length: u16,
    flags: u16,
};

const iwreq = extern struct {
    ifr_name: [IFNAMSIZ]u8,
    u: extern union {
        essid: iw_point,
        data: [24]u8,
    },
};

pub fn getSsid(allocator: std.mem.Allocator, interface_name: []const u8) !?[]const u8 {
    const sock = try posix.socket(posix.AF.INET, posix.SOCK.DGRAM, 0);
    defer posix.close(sock);

    var wrq: iwreq = std.mem.zeroes(iwreq);

    if (interface_name.len >= IFNAMSIZ) return error.InterfaceNameTooLong;
    @memcpy(wrq.ifr_name[0..interface_name.len], interface_name);

    var ssid_buf: [33]u8 = undefined;
    @memset(&ssid_buf, 0);

    wrq.u.essid.pointer = &ssid_buf;
    wrq.u.essid.length = ssid_buf.len;
    wrq.u.essid.flags = 0;

    // ioctl returns raw syscall result (usize)
    const rc = std.os.linux.ioctl(sock, SIOCGIWESSID, @intFromPtr(&wrq));
    if (rc != 0) {
        return null;
    }

    // Check if empty or hidden
    const len = wrq.u.essid.length;
    if (len == 0) return null;

    return try allocator.dupe(u8, ssid_buf[0..len]);
}
