//! nvruntime/nvstream - Low-Latency Game Streaming
//!
//! NVENC-based game streaming with Moonlight compatibility.
//! Provides GPU-accelerated capture, encoding, and network transport.

const std = @import("std");

pub const version = "0.1.0";

// ============================================================================
// Stream State & Configuration
// ============================================================================

/// Stream state machine
pub const StreamState = enum(u8) {
    idle,
    initializing,
    capturing,
    encoding,
    streaming,
    paused,
    stopping,
    error_state,

    pub fn isActive(self: StreamState) bool {
        return switch (self) {
            .capturing, .encoding, .streaming => true,
            else => false,
        };
    }
};

/// Streaming quality preset
pub const QualityPreset = enum(u8) {
    ultra_low_latency, // <5ms encode, lower quality
    low_latency, // <10ms encode, good quality
    balanced, // 15-20ms encode, high quality
    high_quality, // 25-30ms encode, maximum quality
    lossless, // For LAN streaming

    pub fn getTargetBitrate(self: QualityPreset, resolution: Resolution) u32 {
        const base_bitrate: u32 = switch (self) {
            .ultra_low_latency => 10000,
            .low_latency => 20000,
            .balanced => 35000,
            .high_quality => 50000,
            .lossless => 100000,
        };
        // Scale by resolution
        const scale = @as(f32, @floatFromInt(resolution.width * resolution.height)) / (1920.0 * 1080.0);
        return @intFromFloat(@as(f32, @floatFromInt(base_bitrate)) * scale);
    }

    pub fn getPreset(self: QualityPreset) NvencPreset {
        return switch (self) {
            .ultra_low_latency => .p1_fastest,
            .low_latency => .p2_fast,
            .balanced => .p4_medium,
            .high_quality => .p6_slow,
            .lossless => .lossless,
        };
    }
};

/// Video codec for streaming
pub const VideoCodec = enum(u8) {
    h264, // Broadest compatibility
    hevc, // Better compression, HDR support
    av1, // Best compression, newest

    pub fn defaultProfile(self: VideoCodec) []const u8 {
        return switch (self) {
            .h264 => "high",
            .hevc => "main10",
            .av1 => "main",
        };
    }
};

/// Audio codec for streaming
pub const AudioCodec = enum(u8) {
    opus, // Low latency, good quality
    aac, // Broad compatibility
    pcm, // Lossless for LAN
};

/// Stream resolution
pub const Resolution = struct {
    width: u32,
    height: u32,

    pub const r720p = Resolution{ .width = 1280, .height = 720 };
    pub const r1080p = Resolution{ .width = 1920, .height = 1080 };
    pub const r1440p = Resolution{ .width = 2560, .height = 1440 };
    pub const r4k = Resolution{ .width = 3840, .height = 2160 };

    pub fn aspectRatio(self: Resolution) f32 {
        return @as(f32, @floatFromInt(self.width)) / @as(f32, @floatFromInt(self.height));
    }
};

/// Stream configuration
pub const StreamConfig = struct {
    // Video settings
    resolution: Resolution = Resolution.r1080p,
    framerate: u32 = 60,
    video_codec: VideoCodec = .hevc,
    video_bitrate_kbps: u32 = 20000,

    // Audio settings
    audio_codec: AudioCodec = .opus,
    audio_bitrate_kbps: u32 = 256,
    audio_channels: u8 = 2,
    audio_sample_rate: u32 = 48000,

    // Quality preset (overrides bitrate if set)
    quality_preset: ?QualityPreset = .balanced,

    // Latency optimizations
    low_latency_mode: bool = true,
    sliced_encoding: bool = true, // Slice-based encoding for lower latency
    intra_refresh: bool = false, // Periodic intra refresh instead of keyframes

    // Network settings
    max_packet_size: u16 = 1400, // MTU-friendly
    fec_percentage: u8 = 20, // Forward error correction

    // HDR
    hdr_enabled: bool = false,
    hdr_format: HdrFormat = .hdr10,

    pub fn getEffectiveBitrate(self: StreamConfig) u32 {
        if (self.quality_preset) |preset| {
            return preset.getTargetBitrate(self.resolution);
        }
        return self.video_bitrate_kbps;
    }
};

/// HDR format
pub const HdrFormat = enum(u8) {
    sdr,
    hdr10,
    hlg,
    dolby_vision,
};

/// NVENC encoding preset
pub const NvencPreset = enum(u8) {
    p1_fastest,
    p2_fast,
    p3_medium_fast,
    p4_medium,
    p5_medium_slow,
    p6_slow,
    p7_slowest,
    lossless,
};

// ============================================================================
// Capture System
// ============================================================================

/// Capture source type
pub const CaptureSource = enum(u8) {
    display, // Full display capture
    window, // Specific window
    nvfbc, // NVIDIA Frame Buffer Capture (lowest latency)
    pipewire, // PipeWire screen capture
};

/// Captured frame
pub const CapturedFrame = struct {
    data: ?[]u8,
    width: u32,
    height: u32,
    stride: u32,
    format: PixelFormat,
    timestamp_ns: i64,
    dma_buf_fd: ?i32, // For zero-copy
    is_hdr: bool,

    pub fn deinit(self: *CapturedFrame, allocator: std.mem.Allocator) void {
        if (self.data) |d| {
            allocator.free(d);
            self.data = null;
        }
    }
};

/// Pixel format
pub const PixelFormat = enum(u8) {
    nv12,
    p010, // 10-bit for HDR
    rgba,
    bgra,
    argb10,
};

/// Capture context
pub const CaptureContext = struct {
    source: CaptureSource,
    target_fps: u32,
    frame_count: u64,
    last_capture_ns: i64,
    capture_latency_us: u32,

    // NVFBC handle (opaque for C interop)
    nvfbc_handle: ?*anyopaque,

    pub fn init(source: CaptureSource, target_fps: u32) CaptureContext {
        return .{
            .source = source,
            .target_fps = target_fps,
            .frame_count = 0,
            .last_capture_ns = 0,
            .capture_latency_us = 0,
            .nvfbc_handle = null,
        };
    }

    pub fn captureFrame(self: *CaptureContext, allocator: std.mem.Allocator) !CapturedFrame {
        const start = std.time.nanoTimestamp();

        // TODO: Actual NVFBC/PipeWire capture
        // For now, allocate placeholder frame
        const frame_size = 1920 * 1080 * 3 / 2; // NV12
        const data = try allocator.alloc(u8, frame_size);

        const end = std.time.nanoTimestamp();
        self.capture_latency_us = @intCast(@divFloor(end - start, 1000));
        self.frame_count += 1;
        self.last_capture_ns = end;

        return CapturedFrame{
            .data = data,
            .width = 1920,
            .height = 1080,
            .stride = 1920,
            .format = .nv12,
            .timestamp_ns = start,
            .dma_buf_fd = null,
            .is_hdr = false,
        };
    }

    pub fn deinit(self: *CaptureContext) void {
        // TODO: Release NVFBC handle
        _ = self;
    }
};

// ============================================================================
// Encoder System
// ============================================================================

/// Encoded packet
pub const EncodedPacket = struct {
    data: []const u8,
    pts: i64,
    dts: i64,
    is_keyframe: bool,
    is_sps_pps: bool, // Contains codec config
    encode_latency_us: u32,
};

/// Encoder context
pub const EncoderContext = struct {
    config: StreamConfig,
    frame_count: u64,
    keyframe_interval: u32,
    avg_encode_time_us: u32,

    // NVENC handle (opaque)
    nvenc_handle: ?*anyopaque,
    cuda_context: ?*anyopaque,

    pub fn init(config: StreamConfig) !EncoderContext {
        return .{
            .config = config,
            .frame_count = 0,
            .keyframe_interval = config.framerate * 2, // 2 second keyframes
            .avg_encode_time_us = 0,
            .nvenc_handle = null,
            .cuda_context = null,
        };
    }

    pub fn encodeFrame(self: *EncoderContext, frame: *const CapturedFrame, allocator: std.mem.Allocator) !?EncodedPacket {
        const start = std.time.nanoTimestamp();

        // TODO: Actual NVENC encoding
        // 1. Upload frame to GPU (or use DMA-BUF)
        // 2. Submit to NVENC
        // 3. Wait for encoded data

        const is_keyframe = (self.frame_count % self.keyframe_interval) == 0;
        self.frame_count += 1;

        // Placeholder encoded data
        const encoded_size: usize = if (is_keyframe) 50000 else 10000;
        const encoded_data = try allocator.alloc(u8, encoded_size);

        const end = std.time.nanoTimestamp();
        const encode_time: u32 = @intCast(@divFloor(end - start, 1000));

        // Update rolling average
        self.avg_encode_time_us = (self.avg_encode_time_us * 7 + encode_time) / 8;

        return EncodedPacket{
            .data = encoded_data,
            .pts = frame.timestamp_ns,
            .dts = frame.timestamp_ns,
            .is_keyframe = is_keyframe,
            .is_sps_pps = is_keyframe,
            .encode_latency_us = encode_time,
        };
    }

    pub fn deinit(self: *EncoderContext) void {
        // TODO: Release NVENC resources
        _ = self;
    }
};

// ============================================================================
// Network Transport
// ============================================================================

/// Transport protocol
pub const TransportProtocol = enum(u8) {
    rtp_udp, // Standard RTP over UDP (Moonlight)
    rtsp, // RTSP for discovery + RTP for data
    srt, // Secure Reliable Transport
    webrtc, // Browser-compatible
};

/// Network statistics
pub const NetworkStats = struct {
    packets_sent: u64,
    packets_lost: u64,
    bytes_sent: u64,
    rtt_ms: u32,
    jitter_ms: u32,
    bandwidth_kbps: u32,

    pub fn packetLossPercent(self: NetworkStats) f32 {
        if (self.packets_sent == 0) return 0;
        return @as(f32, @floatFromInt(self.packets_lost)) / @as(f32, @floatFromInt(self.packets_sent)) * 100.0;
    }
};

/// Transport context
pub const TransportContext = struct {
    protocol: TransportProtocol,
    host: [256]u8,
    host_len: usize,
    port: u16,
    stats: NetworkStats,
    connected: bool,

    pub fn init(protocol: TransportProtocol, host: []const u8, port: u16) TransportContext {
        var ctx = TransportContext{
            .protocol = protocol,
            .host = undefined,
            .host_len = @min(host.len, 255),
            .port = port,
            .stats = std.mem.zeroes(NetworkStats),
            .connected = false,
        };
        @memcpy(ctx.host[0..ctx.host_len], host[0..ctx.host_len]);
        return ctx;
    }

    pub fn connect(self: *TransportContext) !void {
        // TODO: Establish connection based on protocol
        self.connected = true;
    }

    pub fn sendPacket(self: *TransportContext, data: []const u8) !void {
        if (!self.connected) return error.NotConnected;
        // TODO: Actually send data
        self.stats.packets_sent += 1;
        self.stats.bytes_sent += data.len;
    }

    pub fn disconnect(self: *TransportContext) void {
        self.connected = false;
    }
};

// ============================================================================
// Main Streaming Engine
// ============================================================================

/// Stream statistics
pub const StreamStats = struct {
    state: StreamState,
    frames_captured: u64,
    frames_encoded: u64,
    frames_sent: u64,
    frames_dropped: u64,

    avg_capture_latency_us: u32,
    avg_encode_latency_us: u32,
    avg_network_latency_us: u32,
    total_latency_ms: f32,

    current_bitrate_kbps: u32,
    target_bitrate_kbps: u32,

    network: NetworkStats,

    pub fn getEffectiveFps(self: StreamStats, duration_seconds: f64) f64 {
        return @as(f64, @floatFromInt(self.frames_sent)) / duration_seconds;
    }
};

/// Streaming engine
pub const StreamEngine = struct {
    allocator: std.mem.Allocator,
    config: StreamConfig,
    state: StreamState,

    capture: CaptureContext,
    encoder: EncoderContext,
    transport: TransportContext,

    stats: StreamStats,
    start_time_ns: i64,

    pub fn init(allocator: std.mem.Allocator, config: StreamConfig) !*StreamEngine {
        const engine = try allocator.create(StreamEngine);

        engine.* = StreamEngine{
            .allocator = allocator,
            .config = config,
            .state = .idle,
            .capture = CaptureContext.init(.nvfbc, config.framerate),
            .encoder = try EncoderContext.init(config),
            .transport = TransportContext.init(.rtp_udp, "0.0.0.0", 47998),
            .stats = std.mem.zeroes(StreamStats),
            .start_time_ns = 0,
        };

        return engine;
    }

    pub fn deinit(self: *StreamEngine) void {
        if (self.state.isActive()) {
            self.stop();
        }
        self.capture.deinit();
        self.encoder.deinit();
        self.allocator.destroy(self);
    }

    pub fn start(self: *StreamEngine, host: []const u8, port: u16) !void {
        if (self.state != .idle) return error.InvalidState;

        self.state = .initializing;
        self.transport = TransportContext.init(.rtp_udp, host, port);

        try self.transport.connect();

        self.start_time_ns = std.time.nanoTimestamp();
        self.state = .streaming;
        self.stats.state = .streaming;
    }

    pub fn stop(self: *StreamEngine) void {
        self.state = .stopping;
        self.transport.disconnect();
        self.state = .idle;
        self.stats.state = .idle;
    }

    pub fn processFrame(self: *StreamEngine) !void {
        if (self.state != .streaming) return;

        // Capture
        self.state = .capturing;
        var frame = try self.capture.captureFrame(self.allocator);
        defer frame.deinit(self.allocator);
        self.stats.frames_captured += 1;

        // Encode
        self.state = .encoding;
        if (try self.encoder.encodeFrame(&frame, self.allocator)) |packet| {
            self.stats.frames_encoded += 1;

            // Send
            self.state = .streaming;
            try self.transport.sendPacket(packet.data);
            self.stats.frames_sent += 1;

            // Update latency stats
            self.stats.avg_capture_latency_us = self.capture.capture_latency_us;
            self.stats.avg_encode_latency_us = self.encoder.avg_encode_time_us;
            self.stats.total_latency_ms = @as(f32, @floatFromInt(
                self.stats.avg_capture_latency_us + self.stats.avg_encode_latency_us
            )) / 1000.0;

            self.allocator.free(@constCast(packet.data));
        }
    }

    pub fn getStats(self: *const StreamEngine) StreamStats {
        return self.stats;
    }

    pub fn setQualityPreset(self: *StreamEngine, preset: QualityPreset) void {
        self.config.quality_preset = preset;
        // TODO: Reconfigure encoder on the fly
    }
};

// ============================================================================
// Public API
// ============================================================================

var global_engine: ?*StreamEngine = null;

/// Initialize the streaming engine
pub fn init(allocator: std.mem.Allocator, config: StreamConfig) !void {
    if (global_engine != null) return error.AlreadyInitialized;
    global_engine = try StreamEngine.init(allocator, config);
}

/// Deinitialize the streaming engine
pub fn deinit() void {
    if (global_engine) |engine| {
        engine.deinit();
        global_engine = null;
    }
}

/// Start streaming to a client
pub fn startStream(host: []const u8, port: u16) !void {
    if (global_engine) |engine| {
        try engine.start(host, port);
    } else {
        return error.NotInitialized;
    }
}

/// Stop streaming
pub fn stopStream() void {
    if (global_engine) |engine| {
        engine.stop();
    }
}

/// Get current stream state
pub fn getState() StreamState {
    if (global_engine) |engine| {
        return engine.state;
    }
    return .idle;
}

/// Get stream statistics
pub fn getStats() ?StreamStats {
    if (global_engine) |engine| {
        return engine.getStats();
    }
    return null;
}

/// Check if NVFBC capture is available
pub fn isNvfbcAvailable() bool {
    // TODO: Check for libnvidia-fbc.so
    return true;
}

/// Check if streaming is supported on this system
pub fn isSupported() bool {
    return isNvfbcAvailable();
}

// ============================================================================
// Tests
// ============================================================================

test "quality preset bitrate" {
    const preset = QualityPreset.balanced;
    const bitrate = preset.getTargetBitrate(Resolution.r1080p);
    try std.testing.expect(bitrate > 0);
    try std.testing.expect(bitrate == 35000);
}

test "stream config effective bitrate" {
    const config = StreamConfig{
        .quality_preset = .high_quality,
        .resolution = Resolution.r1440p,
    };
    const bitrate = config.getEffectiveBitrate();
    try std.testing.expect(bitrate > 50000); // Should be scaled up for 1440p
}

test "stream state transitions" {
    try std.testing.expect(StreamState.streaming.isActive());
    try std.testing.expect(!StreamState.idle.isActive());
}

test "capture context init" {
    const ctx = CaptureContext.init(.nvfbc, 60);
    try std.testing.expectEqual(@as(u32, 60), ctx.target_fps);
}

test "network stats packet loss" {
    var stats = NetworkStats{
        .packets_sent = 100,
        .packets_lost = 5,
        .bytes_sent = 1000000,
        .rtt_ms = 10,
        .jitter_ms = 2,
        .bandwidth_kbps = 20000,
    };
    try std.testing.expect(stats.packetLossPercent() == 5.0);
}
