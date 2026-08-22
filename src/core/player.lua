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
        if not track then return false end
        local ok, playing = pcall(function() return track.IsPlaying end)
        return ok and playing == true
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
    local plr = A.Services and A.Services.Players and A.Services.Players.LocalPlayer
    if plr and plr.CharacterAdded then
        A.track(plr.CharacterAdded:Connect(function()
            if currentId and A.Config.looped then
                task.wait(1)
                Player.play(currentId)
            end
        end))
    end

    A.Player = Player
end
