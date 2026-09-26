--[[
	ApexGatherer: the addon object, its saved data and the helpers every other file uses.

	Saved data
	  ApexGathererDB      settings (AceDB: per-profile settings, plus account-wide values)
	  ApexGathererNodes   recorded nodes, learned node names and the unidentified-name log
	  ApexGathererRoutes  farming routes and taboo areas, per zone

	Coordinates are packed as one number, xxxxyyyy: x and y on the zone map (0..1) with four
	decimals each. Nodes, routes and shared messages all use this form.

	Messages (AceEvent) sent by the core
	  APEX_NODE_ADDED      kind, zone, coord, nodeID   a node was recorded (gathered or shared)
	  APEX_NODE_REMOVED    kind, zone, coord, nodeID
	  APEX_NODE_GATHERED   kind, zone, coord, nodeID   the player gathered it (after ADDED)
	  APEX_NODES_CHANGED                               many nodes changed at once (import, cleanup)
	  APEX_CATALOG_CHANGED kind, name, nodeID|nil      a node was learned or forgotten
	  APEX_SETTINGS_CHANGED                            display settings changed
]]
local ADDON, ns = ...
local Apex = LibStub("AceAddon-3.0"):NewAddon(ADDON, "AceEvent-3.0")
_G.ApexGatherer = Apex
ns.Apex = Apex

Apex.name = ADDON
Apex.version = C_AddOns.GetAddOnMetadata(ADDON, "Version") or ""
Apex.HBD = LibStub("HereBeDragons-2.0")
Apex.HBDPins = LibStub("HereBeDragons-Pins-2.0")
Apex.media = "Interface\\AddOns\\" .. ADDON .. "\\Media\\"

-- node kinds, in display order
Apex.KINDS = { "Mining", "Herbalism", "Fishing", "Treasure" }
Apex.KIND_LABEL = { Mining = "Mining", Herbalism = "Herbalism", Fishing = "Fishing", Treasure = "Treasure" }

local floor = math.floor

function Apex.PackXY(x, y)
	if x < 0 then x = 0 elseif x > 0.9999 then x = 0.9999 end
	if y < 0 then y = 0 elseif y > 0.9999 then y = 0.9999 end
	return floor(x * 10000 + 0.5) * 10000 + floor(y * 10000 + 0.5)
end

function Apex.UnpackXY(coord)
	return floor(coord / 10000) / 10000, (coord % 10000) / 10000
end

-- the minimap's radius in yards at its current zoom: the client says so directly where it can
-- (the table is the fallback), which keeps rings and lines in scale with the map and its blips
local MINIMAP_YARDS = {
	indoor  = { [0] = 300, 240, 180, 120, 80, 50 },
	outdoor = { [0] = 466 + 2 / 3, 400, 333 + 1 / 3, 266 + 2 / 3, 200, 133 + 1 / 3 },
}
-- the zoomed-out outdoor radius, from the client where it can say (any zoom scales to it)
local function outdoorRadius()
	local viewRadius = C_Minimap and C_Minimap.GetViewRadius and C_Minimap.GetViewRadius()
	local zoom = Minimap:GetZoom()
	if viewRadius and viewRadius > 0 and not IsIndoors() and MINIMAP_YARDS.outdoor[zoom] then
		return viewRadius * MINIMAP_YARDS.outdoor[0] / MINIMAP_YARDS.outdoor[zoom]
	end
end

-- ... or at another zoom level (0 = the widest view, up to MINIMAP_ZOOMS), scaled from the current
Apex.MINIMAP_ZOOMS = #MINIMAP_YARDS.outdoor
function Apex:MinimapRadiusYards(zoom)
	local sizes = MINIMAP_YARDS[IsIndoors() and "indoor" or "outdoor"]
	local current = Minimap:GetZoom()
	local viewRadius = C_Minimap and C_Minimap.GetViewRadius and C_Minimap.GetViewRadius()
	local radius = (viewRadius and viewRadius > 0) and viewRadius or (sizes[current] or sizes[0]) / 2
	if zoom and zoom ~= current and sizes[zoom] and sizes[current] then
		radius = radius * sizes[zoom] / sizes[current]
	end
	return radius
end

-- how far Find Minerals / Find Herbs show nodes: measured in WoW Forever at 80% of the
-- zoomed-out outdoor minimap's radius
local TRACKING_SHARE = 0.8
function Apex:TrackingRangeYards()
	local radius = outdoorRadius()
	if radius then
		self.db.global.viewRadius = radius   -- kept for when the client can't say (indoors)
	else
		radius = self.db.global.viewRadius or MINIMAP_YARDS.outdoor[0] / 2
	end
	return TRACKING_SHARE * radius
end

-- the tracking that shows a kind's nodes on the minimap: Find Minerals, Find Herbs, Find Fish,
-- Find Treasure. Returns nil when the client has no such spell, else whether it is on.
local TRACKING_SPELL = { Mining = 2580, Herbalism = 2383, Fishing = 43308, Treasure = 2481 }
local function trackingOn(kind)
	local wanted = TRACKING_SPELL[kind] and C_Spell.GetSpellName(TRACKING_SPELL[kind])
	if not wanted then return nil end
	for i = 1, C_Minimap.GetNumTrackingTypes() do
		local info = C_Minimap.GetTrackingInfo(i)
		if info and info.name == wanted then return info.active end
	end
	return false
end

-- whether a kind counts as tracked for showing its routes; a kind without a tracking spell does,
-- and so does treasure, which few can track
function Apex:TrackingActive(kind)
	if kind == "Treasure" then return true end
	return trackingOn(kind) ~= false
end

-- whether the minimap itself shows a kind's nodes (as blips) right now
function Apex:TrackingShows(kind)
	return trackingOn(kind) == true
end

-- a clustered route passes every node within this: half the tracking range, so each node shows
-- on the minimap well before the closest approach, and walks out to nodes that are up stay short
function Apex:DefaultClusterRadius()
	return math.floor(self:TrackingRangeYards() / 2 / 5 + 0.5) * 5
end

function Apex:ClusterRadius()
	return self.db.profile.routes.clusterRadius or self:DefaultClusterRadius()
end

function Apex:ZoneName(zone)
	return self.HBD:GetLocalizedMap(zone) or ("Zone " .. tostring(zone))
end

-- frame levels on the world map's canvas above its art and every pin: route lines and taboo
-- areas, then the editing handles on top of those
Apex.MAP_LINES_LEVEL = 2000
Apex.MAP_HANDLES_LEVEL = 2100

-- text colours, taken from the addon's icon: its gold peak, and its teal badge lightened to read
-- on dark backgrounds; a warm red for problems
Apex.GOLD = "|cffffd96b"
Apex.TEAL = "|cff5ccbd0"
Apex.WARN = "|cffe8674a"

function Apex:Print(...)
	print(self.GOLD .. ADDON .. "|r:", ...)
end

local defaults = {
	profile = {
		pins = {
			worldMap = true,
			minimap = true,
			worldMapScale = 1,
			minimapScale = 0.8,
			hudScale = 1,                  -- pins on the HUD, a little bigger than on the minimap
			alpha = 1,
			tooltips = true,
			show = { ["*"] = true },       -- per kind
			ring = true,                   -- a node tracking shows gets a ring round its blip, not a marker
			ringSize = 12,                 -- the ring's size in pixels: its inside edge on the blip's rim
			ringColor = {
				Mining    = { 1, 0.12, 0.1, 1 },
				Herbalism = { 0.3, 1, 0.3, 1 },
				Fishing   = { 1, 0.95, 0.3, 1 },
				Treasure  = { 1, 0.45, 1, 1 },
			},
			hidden = {},                   -- nodeID -> true: hidden by the filters
		},
		cleanupRange = { ["*"] = 15 },     -- yards; the same node closer than this is one spawn
		locked = { ["*"] = false },        -- per kind: stop recording
		sharing = {
			types        = { ["*"] = true },
			liveGuild    = false,
			acceptGuild  = true,
			askGuild     = true,
			answerGuild  = true,
			allowWhisper = true,
			announce     = true,
		},
		routes = {
			worldMap = true,
			minimap = true,
			color = { 0.25, 1, 0.25, 0.9 },
			worldMapWidth = 3,
			minimapWidth = 2,
			-- clusterRadius: nil = half the tracking range (Apex:DefaultClusterRadius)
			thorough = false,
		},
		minimapButton = { hide = false, angle = 220 },
		hud = {
			size = 0.7,                    -- fraction of the screen height
			alpha = 0.5,                   -- minimap terrain opacity while the HUD is open
			altAlpha = 0,                  -- ... after "toggle background"
			-- reach: yards from the player to the HUD's edge; nil = twice the tracking range
			mapArt = true,                 -- zoomed out past the minimap, the zone's map fills the rest
			rotate = true,                 -- turn with the camera while open
			mouse = false,                 -- start with mouse on (hover pins, no clicking through)
			hideInCombat = false,
			hideInInstance = false,
			circle = true, circleColor = { 0, 1, 0, 0.5 }, circleWidth = 2,   -- circleYards: nil = the tracking range
			compass = true, compassColor = { 1, 0.82, 0, 1 },
			coords = true,
			clock = false, clockServer = false,
			buttons = true,
			trail = true, trailColor = { 1, 1, 1, 0.7 },
			trailBy = "time", trailSeconds = 15, trailDots = 30,   -- keep the last so many seconds, or dots
			tracking = { ["*"] = "client" }, -- tracking name -> "client", "on" or "off" while open
		},
	},
	global = {
		flyoutWidth = 520,
	},
}

function Apex:OnInitialize()
	self.db = LibStub("AceDB-3.0"):New("ApexGathererDB", defaults, true)

	local nodes = type(ApexGathererNodes) == "table" and ApexGathererNodes or {}
	ApexGathererNodes = nodes
	nodes.kinds = nodes.kinds or {}
	for _, kind in ipairs(self.KINDS) do
		nodes.kinds[kind] = nodes.kinds[kind] or {}
	end
	nodes.learned = nodes.learned or { nextID = 9001, names = {} }
	nodes.unknown = nodes.unknown or {}
	self.nodeData = nodes

	local routes = type(ApexGathererRoutes) == "table" and ApexGathererRoutes or {}
	ApexGathererRoutes = routes
	routes.zones = routes.zones or {}
	self.routeData = routes

	self:LoadLearnedNodes()
	for _, callback in ipairs(self.initCallbacks or {}) do callback(self) end
	self.initCallbacks = nil
end

-- lets files that load before OnInitialize run code once the saved data exists
function Apex:OnSavedData(callback)
	if self.db then
		callback(self)
	else
		self.initCallbacks = self.initCallbacks or {}
		tinsert(self.initCallbacks, callback)
	end
end

function Apex:SettingsChanged()
	self:SendMessage("APEX_SETTINGS_CHANGED")
end
