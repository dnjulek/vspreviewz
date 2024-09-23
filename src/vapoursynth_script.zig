const std = @import("std");

const main = @import("main.zig");
const zgui = main.zgui;
const zgpu = main.zgpu;
const zstbi = main.zstbi;

const vapoursynth = @import("vapoursynth");
const vs = vapoursynth.vapoursynth4;
const vsh = vapoursynth.vshelper;
const vss = vapoursynth.vsscript4;

const c_allocator = std.heap.c_allocator;

pub const VVV = struct {
    vsapi: *const vs.API,
    vssapi: *const vss.API,
    vs_script: *vss.VSScript,

    pub fn init(allocator: std.mem.Allocator) !VVV {
        var args_in = try std.process.argsWithAllocator(allocator);
        defer args_in.deinit();
        _ = args_in.next();
        var vpy_in: ?[]const u8 = null;
        if (args_in.next()) |arg| {
            if (args_in.next() == null) {
                vpy_in = arg;
            } else {
                std.log.err("[vspreviewz] Too many arguments provided.\n", .{});
                std.process.exit(1);
            }
        } else {
            std.log.err("[vspreviewz] No vpy file provided.\n", .{});
            std.process.exit(1);
        }

        const vssapi: *const vss.API = vss.getVSScriptAPI(vss.VSSCRIPT_API_VERSION) orelse {
            std.log.err("[vspreviewz] Failed to initialize VSScript library.\n", .{});
            std.process.exit(1);
        };

        const vsapi: *const vs.API = vssapi.getVSAPI.?(vs.VAPOURSYNTH_API_VERSION) orelse {
            std.log.err("[vspreviewz] Failed to initialize VSAPI.\n", .{});
            std.process.exit(1);
        };

        const vs_script = vssapi.createScript.?(null) orelse {
            std.log.err("[vspreviewz] Script creating error.\n", .{});
            std.process.exit(1);
        };

        if (vssapi.evaluateFile.?(vs_script, vpy_in.?.ptr) != 0) {
            const err = vssapi.getError.?(vs_script).?;
            std.log.err("[vspreviewz] {s}.\n", .{err});
            std.process.exit(1);
        }

        return .{
            .vsapi = vsapi,
            .vssapi = vssapi,
            .vs_script = vs_script,
        };
    }
};

pub fn getNode(v: VVV, nodes_idx: *[]i32, node_select: *u32) !struct { node: ?*vs.Node, n_frames: i32, w: i32, h: i32 } {
    const vsapi = v.vsapi;
    const vssapi = v.vssapi;
    const idx_size = vssapi.getAvailableOutputNodes.?(v.vs_script, 0, null);
    if (idx_size <= 0) {
        std.log.err("[vspreviewz] Script has no outputs set.\n", .{});
        std.process.exit(1);
    }
    nodes_idx.* = try c_allocator.alloc(i32, @intCast(idx_size));
    _ = vssapi.getAvailableOutputNodes.?(v.vs_script, idx_size, nodes_idx.ptr);

    const video_node = vssapi.getOutputNode.?(v.vs_script, nodes_idx.*[node_select.*]);

    const vs_core = vssapi.getCore.?(v.vs_script);
    const vi = vsapi.getVideoInfo.?(video_node);
    const matrix: i32 = if (vi.height > 576) 1 else 6;
    const args = vsapi.createMap.?();
    _ = vsapi.mapConsumeNode.?(args, "clip", video_node, .Replace);
    _ = vsapi.mapSetInt.?(args, "matrix_in", matrix, .Replace);
    _ = vsapi.mapSetInt.?(args, "format", @intFromEnum(vs.PresetVideoFormat.RGB24), .Replace);

    const vsplugin = vsapi.getPluginByID.?(vsh.RESIZE_PLUGIN_ID, vs_core);
    const ret = vsapi.invoke.?(vsplugin, "Bicubic", args);
    const pv_node = vsapi.mapGetNode.?(ret, "clip", 0, null);
    vsapi.freeMap.?(ret);
    vsapi.freeMap.?(args);
    return .{
        .node = pv_node,
        .n_frames = vi.numFrames,
        .w = vi.width,
        .h = vi.height,
    };
}

pub fn getFrame(vsapi: *const vs.API, image: *zstbi.Image, node: ?*vs.Node, frame: *i32) ?*const vs.Frame {
    const video_frame = vsapi.getFrame.?(frame.*, node, null, 0);
    const frame_stride: usize = @intCast(vsapi.getStride.?(video_frame, 0));
    const src_r = vsapi.getReadPtr.?(video_frame, 0);
    const src_g = vsapi.getReadPtr.?(video_frame, 1);
    const src_b = vsapi.getReadPtr.?(video_frame, 2);

    var dst = image.data;
    for (0..image.height) |y| {
        for (0..image.width) |x| {
            const i_frame = y * frame_stride + x;
            const i_img = (y * image.width + x) * 4;
            dst[i_img + 0] = src_r[i_frame];
            dst[i_img + 1] = src_g[i_frame];
            dst[i_img + 2] = src_b[i_frame];
            dst[i_img + 3] = 255;
        }
    }

    return video_frame;
}
