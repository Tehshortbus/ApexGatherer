--[[
	The HUD settings page (registered by UI/Settings.lua under ApexGatherer > HUD).
]]
local Apex = ApexGatherer
local HUD = Apex:GetModule("HUD")

local function s() return Apex.db.profile.hud end
local function changed() Apex:SettingsChanged() end

local function color(key)
	return {
		get = function() local c = s()[key]; return c[1], c[2], c[3], c[4] end,
		set = function(_, r, g, b, a) s()[key] = { r, g, b, a }; changed() end,
	}
end

local TRACKING_VALUES = { client = "Like the minimap", on = "On", off = "Off" }

local function trackingArgs()
	local args = {
		desc = {
			order = 0, type = "description", width = "full",
			name = "Tracking to switch on or off while the HUD is open; it goes back when the HUD closes.\n",
		},
	}
	for i, t in ipairs(HUD:TrackingTypes()) do
		args["t" .. i] = {
			order = i, type = "select", values = TRACKING_VALUES,
			name = t.icon and ("|T%s:18:18|t %s"):format(t.icon, t.name) or t.name,
			get = function() return s().tracking[t.name] end,
			set = function(_, v) s().tracking[t.name] = v end,
		}
	end
	return args
end

local options = {
	type = "group", name = "HUD", childGroups = "tab",
	get = function(info) return s()[info[#info]] end,
	set = function(info, v) s()[info[#info]] = v; changed() end,
	args = {
		general = {
			order = 1, type = "group", name = "General",
			args = {
				toggle = { order = 1, type = "execute", name = "Toggle HUD", func = function() HUD:Toggle() end },
				size = { order = 2, type = "range", name = "Size (share of the screen height)", min = 0.3, max = 1, step = 0.05, isPercent = true, width = "double" },
				reach = {
					order = 3, type = "range", name = "Zoom (yards to the edge)", min = 65, max = 1000, step = 5, width = "double",
					desc = function()
						return ("How much of the world the HUD shows: the yards from you to its edge. Size only makes it "
							.. "bigger on screen.\n\nUp to %d yards it's one of the minimap's own zoom steps, and the "
							.. "terrain fills the HUD. The minimap can't show terrain further out than that, so zoomed out "
							.. "past it the terrain stays a disc in the middle, and the HUD draws node pins, routes and your "
							.. "trail out to its edge.\n\nIt starts at twice the tracking range, %d yards, so the range "
							.. "circle sits halfway out."):format(math.floor(Apex:MinimapRadiusYards(0) + 0.5), HUD:DefaultReach())
					end,
					get = function() return math.floor(HUD:ReachFor(s().reach or HUD:DefaultReach()) + 0.5) end,
					set = function(_, v)
						s().reach = math.floor(HUD:ReachFor(v) + 0.5)
						changed()
					end,
				},
				reachReset = {
					order = 4, type = "execute", name = "Twice the tracking range",
					disabled = function() return s().reach == nil end,
					func = function() s().reach = nil; changed() end,
				},
				mapArt = {
					order = 5, type = "toggle", width = "full", name = "Fill in the map past the terrain",
					desc = "Zoomed out further than the minimap can show, the rest of the HUD shows the minimap's own "
						.. "imagery of the land round you (or the zone's world map, where the game can't provide it), "
						.. "faded like the terrain.",
				},
				alpha = { order = 6, type = "range", name = "Map background", desc = "How much of the minimap's terrain (and the zone map round it) shows; 0 = none.", min = 0, max = 1, step = 0.05, isPercent = true },
				altAlpha = { order = 7, type = "range", name = "Background when toggled", desc = "The terrain and map after Toggle background.", min = 0, max = 1, step = 0.05, isPercent = true },
				rotate = { order = 8, type = "toggle", name = "Turn with the camera", width = "full" },
				mouse = {
					order = 9, type = "toggle", width = "full", name = "Start with the mouse on",
					desc = "With the mouse on, pins show tooltips, but you can't click through the HUD.",
				},
				hideInCombat = { order = 10, type = "toggle", name = "Hide in combat", width = "full" },
				hideInInstance = { order = 11, type = "toggle", name = "Hide in dungeons and raids", width = "full" },
			},
		},
		pieces = {
			order = 2, type = "group", name = "Pieces",
			args = {
				circle = { order = 1, type = "toggle", name = "Range circle" },
				circleYards = {
					order = 2, type = "range", name = "Circle radius (yards)", min = 5, max = 300, step = 1,
					desc = function()
						return ("Starts at how far tracking finds nodes: about %d yards."):format(Apex:TrackingRangeYards())
					end,
					get = function() return math.floor((s().circleYards or Apex:TrackingRangeYards()) + 0.5) end,
				},
				circleReset = {
					order = 4, type = "execute", name = "Back to the tracking range",
					disabled = function() return s().circleYards == nil end,
					func = function() s().circleYards = nil; changed() end,
				},
				circleWidth = { order = 5, type = "range", name = "Circle line width", min = 1, max = 10, step = 0.5 },
				circleColor = { order = 3, type = "color", name = "Circle color", hasAlpha = true, get = color("circleColor").get, set = color("circleColor").set },
				compass = { order = 10, type = "toggle", name = "Compass letters" },
				compassColor = { order = 11, type = "color", name = "Compass color", hasAlpha = true, get = color("compassColor").get, set = color("compassColor").set },
				coords = { order = 20, type = "toggle", name = "Coordinates" },
				clock = { order = 21, type = "toggle", name = "Clock" },
				clockServer = { order = 22, type = "toggle", name = "Server time", disabled = function() return not s().clock end },
				buttons = { order = 30, type = "toggle", name = "Buttons under the HUD", width = "full" },
				trail = { order = 40, type = "toggle", name = "Trail" },
				trailBy = {
					order = 41, type = "select", name = "Trail length by",
					values = { time = "Time", dots = "Number of dots" },
				},
				trailSeconds = {
					order = 42, type = "range", name = "Trail length (seconds)", min = 5, max = 600, step = 5,
					hidden = function() return s().trailBy == "dots" end,
				},
				trailDots = {
					order = 42, type = "range", name = "Trail length (dots)", min = 5, max = 300, step = 1,
					desc = "A dot is dropped every 3 yards you move.",
					hidden = function() return s().trailBy ~= "dots" end,
				},
				trailColor = { order = 43, type = "color", name = "Trail color", hasAlpha = true, get = color("trailColor").get, set = color("trailColor").set },
			},
		},
		tracking = { order = 3, type = "group", name = "Tracking", args = {} },   -- filled when shown
	},
}

-- the tracking list is built the first time the page shows (and again if the client's list changes)
local builtFor
options.args.tracking.hidden = function()
	local count = C_Minimap.GetNumTrackingTypes()
	if count ~= builtFor then
		builtFor = count
		options.args.tracking.args = trackingArgs()
	end
	return false
end

function HUD:GetOptions()
	return options
end
