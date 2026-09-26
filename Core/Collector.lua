--[[
	Watches the player's gathering casts and records each node where it was gathered.

	A gathering cast names its target (the vein, herb or chest) when it is sent, and is only sent
	from within reach of the node, so the node is recorded right then: even if the cast then
	fails (someone else is already mining it, say), the node is there. The player stands a step
	short of the node and faces it, so the spot is recorded that step ahead of them. Fishing has
	no target: the pool is read from the tooltip under the cursor, and placed further ahead.
]]
local Apex = ApexGatherer
local Catalog = Apex.Catalog
local Collector = Apex:NewModule("Collector", "AceEvent-3.0")

local GATHER_REACH = 2     -- yards from where the player stands to the middle of the node
local FISHING_REACH = 15   -- yards from the player to where a fished pool sits
local REPEAT_WINDOW = 60   -- seconds in which clicking the same node again isn't recorded again

-- gathering spells by name (the cast's own id varies by rank); nil-safe for unknown ids
local castKind = {}
local function addSpell(id, kind)
	local name = C_Spell.GetSpellName(id)
	if name then castKind[name] = kind end
end
addSpell(2575, "Mining")      -- Mining
addSpell(2366, "Herbalism")   -- Herb Gathering
addSpell(7620, "Fishing")     -- Fishing
addSpell(3365, "Treasure")    -- Opening
addSpell(22810, "Treasure")   -- Opening (silent)
addSpell(1804, "Treasure")    -- Pick Lock

local last   -- { id, zone, coord, time } of the node recorded last

local function secret(value)
	return issecretvalue and issecretvalue(value)
end

local function tooltipName()
	local line = GameTooltipTextLeft1
	local text = line and line:GetText()
	if text and not secret(text) and text ~= "" then return text end
end

function Collector:OnEnable()
	self:RegisterEvent("UNIT_SPELLCAST_SENT")
end

function Collector:UNIT_SPELLCAST_SENT(_, unit, target, _, spellID)
	if unit ~= "player" or secret(spellID) then return end
	local spell = C_Spell.GetSpellName(spellID)
	local kind = spell and castKind[spell]
	if not kind then return end
	local name = kind == "Fishing" and tooltipName() or target
	if secret(name) or not name or name == "" then return end
	self:Record(kind, name)
end

function Collector:Record(kind, name)
	if Apex.db.profile.locked[kind] then return end
	local x, y, zone = Apex.HBD:GetPlayerZonePosition()
	if not x or not zone then return end
	local w, h = Apex.HBD:GetZoneSize(zone)
	local facing = GetPlayerFacing()   -- nil where the client hides it (instances)
	if facing and w > 0 and h > 0 then
		-- facing: 0 is north, counter-clockwise in radians; map y grows southward
		local reach = kind == "Fishing" and FISHING_REACH or GATHER_REACH
		x = x - math.sin(facing) * reach / w
		y = y - math.cos(facing) * reach / h
	elseif kind == "Fishing" then
		return   -- no telling where the pool is
	end
	local coord = Apex.PackXY(x, y)
	local id = Catalog:Find(kind, name) or (Apex:CanLearn(kind) and Apex:LearnNode(kind, name))
	if not id then
		Apex:LogUnknownNode(kind, name, zone, coord)
		return
	end
	-- the same node clicked again (a retry after a failed cast): it's already recorded
	if last and last.id == id and last.zone == zone and GetTime() - last.time < REPEAT_WINDOW
		and Apex:GetZoneNodes(kind, zone) and Apex:GetZoneNodes(kind, zone)[last.coord] == id then
		local lx, ly = Apex.UnpackXY(last.coord)
		local w, h = Apex.HBD:GetZoneSize(zone)
		local dx, dy = (x - lx) * w, (y - ly) * h
		if dx * dx + dy * dy <= Apex.db.profile.cleanupRange[kind] ^ 2 then return end
	end
	local stored = Apex:AddNode(kind, zone, coord, id)
	if stored then
		last = { id = id, zone = zone, coord = stored, time = GetTime() }
		Apex:SendMessage("APEX_NODE_GATHERED", kind, zone, stored, id)
	end
end
