# Animation Player Suite Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A standalone Drawing-API Roblox suite that plays any catalog animation on the local character from a user-built, persistent library, triggered by a keybind and an in-UI toggle.

**Architecture:** Modules follow the `return function(A)` convention (no `require`); a shared table `A` carries injected services (`A.fs`, `A.json`, `A.getObjects`, `A.getAnimator`), config, and the four services (`Store`, `Player`, `UI`, `App`). Dependency injection lets pure logic (store, `player.resolve`) run under a plain Luau VM with mocks. A bash bundler inlines every module into a single self-contained `dist/AnimationPlayer.lua`.

**Tech Stack:** Luau (Roblox executor), Drawing API (0 GUI instances), `writefile`/`readfile`, `HttpService` JSON, git-bash bundler.

**Spec:** `docs/specs/2026-08-21-animation-player-suite-design.md`

## Global Constraints

- Luau on a Roblox executor. No `require`. Every module file is exactly `return function(A) ... end`.
- UI is Drawing API only — **0 GUI instances**.
- Every Roblox API call is wrapped in `pcall`; failures surface via `A.notify(msg)`, never a crash.
- Cleanup guard `getgenv().__ANIMPLAYER_CLEANUP` — running the dist twice must never duplicate UI, connections, or tracks.
- Menu toggle key default `Enum.KeyCode.RightShift`; play key default `Enum.KeyCode.E`; both rebindable in-UI.
- Animation library starts **empty**.
- Persistence: `writefile` JSON at `AnimationPlayer/saved.json`, with in-memory fallback when filesystem is unavailable.

## Verification Method

No local Lua unit runner is assumed. Verify via **roblox-executor-mcp**:
1. `list-clients` / `set-active-client` — confirm a client is connected.
2. `execute-file` the probe or dist.
3. `get-console-output` (low limit) — assert on printed `PASS ...` / `FAIL ...` lines.
4. For UI tasks, `screenshot-window` to confirm render.

Probes for pure-logic tasks (2, 3-resolve) build a fake `A` with mocked
`fs`/`json`/`getObjects` and need no game state — they run on any connected
client. Tasks touching the real character or Drawing (3-play, 4, 5, 6, 7)
require an in-game character.

## File Structure

- `src/init.lua` — entry: cleanup guard, build real `A`, call modules in order, `A.App.start()`.
- `src/core/store.lua` — `A.Store`: JSON library persistence over injected `A.fs` + `A.json`.
- `src/core/player.lua` — `A.Player`: resolve + play/stop/loop/speed over injected `A.getObjects` + `A.getAnimator`.
- `src/ui/drawing.lua` — `A.UI`: retained-mode Drawing widget lib + render loop + teardown + `A.notify`.
- `src/app.lua` — `A.App`: builds the window and wires Store + Player + UI.
- `build/bundle.sh` — inlines modules into `dist/AnimationPlayer.lua`.
- `dist/AnimationPlayer.lua` — built output.
- `tests/` — probe scripts (`*.probe.lua`) executed via the MCP.

### Shared table `A` (authoritative shape)

```
A = {
  Services = { Players, UserInputService, RunService, HttpService },
  fs       = { read(path)->str|nil, write(path,str)->bool, isfile(path)->bool, makefolder(path) },
  json     = { encode(tbl)->str, decode(str)->tbl },   -- decode is pcall-safe, returns tbl or nil
  getObjects = function(url) -> {Instance,...},         -- wraps game:GetObjects
  getAnimator = function() -> Animator|nil,             -- local character's Animator
  Config   = { menuKey, playKey, looped=true, speed=1, hasPersistence=true },
  State    = { selected = nil },                        -- {name,id} or nil
  notify   = function(msg) end,                         -- set by UI (drawing.lua)
  Store=?, Player=?, UI=?, App=?,
}
```

Module call order in `init.lua`: **drawing → store → player → app** (drawing sets `A.notify` first).

---

### Task 1: Repo skeleton + bundler + cleanup guard

**Files:**
- Create: `src/init.lua`
- Create: `src/core/store.lua`, `src/core/player.lua`, `src/ui/drawing.lua`, `src/app.lua` (stubs)
- Create: `build/bundle.sh`
- Create: `dist/AnimationPlayer.lua` (built)
- Create: `.gitignore`

**Interfaces:**
- Consumes: nothing.
- Produces: bundle format (each module is `return function(A) ... end`, assembled by `bundle.sh`); the `A` table and `getgenv().__ANIMPLAYER_CLEANUP` contract used by every later task.

- [ ] **Step 1: Write module stubs**

Each of the four source modules is a stub that records it ran. `src/ui/drawing.lua`:
```lua
return function(A)
    A.UI = { _stub = true }
    A.notify = function(msg) print("[AnimPlayer] notify:", msg) end
end
```
`src/core/store.lua`:
```lua
return function(A)
    A.Store = { _stub = true }
end
```
`src/core/player.lua`:
```lua
return function(A)
    A.Player = { _stub = true }
end
```
`src/app.lua`:
```lua
return function(A)
    A.App = {
        start = function()
            print("[AnimPlayer] app started")
        end,
    }
end
```

- [ ] **Step 2: Write `src/init.lua` (cleanup guard + wiring)**

```lua
-- Animation Player Suite — entry
if getgenv().__ANIMPLAYER_CLEANUP then
    pcall(getgenv().__ANIMPLAYER_CLEANUP)
    getgenv().__ANIMPLAYER_CLEANUP = nil
end

local A = {}
A._connections = {}
A._drawings = {}

A.Services = {
    Players = game:GetService("Players"),
    UserInputService = game:GetService("UserInputService"),
    RunService = game:GetService("RunService"),
    HttpService = game:GetService("HttpService"),
}

-- filesystem wrappers (guarded; degrade to no-op when missing)
local function has(fn) return type(fn) == "function" end
A.fs = {
    read = function(p) local ok, r = pcall(readfile, p); return ok and r or nil end,
    write = function(p, s) return (pcall(writefile, p, s)) end,
    isfile = function(p) local ok, r = pcall(isfile, p); return ok and r or false end,
    makefolder = function(p) if has(makefolder) then pcall(makefolder, p) end end,
}
A.Config = {
    menuKey = Enum.KeyCode.RightShift,
    playKey = Enum.KeyCode.E,
    looped = true,
    speed = 1,
    hasPersistence = has(writefile) and has(readfile),
}
A.json = {
    encode = function(t) local ok, r = pcall(function() return A.Services.HttpService:JSONEncode(t) end); return ok and r or "[]" end,
    decode = function(s) local ok, r = pcall(function() return A.Services.HttpService:JSONDecode(s) end); return ok and r or nil end,
}
A.getObjects = function(url)
    local ok, r = pcall(function() return game:GetObjects(url) end)
    return ok and r or nil
end
A.getAnimator = function()
    local plr = A.Services.Players.LocalPlayer
    local char = plr and plr.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    return hum and hum:FindFirstChildOfClass("Animator") or nil
end
A.State = { selected = nil }

-- helpers used by all modules for tracked lifetime
A.track = function(conn) table.insert(A._connections, conn); return conn end
A.trackDraw = function(d) table.insert(A._drawings, d); return d end

-- module load order: drawing -> store -> player -> app
local MODULES = { DRAWING, STORE, PLAYER, APP } -- placeholders replaced by bundler
for _, m in ipairs(MODULES) do m(A) end

getgenv().__ANIMPLAYER_CLEANUP = function()
    for _, c in ipairs(A._connections) do pcall(function() c:Disconnect() end) end
    for _, d in ipairs(A._drawings) do pcall(function() d:Remove() end) end
    if A.Player and A.Player.stop then pcall(A.Player.stop) end
end

A.App.start()
```

Note for bundler: the `MODULES` line's placeholders (`DRAWING`, `STORE`, `PLAYER`, `APP`) are replaced by `bundle.sh` with the inlined `(function() <module source> end)()` chunks.

- [ ] **Step 3: Write `build/bundle.sh`**

```bash
#!/usr/bin/env bash
# Inlines src modules into dist/AnimationPlayer.lua
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=dist/AnimationPlayer.lua
mkdir -p dist

emit_module() { # $1 = path -> "(function() <src> end)()"
    printf '(function()\n'
    cat "$1"
    printf '\nend)()'
}

INIT=src/init.lua
DRAWING=$(emit_module src/ui/drawing.lua)
STORE=$(emit_module src/core/store.lua)
PLAYER=$(emit_module src/core/player.lua)
APP=$(emit_module src/app.lua)

# Replace the MODULES placeholder line in init.lua with real inlined modules.
awk -v d="$DRAWING" -v s="$STORE" -v p="$PLAYER" -v a="$APP" '
/local MODULES = \{ DRAWING, STORE, PLAYER, APP \}/ {
    print "local MODULES = { " d ", " s ", " p ", " a " }"
    next
}
{ print }
' "$INIT" > "$OUT"

echo "built $OUT ($(wc -l < "$OUT") lines)"
```

Each `emit_module` yields a `(function() return function(A) ... end end)()` expression → evaluates to the module's `return function(A)`, so `MODULES` becomes a table of four `function(A)` values. Correct.

- [ ] **Step 4: `.gitignore`**

```
# nothing ignored yet; dist is committed for loadstring hosting
```

- [ ] **Step 5: Build and verify load**

Run: `bash build/bundle.sh`
Then via MCP `execute-file dist/AnimationPlayer.lua`, `get-console-output`.
Expected console:
```
[AnimPlayer] app started
```
Run the dist a **second** time. Expected: still only one `app started` line per run and no Lua error (cleanup guard ran). No stack traces.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: repo skeleton, bundler, cleanup guard"
```

---

### Task 2: `store.lua` — JSON library persistence

**Files:**
- Modify: `src/core/store.lua`
- Create: `tests/store.probe.lua`

**Interfaces:**
- Consumes: `A.fs.{read,write,isfile,makefolder}`, `A.json.{encode,decode}`, `A.Config.hasPersistence`, `A.notify`.
- Produces: `A.Store = { list()->array, add(name,id)->ok,err, remove(name), get(name)->rec|nil, path=string }`. Record = `{ name=string, id=string }`.

- [ ] **Step 1: Write the failing probe**

`tests/store.probe.lua`:
```lua
-- Build a fake A with in-memory fs + trivial json, load the store module, assert.
local mem = {}
local A = {
    Config = { hasPersistence = true },
    notify = function() end,
    fs = {
        read = function(p) return mem[p] end,
        write = function(p, s) mem[p] = s; return true end,
        isfile = function(p) return mem[p] ~= nil end,
        makefolder = function() end,
    },
    json = {
        encode = function(t)
            local parts = {}
            for _, r in ipairs(t) do parts[#parts+1] = r.name .. "=" .. r.id end
            return table.concat(parts, "|")
        end,
        decode = function(s)
            local t = {}
            if s == "" then return t end
            for pair in string.gmatch(s, "[^|]+") do
                local n, i = string.match(pair, "([^=]+)=(.+)")
                if n then t[#t+1] = { name = n, id = i } end
            end
            return t
        end,
    },
}
local mod = loadstring(readfile("tests/../src/core/store.lua") or readfile("src/core/store.lua"))()
mod(A)
local S = A.Store

local function check(cond, label) print((cond and "PASS " or "FAIL ") .. label) end

check(#S.list() == 0, "empty on boot")
local ok = S.add("wave", "507771019")
check(ok and #S.list() == 1, "add one")
check(S.get("wave").id == "507771019", "get returns record")
local ok2 = S.add("wave", "999")
check(not ok2 and #S.list() == 1, "duplicate name rejected")
check(not (S.add("", "1")), "empty name rejected")
check(not (S.add("x", "")), "empty id rejected")
-- persistence: new store over same mem sees the row
local A2 = setmetatable({}, { __index = A }); A2.Store = nil
mod(A2)
check(#A2.Store.list() == 1 and A2.Store.get("wave") ~= nil, "persisted across reload")
S.remove("wave")
check(#S.list() == 0, "remove")
```

- [ ] **Step 2: Run probe, verify it fails**

Run: MCP `execute-file tests/store.probe.lua`; `get-console-output`.
Expected: `FAIL` lines (or a runtime error) because `A.Store` is still the stub with no `list`.

- [ ] **Step 3: Implement `src/core/store.lua`**

```lua
return function(A)
    local PATH = "AnimationPlayer/saved.json"
    local records = {}      -- array of {name,id}

    local function persist()
        if not A.Config.hasPersistence then return end
        A.fs.makefolder("AnimationPlayer")
        A.fs.write(PATH, A.json.encode(records))
    end

    local function load()
        if A.Config.hasPersistence and A.fs.isfile(PATH) then
            local raw = A.fs.read(PATH)
            local decoded = raw and A.json.decode(raw) or nil
            if type(decoded) == "table" then
                records = {}
                for _, r in ipairs(decoded) do
                    if type(r) == "table" and r.name and r.id then
                        records[#records+1] = { name = tostring(r.name), id = tostring(r.id) }
                    end
                end
            end
        end
    end

    local Store = { path = PATH }

    function Store.list() return records end

    function Store.get(name)
        for _, r in ipairs(records) do if r.name == name then return r end end
        return nil
    end

    function Store.add(name, id)
        name = name and (tostring(name):gsub("^%s+", ""):gsub("%s+$", "")) or ""
        id = id and (tostring(id):gsub("%s+", "")) or ""
        if name == "" then return false, "name required" end
        if id == "" then return false, "id required" end
        if Store.get(name) then return false, "name already exists" end
        records[#records+1] = { name = name, id = id }
        persist()
        return true
    end

    function Store.remove(name)
        for i, r in ipairs(records) do
            if r.name == name then table.remove(records, i); persist(); return true end
        end
        return false
    end

    load()
    A.Store = Store
end
```

- [ ] **Step 4: Run probe, verify pass**

Run: MCP `execute-file tests/store.probe.lua`; `get-console-output`.
Expected: every line begins `PASS`. No `FAIL`, no errors.

- [ ] **Step 5: Commit**

```bash
git add src/core/store.lua tests/store.probe.lua
git commit -m "feat: store.lua JSON library persistence"
```

---

### Task 3: `player.lua` — resolve + playback

**Files:**
- Modify: `src/core/player.lua`
- Create: `tests/player_resolve.probe.lua`

**Interfaces:**
- Consumes: `A.getObjects(url)`, `A.getAnimator()`, `A.Config.{looped,speed}`, `A.Services.Players`, `A.notify`.
- Produces: `A.Player = { resolve(id)->realId,err, play(id)->ok,err, stop(), setSpeed(v), setLooped(b), isPlaying()->bool }`.

- [ ] **Step 1: Write the failing probe (resolve logic, mocked)**

`tests/player_resolve.probe.lua`:
```lua
local function fakeAnim(idStr)
    return { AnimationId = "rbxassetid://" .. idStr,
             IsA = function(_, c) return c == "Animation" end }
end
local scenarios = {}
local A = {
    Config = { looped = true, speed = 1 },
    notify = function() end,
    Services = { Players = { LocalPlayer = {} } },
    getAnimator = function() return nil end,
    getObjects = function(url) return scenarios.ret end,
}
local mod = loadstring(readfile("src/core/player.lua"))()
mod(A)
local P = A.Player
local function check(c, l) print((c and "PASS " or "FAIL ") .. l) end

-- catalog asset resolves to real AnimationId
scenarios.ret = { fakeAnim("123456") }
local r = P.resolve("999")
check(r == "123456", "catalog asset -> real animation id")

-- getObjects returns non-Animation -> fall back to numeric input
scenarios.ret = { { IsA = function() return false end } }
r = P.resolve("777")
check(r == "777", "non-animation falls back to numeric id")

-- getObjects fails (nil) but numeric id -> use it directly
scenarios.ret = nil
r = P.resolve("42")
check(r == "42", "nil objects, numeric id used directly")

-- garbage non-numeric with no asset -> nil,err
scenarios.ret = nil
local r2, err = P.resolve("not-a-number")
check(r2 == nil and err ~= nil, "invalid id rejected")
```

- [ ] **Step 2: Run probe, verify it fails**

Run: MCP `execute-file tests/player_resolve.probe.lua`; `get-console-output`.
Expected: `FAIL`/error — `A.Player` is the stub, no `resolve`.

- [ ] **Step 3: Implement `src/core/player.lua`**

```lua
return function(A)
    local Player = {}
    local track = nil       -- active AnimationTrack
    local currentId = nil

    function Player.resolve(id)
        id = tostring(id)
        local objs = A.getObjects("rbxassetid://" .. id)
        local asset = objs and objs[1]
        if asset then
            local ok, isAnim = pcall(function() return asset:IsA("Animation") end)
            if ok and isAnim then
                local m = string.match(asset.AnimationId or "", "(%d+)")
                if m then return m end
            end
        end
        if id:match("^%d+$") then return id end
        return nil, "invalid asset id"
    end

    function Player.stop()
        if track then pcall(function() track:Stop() end) end
        track = nil
        currentId = nil
    end

    function Player.play(id)
        local realId, err = Player.resolve(id)
        if not realId then A.notify(err or "invalid asset"); return false, err end
        local animator = A.getAnimator()
        if not animator then A.notify("no animator (respawning?)"); return false, "no animator" end
        Player.stop()
        local anim = Instance.new("Animation")
        anim.AnimationId = "rbxassetid://" .. realId
        local ok, t = pcall(function() return animator:LoadAnimation(anim) end)
        if not ok or not t then A.notify("failed to load animation"); return false, "load failed" end
        track = t
        currentId = id
        pcall(function()
            track.Priority = Enum.AnimationPriority.Action4
            track.Looped = A.Config.looped
            track:Play()
            track:AdjustSpeed(A.Config.speed)
        end)
        return true
    end

    function Player.isPlaying()
        return track ~= nil and (pcall(function() return track.IsPlaying end) and track.IsPlaying) == true
    end

    function Player.setSpeed(v)
        A.Config.speed = v
        if track then pcall(function() track:AdjustSpeed(v) end) end
    end

    function Player.setLooped(b)
        A.Config.looped = b
        if track then pcall(function() track.Looped = b end) end
    end

    -- re-fetch animator + resume on respawn if looping was active
    if A.Services and A.Services.Players and A.Services.Players.LocalPlayer then
        local plr = A.Services.Players.LocalPlayer
        if plr.CharacterAdded then
            A.track(plr.CharacterAdded:Connect(function()
                if currentId and A.Config.looped then
                    task.wait(1)
                    Player.play(currentId)
                end
            end))
        end
    end

    A.Player = Player
end
```

- [ ] **Step 4: Run resolve probe, verify pass**

Run: MCP `execute-file tests/player_resolve.probe.lua`; `get-console-output`.
Expected: all `PASS`.

- [ ] **Step 5: Live playback smoke (requires in-game character)**

Ad-hoc via MCP `execute` (real character present):
```lua
loadstring(readfile("dist/AnimationPlayer.lua"))() -- ensure built first, or execute src wiring
-- direct engine probe:
local plr=game.Players.LocalPlayer
local hum=plr.Character:FindFirstChildOfClass("Humanoid")
local animator=hum:FindFirstChildOfClass("Animator")
local anim=Instance.new("Animation"); anim.AnimationId="rbxassetid://507771019"
local tr=animator:LoadAnimation(anim); tr.Priority=Enum.AnimationPriority.Action4; tr:Play()
print("playing:", tr.IsPlaying)
```
Expected console: `playing: true`; character visibly emotes. (Confirms LoadAnimation path the module uses.)

- [ ] **Step 6: Commit**

```bash
git add src/core/player.lua tests/player_resolve.probe.lua
git commit -m "feat: player.lua resolve + playback engine"
```

---

### Task 4: `drawing.lua` core — window, render loop, teardown, Button/Toggle/Slider/Notify

**Files:**
- Modify: `src/ui/drawing.lua`
- Create: `tests/drawing_core.probe.lua`

**Interfaces:**
- Consumes: `A.Services.{UserInputService,RunService}`, `A.trackDraw`, `A.track`.
- Produces: `A.UI` with:
  - `A.UI.window(title)->win` where `win = { pos, size, add(childHeight)->{x,y,w}, setVisible(b), toggle(), _rows }`
  - `A.UI.button(win, text, cb)`, `A.UI.toggle(win, text, initial, cb)`, `A.UI.slider(win, text, min, max, initial, cb)`
  - `A.notify(msg)` — transient bottom-of-window text
  - `A.UI.rect(props)`, `A.UI.text(props)` low-level tracked helpers
  - `A.UI._hitTest(x,y)->widget|nil` (used by later input tasks)
  - internal ordered `A.UI._widgets` list for redraw + click dispatch

Design notes for the implementer:
- Every `Drawing.new` object passes through `A.trackDraw` so cleanup removes it.
- One `RunService.RenderStepped` connection redraws positions; one `UserInputService.InputBegan` dispatches clicks by hit-testing `A.UI._widgets`.
- Window body is a fixed-width column (e.g. 260px). `win.add(h)` returns the next row rect and advances a cursor, so widgets stack vertically.
- Widgets store their own `draw()` (updates Drawing props from state) and optional `onClick(x,y)`.

- [ ] **Step 1: Write the failing probe**

`tests/drawing_core.probe.lua`:
```lua
local drawn = {}
-- stub Drawing so we can run headless-ish (executor has real Drawing, but this
-- probe verifies widget bookkeeping, not pixels)
local realDrawing = Drawing
getgenv().Drawing = {
    new = function(kind)
        local o = { __kind = kind, Visible = false, Remove = function(s) s.__removed = true end }
        drawn[#drawn+1] = o
        return o
    end,
}
local A = {
    Services = {
        UserInputService = { InputBegan = { Connect = function() return { Disconnect=function() end } end } },
        RunService = { RenderStepped = { Connect = function() return { Disconnect=function() end } end } },
    },
    _drawings = {}, _connections = {},
    trackDraw = function(self) return self end,
    track = function(self) return self end,
}
A.trackDraw = function(d) A._drawings[#A._drawings+1] = d; return d end
A.track = function(c) A._connections[#A._connections+1] = c; return c end
local mod = loadstring(readfile("src/ui/drawing.lua"))()
mod(A)
local function check(c,l) print((c and "PASS " or "FAIL ")..l) end

check(type(A.UI.window) == "function", "window constructor exists")
local w = A.UI.window("Test")
check(type(w.add) == "function", "window has add()")
local clicked = false
A.UI.button(w, "Go", function() clicked = true end)
local toggled = nil
A.UI.toggle(w, "Loop", true, function(v) toggled = v end)
local slid = nil
A.UI.slider(w, "Speed", 0, 3, 1, function(v) slid = v end)
check(#A._drawings > 0, "widgets created Drawing objects (tracked)")
check(type(A.notify) == "function", "notify installed")
A.notify("hi")  -- must not error
getgenv().Drawing = realDrawing
print("PASS core constructed")
```

- [ ] **Step 2: Run probe, verify it fails**

Run: MCP `execute-file tests/drawing_core.probe.lua`; `get-console-output`.
Expected: `FAIL`/error — stub `A.UI` has no `window`.

- [ ] **Step 3: Implement `src/ui/drawing.lua` core**

Full retained-mode core. Key elements: `_widgets` list, `redraw` on RenderStepped, click dispatch on InputBegan, `window`/`button`/`toggle`/`slider`, and `A.notify`.
```lua
return function(A)
    local UIS = A.Services.UserInputService
    local RS = A.Services.RunService
    local UI = { _widgets = {}, _windows = {} }

    local COLW = 260
    local ROWH = 22
    local PAD = 6

    local function newRect(props)
        local r = A.trackDraw(Drawing.new("Square"))
        r.Filled = true
        r.Thickness = props.Thickness or 1
        r.Color = props.Color or Color3.fromRGB(30,30,35)
        r.Transparency = props.Transparency or 1
        r.Visible = props.Visible ~= false
        return r
    end
    local function newText(props)
        local t = A.trackDraw(Drawing.new("Text"))
        t.Size = props.Size or 14
        t.Center = props.Center or false
        t.Outline = true
        t.Color = props.Color or Color3.fromRGB(235,235,235)
        t.Text = props.Text or ""
        t.Visible = props.Visible ~= false
        return t
    end
    UI.rect = newRect
    UI.text = newText

    -- ---- window ----
    function UI.window(title)
        local win = {
            pos = Vector2.new(120, 120),
            size = Vector2.new(COLW, 40),
            visible = true,
            _cursorY = 0,
            _widgets = {},
        }
        win.bar = newRect{ Color = Color3.fromRGB(20,20,25) }
        win.body = newRect{ Color = Color3.fromRGB(30,30,35), Transparency = 0.96 }
        win.titleText = newText{ Text = title, Size = 15 }

        function win.add(h)
            local y = 24 + PAD + win._cursorY
            win._cursorY = win._cursorY + h + PAD
            win.size = Vector2.new(COLW, 24 + PAD + win._cursorY)
            return { x = PAD, y = y, w = COLW - PAD*2, h = h }
        end
        function win.setVisible(b)
            win.visible = b
        end
        function win.toggle() win.setVisible(not win.visible) end

        -- drag state
        win._dragging = false
        win._dragOff = Vector2.new(0,0)

        function win.redraw()
            local p = win.pos
            win.bar.Position = p
            win.bar.Size = Vector2.new(win.size.X, 24)
            win.bar.Visible = win.visible
            win.body.Position = p + Vector2.new(0, 24)
            win.body.Size = Vector2.new(win.size.X, math.max(1, win.size.Y - 24))
            win.body.Visible = win.visible
            win.titleText.Position = p + Vector2.new(PAD, 4)
            win.titleText.Visible = win.visible
            for _, wd in ipairs(win._widgets) do wd.draw(p, win.visible) end
        end

        UI._windows[#UI._windows+1] = win
        return win
    end

    -- ---- button ----
    function UI.button(win, label, cb)
        local box = win.add(ROWH)
        local bg = newRect{ Color = Color3.fromRGB(55,55,65) }
        local tx = newText{ Text = label, Center = true }
        local wd = {}
        function wd.draw(origin, vis)
            bg.Position = origin + Vector2.new(box.x, box.y)
            bg.Size = Vector2.new(box.w, box.h)
            bg.Visible = vis
            tx.Position = origin + Vector2.new(box.x + box.w/2, box.y + 3)
            tx.Visible = vis
        end
        function wd.hit(mx, my, origin, vis)
            if not vis then return false end
            local px, py = origin.X + box.x, origin.Y + box.y
            return mx >= px and mx <= px+box.w and my >= py and my <= py+box.h
        end
        function wd.click() cb() end
        win._widgets[#win._widgets+1] = wd
        UI._widgets[#UI._widgets+1] = { wd = wd, win = win }
        return wd
    end

    -- ---- toggle ----
    function UI.toggle(win, label, initial, cb)
        local box = win.add(ROWH)
        local state = initial and true or false
        local bg = newRect{ Color = Color3.fromRGB(45,45,55) }
        local knob = newRect{ Color = Color3.fromRGB(90,200,120) }
        local tx = newText{ Text = label }
        local wd = {}
        function wd.draw(origin, vis)
            bg.Position = origin + Vector2.new(box.x, box.y); bg.Size = Vector2.new(box.w, box.h); bg.Visible = vis
            knob.Size = Vector2.new(16,16)
            knob.Position = origin + Vector2.new(box.x + box.w - 22, box.y + 3)
            knob.Color = state and Color3.fromRGB(90,200,120) or Color3.fromRGB(80,80,90)
            knob.Visible = vis
            tx.Position = origin + Vector2.new(box.x + 6, box.y + 3); tx.Visible = vis
        end
        function wd.hit(mx,my,origin,vis)
            if not vis then return false end
            local px,py = origin.X+box.x, origin.Y+box.y
            return mx>=px and mx<=px+box.w and my>=py and my<=py+box.h
        end
        function wd.click() state = not state; cb(state) end
        function wd.set(v) state = v and true or false end
        function wd.get() return state end
        win._widgets[#win._widgets+1] = wd
        UI._widgets[#UI._widgets+1] = { wd = wd, win = win }
        return wd
    end

    -- ---- slider ----
    function UI.slider(win, label, min, max, initial, cb)
        local box = win.add(ROWH)
        local value = initial
        local bg = newRect{ Color = Color3.fromRGB(45,45,55) }
        local fill = newRect{ Color = Color3.fromRGB(90,140,220) }
        local tx = newText{ Text = label..": "..tostring(value) }
        local wd = {}
        local function frac() return (value-min)/(max-min) end
        function wd.draw(origin, vis)
            bg.Position = origin + Vector2.new(box.x, box.y); bg.Size = Vector2.new(box.w, box.h); bg.Visible = vis
            fill.Position = origin + Vector2.new(box.x, box.y); fill.Size = Vector2.new(box.w*frac(), box.h); fill.Visible = vis
            tx.Text = string.format("%s: %.2f", label, value)
            tx.Position = origin + Vector2.new(box.x + 6, box.y + 3); tx.Visible = vis
        end
        function wd.hit(mx,my,origin,vis)
            if not vis then return false end
            local px,py = origin.X+box.x, origin.Y+box.y
            return mx>=px and mx<=px+box.w and my>=py and my<=py+box.h
        end
        function wd.clickAt(mx, origin)
            local px = origin.X+box.x
            local f = math.clamp((mx-px)/box.w, 0, 1)
            value = min + f*(max-min)
            cb(value)
        end
        wd.isSlider = true
        win._widgets[#win._widgets+1] = wd
        UI._widgets[#UI._widgets+1] = { wd = wd, win = win }
        return wd
    end

    -- ---- notify ----
    local notifyText = newText{ Text = "", Size = 13, Color = Color3.fromRGB(255,210,120), Visible = false }
    local notifyUntil = 0
    A.notify = function(msg)
        notifyText.Text = "[AnimPlayer] " .. tostring(msg)
        notifyText.Visible = true
        notifyUntil = tick() + 3
        print("[AnimPlayer] " .. tostring(msg))
    end

    -- ---- global render + input ----
    UI._activeInput = nil  -- set by TextInput task
    local function redraw()
        for _, win in ipairs(UI._windows) do win.redraw() end
        if notifyText.Visible then
            local base = UI._windows[1]
            if base then
                notifyText.Position = base.pos + Vector2.new(6, base.size.Y + 4)
            end
            if tick() > notifyUntil then notifyText.Visible = false end
        end
    end
    A.track(RS.RenderStepped:Connect(redraw))

    -- click dispatch (drag on titlebar, widget hit-test)
    A.track(UIS.InputBegan:Connect(function(input, gpe)
        if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
        local m = UIS:GetMouseLocation()
        local mx, my = m.X, m.Y
        for _, win in ipairs(UI._windows) do
            if win.visible then
                -- titlebar drag
                local p = win.pos
                if mx>=p.X and mx<=p.X+win.size.X and my>=p.Y and my<=p.Y+24 then
                    win._dragging = true; win._dragOff = Vector2.new(mx-p.X, my-p.Y)
                end
            end
        end
        for _, entry in ipairs(UI._widgets) do
            local wd, win = entry.wd, entry.win
            if wd.hit and wd.hit(mx, my, win.pos, win.visible) then
                if wd.isSlider then wd.clickAt(mx, win.pos)
                elseif wd.click then wd.click() end
            end
        end
        if UI._dispatchClick then UI._dispatchClick(mx, my) end -- text inputs / list (later tasks)
    end))
    A.track(UIS.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            for _, win in ipairs(UI._windows) do win._dragging = false end
        end
    end))
    A.track(UIS.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement then
            local m = UIS:GetMouseLocation()
            for _, win in ipairs(UI._windows) do
                if win._dragging then win.pos = Vector2.new(m.X - win._dragOff.X, m.Y - win._dragOff.Y) end
            end
        end
    end))

    A.UI = UI
end
```

- [ ] **Step 4: Run probe, verify pass**

Run: MCP `execute-file tests/drawing_core.probe.lua`; `get-console-output`.
Expected: all `PASS`, ending `PASS core constructed`.

- [ ] **Step 5: Live render smoke**

Via MCP `execute` on a real client:
```lua
local A = { Services = { UserInputService = game:GetService("UserInputService"), RunService = game:GetService("RunService") }, _drawings={}, _connections={} }
A.trackDraw=function(d) A._drawings[#A._drawings+1]=d return d end
A.track=function(c) A._connections[#A._connections+1]=c return c end
loadstring(readfile("src/ui/drawing.lua"))()(A)
local w=A.UI.window("Anim Player")
A.UI.button(w,"Play",function() print("btn click") end)
A.UI.toggle(w,"Loop",true,function(v) print("toggle",v) end)
A.UI.slider(w,"Speed",0.1,3,1,function(v) print("speed",v) end)
```
Then `screenshot-window`: expect a draggable window titled "Anim Player" with a button, a toggle knob, and a filled slider. Click widgets → console prints. Drag titlebar → window moves.

- [ ] **Step 6: Commit**

```bash
git add src/ui/drawing.lua tests/drawing_core.probe.lua
git commit -m "feat: drawing core (window, button, toggle, slider, notify)"
```

---

### Task 5: `drawing.lua` — TextInput + Keybind picker

**Files:**
- Modify: `src/ui/drawing.lua`
- Create: `tests/drawing_input.probe.lua`

**Interfaces:**
- Consumes: core UI from Task 4 (`UI._windows`, `UI._dispatchClick` hook, `win.add`, `A.track`, `UIS`).
- Produces:
  - `A.UI.textInput(win, placeholder)->inp` where `inp = { get()->string, set(s), clear() }`
  - `A.UI.keybind(win, label, initialKeyCode, cb)->kb` where `kb = { get()->KeyCode, set(kc) }`; `cb(newKeyCode)` fires on rebind.
  - Wires `UI._dispatchClick` for focus, and a global `InputBegan` for typing + keybind capture.

Design notes:
- Only one text input focused at a time (`UI._activeInput`). Focus set when a click lands inside its box (registered through `UI._dispatchClick`).
- Typing: on `InputBegan`, if an input is focused and the key is printable, append `UserInputService:GetStringForKeyCode(keycode)` (respecting shift for letters via `input:IsModifierKeyDown`); Backspace deletes last char; Enter/Escape unfocus.
- Keybind picker: clicking it sets `UI._captureKeybind = kb`; the next non-mouse `InputBegan` becomes the bind and fires `cb`.
- Blinking caret: append `"|"` to displayed text when focused and `tick()%1 < 0.5`.

- [ ] **Step 1: Write the failing probe**

`tests/drawing_input.probe.lua` (logic-level: simulate the input handler directly):
```lua
local A = {
    Services = { UserInputService = {
        InputBegan = { Connect = function() return {Disconnect=function() end} end },
        GetStringForKeyCode = function(_, kc) return kc._s end,
        GetMouseLocation = function() return {X=0,Y=0} end,
    }, RunService = { RenderStepped = { Connect=function() return {Disconnect=function() end} end } } },
    _drawings={}, _connections={},
}
A.trackDraw=function(d) return d end
A.track=function(c) return c end
getgenv().Drawing = { new=function() return { Remove=function() end } end }
loadstring(readfile("src/ui/drawing.lua"))()(A)  -- core
-- core sets A.UI; input module is same file (Task 5 appends to same file) so already present
local function check(c,l) print((c and "PASS " or "FAIL ")..l) end
local w = A.UI.window("t")
local inp = A.UI.textInput(w, "name")
check(inp ~= nil and inp.get() == "", "textInput empty initial")
inp.set("wave"); check(inp.get() == "wave", "set/get")
inp.clear(); check(inp.get() == "", "clear")
local bound = nil
local kb = A.UI.keybind(w, "Play", Enum.KeyCode.E, function(k) bound = k end)
check(kb.get() == Enum.KeyCode.E, "keybind initial")
kb.set(Enum.KeyCode.F); check(kb.get() == Enum.KeyCode.F, "keybind set")
getgenv().Drawing = nil
print("PASS input constructed")
```

- [ ] **Step 2: Run probe, verify it fails**

Run: MCP `execute-file tests/drawing_input.probe.lua`.
Expected: `FAIL`/error — `A.UI.textInput`/`keybind` not defined yet.

- [ ] **Step 3: Implement — append TextInput + Keybind to `src/ui/drawing.lua`**

Insert **before** `A.UI = UI` at the end of the file:
```lua
    -- ================= TextInput =================
    UI._inputs = {}
    UI._activeInput = nil
    function UI.textInput(win, placeholder)
        local box = win.add(ROWH)
        local bg = newRect{ Color = Color3.fromRGB(25,25,32) }
        local tx = newText{ Text = "", Size = 14 }
        local value = ""
        local inp = { _box = box, _placeholder = placeholder }
        function inp.get() return value end
        function inp.set(s) value = tostring(s or "") end
        function inp.clear() value = "" end
        local wd = {}
        function wd.draw(origin, vis)
            bg.Position = origin + Vector2.new(box.x, box.y); bg.Size = Vector2.new(box.w, box.h); bg.Visible = vis
            local shown
            if value == "" and UI._activeInput ~= inp then
                shown = placeholder; tx.Color = Color3.fromRGB(120,120,130)
            else
                tx.Color = Color3.fromRGB(235,235,235)
                shown = value
                if UI._activeInput == inp and (tick() % 1) < 0.5 then shown = shown .. "|" end
            end
            tx.Text = shown
            tx.Position = origin + Vector2.new(box.x + 5, box.y + 3); tx.Visible = vis
        end
        function wd.hitbox(mx,my,origin,vis)
            if not vis then return false end
            local px,py = origin.X+box.x, origin.Y+box.y
            return mx>=px and mx<=px+box.w and my>=py and my<=py+box.h
        end
        inp._wd = wd
        win._widgets[#win._widgets+1] = wd
        UI._inputs[#UI._inputs+1] = { inp = inp, win = win }
        return inp
    end

    -- ================= Keybind =================
    UI._captureKeybind = nil
    function UI.keybind(win, label, initial, cb)
        local box = win.add(ROWH)
        local bg = newRect{ Color = Color3.fromRGB(45,45,55) }
        local tx = newText{ Text = "" }
        local key = initial
        local kb = {}
        function kb.get() return key end
        function kb.set(k) key = k; if cb then cb(k) end end
        local wd = {}
        local function keyName() return UI._captureKeybind == kb and "..." or (key and key.Name or "None") end
        function wd.draw(origin, vis)
            bg.Position = origin + Vector2.new(box.x, box.y); bg.Size = Vector2.new(box.w, box.h); bg.Visible = vis
            tx.Text = label .. ": [" .. keyName() .. "]"
            tx.Position = origin + Vector2.new(box.x + 6, box.y + 3); tx.Visible = vis
        end
        function wd.hit(mx,my,origin,vis)
            if not vis then return false end
            local px,py = origin.X+box.x, origin.Y+box.y
            return mx>=px and mx<=px+box.w and my>=py and my<=py+box.h
        end
        function wd.click() UI._captureKeybind = kb end
        win._widgets[#win._widgets+1] = wd
        UI._widgets[#UI._widgets+1] = { wd = wd, win = win }
        return kb
    end

    -- focus dispatch (called from core InputBegan click handler)
    UI._dispatchClick = function(mx, my)
        local hitOne = nil
        for _, e in ipairs(UI._inputs) do
            if e.inp._wd.hitbox(mx, my, e.win.pos, e.win.visible) then hitOne = e.inp end
        end
        UI._activeInput = hitOne  -- click outside any input unfocuses
        if UI._onDispatchClick then UI._onDispatchClick(mx, my) end -- list task hook
    end

    -- typing + keybind capture
    local PRINTABLE = {} -- keycodes we treat as text
    A.track(UIS.InputBegan:Connect(function(input, gpe)
        local kc = input.KeyCode
        -- keybind capture takes priority
        if UI._captureKeybind and input.UserInputType == Enum.UserInputType.Keyboard
           and kc ~= Enum.KeyCode.Unknown then
            local target = UI._captureKeybind; UI._captureKeybind = nil
            target.set(kc)
            return
        end
        if not UI._activeInput then return end
        if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
        local inp = UI._activeInput
        if kc == Enum.KeyCode.Backspace then
            inp.set(inp.get():sub(1, -2)); return
        elseif kc == Enum.KeyCode.Return or kc == Enum.KeyCode.Escape then
            UI._activeInput = nil; return
        end
        local ok, s = pcall(function() return UIS:GetStringForKeyCode(kc) end)
        if ok and s and s ~= "" then
            local shift = UIS:IsKeyDown(Enum.KeyCode.LeftShift) or UIS:IsKeyDown(Enum.KeyCode.RightShift)
            if shift then s = s:upper() end
            inp.set(inp.get() .. s)
        end
    end))
```

Note: the `PRINTABLE` local is unused scaffolding — omit it; `GetStringForKeyCode` handles printability (returns `""` for non-text keys). Implementer should not add it.

- [ ] **Step 4: Run probe, verify pass**

Run: MCP `execute-file tests/drawing_input.probe.lua`.
Expected: all `PASS`, ending `PASS input constructed`.

- [ ] **Step 5: Live typing smoke**

On a real client, build a window with a text input + keybind, `screenshot-window`, click the input, and via MCP `user_keyboard_input` (or type in-game) confirm characters appear with a blinking caret, Backspace deletes, and the keybind widget captures the next key. Expected: input text reflects typed chars; keybind label updates to the pressed key.

- [ ] **Step 6: Commit**

```bash
git add src/ui/drawing.lua tests/drawing_input.probe.lua
git commit -m "feat: drawing text input + keybind picker"
```

---

### Task 6: `drawing.lua` — always-open selectable List with per-row delete

**Files:**
- Modify: `src/ui/drawing.lua`
- Create: `tests/drawing_list.probe.lua`

**Interfaces:**
- Consumes: core UI (Task 4), `UI._onDispatchClick` hook (Task 5).
- Produces: `A.UI.list(win, opts)->lst` where
  `lst = { setItems(array), refresh(), getSelected()->item|nil, clearSelection() }`,
  `opts = { height=number, rowHeight=number, onSelect=function(item), onDelete=function(item) }`.
  Item = `{ name=string, id=string }` (renders `name`, `X` delete glyph at right).

Design notes:
- Always visible (no collapse). Fixed viewport height `opts.height`; if items exceed it, scroll via mouse wheel (`UIS.InputChanged` `MouseWheel`), tracked offset.
- Rows are pooled Drawing objects sized to the viewport; `refresh()` maps the visible window of items onto the pooled rows.
- Selection: clicking a row (not its `X`) selects it (highlight bg) and calls `onSelect`. Clicking the row's `X` calls `onDelete`.
- Registered through `UI._onDispatchClick(mx,my)` so it shares the core click handler.

- [ ] **Step 1: Write the failing probe**

`tests/drawing_list.probe.lua`:
```lua
local A = {
    Services = { UserInputService = {
        InputBegan={Connect=function() return {Disconnect=function() end} end},
        InputChanged={Connect=function() return {Disconnect=function() end} end},
        InputEnded={Connect=function() return {Disconnect=function() end} end},
        GetMouseLocation=function() return {X=0,Y=0} end,
        IsKeyDown=function() return false end,
    }, RunService={RenderStepped={Connect=function() return {Disconnect=function() end} end}} },
    _drawings={}, _connections={},
}
A.trackDraw=function(d) return d end; A.track=function(c) return c end
getgenv().Drawing={ new=function() return { Remove=function() end } end }
loadstring(readfile("src/ui/drawing.lua"))()(A)
local function check(c,l) print((c and "PASS " or "FAIL ")..l) end
local w=A.UI.window("t")
local selected, deleted = nil, nil
local lst=A.UI.list(w, { height=120, rowHeight=20,
    onSelect=function(it) selected=it end, onDelete=function(it) deleted=it end })
check(lst ~= nil, "list constructed")
lst.setItems({ {name="a",id="1"}, {name="b",id="2"} })
check(lst.getSelected()==nil, "nothing selected initially")
-- simulate selecting row 0 by calling the internal row click
lst._debugSelect(1)
check(selected and selected.name=="a", "onSelect fired")
check(lst.getSelected().name=="a", "getSelected reflects")
lst._debugDelete(2)
check(deleted and deleted.name=="b", "onDelete fired")
lst.clearSelection()
check(lst.getSelected()==nil, "clearSelection")
getgenv().Drawing=nil
print("PASS list constructed")
```

- [ ] **Step 2: Run probe, verify it fails**

Run: MCP `execute-file tests/drawing_list.probe.lua`.
Expected: `FAIL`/error — `A.UI.list` undefined.

- [ ] **Step 3: Implement — append `UI.list` to `src/ui/drawing.lua`**

Insert before `A.UI = UI`:
```lua
    -- ================= List (always open) =================
    function UI.list(win, opts)
        local rowH = opts.rowHeight or 20
        local viewH = opts.height or 120
        local box = win.add(viewH)
        local items = {}
        local selectedIdx = nil
        local scroll = 0
        local rowsVisible = math.floor(viewH / rowH)

        local frame = newRect{ Color = Color3.fromRGB(22,22,28) }
        local pool = {}
        for i = 1, rowsVisible do
            pool[i] = {
                bg = newRect{ Color = Color3.fromRGB(35,35,42) },
                tx = newText{ Text = "", Size = 14 },
                del = newText{ Text = "X", Size = 14, Color = Color3.fromRGB(220,90,90) },
            }
        end

        local lst = {}
        function lst.setItems(arr) items = arr or {}; if selectedIdx and selectedIdx > #items then selectedIdx = nil end end
        function lst.refresh() end -- draw() pulls live; no-op kept for API
        function lst.getSelected() return selectedIdx and items[selectedIdx] or nil end
        function lst.clearSelection() selectedIdx = nil end

        local wd = {}
        function wd.draw(origin, vis)
            frame.Position = origin + Vector2.new(box.x, box.y); frame.Size = Vector2.new(box.w, box.h); frame.Visible = vis
            for i = 1, rowsVisible do
                local itemIdx = i + scroll
                local row = pool[i]
                local it = items[itemIdx]
                local ry = box.y + (i-1)*rowH
                if it and vis then
                    row.bg.Position = origin + Vector2.new(box.x, ry)
                    row.bg.Size = Vector2.new(box.w, rowH-1)
                    row.bg.Color = (itemIdx == selectedIdx) and Color3.fromRGB(70,90,140) or Color3.fromRGB(35,35,42)
                    row.bg.Visible = true
                    row.tx.Text = it.name
                    row.tx.Position = origin + Vector2.new(box.x + 6, ry + 2); row.tx.Visible = true
                    row.del.Position = origin + Vector2.new(box.x + box.w - 16, ry + 2); row.del.Visible = true
                else
                    row.bg.Visible = false; row.tx.Visible = false; row.del.Visible = false
                end
            end
        end

        local function rowAt(mx, my, origin)
            if mx < origin.X+box.x or mx > origin.X+box.x+box.w then return nil end
            if my < origin.Y+box.y or my > origin.Y+box.y+box.h then return nil end
            local rel = my - (origin.Y+box.y)
            local i = math.floor(rel / rowH) + 1
            local itemIdx = i + scroll
            if not items[itemIdx] then return nil end
            local isDelete = mx >= origin.X+box.x+box.w-18
            return itemIdx, isDelete
        end

        -- click handling via shared dispatch
        local prevHook = UI._onDispatchClick
        UI._onDispatchClick = function(mx, my)
            if prevHook then prevHook(mx, my) end
            if not win.visible then return end
            local idx, isDel = rowAt(mx, my, win.pos)
            if not idx then return end
            if isDel then
                local it = items[idx]
                if opts.onDelete then opts.onDelete(it) end
            else
                selectedIdx = idx
                if opts.onSelect then opts.onSelect(items[idx]) end
            end
        end

        -- scroll
        A.track(A.Services.UserInputService.InputChanged:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseWheel and win.visible then
                local m = A.Services.UserInputService:GetMouseLocation()
                if m.X >= win.pos.X+box.x and m.X <= win.pos.X+box.x+box.w
                   and m.Y >= win.pos.Y+box.y and m.Y <= win.pos.Y+box.y+box.h then
                    scroll = math.clamp(scroll - input.Position.Z, 0, math.max(0, #items - rowsVisible))
                end
            end
        end))

        -- debug hooks for headless probe
        lst._debugSelect = function(i) selectedIdx = i; if opts.onSelect then opts.onSelect(items[i]) end end
        lst._debugDelete = function(i) if opts.onDelete then opts.onDelete(items[i]) end end

        win._widgets[#win._widgets+1] = wd
        return lst
    end
```

- [ ] **Step 4: Run probe, verify pass**

Run: MCP `execute-file tests/drawing_list.probe.lua`.
Expected: all `PASS`, ending `PASS list constructed`.

- [ ] **Step 5: Live list smoke**

On a real client build a window + list, `setItems({{name="wave",id="1"},{name="dance",id="2"}})`, `screenshot-window`: expect two rows with red `X` at right. Click row → its bg highlights (blue) and console prints selection. Click `X` → delete callback prints. Mouse-wheel scrolls when >6 rows.

- [ ] **Step 6: Commit**

```bash
git add src/ui/drawing.lua tests/drawing_list.probe.lua
git commit -m "feat: drawing always-open selectable list with delete"
```

---

### Task 7: `app.lua` — assemble the suite

**Files:**
- Modify: `src/app.lua`
- Create: `tests/app.probe.lua`

**Interfaces:**
- Consumes: `A.UI.{window,list,textInput,button,toggle,slider,keybind}`, `A.Store.{list,add,remove}`, `A.Player.{play,stop,setSpeed,setLooped}`, `A.Config`, `A.State`, `A.notify`, `A.Services.UserInputService`, `A.track`.
- Produces: `A.App = { start(), _refreshList(), _onPlayToggle(state), _triggerPlay() }` (the underscored members exist so the probe can drive UI actions without synthetic input).

Layout (top → bottom in the window):
1. Title "Animation Player"
2. List (always open) of saved animations
3. Name text input
4. Animation ID text input
5. "Save" button
6. "Play" toggle (loop while ON)
7. "Speed" slider (0.1–3.0)
8. "Stop" button
9. "Play key" keybind (default E)
10. "Menu key" keybind (default RightShift)

- [ ] **Step 1: Write the failing probe**

`tests/app.probe.lua`:
```lua
-- Headless: stub UI + real store (mem fs) + fake player capturing calls.
local mem = {}
local A = {
    Services = { UserInputService = { InputBegan={Connect=function() return {Disconnect=function() end} end} } },
    Config = { menuKey = Enum.KeyCode.RightShift, playKey = Enum.KeyCode.E, looped=true, speed=1, hasPersistence=false },
    State = { selected = nil },
    notify = function() end,
    track = function(c) return c end,
    fs = { read=function(p) return mem[p] end, write=function(p,s) mem[p]=s return true end, isfile=function(p) return mem[p]~=nil end, makefolder=function() end },
    json = { encode=function(t) local o={} for _,r in ipairs(t) do o[#o+1]=r.name.."="..r.id end return table.concat(o,"|") end,
             decode=function(s) local t={} for p in s:gmatch("[^|]+") do local n,i=p:match("([^=]+)=(.+)") if n then t[#t+1]={name=n,id=i} end end return t end },
}
-- fake UI: constructors return objects whose callbacks the probe can call.
local ui = {}
A.UI = {
    window=function() return { _t=true } end,
    list=function(_, opts) ui.listOpts=opts; return { setItems=function(a) ui.items=a end, getSelected=function() return ui.sel end, clearSelection=function() ui.sel=nil end } end,
    textInput=function() local v="" return { get=function() return v end, set=function(s) v=s end, clear=function() v="" end, _setForTest=function(s) v=s end } end,
    button=function(_, label, cb) ui[label.."_cb"]=cb; return {} end,
    toggle=function(_, label, init, cb) ui[label.."_cb"]=cb; return { set=function() end } end,
    slider=function(_, label, mn, mx, iv, cb) ui[label.."_cb"]=cb; return {} end,
    keybind=function(_, label, init, cb) ui[label.."_kb"]=cb; return { get=function() return init end, set=function(k) if cb then cb(k) end end } end,
}
local player = { calls = {} }
A.Player = {
    play=function(id) player.calls[#player.calls+1]={"play",id}; return true end,
    stop=function() player.calls[#player.calls+1]={"stop"} end,
    setSpeed=function(v) player.calls[#player.calls+1]={"speed",v} end,
    setLooped=function(b) player.calls[#player.calls+1]={"looped",b} end,
}
loadstring(readfile("src/core/store.lua"))()(A)
loadstring(readfile("src/app.lua"))()(A)
A.App.start()
local function check(c,l) print((c and "PASS " or "FAIL ")..l) end

-- name+id inputs are captured in app via closures; drive Save through _addFromInputs
check(type(A.App._addFromInputs)=="function", "app exposes _addFromInputs")
A.App._addFromInputs("wave","507771019")
check(#A.Store.list()==1, "Save added to store")
check(ui.items and #ui.items==1, "list refreshed after save")

-- select then trigger play
ui.sel = { name="wave", id="507771019" }
A.App._triggerPlay()
check(player.calls[#player.calls][1]=="play" and player.calls[#player.calls][2]=="507771019", "trigger plays selected id")

-- play toggle off -> stop
A.App._onPlayToggle(false)
check(player.calls[#player.calls][1]=="stop", "toggle off stops")

-- speed slider -> setSpeed
ui["Speed_cb"](2.0)
check(player.calls[#player.calls][1]=="speed" and player.calls[#player.calls][2]==2.0, "speed slider wired")

-- delete via list opts
ui.listOpts.onDelete({name="wave",id="507771019"})
check(#A.Store.list()==0, "delete removes from store")
print("PASS app wired")
```

- [ ] **Step 2: Run probe, verify it fails**

Run: MCP `execute-file tests/app.probe.lua`.
Expected: `FAIL`/error — `A.App.start` is the stub; no `_addFromInputs`.

- [ ] **Step 3: Implement `src/app.lua`**

```lua
return function(A)
    local App = {}
    local win, list, nameInput, idInput, playToggleWd
    local playing = false

    function App._refreshList()
        if list then list.setItems(A.Store.list()) end
    end

    function App._addFromInputs(name, id)
        local ok, err = A.Store.add(name, id)
        if ok then
            if nameInput then nameInput.clear() end
            if idInput then idInput.clear() end
            App._refreshList()
            A.notify("saved '" .. name .. "'")
        else
            A.notify(err or "could not save")
        end
        return ok
    end

    function App._triggerPlay()
        local sel = list and list.getSelected() or A.State.selected
        if not sel then A.notify("select an animation"); return end
        A.State.selected = sel
        A.Player.play(sel.id)
    end

    function App._onPlayToggle(state)
        playing = state
        if state then App._triggerPlay() else A.Player.stop() end
    end

    function App.start()
        win = A.UI.window("Animation Player")
        A.App._win = win

        list = A.UI.list(win, {
            height = 130, rowHeight = 20,
            onSelect = function(it) A.State.selected = it end,
            onDelete = function(it)
                A.Store.remove(it.name)
                if A.State.selected and A.State.selected.name == it.name then A.State.selected = nil end
                App._refreshList()
                A.notify("deleted '" .. it.name .. "'")
            end,
        })

        nameInput = A.UI.textInput(win, "name")
        idInput = A.UI.textInput(win, "animation / asset id")
        A.UI.button(win, "Save", function()
            App._addFromInputs(nameInput.get(), idInput.get())
        end)

        playToggleWd = A.UI.toggle(win, "Play (loop)", false, function(state)
            App._onPlayToggle(state)
        end)

        A.UI.slider(win, "Speed", 0.1, 3.0, A.Config.speed, function(v)
            A.Player.setSpeed(v)
        end)

        A.UI.toggle(win, "Looped", A.Config.looped, function(v)
            A.Player.setLooped(v)
        end)

        A.UI.button(win, "Stop", function()
            playing = false
            if playToggleWd and playToggleWd.set then playToggleWd.set(false) end
            A.Player.stop()
        end)

        A.UI.keybind(win, "Play key", A.Config.playKey, function(k) A.Config.playKey = k end)
        A.UI.keybind(win, "Menu key", A.Config.menuKey, function(k) A.Config.menuKey = k end)

        if not A.Config.hasPersistence then A.notify("no filesystem: library won't persist") end
        App._refreshList()

        -- global keys: play key triggers; menu key toggles window
        A.track(A.Services.UserInputService.InputBegan:Connect(function(input, gpe)
            if gpe then return end
            if input.KeyCode == A.Config.playKey then
                App._triggerPlay()
            elseif input.KeyCode == A.Config.menuKey then
                win.toggle()
            end
        end))
    end

    A.App = App
end
```

Note: the play keybind fires `_triggerPlay()` (plays the selection). The in-UI "Play (loop)" toggle governs the stop side. This matches the spec's "keybind + toggle trigger playback" with the toggle owning the loop/stop lifecycle.

- [ ] **Step 4: Run probe, verify pass**

Run: MCP `execute-file tests/app.probe.lua`.
Expected: all `PASS`, ending `PASS app wired`.

- [ ] **Step 5: Commit**

```bash
git add src/app.lua tests/app.probe.lua
git commit -m "feat: app.lua assembles the suite"
```

---

### Task 8: Full bundle + README + end-to-end live smoke

**Files:**
- Modify: `dist/AnimationPlayer.lua` (rebuilt)
- Create: `README.md`

**Interfaces:**
- Consumes: everything.
- Produces: shippable `dist/AnimationPlayer.lua`.

- [ ] **Step 1: Rebuild the bundle**

Run: `bash build/bundle.sh`
Expected: `built dist/AnimationPlayer.lua (N lines)`, no error.

- [ ] **Step 2: Syntax/load check via executor**

Run: MCP `execute-file dist/AnimationPlayer.lua`; `get-console-output`.
Expected: no Lua error; window renders (`screenshot-window` shows "Animation Player" with an empty list, two inputs, Save/Play/Speed/Looped/Stop, two keybinds). Re-run once → no duplicate window (cleanup guard). If persistence absent, a "won't persist" notify appears.

- [ ] **Step 3: End-to-end live checklist**

On a real client with a character, drive through MCP (`user_mouse_input`, `user_keyboard_input`, `screenshot-window`):
1. Type name `wave`, id `507771019`, click Save → row appears; `readfile("AnimationPlayer/saved.json")` is non-empty (probe via `get-data-by-code`).
2. Click the row → highlights; press `E` → character plays the emote.
3. Toggle "Play (loop)" ON → loops; move Speed slider → speed changes live; toggle "Looped" OFF then re-play → plays once.
4. Click Stop → animation stops.
5. Add a second animation with a different id; scroll if needed; delete the first via its `X` → row gone and `saved.json` updated.
6. Press RightShift → window hides/shows. Rebind "Menu key" to another key → new key toggles; rebind "Play key" → new key triggers.
7. `getgenv().__ANIMPLAYER_CLEANUP()` → all Drawings gone. Re-execute dist → single clean instance.

Record results; any failure re-enters systematic-debugging.

- [ ] **Step 4: Write `README.md`**

```markdown
# Animation Player Suite

Drawing-API Roblox suite to play any catalog animation/emote on your
character from a saved, persistent library.

## Load
```lua
loadstring(readfile("AnimationPlayer/dist/AnimationPlayer.lua"))()
```
(or host `dist/AnimationPlayer.lua` and `loadstring(game:HttpGet(url))()`)

## Use
- **RightShift** — show/hide menu (rebindable)
- Type a **name** + **animation/asset id**, click **Save** — appears in the list
- Click a list row to select; press **E** or toggle **Play (loop)** to play (rebindable)
- **Speed** slider adjusts playback speed live; **Looped** toggles looping
- **Stop** ends playback; each row's **X** deletes it
- Library persists to `AnimationPlayer/saved.json`

## How it plays catalog animations
Resolves a catalog asset id to its real `AnimationId` via
`game:GetObjects("rbxassetid://"..id)[1]`, then loads it onto the character's
`Animator` (falls back to treating a numeric input as a raw animation id).
```

- [ ] **Step 5: Commit**

```bash
git add dist/AnimationPlayer.lua README.md
git commit -m "chore: build dist + README; end-to-end verified"
```

---

## Self-Review

**1. Spec coverage:**
- Drawing-API UI, 0 instances → Tasks 4–6. ✓
- `game:GetObjects` playback method + fallback → Task 3. ✓
- Keybind (E) + toggle to play selected → Task 7. ✓
- Always-open dropdown/list of in-memory animations → Task 6 + wiring Task 7. ✓
- Save custom animation (name + id) appears in menu → Tasks 2 + 7. ✓
- Persistence (writefile JSON) with memory fallback → Task 2. ✓
- RightShift menu toggle, rebindable; play key rebindable → Task 5 (keybind widget) + Task 7. ✓
- Empty library at start → Task 2 (`load()` yields `{}`). ✓
- Loop + speed slider → Tasks 3 + 7. ✓
- Cleanup guard, no duplicate on re-run → Task 1. ✓
- Single-file bundle → Tasks 1 + 8. ✓

**2. Placeholder scan:** No TBD/TODO/"handle edge cases" left; the one unused `PRINTABLE` local is explicitly called out to omit. Error paths are concrete (`A.notify` messages).

**3. Type consistency:** `A.Store.{list,add,remove,get}`, `A.Player.{resolve,play,stop,setSpeed,setLooped,isPlaying}`, `A.UI.{window,button,toggle,slider,textInput,keybind,list}`, list `opts.{height,rowHeight,onSelect,onDelete}`, item `{name,id}` — used identically across Tasks 2–8. `A.notify` set in Task 4, consumed in 2/3/7. `A.track`/`A.trackDraw` defined in Task 1, used in 3/4/5/6/7. Consistent.
