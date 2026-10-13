//! A plain dvui app on fizzy's backend: dvui's own widgets, its demo, and OS windows of its own
//! through `dvui.osWindow` — nothing of fizzy the editor, and nothing but dvui in the app's code.
//!
//! On fizzy's backend each `dvui.osWindow` is a floating window in the one frame, shown in an OS
//! window of its own that looks just as the floating window does in the main window: dvui's header
//! and close button, no OS title bar. The OS moves it by its header; it resizes itself from its
//! edges, as a floating window does, and its window follows. The backend does all of it
//! (`backend/src/os_windows.zig` in fizzy). On dvui's own SDL3 backend (`-Ddvui-backend=sdl3`)
//! `dvui.osWindow` opens a `dvui.Window` of its own instead, as dvui does anywhere.
//!
//! dvui's demo is a floating window, and stays one: in the main window, as in dvui's own example.
const std = @import("std");
const dvui = @import("dvui");

pub const dvui_app: dvui.App = .{
    .config = .{ .options = .{
        .size = .{ .w = 960, .h = 640 },
        .title = "dvui on fizzy's backend",
    } },
    .frameFn = frame,
};
pub const main = dvui.App.main;
pub const panic = dvui.App.panic;
pub const std_options: std.Options = .{ .logFn = dvui.App.logFn };

/// An OS window of the app's own.
const Window = struct {
    open: bool = true,
    title_buf: [32:0]u8 = @splat(0),
    title_len: usize = 0,
    count: u32 = 0,

    fn title(self: *const Window) [:0]const u8 {
        return self.title_buf[0..self.title_len :0];
    }
};
var windows: [4]?Window = @splat(null);
var made: u32 = 0;
var started = false;

fn frame() !dvui.App.Result {
    // dvui's demo and two OS windows to begin with.
    if (!started) {
        started = true;
        dvui.Examples.show_demo_window = true;
        newWindow();
        newWindow();
    }
    mainWindow();
    for (&windows, 0..) |*slot, i| if (slot.*) |*w| {
        if (!w.open) {
            slot.* = null;
            continue;
        }
        osWindow(w, i);
    };
    dvui.Examples.demo(.lite);
    return .ok;
}

fn mainWindow() void {
    var box = dvui.box(@src(), .{}, .{ .expand = .both, .padding = .all(16) });
    defer box.deinit();
    dvui.labelNoFmt(@src(), "dvui's own widgets on fizzy's backend.", .{}, .{ .font = .theme(.title) });
    dvui.labelNoFmt(@src(), "Each window opened here is a dvui.osWindow.", .{}, .{});
    if (dvui.button(@src(), "New window", .{}, .{ .margin = .{ .y = 12 } })) newWindow();
    if (!dvui.Examples.show_demo_window) {
        if (dvui.button(@src(), "Show the dvui demo", .{}, .{})) dvui.Examples.show_demo_window = true;
    }
}

fn newWindow() void {
    const slot = for (&windows) |*slot| {
        if (slot.* == null) break slot;
    } else return;
    made += 1;
    slot.* = .{};
    const w = &slot.*.?;
    const t: []const u8 = std.fmt.bufPrint(&w.title_buf, "Window {d}", .{made}) catch "";
    w.title_len = t.len;
}

fn osWindow(w: *Window, i: usize) void {
    var os = dvui.osWindow(@src(), .{
        .title = w.title(),
        .size = .{ .w = 280, .h = 180 },
        .min_size = .{ .w = 220, .h = 120 },
    }, .{ .id_extra = i, .open_flag = &w.open });
    defer os.deinit();
    var box = dvui.box(@src(), .{}, .{ .expand = .both, .padding = .all(12) });
    defer box.deinit();
    dvui.label(@src(), "Clicked {d} times", .{w.count}, .{});
    if (dvui.button(@src(), "Count", .{}, .{})) w.count += 1;
}
