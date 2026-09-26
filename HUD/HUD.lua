--[[
	The HUD: the minimap, enlarged and see-through, in the middle of the screen.

	Opening it moves the real minimap (its tracking blips, node pins and route lines come
	along) into a large frame centred on the screen and fades its terrain out. Everything else
	that hangs on the minimap (buttons, borders, other addons' icons) moves to a placeholder
	left where the minimap was, so the rest of the interface stays put. Closing it puts every
	piece back exactly as it was.

	The HUD zooms: its reach is how many yards it shows from you to its edge. Up to the minimap's
	widest view it is one of the minimap's own zoom levels, so the terrain fills the HUD. The
	minimap can't show terrain any further, so zoomed out past that (the default is twice the
	tracking range) the minimap's widest view fills the middle, at the HUD's scale, the HUD fills
	the rest with the minimap's own imagery (or the zone's world map), and draws the node pins,
	route lines and trail out to its edge.

	On top sit the HUD's own pieces: a range circle (by default, how far tracking reaches),
	compass letters, coordinates, a clock, a few buttons and a fading trail of where you've been.
]]
local Apex = ApexGatherer
local HUD = Apex:NewModule("HUD", "AceEvent-3.0")

local UnpackXY = Apex.UnpackXY
-- the minimap's own methods: other addons sometimes replace them on the frame
local MinimapMethods = getmetatable(Minimap).__index

-- tracking the Midnight client offers for retail systems WoW Forever doesn't have
local NOT_ON_FOREVER = { "focus target", "quest poi", "digsite", "account completed", "transmog", "item upgrade", "void storage" }

local frame, overlay, placeholder
local mapClip, mapArt    -- the map round the minimap: a frame clipping it to the HUD, and its pieces' frame
local artZone            -- the zone whose world-map art is loaded; nil to load it again
local saved              -- everything changed while open, to put back on close
local mouseOn, altBackground = false, false
local trail = {}         -- { x, y, time } in the current zone
local trailZone

local function settings() return Apex.db.profile.hud end

function HUD:IsOpen()
	return saved ~= nil
end

-- the HUD's frame, the overlay its pieces and pins sit on, and its radius in pixels
function HUD:Frame() return frame end
function HUD:Canvas() return overlay end
function HUD:Edge() return frame:GetWidth() / 2 end


------------------------------------------------------------------------------------------
-- Moving the minimap in and out

-- frames that ride along with the minimap instead of staying behind
local function ridesAlong(object)
	if object == frame or object == overlay or object == placeholder then return true end
	if Apex.HBDPins.minimapPins[object] then return true end
	if object == Apex:GetModule("RouteDrawing"):MinimapLayer() then return true end
	return object.isApexPin == true
end

local function collect(list, ...)
	for i = 1, select("#", ...) do list[#list + 1] = select(i, ...) end
end

-- everything that could hang on the minimap: the pieces of the minimap, its parent, its cluster
-- and its backdrop, and one level into their child frames (the compass ring and north marker
-- live on the backdrop, anchored to the minimap)
local function attachmentCandidates()
	local roots, list, seen = { Minimap, saved.parent, MinimapCluster, MinimapBackdrop }, {}, {}
	local function add(object)
		if object and not seen[object] and object ~= Minimap then
			seen[object] = true
			list[#list + 1] = object
		end
	end
	for _, root in ipairs(roots) do
		if root then
			local level = {}
			collect(level, root:GetChildren())
			collect(level, root:GetRegions())
			for _, object in ipairs(level) do
				add(object)
				if object.GetChildren and object ~= Minimap and not ridesAlong(object) then
					local deeper = {}
					collect(deeper, object:GetChildren())
					collect(deeper, object:GetRegions())
					for _, inner in ipairs(deeper) do add(inner) end
				end
			end
		end
	end
	return list
end

-- moves whatever hangs on the minimap to the placeholder, remembering how to undo it
local function moveAttachments()
	for _, object in ipairs(attachmentCandidates()) do
		if not ridesAlong(object) and not (object.IsProtected and object:IsProtected()) then
			local entry = { object = object }
			if object:GetParent() == Minimap then
				entry.parent = Minimap
				object:SetParent(placeholder)
			end
			local points, moved = {}, false
			for i = 1, object:GetNumPoints() do
				local point, relativeTo, relativePoint, x, y = object:GetPoint(i)
				points[i] = { point, relativeTo, relativePoint, x, y }
				if relativeTo == Minimap then moved = true end
			end
			if moved then
				entry.points = points
				object:ClearAllPoints()
				for _, p in ipairs(points) do
					object:SetPoint(p[1], p[2] == Minimap and placeholder or p[2], p[3], p[4], p[5])
				end
			end
			if entry.parent or entry.points then tinsert(saved.moved, entry) end
		end
	end
end

local function restoreAttachments()
	for i = #saved.moved, 1, -1 do
		local entry = saved.moved[i]
		local object = entry.object
		if entry.parent then object:SetParent(entry.parent) end
		if entry.points then
			object:ClearAllPoints()
			for _, p in ipairs(entry.points) do object:SetPoint(p[1], p[2], p[3], p[4], p[5]) end
		end
	end
end

local function hudSize()
	return math.floor(UIParent:GetHeight() * settings().size)
end

function HUD:DefaultReach()
	return math.floor(Apex:TrackingRangeYards() * 2 / 5 + 0.5) * 5
end

-- the minimap zoom level whose view is nearest to yards, and that view's radius
local function nearestZoom(yards)
	local best, bestRadius
	for zoom = 0, Apex.MINIMAP_ZOOMS do
		local radius = Apex:MinimapRadiusYards(zoom)
		if not best or math.abs(radius - yards) < math.abs(bestRadius - yards) then best, bestRadius = zoom, radius end
	end
	return best, bestRadius
end

-- what the HUD shows for a reach setting: closer in than the minimap's widest view, the nearest
-- of its zoom levels; past it, the setting itself
function HUD:ReachFor(yards)
	if yards < Apex:MinimapRadiusYards(0) then return (select(2, nearestZoom(yards))) end
	return yards
end

-- yards from the player to the HUD's edge
function HUD:Reach()
	return self:ReachFor(settings().reach or self:DefaultReach())
end

-- zooms the minimap to the HUD's reach (or its widest view) and sizes it to the HUD's scale:
-- it fills the HUD, or only the middle when the HUD reaches further than it can show
local fittedRadius   -- the minimap's reach in yards when it was last fitted
local function fitMinimap()
	local reach = HUD:Reach()
	local zoom = reach < Apex:MinimapRadiusYards(0) and nearestZoom(reach) or 0
	if Minimap:GetZoom() ~= zoom then MinimapMethods.SetZoom(Minimap, zoom) end
	fittedRadius = Apex:MinimapRadiusYards()
	local size = hudSize() * math.min(1, fittedRadius / reach)
	MinimapMethods.SetSize(Minimap, size, size)
end

local function applyBackground()
	local s = settings()
	local alpha = altBackground and s.altAlpha or s.alpha
	MinimapMethods.SetAlpha(Minimap, alpha)
	mapClip:SetAlpha(alpha)
end

local function applyMouse()
	MinimapMethods.EnableMouse(Minimap, mouseOn)
	Apex:GetModule("Pins"):SetMinimapMouse(mouseOn)
	if HUD.buttons then HUD.buttons.mouse:SetText(mouseOn and "Mouse: on" or "Mouse: off") end
end

-- tracking wanted while the HUD is open, by tracking name
local function applyTracking()
	for i = 1, C_Minimap.GetNumTrackingTypes() do
		local info = C_Minimap.GetTrackingInfo(i)
		local want = info and settings().tracking[info.name]
		if want == "on" or want == "off" then
			local active = want == "on"
			if info.active ~= active then
				tinsert(saved.tracking, { index = i, active = info.active })
				C_Minimap.SetTracking(i, active)
			end
		end
	end
end

function HUD:Open()
	if saved then return end
	if InCombatLockdown() and Minimap:IsProtected() then
		Apex:Print("the HUD can't open during combat.")
		return
	end
	saved = { moved = {}, tracking = {}, points = {} }
	saved.parent = Minimap:GetParent()
	for i = 1, Minimap:GetNumPoints() do saved.points[i] = { Minimap:GetPoint(i) } end
	saved.width, saved.height = Minimap:GetSize()
	saved.scale, saved.alpha = Minimap:GetScale(), Minimap:GetAlpha()
	saved.strata, saved.level = Minimap:GetFrameStrata(), Minimap:GetFrameLevel()
	saved.zoom = Minimap:GetZoom()
	saved.mouse, saved.wheel = Minimap:IsMouseEnabled(), Minimap:IsMouseWheelEnabled()
	saved.rotate = GetCVar("rotateMinimap")

	-- the placeholder takes the minimap's place, size and anchors
	placeholder:SetParent(saved.parent)
	placeholder:ClearAllPoints()
	for _, p in ipairs(saved.points) do placeholder:SetPoint(p[1], p[2], p[3], p[4], p[5]) end
	placeholder:SetSize(saved.width, saved.height)
	placeholder:SetScale(saved.scale)
	placeholder:Show()
	moveAttachments()

	local size = hudSize()
	frame:SetSize(size, size)
	frame:Show()
	MinimapMethods.SetParent(Minimap, frame)
	MinimapMethods.ClearAllPoints(Minimap)
	MinimapMethods.SetPoint(Minimap, "CENTER", frame, "CENTER")
	MinimapMethods.SetScale(Minimap, 1)
	MinimapMethods.SetFrameStrata(Minimap, "LOW")
	fitMinimap()
	MinimapMethods.EnableMouseWheel(Minimap, false)
	if settings().rotate then SetCVar("rotateMinimap", "1") end

	mouseOn, altBackground = settings().mouse, false
	artZone = nil
	applyBackground()
	applyMouse()
	applyTracking()
	self:Layout()
	overlay:Show()
	self:SendMessage("APEX_HUD_TOGGLED", true)
end

function HUD:Close()
	if not saved then return end
	overlay:Hide()
	MinimapMethods.SetParent(Minimap, saved.parent)
	MinimapMethods.ClearAllPoints(Minimap)
	for _, p in ipairs(saved.points) do MinimapMethods.SetPoint(Minimap, p[1], p[2], p[3], p[4], p[5]) end
	MinimapMethods.SetScale(Minimap, saved.scale)
	MinimapMethods.SetSize(Minimap, saved.width, saved.height)
	MinimapMethods.SetFrameStrata(Minimap, saved.strata)
	MinimapMethods.SetFrameLevel(Minimap, saved.level)
	MinimapMethods.SetAlpha(Minimap, saved.alpha)
	MinimapMethods.SetZoom(Minimap, saved.zoom)
	MinimapMethods.EnableMouse(Minimap, saved.mouse)
	MinimapMethods.EnableMouseWheel(Minimap, saved.wheel)
	restoreAttachments()
	placeholder:Hide()
	frame:Hide()
	SetCVar("rotateMinimap", saved.rotate)
	for _, t in ipairs(saved.tracking) do C_Minimap.SetTracking(t.index, t.active) end
	Apex:GetModule("Pins"):SetMinimapMouse(true)
	saved = nil
	self:SendMessage("APEX_HUD_TOGGLED", false)
end

function HUD:Toggle(force)
	if force == nil then force = not saved end
	if force then self:Open() else self:Close() end
end

function HUD:ToggleMouse()
	if not saved then return end
	mouseOn = not mouseOn
	applyMouse()
end

function HUD:ToggleBackground()
	if not saved then return end
	altBackground = not altBackground
	applyBackground()
end

-- tracking types the HUD settings offer (the ones that exist on Forever)
function HUD:TrackingTypes()
	local list = {}
	for i = 1, C_Minimap.GetNumTrackingTypes() do
		local info = C_Minimap.GetTrackingInfo(i)
		local name = info and info.name
		if type(name) == "string" then
			local lower, keep = name:lower(), true
			for _, pattern in ipairs(NOT_ON_FOREVER) do
				if lower:find(pattern, 1, true) then keep = false end
			end
			if keep then list[#list + 1] = { name = name, icon = info.texture } end
		end
	end
	return list
end


------------------------------------------------------------------------------------------
-- The HUD's own pieces

local coords, clock, compass, northArrow = nil, nil, {}, nil
local CIRCLE_SEGMENTS = 120
local circleLines = {}
local drawnRadius, drawnWidth   -- what the circle's lines were last placed for

-- the range circle as short lines, so its line keeps the same width at any radius
local function drawCircle(radius, width)
	if radius == drawnRadius and width == drawnWidth then return end
	drawnRadius, drawnWidth = radius, width
	local step = 2 * math.pi / CIRCLE_SEGMENTS
	for i = 1, CIRCLE_SEGMENTS do
		local line = circleLines[i]
		local a, b = (i - 1) * step, i * step
		line:SetThickness(width)
		line:SetStartPoint("CENTER", overlay, math.cos(a) * radius, math.sin(a) * radius)
		line:SetEndPoint("CENTER", overlay, math.cos(b) * radius, math.sin(b) * radius)
	end
end
local trailDots = {}
local COMPASS = { { "N", 0 }, { "E", -90 }, { "S", 180 }, { "W", 90 } }

-- pixels per yard: the minimap's, which the whole HUD keeps
local function pixelsPerYard()
	return (Minimap:GetWidth() / 2) / Apex:MinimapRadiusYards()
end

local function rotation()
	if GetCVar("rotateMinimap") ~= "1" then return 0, 1 end
	local angle = -(GetPlayerFacing() or 0)
	return math.sin(angle), math.cos(angle)
end

function HUD:Layout()
	local s = settings()
	local size = hudSize()
	if saved then
		frame:SetSize(size, size)
		fitMinimap()
	end
	overlay:SetAllPoints(frame)

	local c = s.circleColor
	for _, line in ipairs(circleLines) do
		line:SetShown(s.circle)
		line:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
	end
	for _, letter in ipairs(compass) do
		letter:SetShown(s.compass)
		letter:SetTextColor(unpack(s.compassColor))
	end
	northArrow:SetShown(s.compass)
	northArrow:SetVertexColor(unpack(s.compassColor))
	coords:SetShown(s.coords)
	clock:SetShown(s.clock)
	self.buttons:SetShown(s.buttons)
	self.buttons:ClearAllPoints()
	self.buttons:SetPoint("TOP", frame, "BOTTOM", 0, -4)
	if not s.trail then
		wipe(trail)
		for _, dot in ipairs(trailDots) do dot:Hide() end
	end
end

local TRAIL_STEP = 3   -- yards walked before the trail gets another dot
local TRAIL_GAP = 24   -- pixels round the player the trail leaves clear: about one player arrow
HUD.TRAIL_GAP = TRAIL_GAP

-- the trail keeps the last so many seconds, or the last so many dots (one every TRAIL_STEP yards);
-- it starts a player arrow behind you, so it doesn't cover you or the node you stand at
local function updateTrail(x, y, zone, now, perYard, sin, cos, edge)
	local s = settings()
	if zone ~= trailZone then
		wipe(trail)
		trailZone = zone
	end
	local w, h = Apex.HBD:GetZoneSize(zone)
	local last = trail[#trail]
	if not last or ((x - last[1]) * w) ^ 2 + ((y - last[2]) * h) ^ 2 > TRAIL_STEP * TRAIL_STEP then
		trail[#trail + 1] = { x, y, now }
	end
	local byDots = s.trailBy == "dots"
	if byDots then
		while #trail > s.trailDots do tremove(trail, 1) end
	else
		while trail[1] and now - trail[1][3] > s.trailSeconds do tremove(trail, 1) end
	end

	local used = 0
	for i, point in ipairs(trail) do
		local dx, dy = (point[1] - x) * w * perYard, -(point[2] - y) * h * perYard
		local rx, ry = dx * cos - dy * sin, dx * sin + dy * cos
		local d2 = rx * rx + ry * ry
		if d2 < edge * edge and d2 >= TRAIL_GAP * TRAIL_GAP then
			used = used + 1
			local dot = trailDots[used]
			if not dot then
				dot = overlay:CreateTexture(nil, "ARTWORK")
				dot:SetTexture(Apex.media .. "Dot")
				dot:SetSize(8, 8)
				trailDots[used] = dot
			end
			-- fades toward the far end of the trail
			local fade = byDots and (i / s.trailDots) or (1 - (now - point[3]) / s.trailSeconds)
			local c = s.trailColor
			dot:SetVertexColor(c[1], c[2], c[3], (c[4] or 1) * math.max(0, fade))
			dot:SetPoint("CENTER", overlay, "CENTER", rx, ry)
			dot:Show()
		end
	end
	for i = used + 1, #trailDots do trailDots[i]:Hide() end
end


------------------------------------------------------------------------------------------
-- The map round the minimap

-- Past the minimap's live terrain, the HUD fills in the rest of the world round you. Best is the
-- game's own minimap imagery: one texture per 533-yard square of the world, loaded by file id
-- (HUD/MinimapTiles.lua lists them; the client doesn't know their names). Where there is none,
-- the zone's world-map art stands in, one piece per tile. Either way each piece is a texture placed round you like the pins
-- and turned with the camera (SetRotation turns a texture's whole rectangle), faded like the
-- terrain, and shaped by two masks: the HUD's circle, less the minimap's middle.
local TILE_YARDS = 1600 / 3   -- the side of a square of the world, and of its minimap texture
local CONTINENT = { [0] = "Azeroth", [1] = "Kalimdor" }   -- the minimap texture folders, by instance
local HOLE_FADE = 0.95        -- where the hole mask's fade is centred, as a share of its radius
local tileFiles = {}          -- "instance:x:y" -> the square's minimap texture, or false if there is none
local artPieces = {}          -- artZone's world-map art: { file, u0, u1, v0, v1, x0, x1, y0, y1 } on the zone map
local pieces, pieceCount = {}, 0   -- this update's pieces: { file, u0, u1, v0, v1, dx, dy, width, height } in yards
local pieceTextures = {}
local edgeMask, holeMask

-- the minimap texture of the square (tx, ty) of an instance's grid of 64 x 64: from the list, or
-- by name where the client knows it
local function tileFile(instance, tx, ty)
	local key = instance .. ":" .. tx .. ":" .. ty
	if tileFiles[key] == nil then
		local listed = Apex.MINIMAP_TILES[instance]
		local file = listed and listed[tx * 64 + ty]
		if not file and GetFileIDFromPath then
			file = GetFileIDFromPath(("World\\Minimaps\\%s\\map%d_%d.blp"):format(CONTINENT[instance], tx, ty))
		end
		tileFiles[key] = file or false
	end
	return tileFiles[key]
end

local function addPiece(file, u0, u1, v0, v1, dx, dy, width, height)
	pieceCount = pieceCount + 1
	local piece = pieces[pieceCount]
	if not piece then
		piece = {}
		pieces[pieceCount] = piece
	end
	piece.file, piece.u0, piece.u1, piece.v0, piece.v1 = file, u0, u1, v0, v1
	piece.dx, piece.dy, piece.width, piece.height = dx, dy, width, height
end

-- the minimap squares within reach yards of the player; false if the client can't load the one
-- they stand in. World x runs west and y north (as HereBeDragons gives them), and the squares
-- count east (tx) and south (ty) from the world's north-west corner.
local function addTiles(reach)
	local wx, wy, instance = Apex.HBD:GetPlayerWorldPosition()
	if not wx or not CONTINENT[instance] then return false end
	if not tileFile(instance, math.floor(32 - wx / TILE_YARDS), math.floor(32 - wy / TILE_YARDS)) then return false end
	for tx = math.floor(32 - (wx + reach) / TILE_YARDS), math.floor(32 - (wx - reach) / TILE_YARDS) do
		for ty = math.floor(32 - (wy + reach) / TILE_YARDS), math.floor(32 - (wy - reach) / TILE_YARDS) do
			local file = tileFile(instance, tx, ty)
			if file then
				addPiece(file, 0, 1, 0, 1, wx - (31.5 - tx) * TILE_YARDS, (31.5 - ty) * TILE_YARDS - wy, TILE_YARDS, TILE_YARDS)
			end
		end
	end
	return true
end

-- the tiles of a zone's most detailed world-map art layer
local function loadArt(zone)
	artZone = zone
	wipe(artPieces)
	local layers = C_Map.GetMapArtLayers and C_Map.GetMapArtLayers(zone)
	local index = layers and #layers or 0
	local layer = index > 0 and layers[index]
	local files = layer and C_Map.GetMapArtLayerTextures(zone, index)
	if not files then return end
	local width, height = layer.layerWidth, layer.layerHeight
	local tileWidth, tileHeight = layer.tileWidth, layer.tileHeight
	local cols = math.ceil(width / tileWidth)
	for row = 1, math.ceil(height / tileHeight) do
		for col = 1, cols do
			local file = files[(row - 1) * cols + col]
			local left, top = (col - 1) * tileWidth, (row - 1) * tileHeight
			-- the last row and column of tiles hang past the map: only their part on it is drawn
			local uMax, vMax = math.min(1, (width - left) / tileWidth), math.min(1, (height - top) / tileHeight)
			if file then
				artPieces[#artPieces + 1] = {
					file = file, u0 = 0, u1 = uMax, v0 = 0, v1 = vMax,
					x0 = left / width, x1 = (left + uMax * tileWidth) / width,
					y0 = top / height, y1 = (top + vMax * tileHeight) / height,
				}
			end
		end
	end
end

-- the world-map art round the player at (x, y) on the zone map
local function addArt(x, y, zone)
	local w, h = Apex.HBD:GetZoneSize(zone)
	if w == 0 then return end
	if zone ~= artZone then loadArt(zone) end
	for _, art in ipairs(artPieces) do
		addPiece(art.file, art.u0, art.u1, art.v0, art.v1, ((art.x0 + art.x1) / 2 - x) * w,
			-((art.y0 + art.y1) / 2 - y) * h, (art.x1 - art.x0) * w, (art.y1 - art.y0) * h)
	end
end

local function pieceTexture(i, piece)
	local tex = pieceTextures[i]
	if not tex then
		tex = mapArt:CreateTexture(nil, "ARTWORK")
		pieceTextures[i] = tex
		tex:AddMaskTexture(edgeMask)
		tex:AddMaskTexture(holeMask)
	end
	if tex.file ~= piece.file or tex.u0 ~= piece.u0 or tex.u1 ~= piece.u1 or tex.v0 ~= piece.v0 or tex.v1 ~= piece.v1 then
		tex.file, tex.u0, tex.u1, tex.v0, tex.v1 = piece.file, piece.u0, piece.u1, piece.v0, piece.v1
		tex:SetTexture(piece.file)
		tex:SetTexCoord(piece.u0, piece.u1, piece.v0, piece.v1)
	end
	return tex
end

-- the map round the minimap, when the HUD reaches past it
local function drawMap(x, y, zone, perYard, sin, cos, edge)
	local disc = Minimap:GetWidth() / 2
	local show = settings().mapArt and disc < edge * 0.99
	mapClip:SetShown(show)
	if not show then return end
	pieceCount = 0
	if not addTiles(edge / perYard) then addArt(x, y, zone) end
	holeMask:SetSize(2 * disc / HOLE_FADE, 2 * disc / HOLE_FADE)
	local inner, angle = disc * 0.9, math.atan2(sin, cos)   -- pieces wholly inside inner are under the terrain
	local used = 0
	for i = 1, pieceCount do
		local piece = pieces[i]
		local cx = (piece.dx * cos - piece.dy * sin) * perYard
		local cy = (piece.dx * sin + piece.dy * cos) * perYard
		local width, height = piece.width * perYard, piece.height * perYard
		local corner = math.sqrt(width * width + height * height) / 2
		local d = math.sqrt(cx * cx + cy * cy)
		if d - corner < edge and d + corner > inner then
			used = used + 1
			local tex = pieceTexture(used, piece)
			tex:SetPoint("CENTER", mapArt, "CENTER", cx, cy)
			tex:SetSize(width, height)   -- edge to edge: overlapping pieces would show, faded as they are
			tex:SetRotation(angle)
			tex:Show()
		end
	end
	for i = used + 1, #pieceTextures do pieceTextures[i]:Hide() end
end

local function overlayUpdate(_, elapsed)
	HUD.wait = (HUD.wait or 0) - elapsed
	if HUD.wait > 0 then return end
	HUD.wait = 0.05
	local s = settings()
	if Apex:MinimapRadiusYards() ~= fittedRadius then fitMinimap() end   -- going indoors or out
	local perYard = pixelsPerYard()
	local sin, cos = rotation()
	local edge = HUD:Edge()
	if s.circle then
		drawCircle((s.circleYards or Apex:TrackingRangeYards()) * perYard, s.circleWidth)
	end
	if s.compass then
		for i, letter in ipairs(compass) do
			local a = math.rad(COMPASS[i][2])
			-- north is straight up when the map doesn't turn; otherwise it turns with the camera
			local ux, uy = -math.sin(a), math.cos(a)
			letter:SetPoint("CENTER", overlay, "CENTER", (ux * cos - uy * sin) * (edge - 30), (ux * sin + uy * cos) * (edge - 30))
		end
		-- the north arrow sits on the rim just beyond the N, pointing out
		northArrow:SetPoint("CENTER", overlay, "CENTER", -sin * (edge - 10), cos * (edge - 10))
		northArrow:SetRotation(math.atan2(sin, cos))
	end
	local x, y, zone = Apex.HBD:GetPlayerZonePosition()
	if s.coords then coords:SetText(x and ("%.1f, %.1f"):format(x * 100, y * 100) or "") end
	if s.clock then
		if s.clockServer then
			local hour, minute = GetGameTime()
			clock:SetText(("%02d:%02d"):format(hour, minute))
		else
			clock:SetText(date("%H:%M"))
		end
	end
	if x and zone then
		if s.trail then updateTrail(x, y, zone, GetTime(), perYard, sin, cos, edge) end
		Apex:GetModule("Pins"):PlaceHUD(x, y, zone, perYard, sin, cos, edge)
		drawMap(x, y, zone, perYard, sin, cos, edge)
	end
end

local function smallButton(parent, text, onClick)
	local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	button:SetSize(78, 20)
	button:SetText(text)
	button:SetScript("OnClick", onClick)
	return button
end

local function createFrames()
	frame = CreateFrame("Frame", "ApexGathererHUD", UIParent)
	frame:SetPoint("CENTER")
	frame:SetFrameStrata("LOW")
	frame:Hide()

	placeholder = CreateFrame("Frame", "ApexGathererHUDPlaceholder", UIParent)
	placeholder:Hide()

	-- the zone map, under the minimap
	mapClip = CreateFrame("Frame", nil, frame)
	mapClip:SetAllPoints(frame)
	mapClip:SetFrameStrata("BACKGROUND")
	mapClip:SetClipsChildren(true)
	mapClip:Hide()
	mapArt = CreateFrame("Frame", "ApexGathererHUDMap", mapClip)
	mapArt:SetAllPoints(mapClip)
	edgeMask = mapArt:CreateMaskTexture()
	edgeMask:SetTexture(Apex.media .. "MaskRound", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	edgeMask:SetAllPoints(mapArt)
	holeMask = mapArt:CreateMaskTexture()
	holeMask:SetTexture(Apex.media .. "MaskHole", "CLAMPTOWHITE", "CLAMPTOWHITE")
	holeMask:SetPoint("CENTER")

	overlay = CreateFrame("Frame", "ApexGathererHUDOverlay", frame)
	overlay:SetFrameStrata("MEDIUM")
	overlay:SetAllPoints(frame)
	overlay:Hide()
	overlay:SetScript("OnUpdate", overlayUpdate)

	for i = 1, CIRCLE_SEGMENTS do circleLines[i] = overlay:CreateLine(nil, "ARTWORK") end
	for i, entry in ipairs(COMPASS) do
		local letter = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
		letter:SetText(entry[1])
		compass[i] = letter
	end
	northArrow = overlay:CreateTexture(nil, "OVERLAY")
	northArrow:SetTexture(Apex.media .. "North")
	northArrow:SetSize(20, 20)
	coords = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	coords:SetPoint("CENTER", overlay, "CENTER", 0, -40)
	clock = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	clock:SetPoint("CENTER", overlay, "CENTER", 0, -58)

	local buttons = CreateFrame("Frame", nil, overlay)
	buttons:SetSize(4 * 82, 22)
	buttons.mouse = smallButton(buttons, "Mouse: off", function() HUD:ToggleMouse() end)
	buttons.background = smallButton(buttons, "Background", function() HUD:ToggleBackground() end)
	buttons.settings = smallButton(buttons, "Settings", function() Apex:OpenSettings() end)
	buttons.close = smallButton(buttons, "Close", function() HUD:Close() end)
	buttons.mouse:SetPoint("LEFT")
	buttons.background:SetPoint("LEFT", buttons.mouse, "RIGHT", 4, 0)
	buttons.settings:SetPoint("LEFT", buttons.background, "RIGHT", 4, 0)
	buttons.close:SetPoint("LEFT", buttons.settings, "RIGHT", 4, 0)
	HUD.buttons = buttons
end


------------------------------------------------------------------------------------------
-- Hiding in combat and instances

local hiddenBy   -- why an open HUD was closed for now, so it can come back
local inCombat = false   -- from the combat events: InCombatLockdown() is still false while entering combat

function HUD:CheckAutoHide(event)
	if event == "PLAYER_REGEN_DISABLED" then
		inCombat = true
	elseif event == "PLAYER_REGEN_ENABLED" then
		inCombat = false
	elseif event == "PLAYER_ENTERING_WORLD" then
		inCombat = UnitAffectingCombat("player") or false
	end
	local s = settings()
	local inInstance = select(2, IsInInstance()) ~= "none"
	local reason = (s.hideInCombat and inCombat and "combat") or (s.hideInInstance and inInstance and "instance") or nil
	if reason and saved then
		hiddenBy = reason
		self:Close()
	elseif not reason and hiddenBy then
		hiddenBy = nil
		self:Open()
	end
end

function HUD:OnEnable()
	createFrames()
	self:RegisterEvent("PLAYER_REGEN_DISABLED", "CheckAutoHide")
	self:RegisterEvent("PLAYER_REGEN_ENABLED", "CheckAutoHide")
	self:RegisterEvent("PLAYER_ENTERING_WORLD", "CheckAutoHide")
	self:RegisterEvent("PLAYER_LOGOUT", function() self:Close() end)
	self:RegisterMessage("APEX_SETTINGS_CHANGED", function()
		if saved then
			applyBackground()
			HUD:Layout()
		end
	end)
end
