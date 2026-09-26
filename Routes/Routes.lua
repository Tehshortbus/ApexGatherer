--[[
	Farming routes: data and the operations on them.

	ApexGathererRoutes.zones[zone] = {
		routes = { [name] = route },
		taboos = { [name] = { points = { coord, ... } } },   -- closed polygons to stay out of
	}
	route = {
		points   = { coord, ... },         -- the loop, in order
		clusters = { { coord, ... }, ... } -- clustered routes: the node spots each point covers
		radius   = yards,                  -- clustered routes: how close the loop passes each node
		nodes    = { [nodeID] = true },    -- the node types it was built from
		spots    = { [coord] = true },     -- the node spots it covers; Update route compares against them
		taboos   = { [name] = true },
		color, worldMapWidth, minimapWidth -- nil = the defaults
		show     = "always" | "tracking" | "never",
		length   = yards,
	}

	A route is a snapshot: it doesn't change as nodes are recorded or deleted. Update route adds
	the spots recorded since and drops the ones deleted since, leaving the rest as it is.

	Sends APEX_ROUTES_CHANGED (zone) whenever a zone's routes or taboos change.
]]
local Apex = ApexGatherer
local Catalog = Apex.Catalog
local Optimizer = Apex.Optimizer
local Routes = Apex:NewModule("Routes", "AceEvent-3.0")

local UnpackXY = Apex.UnpackXY

local function zoneData(zone, create)
	local zones = Apex.routeData.zones
	if not zones[zone] and create then zones[zone] = { routes = {}, taboos = {} } end
	return zones[zone]
end

function Routes:Changed(zone)
	self:SendMessage("APEX_ROUTES_CHANGED", zone)
end

function Routes:Get(zone, name)
	local data = zoneData(zone)
	return data and data.routes[name]
end

function Routes:GetTaboo(zone, name)
	local data = zoneData(zone)
	return data and data.taboos[name]
end

local function sortedNames(t)
	local list = {}
	for name in pairs(t or {}) do list[#list + 1] = name end
	sort(list)
	return list
end

function Routes:Names(zone)
	local data = zoneData(zone)
	return sortedNames(data and data.routes)
end

function Routes:TabooNames(zone)
	local data = zoneData(zone)
	return sortedNames(data and data.taboos)
end

-- zones with routes or taboos, sorted by name
function Routes:Zones()
	local list = {}
	for zone, data in pairs(Apex.routeData.zones) do
		if next(data.routes) or next(data.taboos) then list[#list + 1] = zone end
	end
	sort(list, function(a, b) return Apex:ZoneName(a) < Apex:ZoneName(b) end)
	return list
end

function Routes:Style(route)
	local defaults = Apex.db.profile.routes
	return route.color or defaults.color, route.worldMapWidth or defaults.worldMapWidth, route.minimapWidth or defaults.minimapWidth
end


------------------------------------------------------------------------------------------
-- Taboo areas

local function inside(polygon, x, y)
	local hit, n = false, #polygon
	local jx, jy = UnpackXY(polygon[n])
	for i = 1, n do
		local ix, iy = UnpackXY(polygon[i])
		if (iy > y) ~= (jy > y) and x < (jx - ix) * (y - iy) / (jy - iy) + ix then hit = not hit end
		jx, jy = ix, iy
	end
	return hit
end

-- the taboo polygons a route uses
function Routes:RouteTaboos(zone, route)
	local list, data = {}, zoneData(zone)
	for name in pairs(route.taboos) do
		local taboo = data and data.taboos[name]
		if taboo and #taboo.points >= 3 then list[#list + 1] = taboo.points end
	end
	return list
end

function Routes:InTaboo(zone, route, coord)
	local x, y = UnpackXY(coord)
	for _, polygon in ipairs(self:RouteTaboos(zone, route)) do
		if inside(polygon, x, y) then return true end
	end
	return false
end

-- a new taboo starts as a small diamond in the middle of the map, to be shaped on the map
function Routes:CreateTaboo(zone, name)
	name = strtrim(name or "")
	if name == "" then return false, "Give the taboo area a name first." end
	local data = zoneData(zone, true)
	if data.taboos[name] then return false, "There's already a taboo area with that name here." end
	local P = Apex.PackXY
	data.taboos[name] = { points = { P(0.5, 0.42), P(0.58, 0.5), P(0.5, 0.58), P(0.42, 0.5) } }
	self:Changed(zone)
	return true
end

function Routes:DeleteTaboo(zone, name)
	local data = zoneData(zone)
	if not data or not data.taboos[name] then return end
	data.taboos[name] = nil
	for _, route in pairs(data.routes) do route.taboos[name] = nil end
	self:Changed(zone)
end

-- drops the spots inside the route's taboos
function Routes:ApplyTaboos(zone, route)
	if route.clusters then
		for i = #route.points, 1, -1 do
			local members = route.clusters[i]
			for j = #members, 1, -1 do
				if self:InTaboo(zone, route, members[j]) then tremove(members, j) end
			end
			if #members == 0 then
				tremove(route.points, i)
				tremove(route.clusters, i)
			end
		end
	else
		for i = #route.points, 1, -1 do
			if self:InTaboo(zone, route, route.points[i]) then tremove(route.points, i) end
		end
	end
	route.length = Optimizer:PathLength(route.points, zone)
end

function Routes:SetTaboo(zone, name, taboo, used)
	local route = self:Get(zone, name)
	if not route then return end
	route.taboos[taboo] = used or nil
	self:ApplyTaboos(zone, route)
	self:Changed(zone)
end


------------------------------------------------------------------------------------------
-- Creating and changing routes

-- node ids recorded in a zone, with counts
function Routes:NodesInZone(zone)
	local counts = {}
	for _, kind in ipairs(Apex.KINDS) do
		for _, id in pairs(Apex:GetZoneNodes(kind, zone) or {}) do
			counts[id] = (counts[id] or 0) + 1
		end
	end
	return counts
end

-- every recorded spot of these node ids in a zone, as a set
local function spotsOf(zone, nodeIDs)
	local spots = {}
	for id in pairs(nodeIDs) do
		local kind = Catalog:Kind(id)
		for coord, nodeID in pairs(kind and Apex:GetZoneNodes(kind, zone) or {}) do
			if nodeID == id then spots[coord] = true end
		end
	end
	return spots
end

-- builds a route through every recorded spot of the chosen node ids and optimizes it
function Routes:Create(zone, name, nodeIDs)
	name = strtrim(name or "")
	if name == "" then return false, "Give the route a name first." end
	if not zone then return false, "Pick a zone." end
	local data = zoneData(zone, true)
	if data.routes[name] then return false, "There's already a route with that name in this zone." end
	local spots, points = spotsOf(zone, nodeIDs), {}
	for coord in pairs(spots) do points[#points + 1] = coord end
	if #points == 0 then return false, "No recorded spots of those nodes in this zone yet." end
	sort(points)
	local ordered, _, length = Optimizer:Solve(points, nil, {}, zone, { thorough = false })
	local nodes = {}
	for id in pairs(nodeIDs) do nodes[id] = true end
	data.routes[name] = { points = ordered, nodes = nodes, spots = spots, taboos = {}, show = "always", length = length }
	self:Changed(zone)
	return true
end

-- adds the spots of the route's nodes recorded since it was made or last updated, and drops
-- the ones deleted since; everything else (hand-placed points included) stays as it is.
-- Returns how many were added and removed.
function Routes:Update(zone, name)
	local route = self:Get(zone, name)
	if not route then return false, "No such route." end
	if self:Busy(zone, name) then return false, "Finish editing or optimizing this route first." end
	if not route.spots then
		-- routes from before spots were remembered: the spots are what it runs through now
		route.spots = {}
		for i, point in ipairs(route.points) do
			for _, coord in ipairs(route.clusters and route.clusters[i] or { point }) do route.spots[coord] = true end
		end
	end
	local current = spotsOf(zone, route.nodes)
	local added, removed = 0, 0
	for coord in pairs(route.spots) do
		if not current[coord] then
			for i = #route.points, 1, -1 do
				local members = route.clusters and route.clusters[i]
				if members then
					for j = #members, 1, -1 do
						if members[j] == coord then tremove(members, j); removed = removed + 1 end
					end
					if #members == 0 then
						tremove(route.points, i)
						tremove(route.clusters, i)
					end
				elseif route.points[i] == coord then
					tremove(route.points, i)
					removed = removed + 1
				end
			end
		end
	end
	local radius = route.radius or Apex:ClusterRadius()
	for coord in pairs(current) do
		if not route.spots[coord] and not self:InTaboo(zone, route, coord) then
			Optimizer:InsertPoint(route.points, route.clusters, zone, coord, radius)
			added = added + 1
		end
	end
	route.spots = current
	route.length = Optimizer:PathLength(route.points, zone)
	self:Changed(zone)
	return true, added, removed
end

function Routes:Delete(zone, name)
	local data = zoneData(zone)
	if not data or not data.routes[name] then return end
	data.routes[name] = nil
	self:Changed(zone)
end

function Routes:Rename(zone, name, newName)
	newName = strtrim(newName or "")
	local data = zoneData(zone)
	if not data or not data.routes[name] or newName == "" or newName == name then return false end
	if data.routes[newName] then return false, "There's already a route with that name in this zone." end
	data.routes[newName], data.routes[name] = data.routes[name], nil
	self:Changed(zone)
	return true
end

function Routes:Busy(zone, name)
	local running, points = Optimizer:IsRunning()
	local route = self:Get(zone, name)
	return (running and route and points == route.points) or (self.editing and self.editing.zone == zone and self.editing.name == name) or false
end

-- merges spots near each other into route points that cover them all within the radius
function Routes:Cluster(zone, name, radius)
	local route = self:Get(zone, name)
	if not route or route.clusters then return end
	route.points, route.clusters, route.length = Optimizer:Cluster(route.points, zone, radius)
	route.radius = radius
	self:Changed(zone)
end

function Routes:Uncluster(zone, name)
	local route = self:Get(zone, name)
	if not route or not route.clusters then return end
	local points = {}
	for _, members in ipairs(route.clusters) do
		for _, coord in ipairs(members) do points[#points + 1] = coord end
	end
	route.points, route.clusters, route.radius = points, nil, nil
	route.length = Optimizer:PathLength(points, zone)
	self:Changed(zone)
end

local function applyResult(zone, route, points, clusters, length)
	route.points, route.clusters, route.length = points, clusters, length
	Routes:Changed(zone)
end

-- optimizes now; returns the result message
function Routes:Optimize(zone, name)
	local route = self:Get(zone, name)
	if not route then return end
	local points, clusters, length, kicks, seconds = Optimizer:Solve(route.points, route.clusters,
		self:RouteTaboos(zone, route), zone, { thorough = Apex.db.profile.routes.thorough }, nil, false, route.radius)
	applyResult(zone, route, points, clusters, length)
	return ("%d points, %d yards (%d tries, %.1f s)."):format(#points, length, kicks, seconds)
end

-- optimizes a little every frame; onStatus(text) reports progress, and the result
function Routes:OptimizeInBackground(zone, name, onStatus)
	local route = self:Get(zone, name)
	if not route then return false end
	local state, err = Optimizer:SolveInBackground(route.points, route.clusters, self:RouteTaboos(zone, route), zone,
		{ thorough = Apex.db.profile.routes.thorough }, nil, route.radius)
	if state == 2 then return false, "Another route is being optimized; wait for it to finish." end
	if state == 3 then return false, "Optimizing failed: " .. tostring(err) end
	Optimizer:SetStatusFunction(function(tries, progress, length)
		onStatus(("Optimizing: %d%%, %d yards so far (%d tries)"):format(progress * 100, length or 0, tries))
	end)
	Optimizer:SetFinishFunction(function(points, clusters, length, kicks, seconds)
		applyResult(zone, route, points, clusters, length)
		onStatus(("Done: %d points, %d yards (%d tries, %.1f s)."):format(#points, length, kicks, seconds))
	end)
	onStatus("Optimizing...")
	return true
end


------------------------------------------------------------------------------------------
-- When a route shows

function Routes:IsShown(route)
	if route.show == "never" then return false end
	if route.show ~= "tracking" then return true end
	for id in pairs(route.nodes) do
		if Apex:TrackingActive(Catalog:Kind(id)) then return true end
	end
	return false
end

function Routes:OnEnable()
	self:RegisterEvent("MINIMAP_UPDATE_TRACKING", function() self:Changed() end)
end
