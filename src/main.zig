const std = @import("std");
const math = std.math;

const zglfw = @import("zglfw");
pub const zgpu = @import("zgpu");
pub const zgui = @import("zgui");
pub const zstbi = @import("zstbi");

const vssc = @import("vapoursynth_script.zig");
const wgpu = zgpu.wgpu;

const window_title = "vspreviewz";

pub fn main() !void {
    try zglfw.init();
    defer zglfw.terminate();

    var gpa_state = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa_state.deinit();
    const gpa = gpa_state.allocator();

    {
        var buffer: [1024]u8 = undefined;
        const path = std.fs.selfExeDirPath(buffer[0..]) catch ".";
        std.posix.chdir(path) catch {};
    }

    zglfw.windowHintTyped(.client_api, .no_api);

    const vmode = try zglfw.Monitor.getVideoMode(zglfw.Monitor.getPrimary().?);
    const window = try zglfw.Window.create(vmode.width, vmode.height, window_title, null);
    defer window.destroy();
    window.setSizeLimits(400, 400, -1, -1);

    const gctx = try zgpu.GraphicsContext.create(
        gpa,
        .{
            .window = window,
            .fn_getTime = @ptrCast(&zglfw.getTime),
            .fn_getFramebufferSize = @ptrCast(&zglfw.Window.getFramebufferSize),
            .fn_getWin32Window = @ptrCast(&zglfw.getWin32Window),
            .fn_getX11Display = @ptrCast(&zglfw.getX11Display),
            .fn_getX11Window = @ptrCast(&zglfw.getX11Window),
            .fn_getWaylandDisplay = @ptrCast(&zglfw.getWaylandDisplay),
            .fn_getWaylandSurface = @ptrCast(&zglfw.getWaylandWindow),
            .fn_getCocoaWindow = @ptrCast(&zglfw.getCocoaWindow),
        },
        .{},
    );
    defer gctx.destroy(gpa);

    zglfw.swapInterval(1);

    zgui.init(gpa);
    defer zgui.deinit();

    const scale_factor = scale_factor: {
        const scale = window.getContentScale();
        break :scale_factor @max(scale[0], scale[1]);
    };

    const font_data = @embedFile("data/Roboto-Medium.ttf");
    _ = zgui.io.addFontFromMemory(font_data, std.math.floor(16.0 * scale_factor));

    zgui.backend.init(
        window,
        gctx.device,
        @intFromEnum(zgpu.GraphicsContext.swapchain_format),
        @intFromEnum(wgpu.TextureFormat.undef),
    );
    defer zgui.backend.deinit();

    const style = zgui.getStyle();
    style.scaleAllSizes(scale_factor);
    style.frame_border_size = 1;
    // style.frame_rounding = 12;
    // style.grab_rounding = 12;
    // style.grab_min_size = 1;

    const v = try vssc.VVV.init(gpa);
    const n = vssc.getNode(v);

    zstbi.init(gpa);
    defer zstbi.deinit();

    var image = try zstbi.Image.createEmpty(@intCast(n.w), @intCast(n.h), 4, .{});
    defer image.deinit();

    const texture = gctx.createTexture(.{
        .usage = .{ .texture_binding = true, .copy_dst = true },
        .size = .{
            .width = image.width,
            .height = image.height,
            .depth_or_array_layers = 1,
        },
        .format = zgpu.imageInfoToTextureFormat(
            image.num_components,
            image.bytes_per_component,
            image.is_hdr,
        ),
    });

    const texture_view = gctx.createTextureView(texture, .{});

    var frame: i32 = 0;
    var prev_frame: i32 = -1;
    const last_frame = n.n_frames - 1;

    while (!window.shouldClose() and window.getKey(.escape) != .press) {
        zglfw.pollEvents();

        if (prev_frame != frame) {
            const vsframe = vssc.getFrame(v.vsapi, &image, n.node, &frame);
            defer v.vsapi.freeFrame.?(vsframe);

            gctx.queue.writeTexture(
                .{ .texture = gctx.lookupResource(texture).? },
                .{
                    .bytes_per_row = image.bytes_per_row,
                    .rows_per_image = image.height,
                },
                .{ .width = image.width, .height = image.height },
                u8,
                image.data,
            );

            prev_frame = frame;
        }

        zgui.backend.newFrame(
            gctx.swapchain_descriptor.width,
            gctx.swapchain_descriptor.height,
        );

        const viewport = zgui.getMainViewport();
        const pos_x, const pos_y = viewport.getPos();
        const sz_x, const sz_y = viewport.getSize();

        zgui.setNextWindowPos(.{ .x = pos_x, .y = pos_y });
        zgui.setNextWindowSize(.{ .w = sz_x, .h = sz_y - 200 });
        if (zgui.begin(
            "##",
            .{ .flags = .{
                .no_move = true,
                .no_resize = true,
                .no_title_bar = true,
                .no_collapse = true,
                .no_background = false,
                .horizontal_scrollbar = true,
            } },
        )) {
            const tex_id = gctx.lookupResource(texture_view).?;
            zgui.image(tex_id, .{ .w = @floatFromInt(n.w), .h = @floatFromInt(n.h) });

            // zgui.showDemoWindow(null);

        }
        zgui.end();

        zgui.setNextWindowPos(.{ .x = pos_x, .y = pos_y + (sz_y - 200) });
        zgui.setNextWindowSize(.{ .w = sz_x, .h = 200 });
        if (zgui.begin(
            "###",
            .{ .flags = .{
                .no_move = true,
                .no_resize = true,
                .no_title_bar = false,
                .no_collapse = true,
                .no_background = false,
                .horizontal_scrollbar = true,
            } },
        )) {
            zgui.pushStyleVar1f(.{ .idx = .grab_min_size, .v = 1 });

            zgui.setNextItemWidth(sz_x - 15);
            _ = zgui.sliderInt("##", .{
                .v = &frame,
                .min = 0,
                .max = last_frame,
            });
            zgui.popStyleVar(.{ .count = 1 });

            // TODO: frabe-by-frame control
            if (zgui.isKeyDown(.left_arrow)) {
                frame = @max(0, frame - 1);
            } else if (zgui.isKeyDown(.right_arrow)) {
                frame = @min(last_frame, frame + 1);
            }

            zgui.text("{}/{}", .{ frame, last_frame });

            // zgui.showDemoWindow(null);

        }
        zgui.end();

        const swapchain_texv = gctx.swapchain.getCurrentTextureView();
        defer swapchain_texv.release();

        const commands = commands: {
            const encoder = gctx.device.createCommandEncoder(null);
            defer encoder.release();

            // GUI pass
            {
                const pass = zgpu.beginRenderPassSimple(encoder, .load, swapchain_texv, null, null, null);
                defer zgpu.endReleasePass(pass);
                zgui.backend.draw(pass);
            }

            break :commands encoder.finish(null);
        };
        defer commands.release();

        gctx.submit(&.{commands});
        _ = gctx.present();
    }
}
