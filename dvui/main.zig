//! A plain dvui app on fizzy's backend: dvui's own widgets, its demo, and OS windows of its own
//! through `dvui.osWindow` — nothing of fizzy the editor, and nothing but dvui in the app's code.
//!
//! On fizzy's backend each `dvui.osWindow` is a floating window in the one frame, shown in an OS
//! window of its own: the OS's title bar and buttons in the theme's colour, as on the main window,
//! and the floating window's content below. The OS moves, resizes, zooms and closes it; on macOS it
//! is an ordinary window, with a full screen of its own. The backend does all of it
//! (`backend/src/os_windows.zig` in fizzy). Every other floating window, dvui's demo among them,
//! stays in the main window, as in dvui's own example. On dvui's own SDL3 backend
//! (`-Ddvui-backend=sdl3`) `dvui.osWindow` opens a `dvui.Window` of its own instead.
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

/// A window of the app's own: an in-app floating window, which can be dragged out into an OS window
/// of its own on fizzy's backend, or a `dvui.osWindow`.
const Window = struct {
    os: bool,
    open: bool = true,
    title_buf: [32:0]u8 = @splat(0),
    title_len: usize = 0,
    count: u32 = 0,

    fn title(self: *const Window) [:0]const u8 {
        return self.title_buf[0..self.title_len :0];
    }
};
var windows: [6]?Window = @splat(null);
var made: u32 = 0;
var started = false;

fn frame() !dvui.App.Result {
    // dvui's demo, in the main window, to begin with. An OS window opens only when one is asked
    // for ("New window"), or when a floating window is dragged out of the app's windows.
    if (!started) {
        started = true;
        dvui.Examples.show_demo_window = true;
    }
    mainWindow();
    // dvui's demo first: a window opens over those opened before it, and the demo, centred and much
    // the larger, hid the app's own windows opened under it.
    dvui.Examples.demo(.lite);
    for (&windows, 0..) |*slot, i| if (slot.*) |*w| {
        if (!w.open) {
            slot.* = null;
            continue;
        }
        if (w.os) osWindow(w, i) else floatWindow(w, i);
    };
    return .ok;
}

fn mainWindow() void {
    // No fill of its own: the window's colour is the backend's, under what the window is made of
    // (`materialPicker`), the theme's window colour at the transparency asked.
    var box = dvui.box(@src(), .{}, .{ .expand = .both, .padding = .all(16) });
    defer box.deinit();
    dvui.labelNoFmt(@src(), "dvui's own widgets on fizzy's backend.", .{}, .{ .font = .theme(.title) });
    dvui.labelNoFmt(@src(), "A window opens in the app, and drags out into one of its own; an OS window opens as one.", .{}, .{});
    {
        var row = dvui.box(@src(), .{ .dir = .horizontal }, .{ .margin = .{ .y = 12 } });
        defer row.deinit();
        if (dvui.button(@src(), "New window", .{}, .{})) newWindow(false);
        if (dvui.button(@src(), "New OS window", .{}, .{})) newWindow(true);
    }
    if (!dvui.Examples.show_demo_window) {
        if (dvui.button(@src(), "Show the dvui demo", .{}, .{})) dvui.Examples.show_demo_window = true;
    }
    if (comptime @hasDecl(dvui.backend, "window_material")) materialPicker();
}

/// What the app's windows are made of, on fizzy's backend: opaque, clear, blurred, frosted or
/// Liquid Glass, each falling back to what the OS can show, and how transparent. The colour is the
/// theme's window colour (dvui's theme picker).
fn materialPicker() void {
    const B = dvui.backend;
    var row = dvui.box(@src(), .{ .dir = .horizontal }, .{ .margin = .{ .y = 12 } });
    defer row.deinit();
    const names = [_][]const u8{ "Opaque", "Clear", "Blur", "Frost", "Liquid Glass" };
    var choice: usize = @backingInt(B.window_material.kind);
    if (dvui.dropdown(@src(), &names, .{ .choice = &choice }, .{}, .{ .min_size_content = .{ .w = 140 }, .gravity_y = 0.5 })) {
        B.window_material.kind = @fromBackingInt(@as(u8, @intCast(choice)));
        // Opaque, the window's colour covers it whole: half, to begin with.
        if (B.window_material.kind != .none and B.window_material.opacity >= 1) B.window_material.opacity = 0.5;
    }
    dvui.labelNoFmt(@src(), "Transparency", .{}, .{ .gravity_y = 0.5, .margin = .{ .x = 12 } });
    var transparency = if (B.window_material.kind == .none) 0 else 1 - B.window_material.opacity;
    if (dvui.slider(@src(), .{ .fraction = &transparency }, .{ .min_size_content = .{ .w = 160, .h = 20 }, .gravity_y = 0.5 })) {
        // Transparent at all, it is made of something: clear, where it was opaque.
        if (B.window_material.kind == .none and transparency > 0) B.window_material.kind = .transparent;
        B.window_material.opacity = 1 - transparency;
    }
}


fn newWindow(os: bool) void {
    const slot = for (&windows) |*slot| {
        if (slot.* == null) break slot;
    } else return;
    made += 1;
    slot.* = .{ .os = os };
    const w = &slot.*.?;
    const t: []const u8 = std.fmt.bufPrint(&w.title_buf, "{s} {d}", .{ if (os) "OS window" else "Window", made }) catch "";
    w.title_len = t.len;
}

/// An in-app floating window: on fizzy's backend, dragged by its header past the app's windows it
/// tears off into an OS window of its own (its close button, `open_flag`, is what lets it).
fn floatWindow(w: *Window, i: usize) void {
    var float = dvui.floatingWindow(@src(), .{ .open_flag = &w.open, .window_avoid = .nudge }, .{
        .id_extra = i,
        .min_size_content = .{ .w = 220, .h = 120 },
    });
    defer float.deinit();
    float.dragAreaSet(dvui.windowHeader(w.title(), "", &w.open));
    windowContent(w);
}

fn osWindow(w: *Window, i: usize) void {
    var os = dvui.osWindow(@src(), .{
        .title = w.title(),
        .size = .{ .w = 280, .h = 180 },
        .min_size = .{ .w = 220, .h = 120 },
    }, .{ .id_extra = i, .open_flag = &w.open });
    defer os.deinit();
    windowContent(w);
}

fn windowContent(w: *Window) void {
    var box = dvui.box(@src(), .{}, .{ .expand = .both, .padding = .all(12) });
    defer box.deinit();
    dvui.label(@src(), "Clicked {d} times", .{w.count}, .{});
    if (dvui.button(@src(), "Count", .{}, .{})) w.count += 1;
}
