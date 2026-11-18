-- The addon's own window: the macros to copy and what each button does, plus the debug
-- report, instead of a wall of chat lines. Chat keeps short confirmations and errors, so
-- anything that goes wrong still says so when the window is closed.
--
-- Esc closes it, like any pane the client knows about, and the logo fronts it.

local ADDON, ns = ...

local BestBite = ns.BestBite
local API = ns.API

local Window = { page = "main" }
ns.Window = Window

local LOGO = "Interface\\AddOns\\BestBite\\Portrait.png"
local WIDTH, HEIGHT = 430, 430
local CONTENT = WIDTH - 40
local GREY = 0.75

local function Label(parent, text, font)
	local line = parent:CreateFontString(nil, "ARTWORK")
	line:SetFontObject(font or "GameFontHighlight")
	line:SetJustifyH("LEFT")
	line:SetWidth(CONTENT)
	line:SetText(text)
	return line
end

local function Quiet(line)
	line:SetTextColor(GREY, GREY, GREY)
	return line
end

-- A line that can be selected and copied out with Ctrl+C, which is how a macro gets from
-- this window into the macro window.
local function MacroBox(parent, text)
	local box = CreateFrame("EditBox", nil, parent)
	box:SetAutoFocus(false)
	box:SetFontObject("ChatFontNormal")
	box:SetTextInsets(6, 6, 0, 0)
	box:SetText(text)
	box:SetCursorPosition(0)

	local plate = box:CreateTexture(nil, "BACKGROUND")
	plate:SetAllPoints()
	plate:SetColorTexture(0, 0, 0, 0.55)

	box:SetScript("OnEditFocusLost", function(self) self:ClearFocus() end)
	box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
	return box
end

local function Textured(region)
	return type(region) == "table" and region.SetTexture ~= nil and region or nil
end

-- The logo as the frame's portrait. This client's portrait frame names its own method for
-- taking a raw texture; the newer call and the plain texture regions are the fallbacks, so
-- whichever the client has is used.
local function SetPortrait(frame)
	if frame.SetPortraitTextureRaw then
		local ok = pcall(frame.SetPortraitTextureRaw, frame, LOGO)
		if ok then return end
	end
	if frame.SetPortraitToAsset then
		local ok = pcall(frame.SetPortraitToAsset, frame, LOGO)
		if ok then return end
	end

	local direct = Textured(frame.Portrait) or Textured(frame.PortraitFrame)
	if direct then
		direct:SetTexture(LOGO)
		return
	end
	local container = frame.PortraitContainer
	if type(container) == "table" then
		local portrait = Textured(container.portrait) or Textured(container.Portrait)
		if portrait then portrait:SetTexture(LOGO) end
	end
end

-- A setting, drawn as a switch: a ticked box with its name and the whole row clickable.
-- The tick is set from the saved setting whenever the window is shown, so a command typed
-- in chat and a click here cannot disagree.
local function Switch(parent, text, press)
	local check = CreateFrame("Button", nil, parent)
	check:SetSize(180, 22)

	local plate = check:CreateTexture(nil, "BACKGROUND")
	plate:SetSize(18, 18)
	plate:SetPoint("LEFT")
	plate:SetColorTexture(0, 0, 0, 0.6)
	check.plate = plate

	local tick = check:CreateTexture(nil, "ARTWORK")
	tick:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
	tick:SetSize(20, 20)
	tick:SetPoint("CENTER", plate, "CENTER")
	tick:Hide()
	check.tick = tick

	local label = check:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	label:SetPoint("LEFT", plate, "RIGHT", 8, 0)
	label:SetText(text)
	check.label = label

	check:SetScript("OnClick", function() press() end)

	function check:SetState(on)
		self.on = on and true or false
		if self.on then
			self.tick:Show()
		else
			self.tick:Hide()
		end
	end
	return check
end

local function Build(self)
	local frame = CreateFrame("Frame", "BestBiteFrame", UIParent, "PortraitFrameTemplate")
	frame:SetSize(WIDTH, HEIGHT)
	frame:SetPoint("CENTER")
	frame:SetMovable(true)
	frame:SetClampedToScreen(true)
	frame:SetFrameStrata("DIALOG")
	frame:EnableMouse(true)
	if frame.SetTitle then frame:SetTitle("BestBite") end
	SetPortrait(frame)

	-- The template's top edge is what drags the window, between its portrait and the close
	-- button it draws for itself.
	local dragBar = CreateFrame("Frame", nil, frame)
	dragBar:SetPoint("TOPLEFT", frame, "TOPLEFT", 55, 0)
	dragBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -30, 0)
	dragBar:SetHeight(30)
	dragBar:EnableMouse(true)
	dragBar:SetScript("OnMouseDown", function(_, button)
		if button == "LeftButton" then frame:StartMoving() end
	end)
	dragBar:SetScript("OnMouseUp", function() frame:StopMovingOrSizing() end)
	-- The mouse-up never arrives if the window hides mid-drag, which would leave it
	-- following the cursor for good.
	frame:HookScript("OnHide", function() frame:StopMovingOrSizing() end)

	local main = CreateFrame("Frame", nil, frame)
	-- Below the portrait, which hangs past the title bar, so the first line is not covered.
	main:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -62)
	main:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -20, 20)
	self.main = main

	local intro = Label(main, "Your best food and water, on two buttons you can drag anywhere.")
	intro:SetPoint("TOPLEFT")

	local sub = Quiet(Label(main, "Click a button to eat or drink, or copy a macro below into your own. The game never lets an addon use an item, so the click always comes from you.", "GameFontHighlightSmall"))
	sub:SetPoint("TOPLEFT", intro, "BOTTOMLEFT", 0, -8)

	local foodLabel = Label(main, "Eat", "GameFontNormal")
	foodLabel:SetWidth(50)
	foodLabel:SetPoint("TOPLEFT", sub, "BOTTOMLEFT", 0, -18)
	local foodBox = MacroBox(main, "/click BestBiteFood")
	foodBox:SetSize(CONTENT - 62, 22)
	foodBox:SetPoint("LEFT", foodLabel, "RIGHT", 8, 0)

	local waterLabel = Label(main, "Drink", "GameFontNormal")
	waterLabel:SetWidth(50)
	waterLabel:SetPoint("TOPLEFT", foodLabel, "BOTTOMLEFT", 0, -28)
	local waterBox = MacroBox(main, "/click BestBiteWater")
	waterBox:SetSize(CONTENT - 62, 22)
	waterBox:SetPoint("LEFT", waterLabel, "RIGHT", 8, 0)
	self.macroFood, self.macroWater = foodBox, waterBox

	local hint = Quiet(Label(main, "Both at once: put the two lines in one macro.", "GameFontHighlightSmall"))
	hint:SetPoint("TOPLEFT", waterLabel, "BOTTOMLEFT", 0, -16)

	-- The settings are switches, so their state is visible at a glance; the rest are
	-- buttons that do one thing and are done.
	local buttons = {}
	local function Command(name, text, width)
		local button = CreateFrame("Button", nil, main, "UIPanelButtonTemplate")
		button:SetSize(width or 130, 22)
		button:SetText(text)
		button:SetScript("OnClick", function() Window:Run(name) end)
		buttons[name] = button
		return button
	end

	local switches = {}
	switches.icons = Switch(main, "Action bar icons", function() Window:Run("icons") end)
	switches.icons:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 0, -18)
	switches.macroicon = Switch(main, "Macro icons", function() Window:Run("macroicon") end)
	switches.macroicon:SetPoint("TOPLEFT", switches.icons, "TOPLEFT", 190, 0)
	self.switches = switches

	-- Restocking at vendors: a switch, how much of each to keep, and one press that buys
	-- now rather than waiting for a merchant to be opened.
	switches.vendor = Switch(main, "Restock from vendors", function()
		local vendor = ns.Vendor
		if not vendor then return end
		local db = vendor:Db()
		db.on = not db.on
		Window:Refresh()
	end)
	switches.vendor:SetPoint("TOPLEFT", switches.icons, "BOTTOMLEFT", 0, -16)

	local target = Quiet(Label(main, "Keep", "GameFontHighlightSmall"))
	target:SetWidth(34)
	target:SetPoint("TOPLEFT", switches.vendor, "BOTTOMLEFT", 0, -10)
	self.targetLabel = Label(main, "5 of each", "GameFontHighlight")
	self.targetLabel:SetWidth(120)
	self.targetLabel:SetPoint("LEFT", target, "RIGHT", 6, 0)

	local function StepTarget(delta)
		return function()
			local vendor = ns.Vendor
			if not vendor then return end
			local db = vendor:Db()
			local nextTarget = (db.target or vendor.TARGET_MIN) + delta
			db.target = math.max(vendor.TARGET_MIN, math.min(vendor.TARGET_MAX, nextTarget))
			Window:Refresh()
		end
	end
	buttons.vendorLess = Command("vendorLess", "minus", 26)
	buttons.vendorLess:SetPoint("LEFT", self.targetLabel, "RIGHT", 6, 0)
	buttons.vendorLess:SetScript("OnClick", function() StepTarget(-(ns.Vendor and ns.Vendor.TARGET_STEP or 5))() end)
	buttons.vendorMore = Command("vendorMore", "plus", 26)
	buttons.vendorMore:SetPoint("LEFT", buttons.vendorLess, "RIGHT", 4, 0)
	buttons.vendorMore:SetScript("OnClick", function() StepTarget(ns.Vendor and ns.Vendor.TARGET_STEP or 5)() end)

	self.vendorStatus = Quiet(Label(main, "", "GameFontHighlightSmall"))
	self.vendorStatus:SetPoint("TOPLEFT", switches.vendor, "BOTTOMLEFT", 0, -34)

	buttons.vendorBuy = Command("vendorBuy", "Buy now", 100)
	buttons.vendorBuy:SetPoint("LEFT", buttons.vendorMore, "RIGHT", 10, 0)
	buttons.vendorBuy:SetScript("OnClick", function()
		if ns.Vendor then ns.Vendor:Restock(true) end
		Window:Refresh()
	end)

	buttons.move = Command("move", "Move buttons")
	buttons.move:SetPoint("TOPLEFT", self.vendorStatus, "BOTTOMLEFT", 0, -10)
	buttons.reset = Command("reset", "Reset learned", 130)
	buttons.reset:SetPoint("LEFT", buttons.move, "RIGHT", 10, 0)
	buttons.debug = Command("debug", "Debug", 120)
	buttons.debug:SetPoint("LEFT", buttons.reset, "RIGHT", 10, 0)
	self.buttons = buttons

	-- The debug report is long, so it lives on its own page in a scroll frame rather than
	-- scrolling past in chat.
	local debugPage = CreateFrame("Frame", nil, frame)
	debugPage:SetAllPoints(main)
	debugPage:Hide()
	self.debug = debugPage

	local heading = Label(debugPage, "What BestBite sees", "GameFontNormal")
	heading:SetPoint("TOPLEFT")

	local scroll = CreateFrame("ScrollFrame", "BestBiteDebugScroll", debugPage, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", heading, "BOTTOMLEFT", 4, -8)
	scroll:SetPoint("BOTTOMRIGHT", debugPage, "BOTTOMRIGHT", -26, 34)

	local child = CreateFrame("Frame", nil, scroll)
	child:SetSize(CONTENT - 40, 1)
	scroll:SetScrollChild(child)

	self.text = child:CreateFontString(nil, "ARTWORK")
	self.text:SetFontObject("ChatFontNormal")
	self.text:SetJustifyH("LEFT")
	self.text:SetWidth(CONTENT - 44)
	self.text:SetPoint("TOPLEFT")

	local back = CreateFrame("Button", nil, debugPage, "UIPanelButtonTemplate")
	back:SetSize(100, 22)
	back:SetText("Back")
	back:SetPoint("BOTTOMLEFT")
	back:SetScript("OnClick", function() Window:ShowPage("main") end)
	self.backButton = back

	UISpecialFrames = UISpecialFrames or {}
	local listed = false
	for index = 1, #UISpecialFrames do
		if UISpecialFrames[index] == "BestBiteFrame" then listed = true end
	end
	if not listed then table.insert(UISpecialFrames, "BestBiteFrame") end

	frame:Hide()
	self.frame = frame
	return frame
end

-- Built on first use, so a client that refuses the template costs the addon only a
-- message rather than the whole addon failing to load.
function Window:Frame()
	if self.frame then return self.frame end
	local ok, result = pcall(Build, self)
	if not ok then
		self.broken = true
		BestBite:Print("the window could not be built: " .. tostring(result))
		return nil
	end
	return result
end

function Window:ShowPage(page)
	if not self:Frame() then return false end
	page = page == "debug" and "debug" or "main"
	if self.main and self.debug then
		if page == "debug" then
			self.main:Hide()
			self.debug:Show()
		else
			self.debug:Hide()
			self.main:Show()
			self:Refresh()
		end
	end
	self.page = page
	self.frame:Show()
	return true
end

function Window:Open()
	return self:ShowPage("main")
end

-- The report is sized from its own text rather than by measuring the drawn font string: a
-- measurement that answers nothing leaves the scroll child a pixel tall, which shows as an
-- empty page.
local CHARS_PER_ROW = 55
local ROW_HEIGHT = 13

-- One unreadable line must not sink the report. A value the client keeps secret survives
-- being turned into text and survives `..`, but every use of it is refused, so each line is
-- checked before it goes in and anything refused becomes a note.
local function Join(lines)
	local safe = {}
	for index = 1, #lines do
		local line = lines[index]
		safe[index] = API.Showable(line) and line or ("line " .. index .. " could not be read")
	end
	return table.concat(safe, "\n")
end

local function Measure(text)
	local rows = 0
	for line in (text .. "\n"):gmatch("(.-)\n") do
		rows = rows + math.max(1, math.ceil(#line / CHARS_PER_ROW))
	end
	return math.max(rows, 1) * ROW_HEIGHT + 16
end

function Window:Fill(lines)
	self.debugLines = lines
	if not self.text then return end

	local text = Join(lines)
	self.text:SetText(text)

	local height = Measure(text)
	if self.text.SetHeight then self.text:SetHeight(height) end
	local child = self.text:GetParent()
	if child and child.SetHeight then child:SetHeight(math.max(height + 6, 1)) end
end

function Window:ShowDebug()
	if not self:Frame() then return false end
	-- The page turns first, so a report that cannot be built still lands somewhere that
	-- says so rather than leaving the window looking unchanged. Building the report is
	-- inside the guard as well as showing it: it walks the bags and reads tooltips.
	local shown = self:ShowPage("debug")
	local ok, err = pcall(function() self:Fill(BestBite:DebugLines()) end)
	if not ok then
		local why = tostring(err)
		self:Fill({ "The report could not be built:", why })
		BestBite:Print("the debug report could not be built: " .. why)
	end
	return shown
end

function Window:Toggle()
	if not self:Frame() then return false end
	if not self.frame:IsShown() then return self:ShowPage("main") end
	-- From the debug page, /bb goes back a page rather than shutting the window.
	if self.page == "debug" then return self:ShowPage("main") end
	self.frame:Hide()
	return true
end

-- The switches read the saved settings rather than remembering a state of their own, so
-- `/bb icons` typed in chat is reflected the next time the window is shown.
function Window:Refresh()
	local db = BestBite:Db()
	if not self.switches then return end
	if self.switches.icons then self.switches.icons:SetState(db.showIcons ~= false) end
	if self.switches.macroicon then self.switches.macroicon:SetState(db.writeMacroIcons == true) end

	if self.switches.vendor and ns.Vendor then
		local vendor = ns.Vendor
		local settings = vendor:Db()
		self.switches.vendor:SetState(settings.on == true)
		self.targetLabel:SetText(("%d of each"):format(settings.target or vendor.TARGET_MIN))

		local open = GetMerchantNumItems and GetMerchantNumItems() > 0
		if self.buttons and self.buttons.vendorBuy then
			if open then self.buttons.vendorBuy:Enable() else self.buttons.vendorBuy:Disable() end
		end

		if self.vendorStatus then
			local stood, why = vendor:StandDown()
			local text
			if stood then
				text = why .. ", so BestBite stands down."
			elseif open then
				local target = settings.target or vendor.TARGET_MIN
				-- An unknown level counts nothing, rather than counting at level 0.
				local level = UnitLevel("player") or 0
				local food, water = 0, 0
				if level > 0 then
					food, water = vendor:Count("food", level, true), vendor:Count("water", level, true)
				end
				text = ("Food %d/%d, water %d/%d"):format(food, target, water, target)
			else
				text = "No merchant open"
			end
			self.vendorStatus:SetText(text)
		end
	end
end

-- The window's buttons run the same commands the slash line does, so there is one
-- implementation of each.
function Window:Run(command)
	if command == "debug" then
		self:ShowDebug()
		return
	end
	if ns.RunCommand then
		local ok, err = pcall(ns.RunCommand, command)
		if not ok then BestBite:Print("error: " .. tostring(err)) end
	end
	self:Refresh()
end
