# ent_sym_gat
A DFHack Lua script for **Dwarf Fortress** (v50.01 and newer) that exports civilization and entity symbols from the currently loaded world into a searchable HTML report.

The report includes a map:
![output PNG](https://raw.githubusercontent.com/Favozza/Entity_Symbol_Gatherer/refs/heads/main/Assets/map.png)

A Summary with all the civilizations and their symbols:
![output PNG](https://raw.githubusercontent.com/Favozza/Entity_Symbol_Gatherer/refs/heads/main/Assets/summary.png)

And a list with all the sub-entities:
![output PNG](https://raw.githubusercontent.com/Favozza/Entity_Symbol_Gatherer/refs/heads/main/Assets/list.png)

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
1. Embark in your world, preferably in an adjacent mountain area (this contains exposed rocks walls/floor tiles).
2. Smooth a wall or floor tile.
3. Pause the game.
4. Engrave the smoothed tile.
5. Click on the engraved tile, navigate to **Specify Image** -> **Existing Image**, and click on **DFHack**.
   *(Note: This step is necessary because the game doesn't load the symbols into memory until you open the Existing Image window.)*
6. Run the script in the DFHack console:
   ```text
   ent_sym_gat

## Visual Guide
![Guide GIF](https://raw.githubusercontent.com/Favozza/civ_sym_dump/refs/heads/main/Assets/guide.gif)

## Work in Progress
The script is still in development.

## License
Distributed under the MIT License.

