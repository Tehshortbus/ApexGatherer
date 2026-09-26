--[[
	The routes panel (AceConfig app "ApexGatherer/Routes"), shown docked beside the world map
	by Routes/Flyout.lua. Pages: New route, Taboo areas, Display, then one entry per zone with
	its routes; each route has Info, Look, Optimize and Taboos tabs.
]]
local Apex = ApexGatherer
local Catalog = Apex.Catalog
local Routes = Apex:GetModule("Routes")
local Editor = Apex:GetModule("RouteEditor")
local Options = Apex:NewModule("RouteOptions", "AceEvent-3.0")

local ACR = LibStub("AceConfigRegistry-3.0")
local APP = "ApexGatherer/Routes"
Options.APP = APP

local status = {}          -- zone .. name -> last optimizer message
local newRoute = { name = "", nodes = {} }
local newTaboo = { name = "" }

local function notify() ACR:NotifyChange(APP) end

local function report(ok, err)
	if not ok and err then Apex:Print(err) end
	return ok
end

-- the zone the map shows, for the zone pickers' default
local function mapZone()
	return WorldMapFrame and WorldMapFrame:IsShown() and WorldMapFrame:GetMapID() or Apex.HBD:GetPlayerZone()
end

local function zonesWithNodes()
	local out = {}
	for _, zone in ipairs(Apex:ZonesWithNodes()) do out[zone] = Apex:ZoneName(zone) end
	local here = mapZone()
	if here and not out[here] then out[here] = Apex:ZoneName(here) end
	return out
end

local SHOW_VALUES = { always = "Always", tracking = "While tracking its nodes", never = "Never (hidden)" }


------------------------------------------------------------------------------------------
-- One route

local function routeGroup(zone, name, order)
	local key = zone .. "\001" .. name
	-- the panel can redraw once more after a route is renamed or deleted
	local function route() return Routes:Get(zone, name) or { points = {}, nodes = {}, taboos = {} } end
	local function editingThis() return Editor:IsEditing("route", zone, name) end
	local function busy() return Routes:Busy(zone, name) end

	return {
		type = "group", name = name, order = order, childGroups = "tab",
		args = {
			info = {
				order = 1, type = "group", name = "Info",
				args = {
					about = {
						order = 1, type = "description", fontSize = "medium", width = "full",
						name = function()
							local r = route()
							if not r then return "" end
							local names = {}
							for id in pairs(r.nodes) do names[#names + 1] = Catalog:Name(id) or ("#" .. id) end
							sort(names)
							local lines = {
								("%d points, %d yards around."):format(#r.points, r.length or 0),
								"Built from: " .. (#names > 0 and table.concat(names, ", ") or "hand-made"),
							}
							if r.clusters then
								lines[#lines + 1] = ("Clustered: passes within %d yards of every node."):format(r.radius or 0)
							end
							return table.concat(lines, "\n") .. "\n"
						end,
					},
					show = {
						order = 2, type = "select", name = "Show", values = SHOW_VALUES,
						get = function() return route().show or "always" end,
						set = function(_, v) route().show = v; Routes:Changed(zone) end,
					},
					edit = {
						order = 10, type = "execute", name = "Edit points on the map",
						desc = "Drag points to move them, click a small handle between two points to add one, right-click a point to delete it.",
						hidden = editingThis,
						disabled = function() return route().clusters ~= nil or busy() or Editor:IsEditing() end,
						func = function() report(Editor:Start("route", zone, name)) end,
					},
					save = { order = 11, type = "execute", name = "Save points", hidden = function() return not editingThis() end, func = function() Editor:Save() end },
					cancel = { order = 12, type = "execute", name = "Cancel", hidden = function() return not editingThis() end, func = function() Editor:Cancel() end },
					update = {
						order = 15, type = "execute", name = "Update route",
						desc = "Adds the spots of its nodes recorded since you made it (or last updated it) and drops the ones "
							.. "deleted since. Everything else, hand-placed points included, stays as it is. Optimize "
							.. "afterwards for the shortest loop.",
						disabled = busy,
						func = function()
							local ok, added, removed = Routes:Update(zone, name)
							if not ok then Apex:Print(added); return end
							status[key] = ("Updated: %d spots added, %d removed."):format(added, removed)
							Apex:Print(("%s: %d spots added, %d removed."):format(name, added, removed))
						end,
					},
					updateStatus = { order = 16, type = "description", width = "full", name = function() return status[key] or "" end },
					rename = {
						order = 20, type = "input", name = "Rename",
						get = function() return name end,
						set = function(_, v) report(Routes:Rename(zone, name, v)) end,
						disabled = busy,
					},
					delete = {
						order = 21, type = "execute", name = "Delete route",
						confirm = true, confirmText = ("Delete the route %q?"):format(name),
						disabled = busy,
						func = function() Routes:Delete(zone, name) end,
					},
				},
			},
			look = {
				order = 2, type = "group", name = "Look",
				args = {
					color = {
						order = 1, type = "color", name = "Color", hasAlpha = true,
						get = function() local c = Routes:Style(route()); return c[1], c[2], c[3], c[4] end,
						set = function(_, r, g, b, a) route().color = { r, g, b, a }; Routes:Changed(zone) end,
					},
					worldMapWidth = {
						order = 2, type = "range", name = "World map width", min = 1, max = 40, step = 1,
						get = function() local _, w = Routes:Style(route()); return w end,
						set = function(_, v) route().worldMapWidth = v; Routes:Changed(zone) end,
					},
					minimapWidth = {
						order = 3, type = "range", name = "Minimap width", min = 1, max = 20, step = 1,
						get = function() local _, _, w = Routes:Style(route()); return w end,
						set = function(_, v) route().minimapWidth = v; Routes:Changed(zone) end,
					},
					reset = {
						order = 4, type = "execute", name = "Use the defaults",
						func = function()
							local r = route()
							r.color, r.worldMapWidth, r.minimapWidth = nil, nil, nil
							Routes:Changed(zone)
						end,
					},
				},
			},
			optimize = {
				order = 3, type = "group", name = "Optimize",
				args = {
					about = {
						order = 1, type = "description", width = "full",
						name = "Optimizing finds a shorter loop through the same points. It starts from the current order and "
							.. "only keeps a shorter one, so running it again is safe.\n\nClustering merges nodes near each other "
							.. "into one route point; optimizing a clustered route also straightens it, never passing farther "
							.. "than the cluster radius from any node.\n",
					},
					radius = {
						order = 2, type = "range", name = "Cluster radius (yards)", min = 10, max = 200, step = 5,
						desc = function()
							return ("How far the route may pass from a node. Tracking finds nodes out to about %d yards, "
								.. "so the default is half that (%d): every node shows on your minimap well before you're "
								.. "closest. Bigger makes a shorter loop but longer walks out to nodes that are up; with "
								.. "fast respawns, when most nodes are up each lap, smaller is often better."):format(
								Apex:TrackingRangeYards(), Apex:DefaultClusterRadius())
						end,
						hidden = function() return route().clusters ~= nil end,
						get = function() return Apex:ClusterRadius() end,
						set = function(_, v) Apex.db.profile.routes.clusterRadius = v end,
					},
					radiusReset = {
						order = 2.5, type = "execute", name = "Half the tracking range",
						desc = "Back to the default radius.",
						hidden = function() return route().clusters ~= nil end,
						disabled = function() return Apex.db.profile.routes.clusterRadius == nil end,
						func = function() Apex.db.profile.routes.clusterRadius = nil end,
					},
					cluster = {
						order = 3, type = "execute", name = "Cluster",
						hidden = function() return route().clusters ~= nil end,
						disabled = function() return busy() end,
						func = function() Routes:Cluster(zone, name, Apex:ClusterRadius()) end,
					},
					uncluster = {
						order = 4, type = "execute", name = "Uncluster",
						hidden = function() return route().clusters == nil end,
						disabled = busy,
						func = function() Routes:Uncluster(zone, name) end,
					},
					now = {
						order = 10, type = "execute", name = "Optimize now",
						desc = "The game pauses while it works: a fraction of a second for a hundred points.",
						disabled = busy,
						func = function() status[key] = Routes:Optimize(zone, name) end,
					},
					background = {
						order = 11, type = "execute", name = "Optimize in the background",
						desc = "Works a little every frame, so the game never pauses.",
						disabled = busy,
						func = function()
							report(Routes:OptimizeInBackground(zone, name, function(text)
								status[key] = text
								notify()
							end))
						end,
					},
					thorough = {
						order = 12, type = "toggle", name = "Search longer", width = "full",
						desc = "Tries about three times as hard. Most routes are already as short as they get without it.",
						get = function() return Apex.db.profile.routes.thorough end,
						set = function(_, v) Apex.db.profile.routes.thorough = v end,
					},
					status = { order = 13, type = "description", width = "full", name = function() return status[key] or "" end },
				},
			},
			taboos = {
				order = 4, type = "group", name = "Taboos",
				args = {
					about = {
						order = 1, type = "description", width = "full",
						name = "Ticked taboo areas are kept out of this route: spots inside them are dropped, and optimizing "
							.. "goes around them wherever it can. Make taboo areas on the Taboo areas page.",
					},
					list = {
						order = 2, type = "multiselect", width = "full", name = "Avoid",
						values = function()
							local out = {}
							for _, taboo in ipairs(Routes:TabooNames(zone)) do out[taboo] = taboo end
							return out
						end,
						get = function(_, taboo) return route().taboos[taboo] end,
						set = function(_, taboo, v) Routes:SetTaboo(zone, name, taboo, v) end,
						disabled = busy,
					},
				},
			},
		},
	}
end


------------------------------------------------------------------------------------------
-- Fixed pages

local options = {
	type = "group", name = "Routes", childGroups = "tree",
	args = {
		new = {
			order = 1, type = "group", name = "New route",
			args = {
				about = {
					order = 1, type = "description", width = "full",
					name = "A route is a loop through every recorded spot of the nodes you pick, in one zone. It's optimized "
						.. "right away. It stays as it is while you gather; Update route on its Info tab adds spots recorded later.\n",
				},
				name = {
					order = 2, type = "input", name = "Name",
					get = function() return newRoute.name end,
					set = function(_, v) newRoute.name = v end,
				},
				zone = {
					order = 3, type = "select", name = "Zone", values = zonesWithNodes,
					get = function() return newRoute.zone or mapZone() end,
					set = function(_, v) newRoute.zone = v; wipe(newRoute.nodes) end,
				},
				nodes = {
					order = 4, type = "multiselect", width = "full", name = "Nodes",
					values = function()
						local out = {}
						for id, count in pairs(Routes:NodesInZone(newRoute.zone or mapZone() or 0)) do
							out[id] = ("%s |cff999999(%d)|r"):format(Catalog:Name(id) or ("#" .. id), count)
						end
						return out
					end,
					get = function(_, id) return newRoute.nodes[id] end,
					set = function(_, id, v) newRoute.nodes[id] = v or nil end,
				},
				create = {
					order = 5, type = "execute", name = "Create route",
					disabled = function() return not next(newRoute.nodes) end,
					func = function()
						local zone = newRoute.zone or mapZone()
						if report(Routes:Create(zone, newRoute.name, newRoute.nodes)) then
							newRoute.name = ""
							wipe(newRoute.nodes)
							Options:Select(zone)
						end
					end,
				},
			},
		},
		taboos = {
			order = 2, type = "group", name = "Taboo areas",
			args = {
				about = {
					order = 1, type = "description", width = "full",
					name = "Taboo areas are places routes should stay out of: enemy towns, caves, cliffs. Make one here, "
						.. "shape it on the map, then tick it on a route's Taboos tab.\n",
				},
				name = {
					order = 2, type = "input", name = "Name",
					get = function() return newTaboo.name end,
					set = function(_, v) newTaboo.name = v end,
				},
				zone = {
					order = 3, type = "select", name = "Zone", values = zonesWithNodes,
					get = function() return newTaboo.zone or mapZone() end,
					set = function(_, v) newTaboo.zone = v end,
				},
				create = {
					order = 4, type = "execute", name = "Create taboo area",
					func = function()
						local zone = newTaboo.zone or mapZone()
						if report(Routes:CreateTaboo(zone, newTaboo.name)) then
							local name = newTaboo.name
							newTaboo.name = ""
							report(Editor:Start("taboo", zone, strtrim(name)))
						end
					end,
				},
				list = { order = 10, type = "group", inline = true, name = "In this zone", args = {} },
			},
		},
		display = {
			order = 3, type = "group", name = "Display",
			get = function(info) return Apex.db.profile.routes[info[#info]] end,
			set = function(info, v) Apex.db.profile.routes[info[#info]] = v; Apex:SettingsChanged() end,
			args = {
				worldMap = { order = 1, type = "toggle", name = "Draw on the world map", width = "full" },
				minimap = { order = 2, type = "toggle", name = "Draw on the minimap and HUD", width = "full" },
				color = {
					order = 3, type = "color", name = "Default color", hasAlpha = true,
					get = function() local c = Apex.db.profile.routes.color; return c[1], c[2], c[3], c[4] end,
					set = function(_, r, g, b, a) Apex.db.profile.routes.color = { r, g, b, a }; Apex:SettingsChanged() end,
				},
				worldMapWidth = { order = 4, type = "range", name = "Default world map width", min = 1, max = 40, step = 1 },
				minimapWidth = { order = 5, type = "range", name = "Default minimap width", min = 1, max = 20, step = 1 },
			},
		},
	},
}

-- the taboo list shows the zone the map is on
local function tabooList()
	local args = {}
	local zone = newTaboo.zone or mapZone()
	for i, name in ipairs(zone and Routes:TabooNames(zone) or {}) do
		local function editingThis() return Editor:IsEditing("taboo", zone, name) end
		args["t" .. i] = {
			order = i, type = "group", inline = true, name = name,
			args = {
				edit = {
					order = 1, type = "execute", name = "Shape on the map", hidden = editingThis,
					disabled = function() return Editor:IsEditing() end,
					func = function() report(Editor:Start("taboo", zone, name)) end,
				},
				save = { order = 2, type = "execute", name = "Save shape", hidden = function() return not editingThis() end, func = function() Editor:Save() end },
				cancel = { order = 3, type = "execute", name = "Cancel", hidden = function() return not editingThis() end, func = function() Editor:Cancel() end },
				delete = {
					order = 4, type = "execute", name = "Delete", confirm = true,
					confirmText = ("Delete the taboo area %q? Routes stop avoiding it."):format(name),
					func = function() Routes:DeleteTaboo(zone, name) end,
				},
			},
		}
	end
	return args
end

function Options:Rebuild()
	for key in pairs(options.args) do
		if key:find("^z%d") then options.args[key] = nil end
	end
	for i, zone in ipairs(Routes:Zones()) do
		local names = Routes:Names(zone)
		if #names > 0 then
			local args = {}
			for j, name in ipairs(names) do args["r" .. j] = routeGroup(zone, name, j) end
			options.args["z" .. zone] = { order = 10 + i, type = "group", name = Apex:ZoneName(zone), args = args }
		end
	end
	options.args.taboos.args.list.args = tabooList()
	notify()
end

-- opens the panel on a zone's routes, or on New route if the zone has none
function Options:Select(zone)
	local ACD = LibStub("AceConfigDialog-3.0")
	if zone and options.args["z" .. zone] then
		ACD:SelectGroup(APP, "z" .. zone)
	else
		ACD:SelectGroup(APP, "new")
	end
end

function Options:OnEnable()
	ACR:RegisterOptionsTable(APP, options)
	self:RegisterMessage("APEX_ROUTES_CHANGED", "Rebuild")
	self:RegisterMessage("APEX_NODES_CHANGED", notify)
	self:Rebuild()
	if WorldMapFrame then hooksecurefunc(WorldMapFrame, "OnMapChanged", function() Options:Rebuild() end) end
end
