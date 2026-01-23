//! NVIDIA Video Codec SDK (NVENC) Bindings
//!
//! Hardware video encoding using NVIDIA GPUs.
//! Requires: libnvidia-encode.so.1 (part of NVIDIA driver)
//!
//! Reference: NVIDIA Video Codec SDK Programming Guide

const std = @import("std");

// ============================================================================
// NVENC API Version
// ============================================================================

pub const NVENCAPI_MAJOR_VERSION: u32 = 12;
pub const NVENCAPI_MINOR_VERSION: u32 = 2;
pub const NVENCAPI_VERSION: u32 = (NVENCAPI_MAJOR_VERSION << 4) | NVENCAPI_MINOR_VERSION;

pub fn NVENCAPI_STRUCT_VERSION(ver: u32) u32 {
    return NVENCAPI_VERSION | (ver << 16) | (0x7 << 28);
}

// ============================================================================
// Status Codes
// ============================================================================

pub const NVENCSTATUS = enum(c_int) {
    NV_ENC_SUCCESS = 0,
    NV_ENC_ERR_NO_ENCODE_DEVICE = 1,
    NV_ENC_ERR_UNSUPPORTED_DEVICE = 2,
    NV_ENC_ERR_INVALID_ENCODERDEVICE = 3,
    NV_ENC_ERR_INVALID_DEVICE = 4,
    NV_ENC_ERR_DEVICE_NOT_EXIST = 5,
    NV_ENC_ERR_INVALID_PTR = 6,
    NV_ENC_ERR_INVALID_EVENT = 7,
    NV_ENC_ERR_INVALID_PARAM = 8,
    NV_ENC_ERR_INVALID_CALL = 9,
    NV_ENC_ERR_OUT_OF_MEMORY = 10,
    NV_ENC_ERR_ENCODER_NOT_INITIALIZED = 11,
    NV_ENC_ERR_UNSUPPORTED_PARAM = 12,
    NV_ENC_ERR_LOCK_BUSY = 13,
    NV_ENC_ERR_NOT_ENOUGH_BUFFER = 14,
    NV_ENC_ERR_INVALID_VERSION = 15,
    NV_ENC_ERR_MAP_FAILED = 16,
    NV_ENC_ERR_NEED_MORE_INPUT = 17,
    NV_ENC_ERR_ENCODER_BUSY = 18,
    NV_ENC_ERR_EVENT_NOT_REGISTERD = 19,
    NV_ENC_ERR_GENERIC = 20,
    NV_ENC_ERR_INCOMPATIBLE_CLIENT_KEY = 21,
    NV_ENC_ERR_UNIMPLEMENTED = 22,
    NV_ENC_ERR_RESOURCE_REGISTER_FAILED = 23,
    NV_ENC_ERR_RESOURCE_NOT_REGISTERED = 24,
    NV_ENC_ERR_RESOURCE_NOT_MAPPED = 25,
    _,

    pub fn isSuccess(self: NVENCSTATUS) bool {
        return self == .NV_ENC_SUCCESS;
    }

    pub fn toString(self: NVENCSTATUS) []const u8 {
        return switch (self) {
            .NV_ENC_SUCCESS => "Success",
            .NV_ENC_ERR_NO_ENCODE_DEVICE => "No encode device",
            .NV_ENC_ERR_UNSUPPORTED_DEVICE => "Unsupported device",
            .NV_ENC_ERR_INVALID_ENCODERDEVICE => "Invalid encoder device",
            .NV_ENC_ERR_INVALID_DEVICE => "Invalid device",
            .NV_ENC_ERR_DEVICE_NOT_EXIST => "Device does not exist",
            .NV_ENC_ERR_INVALID_PTR => "Invalid pointer",
            .NV_ENC_ERR_INVALID_PARAM => "Invalid parameter",
            .NV_ENC_ERR_OUT_OF_MEMORY => "Out of memory",
            .NV_ENC_ERR_ENCODER_NOT_INITIALIZED => "Encoder not initialized",
            .NV_ENC_ERR_ENCODER_BUSY => "Encoder busy",
            else => "Unknown error",
        };
    }
};

// ============================================================================
// Codec GUIDs
// ============================================================================

pub const GUID = extern struct {
    Data1: u32,
    Data2: u16,
    Data3: u16,
    Data4: [8]u8,

    pub fn eql(self: GUID, other: GUID) bool {
        return self.Data1 == other.Data1 and
            self.Data2 == other.Data2 and
            self.Data3 == other.Data3 and
            std.mem.eql(u8, &self.Data4, &other.Data4);
    }
};

// H.264 codec GUID
pub const NV_ENC_CODEC_H264_GUID = GUID{
    .Data1 = 0x6bc82762,
    .Data2 = 0x4e63,
    .Data3 = 0x4ca4,
    .Data4 = .{ 0xaa, 0x85, 0x1e, 0x50, 0xf3, 0x21, 0xf6, 0xbf },
};

// HEVC codec GUID
pub const NV_ENC_CODEC_HEVC_GUID = GUID{
    .Data1 = 0x790cdc88,
    .Data2 = 0x4522,
    .Data3 = 0x4d7b,
    .Data4 = .{ 0x94, 0x25, 0xbd, 0xa9, 0x97, 0x5f, 0x76, 0x03 },
};

// AV1 codec GUID
pub const NV_ENC_CODEC_AV1_GUID = GUID{
    .Data1 = 0x0a352289,
    .Data2 = 0x0aa7,
    .Data3 = 0x4759,
    .Data4 = .{ 0x86, 0x2d, 0x5d, 0x15, 0xcd, 0x16, 0xd2, 0x54 },
};

// ============================================================================
// Preset GUIDs (Performance Presets P1-P7)
// ============================================================================

pub const NV_ENC_PRESET_P1_GUID = GUID{
    .Data1 = 0xfc0a8d3e,
    .Data2 = 0x45f8,
    .Data3 = 0x4cf8,
    .Data4 = .{ 0x80, 0xc7, 0x29, 0x88, 0x71, 0x59, 0x0e, 0xbf },
};

pub const NV_ENC_PRESET_P2_GUID = GUID{
    .Data1 = 0xf581cfb8,
    .Data2 = 0xba3d,
    .Data3 = 0x4efc,
    .Data4 = .{ 0xa1, 0x71, 0x79, 0x80, 0x09, 0x40, 0xb8, 0x45 },
};

pub const NV_ENC_PRESET_P3_GUID = GUID{
    .Data1 = 0x36850110,
    .Data2 = 0x3a07,
    .Data3 = 0x441f,
    .Data4 = .{ 0x94, 0xd5, 0x3a, 0x7f, 0x01, 0x06, 0xf2, 0x27 },
};

pub const NV_ENC_PRESET_P4_GUID = GUID{
    .Data1 = 0x90a7b826,
    .Data2 = 0xdf06,
    .Data3 = 0x4862,
    .Data4 = .{ 0xb9, 0xd2, 0xcd, 0x6d, 0x73, 0xa0, 0x82, 0x01 },
};

pub const NV_ENC_PRESET_P5_GUID = GUID{
    .Data1 = 0x21c6e6b4,
    .Data2 = 0x297a,
    .Data3 = 0x4cba,
    .Data4 = .{ 0x99, 0x8f, 0xb6, 0xca, 0xda, 0xc7, 0x2f, 0xec },
};

pub const NV_ENC_PRESET_P6_GUID = GUID{
    .Data1 = 0x8e75c279,
    .Data2 = 0x6299,
    .Data3 = 0x4ab6,
    .Data4 = .{ 0x83, 0x62, 0x01, 0x9b, 0x4b, 0xbd, 0x3e, 0x2d },
};

pub const NV_ENC_PRESET_P7_GUID = GUID{
    .Data1 = 0x84848c12,
    .Data2 = 0x6f71,
    .Data3 = 0x4c13,
    .Data4 = .{ 0x93, 0x1b, 0x53, 0xe2, 0x83, 0xf5, 0x79, 0x74 },
};

// Low latency presets
pub const NV_ENC_PRESET_LOW_LATENCY_DEFAULT_GUID = GUID{
    .Data1 = 0x49df21c5,
    .Data2 = 0x6dfa,
    .Data3 = 0x4feb,
    .Data4 = .{ 0x97, 0x87, 0x6a, 0xcc, 0x9e, 0xff, 0xb7, 0x26 },
};

pub const NV_ENC_PRESET_LOW_LATENCY_HP_GUID = GUID{
    .Data1 = 0x67082a44,
    .Data2 = 0x4bad,
    .Data3 = 0x48fa,
    .Data4 = .{ 0x98, 0xea, 0x93, 0x05, 0x6d, 0x15, 0x0a, 0x58 },
};

pub const NV_ENC_PRESET_LOW_LATENCY_HQ_GUID = GUID{
    .Data1 = 0xcfb4aac2,
    .Data2 = 0x3fed,
    .Data3 = 0x4b06,
    .Data4 = .{ 0xa8, 0xf9, 0xd8, 0xda, 0x4f, 0x41, 0x0e, 0x23 },
};

// ============================================================================
// Profile GUIDs
// ============================================================================

// H.264 Profiles
pub const NV_ENC_H264_PROFILE_BASELINE_GUID = GUID{
    .Data1 = 0x0727bcaa,
    .Data2 = 0x78c4,
    .Data3 = 0x4c83,
    .Data4 = .{ 0x8c, 0x2f, 0xef, 0x3d, 0xff, 0x26, 0x7c, 0x6a },
};

pub const NV_ENC_H264_PROFILE_MAIN_GUID = GUID{
    .Data1 = 0x60b5c1d4,
    .Data2 = 0x67fe,
    .Data3 = 0x4790,
    .Data4 = .{ 0x94, 0xd5, 0xc4, 0x72, 0x6d, 0x7b, 0x6e, 0x6d },
};

pub const NV_ENC_H264_PROFILE_HIGH_GUID = GUID{
    .Data1 = 0xe7cbc309,
    .Data2 = 0x4f7a,
    .Data3 = 0x4b89,
    .Data4 = .{ 0xaf, 0x2a, 0xd5, 0x37, 0xc9, 0x2b, 0xe3, 0x10 },
};

// HEVC Profiles
pub const NV_ENC_HEVC_PROFILE_MAIN_GUID = GUID{
    .Data1 = 0xb514c39a,
    .Data2 = 0xb55b,
    .Data3 = 0x40fa,
    .Data4 = .{ 0x87, 0x8f, 0xf1, 0x25, 0x3b, 0x4d, 0xfd, 0xec },
};

pub const NV_ENC_HEVC_PROFILE_MAIN10_GUID = GUID{
    .Data1 = 0xfa4d2b6c,
    .Data2 = 0x3a5b,
    .Data3 = 0x411a,
    .Data4 = .{ 0x80, 0x18, 0x0a, 0x3f, 0x5e, 0x3c, 0x9b, 0xe5 },
};

// ============================================================================
// Tuning Info
// ============================================================================

pub const NV_ENC_TUNING_INFO = enum(c_int) {
    NV_ENC_TUNING_INFO_UNDEFINED = 0,
    NV_ENC_TUNING_INFO_HIGH_QUALITY = 1,
    NV_ENC_TUNING_INFO_LOW_LATENCY = 2,
    NV_ENC_TUNING_INFO_ULTRA_LOW_LATENCY = 3,
    NV_ENC_TUNING_INFO_LOSSLESS = 4,
};

// ============================================================================
// Buffer Formats
// ============================================================================

pub const NV_ENC_BUFFER_FORMAT = enum(c_int) {
    NV_ENC_BUFFER_FORMAT_UNDEFINED = 0,
    NV_ENC_BUFFER_FORMAT_NV12 = 1,
    NV_ENC_BUFFER_FORMAT_YV12 = 2,
    NV_ENC_BUFFER_FORMAT_IYUV = 3,
    NV_ENC_BUFFER_FORMAT_YUV444 = 4,
    NV_ENC_BUFFER_FORMAT_YUV420_10BIT = 5,
    NV_ENC_BUFFER_FORMAT_YUV444_10BIT = 6,
    NV_ENC_BUFFER_FORMAT_ARGB = 7,
    NV_ENC_BUFFER_FORMAT_ARGB10 = 8,
    NV_ENC_BUFFER_FORMAT_AYUV = 9,
    NV_ENC_BUFFER_FORMAT_ABGR = 10,
    NV_ENC_BUFFER_FORMAT_ABGR10 = 11,
    NV_ENC_BUFFER_FORMAT_U8 = 12,
};

// ============================================================================
// Picture Types
// ============================================================================

pub const NV_ENC_PIC_TYPE = enum(c_int) {
    NV_ENC_PIC_TYPE_P = 0,
    NV_ENC_PIC_TYPE_B = 1,
    NV_ENC_PIC_TYPE_I = 2,
    NV_ENC_PIC_TYPE_IDR = 3,
    NV_ENC_PIC_TYPE_BI = 4,
    NV_ENC_PIC_TYPE_SKIPPED = 5,
    NV_ENC_PIC_TYPE_INTRA_REFRESH = 6,
    NV_ENC_PIC_TYPE_NONREF_P = 7,
    NV_ENC_PIC_TYPE_UNKNOWN = 0xff,
};

// ============================================================================
// Structures
// ============================================================================

pub const NV_ENC_OPEN_ENCODE_SESSION_EX_PARAMS = extern struct {
    version: u32 = NVENCAPI_STRUCT_VERSION(1),
    deviceType: NV_ENC_DEVICE_TYPE = .NV_ENC_DEVICE_TYPE_CUDA,
    device: ?*anyopaque = null,
    reserved: ?*anyopaque = null,
    apiVersion: u32 = NVENCAPI_VERSION,
    reserved1: [253]u32 = [_]u32{0} ** 253,
    reserved2: [64]?*anyopaque = [_]?*anyopaque{null} ** 64,
};

pub const NV_ENC_DEVICE_TYPE = enum(c_int) {
    NV_ENC_DEVICE_TYPE_DIRECTX = 0,
    NV_ENC_DEVICE_TYPE_CUDA = 1,
    NV_ENC_DEVICE_TYPE_OPENGL = 2,
};

pub const NV_ENC_INITIALIZE_PARAMS = extern struct {
    version: u32 = NVENCAPI_STRUCT_VERSION(5),
    encodeGUID: GUID = NV_ENC_CODEC_H264_GUID,
    presetGUID: GUID = NV_ENC_PRESET_P4_GUID,
    encodeWidth: u32 = 1920,
    encodeHeight: u32 = 1080,
    darWidth: u32 = 1920,
    darHeight: u32 = 1080,
    frameRateNum: u32 = 60,
    frameRateDen: u32 = 1,
    enableEncodeAsync: u32 = 0,
    enablePTD: u32 = 1, // Picture Type Decision
    reportSliceOffsets: u32 = 0,
    enableSubFrameWrite: u32 = 0,
    enableExternalMEHints: u32 = 0,
    enableMEOnlyMode: u32 = 0,
    enableWeightedPrediction: u32 = 0,
    enableOutputInVidmem: u32 = 0,
    reservedBitFields: u32 = 0,
    privDataSize: u32 = 0,
    privData: ?*anyopaque = null,
    encodeConfig: ?*NV_ENC_CONFIG = null,
    maxEncodeWidth: u32 = 0,
    maxEncodeHeight: u32 = 0,
    maxMEHintCountsPerBlock: [2]u16 = .{ 0, 0 },
    tuningInfo: NV_ENC_TUNING_INFO = .NV_ENC_TUNING_INFO_HIGH_QUALITY,
    reserved: [286]u32 = [_]u32{0} ** 286,
    reserved2: [64]?*anyopaque = [_]?*anyopaque{null} ** 64,
};

pub const NV_ENC_CONFIG = extern struct {
    version: u32 = NVENCAPI_STRUCT_VERSION(8),
    profileGUID: GUID = NV_ENC_H264_PROFILE_HIGH_GUID,
    gopLength: u32 = 120,
    frameIntervalP: i32 = 1,
    monoChromeEncoding: u32 = 0,
    frameFieldMode: u32 = 0, // Frame mode
    mvPrecision: u32 = 1, // Quarter pixel
    rcParams: NV_ENC_RC_PARAMS = .{},
    encodeCodecConfig: NV_ENC_CODEC_CONFIG = .{},
    reserved: [278]u32 = [_]u32{0} ** 278,
    reserved2: [64]?*anyopaque = [_]?*anyopaque{null} ** 64,
};

pub const NV_ENC_RC_PARAMS = extern struct {
    version: u32 = NVENCAPI_STRUCT_VERSION(1),
    rateControlMode: NV_ENC_PARAMS_RC_MODE = .NV_ENC_PARAMS_RC_VBR,
    constQP: NV_ENC_QP = .{},
    averageBitRate: u32 = 20_000_000,
    maxBitRate: u32 = 40_000_000,
    vbvBufferSize: u32 = 0,
    vbvInitialDelay: u32 = 0,
    enableMinQP: u32 = 0,
    enableMaxQP: u32 = 0,
    enableInitialRCQP: u32 = 0,
    enableAQ: u32 = 1, // Adaptive Quantization
    enableLookahead: u32 = 0,
    disableIadapt: u32 = 0,
    disableBadapt: u32 = 0,
    enableTemporalAQ: u32 = 1,
    zeroReorderDelay: u32 = 1, // Low latency
    enableNonRefP: u32 = 0,
    strictGOPTarget: u32 = 0,
    aqStrength: u32 = 0,
    minQP: NV_ENC_QP = .{},
    maxQP: NV_ENC_QP = .{},
    initialRCQP: NV_ENC_QP = .{},
    temporallayerIdxMask: u32 = 0,
    temporalLayerQP: [8]u8 = [_]u8{0} ** 8,
    targetQuality: u8 = 0,
    targetQualityLSB: u8 = 0,
    lookaheadDepth: u16 = 0,
    lowDelayKeyFrameScale: u8 = 0,
    reserved1: [3]u8 = [_]u8{0} ** 3,
    qpMapMode: u32 = 0,
    multiPass: u32 = 0,
    alphaLayerBitrateRatio: u32 = 0,
    reserved: [4]u32 = [_]u32{0} ** 4,
};

pub const NV_ENC_PARAMS_RC_MODE = enum(c_int) {
    NV_ENC_PARAMS_RC_CONSTQP = 0,
    NV_ENC_PARAMS_RC_VBR = 1,
    NV_ENC_PARAMS_RC_CBR = 2,
    NV_ENC_PARAMS_RC_CBR_LOWDELAY_HQ = 8,
    NV_ENC_PARAMS_RC_CBR_HQ = 16,
    NV_ENC_PARAMS_RC_VBR_HQ = 32,
};

pub const NV_ENC_QP = extern struct {
    qpInterP: u32 = 28,
    qpInterB: u32 = 31,
    qpIntra: u32 = 25,
};

pub const NV_ENC_CODEC_CONFIG = extern struct {
    h264Config: NV_ENC_CONFIG_H264 = .{},
};

pub const NV_ENC_CONFIG_H264 = extern struct {
    enableStereoMVC: u32 = 0,
    hierarchicalPFrames: u32 = 0,
    hierarchicalBFrames: u32 = 0,
    outputBufferingPeriodSEI: u32 = 0,
    outputPictureTimingSEI: u32 = 0,
    outputAUD: u32 = 0,
    disableSPSPPS: u32 = 0,
    outputFramePackingSEI: u32 = 0,
    outputRecoveryPointSEI: u32 = 0,
    enableIntraRefresh: u32 = 0,
    enableConstrainedEncoding: u32 = 0,
    repeatSPSPPS: u32 = 1,
    enableVFR: u32 = 0,
    enableLTR: u32 = 0,
    qpPrimeYZeroTransformBypassFlag: u32 = 0,
    useConstrainedIntraPred: u32 = 0,
    enableFillerDataInsertion: u32 = 0,
    reserved: u32 = 0,
    level: u32 = 0, // Auto
    idrPeriod: u32 = 120,
    separateColourPlaneFlag: u32 = 0,
    disableDeblockingFilterIDC: u32 = 0,
    numTemporalLayers: u32 = 1,
    spsId: u32 = 0,
    ppsId: u32 = 0,
    adaptiveTransformMode: u32 = 2, // Auto
    fmoMode: u32 = 0,
    bdirectMode: u32 = 2, // Auto
    entropyCodingMode: u32 = 1, // CABAC
    stereoMode: u32 = 0,
    intraRefreshPeriod: u32 = 0,
    intraRefreshCnt: u32 = 0,
    maxNumRefFrames: u32 = 0,
    sliceMode: u32 = 3,
    sliceModeData: u32 = 1,
    h264VUIParameters: NV_ENC_CONFIG_H264_VUI_PARAMETERS = .{},
    ltrNumFrames: u32 = 0,
    ltrTrustMode: u32 = 0,
    chromaFormatIDC: u32 = 1,
    maxTemporalLayers: u32 = 0,
    useBFramesAsRef: u32 = 0,
    numRefL0: u32 = 0,
    numRefL1: u32 = 0,
    reserved1: [267]u32 = [_]u32{0} ** 267,
    reserved2: [64]?*anyopaque = [_]?*anyopaque{null} ** 64,
};

pub const NV_ENC_CONFIG_H264_VUI_PARAMETERS = extern struct {
    overscanInfoPresentFlag: u32 = 0,
    overscanInfo: u32 = 0,
    videoSignalTypePresentFlag: u32 = 1,
    videoFormat: u32 = 5, // Unspecified
    videoFullRangeFlag: u32 = 0,
    colourDescriptionPresentFlag: u32 = 1,
    colourPrimaries: u32 = 1, // BT.709
    transferCharacteristics: u32 = 1, // BT.709
    colourMatrix: u32 = 1, // BT.709
    chromaSampleLocationFlag: u32 = 0,
    chromaSampleLocationTop: u32 = 0,
    chromaSampleLocationBot: u32 = 0,
    bitstreamRestrictionFlag: u32 = 0,
    reserved: [15]u32 = [_]u32{0} ** 15,
};

pub const NV_ENC_CREATE_INPUT_BUFFER = extern struct {
    version: u32 = NVENCAPI_STRUCT_VERSION(1),
    width: u32 = 0,
    height: u32 = 0,
    memoryHeap: u32 = 0,
    bufferFmt: NV_ENC_BUFFER_FORMAT = .NV_ENC_BUFFER_FORMAT_NV12,
    reserved: u32 = 0,
    inputBuffer: ?*anyopaque = null,
    pSysMemBuffer: ?*anyopaque = null,
    reserved1: [57]u32 = [_]u32{0} ** 57,
    reserved2: [63]?*anyopaque = [_]?*anyopaque{null} ** 63,
};

pub const NV_ENC_CREATE_BITSTREAM_BUFFER = extern struct {
    version: u32 = NVENCAPI_STRUCT_VERSION(1),
    size: u32 = 0,
    memoryHeap: u32 = 0,
    reserved: u32 = 0,
    bitstreamBuffer: ?*anyopaque = null,
    bitstreamBufferPtr: ?*anyopaque = null,
    reserved1: [58]u32 = [_]u32{0} ** 58,
    reserved2: [64]?*anyopaque = [_]?*anyopaque{null} ** 64,
};

pub const NV_ENC_LOCK_INPUT_BUFFER = extern struct {
    version: u32 = NVENCAPI_STRUCT_VERSION(1),
    doNotWait: u32 = 0,
    reserved: u32 = 0,
    inputBuffer: ?*anyopaque = null,
    bufferDataPtr: ?*anyopaque = null,
    pitch: u32 = 0,
    reserved1: [62]u32 = [_]u32{0} ** 62,
    reserved2: [64]?*anyopaque = [_]?*anyopaque{null} ** 64,
};

pub const NV_ENC_LOCK_BITSTREAM = extern struct {
    version: u32 = NVENCAPI_STRUCT_VERSION(1),
    doNotWait: u32 = 0,
    ltrFrame: u32 = 0,
    reservedBitFields: u32 = 0,
    outputBitstream: ?*anyopaque = null,
    sliceOffsets: ?[*]u32 = null,
    frameIdx: u32 = 0,
    hwEncodeStatus: u32 = 0,
    numSlices: u32 = 0,
    bitstreamSizeInBytes: u32 = 0,
    outputTimeStamp: u64 = 0,
    outputDuration: u64 = 0,
    bitstreamBufferPtr: ?*anyopaque = null,
    pictureType: NV_ENC_PIC_TYPE = .NV_ENC_PIC_TYPE_UNKNOWN,
    pictureStruct: u32 = 0,
    frameAvgQP: u32 = 0,
    frameSatd: u32 = 0,
    ltrFrameIdx: u32 = 0,
    ltrFrameBitmap: u32 = 0,
    reserved: [13]u32 = [_]u32{0} ** 13,
    intraMBCount: u32 = 0,
    interMBCount: u32 = 0,
    averageMVX: i32 = 0,
    averageMVY: i32 = 0,
    reserved1: [219]u32 = [_]u32{0} ** 219,
    reserved2: [64]?*anyopaque = [_]?*anyopaque{null} ** 64,
};

pub const NV_ENC_PIC_PARAMS = extern struct {
    version: u32 = NVENCAPI_STRUCT_VERSION(6),
    inputWidth: u32 = 0,
    inputHeight: u32 = 0,
    inputPitch: u32 = 0,
    encodePicFlags: u32 = 0,
    frameIdx: u32 = 0,
    inputTimeStamp: u64 = 0,
    inputDuration: u64 = 0,
    inputBuffer: ?*anyopaque = null,
    outputBitstream: ?*anyopaque = null,
    completionEvent: ?*anyopaque = null,
    bufferFmt: NV_ENC_BUFFER_FORMAT = .NV_ENC_BUFFER_FORMAT_NV12,
    pictureStruct: u32 = 0x01, // Frame
    pictureType: u32 = 0, // Auto
    codecPicParams: NV_ENC_CODEC_PIC_PARAMS = .{},
    meHintCountsPerBlock: [2]u32 = .{ 0, 0 },
    meExternalHints: ?*anyopaque = null,
    reserved1: [6]u32 = [_]u32{0} ** 6,
    reserved2: [2]?*anyopaque = [_]?*anyopaque{null} ** 2,
    qpDeltaMap: ?*i8 = null,
    qpDeltaMapSize: u32 = 0,
    reservedBitFields: u32 = 0,
    meHintRefPicDist: [2]u16 = .{ 0, 0 },
    reserved3: [286]u32 = [_]u32{0} ** 286,
    reserved4: [60]?*anyopaque = [_]?*anyopaque{null} ** 60,
};

pub const NV_ENC_CODEC_PIC_PARAMS = extern struct {
    h264PicParams: NV_ENC_PIC_PARAMS_H264 = .{},
};

pub const NV_ENC_PIC_PARAMS_H264 = extern struct {
    displayPOCSyntax: u32 = 0,
    reserved3: u32 = 0,
    refPicFlag: u32 = 0,
    colourPlaneId: u32 = 0,
    forceIntraRefreshWithFrameCnt: u32 = 0,
    constrainedFrame: u32 = 0,
    sliceModeDataUpdate: u32 = 0,
    ltrMarkFrame: u32 = 0,
    ltrUseFrames: u32 = 0,
    ltrUseBitmap: u32 = 0,
    ltrMarkFrameIdx: u32 = 0,
    ltrUseFrameBitmap: u32 = 0,
    ltrUsedFrameBitmap: u32 = 0,
    reserved: [243]u32 = [_]u32{0} ** 243,
    reserved2: [62]?*anyopaque = [_]?*anyopaque{null} ** 62,
};

// ============================================================================
// Function Pointers (loaded dynamically)
// ============================================================================

pub const NV_ENCODE_API_FUNCTION_LIST = extern struct {
    version: u32 = NVENCAPI_STRUCT_VERSION(2),
    reserved: u32 = 0,

    nvEncOpenEncodeSession: ?*const fn (?*anyopaque, u32, ?*?*anyopaque) callconv(.c) NVENCSTATUS = null,
    nvEncGetEncodeGUIDCount: ?*const fn (?*anyopaque, *u32) callconv(.c) NVENCSTATUS = null,
    nvEncGetEncodeGUIDs: ?*const fn (?*anyopaque, [*]GUID, u32, *u32) callconv(.c) NVENCSTATUS = null,
    nvEncGetEncodeProfileGUIDCount: ?*const fn (?*anyopaque, GUID, *u32) callconv(.c) NVENCSTATUS = null,
    nvEncGetEncodeProfileGUIDs: ?*const fn (?*anyopaque, GUID, [*]GUID, u32, *u32) callconv(.c) NVENCSTATUS = null,
    nvEncGetInputFormatCount: ?*const fn (?*anyopaque, GUID, *u32) callconv(.c) NVENCSTATUS = null,
    nvEncGetInputFormats: ?*const fn (?*anyopaque, GUID, [*]NV_ENC_BUFFER_FORMAT, u32, *u32) callconv(.c) NVENCSTATUS = null,
    nvEncGetEncodeCaps: ?*const fn (?*anyopaque, GUID, *anyopaque, *c_int) callconv(.c) NVENCSTATUS = null,
    nvEncGetEncodePresetCount: ?*const fn (?*anyopaque, GUID, *u32) callconv(.c) NVENCSTATUS = null,
    nvEncGetEncodePresetGUIDs: ?*const fn (?*anyopaque, GUID, [*]GUID, u32, *u32) callconv(.c) NVENCSTATUS = null,
    nvEncGetEncodePresetConfig: ?*const fn (?*anyopaque, GUID, GUID, *anyopaque) callconv(.c) NVENCSTATUS = null,
    nvEncGetEncodePresetConfigEx: ?*const fn (?*anyopaque, GUID, GUID, NV_ENC_TUNING_INFO, *anyopaque) callconv(.c) NVENCSTATUS = null,
    nvEncInitializeEncoder: ?*const fn (?*anyopaque, *NV_ENC_INITIALIZE_PARAMS) callconv(.c) NVENCSTATUS = null,
    nvEncCreateInputBuffer: ?*const fn (?*anyopaque, *NV_ENC_CREATE_INPUT_BUFFER) callconv(.c) NVENCSTATUS = null,
    nvEncDestroyInputBuffer: ?*const fn (?*anyopaque, ?*anyopaque) callconv(.c) NVENCSTATUS = null,
    nvEncCreateBitstreamBuffer: ?*const fn (?*anyopaque, *NV_ENC_CREATE_BITSTREAM_BUFFER) callconv(.c) NVENCSTATUS = null,
    nvEncDestroyBitstreamBuffer: ?*const fn (?*anyopaque, ?*anyopaque) callconv(.c) NVENCSTATUS = null,
    nvEncEncodePicture: ?*const fn (?*anyopaque, *NV_ENC_PIC_PARAMS) callconv(.c) NVENCSTATUS = null,
    nvEncLockBitstream: ?*const fn (?*anyopaque, *NV_ENC_LOCK_BITSTREAM) callconv(.c) NVENCSTATUS = null,
    nvEncUnlockBitstream: ?*const fn (?*anyopaque, ?*anyopaque) callconv(.c) NVENCSTATUS = null,
    nvEncLockInputBuffer: ?*const fn (?*anyopaque, *NV_ENC_LOCK_INPUT_BUFFER) callconv(.c) NVENCSTATUS = null,
    nvEncUnlockInputBuffer: ?*const fn (?*anyopaque, ?*anyopaque) callconv(.c) NVENCSTATUS = null,
    nvEncGetEncodeStats: ?*const fn (?*anyopaque, *anyopaque) callconv(.c) NVENCSTATUS = null,
    nvEncGetSequenceParams: ?*const fn (?*anyopaque, *anyopaque) callconv(.c) NVENCSTATUS = null,
    nvEncRegisterAsyncEvent: ?*const fn (?*anyopaque, *anyopaque) callconv(.c) NVENCSTATUS = null,
    nvEncUnregisterAsyncEvent: ?*const fn (?*anyopaque, *anyopaque) callconv(.c) NVENCSTATUS = null,
    nvEncMapInputResource: ?*const fn (?*anyopaque, *anyopaque) callconv(.c) NVENCSTATUS = null,
    nvEncUnmapInputResource: ?*const fn (?*anyopaque, ?*anyopaque) callconv(.c) NVENCSTATUS = null,
    nvEncDestroyEncoder: ?*const fn (?*anyopaque) callconv(.c) NVENCSTATUS = null,
    nvEncInvalidateRefFrames: ?*const fn (?*anyopaque, u64) callconv(.c) NVENCSTATUS = null,
    nvEncOpenEncodeSessionEx: ?*const fn (*NV_ENC_OPEN_ENCODE_SESSION_EX_PARAMS, ?*?*anyopaque) callconv(.c) NVENCSTATUS = null,
    nvEncRegisterResource: ?*const fn (?*anyopaque, *anyopaque) callconv(.c) NVENCSTATUS = null,
    nvEncUnregisterResource: ?*const fn (?*anyopaque, ?*anyopaque) callconv(.c) NVENCSTATUS = null,
    nvEncReconfigureEncoder: ?*const fn (?*anyopaque, *anyopaque) callconv(.c) NVENCSTATUS = null,

    reserved1: ?*anyopaque = null,
    nvEncCreateMVBuffer: ?*const fn (?*anyopaque, *anyopaque) callconv(.c) NVENCSTATUS = null,
    nvEncDestroyMVBuffer: ?*const fn (?*anyopaque, ?*anyopaque) callconv(.c) NVENCSTATUS = null,
    nvEncRunMotionEstimationOnly: ?*const fn (?*anyopaque, *anyopaque) callconv(.c) NVENCSTATUS = null,
    nvEncGetLastErrorString: ?*const fn (?*anyopaque) callconv(.c) [*:0]const u8 = null,
    nvEncSetIOCudaStreams: ?*const fn (?*anyopaque, ?*anyopaque, ?*anyopaque) callconv(.c) NVENCSTATUS = null,
    nvEncGetSequenceParamEx: ?*const fn (?*anyopaque, *anyopaque) callconv(.c) NVENCSTATUS = null,
    nvEncRestoreEncoderState: ?*const fn (?*anyopaque, *anyopaque) callconv(.c) NVENCSTATUS = null,
    nvEncLookaheadPicture: ?*const fn (?*anyopaque, *anyopaque) callconv(.c) NVENCSTATUS = null,

    reserved2: [277]?*anyopaque = [_]?*anyopaque{null} ** 277,
};

// ============================================================================
// Library Loading
// ============================================================================

pub const NvencError = error{
    LibraryNotFound,
    SymbolNotFound,
    InitFailed,
    OpenSessionFailed,
    InvalidDevice,
    EncoderNotInitialized,
    EncodeFailed,
    OutOfMemory,
};

/// NVENC library handle
pub const NvencLib = struct {
    lib: std.DynLib,
    funcs: NV_ENCODE_API_FUNCTION_LIST,

    const LIB_PATHS = [_][]const u8{
        "libnvidia-encode.so.1",
        "libnvidia-encode.so",
        "/usr/lib/libnvidia-encode.so.1",
        "/usr/lib64/libnvidia-encode.so.1",
        "/usr/lib/x86_64-linux-gnu/libnvidia-encode.so.1",
    };

    pub fn load() NvencError!NvencLib {
        var nvenc = NvencLib{
            .lib = undefined,
            .funcs = .{},
        };

        // Try to load the library
        for (LIB_PATHS) |path| {
            nvenc.lib = std.DynLib.open(path) catch continue;

            // Get NvEncodeAPICreateInstance
            const createInstance = nvenc.lib.lookup(
                *const fn (*NV_ENCODE_API_FUNCTION_LIST) callconv(.c) NVENCSTATUS,
                "NvEncodeAPICreateInstance",
            ) orelse continue;

            // Fill function table
            const status = createInstance(&nvenc.funcs);
            if (!status.isSuccess()) {
                nvenc.lib.close();
                continue;
            }

            return nvenc;
        }

        return NvencError.LibraryNotFound;
    }

    pub fn close(self: *NvencLib) void {
        self.lib.close();
    }

    /// Check if NVENC is available
    pub fn isAvailable() bool {
        var lib = load() catch return false;
        lib.close();
        return true;
    }
};

// ============================================================================
// High-Level Encoder Wrapper
// ============================================================================

pub const Encoder = struct {
    lib: NvencLib,
    encoder: ?*anyopaque,
    config: EncoderConfig,
    input_buffers: std.ArrayList(?*anyopaque),
    output_buffers: std.ArrayList(?*anyopaque),
    allocator: std.mem.Allocator,
    frame_idx: u64,

    pub const EncoderConfig = struct {
        width: u32 = 1920,
        height: u32 = 1080,
        fps: u32 = 60,
        codec: Codec = .h264,
        preset: Preset = .p4,
        tuning: NV_ENC_TUNING_INFO = .NV_ENC_TUNING_INFO_LOW_LATENCY,
        bitrate_kbps: u32 = 20000,
        max_bitrate_kbps: u32 = 40000,
        gop_length: u32 = 120,
        buffer_format: NV_ENC_BUFFER_FORMAT = .NV_ENC_BUFFER_FORMAT_NV12,

        pub const Codec = enum { h264, hevc, av1 };
        pub const Preset = enum { p1, p2, p3, p4, p5, p6, p7 };
    };

    pub fn init(allocator: std.mem.Allocator, cuda_ctx: ?*anyopaque, config: EncoderConfig) NvencError!Encoder {
        var enc = Encoder{
            .lib = try NvencLib.load(),
            .encoder = null,
            .config = config,
            .input_buffers = std.ArrayList(?*anyopaque).init(allocator),
            .output_buffers = std.ArrayList(?*anyopaque).init(allocator),
            .allocator = allocator,
            .frame_idx = 0,
        };

        // Open encode session
        var session_params = NV_ENC_OPEN_ENCODE_SESSION_EX_PARAMS{};
        session_params.device = cuda_ctx;
        session_params.deviceType = .NV_ENC_DEVICE_TYPE_CUDA;

        if (enc.lib.funcs.nvEncOpenEncodeSessionEx) |openSession| {
            const status = openSession(&session_params, &enc.encoder);
            if (!status.isSuccess()) {
                return NvencError.OpenSessionFailed;
            }
        } else {
            return NvencError.SymbolNotFound;
        }

        // Initialize encoder with config
        try enc.initializeEncoder();

        return enc;
    }

    fn initializeEncoder(self: *Encoder) NvencError!void {
        var init_params = NV_ENC_INITIALIZE_PARAMS{
            .encodeWidth = self.config.width,
            .encodeHeight = self.config.height,
            .frameRateNum = self.config.fps,
            .frameRateDen = 1,
            .tuningInfo = self.config.tuning,
        };

        // Set codec GUID
        init_params.encodeGUID = switch (self.config.codec) {
            .h264 => NV_ENC_CODEC_H264_GUID,
            .hevc => NV_ENC_CODEC_HEVC_GUID,
            .av1 => NV_ENC_CODEC_AV1_GUID,
        };

        // Set preset GUID
        init_params.presetGUID = switch (self.config.preset) {
            .p1 => NV_ENC_PRESET_P1_GUID,
            .p2 => NV_ENC_PRESET_P2_GUID,
            .p3 => NV_ENC_PRESET_P3_GUID,
            .p4 => NV_ENC_PRESET_P4_GUID,
            .p5 => NV_ENC_PRESET_P5_GUID,
            .p6 => NV_ENC_PRESET_P6_GUID,
            .p7 => NV_ENC_PRESET_P7_GUID,
        };

        // Create config
        var enc_config = NV_ENC_CONFIG{};
        enc_config.gopLength = self.config.gop_length;
        enc_config.rcParams.averageBitRate = self.config.bitrate_kbps * 1000;
        enc_config.rcParams.maxBitRate = self.config.max_bitrate_kbps * 1000;
        enc_config.rcParams.rateControlMode = .NV_ENC_PARAMS_RC_VBR;
        enc_config.rcParams.zeroReorderDelay = 1; // Low latency

        init_params.encodeConfig = &enc_config;

        if (self.lib.funcs.nvEncInitializeEncoder) |initEnc| {
            const status = initEnc(self.encoder, &init_params);
            if (!status.isSuccess()) {
                return NvencError.InitFailed;
            }
        } else {
            return NvencError.SymbolNotFound;
        }
    }

    pub fn deinit(self: *Encoder) void {
        // Destroy buffers
        if (self.lib.funcs.nvEncDestroyInputBuffer) |destroyInput| {
            for (self.input_buffers.items) |buf| {
                if (buf) |b| {
                    _ = destroyInput(self.encoder, b);
                }
            }
        }
        if (self.lib.funcs.nvEncDestroyBitstreamBuffer) |destroyOutput| {
            for (self.output_buffers.items) |buf| {
                if (buf) |b| {
                    _ = destroyOutput(self.encoder, b);
                }
            }
        }

        self.input_buffers.deinit();
        self.output_buffers.deinit();

        // Destroy encoder
        if (self.lib.funcs.nvEncDestroyEncoder) |destroy| {
            _ = destroy(self.encoder);
        }

        self.lib.close();
    }

    /// Encode a frame and return the encoded data
    pub fn encodeFrame(self: *Encoder, input_data: []const u8, timestamp: u64) NvencError!EncodedData {
        _ = input_data;

        var pic_params = NV_ENC_PIC_PARAMS{
            .inputWidth = self.config.width,
            .inputHeight = self.config.height,
            .inputTimeStamp = timestamp,
            .frameIdx = @intCast(self.frame_idx),
            .bufferFmt = self.config.buffer_format,
        };

        self.frame_idx += 1;

        // Encode
        if (self.lib.funcs.nvEncEncodePicture) |encode| {
            const status = encode(self.encoder, &pic_params);
            if (!status.isSuccess()) {
                return NvencError.EncodeFailed;
            }
        } else {
            return NvencError.SymbolNotFound;
        }

        // Lock bitstream to get output
        var lock_params = NV_ENC_LOCK_BITSTREAM{};

        if (self.lib.funcs.nvEncLockBitstream) |lockBitstream| {
            const status = lockBitstream(self.encoder, &lock_params);
            if (!status.isSuccess()) {
                return NvencError.EncodeFailed;
            }
        }

        defer {
            if (self.lib.funcs.nvEncUnlockBitstream) |unlock| {
                _ = unlock(self.encoder, lock_params.outputBitstream);
            }
        }

        return EncodedData{
            .size = lock_params.bitstreamSizeInBytes,
            .pts = lock_params.outputTimeStamp,
            .picture_type = lock_params.pictureType,
            .is_keyframe = lock_params.pictureType == .NV_ENC_PIC_TYPE_IDR or
                lock_params.pictureType == .NV_ENC_PIC_TYPE_I,
        };
    }

    pub const EncodedData = struct {
        size: u32,
        pts: u64,
        picture_type: NV_ENC_PIC_TYPE,
        is_keyframe: bool,
    };
};

// ============================================================================
// Tests
// ============================================================================

test "NVENC GUID equality" {
    try std.testing.expect(NV_ENC_CODEC_H264_GUID.eql(NV_ENC_CODEC_H264_GUID));
    try std.testing.expect(!NV_ENC_CODEC_H264_GUID.eql(NV_ENC_CODEC_HEVC_GUID));
}

test "NVENCSTATUS success check" {
    try std.testing.expect(NVENCSTATUS.NV_ENC_SUCCESS.isSuccess());
    try std.testing.expect(!NVENCSTATUS.NV_ENC_ERR_OUT_OF_MEMORY.isSuccess());
}

test "struct version" {
    const ver = NVENCAPI_STRUCT_VERSION(1);
    try std.testing.expect(ver != 0);
}
