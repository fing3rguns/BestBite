-- A food buff changes which food is worth eating. While the buff has time to run, eating
-- buff food again spends it for nothing, so the food that restores the most wins; in the
-- buff's last half minute the buff food leads again, to top it up before it goes.
--
-- Nothing can press the button to do both by itself: the client blocks a click the addon
-- makes. So this only decides which item the button holds, and a second press eats it.

local ADDON, ns = ...

local API = ns.API

local Buffs = {}
ns.Buffs = Buffs

-- Seconds of buff left at or below which buff food is worth eating again.
Buffs.REFRESH_WITHIN = 30

-- Aura names that mean "fed", lower case. A client that names the buff something else
-- still works: /bb debug prints every aura, and the name goes here.
local FED = {
	["well fed"] = true,
}

-- Seconds of food buff left, or nil when the player is not fed. A buff without a timer
-- counts as lasting forever, since it is not about to run out.
function Buffs:Left(now)
	now = now or GetTime()
	local best
	for _, aura in ipairs(API.Auras("HELPFUL")) do
		if FED[tostring(aura.name or ""):lower()] then
			local left = math.huge
			if aura.duration and aura.duration > 0 then
				left = math.max(0, (aura.expires or (now + aura.duration)) - now)
			end
			if not best or left > best then best = left end
		end
	end
	return best
end

-- Whether the buff has long enough left that buff food would be wasted on it.
function Buffs:Banked(now)
	local left = self:Left(now)
	return left ~= nil and left > self.REFRESH_WITHIN
end

function Buffs:Changed()
	if ns.Buttons then ns.Buttons:Request(0) end
	if ns.Icons then ns.Icons:Request(0) end
end

-- The buff crossing the threshold is not an event, so one timer is set for the moment it
-- happens: until then the button holds plain food, and at that point it takes buff food.
local generation = 0
function Buffs:Refresh()
	local left = self:Left()
	generation = generation + 1
	if not (left and left > self.REFRESH_WITHIN and C_Timer and C_Timer.After) then return end
	local mine = generation
	C_Timer.After(math.min(left - self.REFRESH_WITHIN + 0.5, 900), function()
		if mine ~= generation then return end
		Buffs:Changed()
	end)
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("UNIT_AURA")
events:RegisterEvent("BAG_UPDATE_DELAYED")
events:SetScript("OnEvent", function(_, event, unit)
	if event == "UNIT_AURA" and unit ~= "player" then return end
	local ok, err = pcall(function()
		Buffs:Refresh()
		if event == "UNIT_AURA" then Buffs:Changed() end
	end)
	if not ok then
		Buffs.warned = Buffs.warned or false
		if not Buffs.warned then
			Buffs.warned = true
			ns.BestBite:Print("could not read your auras: " .. tostring(err))
		end
	end
end)
