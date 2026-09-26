--[[
	Shaping a route or a taboo area by hand on the world map.

	Editing works on a copy (Routes.editing): drag a point (a white knob) to move it, click the
	small plus between two points to add one there, right-click a point to delete it. Save
	writes the copy back; Cancel drops it. Only unclustered routes can be edited point by point.
]]
local Apex = ApexGatherer
local Routes = Apex:GetModule("Routes")
local Drawing = Apex:GetModule("RouteDrawing")
local Optimizer = Apex.Optimizer
local Editor = Apex:NewModule("RouteEditor", "AceEvent-3.0")

local PackXY, UnpackXY = Apex.PackXY, Apex.UnpackXY
local POINT_SIZE, MID_SIZE = 16, 13
local HOVER = { 1, 0.82, 0.2 }

local pointPool, midPool = {}, {}
local shown = {}
local handleLayer   -- over the whole map canvas, above the pins and lines, so the handles stay clickable

local function copy(points)
	local out = {}
	for i, coord in ipairs(points) do out[i] = coord end
	return out
end

local function cursorCoord()
	local x, y = WorldMapFrame:GetNormalizedCursorPosition()
	if not x then return end
	return PackXY(math.min(math.max(x, 0), 1), math.min(math.max(y, 0), 1))
end

local function place(handle, coord)
	local canvas = handleLayer
	local x, y = UnpackXY(coord)
	handle:ClearAllPoints()
	handle:SetPoint("CENTER", canvas, "TOPLEFT", x * canvas:GetWidth(), -y * canvas:GetHeight())
end

local function dragUpdate(handle)
	local coord = cursorCoord()
	local editing = Routes.editing
	if not coord or not editing then return end
	editing.points[handle.index] = coord
	place(handle, coord)
	Drawing:DrawWorldMap()
end

local function newHandle(pool, size, texture, hint)
	local handle = tremove(pool)
	if handle then return handle end
	handle = CreateFrame("Button", nil, handleLayer)
	handle:SetSize(size, size)
	handle.tex = handle:CreateTexture(nil, "OVERLAY")
	handle.tex:SetAllPoints()
	handle.tex:SetTexture(Apex.media .. texture)
	handle:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	handle:SetScript("OnEnter", function(h)
		h.tex:SetVertexColor(HOVER[1], HOVER[2], HOVER[3])
		GameTooltip:SetOwner(h, "ANCHOR_RIGHT")
		GameTooltip:AddLine(hint, 1, 1, 1)
		GameTooltip:Show()
	end)
	handle:SetScript("OnLeave", function(h)
		h.tex:SetVertexColor(1, 1, 1)
		GameTooltip:Hide()
	end)
	return handle
end

local function hideHandles()
	for _, handle in ipairs(shown) do
		handle:Hide()
		handle:SetScript("OnUpdate", nil)
		tinsert(handle.pool, handle)
	end
	wipe(shown)
end

function Editor:ShowHandles()
	hideHandles()
	local editing = Routes.editing
	if not editing or not WorldMapFrame:IsShown() or WorldMapFrame:GetMapID() ~= editing.zone then return end
	handleLayer:SetFrameLevel(WorldMapFrame:GetCanvas():GetFrameLevel() + Apex.MAP_HANDLES_LEVEL)
	local points = editing.points
	for i, coord in ipairs(points) do
		local handle = newHandle(pointPool, POINT_SIZE, "Knob", "Drag to move this point. Right-click to delete it.")
		handle.pool, handle.index = pointPool, i
		place(handle, coord)
		handle:SetScript("OnMouseDown", function(h, button)
			if button == "LeftButton" then h:SetScript("OnUpdate", dragUpdate) end
		end)
		handle:SetScript("OnMouseUp", function(h, button)
			h:SetScript("OnUpdate", nil)
			if button == "RightButton" and #editing.points > 3 then
				tremove(editing.points, h.index)
			end
			Editor:ShowHandles()
			Drawing:DrawWorldMap()
		end)
		handle:SetFrameLevel(handleLayer:GetFrameLevel() + 2)
		handle:Show()
		tinsert(shown, handle)
	end
	-- the handles between points add a point there
	for i = 1, #points do
		local a, b = points[i], points[i % #points + 1]
		local ax, ay = UnpackXY(a)
		local bx, by = UnpackXY(b)
		local handle = newHandle(midPool, MID_SIZE, "Add", "Click to add a point here.")
		handle.pool, handle.index = midPool, i
		place(handle, PackXY((ax + bx) / 2, (ay + by) / 2))
		handle:SetScript("OnMouseDown", nil)
		handle:SetScript("OnMouseUp", function(h, button)
			if button ~= "LeftButton" then return end
			tinsert(editing.points, h.index + 1, PackXY((ax + bx) / 2, (ay + by) / 2))
			Editor:ShowHandles()
			Drawing:DrawWorldMap()
		end)
		handle:SetFrameLevel(handleLayer:GetFrameLevel() + 1)
		handle:Show()
		tinsert(shown, handle)
	end
end

function Editor:IsEditing(kind, zone, name)
	local editing = Routes.editing
	return editing ~= nil and (not kind or (editing.kind == kind and editing.zone == zone and editing.name == name))
end

-- kind "route" or "taboo"
function Editor:Start(kind, zone, name)
	if Routes.editing then return false, "Save or cancel the edit in progress first." end
	local source = kind == "route" and Routes:Get(zone, name) or Routes:GetTaboo(zone, name)
	if not source then return false end
	if kind == "route" and source.clusters then return false, "Uncluster the route to edit its points." end
	if kind == "route" and Routes:Busy(zone, name) then return false, "Wait for the optimizer to finish." end
	Routes.editing = { kind = kind, zone = zone, name = name, points = copy(source.points) }
	if WorldMapFrame:GetMapID() ~= zone then WorldMapFrame:SetMapID(zone) end
	self:ShowHandles()
	Routes:Changed(zone)
	return true
end

function Editor:Save()
	local editing = Routes.editing
	if not editing then return end
	Routes.editing = nil
	hideHandles()
	local zone = editing.zone
	if editing.kind == "route" then
		local route = Routes:Get(zone, editing.name)
		if route then
			route.points = editing.points
			route.length = Optimizer:PathLength(route.points, zone)
		end
	else
		local taboo = Routes:GetTaboo(zone, editing.name)
		if taboo then
			taboo.points = editing.points
			for _, name in ipairs(Routes:Names(zone)) do
				local route = Routes:Get(zone, name)
				if route.taboos[editing.name] then Routes:ApplyTaboos(zone, route) end
			end
		end
	end
	Routes:Changed(zone)
end

function Editor:Cancel()
	local editing = Routes.editing
	if not editing then return end
	Routes.editing = nil
	hideHandles()
	Routes:Changed(editing.zone)
end

function Editor:OnEnable()
	if not WorldMapFrame then return end
	local canvas = WorldMapFrame:GetCanvas()
	handleLayer = CreateFrame("Frame", "ApexGathererRouteHandles", canvas)
	handleLayer:SetAllPoints(canvas)
	hooksecurefunc(WorldMapFrame, "OnMapChanged", function() Editor:ShowHandles() end)
	WorldMapFrame:HookScript("OnShow", function() Editor:ShowHandles() end)
	WorldMapFrame:HookScript("OnHide", hideHandles)
	WorldMapFrame:GetCanvas():HookScript("OnSizeChanged", function() Editor:ShowHandles() end)
end
