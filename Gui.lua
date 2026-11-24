--[[
	DebugKit UI Library v2 (Luau / Roblox) — "tactical HUD" skin
	Visual port of the AERO // MM2 design concept: square panels, accent corner brackets,
	numbered tabs, per-tab banners (optional photo), stat cards, button grids.

	Single file, no external modules. Returns the Library table:
		local Library = require(ReplicatedStorage.DebugKit)   -- ModuleScript
		local Library = loadstring(source)()                  -- where loadstring is available

	API (v1 calls keep working)
		Library:CreateWindow(Title [, Options])                -> Window
			Options = { Subtitle, Size = Vector2, Accent = Color3, Keybind = Enum.KeyCode }
		Library:LoadImage(source [, cacheName])                -> imageId | nil, err
			source = "rbxassetid://…" | local workspace path | "https://…" (HttpGet → writefile → getcustomasset)
		Library.Strings                                        -- built-in UI text, override for localisation

		Window:CreateTab(Name [, IconImage] [, TabOptions])    -> Tab
			TabOptions = { Banner = imageId, Meta = "text", ShowBanner = true }
		Window:SetAccent(Color3) / :SetFpsVisible(bool) / :SetStatus(text|nil) / :SetScale(0.5–1.5)
		Window:Minimize() / :Restore() / :ToggleVisibility() / :SelectTab(tab)
		Window:Reset() / :Log(text) / :Destroy()

		Tab:SetBanner(imageId|nil) / Tab:SetMeta(text)
		Tab:CreateSection(Text)                                -> TextLabel
		Tab:CreateLabel(Text [, { Mono = true }])              -> { Set, Get, Instance }
		Tab:CreateToggle(Text, Default, Callback [, Description])              -> { Value, Set, Get }
		Tab:CreateSlider(Text, Min, Max, Default, Callback [, Options])        -> { Value, Set, Get }
			Options = { Increment = 1, Suffix = " ms", Decimals = 0 }
		Tab:CreateDropdown(Text, Options, Callback [, Default])                -> { Value, Set, Get, Refresh, SetOpen }
		Tab:CreateButton(Text, Callback [, { Danger = true } | { Primary = true }]) -> { Fire }
		Tab:CreateButtonGrid(Columns, { { Text, Callback, Options? }, … })    -> { [i] = { Fire } }
		Tab:CreateStats(Columns, { { Key, Label, Value?, Sub?, Tone? }, … })   -> { Set(key, fields) }
			Tone = "accent" | "danger" | "info" | "success" | "muted" | Color3
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local Library = {}
Library.Version = "2.1.0"
Library.LogToConsole = true

-- Built-in UI strings; override (e.g. for localisation) before creating the window.
-- Entries with %s receive one escaped argument.
Library.Strings = {
	Ready = "Overlay ready",
	Active = "ACTIVE",
	Minimized = "Window <b>minimized</b>",
	Restored = "Window <b>restored</b>",
	Reset = "All settings <b>reset</b> to defaults",
	TabSwitched = "Tab → <b>%s</b>",
	ButtonPressed = "Button <b>%s</b> pressed",
}

local function pickFont(name, fallback)
	local ok, font = pcall(function()
		return Enum.Font[name]
	end)
	return (ok and font) or fallback
end

Library.Theme = {
	Accent = Color3.fromRGB(255, 184, 28),
	Background = Color3.fromRGB(9, 11, 14),
	BackgroundTransparency = 0.04,
	Panel = Color3.fromRGB(255, 255, 255),
	PanelTransparency = 0.97,
	PanelHoverTransparency = 0.94,
	Border = Color3.fromRGB(255, 255, 255),
	BorderTransparency = 0.92,
	Text = Color3.fromRGB(230, 233, 239),
	TextDim = Color3.fromRGB(138, 147, 163),
	TextFaint = Color3.fromRGB(107, 116, 130),
	Danger = Color3.fromRGB(255, 107, 129),
	Info = Color3.fromRGB(64, 156, 255),
	Success = Color3.fromRGB(124, 255, 178),
	Red = Color3.fromRGB(255, 64, 80),
	Font = Enum.Font.Gotham,
	FontMedium = Enum.Font.GothamMedium,
	FontBold = Enum.Font.GothamBold,
	FontHeading = pickFont("Sarpanch", Enum.Font.GothamBold),
	FontMono = Enum.Font.RobotoMono,
	BracketSize = 14,
	BracketThickness = 2,
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

local function stroke(color, transparency, thickness)
	return create("UIStroke", {
		Color = color,
		Transparency = transparency,
		Thickness = thickness or 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
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

-- gethui() (executors) → CoreGui (plugins / command bar) → PlayerGui.
local function getGuiParent()
	if typeof(gethui) == "function" then
		local ok, hui = pcall(gethui)
		if ok and typeof(hui) == "Instance" then
			return hui
		end
	end
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

-- Four L-shaped accent brackets on the frame's corners: just outside the 1px border,
-- or flush inside it when `inside` is set (needed for frames that clip descendants).
local function brackets(parent, size, thickness, inside)
	local parts = {}
	local o = inside and 0 or 1
	for _, corner in ipairs({ { 0, 0 }, { 1, 0 }, { 0, 1 }, { 1, 1 } }) do
		local ax, ay = corner[1], corner[2]
		local pos = UDim2.new(ax, ax == 0 and -o or o, ay, ay == 0 and -o or o)
		table.insert(parts, create("Frame", {
			AnchorPoint = Vector2.new(ax, ay),
			Position = pos,
			Size = UDim2.fromOffset(size, thickness),
			ZIndex = 5,
			Parent = parent,
		}))
		table.insert(parts, create("Frame", {
			AnchorPoint = Vector2.new(ax, ay),
			Position = pos,
			Size = UDim2.fromOffset(thickness, size),
			ZIndex = 5,
			Parent = parent,
		}))
	end
	return parts
end

local function diamond(parent, size, props)
	local base = {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(size, size),
		Rotation = 45,
		Parent = parent,
	}
	for k, v in pairs(props or {}) do
		base[k] = v
	end
	return create("Frame", base)
end

--------------------------------------------------------------------------
-- Images (rbxassetid, local workspace file, or URL via getcustomasset)
--------------------------------------------------------------------------

local function ensureFolder(path)
	if typeof(isfolder) ~= "function" or typeof(makefolder) ~= "function" then
		return
	end
	local current = ""
	for part in string.gmatch(path, "[^/]+") do
		current = current == "" and part or (current .. "/" .. part)
		if not isfolder(current) then
			makefolder(current)
		end
	end
end

local function looksLikeImage(bytes)
	return string.sub(bytes, 1, 4) == "\137PNG" or string.sub(bytes, 1, 3) == "\255\216\255"
end

function Library:LoadImage(source, cacheName)
	if type(source) ~= "string" or source == "" then
		return nil, "no source"
	end
	if string.match(source, "^rbxasset") or string.match(source, "^rbxthumb") then
		return source
	end
	if typeof(getcustomasset) ~= "function" then
		return nil, "getcustomasset unavailable"
	end

	local path = source
	if string.match(source, "^https?://") then
		if typeof(writefile) ~= "function" then
			return nil, "writefile unavailable"
		end
		local name = cacheName or string.sub((string.gsub(source, "[^%w%.]", "_")), -60)
		path = "DebugKit/cache/" .. name
		local cached = typeof(isfile) == "function" and isfile(path)
		if not cached then
			local ok, body = pcall(game.HttpGet, game, source)
			if not ok or type(body) ~= "string" then
				return nil, "download failed: " .. tostring(body)
			end
			if not looksLikeImage(body) then
				return nil, "not a PNG/JPEG (" .. #body .. " bytes)"
			end
			local okFolder = pcall(ensureFolder, "DebugKit/cache")
			if not okFolder then
				return nil, "makefolder failed"
			end
			local okWrite, err = pcall(writefile, path, body)
			if not okWrite then
				return nil, "writefile failed: " .. tostring(err)
			end
		end
	end

	local ok, asset = pcall(getcustomasset, path)
	if ok and type(asset) == "string" and asset ~= "" then
		return asset
	end
	return nil, "getcustomasset failed: " .. tostring(asset)
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

	local W = options.Size and options.Size.X or 680
	local H = options.Size and options.Size.Y or 480
	local SIDEBAR = 150
	local HEADER = 40
	local FOOTER = 26

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

	-- Main frame -----------------------------------------------------------
	local main = create("Frame", {
		Name = "Main",
		Size = UDim2.fromOffset(W, H),
		Position = UDim2.fromOffset(80, 80),
		BackgroundColor3 = T.Background,
		BackgroundTransparency = T.BackgroundTransparency,
		Active = true,
		Parent = gui,
	}, { stroke(T.Border, T.BorderTransparency) })
	local mainScale = create("UIScale", { Parent = main })
	window._main = main
	window._userScale = 1
	local mainBrackets = brackets(main, T.BracketSize, T.BracketThickness)

	local function divider(position, size)
		return create("Frame", {
			Position = position,
			Size = size,
			BackgroundColor3 = T.Border,
			BackgroundTransparency = T.BorderTransparency,
			Parent = main,
		})
	end

	-- Title bar -------------------------------------------------------------
	local titlebar = create("Frame", {
		Name = "Titlebar",
		Size = UDim2.new(1, 0, 0, HEADER),
		BackgroundTransparency = 1,
		Parent = main,
	})

	local titleGroup = create("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(14, 0),
		Size = UDim2.new(1, -130, 1, 0),
		ClipsDescendants = true,
		Parent = titlebar,
	}, { list(10, Enum.FillDirection.Horizontal, Enum.VerticalAlignment.Center) })

	local dotHolder = create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(10, 10),
		LayoutOrder = 1,
		Parent = titleGroup,
	})
	local dot = diamond(dotHolder, 8)
	TweenService:Create(dot, TweenInfo.new(1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
		BackgroundTransparency = 0.5,
	}):Play()

	label({
		Text = string.upper(title),
		Font = T.FontHeading,
		TextSize = 16,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromScale(0, 1),
		LayoutOrder = 2,
		Parent = titleGroup,
	})
	label({
		Text = string.upper(options.Subtitle or ("v" .. Library.Version)),
		Font = T.FontMono,
		TextSize = 10,
		TextColor3 = T.TextDim,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromScale(0, 1),
		LayoutOrder = 3,
		Parent = titleGroup,
	})

	local statusPill = create("Frame", {
		BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 20),
		LayoutOrder = 4,
		Visible = false,
		Parent = titleGroup,
	}, { padding(0, 8, 0, 8) })
	local statusStroke = stroke(window.Accent, 0.5)
	statusStroke.Parent = statusPill
	local statusText = label({
		Font = T.FontMono,
		TextSize = 10,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromScale(0, 1),
		Parent = statusPill,
	})

	local fpsLabel = label({
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -46, 0.5, 0),
		Size = UDim2.fromOffset(70, 16),
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
		Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.fromOffset(26, 26),
		BackgroundColor3 = T.Panel,
		Parent = titlebar,
	})
	local minimizeStroke = stroke(T.Border, 0.85)
	minimizeStroke.Parent = minimizeBtn
	local minusBar = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(10, 2),
		BackgroundColor3 = T.TextDim,
		Parent = minimizeBtn,
	})
	minimizeBtn.MouseEnter:Connect(function()
		tween(minimizeBtn, { BackgroundTransparency = T.PanelHoverTransparency })
		tween(minusBar, { BackgroundColor3 = window.Accent })
		tween(minimizeStroke, { Color = window.Accent, Transparency = 0.5 })
	end)
	minimizeBtn.MouseLeave:Connect(function()
		tween(minimizeBtn, { BackgroundTransparency = 1 })
		tween(minusBar, { BackgroundColor3 = T.TextDim })
		tween(minimizeStroke, { Color = T.Border, Transparency = 0.85 })
	end)

	divider(UDim2.fromOffset(0, HEADER), UDim2.new(1, 0, 0, 1))

	-- Sidebar ---------------------------------------------------------------
	local sidebar = create("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, HEADER + 1),
		Size = UDim2.new(0, SIDEBAR, 1, -(HEADER + 1) - FOOTER - 1),
		Parent = main,
	})
	divider(UDim2.fromOffset(SIDEBAR, HEADER + 1), UDim2.new(0, 1, 1, -(HEADER + 1) - FOOTER - 1))

	window._tabList = create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, -28),
		Parent = sidebar,
	}, { padding(10, 0, 0, 0), list(2) })

	local counter = label({
		Position = UDim2.new(0, 0, 1, -26),
		Size = UDim2.new(1, 0, 0, 20),
		Font = T.FontMono,
		TextSize = 11,
		TextColor3 = T.TextDim,
		RichText = true,
		Parent = sidebar,
	}, { padding(0, 0, 0, 14) })
	window._counter = counter

	-- Content ---------------------------------------------------------------
	window._content = create("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(SIDEBAR + 1, HEADER + 1),
		Size = UDim2.new(1, -(SIDEBAR + 1), 1, -(HEADER + 1) - FOOTER - 1),
		Parent = main,
	})

	-- Footer log ------------------------------------------------------------
	divider(UDim2.new(0, 0, 1, -FOOTER - 1), UDim2.new(1, 0, 0, 1))
	local logBar = create("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 0, 1, -FOOTER),
		Size = UDim2.new(1, 0, 0, FOOTER),
		Parent = main,
	}, { padding(0, 14, 0, 14), list(10, Enum.FillDirection.Horizontal, Enum.VerticalAlignment.Center) })
	window._logTime = label({
		Text = "--:--:--",
		Font = T.FontMono,
		TextSize = 11,
		TextColor3 = T.TextFaint,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromScale(0, 1),
		LayoutOrder = 1,
		Parent = logBar,
	})
	window._logMsg = label({
		Text = Library.Strings.Ready,
		Font = T.FontMono,
		TextSize = 11,
		TextColor3 = T.TextDim,
		RichText = true,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Size = UDim2.new(1, -70, 1, 0),
		LayoutOrder = 2,
		Parent = logBar,
	})

	-- Minimized bubble ------------------------------------------------------
	local bubble = button({
		Name = "Bubble",
		Size = UDim2.fromOffset(48, 48),
		Position = UDim2.fromOffset(80, 80),
		BackgroundColor3 = T.Background,
		BackgroundTransparency = T.BackgroundTransparency,
		Visible = false,
		Parent = gui,
	})
	local bubbleStroke = stroke(window.Accent, 0.5)
	bubbleStroke.Parent = bubble
	local bubbleScale = create("UIScale", { Parent = bubble })
	local bubbleDiamond = diamond(bubble, 14, { BackgroundTransparency = 1 })
	local bubbleDiamondStroke = stroke(window.Accent, 0, 2)
	bubbleDiamondStroke.Parent = bubbleDiamond
	local badge = create("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 6, 0, -6),
		Size = UDim2.fromOffset(18, 18),
		Parent = bubble,
	})
	local badgeText = label({
		Size = UDim2.fromScale(1, 1),
		Font = T.FontBold,
		TextSize = 10,
		TextColor3 = T.Background,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = "0",
		Parent = badge,
	})
	window._badge, window._badgeText = badge, badgeText

	window:_onAccent(function(c)
		for _, part in ipairs(mainBrackets) do
			part.BackgroundColor3 = c
		end
		dot.BackgroundColor3 = c
		statusStroke.Color = c
		statusText.TextColor3 = c
		bubbleStroke.Color = c
		bubbleDiamondStroke.Color = c
		badge.BackgroundColor3 = c
		window:_updateCounter()
	end)

	function window:SetStatus(text)
		if text == nil or text == "" then
			statusPill.Visible = false
			return
		end
		statusText.Text = string.upper(tostring(text))
		statusPill.Visible = true
	end

	gui.Parent = parent

	-- Scale: fit the window to small screens (phones), times the user's own scale.
	local function fitScale()
		local vp = gui.AbsoluteSize
		if vp.X <= 0 or vp.Y <= 0 then
			return 1
		end
		return math.clamp(math.min((vp.X - 24) / W, (vp.Y - 24) / H), 0.5, 1)
	end
	local function effectiveScale()
		return fitScale() * window._userScale
	end

	-- Dragging (smooth, clamped to the viewport) ----------------------------
	local function clampPos(target, pos)
		local vp = gui.AbsoluteSize
		local uiScale = target:FindFirstChildOfClass("UIScale")
		local s = uiScale and uiScale.Scale or 1
		local w, h = target.Size.X.Offset * s, target.Size.Y.Offset * s
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
		local t = tween(mainScale, { Scale = effectiveScale() * 0.92 }, TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.In))
		t.Completed:Once(function()
			if self.Minimized then
				main.Visible = false
			end
		end)
		bubble.Visible = true
		bubbleScale.Scale = 0.5
		tween(bubbleScale, { Scale = 1 }, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out))
		self:Log(Library.Strings.Minimized)
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
		local target = effectiveScale()
		mainScale.Scale = target * 0.92
		tween(mainScale, { Scale = target }, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out))
		self:Log(Library.Strings.Restored)
	end

	makeDraggable(main, titlebar)
	makeDraggable(bubble, bubble, function()
		window:Restore()
	end)
	minimizeBtn.MouseButton1Click:Connect(function()
		window:Minimize()
	end)

	window:_connect(UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == window.Keybind then
			window:ToggleVisibility()
		end
	end))

	local function applyScale()
		if not window.Minimized then
			mainScale.Scale = effectiveScale()
		end
		setPos(main, clampPos(main, getPos(main)))
	end

	-- mult: user scale on top of the automatic fit (0.5–1.5)
	function window:SetScale(mult)
		self._userScale = math.clamp(tonumber(mult) or 1, 0.5, 1.5)
		applyScale()
	end

	window:_connect(gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		applyScale()
		setPos(bubble, clampPos(bubble, getPos(bubble)))
	end))

	local frames, last = 0, os.clock()
	window:_connect(RunService.RenderStepped:Connect(function()
		frames += 1
		local now = os.clock()
		if now - last >= 0.5 then
			fpsLabel.Text = math.floor(frames / (now - last) + 0.5) .. " FPS"
			frames, last = 0, now
		end
	end))

	applyScale()
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
	self._counter.Text = string.format('<font color="%s"><b>%d</b></font> %s', toHex(self.Accent), n, escape(Library.Strings.Active))
	self._badgeText.Text = tostring(n)
	self._badge.Visible = n > 0
end

-- Public window methods -----------------------------------------------------

-- Footer status bar (and Output). <b>text</b> is shown in the accent color.
function Window:Log(message, toConsole)
	local T = Library.Theme
	message = tostring(message)
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

function Window:Reset()
	for _, el in ipairs(self._elements) do
		el:Set(el.Default, true)
	end
	self:Log(Library.Strings.Reset)
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

local BANNER = 72

function Window:CreateTab(name, icon, tabOptions)
	if type(icon) == "table" and tabOptions == nil then
		icon, tabOptions = nil, icon
	end
	tabOptions = tabOptions or {}
	local T = Library.Theme
	local window = self
	local index = #self.Tabs + 1
	local tab = setmetatable({ Window = window, Name = tostring(name), Index = index, _order = 0, Active = false, _hover = false }, Tab)

	-- Sidebar button --------------------------------------------------------
	local btn = button({
		Size = UDim2.new(1, 0, 0, 34),
		BackgroundColor3 = T.Panel,
		LayoutOrder = index,
		Parent = self._tabList,
	})
	local indicator = create("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.new(0, 3, 0, 0),
		Parent = btn,
	})
	local indexText = label({
		Position = UDim2.fromOffset(14, 0),
		Size = UDim2.new(0, 20, 1, 0),
		Font = T.FontMono,
		TextSize = 10,
		TextColor3 = T.TextFaint,
		Text = string.format("%02d", index),
		Parent = btn,
	})
	local textX = 40
	local iconImage
	if icon then
		iconImage = create("ImageLabel", {
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 38, 0.5, 0),
			Size = UDim2.fromOffset(14, 14),
			Image = typeof(icon) == "number" and ("rbxassetid://" .. icon) or tostring(icon),
			ImageColor3 = T.TextDim,
			Parent = btn,
		})
		textX = 58
	end
	local text = label({
		Position = UDim2.fromOffset(textX, 0),
		Size = UDim2.new(1, -textX - 6, 1, 0),
		Font = T.FontHeading,
		TextSize = 13,
		TextColor3 = T.TextDim,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Text = string.upper(tab.Name),
		Parent = btn,
	})

	-- Page: banner + scrolling body ----------------------------------------
	local page = create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		Parent = self._content,
	}, { padding(12, 14, 10, 14) })

	local showBanner = tabOptions.ShowBanner ~= false
	local banner = create("Frame", {
		Size = UDim2.new(1, 0, 0, BANNER),
		BackgroundColor3 = T.Panel,
		BackgroundTransparency = T.PanelTransparency,
		ClipsDescendants = true,
		Visible = showBanner,
		Parent = page,
	}, { stroke(T.Border, T.BorderTransparency) })
	local bannerImage = create("ImageLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ScaleType = Enum.ScaleType.Crop,
		ImageColor3 = Color3.fromRGB(120, 124, 132),
		Visible = false,
		Parent = banner,
	})
	local bannerTint = create("Frame", {
		Size = UDim2.fromScale(1, 1),
		Parent = banner,
	}, {
		create("UIGradient", {
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.84),
				NumberSequenceKeypoint.new(0.6, 1),
				NumberSequenceKeypoint.new(1, 1),
			}),
		}),
	})
	create("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		Parent = banner,
	}, {
		create("UIGradient", {
			Rotation = 90,
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.85),
				NumberSequenceKeypoint.new(1, 0.25),
			}),
		}),
	})
	label({
		Position = UDim2.fromOffset(12, 8),
		Size = UDim2.new(1, -24, 0, 12),
		Font = T.FontMono,
		TextSize = 10,
		TextColor3 = T.TextDim,
		Text = string.format("// %02d", index),
		Parent = banner,
	})
	label({
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 12, 1, -8),
		Size = UDim2.new(0.65, -12, 0, 26),
		Font = T.FontHeading,
		TextSize = 24,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Text = string.upper(tab.Name),
		Parent = banner,
	})
	local metaLabel = label({
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -12, 1, -10),
		Size = UDim2.new(0.35, 0, 0, 14),
		Font = T.FontMono,
		TextSize = 11,
		TextColor3 = T.TextDim,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Text = tabOptions.Meta and string.upper(tostring(tabOptions.Meta)) or "",
		Parent = banner,
	})
	local bannerBrackets = brackets(banner, 10, 2, true)

	local bodyTop = showBanner and (BANNER + 10) or 0
	local scroll = create("ScrollingFrame", {
		Position = UDim2.fromOffset(0, bodyTop),
		Size = UDim2.new(1, 0, 1, -bodyTop),
		BackgroundTransparency = 1,
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = Color3.new(1, 1, 1),
		ScrollBarImageTransparency = 0.8,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Parent = page,
	}, { list(6), padding(1, 8, 4, 1) })
	tab.Page = scroll
	tab._page = page

	function tab:SetBanner(image)
		if type(image) == "string" and image ~= "" then
			bannerImage.Image = image
			bannerImage.Visible = true
		else
			bannerImage.Image = ""
			bannerImage.Visible = false
		end
	end

	function tab:SetMeta(value)
		metaLabel.Text = value and string.upper(tostring(value)) or ""
	end

	if tabOptions.Banner then
		tab:SetBanner(tabOptions.Banner)
	end

	local function render(instant)
		local a = window.Accent
		local textColor = tab.Active and a or (tab._hover and T.Text or T.TextDim)
		local props = {
			BackgroundColor3 = tab.Active and a or T.Panel,
			BackgroundTransparency = tab.Active and 0.88 or (tab._hover and T.PanelHoverTransparency or 1),
		}
		local ind = { Size = UDim2.new(0, 3, tab.Active and 1 or 0, 0) }
		if instant then
			apply(btn, props)
			apply(indicator, ind)
			text.TextColor3 = textColor
		else
			tween(btn, props)
			tween(indicator, ind, SPRING)
			tween(text, { TextColor3 = textColor })
		end
		indexText.TextColor3 = tab.Active and a or T.TextFaint
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
			scroll.Position = UDim2.fromOffset(0, bodyTop + 8)
			tween(scroll, { Position = UDim2.fromOffset(0, bodyTop) }, SMOOTH)
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
			window:Log(string.format(Library.Strings.TabSwitched, escape(tab.Name)), false)
		end
	end)

	window:_onAccent(function(a)
		bannerTint.BackgroundColor3 = a
		for _, part in ipairs(bannerBrackets) do
			part.BackgroundColor3 = a
		end
		render(true)
	end)

	table.insert(self.Tabs, tab)
	if #self.Tabs == 1 then
		window:SelectTab(tab)
	end
	return tab
end

-- Base row: panel background, square, border shown on hover.
function Tab:_row(height, clickable, customHover)
	local T = Library.Theme
	self._order += 1
	local row = create(clickable and "TextButton" or "Frame", {
		Size = UDim2.new(1, 0, 0, height),
		BackgroundColor3 = T.Panel,
		BackgroundTransparency = T.PanelTransparency,
		LayoutOrder = self._order,
		Parent = self.Page,
	})
	if clickable then
		row.Text = ""
		row.AutoButtonColor = false
	end
	local rowStroke = stroke(T.Border, 1)
	rowStroke.Parent = row
	if not customHover then
		row.MouseEnter:Connect(function()
			tween(row, { BackgroundTransparency = T.PanelHoverTransparency })
			tween(rowStroke, { Transparency = T.BorderTransparency })
		end)
		row.MouseLeave:Connect(function()
			tween(row, { BackgroundTransparency = T.PanelTransparency })
			tween(rowStroke, { Transparency = 1 })
		end)
	end
	return row, rowStroke
end

local function rowLabel(parent, text, description, rightInset)
	local T = Library.Theme
	local holder = create("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(12, 0),
		Size = UDim2.new(1, -(rightInset or 60), 1, 0),
		Parent = parent,
	}, { list(2, Enum.FillDirection.Vertical, Enum.VerticalAlignment.Center) })
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
			Font = T.FontMono,
			TextSize = 10,
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
-- Section / Label
--------------------------------------------------------------------------

function Tab:CreateSection(text)
	local T = Library.Theme
	self._order += 1
	text = tostring(text)
	if string.sub(text, 1, 2) ~= "//" then
		text = "// " .. text
	end
	return label({
		Size = UDim2.new(1, 0, 0, 20),
		Font = T.FontMono,
		TextSize = 10,
		TextColor3 = T.TextDim,
		TextYAlignment = Enum.TextYAlignment.Bottom,
		Text = string.upper(text),
		LayoutOrder = self._order,
		Parent = self.Page,
	}, { padding(0, 0, 3, 1) })
end

function Tab:CreateLabel(text, labelOptions)
	local T = Library.Theme
	labelOptions = labelOptions or {}
	self._order += 1
	local inst = label({
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Font = labelOptions.Mono and T.FontMono or T.Font,
		TextSize = labelOptions.Mono and 11 or 12,
		TextColor3 = T.TextDim,
		TextWrapped = true,
		RichText = true,
		Text = tostring(text or ""),
		LayoutOrder = self._order,
		Parent = self.Page,
	}, { padding(2, 2, 2, 2) })
	local obj = { Type = "Label", Instance = inst }
	function obj:Set(value)
		inst.Text = tostring(value or "")
	end
	function obj:Get()
		return inst.Text
	end
	return obj
end

--------------------------------------------------------------------------
-- Toggle
--------------------------------------------------------------------------

function Tab:CreateToggle(text, default, callback, description)
	local T = Library.Theme
	local window = self.Window
	local toggle = { Type = "Toggle", Value = default == true, Default = default == true, _callback = callback }

	local row = self:_row(description and 44 or 34, true)
	rowLabel(row, text, description, 64)

	local switch = create("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.fromOffset(38, 18),
		Parent = row,
	})
	local switchStroke = stroke(T.Border, 0.82)
	switchStroke.Parent = switch
	local knob = create("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 3, 0.5, 0),
		Size = UDim2.fromOffset(12, 12),
		Parent = switch,
	})

	local function render(instant)
		local a = window.Accent
		local on = toggle.Value
		local sw = on and { BackgroundColor3 = a, BackgroundTransparency = 0.85 }
			or { BackgroundColor3 = T.Panel, BackgroundTransparency = 0.94 }
		local kb = { Position = UDim2.new(0, on and 23 or 3, 0.5, 0), BackgroundColor3 = on and a or T.TextDim }
		local st = on and { Color = a, Transparency = 0 } or { Color = T.Border, Transparency = 0.82 }
		if instant then
			apply(switch, sw)
			apply(knob, kb)
			apply(switchStroke, st)
		else
			tween(switch, sw)
			tween(knob, kb, SPRING)
			tween(switchStroke, st)
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

	local row = self:_row(58)
	label({
		Position = UDim2.fromOffset(12, 8),
		Size = UDim2.new(1, -100, 0, 16),
		Font = T.FontMedium,
		Text = text,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = row,
	})
	local valueLabel = label({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 8),
		Size = UDim2.fromOffset(84, 16),
		Font = T.FontMono,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = row,
	})

	local track = create("Frame", {
		Position = UDim2.new(0, 12, 0, 34),
		Size = UDim2.new(1, -24, 0, 4),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.9,
		Parent = row,
	})
	local fill = create("Frame", { Size = UDim2.fromScale(0, 1), Parent = track })
	local knob = diamond(track, 12, {
		Position = UDim2.fromScale(0, 0.5),
		BackgroundColor3 = T.Background,
		ZIndex = 2,
	})
	local knobStroke = stroke(window.Accent, 0, 2)
	knobStroke.Parent = knob
	local knobScale = create("UIScale", { Parent = knob })

	local function format(v)
		return string.format("%." .. decimals .. "f", v) .. suffix
	end

	label({
		Position = UDim2.new(0, 12, 0, 42),
		Size = UDim2.new(0.5, -12, 0, 12),
		Font = T.FontMono,
		TextSize = 9,
		TextColor3 = T.TextFaint,
		Text = format(min),
		Parent = row,
	})
	label({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 42),
		Size = UDim2.new(0.5, -12, 0, 12),
		Font = T.FontMono,
		TextSize = 9,
		TextColor3 = T.TextFaint,
		TextXAlignment = Enum.TextXAlignment.Right,
		Text = format(max),
		Parent = row,
	})

	local hit = button({
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, -8, 0.5, 0),
		Size = UDim2.new(1, 16, 0, 22),
		ZIndex = 3,
		Parent = track,
	})

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
		slider:Set(min + alpha * (max - min), false, true)
	end

	hit.InputBegan:Connect(function(input)
		if isPress(input) then
			dragging, dragInput = true, input
			tween(knobScale, { Scale = 1.3 }, SPRING)
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

	local HEADER = 36
	local ITEM = 24
	local GAP = 2

	local row = self:_row(HEADER)
	row.ClipsDescendants = true

	local header = button({ Size = UDim2.new(1, 0, 0, HEADER), Parent = row })
	rowLabel(header, text, nil, 185)

	local box = create("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -8, 0.5, 0),
		Size = UDim2.fromOffset(160, 24),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.7,
		Parent = header,
	})
	local boxStroke = stroke(T.Border, T.BorderTransparency)
	boxStroke.Parent = box
	local valueText = label({
		Position = UDim2.fromOffset(9, 0),
		Size = UDim2.new(1, -30, 1, 0),
		Font = T.FontMono,
		TextSize = 11,
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
		Position = UDim2.fromOffset(8, HEADER),
		Size = UDim2.new(1, -16, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = row,
	}, { list(GAP) })

	local items = {}

	local function openHeight()
		local n = #dropdown.Options
		return HEADER + n * ITEM + math.max(n - 1, 0) * GAP + 8
	end

	local function renderSelection()
		local a = window.Accent
		valueText.Text = dropdown.Value ~= nil and tostring(dropdown.Value) or "—"
		for _, item in ipairs(items) do
			local selected = item.Value == dropdown.Value
			item.Text.TextColor3 = selected and a or T.Text
			item.Check.TextColor3 = a
			item.Check.Visible = selected
			item.Button.BackgroundColor3 = selected and a or T.Panel
			item.Button.BackgroundTransparency = selected and 0.88 or 1
		end
	end

	local function renderOpen(instant)
		local a = window.Accent
		local open = dropdown.Open
		local rowSize = { Size = UDim2.new(1, 0, 0, open and openHeight() or HEADER) }
		local chev = { Rotation = open and 180 or 0, TextColor3 = open and a or T.TextDim }
		local st = { Color = open and a or T.Border, Transparency = open and 0.4 or T.BorderTransparency }
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
				BackgroundColor3 = T.Panel,
				LayoutOrder = i,
				Parent = listFrame,
			})
			local optText = label({
				Position = UDim2.fromOffset(8, 0),
				Size = UDim2.new(1, -30, 1, 0),
				Font = T.FontMono,
				TextSize = 11,
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
				if option ~= dropdown.Value then
					tween(optBtn, { BackgroundTransparency = T.PanelHoverTransparency })
				end
			end)
			optBtn.MouseLeave:Connect(function()
				if option ~= dropdown.Value then
					tween(optBtn, { BackgroundTransparency = 1 })
				end
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
-- Buttons
--------------------------------------------------------------------------

-- Shared button body used by CreateButton and CreateButtonGrid.
local function makeButton(window, parent, layoutOrder, size, text, callback, options)
	local T = Library.Theme
	options = options or {}
	local style = options.Danger and "danger" or (options.Primary and "primary" or "default")

	local row = button({
		Size = size,
		BackgroundColor3 = T.Panel,
		BackgroundTransparency = style == "danger" and 1 or T.PanelTransparency,
		LayoutOrder = layoutOrder,
		Parent = parent,
	})
	local rowStroke = stroke(T.Border, T.BorderTransparency)
	rowStroke.Parent = row
	local scale = create("UIScale", { Parent = row })
	local textLabel = label({
		Size = UDim2.fromScale(1, 1),
		Font = T.FontHeading,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Text = string.upper(tostring(text)),
		Parent = row,
	}, { padding(0, 6, 0, 6) })

	local function idle()
		local a = window.Accent
		if style == "primary" then
			return { BackgroundColor3 = a, BackgroundTransparency = 0.88 }, { Color = a, Transparency = 0.5 }, a
		elseif style == "danger" then
			return { BackgroundColor3 = T.Danger, BackgroundTransparency = 1 }, { Color = T.Danger, Transparency = 0.5 }, T.Danger
		end
		return { BackgroundColor3 = T.Panel, BackgroundTransparency = T.PanelTransparency }, { Color = T.Border, Transparency = 0.88 }, T.Text
	end

	local function renderIdle(instant)
		local bg, st, color = idle()
		if instant then
			apply(row, bg)
			apply(rowStroke, st)
			textLabel.TextColor3 = color
		else
			tween(row, bg)
			tween(rowStroke, st)
			tween(textLabel, { TextColor3 = color })
		end
	end

	row.MouseEnter:Connect(function()
		if style == "primary" then
			tween(row, { BackgroundTransparency = 0.8 })
		elseif style == "danger" then
			tween(row, { BackgroundTransparency = 0.88 })
			tween(rowStroke, { Transparency = 0.3 })
		else
			tween(row, { BackgroundTransparency = T.PanelHoverTransparency })
			tween(rowStroke, { Transparency = 0.8 })
		end
	end)
	row.MouseLeave:Connect(function()
		renderIdle(false)
		tween(scale, { Scale = 1 })
	end)
	row.MouseButton1Down:Connect(function()
		tween(scale, { Scale = 0.97 }, TweenInfo.new(0.08))
	end)
	row.MouseButton1Up:Connect(function()
		tween(scale, { Scale = 1 }, SPRING)
	end)

	local btnObj = { Type = "Button", Instance = row }
	function btnObj:Fire()
		local flashColor = style == "danger" and T.Danger or window.Accent
		rowStroke.Color = flashColor
		rowStroke.Transparency = 0.1
		textLabel.TextColor3 = flashColor
		local _, st, color = idle()
		tween(rowStroke, st, TweenInfo.new(0.4))
		tween(textLabel, { TextColor3 = color }, TweenInfo.new(0.4))
		window:Log(string.format(Library.Strings.ButtonPressed, escape(text)), false)
		safeCall(callback)
	end

	row.MouseButton1Click:Connect(function()
		btnObj:Fire()
	end)
	window:_onAccent(function()
		renderIdle(true)
	end)
	return btnObj
end

function Tab:CreateButton(text, callback, options)
	self._order += 1
	return makeButton(self.Window, self.Page, self._order, UDim2.new(1, 0, 0, 34), text, callback, options)
end

function Tab:CreateButtonGrid(columns, buttons)
	columns = math.max(1, math.floor(tonumber(columns) or 2))
	self._order += 1
	local GAP = 6
	local holder = create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = self._order,
		Parent = self.Page,
	}, {
		create("UIGridLayout", {
			CellPadding = UDim2.fromOffset(GAP, GAP),
			CellSize = UDim2.new(1 / columns, -math.ceil(GAP * (columns - 1) / columns), 0, 34),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	local result = {}
	for i, spec in ipairs(buttons or {}) do
		result[i] = makeButton(self.Window, holder, i, UDim2.new(), spec[1], spec[2], spec[3])
	end
	return result
end

--------------------------------------------------------------------------
-- Stat cards
--------------------------------------------------------------------------

function Tab:CreateStats(columns, specs)
	local T = Library.Theme
	local window = self.Window
	columns = math.max(1, math.floor(tonumber(columns) or 3))
	self._order += 1
	local GAP = 6
	local holder = create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = self._order,
		Parent = self.Page,
	}, {
		create("UIGridLayout", {
			CellPadding = UDim2.fromOffset(GAP, GAP),
			CellSize = UDim2.new(1 / columns, -math.ceil(GAP * (columns - 1) / columns), 0, 60),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})

	local function toneColor(tone)
		if typeof(tone) == "Color3" then
			return tone
		elseif tone == "accent" then
			return window.Accent
		elseif tone == "danger" then
			return T.Red
		elseif tone == "info" then
			return T.Info
		elseif tone == "success" then
			return T.Success
		end
		return nil
	end

	local cards = {}
	local stats = { Type = "Stats" }

	for i, spec in ipairs(specs or {}) do
		local card = create("Frame", {
			BackgroundColor3 = T.Panel,
			BackgroundTransparency = T.PanelTransparency,
			LayoutOrder = i,
			Parent = holder,
		}, { padding(8, 10, 8, 10), list(3) })
		local cardStroke = stroke(T.Border, T.BorderTransparency)
		cardStroke.Parent = card
		local title = label({
			Size = UDim2.new(1, 0, 0, 11),
			Font = T.FontMono,
			TextSize = 9,
			TextColor3 = T.TextDim,
			Text = string.upper(tostring(spec.Label or spec.Key or "")),
			LayoutOrder = 1,
			Parent = card,
		})
		local value = label({
			Size = UDim2.new(1, 0, 0, 17),
			Font = T.FontMedium,
			TextSize = 14,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Text = tostring(spec.Value or "—"),
			LayoutOrder = 2,
			Parent = card,
		})
		local sub = label({
			Size = UDim2.new(1, 0, 0, 12),
			Font = T.FontMono,
			TextSize = 10,
			TextColor3 = T.TextDim,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Text = tostring(spec.Sub or ""),
			LayoutOrder = 3,
			Parent = card,
		})
		cards[spec.Key or i] = { Stroke = cardStroke, Title = title, Value = value, Sub = sub, Tone = spec.Tone, ValueTone = spec.ValueTone }
	end

	local function renderCard(card)
		local c = toneColor(card.Tone)
		card.Stroke.Color = c or T.Border
		card.Stroke.Transparency = c and 0.55 or T.BorderTransparency
		card.Title.TextColor3 = c or T.TextDim
		card.Value.TextColor3 = toneColor(card.ValueTone) or (card.ValueTone == "muted" and T.TextDim) or T.Text
	end

	-- fields = { Value = "...", Sub = "...", Tone = tone|false, ValueTone = tone|false }
	function stats:Set(key, fields)
		local card = cards[key]
		if not card or type(fields) ~= "table" then
			return
		end
		if fields.Value ~= nil then
			card.Value.Text = tostring(fields.Value)
		end
		if fields.Sub ~= nil then
			card.Sub.Text = tostring(fields.Sub)
		end
		if fields.Tone ~= nil then
			card.Tone = fields.Tone or nil
		end
		if fields.ValueTone ~= nil then
			card.ValueTone = fields.ValueTone or nil
		end
		renderCard(card)
	end

	window:_onAccent(function()
		for _, card in pairs(cards) do
			renderCard(card)
		end
	end)
	return stats
end

return Library
