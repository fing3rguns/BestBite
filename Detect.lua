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

-- What using the item does, by the name of the spell the client files its use under: a
-- client whose merchant tooltip leaves the "Use:" line out still answers this, and "Food"
-- and "Drink" are the words it uses.
local DRINK_WORDS = Words("drink", "water", "boire", "beber", "bebida", "trinken")
local FOOD_WORDS = Words("food", "eat", "essen", "manger", "comer", "comida")

local function SpellKind(itemID)
	if not itemID or type(GetItemSpell) ~= "function" then return nil end
	local ok, name = pcall(GetItemSpell, itemID)
	if not ok or type(name) ~= "string" then
		ok, name = pcall(GetItemSpell, "item:" .. tostring(itemID))
		if not ok or type(name) ~= "string" then return nil end
	end
	local spell = name:lower()
	if SaysWord(spell, DRINK_WORDS) then return "water" end
	if SaysWord(spell, FOOD_WORDS) then return "food" end
	return nil
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
-- The merchant's own tooltip is tried first; a client whose merchant tooltip leaves the
-- "Use:" line out is read through the item's hyperlink instead, and one that answers
-- neither is classified by the spell the client files the item's use under.
function Detect:ScanMerchant(index)
	BestBite:Step("scanning a merchant item tooltip")
	local kind, amount, buffs

	if tooltip.SetMerchantItem then
		tooltip:SetOwner(WorldFrame, "ANCHOR_NONE")
		tooltip:ClearLines()
		tooltip:SetMerchantItem(index)
		kind, amount, buffs = ReadGoods()
		tooltip:ClearLines()
	end

	if not kind and tooltip.SetHyperlink and GetMerchantItemLink then
		local link = GetMerchantItemLink(index)
		if link then
			tooltip:SetOwner(WorldFrame, "ANCHOR_NONE")
			tooltip:ClearLines()
			tooltip:SetHyperlink(link)
			kind, amount, buffs = ReadGoods()
			tooltip:ClearLines()
		end
	end

	if not kind then
		kind = SpellKind(GetMerchantItemID and GetMerchantItemID(index))
	end
	return kind, amount, buffs
end

-- What the tooltip of a merchant item actually held, for `/bb vendor`. A kind that comes
-- back unread is otherwise impossible to tell from a merchant that sells no food.
function Detect:RawMerchant(index)
	local lines = {}
	local function Collect()
		for _, region in ipairs({ tooltip:GetRegions() }) do
			if region.GetObjectType and region:GetObjectType() == "FontString" then
				local text = region:GetText()
				if text then lines[#lines + 1] = StripColors(text) end
			end
		end
	end
	tooltip:SetOwner(WorldFrame, "ANCHOR_NONE")
	tooltip:ClearLines()
	if tooltip.SetMerchantItem then tooltip:SetMerchantItem(index) end
	Collect()
	tooltip:ClearLines()
	return lines
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
-- else nil, nil. `noLearn` reads without writing: a display that counts the bags must
-- not change the saved variables, or a reset would be undone by the redraw.
function Detect:Describe(bag, slot, itemID, noLearn)
	local kind, amount, buffs = self:Scan(bag, slot)
	local db = BestBite:Db()
	local learned = db.learned[itemID]

	if kind then
		amount = amount or (learned and learned.amount)
		buffs = buffs or (learned and learned.buffs)
		if amount then
			if not noLearn and (not learned or learned.kind ~= kind or learned.amount ~= amount
				or self:Points(learned.buffs) ~= self:Points(buffs)) then
				db.learned[itemID] = { kind = kind, amount = amount, buffs = buffs }
			end
			return kind, amount, buffs
		end
		return kind, nil, buffs
	end

	if learned then return learned.kind, learned.amount, learned.buffs end
	return nil, nil, nil
end
