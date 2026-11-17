-- What the action bar says about a macro that runs BestBite, without writing the
-- macro itself (the game reserves that for its own macro window):
--   * the button is repainted with the icon of the item the macro would use;
--   * the tooltip shows that item and its "Restores ..." line instead of the macro's
--     own text.
-- With /bb macroicon on, it also rewrites the macro's stored icon, if the client
-- permits that; if it refuses, the attempt switches itself back off.

local ADDON, ns = ...

local BestBite = ns.BestBite
local API = ns.API

local Icons = { food = nil, water = nil }
ns.Icons = Icons

local BUTTON_BARS = {
	"ActionButton",
	"MultiBarBottomLeftButton",
	"MultiBarBottomRightButton",
	"MultiBarRightButton",
	"MultiBarLeftButton",
}
local BUTTONS_PER_BAR = 12

-- The BestBite command a macro body runs. Both a /bb command and the /click the game
-- requires are understood; anything else in the macro makes it none of our business.
local function KindOf(body)
	local kind
	for line in (body or ""):gmatch("[^\r\n]+") do
		local text = line:gsub("^%s+", ""):gsub("%s+$", ""):lower()
		if text ~= "" and text:sub(1, 1) ~= "#" then
			local slash, argument = text:match("^/(%S+)%s*(.-)$")
			argument = argument and argument:gsub("%s+$", "") or ""
			if slash == "click" then
				if argument == "bestbitefood" then
					kind = kind or "food"
				elseif argument == "bestbitewater" then
					kind = kind or "water"
				else
					return nil
				end
			elseif slash == "bb" or slash == "bestbite" then
				if argument == "food" or argument == "eat" then
					kind = kind or "food"
				elseif argument == "water" or argument == "drink" then
					kind = kind or "water"
				elseif argument == "consume" or argument == "both" then
					kind = kind or "consume"
				else
					return nil
				end
			else
				return nil
			end
		end
	end
	return kind
end

-- The kind the macro in an action slot asks for, and that macro's own icon.
local function MacroAt(action)
	if not (action and GetActionInfo and GetMacroInfo) then return nil end
	local actionType, id = GetActionInfo(action)
	if actionType ~= "macro" then return nil end

	local icon, body
	if type(id) == "number" then
		_, icon, body = GetMacroInfo(id)
	elseif type(id) == "string" and GetMacroIndexByName then
		local index = GetMacroIndexByName(id)
		if index then
			_, icon, body = GetMacroInfo(index)
		end
	end

	local kind = body and KindOf(body)
	if not kind then return nil end
	return kind, icon
end

function Icons:Texture(kind)
	if kind == "consume" then return self.food or self.water end
	if kind == "food" then return self.food end
	return self.water
end

function Icons:Pick(kind)
	if kind == "consume" then return self.foodPick or self.waterPick end
	if kind == "food" then return self.foodPick end
	return self.waterPick
end

function Icons:Button(button)
	local kind = MacroAt(button and button.action)
	if not kind then return end
	local texture = self:Texture(kind)
	local icon = button.icon or button.Icon
	if texture and icon and icon.SetTexture then
		BestBite:Step("repainting an action bar icon")
		icon:SetTexture(texture)
	end
end

local function EachButton(action)
	for _, bar in ipairs(BUTTON_BARS) do
		for index = 1, BUTTONS_PER_BAR do
			local button = _G[bar .. index]
			if button then action(button) end
		end
	end
end

-- The macro's stored icon, for a macro whose body is ours. Returns whether a write
-- was made.
function Icons:WriteMacroIcons()
	if not (BestBite:Db().writeMacroIcons and GetMacroInfo and EditMacro) then return false end
	if InCombatLockdown and InCombatLockdown() then return false end

	local total = (MAX_ACCOUNT_MACROS or 18) + (MAX_CHARACTER_MACROS or 18)
	local wrote = false
	for index = 1, total do
		local name, icon, body, isLocal = GetMacroInfo(index)
		local kind = name and body and KindOf(body)
		local texture = kind and self:Texture(kind)
		if texture and texture ~= icon then
			BestBite:Step("rewriting a macro's icon")
			EditMacro(index, name, texture, body, isLocal)
			wrote = true
		end
	end
	return wrote
end

function Icons:Refresh()
	if BestBite:Db().showIcons == false then return end
	local Consume = ns.Consume
	if not Consume then return end

	self.foodPick, self.waterPick = Consume:Find("food"), Consume:Find("water")
	self.food = self.foodPick and API.ItemIcon(self.foodPick.itemID) or nil
	self.water = self.waterPick and API.ItemIcon(self.waterPick.itemID) or nil

	self:WriteMacroIcons()
	if not (self.food or self.water) then return end
	EachButton(function(button) Icons:Button(button) end)
end

-- Puts the macro's own icon back on every button that runs one of ours, without
-- calling anything of the game's: calling its bar code from an addon is what the
-- client refuses.
function Icons:Restore()
	EachButton(function(button)
		local _, macroIcon = MacroAt(button.action)
		local icon = button.icon or button.Icon
		if macroIcon and icon and icon.SetTexture then
			BestBite:Step("restoring an action bar icon")
			icon:SetTexture(macroIcon)
		end
	end)
end

-- One refresh in flight at a time: the latest bags are read when it runs.
local scheduled, warned = false, false
function Icons:Request(delay)
	if scheduled then return end
	scheduled = true
	local function run()
		scheduled = false
		local ok, err = pcall(Icons.Refresh, Icons)
		if not ok and not warned then
			warned = true
			BestBite:Print("action bar icons are not updating: " .. tostring(err))
		end
	end
	if delay and delay > 0 and C_Timer and C_Timer.After then
		C_Timer.After(delay, run)
	else
		run()
	end
end

-- The macro's own tooltip says nothing about the item, so show the item instead.
local function TooltipFor(tooltip, action)
	if not (action and tooltip and tooltip.ClearLines and ns.Consume) then return end
	local kind = MacroAt(action)
	local pick = kind and Icons:Pick(kind)
	if not (pick and pick.itemID) then return end

	BestBite:Step("showing an item tooltip")
	tooltip:ClearLines()
	if tooltip.SetItemByID then
		tooltip:SetItemByID(pick.itemID)
	elseif tooltip.SetHyperlink then
		tooltip:SetHyperlink("item:" .. pick.itemID)
	end
end

local function OnButtonUpdate(button)
	Icons:Button(button)
end

if ActionButton_Update then
	hooksecurefunc("ActionButton_Update", OnButtonUpdate)
end
if ActionButtonMixin and ActionButtonMixin.Update then
	hooksecurefunc(ActionButtonMixin, "Update", OnButtonUpdate)
end
if GameTooltip and GameTooltip.SetAction then
	hooksecurefunc(GameTooltip, "SetAction", TooltipFor)
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("BAG_UPDATE_DELAYED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(_, event)
	if event == "BAG_UPDATE_DELAYED" then
		Icons:Request(1)
	else
		Icons:Request(0.5)
	end
end)
