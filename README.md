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

`zig build run-dvui` is where a plain dvui app on fizzy's backend goes: dvui's own widgets, with
floating windows, menus and dialogs as OS windows of their own (Liquid Glass windows on macOS).
It needs fizzy's backend as a package an app can depend on without the rest of fizzy, which is
not done yet; until then the step says so.

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
