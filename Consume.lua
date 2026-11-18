-- Picks the best item of a kind out of the bags. "Best" is the most it restores:
-- food and water are a straight trade of one item for a bar, so the largest amount
-- in the bags is the one worth spending. Choosing is all this file does: the game
-- blocks an addon from using the item, so a secure button does that (Buttons.lua).

local ADDON, ns = ...

local API = ns.API
local Detect = ns.Detect

local Consume = {}
ns.Consume = Consume

-- Whether buff food should lead. While a food buff is banked, buff food is no longer the
-- best food: the buff is already paid for, so the biggest restore wins until it is nearly
-- spent (Buffs.lua).
function Consume:PreferBuffs(kind)
	if kind == "food" and ns.Buffs then
		local ok, banked = pcall(ns.Buffs.Banked, ns.Buffs)
		if ok then return not banked end
	end
	return true
end

-- The ordering, in one place: buff food first while it is wanted, then the most points, the
-- most restored, the higher item level, and finally the bigger stack. Shared by what the
-- bags hold and what a merchant sells, so a purchase is the item the buttons would use.
function Consume:Better(candidate, best, preferBuffs)
	if not best then return true end
	local points, bestPoints = candidate.points or 0, best.points or 0
	if (points > 0) ~= (bestPoints > 0) then
		if preferBuffs then
			return points > 0
		end
		return bestPoints > 0
	end
	if points ~= bestPoints then return points > bestPoints end

	local amount, bestAmount = candidate.amount or 0, best.amount or 0
	if amount ~= bestAmount then return amount > bestAmount end

	local itemLevel, bestItemLevel = candidate.itemLevel or 0, best.itemLevel or 0
	if itemLevel ~= bestItemLevel then return itemLevel > bestItemLevel end

	return (candidate.count or 0) > (best.count or 0)
end

-- The best item of `kind` the character can use right now:
-- { bag, slot, itemID, name, amount, points, itemLevel, count }, or nil when the bags hold
-- none.
function Consume:Find(kind)
	local level = UnitLevel("player")
	local now = GetTime()
	local preferBuffs = self:PreferBuffs(kind)
	local best

	for bag = 0, API.NumBags() do
		for slot = 1, API.NumSlots(bag) do
			local item = API.SlotItem(bag, slot)
			if item and not item.locked and item.count > 0 and API.IsFoodDrink(item.itemID) then
				local start, duration = API.Cooldown(item.itemID, bag, slot)
				local ready = not duration or duration <= 0 or (start or 0) + duration <= now
				local name, itemLevel, requiredLevel = API.ItemInfo(item.itemID)
				local levelOkay = not requiredLevel or requiredLevel <= level
				if ready and levelOkay and API.IsUsable(item.itemID) then
					local itemKind, amount, buffs = Detect:Describe(bag, slot, item.itemID)
					if itemKind == kind then
						local candidate = {
							bag = bag, slot = slot, itemID = item.itemID, name = name,
							amount = amount or 0, points = Detect:Points(buffs),
							itemLevel = itemLevel or 0, count = item.count,
						}
						if self:Better(candidate, best, preferBuffs) then best = candidate end
					end
				end
			end
		end
	end

	return best
end
