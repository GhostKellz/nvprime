//! NVPrime CLI
//!
//! Command-line interface for the NVPrime NVIDIA platform.

const std = @import("std");
const nvprime = @import("nvprime");

const Stdout = std.fs.File.Writer;
const Stderr = std.fs.File.Writer;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var stdout_buf: [4096]u8 = undefined;
    var stderr_buf: [4096]u8 = undefined;
    var stdout = std.fs.File.stdout().writer(&stdout_buf);
    var stderr = std.fs.File.stderr().writer(&stderr_buf);

    // Parse command line args
    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    // Skip program name
    _ = args.next();

    const command = args.next() orelse {
        try printUsage(&stdout.interface);
        try stdout.interface.flush();
        return;
    };

    if (std.mem.eql(u8, command, "version") or std.mem.eql(u8, command, "--version") or std.mem.eql(u8, command, "-v")) {
        try printVersion(&stdout.interface);
        try stdout.interface.flush();
        return;
    }

    if (std.mem.eql(u8, command, "help") or std.mem.eql(u8, command, "--help") or std.mem.eql(u8, command, "-h")) {
        try printUsage(&stdout.interface);
        try stdout.interface.flush();
        return;
    }

    if (std.mem.eql(u8, command, "status")) {
        try printStatus(&stdout.interface, &stderr.interface);
        try stdout.interface.flush();
        try stderr.interface.flush();
        return;
    }

    if (std.mem.eql(u8, command, "caps") or std.mem.eql(u8, command, "detect")) {
        try printCapabilities(allocator, &stdout.interface, &stderr.interface);
        try stdout.interface.flush();
        try stderr.interface.flush();
        return;
    }

    if (std.mem.eql(u8, command, "core")) {
        const subcommand = args.next() orelse "status";
        if (std.mem.eql(u8, subcommand, "status")) {
            try printCoreStatus(&stdout.interface, &stderr.interface);
        } else {
            try stderr.interface.print("Unknown core subcommand: {s}\n", .{subcommand});
        }
        try stdout.interface.flush();
        try stderr.interface.flush();
        return;
    }

    if (std.mem.eql(u8, command, "power")) {
        const subcommand = args.next() orelse "status";
        if (std.mem.eql(u8, subcommand, "status")) {
            try printPowerStatus(&stdout.interface, &stderr.interface);
        } else {
            try stderr.interface.print("Unknown power subcommand: {s}\n", .{subcommand});
        }
        try stdout.interface.flush();
        try stderr.interface.flush();
        return;
    }

    if (std.mem.eql(u8, command, "display")) {
        const subcommand = args.next() orelse "status";
        if (std.mem.eql(u8, subcommand, "status")) {
            try printDisplayStatus(&stdout.interface, &stderr.interface);
        } else {
            try stderr.interface.print("Unknown display subcommand: {s}\n", .{subcommand});
        }
        try stdout.interface.flush();
        try stderr.interface.flush();
        return;
    }

    try stderr.interface.print("Unknown command: {s}\n", .{command});
    try stderr.interface.print("Run 'nvprime help' for usage information.\n", .{});
    try stderr.interface.flush();
}

fn printVersion(writer: *std.Io.Writer) !void {
    try writer.print("nvprime {s}\n", .{nvprime.version.string});
    try writer.print("NVPrime - Unified NVIDIA Linux Platform\n", .{});
}

fn printUsage(writer: *std.Io.Writer) !void {
    try writer.print(
        \\NVPrime - Unified NVIDIA Linux Platform
        \\
        \\Usage: nvprime <command> [options]
        \\
        \\Commands:
        \\  status              Show overall system status
        \\  caps, detect        Detect GPUs and show capabilities
        \\  core [subcommand]   GPU clock/pstate/voltage control
        \\  power [subcommand]  Power limit and thermal control
        \\  display [subcommand] Display/VRR/HDR configuration
        \\  runtime [subcommand] Gaming runtime controls
        \\  hud [subcommand]    Overlay and telemetry
        \\  version             Show version information
        \\  help                Show this help message
        \\
        \\Subcommands:
        \\  core status         Show clock and pstate info
        \\  power status        Show power and thermal info
        \\  display status      Show display configuration
        \\
        \\Examples:
        \\  nvprime status
        \\  nvprime caps
        \\  nvprime core status
        \\  nvprime power status
        \\
        \\For more information, visit: https://github.com/ghostkellz/nvprime
        \\
    , .{});
}

fn printStatus(writer: *std.Io.Writer, err_writer: *std.Io.Writer) !void {
    try writer.print("NVPrime {s}\n", .{nvprime.version.string});
    try writer.print("---------------------------------------------------\n", .{});

    // Try to initialize NVML and show GPU info
    nvprime.nvml.init() catch |e| {
        try err_writer.print("Warning: NVML initialization failed: {}\n", .{e});
        try err_writer.print("Make sure NVIDIA drivers are installed.\n", .{});
        return;
    };
    defer nvprime.nvml.shutdown();

    // Show driver version
    if (nvprime.nvml.getDriverVersion()) |version| {
        try writer.print("Driver: {s}\n", .{std.mem.sliceTo(&version, 0)});
    } else |_| {}

    // Show GPU count
    if (nvprime.nvml.getDeviceCount()) |count| {
        try writer.print("GPUs:   {d} detected\n", .{count});

        // Show brief info for each GPU
        for (0..count) |i| {
            if (nvprime.nvml.getDeviceByIndex(@intCast(i))) |device| {
                const name = nvprime.nvml.getDeviceName(device) catch continue;
                const temp = nvprime.nvml.getDeviceTemperature(device, nvprime.nvml.TEMPERATURE_GPU) catch 0;
                const power = nvprime.nvml.getDevicePowerUsage(device) catch 0;
                const util = nvprime.nvml.getDeviceUtilization(device) catch nvprime.nvml.Utilization{ .gpu = 0, .memory = 0 };

                try writer.print("\n[GPU {d}] {s}\n", .{ i, std.mem.sliceTo(&name, 0) });
                try writer.print("        Temp: {d}C | Power: {d:.1}W | GPU: {d}% | MEM: {d}%\n", .{
                    temp,
                    @as(f32, @floatFromInt(power)) / 1000.0,
                    util.gpu,
                    util.memory,
                });
            } else |_| {}
        }
    } else |_| {
        try err_writer.print("Could not detect GPUs.\n", .{});
    }
}

fn printCapabilities(allocator: std.mem.Allocator, writer: *std.Io.Writer, err_writer: *std.Io.Writer) !void {
    nvprime.nvml.init() catch |e| {
        try err_writer.print("NVML initialization failed: {}\n", .{e});
        return;
    };
    defer nvprime.nvml.shutdown();
    try nvprime.nvcaps.init();
    defer nvprime.nvcaps.deinit();

    const gpus = nvprime.nvcaps.detectGpus(allocator) catch |e| {
        try err_writer.print("GPU detection failed: {}\n", .{e});
        return;
    };
    // Note: gpus is owned by nvcaps cache, freed by deinit()

    try writer.print("Detected {d} GPU(s):\n", .{gpus.len});
    try writer.print("---------------------------------------------------\n", .{});

    for (gpus) |gpu| {
        try gpu.print(writer);
    }

    if (gpus.len > 0) {
        const summary = nvprime.nvcaps.getSystemSummary(gpus);
        try writer.print("\nSystem Summary:\n", .{});
        try writer.print("  Total VRAM:      {d} MB\n", .{summary.total_vram_mb});
        try writer.print("  Best Arch:       {s}\n", .{@tagName(summary.best_architecture)});
        try writer.print("  All RTX:         {}\n", .{summary.all_support_rtx});
        try writer.print("  All DLSS:        {}\n", .{summary.all_support_dlss});
        try writer.print("  Primary GPU:     {d}\n", .{summary.primary_gpu_index});
    }
}

fn printCoreStatus(writer: *std.Io.Writer, err_writer: *std.Io.Writer) !void {
    nvprime.nvml.init() catch |e| {
        try err_writer.print("NVML initialization failed: {}\n", .{e});
        return;
    };
    defer nvprime.nvml.shutdown();

    const count = nvprime.nvml.getDeviceCount() catch {
        try err_writer.print("Could not detect GPUs.\n", .{});
        return;
    };

    for (0..count) |i| {
        if (nvprime.nvcore.getState(@intCast(i))) |state| {
            try writer.print("[GPU {d}] ", .{i});
            try state.print(writer);
            try writer.print("\n", .{});
        } else |e| {
            try err_writer.print("[GPU {d}] Error: {}\n", .{ i, e });
        }
    }
}

fn printPowerStatus(writer: *std.Io.Writer, err_writer: *std.Io.Writer) !void {
    nvprime.nvml.init() catch |e| {
        try err_writer.print("NVML initialization failed: {}\n", .{e});
        return;
    };
    defer nvprime.nvml.shutdown();

    const count = nvprime.nvml.getDeviceCount() catch {
        try err_writer.print("Could not detect GPUs.\n", .{});
        return;
    };

    for (0..count) |i| {
        if (nvprime.nvpower.getState(@intCast(i))) |state| {
            try writer.print("[GPU {d}]\n", .{i});
            try state.print(writer);
        } else |e| {
            try err_writer.print("[GPU {d}] Error: {}\n", .{ i, e });
        }
    }
}

fn printDisplayStatus(writer: *std.Io.Writer, _: *std.Io.Writer) !void {
    try writer.print("Display status:\n", .{});
    try writer.print("  Note: Display detection requires X11/Wayland integration.\n", .{});
    try writer.print("  This feature is in development (Phase 4).\n", .{});
}

test "main module compiles" {
    // Basic compilation test
    _ = nvprime;
}
