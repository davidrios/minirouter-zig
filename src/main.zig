const std = @import("std");
const gatherer = @import("gatherer.zig");
const network = @import("network.zig"); // For enums if needed in main

pub fn main() !void {
    var raw_allocator = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = raw_allocator.allocator();

    var stdout_buffer: [4096]u8 = undefined;
    var stdout = std.fs.File.stdout().writer(&stdout_buffer);

    while (true) {
        // Use an arena allocator for each loop iteration to easily free everything
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit(); // This frees everything allocated in this loop
        
        const loop_allocator = arena.allocator();

        const statuses = gatherer.gather(loop_allocator) catch |err| {
            std.debug.print("Error gathering status: {}\n", .{err});
            std.Thread.sleep(1 * std.time.ns_per_s);
            continue;
        };

        // Serialize to JSON
        try std.json.Stringify.value(statuses, .{}, &stdout.interface);
        try stdout.interface.writeAll("\n");
        try stdout.interface.flush();

        std.Thread.sleep(1 * std.time.ns_per_s);
    }
}
