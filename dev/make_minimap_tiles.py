"""Writes HUD/MinimapTiles.lua: the file ids of the game's minimap textures.

The HUD fills in the land past the minimap's live terrain with the minimap's own textures, one
per 533-yard square of the world. The client loads them by file id but doesn't know their
names, so the ids are listed in the addon. They come from the community listfile (file id;path
for every game file), filtered to world/minimaps/<azeroth|kalimdor>/map<x>_<y>.blp.

Run from the addon folder: python3 dev/make_minimap_tiles.py [listfile.csv]
(without a file it downloads the latest listfile, about 150 MB)
"""
import re
import sys
import urllib.request

LISTFILE = "https://github.com/wowdev/wow-listfile/releases/latest/download/community-listfile.csv"
CONTINENTS = {"azeroth": 0, "kalimdor": 1}   # minimap folder -> instance id
TILE = re.compile(r"world/minimaps/(azeroth|kalimdor)/map(\d+)_(\d+)\.blp$", re.I)


def lines():
    if len(sys.argv) > 1:
        with open(sys.argv[1], encoding="utf-8", errors="replace") as f:
            yield from f
    else:
        with urllib.request.urlopen(LISTFILE) as response:
            for raw in response:
                yield raw.decode("utf-8", errors="replace")


def main():
    tiles = {0: {}, 1: {}}
    for line in lines():
        fid, _, path = line.strip().partition(";")
        m = TILE.match(path)
        if m:
            tiles[CONTINENTS[m.group(1).lower()]][(int(m.group(2)), int(m.group(3)))] = int(fid)

    out = [
        "--[[",
        "\tThe file ids of the game's minimap textures for the Eastern Kingdoms (instance 0) and",
        "\tKalimdor (1): the client loads them by id but doesn't know their names. Written by",
        "\tdev/make_minimap_tiles.py; don't edit by hand.",
        "",
        "\tEach run is tx, ty, id, count: the squares tx counts east and ty south, (tx, ty) to",
        "\t(tx, ty + count - 1), have the ids id to id + count - 1. The table built from them is",
        "\tApexGatherer.MINIMAP_TILES[instance][tx * 64 + ty] = id.",
        "]]",
        "local RUNS = {",
    ]
    for instance in (0, 1):
        runs = []
        for tx, ty in sorted(tiles[instance]):
            fid = tiles[instance][(tx, ty)]
            last = runs[-1] if runs else None
            if last and last[0] == tx and last[1] + last[3] == ty and last[2] + last[3] == fid:
                last[3] += 1
            else:
                runs.append([tx, ty, fid, 1])
        out.append("\t[%d] = {" % instance)
        for i in range(0, len(runs), 6):
            out.append("\t\t" + " ".join("%d,%d,%d,%d," % tuple(r) for r in runs[i:i + 6]))
        out.append("\t},")
        print("instance %d: %d squares in %d runs" % (instance, len(tiles[instance]), len(runs)))
    out += [
        "}",
        "",
        "local tiles = {}",
        "for instance, runs in pairs(RUNS) do",
        "\tlocal list = {}",
        "\tfor i = 1, #runs, 4 do",
        "\t\tlocal tx, ty, id, count = runs[i], runs[i + 1], runs[i + 2], runs[i + 3]",
        "\t\tfor k = 0, count - 1 do list[tx * 64 + ty + k] = id + k end",
        "\tend",
        "\ttiles[instance] = list",
        "end",
        "ApexGatherer.MINIMAP_TILES = tiles",
        "",
    ]
    with open("HUD/MinimapTiles.lua", "w", newline="\n") as f:
        f.write("\n".join(out))


if __name__ == "__main__":
    main()
