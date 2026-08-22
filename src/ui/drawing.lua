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
        r.Color = props.Color or Color3.fromRGB(30, 30, 35)
        r.Transparency = props.Transparency or 1
        r.Visible = props.Visible ~= false
        return r
    end
    local function newText(props)
        local t = A.trackDraw(Drawing.new("Text"))
        t.Size = props.Size or 14
        t.Center = props.Center or false
        t.Outline = true
        t.Color = props.Color or Color3.fromRGB(235, 235, 235)
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
        win.bar = newRect{ Color = Color3.fromRGB(20, 20, 25) }
        win.body = newRect{ Color = Color3.fromRGB(30, 30, 35), Transparency = 0.96 }
        win.titleText = newText{ Text = title, Size = 15 }

        function win.add(h)
            local y = 24 + PAD + win._cursorY
            win._cursorY = win._cursorY + h + PAD
            win.size = Vector2.new(COLW, 24 + PAD + win._cursorY)
            return { x = PAD, y = y, w = COLW - PAD * 2, h = h }
        end
        function win.setVisible(b) win.visible = b end
        function win.toggle() win.setVisible(not win.visible) end

        win._dragging = false
        win._dragOff = Vector2.new(0, 0)

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

        UI._windows[#UI._windows + 1] = win
        return win
    end

    -- ---- button ----
    function UI.button(win, label, cb)
        local box = win.add(ROWH)
        local bg = newRect{ Color = Color3.fromRGB(55, 55, 65) }
        local tx = newText{ Text = label, Center = true }
        local wd = {}
        function wd.draw(origin, vis)
            bg.Position = origin + Vector2.new(box.x, box.y)
            bg.Size = Vector2.new(box.w, box.h)
            bg.Visible = vis
            tx.Position = origin + Vector2.new(box.x + box.w / 2, box.y + 3)
            tx.Visible = vis
        end
        function wd.hit(mx, my, origin, vis)
            if not vis then return false end
            local px, py = origin.X + box.x, origin.Y + box.y
            return mx >= px and mx <= px + box.w and my >= py and my <= py + box.h
        end
        function wd.click() cb() end
        win._widgets[#win._widgets + 1] = wd
        UI._widgets[#UI._widgets + 1] = { wd = wd, win = win }
        return wd
    end

    -- ---- toggle ----
    function UI.toggle(win, label, initial, cb)
        local box = win.add(ROWH)
        local state = initial and true or false
        local bg = newRect{ Color = Color3.fromRGB(45, 45, 55) }
        local knob = newRect{ Color = Color3.fromRGB(90, 200, 120) }
        local tx = newText{ Text = label }
        local wd = {}
        function wd.draw(origin, vis)
            bg.Position = origin + Vector2.new(box.x, box.y); bg.Size = Vector2.new(box.w, box.h); bg.Visible = vis
            knob.Size = Vector2.new(16, 16)
            knob.Position = origin + Vector2.new(box.x + box.w - 22, box.y + 3)
            knob.Color = state and Color3.fromRGB(90, 200, 120) or Color3.fromRGB(80, 80, 90)
            knob.Visible = vis
            tx.Position = origin + Vector2.new(box.x + 6, box.y + 3); tx.Visible = vis
        end
        function wd.hit(mx, my, origin, vis)
            if not vis then return false end
            local px, py = origin.X + box.x, origin.Y + box.y
            return mx >= px and mx <= px + box.w and my >= py and my <= py + box.h
        end
        function wd.click() state = not state; cb(state) end
        function wd.set(v) state = v and true or false end
        function wd.get() return state end
        win._widgets[#win._widgets + 1] = wd
        UI._widgets[#UI._widgets + 1] = { wd = wd, win = win }
        return wd
    end

    -- ---- slider ----
    function UI.slider(win, label, min, max, initial, cb)
        local box = win.add(ROWH)
        local value = initial
        local bg = newRect{ Color = Color3.fromRGB(45, 45, 55) }
        local fill = newRect{ Color = Color3.fromRGB(90, 140, 220) }
        local tx = newText{ Text = label .. ": " .. tostring(value) }
        local wd = {}
        local function frac() return (value - min) / (max - min) end
        function wd.draw(origin, vis)
            bg.Position = origin + Vector2.new(box.x, box.y); bg.Size = Vector2.new(box.w, box.h); bg.Visible = vis
            fill.Position = origin + Vector2.new(box.x, box.y); fill.Size = Vector2.new(box.w * frac(), box.h); fill.Visible = vis
            tx.Text = string.format("%s: %.2f", label, value)
            tx.Position = origin + Vector2.new(box.x + 6, box.y + 3); tx.Visible = vis
        end
        function wd.hit(mx, my, origin, vis)
            if not vis then return false end
            local px, py = origin.X + box.x, origin.Y + box.y
            return mx >= px and mx <= px + box.w and my >= py and my <= py + box.h
        end
        function wd.clickAt(mx, origin)
            local px = origin.X + box.x
            local f = math.clamp((mx - px) / box.w, 0, 1)
            value = min + f * (max - min)
            cb(value)
        end
        wd.isSlider = true
        win._widgets[#win._widgets + 1] = wd
        UI._widgets[#UI._widgets + 1] = { wd = wd, win = win }
        return wd
    end

    -- ---- notify ----
    local notifyText = newText{ Text = "", Size = 13, Color = Color3.fromRGB(255, 210, 120), Visible = false }
    local notifyUntil = 0
    A.notify = function(msg)
        notifyText.Text = "[AnimPlayer] " .. tostring(msg)
        notifyText.Visible = true
        notifyUntil = tick() + 3
        print("[AnimPlayer] " .. tostring(msg))
    end

    -- ---- global render + input ----
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

    A.track(UIS.InputBegan:Connect(function(input, gpe)
        if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
        local m = UIS:GetMouseLocation()
        local mx, my = m.X, m.Y
        for _, win in ipairs(UI._windows) do
            if win.visible then
                local p = win.pos
                if mx >= p.X and mx <= p.X + win.size.X and my >= p.Y and my <= p.Y + 24 then
                    win._dragging = true
                    win._dragOff = Vector2.new(mx - p.X, my - p.Y)
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
        if UI._dispatchClick then UI._dispatchClick(mx, my) end
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
