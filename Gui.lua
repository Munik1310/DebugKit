--[[
	DebugKit UI Library (Luau / Roblox)
	Port of the HTML "Game Debug & Mod Overlay".

	Single file, no external modules or assets. Returns the Library table, so it works as:
		local Library = require(ReplicatedStorage.DebugKit)   -- ModuleScript
		local Library = loadstring(source)()                  -- where loadstring is available

	API
		Library:CreateWindow(Title [, Options])               -> Window
			Options = { Subtitle = "v1.0", Size = Vector2, Accent = Color3, Keybind = Enum.KeyCode }
		Window:CreateTab(Name [, IconImage])                  -> Tab
		Window:SetAccent(Color3) / :SetFpsVisible(bool) / :Minimize() / :Restore()
		Window:ToggleVisibility() / :Reset() / :Log(text) / :Destroy()

		Tab:CreateSection(Text)
		Tab:CreateToggle(Text, Default, Callback [, Description])              -> { Value, Set, Get }
		Tab:CreateSlider(Text, Min, Max, Default, Callback [, Options])        -> { Value, Set, Get }
			Options = { Increment = 1, Suffix = " ms", Decimals = 0 }
		Tab:CreateDropdown(Text, Options, Callback [, Default])                -> { Value, Set, Get, Refresh, SetOpen }
		Tab:CreateButton(Text, Callback [, { Danger = true }])                 -> { Fire }
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local Library = {}
Library.Version = "1.0.0"
Library.LogToConsole = true

-- Palette mirrors the CSS tokens (rgba(...) -> Color3 + Transparency)
Library.Theme = {
	Accent = Color3.fromRGB(16, 224, 160),          -- --accent
	Background = Color3.fromRGB(14, 17, 22),        -- --bg
	BackgroundTransparency = 0.08,
	Sidebar = Color3.fromRGB(0, 0, 0),              -- rgba(0,0,0,.15)
	SidebarTransparency = 0.85,
	Surface = Color3.fromRGB(255, 255, 255),        -- --surface rgba(255,255,255,.04)
	SurfaceTransparency = 0.96,
	SurfaceHoverTransparency = 0.93,                -- --surface-hover .07
	Border = Color3.fromRGB(255, 255, 255),         -- --border .08
	BorderTransparency = 0.92,
	Text = Color3.fromRGB(230, 233, 239),           -- --text
	TextDim = Color3.fromRGB(138, 147, 163),        -- --text-dim
	Danger = Color3.fromRGB(255, 107, 129),
	TrackOff = Color3.fromRGB(255, 255, 255),
	TrackOffTransparency = 0.88,
	KnobOff = Color3.fromRGB(196, 202, 212),
	Font = Enum.Font.Gotham,
	FontMedium = Enum.Font.GothamMedium,
	FontBold = Enum.Font.GothamBold,
	FontMono = Enum.Font.RobotoMono,
}

local Window = {}
Window.__index = Window

local Tab = {}
Tab.__index = Tab

--------------------------------------------------------------------------
-- Utilities
--------------------------------------------------------------------------

local FAST = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local SPRING = TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local SMOOTH = TweenInfo.new(0.22, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

local function create(className, props, children)
	local inst = Instance.new(className)
	if inst:IsA("GuiObject") then
		inst.BorderSizePixel = 0
	end
	local parent
	for key, value in pairs(props or {}) do
		if key == "Parent" then
			parent = value
		else
			inst[key] = value
		end
	end
	for _, child in ipairs(children or {}) do
		child.Parent = inst
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

local function corner(px)
	return create("UICorner", { CornerRadius = UDim.new(0, px) })
end

local function stroke(color, transparency, thickness)
	return create("UIStroke", {
		Color = color,
		Transparency = transparency,
		Thickness = thickness or 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border, -- never outline the text of buttons/labels
	})
end

local function padding(top, right, bottom, left)
	return create("UIPadding", {
		PaddingTop = UDim.new(0, top),
		PaddingRight = UDim.new(0, right),
		PaddingBottom = UDim.new(0, bottom),
		PaddingLeft = UDim.new(0, left),
	})
end

local function list(gap, direction, vAlign)
	return create("UIListLayout", {
		Padding = UDim.new(0, gap),
		SortOrder = Enum.SortOrder.LayoutOrder,
		FillDirection = direction or Enum.FillDirection.Vertical,
		VerticalAlignment = vAlign or Enum.VerticalAlignment.Top,
	})
end

local function label(props, children)
	local T = Library.Theme
	local base = {
		BackgroundTransparency = 1,
		Font = T.Font,
		TextSize = 13,
		TextColor3 = T.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "",
	}
	for k, v in pairs(props) do
		base[k] = v
	end
	return create("TextLabel", base, children)
end

local function button(props, children)
	local base = { Text = "", AutoButtonColor = false, BackgroundTransparency = 1 }
	for k, v in pairs(props) do
		base[k] = v
	end
	return create("TextButton", base, children)
end

local function tween(inst, props, info)
	local t = TweenService:Create(inst, info or FAST, props)
	t:Play()
	return t
end

local function apply(inst, props)
	for k, v in pairs(props) do
		inst[k] = v
	end
end

local function isPress(input)
	return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
end

local function isMove(input)
	return input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch
end

local function toHex(c)
	return string.format("#%02X%02X%02X", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
end

local function escape(s)
	return (tostring(s):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

local function decimalsOf(n)
	local s = tostring(n)
	local dot = string.find(s, ".", 1, true)
	return dot and (#s - dot) or 0
end

local function timestamp()
	return DateTime.now():FormatLocalTime("HH:mm:ss", "en-us")
end

local function safeCall(fn, ...)
	if fn then
		task.spawn(fn, ...)
	end
end

-- CoreGui when we have permission (plugins / command bar), otherwise PlayerGui.
local function getGuiParent()
	local ok, coreGui = pcall(function()
		local cg = game:GetService("CoreGui")
		local probe = Instance.new("Folder")
		probe.Parent = cg
		probe:Destroy()
		return cg
	end)
	if ok and coreGui then
		return coreGui
	end
	local player = Players.LocalPlayer
	if player then
		return player:WaitForChild("PlayerGui")
	end
	error("[DebugKit] No GUI container available: run from a LocalScript or with CoreGui access")
end

-- Frame that rounds only one horizontal edge (top or bottom) without overlapping
-- a neighbour, so semi-transparent tints never double up at the seams.
local function edgeCap(parent, position, width, top, color, transparency, extendRight)
	local clip = create("Frame", {
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		Position = position,
		Size = width,
		Parent = parent,
	})
	return create("Frame", {
		BackgroundColor3 = color,
		BackgroundTransparency = transparency,
		Position = top and UDim2.new() or UDim2.fromOffset(0, -8),
		Size = UDim2.new(1, extendRight or 0, 0, 16),
		Parent = clip,
	}, { corner(8) })
end

--------------------------------------------------------------------------
-- Window
--------------------------------------------------------------------------

function Library:CreateWindow(title, options)
	options = options or {}
	local T = self.Theme
	title = tostring(title or "DebugKit")

	local window = setmetatable({}, Window)
	window.Title = title
	window.Accent = options.Accent or T.Accent
	window.Keybind = options.Keybind or Enum.KeyCode.Insert
	window.Minimized = false
	window.Tabs = {}
	window._toggles = {}
	window._dropdowns = {}
	window._elements = {}
	window._accentHooks = {}
	window._connections = {}

	local W = options.Size and options.Size.X or 540
	local H = options.Size and options.Size.Y or 380
	local SIDEBAR = 128
	local HEADER = 38
	local FOOTER = 26

	-- Replace a previous copy (handy when re-running via loadstring)
	local parent = getGuiParent()
	local guiName = "DebugKit_" .. title
	local old = parent:FindFirstChild(guiName)
	if old then
		old:Destroy()
	end

	local gui = create("ScreenGui", {
		Name = guiName,
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 999,
	})
	window.Gui = gui

	-- Main frame ------------------------------------------------------------
	local main = create("Frame", {
		Name = "Main",
		Size = UDim2.fromOffset(W, H),
		Position = UDim2.fromOffset(80, 80),
		BackgroundColor3 = T.Background,
		BackgroundTransparency = T.BackgroundTransparency,
		Active = true,
		Parent = gui,
	}, { corner(8), stroke(T.Border, T.BorderTransparency) })
	local mainScale = create("UIScale", { Parent = main })
	window._main = main

	-- Title bar -------------------------------------------------------------
	local titlebar = create("Frame", {
		Name = "Titlebar",
		Size = UDim2.new(1, 0, 0, HEADER),
		BackgroundTransparency = 1,
		Parent = main,
	})

	-- Accent tint: linear-gradient(90deg, accent .08, transparent 60%)
	local function tintGradient()
		return create("UIGradient", {
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.9),
				NumberSequenceKeypoint.new(0.6, 1),
				NumberSequenceKeypoint.new(1, 1),
			}),
		})
	end
	local tintBody = create("Frame", {
		Position = UDim2.fromOffset(0, 8),
		Size = UDim2.new(1, 0, 1, -8),
		Parent = titlebar,
	}, { tintGradient() })
	local tintCap = edgeCap(titlebar, UDim2.new(), UDim2.new(1, 0, 0, 8), true, window.Accent, 0)
	tintGradient().Parent = tintCap

	local titleGroup = create("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(12, 0),
		Size = UDim2.new(1, -120, 1, 0),
		Parent = titlebar,
	}, { list(8, Enum.FillDirection.Horizontal, Enum.VerticalAlignment.Center) })

	local dot = create("Frame", { Size = UDim2.fromOffset(8, 8), LayoutOrder = 1, Parent = titleGroup }, { corner(4) })
	local dotGlow = stroke(window.Accent, 0.6, 2)
	dotGlow.Parent = dot
	TweenService:Create(dot, TweenInfo.new(1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
		BackgroundTransparency = 0.55,
	}):Play()
	TweenService:Create(dotGlow, TweenInfo.new(1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
		Transparency = 0.9,
	}):Play()

	label({
		Text = title,
		Font = T.FontBold,
		TextSize = 13,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromScale(0, 1),
		LayoutOrder = 2,
		Parent = titleGroup,
	})
	label({
		Text = options.Subtitle or ("v" .. Library.Version),
		Font = T.FontMono,
		TextSize = 10,
		TextColor3 = T.TextDim,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromScale(0, 1),
		LayoutOrder = 3,
		Parent = titleGroup,
	})

	local fpsLabel = label({
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -42, 0.5, 0),
		Size = UDim2.fromOffset(60, 16),
		Font = T.FontMono,
		TextSize = 11,
		TextColor3 = T.TextDim,
		TextXAlignment = Enum.TextXAlignment.Right,
		Text = "-- FPS",
		Parent = titlebar,
	})
	window._fps = fpsLabel

	local minimizeBtn = button({
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -8, 0.5, 0),
		Size = UDim2.fromOffset(26, 26),
		BackgroundColor3 = T.Surface,
		Parent = titlebar,
	}, { corner(6) })
	local minusBar = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(10, 2),
		BackgroundColor3 = T.TextDim,
		Parent = minimizeBtn,
	}, { corner(1) })
	minimizeBtn.MouseEnter:Connect(function()
		tween(minimizeBtn, { BackgroundTransparency = T.SurfaceHoverTransparency })
		tween(minusBar, { BackgroundColor3 = T.Text })
	end)
	minimizeBtn.MouseLeave:Connect(function()
		tween(minimizeBtn, { BackgroundTransparency = 1 })
		tween(minusBar, { BackgroundColor3 = T.TextDim })
	end)

	local function divider(position, size)
		return create("Frame", {
			Position = position,
			Size = size,
			BackgroundColor3 = T.Border,
			BackgroundTransparency = T.BorderTransparency,
			Parent = main,
		})
	end
	divider(UDim2.fromOffset(0, HEADER), UDim2.new(1, 0, 0, 1))

	-- Sidebar ---------------------------------------------------------------
	create("Frame", {
		Position = UDim2.fromOffset(0, HEADER + 1),
		Size = UDim2.new(0, SIDEBAR, 1, -(HEADER + 1) - 8),
		BackgroundColor3 = T.Sidebar,
		BackgroundTransparency = T.SidebarTransparency,
		Parent = main,
	})
	edgeCap(main, UDim2.new(0, 0, 1, -8), UDim2.fromOffset(SIDEBAR, 8), false, T.Sidebar, T.SidebarTransparency, 8)
	divider(UDim2.fromOffset(SIDEBAR, HEADER + 1), UDim2.new(0, 1, 1, -(HEADER + 1)))

	window._tabList = create("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, HEADER + 1),
		Size = UDim2.new(0, SIDEBAR, 1, -(HEADER + 1) - 28),
		Parent = main,
	}, { padding(8, 8, 8, 8), list(2) })

	local counter = label({
		Position = UDim2.new(0, 0, 1, -28),
		Size = UDim2.fromOffset(SIDEBAR, 22),
		Font = T.FontMono,
		TextSize = 11,
		TextColor3 = T.TextDim,
		RichText = true,
		Parent = main,
	}, { padding(0, 0, 0, 18) })
	window._counter = counter

	-- Content + footer log --------------------------------------------------
	window._content = create("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(SIDEBAR + 1, HEADER + 1),
		Size = UDim2.new(1, -(SIDEBAR + 1), 1, -(HEADER + 1) - FOOTER - 1),
		Parent = main,
	})

	divider(UDim2.new(0, SIDEBAR + 1, 1, -FOOTER - 1), UDim2.new(1, -(SIDEBAR + 1), 0, 1))
	local logBar = create("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, SIDEBAR + 1, 1, -FOOTER),
		Size = UDim2.new(1, -(SIDEBAR + 1), 0, FOOTER),
		Parent = main,
	}, { padding(0, 12, 0, 12), list(8, Enum.FillDirection.Horizontal, Enum.VerticalAlignment.Center) })
	window._logTime = label({
		Text = "--:--:--",
		Font = T.FontMono,
		TextSize = 11,
		TextColor3 = T.TextDim,
		TextTransparency = 0.4,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromScale(0, 1),
		LayoutOrder = 1,
		Parent = logBar,
	})
	window._logMsg = label({
		Text = "Overlay ready",
		Font = T.FontMono,
		TextSize = 11,
		TextColor3 = T.TextDim,
		RichText = true,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Size = UDim2.new(1, -66, 1, 0),
		LayoutOrder = 2,
		Parent = logBar,
	})

	-- Minimized bubble ------------------------------------------------------
	local bubble = button({
		Name = "Bubble",
		Size = UDim2.fromOffset(44, 44),
		Position = UDim2.fromOffset(80, 80),
		BackgroundColor3 = T.Background,
		BackgroundTransparency = T.BackgroundTransparency,
		Visible = false,
		Parent = gui,
	}, { corner(12) })
	local bubbleStroke = stroke(window.Accent, 0.65)
	bubbleStroke.Parent = bubble
	local bubbleScale = create("UIScale", { Parent = bubble })
	local diamond = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(14, 14),
		Rotation = 45,
		BackgroundTransparency = 1,
		Parent = bubble,
	}, { corner(3) })
	local diamondStroke = stroke(window.Accent, 0, 2)
	diamondStroke.Parent = diamond
	local diamondCore = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(4, 4),
		Rotation = 45,
		Parent = bubble,
	}, { corner(1) })
	local badge = create("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 5, 0, -5),
		Size = UDim2.fromOffset(16, 16),
		Parent = bubble,
	}, { corner(8) })
	local badgeText = label({
		Size = UDim2.fromScale(1, 1),
		Font = T.FontBold,
		TextSize = 10,
		TextColor3 = Color3.fromRGB(4, 18, 12),
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = "0",
		Parent = badge,
	})
	window._badge, window._badgeText = badge, badgeText

	-- Window-level accent bindings
	window:_onAccent(function(c)
		tintBody.BackgroundColor3 = c
		tintCap.BackgroundColor3 = c
		dot.BackgroundColor3 = c
		dotGlow.Color = c
		bubbleStroke.Color = c
		diamondStroke.Color = c
		diamondCore.BackgroundColor3 = c
		badge.BackgroundColor3 = c
		window:_updateCounter()
	end)

	gui.Parent = parent

	-- Dragging (smooth, clamped to the viewport) ----------------------------
	local function clampPos(target, pos)
		local vp = gui.AbsoluteSize
		local w, h = target.Size.X.Offset, target.Size.Y.Offset
		return Vector2.new(math.clamp(pos.X, 0, math.max(0, vp.X - w)), math.clamp(pos.Y, 0, math.max(0, vp.Y - h)))
	end
	local function getPos(target)
		return Vector2.new(target.Position.X.Offset, target.Position.Y.Offset)
	end
	local function setPos(target, pos)
		target.Position = UDim2.fromOffset(pos.X, pos.Y)
	end

	local function makeDraggable(target, handle, onClick)
		local dragging, dragInput, startInput, startPos, moved, goal = false, nil, nil, nil, false, nil

		handle.InputBegan:Connect(function(input)
			if not isPress(input) then
				return
			end
			dragging, moved, dragInput = true, false, input
			startInput = input.Position
			startPos = getPos(target)
			goal = nil
		end)

		window:_connect(UserInputService.InputChanged:Connect(function(input)
			if not dragging or not isMove(input) then
				return
			end
			if input.UserInputType == Enum.UserInputType.Touch and input ~= dragInput then
				return
			end
			local delta = input.Position - startInput
			local d = Vector2.new(delta.X, delta.Y)
			if not moved and d.Magnitude < 3 then
				return
			end
			moved = true
			goal = clampPos(target, startPos + d)
		end))

		window:_connect(UserInputService.InputEnded:Connect(function(input)
			if not dragging then
				return
			end
			if input == dragInput or input.UserInputType == Enum.UserInputType.MouseButton1 then
				dragging = false
				if not moved and onClick then
					onClick()
				end
			end
		end))

		-- Exponential smoothing toward the cursor target
		window:_connect(RunService.RenderStepped:Connect(function(dt)
			if not goal then
				return
			end
			local nextPos = getPos(target):Lerp(goal, 1 - math.exp(-dt * 30))
			if (goal - nextPos).Magnitude < 0.5 then
				nextPos = goal
				if not dragging then
					goal = nil
				end
			end
			setPos(target, nextPos)
		end))
	end

	-- Minimize / restore ----------------------------------------------------
	function window:Minimize()
		if self.Minimized then
			return
		end
		self.Minimized = true
		self:_closeDropdowns()
		setPos(bubble, clampPos(bubble, getPos(main)))
		local t = tween(mainScale, { Scale = 0.9 }, TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.In))
		t.Completed:Once(function()
			if self.Minimized then
				main.Visible = false
			end
		end)
		bubble.Visible = true
		bubbleScale.Scale = 0.5
		tween(bubbleScale, { Scale = 1 }, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out))
		self:Log("Window <b>minimized</b>")
	end

	function window:Restore()
		if not self.Minimized then
			return
		end
		self.Minimized = false
		setPos(main, clampPos(main, getPos(bubble)))
		local t = tween(bubbleScale, { Scale = 0.5 }, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.In))
		t.Completed:Once(function()
			if not self.Minimized then
				bubble.Visible = false
			end
		end)
		main.Visible = true
		mainScale.Scale = 0.9
		tween(mainScale, { Scale = 1 }, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out))
		self:Log("Window <b>restored</b>")
	end

	makeDraggable(main, titlebar)
	makeDraggable(bubble, bubble, function()
		window:Restore()
	end)
	minimizeBtn.MouseButton1Click:Connect(function()
		window:Minimize()
	end)

	-- Hotkey
	window:_connect(UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == window.Keybind then
			window:ToggleVisibility()
		end
	end))

	-- Keep inside the screen when the viewport changes
	window:_connect(gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		setPos(main, clampPos(main, getPos(main)))
		setPos(bubble, clampPos(bubble, getPos(bubble)))
	end))

	-- FPS counter
	local frames, last = 0, os.clock()
	window:_connect(RunService.RenderStepped:Connect(function()
		frames += 1
		local now = os.clock()
		if now - last >= 0.5 then
			fpsLabel.Text = math.floor(frames / (now - last) + 0.5) .. " FPS"
			frames, last = 0, now
		end
	end))

	window:_updateCounter()
	return window
end

-- Internal helpers ----------------------------------------------------------

function Window:_connect(connection)
	table.insert(self._connections, connection)
	return connection
end

function Window:_onAccent(fn)
	table.insert(self._accentHooks, fn)
	fn(self.Accent)
end

function Window:_closeDropdowns(except)
	for _, dd in ipairs(self._dropdowns) do
		if dd ~= except and dd.Open then
			dd:SetOpen(false)
		end
	end
end

function Window:_updateCounter()
	local n = 0
	for _, t in ipairs(self._toggles) do
		if t.Value then
			n += 1
		end
	end
	self._counter.Text = string.format('<font color="%s"><b>%d</b></font> active', toHex(self.Accent), n)
	self._badgeText.Text = tostring(n)
	self._badge.Visible = n > 0
end

-- Public window methods -----------------------------------------------------

-- Writes to the footer status bar (and Output). <b>text</b> is shown in the accent color.
function Window:Log(message, toConsole)
	local T = Library.Theme
	local hex = toHex(self.Accent)
	self._logTime.Text = timestamp()
	self._logMsg.Text = (message:gsub("<b>", '<font color="' .. hex .. '">'):gsub("</b>", "</font>"))
	self._logMsg.TextColor3 = T.Text
	tween(self._logMsg, { TextColor3 = T.TextDim }, TweenInfo.new(0.4))
	if Library.LogToConsole and toConsole ~= false then
		print("[DebugKit] " .. (message:gsub("<[^>]->", ""):gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&amp;", "&")))
	end
end

function Window:SetAccent(color)
	self.Accent = color
	for _, fn in ipairs(self._accentHooks) do
		fn(color)
	end
end

function Window:SetFpsVisible(visible)
	self._fps.Visible = visible
end

function Window:ToggleVisibility()
	if self.Minimized then
		self:Restore()
	else
		self:Minimize()
	end
end

function Window:SelectTab(tab)
	for _, t in ipairs(self.Tabs) do
		t:_setActive(t == tab)
	end
	self.ActiveTab = tab
	self:_closeDropdowns()
end

-- Restores every element to the default it was created with.
function Window:Reset()
	for _, el in ipairs(self._elements) do
		el:Set(el.Default, true)
	end
	self:Log("All settings <b>reset</b> to defaults")
	for _, el in ipairs(self._elements) do
		safeCall(el._callback, el.Value)
	end
end

function Window:Destroy()
	for _, c in ipairs(self._connections) do
		c:Disconnect()
	end
	table.clear(self._connections)
	self.Gui:Destroy()
end

--------------------------------------------------------------------------
-- Tabs
--------------------------------------------------------------------------

function Window:CreateTab(name, icon)
	local T = Library.Theme
	local window = self
	local tab = setmetatable({ Window = window, Name = tostring(name), _order = 0, Active = false, _hover = false }, Tab)

	local btn = button({
		Size = UDim2.new(1, 0, 0, 32),
		BackgroundColor3 = T.Surface,
		LayoutOrder = #self.Tabs + 1,
		Parent = self._tabList,
	}, { corner(6) })

	-- Active indicator (CSS ::before bar on the sidebar edge)
	local indicator = create("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, -8, 0.5, 0),
		Size = UDim2.fromOffset(3, 0),
		Parent = btn,
	}, { corner(2) })

	local textX = 10
	local iconImage
	if icon then
		iconImage = create("ImageLabel", {
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 10, 0.5, 0),
			Size = UDim2.fromOffset(15, 15),
			Image = typeof(icon) == "number" and ("rbxassetid://" .. icon) or tostring(icon),
			ImageColor3 = T.TextDim,
			Parent = btn,
		})
		textX = 33
	end

	local text = label({
		Position = UDim2.fromOffset(textX, 0),
		Size = UDim2.new(1, -textX - 4, 1, 0),
		Font = T.FontMedium,
		TextSize = 13,
		TextColor3 = T.TextDim,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Text = tab.Name,
		Parent = btn,
	})

	local page = create("ScrollingFrame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = Color3.new(1, 1, 1),
		ScrollBarImageTransparency = 0.85,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Visible = false,
		Parent = self._content,
	}, { list(6) })
	local pagePadding = padding(12, 14, 12, 14)
	pagePadding.Parent = page
	tab.Page = page

	local function render(instant)
		local a = window.Accent
		local textColor = tab.Active and a or (tab._hover and T.Text or T.TextDim)
		local props = {
			BackgroundColor3 = tab.Active and a or T.Surface,
			BackgroundTransparency = tab.Active and 0.9 or (tab._hover and T.SurfaceTransparency or 1),
		}
		local ind = { Size = UDim2.fromOffset(3, tab.Active and 18 or 0) }
		if instant then
			apply(btn, props)
			apply(indicator, ind)
			text.TextColor3 = textColor
		else
			tween(btn, props)
			tween(indicator, ind, SPRING)
			tween(text, { TextColor3 = textColor })
		end
		indicator.BackgroundColor3 = a
		if iconImage then
			iconImage.ImageColor3 = textColor
		end
	end

	function tab:_setActive(active)
		if self.Active == active then
			return
		end
		self.Active = active
		page.Visible = active
		if active then
			-- small slide-up, like the CSS fadeIn keyframes
			pagePadding.PaddingTop = UDim.new(0, 20)
			tween(pagePadding, { PaddingTop = UDim.new(0, 12) }, SMOOTH)
		end
		render(false)
	end

	btn.MouseEnter:Connect(function()
		tab._hover = true
		render(false)
	end)
	btn.MouseLeave:Connect(function()
		tab._hover = false
		render(false)
	end)
	btn.MouseButton1Click:Connect(function()
		if not tab.Active then
			window:SelectTab(tab)
			window:Log("Tab → <b>" .. escape(tab.Name) .. "</b>", false)
		end
	end)

	window:_onAccent(function()
		render(true)
	end)

	table.insert(self.Tabs, tab)
	if #self.Tabs == 1 then
		window:SelectTab(tab)
	end
	return tab
end

-- Base row: surface background, 6px radius, border shown on hover.
function Tab:_row(height, clickable, customHover)
	local T = Library.Theme
	self._order += 1
	local row = create(clickable and "TextButton" or "Frame", {
		Size = UDim2.new(1, 0, 0, height),
		BackgroundColor3 = T.Surface,
		BackgroundTransparency = T.SurfaceTransparency,
		LayoutOrder = self._order,
		Parent = self.Page,
	}, { corner(6) })
	if clickable then
		row.Text = ""
		row.AutoButtonColor = false
	end
	local rowStroke = stroke(T.Border, 1)
	rowStroke.Parent = row
	if not customHover then
		row.MouseEnter:Connect(function()
			tween(row, { BackgroundTransparency = T.SurfaceHoverTransparency })
			tween(rowStroke, { Transparency = T.BorderTransparency })
		end)
		row.MouseLeave:Connect(function()
			tween(row, { BackgroundTransparency = T.SurfaceTransparency })
			tween(rowStroke, { Transparency = 1 })
		end)
	end
	return row, rowStroke
end

local function rowLabel(parent, text, description, rightInset)
	local T = Library.Theme
	local holder = create("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(10, 0),
		Size = UDim2.new(1, -(rightInset or 60), 1, 0),
		Parent = parent,
	}, { list(1, Enum.FillDirection.Vertical, Enum.VerticalAlignment.Center) })
	label({
		Size = UDim2.new(1, 0, 0, 16),
		Font = T.FontMedium,
		TextSize = 13,
		Text = text,
		TextTruncate = Enum.TextTruncate.AtEnd,
		LayoutOrder = 1,
		Parent = holder,
	})
	if description then
		label({
			Size = UDim2.new(1, 0, 0, 13),
			TextSize = 11,
			TextColor3 = T.TextDim,
			Text = description,
			TextTruncate = Enum.TextTruncate.AtEnd,
			LayoutOrder = 2,
			Parent = holder,
		})
	end
	return holder
end

--------------------------------------------------------------------------
-- Section label
--------------------------------------------------------------------------

function Tab:CreateSection(text)
	local T = Library.Theme
	self._order += 1
	return label({
		Size = UDim2.new(1, 0, 0, 18),
		Font = T.FontBold,
		TextSize = 10,
		TextColor3 = T.TextDim,
		TextYAlignment = Enum.TextYAlignment.Bottom,
		Text = string.upper(tostring(text)),
		LayoutOrder = self._order,
		Parent = self.Page,
	}, { padding(0, 0, 2, 2) })
end

--------------------------------------------------------------------------
-- Toggle
--------------------------------------------------------------------------

function Tab:CreateToggle(text, default, callback, description)
	local T = Library.Theme
	local window = self.Window
	local toggle = { Type = "Toggle", Value = default == true, Default = default == true, _callback = callback }

	local row = self:_row(description and 44 or 34, true)
	rowLabel(row, text, description, 60)

	local switch = create("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.fromOffset(34, 18),
		Parent = row,
	}, { corner(9) })
	local glow = stroke(window.Accent, 1, 1)
	glow.Parent = switch
	local knob = create("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 3, 0.5, 0),
		Size = UDim2.fromOffset(12, 12),
		Parent = switch,
	}, { corner(6) })

	local function render(instant)
		local a = window.Accent
		local on = toggle.Value
		local sw = on and { BackgroundColor3 = a, BackgroundTransparency = 0.65 }
			or { BackgroundColor3 = T.TrackOff, BackgroundTransparency = T.TrackOffTransparency }
		local kb = { Position = UDim2.new(0, on and 19 or 3, 0.5, 0), BackgroundColor3 = on and a or T.KnobOff }
		glow.Color = a
		if instant then
			apply(switch, sw)
			apply(knob, kb)
			glow.Transparency = on and 0.55 or 1
		else
			tween(switch, sw)
			tween(knob, kb, SPRING)
			tween(glow, { Transparency = on and 0.55 or 1 })
		end
	end

	function toggle:Set(value, silent)
		value = value == true
		local changed = value ~= self.Value
		self.Value = value
		render(false)
		window:_updateCounter()
		if changed and not silent then
			window:Log(escape(text) .. " → <b>" .. (value and "ON" or "OFF") .. "</b>")
			safeCall(callback, value)
		end
	end

	function toggle:Get()
		return self.Value
	end

	row.MouseButton1Click:Connect(function()
		toggle:Set(not toggle.Value)
	end)

	window:_onAccent(function()
		render(true)
	end)
	table.insert(window._toggles, toggle)
	table.insert(window._elements, toggle)
	window:_updateCounter()
	return toggle
end

--------------------------------------------------------------------------
-- Slider
--------------------------------------------------------------------------

function Tab:CreateSlider(text, min, max, default, callback, options)
	local T = Library.Theme
	local window = self.Window
	options = options or {}
	min, max = tonumber(min) or 0, tonumber(max) or 100
	default = math.clamp(tonumber(default) or min, min, max)

	local allIntegers = math.floor(min) == min and math.floor(max) == max and math.floor(default) == default
	local increment = options.Increment or (allIntegers and 1 or 0.1)
	local decimals = options.Decimals or decimalsOf(increment)
	local suffix = options.Suffix or ""

	local slider = { Type = "Slider", Value = default, Default = default, _callback = callback }

	local row = self:_row(52)
	label({
		Position = UDim2.fromOffset(10, 8),
		Size = UDim2.new(1, -90, 0, 16),
		Font = T.FontMedium,
		Text = text,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = row,
	})
	local valueLabel = label({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 8),
		Size = UDim2.fromOffset(70, 16),
		Font = T.FontMono,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = row,
	})

	local track = create("Frame", {
		Position = UDim2.new(0, 10, 0, 34),
		Size = UDim2.new(1, -20, 0, 4),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.9,
		Parent = row,
	}, { corner(2) })
	local fill = create("Frame", { Size = UDim2.fromScale(0, 1), Parent = track }, { corner(2) })
	local knob = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromOffset(14, 14),
		BackgroundColor3 = T.Background,
		ZIndex = 2,
		Parent = track,
	}, { corner(7) })
	local knobStroke = stroke(window.Accent, 0, 2)
	knobStroke.Parent = knob
	local knobScale = create("UIScale", { Parent = knob })

	-- Larger invisible hit area for easier grabbing
	local hit = button({
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, -7, 0.5, 0),
		Size = UDim2.new(1, 14, 0, 22),
		ZIndex = 3,
		Parent = track,
	})

	local function format(v)
		return string.format("%." .. decimals .. "f", v) .. suffix
	end

	local function render(instant)
		local alpha = (max == min) and 0 or (slider.Value - min) / (max - min)
		valueLabel.Text = format(slider.Value)
		if instant then
			fill.Size = UDim2.fromScale(alpha, 1)
			knob.Position = UDim2.fromScale(alpha, 0.5)
		else
			local info = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			tween(fill, { Size = UDim2.fromScale(alpha, 1) }, info)
			tween(knob, { Position = UDim2.fromScale(alpha, 0.5) }, info)
		end
	end

	function slider:Set(value, silent, quietConsole)
		value = math.clamp(tonumber(value) or min, min, max)
		value = math.floor((value - min) / increment + 0.5) * increment + min
		value = math.clamp(tonumber(string.format("%." .. decimals .. "f", value)), min, max)
		if value == self.Value then
			render(false)
			return
		end
		self.Value = value
		render(false)
		if not silent then
			window:Log(escape(text) .. " → <b>" .. format(value) .. "</b>", not quietConsole)
			safeCall(callback, value)
		end
	end

	function slider:Get()
		return self.Value
	end

	local dragging, dragInput = false, nil
	local function updateFromX(x)
		local width = track.AbsoluteSize.X
		if width <= 0 then
			return
		end
		local alpha = math.clamp((x - track.AbsolutePosition.X) / width, 0, 1)
		slider:Set(min + alpha * (max - min), false, true) -- console print happens on release
	end

	hit.InputBegan:Connect(function(input)
		if isPress(input) then
			dragging, dragInput = true, input
			tween(knobScale, { Scale = 1.25 }, SPRING)
			updateFromX(input.Position.X)
		end
	end)
	window:_connect(UserInputService.InputChanged:Connect(function(input)
		if dragging and isMove(input) and (input.UserInputType ~= Enum.UserInputType.Touch or input == dragInput) then
			updateFromX(input.Position.X)
		end
	end))
	window:_connect(UserInputService.InputEnded:Connect(function(input)
		if dragging and (input == dragInput or input.UserInputType == Enum.UserInputType.MouseButton1) then
			dragging = false
			tween(knobScale, { Scale = 1 }, SPRING)
			if Library.LogToConsole then
				print("[DebugKit] " .. text .. " = " .. format(slider.Value))
			end
		end
	end))
	hit.MouseEnter:Connect(function()
		if not dragging then
			tween(knobScale, { Scale = 1.15 })
		end
	end)
	hit.MouseLeave:Connect(function()
		if not dragging then
			tween(knobScale, { Scale = 1 })
		end
	end)

	window:_onAccent(function(a)
		fill.BackgroundColor3 = a
		knobStroke.Color = a
		valueLabel.TextColor3 = a
		render(true)
	end)
	table.insert(window._elements, slider)
	return slider
end

--------------------------------------------------------------------------
-- Dropdown
--------------------------------------------------------------------------

function Tab:CreateDropdown(text, optionList, callback, default)
	local T = Library.Theme
	local window = self.Window
	optionList = optionList or {}

	local dropdown = {
		Type = "Dropdown",
		Options = optionList,
		Value = default ~= nil and default or optionList[1],
		Open = false,
		_callback = callback,
	}
	dropdown.Default = dropdown.Value

	local HEADER = 34
	local ITEM = 24
	local GAP = 2

	local row = self:_row(HEADER)
	row.ClipsDescendants = true

	local header = button({ Size = UDim2.new(1, 0, 0, HEADER), Parent = row })
	rowLabel(header, text, nil, 175)

	local box = create("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -6, 0.5, 0),
		Size = UDim2.fromOffset(150, 24),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.75,
		Parent = header,
	}, { corner(6) })
	local boxStroke = stroke(T.Border, T.BorderTransparency)
	boxStroke.Parent = box
	local valueText = label({
		Position = UDim2.fromOffset(9, 0),
		Size = UDim2.new(1, -30, 1, 0),
		TextSize = 12,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = box,
	})
	local chevron = label({
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -8, 0.5, 0),
		Size = UDim2.fromOffset(10, 10),
		TextSize = 8,
		TextColor3 = T.TextDim,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = "▼",
		Parent = box,
	})

	local listFrame = create("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(6, HEADER),
		Size = UDim2.new(1, -12, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = row,
	}, { list(GAP) })

	local items = {}

	local function openHeight()
		local n = #dropdown.Options
		return HEADER + n * ITEM + math.max(n - 1, 0) * GAP + 6
	end

	local function renderSelection()
		local a = window.Accent
		valueText.Text = dropdown.Value ~= nil and tostring(dropdown.Value) or "—"
		for _, item in ipairs(items) do
			local selected = item.Value == dropdown.Value
			item.Text.TextColor3 = selected and a or T.Text
			item.Check.TextColor3 = a
			item.Check.Visible = selected
		end
	end

	local function renderOpen(instant)
		local a = window.Accent
		local open = dropdown.Open
		local rowSize = { Size = UDim2.new(1, 0, 0, open and openHeight() or HEADER) }
		local chev = { Rotation = open and 180 or 0, TextColor3 = open and a or T.TextDim }
		local st = { Color = open and a or T.Border, Transparency = open and 0.5 or T.BorderTransparency }
		if instant then
			apply(row, rowSize)
			apply(chevron, chev)
			apply(boxStroke, st)
		else
			tween(row, rowSize, SMOOTH)
			tween(chevron, chev, SMOOTH)
			tween(boxStroke, st)
		end
	end

	local function build()
		for _, item in ipairs(items) do
			item.Button:Destroy()
		end
		table.clear(items)
		for i, option in ipairs(dropdown.Options) do
			local optBtn = button({
				Size = UDim2.new(1, 0, 0, ITEM),
				BackgroundColor3 = T.Surface,
				LayoutOrder = i,
				Parent = listFrame,
			}, { corner(4) })
			local optText = label({
				Position = UDim2.fromOffset(8, 0),
				Size = UDim2.new(1, -30, 1, 0),
				TextSize = 12,
				Text = tostring(option),
				TextTruncate = Enum.TextTruncate.AtEnd,
				Parent = optBtn,
			})
			local check = label({
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -8, 0.5, 0),
				Size = UDim2.fromOffset(12, 12),
				TextSize = 11,
				TextXAlignment = Enum.TextXAlignment.Center,
				Text = "✓",
				Visible = false,
				Parent = optBtn,
			})
			optBtn.MouseEnter:Connect(function()
				tween(optBtn, { BackgroundTransparency = T.SurfaceHoverTransparency })
			end)
			optBtn.MouseLeave:Connect(function()
				tween(optBtn, { BackgroundTransparency = 1 })
			end)
			optBtn.MouseButton1Click:Connect(function()
				dropdown:Set(option)
				dropdown:SetOpen(false)
			end)
			table.insert(items, { Button = optBtn, Text = optText, Check = check, Value = option })
		end
		renderSelection()
	end

	function dropdown:SetOpen(open)
		if open then
			window:_closeDropdowns(self)
		end
		self.Open = open == true
		renderOpen(false)
	end

	function dropdown:Set(value, silent)
		local changed = value ~= self.Value
		self.Value = value
		renderSelection()
		if changed and not silent then
			window:Log(escape(text) .. " → <b>" .. escape(value) .. "</b>")
			safeCall(callback, value)
		end
	end

	function dropdown:Get()
		return self.Value
	end

	function dropdown:Refresh(newOptions, keepValue)
		self.Options = newOptions or {}
		if not keepValue or not table.find(self.Options, self.Value) then
			self.Value = self.Options[1]
		end
		build()
		renderOpen(true)
	end

	header.MouseButton1Click:Connect(function()
		dropdown:SetOpen(not dropdown.Open)
	end)
	header.MouseEnter:Connect(function()
		if not dropdown.Open then
			tween(boxStroke, { Color = window.Accent, Transparency = 0.5 })
		end
	end)
	header.MouseLeave:Connect(function()
		if not dropdown.Open then
			tween(boxStroke, { Color = T.Border, Transparency = T.BorderTransparency })
		end
	end)

	build()
	window:_onAccent(function()
		renderSelection()
		renderOpen(true)
	end)
	table.insert(window._dropdowns, dropdown)
	table.insert(window._elements, dropdown)
	return dropdown
end

--------------------------------------------------------------------------
-- Button
--------------------------------------------------------------------------

function Tab:CreateButton(text, callback, options)
	local T = Library.Theme
	local window = self.Window
	options = options or {}
	local color = options.Danger and T.Danger or T.Text

	local row, rowStroke = self:_row(32, true, true)
	local scale = create("UIScale", { Parent = row })
	local textLabel = label({
		Size = UDim2.fromScale(1, 1),
		Font = T.FontBold,
		TextSize = 12,
		TextColor3 = color,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = text,
		Parent = row,
	})

	local idleStroke = options.Danger and { Color = T.Danger, Transparency = 0.7 } or { Color = T.Border, Transparency = T.BorderTransparency }
	apply(rowStroke, idleStroke)

	row.MouseEnter:Connect(function()
		if options.Danger then
			tween(row, { BackgroundColor3 = T.Danger, BackgroundTransparency = 0.88 })
			tween(rowStroke, { Transparency = 0.45 })
		else
			tween(row, { BackgroundTransparency = T.SurfaceHoverTransparency })
		end
	end)
	row.MouseLeave:Connect(function()
		tween(row, { BackgroundColor3 = T.Surface, BackgroundTransparency = T.SurfaceTransparency })
		tween(rowStroke, idleStroke)
		tween(scale, { Scale = 1 })
	end)
	row.MouseButton1Down:Connect(function()
		tween(scale, { Scale = 0.97 }, TweenInfo.new(0.08))
	end)
	row.MouseButton1Up:Connect(function()
		tween(scale, { Scale = 1 }, SPRING)
	end)

	local btnObj = { Type = "Button" }
	function btnObj:Fire()
		-- accent flash on the border
		local flashColor = options.Danger and T.Danger or window.Accent
		rowStroke.Color = flashColor
		rowStroke.Transparency = 0.2
		tween(rowStroke, idleStroke, TweenInfo.new(0.4))
		textLabel.TextColor3 = flashColor
		tween(textLabel, { TextColor3 = color }, TweenInfo.new(0.4))
		window:Log("Button <b>" .. escape(text) .. "</b> pressed")
		safeCall(callback)
	end

	row.MouseButton1Click:Connect(function()
		btnObj:Fire()
	end)
	return btnObj
end

return Library

--[[ ===================================================================
	EXAMPLE (LocalScript in StarterPlayerScripts):

	local Library = require(game.ReplicatedStorage:WaitForChild("DebugKit"))
	-- or: local Library = loadstring(source)()

	local Window = Library:CreateWindow("DebugKit", { Subtitle = "v1.4", Keybind = Enum.KeyCode.Insert })

	local Main = Window:CreateTab("Main")
	Main:CreateSection("Automation")
	Main:CreateToggle("Auto Action", false, function(on) print("Auto Action:", on) end, "Автоматически выполнять действие")
	Main:CreateToggle("Safe Distance", true, function(on) print("Safe Distance:", on) end)
	Main:CreateDropdown("Target Priority", { "Nearest", "Lowest HP", "Highest Threat", "Manual" }, function(v) print("Target:", v) end)
	Main:CreateSlider("Reaction Delay", 0, 500, 120, function(v) print("Delay:", v) end, { Increment = 10, Suffix = " ms" })

	local Visuals = Window:CreateTab("Visuals")
	Visuals:CreateToggle("Entity Highlight", false, function(on) print("Highlight:", on) end)
	Visuals:CreateSlider("Camera FOV", 60, 120, 70, function(v) workspace.CurrentCamera.FieldOfView = v end, { Suffix = "°" })

	local Movement = Window:CreateTab("Movement")
	Movement:CreateToggle("No Clip", false, function(on) print("No Clip:", on) end)
	Movement:CreateSlider("Speed Multiplier", 0.1, 5, 1, function(v) print("Speed:", v) end, { Suffix = "×" })
	Movement:CreateSlider("Height Offset", -10, 10, 0, function(v) print("Height:", v) end, { Increment = 0.5, Suffix = " m" })

	local Settings = Window:CreateTab("Settings")
	Settings:CreateDropdown("Accent Color", { "Emerald", "Cyan", "Violet" }, function(name)
		local colors = { Emerald = Color3.fromRGB(16, 224, 160), Cyan = Color3.fromRGB(34, 211, 238), Violet = Color3.fromRGB(168, 120, 255) }
		Window:SetAccent(colors[name])
	end)
	Settings:CreateButton("Reset All", function() Window:Reset() end, { Danger = true })

	A fuller runnable version lives in Example.client.lua next to this file.
=================================================================== ]]
