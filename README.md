# ApexGatherer

The gathering addon for **WoW Forever**. It records every Mining, Herbalism, Fishing and Treasure node you gather, pins them on your world map and minimap, builds short farming routes from them, shows it all on a see-through HUD while you farm, and swaps nodes with your guild or friends.

## Installing

1. On this page, click **Code → Download ZIP**.
2. Unzip it. GitHub names the folder after the branch, so you get **`ApexGatherer-main`**.
3. **Rename that folder to exactly `ApexGatherer`**, or the game won't load it.
4. Move it into the `Interface\AddOns` folder of your WoW Forever client, for example:

   ```
   World of Warcraft\_classic_beta_\Interface\AddOns\ApexGatherer
   ```

5. Start the game, or restart it if it was running. A `/reload` doesn't pick up a new addon folder.

**Updating:** replace the folder the same way, and rename it again. Your nodes, routes and settings are kept, because they live in the game's `WTF` folder, not in the addon folder.

## Using it

| | |
|---|---|
| `/ag` (or `/apex`, `/apexgatherer`, `/agatherer`) | settings |
| `/ag hud` | toggle the HUD |
| `/ag routes` | the world map with the routes panel |
| Minimap button | left-click: HUD · Shift + left-click: HUD background · middle-click: routes · right-click: settings |
| Key Bindings → AddOns → ApexGatherer | keys for all of the above |

The settings window has a **FAQ** page that covers every feature.

## What it does

- **Records nodes as you gather.** Nodes are also recorded when someone else is already mining them. The addon learns node names that WoW Forever adds, and a spot settles onto the node itself as you gather it again.
- **Pins** show a picture of each node: a rock with its ore's colour, a herb with its blossom's colour, a pool, a chest. Within tracking range of a kind you're tracking, the pin becomes a ring round the minimap's own yellow dot. An empty ring means the node isn't up right now.
- **HUD:** your minimap, enlarged and see-through, in the middle of the screen. It has a tracking-range circle, compass, trail, coordinates and clock.
  - **Size** sets how big the HUD is on screen.
  - **Zoom** sets how far it shows. Past the minimap's own range, the HUD fills in the land with the minimap's imagery, and pins, routes and your trail reach its edge.
- **Routes:** pick node types in a zone and get an optimized loop through every recorded spot.
  - **Clustering** merges spots that are close together.
  - **Taboo areas** mark places a route should keep out of.
  - **Editing** lets you drag points on the world map.
  - **Update route** brings in newly recorded spots.
- **Sharing:** swap nodes with your guild or with one player. You're asked before someone else's nodes are added; answers to your own request come straight in. Lost messages are asked for again, and the addon keeps the traffic light on the realm. Both sides need ApexGatherer 2.1 or later.

## For developers

The `dev` folder isn't loaded by the game.

- `lua5.1 dev/harness.lua . [path to a SavedVariables file]` runs the addon against a stubbed client and checks every feature.
- `lua5.1 dev/validate.lua .` compiles every file the `.toc` lists.
- `python3 dev/make_media.py` redraws the textures in `Media`.
- `python3 dev/make_minimap_tiles.py` rebuilds `HUD/MinimapTiles.lua`, the file ids of the game's minimap textures.

Bundled libraries in `Libs` (Ace3, HereBeDragons, LibStub, CallbackHandler) keep their own license notices.
