-- Reads what an item refills, and how much, from its own tooltip. The client
-- reports one "Food & Drink" subclass for food and water alike, so the tooltip is
-- the only place the two differ, and the only number to rank them by.

local ADDON, ns = ...

local BestBite = ns.BestBite
local Detect = {}
ns.Detect = Detect

local tooltip = CreateFrame("GameTooltip", "BestBiteScanTooltip", nil, "GameTooltipTemplate")
tooltip:SetOwner(WorldFrame, "ANCHOR_NONE")

-- The words a tooltip uses for the bar an item refills, lower case. The client's
-- own strings lead where it has them; the translations follow, so a non-English
-- client still tells food from water.
local function Words(...)
	local list = {}
	for i = 1, select("#", ...) do
		local word = select(i, ...)
		if type(word) == "string" and word ~= "" then
			list[#list + 1] = word:lower()
		end
	end
	return list
end

local HEALTH_WORDS = Words(_G.HEALTH, "health", "gesundheit", "santé", "vie", "salud", "vida", "saúde", "здоровья", "здоровье", "生命值", "생명력")
local MANA_WORDS = Words(_G.MANA, "mana", "мана", "маны", "法力值", "法力", "마나")

local function SaysWord(text, words)
	for i = 1, #words do
		if text:find(words[i], 1, true) then return true end
	end
	return false
end

-- "food" or "water", and the amount that line restores, for one tooltip line.
local function ReadLine(text)
	local line = text:lower()
	local kind
	if SaysWord(line, MANA_WORDS) then
		kind = "water"
	elseif SaysWord(line, HEALTH_WORDS) then
		kind = "food"
	else
		return nil
	end
	return kind, tonumber(line:match("%d+"))
end

local function StripColors(text)
	return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

-- kind, amount for the item in the slot; nil, nil when its tooltip names neither.
function Detect:Scan(bag, slot)
	tooltip:SetOwner(WorldFrame, "ANCHOR_NONE")
	tooltip:ClearLines()
	tooltip:SetBagItem(bag, slot)

	local kind, amount
	for _, region in ipairs({ tooltip:GetRegions() }) do
		if region.GetObjectType and region:GetObjectType() == "FontString" then
			local text = region:GetText()
			-- The first line that names a bar wins; a buff line further down must
			-- not overwrite the amount the item restores.
			if text and not kind then
				kind, amount = ReadLine(StripColors(text))
			end
		end
	end

	tooltip:ClearLines()
	return kind, amount
end

-- kind, amount for the item, from its tooltip; else from what an earlier use
-- learned of it (BestBiteDB.learned, for an item whose tooltip no longer parses);
-- else nil, nil.
function Detect:Describe(bag, slot, itemID)
	local kind, amount = self:Scan(bag, slot)
	local db = BestBite:Db()
	local learned = db.learned[itemID]

	if kind then
		amount = amount or (learned and learned.amount)
		if amount then
			if not learned or learned.kind ~= kind or learned.amount ~= amount then
				db.learned[itemID] = { kind = kind, amount = amount }
			end
			return kind, amount
		end
		return kind
	end

	if learned then return learned.kind, learned.amount end
	return nil, nil
end
