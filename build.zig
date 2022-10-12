const std = @import("std");
const builtin = std.builtin;
const Builder = std.build.Builder;

var framework_dir: ?[]u8 = null;

fn sdkPath(comptime suffix: []const u8) []const u8 {
    if (suffix[0] != '/') @compileError("relToPath requires an absolute path!");
    return comptime blk: {
        const root_dir = std.fs.path.dirname(@src().file) orelse ".";
        break :blk root_dir ++ suffix;
    };
}

pub fn makeLib(b: *Builder, mode: builtin.Mode, target: std.zig.CrossTarget) *std.build.LibExeObjStep {
    const lib = b.addStaticLibrary("nfd", sdkPath("/src/lib.zig"));
    lib.setBuildMode(mode);
    lib.setTarget(target);

    const cflags = [_][]const u8{"-Wall"};
    lib.addIncludePath(sdkPath("/nativefiledialog/src/include"));
    lib.addCSourceFile(sdkPath("/nativefiledialog/src/nfd_common.c"), &cflags);
    if (lib.target.isDarwin()) {
        lib.addCSourceFile(sdkPath("/nativefiledialog/src/nfd_cocoa.m"), &cflags);
    } else if (lib.target.isWindows()) {
        lib.addCSourceFile(sdkPath("/nativefiledialog/src/nfd_win.cpp"), &cflags);
    } else {
        lib.addCSourceFile(sdkPath("/nativefiledialog/src/nfd_gtk.c"), &cflags);
    }

    lib.linkLibC();
    if (lib.target.isDarwin()) {
        const frameworks_path = macosFrameworksDir(b) catch unreachable;
        lib.addFrameworkPath(frameworks_path);
        lib.linkFramework("AppKit");
    } else if (lib.target.isWindows()) {
        lib.linkSystemLibrary("shell32");
        lib.linkSystemLibrary("ole32");
        lib.linkSystemLibrary("uuid"); // needed by MinGW
    } else {
        lib.linkSystemLibrary("atk-1.0");
        lib.linkSystemLibrary("gdk-3");
        lib.linkSystemLibrary("gtk-3");
        lib.linkSystemLibrary("glib-2.0");
        lib.linkSystemLibrary("gobject-2.0");
    }

    return lib;
}

/// helper function to get SDK path on Mac
fn macosFrameworksDir(b: *Builder) ![]u8 {
    if (framework_dir) |dir| return dir;

    var str = try b.exec(&[_][]const u8{ "xcrun", "--show-sdk-path" });
    const strip_newline = std.mem.lastIndexOf(u8, str, "\n");
    if (strip_newline) |index| {
        str = str[0..index];
    }
    framework_dir = try std.mem.concat(b.allocator, u8, &[_][]const u8{ str, "/System/Library/Frameworks" });
    return framework_dir.?;
}

pub fn getPackage(name: []const u8) std.build.Pkg {
    return std.build.Pkg{
        .name = name,
        .source = .{ .path = sdkPath("/src/lib.zig") },
    };
}

pub fn build(b: *Builder) void {
    const mode = b.standardReleaseOptions();
    const target = b.standardTargetOptions(.{});
    const lib = makeLib(b, mode, target);
    lib.install();

    var demo = b.addExecutable("demo", "src/demo.zig");
    demo.setBuildMode(mode);
    demo.addPackage(getPackage("nfd"));
    demo.linkLibrary(lib);
    demo.install();

    const run_demo_cmd = demo.run();
    run_demo_cmd.step.dependOn(b.getInstallStep());

    const run_demo_step = b.step("run", "Run the demo");
    run_demo_step.dependOn(&run_demo_cmd.step);
}
