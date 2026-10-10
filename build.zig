//! Applications built on fizzy, from outside fizzy.
//!
//! `zig build run-fizzy` builds a fizzy app: fizzy's framework and its plugins, in one of the
//! shapes in `shapes/` (`-Dshape=`), with this repo's plugins bundled in.
//!
//! `zig build run-replay` builds a plain dvui app, nothing of fizzy, with tape playback from the
//! plugin SDK's `replay`: it plays a tape into its own window and prints what is on screen.
//!
//! `zig build run-dvui` builds a plain dvui app on fizzy's backend: dvui's own widgets, each
//! floating window an OS window of its own. `-Ddvui-backend=sdl3` builds the same app on dvui's own
//! SDL3 backend, where the floating windows stay in the main window.
const std = @import("std");
const fizzy = @import("fizzy");
const fizzy_sdk = @import("fizzy_sdk");

/// The layout shapes. Each is one file in `shapes/`, read end to end and copied, never
/// configured: a shape that needs something new is a new file.
const Shape = enum {
    /// One region, the workspace, and nothing else.
    minimal,
    /// A large canvas, a short strip under it, the explorer on the right.
    studio,
    /// One leftover place the user splits from its corner menu.
    endless,
};

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const shape = b.option(Shape, "shape", "The fizzy app's layout shape (default: studio)") orelse .studio;
    // `shapes/studio.zon` is the studio shape as data. A shape that needs a condition has to be
    // the `.zig` one.
    const zon_layout = b.option(bool, "zon-layout", "Studio only: the shape as data (shapes/studio.zon)") orelse false;
    const layout = switch (shape) {
        .minimal => "shapes/minimal.zig",
        .studio => if (zon_layout) "shapes/studio.zon" else "shapes/studio.zig",
        .endless => "shapes/endless.zig",
    };
    const display = switch (shape) {
        .minimal => "Minimal App",
        .studio => "Studio App",
        .endless => "Endless App",
    };
    // Its own executable, window title, bundle id and config directory per shape.
    const name = b.fmt("{s}app", .{@tagName(shape)});

    // `defer-app`: fizzy builds the app when `buildApp` hands it the plugins to bundle, which
    // `b.dependency` options cannot carry (a plugin is a module from another package).
    const fizzy_dep = b.dependency("fizzy", .{
        .target = target,
        .optimize = optimize,
        .@"defer-app" = true,
        .@"app-name" = name,
        .@"app-display-name" = @as([]const u8, display),
        .@"app-bundle-id" = b.fmt("dev.fizzy.{s}", .{name}),
        .@"app-layout" = b.path(layout),
    });
    const hello = b.dependency("hello", .{ .target = target, .optimize = optimize });
    const shader = b.dependency("shader", .{ .target = target, .optimize = optimize });
    try fizzy.buildApp(fizzy_dep, &.{
        .{ .name = "hello", .module = hello.module("plugin") },
        .{ .name = "shader", .module = shader.module("plugin") },
    });

    const exe = fizzy_dep.artifact(name);
    b.installArtifact(exe);

    const run_fizzy = b.addRunArtifact(exe);
    run_fizzy.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_fizzy.addArgs(args);
    b.step("run-fizzy", "Run the fizzy app in the shape -Dshape picks").dependOn(&run_fizzy.step);

    // A plain dvui app with tape playback: dvui as any app has it (the SDK pins it, the app picks
    // its own backend) and `tape` and `replay` built against it. Not part of the default install.
    const sdk = b.dependency("fizzy_sdk", .{ .target = target, .optimize = optimize });
    const dvui_dep = sdk.builder.dependency("dvui", .{ .target = target, .optimize = optimize, .backend = .sdl3 });
    const dvui_mod = dvui_dep.module("dvui_sdl3");
    const automation = fizzy_sdk.replay.modules(b, sdk.builder, dvui_mod, target, optimize);
    const replay_exe = b.addExecutable(.{
        .name = "replay-app",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .root_source_file = b.path("replay/main.zig"),
        }),
    });
    replay_exe.root_module.addImport("dvui", dvui_mod);
    replay_exe.root_module.addImport("tape", automation.tape);
    replay_exe.root_module.addImport("replay", automation.replay);
    const install_replay = b.addInstallArtifact(replay_exe, .{});
    b.step("replay", "Build the replay app").dependOn(&install_replay.step);
    const run_replay = b.addRunArtifact(replay_exe);
    run_replay.step.dependOn(&install_replay.step);
    if (b.args) |args| run_replay.addArgs(args);
    b.step("run-replay", "Run the replay app: a plain dvui app with tape playback").dependOn(&run_replay.step);

    // A plain dvui app on fizzy's backend (`dvui/main.zig`): dvui and the backend from fizzy, the
    // backend's `viewports` for its floating windows' OS windows. Not part of the default install.
    const dvui_backend = b.option(fizzy.NativeBackend, "dvui-backend", "run-dvui: fizzy (OS windows) or sdl3 (dvui's own, the main window only)") orelse .fizzy;
    const dvui_exe = b.addExecutable(.{
        .name = "dvui-app",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .root_source_file = b.path("dvui/main.zig"),
        }),
    });
    try fizzy.addDvui(fizzy_dep, dvui_exe.root_module, dvui_backend);
    const install_dvui = b.addInstallArtifact(dvui_exe, .{});
    b.step("dvui", "Build the dvui app").dependOn(&install_dvui.step);
    const run_dvui = b.addRunArtifact(dvui_exe);
    run_dvui.step.dependOn(&install_dvui.step);
    if (b.args) |args| run_dvui.addArgs(args);
    b.step("run-dvui", "Run a plain dvui app on fizzy's backend, its floating windows OS windows").dependOn(&run_dvui.step);
}
