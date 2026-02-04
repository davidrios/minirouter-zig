const std = @import("std");

pub const Config = struct {
    interfaces: ?[][]const u8 = null,

    // Helper to check if an interface is allowed
    pub fn isInterfaceAllowed(self: Config, name: []const u8) bool {
        const allowed_list = self.interfaces orelse return true; // If null, allow all

        for (allowed_list) |allowed| {
            if (std.mem.eql(u8, allowed, name)) {
                return true;
            }
        }
        return false;
    }
};

// Returns a Parsed(Config) which owns the memory. Caller must call deinit().
pub fn loadConfig(allocator: std.mem.Allocator, path: []const u8) !std.json.Parsed(Config) {
    const file = std.fs.cwd().openFile(path, .{}) catch |err| switch (err) {
        // If file not found, we return a "default" parsed config.
        // But Parsed requires an arena.
        // Easier to just return error and let caller handle "no config" case?
        // Or return a Parsed with null value and empty arena.
        error.FileNotFound => return error.ConfigNotFound,
        else => return err,
    };
    defer file.close();

    const size = (try file.stat()).size;
    const buffer = try allocator.alloc(u8, @intCast(size));
    defer allocator.free(buffer);

    _ = try file.readAll(buffer);

    return std.json.parseFromSlice(Config, allocator, buffer, .{ .allocate = .alloc_always, .ignore_unknown_fields = true });
}
