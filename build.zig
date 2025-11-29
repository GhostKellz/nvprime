const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Option to build without NVML (for development/testing)
    const use_nvml = b.option(bool, "nvml", "Link against NVML (requires NVIDIA driver)") orelse true;
    // Option to build with DRM/wlroots for compositor
    const use_drm = b.option(bool, "drm", "Link against libdrm for compositor") orelse false;

    // Fetch external dependencies
    const nvvk_dep = b.dependency("nvvk", .{
        .target = target,
        .optimize = optimize,
    });
    const nvhud_dep = b.dependency("nvhud", .{
        .target = target,
        .optimize = optimize,
    });
    const nvlatency_dep = b.dependency("nvlatency", .{
        .target = target,
        .optimize = optimize,
    });
    const nvsync_dep = b.dependency("nvsync", .{
        .target = target,
        .optimize = optimize,
    });
    const nvshader_dep = b.dependency("nvshader", .{
        .target = target,
        .optimize = optimize,
    });
    const zeus_dep = b.dependency("zeus", .{
        .target = target,
        .optimize = optimize,
    });
    const ghostvk_dep = b.dependency("ghostVK", .{
        .target = target,
        .optimize = optimize,
    });

    // Create the nvprime module
    const mod = b.addModule("nvprime", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "nvvk", .module = nvvk_dep.module("nvvk") },
            .{ .name = "nvhud", .module = nvhud_dep.module("nvhud") },
            .{ .name = "nvlatency", .module = nvlatency_dep.module("nvlatency") },
            .{ .name = "nvsync", .module = nvsync_dep.module("nvsync") },
            .{ .name = "nvshader", .module = nvshader_dep.module("nvshader") },
            .{ .name = "zeus", .module = zeus_dep.module("zeus") },
            .{ .name = "ghostvk", .module = ghostvk_dep.module("ghostVK") },
        },
    });

    // Link NVML to module (libc required for NVML's internal dependencies)
    if (use_nvml) {
        mod.linkSystemLibrary("nvidia-ml", .{});
        mod.linkSystemLibrary("c", .{});
        mod.addIncludePath(.{ .cwd_relative = "/opt/cuda/targets/x86_64-linux/include" });
    }

    // Link DRM for compositor functionality
    if (use_drm) {
        mod.linkSystemLibrary("drm", .{});
        mod.linkSystemLibrary("c", .{});
    }

    // Create the CLI executable
    const exe = b.addExecutable(.{
        .name = "nvprime",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "nvprime", .module = mod },
            },
        }),
    });

    if (use_nvml) {
        exe.linkSystemLibrary("nvidia-ml");
        exe.linkLibC();
        exe.root_module.addIncludePath(.{ .cwd_relative = "/opt/cuda/targets/x86_64-linux/include" });
    }

    // Install the executable
    b.installArtifact(exe);

    // Run step
    const run_step = b.step("run", "Run the nvprime CLI");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // Test step for the module
    const mod_tests = b.addTest(.{
        .root_module = mod,
    });

    if (use_nvml) {
        mod_tests.linkSystemLibrary("nvidia-ml");
        mod_tests.linkLibC();
    }

    const run_mod_tests = b.addRunArtifact(mod_tests);

    // Test step for the executable
    const exe_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "nvprime", .module = mod },
            },
        }),
    });

    if (use_nvml) {
        exe_tests.linkSystemLibrary("nvidia-ml");
        exe_tests.linkLibC();
        exe_tests.root_module.addIncludePath(.{ .cwd_relative = "/opt/cuda/targets/x86_64-linux/include" });
    }

    const run_exe_tests = b.addRunArtifact(exe_tests);

    // Combined test step
    const test_step = b.step("test", "Run all tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_exe_tests.step);

    // Check step (compile without running)
    const check_step = b.step("check", "Check if the code compiles");
    check_step.dependOn(&exe.step);

}
