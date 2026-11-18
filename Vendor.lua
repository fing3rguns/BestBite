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
local Consume = ns.Consume

local Vendor = {}
ns.Vendor = Vendor

-- Levels below yours that still count as good for you, and the target's range.
Vendor.BAND = 10
Vendor.TARGET_MIN = 5
Vendor.TARGET_MAX = 100
Vendor.TARGET_STEP = 5

-- Set once a weak item has been bought this visit, so MERCHANT_UPDATE cannot buy it again.
Vendor.fallbackDone = false

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

-- How much of a kind the bags hold that is worth counting. `noLearn` counts without
-- remembering the items it read, for the window's display, which must have no side effects.
function Vendor:Count(kind, level, noLearn)
	local total = 0
	for bag = 0, API.NumBags() do
		for slot = 1, API.NumSlots(bag) do
			local item = API.SlotItem(bag, slot)
			if item and not item.locked and item.count > 0 and API.IsFoodDrink(item.itemID)
				and self:LevelAppropriate(item.itemID, level) then
				if Detect:Describe(bag, slot, item.itemID, noLearn) == kind then
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

-- itemID, price, stack size and how many the vendor has, for one of its items. The client
-- answers either a table (C_MerchantFrame) or a list (GetMerchantItemInfo); both are read.
function Vendor:Merchant(index)
	if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
		local ok, info = pcall(C_MerchantFrame.GetItemInfo, index)
		if ok and type(info) == "table" then
			local itemID = info.itemID or (GetMerchantItemID and GetMerchantItemID(index))
			local stack = info.stackCount or info.quantity or 1
			return itemID, tonumber(info.price) or 0, tonumber(stack) or 1,
				tonumber(info.numAvailable or info.totalAvailable) or 0
		end
	end
	if GetMerchantItemInfo then
		local ok, _, _, price, stack, available = pcall(GetMerchantItemInfo, index)
		if ok then
			return GetMerchantItemID and GetMerchantItemID(index), tonumber(price) or 0,
				tonumber(stack) or 1, tonumber(available) or 0
		end
	end
	return nil
end

-- The best item of a kind this vendor sells, ranked by the same ordering the buttons use,
-- so what is bought is what would be used. Items good for this level win; when it sells
-- none of those, the best usable one is offered rather than nothing, and said to be a
-- fallback.
function Vendor:Pick(kind)
	local level = UnitLevel("player") or 0
	local preferBuffs = Consume:PreferBuffs(kind)
	local best, fallback

	for index = 1, (GetMerchantNumItems and GetMerchantNumItems() or 0) do
		local itemID, price, stack, available = self:Merchant(index)
		if itemID and available > 0 and API.IsFoodDrink(itemID) and API.IsUsable(itemID) then
			local itemKind, amount, buffs = Detect:ScanMerchant(index)
			if itemKind == kind then
				local _, itemLevel = API.ItemInfo(itemID)
				local candidate = {
					index = index, itemID = itemID, price = price, stack = stack,
					available = available, amount = amount or 0,
					points = Detect:Points(buffs), itemLevel = itemLevel or 0,
					count = available,
				}
				if self:LevelAppropriate(itemID, level) then
					if Consume:Better(candidate, best, preferBuffs) then best = candidate end
				elseif Consume:Better(candidate, fallback, preferBuffs) then
					fallback = candidate
				end
			end
		end
	end

	if best then return best, false end
	if fallback then return fallback, true end
	return nil, false
end

-- Buys as much of the pick as the shortfall asks for, never more than the vendor holds or
-- the money allows. Returns what was bought, what is still missing, and a reason when it
-- could not finish.
function Vendor:Buy(pick, shortfall)
	local wanted = math.min(shortfall, pick.available or 0)
	if wanted < 1 then return 0, shortfall, "the vendor has none left" end

	local money = GetMoney and GetMoney() or 0
	local price = math.max(1, pick.price or 0)
	local affordable = math.min(wanted, math.floor(money / price))
	if affordable < 1 then
		return 0, shortfall, "not enough money"
	end

	local ok = pcall(BuyMerchantItem, pick.index, affordable)
	if not ok then
		return 0, shortfall, "the client refused the purchase"
	end

	local left = math.max(0, shortfall - affordable)
	local reason
	if left > 0 then
		reason = affordable < wanted and "not enough money" or "the vendor had no more"
	end
	return affordable, left, reason
end

-- One merchant visit: top up whichever kinds are short, then say what happened in one line.
-- A kind the vendor does not sell is only mentioned when someone asked for the purchase
-- (the Buy now button); an automatic visit at every merchant stays quiet about absences.
function Vendor:Restock(explicit)
	if InCombatLockdown and InCombatLockdown() then return false, "in combat" end
	if not (explicit or self:Db().on) then return false end
	if not (GetMerchantNumItems and GetMerchantNumItems() > 0) then return false, "no merchant" end

	-- An explicit purchase always gets a fresh attempt at a fallback.
	if explicit then self.fallbackDone = false end

	local stood, why = self:StandDown()
	if stood then
		BestBite:Print(why .. ", so BestBite leaves it to Polestar.")
		return false, why
	end

	local said, didSomething = {}, false
	for _, kind in ipairs({ "food", "water" }) do
		local shortfall = self:Shortfall(kind)
		if shortfall > 0 then
			local pick, fellBack = self:Pick(kind)
			-- A fallback never counts towards the target, so a second pass of this visit would
			-- buy the same weak item again: one such purchase per visit is enough.
			if pick and not (fellBack and self.fallbackDone) then
				local bought, left, reason = self:Buy(pick, shortfall)
				if bought > 0 then
					didSomething = true
					if fellBack then self.fallbackDone = true end
					local name = (API.ItemInfo(pick.itemID))
					said[#said + 1] = ("bought %d %s for %s"):format(bought, tostring(name or "item"),
						GetCoinTextureString and GetCoinTextureString(bought * (pick.price or 0)) or (bought * (pick.price or 0) .. "c"))
					if left > 0 and reason then
						said[#said + 1] = reason .. ", " .. left .. " short"
					end
					if fellBack then said[#said + 1] = "it was below your level" end
				elseif reason then
					said[#said + 1] = reason
				end
			elseif explicit then
				said[#said + 1] = "nothing at this vendor is " .. kind
			end
		end
	end

	if #said > 0 then BestBite:Print(table.concat(said, "; ")) end
	return didSomething
end

-- MERCHANT_UPDATE arrives in bursts: one visit is one attempt.
local scheduled = false
function Vendor:Request()
	if scheduled then return end
	scheduled = true
	local function run()
		scheduled = false
		local ok, err = pcall(Vendor.Restock, Vendor, false)
		if not ok and not Vendor.warned then
			Vendor.warned = true
			BestBite:Print("could not restock from this vendor: " .. tostring(err))
		end
	end
	if C_Timer and C_Timer.After then
		C_Timer.After(0.2, run)
	else
		run()
	end
end

local events = CreateFrame("Frame")
events:RegisterEvent("MERCHANT_SHOW")
events:RegisterEvent("MERCHANT_UPDATE")
events:SetScript("OnEvent", function(_, event)
	-- Opening a merchant starts a new visit, so a weak item may be bought once again.
	if event == "MERCHANT_SHOW" then Vendor.fallbackDone = false end
	Vendor:Request()
end)
