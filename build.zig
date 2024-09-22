const std = @import("std");
const os = @import("builtin").os.tag;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "vspreviewz",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const zglfw = b.dependency("zglfw", .{
        .target = target,
    });

    exe.root_module.addImport("zglfw", zglfw.module("root"));
    exe.linkLibrary(zglfw.artifact("glfw"));

    @import("zgpu").addLibraryPathsTo(exe);
    const zgpu = b.dependency("zgpu", .{
        .target = target,
    });

    exe.root_module.addImport("zgpu", zgpu.module("root"));
    exe.linkLibrary(zgpu.artifact("zdawn"));

    const zgui = b.dependency("zgui", .{
        .target = target,
        .backend = .glfw_wgpu,
    });

    exe.root_module.addImport("zgui", zgui.module("root"));
    exe.linkLibrary(zgui.artifact("imgui"));

    const zstbi = b.dependency("zstbi", .{
        .target = target,
    });
    exe.root_module.addImport("zstbi", zstbi.module("root"));
    exe.linkLibrary(zstbi.artifact("zstbi"));

    const vapoursynth_dep = b.dependency("vapoursynth", .{
        .target = target,
        .optimize = optimize,
    });

    if (os == .windows) {
        exe.addLibraryPath(.{ .cwd_relative = "C:/Program Files/VapourSynth/sdk/lib64" });
    }

    const vs_lib = switch (os) {
        .windows => "vsscript",
        .linux => "vapoursynth-script",
        else => unreachable,
    };

    exe.root_module.addImport("vapoursynth", vapoursynth_dep.module("vapoursynth"));
    exe.linkSystemLibrary(vs_lib);
    exe.linkLibC();

    b.installArtifact(exe);
}
