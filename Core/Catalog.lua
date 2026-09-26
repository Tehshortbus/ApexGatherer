--[[
	The WoW Forever node catalog: every gatherable node by kind, with a stable id and an icon.

	Ids: 100s mining, 200s herbs, 300s fishing pools, 400s treasure. Nodes the collector learns
	on its own get ids from 9001 up (see Core/Nodes.lua); they join the catalog at load.
	Icons (in lists) come from the game itself: the icon of the item the node gives, or a
	profession icon. Pins draw a marker instead: a picture of the kind of node (a rock, a herb,
	a pool, a chest) with one part tinted for the node, picked by a word in its name, so a
	learned "Glimmering Copper Vein" gets copper's colour too.
]]
local Apex = ApexGatherer
local Catalog = {}
Apex.Catalog = Catalog

local KIND_ICON = {
	Mining    = "Interface\\Icons\\Trade_Mining",
	Herbalism = "Interface\\Icons\\Trade_Herbalism",
	Fishing   = "Interface\\Icons\\Trade_Fishing",
	Treasure  = "Interface\\Icons\\INV_Box_01",
}
Catalog.KIND_ICON = KIND_ICON

-- { id, name, item whose icon the pin shows (optional) }
local NODES = {
	Mining = {
		{ 101, "Copper Vein", 2770 },
		{ 102, "Poor Copper Vein", 2770 },
		{ 103, "Tin Vein", 2771 },
		{ 104, "Silver Vein", 2775 },
		{ 105, "Iron Deposit", 2772 },
		{ 106, "Gold Vein", 2776 },
		{ 107, "Mithril Deposit", 3858 },
		{ 108, "Truesilver Deposit", 7911 },
		{ 109, "Small Thorium Vein", 10620 },
		{ 110, "Rich Thorium Vein", 10620 },
		{ 111, "Hakkari Thorium Vein", 10620 },
		{ 112, "Dark Iron Deposit", 11370 },
		{ 113, "Ooze Covered Silver Vein", 2775 },
		{ 114, "Ooze Covered Gold Vein", 2776 },
		{ 115, "Ooze Covered Mithril Deposit", 3858 },
		{ 116, "Ooze Covered Truesilver Deposit", 7911 },
		{ 117, "Ooze Covered Thorium Vein", 10620 },
		{ 118, "Ooze Covered Rich Thorium Vein", 10620 },
		{ 119, "Lesser Bloodstone Deposit", 4278 },
		{ 120, "Incendicite Mineral Vein", 3340 },
		{ 121, "Indurium Mineral Vein", 5833 },
		{ 122, "Small Obsidian Chunk", 22202 },
		{ 123, "Large Obsidian Chunk", 22203 },
		{ 124, "Cold Iron Deposit", 2772 },
		{ 125, "Fool's Gold Vein", 2776 },
		{ 126, "Greater Moonstone Formation", 7911 },
		{ 127, "Starsilver Vein", 2775 },
	},
	Herbalism = {
		{ 201, "Peacebloom", 2447 },
		{ 202, "Silverleaf", 765 },
		{ 203, "Earthroot", 2449 },
		{ 204, "Mageroyal", 785 },
		{ 205, "Briarthorn", 2450 },
		{ 206, "Stranglekelp", 3820 },
		{ 207, "Bruiseweed", 2453 },
		{ 208, "Wild Steelbloom", 3355 },
		{ 209, "Grave Moss", 3369 },
		{ 210, "Kingsblood", 3356 },
		{ 211, "Liferoot", 3357 },
		{ 212, "Fadeleaf", 3818 },
		{ 213, "Goldthorn", 3821 },
		{ 214, "Khadgar's Whisker", 3358 },
		{ 215, "Wintersbite", 3819 },
		{ 216, "Firebloom", 4625 },
		{ 217, "Purple Lotus", 8831 },
		{ 218, "Arthas' Tears", 8836 },
		{ 219, "Sungrass", 8838 },
		{ 220, "Blindweed", 8839 },
		{ 221, "Ghost Mushroom", 8845 },
		{ 222, "Gromsblood", 8846 },
		{ 223, "Golden Sansam", 13464 },
		{ 224, "Dreamfoil", 13463 },
		{ 225, "Mountain Silversage", 13465 },
		{ 226, "Plaguebloom", 13466 },
		{ 227, "Icecap", 13467 },
		{ 228, "Black Lotus", 13468 },
		{ 229, "Dreamroot", 13463 },
		{ 230, "Gloom Weed", 3369 },
		{ 231, "Moonroot", 2449 },
		{ 232, "Nightmare Moss", 3369 },
		{ 233, "Serpentbloom", 3355 },
		{ 234, "Star Lotus", 8831 },
		{ 235, "Violet Tragan", 8831 },
		{ 236, "Doom Weed", 8846 },
		{ 237, "Incendia Agave", 4625 },
	},
	Fishing = {
		{ 301, "Floating Wreckage" },
		{ 302, "Floating Debris" },
		{ 303, "Patch of Elemental Water", 7070 },
		{ 304, "Oil Spill" },
		{ 305, "Rubble" },
		{ 306, "Firefin Snapper School", 6359 },
		{ 307, "Oily Blackmouth School", 6358 },
		{ 308, "Sagefish School", 21071 },
		{ 309, "Greater Sagefish School", 21153 },
		{ 310, "School of Deviate Fish", 6522 },
		{ 311, "Stonescale Eel Swarm", 13422 },
	},
	Treasure = {
		{ 401, "Giant Clam", 7973 },
		{ 402, "Battered Chest" },
		{ 403, "Tattered Chest" },
		{ 404, "Solid Chest" },
		{ 405, "Large Battered Chest" },
		{ 406, "Large Iron Bound Chest" },
		{ 407, "Large Solid Chest" },
		{ 408, "Large Mithril Bound Chest" },
		{ 409, "Large Darkwood Chest" },
		{ 410, "Buccaneer's Strongbox" },
		{ 411, "Bloodpetal Sprout" },
		{ 412, "Practice Lockbox" },
		{ 413, "Battered Footlocker" },
		{ 414, "Waterlogged Footlocker" },
		{ 415, "Dented Footlocker" },
		{ 416, "Mossy Footlocker" },
		{ 417, "Scarlet Footlocker" },
		{ 418, "Brightly Colored Egg" },
		{ 419, "Takk's Nest" },
		{ 420, "Dart's Nest" },
		{ 421, "Razormaw Matriarch's Nest" },
		{ 422, "Ravasaur Matriarch's Nest" },
		{ 423, "Abandoned Cache" },
		{ 424, "Alliance Strongbox" },
		{ 425, "Ambermill Strongbox" },
		{ 426, "Artifact Storage" },
		{ 427, "Benedict's Chest" },
		{ 428, "Clliffspring Chest" },
		{ 429, "Cozzle's Footlocker" },
		{ 430, "Duskwood Chest" },
		{ 431, "Equipment Stash" },
		{ 432, "Gallywix's Lockbox" },
		{ 433, "Gnarlpine Stash" },
		{ 434, "Kurzen Supply Crate" },
		{ 435, "Large Scarab Coffer" },
		{ 436, "Lucius's Lockbox" },
		{ 437, "Offering Box" },
		{ 438, "Ornamented Chest" },
		{ 439, "Padlocked Reliquary" },
		{ 440, "Personal Letterbox" },
		{ 441, "Relic Coffer" },
		{ 442, "Rusty Safe" },
		{ 443, "Scarab Coffer" },
		{ 444, "Shipwreck Cache" },
		{ 445, "Sizable Stolen Strongbox" },
		{ 446, "Spellbound War Chest" },
		{ 447, "Stable Hand's Trunk" },
		{ 448, "Supply Locker" },
		{ 449, "Venture Co. Strongbox" },
		{ 450, "Waterlogged Captain's Chest" },
	},
}

-- a richer ore can appear on a poorer one's spot: these share spawn points
local SHARED_SPAWNS = {
	{ "Silver Vein", "Tin Vein", "Iron Deposit" },
	{ "Gold Vein", "Iron Deposit", "Mithril Deposit" },
	{ "Truesilver Deposit", "Mithril Deposit", "Small Thorium Vein", "Rich Thorium Vein" },
	{ "Dark Iron Deposit", "Mithril Deposit", "Small Thorium Vein", "Rich Thorium Vein" },
	{ "Ooze Covered Silver Vein", "Ooze Covered Mithril Deposit", "Ooze Covered Thorium Vein", "Ooze Covered Rich Thorium Vein" },
	{ "Ooze Covered Gold Vein", "Ooze Covered Mithril Deposit", "Ooze Covered Thorium Vein", "Ooze Covered Rich Thorium Vein" },
	{ "Ooze Covered Truesilver Deposit", "Ooze Covered Mithril Deposit", "Ooze Covered Thorium Vein", "Ooze Covered Rich Thorium Vein" },
}

local byID, byName, kindNodes, shared = {}, {}, {}, {}

local function register(kind, id, name, item, icon, learned)
	local node = { id = id, name = name, kind = kind, item = item, icon = icon, learned = learned }
	byID[id] = node
	byName[kind][name] = id
	tinsert(kindNodes[kind], node)
	return node
end

for _, kind in ipairs(Apex.KINDS) do
	byName[kind], kindNodes[kind] = {}, {}
	for _, entry in ipairs(NODES[kind]) do
		register(kind, entry[1], entry[2], entry[3])
	end
end
for _, group in ipairs(SHARED_SPAWNS) do
	local rich = byName.Mining[group[1]]
	for i = 2, #group do
		local poor = byName.Mining[group[i]]
		shared[rich] = shared[rich] or {}
		shared[poor] = shared[poor] or {}
		shared[rich][poor], shared[poor][rich] = true, true
	end
end

function Catalog:Get(id)
	return byID[id]
end

function Catalog:Find(kind, name)
	return byName[kind] and byName[kind][name]
end

function Catalog:Name(id)
	local node = byID[id]
	return node and node.name
end

function Catalog:Kind(id)
	local node = byID[id]
	return node and node.kind
end

-- the nodes of one kind, sorted by name
function Catalog:Nodes(kind)
	local list = {}
	for i, node in ipairs(kindNodes[kind] or {}) do list[i] = node end
	sort(list, function(a, b) return a.name < b.name end)
	return list
end

-- two nodes of these ids close together are one spawn point
function Catalog:SameSpawn(a, b)
	return a == b or (shared[a] and shared[a][b]) or false
end

function Catalog:Icon(id)
	local node = byID[id]
	if not node then return KIND_ICON.Treasure end
	if not node.icon then
		local icon = node.item and C_Item.GetItemIconByID(node.item)
		if not icon and node.learned then icon = self:BorrowIcon(node.kind, node.name) end
		node.icon = icon or KIND_ICON[node.kind]
	end
	return node.icon
end

-- the marker's picture and tinted part per kind, and the tint when no word in the name matches
local MARKER = {
	Mining    = { "MarkerRock", "MarkerOre", { 0.85, 0.75, 0.55 } },
	Herbalism = { "MarkerLeaves", "MarkerBloom", { 1, 0.95, 0.75 } },
	Fishing   = { "MarkerWater", "MarkerFish", { 0.85, 0.9, 0.95 } },
	Treasure  = { "MarkerChest", "MarkerFittings", { 1, 0.8, 0.3 } },
}

-- the tinted part's colour by a word in the node's name; the first match wins, so longer names
-- come before the shorter ones inside them ("Truesilver" before "Silver")
local TINTS = {
	Mining = {
		{ "Truesilver", 0.9, 0.85, 1 }, { "Starsilver", 0.8, 0.9, 1 }, { "Silver", 0.86, 0.88, 0.92 },
		{ "Dark Iron", 0.85, 0.22, 0.18 }, { "Cold Iron", 0.6, 0.72, 0.85 }, { "Iron", 0.66, 0.55, 0.5 },
		{ "Copper", 0.95, 0.5, 0.22 }, { "Tin", 0.8, 0.76, 0.6 }, { "Gold", 1, 0.82, 0.18 },
		{ "Mithril", 0.4, 0.88, 0.82 }, { "Thorium", 0.5, 0.88, 0.4 }, { "Bloodstone", 0.85, 0.1, 0.15 },
		{ "Incendicite", 1, 0.4, 0.1 }, { "Indurium", 0.55, 0.62, 0.8 }, { "Obsidian", 0.45, 0.3, 0.6 },
		{ "Moonstone", 0.75, 0.82, 1 },
	},
	Herbalism = {
		{ "Peacebloom", 1, 0.96, 0.75 }, { "Silverleaf", 0.82, 0.9, 0.86 }, { "Earthroot", 0.72, 0.5, 0.3 },
		{ "Mageroyal", 1, 0.75, 0.3 }, { "Briarthorn", 0.8, 0.35, 0.45 }, { "Stranglekelp", 0.4, 0.75, 0.55 },
		{ "Bruiseweed", 0.6, 0.45, 0.85 }, { "Steelbloom", 0.7, 0.78, 0.9 }, { "Grave Moss", 0.55, 0.75, 0.4 },
		{ "Kingsblood", 0.9, 0.2, 0.2 }, { "Liferoot", 1, 0.55, 0.25 }, { "Fadeleaf", 0.7, 0.9, 0.85 },
		{ "Goldthorn", 1, 0.82, 0.25 }, { "Khadgar", 0.45, 0.65, 1 }, { "Wintersbite", 0.85, 0.95, 1 },
		{ "Firebloom", 1, 0.35, 0.15 }, { "Purple Lotus", 0.7, 0.35, 0.95 }, { "Arthas", 0.7, 0.15, 0.35 },
		{ "Sungrass", 1, 0.9, 0.3 }, { "Blindweed", 0.6, 0.5, 0.75 }, { "Ghost Mushroom", 0.8, 0.9, 1 },
		{ "Gromsblood", 0.75, 0.25, 0.2 }, { "Sansam", 1, 0.75, 0.2 }, { "Dreamfoil", 0.5, 0.85, 0.75 },
		{ "Silversage", 0.8, 0.88, 0.8 }, { "Plaguebloom", 0.65, 0.85, 0.3 }, { "Icecap", 0.8, 0.92, 1 },
		{ "Black Lotus", 0.35, 0.25, 0.45 }, { "Dreamroot", 0.55, 0.8, 0.9 }, { "Gloom Weed", 0.45, 0.4, 0.6 },
		{ "Moonroot", 0.8, 0.82, 1 }, { "Nightmare Moss", 0.5, 0.35, 0.6 }, { "Serpentbloom", 0.4, 0.85, 0.5 },
		{ "Star Lotus", 1, 0.95, 0.6 }, { "Violet Tragan", 0.65, 0.4, 1 }, { "Doom Weed", 0.55, 0.3, 0.3 },
		{ "Agave", 1, 0.5, 0.2 },
	},
	Fishing = {
		{ "Wreckage", 0.7, 0.5, 0.3 }, { "Debris", 0.7, 0.5, 0.3 }, { "Elemental Water", 0.55, 0.9, 1 },
		{ "Blackmouth", 0.45, 0.45, 0.5 }, { "Oil", 0.35, 0.33, 0.3 }, { "Rubble", 0.65, 0.62, 0.58 },
		{ "Firefin", 1, 0.42, 0.28 }, { "Sagefish", 0.62, 0.82, 0.55 }, { "Deviate", 0.65, 0.45, 0.95 },
		{ "Eel", 0.55, 0.68, 0.72 },
	},
	Treasure = {
		{ "Mithril", 0.4, 0.88, 0.82 }, { "Iron", 0.72, 0.74, 0.78 }, { "Scarlet", 0.9, 0.2, 0.2 },
		{ "Mossy", 0.5, 0.78, 0.35 }, { "Darkwood", 0.6, 0.45, 0.65 }, { "Waterlogged", 0.55, 0.75, 0.85 },
		{ "Rusty", 0.78, 0.42, 0.25 },
	},
}

local function tintFor(kind, name)
	for _, tint in ipairs(TINTS[kind]) do
		if name:find(tint[1], 1, true) then return { tint[2], tint[3], tint[4] } end
	end
	return MARKER[kind][3]
end

-- a pin's picture, its tinted part and the tint: media paths and { r, g, b }
function Catalog:Marker(id)
	local node = byID[id]
	local kind = node and node.kind or "Treasure"
	local marker = MARKER[kind]
	local tint = marker[3]
	if node then
		node.tint = node.tint or tintFor(kind, node.name)
		tint = node.tint
	end
	return Apex.media .. marker[1], Apex.media .. marker[2], tint
end

-- a learned node shows the icon of the longest catalog name inside its own
-- ("Glimmering Copper Vein" -> Copper Vein)
function Catalog:BorrowIcon(kind, name)
	local best
	for _, node in ipairs(kindNodes[kind]) do
		if not node.learned and #node.name < #name and name:find(node.name, 1, true) and (not best or #node.name > #best.name) then
			best = node
		end
	end
	return best and self:Icon(best.id)
end

function Catalog:AddLearned(kind, name, id)
	if byName[kind][name] then return byName[kind][name] end
	register(kind, id, name, nil, nil, true)
	return id
end

function Catalog:RemoveLearned(kind, name)
	local id = byName[kind][name]
	local node = id and byID[id]
	if not node or not node.learned then return end
	byID[id], byName[kind][name] = nil, nil
	for i, entry in ipairs(kindNodes[kind]) do
		if entry == node then tremove(kindNodes[kind], i) break end
	end
end
