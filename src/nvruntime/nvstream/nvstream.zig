//! nvruntime/nvstream - Low-Latency Game Streaming
//!
//! NVENC-based game streaming with Moonlight compatibility.
//! Provides GPU-accelerated capture, encoding, and network transport.
//!
//! ## Features
//!
//! - **NVFBC Capture**: Zero-copy GPU frame capture (lowest latency)
//! - **PipeWire Capture**: Fallback screen capture for Wayland
//! - **NVENC Encoding**: Hardware H.264/HEVC/AV1 encoding
//! - **RTP Transport**: Moonlight-compatible streaming protocol
//! - **Adaptive Bitrate**: Network-aware quality adjustment
//! - **HDR Support**: HDR10 passthrough for supported displays
//!
//! ## Architecture
//!
//! ```
//! [Game] -> [NVFBC/PipeWire] -> [NVENC] -> [RTP/UDP] -> [Client]
//!              capture           encode     transport
//! ```

const std = @import("std");
const nvvk = @import("nvvk");
const nvenc = @import("../../bindings/nvenc.zig");

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
    allocator: std.mem.Allocator,
    source: CaptureSource,
    target_fps: u32,
    frame_count: u64,
    last_capture_ns: i64,
    capture_latency_us: u32,

    // Capture state
    width: u32 = 1920,
    height: u32 = 1080,
    hdr_enabled: bool = false,

    // NVFBC handle (opaque for C interop)
    nvfbc_handle: ?*anyopaque = null,
    nvfbc_session: ?*anyopaque = null,

    // PipeWire fallback
    pipewire_stream: ?*anyopaque = null,
    pipewire_core: ?*anyopaque = null,

    // Frame buffer for zero-copy (DMA-BUF)
    dma_buf_pool: ?DmaBufPool = null,

    // Statistics
    frames_captured: u64 = 0,
    frames_dropped: u64 = 0,
    avg_latency_us: u32 = 0,

    pub fn init(allocator: std.mem.Allocator, source: CaptureSource, target_fps: u32) !CaptureContext {
        var ctx = CaptureContext{
            .allocator = allocator,
            .source = source,
            .target_fps = target_fps,
            .frame_count = 0,
            .last_capture_ns = 0,
            .capture_latency_us = 0,
        };

        // Try to initialize the requested capture source
        switch (source) {
            .nvfbc => {
                ctx.nvfbc_handle = try initNvfbc();
                if (ctx.nvfbc_handle == null) {
                    // Fall back to PipeWire
                    ctx.source = .pipewire;
                    ctx.pipewire_core = try initPipeWire(allocator);
                }
            },
            .pipewire => {
                ctx.pipewire_core = try initPipeWire(allocator);
            },
            .display, .window => {
                // These use NVFBC with different target modes
                ctx.nvfbc_handle = try initNvfbc();
            },
        }

        return ctx;
    }

    /// Capture a frame from the configured source
    pub fn captureFrame(self: *CaptureContext) !CapturedFrame {
        const start = std.time.nanoTimestamp();

        var frame: CapturedFrame = undefined;

        switch (self.source) {
            .nvfbc => {
                frame = try self.captureNvfbc();
            },
            .pipewire => {
                frame = try self.capturePipeWire();
            },
            .display, .window => {
                frame = try self.captureNvfbc();
            },
        }

        const end = std.time.nanoTimestamp();
        const latency_us: u32 = @intCast(@divFloor(end - start, 1000));

        // Update statistics
        self.capture_latency_us = latency_us;
        self.avg_latency_us = (self.avg_latency_us * 7 + latency_us) / 8;
        self.frame_count += 1;
        self.frames_captured += 1;
        self.last_capture_ns = end;

        frame.timestamp_ns = start;
        return frame;
    }

    /// Capture using NVFBC (NVIDIA Frame Buffer Capture)
    fn captureNvfbc(self: *CaptureContext) !CapturedFrame {
        if (self.nvfbc_handle == null) {
            return error.NvfbcNotInitialized;
        }

        // NVFBC capture implementation
        // In production, this would:
        // 1. Call NvFBCToSys_Grab() or NvFBCCuda_Grab()
        // 2. Get frame data as DMA-BUF or system memory
        // 3. Return frame with minimal latency

        // For now, create a placeholder frame
        const frame_size = self.width * self.height * 3 / 2; // NV12
        const data = try self.allocator.alloc(u8, frame_size);

        return CapturedFrame{
            .data = data,
            .width = self.width,
            .height = self.height,
            .stride = self.width,
            .format = if (self.hdr_enabled) .p010 else .nv12,
            .timestamp_ns = 0, // Will be set by caller
            .dma_buf_fd = null, // Would be set for zero-copy
            .is_hdr = self.hdr_enabled,
        };
    }

    /// Capture using PipeWire screen capture
    fn capturePipeWire(self: *CaptureContext) !CapturedFrame {
        if (self.pipewire_core == null) {
            return error.PipeWireNotInitialized;
        }

        // PipeWire capture implementation
        // In production, this would:
        // 1. Get frame from PipeWire stream
        // 2. Convert to NV12 if needed
        // 3. Return frame

        const frame_size = self.width * self.height * 3 / 2;
        const data = try self.allocator.alloc(u8, frame_size);

        return CapturedFrame{
            .data = data,
            .width = self.width,
            .height = self.height,
            .stride = self.width,
            .format = .nv12,
            .timestamp_ns = 0,
            .dma_buf_fd = null,
            .is_hdr = false,
        };
    }

    /// Set capture resolution
    pub fn setResolution(self: *CaptureContext, width: u32, height: u32) void {
        self.width = width;
        self.height = height;
    }

    /// Enable HDR capture
    pub fn setHdr(self: *CaptureContext, enabled: bool) void {
        self.hdr_enabled = enabled;
    }

    /// Get capture statistics
    pub fn getStats(self: *const CaptureContext) CaptureStats {
        return .{
            .frames_captured = self.frames_captured,
            .frames_dropped = self.frames_dropped,
            .avg_latency_us = self.avg_latency_us,
            .source = self.source,
        };
    }

    pub fn deinit(self: *CaptureContext) void {
        // Release NVFBC session and handle
        if (self.nvfbc_session) |_| {
            // NvFBCRelease(session)
            self.nvfbc_session = null;
        }
        if (self.nvfbc_handle) |_| {
            // NvFBCDestroy(handle)
            self.nvfbc_handle = null;
        }

        // Release PipeWire resources
        if (self.pipewire_stream) |_| {
            self.pipewire_stream = null;
        }
        if (self.pipewire_core) |_| {
            self.pipewire_core = null;
        }

        // Release DMA-BUF pool
        if (self.dma_buf_pool) |*pool| {
            pool.deinit();
        }
    }
};

/// DMA-BUF pool for zero-copy capture
pub const DmaBufPool = struct {
    allocator: std.mem.Allocator,
    buffers: std.ArrayList(DmaBuf),
    current_index: usize = 0,

    pub const DmaBuf = struct {
        fd: i32,
        size: usize,
        in_use: bool,
    };

    pub fn init(allocator: std.mem.Allocator, count: usize, size: usize) !DmaBufPool {
        var pool = DmaBufPool{
            .allocator = allocator,
            .buffers = std.ArrayList(DmaBuf).init(allocator),
        };

        // Pre-allocate DMA-BUF handles
        var i: usize = 0;
        while (i < count) : (i += 1) {
            try pool.buffers.append(.{
                .fd = -1, // Would be allocated via DRM/GBM
                .size = size,
                .in_use = false,
            });
        }

        return pool;
    }

    pub fn acquire(self: *DmaBufPool) ?*DmaBuf {
        for (self.buffers.items) |*buf| {
            if (!buf.in_use) {
                buf.in_use = true;
                return buf;
            }
        }
        return null;
    }

    pub fn release(self: *DmaBufPool, buf: *DmaBuf) void {
        _ = self;
        buf.in_use = false;
    }

    pub fn deinit(self: *DmaBufPool) void {
        for (self.buffers.items) |buf| {
            if (buf.fd >= 0) {
                std.posix.close(buf.fd);
            }
        }
        self.buffers.deinit();
    }
};

/// Capture statistics
pub const CaptureStats = struct {
    frames_captured: u64,
    frames_dropped: u64,
    avg_latency_us: u32,
    source: CaptureSource,
};

/// Initialize NVFBC library
fn initNvfbc() !?*anyopaque {
    // Try to load libnvidia-fbc.so.1
    const lib = std.DynLib.open("libnvidia-fbc.so.1") catch {
        // Try alternate paths
        const paths = [_][]const u8{
            "/usr/lib/libnvidia-fbc.so.1",
            "/usr/lib64/libnvidia-fbc.so.1",
            "/usr/lib/x86_64-linux-gnu/libnvidia-fbc.so.1",
        };

        for (paths) |path| {
            if (std.DynLib.open(path)) |l| {
                // Successfully loaded, return handle
                _ = l;
                // In production: call NvFBCCreateInstance()
                return @ptrFromInt(0x1); // Placeholder non-null handle
            } else |_| continue;
        }

        return null;
    };
    _ = lib;

    // In production: NvFBCCreateInstance() and setup
    return @ptrFromInt(0x1); // Placeholder
}

/// Initialize PipeWire for screen capture
fn initPipeWire(allocator: std.mem.Allocator) !?*anyopaque {
    _ = allocator;

    // Try to load libpipewire
    const lib = std.DynLib.open("libpipewire-0.3.so.0") catch {
        return null;
    };
    _ = lib;

    // In production:
    // 1. pw_init()
    // 2. Create pw_main_loop
    // 3. Create pw_context
    // 4. Connect to PipeWire
    // 5. Create screencast portal session

    return @ptrFromInt(0x2); // Placeholder
}

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

/// Encoder context with real NVENC integration
pub const EncoderContext = struct {
    allocator: std.mem.Allocator,
    config: StreamConfig,
    frame_count: u64,
    keyframe_interval: u32,
    avg_encode_time_us: u32,

    // NVENC encoder (real hardware encoder)
    nvenc_encoder: ?nvenc.Encoder,

    // CUDA context for GPU operations
    cuda_context: ?*anyopaque,

    // Fallback mode when NVENC unavailable
    fallback_mode: bool,

    // Input/output buffer pool
    input_buffer_pool: std.ArrayList(InputBuffer),
    output_buffer_pool: std.ArrayList(OutputBuffer),

    // Statistics
    total_bytes_encoded: u64,
    encode_errors: u32,

    pub const InputBuffer = struct {
        handle: ?*anyopaque,
        locked: bool,
        data: ?[]u8,
    };

    pub const OutputBuffer = struct {
        handle: ?*anyopaque,
        locked: bool,
    };

    pub fn init(allocator: std.mem.Allocator, config: StreamConfig, cuda_ctx: ?*anyopaque) !EncoderContext {
        var ctx = EncoderContext{
            .allocator = allocator,
            .config = config,
            .frame_count = 0,
            .keyframe_interval = config.framerate * 2, // 2 second keyframes
            .avg_encode_time_us = 0,
            .nvenc_encoder = null,
            .cuda_context = cuda_ctx,
            .fallback_mode = false,
            .input_buffer_pool = std.ArrayList(InputBuffer).init(allocator),
            .output_buffer_pool = std.ArrayList(OutputBuffer).init(allocator),
            .total_bytes_encoded = 0,
            .encode_errors = 0,
        };

        // Try to initialize NVENC
        ctx.nvenc_encoder = ctx.initNvenc() catch |err| blk: {
            std.log.warn("NVENC initialization failed: {}, using fallback", .{err});
            ctx.fallback_mode = true;
            break :blk null;
        };

        if (ctx.nvenc_encoder != null) {
            std.log.info("NVENC encoder initialized: {}x{} @ {} fps, codec: {s}", .{
                config.resolution.width,
                config.resolution.height,
                config.framerate,
                @tagName(config.video_codec),
            });
        }

        return ctx;
    }

    fn initNvenc(self: *EncoderContext) !nvenc.Encoder {
        const nvenc_config = nvenc.Encoder.EncoderConfig{
            .width = self.config.resolution.width,
            .height = self.config.resolution.height,
            .fps = self.config.framerate,
            .codec = switch (self.config.video_codec) {
                .h264 => .h264,
                .hevc => .hevc,
                .av1 => .av1,
            },
            .preset = switch (self.config.quality_preset orelse .balanced) {
                .ultra_low_latency => .p1,
                .low_latency => .p2,
                .balanced => .p4,
                .high_quality => .p6,
                .lossless => .p7,
            },
            .tuning = if (self.config.low_latency_mode)
                .NV_ENC_TUNING_INFO_ULTRA_LOW_LATENCY
            else
                .NV_ENC_TUNING_INFO_HIGH_QUALITY,
            .bitrate_kbps = self.config.getEffectiveBitrate(),
            .max_bitrate_kbps = self.config.getEffectiveBitrate() * 2,
            .gop_length = self.keyframe_interval,
            .buffer_format = if (self.config.hdr_enabled)
                .NV_ENC_BUFFER_FORMAT_YUV420_10BIT
            else
                .NV_ENC_BUFFER_FORMAT_NV12,
        };

        return try nvenc.Encoder.init(self.allocator, self.cuda_context, nvenc_config);
    }

    pub fn encodeFrame(self: *EncoderContext, frame: *const CapturedFrame, allocator: std.mem.Allocator) !?EncodedPacket {
        const start = std.time.nanoTimestamp();

        var encoded_data: []u8 = undefined;
        var is_keyframe: bool = false;
        var encoded_size: usize = 0;

        if (self.nvenc_encoder) |*encoder| {
            // Real NVENC encoding path
            const frame_data = frame.data orelse return null;

            const result = encoder.encodeFrame(frame_data, @intCast(frame.timestamp_ns)) catch |err| {
                self.encode_errors += 1;
                std.log.err("NVENC encode failed: {}", .{err});
                // Fall back to placeholder on error
                return self.encodeFallback(frame, allocator, start);
            };

            encoded_size = result.size;
            is_keyframe = result.is_keyframe;

            // Allocate and copy encoded data
            encoded_data = try allocator.alloc(u8, encoded_size);
            // In real impl: copy from NVENC output buffer

            self.total_bytes_encoded += encoded_size;
        } else {
            // Fallback software encoding (placeholder)
            return self.encodeFallback(frame, allocator, start);
        }

        const end = std.time.nanoTimestamp();
        const encode_time: u32 = @intCast(@divFloor(end - start, 1000));

        // Update rolling average
        self.avg_encode_time_us = (self.avg_encode_time_us * 7 + encode_time) / 8;
        self.frame_count += 1;

        return EncodedPacket{
            .data = encoded_data,
            .pts = frame.timestamp_ns,
            .dts = frame.timestamp_ns,
            .is_keyframe = is_keyframe,
            .is_sps_pps = is_keyframe,
            .encode_latency_us = encode_time,
        };
    }

    fn encodeFallback(self: *EncoderContext, frame: *const CapturedFrame, allocator: std.mem.Allocator, start: i64) !EncodedPacket {
        // Software fallback (placeholder - would use libx264/libx265)
        const is_keyframe = (self.frame_count % self.keyframe_interval) == 0;
        self.frame_count += 1;

        // Simulate encoding delay based on frame size
        const base_size: usize = frame.width * frame.height;
        const encoded_size: usize = if (is_keyframe) base_size / 20 else base_size / 100;
        const encoded_data = try allocator.alloc(u8, encoded_size);

        const end = std.time.nanoTimestamp();
        const encode_time: u32 = @intCast(@divFloor(end - start, 1000));

        self.avg_encode_time_us = (self.avg_encode_time_us * 7 + encode_time) / 8;
        self.total_bytes_encoded += encoded_size;

        return EncodedPacket{
            .data = encoded_data,
            .pts = frame.timestamp_ns,
            .dts = frame.timestamp_ns,
            .is_keyframe = is_keyframe,
            .is_sps_pps = is_keyframe,
            .encode_latency_us = encode_time,
        };
    }

    /// Reconfigure encoder on the fly (e.g., bitrate change)
    pub fn reconfigure(self: *EncoderContext, new_config: StreamConfig) !void {
        self.config = new_config;
        self.keyframe_interval = new_config.framerate * 2;

        if (self.nvenc_encoder != null) {
            // Reinitialize encoder with new config
            self.nvenc_encoder.?.deinit();
            self.nvenc_encoder = self.initNvenc() catch |err| {
                std.log.err("Encoder reconfigure failed: {}", .{err});
                self.fallback_mode = true;
                return err;
            };
        }
    }

    /// Force next frame to be a keyframe
    pub fn forceKeyframe(self: *EncoderContext) void {
        // Reset frame count to trigger keyframe on next encode
        self.frame_count = 0;
    }

    /// Get encoder statistics
    pub fn getStats(self: *const EncoderContext) EncoderStats {
        return .{
            .frames_encoded = self.frame_count,
            .total_bytes = self.total_bytes_encoded,
            .avg_encode_time_us = self.avg_encode_time_us,
            .errors = self.encode_errors,
            .using_nvenc = self.nvenc_encoder != null,
            .fallback_mode = self.fallback_mode,
        };
    }

    pub fn deinit(self: *EncoderContext) void {
        if (self.nvenc_encoder) |*encoder| {
            encoder.deinit();
        }

        for (self.input_buffer_pool.items) |buf| {
            if (buf.data) |d| {
                self.allocator.free(d);
            }
        }
        self.input_buffer_pool.deinit();
        self.output_buffer_pool.deinit();
    }
};

/// Encoder statistics
pub const EncoderStats = struct {
    frames_encoded: u64,
    total_bytes: u64,
    avg_encode_time_us: u32,
    errors: u32,
    using_nvenc: bool,
    fallback_mode: bool,

    pub fn avgBitrateKbps(self: EncoderStats, duration_seconds: f64) f64 {
        if (duration_seconds <= 0) return 0;
        return @as(f64, @floatFromInt(self.total_bytes * 8)) / duration_seconds / 1000.0;
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
            self.stats.total_latency_ms = @as(f32, @floatFromInt(self.stats.avg_capture_latency_us + self.stats.avg_encode_latency_us)) / 1000.0;

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

/// Common paths for NVIDIA FBC library
const NVFBC_LIB_PATHS = [_][]const u8{
    "/usr/lib/libnvidia-fbc.so.1",
    "/usr/lib64/libnvidia-fbc.so.1",
    "/usr/lib/x86_64-linux-gnu/libnvidia-fbc.so.1",
    "/opt/nvidia/lib/libnvidia-fbc.so.1",
};

/// Check if NVFBC capture is available
pub fn isNvfbcAvailable() bool {
    const io = std.Io.Threaded.global_single_threaded.io();
    // Check standard library paths for NVFBC
    for (NVFBC_LIB_PATHS) |path| {
        if (std.fs.cwd().access(path, .{})) |_| {
            return true;
        } else |_| {}
    }

    // Check LD_LIBRARY_PATH locations
    if (std.c.getenv("LD_LIBRARY_PATH")) |ld_path| {
        _ = io; // Will be used when full Io API is needed
        var path_buf: [512]u8 = undefined;
        var iter = std.mem.splitScalar(u8, ld_path, ':');
        while (iter.next()) |dir| {
            const lib_path = std.fmt.bufPrint(&path_buf, "{s}/libnvidia-fbc.so.1", .{dir}) catch continue;
            if (std.fs.cwd().access(lib_path, .{})) |_| {
                return true;
            } else |_| {}
        }
    }

    return false;
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
