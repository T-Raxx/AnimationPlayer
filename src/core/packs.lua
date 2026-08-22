-- Animation packs: resolve a catalog bundle to per-type animation ids and apply
-- them by overwriting the character's Animate script, then reloading it.
return function(A)
    local HttpService = A.Services.HttpService
    local Players = A.Services.Players
    local Packs = {}

    -- ordered animation types the UI exposes
    Packs.TYPES = { "Idle", "Walk", "Run", "Jump", "Fall", "Climb", "Swim" }

    -- type -> Animate folder/child targets to overwrite
    local MAP = {
        Idle = { { "idle", "Animation1" }, { "idle", "Animation2" } },
        Walk = { { "walk", "WalkAnim" } },
        Run = { { "run", "RunAnim" } },
        Jump = { { "jump", "JumpAnim" } },
        Fall = { { "fall", "FallAnim" } },
        Climb = { { "climb", "ClimbAnim" } },
        Swim = { { "swim", "Swim" }, { "swimidle", "SwimIdle" } },
    }

    local orig = nil       -- snapshot of the char's original AnimationIds {"folder.child"=id}
    local activeSel = nil  -- last applied {Type=id} so we can re-apply after respawn

    local function getAnimate()
        local plr = Players.LocalPlayer
        local char = plr and plr.Character
        return char and char:FindFirstChild("Animate")
    end

    local function snapshot(animate)
        if orig then return end
        orig = {}
        for _, folder in ipairs(animate:GetChildren()) do
            for _, a in ipairs(folder:GetChildren()) do
                if a:IsA("Animation") then orig[folder.Name .. "." .. a.Name] = a.AnimationId end
            end
        end
    end

    -- Reliable reload: clone the (already-edited) Animate script and swap it in so it
    -- re-runs from scratch with the new AnimationIds. Toggling Disabled does NOT restart
    -- an already-run LocalScript on many clients (leaves the character stiff).
    local function reload()
        local plr = Players.LocalPlayer
        local char = plr and plr.Character
        local animate = char and char:FindFirstChild("Animate")
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if not (animate and char) then return end
        local clone = animate:Clone()
        clone.Disabled = false
        animate:Destroy()
        -- stop lingering tracks from the old Animate so nothing stacks across reloads
        local animator = hum and hum:FindFirstChildOfClass("Animator")
        if animator then
            for _, t in ipairs(animator:GetPlayingAnimationTracks()) do pcall(function() t:Stop(0) end) end
        end
        clone.Parent = char
    end

    -- fetch bundle details -> { id, name, types = { Idle=assetId, Walk=assetId, ... } }
    function Packs.fetch(idOrUrl)
        local s = tostring(idOrUrl or "")
        local id = s:match("bundles/(%d+)") or s:match("(%d+)")
        if not id then return nil, "no bundle id" end
        local ok, res = pcall(function()
            return game:HttpGet("https://catalog.roblox.com/v1/bundles/" .. id .. "/details")
        end)
        if not ok then return nil, "network error" end
        local okj, data = pcall(function() return HttpService:JSONDecode(res) end)
        if not okj or type(data) ~= "table" then return nil, "bad response" end
        local types = {}
        for _, it in ipairs(data.items or {}) do
            if it.type == "Asset" and it.name then
                for _, tp in ipairs(Packs.TYPES) do
                    if string.find(string.lower(it.name), string.lower(tp), 1, true) then types[tp] = it.id end
                end
            end
        end
        if not next(types) then return nil, "no animation items in bundle" end
        return { id = id, name = data.name or ("Bundle " .. id), types = types }
    end

    -- apply a subset. sel = { Type = assetId, ... }
    function Packs.apply(sel)
        local animate = getAnimate()
        if not animate then A.notify("No Animate script on character"); return false end
        snapshot(animate)
        local applied = 0
        for tp, id in pairs(sel) do
            local targets = MAP[tp]
            if targets then
                for _, t in ipairs(targets) do
                    local f = animate:FindFirstChild(t[1])
                    local a = f and f:FindFirstChild(t[2])
                    if a then a.AnimationId = "rbxassetid://" .. tostring(id); applied = applied + 1 end
                end
            end
        end
        reload()
        activeSel = sel
        return applied > 0
    end

    function Packs.reset()
        local animate = getAnimate()
        if not animate or not orig then return false end
        for key, id in pairs(orig) do
            local folder, child = key:match("([^.]+)%.(.+)")
            local f = folder and animate:FindFirstChild(folder)
            local a = f and f:FindFirstChild(child)
            if a then a.AnimationId = id end
        end
        reload()
        activeSel = nil
        return true
    end

    function Packs.isActive() return activeSel ~= nil end

    -- re-apply after respawn (fresh char = fresh defaults, so drop the old snapshot)
    local plr = Players.LocalPlayer
    if plr and plr.CharacterAdded then
        A.track(plr.CharacterAdded:Connect(function()
            if activeSel then
                task.wait(1)
                orig = nil
                Packs.apply(activeSel)
            end
        end))
    end

    -- persistence of saved packs (name + bundle id)
    local PATH = "AnimationPlayer/packs.json"
    local saved = {}
    local function persist()
        if not A.Config.hasPersistence then return end
        A.fs.makefolder("AnimationPlayer")
        A.fs.write(PATH, A.json.encode(saved))
    end
    local function load()
        if A.Config.hasPersistence and A.fs.isfile(PATH) then
            local raw = A.fs.read(PATH)
            local t = raw and A.json.decode(raw)
            if type(t) == "table" then
                saved = {}
                for _, r in ipairs(t) do
                    if type(r) == "table" and r.name and r.id then
                        saved[#saved + 1] = { name = tostring(r.name), id = tostring(r.id) }
                    end
                end
            end
        end
    end

    function Packs.list() return saved end
    function Packs.get(name) for _, r in ipairs(saved) do if r.name == name then return r end end return nil end
    function Packs.save(name, idOrUrl)
        name = name and (tostring(name):gsub("^%s+", ""):gsub("%s+$", "")) or ""
        local id = tostring(idOrUrl or ""):match("bundles/(%d+)") or tostring(idOrUrl or ""):match("(%d+)") or ""
        if name == "" then return false, "name required" end
        if id == "" then return false, "bundle id required" end
        if Packs.get(name) then return false, "name already exists" end
        saved[#saved + 1] = { name = name, id = id }
        persist()
        return true
    end
    function Packs.remove(name)
        for i, r in ipairs(saved) do
            if r.name == name then table.remove(saved, i); persist(); return true end
        end
        return false
    end

    load()
    A.Packs = Packs
end
