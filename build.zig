const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{
        .default_target = .{
            .cpu_arch = .arm,
            .os_tag = .linux,
            .abi = .musleabi,
        },
    });
    const optimize = b.standardOptimizeOption(.{});

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe_mod.link_libc = false; // We are building for musl, often static?
    // Wait, musl usually requires libc? default is link_libc=true for Zig usually implies dynamic?
    // For musl validation, usually Zig bundles musl. `link_libc = true` is correct if we want Zig's libc (musl).
    // Let's stick to link_libc = true which enables the C ABI/startup.
    exe_mod.link_libc = true;

    // Optimization: Single threaded
    exe_mod.single_threaded = true;

    const exe = b.addExecutable(.{
        .name = "minirouter-status",
        .root_module = exe_mod,
    });

    if (optimize == .ReleaseSmall or optimize == .ReleaseFast) {
        exe.root_module.strip = true;
    }

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const test_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    test_mod.link_libc = true;

    const unit_tests = b.addTest(.{
        .root_module = test_mod,
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}
