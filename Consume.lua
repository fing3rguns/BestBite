-- Picks the best item of a kind out of the bags and uses it. "Best" is the most
-- it restores: food and water are a straight trade of one item for a bar, so the
-- largest amount in the bags is the one worth spending.

local ADDON, ns = ...

local BestBite = ns.BestBite
local API = ns.API
local Detect = ns.Detect

local Consume = {}
ns.Consume = Consume

local FOOD, WATER = "food", "water"

local function IsFull(kind)
	if kind == FOOD then
		return UnitHealth("player") >= UnitHealthMax("player")
	end
	return UnitPower("player", 0) >= UnitPowerMax("player", 0)
end

-- The best item of `kind` the character can use right now:
-- { bag, slot, name, amount }, or nil when the bags hold none.
function Consume:Find(kind)
	local level = UnitLevel("player")
	local now = GetTime()
	local best, bestAmount, bestItemLevel, bestCount

	for bag = 0, API.NumBags() do
		for slot = 1, API.NumSlots(bag) do
			local item = API.SlotItem(bag, slot)
			if item and not item.locked and item.count > 0 and API.IsFoodDrink(item.itemID) then
				local start, duration = API.Cooldown(item.itemID, bag, slot)
				local ready = not duration or duration <= 0 or (start or 0) + duration <= now
				local name, itemLevel, requiredLevel = API.ItemInfo(item.itemID)
				local levelOkay = not requiredLevel or requiredLevel <= level
				if ready and levelOkay and API.IsUsable(item.itemID) then
					local itemKind, amount = Detect:Describe(bag, slot, item.itemID)
					if itemKind == kind then
						amount, itemLevel = amount or 0, itemLevel or 0
						local better = best == nil
							or amount > bestAmount
							or (amount == bestAmount and itemLevel > bestItemLevel)
							or (amount == bestAmount and itemLevel == bestItemLevel and item.count > bestCount)
						if better then
							best = { bag = bag, slot = slot, name = name, amount = amount }
							bestAmount, bestItemLevel, bestCount = amount, itemLevel, item.count
						end
					end
				end
			end
		end
	end

	return best
end

-- Uses the best item of `kind`. true when one was used. Says why when none was,
-- except for the two expected silences: a full bar with skipping on, and the
-- quiet passes of /bb consume.
function Consume:Use(kind, quiet)
	local db = BestBite:Db()

	if kind == WATER and not API.HasMana() then
		if not quiet then BestBite:Print("You have no mana to restore.") end
		return false
	end

	if db.skipWhenFull and IsFull(kind) then return false end

	local best = self:Find(kind)
	if not best then
		if not quiet then
			BestBite:Print("No usable " .. kind .. " in your bags.")
		end
		return false
	end

	API.UseSlot(best.bag, best.slot)
	return true
end

function Consume:Eat()
	return self:Use(FOOD)
end

function Consume:Drink()
	return self:Use(WATER)
end

-- Eat and drink together, each only when its own bar needs it.
function Consume:Both()
	local db = BestBite:Db()
	local ate = self:Use(FOOD, true)
	local drank = self:Use(WATER, true)
	if ate or drank then return true end

	-- Silent when the only reason nothing happened is a bar that is already full.
	local manaFull = not API.HasMana() or IsFull(WATER)
	if db.skipWhenFull and IsFull(FOOD) and manaFull then return false end

	BestBite:Print("No usable food or water in your bags.")
	return false
end
