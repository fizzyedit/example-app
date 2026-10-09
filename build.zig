//! Applications built on fizzy, from outside fizzy.
//!
//! `zig build run-fizzy` builds a fizzy app: fizzy's framework and its plugins, in one of the
//! shapes in `shapes/` (`-Dshape=`), with this repo's plugins bundled in.
//!
//! `zig build run-dvui` will build a plain dvui app on fizzy's backend: dvui's widgets, with
//! floating windows, menus and dialogs as OS windows of their own. It needs the backend as a
//! package of its own first.
const std = @import("std");
const fizzy = @import("fizzy");

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

    // Where the dvui app goes: dvui's own widgets on fizzy's backend. Waits on the backend
    // becoming a package an app depends on without the rest of fizzy.
    b.step("run-dvui", "Run a plain dvui app on fizzy's backend (not yet)").dependOn(
        &b.addFail("run-dvui needs fizzy's backend as a package of its own; see this repo's README").step,
    );
}
