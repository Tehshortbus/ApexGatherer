--[[
	Draws routes as lines: on the world map's canvas (so they zoom and pan with it), and on
	the minimap around the player, clipped to its edge. While the HUD is open, the minimap's
	layer moves onto the HUD and the lines reach out to the HUD's edge, past the minimap's.

	While the routes panel is open, the zone's taboo areas are drawn on the world map too
	(outlined and filled), and the route or taboo being edited is drawn from its working copy.
	On the world map all of it sits above the map's pins, so nothing hides it.
]]
local Apex = ApexGatherer
local Routes = Apex:GetModule("Routes")
local Drawing = Apex:NewModule("RouteDrawing", "AceEvent-3.0")

local UnpackXY = Apex.UnpackXY
local TABOO_COLOR = { 1, 0.2, 0.2, 0.9 }
local TABOO_FILL = { 1, 0.2, 0.2, 0.22 }
local FILL_STEP = 3   -- canvas pixels per strip of a taboo area's fill
local EDIT_COLOR = { 0.3, 1, 0.3, 1 }

-- a pool of line regions on one frame; lines are placed relative to `anchor` of the frame
local function newLayer(frame, anchor)
	return { frame = frame, anchor = anchor, lines = {}, used = 0 }
end

local function addLine(layer, x1, y1, x2, y2, width, color)
	layer.used = layer.used + 1
	local line = layer.lines[layer.used]
	if not line then
		line = layer.frame:CreateLine(nil, "OVERLAY")
		layer.lines[layer.used] = line
	end
	line:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
	line:SetThickness(width)
	line:SetStartPoint(layer.anchor, layer.frame, x1, y1)
	line:SetEndPoint(layer.anchor, layer.frame, x2, y2)
	line:Show()
end

local function finishLayer(layer)
	for i = layer.used + 1, #layer.lines do layer.lines[i]:Hide() end
	layer.used = 0
end


------------------------------------------------------------------------------------------
-- World map

local world
local fills, fillsUsed = {}, 0

local function addFill(x, y, width, height)
	fillsUsed = fillsUsed + 1
	local tex = fills[fillsUsed]
	if not tex then
		tex = world.frame:CreateTexture(nil, "ARTWORK")
		fills[fillsUsed] = tex
	end
	tex:SetColorTexture(TABOO_FILL[1], TABOO_FILL[2], TABOO_FILL[3], TABOO_FILL[4])
	tex:ClearAllPoints()
	tex:SetPoint("TOPLEFT", world.frame, "TOPLEFT", x, -y)
	tex:SetSize(width, height)
	tex:Show()
end

-- fills a closed loop of packed coordinates with thin horizontal strips (even-odd rule, so any
-- shape works, even one that crosses itself)
local function worldFill(points)
	local n = #points
	if n < 3 then return end
	local w, h = world.frame:GetWidth(), world.frame:GetHeight()
	local xs, ys = {}, {}
	local top, bottom = math.huge, -math.huge
	for i = 1, n do
		local x, y = UnpackXY(points[i])
		xs[i], ys[i] = x * w, y * h
		top, bottom = math.min(top, ys[i]), math.max(bottom, ys[i])
	end
	for y = top, bottom, FILL_STEP do
		local mid, cuts = y + FILL_STEP / 2, {}
		for i = 1, n do
			local j = i % n + 1
			if (ys[i] <= mid) ~= (ys[j] <= mid) then
				cuts[#cuts + 1] = xs[i] + (mid - ys[i]) * (xs[j] - xs[i]) / (ys[j] - ys[i])
			end
		end
		sort(cuts)
		for k = 1, #cuts - 1, 2 do addFill(cuts[k], y, cuts[k + 1] - cuts[k], FILL_STEP) end
	end
end

-- a closed loop of packed coordinates onto the canvas
local function worldLoop(points, width, color)
	local n = #points
	if n < 2 then return end
	local w, h = world.frame:GetWidth(), world.frame:GetHeight()
	local px, py = UnpackXY(points[n])
	for i = 1, n do
		local x, y = UnpackXY(points[i])
		addLine(world, px * w, -py * h, x * w, -y * h, width, color)
		px, py = x, y
	end
end

function Drawing:DrawWorldMap()
	if not world or not WorldMapFrame:IsShown() then return end
	world.frame:SetFrameLevel(WorldMapFrame:GetCanvas():GetFrameLevel() + Apex.MAP_LINES_LEVEL)
	fillsUsed = 0
	local zone = WorldMapFrame:GetMapID()
	local editing = Routes.editing
	local settings = Apex.db.profile.routes
	if zone and settings.worldMap then
		for _, name in ipairs(Routes:Names(zone)) do
			local route = Routes:Get(zone, name)
			local isEdited = editing and editing.kind == "route" and editing.zone == zone and editing.name == name
			if not isEdited and Routes:IsShown(route) then
				local color, width = Routes:Style(route)
				worldLoop(route.points, width, color)
			end
		end
	end
	if zone and Apex:GetModule("Flyout"):IsOpen() then
		for _, name in ipairs(Routes:TabooNames(zone)) do
			local isEdited = editing and editing.kind == "taboo" and editing.zone == zone and editing.name == name
			if not isEdited then
				local points = Routes:GetTaboo(zone, name).points
				worldFill(points)
				worldLoop(points, 2, TABOO_COLOR)
			end
		end
	end
	if editing and editing.zone == zone then
		if editing.kind == "taboo" then worldFill(editing.points) end
		worldLoop(editing.points, 3, EDIT_COLOR)
	end
	finishLayer(world)
	for i = fillsUsed + 1, #fills do fills[i]:Hide() end
end

function Drawing:WorldCanvas()
	return world and world.frame
end


------------------------------------------------------------------------------------------
-- Minimap

local mini
local lastX, lastY, lastFacing, lastZoom, lastWidth
local dirty = true

-- the part of segment a-b inside the minimap: a circle of radius r, or a square of half-side r
local function clip(ax, ay, bx, by, r, round)
	local dx, dy = bx - ax, by - ay
	local t0, t1 = 0, 1
	if round then
		local A = dx * dx + dy * dy
		if A == 0 then return end
		local B = 2 * (ax * dx + ay * dy)
		local C = ax * ax + ay * ay - r * r
		local disc = B * B - 4 * A * C
		if disc <= 0 then return end
		disc = disc ^ 0.5
		t0 = math.max(t0, (-B - disc) / (2 * A))
		t1 = math.min(t1, (-B + disc) / (2 * A))
	else
		for _, edge in ipairs({ { -dx, ax + r }, { dx, r - ax }, { -dy, ay + r }, { dy, r - ay } }) do
			local p, q = edge[1], edge[2]
			if p == 0 then
				if q < 0 then return end
			else
				local t = q / p
				if p < 0 then t0 = math.max(t0, t) else t1 = math.min(t1, t) end
			end
		end
	end
	if t0 >= t1 then return end
	return ax + t0 * dx, ay + t0 * dy, ax + t1 * dx, ay + t1 * dy
end

function Drawing:DrawMinimap()
	dirty = false
	local settings = Apex.db.profile.routes
	local x, y, zone = Apex.HBD:GetPlayerZonePosition()
	if not settings.minimap or not zone then return finishLayer(mini) end
	local w, h = Apex.HBD:GetZoneSize(zone)
	if w == 0 then return finishLayer(mini) end

	local radius = Minimap:GetWidth() / 2
	local scale = radius / Apex:MinimapRadiusYards()
	local round = not GetMinimapShape or GetMinimapShape() == "ROUND"
	local HUD = Apex:GetModule("HUD")
	if HUD:IsOpen() then radius, round = HUD:Edge(), true end
	local sin, cos = 0, 1
	if GetCVar("rotateMinimap") == "1" then
		local angle = -(GetPlayerFacing() or 0)
		sin, cos = math.sin(angle), math.cos(angle)
	end
	-- a zone coordinate to minimap pixels from the centre (screen y points up)
	local function toMinimap(coord)
		local cx, cy = UnpackXY(coord)
		local dx, dy = (cx - x) * w * scale, -(cy - y) * h * scale
		return dx * cos - dy * sin, dx * sin + dy * cos
	end

	for _, name in ipairs(Routes:Names(zone)) do
		local route = Routes:Get(zone, name)
		local points = route.points
		if #points >= 2 and Routes:IsShown(route) then
			local color, _, width = Routes:Style(route)
			local px, py = toMinimap(points[#points])
			for i = 1, #points do
				local nx, ny = toMinimap(points[i])
				local ax, ay, bx, by = clip(px, py, nx, ny, radius, round)
				if ax then addLine(mini, ax, ay, bx, by, width, color) end
				px, py = nx, ny
			end
		end
	end
	finishLayer(mini)
end

local function minimapUpdate(frame, elapsed)
	frame.wait = (frame.wait or 0) - elapsed
	if frame.wait > 0 then return end
	frame.wait = 0.05
	local x, y = Apex.HBD:GetPlayerZonePosition()
	local facing, zoom, width = GetPlayerFacing(), Minimap:GetZoom(), Minimap:GetWidth()
	if dirty or x ~= lastX or y ~= lastY or facing ~= lastFacing or zoom ~= lastZoom or width ~= lastWidth then
		lastX, lastY, lastFacing, lastZoom, lastWidth = x, y, facing, zoom, width
		Drawing:DrawMinimap()
	end
end

-- the HUD keeps this layer on the minimap when it moves the minimap's other children away
function Drawing:MinimapLayer()
	return mini and mini.frame
end

-- onto the HUD while it's open (its lines reach past the minimap), back onto the minimap after
function Drawing:OnHUDToggled(_, open)
	local parent = open and Apex:GetModule("HUD"):Frame() or Minimap
	local frame = mini.frame
	frame:SetParent(parent)
	frame:ClearAllPoints()
	frame:SetAllPoints(parent)
	frame:SetFrameLevel(Minimap:GetFrameLevel() + 2)
	dirty = true
end


------------------------------------------------------------------------------------------

function Drawing:Refresh()
	dirty = true
	self:DrawWorldMap()
end

function Drawing:OnEnable()
	local miniFrame = CreateFrame("Frame", "ApexGathererRouteLines", Minimap)
	miniFrame:SetAllPoints(Minimap)
	miniFrame:SetFrameLevel(Minimap:GetFrameLevel() + 2)
	miniFrame:SetScript("OnUpdate", minimapUpdate)
	mini = newLayer(miniFrame, "CENTER")

	if WorldMapFrame then
		local canvas = WorldMapFrame:GetCanvas()
		local worldFrame = CreateFrame("Frame", "ApexGathererRouteCanvas", canvas)
		worldFrame:SetAllPoints(canvas)
		world = newLayer(worldFrame, "TOPLEFT")
		hooksecurefunc(WorldMapFrame, "OnMapChanged", function() Drawing:DrawWorldMap() end)
		WorldMapFrame:HookScript("OnShow", function() Drawing:DrawWorldMap() end)
		canvas:HookScript("OnSizeChanged", function() Drawing:DrawWorldMap() end)
	end

	for _, message in ipairs({ "APEX_ROUTES_CHANGED", "APEX_SETTINGS_CHANGED" }) do
		self:RegisterMessage(message, "Refresh")
	end
	self:RegisterMessage("APEX_HUD_TOGGLED", "OnHUDToggled")
end
