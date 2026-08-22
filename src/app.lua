return function(A)
    local App = {}
    local win, list, nameInput, idInput, playToggleWd

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
        local sel = (list and list.getSelected()) or A.State.selected
        if not sel then A.notify("select an animation"); return end
        A.State.selected = sel
        A.Player.play(sel.id)
    end

    function App._onPlayToggle(state)
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
            if playToggleWd and playToggleWd.set then playToggleWd.set(false) end
            A.Player.stop()
        end)

        A.UI.keybind(win, "Play key", A.Config.playKey, function(k) A.Config.playKey = k end)
        A.UI.keybind(win, "Menu key", A.Config.menuKey, function(k) A.Config.menuKey = k end)

        if not A.Config.hasPersistence then A.notify("no filesystem: library won't persist") end
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
