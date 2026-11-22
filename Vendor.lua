-- Restocking at vendors: when a merchant is open and the bags are short of food or water, buy
-- items this character can use to a target, choosing them with the same ordering the two
-- buttons use. Off unless switched on (Window.lua), and silent whenever Polestar's own
-- Restock is configured for food or water, since it would buy on top of ours.
--
-- An item counts as stock, and is the only kind bought, when its own level requirement is one
-- this character already meets: anything you could use right now.

local ADDON, ns = ...

local BestBite = ns.BestBite
local API = ns.API
local Detect = ns.Detect
local Consume = ns.Consume

local Vendor = {}
ns.Vendor = Vendor

-- The target's range.
Vendor.TARGET_MIN = 5
Vendor.TARGET_MAX = 100
Vendor.TARGET_STEP = 5

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
	amount = math.floor((tonumber(amount) or 0) + 0.5)
	if amount < 0 then amount = 0 end
	local gold = math.floor(amount / 10000)
	local silver = math.floor(amount / 100) % 100
	local copper = amount % 100
	local parts = {}
	local function Part(count, icon)
		parts[#parts + 1] = count .. "|TInterface\\MoneyFrame\\UI-" .. icon .. "Icon:0:0|t"
	end
	if gold > 0 then Part(gold, "Gold") end
	if silver > 0 or gold > 0 then Part(silver, "Silver") end
	Part(copper, "Copper")
	return table.concat(parts, " ")
end
Vendor.Coins = Coins

-- What a visit did is said above the character's head rather than in chat, where a busy
-- channel swallows it. Two lines at most, one per kind, and it goes away on its own.
local NOTICE_LIFE = 5
local NOTICE_MAX = 3       -- a heading and the two kinds, at most
local NOTICE_PAD = 16      -- room inside the bubble, between the text and its edge
local NOTICE_GAP = 2       -- between the two lines
local NOTICE_TEXT_MAX = 560 -- wider text wraps rather than spilling out of the bubble
local notice, noticeLines, noticeUntil, noticeTitle = nil, {}, 0, false
-- Held back while a merchant is open: the shop window covers the character, so the bubble is
-- shown once that window is closed rather than behind it.
local noticeHeld = false

local function LineHeight(line)
	if line.GetStringHeight then
		local ok, height = pcall(line.GetStringHeight, line)
		if ok and height and height > 0 then return height end
	end
	return 18
end

local function LineWidth(line)
	if line.GetStringWidth then
		local ok, width = pcall(line.GetStringWidth, line)
		if ok and width then return width end
	end
	return 0
end

local function BuildNotice()
	-- This client needs the backdrop mixin on a frame before it will draw one, which is the
	-- same guard Polestar uses; without it SetBackdrop is there but paints nothing.
	local frame = CreateFrame("Frame", "BestBiteNotice", UIParent,
		BackdropTemplateMixin and "BackdropTemplate" or nil)
	frame:SetPoint("CENTER", UIParent, "CENTER", 0, 132)
	frame:SetSize(360, 76)
	frame:SetFrameStrata("HIGH")
	frame:SetFrameLevel(50)
	-- A dark panel with the client's tooltip border, so the line stays readable over whatever
	-- is behind it. Drawn here and never sent anywhere: no other player sees it.
	if frame.SetBackdrop then
		pcall(frame.SetBackdrop, frame, {
			bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true, tileSize = 16, edgeSize = 16,
			insets = { left = 5, right = 5, top = 5, bottom = 5 },
		})
		if frame.SetBackdropColor then frame:SetBackdropColor(0, 0, 0, 0.8) end
		if frame.SetBackdropBorderColor then frame:SetBackdropBorderColor(1, 0.82, 0, 0.9) end
	else
		-- A client without backdrop support still gets a readable ground under the text.
		local ground = frame:CreateTexture(nil, "BACKGROUND")
		ground:SetAllPoints(frame)
		ground:SetTexture(0, 0, 0, 0.8)
	end
	frame.lines = {}
	for index = 1, 3 do
		local line = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
		line:SetJustifyH("CENTER")
		line:SetTextColor(1, 1, 1)
		line:SetText("")
		if index == 1 then
			line:SetPoint("TOP", frame, "TOP", 0, -NOTICE_PAD)
		else
			line:SetPoint("TOP", frame.lines[index - 1], "BOTTOM", 0, -NOTICE_GAP)
		end
		frame.lines[index] = line
	end
	frame:SetScript("OnUpdate", function(self)
		if (GetTime() or 0) >= noticeUntil then self:Hide() end
	end)
	return frame
end

-- Sizes the bubble to the text it holds, so the lines sit inside the art rather than over
-- its edges.
local function FitNotice()
	local shown, widest, tallest = {}, 0, 0
	for _, line in ipairs(notice.lines) do
		local text = line:GetText() or ""
		if text ~= "" then
			shown[#shown + 1] = line
			widest = math.max(widest, LineWidth(line))
		end
	end
	for _, line in ipairs(notice.lines) do
		if LineWidth(line) > NOTICE_TEXT_MAX then line:SetWidth(NOTICE_TEXT_MAX) end
	end
	widest = math.min(widest, NOTICE_TEXT_MAX)
	for _, line in ipairs(shown) do tallest = tallest + LineHeight(line) end
	tallest = tallest + math.max(0, #shown - 1) * NOTICE_GAP

	notice:SetSize(math.max(140, widest + NOTICE_PAD * 2 + 8), math.max(56, tallest + NOTICE_PAD * 2))
end

-- A notice line is dropped when the notice has been away long enough to be a new one. While
-- a merchant is open the notice is waiting to be shown, so its lines are kept.
local function Reopen()
	local now = GetTime and GetTime() or 0
	if not noticeHeld and now >= noticeUntil then
		noticeLines, noticeTitle = {}, false
	end
end

function Vendor:ShowNotice()
	if not notice then notice = BuildNotice() end
	for index, line in ipairs(notice.lines) do
		line:SetWidth(0)
		line:SetText(noticeLines[index] or "")
	end
	FitNotice()
	if GetMerchantNumItems and GetMerchantNumItems() > 0 then
		-- The shop window is over the character: hold the bubble until it closes.
		noticeHeld = true
		return
	end
	noticeHeld = false
	noticeUntil = (GetTime and GetTime() or 0) + NOTICE_LIFE
	notice:Show()
end

-- Shown when the merchant window closes, if a visit had something to say while it was open.
function Vendor:FlushNotice()
	if not noticeHeld then return end
	noticeHeld = false
	if not notice or #noticeLines == 0 then return end
	noticeUntil = (GetTime and GetTime() or 0) + NOTICE_LIFE
	notice:Show()
end

-- One line, for whatever a visit has to say that is not a restock: why it bought nothing.
function Vendor:Notice(text)
	if not text or text == "" then return end
	Reopen()
	noticeLines[#noticeLines + 1] = text
	while #noticeLines > NOTICE_MAX do table.remove(noticeLines, 1) end
	self:ShowNotice()
end

-- A restock's own line. "Restocked" heads it once, however many items land, rather than
-- being repeated on every line.
function Vendor:NoticeRestock(text)
	if not text or text == "" then return end
	Reopen()
	if not noticeTitle then
		noticeTitle = true
		table.insert(noticeLines, 1, "Restocked")
	end
	noticeLines[#noticeLines + 1] = text
	while #noticeLines > NOTICE_MAX do table.remove(noticeLines, 2) end
	self:ShowNotice()
end

-- A new visit starts with a clean notice, and so does a test.
function Vendor:ClearNotice()
	noticeLines, noticeTitle = {}, false
	noticeUntil, noticeHeld = 0, false
	if notice then
		for _, line in ipairs(notice.lines) do line:SetText("") end
		notice:Hide()
	end
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
		local said = ("%d %s for %s"):format(fresh, record.name or "item",
			Coins(Cost(record, landed) - Cost(record, already)))
		if #record.notes > 0 then said = said .. ": " .. table.concat(record.notes, ", ") end
		self:NoticeRestock(said)
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

-- Whether an item can be used at this level: its own requirement is one you already meet. That
-- is what counts as stock and what may be restocked. Food and drink have no class gate, and
-- the client's "is it usable" lookup is not asked, since a client that only half answers it
-- empties the vendor.
function Vendor:LevelAppropriate(itemID, level)
	if not itemID then return false end
	local _, _, requiredLevel = API.ItemInfo(itemID)
	if type(requiredLevel) ~= "number" then return true end
	return requiredLevel <= (level or 0)
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

-- A vendor's stock, as the client counts it: items, with -1 for unlimited. A client that
-- answers no availability at all is taken as unlimited rather than sold out, so a field this
-- client does not fill in cannot make every item look gone.
local function Available(count)
	return tonumber(count) or -1
end

-- itemID, price, stack size and how many items the vendor has, for one of its items. The
-- price is what one purchase of `stack` items costs. The tuple GetMerchantItemInfo is read
-- first because its fields are fixed; C_MerchantFrame's table is a client's own shape and is
-- read for the item id and as the fallback.
function Vendor:Merchant(index)
	local itemID = GetMerchantItemID and GetMerchantItemID(index)
	if GetMerchantItemInfo then
		local ok, _, _, price, stack, available = pcall(GetMerchantItemInfo, index)
		if ok and (price ~= nil or stack ~= nil or available ~= nil) then
			return itemID, tonumber(price) or 0, tonumber(stack) or 1, Available(available)
		end
	end
	if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
		local ok, info = pcall(C_MerchantFrame.GetItemInfo, index)
		if ok and type(info) == "table" then
			local stack = info.stackCount or info.quantity or 1
			return info.itemID or itemID, tonumber(info.price) or 0, tonumber(stack) or 1,
				Available(info.numAvailable or info.totalAvailable)
		end
	end
	return nil
end

-- The client reports a negative count for a vendor with unlimited stock, so only zero
-- means sold out.
local function Sold(available)
	return (available or 0) ~= 0
end

-- The best item of a kind this vendor sells that this character can use, ranked by the same
-- ordering the buttons use, so what is bought is what would be used. Nil when it sells none.
function Vendor:Pick(kind)
	local level = UnitLevel("player") or 0
	local preferBuffs = Consume:PreferBuffs(kind)
	local best

	for index = 1, (GetMerchantNumItems and GetMerchantNumItems() or 0) do
		local itemID, price, stack, available = self:Merchant(index)
		if itemID and Sold(available) and API.IsFoodDrink(itemID) then
			local itemKind, amount, buffs = Detect:ScanMerchant(index)
			if itemKind == kind and self:LevelAppropriate(itemID, level) then
				local name, itemLevel = API.ItemInfo(itemID)
				local candidate = {
					index = index, itemID = itemID, price = price, stack = stack,
					available = available, amount = amount or 0,
					points = Detect:Points(buffs), itemLevel = itemLevel or 0,
					count = available,
				}
				if Consume:Better(candidate, best, preferBuffs) then best = candidate end
			end
		end
	end

	return best
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

-- Whether this vendor sells anything of a kind, whether it sells food or water it could not
-- read, and whether any of that kind is one this character can use: a purchase that found
-- nothing has to be told apart from a vendor that sells none, or one selling only food above
-- this level.
function Vendor:Stock(kind, level)
	local found, unread, usable = false, false, false
	for index = 1, (GetMerchantNumItems and GetMerchantNumItems() or 0) do
		local itemID = self:Merchant(index)
		if itemID and API.IsFoodDrink(itemID) then
			local itemKind = Detect:ScanMerchant(index)
			if itemKind == kind then
				found = true
				if self:LevelAppropriate(itemID, level or 0) then usable = true end
			elseif itemKind == nil then
				unread = true
			end
		end
	end
	return found, unread, usable
end

-- One merchant visit: top up whichever kinds are short, then say what happened in one line.
-- A kind the vendor does not sell is only mentioned when someone asked for the purchase
-- (the Buy now button); an automatic visit at every merchant stays quiet about absences.
function Vendor:Restock(explicit)
	if InCombatLockdown and InCombatLockdown() then return false, "in combat" end
	if not (explicit or self:Db().on) then return false end
	if not (GetMerchantNumItems and GetMerchantNumItems() > 0) then
		if explicit then BestBite:Print("no vendor is open") end
		return false, "no merchant"
	end

	-- A purchase made a moment ago may be in the bags by now; saying so costs nothing and
	-- happens before anything else the visit does.
	self:ReportLanded()

	local stood, why = self:StandDown()
	if stood then
		BestBite:Print(why .. ", so BestBite leaves it to Polestar.")
		return false, why
	end

	local said, didSomething = {}, false
	for _, kind in ipairs({ "food", "water" }) do
		local shortfall = self:Shortfall(kind)
		if shortfall > 0 then
			local pick = self:Pick(kind)
			if pick then
				local bought, left, reason = self:Buy(pick, shortfall)
				if bought > 0 then
					didSomething = true
					-- The purchase is reported once it lands, so what is worth saying about it
					-- waits with it rather than in a line of its own.
					local record = pending[pick.itemID]
					if record and left > 0 and reason then
						record.notes[#record.notes + 1] = reason .. ", " .. left .. " short"
					end
					self:Settle(pick.itemID)
				elseif reason then
					said[#said + 1] = reason
				end
			elseif explicit then
				said[#said + 1] = "nothing at this vendor is " .. kind
			else
				-- An automatic visit that buys nothing has to say why, or a read that fails
				-- in the client looks exactly like a feature that does nothing.
				local found, unread, usable = self:Stock(kind, UnitLevel("player") or 0)
				if found and not usable then
					said[#said + 1] = "the " .. kind .. " here needs a higher level"
				elseif unread then
					said[#said + 1] = "it could not read what this vendor sells for " .. kind
				elseif found then
					said[#said + 1] = "no " .. kind .. " here it could buy"
				end
			end
		end
	end

	if #said > 0 then
		for _, line in ipairs(said) do self:Notice(line) end
	end
	if didSomething then self:RefreshWindow() end
	return didSomething
end

-- What restocking sees right now, line by line, for `/bb vendor`: the setting as it will be
-- saved, the Polestar gate, the bags, and every item this vendor sells with the kind that
-- was read for it. A feature that does nothing at a vendor is otherwise indistinguishable
-- from a read that came back empty.
function Vendor:Lines()
	local lines = {}
	local db = self:Db()
	local target = db.target or self.TARGET_MIN
	local level = UnitLevel("player") or 0
	lines[#lines + 1] = ("restock %s, keep %d, level %d"):format(db.on and "on" or "off", target, level)

	local saved = type(BestBiteDB) == "table" and type(BestBiteDB.vendor) == "table"
	lines[#lines + 1] = "saved in BestBiteDB: " .. (saved and "yes" or "no")

	local stood, why = self:StandDown()
	lines[#lines + 1] = stood and ("Polestar keeps it: " .. tostring(why))
		or "Polestar does not keep food or water"

	local merchant = GetMerchantNumItems and GetMerchantNumItems() or 0
	lines[#lines + 1] = ("vendor: %d items, money %s"):format(merchant, Coins(GetMoney and GetMoney() or 0))
	if merchant < 1 then
		lines[#lines + 1] = "no vendor open"
		return lines
	end

	for _, kind in ipairs({ "food", "water" }) do
		local shortfall, have = self:Shortfall(kind)
		lines[#lines + 1] = ("%s: %d carried, %d short"):format(kind, have, shortfall)
		local pick = self:Pick(kind)
		if pick then
			lines[#lines + 1] = ("  picks %s (%d): %d per %d, %d available"):format(
				(API.ItemInfo(pick.itemID)) or ("item " .. tostring(pick.itemID)), pick.itemID,
				pick.price or 0, pick.stack or 1, pick.available or 0)
		else
			lines[#lines + 1] = "  nothing of that kind here it can use"
		end
	end

	for index = 1, merchant do
		local itemID, price, stack, available = self:Merchant(index)
		if itemID then
			local _, _, required = API.ItemInfo(itemID)
			local note = ""
			if required and required > level then note = ", needs level " .. required end
			lines[#lines + 1] = ("[%d] %s (%d) %s: %d per %d, %d available%s"):format(index,
				(API.ItemInfo(itemID)) or "unread", itemID, Detect:ScanMerchant(index) or "not food or water",
				price or 0, stack or 1, available or 0, note)
		end
	end

	-- Why a kind came back with nothing to buy, counted the way the buy does it.
	for _, kind in ipairs({ "food", "water" }) do
		local readable, soldOut, tooHigh = 0, 0, 0
		for index = 1, merchant do
			local itemID, _, _, available = self:Merchant(index)
			if itemID and Detect:ScanMerchant(index) == kind then
				readable = readable + 1
				local _, _, required = API.ItemInfo(itemID)
				if not Sold(available) then soldOut = soldOut + 1 end
				if required and required > level then tooHigh = tooHigh + 1 end
			end
		end
		lines[#lines + 1] = ("%s: %d readable, %d sold out, %d need a higher level"):format(
			kind, readable, soldOut, tooHigh)
	end
	return lines
end

-- MERCHANT_UPDATE arrives in bursts: one visit is one attempt. A merchant whose goods are
-- not readable yet (the client fills them in shortly after the frame opens) is tried again,
-- so a slow open is not mistaken for a vendor with nothing to sell.
local scheduled = false
function Vendor:Request(attempt)
	attempt = attempt or 1
	if scheduled then return end
	scheduled = true
	local function run()
		scheduled = false
		local ok, err = pcall(Vendor.Restock, Vendor, false)
		if not ok then
			if not Vendor.warned then
				Vendor.warned = true
				BestBite:Print("could not restock from this vendor: " .. tostring(err))
			end
			return
		end
		if attempt < 3 and GetMerchantNumItems and GetMerchantNumItems() == 0 and C_Timer and C_Timer.After then
			C_Timer.After(0.5, function() Vendor:Request(attempt + 1) end)
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
events:RegisterEvent("MERCHANT_CLOSED")
events:RegisterEvent("PLAYER_MONEY")
events:SetScript("OnEvent", function(_, event)
	-- Money changing is what the window's counts are drawn against, and no reason to buy.
	if event == "PLAYER_MONEY" then
		Vendor:RefreshWindow()
		return
	end
	-- Closing the merchant is when a visit's bubble is shown, since the window was over the
	-- character while it bought.
	if event == "MERCHANT_CLOSED" then
		Vendor:FlushNotice()
		return
	end
	-- Opening a merchant starts a new visit with a clean notice.
	if event == "MERCHANT_SHOW" then Vendor:ClearNotice() end
	Vendor:Request()
end)
