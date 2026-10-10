# example-app

Applications built on [fizzy](https://github.com/fizzyedit/fizzy) as a library, from outside fizzy.

```sh
zig build run-fizzy                  # the studio shape
zig build run-fizzy -Dshape=minimal
zig build run-fizzy -Dshape=endless
zig build run-fizzy -Dshape=studio -Dzon-layout=true
```

Each is a whole fizzy app: fizzy's frame, its built-in plugins (files, text, images, markdown),
in a layout of this repo's own, with two more plugins bundled in. Each shape gets its own
executable, window title and config directory (`minimalapp`, `studioapp`, `endlessapp`).

`zig build run-replay` is a plain dvui app, nothing of fizzy, with tape playback from the plugin
SDK's `replay` (`replay/main.zig`). At launch it plays a live tape into its own window (clicks,
typing, a command), draws the tape's pointer, stops if you click or type, and when the tape ends
prints what is on screen as text: the names a test or an automation client reads instead of
pixels. It depends only on the SDK package.

`zig build run-dvui` is a plain dvui app on fizzy's backend (`dvui/main.zig`): dvui's own
widgets, and each `dvui.floatingWindow` an OS window of its own, moved, resized and closed by the
OS like any window. `fizzy.addDvui` gives it dvui, the backend and the backend's `viewports`.
`-Ddvui-backend=sdl3` builds the same app on dvui's own SDL3 backend, where there are no OS
windows besides the main one and the floating windows stay in it, as in any dvui app. Menus and
dialogs as OS windows of their own come later.

## Shapes

A shape is the app's layout: one file, ordinary code over fizzy's public `Layout` API. Fizzy
does not configure shapes; you pick the closest one, copy it into your app and change it.

| Shape | File | What it is |
|---|---|---|
| `minimal` | `shapes/minimal.zig` | One region, the workspace. Surfaces meant for a sidebar or panel have nowhere to go, and the same plugins run anyway. |
| `studio` | `shapes/studio.zig` | A large canvas, a short strip under it, the explorer on the right. |
| `studio`, as data | `shapes/studio.zon` | The same arrangement as a tree of places. A shape that needs a condition has to be the `.zig` one. |
| `endless` | `shapes/endless.zig` | One leftover place, split from its corner menu as often as you like. |

A shape exports `pub fn layout(ctx: ?*anyopaque, f: *Layout) !dvui.App.Result` and imports only
`dvui`, `app`, `core` and `fizzy_sdk`.

## Plugins

- **hello**, from [fizzyedit/example-plugin](https://github.com/fizzyedit/example-plugin): a
  plugin from its own repo, bundled in by URL as any third-party plugin would be.
- **shader** (`plugins/shader`): this app's own plugin, drawing liquid metaballs that follow the
  pointer with its own GPU program (`core.programs`). It also builds alone as a dylib
  (`cd plugins/shader && zig build`).

`build.zig` hands both to fizzy with `fizzy.buildApp`; they are linked in and registered like
fizzy's own.

## Your own app

`build.zig` is the whole recipe: depend on fizzy (`build.zig.zon`), call `b.dependency("fizzy",
…)` with your app's name, display name, bundle id, `.@"defer-app" = true` and your shape as
`app-layout`, then `fizzy.buildApp` with the plugins you bundle. Pin fizzy by commit, as this
repo does.
