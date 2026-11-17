-- BestBite: uses the best food or water in the bags from one macro-ready command.
-- This file holds the client calls the rest of the addon shares, the saved
-- variables, and the slash commands.

local ADDON, ns = ...

local BestBite = {}
ns.BestBite = BestBite
_G.BestBite = BestBite

local C_Container, C_Item = C_Container, C_Item

-- Forever answers the C_Container and C_Item namespaces; the pre-10.0 globals are
-- read where the namespaces are missing, so the addon also runs on an older client.
local LegacySlots = _G.GetContainerNumSlots
local LegacySlotInfo = _G.GetContainerItemInfo
local LegacyUse = _G.UseContainerItem
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
		return { itemID = info.itemID, count = info.stackCount or 0, locked = info.isLocked and true or false }
	elseif LegacySlotInfo then
		local _, count, locked, _, _, _, link = LegacySlotInfo(bag, slot)
		local itemID = link and link:match("item:(%d+)")
		if not itemID then return nil end
		return { itemID = tonumber(itemID), count = count or 0, locked = locked and true or false }
	end
	return nil
end

function API.UseSlot(bag, slot)
	if C_Container and C_Container.UseContainerItem then
		C_Container.UseContainerItem(bag, slot)
	elseif LegacyUse then
		LegacyUse(bag, slot)
	end
end

-- name, itemLevel, requiredLevel. Each is nil while the client has not cached
-- the item, which does not happen for an item in the bags.
function API.ItemInfo(itemID)
	if not ItemInfoFn then return nil end
	local name, _, _, itemLevel, requiredLevel = ItemInfoFn(itemID)
	return name, itemLevel, requiredLevel
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
		return C_Item.IsUsableItem(itemID) and true or false
	end
	return true
end

-- start, duration of the item's cooldown; 0, 0 when it is ready or unknown.
function API.Cooldown(itemID, bag, slot)
	if C_Container and C_Container.GetContainerItemCooldown then
		return C_Container.GetContainerItemCooldown(itemID)
	elseif LegacyCooldown then
		return LegacyCooldown(bag, slot)
	end
	return 0, 0
end

-- Whether this character has a mana bar at all: a warrior or rogue has none.
function API.HasMana()
	return (UnitPowerMax("player", 0) or 0) > 0
end

-- The saved variables, filled in on first use so the file needs no load event.
function BestBite:Db()
	if ns.db then return ns.db end
	if type(BestBiteDB) ~= "table" then BestBiteDB = {} end
	if type(BestBiteDB.learned) ~= "table" then BestBiteDB.learned = {} end
	if BestBiteDB.skipWhenFull == nil then BestBiteDB.skipWhenFull = true end
	ns.db = BestBiteDB
	return ns.db
end

function BestBite:Print(message)
	DEFAULT_CHAT_FRAME:AddMessage("|cff7fd4ffBestBite|r: " .. message)
end

function BestBite:Help()
	local frame = DEFAULT_CHAT_FRAME
	frame:AddMessage("|cff7fd4ffBestBite|r uses the best food or water you carry.")
	frame:AddMessage("  /bb food - eat the best food in your bags")
	frame:AddMessage("  /bb water - drink the best water in your bags")
	frame:AddMessage("  /bb consume - eat and drink together")
	frame:AddMessage("  /bb full - stop eating or drinking when that bar is already full")
	frame:AddMessage("  /bb reset - forget the items it has learned")
end

-- For macros and /run: BestBite.Eat(), BestBite.Drink(), BestBite.Consume().
function BestBite.Eat()
	return ns.Consume:Eat()
end

function BestBite.Drink()
	return ns.Consume:Drink()
end

function BestBite.Consume()
	return ns.Consume:Both()
end

local function HandleCommand(message)
	local command = tostring(message or ""):match("^%s*(.-)%s*$"):lower()
	if command == "food" or command == "eat" then
		ns.Consume:Eat()
	elseif command == "water" or command == "drink" then
		ns.Consume:Drink()
	elseif command == "consume" or command == "both" then
		ns.Consume:Both()
	elseif command == "full" then
		local db = BestBite:Db()
		db.skipWhenFull = not db.skipWhenFull
		BestBite:Print("Skipping a full bar: " .. (db.skipWhenFull and "on" or "off"))
	elseif command == "reset" then
		wipe(BestBite:Db().learned)
		BestBite:Print("Forgot the items it had learned.")
	else
		BestBite:Help()
	end
end

SLASH_BESTBITE1 = "/bb"
SLASH_BESTBITE2 = "/bestbite"
SlashCmdList.BESTBITE = HandleCommand
