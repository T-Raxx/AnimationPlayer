-- Instance-based UI (Spotlight theme). Parented to gethui() for stealth.
-- Exposes A.UI.{window,section,list,textInput,button,buttonRow,toggle,slider,keybind,nowPlaying} + A.notify.
return function(A)
    local UIS = A.Services.UserInputService
    local Tween = game:GetService("TweenService")

    local T = {
        bg = Color3.fromHex("16151A"),
        panel = Color3.fromHex("1E1D24"),
        elevated = Color3.fromHex("26242E"),
        stroke = Color3.fromHex("332F3B"),
        text = Color3.fromHex("EDEAF2"),
        muted = Color3.fromHex("8A8594"),
        accent = Color3.fromHex("FFC24B"),
        accentDim = Color3.fromHex("3A3320"),
        playing = Color3.fromHex("7ED08A"),
        danger = Color3.fromHex("E5678A"),
        fontDisplay = Enum.Font.Michroma,
        fontBody = Enum.Font.GothamMedium,
        fontMono = Enum.Font.RobotoMono,
    }
    local WIDTH = 300
    local PAD = 12

    local function mk(cls, props, kids)
        local o = Instance.new(cls)
        pcall(function() o.AutoLocalize = false end) -- stop games' LocalizationTable from translating our labels
        for k, v in pairs(props or {}) do o[k] = v end
        for _, c in ipairs(kids or {}) do c.Parent = o end
        return o
    end
    local function corner(r) return mk("UICorner", { CornerRadius = UDim.new(0, r or 6) }) end
    local function strokeOf(col, th, tr) return mk("UIStroke", { Color = col or T.stroke, Thickness = th or 1, Transparency = tr or 0 }) end
    local function padAll(p) return mk("UIPadding", { PaddingTop = UDim.new(0, p), PaddingBottom = UDim.new(0, p), PaddingLeft = UDim.new(0, p), PaddingRight = UDim.new(0, p) }) end
    local function vlist(gap) return mk("UIListLayout", { FillDirection = Enum.FillDirection.Vertical, SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, gap or 6) }) end

    local function guiParent()
        local ok, h = pcall(function() return gethui() end)
        if ok and h then return h end
        return game:GetService("CoreGui")
    end
    local function randName()
        local s = ""
        for _ = 1, 12 do s = s .. string.char(math.random(97, 122)) end
        return s
    end

    local UI_FILE = "AnimationPlayer/ui.json"
    local function loadUISize()
        if not A.Config.hasPersistence then return nil end
        if not A.fs.isfile(UI_FILE) then return nil end
        local raw = A.fs.read(UI_FILE)
        local t = raw and A.json.decode(raw)
        if type(t) == "table" and tonumber(t.w) and tonumber(t.h) then return tonumber(t.w), tonumber(t.h) end
        return nil
    end
    local function saveUISize(w, h)
        if not A.Config.hasPersistence then return end
        A.fs.makefolder("AnimationPlayer")
        A.fs.write(UI_FILE, A.json.encode({ w = math.floor(w), h = math.floor(h) }))
    end
    local function flexFill(inst)
        pcall(function()
            local f = Instance.new("UIFlexItem")
            f.FlexMode = Enum.UIFlexMode.Fill
            f.Parent = inst
        end)
    end

    local UI = {}

    -- hover lerp helper for buttons
    local function hoverable(btn, base, hover)
        A.track(btn.MouseEnter:Connect(function() Tween:Create(btn, TweenInfo.new(0.12), { BackgroundColor3 = hover }):Play() end))
        A.track(btn.MouseLeave:Connect(function() Tween:Create(btn, TweenInfo.new(0.12), { BackgroundColor3 = base }):Play() end))
    end

    -- ===================== window =====================
    function UI.window(title)
        local MINW, MAXW, MINH, MAXH = 250, 560, 380, 820
        local sw, sh = loadUISize()
        local W = math.clamp(sw or 300, MINW, MAXW)
        local H = math.clamp(sh or 560, MINH, MAXH)

        local gui = mk("ScreenGui", { Name = randName(), ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 999999, IgnoreGuiInset = true })
        gui.Parent = guiParent()
        A.trackInst(gui)
        A._screenGui = gui

        local card = mk("Frame", {
            Name = "Card", Size = UDim2.fromOffset(W, H), Position = UDim2.fromOffset(80, 90),
            BackgroundColor3 = T.panel, BorderSizePixel = 0, ClipsDescendants = true,
        }, { corner(12), strokeOf(T.stroke, 1, 0.25) })
        card.Parent = gui

        -- stack holds the laid-out rows; keeps the resize grip OUT of the list layout
        local stack = mk("Frame", { Name = "Stack", Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1 }, { vlist(0) })
        stack.Parent = card

        -- header (drag handle)
        local header = mk("Frame", { Name = "Header", Size = UDim2.new(1, 0, 0, 44), BackgroundColor3 = T.bg, BorderSizePixel = 0, LayoutOrder = 0 }, { corner(12) })
        mk("Frame", { Size = UDim2.new(1, 0, 0, 12), Position = UDim2.new(0, 0, 1, -12), BackgroundColor3 = T.bg, BorderSizePixel = 0 }).Parent = header -- square off bottom corners
        mk("TextLabel", {
            BackgroundTransparency = 1, Size = UDim2.new(1, -60, 1, 0), Position = UDim2.fromOffset(PAD, 0),
            Font = T.fontDisplay, Text = string.upper(title), TextSize = 14, TextColor3 = T.text, TextXAlignment = Enum.TextXAlignment.Left,
        }).Parent = header
        local closeBtn = mk("TextButton", {
            Size = UDim2.fromOffset(24, 24), Position = UDim2.new(1, -32, 0.5, -12), BackgroundColor3 = T.elevated,
            Font = T.fontBody, Text = "\u{2715}", TextSize = 13, TextColor3 = T.muted, AutoButtonColor = false,
        }, { corner(6) })
        closeBtn.Parent = header
        header.Parent = stack

        -- content fills the remaining height (flex); its own list layout stacks the widgets
        local content = mk("Frame", { Name = "Content", Size = UDim2.new(1, 0, 0, 0), BackgroundTransparency = 1, LayoutOrder = 2, ClipsDescendants = true }, { padAll(PAD), vlist(8) })
        flexFill(content)
        content.Parent = stack

        local win = { gui = gui, card = card, header = header, content = content, _order = 0, visible = true }
        function win.next() win._order = win._order + 1; return win._order end
        function win.setVisible(b) win.visible = b; card.Visible = b end
        function win.toggle() win.setVisible(not win.visible) end
        A.track(closeBtn.MouseButton1Click:Connect(function() win.setVisible(false) end))

        -- bottom-right resize grip (real width/height, persisted)
        local grip = mk("TextButton", {
            Name = "Resize", AnchorPoint = Vector2.new(1, 1), Size = UDim2.fromOffset(20, 20),
            Position = UDim2.new(1, -2, 1, -2), BackgroundTransparency = 1, AutoButtonColor = false,
            Font = T.fontBody, Text = "\u{25E2}", TextSize = 14, TextColor3 = T.muted, ZIndex = 20,
        })
        grip.Parent = card
        A.track(grip.MouseEnter:Connect(function() grip.TextColor3 = T.accent end))

        -- drag (header) + resize (grip) share the pointer stream
        local dragging, dragStart, startPos = false, nil, nil
        local resizing, rStart, rStartW, rStartH = false, nil, W, H
        A.track(header.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                dragging = true; dragStart = input.Position; startPos = card.Position
            end
        end))
        A.track(grip.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                resizing = true; rStart = input.Position; rStartW = card.Size.X.Offset; rStartH = card.Size.Y.Offset; grip.TextColor3 = T.accent
            end
        end))
        A.track(UIS.InputChanged:Connect(function(input)
            if input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch then return end
            if dragging then
                local d = input.Position - dragStart
                card.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
            elseif resizing then
                local d = input.Position - rStart
                card.Size = UDim2.fromOffset(math.clamp(rStartW + d.X, MINW, MAXW), math.clamp(rStartH + d.Y, MINH, MAXH))
            end
        end))
        A.track(UIS.InputEnded:Connect(function(input)
            if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end
            dragging = false
            if resizing then
                resizing = false; grip.TextColor3 = T.muted
                saveUISize(card.Size.X.Offset, card.Size.Y.Offset)
            end
        end))

        return win
    end

    -- ===================== section label =====================
    function UI.section(win, title)
        local row = mk("TextLabel", {
            BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 14), LayoutOrder = win.next(),
            Font = T.fontBody, Text = string.upper(title), TextSize = 10, TextColor3 = T.muted,
            TextXAlignment = Enum.TextXAlignment.Left,
        })
        row.Parent = win.content
        return row
    end

    -- ===================== now playing (signature) =====================
    function UI.nowPlaying(win)
        local bar = mk("Frame", { Name = "NowPlaying", Size = UDim2.new(1, 0, 0, 26), BackgroundColor3 = T.bg, BorderSizePixel = 0, LayoutOrder = win.next(), Visible = false }, { corner(6), padAll(6) })
        bar.Parent = win.content
        local eqHolder = mk("Frame", { Size = UDim2.fromOffset(70, 14), Position = UDim2.new(0, PAD, 0.5, -7), BackgroundTransparency = 1 })
        eqHolder.Parent = bar
        local eqLayout = mk("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 3), VerticalAlignment = Enum.VerticalAlignment.Center })
        eqLayout.Parent = eqHolder
        local bars = {}
        for i = 1, 7 do
            bars[i] = mk("Frame", { Size = UDim2.fromOffset(5, 4 + (i % 3) * 4), BackgroundColor3 = T.accent, BorderSizePixel = 0, LayoutOrder = i }, { corner(2) })
            bars[i].Parent = eqHolder
        end
        local lbl = mk("TextLabel", {
            BackgroundTransparency = 1, Size = UDim2.new(1, -100, 1, 0), Position = UDim2.new(0, 90, 0, 0),
            Font = T.fontBody, Text = "", TextSize = 11, TextColor3 = T.muted, TextXAlignment = Enum.TextXAlignment.Left,
        })
        lbl.Parent = bar
        local anim = {}
        local function stopAnim() for _, tw in ipairs(anim) do pcall(function() tw:Cancel() end) end anim = {} end
        local h = {}
        function h.set(name)
            bar.Visible = true
            lbl.Text = "now playing  " .. tostring(name)
            stopAnim()
            for i, b in ipairs(bars) do
                local tw = Tween:Create(b, TweenInfo.new(0.35 + (i % 4) * 0.08, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Size = UDim2.fromOffset(5, 13) })
                tw:Play(); anim[#anim + 1] = tw
            end
        end
        function h.clear() stopAnim(); bar.Visible = false; lbl.Text = "" end
        return h
    end

    -- ===================== button =====================
    local function makeButton(parent, label, cb, opts)
        opts = opts or {}
        local accent = opts.accent
        local base = accent and T.accent or T.elevated
        local hover = accent and Color3.fromHex("FFD070") or Color3.fromHex("312E3A")
        local btn = mk("TextButton", {
            Size = opts.size or UDim2.new(1, 0, 0, 32), BackgroundColor3 = base, AutoButtonColor = false,
            Font = T.fontBody, Text = label, TextSize = 13, TextColor3 = accent and T.bg or T.text, LayoutOrder = opts.order or 0,
        }, { corner(8) })
        hoverable(btn, base, hover)
        if cb then A.track(btn.MouseButton1Click:Connect(cb)) end
        btn.Parent = parent
        local handle = { instance = btn, _base = base }
        function handle.setAccent(on)
            local b = on and T.playing or handle._base
            btn.BackgroundColor3 = b; btn.TextColor3 = on and T.bg or (accent and T.bg or T.text)
        end
        return handle
    end
    function UI.button(win, label, cb, opts)
        opts = opts or {}
        opts.order = win.next()
        return makeButton(win.content, label, cb, opts)
    end
    function UI.buttonRow(win, items)
        local row = mk("Frame", { Size = UDim2.new(1, 0, 0, 32), BackgroundTransparency = 1, LayoutOrder = win.next() }, {})
        local lay = mk("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder })
        lay.Parent = row
        local handles = {}
        for i, it in ipairs(items) do
            handles[i] = makeButton(row, it.label, it.cb, { accent = it.accent, size = UDim2.new(it.flex or 0.5, -4, 1, 0), order = i })
        end
        row.Parent = win.content
        return handles
    end

    -- ===================== textInput (real TextBox: paste + no caps) =====================
    function UI.textInput(win, placeholder, mono)
        local frame = mk("Frame", { Size = UDim2.new(1, 0, 0, 32), BackgroundColor3 = T.elevated, BorderSizePixel = 0, LayoutOrder = win.next() }, { corner(8), strokeOf(T.stroke, 1, 0.4) })
        local tb = mk("TextBox", {
            BackgroundTransparency = 1, Size = UDim2.new(1, -16, 1, 0), Position = UDim2.fromOffset(10, 0),
            Font = mono and T.fontMono or T.fontBody, Text = "", PlaceholderText = placeholder, PlaceholderColor3 = T.muted,
            TextColor3 = T.text, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left, ClearTextOnFocus = false, ClipsDescendants = true,
        })
        tb.Parent = frame
        local st = strokeOf(T.accent, 1, 0)
        st.Enabled = false; st.Parent = frame
        A.track(tb.Focused:Connect(function() st.Enabled = true end))
        A.track(tb.FocusLost:Connect(function() st.Enabled = false end))
        frame.Parent = win.content
        local inp = {}
        function inp.get() return tb.Text end
        function inp.set(s) tb.Text = tostring(s or "") end
        function inp.clear() tb.Text = "" end
        return inp
    end

    -- ===================== toggle =====================
    function UI.toggle(win, label, initial, cb)
        local state = initial and true or false
        local row = mk("Frame", { Size = UDim2.new(1, 0, 0, 28), BackgroundTransparency = 1, LayoutOrder = win.next() })
        mk("TextLabel", { BackgroundTransparency = 1, Size = UDim2.new(1, -50, 1, 0), Font = T.fontBody, Text = label, TextSize = 13, TextColor3 = T.text, TextXAlignment = Enum.TextXAlignment.Left }).Parent = row
        local pill = mk("TextButton", { Size = UDim2.fromOffset(40, 22), Position = UDim2.new(1, -40, 0.5, -11), BackgroundColor3 = state and T.accent or T.elevated, AutoButtonColor = false, Text = "" }, { corner(11) })
        local knob = mk("Frame", { Size = UDim2.fromOffset(16, 16), Position = state and UDim2.new(1, -19, 0.5, -8) or UDim2.new(0, 3, 0.5, -8), BackgroundColor3 = state and T.bg or T.muted, BorderSizePixel = 0 }, { corner(8) })
        knob.Parent = pill
        pill.Parent = row
        row.Parent = win.content
        local h = {}
        local function render()
            Tween:Create(pill, TweenInfo.new(0.12), { BackgroundColor3 = state and T.accent or T.elevated }):Play()
            Tween:Create(knob, TweenInfo.new(0.12), { Position = state and UDim2.new(1, -19, 0.5, -8) or UDim2.new(0, 3, 0.5, -8), BackgroundColor3 = state and T.bg or T.muted }):Play()
        end
        function h.set(v) state = v and true or false; render() end
        function h.get() return state end
        A.track(pill.MouseButton1Click:Connect(function() state = not state; render(); if cb then cb(state) end end))
        return h
    end

    -- ===================== slider =====================
    function UI.slider(win, label, min, max, initial, cb)
        local value = initial
        local row = mk("Frame", { Size = UDim2.new(1, 0, 0, 40), BackgroundTransparency = 1, LayoutOrder = win.next() })
        local head = mk("TextLabel", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 16), Font = T.fontBody, Text = label, TextSize = 12, TextColor3 = T.text, TextXAlignment = Enum.TextXAlignment.Left })
        head.Parent = row
        local valLbl = mk("TextLabel", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 16), Font = T.fontMono, Text = "", TextSize = 12, TextColor3 = T.accent, TextXAlignment = Enum.TextXAlignment.Right })
        valLbl.Parent = row
        local track = mk("Frame", { Size = UDim2.new(1, 0, 0, 6), Position = UDim2.new(0, 0, 0, 26), BackgroundColor3 = T.elevated, BorderSizePixel = 0 }, { corner(3) })
        local fill = mk("Frame", { Size = UDim2.new(0, 0, 1, 0), BackgroundColor3 = T.accent, BorderSizePixel = 0 }, { corner(3) })
        fill.Parent = track
        local handle = mk("Frame", { Size = UDim2.fromOffset(12, 12), BackgroundColor3 = T.text, BorderSizePixel = 0, ZIndex = 2 }, { corner(6) })
        handle.Parent = track
        track.Parent = row
        row.Parent = win.content

        local function frac() return (value - min) / (max - min) end
        local function render()
            fill.Size = UDim2.new(frac(), 0, 1, 0)
            handle.Position = UDim2.new(frac(), -6, 0.5, -6)
            valLbl.Text = string.format("%.2fx", value)
        end
        render()
        local sliding = false
        local function setFromX(px)
            local abs = track.AbsolutePosition.X
            local w = track.AbsoluteSize.X
            local f = math.clamp((px - abs) / w, 0, 1)
            value = min + f * (max - min)
            render(); if cb then cb(value) end
        end
        A.track(track.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then sliding = true; setFromX(input.Position.X) end
        end))
        A.track(UIS.InputChanged:Connect(function(input)
            if sliding and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then setFromX(input.Position.X) end
        end))
        A.track(UIS.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then sliding = false end
        end))
        local h = {}
        function h.set(v) value = v; render() end
        function h.get() return value end
        return h
    end

    -- ===================== keybind =====================
    UI._capture = nil
    function UI.keybind(win, label, initial, cb)
        local key = initial
        local row = mk("Frame", { Size = UDim2.new(1, 0, 0, 26), BackgroundTransparency = 1, LayoutOrder = win.next() })
        mk("TextLabel", { BackgroundTransparency = 1, Size = UDim2.new(1, -80, 1, 0), Font = T.fontBody, Text = label, TextSize = 12, TextColor3 = T.muted, TextXAlignment = Enum.TextXAlignment.Left }).Parent = row
        local btn = mk("TextButton", { Size = UDim2.fromOffset(76, 22), Position = UDim2.new(1, -76, 0.5, -11), BackgroundColor3 = T.elevated, AutoButtonColor = false, Font = T.fontMono, Text = "[" .. (key and key.Name or "None") .. "]", TextSize = 11, TextColor3 = T.text }, { corner(6), strokeOf(T.stroke, 1, 0.4) })
        btn.Parent = row
        row.Parent = win.content
        local kb = {}
        function kb.get() return key end
        function kb.set(k) key = k; btn.Text = "[" .. (k and k.Name or "None") .. "]"; if cb then cb(k) end end
        A.track(btn.MouseButton1Click:Connect(function() UI._capture = kb; btn.Text = "[ ... ]" end))
        A.track(UIS.InputBegan:Connect(function(input, gpe)
            if UI._capture == kb and input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode ~= Enum.KeyCode.Unknown then
                UI._capture = nil; kb.set(input.KeyCode)
            end
        end))
        return kb
    end

    -- ===================== list (always open) =====================
    function UI.list(win, opts)
        opts = opts or {}
        local rowH = opts.rowHeight or 34
        local viewH = opts.height or 150
        local container = mk("ScrollingFrame", {
            Size = UDim2.new(1, 0, 0, viewH), BackgroundColor3 = T.bg, BorderSizePixel = 0, LayoutOrder = win.next(),
            ScrollBarThickness = 4, ScrollBarImageColor3 = T.stroke, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
            ScrollingDirection = Enum.ScrollingDirection.Y,
        }, { corner(8), padAll(6), vlist(4) })
        flexFill(container) -- list grows/shrinks as the window is resized taller/shorter
        container.Parent = win.content
        local emptyLbl = mk("TextLabel", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, viewH - 12), Font = T.fontBody, Text = "no animations yet \u{2014} add one below", TextSize = 12, TextColor3 = T.muted, TextWrapped = true })
        emptyLbl.Parent = container

        local items, selectedName, rows = {}, nil, {}
        local lst = {}

        local function rebuild()
            for _, r in ipairs(rows) do r:Destroy() end
            rows = {}
            emptyLbl.Visible = (#items == 0)
            for i, it in ipairs(items) do
                local selected = (it.name == selectedName)
                local rowBtn = mk("TextButton", { Size = UDim2.new(1, 0, 0, rowH), BackgroundColor3 = selected and T.accentDim or T.elevated, AutoButtonColor = false, Text = "", LayoutOrder = i }, { corner(6) })
                if selected then mk("Frame", { Size = UDim2.fromOffset(3, rowH - 10), Position = UDim2.fromOffset(0, 5), BackgroundColor3 = T.accent, BorderSizePixel = 0 }, { corner(2) }).Parent = rowBtn end
                mk("TextLabel", { BackgroundTransparency = 1, Size = UDim2.new(0.55, -12, 1, 0), Position = UDim2.fromOffset(10, 0), Font = T.fontBody, Text = it.name, TextSize = 13, TextColor3 = T.text, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd }).Parent = rowBtn
                mk("TextLabel", { BackgroundTransparency = 1, Size = UDim2.new(0.45, -34, 1, 0), Position = UDim2.new(0.55, 0, 0, 0), Font = T.fontMono, Text = it.id, TextSize = 11, TextColor3 = T.muted, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd }).Parent = rowBtn
                local del = mk("TextButton", { Size = UDim2.fromOffset(22, 22), Position = UDim2.new(1, -28, 0.5, -11), BackgroundColor3 = T.panel, AutoButtonColor = false, Font = T.fontBody, Text = "\u{2715}", TextSize = 12, TextColor3 = T.danger }, { corner(6) })
                del.Parent = rowBtn
                local capturedName = it.name
                A.track(del.MouseButton1Click:Connect(function() if opts.onDelete then opts.onDelete(lst.get(capturedName)) end end))
                A.track(rowBtn.MouseButton1Click:Connect(function() selectedName = capturedName; rebuild(); if opts.onSelect then opts.onSelect(lst.get(capturedName)) end end))
                rowBtn.Parent = container
                rows[#rows + 1] = rowBtn
            end
        end

        function lst.get(name) for _, it in ipairs(items) do if it.name == name then return it end end return nil end
        function lst.setItems(arr) items = arr or {}; if selectedName and not lst.get(selectedName) then selectedName = nil end; rebuild() end
        function lst.getSelected() return selectedName and lst.get(selectedName) or nil end
        function lst.clearSelection() selectedName = nil; rebuild() end
        rebuild()
        return lst
    end

    -- ===================== notify =====================
    do
        local sg = mk("ScreenGui", { Name = randName(), ResetOnSpawn = false, DisplayOrder = 1000000, IgnoreGuiInset = true })
        sg.Parent = guiParent()
        A.trackInst(sg)
        local toast = mk("Frame", { Size = UDim2.fromOffset(240, 34), Position = UDim2.new(0.5, -120, 0, -50), BackgroundColor3 = T.bg, BorderSizePixel = 0, Visible = false }, { corner(8), strokeOf(T.accent, 1, 0.3) })
        local msg = mk("TextLabel", { BackgroundTransparency = 1, Size = UDim2.new(1, -16, 1, 0), Position = UDim2.fromOffset(8, 0), Font = T.fontBody, Text = "", TextSize = 12, TextColor3 = T.text, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd })
        msg.Parent = toast
        toast.Parent = sg
        local token = 0
        A.notify = function(text)
            print("[AnimPlayer] " .. tostring(text))
            msg.Text = tostring(text)
            toast.Visible = true
            Tween:Create(toast, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = UDim2.new(0.5, -120, 0, 16) }):Play()
            token = token + 1
            local mine = token
            task.delay(2.6, function()
                if mine ~= token then return end
                Tween:Create(toast, TweenInfo.new(0.2), { Position = UDim2.new(0.5, -120, 0, -50) }):Play()
                task.wait(0.2); if mine == token then toast.Visible = false end
            end)
        end
    end

    -- ===================== label =====================
    function UI.label(page, text)
        local lbl = mk("TextLabel", {
            BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 18), LayoutOrder = page.next(),
            Font = T.fontBody, Text = text or "", TextSize = 12, TextColor3 = T.text, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
        })
        lbl.Parent = page.content
        local h = {}
        function h.set(t) lbl.Text = tostring(t or "") end
        return h
    end

    -- ===================== tabs (chrome-style) =====================
    function UI.tabs(win, names)
        local bar = mk("Frame", { Name = "Tabs", Size = UDim2.new(1, 0, 0, 30), BackgroundColor3 = T.bg, BorderSizePixel = 0, LayoutOrder = win.next() }, { corner(8) })
        mk("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Left }).Parent = bar
        mk("UIPadding", { PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 4), PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4) }).Parent = bar
        bar.Parent = win.content

        local host = mk("Frame", { Name = "Pages", Size = UDim2.new(1, 0, 0, 0), BackgroundTransparency = 1, LayoutOrder = win.next() })
        flexFill(host)
        host.Parent = win.content

        local pages, tabBtns = {}, {}
        local n = #names
        local function activate(idx)
            for i, p in ipairs(pages) do p.frame.Visible = (i == idx) end
            for i, b in ipairs(tabBtns) do
                b.BackgroundColor3 = (i == idx) and T.elevated or T.bg
                b.TextColor3 = (i == idx) and T.accent or T.muted
                b:FindFirstChild("Underline").Visible = (i == idx)
            end
        end
        for i, name in ipairs(names) do
            local btn = mk("TextButton", {
                Size = UDim2.new(1 / n, -3, 1, 0), BackgroundColor3 = T.bg, AutoButtonColor = false,
                Font = T.fontBody, Text = name, TextSize = 12, TextColor3 = T.muted, LayoutOrder = i,
            }, { corner(6) })
            mk("Frame", { Name = "Underline", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -1), Size = UDim2.new(1, -18, 0, 2), BackgroundColor3 = T.accent, BorderSizePixel = 0, Visible = false }, { corner(1) }).Parent = btn
            btn.Parent = bar
            tabBtns[i] = btn

            local frame = mk("Frame", { Name = "Page_" .. i, Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Visible = false, ClipsDescendants = true }, { vlist(8) })
            frame.Parent = host
            local page = { frame = frame, content = frame, card = win.card, _order = 0 }
            function page.next() page._order = page._order + 1; return page._order end
            pages[i] = page
            A.track(btn.MouseButton1Click:Connect(function() activate(i) end))
        end
        activate(1)
        return pages
    end

    -- ===================== chips (wrapping multi-select) =====================
    function UI.chips(page, items)
        local frame = mk("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = page.next() })
        local lay = mk("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder })
        pcall(function() lay.Wraps = true end)
        lay.Parent = frame
        frame.Parent = page.content
        local sel, chips = {}, {}
        local h = { onChange = nil }
        local function refresh(key)
            local c = chips[key]
            c.BackgroundColor3 = sel[key] and T.accent or T.elevated
            c.TextColor3 = sel[key] and T.bg or T.text
        end
        for i, it in ipairs(items) do
            local btn = mk("TextButton", {
                Size = UDim2.new(0, 0, 0, 26), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = T.elevated,
                AutoButtonColor = false, Font = T.fontBody, Text = it.label, TextSize = 12, TextColor3 = T.text, LayoutOrder = i,
            }, { corner(13) })
            mk("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }).Parent = btn
            btn.Parent = frame
            chips[it.key] = btn
            A.track(btn.MouseButton1Click:Connect(function() sel[it.key] = not sel[it.key]; refresh(it.key); if h.onChange then h.onChange() end end))
            refresh(it.key)
        end
        function h.getSelected() local out = {} for k, v in pairs(sel) do if v then out[#out + 1] = k end end return out end
        function h.isSelected(k) return sel[k] == true end
        function h.setAll(v) for k in pairs(chips) do sel[k] = v; refresh(k) end if h.onChange then h.onChange() end end
        function h.set(k, v) if chips[k] then sel[k] = v; refresh(k) end end
        return h
    end

    A.UI = UI
end
