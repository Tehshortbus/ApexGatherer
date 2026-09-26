--[[
	The routes panel, docked beside the world map.

	Routes are built on the world map: create a route, shape it on the map, then optimize it.
	The Blizzard settings panel can't stay open alongside the map, so the routes panel is
	docked to the edge of the world map instead, opened from a "Routes" button on the map.

	Docking works through AceConfigDialog's own status table (top/left/width/height): the
	window re-applies it every time the panel refreshes (constantly while editing), so it
	stays put, and if you drag or resize it, the window writes your changes back to that same
	table. The window closes with the map and remembers its width.
]]
local Apex = ApexGatherer
local Flyout = Apex:NewModule("Flyout")
local ACD = LibStub("AceConfigDialog-3.0")
local AceGUI = LibStub("AceGUI-3.0")

local APP = "ApexGatherer/Routes"
local MIN_WIDTH = 380
local MIN_HEIGHT = 320
local GAP = 2

local seenWindow  -- the panel widget we last docked (AceGUI recycles widgets)

function Flyout:IsOpen()
	return ACD.OpenFrames[APP] ~= nil
end

-- keep whatever width the user dragged the window to
local function rememberWidth()
	local st = ACD:GetStatusTable(APP)
	if st.width and Flyout:IsOpen() then
		Apex.db.global.flyoutWidth = math.max(MIN_WIDTH, st.width)
	end
end

-- beside the map's right edge if it fits, else its left edge, else over the map's right side
local function dockGeometry()
	local map = WorldMapFrame
	local left, right, top, bottom = map:GetLeft(), map:GetRight(), map:GetTop(), map:GetBottom()
	if not (left and right and top and bottom) then return end
	local s = map:GetEffectiveScale() / UIParent:GetEffectiveScale()
	left, right, top, bottom = left * s, right * s, top * s, bottom * s
	local width = math.max(MIN_WIDTH, Apex.db.global.flyoutWidth)
	local x
	if right + GAP + width <= UIParent:GetWidth() then
		x = right + GAP
	elseif left - GAP - width >= 0 then
		x = left - GAP - width
	else
		x = right - width
	end
	return x, top, width, math.max(MIN_HEIGHT, top - bottom)
end

function Flyout:Dock()
	if not (WorldMapFrame and WorldMapFrame:IsShown()) then return end
	rememberWidth()
	local x, top, width, height = dockGeometry()
	if not x then return end
	local st = ACD:GetStatusTable(APP)
	st.left, st.top, st.width, st.height = x, top, width, height
	local window = ACD.OpenFrames[APP]
	if window then
		window:ApplyStatus()
		seenWindow = window
	end
end

-- show the routes of the zone the map is showing, or the New route page if it has none
local function selectMapZone()
	Apex:GetModule("RouteOptions"):Select(WorldMapFrame:GetMapID())
end

function Flyout:Open()
	if not WorldMapFrame:IsShown() then
		if ToggleWorldMap then ToggleWorldMap() else ShowUIPanel(WorldMapFrame) end
	end
	self:Dock()              -- position first so the window appears in place
	ACD:Open(APP)
	self:Dock()
	selectMapZone()
	-- the map may still be laying out on the frame it was opened: re-dock next frame
	C_Timer.After(0, function()
		if self:IsOpen() then self:Dock() end
	end)
end

function Flyout:Close()
	if self:IsOpen() then
		rememberWidth()
		ACD:Close(APP)
	end
end

function Flyout:Toggle()
	if self:IsOpen() and WorldMapFrame:IsShown() then
		self:Close()
	else
		self:Open()
	end
end

local function createMapButton()
	-- Right end of the map's breadcrumb bar ("Kalimdor > The Barrens"): always drawn above the
	-- map and mostly empty. (A button parented to the map itself ends up underneath the title
	-- bar's border art, which is why it's parented to the bar it sits on.)
	local navBar = WorldMapFrame.NavBar
	local border = WorldMapFrame.BorderFrame
	local parent = navBar or border or WorldMapFrame
	local button = CreateFrame("Button", "ApexGathererMapButton", parent, "UIPanelButtonTemplate")
	button:SetSize(72, 22)
	button:SetText("Routes")
	if navBar then
		button:SetPoint("RIGHT", navBar, "RIGHT", -6, 0)
	elseif border and border.MaximizeMinimizeFrame then
		button:SetPoint("RIGHT", border.MaximizeMinimizeFrame, "LEFT", -2, 0)
	else
		button:SetPoint("TOPRIGHT", WorldMapFrame, "TOPRIGHT", -60, -2)
	end
	button:SetFrameLevel(parent:GetFrameLevel() + 10)
	button:SetScript("OnClick", function() Flyout:Toggle() end)
	button:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:AddLine("Routes")
		GameTooltip:AddLine("Create, shape and optimize gathering routes for this map.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", function() GameTooltip:Hide() end)
	return button
end

function Flyout:OnEnable()
	if self.button or not WorldMapFrame then return end
	self.button = createMapButton()

	-- the flyout lives and dies with the map
	WorldMapFrame:HookScript("OnShow", function()
		if Flyout:IsOpen() then Flyout:Dock() end   -- e.g. opened with /ag routes before the map
	end)
	WorldMapFrame:HookScript("OnHide", function() Flyout:Close() end)
	WorldMapFrame:HookScript("OnSizeChanged", function()
		if Flyout:IsOpen() then Flyout:Dock() end   -- maximize / minimize
	end)
	-- follow the map when it is dragged (e.g. by DragMods)
	hooksecurefunc(WorldMapFrame, "StopMovingOrSizing", function()
		if Flyout:IsOpen() then Flyout:Dock() end
	end)

	-- a routes panel opened any other way while the map is up docks too; its own
	-- refreshes reuse the same widget and are left alone so your drags/resizes stick
	hooksecurefunc(ACD, "Open", function(_, appName, container)
		if appName ~= APP or container then return end
		local window = ACD.OpenFrames[APP]
		if window and window ~= seenWindow and WorldMapFrame:IsShown() then
			Flyout:Dock()
		end
	end)
	hooksecurefunc(AceGUI, "Release", function(_, widget)
		if widget == seenWindow then seenWindow = nil end
	end)
end
