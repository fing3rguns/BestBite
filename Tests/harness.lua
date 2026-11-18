-- Runs BestBite against a fake Forever client. The important part of this fake is
-- that C_Container.UseContainerItem raises, exactly like the real client blocks it:
-- if the addon ever goes back to using a bag item itself, every test here fails.
--
--   python Tests/run.py
--
-- Needs lupa: pip install lupa. Nothing here is loaded by the game; the file is not
-- in the .toc.

-- Where the addon's own files are: run.py passes it in, and running this file
-- directly works it out from its own path, so a checkout anywhere still works.
local ADDON_DIR = (function()
	if BESTBITE_DIR and BESTBITE_DIR ~= "" then
		return (BESTBITE_DIR:gsub("[/\\]$", "")) .. "/"
	end
	local path = (debug.getinfo(1, "S").source or ""):match("^@(.*)$")
		or (arg and arg[0])
		or ""
	local tests = path:match("^(.*)[/\\][^/\\]+$")
	local addon = tests and tests:match("^(.*)[/\\][^/\\]+$")
	return addon and (addon:gsub("[/\\]$", "") .. "/") or "./"
end)()

---------------------------------------------------------------------------- items
local ITEMS = {}
local function Item(id, t)
	t.id = id
	ITEMS[id] = t
end

Item(117, { name = "Tough Jerky", class = 0, sub = 5, ilvl = 5, req = 1, lines = {
	"Tough Jerky", "Use: Restores 61 health over 15 sec. Must remain seated while eating." } })
Item(422, { name = "Dwarven Mild", class = 0, sub = 5, ilvl = 25, req = 15, lines = {
	"Dwarven Mild", "Use: Restores 243 health over 21 sec. Must remain seated while eating." } })
Item(159, { name = "Refreshing Spring Water", class = 0, sub = 5, ilvl = 5, req = 1, lines = {
	"Refreshing Spring Water", "Use: Restores 151 mana over 18 sec. Must remain seated while drinking." } })
Item(8766, { name = "Morning Glory Dew", class = 0, sub = 5, ilvl = 55, req = 45, lines = {
	"Morning Glory Dew", "Use: Restores 835 mana over 24 sec. Must remain seated while drinking." } })
Item(118, { name = "Minor Healing Potion", class = 0, sub = 1, ilvl = 5, req = 1, lines = {
	"Minor Healing Potion", "Use: Restores 70 health." } })
Item(9999, { name = "Raid Food", class = 0, sub = 5, ilvl = 60, req = 60, lines = {
	"Raid Food", "Use: Restores 2000 health over 20 sec. Must remain seated while eating." } })
Item(2001, { name = "Buff Rations", class = 0, sub = 5, ilvl = 20, req = 1, lines = {
	"Buff Rations", "Use: Restores 61 health over 15 sec.",
	"Well Fed: Stamina increased by 12." } })
Item(2002, { name = "Feast Plate", class = 0, sub = 5, ilvl = 20, req = 1, lines = {
	"Feast Plate", "Use: Restores 61 health over 15 sec.",
	"Well Fed: Stamina increased by 8 and Spirit increased by 8." } })
Item(2003, { name = "Plain Loaf", class = 0, sub = 5, ilvl = 20, req = 1, lines = {
	"Plain Loaf", "Use: Restores 500 health over 20 sec. Must remain seated while eating." } })
Item(2004, { name = "Hearty Stew", class = 0, sub = 5, ilvl = 20, req = 1, lines = {
	"Hearty Stew", "Use: Restores 100 health over 15 sec.",
	"Use: Increases Stamina by 12 for 15 min." } })
Item(2010, { name = "Banquet Portions", class = 0, sub = 5, ilvl = 55, req = 55, lines = {
	"Banquet Portions", "Use: Restores 400 health over 20 sec.",
	"Well Fed: Stamina increased by 14." } })
Item(8770, { name = "Sparkling Spring Water", class = 0, sub = 5, ilvl = 55, req = 55, lines = {
	"Sparkling Spring Water", "Use: Restores 1344 mana over 24 sec. Must remain seated while drinking." } })

---------------------------------------------------------------------------- state
local BAGS, COOLDOWNS, MESSAGES = {}, {}, {}
local MACROS, MACTION, MACTION_TEXTURE = {}, {}, {}
local PLAYER = { level = 60, health = 500, healthMax = 1000, mana = 500, manaMax = 1000 }
local COMBAT = false

---------------------------------------------------------------------------- merchant
-- Two items the vendor tests need: one inside a level 40 band, one with no requirement.
Item(9997, { name = "Trail Stew", class = 0, sub = 5, ilvl = 40, req = 35, lines = {
	"Trail Stew", "Use: Restores 400 health over 20 sec. Must remain seated while eating." } })
Item(5350, { name = "Conjured Bread", class = 0, sub = 5, ilvl = 5, req = 0, lines = {
	"Conjured Bread", "Use: Restores 61 health over 15 sec. Must remain seated while eating." } })

MERCHANT = { stock = {}, money = 100000, bought = {} }
local function Stock(index, itemID, price, stack, available)
	MERCHANT.stock[index] = { itemID = itemID, price = price, stack = stack or 5, available = available or 5 }
end

GetMerchantNumItems = function() return #MERCHANT.stock end
GetMerchantItemID = function(index)
	local entry = MERCHANT.stock[index]
	return entry and entry.itemID or nil
end
GetMerchantItemLink = function(index)
	local entry = MERCHANT.stock[index]
	return entry and ("|Hitem:" .. entry.itemID .. "|h") or nil
end
GetMerchantItemMaxStack = function(index)
	local entry = MERCHANT.stock[index]
	return entry and entry.stack or 1
end
C_MerchantFrame = {
	GetItemInfo = function(index)
		local entry = MERCHANT.stock[index]
		if not entry then return nil end
		return { itemID = entry.itemID, price = entry.price, stackCount = entry.stack,
			numAvailable = entry.available, isPurchasable = true }
	end,
}
GetMoney = function() return MERCHANT.money end
BuyMerchantItem = function(index, quantity)
	local entry = MERCHANT.stock[index]
	if not entry or quantity < 1 then return false end
	local cost = entry.price * quantity
	if cost > MERCHANT.money then return false end
	MERCHANT.money = MERCHANT.money - cost
	entry.available = math.max(0, entry.available - quantity)
	MERCHANT.bought[#MERCHANT.bought + 1] = { itemID = entry.itemID, quantity = quantity }
	for slot = 1, 16 do
		BAGS[0] = BAGS[0] or {}
		local held = BAGS[0][slot]
		if held and held.itemID == entry.itemID then
			held.count = held.count + quantity
			return true
		end
	end
	for slot = 1, 16 do
		BAGS[0] = BAGS[0] or {}
		if not BAGS[0][slot] then
			BAGS[0][slot] = { itemID = entry.itemID, count = quantity }
			return true
		end
	end
	return false
end

--------------------------------------------------------------------------- client
NUM_BAG_SLOTS, NUM_TOTAL_EQUIPPED_BAG_SLOTS = 4, 4
Enum = { ItemClass = { Consumable = 0 }, ItemConsumableSubclass = { FoodDrink = 5 } }
WorldFrame, SlashCmdList = {}, {}
MAX_ACCOUNT_MACROS, MAX_CHARACTER_MACROS = 4, 2
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
unpack = unpack or table.unpack

DEFAULT_CHAT_FRAME = { AddMessage = function(_, message) MESSAGES[#MESSAGES + 1] = message end }

UnitLevel = function() return PLAYER.level end
UnitHealth = function() return PLAYER.health end
UnitHealthMax = function() return PLAYER.healthMax end
UnitPower = function() return PLAYER.mana end
UnitPowerMax = function() return PLAYER.manaMax end
GetTime = function() return 1000 end
InCombatLockdown = function() return COMBAT end
C_Timer = { After = function(_, run) TIMERS = (TIMERS or 0) + 1; run() end }
hooksecurefunc = function() end

C_Container = {
	GetContainerNumSlots = function(bag) return BAGS[bag] and 20 or 0 end,
	GetContainerItemInfo = function(bag, slot)
		local held = BAGS[bag] and BAGS[bag][slot]
		if not held then return nil end
		return { itemID = held.itemID, stackCount = held.count or 1, isLocked = held.locked }
	end,
	-- The real client blocks this; so does the fake.
	UseContainerItem = function()
		error("the game blocks an addon from using an item", 0)
	end,
	GetContainerItemCooldown = function(bag, slot)
		if slot == nil then
			error("bad argument #2 to 'GetContainerItemCooldown' (Usage: local startTime, duration, enable = C_Container.GetContainerItemCooldown(containerIndex, slotIndex))", 2)
		end
		local held = BAGS[bag] and BAGS[bag][slot]
		local cool = held and COOLDOWNS[held.itemID]
		if not cool then return 0, 0 end
		return cool[1], cool[2]
	end,
}

C_UnitAuras = {
	GetAuraDataByIndex = function(_, index, filter)
		local aura = AURAS[index]
		if not aura then return nil end
		return {
			name = aura.name,
			icon = aura.icon,
			duration = aura.duration,
			expirationTime = aura.expirationTime,
			spellId = aura.spellId,
		}
	end,
}

C_Item = {
	GetItemInfo = function(itemID)
		local it = ITEMS[itemID]
		if not it then return nil end
		return it.name, "|Hitem:" .. itemID .. "|h", 1, it.ilvl, it.req, "Consumable", "Food & Drink", 20, "", 0, 0
	end,
	GetItemInfoInstant = function(itemID)
		local it = ITEMS[itemID]
		if not it then return nil end
		return itemID, "Consumable", "Food & Drink", "", 0, it.class, it.sub
	end,
	IsUsableItem = function(itemID) return ITEMS[itemID] ~= nil end,
	GetItemIconByID = function(itemID) return "Interface\\Icons\\Item" .. itemID end,
}

local regions = {}
local TOOLTIP = {
	SetOwner = function() end,
	ClearLines = function() regions = {} end,
	GetRegions = function() return unpack(regions) end,
	RegisterEvent = function() end,
	SetScript = function() end,
	SetBagItem = function(_, bag, slot)
		local held = BAGS[bag] and BAGS[bag][slot]
		if not held then return end
		for _, line in ipairs(ITEMS[held.itemID].lines or {}) do
			regions[#regions + 1] = {
				GetObjectType = function() return "FontString" end,
				GetText = function() return line end,
			}
		end
	end,
	SetMerchantItem = function(_, index)
		local entry = MERCHANT and MERCHANT.stock and MERCHANT.stock[index]
		if not entry then return end
		for _, line in ipairs(ITEMS[entry.itemID].lines or {}) do
			regions[#regions + 1] = {
				GetObjectType = function() return "FontString" end,
				GetText = function() return line end,
			}
		end
	end,
}

-- A frame of any other kind: the window builds itself out of these, so every method a
-- frame might have answers instead of the harness having to list them all.
local function Region(parent)
	local region = { parent = parent }
	region.SetPoint = function() end
	region.SetAllPoints = function() end
	region.SetSize = function(self, width, height) self.width, self.height = width, height end
	region.SetWidth = function(self, width) self.width = width end
	region.SetHeight = function(self, height) self.height = height end
	region.SetColorTexture = function() end
	region.SetTexture = function(self, texture) self.texture = texture end
	region.SetFontObject = function() end
	region.SetJustifyH = function() end
	region.SetTextColor = function() end
	region.SetText = function(self, text) self.text = tostring(text or "") end
	region.GetText = function(self) return self.text end
	region.GetParent = function(self) return self.parent end
	region.GetStringHeight = function() return 0 end
	region.GetHeight = function(self) return self.height or 0 end
	region.Show = function(self) self.shown = true end
	region.Hide = function(self) self.shown = false end
	region.IsShown = function(self) return self.shown and true or false end
	return region
end

local function InterfaceFrame(name)
	local frame = Region(nil)
	frame.shown = false
	frame.scripts = {}
	function frame:SetScript(event, fn) self.scripts[event] = fn end
	function frame:Show() self.shown = true end
	function frame:Hide() self.shown = false end
	function frame:SetShown(flag) self.shown = flag and true or false end
	function frame:IsShown() return self.shown end
	function frame:CreateTexture() return Region(self) end
	function frame:CreateFontString() return Region(self) end
	function frame:SetScrollChild(child) self.scrollChild = child end
	setmetatable(frame, { __index = function() return function() end end })
	if name then _G[name] = frame end
	return frame
end

CreateFrame = function(kind, name, _, template)
	if template == "SecureActionButtonTemplate" then
		local button = { attributes = {}, shown = true, key = name }
		function button:SetAttribute(key, value) self.attributes[key] = value end
		function button:GetAttribute(key) return self.attributes[key] end
		button.SetSize = function(self, size) self.size = size end
		button.SetFrameStrata = function() end
		button.SetClampedToScreen = function() end
		button.SetMovable = function() end
		button.SetNormalTexture = function(self, path) self.normalTexture = path end
		button.SetPushedTexture = function(self, path) self.pushedTexture = path end
		button.SetHighlightTexture = function(self, path)
			self.highlightTexture = path
			return { SetBlendMode = function() end, SetAlpha = function() end }
		end
		button.RegisterForClicks = function(self, ...) self.clicks = { ... } end
		button.RegisterForDrag = function() end
		button.EnableMouse = function() end
		button.SetPoint = function() end
		button.GetPoint = function() return "BOTTOM", nil, "BOTTOM", 0, 100 end
		button.StartMoving = function() MOVE_STARTED = (MOVE_STARTED or 0) + 1 end
		button.StopMovingOrSizing = function() end
		button.Show = function(self) self.shown = true end
		button.Hide = function(self) self.shown = false end
		button.IsShown = function(self) return self.shown end
		button.SetScript = function(self, event, fn) self[event] = fn end
		button.CreateTexture = function()
			local texture = {}
			function texture:SetAllPoints() end
			function texture:SetPoint() end
			function texture:SetSize(w, h) self.width = w end
			function texture:SetTexCoord() end
			function texture:SetBlendMode() end
			function texture:SetAlpha(alpha) self.alpha = alpha end
			function texture:SetDesaturated(flag) self.desaturated = flag end
			function texture:SetTexture(path) self.texture = path end
			return texture
		end
		button.CreateFontString = function()
			local text = { value = "" }
			text.SetFontObject = function() end
			text.SetJustifyH = function() end
			text.SetPoint = function() end
			text.SetText = function(self, value) self.value = tostring(value or "") end
			text.GetText = function(self) return self.value end
			return text
		end
		button.RegisterEvent = function() end
		_G[name] = button
		return button
	end
	if kind == "GameTooltip" or template == "GameTooltipTemplate" then return TOOLTIP end
	return InterfaceFrame(name)
end

TOOLTIP_LINES = {}
GameTooltip = {
	SetOwner = function() TOOLTIP_LINES = {} end,
	AddLine = function(_, text) TOOLTIP_LINES[#TOOLTIP_LINES + 1] = text end,
	Show = function() end,
	Hide = function() end,
	SetItemByID = function() end,
}

-- Action bar buttons, and the macros behind them.
local QUESTION_MARK = "Interface\\Icons\\INV_Misc_QuestionMark"
for index = 1, 12 do
	local button = { action = index }
	button.icon = { SetTexture = function(_, texture) MACTION_TEXTURE[button.action] = texture end }
	_G["ActionButton" .. index] = button
end

GetActionInfo = function(action)
	local entry = MACTION[action]
	if not entry then return nil end
	return entry[1], entry[2]
end
GetMacroInfo = function(index)
	local macro = MACROS[index]
	if not macro then return nil end
	return macro.name, macro.icon or QUESTION_MARK, macro.body
end
GetMacroIndexByName = function(name)
	for index, macro in pairs(MACROS) do
		if macro.name == name then return index end
	end
	return nil
end
EditMacro = function(index, name, icon, body)
	local macro = MACROS[index]
	if not macro then return false end
	macro.icon, macro.body = icon, body
	return true
end

---------------------------------------------------------------------------- addon
local ns = {}
local function LoadAddon(file)
	assert(loadfile(ADDON_DIR .. file))("BestBite", ns)
end
LoadAddon("Core.lua")
LoadAddon("Detect.lua")
LoadAddon("Buffs.lua")
LoadAddon("Consume.lua")
LoadAddon("Vendor.lua")
LoadAddon("Buttons.lua")
LoadAddon("Icons.lua")
LoadAddon("Window.lua")

local slash = SlashCmdList.BESTBITE

---------------------------------------------------------------------------- tests
local failures, total = 0, 0
local function Check(name, condition, detail)
	total = total + 1
	if condition then
		print("ok   " .. name)
	else
		failures = failures + 1
		print("FAIL " .. name .. (detail and (" -- " .. detail) or ""))
	end
end

local function Reset()
	BAGS, COOLDOWNS, MESSAGES = {}, {}, {}
	TOOLTIP_LINES = {}
	AURAS = {}
	TIMERS = 0
	MACROS, MACTION, MACTION_TEXTURE = {}, {}, {}
	PLAYER = { level = 60, health = 500, healthMax = 1000, mana = 500, manaMax = 1000 }
	COMBAT = false
	BestBiteDB, ns.db = nil, nil
	MERCHANT = { stock = {}, money = 100000, bought = {} }
	ns.Vendor.fallbackDone = false
end

local function Put(bagID, slot, itemID, count, locked)
	BAGS[bagID] = BAGS[bagID] or {}
	BAGS[bagID][slot] = { itemID = itemID, count = count or 1, locked = locked }
end

local function Said(text)
	for _, message in ipairs(MESSAGES) do
		if message:find(text, 1, true) then return true end
	end
	return false
end

-- /bb debug writes its report into the window now, not the chat frame.
local function Debugged(text)
	ns.Window:ShowDebug()
	for _, line in ipairs(ns.Window.debugLines or {}) do
		if line:find(text, 1, true) then return true end
	end
	return false
end

local function Food() return ns.Buttons.food:GetAttribute("item") end
local function Water() return ns.Buttons.water:GetAttribute("item") end

-- The buttons the client clicks carry the best item of each kind.
Reset()
Put(0, 1, 117); Put(0, 2, 422); Put(0, 3, 159); Put(0, 4, 8766)
ns.Buttons:Update()
Check("stock: the best food is on the food button", Food() == "item:422", Food())
Check("stock: the best water is on the water button", Water() == "item:8766", Water())
Check("stock: the button is shown with its item", ns.Buttons.food.shown and ns.Buttons.food.itemID == 422,
	tostring(ns.Buttons.food.itemID))
Check("stock: a stocked button is drawn at full strength",
	ns.Buttons.food.icon.desaturated == false and ns.Buttons.food.icon.alpha == 1,
	tostring(ns.Buttons.food.icon.desaturated) .. " " .. tostring(ns.Buttons.food.icon.alpha))

-- The count in the button's corner is how many the bags hold, over every stack.
Reset()
Put(0, 1, 422, 3); Put(0, 2, 422, 2); Put(1, 1, 159, 1)
ns.Buttons:Update()
Check("count: the food button counts every stack", ns.Buttons.food.count:GetText() == "5", ns.Buttons.food.count:GetText())
Check("count: a single item shows no number", ns.Buttons.water.count:GetText() == "", ns.Buttons.water.count:GetText())

BAGS = {}
ns.Buttons:Update()
Check("count: an emptied button shows no number", ns.Buttons.food.count:GetText() == "", ns.Buttons.food.count:GetText())

-- Well Fed food outranks plain food, whatever the plain food restores.
Reset()
Put(0, 1, 2003); Put(0, 2, 2001)
ns.Buttons:Update()
Check("buffs: buff food beats plain food that restores more", Food() == "item:2001", Food())
Check("buffs: the points are read from the Well Fed line", ns.Buttons.food.itemID == 2001
	and ns.Consume:Find("food").points == 12, tostring(ns.Consume:Find("food").points))

-- More points wins; on equal points the larger restore does.
Reset()
Put(0, 1, 2001); Put(0, 2, 2002)
ns.Buttons:Update()
Check("buffs: more points win", Food() == "item:2002", Food())

Reset()
Put(0, 1, 2001); Put(0, 2, 2004)
ns.Buttons:Update()
Check("buffs: equal points fall back to the restore", Food() == "item:2004", Food())

-- Buff points survive in what was learned, for a tooltip that stops parsing.
Reset()
Put(0, 1, 2001); Put(0, 2, 2003)
ns.Buttons:Update()
Check("buffs: the learned entry keeps the points", ns.db.learned[2001] and ns.db.learned[2001].buffs ~= nil)
ITEMS[2001].lines = {}
BestBiteDB = { learned = { [2001] = { kind = "food", amount = 61, buffs = { ["stamina"] = 12 } } } }
ns.db = nil
Check("buffs: a remembered buff still counts", (function()
	local best = ns.Consume:Find("food")
	return best ~= nil and best.itemID == 2001
end)())
ITEMS[2001].lines = {
	"Buff Rations", "Use: Restores 61 health over 15 sec.", "Well Fed: Stamina increased by 12." }

-- A food buff changes the ranking: while it is banked the buff food is not worth eating,
-- and in its last half minute it is again. The buff is a player aura with a name and a
-- time left, which is what Buffs.lua reads.
local function Fed(seconds)
	AURAS = { { name = "Well Fed", icon = "Interface\\Icons\\INV_Misc_Food_15", duration = seconds,
		expirationTime = seconds > 0 and (1000 + seconds) or 0, spellId = 232493 } }
end

Reset()
Put(0, 1, 2003); Put(0, 2, 2001)
Fed(600)
ns.Buttons:Update()
Check("buff: with the buff banked the biggest restore wins", Food() == "item:2003", Food())

Reset()
Put(0, 1, 2003); Put(0, 2, 2001)
Fed(20)
ns.Buttons:Update()
Check("buff: in its last half minute buff food leads again", Food() == "item:2001", Food())

Fed(30)
ns.Buttons:Update()
Check("buff: at half a minute it is worth topping up", Food() == "item:2001", Food())

Reset()
Put(0, 1, 2003); Put(0, 2, 2001)
AURAS = { { name = "Well Fed", icon = "Interface\\Icons\\INV_Misc_Food_15", duration = 0, expirationTime = 0 } }
ns.Buttons:Update()
Check("buff: a buff without a timer counts as banked", Food() == "item:2003", Food())

Reset()
Put(0, 1, 2003); Put(0, 2, 2001); Put(0, 3, 159)
Fed(600)
ns.Buttons:Update()
Check("buff: water is chosen the same way as always", Water() == "item:159", Water())

Reset()
Put(0, 1, 2003); Put(0, 2, 2001)
AURAS = { { name = "Nourished", icon = "Interface\\Icons\\INV_Misc_Food_15", duration = 900, expirationTime = 1900 } }
ns.Buttons:Update()
Check("buff: an aura it does not know is not a food buff", Food() == "item:2001", Food())

-- The crossing itself is not an event, so a timer is set for it: one while the buff is
-- banked, none when buff food should lead.
Reset()
Put(0, 1, 2001)
Fed(600)
TIMERS = 0
ns.Buffs:Refresh()
Check("buff: a timer is set for when the buff stops being banked", TIMERS == 1, tostring(TIMERS))

Fed(20)
TIMERS = 0
ns.Buffs:Refresh()
Check("buff: no timer is set once buff food leads", TIMERS == 0, tostring(TIMERS))

AURAS = {}
TIMERS = 0
ns.Buffs:Refresh()
Check("buff: no timer is set without a buff", TIMERS == 0, tostring(TIMERS))

-- Aura data this client refuses to let arithmetic touch is skipped, not fatal: the restock
-- and the report still work.
AURAS = { setmetatable({}, { __index = function() error("secret", 0) end }) }
Check("buff: an unreadable aura is skipped", ns.Buffs:Left() == nil, tostring(ns.Buffs:Left()))
Check("buff: and the button still stocks", (function()
	Put(0, 1, 2001)
	ns.Buttons:Update()
	return Food() == "item:2001"
end)(), tostring(Food()))
AURAS = {}

-- /bb debug says what it makes of the buff.
Reset()
Put(0, 1, 2001)
Fed(600)
slash("debug")
Check("buff: the debug reports the time left and the ranking",
	Debugged("food buff: 600s left, so buff food waits"), table.concat(ns.Window.debugLines or {}, " / "))

AURAS = {}
slash("debug")
Check("buff: the debug says when there is no buff", Debugged("food buff: none"))

-- A potion restores health but is not food.
Reset()
Put(0, 1, 118)
ns.Buttons:Update()
Check("stock: a healing potion is not food", Food() == nil, Food())

-- The character's level, a locked slot and a cooldown all pass an item over.
Reset()
Put(0, 1, 9999)
PLAYER.level = 40
ns.Buttons:Update()
Check("stock: an item above the character's level is passed over", Food() == nil, Food())

PLAYER.level = 60
ns.Buttons:Update()
Check("stock: used once the level requirement is met", Food() == "item:9999", Food())

Reset()
Put(0, 1, 8766, 1, true); Put(0, 2, 159)
ns.Buttons:Update()
Check("stock: a locked slot is passed over", Water() == "item:159", Water())

Reset()
Put(0, 1, 8766); Put(0, 2, 159)
COOLDOWNS[8766] = { 900, 300 }
ns.Buttons:Update()
Check("stock: an item on cooldown is passed over", Water() == "item:159", Water())

-- Emptying the bags clears the items, so a click does nothing rather than the wrong
-- thing, but each button keeps its place and goes grey instead of vanishing.
BAGS = {}
ns.Buttons:Update()
Check("stock: empty bags clear the food button", Food() == nil, tostring(Food()))
Check("stock: empty bags clear the water button", Water() == nil, tostring(Water()))
Check("empty: the button stays where it is", ns.Buttons.food.shown == true)
Check("empty: the food button shows its own kind, greyed",
	ns.Buttons.food.icon.texture == "Interface\\Icons\\INV_Misc_Food_16"
		and ns.Buttons.food.icon.desaturated == true
		and ns.Buttons.food.icon.alpha < 1,
	tostring(ns.Buttons.food.icon.texture) .. " " .. tostring(ns.Buttons.food.icon.alpha))
Check("empty: the water button shows a drink", ns.Buttons.water.icon.texture == "Interface\\Icons\\INV_Drink_04",
	tostring(ns.Buttons.water.icon.texture))
Check("empty: an empty button counts nothing", ns.Buttons.food.count:GetText() == "",
	ns.Buttons.food.count:GetText())

ns.Buttons.food.OnEnter(ns.Buttons.food)
Check("empty: the tooltip says it is out of food", TOOLTIP_LINES[1] == "Out of food", tostring(TOOLTIP_LINES[1]))
Check("empty: the tooltip says what fills it",
	TOOLTIP_LINES[2] ~= nil and TOOLTIP_LINES[2]:find("fills this slot", 1, true) ~= nil, tostring(TOOLTIP_LINES[2]))

ns.Buttons.water.OnEnter(ns.Buttons.water)
Check("empty: the water tooltip says it is out of water", TOOLTIP_LINES[1] == "Out of water",
	tostring(TOOLTIP_LINES[1]))

-- A fight locks a secure button's attributes: the change waits for it to end.
Reset()
Put(0, 1, 422)
COMBAT = true
ns.Buttons:Update()
Check("stock: nothing is written during a fight", Food() == nil, tostring(Food()))
Check("stock: the change is held for after the fight", ns.Buttons.waiting == true)

COMBAT = false
ns.Buttons:Update()
Check("stock: the held change is applied after the fight", Food() == "item:422", Food())
Check("stock: nothing is left waiting", ns.Buttons.waiting == false)

-- The action bar button of a /click macro shows the item it will use.
Reset()
Put(0, 1, 422); Put(0, 2, 8766)
MACROS = {
	{ name = "Food", body = "/click BestBiteFood" },
	{ name = "Water", body = "#showtooltip\n/click BestBiteWater" },
	{ name = "Other", body = "/use Minor Healing Potion" },
}
MACTION = { [1] = { "macro", 1 }, [2] = { "macro", 2 }, [3] = { "macro", 3 }, [4] = { "spell", 133 } }
ns.Icons:Refresh()
Check("icons: a /click food macro shows the best food", MACTION_TEXTURE[1] == "Interface\\Icons\\Item422", MACTION_TEXTURE[1])
Check("icons: a /click water macro shows the best water", MACTION_TEXTURE[2] == "Interface\\Icons\\Item8766", MACTION_TEXTURE[2])
Check("icons: a macro that is not ours is left alone", MACTION_TEXTURE[3] == nil, tostring(MACTION_TEXTURE[3]))
Check("icons: a spell button is left alone", MACTION_TEXTURE[4] == nil, tostring(MACTION_TEXTURE[4]))

slash("icons")
Check("icons: the toggle puts the macro's own icon back", MACTION_TEXTURE[1] ~= "Interface\\Icons\\Item422", MACTION_TEXTURE[1])
slash("icons")
ns.Icons:Refresh()
Check("icons: the toggle turns it back on", MACTION_TEXTURE[1] == "Interface\\Icons\\Item422", MACTION_TEXTURE[1])

-- Rewriting the macro's own icon is opt-in: off, nothing is written; on, the macro
-- picks up the item icon.
Reset()
Put(0, 1, 422)
MACROS = { { name = "Food", body = "/click BestBiteFood" } }
ns.Icons:Refresh()
Check("macroicon: nothing is written while it is off", MACROS[1].icon == nil, tostring(MACROS[1].icon))

slash("macroicon")
Check("macroicon: the command turns it on", ns.db.writeMacroIcons == true)
ns.Icons:Refresh()
Check("macroicon: the macro picks up the item icon", MACROS[1].icon == "Interface\\Icons\\Item422", tostring(MACROS[1].icon))

slash("macroicon")
Check("macroicon: the command turns it off again", ns.db.writeMacroIcons == false)

-- Moving the buttons: /bb move clears their items so a click is inert, turns on
-- left-drag, and the position of each is remembered for every character.
Reset()
Put(0, 1, 422); Put(0, 2, 8766)
ns.Buttons:Update()
Check("move: the buttons hold their items to start with", Food() == "item:422", Food())

slash("move")
Check("move: the mode is on", ns.Buttons.moving == true)
Check("move: a click cannot use anything while moving", Food() == nil and Water() == nil)

BAGS = {}
ns.Buttons:Update()
Check("move: restocking waits while moving", ns.Buttons.food.itemID == 422, tostring(ns.Buttons.food.itemID))

slash("move")
Check("move: the mode is off", ns.Buttons.moving == false)
Check("move: restocking resumes", ns.Buttons.food.itemID == nil and ns.Buttons.food.shown == true,
	tostring(ns.Buttons.food.itemID))

-- Right-drag must not use the item: only the left button may click, and both of its
-- events are registered so a macro's /click reaches the button.
Check("move: only the left button is registered for clicks",
	ns.Buttons.food.clicks and #ns.Buttons.food.clicks == 2
		and ns.Buttons.food.clicks[1] == "LeftButtonUp" and ns.Buttons.food.clicks[2] == "LeftButtonDown",
	ns.Buttons.food.clicks and table.concat(ns.Buttons.food.clicks, ", "))
Check("move: the right button is never registered for clicks",
	not table.concat(ns.Buttons.food.clicks, ","):find("Right", 1, true))
-- Left unset, the client reads "cast on key press" (on by default) and then ignores
-- a macro's /click, which never sends a key down.
Check("move: the button acts on a macro's click, not only a key down",
	ns.Buttons.food:GetAttribute("useOnKeyDown") == false,
	tostring(ns.Buttons.food:GetAttribute("useOnKeyDown")))

-- Dressed as an action button: a slot ring with the icon inside it, hover highlight.
Check("look: the slot ring is drawn around the icon",
	ns.Buttons.food.border.texture == "Interface\\Buttons\\UI-Quickslot2", tostring(ns.Buttons.food.border.texture))
Check("look: the icon sits inside the ring", ns.Buttons.food.icon.width == 32, tostring(ns.Buttons.food.icon.width))
Check("look: hovering highlights it", ns.Buttons.food.highlightTexture == "Interface\\Buttons\\ButtonHilight-Square",
	tostring(ns.Buttons.food.highlightTexture))
Check("look: it is a little bigger than a bag icon", ns.Buttons.food.size == 40, tostring(ns.Buttons.food.size))

-- Right-drag always moves; left-drag only in move mode.
Reset()
Put(0, 1, 422)
ns.Buttons:Update()
MOVE_STARTED = 0
ns.Buttons.food.OnDragStart(ns.Buttons.food, "LeftButton")
Check("move: a left drag does nothing outside the mode", MOVE_STARTED == 0, tostring(MOVE_STARTED))

ns.Buttons.food.OnDragStart(ns.Buttons.food, "RightButton")
Check("move: a right drag moves the button", MOVE_STARTED == 1, tostring(MOVE_STARTED))

slash("move")
MOVE_STARTED = 0
ns.Buttons.food.OnDragStart(ns.Buttons.food, "LeftButton")
Check("move: a left drag moves it in the mode", MOVE_STARTED == 1, tostring(MOVE_STARTED))
slash("move")

-- A fight locks the buttons in place instead of moving them.
Reset()
COMBAT = true
MOVE_STARTED = 0
MESSAGES = {}
ns.Buttons.food.OnDragStart(ns.Buttons.food, "RightButton")
Check("move: a fight keeps the buttons where they are", MOVE_STARTED == 0, tostring(MOVE_STARTED))
Check("move: and says why", Said("out of combat"), MESSAGES[1])
COMBAT = false

-- The aura list in /bb debug is what a food buff gets recognised from, and how long it
-- has left to run.
Reset()
Put(0, 1, 422)
AURAS = { { name = "Well Fed", icon = "Interface\\Icons\\INV_Misc_Food_15", duration = 900, expirationTime = 1812,
	spellId = 232493 } }
slash("debug")
Check("auras: the debug lists the aura with its icon and time left",
	Debugged("auras: Well Fed [INV_Misc_Food_15] 812s"), table.concat(ns.Window.debugLines or {}, " / "))

AURAS = {}
slash("debug")
Check("auras: the debug says when there are none", Debugged("auras: none"))

-- /bb debug reports what it sees, including what the buttons would click.
Reset()
Put(0, 1, 422); Put(0, 2, 8766); Put(0, 3, 118)
ns.Buttons:Update()
slash("debug")
Check("debug: reports the loaded files", Debugged("files: Core ok, Detect ok, Consume ok, Buttons ok, Icons ok"))
Check("debug: reports the stocked buttons", Debugged("buttons: food item:422"))
Check("debug: names the food it found", Debugged("Dwarven Mild"))
Check("debug: says the potion is not food", not Debugged("Minor Healing Potion"))

local realConsume = ns.Consume
ns.Consume = nil
MESSAGES = {}
slash("debug")
Check("debug: survives a missing Consume module", Debugged("Consume MISSING"))
ns.Consume = realConsume

-- The window is the interface: /bb opens it, /bb again closes it, and its buttons run
-- the commands so they need not be typed.
Reset()
Put(0, 1, 422); Put(0, 2, 8766)
ns.Buttons:Update()
MESSAGES = {}

slash("")
Check("window: /bb opens it", ns.Window.frame ~= nil and ns.Window.frame.shown == true)
Check("window: it opens on the commands page", ns.Window.page == "main")
Check("window: the eat box holds the macro to copy", ns.Window.macroFood:GetText() == "/click BestBiteFood",
	ns.Window.macroFood:GetText())
Check("window: the drink box holds the macro to copy", ns.Window.macroWater:GetText() == "/click BestBiteWater",
	ns.Window.macroWater:GetText())
Check("window: opening it prints nothing to chat", #MESSAGES == 0, table.concat(MESSAGES, " / "))

slash("")
Check("window: /bb again closes it", ns.Window.frame.shown == false)

Check("window: Esc closes it, as a pane the client knows", (function()
	for _, name in ipairs(UISpecialFrames or {}) do
		if name == "BestBiteFrame" then return true end
	end
	return false
end)())

slash("")
ns.Window.switches.icons.scripts.OnClick()
Check("window: the action bar switch turns the setting off", ns.db.showIcons == false)
Check("window: the switch shows it off", ns.Window.switches.icons.on == false and ns.Window.switches.icons.tick.shown ~= true)

ns.Window.switches.icons.scripts.OnClick()
Check("window: and back on again", ns.db.showIcons == true)
Check("window: the switch shows it on", ns.Window.switches.icons.on == true and ns.Window.switches.icons.tick.shown == true)

ns.Window.switches.macroicon.scripts.OnClick()
Check("window: the macro icon switch turns that setting on", ns.db.writeMacroIcons == true
	and ns.Window.switches.macroicon.on == true, tostring(ns.db.writeMacroIcons))
ns.Window.switches.macroicon.scripts.OnClick()
Check("window: and off again", ns.db.writeMacroIcons == false and ns.Window.switches.macroicon.on == false)

-- A setting changed in chat shows in the window next time it is opened.
ns.Window.frame:Hide()
ns.db.showIcons = false
slash("")
Check("window: the switch follows a setting changed in chat", ns.Window.switches.icons.on == false)
ns.db.showIcons = true
ns.Window.frame:Hide()

ns.Window.buttons.move.scripts.OnClick()
Check("window: the move button turns move mode on", ns.Buttons.moving == true)
ns.Window.buttons.move.scripts.OnClick()
Check("window: and off again", ns.Buttons.moving == false)

ns.db.learned[422] = { kind = "food", amount = 61 }
ns.Window.buttons.reset.scripts.OnClick()
Check("window: reset forgets what it learned", next(ns.db.learned) == nil)

ns.Window.buttons.debug.scripts.OnClick()
Check("window: the debug button shows the debug page", ns.Window.page == "debug")
Check("window: the debug page is filled", #(ns.Window.debugLines or {}) > 0)
Check("window: the report is tall enough to be seen", (ns.Window.text:GetParent().height or 0) > 100,
	tostring(ns.Window.text:GetParent().height))
Check("window: the report carries the file lines",
	(ns.Window.text:GetText() or ""):find("files:", 1, true) ~= nil)

slash("")
Check("window: /bb on the debug page goes back to the commands", ns.Window.page == "main" and ns.Window.frame.shown == true)

ns.Window.buttons.debug.scripts.OnClick()
ns.Window.backButton.scripts.OnClick()
Check("window: back returns to the commands page", ns.Window.page == "main")

-- A report line the client refuses to read does not sink the page: it becomes a note and
-- the rest of the report still shows. This is how the "secret value" failure appears.
local realLines = ns.BestBite.DebugLines
ns.BestBite.DebugLines = function()
	return { "files: Core ok", "buttons: food item:422", "macros: /click BestBiteFood", {} }
end
MESSAGES = {}
ns.Window:ShowDebug()
Check("window: an unreadable line is noted, not fatal", ns.Window.page == "debug")
Check("window: the note names the line",
	(ns.Window.text:GetText() or ""):find("line 4 could not be read", 1, true) ~= nil,
	ns.Window.text:GetText())
Check("window: the readable lines still show", (ns.Window.text:GetText() or ""):find("files: Core ok", 1, true) ~= nil)
ns.BestBite.DebugLines = realLines
ns.Window:ShowPage("main")

-- A "secret" value survives tostring and `..` but is refused on use. Patching table.concat
-- to refuse a marker string reproduces exactly what the client did to the report.
local realConcat = table.concat
local SECRET = "SECRET-VALUE"
table.concat = function(list, sep, first, last)
	if type(list) == "table" then
		for _, value in pairs(list) do
			if value == SECRET then error("invalid value (secret)", 0) end
		end
	end
	return realConcat(list, sep, first, last)
end

Check("debug: a secret value is not showable", ns.API.Showable(SECRET) == false)
Check("debug: a plain string is showable", ns.API.Showable("hello") == true)
Check("debug: a table is not showable", ns.API.Showable({}) == false)

ns.BestBite.DebugLines = function() return { "files: Core ok", SECRET, "best food: none" } end
ns.Window:ShowDebug()
Check("window: a secret line becomes a note, not the whole page",
	(ns.Window.text:GetText() or ""):find("line 2 could not be read", 1, true) ~= nil, ns.Window.text:GetText())
Check("window: the lines around a secret still show",
	(ns.Window.text:GetText() or ""):find("best food: none", 1, true) ~= nil, ns.Window.text:GetText())

-- The health line marks a secret rather than passing it into the report.
ns.BestBite.DebugLines = realLines
local realHealthValue = UnitHealth
UnitHealth = function() return SECRET end
local secretReport = ns.BestBite:DebugLines()
UnitHealth = realHealthValue
table.concat = realConcat

local secretHealth
for _, line in ipairs(secretReport) do
	if type(line) == "string" and line:find("health", 1, true) then secretHealth = line end
end
Check("debug: a secret health value is marked", secretHealth ~= nil and secretHealth:find("health %?/", 1) ~= nil,
	tostring(secretHealth))

-- The health line reads its values through a guard, so a call the client refuses leaves a
-- placeholder rather than an error.
local realHealth = UnitHealth
UnitHealth = function() error("secret", 0) end
MESSAGES = {}
local guarded = ns.BestBite:DebugLines()
UnitHealth = realHealth
local healthLine
for _, line in ipairs(guarded) do
	if line:find("health", 1, true) then healthLine = line end
end
Check("debug: a refused value becomes a placeholder", healthLine ~= nil and healthLine:find("health %?/", 1) ~= nil,
	tostring(healthLine))

realLines = ns.BestBite.DebugLines
ns.BestBite.DebugLines = function() error("boom", 0) end
MESSAGES = {}
ns.Window.buttons.debug.scripts.OnClick()
Check("window: a broken report still shows the debug page", ns.Window.page == "debug")
Check("window: and says why on the page",
	(ns.Window.debugLines and ns.Window.debugLines[1] or ""):find("could not be built", 1, true) ~= nil,
	tostring(ns.Window.debugLines and ns.Window.debugLines[1]))
Check("window: and says why in chat too", Said("could not be built"))
ns.BestBite.DebugLines = realLines
ns.Window:ShowPage("main")

-- Without the window, every command still answers in chat.
local realWindow = ns.Window
ns.Window = nil
MESSAGES = {}
slash("")
Check("window: without it, /bb falls back to chat", Said("uses the best food or water you carry"))
ns.Window = realWindow

-- A command that would use an item says what to put in a macro instead.
Reset()
Put(0, 1, 422)
slash("consume")
Check("advice: says the game blocks an addon from using an item", Said("blocks an addon from using an item"))
Check("advice: gives the macro to use", Said("/click BestBiteFood then /click BestBiteWater"))

-- A client call that throws is reported in chat, not swallowed.
Reset()
Put(0, 1, 422)
local realSlotInfo = C_Container.GetContainerItemInfo
C_Container.GetContainerItemInfo = function() error("boom", 0) end
slash("food")
Check("error: a failing client call is reported", Said("could not stock the click buttons"), MESSAGES[1])
C_Container.GetContainerItemInfo = realSlotInfo

-- A merchant's item is read from its own tooltip, the same way a bag item is.
Reset()
Stock(1, 422, 25, 5, 5)
local mercKind, mercAmount = ns.Detect:ScanMerchant(1)
Check("vendor: a merchant item's kind is read from its tooltip", mercKind == "food", tostring(mercKind))
Check("vendor: and the amount it restores", mercAmount == 243, tostring(mercAmount))

Stock(2, 2001, 30, 5, 5)
local _, _, mercBuffs = ns.Detect:ScanMerchant(2)
Check("vendor: a merchant item's buff points are read", ns.Detect:Points(mercBuffs) == 12,
	tostring(ns.Detect:Points(mercBuffs)))

local unknown = ns.Detect:ScanMerchant(99)
Check("vendor: an index the merchant does not have reads as nothing", unknown == nil, tostring(unknown))

-- The ordering that picks from the bags is the same one a vendor purchase uses.
Reset()
local prefer = ns.Consume:PreferBuffs("food")
Check("vendor: buff food leads when nothing is banked", prefer == true)

local plain = { amount = 500, points = 0, itemLevel = 20, count = 1 }
local buffed = { amount = 61, points = 12, itemLevel = 20, count = 1 }
Check("vendor: the ranking puts buff food first", ns.Consume:Better(buffed, plain, true) == true)
Check("vendor: and plain food first when the buff is banked", ns.Consume:Better(plain, buffed, false) == true)
Check("vendor: more restore wins on equal points",
	ns.Consume:Better({ amount = 500, points = 0, itemLevel = 1, count = 1 },
		{ amount = 100, points = 0, itemLevel = 60, count = 9 }, false) == true)

-- Nothing is restocked while Polestar says it is doing it.
Reset()
local standDown, why = ns.Vendor:StandDown()
Check("vendor: nothing stands down without Polestar", standDown == false, tostring(why))

Polestar = { QoL = { Restock = { Get = function(kind) return kind == "food" and 20 or 0 end } } }
local standDown2, why2 = ns.Vendor:StandDown()
Check("vendor: Polestar with food amounts stands BestBite down", standDown2 == true, tostring(why2))
Check("vendor: and says which addon is doing it", tostring(why2):find("Polestar", 1, true) ~= nil, tostring(why2))
Polestar = nil

-- Only items good for your level count towards the target: at level 40, the band starts
-- at 30, so a level 35 food counts, a level 15 one is too weak and a level 60 one unusable.
Reset()
PLAYER.level = 40
Check("vendor: a level 15 food is too weak to count", ns.Vendor:LevelAppropriate(422, 40) == false)
Check("vendor: a level 60 food is not usable yet", ns.Vendor:LevelAppropriate(9999, 40) == false)
Check("vendor: a level 35 food counts", ns.Vendor:LevelAppropriate(9997, 40) == true)
Check("vendor: an item with no level requirement counts", ns.Vendor:LevelAppropriate(5350, 40) == true)

-- Twenty weak items do not satisfy the target.
Reset()
PLAYER.level = 60
Put(0, 1, 422, 20)
Put(0, 2, 9999, 2)
local shortfall, have = ns.Vendor:Shortfall("food")
Check("vendor: weak food does not count towards the target", have == 2, tostring(have))
Check("vendor: so the shortfall is measured against the good food", shortfall == 3, tostring(shortfall))

-- The switch and the target come from the saved settings.
Reset()
Check("vendor: restocking is off by default", ns.Vendor:Db().on == false)
Check("vendor: one stack is the default target", ns.Vendor:Db().target == 5, tostring(ns.Vendor:Db().target))

-- With the switch on and the bags empty, a visit buys up to the target for each kind.
Reset()
PLAYER.level = 60
Stock(1, 9999, 40, 5, 20)   -- Raid Food, restores 2000
Stock(2, 8770, 20, 5, 20)   -- Sparkling Spring Water, restores 1344 mana
ns.db = nil
BestBiteDB = { vendor = { on = true, target = 5 } }
ns.Vendor:Restock()
Check("vendor: food is bought up to the target", ns.Vendor:Count("food", 60) == 5,
	tostring(ns.Vendor:Count("food", 60)))
Check("vendor: water is bought up to the target", ns.Vendor:Count("water", 60) == 5,
	tostring(ns.Vendor:Count("water", 60)))
Check("vendor: the money was spent", MERCHANT.money < 100000, tostring(MERCHANT.money))
Check("vendor: and it said what it bought", Said("bought"), table.concat(MESSAGES, " / "))

-- Part of a target is topped up, not a whole one.
Reset()
PLAYER.level = 60
Stock(1, 9999, 40, 5, 20)
Put(0, 1, 9999, 3)
ns.db = nil
BestBiteDB = { vendor = { on = true, target = 5 } }
ns.Vendor:Restock()
Check("vendor: a partial target is topped up to exactly the target", ns.Vendor:Count("food", 60) == 5,
	tostring(ns.Vendor:Count("food", 60)))

-- A vendor holding less than the shortfall sells what it has.
Reset()
PLAYER.level = 60
Stock(1, 9999, 40, 5, 2)
ns.db = nil
BestBiteDB = { vendor = { on = true, target = 5 } }
ns.Vendor:Restock()
Check("vendor: a thin vendor sells what it has", ns.Vendor:Count("food", 60) == 2,
	tostring(ns.Vendor:Count("food", 60)))

-- Buff food is bought while the buff is missing; the biggest restore once it is banked.
Reset()
PLAYER.level = 60
Stock(1, 9999, 40, 5, 20)
Stock(2, 2010, 45, 5, 20)   -- Banquet Portions: 400 health, 14 stamina
ns.db = nil
BestBiteDB = { vendor = { on = true, target = 5 } }
ns.Vendor:Restock()
Check("vendor: buff food is bought when nothing is banked",
	MERCHANT.bought[1] ~= nil and MERCHANT.bought[1].itemID == 2010,
	MERCHANT.bought[1] and tostring(MERCHANT.bought[1].itemID))

Reset()
PLAYER.level = 60
Stock(1, 9999, 40, 5, 20)
Stock(2, 2010, 45, 5, 20)
Fed(600)
ns.db = nil
BestBiteDB = { vendor = { on = true, target = 5 } }
ns.Vendor:Restock()
Check("vendor: the biggest restore is bought when the buff is banked",
	MERCHANT.bought[1] ~= nil and MERCHANT.bought[1].itemID == 9999,
	MERCHANT.bought[1] and tostring(MERCHANT.bought[1].itemID))
AURAS = {}

-- Off by default: nothing is bought.
Reset()
PLAYER.level = 60
Stock(1, 9999, 40, 5, 20)
ns.db = nil
BestBiteDB = {}
ns.Vendor:Restock()
Check("vendor: nothing is bought with the switch off", #MERCHANT.bought == 0, tostring(#MERCHANT.bought))
Check("vendor: and nothing is said", #MESSAGES == 0, table.concat(MESSAGES, " / "))

-- A target already met buys nothing and says nothing.
Reset()
PLAYER.level = 60
Stock(1, 9999, 40, 5, 20)
Put(0, 1, 9999, 5)
ns.db = nil
BestBiteDB = { vendor = { on = true, target = 5 } }
ns.Vendor:Restock()
Check("vendor: a full bag buys nothing", #MERCHANT.bought == 0, tostring(#MERCHANT.bought))
Check("vendor: a full bag says nothing", #MESSAGES == 0, table.concat(MESSAGES, " / "))

-- Short money buys what it can and says how short it fell.
Reset()
PLAYER.level = 60
Stock(1, 9999, 100, 5, 20)
MERCHANT.money = 250
ns.db = nil
BestBiteDB = { vendor = { on = true, target = 5 } }
ns.Vendor:Restock()
Check("vendor: short money buys what it can", #MERCHANT.bought == 1, tostring(#MERCHANT.bought))
Check("vendor: and says it fell short", Said("short"), table.concat(MESSAGES, " / "))

-- Nothing good for the level is sold: the best usable one is bought as a fallback.
Reset()
PLAYER.level = 60
Stock(1, 422, 10, 5, 20)   -- Dwarven Mild, level 15: outside the band
ns.db = nil
BestBiteDB = { vendor = { on = true, target = 5 } }
ns.Vendor:Restock()
Check("vendor: a fallback is bought when nothing is in band", #MERCHANT.bought == 1, tostring(#MERCHANT.bought))
Check("vendor: and it says it was a fallback", Said("below your level"), table.concat(MESSAGES, " / "))

-- A weak item never outranks one of the band on the same vendor.
Reset()
PLAYER.level = 60
Stock(1, 9999, 40, 5, 20)   -- Raid Food, level 60: in the band
Stock(2, 2001, 10, 5, 20)   -- Buff Rations, level 1: outside it, but buffs
ns.db = nil
BestBiteDB = { vendor = { on = true, target = 5 } }
ns.Vendor:Restock()
Check("vendor: an item of the band wins over a weak one",
	MERCHANT.bought[1] ~= nil and MERCHANT.bought[1].itemID == 9999,
	MERCHANT.bought[1] and tostring(MERCHANT.bought[1].itemID))
Check("vendor: and nothing is said to be below the level", not Said("below your level"),
	table.concat(MESSAGES, " / "))

-- MERCHANT_UPDATE re-runs the pass after every purchase: one fallback a visit is enough.
Reset()
PLAYER.level = 60
Stock(1, 422, 10, 5, 20)
ns.db = nil
BestBiteDB = { vendor = { on = true, target = 5 } }
ns.Vendor:Restock()
ns.Vendor:Restock()
Check("vendor: a fallback is bought once a visit", #MERCHANT.bought == 1, tostring(#MERCHANT.bought))
ns.Vendor:Restock(true)
Check("vendor: a Buy now press buys the fallback again", #MERCHANT.bought == 2, tostring(#MERCHANT.bought))

-- Polestar handling it means BestBite does not buy.
Reset()
PLAYER.level = 60
Stock(1, 9999, 40, 5, 20)
ns.db = nil
BestBiteDB = { vendor = { on = true, target = 5 } }
Polestar = { QoL = { Restock = { Get = function() return 20 end } } }
ns.Vendor:Restock()
Polestar = nil
Check("vendor: Polestar handling it means nothing is bought", #MERCHANT.bought == 0, tostring(#MERCHANT.bought))
Check("vendor: and the reason is said", Said("Polestar"), table.concat(MESSAGES, " / "))

-- A fight stops it.
Reset()
PLAYER.level = 60
Stock(1, 9999, 40, 5, 20)
ns.db = nil
BestBiteDB = { vendor = { on = true, target = 5 } }
COMBAT = true
ns.Vendor:Restock()
COMBAT = false
Check("vendor: nothing is bought in combat", #MERCHANT.bought == 0, tostring(#MERCHANT.bought))

print(string.format("\n%d checks, %d failures", total, failures))
if failures > 0 then
	error(("%d checks failed"):format(failures), 0)
end
