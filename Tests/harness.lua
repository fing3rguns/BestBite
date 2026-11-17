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

---------------------------------------------------------------------------- state
local BAGS, COOLDOWNS, MESSAGES = {}, {}, {}
local MACROS, MACTION, MACTION_TEXTURE = {}, {}, {}
local PLAYER = { level = 60, health = 500, healthMax = 1000, mana = 500, manaMax = 1000 }
local COMBAT = false

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
C_Timer = { After = function(_, run) run() end }
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
}

CreateFrame = function(_, name, _, template)
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
			function texture:SetAlpha() end
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
	return TOOLTIP
end

GameTooltip = {
	SetOwner = function() end,
	AddLine = function() end,
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
LoadAddon("Consume.lua")
LoadAddon("Buttons.lua")
LoadAddon("Icons.lua")

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
	MACROS, MACTION, MACTION_TEXTURE = {}, {}, {}
	PLAYER = { level = 60, health = 500, healthMax = 1000, mana = 500, manaMax = 1000 }
	COMBAT = false
	BestBiteDB, ns.db = nil, nil
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

-- Emptying the bags clears the buttons, so a click does nothing rather than the
-- wrong thing, and hides them.
BAGS = {}
ns.Buttons:Update()
Check("stock: the button hides when the bags hold none", ns.Buttons.food.shown == false)
Check("stock: empty bags clear the food button", Food() == nil, tostring(Food()))
Check("stock: empty bags clear the water button", Water() == nil, tostring(Water()))

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
Check("move: restocking waits while moving", ns.Buttons.food.shown == true)

slash("move")
Check("move: the mode is off", ns.Buttons.moving == false)
Check("move: restocking resumes", ns.Buttons.food.shown == false)

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

-- /bb debug reports what it sees, including what the buttons would click.
Reset()
Put(0, 1, 422); Put(0, 2, 8766); Put(0, 3, 118)
ns.Buttons:Update()
slash("debug")
Check("debug: reports the loaded files", Said("files: Core ok, Detect ok, Consume ok, Buttons ok, Icons ok"))
Check("debug: reports the stocked buttons", Said("buttons: food item:422"), MESSAGES[2])
Check("debug: names the food it found", Said("Dwarven Mild"))
Check("debug: says the potion is not food", not Said("Minor Healing Potion"))

local realConsume = ns.Consume
ns.Consume = nil
MESSAGES = {}
slash("debug")
Check("debug: survives a missing Consume module", Said("Consume MISSING"))
ns.Consume = realConsume

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

print(string.format("\n%d checks, %d failures", total, failures))
if failures > 0 then
	error(("%d checks failed"):format(failures), 0)
end
