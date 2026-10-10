//! A plain dvui app on fizzy's backend: dvui's own widgets and its demo, nothing of fizzy the
//! editor, and each floating window an OS window of its own where the backend has them
//! (`viewports`), looking just as it does in the main window: its own header and close button, no
//! OS title bar (`.app`). The main window is an ordinary OS window. On a backend without them —
//! dvui's own SDL3 backend (`-Ddvui-backend=sdl3`), or Wayland, where a window cannot be placed —
//! the same floating windows stay in the main window, as in any dvui app.
//!
//! There stays one `dvui.Window` and one frame. A floating window that is out is drawn in its
//! viewport's band of the frame, far past the main window's edge, and its OS window shows that
//! band; the pointer over the OS window comes back to dvui as a pointer in the band. Any floating
//! window can go out, the app's own or dvui's demo: dvui keeps where each is (`_rect` in its data,
//! by its id), and the app moves that into the band and reads it back. What it takes, each frame:
//!
//! - before drawing (`beforeFloats`): a window the OS moved takes its floating window with it
//!   (`osPlaced`), and each band is a screen of dvui's (`dvui.screensSet`), so dvui keeps the
//!   floating window in it;
//! - drawing, as dvui draws anywhere, naming the floating windows to put out as they draw (`out`);
//! - after drawing (`afterFloats`): dvui's dialogs and toasts made (`Window.drawRetained`); a
//!   window whose floating window was not drawn — closed — goes; each one named and not yet out
//!   goes into a viewport over where it is (`viewports.open`); and each window is put where its
//!   floating window is (`viewports.place`), told where its header is for the OS to move it by
//!   (`hints`), and handed its picture: every subwindow in its band, taken out of the frame
//!   (`viewports.Picture`), so the main window draws none of it.
//!
//! A floating window resizes itself from its edges, as dvui's does anywhere, and its OS window
//! follows (`place`); while it holds the pointer the pointer is read in its band, wherever it goes
//! (`pinPointer`).
const std = @import("std");
const dvui = @import("dvui");
const backend = @import("backend");
const viewports = if (@hasDecl(backend, "viewports")) backend.viewports else @import("viewports_none");

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

/// The most floating windows out at once: as many as the backend has viewports. Past what it can
/// open, a floating window stays in the main window.
const max_outs = 8;

/// A floating window out in an OS window of its own, by its dvui id.
const Out = struct {
    id: dvui.Id,
    viewport: *viewports.Viewport,
    target: ?dvui.Texture.Target = null,
    /// Opened this frame: drawn in the main window still, in its band from the next.
    fresh: bool = true,
};
var outs: [max_outs]?Out = @splat(null);

/// The floating windows to put out, named as they draw this frame (`out`).
const Wanted = struct { id: dvui.Id, title: [:0]const u8 };
var wanted: [max_outs]Wanted = undefined;
var wanted_n: usize = 0;

/// How tall `dvui.windowHeader` is, natural: the strip the OS moves a window by. Measured on the
/// app's own floating windows; dvui's demo draws the same header.
var header_h: f32 = 32;

/// A floating window of the app's own. dvui keeps where it is, as for any floating window.
const Float = struct {
    open: bool = true,
    /// Where it first opens, natural, in the main window.
    at: dvui.Rect,
    title_buf: [32:0]u8 = @splat(0),
    title_len: usize = 0,
    count: u32 = 0,

    fn title(self: *const Float) [:0]const u8 {
        return self.title_buf[0..self.title_len :0];
    }
};
var floats: [4]?Float = @splat(null);
var made: u32 = 0;
var started = false;

fn frame() !dvui.App.Result {
    // dvui's demo and two floating windows of the app's own to begin with.
    if (!started) {
        started = true;
        dvui.Examples.show_demo_window = true;
        newFloat();
        newFloat();
    }
    beforeFloats();
    mainWindow();
    for (&floats, 0..) |*slot, i| if (slot.*) |*f| drawFloat(f, i);
    dvui.Examples.demo(.lite);
    if (dvui.Examples.show_demo_window) if (demoWindow()) |id| out(id, "DVUI Demo");
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
    if (!dvui.Examples.show_demo_window) {
        if (dvui.button(@src(), "Show the dvui demo", .{}, .{})) dvui.Examples.show_demo_window = true;
    }
}

fn newFloat() void {
    const slot = for (&floats) |*slot| {
        if (slot.* == null) break slot;
    } else return;
    made += 1;
    const step: f32 = @floatFromInt(made % 6);
    slot.* = .{ .at = .{ .x = 80 + 32 * step, .y = 140 + 24 * step, .w = 280, .h = 180 } };
    const f = &slot.*.?;
    const t: []const u8 = std.fmt.bufPrint(&f.title_buf, "Floating window {d}", .{made}) catch "";
    f.title_len = t.len;
}

fn drawFloat(f: *Float, i: usize) void {
    var fw = dvui.floatingWindow(@src(), .{ .open_flag = &f.open }, .{ .id_extra = i, .rect = f.at, .min_size_content = .{ .w = 220, .h = 120 } });
    defer fw.deinit();
    const header = dvui.windowHeader(f.title(), "", &f.open);
    // Moved by its header only, as dvui's demos do: elsewhere a press is its content's.
    fw.dragAreaSet(header);
    header_h = header.h / dvui.windowNaturalScale();
    out(fw.data().id, f.title());
    // Closed by its X: its window goes next frame, which comes now rather than at the next event.
    if (!f.open) dvui.refresh(null, @src(), null);
    var box = dvui.box(@src(), .{}, .{ .expand = .both, .padding = .all(12) });
    defer box.deinit();
    dvui.label(@src(), "Clicked {d} times", .{f.count}, .{});
    if (dvui.button(@src(), "Count", .{}, .{})) f.count += 1;
}

/// dvui's demo's floating window, by its id: the subwindow its tag's rect is. dvui gives a floating
/// window's `tag` to the box it draws in, which fills it, not to the window itself.
fn demoWindow() ?dvui.Id {
    const t = dvui.tagGet(dvui.Examples.demo_window_tag) orelse return null;
    if (t.rect.w < 1 or t.rect.h < 1) return null;
    for (dvui.currentWindow().subwindows.stack.items) |sw| {
        const r = sw.rect_pixels;
        if (@abs(r.x - t.rect.x) < 1 and @abs(r.y - t.rect.y) < 1 and @abs(r.w - t.rect.w) < 1 and @abs(r.h - t.rect.h) < 1) return sw.id;
    }
    return null;
}

/// Put floating window `id` out in an OS window of its own, called `title` there: named each frame
/// it draws.
fn out(id: dvui.Id, title: [:0]const u8) void {
    if (wanted_n == wanted.len) return;
    wanted[wanted_n] = .{ .id = id, .title = title };
    wanted_n += 1;
}

fn outOf(id: dvui.Id) ?*Out {
    for (&outs) |*slot| if (slot.*) |*o| if (o.id == id) return o;
    return null;
}

fn release(o: *Out) void {
    viewports.close(o.viewport);
    if (o.target) |t| t.destroyLater();
}

fn natural(r: viewports.Rect, s: f32) dvui.Rect {
    return .{ .x = r.x / s, .y = r.y / s, .w = r.w / s, .h = r.h / s };
}

fn physical(r: dvui.Rect, s: f32) viewports.Rect {
    return .{ .x = r.x * s, .y = r.y * s, .w = r.w * s, .h = r.h * s };
}

fn beforeFloats() void {
    wanted_n = 0;
    for (&floats) |*slot| if (slot.*) |f| if (!f.open) {
        slot.* = null;
    };
    if (comptime !viewports.supported) return;
    const s = dvui.windowNaturalScale();
    var screens: [max_outs]dvui.Rect.Natural = undefined;
    var n: usize = 0;
    var pin: viewports.Pin = .none;
    for (&outs) |*slot| {
        const o = if (slot.*) |*o| o else continue;
        // The OS moved its window: the floating window goes with it.
        if (viewports.osPlaced(o.viewport)) |fr| dvui.dataSet(null, o.id, "_rect", natural(fr, s));
        _ = viewports.osMoveEnded(o.viewport);
        const r = dvui.dataGet(null, o.id, "_rect", dvui.Rect) orelse continue;
        screens[n] = .{ .x = r.x, .y = r.y, .w = r.w, .h = r.h };
        n += 1;
        // Resized from its edges, it holds the pointer: read in its band till it lets go, even
        // past its window's edge.
        if (dvui.captured(o.id)) pin = .{ .viewport = o.viewport };
    }
    dvui.screensSet(screens[0..n]);
    viewports.pinPointer(pin);
}

fn afterFloats() void {
    if (comptime !viewports.supported) return;
    const cw = dvui.currentWindow();
    // Dialogs and toasts are subwindows from here, so each lands in the window it is over.
    cw.drawRetained(.{});
    const s = dvui.windowNaturalScale();

    // One no longer named — its X cleared what showed it, as dvui's demo's does — goes next frame,
    // which comes now rather than at the next event.
    for (outs) |slot| if (slot) |o| {
        const named = for (wanted[0..wanted_n]) |w| {
            if (w.id == o.id) break true;
        } else false;
        if (!named) dvui.refresh(null, @src(), null);
    };
    // A window whose floating window was not drawn this frame — closed — goes.
    for (&outs) |*slot| {
        const o = if (slot.*) |*o| o else continue;
        const drawn = for (cw.subwindows.stack.items) |sw| {
            if (sw.id == o.id) break sw.used;
        } else false;
        if (drawn) continue;
        release(o);
        slot.* = null;
    }

    // Each floating window named and not out yet goes into a window of its own, opening over
    // where it is in the main window; it is drawn in that window's band from the next frame.
    for (wanted[0..wanted_n]) |w| {
        if (outOf(w.id) != null) continue;
        if (!viewports.available()) break;
        const slot = for (&outs) |*slot| {
            if (slot.* == null) break slot;
        } else break;
        const r = dvui.dataGet(null, w.id, "_rect", dvui.Rect) orelse continue;
        // Not on its first frame, which dvui spends measuring it, hidden, with no size yet.
        if (r.w < 1 or r.h < 1) continue;
        const vp = viewports.open(physical(r, s), w.title, .app) orelse break;
        slot.* = .{ .id = w.id, .viewport = vp };
        dvui.dataSet(null, w.id, "_rect", natural(viewports.frameOf(vp), s));
        dvui.refresh(null, @src(), null);
    }

    for (&outs) |*slot| {
        const o = if (slot.*) |*o| o else continue;
        if (o.fresh) {
            o.fresh = false;
            continue;
        }
        const r = dvui.dataGet(null, o.id, "_rect", dvui.Rect) orelse continue;
        const shown = viewports.place(o.viewport, physical(r, s));
        // The OS moves its window by its header — the top `header_h` — but for the close button,
        // square at the header's height: at its right end where buttons go OK then Cancel
        // (Windows), else at its left (`dvui.windowHeader`); and not from the floating window's
        // own resize zones round its edge (`app_side`).
        const hh = header_h * s;
        const keep_x = if (cw.button_order == .ok_cancel) shown.x + shown.w - hh else shown.x;
        viewports.hints(o.viewport, .{
            .drag = .{ .x = shown.x, .y = shown.y, .w = shown.w, .h = hh },
            .keep = .{ .x = keep_x, .y = shown.y, .w = hh, .h = hh },
            .glass = shown,
            .edge = 0,
            .app_side = 6 * s,
            .app_corner = 15 * s,
        });
        const w: u32 = @intFromFloat(@max(1, @round(shown.w)));
        const h: u32 = @intFromFloat(@max(1, @round(shown.h)));
        const target = viewports.sizedTarget(&o.target, w, h) orelse continue;
        const area: dvui.Rect.Physical = .{ .x = shown.x, .y = shown.y, .w = shown.w, .h = shown.h };
        const picture: viewports.Picture = .begin(target, shown);
        for (cw.subwindows.stack.items) |*sw| {
            if (area.contains(sw.rect_pixels.center())) picture.subwindow(sw, true);
        }
        picture.end();
        viewports.present(o.viewport, target);
    }
}
