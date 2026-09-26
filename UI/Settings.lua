--[[
	The settings tree under Options > AddOns > ApexGatherer.

	Pages: the main page (pins), Filters, Maintenance, Learned Nodes, Import, Export, Sharing,
	HUD (built by HUD/Options.lua), Routes (opens the map flyout), Profiles and the FAQ.
]]
local Apex = ApexGatherer
local Catalog = Apex.Catalog
local Config = Apex:NewModule("Settings", "AceEvent-3.0")

local ACR = LibStub("AceConfigRegistry-3.0")
local ACD = LibStub("AceConfigDialog-3.0")
local APP = "ApexGatherer"
local Y = Apex.GOLD   -- highlight for page and button names

local function profile() return Apex.db.profile end
local function changed() Apex:SettingsChanged() end

local function kindValues()
	local out = {}
	for _, kind in ipairs(Apex.KINDS) do out[kind] = Apex.KIND_LABEL[kind] end
	return out
end

local function countSummary()
	local parts, total = {}, 0
	for _, kind in ipairs(Apex.KINDS) do
		local n = Apex:CountNodes(kind)
		total = total + n
		if n > 0 then parts[#parts + 1] = ("%s %d"):format(Apex.KIND_LABEL[kind], n) end
	end
	if total == 0 then return "No nodes recorded yet. Gather something and it appears here." end
	return ("%d nodes recorded: %s."):format(total, table.concat(parts, ", "))
end

-- the world map and the settings panel can't be open together: close settings first
local function openRoutes()
	if SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
	C_Timer.After(0, function() Apex:GetModule("Flyout"):Open() end)
end


------------------------------------------------------------------------------------------
-- Main page

local general = {
	type = "group",
	name = "ApexGatherer",
	get = function(info) return profile().pins[info[#info]] end,
	set = function(info, v) profile().pins[info[#info]] = v; changed() end,
	args = {
		summary = {
			order = 1, type = "description", fontSize = "medium", width = "full",
			name = function() return countSummary() .. "\n" end,
		},
		toggleHUD = {
			order = 2, type = "execute", name = "Toggle HUD",
			desc = "Show or hide the gathering HUD (also: left-click the minimap button, or /ag hud).",
			func = function() Apex:ToggleHUD() end,
		},
		openRoutes = {
			order = 3, type = "execute", name = "Routes on the map",
			desc = "Open the world map with the routes panel (also: middle-click the minimap button, or /ag routes).",
			func = openRoutes,
		},
		pinsHeader = { order = 10, type = "header", name = "Node pins" },
		worldMap = { order = 11, type = "toggle", name = "Show on the world map" },
		minimap = { order = 12, type = "toggle", name = "Show on the minimap" },
		tooltips = { order = 13, type = "toggle", name = "Name nodes on hover" },
		show = {
			order = 14, type = "multiselect", name = "Node kinds to show", values = kindValues,
			get = function(_, kind) return profile().pins.show[kind] end,
			set = function(_, kind, v) profile().pins.show[kind] = v; changed() end,
		},
		worldMapScale = { order = 15, type = "range", name = "World map pin size", min = 0.5, max = 3, step = 0.05, isPercent = true },
		minimapScale = { order = 16, type = "range", name = "Minimap pin size", min = 0.5, max = 3, step = 0.05, isPercent = true },
		hudScale = { order = 17, type = "range", name = "HUD pin size", min = 0.5, max = 3, step = 0.05, isPercent = true },
		alpha = { order = 18, type = "range", name = "Pin opacity", min = 0.1, max = 1, step = 0.05, isPercent = true },
		ringHeader = { order = 30, type = "header", name = "Tracking rings" },
		ringDesc = {
			order = 31, type = "description", width = "full",
			name = function()
				return ("Within tracking range (about %d yards) of a kind you're tracking, the minimap shows the node "
					.. "itself with a yellow dot. There a minimap or HUD pin is just a ring round that dot; an empty "
					.. "ring means the node isn't up right now. Further out, and for kinds you aren't tracking, pins "
					.. "show the node's picture."):format(Apex:TrackingRangeYards())
			end,
		},
		ring = { order = 32, type = "toggle", name = "Rings round tracked nodes", desc = "Off: pins always show the node's picture." },
		ringSize = {
			order = 33, type = "range", name = "Ring size", min = 8, max = 40, step = 1,
			desc = "In pixels: set it to fit round the minimap's yellow dot.",
			disabled = function() return not profile().pins.ring end,
		},
		ringColors = {
			order = 34, type = "group", inline = true, name = "Ring colors",
			disabled = function() return not profile().pins.ring end,
			args = {},
		},
		buttonHeader = { order = 20, type = "header", name = "Minimap button" },
		minimapButton = {
			order = 21, type = "toggle", name = "Show the minimap button",
			get = function() return not profile().minimapButton.hide end,
			set = function(_, v)
				profile().minimapButton.hide = not v
				Apex:GetModule("Launcher"):UpdateButton()
			end,
		},
	},
}


------------------------------------------------------------------------------------------
-- Filters: which catalog nodes get pins

local filters = { type = "group", name = "Filters", childGroups = "tab", args = {} }
for i, kind in ipairs(Apex.KINDS) do
	filters.args[kind] = {
		order = i, type = "group", name = Apex.KIND_LABEL[kind],
		args = {
			all = {
				order = 1, type = "execute", name = "Show all",
				func = function()
					for _, node in ipairs(Catalog:Nodes(kind)) do profile().pins.hidden[node.id] = nil end
					changed()
				end,
			},
			none = {
				order = 2, type = "execute", name = "Hide all",
				func = function()
					for _, node in ipairs(Catalog:Nodes(kind)) do profile().pins.hidden[node.id] = true end
					changed()
				end,
			},
			nodes = {
				order = 3, type = "multiselect", width = "full", name = "Show pins for",
				values = function()
					local out = {}
					for _, node in ipairs(Catalog:Nodes(kind)) do
						local n = Apex:CountNodes(kind, node.id)
						out[node.id] = n > 0 and ("%s |cff999999(%d)|r"):format(node.name, n) or node.name
					end
					return out
				end,
				get = function(_, id) return not profile().pins.hidden[id] end,
				set = function(_, id, v) profile().pins.hidden[id] = not v or nil; changed() end,
			},
		},
	}
end


------------------------------------------------------------------------------------------
-- Maintenance: duplicates, locks and deleting nodes

local pick = { kind = "Mining" }
local maintenance = {
	type = "group", name = "Maintenance",
	args = {
		cleanupHeader = { order = 1, type = "header", name = "Duplicates" },
		cleanupDesc = {
			order = 2, type = "description", width = "full",
			name = "The same node recorded twice closer than these distances counts as one spot. Gathering already "
				.. "keeps them apart; Clean up merges any that slipped in (from imports or sharing, say).",
		},
		range = {
			order = 3, type = "group", inline = true, name = "Same spot within (yards)",
			get = function(info) return profile().cleanupRange[info[#info]] end,
			set = function(info, v) profile().cleanupRange[info[#info]] = v end,
			args = {},
		},
		cleanup = {
			order = 4, type = "execute", name = "Clean up",
			func = function() Apex:Print(("removed %d duplicate nodes."):format(Apex:CleanupDuplicates())) end,
		},
		lockHeader = { order = 10, type = "header", name = "Recording" },
		locked = {
			order = 11, type = "multiselect", name = "Stop recording these kinds", values = kindValues,
			get = function(_, kind) return profile().locked[kind] end,
			set = function(_, kind, v) profile().locked[kind] = v end,
		},
		deleteHeader = { order = 20, type = "header", name = "Delete nodes" },
		kind = {
			order = 21, type = "select", name = "Kind", values = kindValues,
			get = function() return pick.kind end,
			set = function(_, v) pick.kind, pick.zone, pick.node = v, nil, nil end,
		},
		zone = {
			order = 22, type = "select", name = "Zone",
			values = function()
				local out = {}
				for _, zone in ipairs(Apex:ZonesWithNodes(pick.kind)) do out[zone] = Apex:ZoneName(zone) end
				return out
			end,
			get = function() return pick.zone end,
			set = function(_, v) pick.zone, pick.node = v, nil end,
		},
		node = {
			order = 23, type = "select", name = "Node",
			values = function()
				local out, data = {}, pick.zone and Apex:GetZoneNodes(pick.kind, pick.zone)
				for _, id in pairs(data or {}) do out[id] = Catalog:Name(id) end
				return out
			end,
			get = function() return pick.node end,
			set = function(_, v) pick.node = v end,
		},
		deleteNode = {
			order = 24, type = "execute", name = "Delete them",
			disabled = function() return not (pick.zone and pick.node) end,
			confirm = function()
				return ("Delete every %s recorded in %s?"):format(Catalog:Name(pick.node) or "?", Apex:ZoneName(pick.zone))
			end,
			func = function()
				Apex:Print(("deleted %d nodes."):format(Apex:RemoveNodeType(pick.kind, pick.node, pick.zone)))
				pick.node = nil
			end,
		},
		deleteKind = {
			order = 25, type = "execute", name = "Delete the whole kind",
			confirm = function() return ("Delete every %s node in every zone? This can't be undone."):format(Apex.KIND_LABEL[pick.kind]:lower()) end,
			func = function()
				Apex:ClearKind(pick.kind)
				pick.zone, pick.node = nil, nil
			end,
		},
	},
}
for i, kind in ipairs(Apex.KINDS) do
	maintenance.args.range.args[kind] = { order = i, type = "range", name = Apex.KIND_LABEL[kind], min = 5, max = 50, step = 1 }
	general.args.ringColors.args[kind] = {
		order = i, type = "color", name = Apex.KIND_LABEL[kind], hasAlpha = true,
		get = function() local c = profile().pins.ringColor[kind]; return c[1], c[2], c[3], c[4] end,
		set = function(_, r, g, b, a) profile().pins.ringColor[kind] = { r, g, b, a } end,
	}
end


------------------------------------------------------------------------------------------
-- Learned nodes and the unidentified-name log

local selectedLearned
local function learnedValues()
	local out = {}
	for kind, names in pairs(Apex:GetLearnedNodes()) do
		for name, id in pairs(names) do
			out[kind .. "\001" .. name] = ("%s: %s  (%d recorded)"):format(Apex.KIND_LABEL[kind], name, Apex:CountNodes(kind, id))
		end
	end
	return out
end

local learned = {
	type = "group", name = "Learned Nodes",
	args = {
		desc = {
			order = 1, type = "description", width = "full",
			name = "WoW Forever keeps adding gathering nodes. When you mine or pick one ApexGatherer doesn't know yet, "
				.. "it learns the name and records it from then on.\nIf it learned something that isn't a real node, "
				.. "select it and click Forget (this also deletes its recorded spots).\n",
		},
		pick = {
			order = 2, type = "select", width = "full", name = "Learned node", values = learnedValues,
			get = function() return selectedLearned end,
			set = function(_, v) selectedLearned = v end,
		},
		forget = {
			order = 3, type = "execute", name = "Forget",
			confirm = true, confirmText = "Forget this node and delete all of its recorded spots?",
			disabled = function() return not (selectedLearned and learnedValues()[selectedLearned]) end,
			func = function()
				local kind, name = strsplit("\001", selectedLearned)
				Apex:ForgetLearnedNode(kind, name)
				selectedLearned = nil
			end,
		},
		unknownHeader = { order = 10, type = "header", name = "Seen but not recognized" },
		unknown = {
			order = 11, type = "description", width = "full", fontSize = "medium",
			name = function()
				local lines = {}
				for _, entry in pairs(Apex:GetUnknownNodes()) do
					if not Catalog:Find(entry.kind, entry.name) then
						lines[#lines + 1] = ("%s: %s  (seen %d)"):format(Apex.KIND_LABEL[entry.kind], entry.name, entry.count)
					end
				end
				sort(lines)
				if #lines == 0 then return "Nothing logged." end
				return "Fishing pools and treasure aren't learned automatically (the bobber and quest objects would "
					.. "be picked up by mistake), so names seen but not recognized are listed here:\n\n" .. table.concat(lines, "\n")
			end,
		},
		clearLog = {
			order = 12, type = "execute", name = "Clear this list",
			func = function() wipe(Apex:GetUnknownNodes()) end,
		},
	},
}


------------------------------------------------------------------------------------------
-- Import and export

local importText, importStatus, exportText = "", "", ""
local exportKinds = { Mining = true, Herbalism = true, Fishing = true, Treasure = true }

local import = {
	type = "group", name = "Import",
	args = {
		desc = {
			order = 1, type = "description", width = "full",
			name = "Paste an ApexGatherer export below (click in the box, Ctrl-A, Ctrl-V), then click " .. Y
				.. "Import|r. Nodes are added to the ones you have; spots you already have are skipped.",
		},
		text = {
			order = 2, type = "input", multiline = 18, width = "full", name = "Export text",
			get = function() return importText end,
			set = function(_, v) importText = v end,
		},
		go = {
			order = 3, type = "execute", name = "Import",
			func = function()
				local ok, added, skipped = Apex:ImportNodes(importText)
				if ok then
					importStatus = (Apex.TEAL .. "Imported %d nodes%s.|r"):format(added,
						skipped > 0 and (", skipped %d already known or unreadable"):format(skipped) or "")
				else
					importStatus = Apex.WARN .. added .. "|r"
				end
			end,
		},
		status = { order = 4, type = "description", width = "full", name = function() return importStatus end },
	},
}

local export = {
	type = "group", name = "Export",
	args = {
		desc = {
			order = 1, type = "description", width = "full",
			name = "Export your recorded nodes as text: tick the kinds, click " .. Y .. "Export|r, then click in the "
				.. "box and press Ctrl-A, Ctrl-C. Keep it as a backup, or import it on another character.",
		},
		kinds = {
			order = 2, type = "multiselect", name = "Kinds", values = kindValues,
			get = function(_, k) return exportKinds[k] end,
			set = function(_, k, v) exportKinds[k] = v end,
		},
		go = { order = 3, type = "execute", name = "Export", func = function() exportText = Apex:ExportNodes(exportKinds) end },
		text = {
			order = 4, type = "input", multiline = 20, width = "full", name = "Export text",
			get = function() return exportText end,
			set = function() end,
		},
	},
}


------------------------------------------------------------------------------------------
-- Sharing (Core/Sharing.lua does the talking)

local shareWith, shareName = "GUILD", ""
local function sharing() return Apex:GetModule("Sharing") end
local function shareProfile() return profile().sharing end
local function shareRun(method)
	local channel, target = "GUILD", nil
	if shareWith == "PLAYER" then
		target = strtrim(shareName or "")
		if target == "" then Apex:Print("type the player's name first."); return end
		channel = "WHISPER"
	end
	local ok, err = sharing()[method](sharing(), channel, target, shareProfile().types)
	if not ok then Apex:Print(err) end
end

local share = {
	type = "group", name = "Sharing",
	get = function(info) return shareProfile()[info[#info]] end,
	set = function(info, v) shareProfile()[info[#info]] = v end,
	args = {
		desc = {
			order = 1, type = "description", fontSize = "medium", width = "full",
			name = "Swap gathering nodes with your guild or with another player (they need ApexGatherer too). "
				.. "Nodes you receive are added to yours; spots you already have are skipped.\n",
		},
		swap = {
			order = 10, type = "group", inline = true, name = "Swap nodes",
			args = {
				with = {
					order = 1, type = "select", name = "With", values = { GUILD = "My guild", PLAYER = "A player" },
					get = function() return shareWith end,
					set = function(_, v) shareWith = v end,
				},
				player = {
					order = 2, type = "input", name = "Player name",
					desc = "Their character name; add -Realm for someone on another realm.",
					hidden = function() return shareWith ~= "PLAYER" end,
					get = function() return shareName end,
					set = function(_, v) shareName = v end,
				},
				types = {
					order = 3, type = "multiselect", width = "full", name = "Node kinds to share and accept", values = kindValues,
					get = function(_, k) return shareProfile().types[k] end,
					set = function(_, k, v) shareProfile().types[k] = v end,
				},
				send = {
					order = 4, type = "execute", name = "Send my nodes",
					desc = function()
						return ("Sends your %d nodes of the ticked kinds. A player is asked before they receive them."):format(
							sharing():CountNodes(shareProfile().types))
					end,
					disabled = function() return sharing():IsSending() end,
					func = function() shareRun("SendNodes") end,
				},
				request = {
					order = 5, type = "execute", name = "Ask for their nodes",
					desc = "Asks the player, or everyone in your guild, to send you their nodes of the ticked kinds. "
						.. "Answers to your own request come straight in.",
					func = function() shareRun("RequestNodes") end,
				},
				status = { order = 6, type = "description", width = "full", name = function() return "\n" .. sharing():GetStatus() end },
			},
		},
		guild = {
			order = 20, type = "group", inline = true, name = "Guild",
			args = {
				liveGuild = { order = 1, type = "toggle", width = "full", name = "Share each node with my guild as I gather it" },
				acceptGuild = { order = 2, type = "toggle", width = "full", name = "Accept nodes my guild shares" },
				askGuild = {
					order = 3, type = "toggle", width = "full", name = "Ask me before accepting a guildmate's whole collection",
					disabled = function() return not shareProfile().acceptGuild end,
				},
				answerGuild = { order = 4, type = "toggle", width = "full", name = "Send my nodes when a guildmate asks for them" },
			},
		},
		players = {
			order = 30, type = "group", inline = true, name = "Other players",
			args = {
				allowWhisper = { order = 1, type = "toggle", width = "full", name = "Let players send me nodes or ask for mine (I'm always asked first)" },
			},
		},
		announce = { order = 40, type = "toggle", width = "full", name = "Tell me in chat when shared nodes arrive" },
		activity = {
			order = 50, type = "group", inline = true, name = "Recent activity",
			args = {
				log = {
					order = 1, type = "description", width = "full",
					name = function()
						local lines = sharing():GetLog()
						return #lines > 0 and table.concat(lines, "\n") or "|cff999999Nothing yet this session.|r"
					end,
				},
			},
		},
	},
}


------------------------------------------------------------------------------------------
-- Routes: a launcher, since route editing needs the world map

local routes = {
	type = "group", name = "Routes",
	args = {
		desc = {
			order = 1, type = "description", fontSize = "medium", width = "full",
			name = "Routes are built on the world map: create a route from your recorded nodes, shape it on the map, "
				.. "then optimize it. This settings window can't stay open next to the map, so the route controls "
				.. "live in a panel docked beside the world map.\n\nOpen it with the " .. Y .. "Routes|r button at "
				.. "the top of the world map, " .. Y .. "/ag routes|r, a middle-click on the minimap button, or a key "
				.. "bound under Key Bindings > AddOns.\n",
		},
		open = { order = 2, type = "execute", name = "Open routes on the map", width = "double", func = openRoutes },
	},
}


------------------------------------------------------------------------------------------

-- Blizzard's settings window doesn't move. A strip along its title bar drags it, and it opens
-- where it was left, even after a reload (not in combat, if the window is protected then).
local function movableSettings()
	local panel = SettingsPanel
	if not panel or Config.dragBar then return end
	local function locked() return InCombatLockdown() and panel:IsProtected() end
	local bar = CreateFrame("Frame", nil, panel)
	bar:SetPoint("TOPLEFT", panel, "TOPLEFT", 4, 0)
	bar:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -32, 0)   -- clear of the close button
	bar:SetHeight(24)
	bar:SetFrameLevel(panel:GetFrameLevel() + 20)
	bar:EnableMouse(true)
	bar:RegisterForDrag("LeftButton")
	bar:SetScript("OnDragStart", function()
		if locked() then return end
		panel:SetMovable(true)
		panel:SetClampedToScreen(true)
		panel:StartMoving()
	end)
	bar:SetScript("OnDragStop", function()
		panel:StopMovingOrSizing()
		panel:SetUserPlaced(false)   -- kept in our settings, not the game's layout file
		local point, _, relativePoint, x, y = panel:GetPoint(1)
		if point then Apex.db.global.settingsPoint = { point, relativePoint, x, y } end
	end)
	panel:HookScript("OnShow", function()
		-- once the game has placed it
		C_Timer.After(0, function()
			local p = Apex.db.global.settingsPoint
			if p and not locked() then
				panel:ClearAllPoints()
				panel:SetPoint(p[1], UIParent, p[2], p[3], p[4])
			end
		end)
	end)
	Config.dragBar = bar
end

function Config:Open()
	movableSettings()
	if self.categoryID then Settings.OpenToCategory(self.categoryID) end
end

local function page(app, options, title)
	ACR:RegisterOptionsTable(app, options)
	return ACD:AddToBlizOptions(app, title, title and APP or nil)
end

function Config:OnEnable()
	local _, id = page(APP, general)
	self.categoryID = id
	page(APP .. "/Filters", filters, "Filters")
	page(APP .. "/Maintenance", maintenance, "Maintenance")
	page(APP .. "/Learned", learned, "Learned Nodes")
	page(APP .. "/Import", import, "Import")
	page(APP .. "/Export", export, "Export")
	page(APP .. "/Sharing", share, "Sharing")
	page(APP .. "/HUD", Apex:GetModule("HUD"):GetOptions(), "HUD")
	page(APP .. "/RoutesPage", routes, "Routes")
	page(APP .. "/Profiles", LibStub("AceDBOptions-3.0"):GetOptionsTable(Apex.db), "Profiles")
	page(APP .. "/FAQ", Apex.FAQOptions, "FAQ")
	movableSettings()

	-- settings pages that show node counts refresh as nodes change
	local function refresh() ACR:NotifyChange(APP); ACR:NotifyChange(APP .. "/Filters"); ACR:NotifyChange(APP .. "/Learned") end
	for _, message in ipairs({ "APEX_NODE_ADDED", "APEX_NODE_REMOVED", "APEX_NODES_CHANGED", "APEX_CATALOG_CHANGED" }) do
		self:RegisterMessage(message, refresh)
	end
end
