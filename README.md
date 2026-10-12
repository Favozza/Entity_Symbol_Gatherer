# ent_sym_gat
A DFHack Lua script for **Dwarf Fortress** (v50.01 and newer) that exports civilization and entity symbols from the currently loaded world into a searchable HTML report.

The report also includes a world map, civilization locations, races, and the symbols associated with each entity.

![output PNG](https://raw.githubusercontent.com/Favozza/civ_sym_dump/refs/heads/main/Assets/output.png)

## Features
* HTML output
* Export civilization and entity symbols
* Group entities by race and civilization
* Display creature, plant, tree, item, and shape symbols
* Generate an ascii world map
* Mark civilization-controlled sites on the map
* Search entities by name
* Expand/collapse civilization sections
* Include glyph information for each symbol
* Automatically update the report when additional symbol data becomes available

## Requirements
- *Dwarf Fortress* (v50.01 or later)
- [DFHack](https://github.com/DFHack/dfhack) installed

## Installation
1. Download the script from this repository.
2. Place the script file inside your `\dfhack-config\scripts\` folder.

## Usage
1. Embark in your world (preferably with exposed rock).
2. Smooth a wall or floor tile.
3. Pause the game.
4. Engrave the smoothed tile.
5. Click on the engraved tile, navigate to **Specify Image** -> **Existing Image**, and click on **DFHack**.
   *(Note: This step is necessary because the game doesn't load the symbols into memory until you open the Existing Image window.)*
6. Run the script in the DFHack console:
   ```text
   civ_sym_dump

## Visual Guide
![Guide GIF](https://raw.githubusercontent.com/Favozza/civ_sym_dump/refs/heads/main/Assets/guide.gif)

## Work in Progress
The script is still in development. Some symbols will not appear, may be wrong and some sites may not belong to the civilization indicated in the legend.

## License
See the repository license.

