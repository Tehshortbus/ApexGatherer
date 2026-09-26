-- Usage (from the addon folder):  lua5.1 dev/harness.lua . [path/to/SavedVariables/<Addon>.lua]
-- Not listed in the TOC, so WoW never loads it.
-- Offline load test for the addon: runs the real addon code under Lua 5.1 with a stub
-- WoW API, loads the real SavedVariables file, fires the addon lifecycle events, then
-- simulates gathering. Every error is captured the way an error-catching addon would.
local ROOT, SVFILE = arg[1], arg[2]
local ROOT_FOR_TOC = ROOT
local TOC_NAME = (function()   -- the addon folder holds exactly one .toc
	local p = io.popen('ls "' .. ROOT_FOR_TOC .. '"/*.toc 2>/dev/null')
	local line = p and p:read("*l"); if p then p:close() end
	return assert(line and line:match("([^/]+)%.toc$"), "no .toc found in " .. ROOT_FOR_TOC)
end)()
local errors, missing, chat = {}, {}, {}

---------------------------------------------------------------- environment
local base = {}
for k, v in pairs(_G) do base[k] = v end
local W = setmetatable({}, { __index = function(_, k)
	local v = base[k]
	if v == nil and type(k) == "string" then missing[k] = (missing[k] or 0) + 1 end
	return v
end })
base._G = W

local function report(msg)
	errors[#errors + 1] = debug.traceback(tostring(msg), 2)
end
base.geterrorhandler = function() return function(m) report(m) end end
base.seterrorhandler = function() end
base.securecallfunction = function(f, ...) return f(...) end
base.securecall = function(f, ...) if type(f) == "string" then f = W[f] end return f(...) end
base.issecurevariable = function() return false, nil end
base.hooksecurefunc = function(t, name, fn)
	if type(t) == "string" then t, name, fn = W, t, name end
	local orig = t[name]
	t[name] = function(...) local r = { orig(...) }; fn(...); return unpack(r) end
end
base.InCombatLockdown = function() return false end
base.IsLoggedIn = function() return W.__loggedIn end
local clockOffset = 0   -- tests move time forward (e.g. so ChatThrottleLib's bandwidth refills)
base.GetTime = function() return os.clock() + clockOffset end
base.debugprofilestop = function() return os.clock() * 1000 end
base.GetServerTime = os.time
base.GetLocale = function() return "enUS" end
base.GetCurrentRegion = function() return 1 end
base.GetCurrentRegionName = function() return "US" end
base.random = math.random
base.WOW_PROJECT_MAINLINE, base.WOW_PROJECT_CLASSIC, base.WOW_PROJECT_BURNING_CRUSADE_CLASSIC = 1, 2, 5
base.WOW_PROJECT_WRATH_CLASSIC, base.WOW_PROJECT_CATACLYSM_CLASSIC, base.WOW_PROJECT_MISTS_CLASSIC = 11, 14, 19
base.WOW_PROJECT_ID = 1   -- the Midnight engine reports mainline
do  -- WoW's Lua 5.1 xpcall forwards extra arguments (stock 5.1 does not)
	local _xpcall = xpcall
	base.xpcall = function(f, h, ...)
		local n, args = select("#", ...), { ... }
		return _xpcall(function() return f(unpack(args, 1, n)) end, h)
	end
end
base.GetBuildInfo = function() return "12.1.0", "60000", "Sep 24 2026", 120100 end
base.GetRealmName = function() return "Classic Beta PvE 2" end
base.UnitName = function() return "Tester" end   -- like WoW Forever: the surname comes apart
-- WoW Forever: names are unique region-wide and carry a surname
base.UnitNameUnmodified = function() return "Tester", "Example" end
base.RegionalUniqueNamesEnabled = function() return true end
base.C_GameRules = { IsGameRuleActive = function() return false end }
base.strlenutf8 = function(str) return #str end
base.UnitFactionGroup = function() return "Horde", "Horde" end
base.UnitClass = function() return "Warrior", "WARRIOR" end
base.UnitRace = function() return "Orc", "Orc" end
base.IsShiftKeyDown = function() return false end
local facing = {}   -- facing.value: the player's facing (nil, like in an instance, unless a test sets it)
base.GetPlayerFacing = function() return facing.value end
base.issecretvalue = function() return false end
base.IsPlayerSpell = function(id) return id == 2575 end
base.GetProfessions = function() return 1 end
base.GetProfessionInfo = function(i) return "Mining" end
local cvars = {}
base.GetCVar = function(k) return cvars[k] or "0" end
base.SetCVar = function(k, v) cvars[k] = tostring(v) end
base.IsIndoors = function() return false end
base.GetCVarBool = function() return false end
base.PlaySound = function() end
base.date, base.time = os.date, os.time
base.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
table.wipe = base.wipe
base.tinsert, base.tremove, base.sort = table.insert, table.remove, table.sort
base.format, base.strfind, base.strsub, base.strlower, base.strupper, base.strlen, base.strrep, base.strmatch, base.gsub, base.strbyte, base.strchar =
	string.format, string.find, string.sub, string.lower, string.upper, string.len, string.rep, string.match, string.gsub, string.byte, string.char
base.floor, base.ceil, base.abs, base.max, base.min, base.sqrt, base.mod = math.floor, math.ceil, math.abs, math.max, math.min, math.sqrt, math.fmod
base.tContains = function(t, v) for _, x in pairs(t) do if x == v then return true end end return false end
base.strtrim = function(s, chars) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
string.trim = base.strtrim
base.strsplit = function(sep, s, limit)
	local out, pos = {}, 1
	while true do
		local a, b = s:find(sep, pos, true)
		if not a or (limit and #out == limit - 1) then out[#out + 1] = s:sub(pos); break end
		out[#out + 1] = s:sub(pos, a - 1); pos = b + 1
	end
	return unpack(out)
end
base.strjoin = function(sep, ...) return table.concat({...}, sep) end
string.split = base.strsplit   -- WoW: string.split IS strsplit, so ("\001"):split(s) splits s on \001
base.Mixin = function(o, ...) for i = 1, select("#", ...) do for k, v in pairs((select(i, ...))) do o[k] = v end end return o end
base.CreateFromMixins = function(...) return base.Mixin({}, ...) end
base.CreateVector2D = function(x, y) return { x = x, y = y, GetXY = function(s) return s.x, s.y end } end
base.CreateColor = function(r, g, b, a) return { r = r, g = g, b = b, a = a, GetRGB = function(s) return s.r, s.g, s.b end } end
base.NORMAL_FONT_COLOR = base.CreateColor(1, .82, 0)
base.GREEN_FONT_COLOR_CODE, base.GRAY_FONT_COLOR_CODE, base.FONT_COLOR_CODE_CLOSE = "|cff00ff00", "|cff808080", "|r"
base.MapCanvasDataProviderMixin = {
	GetMap = function(s) return s.owningMap end,
	OnAdded = function(s, map) s.owningMap = map end,
	OnRemoved = function(s) s.owningMap = nil end,
	RemoveAllData = function() end, RefreshAllData = function() end,
}
base.MapCanvasPinMixin = { GetMap = function(s) return s.owningMap end }
base.UnitPosition = function() return nil end
base.Enum = { UIMapType = { Cosmic = 0, World = 1, Continent = 2, Zone = 3, Dungeon = 4, Micro = 5, Orphan = 6 },
	GameRule = { HardcoreRuleset = 1, RPRuleset = 2, PvPRuleset = 3 } }
base.SlashCmdList, base.hash_SlashCmdList = {}, {}
local timers = {}
local function tick() local q = timers; timers = {}; for _, f in ipairs(q) do f() end end
-- addon messages: everything sent is captured; tests replay it as if another player sent it
local sentAddon = {}
base.C_ChatInfo = {
	RegisterAddonMessagePrefix = function() return true end,
	IsAddonMessagePrefixRegistered = function() return true end,
	SendAddonMessage = function(prefix, text, chatType, target)
		sentAddon[#sentAddon + 1] = { prefix = prefix, text = text, chatType = chatType, target = target }
		return 0
	end,
}
base.IsInGuild = function() return true end
base.GetFramerate = function() return 60 end
base.Ambiguate = function(name) return (name:gsub("%-.*", "")) end
base.ACCEPT, base.DECLINE, base.YES, base.NO = "Accept", "Decline", "Yes", "No"
base.StaticPopupDialogs = {}
local popups = {}
base.StaticPopup_Show = function(which, a1, a2, data)
	popups[#popups + 1] = { which = which, a1 = a1, a2 = a2, data = data }
end
base.C_Timer = { After = function(_, f) timers[#timers + 1] = f end, NewTimer = function() return {} end, NewTicker = function() return { Cancel = function() end } end }

local SPELLS = { [2575] = "Mining", [2366] = "Herb Gathering", [7620] = "Fishing", [3365] = "Opening",
	[22810] = "Opening - No Text", [1804] = "Pick Lock", [2580] = "Find Minerals", [2383] = "Find Herbs",
	[43308] = "Find Fish", [170691] = "Herbalism" }   -- 2481 (Find Treasure) deliberately absent
base.C_Spell = { GetSpellName = function(id) return SPELLS[id] end }
base.C_Item = { GetItemNameByID = function() return nil end, GetItemIconByID = function(id) return 100000 + id end }
base.C_Map = setmetatable({}, { __index = function() return function() return nil end end })
local tracking = {
	{ name = "Find Minerals", texture = 136025, active = true, type = "spell" },
	{ name = "Find Herbs", texture = 133939, active = false, type = "spell" },
	{ name = "Focus Target", texture = 524051, active = false, type = "other" },
	{ name = "Track Digsites", texture = 535615, active = false, type = "other" },
	{ name = "Transmogrifier", texture = 1318128, active = false, type = "other", subType = 2 },
}
base.C_Minimap = {
	GetNumTrackingTypes = function() return #tracking end,
	GetTrackingInfo = function(i)
		local t = tracking[i]
		return t and { name = t.name, texture = t.texture, active = t.active, type = t.type, subType = t.subType }
	end,
	SetTracking = function(i, v) tracking[i].active = v and true or false end,
	-- 100 yards zoomed out, less at each zoom step in, like the client
	GetViewRadius = function()
		local steps = { [0] = 466 + 2 / 3, 400, 333 + 1 / 3, 266 + 2 / 3, 200, 133 + 1 / 3 }
		return 100 * steps[W.Minimap:GetZoom()] / steps[0]
	end,
}
base.C_CVar = { GetCVar = function() return "0" end, GetCVarBool = function() return false end, SetCVar = function() end }
base.C_AddOns = {
	GetAddOnMetadata = function() return nil end,
	GetAddOnInfo = function(n) return n, n, "", false, "MISSING" end,
	GetAddOnEnableState = function() return 0 end,
	IsAddOnLoaded = function() return false end,
	LoadAddOn = function() return false, "MISSING" end,
}

---------------------------------------------------------------- frames
local registered = {}   -- event -> list of frames
local Obj = {}
local allObjs = {}
local function newObj(kind, name)
	local o = setmetatable({ __kind = kind, __name = name, __scripts = {} }, Obj)
	if kind == "CreateLine" then o.AddMaskTexture = false end   -- the client's lines take no masks
	if name then W[name] = o end
	allObjs[#allObjs + 1] = o
	return o
end
-- one game frame for parentless frames (the ones the client always updates), e.g. background jobs
local function pump()
	for i = 1, #allObjs do
		local o = allObjs[i]
		local h = o.__parent == nil and o.__scripts.OnUpdate
		if h then h(o, 0.016) end
	end
end
local methods = {
	SetScript = function(s, n, f) s.__scripts[n] = f end,
	GetScript = function(s, n) return s.__scripts[n] end,
	HookScript = function(s, n, f)
		local prev = s.__scripts[n]
		s.__scripts[n] = prev and function(...) prev(...); f(...) end or f
	end,
	Show = function(s) if not s.__shown then s.__shown = true; local h = s.__scripts.OnShow; if h then h(s) end end end,
	Hide = function(s) if s.__shown then s.__shown = false; local h = s.__scripts.OnHide; if h then h(s) end end end,
	SetShown = function(s, v) if v then s:Show() else s:Hide() end end,
	IsShown = function(s) return s.__shown or false end, IsVisible = function(s) return s.__shown or false end,
	GetLeft = function(s) return s.__l end, GetRight = function(s) return s.__r end,
	GetTop = function(s) return s.__t end, GetBottom = function(s) return s.__b end,
	RegisterEvent = function(s, e) registered[e] = registered[e] or {}; registered[e][s] = true end,
	RegisterUnitEvent = function(s, e) registered[e] = registered[e] or {}; registered[e][s] = true end,
	UnregisterEvent = function(s, e) if registered[e] then registered[e][s] = nil end end,
	UnregisterAllEvents = function(s) for _, t in pairs(registered) do t[s] = nil end end,
	GetName = function(s) return s.__name end,
	GetDebugName = function(s) return s.__name or (s.__kind .. tostring(s):match("0x%x+")) end,
	GetObjectType = function(s) return s.__kind end,
	IsObjectType = function() return false end,
	GetParent = function(s) return s.__parent or W.UIParent end,
	SetParent = function(s, p) s.__parent = p end,
	GetWidth = function(s) return s.__w or 100 end, GetHeight = function(s) return s.__h or 100 end,
	GetSize = function(s) return s.__w or 100, s.__h or 100 end,
	SetSize = function(s, w, h) s.__w, s.__h = w, h end, SetWidth = function(s, w) s.__w = w end, SetHeight = function(s, h) s.__h = h end,
	GetCenter = function() return 0, 0 end, GetEffectiveScale = function() return 1 end,
	GetScale = function(s) return s.__scale or 1 end, SetScale = function(s, v) s.__scale = v end,
	GetAlpha = function(s) return s.__alpha or 1 end, SetAlpha = function(s, v) s.__alpha = v end,
	GetFrameLevel = function(s) return s.__level or 1 end, SetFrameLevel = function(s, v) s.__level = v end,
	GetFrameStrata = function(s) return s.__strata or "MEDIUM" end, SetFrameStrata = function(s, v) s.__strata = v end,
	EnableMouse = function(s, v) s.__mouse = v and true or false end, IsMouseEnabled = function(s) return s.__mouse or false end,
	EnableMouseWheel = function(s, v) s.__wheel = v and true or false end, IsMouseWheelEnabled = function(s) return s.__wheel or false end,
	SetPoint = function(s, point, rel, relPoint, x, y)
		s.__points = s.__points or {}
		if type(rel) == "number" then rel, relPoint, x, y = nil, point, rel, relPoint end
		s.__points[#s.__points + 1] = { point, rel or s.__parent, relPoint or point, x or 0, y or 0 }
	end,
	ClearAllPoints = function(s) s.__points = {} end,
	SetAllPoints = function(s, rel) s.__points = { { "TOPLEFT", rel or s.__parent, "TOPLEFT", 0, 0 }, { "BOTTOMRIGHT", rel or s.__parent, "BOTTOMRIGHT", 0, 0 } } end,
	GetNumPoints = function(s) return s.__points and #s.__points or 0 end,
	GetPoint = function(s, i) local p = s.__points and s.__points[i or 1]; if p then return p[1], p[2], p[3], p[4], p[5] end end,
	SetZoom = function(s, z) s.__zoom = z end, GetText = function(s) return s.__text end, SetText = function(s, t) s.__text = t end,
	GetFont = function() return "font", 12, "" end, GetStringWidth = function() return 10 end, GetStringHeight = function() return 10 end,
	GetChildren = function(s)
		local kids = {}
		-- regions (made by CreateTexture, CreateLine, ...) aren't children
		for _, o in ipairs(allObjs) do if o.__parent == s and not o.__kind:match("^Create") and o.__kind ~= "Texture" and o.__kind ~= "FontString" then kids[#kids + 1] = o end end
		return unpack(kids)
	end,
	GetRegions = function(s)
		local regions = {}
		for _, o in ipairs(allObjs) do
			if o.__parent == s and (o.__kind:match("^Create") or o.__kind == "Texture" or o.__kind == "FontString") then regions[#regions + 1] = o end
		end
		return unpack(regions)
	end,
	GetID = function() return 0 end,
	GetZoom = function(s) return s.__zoom or 0 end, GetZoomLevels = function() return 5 end,
	IsMouseOver = function() return false end,
}
local VERBS = { "Set", "Enable", "Disable", "Clear", "Register", "Unregister", "Update", "Raise", "Lower", "Stop", "Start",
	"Play", "Refresh", "Add", "Remove", "Release", "Hook", "Lock", "Unlock", "Click", "Adjust", "Apply", "Reset", "Toggle",
	"Invalidate", "Mark", "Attach", "Fire", "Enumerate", "Resize", "Scroll", "Refresh", "Layout", "Mark", "Pan", "Zoom",
	"Navigate", "Trigger", "Adjust", "Fade", "Flash", "Stop", "Rotate", "Load", "Save", "Select", "Close", "Open",
	"Initialize", "Clamp", "Enable", "Unlink", "Link", "On", "Show", "Hide", "Setup", "Mouse", "Draw", "Tex", "Acquire" }
local methodFallback = function(_, k)
	-- data fields read nil, like real frames (Blizzard methods are CamelCase with no underscores)
	if type(k) ~= "string" or not k:match("^%u") or k:find("_", 1, true) then return nil end
	if k:match("^Create") or k:match("^Acquire") then return function(s, ...) local o = newObj(k); o.__parent = s; return o end end
	if k:match("^Get") then
		if k:match("Texture$") or k:match("FontString$") or k:match("Frame$") or k:match("Button$") or k:match("Region$") or k:match("Object$") or k:match("Canvas$") or k:match("Map$") then
			return function() return newObj(k) end
		end
		return function() return nil end
	end
	if k:match("^Is") or k:match("^Has") or k:match("^Can") then return function() return false end end
	-- only verb-named keys act as no-op methods; anything else is a data field (nil), e.g. self.CirclesCustom
	for _, verb in ipairs(VERBS) do
		if k:sub(1, #verb) == verb and k:sub(#verb + 1, #verb + 1):match("^[%u%d]?$") then return function() end end
	end
	return nil
end
setmetatable(methods, { __index = methodFallback })
Obj.__index = methods
base.CreateFrame = function(kind, name, parent, template)
	local f = newObj(kind or "Frame", name); f.__parent = parent
	-- Blizzard templates create named child regions that AceGUI looks up via _G
	if name and template and template:find("UIDropDownMenuTemplate") then
		for _, suffix in ipairs({ "Left", "Middle", "Right", "Text", "Button", "Icon" }) do newObj("Texture", name .. suffix) end
	end
	return f
end
base.UIParent = newObj("Frame", "UIParent")
base.Minimap = newObj("Minimap", "Minimap")
base.MinimapCluster = newObj("Frame", "MinimapCluster")
base.MinimapBackdrop = newObj("Frame", "MinimapBackdrop")
base.WorldFrame = newObj("Frame", "WorldFrame")
base.WorldMapFrame = newObj("Frame", "WorldMapFrame")
base.WorldMapFrame.pinPools = {}
base.WorldMapFrame.__l, base.WorldMapFrame.__r, base.WorldMapFrame.__t, base.WorldMapFrame.__b = 300, 1300, 900, 200
base.WorldMapFrame.BorderFrame = newObj("Frame")
base.WorldMapFrame.BorderFrame.MaximizeMinimizeFrame = newObj("Frame")
base.WorldMapFrame.NavBar = newObj("Frame")
methods.GetMapID = function(s) return s.__mapID end
base.WorldMapFrame.__mapID = 1411
local mapCanvas = newObj("Frame", "WorldMapCanvas")
mapCanvas.__w, mapCanvas.__h = 1000, 667
base.WorldMapFrame.GetCanvas = function() return mapCanvas end
local mapCursor = { 0.5, 0.5 }
base.WorldMapFrame.GetNormalizedCursorPosition = function() return mapCursor[1], mapCursor[2] end
base.WorldMapFrame.SetMapID = function(s, id) s.__mapID = id end
base.UIParent.__w, base.UIParent.__h = 1920, 1080
base.ToggleWorldMap = function() local m = W.WorldMapFrame; if m:IsShown() then m:Hide() else m:Show() end end
base.ShowUIPanel = function(f) f:Show() end
base.HideUIPanel = function(f) f:Hide() end
base.SettingsPanel = newObj("Frame", "SettingsPanel")
base.EditModeManagerFrame = newObj("Frame", "EditModeManagerFrame")
base.IsInInstance = function() return false, "none" end
base.UnitAffectingCombat = function() return false end
for k, v in pairs({ ADD = "Add", ADDON_DISABLED = "Disabled", ALT_KEY = "ALT", CTRL_KEY = "CTRL", SHIFT_KEY = "SHIFT",
	COLOR = "Color", DEFAULT = "Default", DELETE = "Delete", HIDE = "Hide", SHOW = "Show", NONE = "None", NAME = "Name",
	UNKNOWN = "Unknown", OPACITY = "Opacity", MISCELLANEOUS = "Miscellaneous", KEY_BINDINGS = "Key Bindings",
	KEY_BUTTON1 = "Left Mouse Button", KEY_BUTTON2 = "Right Mouse Button", KEY_BUTTON3 = "Middle Mouse Button",
	LALT_KEY_TEXT = "Left ALT", RALT_KEY_TEXT = "Right ALT", LCTRL_KEY_TEXT = "Left CTRL", RCTRL_KEY_TEXT = "Right CTRL",
	LSHIFT_KEY_TEXT = "Left SHIFT", RSHIFT_KEY_TEXT = "Right SHIFT", MINIMAP_LABEL = "Minimap", HEADER_COLON = "%s:",
	CHAT_HEADER_SUFFIX = ": ", GAME_VERSION_LABEL = "Version", TOWNSFOLK_TRACKING_TEXT = "Town", VIDEO_QUALITY_LABEL6 = "Ultra",
	CHANNEL_CATEGORY_CUSTOM = "Custom", SELF_HIGHLIGHT_MODE_CIRCLE = "Circle", COMPACT_UNIT_FRAME_PROFILE_SUBTYPE_ALL = "All",
	LFG_LIST_LANGUAGE_PTBR = "Portuguese (BR)", LFG_LIST_LANGUAGE_PTPT = "Portuguese (PT)", BINDING_HEADER_DEBUG = "Debug",
	INTERFACEOPTIONS_ADDONCATEGORIES = "AddOns" }) do base[k] = v end
base.LOCALIZED_CLASS_NAMES_MALE = { WARRIOR = "Warrior" }
base.ITEM_QUALITY_COLORS = { [0] = { r = 0.6, g = 0.6, b = 0.6, hex = "|cff9d9d9d" }, [1] = { r = 1, g = 1, b = 1, hex = "|cffffffff" } }
base.LOCALIZED_CLASS_NAMES_FEMALE = { WARRIOR = "Warrior" }
base.RAID_CLASS_COLORS = { WARRIOR = { r = 0.78, g = 0.61, b = 0.43, colorStr = "ffc79c6e" } }
base.CopyTable = function(t, shallow)
	local c = {}
	for k, v in pairs(t) do c[k] = (type(v) == "table" and not shallow) and base.CopyTable(v) or v end
	return c
end
base.CreateFramePool = function(kind, parent, template, reset)
	local active, free = {}, {}
	return {
		Acquire = function(self)
			local f = table.remove(free)
			local new = not f
			f = f or base.CreateFrame(kind, nil, parent, template)
			active[f] = true
			return f, new
		end,
		Release = function(self, f) if active[f] then active[f] = nil; if reset then reset(self, f) end; free[#free + 1] = f end end,
		ReleaseAll = function(self) for f in pairs(active) do self:Release(f) end end,
		EnumerateActive = function() return pairs(active) end,
		GetNumActive = function() local n = 0; for _ in pairs(active) do n = n + 1 end; return n end,
	}
end
base.GetGameTime = function() return 12, 0 end
methods.AddDataProvider = function(map, p) if p.OnAdded then p:OnAdded(map) else p.owningMap = map end end
methods.RemoveDataProvider = function(map, p) p.owningMap = nil end
methods.EnumeratePinsByTemplate = function() return function() end end
base.GameTooltip = newObj("GameTooltip", "GameTooltip")
base.GameFontNormal = newObj("Font", "GameFontNormal")
base.GameFontHighlight = newObj("Font", "GameFontHighlight")
base.ACCEPT, base.CANCEL = "Accept", "Cancel"
base.GameTooltipTextLeft1 = newObj("FontString", "GameTooltipTextLeft1")
base.DEFAULT_CHAT_FRAME = newObj("Frame", "DEFAULT_CHAT_FRAME")
methods.AddMessage = function(s, m) chat[#chat + 1] = m end
base.print = function(...) local t = {} for i = 1, select("#", ...) do t[#t + 1] = tostring((select(i, ...))) end chat[#chat + 1] = table.concat(t, " ") end

-- Settings (Blizzard options) registry used by AceConfigDialog:AddToBlizOptions
local cats, nextCat = {}, 1
local function newCat(name) local c = { ID = nextCat, name = name, GetID = function(s) return s.ID end }; cats[nextCat] = c; nextCat = nextCat + 1; return c end
base.Settings = {
	RegisterCanvasLayoutCategory = function(frame, name) return newCat(name) end,
	RegisterCanvasLayoutSubcategory = function(parent, frame, name) local c = newCat(name); c.parent = parent; return c end,
	RegisterAddOnCategory = function() end,
	GetCategory = function(id) for _, c in pairs(cats) do if c.ID == id then return c end end end,
	OpenToCategory = function() end,
}

local function fire(event, ...)
	for f in pairs(registered[event] or {}) do
		local h = f.__scripts.OnEvent
		if h then
			local ok, err = pcall(h, f, event, ...)
			if not ok then report(event .. ": " .. tostring(err)) end
		end
	end
end
-- like the client: changing tracking fires MINIMAP_UPDATE_TRACKING; and every read of the tracking
-- list is counted (each makes a table per entry, so the addon mustn't read it every frame)
local trackingReads = 0
do
	local set, get = base.C_Minimap.SetTracking, base.C_Minimap.GetTrackingInfo
	base.C_Minimap.SetTracking = function(i, v) set(i, v); fire("MINIMAP_UPDATE_TRACKING") end
	base.C_Minimap.GetTrackingInfo = function(i) trackingReads = trackingReads + 1; return get(i) end
end

---------------------------------------------------------------- load the TOC
local NS = {}   -- the addon-private table every file receives as its 2nd vararg
local function norm(p) return (p:gsub("\\", "/")) end

local function parseXML(src)
	src = src:gsub("<!%-%-.-%-%->", ""):gsub("<%?.-%?>", "")
	local root = { tag = "#root", attr = {}, kids = {} }
	local stack = { root }
	for closing, tag, attrs, selfclose in src:gmatch("<(/?)([%w_:%-]+)(.-)(/?)>") do
		if closing == "/" then
			table.remove(stack)
		else
			local node = { tag = tag, attr = {}, kids = {} }
			for k, v in attrs:gmatch('([%w_:%-]+)%s*=%s*"(.-)"') do node.attr[k] = v end
			local top = stack[#stack]
			top.kids[#top.kids + 1] = node
			if selfclose ~= "/" then stack[#stack + 1] = node end
		end
	end
	return root
end

-- build an XML-defined frame the way the client does: children, parentKey/parentArray, mixins,
-- script methods, then OnLoad
local CONTAINERS = { Layers = true, Layer = true, Frames = true }
local OBJECTS = { Frame = true, Button = true, CheckButton = true, StatusBar = true, ScrollFrame = true, EditBox = true,
	Slider = true, Cooldown = true, Texture = true, FontString = true, MaskTexture = true, Line = true,
	NormalTexture = true, PushedTexture = true, HighlightTexture = true, DisabledTexture = true }
local function instantiate(node, parent)
	if node.attr.virtual == "true" then return end
	local tag = node.tag
	if CONTAINERS[tag] then
		for _, k in ipairs(node.kids) do instantiate(k, parent) end
		return
	end
	if tag == "Scripts" then
		for _, sc in ipairs(node.kids) do
			local method, fn = sc.attr.method, sc.attr["function"]
			if method then parent.__scripts[sc.tag] = function(self, ...) return self[method](self, ...) end
			elseif fn then parent.__scripts[sc.tag] = function(...) return W[fn](...) end end
		end
		return
	end
	if not OBJECTS[tag] then return end
	local name = node.attr.name
	if name and parent and parent.__name then name = name:gsub("%$parent", parent.__name) end
	local obj = newObj(tag, name)
	obj.__parent = (node.attr.parent and W[node.attr.parent]) or parent or W.UIParent
	obj.__shown = node.attr.hidden ~= "true"
	obj.__text = node.attr.text
	for mx in (node.attr.mixin or ""):gmatch("[^,%s]+") do base.Mixin(obj, W[mx] or {}) end
	if parent and node.attr.parentKey then parent[node.attr.parentKey] = obj end
	if parent and node.attr.parentArray then
		local k = node.attr.parentArray
		parent[k] = parent[k] or {}
		table.insert(parent[k], obj)
	end
	for _, k in ipairs(node.kids) do instantiate(k, obj) end
	local onload = obj.__scripts.OnLoad
	if onload then
		local ok, err = xpcall(function() onload(obj) end, function(m) return debug.traceback(m, 2) end)
		if not ok then errors[#errors + 1] = "OnLoad " .. tostring(name or tag) .. ": " .. err end
	end
	return obj
end

local function runfile(path, ...)
	local fh = assert(io.open(path, "rb")); local src = fh:read("*a"); fh:close()
	src = src:gsub("^\239\187\191", "")
	local fn, err = loadstring(src, "@" .. path:gsub("^.*/AddOns/", ""))
	if not fn then report(err); return end
	setfenv(fn, W)
	local n, args = select("#", ...), { ... }
	local ok, e = xpcall(function() return fn(unpack(args, 1, n)) end, function(m) return debug.traceback(m, 2) end)
	if not ok then errors[#errors + 1] = e end
end

local files = {}
local function loadXml(xml)
	local f = assert(io.open(ROOT .. "/" .. xml))
	local tree = parseXML(f:read("*a")); f:close()
	local dir = xml:match("^(.*)/[^/]*$") or ""
	local ui = tree.kids[1] or tree
	for _, node in ipairs(ui.kids) do
		local file = node.attr.file and ((dir ~= "" and dir .. "/" or "") .. norm(node.attr.file))
		if node.tag == "Script" then
			files[#files + 1] = file; runfile(ROOT .. "/" .. file, TOC_NAME, NS)
		elseif node.tag == "Include" then
			loadXml(file)
		else
			instantiate(node, nil)
		end
	end
end
for line in io.lines(ROOT .. "/" .. TOC_NAME .. ".toc") do
	line = line:gsub("\r", "")
	if line ~= "" and not line:match("^#") then
		local p = norm(line)
		if p:match("%.xml$") then loadXml(p) else files[#files + 1] = p; runfile(ROOT .. "/" .. p, TOC_NAME, NS) end
	end
end
print(("loaded %d files"):format(#files))

---------------------------------------------------------------- saved variables + lifecycle
if SVFILE and SVFILE ~= "" then runfile(SVFILE) end
fire("ADDON_LOADED", TOC_NAME)
W.__loggedIn = true
fire("PLAYER_LOGIN")
fire("PLAYER_ENTERING_WORLD", true, false)
fire("SKILL_LINES_CHANGED")
fire("MINIMAP_UPDATE_TRACKING")

---------------------------------------------------------------- gameplay simulation
local Apex = W.ApexGatherer
local function step(name, f)
	local ok, err = xpcall(f, function(m) return debug.traceback(m, 2) end)
	print((ok and "ok   " or "FAIL ") .. name)
	if not ok then errors[#errors + 1] = name .. ": " .. err end
end
-- the client maps SLASH_<NAME><n> globals to SlashCmdList[NAME]
local function slashCommands()
	local map = {}
	for k, v in pairs(W) do
		local name = type(k) == "string" and k:match("^SLASH_(.-)%d+$")
		if name and type(v) == "string" then map[v:lower()] = name end
	end
	return map
end
local function slash(line)
	local cmd, rest = line:match("^(%S+)%s*(.-)$")
	local name = slashCommands()[cmd:lower()]
	assert(name and W.SlashCmdList[name], "unknown slash command " .. cmd)
	W.SlashCmdList[name](rest)
end
local function pack(x, y) return math.floor(x * 10000 + 0.5) * 10000 + math.floor(y * 10000 + 0.5) end
local function unpackC(c) return math.floor(c / 10000) / 10000, (c % 10000) / 10000 end
local ZONE = 1411
local player = { 0.4321, 0.5678 }

if not Apex then errors[#errors + 1] = "ApexGatherer global missing after load" else
	local Catalog = Apex.Catalog
	Apex.HBD.GetPlayerZonePosition = function() return player[1], player[2], ZONE end
	Apex.HBD.GetPlayerZone = function() return ZONE end
	Apex.HBD.GetZoneSize = function(_, zone) if zone == 999999 then return 0, 0 end return 1000, 1000 end   -- 999999: unknown, like real HBD
	Apex.HBD.GetLocalizedMap = function(_, zone) return zone == ZONE and "Durotar" or ("Map " .. zone) end
	Apex.HBD.GetWorldCoordinatesFromZone = function(_, x, y, zone) if zone == ZONE then return x * 1000, y * 1000, 1 end end
	local function at(x, y) player[1], player[2] = x, y end
	local function gather(spellID, target, tooltip)
		W.GameTooltipTextLeft1.__text = tooltip
		fire("UNIT_SPELLCAST_SENT", "player", target, "guid", spellID)
		fire("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", spellID)
	end
	local function mining() return Apex:CountNodes("Mining") end

	step("startup: saved data and modules", function()
		assert(type(W.ApexGathererDB) == "table" and type(W.ApexGathererNodes) == "table" and type(W.ApexGathererRoutes) == "table", "saved variables missing")
		for _, name in ipairs({ "Collector", "Pins", "Sharing", "Routes", "RouteDrawing", "RouteEditor", "RouteOptions", "Flyout", "HUD", "Settings", "Launcher" }) do
			assert(Apex:GetModule(name, true), "module missing: " .. name)
		end
	end)

	-- gathering
	step("mine a known vein", function()
		local before = mining()
		at(0.30, 0.30); gather(2575, "Copper Vein")
		assert(mining() == before + 1, "not recorded")
		assert(Apex:GetZoneNodes("Mining", ZONE)[pack(0.30, 0.30)] == Catalog:Find("Mining", "Copper Vein"), "wrong spot or id")
	end)
	step("the same vein again: one spot; later visits settle it between where you stood", function()
		local before = mining()
		at(0.30, 0.30); gather(2575, "Copper Vein")
		at(0.303, 0.30); gather(2575, "Copper Vein")   -- clicked again 3 yards on, same visit
		assert(mining() == before, "recorded twice")
		assert(Apex:GetZoneNodes("Mining", ZONE)[pack(0.30, 0.30)], "a repeat click moved it")
		clockOffset = clockOffset + 61                  -- a later visit, from 5 yards east
		at(0.305, 0.30); gather(2575, "Copper Vein")
		assert(mining() == before, "recorded twice")
		assert(Apex:GetZoneNodes("Mining", ZONE)[pack(0.3025, 0.30)], "not moved halfway")
		clockOffset = clockOffset + 61                  -- and one from the west side
		at(0.2975, 0.30); gather(2575, "Copper Vein")
		assert(mining() == before and Apex:GetZoneNodes("Mining", ZONE)[pack(0.30, 0.30)], "didn't settle between the visits")
		at(0.35, 0.30); gather(2575, "Copper Vein")    -- 50 yards away: another spot
		assert(mining() == before + 1, "a separate spot was merged")
	end)
	step("a richer ore on a poorer one's spot replaces it", function()
		local before = mining()
		at(0.50, 0.50); gather(2575, "Tin Vein")
		at(0.50, 0.50); gather(2575, "Silver Vein")
		assert(mining() == before + 1, "shared spawn recorded twice")
	end)
	step("an unknown vein is learned", function()
		at(0.60, 0.20); gather(2575, "Glimmering Copper Vein")
		local id = Catalog:Find("Mining", "Glimmering Copper Vein")
		assert(id and id >= 9001, "not learned")
		assert(Catalog:Icon(id) == Catalog:Icon(Catalog:Find("Mining", "Copper Vein")), "didn't borrow the copper icon")
		local rock, ore, tint = Catalog:Marker(id)
		local _, _, copper = Catalog:Marker(Catalog:Find("Mining", "Copper Vein"))
		assert(rock:find("MarkerRock$") and ore:find("MarkerOre$") and tint[1] == copper[1] and tint[2] == copper[2], "not drawn as copper")
		local _, _, silver = Catalog:Marker(Catalog:Find("Mining", "Silver Vein"))
		local _, _, truesilver = Catalog:Marker(Catalog:Find("Mining", "Truesilver Deposit"))
		assert(silver[3] ~= truesilver[3], "truesilver drawn as silver")
	end)
	step("an unknown herb is learned", function()
		at(0.62, 0.22); gather(2366, "Weird Gloomleaf")
		assert(Catalog:Find("Herbalism", "Weird Gloomleaf"), "not learned")
	end)
	step("an unknown fishing pool is only logged", function()
		facing.value = 0
		at(0.64, 0.24); gather(7620, nil, "Weird Pool")
		facing.value = nil
		assert(not Catalog:Find("Fishing", "Weird Pool"), "fishing pool learned")
		assert(Apex:GetUnknownNodes()["Fishing:Weird Pool"], "not logged")
	end)
	step("a known pool is recorded ahead of the player", function()
		facing.value = 0   -- north
		at(0.40, 0.40); gather(7620, nil, "Oily Blackmouth School")
		facing.value = nil
		local data = Apex:GetZoneNodes("Fishing", ZONE)
		assert(data and data[pack(0.40, 0.385)], "pool not 15 yards north of the player")
	end)
	step("a node is recorded a step ahead of the player, who faces it", function()
		facing.value = math.pi / 2   -- west
		at(0.86, 0.86); gather(2575, "Copper Vein")
		facing.value = nil
		assert(Apex:GetZoneNodes("Mining", ZONE)[pack(0.858, 0.86)], "not 2 yards west of the player")
		Apex:RemoveNode("Mining", ZONE, pack(0.858, 0.86))
	end)
	step("opening an unknown object is only logged", function()
		at(0.66, 0.26); gather(3365, "Quest Crate")
		assert(not Catalog:Find("Treasure", "Quest Crate") and Apex:GetUnknownNodes()["Treasure:Quest Crate"], "quest object mishandled")
	end)
	step("a gather that fails (someone else is mining it) still records the spot", function()
		local before = mining()
		at(0.70, 0.70)
		fire("UNIT_SPELLCAST_SENT", "player", "Iron Deposit", "guid", 2575)
		fire("UNIT_SPELLCAST_FAILED", "player", "guid", 2575)
		assert(mining() == before + 1, "the node wasn't recorded")
	end)
	step("clicking the same node again records and shares it once", function()
		local gathered = 0
		local listener = {}
		W.LibStub("AceEvent-3.0"):Embed(listener)
		listener:RegisterMessage("APEX_NODE_GATHERED", function() gathered = gathered + 1 end)
		at(0.74, 0.74)
		gather(2575, "Copper Vein"); gather(2575, "Copper Vein"); gather(2575, "Copper Vein")
		listener:UnregisterMessage("APEX_NODE_GATHERED")
		assert(gathered == 1, "gathered " .. gathered .. " times")
	end)
	step("a stopped kind isn't recorded", function()
		Apex.db.profile.locked.Mining = true
		local before = mining()
		at(0.72, 0.72); gather(2575, "Copper Vein")
		Apex.db.profile.locked.Mining = false
		assert(mining() == before, "recorded while stopped")
	end)

	-- the database
	step("export, clear and import give the same nodes back", function()
		local text = Apex:ExportNodes()
		local saved = {}
		for _, kind in ipairs(Apex.KINDS) do
			saved[kind] = {}
			for zone, data in pairs(W.ApexGathererNodes.kinds[kind]) do
				saved[kind][zone] = {}
				for coord, id in pairs(data) do saved[kind][zone][coord] = id end
			end
			Apex:ClearKind(kind)
		end
		assert(mining() == 0)
		local ok, added = Apex:ImportNodes(text)
		assert(ok, added)
		-- every node came back, or one of the same spawn within the cleanup range stands for it
		for kind, zones in pairs(saved) do
			for zone, data in pairs(zones) do
				for coord, id in pairs(data) do
					local found = false
					for _, other in Apex:NodesNear(kind, zone, coord, Apex.db.profile.cleanupRange[kind]) do
						if Catalog:SameSpawn(id, other) then found = true end
					end
					assert(found, ("%s node %d in zone %d missing after the import"):format(kind, coord, zone))
				end
			end
		end
		local again, added2 = Apex:ImportNodes(text)
		assert(again and added2 == 0, "importing twice added nodes")
		assert(not Apex:ImportNodes("print('hi')"), "accepted something that isn't an export")
		assert(not Apex:ImportNodes(""), "accepted nothing")
	end)
	step("clean up merges duplicate spots", function()
		local data = Apex:GetZoneNodes("Mining", ZONE)
		local id = Catalog:Find("Mining", "Iron Deposit")
		data[pack(0.80, 0.80)], data[pack(0.801, 0.80)] = id, id   -- one yard apart
		assert(Apex:CleanupDuplicates() >= 1, "nothing cleaned up")
		assert(not (data[pack(0.80, 0.80)] and data[pack(0.801, 0.80)]), "duplicate left")
	end)
	step("forget a learned node", function()
		Apex:ForgetLearnedNode("Herbalism", "Weird Gloomleaf")
		assert(not Catalog:Find("Herbalism", "Weird Gloomleaf"), "still learned")
	end)

	-- pins
	local function minimapPins()
		local n = 0
		for icon in pairs(Apex.HBDPins.minimapPins) do if icon.isApexPin then n = n + 1 end end
		return n
	end
	step("pins: one per shown node on the minimap", function()
		tick()
		local shown = 0
		for _, kind in ipairs(Apex.KINDS) do shown = shown + #(function() local t = {} for c in pairs(Apex:GetZoneNodes(kind, ZONE) or {}) do t[#t + 1] = c end return t end)() end
		assert(minimapPins() == shown, ("minimap pins %d, nodes %d"):format(minimapPins(), shown))
		Apex.db.profile.pins.show.Mining = false; Apex:SettingsChanged(); tick()
		local miningHere = 0
		for _ in pairs(Apex:GetZoneNodes("Mining", ZONE) or {}) do miningHere = miningHere + 1 end
		assert(minimapPins() == shown - miningHere, "hidden kind still pinned")
		Apex.db.profile.pins.show.Mining = true; Apex:SettingsChanged(); tick()
		assert(minimapPins() == shown, "pins didn't come back")
	end)

	step("pins: nameless, so minimap button collectors leave them on the map", function()
		for icon in pairs(Apex.HBDPins.minimapPins) do
			if icon.isApexPin then assert(icon:GetName() == nil, "a named pin: " .. tostring(icon:GetName())) end
		end
	end)
	step("pins: a ring round nodes tracking shows, a picture elsewhere", function()
		local Pins = Apex:GetModule("Pins")
		local data = Apex:GetZoneNodes("Mining", ZONE)
		data[pack(0.20, 0.20)] = Catalog:Find("Mining", "Copper Vein")
		data[pack(0.20, 0.30)] = Catalog:Find("Mining", "Copper Vein")   -- 100 yards on
		Apex:SettingsChanged(); tick()
		at(0.20, 0.21)   -- tracking range here: 80% of the stub's 100-yard view = 80 yards
		Pins:UpdateRings()
		local near, far
		for icon in pairs(Apex.HBDPins.minimapPins) do
			if icon.coord == pack(0.20, 0.20) then near = icon elseif icon.coord == pack(0.20, 0.30) then far = icon end
		end
		assert(near and far, "pins missing")
		local function looks(pin)
			return (pin.ring:IsShown() and "ring" or "") .. (pin.picture:IsShown() and pin.tinted:IsShown() and "picture" or "")
		end
		assert(looks(near) == "ring" and looks(far) == "picture", "near " .. looks(near) .. ", far " .. looks(far))
		assert(near.ring:GetWidth() == Apex.db.profile.pins.ringSize, "ring not sized for the blip")
		W.C_Minimap.SetTracking(1, false)   -- Find Minerals off: no blip, so the picture
		Pins:UpdateRings()
		assert(looks(near) == "picture", "not tracking minerals: " .. looks(near))
		W.C_Minimap.SetTracking(1, true)
		Apex.db.profile.pins.ring = false   -- rings off: pictures everywhere
		Pins:UpdateRings()
		assert(looks(near) == "picture", "rings off: " .. looks(near))
		Apex.db.profile.pins.ring = true
		data[pack(0.20, 0.20)], data[pack(0.20, 0.30)] = nil, nil
		Apex:SettingsChanged(); tick()
	end)

	-- settings
	local ACR = W.LibStub("AceConfigRegistry-3.0")
	step("settings pages are valid", function()
		for _, app in ipairs({ "ApexGatherer", "ApexGatherer/Filters", "ApexGatherer/Maintenance", "ApexGatherer/Learned", "ApexGatherer/Import",
			"ApexGatherer/Export", "ApexGatherer/Sharing", "ApexGatherer/HUD", "ApexGatherer/RoutesPage", "ApexGatherer/Profiles",
			"ApexGatherer/FAQ", "ApexGatherer/Routes" }) do
			local ok, err = pcall(ACR.ValidateOptionsTable, ACR, ACR:GetOptionsTable(app, "dialog", "Harness-1.0"), app)
			assert(ok, app .. ": " .. tostring(err))
		end
		local o = ACR:GetOptionsTable("ApexGatherer", "dialog", "Harness-1.0")
		assert(o.args.summary.name():find("nodes recorded"), "summary")
	end)
	step("FAQ has its sections", function()
		local faq = ACR:GetOptionsTable("ApexGatherer/FAQ", "dialog", "Harness-1.0")
		local sections, questions = 0, 0
		for _, o in pairs(faq.args) do
			if o.type == "header" then sections = sections + 1 else questions = questions + 1 end
		end
		assert(sections == 6 and questions >= 25, ("%d sections, %d questions"):format(sections, questions))
	end)

	-- slash commands and the minimap button
	local opened
	W.Settings.OpenToCategory = function(id) opened = id end
	step("only /ag, /apex, /apexgatherer, /agatherer, each opening settings", function()
		local cmds = {}
		for cmd, name in pairs(slashCommands()) do
			cmds[#cmds + 1] = cmd
			assert(name == "APEXGATHERER", cmd .. " belongs to " .. name)
		end
		table.sort(cmds)
		assert(table.concat(cmds, " ") == "/ag /agatherer /apex /apexgatherer", "slash commands: " .. table.concat(cmds, " "))
		for name in pairs(W.SlashCmdList) do assert(name == "APEXGATHERER", "extra slash handler " .. name) end
		for _, c in ipairs({ "/ag", "/apex", "/apexgatherer", "/agatherer", "/AG" }) do
			opened = nil; slash(c); assert(opened, c .. " did not open settings")
		end
	end)
	local HUD = Apex:GetModule("HUD")
	local Flyout = Apex:GetModule("Flyout")
	local ACD = W.LibStub("AceConfigDialog-3.0")
	step("minimap button clicks", function()
		local button = W.ApexGathererMinimapButton
		assert(button and button:GetParent() == W.Minimap, "no minimap button")
		opened = nil; button.__scripts.OnClick(button, "RightButton"); assert(opened, "right-click: settings")
		button.__scripts.OnClick(button, "LeftButton"); assert(HUD:IsOpen(), "left-click: HUD")
		button.__scripts.OnClick(button, "LeftButton"); assert(not HUD:IsOpen(), "left-click again: HUD closed")
		button.__scripts.OnClick(button, "MiddleButton"); tick(); assert(Flyout:IsOpen(), "middle-click: routes")
		W.WorldMapFrame:Hide(); ACD.frame.__scripts.OnUpdate(ACD.frame)
	end)

	-- sharing
	local S = Apex:GetModule("Sharing")
	local share = Apex.db.profile.sharing
	local function flush()
		for _ = 1, 400 do
			clockOffset = clockOffset + 0.5
			pump(); tick()
			if not S:IsSending() and not (W.ChatThrottleLib and W.ChatThrottleLib.bQueueing) then break end
		end
	end
	local function take() local t = sentAddon; sentAddon = {}; return t end
	local function deliver(msgs, from, channel)
		for _, m in ipairs(msgs) do
			if m.prefix == "ApexGatherer" then fire("CHAT_MSG_ADDON", m.prefix, m.text, channel or m.chatType, from) end
		end
	end
	local function raw(text, from, channel) fire("CHAT_MSG_ADDON", "ApexGatherer", text, channel, from) end
	local function kinds(msgs)
		local out = {}
		for _, m in ipairs(msgs) do
			if not m.text:find("^[\2\3]") then out[#out + 1] = m.text:match("^\1?(%u);") or "?" end
		end
		return table.concat(out)
	end
	local COPPER = Catalog:Find("Mining", "Copper Vein")
	local shared
	step("sharing: send my nodes to the guild", function()
		take()
		assert(S:SendNodes("GUILD", nil, share.types))
		flush()
		shared = take()
		assert(#shared >= 3 and shared[1].chatType == "GUILD", "nothing sent")
		assert(kinds(shared):match("^OD+E$"), "message order " .. kinds(shared))
	end)
	step("sharing: a guildmate's collection is asked about, then merged", function()
		local saved = {}
		for zone, data in pairs(W.ApexGathererNodes.kinds.Mining) do saved[zone] = data end
		W.wipe(W.ApexGathererNodes.kinds.Mining)
		popups = {}
		deliver(shared, "Guildie-Realm", "GUILD")
		assert(#popups == 1 and popups[1].which == "APEXGATHERER_SHARE_OFFER", "no prompt")
		assert(mining() == 0, "merged before accepting")
		W.StaticPopupDialogs.APEXGATHERER_SHARE_OFFER.OnAccept(nil, popups[1].data)
		for zone, data in pairs(saved) do
			for coord, id in pairs(data) do
				local found = false
				for _, other in Apex:NodesNear("Mining", zone, coord, Apex.db.profile.cleanupRange.Mining) do
					if Catalog:SameSpawn(id, other) then found = true end
				end
				assert(found, "node missing after the merge")
			end
		end
		local count = mining()
		deliver(shared, "Guildie-Realm", "GUILD")
		W.StaticPopupDialogs.APEXGATHERER_SHARE_OFFER.OnAccept(nil, popups[2].data)
		assert(mining() == count, "the same nodes were added twice")
	end)
	step("sharing: a declined whisper adds nothing", function()
		local before = mining()
		popups = {}
		deliver({ { prefix = "ApexGatherer", text = "O;2;ab12;1;-;1" }, { prefix = "ApexGatherer", text = "D;2;ab12;1;M;1411;12344321:" .. COPPER }, { prefix = "ApexGatherer", text = "E;2;ab12;1" } }, "Stranger", "WHISPER")
		assert(#popups == 1, "a whispered send must ask")
		W.StaticPopupDialogs.APEXGATHERER_SHARE_OFFER.OnCancel(nil, popups[1].data)
		assert(mining() == before, "declined nodes added")
	end)
	step("sharing: learned nodes travel by name", function()
		popups = {}
		deliver({ { prefix = "ApexGatherer", text = "O;2;cd34;1;-;1" }, { prefix = "ApexGatherer", text = "D;2;cd34;1;M;1411;23455432:@Shimmering Test Vein" }, { prefix = "ApexGatherer", text = "E;2;cd34;1" } }, "Friend", "WHISPER")
		W.StaticPopupDialogs.APEXGATHERER_SHARE_OFFER.OnAccept(nil, popups[1].data)
		local id = Catalog:Find("Mining", "Shimmering Test Vein")
		assert(id and id >= 9001 and Apex:GetZoneNodes("Mining", ZONE)[23455432] == id, "shared learned node not recorded")
		take()
		S:SendNodes("WHISPER", "Friend", { Mining = true })
		flush()
		local all = {}
		for _, m in ipairs(take()) do all[#all + 1] = m.text end
		assert(table.concat(all):find("@Shimmering Test Vein", 1, true), "learned node not sent by name")
		Apex:ForgetLearnedNode("Mining", "Shimmering Test Vein")
	end)
	step("sharing: live nodes from the guild only", function()
		local before = mining()
		raw("N;2;M;1411;34566543;" .. COPPER, "Guildie", "GUILD")
		assert(mining() == before + 1, "live node not added")
		raw("N;2;M;1411;34566543;" .. COPPER, "Guildie", "GUILD")
		raw("N;2;M;1411;45677654;" .. COPPER, "Partymate", "PARTY")
		raw("N;2;M;1411;45677654;" .. COPPER, "Guildie", "WHISPER")
		raw("N;9;M;1411;45677654;" .. COPPER, "Guildie", "GUILD")
		assert(mining() == before + 1, "accepted a duplicate, party, whisper or other version")
		tick()
	end)
	step("sharing: my gathers go to the guild only when switched on", function()
		take()
		at(0.61, 0.62); gather(2575, "Copper Vein")
		assert(#take() == 0, "shared with live sharing off")
		share.liveGuild = true
		at(0.63, 0.64); gather(2575, "Copper Vein")
		flush()
		local msgs = take()
		share.liveGuild = false
		assert(#msgs == 1 and msgs[1].text == ("N;2;M;1411;63006400;%d"):format(COPPER), "live share: " .. tostring(msgs[1] and msgs[1].text))
	end)
	step("sharing: ask the guild; answers come straight in", function()
		take()
		assert(S:RequestNodes("GUILD", nil, share.types))
		flush()
		local q = take()
		local req = q[1] and q[1].text:match("^Q;2;(%w+);MHFT$")
		assert(req, "bad request")
		local before = mining()
		popups = {}
		deliver({ { prefix = "ApexGatherer", text = "O;2;ef56;2;" .. req .. ";1" }, { prefix = "ApexGatherer", text = ("D;2;ef56;1;M;1411;56788765:%d,67899876:%d"):format(COPPER, COPPER) }, { prefix = "ApexGatherer", text = "E;2;ef56;1" } }, "Guildie", "WHISPER")
		assert(#popups == 0 and mining() == before + 2, "answer to my request not merged straight in")
	end)
	step("sharing: answer a guildmate's request by whisper", function()
		take()
		raw("Q;2;9f9f;M", "Guildie", "GUILD")
		tick(); flush()
		local msgs = take()
		assert(#msgs >= 3 and msgs[1].chatType == "WHISPER" and msgs[1].target == "Guildie" and msgs[1].text:match(";9f9f;%d+$"), "no whispered answer")
	end)
	step("sharing: a player's request asks first; declining tells them", function()
		take(); popups = {}
		raw("Q;2;7a7a;MH", "Stranger", "WHISPER")
		assert(#popups == 1 and popups[1].which == "APEXGATHERER_SHARE_REQUEST", "no prompt")
		W.StaticPopupDialogs.APEXGATHERER_SHARE_REQUEST.OnCancel(nil, popups[1].data)
		flush()
		local msgs = take()
		assert(#msgs == 1 and msgs[1].text == "R;2;7a7a;declined", "no decline sent")
	end)
	step("sharing: junk and my own messages are ignored", function()
		local before = mining()
		for _, text in ipairs({ "N;2;M;999999;12341234;101", "N;2;M;1411;123456789;101", "N;2;M;1411;1234x;101", "N;2;M;1411;12341234;4242",
			"N;2;Z;1411;12341234;101", "N;2;M;1411;12341234;@", "N;2;M;1411;12341234;201", "N;2", "D;2;zz;1;M;1411;1:1", "E;2;zz;1", "O;2;;", "garbage", "" }) do
			raw(text, "Guildie", "GUILD")
		end
		raw("N;2;M;1411;11112222;101", "Tester Example", "GUILD")   -- my own, by my whole name
		assert(mining() == before, "junk or own message added a node")
		-- my own guild request isn't answered by me
		take()
		raw("Q;2;selfreq;M", "Tester Example", "GUILD")
		for _ = 1, 3 do tick() end
		flush()
		assert(#take() == 0, "answered my own request")
	end)

	step("sharing: what a player has from me (or gave me) doesn't go back when they ask", function()
		take()
		assert(S:SendNodes("WHISPER", "Swapper Friend", share.types))   -- they get all mine
		flush(); take()
		-- later they ask me: nothing new for them, so a short "nothing you don't have" instead
		S:AnswerRequest({ sender = "Swapper Friend", types = share.types, req = "swapreq" }, true)
		flush()
		local msgs = take()
		assert(kinds(msgs) == "R" and msgs[1].text:find("^R;2;swapreq;same"), "sent back: " .. kinds(msgs))
		-- a node gathered since does go to them
		at(0.91, 0.91); gather(2575, "Copper Vein")
		S:AnswerRequest({ sender = "Swapper Friend", types = share.types, req = "swapreq2" }, true)
		flush()
		msgs = take()
		local items = 0
		for _, m in ipairs(msgs) do
			local list = m.text:match("^D;2;[^;]+;[^;]+;[^;]+;[^;]+;(.+)$")
			if list then for _ in list:gmatch("[^,]+") do items = items + 1 end end
		end
		assert(kinds(msgs):match("^OD+E$") and items == 1, ("new node: %s, %d items"):format(kinds(msgs), items))
		Apex:RemoveNode("Mining", ZONE, pack(0.91, 0.91))
	end)
	step("sharing: a lost part is asked for again; one that stays lost is reported", function()
		-- I ask a player, and their answer is the send below (my own nodes, as if from them)
		local function answer(peer, dropPart)
			take()
			assert(S:RequestNodes("WHISPER", peer, share.types))
			flush()
			local req = take()[1].text:match("^Q;2;(%w+);")
			assert(S:SendNodes("WHISPER", peer, share.types, req))
			flush()
			local msgs, batch, parts = {}, nil, nil
			for _, m in ipairs(take()) do
				local b, n = m.text:match("^O;2;(%w+);%d+;%w+;(%d+)$")
				if b then batch, parts = b, tonumber(n) end
				if not m.text:find("^D;2;%w+;" .. dropPart .. ";") then msgs[#msgs + 1] = m end
			end
			return msgs, batch, parts
		end
		local function asked(msgs)
			for _, m in ipairs(msgs) do
				if m.text:find("^M;2;") then return m end
			end
		end
		local msgs, batch, parts = answer("Lossy Peer", 2)
		assert(parts and parts >= 2 and #msgs == parts + 1, ("parts %s, messages %d"):format(tostring(parts), #msgs))
		deliver(msgs, "Lossy Peer", "WHISPER")
		flush()
		local m = asked(take())
		assert(m and m.target == "Lossy Peer" and m.text == ("M;2;%s;2"):format(batch), "lost part not asked for: " .. tostring(m and m.text))
		-- their addon (mine here) sends it again, and the end
		deliver({ m }, "Lossy Peer", "WHISPER")
		flush()
		local again = take()
		assert(kinds(again) == "DE", "sent again: " .. kinds(again))
		deliver(again, "Lossy Peer", "WHISPER")
		local line = S:GetLog()[1]
		assert(line:find("from Lossy Peer") and not line:find("lost"), "after the resend: " .. line)
		-- the next time the part never comes: asked for twice, then reported lost
		msgs = answer("Lossier Peer", 1)
		deliver(msgs, "Lossier Peer", "WHISPER")
		for _ = 1, 3 do clockOffset = clockOffset + 31; tick() end   -- nothing more ever arrives
		local asks = 0
		for _, sent in ipairs(take()) do if sent.text:find("^M;2;") then asks = asks + 1 end end
		line = S:GetLog()[1]
		assert(asks == 2 and line:find("from Lossier Peer") and line:find("lost on the way"), ("asked %d times; %s"):format(asks, line))
	end)
	step("sharing: light on the realm (cooldowns, one popup per sender)", function()
		-- a second guild-wide send or ask right away is refused, and allowed again later
		local ok, err = S:SendNodes("GUILD", nil, share.types)
		assert(not ok and err:find("few minutes ago"), "a second guild send went out right away")
		ok, err = S:RequestNodes("GUILD", nil, share.types)
		assert(not ok and err:find("few minutes ago"), "asked the guild again right away")
		assert(S:RequestNodes("WHISPER", "Friend2", share.types), "asking someone else was blocked")
		flush(); take()
		clockOffset = clockOffset + 301
		assert(S:RequestNodes("GUILD", nil, share.types), "still blocked after the cooldown")
		flush(); take()
		-- the same guildmate's request is answered once per half hour
		raw("Q;2;8e8e;M", "Guildie", "GUILD")
		tick(); flush()
		assert(#take() == 0, "answered the same guildmate twice within the cooldown")
		-- one popup per sender at a time
		popups = {}
		raw("O;2;aa01;3;-;1", "Pest", "WHISPER")
		raw("O;2;aa02;3;-;1", "Pest", "WHISPER")
		raw("Q;2;aa03;M", "Pest", "WHISPER")
		raw("Q;2;aa04;M", "Pest", "WHISPER")
		assert(#popups == 2, "popups from one sender: " .. #popups)
		W.StaticPopupDialogs.APEXGATHERER_SHARE_OFFER.OnCancel(nil, popups[1].data)
		W.StaticPopupDialogs.APEXGATHERER_SHARE_REQUEST.OnCancel(nil, popups[2].data)
		flush(); take()
	end)

	-- routes
	local Routes = Apex:GetModule("Routes")
	local Optimizer = Apex.Optimizer
	local Editor = Apex:GetModule("RouteEditor")
	local function addCopper(n, seed)
		math.randomseed(seed)
		for _ = 1, n do Apex:MergeNode("Mining", ZONE, pack(0.1 + math.random() * 0.8, 0.1 + math.random() * 0.8), COPPER, true) end
	end
	local function copperSpots()
		local n = 0
		for _, id in pairs(Apex:GetZoneNodes("Mining", ZONE)) do if id == COPPER then n = n + 1 end end
		return n
	end
	step("routes: create from recorded nodes, optimized", function()
		addCopper(60, 3)
		assert(Routes:Create(ZONE, "Copper run", { [COPPER] = true }))
		local route = Routes:Get(ZONE, "Copper run")
		assert(#route.points == copperSpots(), "points " .. #route.points)
		local naive = {}
		for i, c in ipairs(route.points) do naive[i] = c end
		table.sort(naive)
		assert(route.length < Optimizer:PathLength(naive, ZONE) * 0.6, "not optimized")
		assert(not Routes:Create(ZONE, "Copper run", { [COPPER] = true }), "duplicate name allowed")
		assert(not Routes:Create(ZONE, "Empty", { [Catalog:Find("Mining", "Gold Vein")] = true }), "empty route allowed")
	end)
	step("routes: stay as made; Update route adds new spots and drops deleted ones", function()
		local route = Routes:Get(ZONE, "Copper run")
		local before = #route.points
		at(0.95, 0.05); gather(2575, "Copper Vein")
		assert(#route.points == before, "a new spot joined the route by itself")
		-- a hand-placed point must survive an update
		table.insert(route.points, 1, pack(0.02, 0.98))
		local victim = route.points[3]
		Apex:RemoveNode("Mining", ZONE, victim)
		assert(#route.points == before + 1, "a deleted spot left the route by itself")
		local ok, added, removed = Routes:Update(ZONE, "Copper run")
		assert(ok and added == 1 and removed == 1, ("update: %s %s %s"):format(tostring(ok), tostring(added), tostring(removed)))
		route = Routes:Get(ZONE, "Copper run")
		local hasNew, hasHand, hasVictim = false, false, false
		for _, c in ipairs(route.points) do
			if c == pack(0.95, 0.05) then hasNew = true end
			if c == pack(0.02, 0.98) then hasHand = true end
			if c == victim then hasVictim = true end
		end
		assert(hasNew and hasHand and not hasVictim, "update result wrong")
		assert(select(2, Routes:Update(ZONE, "Copper run")) == 0, "a second update added spots again")
		-- put it back the way the later steps expect
		for i, c in ipairs(route.points) do if c == pack(0.02, 0.98) then table.remove(route.points, i) break end end
	end)
	step("routes: drawn on the world map and minimap", function()
		W.WorldMapFrame.__mapID = ZONE
		W.WorldMapFrame:Show()
		local Drawing = Apex:GetModule("RouteDrawing")
		Drawing:Refresh()
		local canvas = Drawing:WorldCanvas()
		local lines = 0
		for _, o in ipairs(allObjs) do if o.__parent == canvas and o.__kind == "CreateLine" and o.__shown then lines = lines + 1 end end
		assert(lines == #Routes:Get(ZONE, "Copper run").points, "world map lines " .. lines)
		at(0.5, 0.5)   -- among the route's points, inside the minimap's view
		Drawing:DrawMinimap()
		local mini = Drawing:MinimapLayer()
		lines = 0
		for _, o in ipairs(allObjs) do if o.__parent == mini and o.__kind == "CreateLine" and o.__shown then lines = lines + 1 end end
		assert(lines > 0, "nothing on the minimap")
		W.WorldMapFrame:Hide()
	end)
	step("routes: cluster, optimize and uncluster", function()
		local route = Routes:Get(ZONE, "Copper run")
		local spots = #route.points
		Routes:Cluster(ZONE, "Copper run", 40)
		assert(route.clusters and #route.points < spots, "not clustered")
		local plain = route.length
		Routes:Optimize(ZONE, "Copper run")
		route = Routes:Get(ZONE, "Copper run")
		assert(route.length <= plain + 1e-6, "optimizing made it longer")
		local farthest, covered = 0, 0
		for i, point in ipairs(route.points) do
			local x, y = unpackC(point)
			for _, m in ipairs(route.clusters[i]) do
				local mx, my = unpackC(m)
				farthest, covered = math.max(farthest, (((x - mx) * 1000) ^ 2 + ((y - my) * 1000) ^ 2) ^ 0.5), covered + 1
			end
		end
		assert(covered == spots and farthest <= 40 + 1e-6, ("covers %d of %d, farthest %.1f yd"):format(covered, spots, farthest))
		Routes:Uncluster(ZONE, "Copper run")
		assert(not route.clusters and #Routes:Get(ZONE, "Copper run").points == spots, "uncluster")
	end)
	step("routes: background optimizing keeps the game running and finishes", function()
		local text
		assert(Routes:OptimizeInBackground(ZONE, "Copper run", function(t) text = t end))
		assert(Routes:Busy(ZONE, "Copper run"), "not busy while optimizing")
		local frames = 0
		while Optimizer:IsRunning() and frames < 20000 do pump(); frames = frames + 1 end
		assert(not Optimizer:IsRunning() and text and text:find("^Done"), "didn't finish: " .. tostring(text))
	end)
	step("routes: taboo areas drop spots and are avoided", function()
		assert(Routes:CreateTaboo(ZONE, "Camp"))
		local taboo = Routes:GetTaboo(ZONE, "Camp")
		taboo.points = { pack(0.3, 0.3), pack(0.7, 0.3), pack(0.7, 0.7), pack(0.3, 0.7) }
		Routes:SetTaboo(ZONE, "Copper run", "Camp", true)
		for _, point in ipairs(Routes:Get(ZONE, "Copper run").points) do
			local x, y = unpackC(point)
			assert(not (x > 0.3 and x < 0.7 and y > 0.3 and y < 0.7), "spot inside the taboo kept")
		end
		Routes:SetTaboo(ZONE, "Copper run", "Camp", false)
		Routes:DeleteTaboo(ZONE, "Camp")
	end)
	step("routes: the optimizer never crosses a taboo wall (vertical edges too)", function()
		local wall = { pack(0.1, 0.49), pack(0.9, 0.49), pack(0.9, 0.51), pack(0.1, 0.51) }
		local nodes = { pack(0.05, 0.5), pack(0.95, 0.5) }
		for col = 2, 8 do nodes[#nodes + 1] = pack(col / 10, 0.4); nodes[#nodes + 1] = pack(col / 10, 0.6) end
		local route = Optimizer:Solve(nodes, nil, { wall }, ZONE, {})
		local function o(ax, ay, bx, by, cx, cy) return (bx - ax) * (cy - ay) - (by - ay) * (cx - ax) end
		for i = 1, #route do
			local ax, ay = unpackC(route[i])
			local bx, by = unpackC(route[i % #route + 1])
			for k = 1, 4 do
				local cx, cy = unpackC(wall[k])
				local dx, dy = unpackC(wall[k % 4 + 1])
				assert(not (o(ax, ay, bx, by, cx, cy) * o(ax, ay, bx, by, dx, dy) < 0 and o(cx, cy, dx, dy, ax, ay) * o(cx, cy, dx, dy, bx, by) < 0), "edge crosses the wall")
			end
		end
	end)
	step("routes: edit points on the map, save and cancel", function()
		W.WorldMapFrame:Show()
		local route = Routes:Get(ZONE, "Copper run")
		local count, first = #route.points, route.points[1]
		assert(Editor:Start("route", ZONE, "Copper run"))
		assert(Routes:Busy(ZONE, "Copper run"), "editing doesn't block other changes")
		Routes.editing.points[1] = pack(0.01, 0.01)
		table.insert(Routes.editing.points, 2, pack(0.02, 0.02))
		Editor:Cancel()
		assert(Routes:Get(ZONE, "Copper run").points[1] == first and #Routes:Get(ZONE, "Copper run").points == count, "cancel changed the route")
		assert(Editor:Start("route", ZONE, "Copper run"))
		table.insert(Routes.editing.points, 2, pack(0.02, 0.02))
		Editor:Save()
		assert(#Routes:Get(ZONE, "Copper run").points == count + 1, "save lost the new point")
		W.WorldMapFrame:Hide()
	end)
	step("routes: the panel lists the zone's routes; rename and delete", function()
		local o = ACR:GetOptionsTable("ApexGatherer/Routes", "dialog", "Harness-1.0")
		assert(o.args["z" .. ZONE] and o.args["z" .. ZONE].args.r1.name == "Copper run", "zone group missing")
		assert(Routes:Rename(ZONE, "Copper run", "Copper loop"))
		assert(Routes:Get(ZONE, "Copper loop") and not Routes:Get(ZONE, "Copper run"), "rename")
		o = ACR:GetOptionsTable("ApexGatherer/Routes", "dialog", "Harness-1.0")
		assert(o.args["z" .. ZONE].args.r1.name == "Copper loop", "panel not rebuilt")
	end)

	-- the map flyout
	local function st() return ACD:GetStatusTable("ApexGatherer/Routes") end
	step("flyout: map button opens the map and docks right of it", function()
		assert(Flyout.button and Flyout.button:GetParent() == W.WorldMapFrame.NavBar, "button not on the breadcrumb bar")
		W.WorldMapFrame:Hide()
		Flyout.button.__scripts.OnClick(Flyout.button); tick()
		assert(W.WorldMapFrame:IsShown() and Flyout:IsOpen(), "not open")
		local t = st(); assert(t.left == 1302 and t.top == 900 and t.height == 700, ("bad dock %s %s %s"):format(t.left, t.top, t.height))
	end)
	step("flyout: remembers its width, docks left when there's no room, closes with the map", function()
		st().width = 610
		W.WorldMapFrame:Hide(); tick()
		ACD.frame.__scripts.OnUpdate(ACD.frame)
		assert(Apex.db.global.flyoutWidth == 610 and not Flyout:IsOpen(), "width not kept or still open")
		Flyout:Open(); tick()
		local m = W.WorldMapFrame; m.__l, m.__r = 1000, 1850
		Flyout:Dock(); assert(st().left == 1000 - 2 - 610, "left dock " .. tostring(st().left))
		m.__l, m.__r = 300, 1300
		Flyout:Toggle(); ACD.frame.__scripts.OnUpdate(ACD.frame)
		assert(not Flyout:IsOpen(), "toggle didn't close")
		W.WorldMapFrame:Hide()
	end)
	step("routes: delete", function()
		Routes:Delete(ZONE, "Copper loop")
		assert(not Routes:Get(ZONE, "Copper loop"), "not deleted")
	end)

	-- the HUD
	step("HUD: takes the minimap and puts everything back", function()
		local M = W.Minimap
		M.__w, M.__h, M.__parent = 140, 140, W.MinimapCluster
		M:ClearAllPoints(); M:SetPoint("TOPRIGHT", W.MinimapCluster, "TOPRIGHT", -10, -20)
		M.__alpha, M.__scale, M.__mouse = 1, 1, true
		local button = W.ApexGathererMinimapButton
		local other = W.CreateFrame("Button", "SomeAddonButton", M)
		other:SetPoint("CENTER", M, "CENTER", 60, 60)
		-- like the client: the compass ring's north marker lives on the backdrop, anchored to the minimap
		W.MinimapBackdrop.__parent = W.MinimapCluster
		local compassRing = W.MinimapBackdrop:CreateTexture("MinimapCompassTexture")
		compassRing:SetPoint("CENTER", M, "CENTER", 0, 0)
		W.C_Minimap.SetTracking(2, false)
		Apex.db.profile.hud.tracking["Find Herbs"] = "on"
		slash("/ag hud")
		assert(HUD:IsOpen() and M:GetParent() == W.ApexGathererHUD, "minimap not in the HUD")
		assert(button:GetParent() == W.ApexGathererHUDPlaceholder and other:GetParent() == W.ApexGathererHUDPlaceholder, "buttons followed the minimap")
		assert(select(2, other:GetPoint(1)) == W.ApexGathererHUDPlaceholder, "button not re-anchored")
		assert(select(2, compassRing:GetPoint(1)) == W.ApexGathererHUDPlaceholder, "the compass ring followed the minimap into the HUD")
		local hs = Apex.db.profile.hud
		assert(M:GetAlpha() == hs.alpha and M:IsMouseEnabled() == hs.mouse, "terrain or mouse not as set")
		assert(W.C_Minimap.GetTrackingInfo(2).active, "tracking not switched on")
		assert(W.GetCVar("rotateMinimap") == "1", "not rotating")
		-- the minimap keeps its scale: its 100 yards fill only part of the HUD's reach
		local reach = HUD:Reach()
		assert(reach == (hs.reach or 160), "reach " .. reach)
		assert(math.abs(M:GetWidth() - W.ApexGathererHUD:GetWidth() * 100 / reach) < 0.01, "minimap not fitted: " .. M:GetWidth())
		-- zoomed in: one of the minimap's own zoom steps (57 yards at step 3), filling the HUD
		local oldReach = hs.reach
		hs.reach = 60; Apex:SettingsChanged()
		assert(M:GetZoom() == 3 and math.abs(HUD:Reach() - 400 / 7) < 0.01, ("zoom %s, reach %s"):format(M:GetZoom(), HUD:Reach()))
		assert(math.abs(M:GetWidth() - W.ApexGathererHUD:GetWidth()) < 0.01, "zoomed in, the terrain doesn't fill the HUD")
		hs.reach = 500; Apex:SettingsChanged()
		assert(M:GetZoom() == 0 and math.abs(M:GetWidth() - W.ApexGathererHUD:GetWidth() / 5) < 0.01, "zoomed out: not the widest view in the middle")
		hs.reach = oldReach; Apex:SettingsChanged()
		HUD:ToggleMouse(); assert(M:IsMouseEnabled() == not hs.mouse, "mouse toggle")
		HUD:ToggleBackground(); assert(M:GetAlpha() == Apex.db.profile.hud.altAlpha, "background toggle")
		slash("/ag hud")
		assert(not HUD:IsOpen() and M:GetParent() == W.MinimapCluster, "minimap not given back")
		local point, rel, relPoint, x, y = M:GetPoint(1)
		assert(point == "TOPRIGHT" and rel == W.MinimapCluster and x == -10 and y == -20 and M:GetNumPoints() == 1, "minimap anchor not restored")
		assert(M:GetAlpha() == 1 and M:IsMouseEnabled() and M:GetWidth() == 140, "minimap look not restored")
		assert(button:GetParent() == M and other:GetParent() == M and select(2, other:GetPoint(1)) == M, "buttons not given back")
		assert(select(2, compassRing:GetPoint(1)) == M and compassRing:GetParent() == W.MinimapBackdrop, "compass ring not given back")
		assert(not W.C_Minimap.GetTrackingInfo(2).active, "tracking not restored")
		assert(W.GetCVar("rotateMinimap") == "0", "rotation not restored")
	end)
	step("HUD: the trail keeps the last so many dots, or so many seconds", function()
		local hs = Apex.db.profile.hud
		local overlay = W.ApexGathererHUDOverlay
		local function dots()
			local n = 0
			for _, o in ipairs(allObjs) do
				if o.__parent == overlay and o.__kind == "CreateTexture" and o.__shown and o.__w == 8 then n = n + 1 end
			end
			return n
		end
		local function walk(steps)
			for i = 1, steps do
				player[1] = player[1] + 0.004   -- 4 yards a step
				overlay.__scripts.OnUpdate(overlay, 1)
			end
		end
		-- dots kept, less the newest ones within a player arrow of us (the trail starts behind us)
		local function expect(kept)
			local perYard, n = W.Minimap:GetWidth() / 2 / 100, 0
			for k = 0, kept - 1 do if k * 4 * perYard >= HUD.TRAIL_GAP then n = n + 1 end end
			return n
		end
		hs.trail, hs.trailBy, hs.trailDots = true, "dots", 12
		at(0.40, 0.60)
		HUD:Open()
		walk(20)
		assert(expect(12) < 12 and dots() == expect(12), ("dots mode shows %d, not %d"):format(dots(), expect(12)))
		hs.trailBy, hs.trailSeconds = "time", 15
		clockOffset = clockOffset + 16            -- every dot so far is older than 15 s
		walk(8)
		assert(dots() == expect(8), ("time mode shows %d, not %d"):format(dots(), expect(8)))
		HUD:Close()
		hs.trailBy, hs.trailSeconds, hs.trailDots = "time", 15, 30
	end)
	step("HUD: pins and routes out to its edge, past the minimap", function()
		local data = Apex:GetZoneNodes("Mining", ZONE)
		local near, mid, out = pack(0.70, 0.75), pack(0.70, 0.83), pack(0.70, 0.95)   -- 50, 130, 250 yards south
		local copper = Catalog:Find("Mining", "Copper Vein")
		data[near], data[mid], data[out] = copper, copper, copper
		local hs = Apex.db.profile.hud
		local ownReach = hs.reach
		hs.reach = nil   -- the default: 160 yards here
		Apex:SettingsChanged(); tick()
		at(0.70, 0.70)
		HUD:Open(); tick()
		assert(minimapPins() == 0, "minimap pins while the HUD draws them")
		local overlay = W.ApexGathererHUDOverlay
		overlay.__scripts.OnUpdate(overlay, 1)
		local pins = {}
		for _, o in ipairs(allObjs) do if o.__parent == overlay and o.coord and o.ring then pins[o.coord] = o end end
		local function looks(pin)
			if not pin then return "missing" end
			return (pin:IsShown() and "shown " or "hidden ") .. (pin.ring:IsShown() and "ring" or "picture")
		end
		assert(looks(pins[near]) == "shown ring", "in tracking range: " .. looks(pins[near]))
		assert(looks(pins[mid]) == "shown picture", "past the minimap: " .. looks(pins[mid]))
		assert(not pins[out]:IsShown(), "past the HUD's reach: shown")
		local Drawing = Apex:GetModule("RouteDrawing")
		assert(Drawing:MinimapLayer():GetParent() == W.ApexGathererHUD, "route lines not on the HUD")
		HUD:Close(); tick()
		assert(Drawing:MinimapLayer():GetParent() == W.Minimap, "route lines not back on the minimap")
		assert(minimapPins() > 0 and not pins[mid]:IsShown(), "minimap pins not back")
		data[near], data[mid], data[out] = nil, nil, nil
		hs.reach = ownReach
		Apex:SettingsChanged(); tick()
	end)
	step("HUD: past the minimap, the minimap's own imagery (or the zone map) fills in, only when zoomed out", function()
		local hs = Apex.db.profile.hud
		local ownReach = hs.reach
		hs.reach = nil   -- 160 yards: past the stub minimap's 100
		local mapFrame = W.ApexGathererHUDMap
		local overlay = W.ApexGathererHUDOverlay
		local function pieces()
			local files, n = {}, 0
			for _, o in ipairs(allObjs) do
				if o.__parent == mapFrame and o.__kind == "CreateTexture" and o.__shown then n = n + 1; files[o.file] = true end
			end
			return n, files
		end
		at(0.5, 0.5)
		-- the minimap's squares, from the list: the player stands in Kalimdor square 40_30 (world x
		-- runs west, y north)
		local worldPosition = Apex.HBD.GetPlayerWorldPosition
		Apex.HBD.GetPlayerWorldPosition = function() return (32 - 40.5) * 1600 / 3, (32 - 30.5) * 1600 / 3, 1 end
		local own = Apex.MINIMAP_TILES[1][40 * 64 + 30]
		assert(own and Apex.MINIMAP_TILES[1][38 * 64 + 31] == 208247, "the minimap list is missing or wrong")
		HUD:Open(); tick()
		overlay.__scripts.OnUpdate(overlay, 1)
		local n, files = pieces()
		assert(mapFrame:GetParent():IsShown() and n > 0 and files[own], "the player's own minimap square isn't drawn")
		assert(n <= 9, "more squares than reach 160 yards: " .. n)
		-- a square with no minimap texture (past the list's edge, and no names known): the zone's
		-- world map instead, 1002 x 668 in 256-pixel tiles
		HUD:Close()
		Apex.HBD.GetPlayerWorldPosition = function() return (32 - 60.5) * 1600 / 3, (32 - 60.5) * 1600 / 3, 1 end
		W.C_Map.GetMapArtLayers = function() return { { layerWidth = 1002, layerHeight = 668, tileWidth = 256, tileHeight = 256 } } end
		W.C_Map.GetMapArtLayerTextures = function() local t = {} for i = 1, 12 do t[i] = 5000 + i end return t end
		HUD:Open(); tick()
		overlay.__scripts.OnUpdate(overlay, 1)
		n, files = pieces()
		assert(n > 0 and n <= 12 and not files[own], "world map pieces: " .. n)
		hs.reach = 60; Apex:SettingsChanged()   -- zoomed in: the terrain fills the HUD
		overlay.__scripts.OnUpdate(overlay, 1)
		assert(not mapFrame:GetParent():IsShown(), "map shown with the terrain filling the HUD")
		hs.reach = nil; hs.mapArt = false; Apex:SettingsChanged()
		overlay.__scripts.OnUpdate(overlay, 1)
		assert(not mapFrame:GetParent():IsShown(), "map shown while switched off")
		HUD:Close()
		hs.mapArt, hs.reach = true, ownReach
		W.C_Map.GetMapArtLayers, W.C_Map.GetMapArtLayerTextures = nil, nil
		Apex.HBD.GetPlayerWorldPosition = worldPosition
	end)
	step("settings: the options window drags by its title and opens where it was left", function()
		local panel = W.SettingsPanel
		local bar = Apex:GetModule("Settings").dragBar
		assert(bar, "no drag bar")
		panel:ClearAllPoints(); panel:SetPoint("TOPLEFT", W.UIParent, "TOPLEFT", 120, -40)
		bar.__scripts.OnDragStart(bar); bar.__scripts.OnDragStop(bar)
		local p = Apex.db.global.settingsPoint
		assert(p and p[1] == "TOPLEFT" and p[3] == 120 and p[4] == -40, "position not kept")
		panel:Hide(); panel:ClearAllPoints(); panel:SetPoint("CENTER")   -- the game centres it again
		panel:Show(); tick()
		local point, _, _, x, y = panel:GetPoint(1)
		assert(point == "TOPLEFT" and x == 120 and y == -40, "not put back where it was left")
		panel:Hide()
		Apex.db.global.settingsPoint = nil
	end)
	step("no churn: the tracking list is read every couple of seconds, not every frame", function()
		local overlay, lines = W.ApexGathererHUDOverlay, W.ApexGathererRouteLines
		at(0.5, 0.5)
		HUD:Open(); tick()
		local before = trackingReads
		for _ = 1, 200 do   -- ten seconds of frames, walking
			clockOffset = clockOffset + 0.05
			player[1] = player[1] + 0.0005
			pump()
			overlay.__scripts.OnUpdate(overlay, 0.05)
			lines.__scripts.OnUpdate(lines, 0.05)
		end
		HUD:Close()
		local passes = (trackingReads - before) / W.C_Minimap.GetNumTrackingTypes()
		assert(passes <= 7, ("read the tracking list %d times in ten seconds"):format(passes))
	end)
	step("HUD: only Forever tracking types are offered", function()
		local names = {}
		for _, t in ipairs(HUD:TrackingTypes()) do names[#names + 1] = t.name end
		table.sort(names)
		assert(table.concat(names, ",") == "Find Herbs,Find Minerals", "tracking: " .. table.concat(names, ","))
	end)
	step("HUD: hides in combat and comes back", function()
		Apex.db.profile.hud.hideInCombat = true
		HUD:Open()
		-- like the client: the combat event arrives before InCombatLockdown() turns true
		fire("PLAYER_REGEN_DISABLED")
		assert(not HUD:IsOpen(), "still open in combat")
		fire("PLAYER_REGEN_ENABLED")
		assert(HUD:IsOpen(), "didn't come back")
		HUD:Close()
		Apex.db.profile.hud.hideInCombat = false
	end)
	step("logout", function() fire("PLAYER_LOGOUT") end)
end

---------------------------------------------------------------- report
print("\n--- chat output ---")
for _, m in ipairs(chat) do print("  " .. tostring(m):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
local miss = {}
for k, n in pairs(missing) do miss[#miss + 1] = k end
table.sort(miss)
print("\n--- globals read but not stubbed (fine if the code guards them) ---\n  " .. table.concat(miss, ", "))
print(("\n--- %d error(s) ---"):format(#errors))
for i, e in ipairs(errors) do print(("[%d] %s\n"):format(i, e)) end
os.exit(#errors == 0 and 0 or 1)
