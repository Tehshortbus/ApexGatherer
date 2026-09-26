--[[
	Node pins on the world map, the minimap and the HUD.

	The world map shows the nodes of the zone it is displaying and the minimap those of the zone
	the player is in, both placed through HereBeDragons-Pins. While the HUD is open, the player's
	zone is shown on the HUD instead, out to its edge (further than the minimap reaches), and
	the HUD places those pins itself (Pins:PlaceHUD). All are rebuilt (on the next frame)
	whenever nodes or display settings change. Hovering a pin names the node; right-clicking
	offers deletion.

	A pin is a marker: a picture of the kind of node with one part tinted for the node (see
	Catalog:Marker). Where tracking already shows the node (its kind is tracked and the spot is
	within tracking range), the minimap has its own blip there, so the pin draws only a ring in
	the kind's colour round that blip; an empty ring means the node isn't up right now.
]]
local Apex = ApexGatherer
local Catalog = Apex.Catalog
local Pins = Apex:NewModule("Pins", "AceEvent-3.0")

local PIN_SIZE = 14
local UnpackXY = Apex.UnpackXY

local pools = { minimap = {}, worldmap = {}, hud = {} }
local active = { minimap = {}, worldmap = {}, hud = {} }
local minimapRef, worldmapRef = {}, {}
local minimapMouse = true   -- off while the HUD lets clicks through
local tracked = {}          -- kind -> whether the minimap is showing its nodes itself

local function onEnter(pin)
	if not Apex.db.profile.pins.tooltips then return end
	GameTooltip:SetOwner(pin, "ANCHOR_RIGHT")
	GameTooltip:AddLine(Catalog:Name(pin.nodeID) or "?", 1, 1, 1)
	GameTooltip:AddLine(Apex.KIND_LABEL[pin.kind], 0.7, 0.7, 0.7)
	GameTooltip:Show()
end

local function onLeave()
	GameTooltip:Hide()
end

local function onClick(pin, button)
	if button ~= "RightButton" or not MenuUtil then return end
	local kind, zone, coord, id = pin.kind, pin.zone, pin.coord, pin.nodeID
	local name = Catalog:Name(id) or "?"
	MenuUtil.CreateContextMenu(pin, function(_, root)
		root:CreateTitle(name)
		root:CreateButton("Delete this node", function() Apex:RemoveNode(kind, zone, coord) end)
		root:CreateButton(("Delete every %s in this zone"):format(name), function() Apex:RemoveNodeType(kind, id, zone) end)
	end)
end

local function acquire(which)
	local pin = tremove(pools[which])
	if not pin then
		-- no name: minimap button collectors take any named clickable child of the minimap for an
		-- addon's button and move it off the map
		pin = CreateFrame("Button", nil, UIParent)
		pin.isApexPin = true
		pin.picture = pin:CreateTexture(nil, "ARTWORK")
		pin.picture:SetAllPoints()
		pin.tinted = pin:CreateTexture(nil, "OVERLAY")
		pin.tinted:SetAllPoints()
		pin.ring = pin:CreateTexture(nil, "OVERLAY")
		pin.ring:SetTexture(Apex.media .. "PinRing")
		pin.ring:SetPoint("CENTER")
		pin.ring:Hide()
		pin:RegisterForClicks("RightButtonUp")
		pin:SetScript("OnEnter", onEnter)
		pin:SetScript("OnLeave", onLeave)
		pin:SetScript("OnClick", onClick)
	end
	tinsert(active[which], pin)
	return pin
end

local function releaseAll(which)
	for i = #active[which], 1, -1 do
		local pin = active[which][i]
		pin:Hide()
		active[which][i] = nil
		tinsert(pools[which], pin)
	end
end

-- a node the minimap's tracking shows gets just a ring round its blip; any other, its marker
local function mark(pin, inRange)
	local pins = Apex.db.profile.pins
	local ringed = (inRange and pins.ring and tracked[pin.kind]) and true or false
	if ringed then
		local c = pins.ringColor[pin.kind]
		pin.ring:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
	end
	pin.ring:SetShown(ringed)
	pin.picture:SetShown(not ringed)
	pin.tinted:SetShown(not ringed)
end

local function setup(pin, kind, zone, coord, id, size)
	pin.kind, pin.zone, pin.coord, pin.nodeID = kind, zone, coord, id
	local picture, tinted, tint = Catalog:Marker(id)
	pin.picture:SetTexture(picture)
	pin.tinted:SetTexture(tinted)
	pin.tinted:SetVertexColor(tint[1], tint[2], tint[3])
	pin:SetSize(size, size)
	local ring = Apex.db.profile.pins.ringSize
	pin.ring:SetSize(ring, ring)
	mark(pin, false)
	pin:SetAlpha(Apex.db.profile.pins.alpha)
end

-- calls fn(kind, coord, id) for every node of a zone the settings let through
local function eachShown(zone, fn)
	local pins = Apex.db.profile.pins
	for _, kind in ipairs(Apex.KINDS) do
		local data = pins.show[kind] and Apex:GetZoneNodes(kind, zone)
		if data then
			for coord, id in pairs(data) do
				if not pins.hidden[id] then fn(kind, coord, id) end
			end
		end
	end
end

local function updateTracked()
	for _, kind in ipairs(Apex.KINDS) do tracked[kind] = Apex:TrackingShows(kind) end
end

function Pins:RefreshMinimap()
	Apex.HBDPins:RemoveAllMinimapIcons(minimapRef)
	releaseAll("minimap")
	releaseAll("hud")
	local pins = Apex.db.profile.pins
	local zone = pins.minimap and Apex.HBD:GetPlayerZone()
	if not zone then return end
	updateTracked()
	local HUD = Apex:GetModule("HUD")
	local canvas = HUD:IsOpen() and HUD:Canvas()
	local size = PIN_SIZE * (canvas and pins.hudScale or pins.minimapScale)
	eachShown(zone, function(kind, coord, id)
		local pin = acquire(canvas and "hud" or "minimap")
		setup(pin, kind, zone, coord, id, size)
		pin:EnableMouse(minimapMouse)
		if canvas then
			pin:SetParent(canvas)
			pin:SetFrameLevel(canvas:GetFrameLevel() + 2)
			pin:Hide()   -- until the HUD places it
		else
			local x, y = UnpackXY(coord)
			Apex.HBDPins:AddMinimapIconMap(minimapRef, pin, zone, x, y, false, false)
		end
	end)
	self:UpdateRings()
end

function Pins:RefreshWorldMap()
	Apex.HBDPins:RemoveAllWorldMapIcons(worldmapRef)
	releaseAll("worldmap")
	local pins = Apex.db.profile.pins
	if not pins.worldMap or not WorldMapFrame or not WorldMapFrame:IsShown() then return end
	local zone = WorldMapFrame:GetMapID()
	if not zone then return end
	local size = PIN_SIZE * pins.worldMapScale
	eachShown(zone, function(kind, coord, id)
		local pin = acquire("worldmap")
		setup(pin, kind, zone, coord, id, size)
		pin:EnableMouse(true)
		local x, y = UnpackXY(coord)
		Apex.HBDPins:AddWorldMapIconMap(worldmapRef, pin, zone, x, y, 0)
	end)
end

local queued = false
function Pins:Refresh()
	if queued then return end
	queued = true
	C_Timer.After(0, function()
		queued = false
		Pins:RefreshMinimap()
		Pins:RefreshWorldMap()
	end)
end

-- rings the minimap pins that tracking shows (the HUD's pins are marked as it places them)
function Pins:UpdateRings()
	updateTracked()
	local x, y, zone = Apex.HBD:GetPlayerZonePosition()
	local w, h = 0, 0
	if zone then w, h = Apex.HBD:GetZoneSize(zone) end
	local range = Apex:TrackingRangeYards()
	for _, pin in ipairs(active.minimap) do
		local inRange = false
		if x and pin.zone == zone and w > 0 then
			local px, py = UnpackXY(pin.coord)
			local dx, dy = (px - x) * w, (py - y) * h
			inRange = dx * dx + dy * dy <= range * range
		end
		mark(pin, inRange)
	end
end

-- places the HUD's pins round the player at (x, y) in zone: perYard pixels to a yard, turned
-- by sin/cos like the minimap, shown out to edge pixels from the middle
function Pins:PlaceHUD(x, y, zone, perYard, sin, cos, edge)
	local list = active.hud
	if #list == 0 then return end
	local w, h = Apex.HBD:GetZoneSize(zone)
	local range = Apex:TrackingRangeYards()
	for _, pin in ipairs(list) do
		local shown = false
		if pin.zone == zone and w > 0 then
			local px, py = UnpackXY(pin.coord)
			local dx, dy = (px - x) * w, -(py - y) * h   -- yards east and north of the player
			local sx, sy = (dx * cos - dy * sin) * perYard, (dx * sin + dy * cos) * perYard
			if sx * sx + sy * sy <= edge * edge then
				shown = true
				pin:SetPoint("CENTER", pin:GetParent(), "CENTER", sx, sy)
				mark(pin, dx * dx + dy * dy <= range * range)
			end
		end
		pin:SetShown(shown)
	end
end

function Pins:SetMinimapMouse(on)
	minimapMouse = on
	for _, pin in ipairs(active.minimap) do pin:EnableMouse(on) end
	for _, pin in ipairs(active.hud) do pin:EnableMouse(on) end
end

function Pins:OnEnable()
	for _, message in ipairs({ "APEX_NODE_ADDED", "APEX_NODE_REMOVED", "APEX_NODES_CHANGED", "APEX_CATALOG_CHANGED",
		"APEX_SETTINGS_CHANGED", "APEX_HUD_TOGGLED" }) do
		self:RegisterMessage(message, "Refresh")
	end
	Apex.HBD.RegisterCallback(self, "PlayerZoneChanged", "Refresh")
	local ticker = CreateFrame("Frame")
	ticker:SetScript("OnUpdate", function(_, elapsed)
		ticker.wait = (ticker.wait or 0) - elapsed
		if ticker.wait > 0 then return end
		ticker.wait = 0.25
		Pins:UpdateRings()
	end)
	if WorldMapFrame then
		hooksecurefunc(WorldMapFrame, "OnMapChanged", function() Pins:RefreshWorldMap() end)
		WorldMapFrame:HookScript("OnShow", function() Pins:RefreshWorldMap() end)
	end
	self:Refresh()
end
