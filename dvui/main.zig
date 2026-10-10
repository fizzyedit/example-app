//! A plain dvui app on fizzy's backend: dvui's own widgets, nothing of fizzy the editor, and each
//! floating window an OS window of its own where the backend has them (`viewports`). On a backend
//! without them — dvui's own SDL3 backend (`-Ddvui-backend=sdl3`), or Wayland, where a window
//! cannot be placed — the same floating windows stay in the main window, as in any dvui app.
//!
//! There stays one `dvui.Window` and one frame. A floating window that is out is drawn in its
//! viewport's band of the frame, far past the main window's edge, and its OS window shows that
//! band; the pointer over the OS window comes back to dvui as a pointer in the band. What it takes,
//! each frame:
//!
//! - before drawing (`beforeFloats`): each floating window not out yet goes out into a viewport
//!   (`viewports.open`), one the OS moved or resized follows its window (`osPlaced`), and each
//!   band is a screen of dvui's (`dvui.screensSet`), so dvui keeps the floating window in it;
//! - the floating windows, drawn as dvui draws them anywhere (`drawFloat`);
//! - after drawing (`afterFloats`): dvui's dialogs and toasts made (`Window.drawRetained`), then
//!   each OS window put where its floating window is (`viewports.place`), told where its header is
//!   for the OS to move it by (`hints`), and handed its picture: every subwindow in its band,
//!   taken out of the frame (`viewports.Picture`), so the main window draws none of it.
const std = @import("std");
const dvui = @import("dvui");
const backend = @import("backend");
const viewports = if (@hasDecl(backend, "viewports")) backend.viewports else @import("viewports_none");

pub const dvui_app: dvui.App = .{
    .config = .{ .options = .{
        .size = .{ .w = 720, .h = 480 },
        .title = "dvui on fizzy's backend",
    } },
    .frameFn = frame,
};
pub const main = dvui.App.main;
pub const panic = dvui.App.panic;
pub const std_options: std.Options = .{ .logFn = dvui.App.logFn };

/// The most floating windows at once: as many as the backend has viewports. Past what it can
/// open, a floating window stays in the main window.
const max_floats = 8;

const Float = struct {
    /// Natural units of the frame: in the main window, or in its viewport's band once out.
    rect: dvui.Rect,
    open: bool = true,
    title_buf: [32:0]u8 = @splat(0),
    title_len: usize = 0,
    count: u32 = 0,
    viewport: ?*viewports.Viewport = null,
    target: ?dvui.Texture.Target = null,
    /// Its header this frame, physical (`dvui.windowHeader`): where the OS moves its window from.
    header: dvui.Rect.Physical = .{},

    fn title(self: *const Float) [:0]const u8 {
        return self.title_buf[0..self.title_len :0];
    }
};

var floats: [max_floats]?Float = @splat(null);
var made: u32 = 0;
var started = false;

fn frame() !dvui.App.Result {
    // Two floating windows to begin with.
    if (!started) {
        started = true;
        newFloat();
        newFloat();
    }
    beforeFloats();
    mainWindow();
    for (&floats, 0..) |*slot, i| if (slot.*) |*f| drawFloat(f, i);
    afterFloats();
    return .ok;
}

fn mainWindow() void {
    var box = dvui.box(@src(), .{}, .{ .expand = .both, .padding = .all(16) });
    defer box.deinit();
    dvui.labelNoFmt(@src(), "dvui's own widgets on fizzy's backend.", .{}, .{ .font = .theme(.title) });
    const how = if (viewports.supported and viewports.available())
        "Each floating window is an OS window of its own: move it, resize it, put it on another display."
    else
        "This backend has no OS windows besides this one, so floating windows stay in it.";
    dvui.labelNoFmt(@src(), how, .{}, .{});
    if (dvui.button(@src(), "New floating window", .{}, .{ .margin = .{ .y = 12 } })) newFloat();
}

fn newFloat() void {
    const slot = for (&floats) |*slot| {
        if (slot.* == null) break slot;
    } else return;
    made += 1;
    const step: f32 = @floatFromInt(made % 6);
    slot.* = .{ .rect = .{ .x = 80 + 32 * step, .y = 120 + 24 * step, .w = 280, .h = 180 } };
    const f = &slot.*.?;
    const t: []const u8 = std.fmt.bufPrint(&f.title_buf, "Floating window {d}", .{made}) catch "";
    f.title_len = t.len;
}

fn release(f: *Float) void {
    if (f.viewport) |vp| viewports.close(vp);
    if (f.target) |t| t.destroyLater();
}

fn beforeFloats() void {
    const s = dvui.windowNaturalScale();
    var screens: [max_floats]dvui.Rect.Natural = undefined;
    var n: usize = 0;
    for (&floats) |*slot| {
        const f = if (slot.*) |*f| f else continue;
        if (!f.open) {
            release(f);
            slot.* = null;
            continue;
        }
        if (f.viewport == null and viewports.available()) {
            // Out into an OS window over where it is in the main window; drawn in the band from now.
            const at: viewports.Rect = .{ .x = f.rect.x * s, .y = f.rect.y * s, .w = f.rect.w * s, .h = f.rect.h * s };
            if (viewports.open(at, f.title())) |vp| {
                f.viewport = vp;
                const fr = viewports.frameOf(vp);
                f.rect = .{ .x = fr.x / s, .y = fr.y / s, .w = fr.w / s, .h = fr.h / s };
            }
        }
        const vp = f.viewport orelse continue;
        // Its close button, or the OS's (⌘W): gone next frame.
        if (viewports.closeRequested(vp)) f.open = false;
        // The OS moved or resized its window: the floating window follows it.
        if (viewports.osPlaced(vp)) |fr| f.rect = .{ .x = fr.x / s, .y = fr.y / s, .w = fr.w / s, .h = fr.h / s };
        _ = viewports.osMoveEnded(vp);
        screens[n] = .{ .x = f.rect.x, .y = f.rect.y, .w = f.rect.w, .h = f.rect.h };
        n += 1;
    }
    dvui.screensSet(screens[0..n]);
}

fn drawFloat(f: *Float, i: usize) void {
    var fw = dvui.floatingWindow(@src(), .{ .rect = &f.rect, .open_flag = &f.open }, .{ .id_extra = i, .min_size_content = .{ .w = 220, .h = 120 } });
    defer fw.deinit();
    f.header = dvui.windowHeader(f.title(), "", &f.open);
    var box = dvui.box(@src(), .{}, .{ .expand = .both, .padding = .all(12) });
    defer box.deinit();
    dvui.label(@src(), "Clicked {d} times", .{f.count}, .{});
    if (dvui.button(@src(), "Count", .{}, .{})) f.count += 1;
}

fn afterFloats() void {
    if (comptime !viewports.supported) return;
    const cw = dvui.currentWindow();
    // Dialogs and toasts are subwindows from here, so each lands in the window it is over.
    cw.drawRetained(.{});
    const s = dvui.windowNaturalScale();
    for (&floats) |*slot| {
        const f = if (slot.*) |*f| f else continue;
        const vp = f.viewport orelse continue;
        const shown = viewports.place(vp, .{ .x = f.rect.x * s, .y = f.rect.y * s, .w = f.rect.w * s, .h = f.rect.h * s });
        // Its header moves its window, but for the close button at its right end; its edges resize it.
        const keep_w = f.header.h;
        viewports.hints(vp, .{
            .drag = .{ .x = f.header.x, .y = f.header.y, .w = f.header.w, .h = f.header.h },
            .keep = .{ .x = f.header.x + f.header.w - keep_w, .y = f.header.y, .w = keep_w, .h = f.header.h },
            .glass = shown,
            .edge = 6 * s,
        });
        const w: u32 = @intFromFloat(@max(1, @round(shown.w)));
        const h: u32 = @intFromFloat(@max(1, @round(shown.h)));
        const target = viewports.sizedTarget(&f.target, w, h) orelse continue;
        const area: dvui.Rect.Physical = .{ .x = shown.x, .y = shown.y, .w = shown.w, .h = shown.h };
        const picture: viewports.Picture = .begin(target, shown);
        for (cw.subwindows.stack.items) |*sw| {
            if (area.contains(sw.rect_pixels.center())) picture.subwindow(sw, true);
        }
        picture.end();
        viewports.present(vp, target);
    }
}
