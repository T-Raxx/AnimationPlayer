# Animation Player Suite

Drawing-API Roblox suite that plays any catalog animation/emote on your
character from a saved, persistent library. Custom Drawing UI (0 GUI
instances), keybind + toggle playback, loop + speed control.

## Load

```lua
loadstring(readfile("AnimationPlayer/dist/AnimationPlayer.lua"))()
```

(or host `dist/AnimationPlayer.lua` and `loadstring(game:HttpGet(url))()`)

## Use

- **RightShift** — show/hide menu (rebindable via "Menu key")
- Type a **name** + **animation / asset id**, click **Save** — appears in the list (starts empty; fill it with whatever emotes you want)
- Click a list row to select it; press **E** or the **Play (loop)** toggle to play (rebindable via "Play key")
- **Speed** slider adjusts playback speed live; **Looped** toggles looping
- **Stop** ends playback; each row's **X** deletes it
- Library persists to `AnimationPlayer/saved.json`

## How it plays catalog animations

Resolves a catalog asset id to its real `AnimationId` via
`game:GetObjects("rbxassetid://"..id)[1]`, then loads it onto the
character's `Animator`. If the input is a plain numeric animation id, it is
used directly as a fallback. So the id field accepts **both** catalog
emote/bundle asset ids and raw animation ids.

## Layout

```
src/
  core/player.lua   playback engine (resolve + play/stop/loop/speed)
  core/store.lua    JSON library persistence
  ui/drawing.lua    minimal Drawing-API widget lib
  app.lua           wires UI + core
  init.lua          entry: cleanup guard, builds shared table A
build/bundle.sh     inlines src -> dist/AnimationPlayer.lua
dist/AnimationPlayer.lua
```

Build: `bash build/bundle.sh`.

Re-running the loader never duplicates the UI (cleanup via
`getgenv().__ANIMPLAYER_CLEANUP`).
