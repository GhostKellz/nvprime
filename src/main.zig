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

    if (std.mem.eql(u8, command, "hud")) {
        const subcommand = args.next() orelse "status";
        if (std.mem.eql(u8, subcommand, "status")) {
            try printHudStatus(&stdout.interface, &stderr.interface);
        } else if (std.mem.eql(u8, subcommand, "metrics")) {
            try printHudMetrics(&stdout.interface, &stderr.interface);
        } else {
            try stderr.interface.print("Unknown hud subcommand: {s}\n", .{subcommand});
            try stderr.interface.print("Available: status, metrics\n", .{});
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
        \\  hud status          Show overlay availability and config
        \\  hud metrics         Show live GPU metrics
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

fn printDisplayStatus(writer: *std.Io.Writer, err_writer: *std.Io.Writer) !void {
    try writer.print("Display Status\n", .{});
    try writer.print("---------------------------------------------------\n", .{});

    // Try to get display state via nvsync DRM scanning
    const allocator = std.heap.page_allocator;
    if (nvprime.nvdisplay.getState(allocator)) |state| {
        if (state.display_count == 0) {
            try writer.print("No displays detected via DRM.\n", .{});
            return;
        }

        try writer.print("Displays: {d} connected\n\n", .{state.display_count});

        for (state.displays[0..state.display_count], 0..) |display, i| {
            const is_primary = i == state.primary_display;
            try writer.print("[{d}] {s}{s}\n", .{
                i,
                display.getName(),
                if (is_primary) " (primary)" else "",
            });
            try writer.print("    Resolution: {d}x{d} @ {d}Hz\n", .{
                display.current_width,
                display.current_height,
                display.current_refresh_hz,
            });
            try writer.print("    Connection: {s}\n", .{@tagName(display.connection)});
            try writer.print("    VRR: {s} ({d}-{d}Hz) | G-Sync: {s} | HDR: {s}\n", .{
                if (display.vrr_active) "active" else if (display.supports_vrr) "supported" else "no",
                display.min_vrr_hz,
                display.max_vrr_hz,
                if (display.supports_gsync) "native" else if (display.supports_gsync_compatible) "compatible" else "no",
                if (display.hdr_active) "active" else if (display.supports_hdr) "supported" else "no",
            });
            try writer.print("\n", .{});
        }
    } else |e| {
        try err_writer.print("Display detection error: {}\n", .{e});
        try writer.print("No displays detected. Ensure DRM access is available.\n", .{});
    }
}

fn printHudStatus(writer: *std.Io.Writer, err_writer: *std.Io.Writer) !void {
    try writer.print("NVHUD Overlay Status\n", .{});
    try writer.print("---------------------------------------------------\n", .{});
    try writer.print("Version:    {s}\n", .{nvprime.nvhud.version_string});

    // Check NVIDIA availability
    const nvidia_available = nvprime.nvhud.isOverlayAvailable();
    try writer.print("NVIDIA:     {s}\n", .{if (nvidia_available) "Available" else "Not available"});

    if (!nvidia_available) {
        try err_writer.print("Warning: No NVIDIA GPU detected or NVML unavailable.\n", .{});
        return;
    }

    // Check overlay enabled via environment
    const overlay_enabled = nvprime.nvhud.isOverlayEnabled();
    try writer.print("Enabled:    {s}\n", .{if (overlay_enabled) "Yes (NVHUD=1)" else "No (set NVHUD=1 to enable)"});

    // Get GPU info
    var collector = nvprime.nvhud.Collector.init();
    defer collector.deinit();

    if (collector.isAvailable()) {
        const info = collector.getInfo();
        try writer.print("\nGPU Information:\n", .{});
        try writer.print("  Name:     {s}\n", .{info.getName()});
        try writer.print("  Driver:   {s}\n", .{info.getDriver()});
        try writer.print("  Arch:     {s}\n", .{info.getArchitecture()});
        try writer.print("  VRAM:     {d} MB\n", .{info.vram_total_mb});
    }

    try writer.print("\nEnvironment Variables:\n", .{});
    try writer.print("  NVHUD          - Enable overlay (1/true)\n", .{});
    try writer.print("  NVHUD_POSITION - Overlay position (top-left, top-right, etc.)\n", .{});
    try writer.print("  NVHUD_FPS      - Show FPS counter (0 to disable)\n", .{});
    try writer.print("  NVHUD_CONFIG   - Path to config file\n", .{});
}

fn printHudMetrics(writer: *std.Io.Writer, err_writer: *std.Io.Writer) !void {
    var collector = nvprime.nvhud.Collector.init();
    defer collector.deinit();

    if (!collector.isAvailable()) {
        try err_writer.print("Error: No NVIDIA GPU available.\n", .{});
        return;
    }

    const info = collector.getInfo();
    const metrics = collector.collect();

    try writer.print("GPU Metrics - {s}\n", .{info.getName()});
    try writer.print("---------------------------------------------------\n", .{});

    // Core metrics
    try writer.print("Temperature:  {d}°C\n", .{metrics.temperature});
    try writer.print("GPU Usage:    {d}%\n", .{metrics.gpu_util});
    try writer.print("Memory Usage: {d}%\n", .{metrics.mem_util});
    try writer.print("P-State:      P{d}\n", .{metrics.pstate});

    // Clocks
    try writer.print("\nClocks:\n", .{});
    try writer.print("  GPU:    {d} MHz\n", .{metrics.gpu_clock});
    try writer.print("  Memory: {d} MHz\n", .{metrics.mem_clock});

    // Power
    try writer.print("\nPower:\n", .{});
    try writer.print("  Draw:   {d}W / {d}W ({d:.0}%)\n", .{
        metrics.power_draw,
        metrics.power_limit,
        metrics.powerUsagePercent(),
    });
    try writer.print("  Fan:    {d}%\n", .{metrics.fan_speed});

    // Memory
    try writer.print("\nVRAM:\n", .{});
    try writer.print("  Used:   {d} MB / {d} MB ({d:.0}%)\n", .{
        metrics.vram_used,
        metrics.vram_total,
        metrics.vramUsagePercent(),
    });
    try writer.print("  Free:   {d} MB\n", .{metrics.vramFree()});

    // PCIe
    try writer.print("\nPCIe:\n", .{});
    try writer.print("  Gen:    {d} x{d}\n", .{ metrics.pcie_gen, metrics.pcie_width });

    // Encoder/Decoder
    if (metrics.encoder_util > 0 or metrics.decoder_util > 0) {
        try writer.print("\nVideo:\n", .{});
        try writer.print("  NVENC:  {d}%\n", .{metrics.encoder_util});
        try writer.print("  NVDEC:  {d}%\n", .{metrics.decoder_util});
    }
}

test "main module compiles" {
    // Basic compilation test
    _ = nvprime;
}
