--[[
╔══════════════════════════════════════════════════════════════════╗
║             ULTIMATE DRAW LIB  (UDL)  v1.0                      ║
║       Pure Drawing-API UI Library · Roblox Script Executors      ║
╠══════════════════════════════════════════════════════════════════╣
║  NO Roblox Instances · Low detectability · Full render loop      ║
╠══════════════════════════════════════════════════════════════════╣
║  Features:                                                       ║
║   Window │ Drag │ Minimize │ Close │ Multi-Tab │ Scroll          ║
║   Toggle │ Button │ Slider │ Dropdown │ KeyBind │ TextBox        ║
║   Label  │ Separator │ Notifications │ Watermark │ Theme         ║
╠══════════════════════════════════════════════════════════════════╣
║  Quick Start:                                                    ║
║    local UDL  = loadstring(...)()                                ║
║    local win  = UDL:Window({Title="My UI",Key=Enum.KeyCode.Insert}) ║
║    local tab  = win:Tab("Main")                                  ║
║    local sec  = tab:Section("Combat")                            ║
║    local tog  = sec:Toggle({Label="Aimbot",Callback=function(v)end}) ║
║    sec:Button({Label="Trigger",Callback=function()end})          ║
║    sec:Slider({Label="FOV",Min=0,Max=360,Default=90,Callback=fn}) ║
║    sec:Dropdown({Label="Team",Options={"Red","Blue"},Callback=fn}) ║
║    sec:KeyBind({Label="Toggle",Default=Enum.KeyCode.F,Callback=fn}) ║
║    sec:TextBox({Label="Target",Placeholder="username",Callback=fn}) ║
║    UDL:Notify({Title="Loaded",Message="OK",Type="success"})      ║
║    UDL:SetWatermark("UDL v1.0  |  "..game.PlaceId)              ║
╚══════════════════════════════════════════════════════════════════╝
]]

-- ═══════════════════════════════════════════════════════════════
-- GUARD  – destroy any previous instance on reload
-- ═══════════════════════════════════════════════════════════════
local _KEY = "__UltimateDrawLib_v1"
if getgenv and getgenv()[_KEY] then
    pcall(function() getgenv()[_KEY]:Destroy() end)
end

-- ═══════════════════════════════════════════════════════════════
-- SERVICES
-- ═══════════════════════════════════════════════════════════════
local UIS = game:GetService("UserInputService")
local RS  = game:GetService("RunService")

-- ═══════════════════════════════════════════════════════════════
-- UTILITIES
-- ═══════════════════════════════════════════════════════════════
local function lerp(a, b, t)    return a + (b - a) * t end
local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
local function lerpC(a, b, t)
    return Color3.new(lerp(a.R,b.R,t), lerp(a.G,b.G,t), lerp(a.B,b.B,t))
end
local function hitV(p, x, y, w, h)
    return p.X >= x and p.X <= x+w and p.Y >= y and p.Y <= y+h
end
local function roundN(v, d)
    local f = 10^d; return math.floor(v*f + .5)/f
end
local function keyName(kc)
    local s = tostring(kc):gsub("Enum%.KeyCode%.","")
    return s == "Unknown" and "NONE" or s
end
local function hexCol(h)
    local r,g,b = h:match("^#?(%x%x)(%x%x)(%x%x)$")
    if r then return Color3.fromRGB(tonumber(r,16),tonumber(g,16),tonumber(b,16)) end
    return Color3.new(1,1,1)
end

-- ═══════════════════════════════════════════════════════════════
-- THEME  – every colour & size in one table
-- ═══════════════════════════════════════════════════════════════
local T = {
    -- ── Backgrounds ─────────────────────────────────────────
    bgWin   = Color3.fromRGB(14,  14,  20),   -- window body
    bgBar   = Color3.fromRGB(19,  19,  29),   -- title bar / tab bar
    bgElem  = Color3.fromRGB(24,  24,  36),   -- element row bg
    bgHov   = Color3.fromRGB(34,  34,  52),   -- element hover
    bgDrop  = Color3.fromRGB(16,  16,  24),   -- dropdown option bg
    bgDropH = Color3.fromRGB(34,  34,  52),   -- dropdown option hover
    bgDropS = Color3.fromRGB(62,  92,  180),  -- dropdown option selected

    -- ── Borders ─────────────────────────────────────────────
    brd     = Color3.fromRGB(48,  48,  68),
    brdH    = Color3.fromRGB(70,  70,  98),

    -- ── Accent ──────────────────────────────────────────────
    acc     = Color3.fromRGB(100, 140, 255),
    accDk   = Color3.fromRGB(70,  100, 200),
    accLt   = Color3.fromRGB(145, 178, 255),

    -- ── Text ────────────────────────────────────────────────
    txtPri  = Color3.fromRGB(222, 222, 240),  -- primary
    txtSec  = Color3.fromRGB(148, 148, 178),  -- secondary
    txtDim  = Color3.fromRGB(80,  80,  108),  -- dim / placeholder
    txtWht  = Color3.fromRGB(255, 255, 255),  -- white

    -- ── Toggle ──────────────────────────────────────────────
    togOn   = Color3.fromRGB(68,  196, 100),
    togOff  = Color3.fromRGB(48,  48,  72),
    togKnob = Color3.fromRGB(238, 238, 255),

    -- ── Slider ──────────────────────────────────────────────
    slTrack = Color3.fromRGB(34,  34,  52),
    slFill  = Color3.fromRGB(100, 140, 255),
    slKnob  = Color3.fromRGB(238, 238, 255),

    -- ── Notifications ───────────────────────────────────────
    notBg   = Color3.fromRGB(16,  16,  24),
    notInfo = Color3.fromRGB(100, 140, 255),
    notOk   = Color3.fromRGB(68,  196, 100),
    notWarn = Color3.fromRGB(248, 180, 48),
    notErr  = Color3.fromRGB(210, 60,  60),

    -- ── Fonts ───────────────────────────────────────────────
    font    = Drawing.Fonts.UI,
    fontMn  = Drawing.Fonts.Monospace,

    -- ── Font sizes ──────────────────────────────────────────
    szTitle = 15,
    szTab   = 13,
    szElem  = 13,
    szSec   = 10,
    szSmall = 11,
}

-- ═══════════════════════════════════════════════════════════════
-- LAYOUT CONSTANTS
-- ═══════════════════════════════════════════════════════════════
local L = {
    W      = 330,   -- window width
    H      = 430,   -- window height
    titleH = 34,    -- title bar height
    tabH   = 28,    -- tab bar height
    padX   = 10,    -- left/right padding
    padY   = 7,     -- top/bottom padding per section
    elemH  = 30,    -- element row height
    elemGp = 4,     -- gap between element rows
    secH   = 20,    -- section header height
    secGp  = 5,     -- gap below section header
    scrollW= 4,     -- scrollbar width
    -- Toggle
    togW   = 38,
    togH   = 18,
    -- Slider track
    slH    = 6,
    -- Shared right-side widget box sizes
    boxH   = 24,    -- box height (dropdown / keybind / textbox)
    ddW    = 108,   -- dropdown option width
    ddRowH = 23,    -- dropdown option row height
    kbW    = 72,    -- keybind box width
    tbW    = 128,   -- textbox box width
}
-- Derived
L.cStartY = L.titleH + L.tabH          -- content area top (relative)
L.cH      = L.H - L.cStartY            -- content area height
L.iW      = L.W - L.padX*2 - L.scrollW - 4  -- inner element width

-- ═══════════════════════════════════════════════════════════════
-- DRAWING POOL  – every Drawing.new call tracked here for cleanup
-- ═══════════════════════════════════════════════════════════════
local _pool = {}
local function nd(type_)
    local d = Drawing.new(type_)
    d.Visible = false
    _pool[d] = true
    return d
end
local function rd(d)
    if not d then return end
    _pool[d] = nil
    pcall(function() d:Remove() end)
end

-- helper: create a Text drawing with common defaults
local function newTxt(font, sz)
    local t = nd("Text")
    t.Font = font; t.Size = sz
    t.Outline = true; t.OutlineColor = Color3.new(0,0,0)
    return t
end
-- helper: create a filled Square drawing
local function newSq(zi, col)
    local s = nd("Square")
    s.Filled = true; s.ZIndex = zi
    if col then s.Color = col end
    return s
end

-- ═══════════════════════════════════════════════════════════════
-- FRAME MOUSE STATE
-- ═══════════════════════════════════════════════════════════════
local M = { pos = Vector2.new(), dn=false, up=false, held=false, whl=0 }
local _mCons = {
    UIS.InputBegan:Connect(function(i, g)
        if g then return end
        if i.UserInputType == Enum.UserInputType.MouseButton1 then
            M.dn = true; M.held = true
        end
    end),
    UIS.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 then
            M.up = true; M.held = false
        end
    end),
    UIS.InputChanged:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseWheel then
            M.whl = M.whl + i.Position.Z
        end
    end),
}

-- ═══════════════════════════════════════════════════════════════
-- GLOBAL STATE
-- ═══════════════════════════════════════════════════════════════
local _wins   = {}       -- all Win objects
local _notifs = {}       -- active notifications
local _wmDrws = {}       -- watermark drawings
local _wmOn   = false
local _kbCap  = nil      -- keybind element currently listening
local _openDd = nil      -- dropdown element currently open
local _rConn  = nil
local _kCons  = {}

-- ═══════════════════════════════════════════════════════════════
-- ══ ELEMENT BUILDERS ══════════════════════════════════════════
-- Each returns a table with these methods:
--   _update(pos, clipped)   – called every frame by the render loop
--   _setVisible(v)          – show/hide all sub-drawings
--   _onClick()              – fired when the element is clicked
--   _onRelease()            – fired when mouse releases
--   _onHover(isHovered)     – fired every frame with hover state
-- ═══════════════════════════════════════════════════════════════

-- ── TOGGLE ─────────────────────────────────────────────────────
local function mkToggle(opts)
    local lbl = opts.Label    or "Toggle"
    local val = opts.Default  ~= nil and opts.Default or false
    local cb  = opts.Callback or function() end

    local e  = { type="toggle", value=val, _hov=false, _ka=val and 1 or 0 }
    local bg  = newSq(9);  bg.Color = T.bgElem
    local lbT = newTxt(T.font, T.szElem); lbT.ZIndex=10; lbT.Color=T.txtPri
    local tBg = newSq(10); tBg.Size=Vector2.new(L.togW, L.togH)
    local tKn = nd("Circle")
    tKn.Filled=true; tKn.ZIndex=11; tKn.Radius=7; tKn.NumSides=32; tKn.Color=T.togKnob

    e._update = function(pos, clip)
        bg.Position=pos; bg.Size=Vector2.new(L.iW,L.elemH)
        bg.Color = e._hov and T.bgHov or T.bgElem; bg.Visible=not clip
        lbT.Text=lbl; lbT.Color=T.txtPri
        lbT.Position=pos+Vector2.new(8,(L.elemH-T.szElem)/2-1); lbT.Visible=not clip
        -- Animate knob
        e._ka = lerp(e._ka, e.value and 1 or 0, 0.28)
        local tx=pos.X+L.iW-L.togW-8; local ty=pos.Y+(L.elemH-L.togH)/2
        tBg.Position=Vector2.new(tx,ty); tBg.Color=lerpC(T.togOff,T.togOn,e._ka); tBg.Visible=not clip
        -- Circle.Position = center point
        local kcx = tx + L.togH/2 + (L.togW - L.togH) * e._ka
        tKn.Position=Vector2.new(kcx, ty + L.togH/2); tKn.Visible=not clip
    end
    e._setVisible = function(v) bg.Visible=v; lbT.Visible=v; tBg.Visible=v; tKn.Visible=v end
    e._onClick    = function() e.value = not e.value; pcall(cb, e.value) end
    e._onRelease  = function() end
    e._onHover    = function(h) e._hov=h end
    function e:SetValue(v) self.value=v; pcall(cb,v) end
    function e:GetValue() return self.value end
    return e
end

-- ── BUTTON ─────────────────────────────────────────────────────
local function mkButton(opts)
    local lbl = opts.Label    or "Button"
    local cb  = opts.Callback or function() end

    local e  = { type="button", _hov=false, _press=false }
    local brd = newSq(9)
    local bg  = newSq(10)
    local lbT = newTxt(T.font, T.szElem); lbT.ZIndex=11; lbT.Color=T.txtPri

    e._update = function(pos, clip)
        brd.Position=pos; brd.Size=Vector2.new(L.iW,L.elemH)
        brd.Color = e._hov and T.acc or T.brd; brd.Visible=not clip
        bg.Position=pos+Vector2.new(1,1); bg.Size=Vector2.new(L.iW-2,L.elemH-2)
        bg.Color = e._press and T.accDk or (e._hov and T.bgHov or T.bgElem); bg.Visible=not clip
        lbT.Text=lbl
        local b=lbT.TextBounds
        lbT.Position=pos+Vector2.new((L.iW-b.X)/2,(L.elemH-b.Y)/2)
        lbT.Color = e._hov and T.txtWht or T.txtPri; lbT.Visible=not clip
    end
    e._setVisible = function(v) brd.Visible=v; bg.Visible=v; lbT.Visible=v end
    e._onClick    = function() e._press=true; pcall(cb) end
    e._onRelease  = function() e._press=false end
    e._onHover    = function(h) e._hov=h end
    return e
end

-- ── SLIDER ─────────────────────────────────────────────────────
local function mkSlider(opts)
    local lbl = opts.Label    or "Slider"
    local mn  = opts.Min      or 0
    local mx  = opts.Max      or 100
    local def = clamp(opts.Default or mn, mn, mx)
    local suf = opts.Suffix   or ""
    local dec = opts.Decimals or 0
    local cb  = opts.Callback or function() end

    local slW = L.iW - 16
    local e   = { type="slider", value=def, _hov=false, _drag=false }
    local bg  = newSq(9)
    local lbT = newTxt(T.font, T.szElem); lbT.ZIndex=10; lbT.Color=T.txtPri
    local valT= newTxt(T.fontMn, T.szSmall); valT.ZIndex=10; valT.Color=T.acc
    local trk = newSq(10); trk.Color=T.slTrack
    local fil = newSq(11); fil.Color=T.slFill
    local kn  = nd("Circle")
    kn.Filled=true; kn.ZIndex=12; kn.NumSides=32; kn.Radius=6; kn.Color=T.slKnob

    local function fmt(v) return string.format("%."..dec.."f",v)..suf end

    e._update = function(pos, clip)
        bg.Position=pos; bg.Size=Vector2.new(L.iW,L.elemH)
        bg.Color=e._hov and T.bgHov or T.bgElem; bg.Visible=not clip
        lbT.Text=lbl; lbT.Position=pos+Vector2.new(8,3); lbT.Visible=not clip
        valT.Text=fmt(e.value)
        local vb=valT.TextBounds; valT.Position=pos+Vector2.new(L.iW-vb.X-8,3); valT.Visible=not clip
        local tx=pos.X+8; local ty=pos.Y+L.elemH-10
        trk.Position=Vector2.new(tx,ty); trk.Size=Vector2.new(slW,L.slH); trk.Visible=not clip
        local rat=clamp((e.value-mn)/math.max(1e-9,mx-mn),0,1)
        fil.Position=Vector2.new(tx,ty); fil.Size=Vector2.new(slW*rat,L.slH); fil.Visible=not clip
        kn.Position=Vector2.new(tx+slW*rat, ty+L.slH/2)
        kn.Color=e._hov and T.accLt or T.slKnob; kn.Visible=not clip
        if e._drag and M.held then
            local r  = clamp((M.pos.X-tx)/slW, 0, 1)
            local nv = roundN(mn+(mx-mn)*r, dec)
            if nv ~= e.value then e.value=nv; pcall(cb,nv) end
        end
    end
    e._setVisible = function(v)
        bg.Visible=v; lbT.Visible=v; valT.Visible=v
        trk.Visible=v; fil.Visible=v; kn.Visible=v
    end
    e._onClick   = function() e._drag=true end
    e._onRelease = function() e._drag=false end
    e._onHover   = function(h) e._hov=h end
    function e:SetValue(v) self.value=clamp(v,mn,mx); pcall(cb,self.value) end
    function e:GetValue() return self.value end
    return e
end

-- ── DROPDOWN ───────────────────────────────────────────────────
local function mkDropdown(opts)
    local lbl  = opts.Label    or "Dropdown"
    local optL = opts.Options  or {}
    local def  = opts.Default  or optL[1]
    local cb   = opts.Callback or function() end

    local e = { type="dropdown", value=def, options=optL, _hov=false, _open=false, _ep=Vector2.new() }
    local bg   = newSq(9)
    local lbT  = newTxt(T.font, T.szElem); lbT.ZIndex=10; lbT.Color=T.txtPri
    local bBrd = newSq(10)
    local box  = newSq(11)
    local selT = newTxt(T.font, T.szSmall); selT.ZIndex=12; selT.Color=T.txtPri
    local arrT = nd("Text"); arrT.Font=T.font; arrT.Size=T.szSmall; arrT.Outline=false; arrT.ZIndex=12
    -- Pre-allocate option row drawings
    local ods  = {}
    for _ = 1, #optL do
        local o = {
            bg  = newSq(18),
            txt = newTxt(T.font, T.szSmall),
            chk = nd("Text"),
        }
        o.bg.ZIndex=18; o.txt.ZIndex=19
        o.chk.Font=T.font; o.chk.Size=T.szSmall; o.chk.Outline=false; o.chk.ZIndex=19; o.chk.Color=T.accLt
        table.insert(ods, o)
    end

    e._update = function(pos, clip)
        e._ep = pos
        bg.Position=pos; bg.Size=Vector2.new(L.iW,L.elemH)
        bg.Color=e._hov and T.bgHov or T.bgElem; bg.Visible=not clip
        lbT.Text=lbl; lbT.Color=T.txtPri
        lbT.Position=pos+Vector2.new(8,(L.elemH-T.szElem)/2-1); lbT.Visible=not clip
        local bx=pos.X+L.iW-L.ddW-6; local by=pos.Y+(L.elemH-L.boxH)/2
        bBrd.Position=Vector2.new(bx-1,by-1); bBrd.Size=Vector2.new(L.ddW+2,L.boxH+2)
        bBrd.Color=e._open and T.acc or T.brd; bBrd.Visible=not clip
        box.Position=Vector2.new(bx,by); box.Size=Vector2.new(L.ddW,L.boxH)
        box.Color=T.bgElem; box.Visible=not clip
        selT.Text=tostring(e.value or "—"); selT.Color=T.txtPri
        selT.Position=Vector2.new(bx+7, by+(L.boxH-T.szSmall)/2-1); selT.Visible=not clip
        arrT.Text=e._open and "▲" or "▼"; arrT.Color=T.txtSec; arrT.ZIndex=12
        arrT.Position=Vector2.new(bx+L.ddW-14, by+(L.boxH-T.szSmall)/2); arrT.Visible=not clip
        -- Option rows
        for i, od in ipairs(ods) do
            local opt = optL[i]
            if not opt then
                od.bg.Visible=false; od.txt.Visible=false; od.chk.Visible=false; continue
            end
            local oy  = by + L.boxH + (i-1)*L.ddRowH
            local ih  = hitV(M.pos, bx, oy, L.ddW, L.ddRowH)
            local isSel = (opt == e.value)
            od.bg.Position=Vector2.new(bx,oy); od.bg.Size=Vector2.new(L.ddW,L.ddRowH)
            od.bg.Color = isSel and T.bgDropS or (ih and T.bgDropH or T.bgDrop)
            od.bg.Visible = e._open and not clip
            od.txt.Text=tostring(opt); od.txt.Color = isSel and T.txtWht or T.txtPri
            od.txt.Position=Vector2.new(bx+8, oy+(L.ddRowH-T.szSmall)/2-1)
            od.txt.Visible = e._open and not clip
            od.chk.Text = isSel and "✓" or ""
            od.chk.Position=Vector2.new(bx+L.ddW-15, oy+(L.ddRowH-T.szSmall)/2-1)
            od.chk.Visible = e._open and isSel and not clip
            if M.dn and e._open and not clip and ih then
                e.value=opt; e._open=false; _openDd=nil; pcall(cb,opt)
            end
        end
    end
    e._setVisible = function(v)
        bg.Visible=v; lbT.Visible=v; bBrd.Visible=v; box.Visible=v
        selT.Visible=v; arrT.Visible=v
        if not v then
            e._open=false
            for _, od in ipairs(ods) do od.bg.Visible=false; od.txt.Visible=false; od.chk.Visible=false end
        end
    end
    e._onClick = function()
        local bx=e._ep.X+L.iW-L.ddW-6; local by=e._ep.Y+(L.elemH-L.boxH)/2
        if hitV(M.pos, bx, by, L.ddW, L.boxH) then
            e._open = not e._open
            if e._open then
                if _openDd and _openDd~=e then _openDd._open=false end
                _openDd=e
            else
                _openDd=nil
            end
        end
    end
    e._onRelease = function() end
    e._onHover   = function(h) e._hov=h end
    function e:GetValue() return self.value end
    function e:SetValue(v)
        for _, o in ipairs(optL) do
            if o==v then self.value=v; pcall(cb,v); return end
        end
    end
    function e:SetOptions(newOpts)
        optL = newOpts
        if not table.find(optL, self.value) then self.value = optL[1] end
        -- Rebuild option drawings
        for i, od in ipairs(ods) do
            for _, d in pairs(od) do d:Remove() end
        end
        ods = {}
        for _ = 1, #optL do
            local o = { bg=newSq(18), txt=newTxt(T.font,T.szSmall), chk=nd("Text") }
            o.bg.ZIndex=18; o.txt.ZIndex=19
            o.chk.Font=T.font; o.chk.Size=T.szSmall; o.chk.Outline=false; o.chk.ZIndex=19; o.chk.Color=T.accLt
            table.insert(ods, o)
        end
        e.options = optL
    end
    return e
end

-- ── LABEL ──────────────────────────────────────────────────────
local function mkLabel(opts)
    local txt = opts.Text  or "Label"
    local col = opts.Color

    local e   = { type="label", _txt=txt }
    local bg  = newSq(9); bg.Color=T.bgElem
    local lbT = newTxt(T.font, T.szElem); lbT.ZIndex=10

    e._update = function(pos, clip)
        bg.Position=pos; bg.Size=Vector2.new(L.iW,L.elemH); bg.Visible=not clip
        lbT.Text=e._txt; lbT.Color=col or T.txtSec
        lbT.Position=pos+Vector2.new(8,(L.elemH-T.szElem)/2-1); lbT.Visible=not clip
    end
    e._setVisible = function(v) bg.Visible=v; lbT.Visible=v end
    e._onClick=function()end; e._onRelease=function()end; e._onHover=function()end
    function e:SetText(t)  self._txt=t end
    function e:GetText()   return self._txt end
    return e
end

-- ── SEPARATOR ──────────────────────────────────────────────────
local function mkSep()
    local e  = { type="separator" }
    local ln = newSq(9); ln.Color=T.brd; ln.Size=Vector2.new(L.iW,1)

    e._update = function(pos, clip)
        ln.Position=pos+Vector2.new(4, L.elemH/2-1)
        ln.Size=Vector2.new(L.iW-8, 1); ln.Visible=not clip
    end
    e._setVisible = function(v) ln.Visible=v end
    e._onClick=function()end; e._onRelease=function()end; e._onHover=function()end
    return e
end

-- ── KEYBIND ────────────────────────────────────────────────────
local function mkKeyBind(opts)
    local lbl = opts.Label    or "KeyBind"
    local def = opts.Default  or Enum.KeyCode.Unknown
    local cb  = opts.Callback or function() end

    local e   = { type="keybind", key=def, _hov=false, _list=false }
    local bg  = newSq(9)
    local lbT = newTxt(T.font, T.szElem); lbT.ZIndex=10; lbT.Color=T.txtPri
    local brd = newSq(10)
    local box = newSq(11)
    local keyT= newTxt(T.fontMn, T.szSmall); keyT.ZIndex=12; keyT.Color=T.txtSec

    e._update = function(pos, clip)
        bg.Position=pos; bg.Size=Vector2.new(L.iW,L.elemH)
        bg.Color=e._hov and T.bgHov or T.bgElem; bg.Visible=not clip
        lbT.Text=lbl; lbT.Position=pos+Vector2.new(8,(L.elemH-T.szElem)/2-1); lbT.Visible=not clip
        local bx=pos.X+L.iW-L.kbW-6; local by=pos.Y+(L.elemH-L.boxH)/2
        brd.Position=Vector2.new(bx-1,by-1); brd.Size=Vector2.new(L.kbW+2,L.boxH+2)
        brd.Color=e._list and T.acc or T.brd; brd.Visible=not clip
        box.Position=Vector2.new(bx,by); box.Size=Vector2.new(L.kbW,L.boxH)
        box.Color=T.bgElem; box.Visible=not clip
        keyT.Text = e._list and "[ ··· ]" or keyName(e.key)
        keyT.Color = e._list and T.acc or T.txtSec
        local kb=keyT.TextBounds
        keyT.Position=Vector2.new(bx+(L.kbW-kb.X)/2, by+(L.boxH-kb.Y)/2-1); keyT.Visible=not clip
    end
    e._setVisible = function(v)
        bg.Visible=v; lbT.Visible=v; brd.Visible=v; box.Visible=v; keyT.Visible=v
        if not v then e._list=false end
    end
    e._onClick = function()
        e._list = not e._list
        if e._list then
            if _kbCap then _kbCap._list=false end
            _kbCap = e
        else
            _kbCap = nil
        end
    end
    e._onRelease = function() end
    e._onHover   = function(h) e._hov=h end
    e._capture   = function(kc) e.key=kc; e._list=false; _kbCap=nil; pcall(cb,kc) end
    function e:GetKey() return self.key end
    function e:SetKey(kc) self.key=kc; pcall(cb,kc) end
    return e
end

-- ── TEXTBOX ────────────────────────────────────────────────────
local function mkTextBox(opts)
    local lbl  = opts.Label       or "TextBox"
    local ph   = opts.Placeholder or "Type here..."
    local cb   = opts.Callback    or function() end
    local maxL = opts.MaxLength   or 64

    local e    = { type="textbox", text="", _hov=false, _focus=false }
    local bg   = newSq(9)
    local lbT  = newTxt(T.font, T.szElem); lbT.ZIndex=10; lbT.Color=T.txtPri
    local brd  = newSq(10)
    local box  = newSq(11)
    local inpT = newTxt(T.fontMn, T.szSmall); inpT.ZIndex=12
    local _tc  -- text input connection

    e._update = function(pos, clip)
        bg.Position=pos; bg.Size=Vector2.new(L.iW,L.elemH)
        bg.Color=e._hov and T.bgHov or T.bgElem; bg.Visible=not clip
        lbT.Text=lbl; lbT.Position=pos+Vector2.new(8,(L.elemH-T.szElem)/2-1); lbT.Visible=not clip
        local bx=pos.X+L.iW-L.tbW-6; local by=pos.Y+(L.elemH-L.boxH)/2
        brd.Position=Vector2.new(bx-1,by-1); brd.Size=Vector2.new(L.tbW+2,L.boxH+2)
        brd.Color=e._focus and T.acc or T.brd; brd.Visible=not clip
        box.Position=Vector2.new(bx,by); box.Size=Vector2.new(L.tbW,L.boxH)
        box.Color=T.bgElem; box.Visible=not clip
        local cur  = (e._focus and tick()%1 < .5) and "|" or ""
        local disp = e.text~="" and (e.text..cur) or (e._focus and cur or ph)
        inpT.Text=disp; inpT.Color = e.text~="" and T.txtPri or T.txtDim
        inpT.Position=Vector2.new(bx+6, by+(L.boxH-T.szSmall)/2-1); inpT.Visible=not clip
    end
    e._setVisible = function(v)
        bg.Visible=v; lbT.Visible=v; brd.Visible=v; box.Visible=v; inpT.Visible=v
        if not v then
            e._focus=false
            if _tc then _tc:Disconnect(); _tc=nil end
        end
    end
    e._onClick = function()
        e._focus = true
        if _tc then _tc:Disconnect() end
        _tc = UIS.InputBegan:Connect(function(inp, gpe)
            if not e._focus then return end
            if inp.UserInputType ~= Enum.UserInputType.Keyboard then return end
            local kc = inp.KeyCode
            if kc==Enum.KeyCode.Return or kc==Enum.KeyCode.Escape then
                e._focus=false
                if _tc then _tc:Disconnect(); _tc=nil end
                pcall(cb, e.text)
            elseif kc==Enum.KeyCode.Backspace then
                e.text = e.text:sub(1, -2)
            elseif kc==Enum.KeyCode.Space then
                if #e.text < maxL then e.text = e.text.." " end
            else
                local ch = UIS:GetStringForKeyCode(kc)
                if #ch==1 and #e.text < maxL then
                    local shift = UIS:IsKeyDown(Enum.KeyCode.LeftShift)
                               or UIS:IsKeyDown(Enum.KeyCode.RightShift)
                    e.text = e.text..(shift and ch or ch:lower())
                end
            end
        end)
    end
    e._onRelease = function() end
    e._onHover   = function(h) e._hov=h end
    function e:GetText()  return self.text end
    function e:SetText(v) self.text=v end
    function e:Clear()    self.text="" end
    return e
end

-- ═══════════════════════════════════════════════════════════════
-- TAB CLASS
-- ═══════════════════════════════════════════════════════════════
local Tab = {}; Tab.__index = Tab

function Tab.new(name)
    local t = setmetatable({ name=name, sections={}, _so=0, _tH=0 }, Tab)
    -- Tab button drawings
    t._d = {
        bg  = newSq(4);
        bar = newSq(5);
        div = newSq(5); -- vertical divider
        txt = newTxt(T.font, T.szTab);
    }
    t._d.div.Color = T.brd
    t._d.txt.ZIndex = 6
    t._d.txt.Outline = true; t._d.txt.OutlineColor = Color3.new(0,0,0)
    return t
end

function Tab:_recalc()
    local h = L.padY
    for _, sec in ipairs(self.sections) do
        h = h + L.secH + L.secGp
        h = h + #sec.elements * (L.elemH + L.elemGp)
        h = h + L.padY
    end
    self._tH = h
end

function Tab:_setVisible(v)
    for _, sec in ipairs(self.sections) do
        sec._d.lbl.Visible = v
        sec._d.ln.Visible  = v
        for _, e in ipairs(sec.elements) do
            e._setVisible(v)
        end
    end
end

function Tab:Section(name)
    local sec = { name=name, elements={}, _d={} }
    sec._d.lbl = nd("Text")
    sec._d.lbl.Font=T.font; sec._d.lbl.Size=T.szSec
    sec._d.lbl.Color=T.txtDim; sec._d.lbl.ZIndex=8; sec._d.lbl.Outline=false
    sec._d.ln  = newSq(8); sec._d.ln.Color=T.brd
    table.insert(self.sections, sec)
    self:_recalc()

    local tab = self
    local S   = {}
    local function reg(e)
        table.insert(sec.elements, e); tab:_recalc(); return e
    end
    function S:Toggle(o)   return reg(mkToggle(o)) end
    function S:Button(o)   return reg(mkButton(o)) end
    function S:Slider(o)   return reg(mkSlider(o)) end
    function S:Dropdown(o) return reg(mkDropdown(o)) end
    function S:Label(o)    return reg(mkLabel(o)) end
    function S:Separator() return reg(mkSep()) end
    function S:KeyBind(o)  return reg(mkKeyBind(o)) end
    function S:TextBox(o)  return reg(mkTextBox(o)) end
    return S
end

-- ═══════════════════════════════════════════════════════════════
-- WINDOW CLASS
-- ═══════════════════════════════════════════════════════════════
local Win = {}; Win.__index = Win

function Win.new(opts)
    local w = setmetatable({
        title     = opts.Title    or "UDL",
        toggleKey = opts.Key      or Enum.KeyCode.Insert,
        pos       = opts.Position
                        and Vector2.new(opts.Position.X, opts.Position.Y)
                        or  Vector2.new(200, 150),
        tabs = {}, _at = 1,
        _vis = false, _min = false,
        _drg = false, _doff= Vector2.new(),
    }, Win)

    local d = {}; w._d = d
    -- Window layers
    d.oBrd  = newSq(1, T.brd)          -- outer glow border
    d.wBg   = newSq(2, T.bgWin)        -- window background
    -- Title bar
    d.tBg   = newSq(3, T.bgBar)
    d.tLn   = newSq(4, T.brd)          -- title bottom line
    d.tAcc  = newSq(4, T.acc)          -- left accent strip
    d.tTxt  = newTxt(T.font, T.szTitle); d.tTxt.ZIndex=5; d.tTxt.Color=T.txtPri
    -- Close & minimize buttons
    d.clBrd = newSq(5, T.brd); d.clBg = newSq(6, T.bgElem)
    d.clTxt = nd("Text"); d.clTxt.Font=T.font; d.clTxt.Size=T.szSmall
    d.clTxt.Text="✕"; d.clTxt.Outline=false; d.clTxt.ZIndex=7; d.clTxt.Color=T.txtSec
    d.mnBrd = newSq(5, T.brd); d.mnBg = newSq(6, T.bgElem)
    d.mnTxt = nd("Text"); d.mnTxt.Font=T.font; d.mnTxt.Size=T.szSmall
    d.mnTxt.Text="–"; d.mnTxt.Outline=false; d.mnTxt.ZIndex=7; d.mnTxt.Color=T.txtSec
    -- Tab bar
    d.tbBg  = newSq(3, T.bgBar)
    d.tbLn  = newSq(4, T.brd)
    -- Content + scrollbar
    d.cBg   = newSq(2, T.bgWin)
    d.bLn   = newSq(4, T.brd)
    d.sTrk  = newSq(5, Color3.fromRGB(20,20,30))
    d.sThm  = newSq(6, T.brdH)

    -- Register toggle hotkey
    table.insert(_kCons, UIS.InputBegan:Connect(function(inp, gpe)
        if gpe then return end
        if inp.KeyCode == w.toggleKey then w:Toggle() end
    end))

    return w
end

function Win:_layout()
    local p  = self.pos
    local d  = self._d
    local v  = self._vis
    local mn = self._min
    local ct = v and not mn  -- show content (tab bar + elements)

    local fullH = mn and L.titleH or L.H
    d.oBrd.Position=p-Vector2.new(1,1); d.oBrd.Size=Vector2.new(L.W+2,fullH+2); d.oBrd.Visible=v
    d.wBg.Position=p;                   d.wBg.Size=Vector2.new(L.W,fullH);       d.wBg.Visible=v
    -- Title bar
    d.tBg.Position=p;                          d.tBg.Size=Vector2.new(L.W,L.titleH);  d.tBg.Visible=v
    d.tLn.Position=p+Vector2.new(0,L.titleH-1);d.tLn.Size=Vector2.new(L.W,1);         d.tLn.Visible=v
    d.tAcc.Position=p;                         d.tAcc.Size=Vector2.new(3,L.titleH);    d.tAcc.Visible=v
    d.tTxt.Text=self.title
    d.tTxt.Position=p+Vector2.new(12,(L.titleH-T.szTitle)/2-1); d.tTxt.Visible=v
    -- Buttons
    local btY=p.Y+(L.titleH-16)/2; local clX=p.X+L.W-26; local mnX=p.X+L.W-48
    d.clBrd.Position=Vector2.new(clX-1,btY-1); d.clBrd.Size=Vector2.new(18,16); d.clBrd.Visible=v
    d.clBg.Position=Vector2.new(clX,btY);       d.clBg.Size=Vector2.new(16,14);  d.clBg.Visible=v
    d.clTxt.Position=Vector2.new(clX+4,btY+1);                                    d.clTxt.Visible=v
    d.mnBrd.Position=Vector2.new(mnX-1,btY-1); d.mnBrd.Size=Vector2.new(18,16); d.mnBrd.Visible=v
    d.mnBg.Position=Vector2.new(mnX,btY);       d.mnBg.Size=Vector2.new(16,14);  d.mnBg.Visible=v
    d.mnTxt.Position=Vector2.new(mnX+4,btY+1);                                    d.mnTxt.Visible=v
    -- Tab bar
    d.tbBg.Position=p+Vector2.new(0,L.titleH);         d.tbBg.Size=Vector2.new(L.W,L.tabH); d.tbBg.Visible=ct
    d.tbLn.Position=p+Vector2.new(0,L.titleH+L.tabH-1);d.tbLn.Size=Vector2.new(L.W,1);      d.tbLn.Visible=ct
    -- Content
    d.cBg.Position=p+Vector2.new(0,L.cStartY); d.cBg.Size=Vector2.new(L.W,L.cH); d.cBg.Visible=ct
    d.bLn.Position=p+Vector2.new(0,L.H-1);     d.bLn.Size=Vector2.new(L.W,1);    d.bLn.Visible=ct
    -- Scrollbar
    local tab     = self.tabs[self._at]
    local hasScrl = ct and tab and tab._tH > L.cH
    local scX=p.X+L.W-L.scrollW-2; local scY=p.Y+L.cStartY+4; local trkH=L.cH-8
    d.sTrk.Position=Vector2.new(scX,scY); d.sTrk.Size=Vector2.new(L.scrollW,trkH); d.sTrk.Visible=hasScrl
    if hasScrl and tab then
        local rat=L.cH/tab._tH; local tH2=math.max(16,math.floor(trkH*rat))
        local sRat=tab._so/math.max(1,tab._tH-L.cH)
        d.sThm.Position=Vector2.new(scX,scY+(trkH-tH2)*sRat)
        d.sThm.Size=Vector2.new(L.scrollW,tH2); d.sThm.Visible=true
    else
        d.sThm.Visible=false
    end
end

function Win:_layoutTabs()
    if #self.tabs==0 then return end
    local p  = self.pos
    local n  = #self.tabs
    local tw = math.floor(L.W/n)
    local ct = self._vis and not self._min

    for i, tab in ipairs(self.tabs) do
        local isA = (i==self._at)
        local tx_ = p.X+(i-1)*tw; local ty_=p.Y+L.titleH
        local d   = tab._d
        d.bg.Position=Vector2.new(tx_,ty_); d.bg.Size=Vector2.new(tw,L.tabH)
        d.bg.Color=isA and T.accDk or T.bgBar; d.bg.Visible=ct
        d.bar.Position=Vector2.new(tx_,ty_+L.tabH-2); d.bar.Size=Vector2.new(tw,2)
        d.bar.Color=isA and T.acc or T.brdH; d.bar.Visible=ct
        d.div.Position=Vector2.new(tx_+tw-1,ty_+5); d.div.Size=Vector2.new(1,L.tabH-10)
        d.div.Visible=ct and i<n
        d.txt.Text=tab.name; d.txt.Color=isA and T.txtWht or T.txtSec
        local b=d.txt.TextBounds
        d.txt.Position=Vector2.new(tx_+(tw-b.X)/2, ty_+(L.tabH-b.Y)/2); d.txt.Visible=ct
    end
end

function Win:_input(fDn, fUp, fWhl)
    local p = self.pos; local d = self._d
    -- Drag (title minus button zone)
    if fDn and hitV(M.pos, p.X, p.Y, L.W-56, L.titleH) then
        self._drg=true; self._doff=M.pos-p
    end
    if fUp then self._drg=false end
    if self._drg and M.held then self.pos=M.pos-self._doff end
    -- Close / minimize hover colours
    local btY=p.Y+(L.titleH-16)/2; local clX=p.X+L.W-26; local mnX=p.X+L.W-48
    local clH=hitV(M.pos,clX,btY,16,14); local mnH=hitV(M.pos,mnX,btY,16,14)
    d.clBg.Color  = clH and Color3.fromRGB(195,55,55) or T.bgElem
    d.clBrd.Color = clH and Color3.fromRGB(220,70,70) or T.brd
    d.clTxt.Color = clH and T.txtWht or T.txtSec
    d.mnBg.Color  = mnH and T.bgHov or T.bgElem
    d.mnBrd.Color = mnH and T.brdH or T.brd
    d.mnTxt.Color = mnH and T.txtPri or T.txtSec
    if fDn then
        if clH then self:SetVisible(false); return end
        if mnH then
            self._min = not self._min
            local t=self.tabs[self._at]
            if t then t:_setVisible(self._vis and not self._min) end
            return
        end
    end
    if self._min then return end
    -- Tab clicks
    local n=#self.tabs
    if n>0 then
        local tw=math.floor(L.W/n)
        for i=1,n do
            if fDn and hitV(M.pos, p.X+(i-1)*tw, p.Y+L.titleH, tw, L.tabH) then
                if i~=self._at then self:_switchTab(i) end
            end
        end
    end
    -- Scroll wheel in content area
    if fWhl~=0 and hitV(M.pos, p.X, p.Y+L.cStartY, L.W, L.cH) then
        local tab=self.tabs[self._at]
        if tab then
            tab._so=clamp(tab._so-fWhl*22, 0, math.max(0,tab._tH-L.cH))
        end
    end
end

function Win:_switchTab(i)
    local prev=self.tabs[self._at]
    if prev then prev:_setVisible(false) end
    self._at=clamp(i,1,#self.tabs)
    local curr=self.tabs[self._at]
    if curr then curr:_setVisible(self._vis and not self._min) end
    self:_layoutTabs()
end

function Win:SetVisible(v)
    self._vis=v
    for _,dr in pairs(self._d) do dr.Visible=v end
    self:_layoutTabs()
    for i,tab in ipairs(self.tabs) do
        tab:_setVisible(v and not self._min and i==self._at)
    end
end

function Win:Toggle()
    self:SetVisible(not self._vis)
end

function Win:Tab(name)
    local tab=Tab.new(name)
    table.insert(self.tabs, tab)
    self:_layoutTabs()
    if #self.tabs==1 and self._vis then tab:_setVisible(true) end
    local proxy={}
    function proxy:Section(n) return tab:Section(n) end
    return proxy
end

-- ═══════════════════════════════════════════════════════════════
-- NOTIFICATION SYSTEM
-- ═══════════════════════════════════════════════════════════════
local NW, NH, NPad = 285, 66, 8

local function notifColor(t)
    if t=="success" then return T.notOk
    elseif t=="warning" then return T.notWarn
    elseif t=="error"   then return T.notErr
    else                     return T.notInfo end
end

local function makeNotif(opts)
    local title=opts.Title or "Notification"
    local msg  =opts.Message or ""
    local dur  =opts.Duration or 3.5
    local nc   =notifColor(opts.Type)

    local n={timer=0, dur=dur, alpha=0, d={}}
    local d=n.d
    d.bg   = newSq(95, T.notBg)
    d.side = newSq(96, nc); d.side.Size=Vector2.new(3, NH)
    d.top  = newSq(96, nc); d.top.Size=Vector2.new(NW, 2)
    d.ttl  = newTxt(T.font, T.szElem); d.ttl.ZIndex=97; d.ttl.Color=T.txtWht; d.ttl.Text=title
    d.msg  = newTxt(T.font, T.szSmall); d.msg.ZIndex=97; d.msg.Color=T.txtSec; d.msg.Text=msg
    d.bar  = newSq(97, nc)
    for _,v in pairs(d) do v.Visible=false end
    return n
end

local function updateNotifs(dt)
    local vp=workspace.CurrentCamera.ViewportSize
    local nx=vp.X-NW-14; local ny=vp.Y-14
    for i=#_notifs,1,-1 do
        local n=_notifs[i]; n.timer=n.timer+dt
        local fd=0.22
        if     n.timer<fd then        n.alpha=n.timer/fd
        elseif n.timer>n.dur-fd then  n.alpha=clamp((n.dur-n.timer)/fd,0,1)
        else                          n.alpha=1 end
        if n.timer>=n.dur then
            for _,v in pairs(n.d) do rd(v) end; table.remove(_notifs,i)
        else
            ny=ny-NH-NPad
            local d=n.d; local a=n.alpha
            d.bg.Position=Vector2.new(nx,ny);   d.bg.Size=Vector2.new(NW,NH); d.bg.Transparency=a; d.bg.Visible=a>0.01
            d.side.Position=Vector2.new(nx,ny);                                d.side.Transparency=a; d.side.Visible=a>0.01
            d.top.Position=Vector2.new(nx,ny);                                 d.top.Transparency=a; d.top.Visible=a>0.01
            d.ttl.Position=Vector2.new(nx+10,ny+10); d.ttl.Transparency=a; d.ttl.Visible=a>0.01
            d.msg.Position=Vector2.new(nx+10,ny+28); d.msg.Transparency=a; d.msg.Visible=a>0.01
            local prog=1-clamp(n.timer/n.dur,0,1)
            d.bar.Position=Vector2.new(nx+3,ny+NH-3); d.bar.Size=Vector2.new((NW-3)*prog,3)
            d.bar.Transparency=a; d.bar.Visible=a>0.01
        end
    end
end

-- ═══════════════════════════════════════════════════════════════
-- WATERMARK
-- ═══════════════════════════════════════════════════════════════
local function initWM()
    if _wmDrws.bg then return end
    _wmDrws.bg  = newSq(50, T.bgBar)
    _wmDrws.txt = newTxt(T.font, T.szElem); _wmDrws.txt.ZIndex=51; _wmDrws.txt.Color=T.txtPri
end

local function updateWM()
    if not _wmOn or not _wmDrws.txt then return end
    local b=_wmDrws.txt.TextBounds
    _wmDrws.txt.Position=Vector2.new(17,12)
    _wmDrws.bg.Position=Vector2.new(8,6)
    _wmDrws.bg.Size=Vector2.new(b.X+20, b.Y+12)
end

-- ═══════════════════════════════════════════════════════════════
-- RENDER LOOP
-- ═══════════════════════════════════════════════════════════════
local _lt = tick()

_rConn = RS.RenderStepped:Connect(function()
    local now=tick(); local dt=now-_lt; _lt=now

    -- Snapshot frame input
    M.pos=UIS:GetMouseLocation()
    local fDn=M.dn; M.dn=false
    local fUp=M.up; M.up=false
    local fWhl=M.whl; M.whl=0

    -- Close open dropdown on outside click
    if fDn and _openDd then
        local e=_openDd
        local bx=e._ep.X+L.iW-L.ddW-6
        local by=e._ep.Y+(L.elemH-L.boxH)/2
        if not hitV(M.pos, bx, by, L.ddW, L.boxH + #e.options*L.ddRowH) then
            e._open=false; _openDd=nil
        end
    end

    -- ── Windows ──────────────────────────────────────────────
    for _, win in ipairs(_wins) do
        if not win._vis then continue end
        win:_input(fDn, fUp, fWhl)
        win:_layout()
        win:_layoutTabs()
        if win._min then continue end

        local tab=win.tabs[win._at]
        if not tab then continue end

        local bX   = win.pos.X + L.padX
        local bY   = win.pos.Y + L.cStartY + L.padY
        local cTop = win.pos.Y + L.cStartY
        local cBot = win.pos.Y + L.H
        local yAcc = 0

        for _, sec in ipairs(tab.sections) do
            -- Section header
            local sY   = bY + yAcc - tab._so
            local sClp = sY < cTop or sY+L.secH > cBot
            sec._d.lbl.Text = sec.name:upper()
            sec._d.lbl.Position = Vector2.new(bX, sY+(L.secH-T.szSec)/2)
            sec._d.lbl.Visible  = not sClp
            local lb  = sec._d.lbl.TextBounds
            sec._d.ln.Position  = Vector2.new(bX+lb.X+6, sY+L.secH/2)
            sec._d.ln.Size      = Vector2.new(math.max(0,L.iW-lb.X-6), 1)
            sec._d.ln.Visible   = not sClp
            yAcc = yAcc + L.secH + L.secGp

            -- Elements
            for _, e in ipairs(sec.elements) do
                local eY   = bY + yAcc - tab._so
                local clip = eY < cTop or eY+L.elemH > cBot
                local hov  = (not clip) and hitV(M.pos, bX, eY, L.iW, L.elemH)
                e._onHover(hov)
                if fDn and hov  then e._onClick()  end
                if fUp          then e._onRelease() end
                e._update(Vector2.new(bX, eY), clip)
                yAcc = yAcc + L.elemH + L.elemGp
            end

            yAcc = yAcc + L.padY
        end
    end

    updateNotifs(dt)
    updateWM()
end)

-- Keybind capture
table.insert(_kCons, UIS.InputBegan:Connect(function(inp, gpe)
    if gpe or not _kbCap then return end
    if inp.UserInputType == Enum.UserInputType.Keyboard then
        if inp.KeyCode == Enum.KeyCode.Escape then
            _kbCap._list=false; _kbCap=nil
        else
            _kbCap._capture(inp.KeyCode)
        end
    end
end))

-- ═══════════════════════════════════════════════════════════════
-- PUBLIC API
-- ═══════════════════════════════════════════════════════════════
local UDL = {}

--- Create a new draggable window.
-- @param opts { Title, Key, Position }
function UDL:Window(opts)
    local w = Win.new(opts or {})
    table.insert(_wins, w)
    return w
end

--- Show a temporary notification in the bottom-right corner.
-- @param opts { Title, Message, Duration, Type="info"|"success"|"warning"|"error" }
function UDL:Notify(opts)
    table.insert(_notifs, makeNotif(opts or {}))
end

--- Set or update the watermark text (top-left corner).
function UDL:SetWatermark(text)
    initWM()
    _wmOn = true
    _wmDrws.txt.Text    = text
    _wmDrws.txt.Visible = true
    _wmDrws.bg.Visible  = true
end

--- Hide the watermark.
function UDL:HideWatermark()
    _wmOn=false
    if _wmDrws.bg  then _wmDrws.bg.Visible=false  end
    if _wmDrws.txt then _wmDrws.txt.Visible=false end
end

--- Merge colour/size overrides into the theme table.
-- Any key from T can be overridden.  Call before creating windows.
-- Example:  UDL:SetTheme({ acc = Color3.fromRGB(255,80,80) })
function UDL:SetTheme(overrides)
    for k, v in pairs(overrides) do T[k]=v end
end

--- Utility: convert a hex string to Color3.
function UDL:HexColor(h) return hexCol(h) end

--- Retrieve the full theme table.
function UDL:GetTheme() return T end

--- Destroy the entire library: disconnect events, remove all drawings.
function UDL:Destroy()
    if _rConn then _rConn:Disconnect(); _rConn=nil end
    for _,c in ipairs(_kCons)  do pcall(function()c:Disconnect()end) end
    for _,c in ipairs(_mCons)  do pcall(function()c:Disconnect()end) end
    for d in pairs(_pool) do pcall(function()d:Remove()end) end
    _pool={}; _wins={}; _notifs={}
    _wmOn=false; _kbCap=nil; _openDd=nil
    if getgenv then getgenv()[_KEY]=nil end
end

-- Register global so subsequent loadstring calls can Destroy first
if getgenv then getgenv()[_KEY] = UDL end

return UDL
