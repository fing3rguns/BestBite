-- Restocking at vendors: when a merchant is open and the bags are short of food or water,
-- buy level-appropriate items to a target, choosing them with the same ordering the two
-- buttons use. Off unless switched on (Window.lua), and silent whenever Polestar's own
-- Restock is configured for food or water, since it would buy on top of ours.
--
-- Items good for your level are the ones that count and the ones bought: an item whose own
-- level requirement is more than BAND below yours is left out of the count, so a bag of
-- weak leftovers cannot pass as stock.

local ADDON, ns = ...

local BestBite = ns.BestBite
local API = ns.API
local Detect = ns.Detect

local Vendor = {}
ns.Vendor = Vendor

-- Levels below yours that still count as good for you, and the target's range.
Vendor.BAND = 10
Vendor.TARGET_MIN = 5
Vendor.TARGET_MAX = 100
Vendor.TARGET_STEP = 5

function Vendor:Db()
	local db = BestBite:Db()
	return db.vendor
end

-- Polestar's Restock tops food and drink up to amounts it keeps per character. With either
-- amount set it is already doing this job, so ours would buy twice.
function Vendor:StandDown()
	local Polestar = _G.Polestar
	local restock = Polestar and Polestar.QoL and Polestar.QoL.Restock
	if not (restock and restock.Get) then return false end

	local okFood, food = pcall(restock.Get, "food")
	if not okFood then return false end
	local okDrink, drink = pcall(restock.Get, "drink")
	if not okDrink then return false end

	if (tonumber(food) or 0) > 0 or (tonumber(drink) or 0) > 0 then
		return true, "Polestar restocks food and water"
	end
	return false
end

-- Whether an item is good for this level: usable, and its own requirement no more than BAND
-- levels below. An item with no requirement (conjured food) always counts.
function Vendor:LevelAppropriate(itemID, level)
	if not itemID then return false end
	if not API.IsUsable(itemID) then return false end

	local _, _, requiredLevel = API.ItemInfo(itemID)
	if type(requiredLevel) ~= "number" then return true end
	if requiredLevel > level then return false end
	if requiredLevel > 0 and requiredLevel < level - self.BAND then return false end
	return true
end

-- How much of a kind the bags hold that is worth counting.
function Vendor:Count(kind, level)
	local total = 0
	for bag = 0, API.NumBags() do
		for slot = 1, API.NumSlots(bag) do
			local item = API.SlotItem(bag, slot)
			if item and not item.locked and item.count > 0 and API.IsFoodDrink(item.itemID)
				and self:LevelAppropriate(item.itemID, level) then
				if Detect:Describe(bag, slot, item.itemID) == kind then
					total = total + item.count
				end
			end
		end
	end
	return total
end

-- What is missing, and what was counted.
function Vendor:Shortfall(kind)
	local target = self:Db().target or self.TARGET_MIN
	local have = self:Count(kind, UnitLevel("player") or 0)
	return math.max(0, target - have), have
end
