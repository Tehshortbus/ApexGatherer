--[[
	The FAQ page. Each section is { title, { { question, answer }, ... } }; add questions here.
]]
local Apex = ApexGatherer
local Y = Apex.GOLD   -- highlight for page and button names

local FAQ = {
	{ "Getting started", {
		{ "What does ApexGatherer do?",
		  "It records every Mining, Herbalism, Fishing and Treasure node you gather on WoW Forever and pins them on "
		  .. "your world map and minimap. It turns them into short farming routes, puts it all on a HUD in the "
		  .. "middle of your screen while you farm, and swaps nodes with your guild or friends." },
		{ "How do I open things?",
		  "Settings: " .. Y .. "/ag|r, " .. Y .. "/apex|r, " .. Y .. "/apexgatherer|r or " .. Y .. "/agatherer|r, a "
		  .. "right-click on the minimap button, or Options > AddOns > ApexGatherer.\nHUD: " .. Y .. "/ag hud|r or a "
		  .. "left-click on the minimap button.\nRoutes: " .. Y .. "/ag routes|r, a middle-click on the minimap "
		  .. "button, or the " .. Y .. "Routes|r button at the top of the world map.\nEverything can also be bound "
		  .. "to keys under Key Bindings > AddOns > ApexGatherer." },
	}},
	{ "Nodes", {
		{ "How do I record nodes?",
		  "Just gather. Mining a vein, picking a herb, fishing from a pool, or opening a chest records the spot "
		  .. "automatically, and a pin appears on your maps." },
		{ "I gathered something but don't see a pin.",
		  "Check the main page (pins on for that map, the kind ticked) and " .. Y .. "Filters|r (the node ticked). "
		  .. "Pins show for the zone you're in (minimap) or looking at (world map)." },
		{ "What does \"learned a new node\" mean?",
		  "WoW Forever keeps adding nodes, like Poor Copper Vein. When you mine or pick one ApexGatherer doesn't "
		  .. "know, it learns the name, takes the colour of the node it resembles and records it from then on. "
		  .. "Review or forget learned nodes on the " .. Y .. "Learned Nodes|r page." },
		{ "Why aren't unknown fishing pools and chests learned too?",
		  "Fishing reads what's under your cursor (often the bobber), and \"Opening\" is also used on quest "
		  .. "objects, so learning those would record junk. They're listed on " .. Y .. "Learned Nodes|r instead." },
		{ "Some \"herbs\" aren't really gathering herbs.",
		  "Gloom Weed, Serpentbloom, Violet Tragan, Doom Weed and Incendia Agave are quest pick-ups that Forever "
		  .. "treats as herbs. Untick them under " .. Y .. "Filters|r if you don't want their pins." },
		{ "What do the pins show?",
		  "A picture of the node: a rock with its ore's colour, a herb with its blossom's colour, a pool with its "
		  .. "fish, a chest. Close enough for tracking to find (and while you track that kind), the minimap shows "
		  .. "the node itself as a yellow dot, so the pin turns into a ring round that dot; an empty ring means the "
		  .. "node isn't up right now. Set the ring size on the main page.\nA ring can sit a little off the dot at "
		  .. "first: the game doesn't say where a node is, so it's recorded a step ahead of where you stood, facing "
		  .. "it. Each later gather moves it halfway to the new spot, so after a few visits it settles on the node." },
		{ "How do I remove wrong or duplicate pins?",
		  "Right-click a pin to delete it, or every node of that type in the zone. " .. Y .. "Maintenance|r can "
		  .. "clean up duplicates, delete one node type from a zone, stop recording a kind, or clear a kind." },
		{ "How do I back up my nodes?",
		  Y .. "Export|r: tick the kinds, click Export, then click the box and press Ctrl-A, Ctrl-C. To load it: "
		  .. Y .. "Import|r, paste, click Import. Imports add to the nodes you already have." },
	}},
	{ "Sharing", {
		{ "How do I share nodes with my guild or a friend?",
		  "Open " .. Y .. "Sharing|r, choose your guild or type a player's name, tick the kinds, then click " .. Y
		  .. "Send my nodes|r or " .. Y .. "Ask for their nodes|r. Both sides need ApexGatherer 2.1 or later." },
		{ "Can nodes go missing on the way?",
		  "Addon messages sometimes do, so a send comes in numbered parts: when it ends, your addon asks again "
		  .. "for any part that didn't arrive (twice at most). If some still don't, the chat line says how many "
		  .. "were lost; ask again later for the rest." },
		{ "Can someone fill my map with junk?",
		  "A player is always asked before their nodes arrive (one question at a time per player); for your "
		  .. "guild that's a setting. Answers to your own request come straight in. Nodes you already have are "
		  .. "skipped, and a sender can't share more than 30 live nodes a minute." },
		{ "Why can't I ask or send again right away?",
		  "To keep addon traffic light on the realm, you can ask the same guild or player, or send your nodes to "
		  .. "the guild, once every 5 minutes, and your addon answers the same guildmate at most once every half "
		  .. "hour. Sending to one player has no wait." },
		{ "Someone answered with nothing new. Why?",
		  "An answer leaves out the nodes you and that player already swapped this session (ones they sent you, "
		  .. "or you sent them), so your own nodes don't come straight back. If that's all they have, they tell you "
		  .. "they have nothing you don't already have." },
		{ "What is \"share each node with my guild as I gather it\"?",
		  "With it on, every node you gather is sent to your guild the moment you gather it, so everyone's maps "
		  .. "fill in together. Only nodes you gather yourself are passed on, never ones shared with you." },
	}},
	{ "Routes", {
		{ "How do I make a route?",
		  "Open the world map to the zone and click " .. Y .. "Routes|r. On " .. Y .. "New route|r: type a name, "
		  .. "tick the nodes (for copper, tick Copper Vein and Poor Copper Vein), and click " .. Y .. "Create route|r. "
		  .. "It goes through every spot recorded so far and is optimized right away." },
		{ "How do I make a route shorter?",
		  "On the route's " .. Y .. "Optimize|r tab, click " .. Y .. "Optimize now|r (pauses the game for a moment) "
		  .. "or " .. Y .. "Optimize in the background|r (no pause). Optimizing only ever keeps a shorter loop, so "
		  .. "running it again is safe." },
		{ "What does clustering do?",
		  Y .. "Cluster|r merges nodes near each other into one route point (" .. Y .. "Uncluster|r undoes it). A "
		  .. "clustered route is also straightened when optimized, never passing farther than the cluster radius "
		  .. "from any node, which usually makes it 15-20% shorter. The default radius is half of how far tracking "
		  .. "reaches, so every node shows on your minimap well before you pass it. A bigger radius makes a shorter "
		  .. "loop but longer walks out to nodes that are up; with fast respawns, smaller is often better." },
		{ "How do I shape a route by hand?",
		  "On the route's " .. Y .. "Info|r tab, click " .. Y .. "Edit points on the map|r: drag points to move them, "
		  .. "click a small handle between two points to add one, right-click a point to delete it, then " .. Y
		  .. "Save points|r. Uncluster a clustered route first." },
		{ "What are taboo areas?",
		  "Places a route should stay out of: enemy towns, caves, cliffs. On " .. Y .. "Taboo areas|r, name one "
		  .. "and click " .. Y .. "Create taboo area|r, shape it on the map, save it, then tick it on a route's "
		  .. Y .. "Taboos|r tab. Spots inside are dropped and optimizing goes around it wherever it can." },
		{ "Will my routes change as I gather?",
		  "No: a route stays as you made it. To bring in spots recorded since, click " .. Y .. "Update route|r on "
		  .. "its " .. Y .. "Info|r tab: new spots of its nodes are added and deleted ones dropped, and the rest "
		  .. "(hand-placed points too) stays put. Optimize afterwards for the shortest loop." },
		{ "How do I change how routes look, or when they show?",
		  Y .. "Display|r sets which maps draw routes and the default color and widths. A route's " .. Y .. "Look|r "
		  .. "tab overrides them, and its " .. Y .. "Info|r tab sets when it shows: always, only while you track its "
		  .. "nodes, or never." },
	}},
	{ "HUD", {
		{ "What is the HUD?",
		  "Your minimap, enlarged and see-through, in the middle of the screen: tracked nodes, pins and routes "
		  .. "appear right around your character while you farm." },
		{ "How do Zoom and Size differ?",
		  Y .. "Size|r is how big the HUD is on screen. " .. Y .. "Zoom|r is how much of the world it shows: the yards "
		  .. "from you to its edge (twice the tracking range to start with). Zoomed in, up to about 233 yards, the "
		  .. "minimap's terrain fills the HUD. The minimap can't show terrain any further, so zoomed out past that "
		  .. "the live terrain stays a disc in the middle and the rest is filled in with the minimap's own imagery "
		  .. "of the land round you (or the zone's world map where the game can't provide it; switch it off with "
		  .. Y .. "Fill in the map past the terrain|r). Pins, routes and your trail go out to the edge." },
		{ "Why can't I hover pins on the HUD?",
		  "The HUD lets clicks through to the world. Turn the mouse on (the " .. Y .. "Mouse|r button under the "
		  .. "HUD, or its key binding) for pin tooltips; turn it off again to click through." },
		{ "How do I change what it shows?",
		  Y .. "HUD|r settings: size, zoom, filling in the map round the terrain, background, turning with the camera, "
		  .. "range circle, compass, coordinates, clock, trail (kept by time or by number of dots), buttons, which "
		  .. "tracking it switches on, and hiding it in combat or dungeons. Pin sizes (the HUD has its own) are on "
		  .. "the main page." },
		{ "What does the green circle show?",
		  "How far tracking finds nodes: a node only shows up once it's inside the circle. You can set it to "
		  .. "another distance on the " .. Y .. "HUD|r settings page, and put it back with " .. Y .. "Back to the "
		  .. "tracking range|r." },
		{ "What does each click on the minimap button do?",
		  "Left-click toggles the HUD, Shift + left-click its background, middle-click opens routes on the world "
		  .. "map and right-click opens settings. Drag it to move it; hide it on the main settings page." },
	}},
	{ "Troubleshooting", {
		{ "Creating a route says there are no recorded spots.",
		  "You haven't recorded those nodes in that zone yet. Gather some there first, and check the zone picked "
		  .. "on " .. Y .. "New route|r." },
		{ "The settings window is in the way.",
		  "Drag it by its title bar; it opens where you left it next time, even after a reload." },
		{ "Why aren't routes in the settings window?",
		  "The settings window can't stay open next to the world map, and routes are shaped on the map, so they "
		  .. "live in a panel docked beside it. The " .. Y .. "Routes|r settings page just opens it." },
		{ "I got a Lua error.",
		  "Copy it (an error-catching addon makes that easy) and report it, along with what you were doing when it "
		  .. "happened." },
	}},
}

local options = { type = "group", name = "ApexGatherer FAQ", args = {} }
local order = 0
for _, section in ipairs(FAQ) do
	order = order + 1
	options.args["s" .. order] = { order = order, type = "header", name = section[1] }
	for _, qa in ipairs(section[2]) do
		order = order + 1
		options.args["q" .. order] = {
			order = order, type = "description", width = "full", fontSize = "medium",
			name = Y .. qa[1] .. "|r\n" .. qa[2] .. "\n",
		}
	end
end
Apex.FAQOptions = options
