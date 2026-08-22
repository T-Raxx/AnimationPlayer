-- Animation Player Suite -- entry (bundled after module locals __DRAWING/__STORE/__PLAYER/__APP)
if getgenv().__ANIMPLAYER_CLEANUP then
    pcall(getgenv().__ANIMPLAYER_CLEANUP)
    getgenv().__ANIMPLAYER_CLEANUP = nil
end

local A = {}
A._connections = {}
A._instances = {}

A.Services = {
    Players = game:GetService("Players"),
    UserInputService = game:GetService("UserInputService"),
    RunService = game:GetService("RunService"),
    HttpService = game:GetService("HttpService"),
}

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
    encode = function(t)
        local ok, r = pcall(function() return A.Services.HttpService:JSONEncode(t) end)
        return ok and r or "[]"
    end,
    decode = function(s)
        local ok, r = pcall(function() return A.Services.HttpService:JSONDecode(s) end)
        return ok and r or nil
    end,
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

A.track = function(conn) table.insert(A._connections, conn); return conn end
A.trackInst = function(inst) table.insert(A._instances, inst); return inst end

-- module load order: gui -> store -> player -> packs -> app (gui sets A.notify first)
local MODULES = { __GUI, __STORE, __PLAYER, __PACKS, __APP }
for _, m in ipairs(MODULES) do m(A) end

getgenv().__ANIMPLAYER_CLEANUP = function()
    for _, c in ipairs(A._connections) do pcall(function() c:Disconnect() end) end
    for _, i in ipairs(A._instances) do pcall(function() i:Destroy() end) end
    if A.Player and A.Player.stop then pcall(A.Player.stop) end
end

getgenv().__ANIMPLAYER = A  -- debug/scripting handle

A.App.start()
