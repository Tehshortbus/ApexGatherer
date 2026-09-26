--[[
	The node database: ApexGathererNodes.kinds[kind][zone][coord] = nodeID.

	Recording a node first drops any node of the same spawn (same id, or ores that share
	spawn points) within the kind's cleanup range, so a spot is stored once, halfway between
	where it was and where it was gathered now. Merging (shared or imported nodes) instead
	skips a node we already have there.

	Learned nodes: Forever adds gather nodes faster than any datamine. When a Mining or
	Herbalism cast targets a name the catalog doesn't know, the name gets an id from 9001 up
	and is recorded like any other node. Fishing and treasure names are only logged: fishing
	reads the tooltip (which could be the bobber), and "Opening" is cast on quest objects too.
]]
local Apex = ApexGatherer
local Catalog = Apex.Catalog
local PackXY, UnpackXY = Apex.PackXY, Apex.UnpackXY

local LEARNABLE = { Mining = true, Herbalism = true }

local function store(kind)
	return Apex.nodeData.kinds[kind]
end

function Apex:GetZoneNodes(kind, zone)
	local zones = store(kind)
	return zones and zones[zone]
end

-- iterates the nodes of one kind in a zone within yards of a coordinate: coord, nodeID
function Apex:NodesNear(kind, zone, coord, yards)
	local data = self:GetZoneNodes(kind, zone)
	if not data then return function() end end
	local w, h = self.HBD:GetZoneSize(zone)
	local x, y = UnpackXY(coord)
	local limit = yards * yards
	local key, id
	return function()
		repeat
			key, id = next(data, key)
			if key then
				local nx, ny = UnpackXY(key)
				local dx, dy = (nx - x) * w, (ny - y) * h
				if dx * dx + dy * dy <= limit then return key, id end
			end
		until not key
	end
end

local function sameSpawnNear(self, kind, zone, coord, id)
	for other, otherID in self:NodesNear(kind, zone, coord, self.db.profile.cleanupRange[kind]) do
		if Catalog:SameSpawn(id, otherID) then return other end
	end
end

-- records a node where the player gathered it; returns the coordinate it was stored at, or
-- false. The player stands a few yards off the node, on whichever side they came from, so a
-- spot gathered again moves halfway to where they stand now: over a few visits from different
-- sides it settles close to the node itself.
function Apex:AddNode(kind, zone, coord, id)
	if not store(kind) or self.db.profile.locked[kind] or not Catalog:Get(id) then return false end
	local zones = store(kind)
	if zones[zone] then
		local old = sameSpawnNear(self, kind, zone, coord, id)
		if old then
			local ox, oy = UnpackXY(old)
			local nx, ny = UnpackXY(coord)
			coord = PackXY((ox + nx) / 2, (oy + ny) / 2)
		end
		while old do
			self:RemoveNode(kind, zone, old)
			old = zones[zone] and sameSpawnNear(self, kind, zone, coord, id)
		end
	end
	zones[zone] = zones[zone] or {}
	zones[zone][coord] = id
	self:SendMessage("APEX_NODE_ADDED", kind, zone, coord, id)
	return coord
end

-- adds a node from someone else unless we already have it; quiet skips the message
function Apex:MergeNode(kind, zone, coord, id, quiet)
	if not store(kind) or self.db.profile.locked[kind] or not Catalog:Get(id) then return false end
	if self:GetZoneNodes(kind, zone) and sameSpawnNear(self, kind, zone, coord, id) then return false end
	local zones = store(kind)
	zones[zone] = zones[zone] or {}
	zones[zone][coord] = id
	if not quiet then self:SendMessage("APEX_NODE_ADDED", kind, zone, coord, id) end
	return true
end

function Apex:RemoveNode(kind, zone, coord)
	local data = self:GetZoneNodes(kind, zone)
	local id = data and data[coord]
	if not id then return end
	data[coord] = nil
	if not next(data) then store(kind)[zone] = nil end
	self:SendMessage("APEX_NODE_REMOVED", kind, zone, coord, id)
end

-- removes every node of one id in a zone (or in every zone); returns how many
function Apex:RemoveNodeType(kind, id, zone)
	local removed = 0
	for z, data in pairs(store(kind)) do
		if not zone or z == zone then
			for coord, nodeID in pairs(data) do
				if nodeID == id then
					data[coord] = nil
					removed = removed + 1
				end
			end
			if not next(data) then store(kind)[z] = nil end
		end
	end
	if removed > 0 then self:SendMessage("APEX_NODES_CHANGED") end
	return removed
end

function Apex:ClearKind(kind)
	wipe(store(kind))
	self:SendMessage("APEX_NODES_CHANGED")
end

function Apex:CountNodes(kind, id)
	local count = 0
	for _, data in pairs(store(kind)) do
		for _, nodeID in pairs(data) do
			if not id or nodeID == id then count = count + 1 end
		end
	end
	return count
end

-- zones that hold nodes of a kind (or of any kind), sorted by name
function Apex:ZonesWithNodes(kind)
	local seen, list = {}, {}
	for _, k in ipairs(self.KINDS) do
		if not kind or k == kind then
			for zone in pairs(store(k)) do
				if not seen[zone] then
					seen[zone] = true
					list[#list + 1] = zone
				end
			end
		end
	end
	sort(list, function(a, b) return self:ZoneName(a) < self:ZoneName(b) end)
	return list
end

-- merges spots recorded twice (same spawn within the cleanup range); returns how many went
function Apex:CleanupDuplicates()
	local removed = 0
	for _, kind in ipairs(self.KINDS) do
		for zone, data in pairs(store(kind)) do
			local coords = {}
			for coord in pairs(data) do coords[#coords + 1] = coord end
			sort(coords)
			for _, coord in ipairs(coords) do
				local id = data[coord]
				if id then
					for other, otherID in self:NodesNear(kind, zone, coord, self.db.profile.cleanupRange[kind]) do
						if other ~= coord and Catalog:SameSpawn(id, otherID) then
							data[other] = nil
							removed = removed + 1
						end
					end
				end
			end
		end
	end
	if removed > 0 then self:SendMessage("APEX_NODES_CHANGED") end
	return removed
end

-- a location that is really a node: a zone the map knows, a coordinate on it
function Apex:ValidLocation(zone, coord)
	local w = zone and self.HBD:GetZoneSize(zone)
	return w and w > 0 and type(coord) == "number" and coord == math.floor(coord)
		and coord >= 0 and coord <= 99999999 and coord % 10000 <= 9999
end


------------------------------------------------------------------------------------------
-- Learned nodes and the unidentified-name log

function Apex:LoadLearnedNodes()
	local learned = self.nodeData.learned
	local remap = {}
	for kind, names in pairs(learned.names) do
		if store(kind) then
			for name, id in pairs(names) do
				local known = Catalog:Find(kind, name)
				if known then
					-- added to the catalog since: its stored spots move to the catalog id
					remap[id] = known
					names[name] = nil
				else
					Catalog:AddLearned(kind, name, id)
				end
			end
		end
	end
	if next(remap) then
		for _, kind in ipairs(self.KINDS) do
			for _, data in pairs(store(kind)) do
				for coord, id in pairs(data) do
					if remap[id] then data[coord] = remap[id] end
				end
			end
		end
	end
end

function Apex:CanLearn(kind)
	return LEARNABLE[kind] or false
end

-- the id to record a node name under, learning the name if needed; nil if it can't be learned
function Apex:LearnNode(kind, name)
	if type(name) ~= "string" or name == "" or #name > 60 then return end
	local known = Catalog:Find(kind, name)
	if known or not LEARNABLE[kind] then return known end
	local learned = self.nodeData.learned
	local id = learned.nextID
	learned.nextID = id + 1
	learned.names[kind] = learned.names[kind] or {}
	learned.names[kind][name] = id
	Catalog:AddLearned(kind, name, id)
	self:SendMessage("APEX_CATALOG_CHANGED", kind, name, id)
	self:Print(("%slearned a new %s node|r '%s'; it's recorded from now on."):format(self.TEAL, self.KIND_LABEL[kind]:lower(), name))
	return id
end

-- forgets a learned node and every spot recorded for it
function Apex:ForgetLearnedNode(kind, name)
	local names = self.nodeData.learned.names[kind]
	local id = names and names[name]
	if not id then return end
	names[name] = nil
	self:RemoveNodeType(kind, id)
	Catalog:RemoveLearned(kind, name)
	self:SendMessage("APEX_CATALOG_CHANGED", kind, name, nil)
	self:SendMessage("APEX_NODES_CHANGED")
end

function Apex:GetLearnedNodes()
	return self.nodeData.learned.names
end

-- names gathered but not identified, so they can be added to the catalog later
function Apex:LogUnknownNode(kind, name, zone, coord)
	local log = self.nodeData.unknown
	local key = kind .. ":" .. name
	local entry = log[key]
	if not entry then
		entry = { kind = kind, name = name, count = 0 }
		log[key] = entry
		self:Print(("unidentified %s node '%s' logged."):format(self.KIND_LABEL[kind]:lower(), name))
	end
	entry.count = entry.count + 1
	entry.zone, entry.coord, entry.last = zone, coord, time()
end

function Apex:GetUnknownNodes()
	return self.nodeData.unknown
end


------------------------------------------------------------------------------------------
-- Export / import: a Lua table of kind -> zone -> coord -> node name

function Apex:ExportNodes(kinds)
	local lines = { "-- ApexGatherer nodes: keep it as a backup, or import it on another character.", "ApexGathererExport = {" }
	for _, kind in ipairs(self.KINDS) do
		if (not kinds or kinds[kind]) and next(store(kind)) then
			lines[#lines + 1] = ("  [%q] = {"):format(kind)
			for zone, data in pairs(store(kind)) do
				lines[#lines + 1] = ("    [%d] = {"):format(zone)
				for coord, id in pairs(data) do
					lines[#lines + 1] = ("      [%d] = %q,"):format(coord, Catalog:Name(id) or tostring(id))
				end
				lines[#lines + 1] = "    },"
			end
			lines[#lines + 1] = "  },"
		end
	end
	lines[#lines + 1] = "}"
	return table.concat(lines, "\n")
end

-- returns ok, added, skipped (or false, error message)
function Apex:ImportNodes(text)
	if type(text) ~= "string" or not text:find("%S") then return false, "Nothing to import; paste an export first." end
	local chunk, err = loadstring(text)
	if not chunk then return false, "That text isn't an export: " .. tostring(err) end
	local env = {}
	setfenv(chunk, env)
	local ok, runErr = pcall(chunk)
	if not ok then return false, "Couldn't read the export: " .. tostring(runErr) end
	local data = env.ApexGathererExport
	if type(data) ~= "table" then return false, "This isn't an ApexGatherer export." end
	local added, skipped = 0, 0
	for kind, zones in pairs(data) do
		if store(kind) and type(zones) == "table" then
			for zone, nodes in pairs(zones) do
				zone = tonumber(zone)
				if type(nodes) == "table" then
					for coord, name in pairs(nodes) do
						coord = tonumber(coord)
						local id = type(name) == "string" and (Catalog:Find(kind, name) or self:LearnNode(kind, name))
						if id and self:ValidLocation(zone, coord) and self:MergeNode(kind, zone, coord, id, true) then
							added = added + 1
						else
							skipped = skipped + 1
						end
					end
				end
			end
		end
	end
	self:SendMessage("APEX_NODES_CHANGED")
	return true, added, skipped
end
