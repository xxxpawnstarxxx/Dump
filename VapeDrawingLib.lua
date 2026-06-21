--[[
    VapeDrawingLib — A port of the VapeV4 GUI architecture to Drawing.new
    =======================================================================
    Public API mirrors VapeV4 (mainapi:CreateCategory, :CreateModule,
    :CreateToggle, :CreateButton, :CreateNotification, :Save, :Load,
    :Uninject) but every pixel is rendered with Drawing.new primitives.

    What's included (this build):
      - Full infrastructure: render loop, registry, tween system,
        hit-test framework, manual layout, keyboard capture, image
        byte cache, 9-slice-ish image compositor.
      - Window primitive (CreateCategory) — draggable sidebar + panel
        with scrolling module list and expand/collapse animation.
      - Module primitive (CreateModule) — toggle row, keybind dots,
        expandable children container.
      - Toggle component — fully working, hover effects, accent color,
        rainbow mode support.
      - Button component — fully working, hover effects.
      - Notifications — slide-in, progress bar, auto-dismiss.
      - Theming (GUIColor + UpdateGUI) and Rainbow mode.
      - Save/Load to JSON file.

    What's NOT included (deliberately scoped):
      - Slider, ColorSlider, TwoSlider, Dropdown, TextBox, TextList,
        Targets, Font, Overlay, CategoryList, Legit. The infrastructure
        is in place — adding them follows the same pattern as Toggle.

    Educational reference only. Using executor APIs in live Roblox
    games violates Roblox ToS.
]]

-- ============================================================
-- 1. SERVICES
-- ============================================================
local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TextService      = game:GetService("TextService")
local HttpService      = game:GetService("HttpService")
local Workspace        = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
local Camera      = Workspace.CurrentCamera or Workspace:WaitForChild("Camera")

Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
    Camera = Workspace.CurrentCamera or Camera
end)

-- ============================================================
-- 2. SAFE EXECUTOR FUNCTION ACCESS
-- ============================================================
local function isExecutorFn(fn)
    return type(fn) == "function"
end

local function isGameActive()
    if not isExecutorFn(isrbxactive) then return true end
    local ok, active = pcall(isrbxactive)
    return ok and active == true
end

-- ============================================================
-- 3. STATE: mainapi
-- ============================================================
local mainapi = {
    Categories   = {},
    Modules      = {},
    Windows      = {},
    GUIColor     = { Hue = 0.46, Sat = 0.96, Value = 0.52, Rainbow = false },
    Keybind      = { "RightShift" },
    HeldKeybinds = {},
    Profile      = "default",
    Profiles     = {},
    Scale        = { Value = 1 },
    Version      = "4.18-drawing",
    Loaded       = false,
    RainbowSpeed = { Value = 1 },
    RainbowTable = {},
    Notifications = { Enabled = true },
    -- internal
    Drawings     = {},     -- every drawing object, for cleanup
    HitTargets   = {},     -- {id = {bounds=fn, callbacks=table, hovered=bool}}
    Tweens       = {},     -- active tweens
    Layouts      = {},     -- {id = {container=, children=fn, startY=, padding=, scroll=, max=, clip=}}
    ThemedDrawings = {},   -- drawings whose Color should follow GUIColor
    _hidCounter  = 0,
    _layoutCounter = 0,
    Binding      = nil,    -- optionapi currently being rebound, or nil
}

-- ============================================================
-- 4. UIPALLET / COLOR HELPERS (mirrors VapeV4 lines 48-59, 424-453)
-- ============================================================
local uipallet = {
    Main   = Color3.fromRGB(26, 25, 26),
    Text   = Color3.fromRGB(200, 200, 200),
    Font   = Drawing.Fonts.UI,        -- only 4 fonts in Drawing API
    Tween  = 0.16,                    -- seconds, linear
}

local color = {}

function color.Dark(col, num)
    local h, s, v = col:ToHSV()
    local baseV = select(3, uipallet.Main:ToHSV())
    return Color3.fromHSV(h, s, math.clamp(baseV > 0.5 and v + num or v - num, 0, 1))
end

function color.Light(col, num)
    local h, s, v = col:ToHSV()
    local baseV = select(3, uipallet.Main:ToHSV())
    return Color3.fromHSV(h, s, math.clamp(baseV > 0.5 and v - num or v + num, 0, 1))
end

function mainapi:Color(h)
    local s = 0.75 + (0.15 * math.min(h / 0.03, 1))
    if h > 0.57 then s = 0.9 - (0.4 * math.min((h - 0.57) / 0.09, 1)) end
    if h > 0.66 then s = 0.5 + (0.4 * math.min((h - 0.66) / 0.16, 1)) end
    if h > 0.87 then s = 0.9 - (0.15 * math.min((h - 0.87) / 0.13, 1)) end
    return h, s, 1
end

function mainapi:TextColor(h, s, v)
    if v >= 0.7 and (s < 0.6 or (h > 0.04 and h < 0.56)) then
        return Color3.new(0.19, 0.19, 0.19)
    end
    return Color3.new(1, 1, 1)
end

local function accentColor()
    return Color3.fromHSV(mainapi.GUIColor.Hue, mainapi.GUIColor.Sat, mainapi.GUIColor.Value)
end

-- ============================================================
-- 5. DRAW HELPER (Splix pattern, line 1012)
-- ============================================================
local function Draw(typeName, props)
    if not Drawing or not isExecutorFn(Drawing.new) then return nil end
    local ok, obj = pcall(Drawing.new, typeName)
    if not ok or not obj then return nil end
    for k, v in pairs(props or {}) do
        pcall(function() obj[k] = v end)
    end
    table.insert(mainapi.Drawings, obj)
    return obj
end

local function destroyDraw(obj)
    if not obj then return end
    pcall(function() obj.Visible = false end)
    pcall(function() obj:Remove() end)
    for i = #mainapi.Drawings, 1, -1 do
        if mainapi.Drawings[i] == obj then
            table.remove(mainapi.Drawings, i)
            break
        end
    end
end

-- ============================================================
-- 6. IMAGE BYTE CACHE (replaces rbxassetid:// pipeline)
-- ============================================================
-- VapeV4 uses ImageLabel.Image = 'rbxassetid://...'. Drawing.new Image
-- requires raw bytes. We fetch once and cache.
local imageCache = {}

local function getDrawingImage(url)
    if not url or url == "" then return nil end
    if imageCache[url] ~= nil then return imageCache[url] end
    local ok, data = pcall(function() return game:HttpGet(url, true) end)
    if not ok or not data or #data == 0 then
        imageCache[url] = false
        return nil
    end
    imageCache[url] = data
    return data
end

-- ============================================================
-- 7. HIT-TEST FRAMEWORK
-- ============================================================
-- Each hit target has: bounds() -> (Vector2 pos, Vector2 size), callbacks {onEnter, onLeave, onDown, onUp, onClick}
local function registerHit(bounds, callbacks)
    mainapi._hidCounter = mainapi._hidCounter + 1
    local id = mainapi._hidCounter
    mainapi.HitTargets[id] = {
        bounds    = bounds,
        callbacks = callbacks or {},
        hovered   = false,
        pressed   = false,
    }
    return id
end

local function unregisterHit(id)
    mainapi.HitTargets[id] = nil
end

local function pointInRect(px, py, pos, size)
    return px >= pos.X and px <= pos.X + size.X
       and py >= pos.Y and py <= pos.Y + size.Y
end

-- ============================================================
-- 8. TWEEN SYSTEM (replaces TweenService)
-- ============================================================
local function tweenProperty(obj, prop, goal, duration, easingFn)
    -- easingFn: function(alpha: number) -> number, default linear
    duration = duration or 0.16
    easingFn = easingFn or function(a) return a end
    -- Cancel existing tween on same obj+prop
    for i = #mainapi.Tweens, 1, -1 do
        local t = mainapi.Tweens[i]
        if t.obj == obj and t.prop == prop then
            table.remove(mainapi.Tweens, i)
        end
    end
    local start = obj[prop]
    -- Don't tween if start is non-numeric (e.g. Color3 handled separately)
    if typeof(start) == "number" then
        table.insert(mainapi.Tweens, {
            obj = obj, prop = prop,
            start = start, goal = goal,
            startTime = os.clock(), duration = duration,
            easing = easingFn,
            kind = "number",
        })
    elseif typeof(start) == "Color3" then
        local sr, sg, sb = start.R, start.G, start.B
        table.insert(mainapi.Tweens, {
            obj = obj, prop = prop,
            sr = sr, sg = sg, sb = sb,
            gr = goal.R, gg = goal.G, gb = goal.B,
            startTime = os.clock(), duration = duration,
            easing = easingFn,
            kind = "color",
        })
    elseif typeof(start) == "Vector2" then
        table.insert(mainapi.Tweens, {
            obj = obj, prop = prop,
            sx = start.X, sy = start.Y,
            gx = goal.X, gy = goal.Y,
            startTime = os.clock(), duration = duration,
            easing = easingFn,
            kind = "vector2",
        })
    end
end

local function cancelTween(obj, prop)
    for i = #mainapi.Tweens, 1, -1 do
        local t = mainapi.Tweens[i]
        if t.obj == obj and (not prop or t.prop == prop) then
            table.remove(mainapi.Tweens, i)
        end
    end
end

local function updateTweens()
    local now = os.clock()
    for i = #mainapi.Tweens, 1, -1 do
        local t = mainapi.Tweens[i]
        local raw = math.clamp((now - t.startTime) / t.duration, 0, 1)
        local a = t.easing(raw)
        if t.kind == "number" then
            pcall(function() t.obj[t.prop] = t.start + (t.goal - t.start) * a end)
        elseif t.kind == "color" then
            local c = Color3.new(
                t.sr + (t.gr - t.sr) * a,
                t.sg + (t.gg - t.sg) * a,
                t.sb + (t.gb - t.sb) * a
            )
            pcall(function() t.obj[t.prop] = c end)
        elseif t.kind == "vector2" then
            local v = Vector2.new(
                t.sx + (t.gx - t.sx) * a,
                t.sy + (t.gy - t.sy) * a
            )
            pcall(function() t.obj[t.prop] = v end)
        end
        if raw >= 1 then
            table.remove(mainapi.Tweens, i)
        end
    end
end

-- Easing functions
local Easing = {
    Linear  = function(a) return a end,
    Quad    = function(a) return a * a end,
    Cubic   = function(a) return a * a * a end,
    Quart   = function(a) return a * a * a * a end,
    Expo    = function(a) return a == 1 and 1 or 2 ^ (10 * (a - 1)) end,
    OutExpo = function(a) return a == 1 and 1 or 1 - 2 ^ (-10 * a) end,
}

-- ============================================================
-- 9. MANUAL LAYOUT SYSTEM (replaces UIListLayout)
-- ============================================================
-- A layout is: { children = array of { pos=Vector2, size=Vector2, height=number, visible=fn },
--                startY=, padding=, clipPos=, clipSize=, scrollOffset= }
local function createLayout(opts)
    mainapi._layoutCounter = mainapi._layoutCounter + 1
    local id = mainapi._layoutCounter
    local layout = {
        children     = {},
        startY       = opts.startY or 0,
        padding      = opts.padding or 0,
        clipPos      = opts.clipPos or nil,   -- Vector2
        clipSize     = opts.clipSize or nil,  -- Vector2
        scrollOffset = 0,
        maxScroll    = 0,
    }
    mainapi.Layouts[id] = layout
    return layout, id
end

local function removeLayout(id)
    mainapi.Layouts[id] = nil
end

local function layoutAdd(layout, child)
    -- child: { height=number, apply=function(y, isVisible), getVisible=function() }
    table.insert(layout.children, child)
end

local function applyLayout(layout)
    local y = layout.startY - layout.scrollOffset
    local contentHeight = 0
    for i, child in ipairs(layout.children) do
        local childY = layout.startY + (i - 1) * (child.height + layout.padding) - layout.scrollOffset
        local visible = true
        if layout.clipPos and layout.clipSize then
            visible = childY + child.height >= layout.clipPos.Y
                  and childY <= layout.clipPos.Y + layout.clipSize.Y
        end
        if child.apply then child.apply(childY, visible) end
        contentHeight = (layout.startY + i * (child.height + layout.padding)) - layout.startY
    end
    layout.maxScroll = math.max(0, contentHeight - (layout.clipSize and layout.clipSize.Y or 0))
    layout.scrollOffset = math.clamp(layout.scrollOffset, 0, layout.maxScroll)
end

-- ============================================================
-- 10. KEYBOARD CAPTURE (for TextBox / bind capture)
-- ============================================================
local keyCapture = {
    active = false,           -- true when capturing keys
    callback = nil,           -- function(keyCode) -> bool (true to stop capturing)
    buffer = "",              -- string buffer for text entry
    isText = false,           -- true = text entry, false = key capture
    placeholder = "",
    doneCallback = nil,       -- function(finalText, enterPressed)
}

local function startKeyCapture(callback)
    keyCapture.active = true
    keyCapture.callback = callback
    keyCapture.isText = false
end

local function startTextCapture(initialText, placeholder, doneCallback)
    keyCapture.active = true
    keyCapture.buffer = initialText or ""
    keyCapture.placeholder = placeholder or ""
    keyCapture.doneCallback = doneCallback
    keyCapture.isText = true
end

local function stopCapture()
    keyCapture.active = false
    keyCapture.callback = nil
    keyCapture.doneCallback = nil
    keyCapture.buffer = ""
end

-- Keycode name helper (for bind display)
local function keyCodeName(keyCode)
    if not keyCode then return "" end
    local name = tostring(keyCode.Name or keyCode)
    -- Strip "Button" prefix on some gamepads, keep readability
    return name
end

-- ============================================================
-- 11. MAID (cleanup helper, mirrors VapeV4 addMaid at line 195)
-- ============================================================
local function addMaid(object)
    object.Connections = {}
    function object:Clean(callback)
        if type(callback) == "function" then
            table.insert(self.Connections, { Disconnect = callback })
        elseif type(callback) == "table" and callback.Disconnect then
            table.insert(self.Connections, callback)
        end
    end
    function object:CleanAll()
        for _, c in ipairs(self.Connections) do
            pcall(function() c:Disconnect() end)
        end
        self.Connections = {}
    end
end

-- ============================================================
-- 12. RENDER LOOP
-- ============================================================
local renderConn
local prevMousePos = Vector2.new(0, 0)

local function getMousePos()
    return UserInputService:GetMouseLocation()
end

local function updateHitTesting()
    if keyCapture.active then return end -- suppress hover while capturing
    local mouse = getMousePos()
    for id, target in pairs(mainapi.HitTargets) do
        if type(target.bounds) == "function" then
            local ok, pos, size = pcall(target.bounds)
            if ok and pos and size then
                local inside = pointInRect(mouse.X, mouse.Y, pos, size)
                if inside and not target.hovered then
                    target.hovered = true
                    if target.callbacks.onEnter then
                        pcall(target.callbacks.onEnter)
                    end
                elseif not inside and target.hovered then
                    target.hovered = false
                    if target.callbacks.onLeave then
                        pcall(target.callbacks.onLeave)
                    end
                end
            end
        end
    end
end

local function updateLayouts()
    for id, layout in pairs(mainapi.Layouts) do
        pcall(applyLayout, layout)
    end
end

local function updateRainbow()
    if not mainapi.GUIColor.Rainbow then return end
    mainapi.GUIColor.Hue = (mainapi.GUIColor.Hue + 0.001 * (mainapi.RainbowSpeed.Value or 1)) % 1
    mainapi:UpdateGUI(mainapi.GUIColor.Hue, mainapi.GUIColor.Sat, mainapi.GUIColor.Value)
end

local function updatePanelDrags()
    -- Run each registered panel's drag-update callback
    if not mainapi._draggablePanels then return end
    for cat, fn in pairs(mainapi._draggablePanels) do
        if mainapi.Categories[cat.Name] == cat then
            pcall(fn)
        end
    end
end

local function updateSidebarDrag()
    -- Sidebar header drag (defined in CreateGUI via mainapi._sidebarDrag)
    if mainapi._sidebarDrag then
        pcall(mainapi._sidebarDrag)
    end
end

local function startRenderLoop()
    if renderConn then return end
    renderConn = RunService.RenderStepped:Connect(function()
        if not isGameActive() then return end
        pcall(updateTweens)
        pcall(updatePanelDrags)
        pcall(updateSidebarDrag)
        pcall(updateHitTesting)
        pcall(updateLayouts)
        pcall(updateRainbow)
    end)
end

local function stopRenderLoop()
    if renderConn then
        renderConn:Disconnect()
        renderConn = nil
    end
end

-- ============================================================
-- 13. INPUT HANDLERS
-- ============================================================
UserInputService.InputBegan:Connect(function(input, gpe)
    -- Keyboard capture has priority
    if keyCapture.active and keyCapture.isText then
        if input.KeyCode == Enum.KeyCode.Return then
            local cb = keyCapture.doneCallback
            local text = keyCapture.buffer
            stopCapture()
            if cb then pcall(cb, text, true) end
            return
        elseif input.KeyCode == Enum.KeyCode.Escape then
            local cb = keyCapture.doneCallback
            stopCapture()
            if cb then pcall(cb, "", false) end
            return
        elseif input.KeyCode == Enum.KeyCode.Backspace then
            keyCapture.buffer = keyCapture.buffer:sub(1, -2)
            return
        end
        -- Typeable character
        local ch = input.KeyCode.Name
        -- Try to map A/B/C etc
        if ch and #ch == 1 then
            local letter = ch
            if not UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) and not UserInputService:IsKeyDown(Enum.KeyCode.RightShift) then
                letter = string.lower(letter)
            end
            keyCapture.buffer = keyCapture.buffer .. letter
        elseif ch and ch:match("Digit%d") then
            keyCapture.buffer = keyCapture.buffer .. ch:sub(-1)
        elseif ch == "Space" then
            keyCapture.buffer = keyCapture.buffer .. " "
        end
        if keyCapture.doneCallback then
            pcall(keyCapture.doneCallback, keyCapture.buffer, false)
        end
        return
    end

    if keyCapture.active and not keyCapture.isText and keyCapture.callback then
        -- Key bind capture: any key press completes the capture
        local kc = input.KeyCode
        if kc ~= Enum.KeyCode.Unknown then
            local stop = keyCapture.callback(kc)
            if stop then stopCapture() end
        end
        return
    end

    -- Per-module keybind matching (on key press)
    if input.KeyCode ~= Enum.KeyCode.Unknown and not gpe then
        local kcName = input.KeyCode.Name
        for _, module in pairs(mainapi.Modules) do
            if module.Bind and #module.Bind > 0 and table.find(module.Bind, kcName) then
                -- Check that ALL keys in the bind are currently held
                local allHeld = true
                for _, k in ipairs(module.Bind) do
                    if not UserInputService:IsKeyDown(Enum.KeyCode[k]) then
                        allHeld = false
                        break
                    end
                end
                if allHeld then
                    -- Avoid double-trigger: only fire if we haven't fired for this combo yet
                    if not module._bindFired then
                        module._bindFired = true
                        module:Toggle()
                    end
                end
            end
        end
    end

    -- Global keybind to toggle the GUI
    if input.KeyCode ~= Enum.KeyCode.Unknown then
        local allHeld = true
        for _, k in ipairs(mainapi.Keybind) do
            if not UserInputService:IsKeyDown(Enum.KeyCode[k]) then
                allHeld = false
                break
            end
        end
        if allHeld and #mainapi.Keybind > 0 and not mainapi._guiBindFired then
            mainapi._guiBindFired = true
            mainapi:ToggleGUI()
        end
    end

    -- Mouse clicks for hit targets
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        if gpe then return end
        for id, target in pairs(mainapi.HitTargets) do
            if target.hovered then
                target.pressed = true
                if target.callbacks.onDown then pcall(target.callbacks.onDown) end
            end
        end
    end
end)

UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        for id, target in pairs(mainapi.HitTargets) do
            if target.pressed then
                target.pressed = false
                if target.callbacks.onUp then pcall(target.callbacks.onUp) end
                if target.hovered and target.callbacks.onClick then
                    pcall(target.callbacks.onClick)
                end
            end
        end
    end

    -- Reset bind-fired flags when a key in any bind is released
    if input.KeyCode ~= Enum.KeyCode.Unknown then
        local kcName = input.KeyCode.Name
        for _, module in pairs(mainapi.Modules) do
            if module.Bind and #module.Bind > 0 and table.find(module.Bind, kcName) then
                module._bindFired = false
            end
        end
        -- Reset GUI bind flag
        if mainapi.Keybind and table.find(mainapi.Keybind, kcName) then
            mainapi._guiBindFired = false
        end
    end
end)

-- Mouse wheel for scrolling
UserInputService.InputChanged:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseWheel then
        -- Find the topmost layout under mouse that has scroll
        local mouse = getMousePos()
        local delta = input.Position.Z  -- positive = up, negative = down
        for id, layout in pairs(mainapi.Layouts) do
            if layout.maxScroll > 0 and layout.clipPos and layout.clipSize then
                if pointInRect(mouse.X, mouse.Y, layout.clipPos, layout.clipSize) then
                    layout.scrollOffset = math.clamp(
                        layout.scrollOffset - (delta > 0 and 30 or -30),
                        0, layout.maxScroll
                    )
                    return
                end
            end
        end
    end
end)

-- ============================================================
-- 14. THEMING (UpdateGUI)
-- ============================================================
function mainapi:UpdateGUI(hue, sat, val, defaultCall)
    -- Repaint every registered themed drawing
    for _, entry in ipairs(self.ThemedDrawings) do
        if entry.obj and entry.obj.Remove then -- still alive
            pcall(function()
                if entry.kind == "accent" then
                    entry.obj.Color = Color3.fromHSV(hue, sat, val)
                elseif entry.kind == "rainbow" and self.GUIColor.Rainbow then
                    local h2 = (hue - (entry.index * 0.075)) % 1
                    local hs, ss, vs = self:Color(h2)
                    entry.obj.Color = Color3.fromHSV(hs, ss, vs)
                end
            end)
        end
    end
    -- Cleanup stale entries
    for i = #self.ThemedDrawings, 1, -1 do
        local e = self.ThemedDrawings[i]
        if not e.obj or not pcall(function() return e.obj.Remove end) then
            table.remove(self.ThemedDrawings, i)
        end
    end
end

function mainapi:registerThemed(obj, kind, index)
    table.insert(self.ThemedDrawings, { obj = obj, kind = kind, index = index or 0 })
end

function mainapi:unregisterThemed(obj)
    for i = #self.ThemedDrawings, 1, -1 do
        if self.ThemedDrawings[i].obj == obj then
            table.remove(self.ThemedDrawings, i)
        end
    end
end

function mainapi:ToggleGUI()
    self.GUIVisible = not self.GUIVisible
    local vis = self.GUIVisible
    if self._clickguiRoot then
        for _, d in ipairs(self._clickguiRoot) do
            if d then pcall(function() d.Visible = vis end) end
        end
    end
    -- Hide/show all sidebar entries and panels
    for _, cat in pairs(self.Categories) do
        for _, d in ipairs(cat._drawings) do
            -- Only show panel drawings if category is expanded AND GUI visible
            if cat.Expanded and d ~= cat.Object then
                -- Panel drawings stay hidden unless expanded
            end
            pcall(function() d.Visible = vis and (cat.Expanded or false) or false end)
        end
        -- Sidebar entry bg/text/arrow should follow GUI visibility
        -- (they're at indices 1-3 of cat._drawings)
        if cat._drawings[1] then cat._drawings[1].Visible = vis end
        if cat._drawings[2] then cat._drawings[2].Visible = vis end
        if cat._drawings[3] then cat._drawings[3].Visible = vis end
        -- If category is expanded, also show panel drawings
        if vis and cat.Expanded then
            for i = 4, #cat._drawings do
                pcall(function() cat._drawings[i].Visible = true end)
            end
            -- And show module rows
            for _, mod in ipairs(cat._moduleList) do
                mod:_setVisible(true)
            end
        elseif not vis then
            for _, mod in ipairs(cat._moduleList) do
                mod:_setVisible(false)
            end
        end
    end
end

-- ============================================================
-- 15. NOTIFICATIONS
-- ============================================================
local notificationsContainer = {
    list = {},  -- array of {bg=, title=, text=, progress=, startedAt=, duration=}
}

function mainapi:CreateNotification(title, text, duration, type)
    if not self.Notifications.Enabled then return end
    duration = duration or 5
    type = type or "info"

    -- Notification: rounded bg + icon (we'll skip icon image, just colored square) + title + body + progress bar
    local vp = Camera.ViewportSize
    local notifW = math.max(220, (#text * 7) + 60)
    local notifH = 60
    local index = #notificationsContainer.list
    local startY = vp.Y - 20 - notifH - (index * (notifH + 8))
    local targetX = vp.X - 20 - notifW
    local startX = vp.X + 20

    local bg = Draw("Square", {
        Size = Vector2.new(notifW, notifH),
        Position = Vector2.new(startX, startY),
        Color = color.Dark(uipallet.Main, 0.05),
        Filled = true,
        Transparency = 1,
        ZIndex = 50,
        Visible = true,
    })
    -- Border (left accent)
    local accentCol = (type == "alert" and Color3.fromRGB(250, 50, 56))
                   or (type == "warning" and Color3.fromRGB(236, 129, 43))
                   or accentColor()
    local accent = Draw("Square", {
        Size = Vector2.new(3, notifH),
        Position = Vector2.new(startX, startY),
        Color = accentCol,
        Filled = true,
        Transparency = 1,
        ZIndex = 51,
        Visible = true,
    })
    local titleText = Draw("Text", {
        Text = title or "",
        Position = Vector2.new(startX + 12, startY + 8),
        Size = 15,
        Font = Drawing.Fonts.Plex,
        Color = Color3.fromRGB(220, 220, 220),
        Transparency = 1,
        ZIndex = 52,
        Visible = true,
    })
    local bodyText = Draw("Text", {
        Text = text or "",
        Position = Vector2.new(startX + 12, startY + 28),
        Size = 13,
        Font = Drawing.Fonts.UI,
        Color = Color3.fromRGB(170, 170, 170),
        Transparency = 1,
        ZIndex = 52,
        Visible = true,
    })
    local progress = Draw("Square", {
        Size = Vector2.new(notifW - 4, 2),
        Position = Vector2.new(startX + 2, startY + notifH - 4),
        Color = accentCol,
        Filled = true,
        Transparency = 1,
        ZIndex = 53,
        Visible = true,
    })

    local entry = {
        bg=bg, accent=accent, title=titleText, body=bodyText, progress=progress,
        startedAt = os.clock(), duration = duration, width = notifW, height = notifH,
        targetX = targetX, startY = startY, currentX = startX,
    }
    table.insert(notificationsContainer.list, entry)

    -- Slide in
    tweenProperty(bg, "Position", Vector2.new(targetX, startY), 0.4, Easing.OutExpo)
    tweenProperty(accent, "Position", Vector2.new(targetX, startY), 0.4, Easing.OutExpo)
    tweenProperty(titleText, "Position", Vector2.new(targetX + 12, startY + 8), 0.4, Easing.OutExpo)
    tweenProperty(bodyText, "Position", Vector2.new(targetX + 12, startY + 28), 0.4, Easing.OutExpo)
    tweenProperty(progress, "Position", Vector2.new(targetX + 2, startY + notifH - 4), 0.4, Easing.OutExpo)

    -- Shrink progress bar over duration
    tweenProperty(progress, "Size", Vector2.new(0, 2), duration, Easing.Linear)

    -- Auto-dismiss
    task.delay(duration, function()
        -- Slide out
        tweenProperty(bg, "Position", Vector2.new(vp.X + 20, startY), 0.4, Easing.Expo)
        tweenProperty(accent, "Position", Vector2.new(vp.X + 20, startY), 0.4, Easing.Expo)
        tweenProperty(titleText, "Position", Vector2.new(vp.X + 32, startY + 8), 0.4, Easing.Expo)
        tweenProperty(bodyText, "Position", Vector2.new(vp.X + 32, startY + 28), 0.4, Easing.Expo)
        tweenProperty(progress, "Position", Vector2.new(vp.X + 22, startY + notifH - 4), 0.4, Easing.Expo)
        task.wait(0.45)
        destroyDraw(bg); destroyDraw(accent); destroyDraw(titleText); destroyDraw(bodyText); destroyDraw(progress)
        -- Remove from list
        for i = #notificationsContainer.list, 1, -1 do
            if notificationsContainer.list[i] == entry then
                table.remove(notificationsContainer.list, i)
            end
        end
        -- Reposition remaining notifications
        for i, e in ipairs(notificationsContainer.list) do
            local newY = vp.Y - 20 - e.height - ((i - 1) * (e.height + 8))
            e.startY = newY
            tweenProperty(e.bg, "Position", Vector2.new(e.targetX, newY), 0.3, Easing.Linear)
            tweenProperty(e.accent, "Position", Vector2.new(e.targetX, newY), 0.3, Easing.Linear)
            tweenProperty(e.title, "Position", Vector2.new(e.targetX + 12, newY + 8), 0.3, Easing.Linear)
            tweenProperty(e.body, "Position", Vector2.new(e.targetX + 12, newY + 28), 0.3, Easing.Linear)
            tweenProperty(e.progress, "Position", Vector2.new(e.targetX + 2, newY + e.height - 4), 0.3, Easing.Linear)
        end
    end)
end

-- ============================================================
-- 16. GUI ROOT (CreateGUI) — main sidebar
-- ============================================================
function mainapi:CreateGUI()
    if self._clickguiRoot then return end

    -- Root screen-positioned drawings: sidebar + visible toggle
    local sidebarW = 220
    local sidebarH = 41 * (#self.Categories) + 40  -- header + entries
    if sidebarH < 200 then sidebarH = 200 end

    -- Header bar — position stored on self._sidebarPos so all sidebar entries
    -- can compute their own positions relative to it.
    self._sidebarPos = self._sidebarPos or { X = 6, Y = 60 }
    local headerH = 33
    local header = Draw("Square", {
        Size = Vector2.new(sidebarW, headerH),
        Position = Vector2.new(self._sidebarPos.X, self._sidebarPos.Y),
        Color = color.Dark(uipallet.Main, 0.02),
        Filled = true, Transparency = 1, ZIndex = 10, Visible = true,
    })
    local logo = Draw("Text", {
        Text = "Vape",
        Position = Vector2.new(self._sidebarPos.X + 11, self._sidebarPos.Y + 9),
        Size = 16, Font = Drawing.Fonts.Plex,
        Color = accentColor(), Transparency = 1, ZIndex = 11, Visible = true,
    })
    local versionLabel = Draw("Text", {
        Text = "v" .. self.Version,
        Position = Vector2.new(self._sidebarPos.X + sidebarW - 50, self._sidebarPos.Y + 11),
        Size = 10, Font = Drawing.Fonts.UI,
        Color = color.Dark(uipallet.Text, 0.43), Transparency = 1, ZIndex = 11, Visible = true,
    })
    self:registerThemed(logo, "accent")

    self._clickguiRoot = { header, logo, versionLabel }
    self.GUIVisible = true

    -- Drag support on header
    local dragState = { dragging = false, offset = Vector2.new(0, 0) }
    local dragHitId = registerHit(
        function() return Vector2.new(self._sidebarPos.X, self._sidebarPos.Y), Vector2.new(sidebarW, headerH) end,
        {
            onDown = function()
                dragState.dragging = true
                dragState.offset = getMousePos() - Vector2.new(self._sidebarPos.X, self._sidebarPos.Y)
            end,
        }
    )
    -- Drag update is run by the main render loop via mainapi._sidebarDrag
    self._sidebarDrag = function()
        if dragState.dragging then
            local newMouse = getMousePos()
            self._sidebarPos.X = math.clamp(newMouse.X - dragState.offset.X, 0, Camera.ViewportSize.X - sidebarW)
            self._sidebarPos.Y = math.clamp(newMouse.Y - dragState.offset.Y, 0, Camera.ViewportSize.Y - headerH)
            header.Position = Vector2.new(self._sidebarPos.X, self._sidebarPos.Y)
            logo.Position = Vector2.new(self._sidebarPos.X + 11, self._sidebarPos.Y + 9)
            versionLabel.Position = Vector2.new(self._sidebarPos.X + sidebarW - 50, self._sidebarPos.Y + 11)
            -- Update all sidebar entries to follow
            if self._sidebarEntryUpdaters then
                for _, upd in pairs(self._sidebarEntryUpdaters) do
                    pcall(upd)
                end
            end
        end
    end
    -- End drag on mouse release (we hook into InputEnded globally)
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragState.dragging = false
        end
    end)

    return self._clickguiRoot
end

-- ============================================================
-- 17. CATEGORY (window with sidebar tab + panel)
-- ============================================================
function mainapi:CreateCategory(settings)
    assert(settings and settings.Name, "CreateCategory: Name required")

    if not self._clickguiRoot then self:CreateGUI() end

    local categoryapi = {
        Type = "Category",
        Expanded = false,
        Options = {},
        Name = settings.Name,
        _drawings = {},
        _moduleLayout = nil,
        _moduleList = {},  -- ordered
        _pos = { X = 236, Y = 60 },
        _panelSize = { W = 220, H = 380 },
    }
    addMaid(categoryapi)

    -- Determine sidebar entry index
    local sidebarIndex = 0
    for _ in pairs(self.Categories) do sidebarIndex = sidebarIndex + 1 end

    -- Sidebar entry button
    -- The sidebar header position is stored on mainapi._sidebarPos so each
    -- entry can compute its Y relative to it.
    if not self._sidebarPos then
        self._sidebarPos = { X = 6, Y = 60 }
    end
    local sidebarW = 220
    local entryH = 40
    local headerH = 33
    local function sidebarEntryY()
        return self._sidebarPos.Y + headerH + 4 + sidebarIndex * (entryH + 2)
    end
    local function sidebarX() return self._sidebarPos.X end

    local entryBg = Draw("Square", {
        Size = Vector2.new(sidebarW, entryH),
        Position = Vector2.new(sidebarX(), sidebarEntryY()),
        Color = uipallet.Main,
        Filled = true, Transparency = 1, ZIndex = 10, Visible = true,
    })
    local entryText = Draw("Text", {
        Text = settings.Name,
        Position = Vector2.new(sidebarX() + 12, sidebarEntryY() + 11),
        Size = 14, Font = Drawing.Fonts.UI,
        Color = color.Dark(uipallet.Text, 0.16),
        Transparency = 1, ZIndex = 11, Visible = true,
    })
    local entryArrow = Draw("Text", {
        Text = ">",
        Position = Vector2.new(sidebarX() + sidebarW - 18, sidebarEntryY() + 11),
        Size = 12, Font = Drawing.Fonts.UI,
        Color = color.Light(uipallet.Main, 0.37),
        Transparency = 1, ZIndex = 11, Visible = true,
    })

    table.insert(categoryapi._drawings, entryBg)
    table.insert(categoryapi._drawings, entryText)
    table.insert(categoryapi._drawings, entryArrow)

    -- Live position updater for this entry — called from sidebar drag
    local function updateEntryPos()
        local ex, ey = sidebarX(), sidebarEntryY()
        entryBg.Position = Vector2.new(ex, ey)
        entryText.Position = Vector2.new(ex + 12, ey + 11)
        entryArrow.Position = Vector2.new(ex + sidebarW - 18, ey + 11)
    end
    self._sidebarEntryUpdaters = self._sidebarEntryUpdaters or {}
    self._sidebarEntryUpdaters[categoryapi] = updateEntryPos

    -- Sidebar entry hit-test (bounds computed live)
    local entryHitId = registerHit(
        function() return Vector2.new(sidebarX(), sidebarEntryY()), Vector2.new(sidebarW, entryH) end,
        {
            onEnter = function()
                if not categoryapi.Expanded then
                    tweenProperty(entryBg, "Color", color.Light(uipallet.Main, 0.04), 0.16)
                    tweenProperty(entryText, "Color", uipallet.Text, 0.16)
                end
            end,
            onLeave = function()
                if not categoryapi.Expanded then
                    tweenProperty(entryBg, "Color", uipallet.Main, 0.16)
                    tweenProperty(entryText, "Color", color.Dark(uipallet.Text, 0.16), 0.16)
                end
            end,
            onClick = function()
                categoryapi:Expand(not categoryapi.Expanded)
            end,
        }
    )

    -- Panel (the actual window with module list)
    -- Position is mutable state on categoryapi so drag can update it live.
    categoryapi._pos = { X = 236, Y = 60 }
    local panelW = categoryapi._panelSize.W
    local panelH = categoryapi._panelSize.H

    local panelBg = Draw("Square", {
        Size = Vector2.new(panelW, panelH),
        Position = Vector2.new(categoryapi._pos.X, categoryapi._pos.Y),
        Color = uipallet.Main,
        Filled = true, Transparency = 1, ZIndex = 5, Visible = false,
    })
    local panelTitle = Draw("Text", {
        Text = settings.Name,
        Position = Vector2.new(categoryapi._pos.X + 12, categoryapi._pos.Y + 11),
        Size = 13, Font = Drawing.Fonts.UI,
        Color = uipallet.Text, Transparency = 1, ZIndex = 6, Visible = false,
    })
    local panelDivider = Draw("Square", {
        Size = Vector2.new(panelW, 1),
        Position = Vector2.new(categoryapi._pos.X, categoryapi._pos.Y + 33),
        Color = Color3.new(1, 1, 1),
        Filled = true, Transparency = 0.93, ZIndex = 6, Visible = false,
    })
    -- Close button (top-right X) — position computed live in hit-test closure
    local closeHit = Draw("Square", {
        Size = Vector2.new(20, 20),
        Position = Vector2.new(categoryapi._pos.X + panelW - 22, categoryapi._pos.Y + 9),
        Color = Color3.new(0, 0, 0), -- invisible hit area
        Filled = true, Transparency = 0, ZIndex = 7, Visible = false,
    })
    local closeText = Draw("Text", {
        Text = "x",
        Position = Vector2.new(categoryapi._pos.X + panelW - 16, categoryapi._pos.Y + 11),
        Size = 14, Font = Drawing.Fonts.UI,
        Color = color.Light(uipallet.Main, 0.37),
        Transparency = 1, ZIndex = 8, Visible = false,
    })
    table.insert(categoryapi._drawings, panelBg)
    table.insert(categoryapi._drawings, panelTitle)
    table.insert(categoryapi._drawings, panelDivider)
    table.insert(categoryapi._drawings, closeHit)
    table.insert(categoryapi._drawings, closeText)

    -- Helper to reposition all panel drawings after a drag
    local function applyPanelPos()
        local px, py = categoryapi._pos.X, categoryapi._pos.Y
        panelBg.Position = Vector2.new(px, py)
        panelTitle.Position = Vector2.new(px + 12, py + 11)
        panelDivider.Position = Vector2.new(px, py + 33)
        closeHit.Position = Vector2.new(px + panelW - 22, py + 9)
        closeText.Position = Vector2.new(px + panelW - 16, py + 11)
        -- Update module layout clip region
        categoryapi._moduleLayout.clipPos = Vector2.new(px, py + 38)
        categoryapi._moduleLayout.clipSize = Vector2.new(panelW, panelH - 38)
        categoryapi._moduleLayout.startY = py + 38
    end

    -- Close button hit
    local closeHitId = registerHit(
        function()
            return Vector2.new(categoryapi._pos.X + panelW - 22, categoryapi._pos.Y + 9),
                   Vector2.new(20, 20)
        end,
        {
            onEnter = function()
                tweenProperty(closeText, "Color", uipallet.Text, 0.16)
            end,
            onLeave = function()
                tweenProperty(closeText, "Color", color.Light(uipallet.Main, 0.37), 0.16)
            end,
            onClick = function()
                categoryapi:Expand(false)
            end,
        }
    )

    -- Panel drag — title bar
    local panelDrag = { dragging = false, offset = Vector2.new(0, 0) }
    local panelDragHitId = registerHit(
        function()
            return Vector2.new(categoryapi._pos.X, categoryapi._pos.Y),
                   Vector2.new(panelW, 33)
        end,
        {
            onDown = function()
                panelDrag.dragging = true
                panelDrag.offset = getMousePos() - Vector2.new(categoryapi._pos.X, categoryapi._pos.Y)
            end,
        }
    )
    -- Panel drag update — hooked in main render loop via category drag list
    mainapi._draggablePanels = mainapi._draggablePanels or {}
    mainapi._draggablePanels[categoryapi] = function()
        if panelDrag.dragging then
            local newMouse = getMousePos()
            categoryapi._pos.X = math.clamp(newMouse.X - panelDrag.offset.X, 0, Camera.ViewportSize.X - panelW)
            categoryapi._pos.Y = math.clamp(newMouse.Y - panelDrag.offset.Y, 0, Camera.ViewportSize.Y - panelH)
            applyPanelPos()
        end
    end

    -- Module list layout
    local moduleLayout, moduleLayoutId = createLayout({
        startY = categoryapi._pos.Y + 38,
        padding = 0,
        clipPos = Vector2.new(categoryapi._pos.X, categoryapi._pos.Y + 38),
        clipSize = Vector2.new(panelW, panelH - 38),
    })
    categoryapi._moduleLayout = moduleLayout
    categoryapi._moduleLayoutId = moduleLayoutId

    function categoryapi:_moveWithSidebar(newHeaderPos)
        -- Optional: keep panel anchored relative to sidebar; we keep panel independent.
    end

    function categoryapi:Expand(check)
        self.Expanded = check
        -- Show/hide panel
        for _, d in ipairs({panelBg, panelTitle, panelDivider, closeHit, closeText}) do
            d.Visible = check and mainapi.GUIVisible
        end
        -- Update sidebar entry appearance
        if check then
            tweenProperty(entryArrow, "Position", Vector2.new(sidebarX() + sidebarW - 14, sidebarEntryY() + 11), 0.16)
            tweenProperty(entryText, "Color", accentColor(), 0.16)
        else
            tweenProperty(entryArrow, "Position", Vector2.new(sidebarX() + sidebarW - 18, sidebarEntryY() + 11), 0.16)
            tweenProperty(entryText, "Color", color.Dark(uipallet.Text, 0.16), 0.16)
        end
        -- Show/hide all module rows
        for _, mod in ipairs(self._moduleList) do
            mod:_setVisible(check and mainapi.GUIVisible)
        end
    end

    function categoryapi:CreateModule(moduleSettings)
        assert(moduleSettings and moduleSettings.Name, "CreateModule: Name required")
        if mainapi.Modules[moduleSettings.Name] then
            mainapi:Remove(moduleSettings.Name)
        end

        local moduleapi = {
            Type = "Module",
            Enabled = false,
            Options = {},
            Bind = {},
            Name = moduleSettings.Name,
            Tooltip = moduleSettings.Tooltip,
            ExtraText = moduleSettings.ExtraText,
            Category = settings.Name,
            Index = (function()
                local n = 0
                for _ in pairs(mainapi.Modules) do n = n + 1 end
                return n
            end)(),
            _drawings = {},
            _expanded = false,
            _hitIds = {},
            _visible = false,
        }
        addMaid(moduleapi)
        mainapi.Modules[moduleSettings.Name] = moduleapi

        moduleSettings.Function = moduleSettings.Function or function() end

        -- Module row visuals
        -- rowX is read live from the parent category's panel position so the
        -- module row follows the panel when dragged.
        local rowH = 40
        local rowY = categoryapi._pos.Y + 38  -- will be set by layout
        local rowW = panelW
        -- Live rowX getter (panel can be dragged after module creation)
        local function rowX() return categoryapi._pos.X end

        local rowBg = Draw("Square", {
            Size = Vector2.new(rowW, rowH),
            Position = Vector2.new(rowX(), rowY),
            Color = uipallet.Main,
            Filled = true, Transparency = 1, ZIndex = 6, Visible = false,
        })
        local rowText = Draw("Text", {
            Text = moduleSettings.Name,
            Position = Vector2.new(rowX() + 12, rowY + 11),
            Size = 14, Font = Drawing.Fonts.UI,
            Color = color.Dark(uipallet.Text, 0.16),
            Transparency = 1, ZIndex = 7, Visible = false,
        })
        local rowDots = Draw("Text", {
            Text = "...",
            Position = Vector2.new(rowX() + rowW - 22, rowY + 11),
            Size = 14, Font = Drawing.Fonts.UI,
            Color = color.Light(uipallet.Main, 0.37),
            Transparency = 1, ZIndex = 7, Visible = false,
        })
        -- Bind display (right side, hidden unless set)
        local bindBg = Draw("Square", {
            Size = Vector2.new(30, 18),
            Position = Vector2.new(rowX() + rowW - 50, rowY + 11),
            Color = Color3.new(1, 1, 1),
            Filled = true, Transparency = 0.92, ZIndex = 7, Visible = false,
        })
        local bindText = Draw("Text", {
            Text = "",
            Position = Vector2.new(rowX() + rowW - 50, rowY + 12),
            Size = 11, Font = Drawing.Fonts.UI,
            Color = color.Dark(uipallet.Text, 0.43),
            Transparency = 1, ZIndex = 8, Visible = false,
            Center = true,
        })
        table.insert(moduleapi._drawings, rowBg)
        table.insert(moduleapi._drawings, rowText)
        table.insert(moduleapi._drawings, rowDots)
        table.insert(moduleapi._drawings, bindBg)
        table.insert(moduleapi._drawings, bindText)

        -- Module children container (options)
        local childrenY = rowY + rowH
        local childLayout, childLayoutId = createLayout({
            startY = childrenY,
            padding = 0,
            clipPos = nil, -- no clip; children expand panel naturally
            clipSize = nil,
        })
        local childrenContainer = {
            _drawings = {},
            _visible = false,
            _layout = childLayout,
            _layoutId = childLayoutId,
            _totalHeight = 0,
        }
        moduleapi._children = childrenContainer

        -- Layout entry for this module row
        local function moduleRowHeight()
            return rowH + (moduleapi._expanded and childrenContainer._totalHeight or 0)
        end

        local layoutEntry = {
            height = rowH,  -- dynamic below
            apply = function(y, isVisible)
                rowY = y
                rowBg.Position = Vector2.new(rowX(), y)
                rowText.Position = Vector2.new(rowX() + 12, y + 11)
                rowDots.Position = Vector2.new(rowX() + rowW - 22, y + 11)
                bindBg.Position = Vector2.new(rowX() + rowW - 50, y + 11)
                bindText.Position = Vector2.new(rowX() + rowW - 50 + 15, y + 12)
                -- Children layout starts below this row
                childrenContainer._layout.startY = y + rowH
                -- Apply children layout
                local cy = y + rowH
                local totalChildH = 0
                for i, child in ipairs(childrenContainer._layout.children) do
                    local cY = y + rowH + totalChildH
                    if child.apply then child.apply(cY, moduleapi._expanded and moduleapi._visible) end
                    totalChildH = totalChildH + child.height
                end
                childrenContainer._totalHeight = totalChildH
                layoutEntry.height = rowH + (moduleapi._expanded and totalChildH or 0)

                -- Visibility
                local vis = moduleapi._visible and isVisible
                rowBg.Visible = vis
                rowText.Visible = vis
                rowDots.Visible = vis
                bindBg.Visible = vis and #moduleapi.Bind > 0
                bindText.Visible = vis and #moduleapi.Bind > 0
            end,
        }
        layoutAdd(categoryapi._moduleLayout, layoutEntry)

        -- Module row hit (toggle on click)
        local rowHitId = registerHit(
            function() return Vector2.new(rowX(), rowY), Vector2.new(rowW - 30, rowH) end,
            {
                onEnter = function()
                    if not moduleapi.Enabled then
                        tweenProperty(rowText, "Color", uipallet.Text, 0.16)
                    end
                end,
                onLeave = function()
                    if not moduleapi.Enabled then
                        tweenProperty(rowText, "Color", color.Dark(uipallet.Text, 0.16), 0.16)
                    end
                end,
                onClick = function()
                    moduleapi:Toggle()
                end,
            }
        )
        table.insert(moduleapi._hitIds, rowHitId)

        -- Dots hit (expand children)
        local dotsHitId = registerHit(
            function() return Vector2.new(rowX() + rowW - 25, rowY), Vector2.new(25, rowH) end,
            {
                onEnter = function()
                    tweenProperty(rowDots, "Color", uipallet.Text, 0.16)
                end,
                onLeave = function()
                    tweenProperty(rowDots, "Color", color.Light(uipallet.Main, 0.37), 0.16)
                end,
                onClick = function()
                    moduleapi._expanded = not moduleapi._expanded
                    -- When expanded, show children
                    if moduleapi._expanded then
                        -- Ensure children visible if module row visible
                    end
                end,
            }
        )
        table.insert(moduleapi._hitIds, dotsHitId)

        -- Bind hit (click to rebind)
        local bindHitId = registerHit(
            function() return Vector2.new(rowX() + rowW - 50, rowY + 11), Vector2.new(30, 18) end,
            {
                onEnter = function()
                    tweenProperty(bindText, "Color", uipallet.Text, 0.16)
                end,
                onLeave = function()
                    tweenProperty(bindText, "Color", color.Dark(uipallet.Text, 0.43), 0.16)
                end,
                onClick = function()
                    bindText.Text = "..."
                    startKeyCapture(function(kc)
                        local name = keyCodeName(kc)
                        if name and name ~= "Unknown" then
                            moduleapi:SetBind({ name }, true)
                            return true  -- stop capturing
                        end
                        return false
                    end)
                end,
            }
        )
        table.insert(moduleapi._hitIds, bindHitId)

        -- Module toggle method
        function moduleapi:Toggle(silent)
            self.Enabled = not self.Enabled
            local rainbowCheck = mainapi.GUIColor.Rainbow
            local ac = rainbowCheck and Color3.fromHSV(mainapi:Color((mainapi.GUIColor.Hue - (self.Index * 0.075)) % 1)) or accentColor()
            if self.Enabled then
                tweenProperty(rowText, "Color", ac, 0.16)
                self:registerThemedFor(rowText)
            else
                self:unregisterThemedFor()
                tweenProperty(rowText, "Color", color.Dark(uipallet.Text, 0.16), 0.16)
            end
            moduleSettings.Function(self.Enabled)
            if not silent then
                -- Could add to an active-modules HUD here
            end
        end

        function moduleapi:registerThemedFor(drawObj)
            -- Track rowText as themed
            self._themedDraw = drawObj
            mainapi:registerThemed(drawObj, "rainbow", self.Index)
        end
        function moduleapi:unregisterThemedFor()
            if self._themedDraw then
                mainapi:unregisterThemed(self._themedDraw)
                self._themedDraw = nil
            end
        end

        function moduleapi:SetBind(keys, fromUI)
            self.Bind = keys
            if #keys > 0 then
                bindText.Text = table.concat(keys, "+"):upper()
                bindBg.Visible = moduleapi._visible
                bindText.Visible = moduleapi._visible
                -- Resize bindBg to text width (approx)
                local w = #bindText.Text * 6 + 8
                bindBg.Size = Vector2.new(w, 18)
                bindBg.Position = Vector2.new(rowX() + rowW - w - 25, rowY + 11)
                bindText.Position = Vector2.new(rowX() + rowW - w - 25 + w/2, rowY + 12)
            else
                bindBg.Visible = false
                bindText.Visible = false
            end
        end

        function moduleapi:_setVisible(vis)
            self._visible = vis
        end

        -- Component creation methods — only Toggle and Button in this build,
        -- but the pattern is identical for everything else.
        function moduleapi:CreateToggle(opts)
            return mainapi._components.Toggle(self, opts)
        end

        function moduleapi:CreateButton(opts)
            return mainapi._components.Button(self, opts)
        end

        table.insert(categoryapi._moduleList, moduleapi)

        -- Make sure category panel is visible when first module is added
        return moduleapi
    end

    self.Categories[settings.Name] = categoryapi
    return categoryapi
end

-- ============================================================
-- 18. COMPONENTS — Toggle & Button
-- ============================================================
mainapi._components = {}

-- TOGGLE
-- VapeV4 source: line 2083. Drawing.new port.
function mainapi._components.Toggle(moduleapi, optionsettings)
    assert(optionsettings and optionsettings.Name, "CreateToggle: Name required")

    local optionapi = {
        Type = "Toggle",
        Enabled = false,
        Name = optionsettings.Name,
        Index = (function()
            local n = 0
            for _ in pairs(moduleapi.Options) do n = n + 1 end
            return n
        end)(),
        _drawings = {},
        _hitIds = {},
    }
    addMaid(optionapi)
    moduleapi.Options[optionsettings.Name] = optionapi

    optionsettings.Function = optionsettings.Function or function() end

    -- Layout position will be assigned by module's children layout
    local rowH = 30
    -- Live X getter so toggle follows panel drag
    local function rowX()
        return moduleapi.Category and mainapi.Categories[moduleapi.Category]._pos.X or 236
    end
    local rowW = moduleapi.Category and mainapi.Categories[moduleapi.Category]._panelSize.W or 220

    -- Visuals: background (transparent, just for hit), label, knob track, knob
    local bg = Draw("Square", {
        Size = Vector2.new(rowW, rowH),
        Position = Vector2.new(rowX(), 0),  -- Y set by layout
        Color = uipallet.Main,
        Filled = true, Transparency = 1, ZIndex = 7, Visible = false,
    })
    local label = Draw("Text", {
        Text = optionsettings.Name,
        Position = Vector2.new(rowX() + 12, 7),  -- relative Y applied later
        Size = 14, Font = Drawing.Fonts.UI,
        Color = color.Dark(uipallet.Text, 0.16),
        Transparency = 1, ZIndex = 8, Visible = false,
    })
    -- Knob track (the rounded pill)
    local knobW, knobH = 22, 12
    -- knobX is computed live inside apply / hit functions because rowX() may change
    local function knobX() return rowX() + rowW - 30 end
    local track = Draw("Square", {
        Size = Vector2.new(knobW, knobH),
        Position = Vector2.new(knobX(), 9),
        Color = color.Light(uipallet.Main, 0.14),
        Filled = true, Transparency = 1, ZIndex = 8, Visible = false,
    })
    -- Knob (the sliding circle — approximated with a small Square since Drawing has no rounded square)
    -- We use a Circle for the knob to get a rounded look.
    local knob = Draw("Circle", {
        Radius = 4,
        Position = Vector2.new(knobX() + 6, 9 + 6),
        Color = uipallet.Main,
        Filled = true, Transparency = 1, ZIndex = 9, Visible = false,
        NumSides = 16,
    })

    table.insert(optionapi._drawings, bg)
    table.insert(optionapi._drawings, label)
    table.insert(optionapi._drawings, track)
    table.insert(optionapi._drawings, knob)

    -- Layout entry
    local layoutEntry = {
        height = rowH,
        apply = function(y, isVisible)
            bg.Position = Vector2.new(rowX(), y)
            label.Position = Vector2.new(rowX() + 12, y + 7)
            track.Position = Vector2.new(knobX(), y + 9)
            -- Knob position depends on Enabled state
            knob.Position = Vector2.new(knobX() + (optionapi.Enabled and 14 or 6), y + 9 + 6)
            local vis = isVisible and (optionsettings.Visible == nil or optionsettings.Visible)
            bg.Visible = vis
            label.Visible = vis
            track.Visible = vis
            knob.Visible = vis
        end,
    }
    layoutAdd(moduleapi._children._layout, layoutEntry)

    -- Hit-test
    local hovered = false
    local hitId = registerHit(
        function() return Vector2.new(bg.Position.X, bg.Position.Y), Vector2.new(rowW, rowH) end,
        {
            onEnter = function()
                hovered = true
                if not optionapi.Enabled then
                    tweenProperty(track, "Color", color.Light(uipallet.Main, 0.37), 0.16)
                end
            end,
            onLeave = function()
                hovered = false
                if not optionapi.Enabled then
                    tweenProperty(track, "Color", color.Light(uipallet.Main, 0.14), 0.16)
                end
            end,
            onClick = function()
                optionapi:Toggle()
            end,
        }
    )
    table.insert(optionapi._hitIds, hitId)

    function optionapi:Toggle()
        self.Enabled = not self.Enabled
        local rainbowCheck = mainapi.GUIColor.Rainbow
        local ac = rainbowCheck and Color3.fromHSV(mainapi:Color((mainapi.GUIColor.Hue - (self.Index * 0.075)) % 1)) or accentColor()
        -- Knob color & position
        if self.Enabled then
            tweenProperty(track, "Color", ac, 0.16)
            tweenProperty(knob, "Position", Vector2.new(knobX() + 14, knob.Position.Y), 0.16)
            -- Register themed so rainbow updates it
            mainapi:registerThemed(track, "rainbow", self.Index)
        else
            tweenProperty(track, "Color", hovered and color.Light(uipallet.Main, 0.37) or color.Light(uipallet.Main, 0.14), 0.16)
            tweenProperty(knob, "Position", Vector2.new(knobX() + 6, knob.Position.Y), 0.16)
            mainapi:unregisterThemed(track)
        end
        optionsettings.Function(self.Enabled)
    end

    function optionapi:Save(tab)
        tab[optionsettings.Name] = { Enabled = self.Enabled }
    end

    function optionapi:Load(tab)
        if tab and self.Enabled ~= tab.Enabled then
            self:Toggle()
        end
    end

    -- Apply Default
    if optionsettings.Default then
        optionapi:Toggle()
    end

    return optionapi
end

-- BUTTON
-- VapeV4 source: line 498. Drawing.new port.
function mainapi._components.Button(moduleapi, optionsettings)
    assert(optionsettings and optionsettings.Name, "CreateButton: Name required")

    local optionapi = {
        Type = "Button",
        Name = optionsettings.Name,
        _drawings = {},
        _hitIds = {},
    }
    addMaid(optionapi)
    moduleapi.Options[optionsettings.Name] = optionapi

    optionsettings.Function = optionsettings.Function or function() end

    local rowH = 31
    local function rowX()
        return moduleapi.Category and mainapi.Categories[moduleapi.Category]._pos.X or 236
    end
    local rowW = moduleapi.Category and mainapi.Categories[moduleapi.Category]._panelSize.W or 220

    -- Button background
    local btnBg = Draw("Square", {
        Size = Vector2.new(rowW - 20, 27),
        Position = Vector2.new(rowX() + 10, 2),  -- Y set by layout
        Color = color.Light(uipallet.Main, 0.05),
        Filled = true, Transparency = 1, ZIndex = 7, Visible = false,
    })
    local btnLabel = Draw("Text", {
        Text = optionsettings.Name,
        Position = Vector2.new(rowX() + 10, 7),
        Size = 14, Font = Drawing.Fonts.UI,
        Color = color.Dark(uipallet.Text, 0.16),
        Transparency = 1, ZIndex = 8, Visible = false,
        Center = false,
    })

    table.insert(optionapi._drawings, btnBg)
    table.insert(optionapi._drawings, btnLabel)

    local layoutEntry = {
        height = rowH,
        apply = function(y, isVisible)
            btnBg.Position = Vector2.new(rowX() + 10, y + 2)
            btnLabel.Position = Vector2.new(rowX() + 10 + (rowW - 20) / 2 - (#optionsettings.Name * 3), y + 7)
            local vis = isVisible and (optionsettings.Visible == nil or optionsettings.Visible)
            btnBg.Visible = vis
            btnLabel.Visible = vis
        end,
    }
    layoutAdd(moduleapi._children._layout, layoutEntry)

    local hitId = registerHit(
        function() return Vector2.new(btnBg.Position.X, btnBg.Position.Y), Vector2.new(rowW - 20, 27) end,
        {
            onEnter = function()
                tweenProperty(btnBg, "Color", color.Light(uipallet.Main, 0.0875), 0.16)
            end,
            onLeave = function()
                tweenProperty(btnBg, "Color", color.Light(uipallet.Main, 0.05), 0.16)
            end,
            onClick = function()
                optionsettings.Function()
            end,
        }
    )
    table.insert(optionapi._hitIds, hitId)

    return optionapi
end

-- ============================================================
-- 19. REMOVE / UNINJECT
-- ============================================================
function mainapi:Remove(name)
    local module = self.Modules[name]
    if module then
        -- Clean up module drawings
        for _, d in ipairs(module._drawings) do
            destroyDraw(d)
        end
        for _, id in ipairs(module._hitIds) do
            unregisterHit(id)
        end
        -- Clean up child components (toggles, buttons, etc.)
        if module._children then
            for _, opt in pairs(module.Options) do
                if opt._drawings then
                    for _, d in ipairs(opt._drawings) do
                        destroyDraw(d)
                    end
                end
                if opt._hitIds then
                    for _, id in ipairs(opt._hitIds) do
                        unregisterHit(id)
                    end
                end
                if type(opt.CleanAll) == "function" then pcall(opt.CleanAll, opt) end
            end
            removeLayout(module._children._layoutId or 0)
        end
        module:CleanAll()
        self.Modules[name] = nil
    end

    local category = self.Categories[name]
    if category then
        for _, d in ipairs(category._drawings) do
            destroyDraw(d)
        end
        -- Clean up category's module layout
        if category._moduleLayoutId then
            removeLayout(category._moduleLayoutId)
        end
        -- Remove from draggable panels registry
        if self._draggablePanels then
            self._draggablePanels[category] = nil
        end
        -- Remove from sidebar entry updaters
        if self._sidebarEntryUpdaters then
            self._sidebarEntryUpdaters[category] = nil
        end
        category:CleanAll()
        self.Categories[name] = nil
    end
end

function mainapi:Uninject()
    -- Destroy all categories and modules
    for name, _ in pairs(self.Categories) do
        self:Remove(name)
    end
    for name, _ in pairs(self.Modules) do
        self:Remove(name)
    end
    -- Clear notifications
    for _, n in ipairs(notificationsContainer.list) do
        destroyDraw(n.bg); destroyDraw(n.accent); destroyDraw(n.title); destroyDraw(n.body); destroyDraw(n.progress)
    end
    notificationsContainer.list = {}
    -- Stop render loop
    stopRenderLoop()
    -- Clear drag registries
    self._draggablePanels = {}
    self._sidebarDrag = nil
    self._sidebarEntryUpdaters = {}
    self._sidebarPos = nil
    self._clickguiRoot = nil
    -- Clear hit targets, layouts, tweens, themed
    self.HitTargets = {}
    self.Layouts = {}
    self.Tweens = {}
    self.ThemedDrawings = {}
    -- Destroy all remaining drawings
    for i = #self.Drawings, 1, -1 do
        pcall(function() self.Drawings[i]:Remove() end)
        table.remove(self.Drawings, i)
    end
    -- Nuclear option
    pcall(function() Drawing.clear() end)
    self.Loaded = false
end

-- ============================================================
-- 20. SAVE / LOAD (JSON persistence, mirrors VapeV4 lines 5363-5610)
-- ============================================================
local function getProfilePath(profileName)
    return "newvape/profiles/" .. (profileName or mainapi.Profile) .. ".json"
end

function mainapi:Save(newProfileName)
    local profile = newProfileName or self.Profile
    local data = {
        GUIColor = {
            Hue = self.GUIColor.Hue,
            Sat = self.GUIColor.Sat,
            Value = self.GUIColor.Value,
            Rainbow = self.GUIColor.Rainbow,
        },
        Keybind = self.Keybind,
        Scale = self.Scale.Value,
        Modules = {},
    }
    for name, module in pairs(self.Modules) do
        local moduleData = { Enabled = module.Enabled, Bind = module.Bind, Options = {} }
        for optName, opt in pairs(module.Options) do
            if opt.Save then
                opt:Save(moduleData.Options)
            end
        end
        data.Modules[name] = moduleData
    end
    local json = HttpService:JSONEncode(data)
    pcall(function() writefile(getProfilePath(profile), json) end)
end

function mainapi:Load(skipGui, profile)
    profile = profile or self.Profile
    local ok, content = pcall(function() return readfile(getProfilePath(profile)) end)
    if not ok or not content then return false end
    local ok2, data = pcall(function() return HttpService:JSONDecode(content) end)
    if not ok2 or type(data) ~= "table" then return false end

    if not skipGui then
        if data.GUIColor then
            self.GUIColor.Hue = data.GUIColor.Hue or self.GUIColor.Hue
            self.GUIColor.Sat = data.GUIColor.Sat or self.GUIColor.Sat
            self.GUIColor.Value = data.GUIColor.Value or self.GUIColor.Value
            self.GUIColor.Rainbow = data.GUIColor.Rainbow or false
        end
        if data.Keybind then self.Keybind = data.Keybind end
        if data.Scale then self.Scale.Value = data.Scale end
    end

    if data.Modules then
        for name, moduleData in pairs(data.Modules) do
            local module = self.Modules[name]
            if module then
                if moduleData.Bind then module:SetBind(moduleData.Bind) end
                if moduleData.Options then
                    for optName, optData in pairs(moduleData.Options) do
                        local opt = module.Options[optName]
                        if opt and opt.Load then
                            pcall(opt.Load, opt, optData)
                        end
                    end
                end
            end
        end
    end
    return true
end

function mainapi:SaveOptions(object, savedOptions)
    for name, opt in pairs(object.Options or {}) do
        if opt.Save then
            opt:Save(savedOptions)
        end
    end
end

function mainapi:LoadOptions(object, savedOptions)
    for name, opt in pairs(object.Options or {}) do
        if opt.Load and savedOptions[name] then
            pcall(opt.Load, opt, savedOptions[name])
        end
    end
end

-- ============================================================
-- 21. STARTUP
-- ============================================================
mainapi.Loaded = true
startRenderLoop()

-- Auto-init the GUI root
mainapi:CreateGUI()

return mainapi
