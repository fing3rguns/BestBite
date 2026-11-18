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

-- A purchase is taken by the client at once but put in the bags a moment later, so what has
-- been bought and not yet landed is remembered per item; MERCHANT_UPDATE re-reads the bags,
-- and without that record it would buy the same shortfall again. One that has not landed by
-- PENDING_WAIT was refused by the client and is forgotten.
local PENDING_WAIT = 5
local LAND_WAIT = 1
local pending = {}
Vendor.pending = pending

function Vendor:Db()
	local db = BestBite:Db()
	return db.vendor
end

-- The window's status line counts the bags, so it is stale as soon as a purchase lands. The
-- window may not be built, or may be broken, which is no reason to fail a purchase.
function Vendor:RefreshWindow()
	local window = ns.Window
	if not (window and window.Refresh) then return end
	pcall(window.Refresh, window)
end

-- The items bought and not in the bags yet: a refused purchase never lands, so its record
-- is dropped rather than holding up the next attempt.
function Vendor:OnTheWay(itemID)
	local record = pending[itemID]
	if not record then return 0 end
	local left = record.before + record.items - API.CountInBags(itemID)
	if left <= 0 or (GetTime() or 0) - record.at > PENDING_WAIT then
		pending[itemID] = nil
		return 0
	end
	-- Items spent while the purchase was in flight are not a reason to count more on their
	-- way than were bought.
	return math.min(left, record.items)
end

-- What `items` of a purchase cost: `price` is the cost of one purchase of `stack` items,
-- so the items that landed are worth their share of it.
local function Cost(record, items)
	if record.stack < 1 or record.price <= 0 then return 0 end
	return math.floor(items * record.price / record.stack + 0.5)
end

local function Coins(amount)
	if GetCoinTextureString then return GetCoinTextureString(amount) end
	return ("%dc"):format(amount)
end

-- Says what has landed of a purchase, once per landing and for what those items cost, and
-- forgets the record once all of it is in the bags. A refused purchase never lands, so it
-- is never reported as bought.
function Vendor:Land(itemID)
	local record = pending[itemID]
	if not record then return end

	local landed = math.min(API.CountInBags(itemID) - record.before, record.items)
	if landed < 0 then landed = 0 end
	local fresh = landed - record.reported
	if fresh > 0 then
		local already = record.reported
		record.reported = landed
		local said = ("bought %d %s for %s"):format(fresh, record.name or "item",
			Coins(Cost(record, landed) - Cost(record, already)))
		if #record.notes > 0 then said = said .. ": " .. table.concat(record.notes, ", ") end
		BestBite:Print(said)
		self:RefreshWindow()
	end

	if record.reported >= record.items or (GetTime() or 0) - record.at > PENDING_WAIT then
		pending[itemID] = nil
	end
end

-- Looks for the purchase in the bags now and once more a moment later: the client does not
-- put bought items there at once, and a purchase that arrives without a MERCHANT_UPDATE of
-- its own would otherwise never be reported.
function Vendor:Settle(itemID)
	if not pending[itemID] then return end
	self:Land(itemID)
	if pending[itemID] and C_Timer and C_Timer.After then
		C_Timer.After(LAND_WAIT, function() Vendor:Land(itemID) end)
	end
end

-- Every purchase that may have landed since it was made, whatever the bags are short of now:
-- a landing buys nothing, it only has to be reported.
function Vendor:ReportLanded()
	for itemID in pairs(pending) do
		self:Land(itemID)
	end
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

-- itemID, price, stack size and how many items the vendor has, for one of its items. The
-- price is what one purchase of `stack` items costs, and a negative count is the client's
-- word for unlimited stock. The client answers either a table (C_MerchantFrame) or a list
-- (GetMerchantItemInfo); both are read.
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

-- The client reports a negative count for a vendor with unlimited stock, so only zero
-- means sold out.
local function Sold(available)
	return (available or 0) ~= 0
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
		if itemID and Sold(available) and API.IsFoodDrink(itemID) and API.IsUsable(itemID) then
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

-- Buys as much of the pick as the shortfall asks for, never more than the vendor holds, the
-- money allows, or is already on its way from an earlier purchase. Purchases are split to
-- the merchant's per-purchase limit, since one call for the whole shortfall is more than the
-- client sells at once. Returns the items bought (the client confirms them later, in the
-- bags), what is still missing, and a reason when it could not finish.
function Vendor:Buy(pick, shortfall)
	local before = API.CountInBags(pick.itemID)

	-- A purchase is `stack` items for `price`, so this is what a single item costs.
	local stack = math.max(1, pick.stack or 1)
	local price = math.max(0, pick.price or 0)
	local unit = price / stack

	local wanted = shortfall - self:OnTheWay(pick.itemID)
	if wanted < 1 then return 0, shortfall end

	local available = pick.available or 0
	if available >= 0 then
		wanted = math.min(wanted, available)
		if wanted < 1 then return 0, shortfall, "the vendor has none left" end
	end

	local shortOfMoney = false
	if unit > 0 then
		local money = GetMoney and GetMoney() or 0
		local affordable = math.floor(money / unit)
		if affordable < 1 then return 0, shortfall, "not enough money" end
		if affordable < wanted then
			wanted, shortOfMoney = affordable, true
		end
	end

	local maxStack = GetMerchantItemMaxStack and GetMerchantItemMaxStack(pick.index) or stack
	if type(maxStack) ~= "number" or maxStack < 1 then maxStack = stack end
	local per = maxStack >= stack and (maxStack - maxStack % stack) or maxStack
	if per < 1 then per = stack end

	local left = wanted
	while left > 0 do
		local items = math.min(left, per)
		local ok = pcall(BuyMerchantItem, pick.index, items)
		if not ok then break end
		left = left - items
	end

	local bought = wanted - left
	if bought < 1 then return 0, shortfall, "the client refused the purchase" end

	local record = pending[pick.itemID]
	if record then
		record.items, record.at = record.items + bought, GetTime() or 0
	else
		record = { before = before, items = bought, at = GetTime() or 0, reported = 0, notes = {} }
		pending[pick.itemID] = record
	end
	record.name = (API.ItemInfo(pick.itemID)) or record.name or "item"
	record.stack, record.price = stack, price

	local rest = math.max(0, shortfall - bought)
	local reason
	if rest > 0 then
		reason = shortOfMoney and "not enough money" or "the vendor had no more"
	end
	return bought, rest, reason
end

-- One merchant visit: top up whichever kinds are short, then say what happened in one line.
-- A kind the vendor does not sell is only mentioned when someone asked for the purchase
-- (the Buy now button); an automatic visit at every merchant stays quiet about absences.
function Vendor:Restock(explicit)
	if InCombatLockdown and InCombatLockdown() then return false, "in combat" end
	if not (explicit or self:Db().on) then return false end
	if not (GetMerchantNumItems and GetMerchantNumItems() > 0) then return false, "no merchant" end

	-- A purchase made a moment ago may be in the bags by now; saying so costs nothing and
	-- happens before anything else the visit does.
	self:ReportLanded()

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
					-- The purchase is reported once it lands, so what is worth saying about it
					-- waits with it rather than in a line of its own.
					local record = pending[pick.itemID]
					if record then
						if left > 0 and reason then
							record.notes[#record.notes + 1] = reason .. ", " .. left .. " short"
						end
						if fellBack then record.notes[#record.notes + 1] = "it was below your level" end
					end
					self:Settle(pick.itemID)
				elseif reason then
					said[#said + 1] = reason
				end
			elseif explicit then
				said[#said + 1] = "nothing at this vendor is " .. kind
			end
		end
	end

	if #said > 0 then BestBite:Print(table.concat(said, "; ")) end
	if didSomething then self:RefreshWindow() end
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
events:RegisterEvent("PLAYER_MONEY")
events:SetScript("OnEvent", function(_, event)
	-- Money changing is what the window's counts are drawn against, and no reason to buy.
	if event == "PLAYER_MONEY" then
		Vendor:RefreshWindow()
		return
	end
	-- Opening a merchant starts a new visit, so a weak item may be bought once again.
	if event == "MERCHANT_SHOW" then Vendor.fallbackDone = false end
	Vendor:Request()
end)
