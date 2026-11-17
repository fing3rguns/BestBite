-- The game does not let an addon use a bag item: the call is blocked and the player
-- gets "BestBite has been blocked from an action only available to the Blizzard UI".
-- A secure button is allowed to, because the client performs the use itself and the
-- addon only says which item.
--
-- So these are two real buttons, drawn like gems above the action bar and draggable
-- by their right button: click one to eat or drink, or run a macro holding
-- /click BestBiteFood. They follow the bags out of combat, since a secure button's
-- attributes and position are the game's to lock during a fight.

local ADDON, ns = ...

local BestBite = ns.BestBite
local API = ns.API

local Buttons = {}
ns.Buttons = Buttons

local SIZE = 40
local FALLBACK_ICON = "Interface\\Icons\\INV_Misc_Food_16"

local function SavePosition(button)
	local point, _, relativePoint, x, y = button:GetPoint(1)
	local db = BestBite:Db()
	db.buttonPos = db.buttonPos or {}
	db.buttonPos[button.BestBiteKey] = { point, relativePoint, x, y }
end

local function NewButton(name, key, offset)
	local button = CreateFrame("Button", name, UIParent, "SecureActionButtonTemplate")
	button.BestBiteKey = key
	button:SetSize(SIZE, SIZE)
	button:SetFrameStrata("MEDIUM")
	button:SetClampedToScreen(true)
	-- Match the client's own action buttons (AnyUp, LeftButtonDown, RightButtonDown)
	-- minus the right button, which belongs to dragging. /click is native, so
	-- registering both left events is what makes a macro's click reach the button.
	button:RegisterForClicks("LeftButtonUp", "LeftButtonDown")
	button:SetAttribute("type", "item")
	-- A macro's /click arrives as a key press, and the client only acts on one when
	-- told to: left unset it reads the "cast on key press" setting, which is on by
	-- default, and the button then waits for a key down that a /click never sends.
	button:SetAttribute("useOnKeyDown", false)

	-- How the slot ring is meant to sit: the border texture is a frame the icon goes
	-- inside, so it fills the button and the icon is inset within it.
	button.plate = button:CreateTexture(nil, "BACKGROUND")
	button.plate:SetAllPoints()
	button.plate:SetTexture(0, 0, 0, 0.6)

	button.border = button:CreateTexture(nil, "BORDER")
	button.border:SetTexture("Interface\\Buttons\\UI-Quickslot2")
	button.border:SetAllPoints()

	button.icon = button:CreateTexture(nil, "ARTWORK")
	button.icon:SetSize(SIZE - 8, SIZE - 8)
	button.icon:SetPoint("CENTER")
	button.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	button.icon:SetTexture(FALLBACK_ICON)

	local highlight = button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
	if highlight and highlight.SetBlendMode then
		highlight:SetBlendMode("ADD")
		highlight:SetAlpha(0.6)
	end

	-- How many the bags hold, in the corner, the way an action button counts a stack.
	button.count = button:CreateFontString(nil, "OVERLAY")
	button.count:SetFontObject("NumberFontNormal")
	button.count:SetJustifyH("RIGHT")
	button.count:SetPoint("BOTTOMRIGHT", -2, 2)

	button:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		if Buttons.moving then
			GameTooltip:AddLine("Drag to move these buttons")
			GameTooltip:AddLine("/bb move when they are where you want them", 0.7, 0.7, 0.7)
		elseif self.itemID and GameTooltip.SetItemByID then
			pcall(GameTooltip.SetItemByID, GameTooltip, self.itemID)
			GameTooltip:AddLine("Right-drag to move", 0.7, 0.7, 0.7)
		elseif not self.itemID then
			GameTooltip:AddLine(key == "water" and "No water in your bags" or "No food in your bags")
		end
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", function() GameTooltip:Hide() end)

	-- The left button is the item, so it only drags in move mode (/bb move); the
	-- right button always drags. Moving a protected frame is out of combat only.
	button:SetMovable(true)
	button:RegisterForDrag("LeftButton", "RightButton")
	button:SetScript("OnDragStart", function(self, mouseButton)
		if InCombatLockdown and InCombatLockdown() then
			BestBite:Print("the buttons can be moved out of combat.")
			return
		end
		if mouseButton == "RightButton" or Buttons.moving then
			self:StartMoving()
		end
	end)
	button:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		SavePosition(self)
	end)

	local saved = BestBite:Db().buttonPos and BestBite:Db().buttonPos[key]
	if saved then
		button:SetPoint(saved[1], UIParent, saved[2], saved[3], saved[4])
	else
		button:SetPoint("BOTTOM", UIParent, "BOTTOM", offset, 150)
	end
	return button
end

-- Stocked by item rather than by slot, so the click uses the item that was chosen
-- even if the bags are rearranged before the button is pressed.
local function Stock(button, pick)
	button.itemID = pick and pick.itemID or nil
	button:SetAttribute("item", pick and pick.itemID and ("item:" .. pick.itemID) or nil)
	if pick then
		local count = API.CountInBags(pick.itemID)
		button.icon:SetTexture(API.ItemIcon(pick.itemID) or FALLBACK_ICON)
		-- One of a thing reads better bare, as on an action button.
		button.count:SetText(count > 1 and count or "")
		button:Show()
	else
		button.count:SetText("")
		button:Hide()
	end
end

-- The game locks a secure button's attributes and position during a fight: a change
-- made in one waits for it to end.
function Buttons:Update()
	if InCombatLockdown and InCombatLockdown() then
		self.waiting = true
		return
	end
	self.waiting = false
	if self.moving then return end

	local Consume = ns.Consume
	if not Consume then return end
	Stock(self.food, Consume:Find("food"))
	Stock(self.water, Consume:Find("water"))
end

-- Arranging the buttons is its own little mode: while it is on they hold no item,
-- so a click cannot use anything and a left-drag moves them instead.
function Buttons:SetMoving(on)
	if InCombatLockdown and InCombatLockdown() then
		BestBite:Print("the buttons can be moved out of combat.")
		return
	end
	self.moving = on and true or false
	if self.moving then
		self.food:SetAttribute("item", nil)
		self.water:SetAttribute("item", nil)
		BestBite:Print("drag the buttons where you want them, then /bb move again.")
	else
		self:Update()
		BestBite:Print("the buttons are back to eating and drinking.")
	end
end

-- One update in flight at a time: the latest bags are read when it runs.
local scheduled, warned = false, false
function Buttons:Request(delay)
	if scheduled then return end
	scheduled = true
	local function run()
		scheduled = false
		local ok, err = pcall(Buttons.Update, Buttons)
		if not ok and not warned then
			warned = true
			BestBite:Print("could not stock the click buttons: " .. tostring(err))
		end
	end
	if delay and delay > 0 and C_Timer and C_Timer.After then
		C_Timer.After(delay, run)
	else
		run()
	end
end

-- What each button would use right now, for /bb debug.
function Buttons:Stocked()
	return self.food and self.food:GetAttribute("item"), self.water and self.water:GetAttribute("item")
end

Buttons.food = NewButton("BestBiteFood", "food", -60)
Buttons.water = NewButton("BestBiteWater", "water", -108)

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("BAG_UPDATE_DELAYED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(_, event)
	if event == "BAG_UPDATE_DELAYED" then
		Buttons:Request(1)
	else
		Buttons:Request(0.5)
	end
end)
