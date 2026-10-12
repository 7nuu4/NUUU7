--[[
    NuuUI v1.0  |  Biblioteca de interfaz para Roblox (Luau)
    Un solo LocalScript. Sin ModuleScripts, sin dependencias, sin loadstring.
    Ubicación: StarterPlayer > StarterPlayerScripts > LocalScript

    API resumida:
      NuuUI:CreateWindow({Title, Subtitle, Size, Theme, MinSize, MaxSize})
      Window:CreateTab({Name, Icon}) / SelectTab / Show / Hide / Toggle
              Minimize / Restore / SetScale / SetTitle / Close / Destroy
      Tab:CreateButton / CreateToggle / CreateSlider / CreateDropdown
          CreateInput / CreateKeybind / CreateSection / CreateLabel
          CreateParagraph / CreateDivider / CreateSearch
      NuuUI:Notify({Title, Content, Duration, Type})
      NuuUI:SetTheme("Dark" | "Light" | {Background, Surface, Accent, Text, Muted, Border})
      NuuUI:Destroy()
      Los métodos Set(valor, silent) de los componentes ejecutan el callback
      salvo que silent == true. Los valores Default nunca ejecutan callbacks.
      Iconos: NuuUI.Icons.home = "rbxassetid://ID"  (sin asset se dibuja un icono nativo)
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local NuuUI = { Version = "1.0", Name = "NuuUI", Windows = {}, Icons = {} }

local AUTO_Y = Enum.AutomaticSize.Y
local LEFT = Enum.TextXAlignment.Left
local RIGHT = Enum.TextXAlignment.Right

--==================================================================--
-- 1. UTILIDADES (Maid, SafeCall, tweens, constructores)
--==================================================================--
local Maid = {}
Maid.__index = Maid
function Maid.new() return setmetatable({ _tasks = {} }, Maid) end
function Maid:Give(item) table.insert(self._tasks, item) return item end
function Maid:Clean()
	local tasks = self._tasks
	self._tasks = {}
	for _, t in ipairs(tasks) do
		local ty = typeof(t)
		if ty == "RBXScriptConnection" then
			t:Disconnect()
		elseif ty == "Instance" then
			t:Destroy()
		elseif ty == "function" then
			pcall(t)
		elseif ty == "table" and type(t.Destroy) == "function" then
			pcall(t.Destroy, t)
		end
	end
end

local function SafeCall(label, callback, ...)
	if type(callback) ~= "function" then return true end
	local ok, err = xpcall(callback, function(e) return debug.traceback(tostring(e), 2) end, ...)
	if not ok then
		warn(("[NuuUI] Error en el callback de '%s':\n%s"):format(tostring(label), tostring(err)))
	end
	return ok
end

local TWEEN_FAST = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TWEEN_MED = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local function Tween(inst, props, info)
	local tw = TweenService:Create(inst, info or TWEEN_FAST, props)
	tw:Play()
	return tw
end

local function Apply(inst, props, animate)
	if animate then
		Tween(inst, props)
	else
		for k, v in pairs(props) do inst[k] = v end
	end
end

local function Make(class, props, children)
	local inst = Instance.new(class)
	if inst:IsA("GuiObject") then
		inst.BorderSizePixel = 0
		if inst:IsA("GuiButton") then inst.AutoButtonColor = false end
		if inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox") then
			inst.BackgroundTransparency = 1
			inst.Font = Enum.Font.GothamMedium
			inst.TextSize = 14
		end
	end
	local parent
	for k, v in pairs(props or {}) do
		if k == "Parent" then parent = v else inst[k] = v end
	end
	if children then
		for _, c in ipairs(children) do c.Parent = inst end
	end
	if parent then inst.Parent = parent end
	return inst
end

local function Corner(parent, radius)
	return Make("UICorner", { CornerRadius = UDim.new(0, radius), Parent = parent })
end
local function Stroke(parent, thickness, transparency)
	return Make("UIStroke", {
		Thickness = thickness or 1, Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = parent,
	})
end
local function Padding(parent, t, b, l, r)
	return Make("UIPadding", {
		PaddingTop = UDim.new(0, t), PaddingBottom = UDim.new(0, b),
		PaddingLeft = UDim.new(0, l), PaddingRight = UDim.new(0, r), Parent = parent,
	})
end
local function List(parent, pad)
	return Make("UIListLayout", {
		Padding = UDim.new(0, pad or 0), SortOrder = Enum.SortOrder.LayoutOrder,
		FillDirection = Enum.FillDirection.Vertical, Parent = parent,
	})
end

--==================================================================--
-- 2. SISTEMA DE TEMAS
--==================================================================--
local Themes = {
	Dark = {
		Background = Color3.fromRGB(15, 17, 24), Surface = Color3.fromRGB(23, 26, 36),
		Accent = Color3.fromRGB(170, 145, 255), Text = Color3.fromRGB(245, 245, 250),
		Muted = Color3.fromRGB(155, 160, 178), Border = Color3.fromRGB(55, 59, 76),
	},
	Light = {
		Background = Color3.fromRGB(242, 242, 247), Surface = Color3.fromRGB(255, 255, 255),
		Accent = Color3.fromRGB(124, 92, 255), Text = Color3.fromRGB(28, 28, 32),
		Muted = Color3.fromRGB(110, 112, 125), Border = Color3.fromRGB(208, 210, 222),
	},
}
local STATUS_COLORS = {
	Info = Color3.fromRGB(100, 170, 255), Success = Color3.fromRGB(80, 205, 150),
	Warning = Color3.fromRGB(255, 190, 80), Error = Color3.fromRGB(255, 100, 110),
}
local THEME_KEYS = { "Background", "Surface", "Accent", "Text", "Muted", "Border" }

local Theme = {}
local function deriveTheme()
	Theme.Raised = Theme.Surface:Lerp(Theme.Text, 0.05)
	Theme.Hover = Theme.Surface:Lerp(Theme.Text, 0.11)
end
local function mergeTheme(src)
	for _, k in ipairs(THEME_KEYS) do
		if typeof(src[k]) == "Color3" then Theme[k] = src[k] end
	end
	for k in pairs(STATUS_COLORS) do
		if typeof(src[k]) == "Color3" then Theme[k] = src[k] end
	end
	deriveTheme()
end
for k, v in pairs(Themes.Dark) do Theme[k] = v end
for k, v in pairs(STATUS_COLORS) do Theme[k] = v end
deriveTheme()

local Bindings = {}
local function Bind(owner, fn)
	fn()
	table.insert(Bindings, { owner = owner, fn = fn })
end
local function RefreshBindings(callFns)
	for i = #Bindings, 1, -1 do
		local b = Bindings[i]
		if not b.owner:IsDescendantOf(game) then
			table.remove(Bindings, i)
		elseif callFns then
			local ok, err = pcall(b.fn)
			if not ok then warn("[NuuUI] Error al aplicar el tema: " .. tostring(err)) end
		end
	end
end
local function Paint(inst, prop, key)
	Bind(inst, function() inst[prop] = Theme[key] end)
end

function NuuUI:SetTheme(arg)
	if type(arg) == "string" then
		local found
		for name, preset in pairs(Themes) do
			if string.lower(name) == string.lower(arg) then found = preset end
		end
		if not found then
			warn("[NuuUI] Tema desconocido: " .. arg)
			return false
		end
		mergeTheme(found)
	elseif type(arg) == "table" then
		mergeTheme(arg)
	else
		return false
	end
	RefreshBindings(true)
	return true
end
function NuuUI:GetTheme()
	return table.clone(Theme)
end

--==================================================================--
-- 3. ICONOS
--==================================================================--
local function resolveIcon(icon)
	if icon == nil then return nil end
	if type(icon) == "number" then return "rbxassetid://" .. tostring(math.floor(icon)) end
	if type(icon) ~= "string" or icon == "" then return nil end
	if icon:match("^rbxassetid://") or icon:match("^rbxasset://") then return icon end
	if icon:match("^%d+$") then return "rbxassetid://" .. icon end
	local reg = NuuUI.Icons[string.lower(icon)]
	if type(reg) == "number" then return "rbxassetid://" .. tostring(reg) end
	if type(reg) == "string" and (reg:match("^rbxassetid://") or reg:match("^rbxasset://") or reg:match("^%d+$")) then
		return reg:match("^%d+$") and ("rbxassetid://" .. reg) or reg
	end
	return nil
end

--==================================================================--
-- 4. NOTIFICACIONES (globales)
--==================================================================--
local notifGui, notifHolder
local notifCounter = 0
local activeNotifs = {}

local function ensureNotifGui()
	if notifGui and notifGui.Parent then return end
	notifGui = Make("ScreenGui", {
		Name = "NuuUI_Notifications", ResetOnSpawn = false, IgnoreGuiInset = true,
		DisplayOrder = 10000, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Parent = PlayerGui,
	})
	notifHolder = Make("Frame", {
		Name = "Holder", BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 12), Size = UDim2.new(0, 280, 1, -24), Parent = notifGui,
	})
	local l = List(notifHolder, 8)
	l.HorizontalAlignment = Enum.HorizontalAlignment.Right
	l.VerticalAlignment = Enum.VerticalAlignment.Top
end

function NuuUI:Notify(config)
	if type(config) ~= "table" then config = { Content = tostring(config or "") } end
	ensureNotifGui()

	local ntype = tostring(config.Type or "Info")
	ntype = string.upper(string.sub(ntype, 1, 1)) .. string.lower(string.sub(ntype, 2))
	if not STATUS_COLORS[ntype] then ntype = "Info" end
	local duration = math.clamp(tonumber(config.Duration) or 4, 0.5, 60)

	while #activeNotifs >= 5 do
		local oldest = table.remove(activeNotifs, 1)
		oldest.Dismiss()
	end

	notifCounter += 1
	local wrapper = Make("Frame", {
		Name = "Notification", BackgroundTransparency = 1, AutomaticSize = AUTO_Y,
		Size = UDim2.new(1, 0, 0, 0), LayoutOrder = notifCounter, Parent = notifHolder,
	})
	local card = Make("Frame", {
		Name = "Card", AutomaticSize = AUTO_Y, Size = UDim2.new(1, 0, 0, 0),
		Position = UDim2.new(1, 40, 0, 0), ClipsDescendants = true, Parent = wrapper,
	})
	Paint(card, "BackgroundColor3", "Surface")
	Corner(card, 10)
	local st = Stroke(card, 1, 0.3)
	Paint(st, "Color", "Border")

	local bar = Make("Frame", {
		Name = "TypeBar", Position = UDim2.fromOffset(0, 0), Size = UDim2.new(0, 3, 1, 0), Parent = card,
	})
	Bind(bar, function() bar.BackgroundColor3 = Theme[ntype] end)

	local inner = Make("Frame", {
		Name = "Inner", BackgroundTransparency = 1, AutomaticSize = AUTO_Y,
		Size = UDim2.new(1, 0, 0, 0), Parent = card,
	})
	Padding(inner, 10, 12, 16, 12)
	List(inner, 3)

	local title = Make("TextLabel", {
		Name = "Title", AutomaticSize = AUTO_Y, Size = UDim2.new(1, 0, 0, 16), LayoutOrder = 1,
		Text = tostring(config.Title or "NuuUI"), Font = Enum.Font.GothamBold, TextSize = 13,
		TextXAlignment = LEFT, TextWrapped = true, Parent = inner,
	})
	Paint(title, "TextColor3", "Text")
	local content
	if config.Content ~= nil and tostring(config.Content) ~= "" then
		content = Make("TextLabel", {
			Name = "Content", AutomaticSize = AUTO_Y, Size = UDim2.new(1, 0, 0, 0), LayoutOrder = 2,
			Text = tostring(config.Content), Font = Enum.Font.Gotham, TextSize = 12,
			TextXAlignment = LEFT, TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = true, Parent = inner,
		})
		Paint(content, "TextColor3", "Muted")
	end

	local progress = Make("Frame", {
		Name = "Timer", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0),
		Size = UDim2.new(1, 0, 0, 2), Parent = card,
	})
	Bind(progress, function() progress.BackgroundColor3 = Theme[ntype] end)
	progress.BackgroundTransparency = 0.4

	local hit = Make("TextButton", { Name = "Hit", Size = UDim2.fromScale(1, 1), Text = "", ZIndex = 5, Parent = card })

	local dismissed = false
	local progressTween
	local handle = {}
	local function dismiss()
		if dismissed then return end
		dismissed = true
		local idx = table.find(activeNotifs, handle)
		if idx then table.remove(activeNotifs, idx) end
		if progressTween then progressTween:Cancel() end
		local out = Tween(card, { Position = UDim2.new(1, 40, 0, 0) },
			TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In))
		out.Completed:Once(function()
			if not wrapper:IsDescendantOf(game) then return end
			local h = wrapper.AbsoluteSize.Y
			wrapper.AutomaticSize = Enum.AutomaticSize.None
			wrapper.Size = UDim2.new(1, 0, 0, h)
			card.Visible = false
			local shrink = Tween(wrapper, { Size = UDim2.new(1, 0, 0, 0) }, TweenInfo.new(0.15))
			shrink.Completed:Once(function() wrapper:Destroy() end)
		end)
	end
	handle.Dismiss = dismiss
	table.insert(activeNotifs, handle)

	hit.Activated:Connect(dismiss)
	Tween(card, { Position = UDim2.new(0, 0, 0, 0) }, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out))
	progressTween = Tween(progress, { Size = UDim2.new(0, 0, 0, 2) },
		TweenInfo.new(duration, Enum.EasingStyle.Linear))
	progressTween.Completed:Once(function(state)
		if state == Enum.PlaybackState.Completed then dismiss() end
	end)
	return handle
end

--==================================================================--
-- 5. REGISTRO GLOBAL DE KEYBINDS (una sola conexión compartida)
--==================================================================--
local keybinds = {}
local keybindConn

local function ensureKeybindListener()
	if keybindConn then return end
	keybindConn = UserInputService.InputBegan:Connect(function(input, processed)
		if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
		for _, kb in ipairs(keybinds) do
			if kb.Listening then
				kb:_finishListening(input.KeyCode)
				return
			end
		end
		if processed then return end
		if UserInputService:GetFocusedTextBox() then return end
		for _, kb in ipairs(table.clone(keybinds)) do
			if kb.Key and kb.Key == input.KeyCode then
				SafeCall(kb.NameText, kb.Callback, kb.Key)
			end
		end
	end)
end
local function removeKeybind(kb)
	local i = table.find(keybinds, kb)
	if i then table.remove(keybinds, i) end
	if #keybinds == 0 and keybindConn then
		keybindConn:Disconnect()
		keybindConn = nil
	end
end

--==================================================================--
-- 6. COMPONENTES (clases)
--==================================================================--
local Component = {}
Component.__index = Component
local function newClass()
	local c = setmetatable({}, Component)
	c.__index = c
	return c
end
local ButtonC, ToggleC, SliderC, DropdownC = newClass(), newClass(), newClass(), newClass()
local InputC, KeybindC, LabelC, ParagraphC = newClass(), newClass(), newClass(), newClass()
local SectionC, DividerC, SearchC = newClass(), newClass(), newClass()

function Component:_updateSearch()
	self.SearchText = string.lower((self.NameText or "") .. " " .. (self.DescText or ""))
	if self.Tab and self.Tab.Query ~= "" then self.Tab:Filter(self.Tab.Query) end
end
function Component:SetName(text)
	self.NameText = tostring(text)
	if self.NameLabel then self.NameLabel.Text = self.NameText end
	self:_updateSearch()
end
function Component:SetDescription(text)
	self.DescText = tostring(text or "")
	if self.DescLabel then
		self.DescLabel.Text = self.DescText
		self.DescLabel.Visible = self.DescText ~= ""
	end
	self:_updateSearch()
end
function Component:Destroy()
	if self.Destroyed then return end
	self.Destroyed = true
	self.Maid:Clean()
	local list = self.Tab.Components
	local i = table.find(list, self)
	if i then table.remove(list, i) end
	if self.Frame then self.Frame:Destroy() end
	if self.Tab.Query ~= "" then self.Tab:Filter(self.Tab.Query) end
end

-- Press / hover para tarjetas clicables
local function Interactive(card, hit, maid, onClick)
	local hovering, pressing = false, false
	local function paint()
		local c = Theme.Raised
		if pressing then c = Theme.Raised:Lerp(Theme.Accent, 0.2)
		elseif hovering then c = Theme.Hover end
		Tween(card, { BackgroundColor3 = c })
	end
	maid:Give(hit.MouseEnter:Connect(function() hovering = true paint() end))
	maid:Give(hit.MouseLeave:Connect(function() hovering = false pressing = false paint() end))
	maid:Give(hit.MouseButton1Down:Connect(function() pressing = true paint() end))
	maid:Give(hit.MouseButton1Up:Connect(function() pressing = false paint() end))
	maid:Give(hit.Activated:Connect(function()
		pressing = false
		paint()
		onClick()
	end))
end

--==================================================================--
-- 7. PESTAÑAS
--==================================================================--
local Tab = {}
Tab.__index = Tab

function Tab:_nextOrder()
	self.Order += 1
	return self.Order
end

function Tab:_register(class, frame, kind, name, desc, nameLabel, descLabel)
	local comp = setmetatable({}, class)
	comp.Tab = self
	comp.Frame = frame
	comp.Kind = kind
	comp.NameText = tostring(name or "")
	comp.DescText = tostring(desc or "")
	comp.NameLabel = nameLabel
	comp.DescLabel = descLabel
	comp.SearchText = string.lower(comp.NameText .. " " .. comp.DescText)
	comp.Maid = Maid.new()
	comp.Destroyed = false
	table.insert(self.Components, comp)
	if self.Query ~= "" then self:Filter(self.Query) end
	return comp
end

-- Tarjeta base: card (visual) > body (padding + lista) > header (textos + control a la derecha)
function Tab:_card(name, desc, ctrlW, forceDesc)
	local card = Make("Frame", {
		Name = "Card", AutomaticSize = AUTO_Y, Size = UDim2.new(1, 0, 0, 0),
		LayoutOrder = self:_nextOrder(), Parent = self.Page,
	})
	Paint(card, "BackgroundColor3", "Raised")
	Corner(card, 10)
	local st = Stroke(card, 1, 0.45)
	Paint(st, "Color", "Border")
	local body = Make("Frame", {
		Name = "Body", BackgroundTransparency = 1, AutomaticSize = AUTO_Y,
		Size = UDim2.new(1, 0, 0, 0), Parent = card,
	})
	Padding(body, 11, 11, 12, 12)
	List(body, 8)
	local header = Make("Frame", {
		Name = "Header", BackgroundTransparency = 1, AutomaticSize = AUTO_Y,
		Size = UDim2.new(1, 0, 0, 22), LayoutOrder = 1, Parent = body,
	})
	local reserve = (ctrlW and ctrlW > 0) and (ctrlW + 10) or 0
	local texts = Make("Frame", {
		Name = "Texts", BackgroundTransparency = 1, AutomaticSize = AUTO_Y,
		Size = UDim2.new(1, -reserve, 0, 0), Parent = header,
	})
	List(texts, 2)
	local nameLabel = Make("TextLabel", {
		Name = "Name", AutomaticSize = AUTO_Y, Size = UDim2.new(1, 0, 0, 22), LayoutOrder = 1,
		Text = tostring(name), TextXAlignment = LEFT, TextWrapped = true, Parent = texts,
	})
	Paint(nameLabel, "TextColor3", "Text")
	local descLabel
	if forceDesc or (desc ~= nil and tostring(desc) ~= "") then
		descLabel = Make("TextLabel", {
			Name = "Description", AutomaticSize = AUTO_Y, Size = UDim2.new(1, 0, 0, 0), LayoutOrder = 2,
			Text = tostring(desc or ""), Font = Enum.Font.Gotham, TextSize = 12, TextXAlignment = LEFT,
			TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = true,
			Visible = (desc ~= nil and tostring(desc) ~= ""), Parent = texts,
		})
		Paint(descLabel, "TextColor3", "Muted")
	end
	return card, body, header, nameLabel, descLabel
end

local function overlay(parent)
	return Make("TextButton", { Name = "Hit", Size = UDim2.fromScale(1, 1), Text = "", ZIndex = 5, Parent = parent })
end

-- Botón -------------------------------------------------------------
function Tab:CreateButton(config)
	config = type(config) == "table" and config or {}
	local name = tostring(config.Name or "Botón")
	local card, _, header, nl, dl = self:_card(name, config.Description, 28)
	local comp = self:_register(ButtonC, card, "Button", name, config.Description, nl, dl)
	comp.Callback = config.Callback

	local dot = Make("Frame", {
		Name = "Affordance", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.fromOffset(24, 24), Parent = header,
	})
	Corner(dot, 12)
	local core = Make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(8, 8), Parent = dot,
	})
	Corner(core, 4)
	Bind(dot, function()
		dot.BackgroundColor3 = Theme.Accent
		dot.BackgroundTransparency = 0.82
		core.BackgroundColor3 = Theme.Accent
	end)

	Interactive(card, overlay(card), comp.Maid, function()
		SafeCall(comp.NameText, comp.Callback)
	end)
	return comp
end
function ButtonC:Fire() SafeCall(self.NameText, self.Callback) end

-- Toggle ------------------------------------------------------------
function Tab:CreateToggle(config)
	config = type(config) == "table" and config or {}
	local name = tostring(config.Name or "Toggle")
	local card, _, header, nl, dl = self:_card(name, config.Description, 44)
	local comp = self:_register(ToggleC, card, "Toggle", name, config.Description, nl, dl)
	comp.Callback = config.Callback
	comp.Value = config.Default == true

	local track = Make("Frame", {
		Name = "Switch", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.fromOffset(40, 22), Parent = header,
	})
	Corner(track, 11)
	local knob = Make("Frame", {
		Name = "Knob", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 3, 0.5, 0),
		Size = UDim2.fromOffset(16, 16), BackgroundColor3 = Color3.new(1, 1, 1), Parent = track,
	})
	Corner(knob, 8)

	comp._render = function(animate)
		local on = comp.Value
		Apply(track, { BackgroundColor3 = on and Theme.Accent or Theme.Border }, animate)
		Apply(knob, { Position = on and UDim2.new(1, -19, 0.5, 0) or UDim2.new(0, 3, 0.5, 0) }, animate)
	end
	Bind(card, function() comp._render(false) end)

	Interactive(card, overlay(card), comp.Maid, function() comp:Set(not comp.Value) end)
	return comp
end
function ToggleC:Set(value, silent)
	value = value and true or false
	if self.Value == value then return end
	self.Value = value
	self._render(true)
	if not silent then SafeCall(self.NameText, self.Callback, value) end
end
function ToggleC:Get() return self.Value end
function ToggleC:Toggle() self:Set(not self.Value) end

-- Slider ------------------------------------------------------------
function Tab:CreateSlider(config)
	config = type(config) == "table" and config or {}
	local name = tostring(config.Name or "Slider")
	local min = tonumber(config.Min) or 0
	local max = tonumber(config.Max) or 100
	if max <= min then max = min + 1 end
	local step = tonumber(config.Step) or 1
	if step <= 0 then step = 1 end
	local suffix = config.Suffix and tostring(config.Suffix) or ""

	local card, body, header, nl, dl = self:_card(name, config.Description, 64)
	local comp = self:_register(SliderC, card, "Slider", name, config.Description, nl, dl)
	comp.Callback = config.Callback
	comp.Min, comp.Max, comp.Step = min, max, step

	local function snap(v)
		v = math.clamp(v, min, max)
		v = min + math.floor((v - min) / step + 0.5) * step
		v = math.clamp(v, min, max)
		return math.floor(v * 1e6 + 0.5) / 1e6
	end
	comp._snap = snap
	comp.Value = snap(tonumber(config.Default) or min)

	local valueLabel = Make("TextLabel", {
		Name = "Value", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.fromOffset(64, 22), Font = Enum.Font.GothamBold, TextSize = 13,
		TextXAlignment = RIGHT, Parent = header,
	})
	Paint(valueLabel, "TextColor3", "Accent")

	local row = Make("Frame", {
		Name = "SliderRow", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 20),
		LayoutOrder = 2, Active = true, Parent = body,
	})
	local track = Make("Frame", {
		Name = "Track", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 0),
		Size = UDim2.new(1, 0, 0, 6), Parent = row,
	})
	Corner(track, 3)
	Paint(track, "BackgroundColor3", "Border")
	local fill = Make("Frame", { Name = "Fill", Size = UDim2.new(0, 0, 1, 0), Parent = track })
	Corner(fill, 3)
	Paint(fill, "BackgroundColor3", "Accent")
	local knob = Make("Frame", {
		Name = "Knob", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, 0, 0.5, 0),
		Size = UDim2.fromOffset(16, 16), Parent = track,
	})
	Corner(knob, 8)
	Paint(knob, "BackgroundColor3", "Text")

	comp._render = function()
		local rel = (comp.Value - min) / (max - min)
		fill.Size = UDim2.new(rel, 0, 1, 0)
		knob.Position = UDim2.new(rel, 0, 0.5, 0)
		valueLabel.Text = tostring(comp.Value) .. suffix
	end
	comp._render()

	local dragType, moveConn, endConn
	local function stopDrag()
		dragType = nil
		if moveConn then moveConn:Disconnect() moveConn = nil end
		if endConn then endConn:Disconnect() endConn = nil end
		if self.Page and self.Page.Parent then self.Page.ScrollingEnabled = true end
	end
	local function updateFromX(x)
		local w = track.AbsoluteSize.X
		if w <= 0 then return end
		comp:Set(min + (max - min) * math.clamp((x - track.AbsolutePosition.X) / w, 0, 1))
	end
	comp.Maid:Give(row.InputBegan:Connect(function(input)
		local ut = input.UserInputType
		if ut ~= Enum.UserInputType.MouseButton1 and ut ~= Enum.UserInputType.Touch then return end
		stopDrag()
		dragType = ut
		self.Page.ScrollingEnabled = false
		updateFromX(input.Position.X)
		moveConn = UserInputService.InputChanged:Connect(function(i)
			if not dragType then return end
			if (dragType == Enum.UserInputType.MouseButton1 and i.UserInputType == Enum.UserInputType.MouseMovement)
				or (dragType == Enum.UserInputType.Touch and i.UserInputType == Enum.UserInputType.Touch) then
				updateFromX(i.Position.X)
			end
		end)
		endConn = UserInputService.InputEnded:Connect(function(i)
			if i.UserInputType == dragType then stopDrag() end
		end)
	end))
	comp.Maid:Give(stopDrag)
	return comp
end
function SliderC:Set(value, silent)
	if type(value) ~= "number" then return end
	local v = self._snap(value)
	if v == self.Value then return end
	self.Value = v
	self._render()
	if not silent then SafeCall(self.NameText, self.Callback, v) end
end
function SliderC:Get() return self.Value end

-- Dropdown ----------------------------------------------------------
function Tab:CreateDropdown(config)
	config = type(config) == "table" and config or {}
	local name = tostring(config.Name or "Dropdown")
	local card, body, header, nl, dl = self:_card(name, config.Description, 150)
	local comp = self:_register(DropdownC, card, "Dropdown", name, config.Description, nl, dl)
	comp.Callback = config.Callback
	comp.Options = {}
	comp.Value = nil
	comp.IsOpen = false
	local placeholder = tostring(config.Placeholder or "Seleccionar")

	local ctrl = Make("Frame", {
		Name = "Control", BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.fromOffset(150, 22), Parent = header,
	})
	local valueLabel = Make("TextLabel", {
		Name = "Value", Size = UDim2.new(1, -20, 1, 0), TextSize = 13, TextXAlignment = RIGHT,
		TextTruncate = Enum.TextTruncate.AtEnd, Parent = ctrl,
	})
	Paint(valueLabel, "TextColor3", "Accent")
	local chev = Make("Frame", {
		Name = "Chevron", BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.fromOffset(12, 10), Parent = ctrl,
	})
	for _, spec in ipairs({ { 45, 0.2917 }, { -45, 0.7083 } }) do
		local b = Make("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(spec[2], 0.4),
			Size = UDim2.fromOffset(7, 2), Rotation = spec[1], Parent = chev,
		})
		Corner(b, 1)
		Paint(b, "BackgroundColor3", "Muted")
	end

	local holder = Make("Frame", {
		Name = "List", BackgroundTransparency = 1, ClipsDescendants = true,
		Size = UDim2.new(1, 0, 0, 0), LayoutOrder = 2, Visible = false, Parent = body,
	})
	local scroller = Make("ScrollingFrame", {
		Name = "Options", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1),
		ScrollBarThickness = 2, AutomaticCanvasSize = AUTO_Y, CanvasSize = UDim2.new(),
		ScrollingDirection = Enum.ScrollingDirection.Y, Parent = holder,
	})
	Paint(scroller, "ScrollBarImageColor3", "Muted")
	List(scroller, 3)

	local optionButtons = {}
	local function listHeight()
		local n = math.min(#comp.Options, 5)
		if n == 0 then return 0 end
		return n * 30 + (n - 1) * 3
	end
	local function paintOptions(animate)
		for _, entry in ipairs(optionButtons) do
			local sel = entry.value == comp.Value
			Apply(entry.button, {
				BackgroundColor3 = sel and Theme.Accent or Theme.Hover,
				BackgroundTransparency = sel and 0.84 or 1,
			}, animate)
			entry.button.TextColor3 = sel and Theme.Accent or Theme.Text
		end
	end
	local function renderValue()
		valueLabel.Text = comp.Value ~= nil and tostring(comp.Value) or placeholder
	end
	Bind(card, function() renderValue() paintOptions(false) end)

	local function setOpen(state)
		comp.IsOpen = state
		if state then
			holder.Visible = true
			Tween(holder, { Size = UDim2.new(1, 0, 0, listHeight()) }, TWEEN_MED)
			Tween(chev, { Rotation = 180 })
		else
			local tw = Tween(holder, { Size = UDim2.new(1, 0, 0, 0) }, TWEEN_MED)
			tw.Completed:Once(function() if not comp.IsOpen then holder.Visible = false end end)
			Tween(chev, { Rotation = 0 })
		end
	end
	comp._setOpen = setOpen

	local function buildOptions()
		for _, entry in ipairs(optionButtons) do
			entry.button:Destroy()
		end
		optionButtons = {}
		for i, opt in ipairs(comp.Options) do
			local b = Make("TextButton", {
				Name = "Option", Size = UDim2.new(1, -4, 0, 30), LayoutOrder = i, Text = tostring(opt),
				TextSize = 13, TextXAlignment = LEFT, Parent = scroller,
			})
			Corner(b, 8)
			Padding(b, 0, 0, 10, 10)
			local entry = { button = b, value = opt }
			table.insert(optionButtons, entry)
			b.MouseEnter:Connect(function()
				if entry.value ~= comp.Value then Tween(b, { BackgroundTransparency = 0.6 }) end
			end)
			b.MouseLeave:Connect(function()
				if entry.value ~= comp.Value then Tween(b, { BackgroundTransparency = 1 }) end
			end)
			b.Activated:Connect(function() comp:Set(opt) setOpen(false) end)
		end
		paintOptions(false)
		if comp.IsOpen then holder.Size = UDim2.new(1, 0, 0, listHeight()) end
	end
	comp._build = function(options)
		comp.Options = {}
		for _, o in ipairs(options) do table.insert(comp.Options, o) end
		buildOptions()
	end
	comp._renderValue = renderValue
	comp._paintOptions = paintOptions

	comp._build(type(config.Options) == "table" and config.Options or {})
	if config.Default ~= nil and table.find(comp.Options, config.Default) then comp.Value = config.Default end
	renderValue()
	paintOptions(false)

	local hit = overlay(header)
	comp.Maid:Give(hit.Activated:Connect(function() setOpen(not comp.IsOpen) end))
	return comp
end
function DropdownC:Set(value, silent)
	if table.find(self.Options, value) == nil then return end
	if self.Value == value then return end
	self.Value = value
	self._renderValue()
	self._paintOptions(true)
	if not silent then SafeCall(self.NameText, self.Callback, value) end
end
function DropdownC:Get() return self.Value end
function DropdownC:SetOptions(options)
	if type(options) ~= "table" then return end
	self._build(options)
	if self.Value ~= nil and table.find(self.Options, self.Value) == nil then self.Value = nil end
	self._renderValue()
	self._paintOptions(false)
end
function DropdownC:Open() self._setOpen(true) end
function DropdownC:Close() self._setOpen(false) end

-- Input -------------------------------------------------------------
function Tab:CreateInput(config)
	config = type(config) == "table" and config or {}
	local name = tostring(config.Name or "Input")
	local card, body, _, nl, dl = self:_card(name, config.Description, 0)
	local comp = self:_register(InputC, card, "Input", name, config.Description, nl, dl)
	comp.Callback = config.Callback
	comp.Value = tostring(config.Default or "")

	local box = Make("Frame", { Name = "InputBox", Size = UDim2.new(1, 0, 0, 32), LayoutOrder = 2, Parent = body })
	Corner(box, 8)
	Paint(box, "BackgroundColor3", "Background")
	local st = Stroke(box, 1, 0.2)
	Paint(st, "Color", "Border")
	local tb = Make("TextBox", {
		Name = "TextBox", Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -20, 1, 0),
		Text = comp.Value, PlaceholderText = tostring(config.Placeholder or ""), ClearTextOnFocus = false,
		Font = Enum.Font.Gotham, TextSize = 13, TextXAlignment = LEFT, Parent = box,
	})
	Paint(tb, "TextColor3", "Text")
	Paint(tb, "PlaceholderColor3", "Muted")
	comp.TextBox = tb

	comp.Maid:Give(tb.Focused:Connect(function() Tween(st, { Color = Theme.Accent }) end))
	comp.Maid:Give(tb.FocusLost:Connect(function()
		Tween(st, { Color = Theme.Border })
		comp.Value = tb.Text
		SafeCall(comp.NameText, comp.Callback, comp.Value)
	end))
	return comp
end
function InputC:Get() return self.Value end
function InputC:Set(text, silent)
	self.Value = tostring(text or "")
	self.TextBox.Text = self.Value
	if not silent then SafeCall(self.NameText, self.Callback, self.Value) end
end

-- Keybind -----------------------------------------------------------
function Tab:CreateKeybind(config)
	config = type(config) == "table" and config or {}
	local name = tostring(config.Name or "Atajo")
	local card, _, header, nl, dl = self:_card(name, config.Description, 110)
	local comp = self:_register(KeybindC, card, "Keybind", name, config.Description, nl, dl)
	comp.Callback = config.Callback
	comp.OnChanged = config.OnChanged
	comp.Key = typeof(config.Default) == "EnumItem" and config.Default or nil
	comp.Listening = false

	local btn = Make("TextButton", {
		Name = "Key", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.fromOffset(110, 26), TextSize = 12, BackgroundTransparency = 0, Parent = header,
	})
	Corner(btn, 7)
	local st = Stroke(btn, 1, 0.2)

	comp._render = function()
		btn.Text = comp.Listening and "Presiona..." or (comp.Key and comp.Key.Name or "Ninguna")
		btn.BackgroundColor3 = Theme.Background
		btn.TextColor3 = comp.Listening and Theme.Text or Theme.Accent
		st.Color = comp.Listening and Theme.Accent or Theme.Border
	end
	Bind(card, comp._render)

	comp.Maid:Give(btn.Activated:Connect(function()
		comp.Listening = not comp.Listening
		comp._render()
	end))
	table.insert(keybinds, comp)
	ensureKeybindListener()
	comp.Maid:Give(function() removeKeybind(comp) end)
	return comp
end
function KeybindC:_finishListening(keyCode)
	self.Listening = false
	if keyCode ~= Enum.KeyCode.Escape and keyCode ~= Enum.KeyCode.Unknown then
		self:Set(keyCode)
	else
		self._render()
	end
end
function KeybindC:Set(key, silent)
	if key ~= nil and typeof(key) ~= "EnumItem" then return end
	self.Key = key
	self.Listening = false
	self._render()
	if not silent then SafeCall(self.NameText, self.OnChanged, key) end
end
function KeybindC:Get() return self.Key end

-- Section / Label / Paragraph / Divider ------------------------------
function Tab:CreateSection(text)
	text = tostring(text or "")
	local label = Make("TextLabel", {
		Name = "Section", Size = UDim2.new(1, 0, 0, 26), Text = string.upper(text),
		Font = Enum.Font.GothamBold, TextSize = 12, TextXAlignment = LEFT,
		TextYAlignment = Enum.TextYAlignment.Bottom, LayoutOrder = self:_nextOrder(), Parent = self.Page,
	})
	Padding(label, 0, 2, 4, 4)
	Paint(label, "TextColor3", "Accent")
	local comp = self:_register(SectionC, label, "Section", text, "", label, nil)
	return comp
end
function SectionC:SetName(text)
	self.NameText = tostring(text)
	self.NameLabel.Text = string.upper(self.NameText)
	self:_updateSearch()
end
SectionC.Set = SectionC.SetName

function Tab:CreateLabel(text)
	if type(text) == "table" then text = text.Text or text.Name end
	text = tostring(text or "")
	local label = Make("TextLabel", {
		Name = "Label", AutomaticSize = AUTO_Y, Size = UDim2.new(1, 0, 0, 0), Text = text,
		Font = Enum.Font.Gotham, TextSize = 13, TextXAlignment = LEFT, TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true, LayoutOrder = self:_nextOrder(), Parent = self.Page,
	})
	Padding(label, 2, 2, 4, 4)
	Paint(label, "TextColor3", "Muted")
	return self:_register(LabelC, label, "Label", text, "", label, nil)
end
function LabelC:Set(text) self:SetName(text) end
function LabelC:Get() return self.NameText end

function Tab:CreateParagraph(config)
	config = type(config) == "table" and config or {}
	local title = tostring(config.Title or "")
	local content = tostring(config.Content or "")
	local card, _, _, nl, dl = self:_card(title, content, 0, true)
	nl.Font = Enum.Font.GothamBold
	local comp = self:_register(ParagraphC, card, "Paragraph", title, content, nl, dl)
	return comp
end
function ParagraphC:Set(title, content)
	if title ~= nil then self:SetName(title) end
	if content ~= nil then self:SetDescription(content) end
end

function Tab:CreateDivider()
	local line = Make("Frame", {
		Name = "Divider", Size = UDim2.new(1, 0, 0, 1), BackgroundTransparency = 0.3,
		LayoutOrder = self:_nextOrder(), Parent = self.Page,
	})
	Paint(line, "BackgroundColor3", "Border")
	return self:_register(DividerC, line, "Divider", "", "", nil, nil)
end

-- Búsqueda ----------------------------------------------------------
function Tab:Filter(query)
	query = string.lower(tostring(query or ""))
	query = query:match("^%s*(.-)%s*$")
	self.Query = query
	local section, sectionHasMatch = nil, false
	local function closeSection()
		if section then section.Frame.Visible = (query == "") or sectionHasMatch end
	end
	for _, comp in ipairs(self.Components) do
		if comp.Kind == "Section" then
			closeSection()
			section = comp
			sectionHasMatch = false
		elseif comp.Kind == "Divider" then
			comp.Frame.Visible = (query == "")
		elseif comp.Kind ~= "Search" then
			local vis = (query == "") or (string.find(comp.SearchText, query, 1, true) ~= nil)
			comp.Frame.Visible = vis
			if vis then sectionHasMatch = true end
		end
	end
	closeSection()
end

function Tab:CreateSearch(config)
	if self.SearchComponent and not self.SearchComponent.Destroyed then return self.SearchComponent end
	config = type(config) == "table" and config or {}
	local box = Make("Frame", { Name = "Search", Size = UDim2.new(1, 0, 0, 34), LayoutOrder = 0, Parent = self.Page })
	Paint(box, "BackgroundColor3", "Raised")
	Corner(box, 10)
	local st = Stroke(box, 1, 0.45)
	Paint(st, "Color", "Border")
	local tb = Make("TextBox", {
		Name = "TextBox", Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -24, 1, 0), Text = "",
		PlaceholderText = tostring(config.Placeholder or "Buscar..."), ClearTextOnFocus = false,
		Font = Enum.Font.Gotham, TextSize = 13, TextXAlignment = LEFT, Parent = box,
	})
	Paint(tb, "TextColor3", "Text")
	Paint(tb, "PlaceholderColor3", "Muted")
	local comp = self:_register(SearchC, box, "Search", "", "", nil, nil)
	comp.TextBox = tb
	comp.Maid:Give(tb:GetPropertyChangedSignal("Text"):Connect(function() self:Filter(tb.Text) end))
	comp.Maid:Give(tb.Focused:Connect(function() Tween(st, { Color = Theme.Accent }) end))
	comp.Maid:Give(tb.FocusLost:Connect(function() Tween(st, { Color = Theme.Border }) end))
	self.SearchComponent = comp
	return comp
end
function SearchC:Get() return self.TextBox.Text end
function SearchC:Set(text) self.TextBox.Text = tostring(text or "") end
function SearchC:Clear() self.TextBox.Text = "" end

-- Pestaña: estado visual y ciclo de vida ------------------------------
function Tab:_refresh(animate)
	if self.Destroyed then return end
	local sel, hov = self.Selected, self.Hovered
	Apply(self.Button, {
		BackgroundColor3 = sel and Theme.Accent or Theme.Hover,
		BackgroundTransparency = sel and 0.86 or (hov and 0.6 or 1),
	}, animate)
	local tint = sel and Theme.Accent or Theme.Muted
	Apply(self.Label, { TextColor3 = sel and Theme.Text or Theme.Muted }, animate)
	Apply(self.Indicator, { Size = UDim2.fromOffset(3, sel and 16 or 0), BackgroundColor3 = Theme.Accent }, animate)
	if self.IconImage then
		Apply(self.IconImage, { ImageColor3 = tint }, animate)
	else
		Apply(self.Badge, { BackgroundColor3 = tint, BackgroundTransparency = sel and 0.75 or 0.88 }, animate)
		Apply(self.BadgeText, { TextColor3 = tint }, animate)
	end
end
function Tab:Select() self.Window:SelectTab(self) end
function Tab:Destroy()
	if self.Destroyed then return end
	self.Destroyed = true
	self.Query = ""
	for _, c in ipairs(table.clone(self.Components)) do c:Destroy() end
	self.Maid:Clean()
	self.Button:Destroy()
	self.Page:Destroy()
	local win = self.Window
	local i = table.find(win.Tabs, self)
	if i then table.remove(win.Tabs, i) end
	if win.ActiveTab == self then
		win.ActiveTab = nil
		if not win.Destroyed and win.Tabs[1] then win:SelectTab(win.Tabs[1]) end
	end
end

--==================================================================--
-- 8. VENTANA
--==================================================================--
local Window = {}
Window.__index = Window
local TOPBAR_H = 44
local displayCounter = 100

function Window:_viewport()
	local s = self.Gui.AbsoluteSize
	if s.X < 100 or s.Y < 100 then
		local cam = workspace.CurrentCamera
		if cam then return cam.ViewportSize end
		return Vector2.new(1280, 720)
	end
	return s
end

function Window:_clamp()
	local vp = self:_viewport()
	local h = self.Minimized and TOPBAR_H or self.BaseSize.Y
	local sz = Vector2.new(self.BaseSize.X, h) * self.CurrentScale
	local m = 4
	local x, y = self.Pos.X, self.Pos.Y
	if sz.X + 2 * m >= vp.X then x = vp.X / 2 else x = math.clamp(x, sz.X / 2 + m, vp.X - sz.X / 2 - m) end
	if sz.Y + 2 * m >= vp.Y then y = m else y = math.clamp(y, m, vp.Y - sz.Y - m) end
	self.Pos = Vector2.new(x, y)
	self.Frame.Position = UDim2.fromOffset(x, y)
end

function Window:_layout()
	if self.Destroyed then return end
	local vp = self:_viewport()
	local req = self.Requested
	local fit = math.min((vp.X - 16) / req.X, (vp.Y - 16) / req.Y)
	local s = math.clamp(fit, 0.8, 1) * self.UserScale
	local w = math.clamp(req.X, self.MinSize.X, self.MaxSize.X)
	local h = math.clamp(req.Y, self.MinSize.Y, self.MaxSize.Y)
	w = math.min(w, (vp.X - 16) / s)
	h = math.min(h, (vp.Y - 16) / s)
	self.BaseSize = Vector2.new(w, h)
	self.CurrentScale = s
	self.Frame.Size = UDim2.fromOffset(w, self.Minimized and TOPBAR_H or h)
	self.UIScale.Scale = s
	local sideW = (w < 540) and 118 or 150
	self.Sidebar.Size = UDim2.new(0, sideW, 1, 0)
	self.Content.Position = UDim2.new(0, sideW, 0, 0)
	self.Content.Size = UDim2.new(1, -sideW, 1, 0)
	self:_clamp()
end

function Window:Raise()
	displayCounter += 1
	self.Gui.DisplayOrder = displayCounter
end

function Window:Show()
	if self.Destroyed then return end
	self.Visible = true
	self.Gui.Enabled = true
	self.LauncherGui.Enabled = false
	self:Raise()
	self.UIScale.Scale = self.CurrentScale * 0.92
	Tween(self.UIScale, { Scale = self.CurrentScale }, TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out))
end
function Window:Hide()
	if self.Destroyed or not self.Visible then return end
	self.Visible = false
	self.LauncherGui.Enabled = true
	local tw = Tween(self.UIScale, { Scale = self.CurrentScale * 0.92 },
		TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In))
	tw.Completed:Once(function()
		if not self.Visible and not self.Destroyed then self.Gui.Enabled = false end
	end)
end
function Window:Toggle()
	if self.Visible then self:Hide() else self:Show() end
end
function Window:IsVisible() return self.Visible end

function Window:Minimize()
	if self.Destroyed or self.Minimized then return end
	self.Minimized = true
	local tw = Tween(self.Frame, { Size = UDim2.fromOffset(self.BaseSize.X, TOPBAR_H) }, TWEEN_MED)
	tw.Completed:Once(function()
		if self.Minimized and not self.Destroyed then self.Body.Visible = false end
	end)
end
function Window:Restore()
	if self.Destroyed or not self.Minimized then return end
	self.Minimized = false
	self.Body.Visible = true
	Tween(self.Frame, { Size = UDim2.fromOffset(self.BaseSize.X, self.BaseSize.Y) }, TWEEN_MED)
	self:_clamp()
end
function Window:ToggleMinimize()
	if self.Minimized then self:Restore() else self:Minimize() end
end

function Window:SetScale(n)
	if type(n) ~= "number" then return end
	self.UserScale = math.clamp(n, 0.5, 1.5)
	self:_layout()
end
function Window:SetTitle(title, subtitle)
	if title ~= nil then self.TitleLabel.Text = tostring(title) end
	if subtitle ~= nil then self.SubtitleLabel.Text = tostring(subtitle) end
end
function Window:GetTab(name)
	for _, t in ipairs(self.Tabs) do
		if t.Name == name then return t end
	end
	return nil
end

function Window:SelectTab(target)
	if self.Destroyed then return end
	local tab = target
	if type(target) == "string" then tab = self:GetTab(target)
	elseif type(target) == "number" then tab = self.Tabs[target] end
	if type(tab) ~= "table" or tab.Destroyed or tab == self.ActiveTab then return end
	local prev = self.ActiveTab
	self.ActiveTab = tab
	if prev and not prev.Destroyed then
		prev.Selected = false
		prev.Page.Visible = false
		prev:_refresh(true)
	end
	tab.Selected = true
	tab.Page.Visible = true
	tab:_refresh(true)
end

function Window:CreateTab(config)
	if type(config) == "string" then config = { Name = config } end
	config = type(config) == "table" and config or {}
	local tab = setmetatable({}, Tab)
	tab.Window = self
	tab.Name = tostring(config.Name or ("Pestaña " .. (#self.Tabs + 1)))
	tab.Maid = Maid.new()
	tab.Components = {}
	tab.Order = 0
	tab.Query = ""
	tab.Selected = false
	tab.Hovered = false
	tab.Destroyed = false

	local btn = Make("TextButton", {
		Name = "Tab_" .. tab.Name, Size = UDim2.new(1, 0, 0, 36), Text = "",
		LayoutOrder = #self.Tabs + 1, Parent = self.TabList,
	})
	Corner(btn, 9)
	tab.Button = btn
	tab.Indicator = Make("Frame", {
		Name = "Indicator", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 0),
		Size = UDim2.fromOffset(3, 0), Parent = btn,
	})
	Corner(tab.Indicator, 2)
	local iconHolder = Make("Frame", {
		Name = "Icon", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 12, 0.5, 0), Size = UDim2.fromOffset(18, 18), Parent = btn,
	})
	local asset = resolveIcon(config.Icon)
	if asset then
		tab.IconImage = Make("ImageLabel", {
			BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Image = asset, Parent = iconHolder,
		})
	else
		tab.Badge = Make("Frame", { Size = UDim2.fromScale(1, 1), Parent = iconHolder })
		Corner(tab.Badge, 5)
		tab.BadgeText = Make("TextLabel", {
			Size = UDim2.fromScale(1, 1), Text = string.upper(string.sub(tab.Name, 1, 1)),
			Font = Enum.Font.GothamBold, TextSize = 11, Parent = tab.Badge,
		})
	end
	tab.Label = Make("TextLabel", {
		Name = "Label", Position = UDim2.new(0, 38, 0, 0), Size = UDim2.new(1, -44, 1, 0), Text = tab.Name,
		TextSize = 13, TextXAlignment = LEFT, TextTruncate = Enum.TextTruncate.AtEnd, Parent = btn,
	})

	local page = Make("ScrollingFrame", {
		Name = "Page_" .. tab.Name, BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1),
		ScrollBarThickness = 3, AutomaticCanvasSize = AUTO_Y, CanvasSize = UDim2.new(),
		ScrollingDirection = Enum.ScrollingDirection.Y, Visible = false, Parent = self.Content,
	})
	Paint(page, "ScrollBarImageColor3", "Muted")
	Padding(page, 12, 12, 12, 12)
	List(page, 8)
	tab.Page = page

	Bind(btn, function() tab:_refresh(false) end)
	tab.Maid:Give(btn.MouseEnter:Connect(function() tab.Hovered = true tab:_refresh(true) end))
	tab.Maid:Give(btn.MouseLeave:Connect(function() tab.Hovered = false tab:_refresh(true) end))
	tab.Maid:Give(btn.Activated:Connect(function() self:SelectTab(tab) end))

	table.insert(self.Tabs, tab)
	if not self.ActiveTab then self:SelectTab(tab) end
	return tab
end

function Window:Destroy()
	if self.Destroyed then return end
	self.Destroyed = true
	for _, tab in ipairs(table.clone(self.Tabs)) do tab:Destroy() end
	self.Maid:Clean()
	local i = table.find(NuuUI.Windows, self)
	if i then table.remove(NuuUI.Windows, i) end
	RefreshBindings(false)
end
function Window:Close()
	if self.Destroyed then return end
	local tw = Tween(self.UIScale, { Scale = self.CurrentScale * 0.9 },
		TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In))
	tw.Completed:Once(function() self:Destroy() end)
end

local function drawBar(parent, rotation, width)
	local f = Make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(width, 2), Rotation = rotation, Parent = parent,
	})
	Corner(f, 1)
	Paint(f, "BackgroundColor3", "Muted")
	return f
end

local function topButton(parent, xOffset, hoverKey)
	local b = Make("TextButton", {
		AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, xOffset, 0.5, 0),
		Size = UDim2.fromOffset(30, 30), Text = "", BackgroundTransparency = 1, Parent = parent,
	})
	Corner(b, 8)
	Bind(b, function() b.BackgroundColor3 = Theme[hoverKey] end)
	b.MouseEnter:Connect(function() Tween(b, { BackgroundTransparency = 0.15 }) end)
	b.MouseLeave:Connect(function() Tween(b, { BackgroundTransparency = 1 }) end)
	return b
end

function NuuUI:CreateWindow(config)
	config = type(config) == "table" and config or {}
	if config.Theme ~= nil then self:SetTheme(config.Theme) end

	local win = setmetatable({}, Window)
	win.Maid = Maid.new()
	win.Tabs = {}
	win.Visible = true
	win.Minimized = false
	win.Destroyed = false
	win.UserScale = 1
	win.CurrentScale = 1
	local sz = typeof(config.Size) == "UDim2" and config.Size or UDim2.fromOffset(650, 450)
	win.Requested = Vector2.new(sz.X.Offset > 0 and sz.X.Offset or 650, sz.Y.Offset > 0 and sz.Y.Offset or 450)
	win.MinSize = typeof(config.MinSize) == "Vector2" and config.MinSize or Vector2.new(420, 300)
	win.MaxSize = typeof(config.MaxSize) == "Vector2" and config.MaxSize or Vector2.new(1100, 760)
	win.BaseSize = win.Requested
	win.Pos = Vector2.new(0, 0)

	displayCounter += 1
	local gui = win.Maid:Give(Make("ScreenGui", {
		Name = "NuuUI_Window", ResetOnSpawn = false, IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = displayCounter, Parent = PlayerGui,
	}))
	win.Gui = gui

	local main = Make("Frame", {
		Name = "Window", AnchorPoint = Vector2.new(0.5, 0), ClipsDescendants = true,
		Size = UDim2.fromOffset(win.Requested.X, win.Requested.Y), Parent = gui,
	})
	Paint(main, "BackgroundColor3", "Background")
	Corner(main, 14)
	local mainStroke = Stroke(main, 1, 0.15)
	Paint(mainStroke, "Color", "Border")
	win.Frame = main
	win.UIScale = Make("UIScale", { Parent = main })

	-- Barra superior
	local top = Make("Frame", { Name = "TopBar", Size = UDim2.new(1, 0, 0, TOPBAR_H), Parent = main })
	Paint(top, "BackgroundColor3", "Surface")
	local topLine = Make("Frame", {
		AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0), Size = UDim2.new(1, 0, 0, 1), Parent = top,
	})
	Paint(topLine, "BackgroundColor3", "Border")
	win.TitleLabel = Make("TextLabel", {
		Name = "Title", Position = UDim2.fromOffset(16, 6), Size = UDim2.new(1, -110, 0, 18),
		Text = tostring(config.Title or "NuuUI"), Font = Enum.Font.GothamBold, TextSize = 15,
		TextXAlignment = LEFT, TextTruncate = Enum.TextTruncate.AtEnd, Parent = top,
	})
	Paint(win.TitleLabel, "TextColor3", "Text")
	win.SubtitleLabel = Make("TextLabel", {
		Name = "Subtitle", Position = UDim2.fromOffset(16, 24), Size = UDim2.new(1, -110, 0, 14),
		Text = tostring(config.Subtitle or ""), Font = Enum.Font.Gotham, TextSize = 11,
		TextXAlignment = LEFT, TextTruncate = Enum.TextTruncate.AtEnd, Parent = top,
	})
	Paint(win.SubtitleLabel, "TextColor3", "Muted")

	local closeBtn = topButton(top, -8, "Error")
	drawBar(closeBtn, 45, 14)
	drawBar(closeBtn, -45, 14)
	local minBtn = topButton(top, -42, "Hover")
	drawBar(minBtn, 0, 12)
	win.Maid:Give(closeBtn.Activated:Connect(function() win:Close() end))
	win.Maid:Give(minBtn.Activated:Connect(function() win:ToggleMinimize() end))

	-- Cuerpo: barra lateral + contenido
	local body = Make("Frame", {
		Name = "Body", BackgroundTransparency = 1, Position = UDim2.fromOffset(0, TOPBAR_H),
		Size = UDim2.new(1, 0, 1, -TOPBAR_H), Parent = main,
	})
	win.Body = body
	local sidebar = Make("Frame", { Name = "Sidebar", Size = UDim2.new(0, 150, 1, 0), Parent = body })
	Paint(sidebar, "BackgroundColor3", "Surface")
	local sideLine = Make("Frame", {
		AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.new(0, 1, 1, 0), Parent = sidebar,
	})
	Paint(sideLine, "BackgroundColor3", "Border")
	win.Sidebar = sidebar
	win.TabList = Make("ScrollingFrame", {
		Name = "Tabs", BackgroundTransparency = 1, Size = UDim2.new(1, -1, 1, -28), ScrollBarThickness = 0,
		AutomaticCanvasSize = AUTO_Y, CanvasSize = UDim2.new(), ScrollingDirection = Enum.ScrollingDirection.Y,
		Parent = sidebar,
	})
	Padding(win.TabList, 10, 10, 8, 8)
	List(win.TabList, 4)
	local version = Make("TextLabel", {
		Name = "Version", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0),
		Size = UDim2.new(1, -1, 0, 24), Text = "NuuUI v" .. NuuUI.Version, Font = Enum.Font.Gotham,
		TextSize = 11, Parent = sidebar,
	})
	Paint(version, "TextColor3", "Muted")
	win.Content = Make("Frame", {
		Name = "Content", BackgroundTransparency = 1, ClipsDescendants = true,
		Position = UDim2.new(0, 150, 0, 0), Size = UDim2.new(1, -150, 1, 0), Parent = body,
	})

	-- Lanzador flotante (aparece sólo cuando la ventana está oculta; útil en móvil)
	local launcherGui = win.Maid:Give(Make("ScreenGui", {
		Name = "NuuUI_Launcher", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 9000,
		Enabled = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Parent = PlayerGui,
	}))
	win.LauncherGui = launcherGui
	local launcher = Make("TextButton", {
		Name = "Launcher", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 12, 0.5, 0),
		Size = UDim2.fromOffset(44, 44), Text = "N", Font = Enum.Font.GothamBold, TextSize = 18,
		BackgroundTransparency = 0, Parent = launcherGui,
	})
	Corner(launcher, 22)
	Bind(launcher, function()
		launcher.BackgroundColor3 = Theme.Accent
		launcher.TextColor3 = Theme.Background
	end)
	win.Maid:Give(launcher.Activated:Connect(function() win:Show() end))

	-- Arrastre (mouse y táctil); las conexiones de movimiento sólo existen mientras se arrastra
	local dragType, dragStart, startPos, dragMove, dragEnd
	local function stopDrag()
		dragType = nil
		if dragMove then dragMove:Disconnect() dragMove = nil end
		if dragEnd then dragEnd:Disconnect() dragEnd = nil end
	end
	win.Maid:Give(top.InputBegan:Connect(function(input)
		local ut = input.UserInputType
		if ut ~= Enum.UserInputType.MouseButton1 and ut ~= Enum.UserInputType.Touch then return end
		win:Raise()
		stopDrag()
		dragType = ut
		dragStart = Vector2.new(input.Position.X, input.Position.Y)
		startPos = win.Pos
		dragMove = UserInputService.InputChanged:Connect(function(i)
			if not dragType then return end
			if (dragType == Enum.UserInputType.MouseButton1 and i.UserInputType == Enum.UserInputType.MouseMovement)
				or (dragType == Enum.UserInputType.Touch and i.UserInputType == Enum.UserInputType.Touch) then
				win.Pos = startPos + (Vector2.new(i.Position.X, i.Position.Y) - dragStart)
				win:_clamp()
			end
		end)
		dragEnd = UserInputService.InputEnded:Connect(function(i)
			if i.UserInputType == dragType then stopDrag() end
		end)
	end))
	win.Maid:Give(stopDrag)

	-- Resolución / orientación
	win.Maid:Give(gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function() win:_layout() end))

	-- Posición inicial centrada
	local vp = win:_viewport()
	win.Pos = Vector2.new(vp.X / 2, 0)
	win:_layout()
	win.Pos = Vector2.new(vp.X / 2, (vp.Y - win.BaseSize.Y * win.CurrentScale) / 2)
	win:_clamp()

	table.insert(NuuUI.Windows, win)
	win.UIScale.Scale = win.CurrentScale * 0.92
	Tween(win.UIScale, { Scale = win.CurrentScale }, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out))
	return win
end

function NuuUI:Destroy()
	for _, w in ipairs(table.clone(self.Windows)) do w:Destroy() end
	for _, n in ipairs(table.clone(activeNotifs)) do n.Dismiss() end
	if notifGui then notifGui:Destroy() notifGui = nil end
	if keybindConn then keybindConn:Disconnect() keybindConn = nil end
	RefreshBindings(false)
end

--==================================================================--
-- 9. DEMOSTRACIÓN INTEGRADA
--==================================================================--
local Window1 = NuuUI:CreateWindow({
	Title = "Nuu7 Hub",
	Subtitle = "Premium Interface",
	Size = UDim2.fromOffset(650, 450),
	Theme = "Dark",
})

local Home = Window1:CreateTab({ Name = "Inicio", Icon = "home" })
local Visual = Window1:CreateTab({ Name = "Visual", Icon = "eye" })
local Config = Window1:CreateTab({ Name = "Configuración", Icon = "settings" })

-- Inicio
Home:CreateSection("Bienvenida")
Home:CreateParagraph({
	Title = "NuuUI v1.0",
	Content = "Biblioteca de interfaz premium en un solo LocalScript. Prueba los controles: cada uno actualiza la etiqueta de estado o lanza una notificación.",
})
local statusLabel = Home:CreateLabel("Estado: listo")

Home:CreateSection("Acciones")
local pressCount = 0
Home:CreateButton({
	Name = "Ejecutar",
	Description = "Cuenta las pulsaciones y muestra una notificación",
	Callback = function()
		pressCount += 1
		statusLabel:Set("Estado: botón pulsado " .. pressCount .. " vez/veces")
		NuuUI:Notify({ Title = "NuuUI", Content = "Acción ejecutada (" .. pressCount .. ")", Duration = 3, Type = "Success" })
	end,
})
local notifType = "Info"
Home:CreateDropdown({
	Name = "Tipo de notificación",
	Options = { "Info", "Success", "Warning", "Error" },
	Default = "Info",
	Callback = function(value) notifType = value end,
})
Home:CreateButton({
	Name = "Enviar notificación",
	Description = "Usa el tipo elegido arriba",
	Callback = function()
		NuuUI:Notify({ Title = "Notificación " .. notifType, Content = "Mensaje de ejemplo de tipo " .. notifType, Duration = 3, Type = notifType })
	end,
})
Home:CreateDivider()
Home:CreateInput({
	Name = "Nombre",
	Placeholder = "Escribe aquí...",
	Default = "",
	Callback = function(value)
		statusLabel:Set(value ~= "" and ("Estado: hola, " .. value) or "Estado: nombre vacío")
	end,
})
Home:CreateKeybind({
	Name = "Mostrar / ocultar ventana",
	Description = "Pulsa el botón y luego una tecla. En móvil usa el botón N flotante",
	Default = Enum.KeyCode.RightShift,
	Callback = function() Window1:Toggle() end,
})

-- Visual
Visual:CreateSection("Apariencia")
local accents = {
	Violeta = Color3.fromRGB(170, 145, 255), Azul = Color3.fromRGB(100, 170, 255),
	Verde = Color3.fromRGB(80, 205, 150), Rosa = Color3.fromRGB(255, 130, 190),
	Naranja = Color3.fromRGB(255, 165, 90),
}
Visual:CreateDropdown({
	Name = "Color de acento",
	Options = { "Violeta", "Azul", "Verde", "Rosa", "Naranja" },
	Default = "Violeta",
	Callback = function(value)
		NuuUI:SetTheme({ Accent = accents[value] })
		NuuUI:Notify({ Title = "Tema", Content = "Acento: " .. value, Duration = 2, Type = "Info" })
	end,
})
Visual:CreateDropdown({
	Name = "Tema",
	Options = { "Dark", "Light" },
	Default = "Dark",
	Callback = function(value) NuuUI:SetTheme(value) end,
})
Visual:CreateSlider({
	Name = "Escala de interfaz",
	Min = 70, Max = 130, Default = 100, Step = 5, Suffix = "%",
	Callback = function(value) Window1:SetScale(value / 100) end,
})
Visual:CreateSection("Controles de ejemplo")
local sliderLabel = Visual:CreateLabel("Velocidad: 16")
Visual:CreateSlider({
	Name = "Velocidad",
	Min = 1, Max = 100, Default = 16, Step = 1,
	Callback = function(value) sliderLabel:Set("Velocidad: " .. value) end,
})
local toggleLabel = Visual:CreateLabel("Función: desactivada")
Visual:CreateToggle({
	Name = "Activar función",
	Description = "Cambia el estado de la etiqueta",
	Default = false,
	Callback = function(value) toggleLabel:Set("Función: " .. (value and "activada" or "desactivada")) end,
})

-- Configuración
Config:CreateSearch({ Placeholder = "Buscar ajustes..." })
Config:CreateSection("Ventana")
Config:CreateButton({
	Name = "Minimizar",
	Description = "Reduce la ventana a la barra superior (restaura con el mismo botón)",
	Callback = function() Window1:Minimize() end,
})
Config:CreateButton({
	Name = "Ocultar ventana",
	Description = "Usa el botón N flotante o el atajo para volver",
	Callback = function() Window1:Hide() end,
})
Config:CreateButton({
	Name = "Cerrar y destruir",
	Description = "Elimina la interfaz y libera conexiones",
	Callback = function() Window1:Close() end,
})
Config:CreateSection("Pestañas dinámicas")
local extraCount = 0
Config:CreateButton({
	Name = "Crear pestaña nueva",
	Description = "Añade una pestaña en tiempo de ejecución",
	Callback = function()
		extraCount += 1
		local t = Window1:CreateTab({ Name = "Extra " .. extraCount })
		t:CreateSection("Pestaña dinámica")
		t:CreateLabel("Esta pestaña se creó mientras el script se ejecutaba.")
		t:CreateButton({
			Name = "Eliminar esta pestaña",
			Callback = function() t:Destroy() end,
		})
		NuuUI:Notify({ Title = "NuuUI", Content = "Pestaña 'Extra " .. extraCount .. "' creada", Duration = 2, Type = "Success" })
	end,
})
Config:CreateSection("Acerca de")
Config:CreateParagraph({
	Title = "Búsqueda",
	Content = "Escribe arriba para filtrar los componentes de esta pestaña por nombre o descripción, sin importar mayúsculas.",
})

NuuUI:Notify({ Title = "NuuUI v1.0", Content = "Interfaz cargada correctamente", Duration = 3, Type = "Success" })
