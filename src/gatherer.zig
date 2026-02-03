const std = @import("std");
const network = @import("network.zig");
const wifi = @import("wifi.zig");
const wan = @import("wan.zig");

pub const Statuses = struct {
    interfaces: ?InterfacesStatus = null,
    dns: ?bool = null,
    wan_ip: ?[]const u8 = null,
};

pub const InterfacesStatus = struct {
    devices: std.StringArrayHashMap(network.InterfaceInfo),
    wifi: ?[]const u8 = null,

    pub fn jsonStringify(self: InterfacesStatus, out: anytype) !void {
        try out.beginObject();
        try out.objectField("devices");
        
        try out.beginObject();
        var it = self.devices.iterator();
        while (it.next()) |entry| {
            try out.objectField(entry.key_ptr.*);
            try out.write(entry.value_ptr.*);
        }
        try out.endObject();

        if (self.wifi) |w| {
            try out.objectField("wifi");
            try out.write(w);
        }
        try out.endObject();
    }
};

pub fn gather(allocator: std.mem.Allocator) !Statuses {
    var statuses = Statuses{};

    // 1. Interfaces
    var interfaces = InterfacesStatus{
        .devices = std.StringArrayHashMap(network.InterfaceInfo).init(allocator),
    };
    
    // errdefer interfaces.devices.deinit(); // Allow partial return? No, let's keep it simple.

    var if_list = try network.getInterfaces(allocator);
    defer {
        for (if_list.items) |item| {
            // We need to be careful not to double free if we move strings to the map
            // For now let's just copy or rely on arena allocator for the whole frame
            _ = item;
        }
        if_list.deinit(allocator);
    }

    for (if_list.items) |*item| {
        // Check for WiFi SSID if it's a wireless interface
        // We can try calling getSsid on everything, or check name conventions (wl*, wlan*)
        if (std.mem.startsWith(u8, item.name, "wl") or std.mem.startsWith(u8, item.name, "wlan")) {
            item.type = .wifi;
            interfaces.wifi = try allocator.dupe(u8, item.name);
            
            // Try to get SSID
            if (wifi.getSsid(allocator, item.name)) |ssid| {
                item.ssid = ssid;
            } else |_| {
                item.ssid = null;
            }
        }
        
        try interfaces.devices.put(item.name, item.*);
    }
    statuses.interfaces = interfaces;

    // 2. DNS
    statuses.dns = wan.checkDns(allocator, "google.com");

    // 3. WAN IP
    if (statuses.dns == true) {
        if (wan.getWanIp(allocator)) |ip| {
            statuses.wan_ip = ip;
        } else |_| {
            statuses.wan_ip = try allocator.dupe(u8, "-error-");
        }
    } else {
        statuses.wan_ip = try allocator.dupe(u8, "offline");
    }

    return statuses;
}
