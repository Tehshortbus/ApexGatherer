--[[
	The minimap button, the addon-compartment entry, the slash commands and key-binding names.

	Minimap button (drag it around the minimap edge):
	  Left-click          toggle the HUD
	  Shift + left-click  toggle the HUD's minimap background
	  Middle-click        routes on the world map
	  Right-click         settings
]]
local Apex = ApexGatherer
local Launcher = Apex:NewModule("Launcher")

local ICON = Apex.media .. "Icon"

BINDING_HEADER_APEXGATHERER = "ApexGatherer"
BINDING_NAME_APEXGATHERER_HUD = "Toggle the HUD"
BINDING_NAME_APEXGATHERER_HUD_MOUSE = "Toggle HUD mouse (hover pins, but no clicking through)"
BINDING_NAME_APEXGATHERER_HUD_BACKGROUND = "Toggle the HUD's minimap background"
BINDING_NAME_APEXGATHERER_ROUTES = "Toggle routes on the world map"
BINDING_NAME_APEXGATHERER_MINIMAP_PINS = "Toggle node pins on the minimap"
BINDING_NAME_APEXGATHERER_WORLDMAP_PINS = "Toggle node pins on the world map"

function Apex:OpenSettings()
	self:GetModule("Settings"):Open()
end

function Apex:ToggleHUD()
	self:GetModule("HUD"):Toggle()
end

function Apex:ToggleRoutes()
	self:GetModule("Flyout"):Toggle()
end

function Apex:TogglePins(where)
	local pins = self.db.profile.pins
	pins[where] = not pins[where]
	self:SettingsChanged()
end

local function onClick(_, button)
	if button == "RightButton" then
		Apex:OpenSettings()
	elseif button == "MiddleButton" then
		Apex:ToggleRoutes()
	elseif IsShiftKeyDown() then
		Apex:GetModule("HUD"):ToggleBackground()
	else
		Apex:ToggleHUD()
	end
end

local function onEnter(button)
	GameTooltip:SetOwner(button, "ANCHOR_LEFT")
	GameTooltip:AddLine("ApexGatherer")
	GameTooltip:AddLine(Apex.GOLD .. "Left-click|r  toggle the HUD", 1, 1, 1)
	GameTooltip:AddLine(Apex.GOLD .. "Shift + left-click|r  toggle the HUD background", 1, 1, 1)
	GameTooltip:AddLine(Apex.GOLD .. "Middle-click|r  routes on the world map", 1, 1, 1)
	GameTooltip:AddLine(Apex.GOLD .. "Right-click|r  settings", 1, 1, 1)
	GameTooltip:AddLine("Drag to move this button.", 0.6, 0.6, 0.6)
	GameTooltip:Show()
end

-- keeps the button on the minimap's edge at the saved angle
local function place(button)
	local angle = math.rad(Apex.db.profile.minimapButton.angle)
	local radius = Minimap:GetWidth() / 2 + 10
	button:ClearAllPoints()
	button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function dragUpdate(button)
	local mx, my = Minimap:GetCenter()
	local scale = Minimap:GetEffectiveScale()
	local cx, cy = GetCursorPosition()
	cx, cy = cx / scale, cy / scale
	Apex.db.profile.minimapButton.angle = math.deg(math.atan2(cy - my, cx - mx)) % 360
	place(button)
end

function Launcher:CreateButton()
	local button = CreateFrame("Button", "ApexGathererMinimapButton", Minimap)
	button:SetSize(31, 31)
	button:SetFrameStrata("MEDIUM")
	button:SetFrameLevel(8)
	button:RegisterForClicks("AnyUp")
	button:RegisterForDrag("LeftButton")
	button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

	local icon = button:CreateTexture(nil, "BACKGROUND")
	icon:SetTexture(ICON)
	icon:SetSize(21, 21)
	icon:SetPoint("CENTER", 0, 1)
	local border = button:CreateTexture(nil, "OVERLAY")
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	border:SetSize(53, 53)
	border:SetPoint("TOPLEFT")

	button:SetScript("OnClick", onClick)
	button:SetScript("OnEnter", onEnter)
	button:SetScript("OnLeave", function() GameTooltip:Hide() end)
	button:SetScript("OnDragStart", function(b)
		b:SetScript("OnUpdate", dragUpdate)
		GameTooltip:Hide()
	end)
	button:SetScript("OnDragStop", function(b) b:SetScript("OnUpdate", nil) end)
	self.button = button
	self:UpdateButton()
end

function Launcher:UpdateButton()
	if not self.button then return end
	place(self.button)
	self.button:SetShown(not Apex.db.profile.minimapButton.hide)
end

function Launcher:OnEnable()
	self:CreateButton()
	if AddonCompartmentFrame and AddonCompartmentFrame.RegisterAddon then
		AddonCompartmentFrame:RegisterAddon({
			text = "ApexGatherer",
			icon = ICON,
			notCheckable = true,
			func = function() Apex:OpenSettings() end,
		})
	end
end

SLASH_APEXGATHERER1 = "/ag"
SLASH_APEXGATHERER2 = "/apex"
SLASH_APEXGATHERER3 = "/apexgatherer"
SLASH_APEXGATHERER4 = "/agatherer"
SlashCmdList.APEXGATHERER = function(msg)
	local command = strlower(strtrim(msg or ""))
	if command == "hud" then
		Apex:ToggleHUD()
	elseif command == "routes" then
		Apex:ToggleRoutes()
	else
		Apex:OpenSettings()
	end
end
