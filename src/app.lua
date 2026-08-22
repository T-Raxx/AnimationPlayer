return function(A)
    local App = {}
    local win, list, nameInput, idInput, nowPlaying

    function App._refreshList()
        if list then list.setItems(A.Store.list()) end
    end

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
        if not sel then A.notify("Select an animation first"); return end
        A.State.selected = sel
        local ok = A.Player.play(sel.id)
        if ok and nowPlaying then nowPlaying.set(sel.name) end
    end

    function App._stop()
        A.Player.stop()
        if nowPlaying then nowPlaying.clear() end
    end

    function App._onPlayToggle(state)
        if state then App._triggerPlay() else App._stop() end
    end

    function App.start()
        win = A.UI.window("Animation Player")
        A.App._win = win
        nowPlaying = A.UI.nowPlaying(win)

        A.UI.section(win, "Library")
        list = A.UI.list(win, {
            height = 150, rowHeight = 34,
            onSelect = function(it) A.State.selected = it end,
            onDelete = function(it)
                A.Store.remove(it.name)
                if A.State.selected and A.State.selected.name == it.name then A.State.selected = nil end
                App._refreshList()
                A.notify("Deleted '" .. it.name .. "'")
            end,
        })

        A.UI.section(win, "Add animation")
        nameInput = A.UI.textInput(win, "name")
        idInput = A.UI.textInput(win, "animation / asset id", true)
        A.UI.button(win, "+ Save to library", function()
            App._addFromInputs(nameInput.get(), idInput.get())
        end, { accent = true })

        A.UI.section(win, "Playback")
        A.UI.buttonRow(win, {
            { label = "\u{25B6} Play", accent = true, flex = 0.5, cb = function() App._triggerPlay() end },
            { label = "\u{25A0} Stop", flex = 0.5, cb = function() App._stop() end },
        })
        A.UI.toggle(win, "Loop", A.Config.looped, function(v) A.Player.setLooped(v) end)
        A.UI.slider(win, "Speed", 0.1, 3.0, A.Config.speed, function(v) A.Player.setSpeed(v) end)

        A.UI.section(win, "Keys")
        A.UI.keybind(win, "Play key", A.Config.playKey, function(k) A.Config.playKey = k end)
        A.UI.keybind(win, "Menu key", A.Config.menuKey, function(k) A.Config.menuKey = k end)

        if not A.Config.hasPersistence then A.notify("No filesystem: library won't persist") end
        App._refreshList()

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
