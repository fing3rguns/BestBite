-- Picks the best item of a kind out of the bags. "Best" is the most it restores:
-- food and water are a straight trade of one item for a bar, so the largest amount
-- in the bags is the one worth spending. Choosing is all this file does: the game
-- blocks an addon from using the item, so a secure button does that (Buttons.lua).

local ADDON, ns = ...

local API = ns.API
local Detect = ns.Detect

local Consume = {}
ns.Consume = Consume

-- The best item of `kind` the character can use right now:
-- { bag, slot, itemID, name, amount, points }, or nil when the bags hold none.
-- Food that buffs a stat counts for more than food that does not, however much the
-- plain one restores: a Well Fed bonus outlasts one meal's worth of health.
function Consume:Find(kind)
	local level = UnitLevel("player")
	local now = GetTime()
	local best, bestPoints, bestAmount, bestItemLevel, bestCount

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
						local points = Detect:Points(buffs)
						amount, itemLevel = amount or 0, itemLevel or 0
						local better
						if not best then
							better = true
						elseif (points > 0) ~= (bestPoints > 0) then
							better = points > 0
						elseif points ~= bestPoints then
							better = points > bestPoints
						elseif amount ~= bestAmount then
							better = amount > bestAmount
						elseif itemLevel ~= bestItemLevel then
							better = itemLevel > bestItemLevel
						else
							better = item.count > bestCount
						end
						if better then
							best = { bag = bag, slot = slot, itemID = item.itemID, name = name,
								amount = amount, points = points }
							bestPoints, bestAmount, bestItemLevel, bestCount = points, amount, itemLevel, item.count
						end
					end
				end
			end
		end
	end

	return best
end
