# Animation Player Suite — Design Spec

**Date:** 2026-08-21
**Status:** Approved (design), pending implementation plan
**Repo:** `Escritorio\Scripts\AnimationPlayer` (own git repo)

## Purpose

A standalone Roblox exploit suite that plays any catalog animation/emote on
the local character, driven by a custom Drawing-API UI (0 GUI instances).
The user builds their own library of animations by name + ID, which persist
across sessions. A keybind and an in-UI toggle trigger playback of the
selected animation.

## The Core Method

The playback engine is built on the recently discovered method: a catalog
asset ID (emote, bundle animation, animation pack item) can be resolved to a
real `AnimationId` without knowing the raw animation ID:

```lua
local asset = game:GetObjects("rbxassetid://" .. id)[1]
if asset and asset:IsA("Animation") then
    local realId = string.match(asset.AnimationId, "(%d+)")
    -- load realId onto the character's Animator and play
end
```

This lets the user paste any catalog animation asset ID and play it.

## Non-Goals (YAGNI)

- No replication of the animation to other players (self-play only).
- No animation editing/authoring — playback only.
- No cloud/shared library — local filesystem only.
- No seed/default animations — the list starts empty (user's decision).
- Reuse of an existing UI lib is out; a new minimal Drawing lib is built
  scoped to exactly the widgets this suite needs.

## Architecture

Module convention: every source file is `return function(A) ... end`, where
`A` is the shared app table carrying services and config. No `require` (not
available in the executor). A bundler concatenates modules into a single
self-contained `dist/AnimationPlayer.lua` loaded via `loadstring`/`readfile`.

```
src/
  core/
    player.lua   -- playback engine (GetObjects method, play/stop/loop/speed)
    store.lua    -- JSON persistence (readfile/writefile, add/remove/list)
  ui/
    drawing.lua  -- minimal Drawing-API widget lib
  app.lua        -- wires UI + core into the suite window
  init.lua       -- entry: cleanup guard, instantiate app
build/
  bundle.sh      -- inline modules -> dist/AnimationPlayer.lua
dist/
  AnimationPlayer.lua
docs/specs/
  2026-08-21-animation-player-suite-design.md
```

### Shared table `A`

Built by `init.lua`, passed to every module:

```
A.Services  = { Players, UserInputService, RunService, ... }  -- cached
A.Config    = { menuKey = Enum.KeyCode.RightShift,
                playKey = Enum.KeyCode.E,
                speed = 1, looped = true }
A.Player    = <player.lua service>
A.Store     = <store.lua service>
A.UI        = <drawing.lua lib>
A.State     = { selected = nil }   -- currently selected saved anim {name,id}
```

## Component: `core/player.lua`

Owns the single active `AnimationTrack`.

- `player.resolve(id) -> realId | nil, err`
  1. `pcall(game.GetObjects, game, "rbxassetid://"..id)` → first result.
  2. If it's an `Animation`, return the numeric id from its `AnimationId`.
  3. Else fall back: treat `id` itself as a raw animation id (build an
     `Animation` with `AnimationId = "rbxassetid://"..id`) and use it.
  4. On any failure return `nil, "invalid asset"`.
- `player.play(id)`:
  - `stop()` any current track first.
  - Resolve id → build `Animation`, `animator:LoadAnimation`.
  - `track.Priority = Enum.AnimationPriority.Action4`.
  - `track.Looped = A.Config.looped`.
  - `track:Play()`, then `track:AdjustSpeed(A.Config.speed)`.
- `player.stop()`: `track:Stop()` if present, drop the reference.
- `player.setSpeed(v)`: live `track:AdjustSpeed(v)` + store in Config.
- `player.setLooped(b)`: sets `track.Looped` live + Config.
- Animator handling: fetch from
  `character.Humanoid:FindFirstChildOfClass("Animator")`; re-fetch on
  `Players.LocalPlayer.CharacterAdded` (respawn). If the loop toggle is ON
  and a selection exists, optionally resume after respawn.
- All Roblox calls wrapped in `pcall`; failures surface as a UI notification
  string, never a crash.

## Component: `core/store.lua`

Persistence of the user's animation library.

- File: `AnimationPlayer/saved.json` (folder created via `makefolder` if the
  executor supports it, guarded by `pcall`).
- Record shape: `{ name = string, id = string }`. Stored as a JSON array.
- API:
  - `store.list() -> array` (in-memory cache, source of truth for UI)
  - `store.add(name, id) -> ok, err` — rejects empty name/id and duplicate
    names; appends; writes file.
  - `store.remove(name)` — removes by name; writes file.
  - `store.get(name) -> record | nil`
- Boot: `pcall(readfile)`; if missing/unparseable, start with `{}` (empty).
- If `writefile` is unavailable, keep the library in memory only and set a
  flag so the UI can warn "no persistence".
- JSON via the executor's global (`HttpService:JSONEncode/Decode` is always
  available in-game; use that rather than a bundled JSON lib).

## Component: `ui/drawing.lua`

Retained-mode Drawing-API widget library, 0 GUI instances. Only the widgets
this suite needs. A single `RenderStepped` redraw loop + `InputBegan/Ended`
handlers.

Widgets:
- **Window** — titlebar + body rectangle, draggable by titlebar; global
  show/hide bound to `A.Config.menuKey` (default RightShift, rebindable).
- **List** (always-open, non-collapsing) — one row per saved animation:
  row text = name; click row = select (highlight the selected row); a small
  `X` glyph at the row's right edge = delete that animation. Scrolls if rows
  exceed the visible area.
- **TextInput** ×2 (name, animation ID) — click to focus; captures keys via
  `UserInputService.InputBegan` + `UserInputService:GetStringForKeyCode` for
  the character, plus Backspace and a blinking caret. Only one input focused
  at a time.
- **Button** — Save, Play, Stop.
- **Toggle** — Loop (bound to `A.Config.looped`).
- **Slider** — Speed, range 0.1–3.0, live.
- **Keybind picker** — for the play key: click, next key pressed becomes the
  bind; shows current key. (Menu key rebindable through the same widget.)
- **Notify** — transient one-line text (errors / "saved" / "no persistence").

Every Drawing object is tracked in a table for teardown.

## Component: `app.lua` (flow)

- Build the window; render the always-open List from `store.list()`.
- Clicking a list row sets `A.State.selected`.
- Add form: `[Name] [Animation ID] [Save]` → `store.add` → refresh list;
  show notify on success/error.
- Delete: row `X` → `store.remove` → refresh list; clear selection if it was
  the deleted one.
- Play trigger (both the play keybind and the Play toggle):
  - Toggle ON or keybind press → `player.play(selected.id)` (needs a
    selection; otherwise notify "select an animation").
  - Toggle OFF → `player.stop()`.
  - The keybind toggles the same play state as the toggle (they stay in
    sync).
- Loop toggle → `player.setLooped`. Speed slider → `player.setSpeed`.
- Global Stop button → `player.stop()` + toggle OFF.

## Component: `init.lua` (entry & lifecycle)

- Cleanup guard: if `getgenv().__ANIMPLAYER_CLEANUP` exists, call it first
  (destroy all Drawings, disconnect all connections, stop the track) so
  re-running never duplicates the UI. Then set a fresh cleanup closure.
- Cache services, build `A`, instantiate store → ui → app.

## Config defaults

| Setting   | Default              | Rebindable |
|-----------|----------------------|------------|
| menu key  | RightShift           | yes (UI)   |
| play key  | E                    | yes (UI)   |
| looped    | true                 | yes (UI)   |
| speed     | 1.0                  | yes (UI)   |

## Error handling summary

- Invalid / non-Animation asset id → notify "invalid asset", no play.
- No selection on trigger → notify "select an animation".
- Respawn mid-play → re-fetch Animator; resume if loop is on.
- No `writefile` → in-memory library + persistent "no persistence" warning.
- Any Roblox API error → `pcall`-guarded, surfaced as notify text.

## Build

`build/bundle.sh` (git-bash) inlines `drawing.lua`, `store.lua`,
`player.lua`, `app.lua` as `return function(A)` chunks into an assembly
template that builds `A`, calls each in dependency order (drawing → store →
player → app), and wraps with the `init.lua` cleanup guard. Output:
`dist/AnimationPlayer.lua`, loadable via `loadstring(readfile(...))()` or an
`HttpGet` host later.

## Testing

No local Lua runtime. Verification via **roblox-executor-mcp**:
`execute-file` the built dist, then `get-console-output` and screenshots.
Smoke checklist:
1. Loads clean, no errors; window renders; list empty.
2. Add "test" + a known emote id → row appears; `saved.json` written.
3. Re-run → row persists (loaded from file).
4. Select row, press E / Play toggle → emote plays on character.
5. Loop stays looping; speed slider changes speed live; Stop stops.
6. Delete row → gone from list + file.
7. RightShift hides/shows window; rebinding keys works.
8. `getgenv().__ANIMPLAYER_CLEANUP()` removes everything; re-run does not
   duplicate.

Final live-fire (real gameplay use) by the user.
```
