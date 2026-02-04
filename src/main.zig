const std = @import("std");
const gatherer = @import("gatherer.zig");
const network = @import("network.zig"); // For enums if needed in main

pub fn panic(msg: []const u8, _: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    _ = msg;
    std.process.exit(1);
}

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    var stdout_buffer: [4096]u8 = undefined;
    var stdout = std.fs.File.stdout().writer(&stdout_buffer);

    // Parse args for config path
    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();
    _ = args.skip(); // Skip program name
    const config_path = args.next() orelse "config.json";

    const config_mod = @import("config.zig");
    var config_parsed = config_mod.loadConfig(allocator, config_path) catch |err| blk: {
        if (err == error.ConfigNotFound) {
            break :blk null;
        }
        std.debug.print("Error loading config: {}\n", .{err});
        return err; // Or exit?
    };
    defer if (config_parsed) |*p| p.deinit();

    const config = if (config_parsed) |p| p.value else config_mod.Config{};

    while (true) {
        // Use an arena allocator for each loop iteration to easily free everything
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit(); // This frees everything allocated in this loop

        const loop_allocator = arena.allocator();

        const statuses = gatherer.gather(loop_allocator, config) catch {
            // std.debug.print("Error gathering status: {}\n", .{err});
            try stdout.interface.writeAll("Error gathering status\n");
            std.Thread.sleep(1 * std.time.ns_per_s);
            continue;
        };

        try std.json.Stringify.value(statuses, .{}, &stdout.interface);
        try stdout.interface.writeAll("\n");
        try stdout.interface.flush();

        std.Thread.sleep(1 * std.time.ns_per_s);
    }
}
