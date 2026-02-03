const std = @import("std");
const c = @cImport({
    @cInclude("ifaddrs.h");
    @cInclude("net/if.h");
    @cInclude("netinet/in.h");
    @cInclude("arpa/inet.h");
    @cInclude("sys/ioctl.h");
    @cInclude("linux/wireless.h"); // For later, but might be useful here depending on flags
});

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
    type: DeviceType = .unknown, // We might not be able to fully deduce type from ifaddrs easily without checking /sys/class/net
    ssid: ?[]const u8 = null,
    strength: ?u8 = null,
};

pub fn getInterfaces(allocator: std.mem.Allocator) !std.ArrayList(InterfaceInfo) {
    var ifap: ?*c.ifaddrs = null;
    if (c.getifaddrs(&ifap) != 0) {
        return error.GetIfAddrsFailed;
    }
    defer c.freeifaddrs(ifap);

    var list = std.ArrayList(InterfaceInfo).empty;
    errdefer list.deinit(allocator);

    var current: ?*c.ifaddrs = ifap;
    while (current) |ifa| : (current = ifa.ifa_next) {
        if (ifa.ifa_addr == null) continue;
        
        // We only care about AF_INET (IPv4) for now, as per python script requirements mostly
        if (ifa.ifa_addr.*.sa_family == c.AF_INET) {
            const name = std.mem.span(ifa.ifa_name);
            
            // Check if we already have this interface in our list (to update IP)
            // Or usually getifaddrs returns one entry per address.
            // We want to group by interface.
            
            var info: *InterfaceInfo = blk: {
                for (list.items) |*item| {
                    if (std.mem.eql(u8, item.name, name)) {
                        break :blk item;
                    }
                }
                
                // New interface found
                const new_info = InterfaceInfo{
                    .name = try allocator.dupe(u8, name),
                    .state = if ((ifa.ifa_flags & c.IFF_UP) != 0) .activated else .disconnected,
                    // Type deduction is harder here, we might need to check /sys/class/net/{name}/wireless or similar
                    .type = .ethernet, // Default
                };
                
                try list.append(allocator, new_info);
                break :blk &list.items[list.items.len - 1];
            };

            // Get IP address
            var addr_buf: [c.INET_ADDRSTRLEN]u8 = undefined;
            const sockaddr_in: *c.sockaddr_in = @ptrCast(@alignCast(ifa.ifa_addr));
            _ = c.inet_ntop(c.AF_INET, &sockaddr_in.sin_addr, &addr_buf, c.INET_ADDRSTRLEN);
            
            // Calculate CIDR prefix
            // To do this we need netmask
            var cidr: u32 = 0;
            if (ifa.ifa_netmask != null) {
                const mask_in: *c.sockaddr_in = @ptrCast(@alignCast(ifa.ifa_netmask));
                const mask = @as(u32, @bitCast(mask_in.sin_addr.s_addr));
                // mask is in network byte order usually, but let's just count bits
                // Actually s_addr is just u32, let's count set bits.
                
                // However, standard C popcount might not be available or tricky. 
                // Let's do it manually or use @popCount
                cidr = @popCount(mask); 
            }
            
            const ip_str = std.fmt.allocPrint(allocator, "{s}/{d}", .{std.mem.sliceTo(&addr_buf, 0), cidr}) catch "E";
            info.ip4 = ip_str;
        }
    }

    return list;
}
