const std = @import("std");
const posix = std.posix;

pub const DeviceState = enum {
    unknown,
    unmanaged,
    unavailable,
    disconnected,
    prepare,
    config,
    need_auth,
    ip_config,
    ip_check,
    secondaries,
    activated,
    deactivating,
    failed,
};

pub const DeviceType = enum {
    unknown,
    ethernet,
    wifi,
    unused1,
    unused2,
    bt,
    olpc,
    wimax,
    modem,
    infiniband,
    bond,
    vlan,
    adsl,
    bridge,
    generic,
    team,
    tun,
    ip_tunnel,
    macvlan,
    vxlan,
    veth,
};

pub const InterfaceInfo = struct {
    name: []const u8,
    ip4: ?[]const u8 = null,
    state: DeviceState = .unknown,
    type: DeviceType = .unknown,
    ssid: ?[]const u8 = null,
    strength: ?u8 = null,
};

const SIOCGIFADDR = 0x8915;
const SIOCGIFFLAGS = 0x8913;
const IFNAMSIZ = 16;
const IFF_UP = 0x1;
const AF_INET = 2;

const sockaddr = extern struct {
    family: u16,
    data: [14]u8,
};

const ifreq = extern struct {
    ifr_name: [IFNAMSIZ]u8,
    u: extern union {
        addr: sockaddr,
        flags: i16,
        data: [24]u8,
    },
};

pub fn getInterfaces(allocator: std.mem.Allocator) !std.ArrayListUnmanaged(InterfaceInfo) {
    var list = std.ArrayListUnmanaged(InterfaceInfo){};
    errdefer list.deinit(allocator);

    // Iterate /sys/class/net
    var dir = std.fs.openDirAbsolute("/sys/class/net", .{ .iterate = true }) catch return list;
    defer dir.close();

    var it = dir.iterate();

    const sock = posix.socket(posix.AF.INET, posix.SOCK.DGRAM, 0) catch return list;
    defer posix.close(sock);

    while (try it.next()) |entry| {
        const name = entry.name;
        if (name.len >= IFNAMSIZ) continue;

        var info = InterfaceInfo{
            .name = try allocator.dupe(u8, name),
            .type = .ethernet,
            .state = .disconnected,
        };
        errdefer allocator.free(info.name);

        var ifr: ifreq = std.mem.zeroes(ifreq);
        @memcpy(ifr.ifr_name[0..name.len], name);

        // Get Flags
        const rc_flags = std.os.linux.ioctl(sock, SIOCGIFFLAGS, @intFromPtr(&ifr));
        if (rc_flags == 0) {
            if ((ifr.u.flags & IFF_UP) != 0) {
                info.state = .activated;
            }
        }

        // Get IP
        const rc_addr = std.os.linux.ioctl(sock, SIOCGIFADDR, @intFromPtr(&ifr));
        if (rc_addr == 0) {
            if (ifr.u.addr.family == AF_INET) {
                const ip_bytes = ifr.u.addr.data[2..6];
                info.ip4 = try std.fmt.allocPrint(allocator, "{d}.{d}.{d}.{d}", .{ ip_bytes[0], ip_bytes[1], ip_bytes[2], ip_bytes[3] });
            }
        }

        try list.append(allocator, info);
    }

    return list;
}
