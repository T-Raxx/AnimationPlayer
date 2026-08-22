return function(A)
    local App = {}
    local win, nowPlaying, playBtn
    -- Anims tab
    local list, nameInput, idInput
    local playing = false
    -- Anim packs tab
    local packUrlInput, packNameLbl, packChips, packList, packSaveName
    local currentPack = nil

    -- ============ Anims: single-animation player ============
    function App._refreshList()
        if list then list.setItems(A.Store.list()) end
    end

    function App._setPlaying(on)
        playing = on
        if playBtn and playBtn.setAccent then playBtn.setAccent(on) end
    end
    function App.isPlaying() return playing end

    function App._addFromInputs(name, id)
        local ok, err = A.Store.add(name, id)
        if ok then
            if nameInput then nameInput.clear() end
            if idInput then idInput.clear() end
            App._refreshList()
            A.notify("Saved '" .. name .. "'")
        else
            A.notify(err or "Could not save")
        end
        return ok
    end

    function App._triggerPlay()
        local sel = (list and list.getSelected()) or A.State.selected
        if not sel then A.notify("Select an animation first"); return false end
        A.State.selected = sel
        local ok = A.Player.play(sel.id)
        if ok then
            App._setPlaying(true)
            if nowPlaying then nowPlaying.set(sel.name) end
        end
        return ok
    end

    function App._stop()
        A.Player.stop()
        App._setPlaying(false)
        if nowPlaying then nowPlaying.clear() end
    end

    function App._togglePlay()
        if playing then App._stop() else App._triggerPlay() end
    end

    -- ============ Anim packs ============
    local function typeCount(pack)
        local n = 0
        for _ in pairs(pack.types) do n = n + 1 end
        return n
    end

    function App._loadPack(urlOrId)
        local pack, err = A.Packs.fetch(urlOrId)
        if not pack then A.notify(err or "Could not load bundle"); return false end
        currentPack = pack
        if packNameLbl then packNameLbl.set(pack.name .. "  \u{2022} " .. typeCount(pack) .. " types") end
        A.notify("Loaded '" .. pack.name .. "'")
        return true
    end

    function App._applyPack()
        if not currentPack then A.notify("Load a bundle first"); return end
        local chosen = packChips.getSelected()
        if #chosen == 0 then A.notify("Pick at least one animation type"); return end
        local sel = {}
        for _, tp in ipairs(chosen) do
            if currentPack.types[tp] then sel[tp] = currentPack.types[tp] end
        end
        if not next(sel) then A.notify("This pack has none of the picked types"); return end
        if A.Packs.apply(sel) then A.notify("Applied " .. currentPack.name) end
    end

    function App._refreshPackList()
        if packList then packList.setItems(A.Packs.list()) end
    end

    function App._savePack(name, urlOrId)
        local ok, err = A.Packs.save(name, urlOrId)
        if ok then
            if packSaveName then packSaveName.clear() end
            App._refreshPackList()
            A.notify("Saved pack '" .. name .. "'")
        else
            A.notify(err or "Could not save pack")
        end
    end

    local function buildAnimsPage(page)
        A.UI.section(page, "Library")
        list = A.UI.list(page, {
            height = 130, rowHeight = 34,
            onSelect = function(it) A.State.selected = it end,
            onDelete = function(it)
                A.Store.remove(it.name)
                if A.State.selected and A.State.selected.name == it.name then A.State.selected = nil end
                App._refreshList()
                A.notify("Deleted '" .. it.name .. "'")
            end,
        })
        A.UI.section(page, "Add animation")
        nameInput = A.UI.textInput(page, "name")
        idInput = A.UI.textInput(page, "animation / asset id", true)
        A.UI.button(page, "+ Save to library", function() App._addFromInputs(nameInput.get(), idInput.get()) end, { accent = true })

        A.UI.section(page, "Playback")
        local transport = A.UI.buttonRow(page, {
            { label = "\u{25B6} Play", accent = true, flex = 0.5, cb = function() App._togglePlay() end },
            { label = "\u{25A0} Stop", flex = 0.5, cb = function() App._stop() end },
        })
        playBtn = transport[1]
        A.UI.toggle(page, "Loop", A.Config.looped, function(v) A.Player.setLooped(v) end)
        A.UI.slider(page, "Speed", 0.1, 3.0, A.Config.speed, function(v) A.Player.setSpeed(v) end)

        A.UI.section(page, "Keys")
        A.UI.keybind(page, "Play key", A.Config.playKey, function(k) A.Config.playKey = k end)
        A.UI.keybind(page, "Menu key", A.Config.menuKey, function(k) A.Config.menuKey = k end)
    end

    local function buildPacksPage(page)
        A.UI.section(page, "Load a bundle")
        packUrlInput = A.UI.textInput(page, "bundle url or id", true)
        A.UI.button(page, "Load pack", function() App._loadPack(packUrlInput.get()) end, { accent = true })
        packNameLbl = A.UI.label(page, "no pack loaded")

        A.UI.section(page, "Apply which animations")
        local items = {}
        for _, tp in ipairs(A.Packs.TYPES) do items[#items + 1] = { key = tp, label = tp } end
        packChips = A.UI.chips(page, items)
        A.UI.buttonRow(page, {
            { label = "Full pack", flex = 0.5, cb = function() packChips.setAll(true) end },
            { label = "Clear", flex = 0.5, cb = function() packChips.setAll(false) end },
        })
        A.UI.buttonRow(page, {
            { label = "Apply", accent = true, flex = 0.5, cb = function() App._applyPack() end },
            { label = "Reset", flex = 0.5, cb = function() A.Packs.reset(); A.notify("Reset to default animations") end },
        })

        A.UI.section(page, "Saved packs")
        packList = A.UI.list(page, {
            height = 100, rowHeight = 30,
            onSelect = function(it) packUrlInput.set(it.id); App._loadPack(it.id) end,
            onDelete = function(it) A.Packs.remove(it.name); App._refreshPackList(); A.notify("Removed '" .. it.name .. "'") end,
        })
        A.UI.section(page, "Save current")
        packSaveName = A.UI.textInput(page, "pack name")
        A.UI.button(page, "+ Save pack", function() App._savePack(packSaveName.get(), packUrlInput.get()) end)
    end

    function App.start()
        win = A.UI.window("Animation Player")
        A.App._win = win
        nowPlaying = A.UI.nowPlaying(win)

        local pages = A.UI.tabs(win, { "Anims", "Anim packs" })
        buildAnimsPage(pages[1])
        buildPacksPage(pages[2])

        if not A.Config.hasPersistence then A.notify("No filesystem: library won't persist") end
        App._refreshList()
        App._refreshPackList()

        A.track(A.Services.UserInputService.InputBegan:Connect(function(input, gpe)
            if gpe then return end
            if input.KeyCode == A.Config.playKey then
                App._togglePlay()
            elseif input.KeyCode == A.Config.menuKey then
                win.toggle()
            end
        end))
    end

    A.App = App
end
