-- BestBite: uses the best food or water in the bags from one macro-ready command.
-- This file holds the client calls the rest of the addon shares, the saved
-- variables, and the slash commands.

local ADDON, ns = ...

local BestBite = {}
ns.BestBite = BestBite
_G.BestBite = BestBite

local C_Container, C_Item, C_UnitAuras = C_Container, C_Item, C_UnitAuras

-- Forever answers the C_Container and C_Item namespaces; the pre-10.0 globals are
-- read where the namespaces are missing, so the addon also runs on an older client.
local LegacySlots = _G.GetContainerNumSlots
local LegacySlotInfo = _G.GetContainerItemInfo
local LegacyCooldown = _G.GetContainerItemCooldown
local ItemInfoFn = (C_Item and C_Item.GetItemInfo) or _G.GetItemInfo

local CONSUMABLE = (Enum and Enum.ItemClass and Enum.ItemClass.Consumable) or 0
local FOOD_DRINK = (Enum and Enum.ItemConsumableSubclass and Enum.ItemConsumableSubclass.FoodDrink) or 5

local API = {}
ns.API = API

-- The last bag to scan: the backpack is bag 0 and the equipped bags follow it.
function API.NumBags()
	return NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4
end

function API.NumSlots(bag)
	if C_Container and C_Container.GetContainerNumSlots then
		return C_Container.GetContainerNumSlots(bag) or 0
	elseif LegacySlots then
		return LegacySlots(bag) or 0
	end
	return 0
end

-- What the slot holds: { itemID = number, count = number, locked = boolean },
-- or nil when the slot is empty.
function API.SlotItem(bag, slot)
	if C_Container and C_Container.GetContainerItemInfo then
		local info = C_Container.GetContainerItemInfo(bag, slot)
		if not info or not info.itemID or info.itemID == 0 then return nil end
		-- A client that names the stack size differently must not read as an empty
		-- slot, which would hide every item in the bags.
		local count = info.stackCount or info.quantity or info.count or 1
		return { itemID = info.itemID, count = count, locked = info.isLocked and true or false }
	elseif LegacySlotInfo then
		local _, count, locked, _, _, _, link = LegacySlotInfo(bag, slot)
		local itemID = link and link:match("item:(%d+)")
		if not itemID then return nil end
		return { itemID = tonumber(itemID), count = count or 1, locked = locked and true or false }
	end
	return nil
end

-- Nothing here uses a bag item: the game blocks that for an addon (Buttons.lua
-- holds the secure buttons the client clicks for us).

-- name, itemLevel, requiredLevel. Each is nil while the client has not cached
-- the item, which does not happen for an item in the bags.
function API.ItemInfo(itemID)
	if not ItemInfoFn then return nil end
	local name, _, _, itemLevel, requiredLevel = ItemInfoFn(itemID)
	return name, itemLevel, requiredLevel
end

-- The item's inventory icon, or nil while the client has not cached the item.
function API.ItemIcon(itemID)
	if C_Item and C_Item.GetItemIconByID then
		local ok, icon = pcall(C_Item.GetItemIconByID, itemID)
		if ok and icon then return icon end
	end
	return ItemInfoFn and select(10, ItemInfoFn(itemID)) or nil
end

-- How many of the item the bags hold, for the number on a button.
function API.CountInBags(itemID)
	local total = 0
	for bag = 0, API.NumBags() do
		for slot = 1, API.NumSlots(bag) do
			local item = API.SlotItem(bag, slot)
			if item and item.itemID == itemID then
				total = total + (item.count or 0)
			end
		end
	end
	return total
end

-- classID, subclassID (nil, nil on a client without the instant lookup).
function API.ItemClass(itemID)
	if C_Item and C_Item.GetItemInfoInstant then
		return select(6, C_Item.GetItemInfoInstant(itemID))
	end
	return nil, nil
end

-- Whether the item is food or drink at all. Which of the two it is takes a
-- tooltip: the client reports one "Food & Drink" subclass for both (Detect.lua).
function API.IsFoodDrink(itemID)
	local classID, subclassID = API.ItemClass(itemID)
	return classID == CONSUMABLE and subclassID == FOOD_DRINK
end

-- Whether this character may use the item at all (class, proficiency, level).
function API.IsUsable(itemID)
	if C_Item and C_Item.IsUsableItem then
		local ok, usable = pcall(C_Item.IsUsableItem, itemID)
		if ok then return usable and true or false end
	end
	-- A client without the C_Item lookup: the older call takes the item's link.
	local LegacyUsable = _G.IsUsableItem
	local link = ItemInfoFn and select(2, ItemInfoFn(itemID))
	if LegacyUsable and link then
		local ok, usable = pcall(LegacyUsable, link)
		if ok then return usable and true or false end
	end
	return true
end

-- start, duration of the item's cooldown; 0, 0 when it is ready or unknown.
-- The container call takes the slot, not the item: Forever's own usage line reads
-- C_Container.GetContainerItemCooldown(containerIndex, slotIndex). A client that
-- answers only the item form is given that instead.
function API.Cooldown(itemID, bag, slot)
	if C_Container and C_Container.GetContainerItemCooldown then
		local ok, start, duration = pcall(C_Container.GetContainerItemCooldown, bag, slot)
		if ok then return start, duration end
	end
	if C_Item and C_Item.GetItemCooldown then
		local ok, start, duration = pcall(C_Item.GetItemCooldown, itemID)
		if ok then return start, duration end
	end
	if LegacyCooldown then
		local ok, start, duration = pcall(LegacyCooldown, bag, slot)
		if ok then return start, duration end
	end
	return 0, 0
end

-- Whether this character has a mana bar at all: a warrior or rogue has none.
function API.HasMana()
	return (UnitPowerMax("player", 0) or 0) > 0
end

-- The player's auras as { name = string, icon = texture, duration = seconds,
-- expires = GetTime() stamp or nil, spellID = number }, so a food buff on the player
-- can be recognised and timed. Both shapes of the call are answered: this client has
-- C_UnitAuras, and older ones have UnitAura, which Forever still resolves.
function API.Auras(filter)
	filter = filter or "HELPFUL"
	local list = {}
	for index = 1, 40 do
		local name, icon, duration, expires, spellID
		if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
			local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "player", index, filter)
			if ok and aura then
				name, icon, duration, expires, spellID =
					aura.name, aura.icon, aura.duration, aura.expirationTime, aura.spellId
			end
		elseif UnitAura then
			name, icon, _, _, duration, expires, _, _, _, spellID = UnitAura("player", index, filter)
		end
		if not name then break end
		list[#list + 1] = { name = name, icon = icon, duration = duration, expires = expires, spellID = spellID }
	end
	return list
end

-- Whether a value can be shown at all. This client keeps some values "secret": they
-- survive tostring and `..`, but every use of one is refused, table.concat included. A
-- client without the check still refuses one at the point of use, which is what the probe
-- catches.
function API.Showable(value)
	if issecretvalue and issecretvalue(value) then return false end
	if type(value) ~= "string" then return false end
	return pcall(table.concat, { value }, "") and true or false
end

-- The saved variables, filled in on first use so the file needs no load event.
function BestBite:Db()
	if ns.db then return ns.db end
	if type(BestBiteDB) ~= "table" then BestBiteDB = {} end
	if type(BestBiteDB.learned) ~= "table" then BestBiteDB.learned = {} end
	if BestBiteDB.showIcons == nil then BestBiteDB.showIcons = true end
	if BestBiteDB.writeMacroIcons == nil then BestBiteDB.writeMacroIcons = false end
	if type(BestBiteDB.vendor) ~= "table" then BestBiteDB.vendor = {} end
	if BestBiteDB.vendor.on == nil then BestBiteDB.vendor.on = false end
	if type(BestBiteDB.vendor.target) ~= "number" then BestBiteDB.vendor.target = 5 end
	ns.db = BestBiteDB
	return ns.db
end

function BestBite:Print(message)
	DEFAULT_CHAT_FRAME:AddMessage("|cff7fd4ffBestBite|r: " .. message)
end

-- The client names the addon behind a blocked action but never the call that did
-- it, and writes no line to its log for it. So record what the addon was doing,
-- and raise it as an error: the client logs Lua errors even when it hides them.
ns.lastStep = "idle"

function BestBite:Step(text)
	ns.lastStep = text
end

local guard = CreateFrame("Frame")
local reported = nil
guard:RegisterEvent("ADDON_ACTION_BLOCKED")
guard:RegisterEvent("ADDON_ACTION_FORBIDDEN")
guard:SetScript("OnEvent", function(_, event, addonName)
	if addonName ~= ADDON then return end
	local step = tostring(ns.lastStep)
	if reported ~= step then
		reported = step
		BestBite:Print("the game blocked BestBite while: " .. step)
	end
	if step == "rewriting a macro's icon" then
		BestBite:Db().writeMacroIcons = false
		BestBite:Print("turning that off: this client does not allow it.")
	end
	local trace = debugstack and debugstack(2, 10, 4) or ""
	error(("blocked (%s) during: %s\n%s"):format(event, step, trace), 0)
end)

function BestBite:Help()
	local frame = DEFAULT_CHAT_FRAME
	frame:AddMessage("|cff7fd4ffBestBite|r uses the best food or water you carry, through a macro:")
	frame:AddMessage("  food:    /click BestBiteFood")
	frame:AddMessage("  water:   /click BestBiteWater")
	frame:AddMessage("  both:    both lines, one after the other")
	frame:AddMessage("The game blocks an addon from using an item, so a command cannot do it: the click has to come from a macro.")
	frame:AddMessage("  /bb move - drag the two buttons where you want them")
	frame:AddMessage("  /bb icons - repaint the action bar button with the item it would use")
	frame:AddMessage("  /bb macroicon - also rewrite the macro's own icon, if this client allows it")
	frame:AddMessage("  /bb reset - forget the items it has learned")
	frame:AddMessage("  /bb debug - report what it sees")
	frame:AddMessage("  /bb vendor - what restocking sees at the vendor that is open")
end

-- Why the commands cannot do the job themselves, and the macro that can, said once
-- a session so a macro that still holds /bb consume is told what went wrong.
local advised = false
function BestBite:Advise(kind)
	if ns.Buttons then ns.Buttons:Request(0) end
	if advised then return end
	advised = true

	local Consume = ns.Consume
	local missing = Consume and not Consume:Find(kind == "consume" and "food" or kind)
	local macro = kind == "water" and "/click BestBiteWater"
		or kind == "food" and "/click BestBiteFood"
		or "/click BestBiteFood then /click BestBiteWater"

	BestBite:Print("the game blocks an addon from using an item, so this has to come from a macro:")
	BestBite:Print("    " .. macro)
	if missing then
		BestBite:Print("(" .. (kind == "consume" and "no usable food" or "no usable " .. kind) .. " in your bags just now)")
	end
end

-- Everything the addon sees, for when a command seems to do nothing: which files
-- loaded, the setting, the bars, and every food or drink in the bags. It lives
-- here rather than beside the rest so it still answers when a later file fails.
-- It returns lines rather than printing them, so the window and the chat fallback
-- show the same report.
function BestBite:DebugLines()
	local lines = {}
	local function Say(text) lines[#lines + 1] = text end

	-- This client keeps some unit values "secret", and any use of one is refused, so they
	-- are read through a guard and marked rather than taking the report down.
	local function Asked(read, fallback)
		local ok, value = pcall(read)
		if not ok or value == nil then return fallback end
		local readText, text = pcall(tostring, value)
		if not readText or not API.Showable(text) then return fallback end
		return text
	end

	Say(("files: Core ok, Detect %s, Consume %s, Vendor %s, Buttons %s, Icons %s"):format(
		ns.Detect and "ok" or "MISSING", ns.Consume and "ok" or "MISSING",
		ns.Vendor and "ok" or "MISSING",
		ns.Buttons and "ok" or "MISSING", ns.Icons and "ok" or "MISSING"))
	if ns.Buttons then
		local food, water = ns.Buttons:Stocked()
		Say(("buttons: food %s | water %s"):format(food or "empty", water or "empty"))
		Say("macros: /click BestBiteFood and /click BestBiteWater")
	end
	if ns.Vendor then
		local db = ns.Vendor:Db()
		Say(("restock: %s, keep %d"):format(db.on and "on" or "off", db.target or ns.Vendor.TARGET_MIN))
	end
	Say(("health %s/%s | mana %s/%s | hasMana %s"):format(
		Asked(function() return UnitHealth("player") end, "?"),
		Asked(function() return UnitHealthMax("player") end, "?"),
		Asked(function() return UnitPower("player", 0) end, "?"),
		Asked(function() return UnitPowerMax("player", 0) end, "?"),
		Asked(function() return API.HasMana() and "yes" or "no" end, "?")))

	-- What the player is under, with the icon and time left: this is how a food buff is
	-- told apart from any other, and how long it has to run.
	local auras = API.Auras("HELPFUL")
	if #auras == 0 then
		Say("auras: none")
	else
		local parts = {}
		for _, aura in ipairs(auras) do
			parts[#parts + 1] = Asked(function()
				local left = aura.duration and aura.duration > 0 and aura.expires
					and math.max(0, math.floor(aura.expires - GetTime()))
				return ("%s [%s] %s"):format(
					tostring(aura.name),
					tostring(aura.icon or "?"):match("[^\\]+$") or "?",
					left and (left .. "s") or "no timer")
			end, "an aura that could not be read")
		end
		Say("auras: " .. table.concat(parts, ", "))
	end

	-- Which food the button should hold turns on this: a banked buff means plain food
	-- leads, a missing or nearly spent one means buff food does.
	if ns.Buffs then
		local ok, left = pcall(ns.Buffs.Left, ns.Buffs)
		local banked = ok and select(1, pcall(ns.Buffs.Banked, ns.Buffs))
		if not ok then
			Say("food buff: could not be read")
		elseif left then
			Say(("food buff: %s left, so buff food %s"):format(
				left == math.huge and "no timer" or (math.floor(left) .. "s"),
				banked and "waits" or "leads"))
		else
			Say("food buff: none, so buff food leads")
		end
	else
		Say("food buff: Buffs MISSING")
	end

	local seen = 0
	for bag = 0, API.NumBags() do
		for slot = 1, API.NumSlots(bag) do
			local item = API.SlotItem(bag, slot)
			if item and API.IsFoodDrink(item.itemID) then
				seen = seen + 1
				local name, _, requiredLevel = API.ItemInfo(item.itemID)
				local kind, amount, buffs = "?", nil, nil
				if ns.Detect then
					local ok, scanned, size, found = pcall(ns.Detect.Scan, ns.Detect, bag, slot)
					if ok then
						kind, amount, buffs = scanned or "unreadable", size, found
					else
						kind = "SCAN ERROR " .. tostring(scanned)
					end
				end
				local points = ns.Detect and ns.Detect:Points(buffs) or 0
				local label = ("%d/%d"):format(bag, slot)
				Say(Asked(function()
					return ("%s %s: %s, %s %s | usable %s | level %s | x%d%s%s"):format(
						label, item.itemID, name or "?", kind, amount or "?",
						API.IsUsable(item.itemID) and "yes" or "NO",
						requiredLevel or 0, item.count or 0,
						points > 0 and (" | buffs " .. points) or "",
						item.locked and " | LOCKED" or "")
				end, label .. ": an item that could not be read"))
			end
		end
	end
	if seen == 0 then Say("no Food & Drink item in any bag") end

	local function Best(kind)
		if not ns.Consume then return "no Consume module" end
		local ok, pick = pcall(ns.Consume.Find, ns.Consume, kind)
		if not ok then return "ERROR " .. tostring(pick) end
		if not pick then return "none" end
		return ("bag %d slot %d, %s"):format(pick.bag, pick.slot, tostring(pick.amount))
	end
	Say(Asked(function()
		return "best food: " .. Best("food") .. " | best water: " .. Best("water")
	end, "best food and water: could not be read"))
	return lines
end

-- The report in chat, for when the window cannot be shown.
function BestBite:Debug()
	for _, line in ipairs(BestBite:DebugLines()) do
		DEFAULT_CHAT_FRAME:AddMessage("|cff7fd4ffBestBite|r debug: " .. line)
	end
end

-- For macros and /run: BestBite.Eat(), BestBite.Drink(), BestBite.Consume().
function BestBite.Eat()
	return BestBite:Advise("food")
end

function BestBite.Drink()
	return BestBite:Advise("water")
end

function BestBite.Consume()
	return BestBite:Advise("consume")
end

local function RunCommand(message)
	local command = tostring(message or ""):match("^%s*(.-)%s*$"):lower()
	if command == "food" or command == "eat" then
		BestBite:Advise("food")
	elseif command == "water" or command == "drink" then
		BestBite:Advise("water")
	elseif command == "consume" or command == "both" then
		BestBite:Advise("consume")
	elseif command == "reset" then
		wipe(BestBite:Db().learned)
		BestBite:Print("Forgot the items it had learned.")
	elseif command == "icons" then
		local db = BestBite:Db()
		db.showIcons = db.showIcons == false
		BestBite:Print("Action bar icons: " .. (db.showIcons and "on" or "off"))
		if ns.Icons then
			if db.showIcons then
				ns.Icons:Request(0)
			else
				ns.Icons:Restore()
			end
		end
	elseif command == "move" then
		if ns.Buttons then ns.Buttons:SetMoving(not ns.Buttons.moving) end
	elseif command == "macroicon" then
		local db = BestBite:Db()
		db.writeMacroIcons = not db.writeMacroIcons
		BestBite:Print("Rewriting the macro's own icon: " .. (db.writeMacroIcons and "on" or "off"))
		if db.writeMacroIcons and ns.Icons then ns.Icons:Request(0) end
	elseif command == "vendor" then
		local lines = ns.Vendor and ns.Vendor:Lines() or { "Vendor.lua did not load" }
		for _, line in ipairs(lines) do BestBite:Print("vendor: " .. line) end
	elseif command == "debug" then
		if not (ns.Window and ns.Window:ShowDebug()) then BestBite:Debug() end
	else
		if not (ns.Window and ns.Window:Toggle()) then BestBite:Help() end
	end
end

-- A command that throws says so in chat: a client call that disagrees with this
-- addon must not leave a macro looking like it did nothing.
local function HandleCommand(message)
	local ok, err = pcall(RunCommand, message)
	if not ok then
		BestBite:Print("error: " .. tostring(err))
	end
end

SLASH_BESTBITE1 = "/bb"
SLASH_BESTBITE2 = "/bestbite"
SlashCmdList.BESTBITE = HandleCommand

-- The window's own buttons run the same commands as the slash line, through the same
-- guard that turns a thrown error into a line in chat.
ns.RunCommand = HandleCommand
