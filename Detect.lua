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

-- A Well Fed bonus is worth having, so its points count in the ranking. Only a line
-- that reads like a buff is read, so a flavour line about a spirit of the forest
-- cannot pass itself off as Spirit.
local STAT_WORDS = Words(
	"stamina", "strength", "agility", "intellect", "spirit", "armor",
	"ausdauer", "stärke", "beweglichkeit", "intelligenz", "willenskraft",
	"endurance", "force", "agilité", "intelligence", "esprit",
	"aguante", "fuerza", "agilidad", "intelecto", "espíritu",
	"resistência", "força", "agilidade", "intelecto", "espírito",
	"выносливости", "силы", "ловкости", "интеллекта", "духа",
	"耐力", "力量", "敏捷", "智力", "精神",
	"체력", "힘", "민첩성", "지능", "정신력"
)
local BUFF_CUES = Words(
	"well fed", "increase", "erhöht", "augmente", "aumenta",
	"увеличивает", "提高", "증가"
)

local function ReadsLikeBuff(line)
	for i = 1, #BUFF_CUES do
		if line:find(BUFF_CUES[i], 1, true) then return true end
	end
	return false
end

-- The stat points a tooltip line grants, as { word = points }, or nil.
local function ReadBuffs(line)
	if not ReadsLikeBuff(line) then return nil end

	local buffs
	for i = 1, #STAT_WORDS do
		local word = STAT_WORDS[i]
		local from = 1
		while true do
			local start = line:find(word, from, true)
			if not start then break end
			local points = tonumber(line:sub(start + #word, start + #word + 24):match("%D-(%d+)"))
			if points and points > 0 then
				buffs = buffs or {}
				buffs[word] = math.max(buffs[word] or 0, points)
				break
			end
			from = start + #word
		end
	end
	return buffs
end

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

-- kind, amount and any Well Fed points for whatever the tooltip is currently showing;
-- each nil when its lines say nothing of the sort.
local function ReadGoods()
	local kind, amount, buffs
	for _, region in ipairs({ tooltip:GetRegions() }) do
		if region.GetObjectType and region:GetObjectType() == "FontString" then
			local text = region:GetText()
			if text then
				local line = StripColors(text)
				-- The first line that names a bar wins; a buff line further down must
				-- not overwrite the amount the item restores.
				if not kind then
					kind, amount = ReadLine(line)
				end
				local linebuffs = ReadBuffs(line:lower())
				if linebuffs then
					buffs = buffs or {}
					for word, points in pairs(linebuffs) do
						buffs[word] = math.max(buffs[word] or 0, points)
					end
				end
			end
		end
	end
	return kind, amount, buffs
end

-- kind, amount and any Well Fed points for the item in the slot.
function Detect:Scan(bag, slot)
	BestBite:Step("scanning an item tooltip")
	tooltip:SetOwner(WorldFrame, "ANCHOR_NONE")
	tooltip:ClearLines()
	tooltip:SetBagItem(bag, slot)
	local kind, amount, buffs = ReadGoods()
	tooltip:ClearLines()
	return kind, amount, buffs
end

-- The same for the item a merchant is selling, which only the tooltip can tell us about.
function Detect:ScanMerchant(index)
	BestBite:Step("scanning a merchant item tooltip")
	tooltip:SetOwner(WorldFrame, "ANCHOR_NONE")
	tooltip:ClearLines()
	if tooltip.SetMerchantItem then
		tooltip:SetMerchantItem(index)
	elseif tooltip.SetHyperlink and GetMerchantItemLink and GetMerchantItemLink(index) then
		tooltip:SetHyperlink(GetMerchantItemLink(index))
	end
	local kind, amount, buffs = ReadGoods()
	tooltip:ClearLines()
	return kind, amount, buffs
end

-- The total stat points a buff set grants: 0 for none.
function Detect:Points(buffs)
	local total = 0
	for _, points in pairs(buffs or {}) do
		total = total + points
	end
	return total
end

-- kind, amount, buffs for the item, from its tooltip; else from what an earlier use
-- learned of it (BestBiteDB.learned, for an item whose tooltip no longer parses);
-- else nil, nil.
function Detect:Describe(bag, slot, itemID)
	local kind, amount, buffs = self:Scan(bag, slot)
	local db = BestBite:Db()
	local learned = db.learned[itemID]

	if kind then
		amount = amount or (learned and learned.amount)
		buffs = buffs or (learned and learned.buffs)
		if amount then
			if not learned or learned.kind ~= kind or learned.amount ~= amount
				or self:Points(learned.buffs) ~= self:Points(buffs) then
				db.learned[itemID] = { kind = kind, amount = amount, buffs = buffs }
			end
			return kind, amount, buffs
		end
		return kind, nil, buffs
	end

	if learned then return learned.kind, learned.amount, learned.buffs end
	return nil, nil, nil
end
