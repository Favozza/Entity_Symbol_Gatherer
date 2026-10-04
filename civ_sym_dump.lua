-- civ_sym_dump: dump all civilization and entity symbols of the loaded world to a civ_symbols_<worldname>.html file in the DF folder
-- Usage: Embark -> Smooth stone wall/floor -> Detail -> Specify image -> Existing image -> Click on DFHack -> civ_sym_dump

-- Glyph table: paste the content of glyph.txt at the END of this file (search for "PASTE GLYPH TABLE").
-- If nothing is pasted there, a glyph.txt next to the script is used instead.
local GLYPH_TEXT = ''

local function safe(f, ...)
    local ok, r = pcall(f, ...)
    if ok then return r end
end

if not dfhack.isWorldLoaded() then
    qerror('No world data loaded yet. Try again after loading the save.')
end

-- ---------------------------------------------------------------------------
-- helpers
-- ---------------------------------------------------------------------------

local ESC = { ['&'] = '&amp;', ['<'] = '&lt;', ['>'] = '&gt;', ['"'] = '&quot;', ["'"] = '&#39;' }

-- DF strings are CP437; convert to UTF-8, then escape for HTML
local function esc(s)
    s = tostring(s)
    s = safe(dfhack.df2utf, s) or s
    return (s:gsub('[&<>"\']', ESC))
end

local function find_image(id, subid)
    for _, c in ipairs(df.global.world.art_image_chunks.all) do
        if c.id == id then
            for _, m in ipairs(c.images) do
                local a = m.art_image
                if a and a.subid == subid then return a end
            end
        end
    end
end

local function plant_name(pid)
    local p = safe(function() return df.global.world.raws.plants.all[pid] end)
    return p and p.name or ('plant#' .. pid)
end

local function shape_name(e)
    local sh = safe(function() return df.global.world.raws.descriptors.shapes[e.shape_id] end)
    local nm = sh and safe(function() return sh.name end)
    return nm and ('shape: ' .. nm) or ('shape#' .. e.shape_id)
end

-- lookup keys for glyph.txt: full name, last word (usually the noun), then the other words
local function add_keys(keys, name)
    if not name then return end
    name = tostring(name):lower():gsub('_', ' ')
    name = name:gsub('^%s+', ''):gsub('%s+$', '')
    if name == '' then return end
    keys[#keys + 1] = name
    local words = {}
    for w in name:gmatch('%S+') do
        if #w > 2 then words[#words + 1] = w end
    end
    if #words > 1 or (#words == 1 and words[1] ~= name) then
        for k = #words, 1, -1 do keys[#keys + 1] = words[k] end
    end
end

-- returns the readable text and the glyph lookup keys of one symbol element
local function describe(e)
    local t = tostring(e._type)
    local cnt = e.count and e.count > 1 and (' x' .. e.count) or ''
    local keys = {}
    if t:find('creaturest') then
        local cr = df.creature_raw.find(e.race)
        local nm = cr and cr.name[0]
        add_keys(keys, nm)
        return (nm or ('race#' .. e.race)) .. cnt, keys
    elseif t:find('treest') then
        local nm = plant_name(e.plant_id)
        add_keys(keys, nm)
        keys[#keys + 1] = 'tree'
        return 'tree: ' .. nm .. cnt, keys
    elseif t:find('plantst') then
        local nm = plant_name(e.plant_id)
        add_keys(keys, nm)
        keys[#keys + 1] = 'plant'
        return 'plant: ' .. nm .. cnt, keys
    elseif t:find('itemst') then
        local type_name = df.item_type[e.item_type] or ('item#' .. e.item_type)
        local name = type_name
        if e.item_subtype >= 0 then
            local d = safe(dfhack.items.getSubtypeDef, e.item_type, e.item_subtype)
            if d then name = d.name end
        end
        add_keys(keys, name)
        if name ~= type_name then add_keys(keys, type_name) end
        return 'item: ' .. name .. cnt, keys
    elseif t:find('shapest') then
        local txt = shape_name(e)
        add_keys(keys, txt:match('^shape: (.+)$'))
        return txt .. cnt, keys
    end
    return t, keys
end

-- glyph.txt: lines like "001 ☺<TAB>Civilian dwarves#, ..." (ID, space, glyph, TAB, usage),
-- pasted at the end of the script or in a glyph.txt next to it. The older "ID<TAB>Glyph<TAB>Usage" layout is accepted too.
local glyph_rows  -- nil = not tried yet, false = not found
local glyph_cache = {}

-- turns the lines of a glyph table into rows; returns the rows and the number of numbered lines
local function parse_glyph_lines(lines)
    local rows, numbered = {}, 0
    for line in lines do
        line = line:gsub('\r$', '')
        local id, rest = line:match('^(%d+)(.*)$')
        if id then
            numbered = numbered + 1
            local glyph, usage
            local g_old, u_old = rest:match('^\t([^\t]*)\t(.*)$')  -- ID<TAB>glyph<TAB>usage
            if g_old then
                glyph, usage = g_old:match('^%s*(.-)%s*$'), u_old
            else
                -- ID, then any number of spaces, then the glyph, then a tab or spaces, then the usage.
                -- A tab right after the spaces means the glyph is blank (e.g. 000): skip the row.
                rest = rest:gsub('^ +', '')
                if rest:sub(1, 1) ~= '\t' then
                    glyph = rest:match('^' .. utf8.charpattern)
                    usage = glyph and rest:sub(#glyph + 1):gsub('^%s+', '')
                end
            end
            if glyph and glyph ~= '' then
                usage = usage:lower()
                -- the comma/semicolon separated entries of the usage text, without notes and markers
                local items, heads = {}, {}
                for item in usage:gmatch('[^,;]+') do
                    item = item:gsub('%b()', ''):gsub('^[%s%p]+', ''):gsub('[%s%p]+$', '')
                    if item ~= '' then
                        items[item] = true
                        heads[item:match('(%S+)$')] = true  -- last word, e.g. "dwarves" in "civilian dwarves"
                    end
                end
                rows[#rows + 1] = { id = id, glyph = glyph, usage = usage, items = items, heads = heads }
            end
        end
    end
    return rows, numbered
end

local function load_glyphs()
    -- 1. the table pasted into this script
    local rows, numbered = parse_glyph_lines(GLYPH_TEXT:gmatch('[^\n]+'))
    if #rows > 0 then
        print(('civ_sym_dump: loaded %d glyphs (%d numbered lines) from the table inside the script')
            :format(#rows, numbered))
        return rows
    end

    -- 2. a glyph.txt next to the script
    local dirs = {}
    local sp = safe(dfhack.findScript, 'civ_sym_dump')
    if sp then dirs[#dirs + 1] = (tostring(sp):gsub('[/\\][^/\\]*$', '')) end
    local df_path = dfhack.getDFPath()
    dirs[#dirs + 1] = df_path
    dirs[#dirs + 1] = df_path .. '/dfhack-config/scripts'
    local hp = safe(dfhack.getHackPath)
    if hp then dirs[#dirs + 1] = (tostring(hp):gsub('[/\\]$', '')) .. '/scripts' end

    for _, dir in ipairs(dirs) do
        local f = io.open(dir .. '/glyph.txt', 'r')
        if f then
            rows, numbered = parse_glyph_lines(f:lines())
            f:close()
            print(('civ_sym_dump: loaded %d glyphs (%d numbered lines) from %s/glyph.txt'):format(#rows, numbered, dir))
            return rows
        end
    end
    print('civ_sym_dump: no glyph table found (nothing pasted in the script, no glyph.txt); glyph column will be empty')
    return false
end

-- singular/plural spellings to try, e.g. dwarf -> dwarves, goblin -> goblins
local function key_variants(k)
    local v = { k }
    if k:match('fe$') then v[#v + 1] = k:sub(1, -3) .. 'ves'
    elseif k:match('f$') then v[#v + 1] = k:sub(1, -2) .. 'ves' end
    if k:match('y$') then v[#v + 1] = k:sub(1, -2) .. 'ies' end
    v[#v + 1] = k .. 's'
    v[#v + 1] = k .. 'es'
    return v
end

-- Picks the best row for a key, in this order:
--   1. a row that lists it as an entry of its own ("..., Raccoon, ..." beats "Giant raccoon, ...")
--   2. a row with an entry ending in it ("Civilian dwarves" for dwarf); the first row wins ties
--   3. a row that mentions it anywhere, the earliest mention first
-- Rows mentioning "military" only win if nothing else matches. Run with the argument "glyphdebug" to see every choice.
local glyph_debug = false

local function glyph_for(keys)
    if not glyph_rows then return '' end
    for _, k in ipairs(keys) do
        local hit = glyph_cache[k]
        if hit == nil then
            hit = false
            local forms, pats = key_variants(k), {}
            for _, form in ipairs(forms) do
                pats[#pats + 1] = '%f[%w]' .. (form:gsub('%p', '%%%0')) .. '%f[%W]'
            end
            local best_score
            for _, r in ipairs(glyph_rows) do
                local score
                for _, form in ipairs(forms) do
                    if r.items[form] then score = 0 break end  -- an entry of its own: "..., Raccoon, ..."
                end
                if not score then
                    for _, form in ipairs(forms) do
                        if r.heads[form] then score = 1000 break end  -- last word of an entry: "Civilian dwarves"
                    end
                end
                if not score then
                    for _, pat in ipairs(pats) do
                        local pos = r.usage:find(pat)
                        if pos and (not score or 2000 + pos < score) then score = 2000 + pos end  -- mentioned anywhere
                    end
                end
                if score then
                    if r.usage:find('military', 1, true) then score = score + 100000 end
                    if not best_score or score < best_score then best_score, hit = score, r end
                end
            end
            glyph_cache[k] = hit
            if glyph_debug then
                if hit then
                    print(('civ_sym_dump glyph: "%s" -> %s  (line %s: %s)'):format(k, hit.glyph, hit.id, hit.usage:sub(1, 60)))
                else
                    print(('civ_sym_dump glyph: "%s" -> no match'):format(k))
                end
            end
        end
        if hit then return hit.glyph end
    end
    return '–'
end

-- name of the entity's own race, e.g. "Dwarf"
local function civ_race_name(ent)
    local cr = ent.race >= 0 and safe(df.creature_raw.find, ent.race)
    local nm = cr and cr.name[0]
    if not nm or nm == '' then return 'Unknown race' end
    return (nm:gsub('^%l', string.upper))
end

local function loaded_signature()
    local ids = {}
    for _, c in ipairs(df.global.world.art_image_chunks.all) do
        ids[#ids + 1] = c.id
    end
    table.sort(ids)
    return table.concat(ids, ',')
end

-- human-readable label for an entity's actual DF type
local function entity_type_name(ent)
    local nm = safe(function() return df.historical_entity_type[ent.type] end)
    return nm or ('type#' .. tostring(ent.type))
end

-- find parent civilization name from entity links
local function find_parent_civ_name(ent, civ_map)
    if ent.type == df.historical_entity_type.Civilization then
        return nil
    end
    for _, link in ipairs(ent.entity_links) do
        if civ_map[link.target] then
            return civ_map[link.target]
        end
    end
    return "Independent"
end

-- ---------------------------------------------------------------------------
-- HTML output
-- ---------------------------------------------------------------------------

local CSS = [[
:root{
  --bg:#000;--ink:#fff;--muted:#a9a9a9;--line:#303030;--hover:#0f0f0f;
  --accent:#fff;--warn:#f0b040;
  --font:"DejaVu Sans Mono",Consolas,ui-monospace,SFMono-Regular,monospace;
}
*{box-sizing:border-box}
html{scroll-padding-top:4.5rem;color-scheme:dark}
body{margin:0;background:var(--bg);color:var(--ink);font:14px/1.5 var(--font)}
header.top{position:sticky;top:0;z-index:5;background:var(--bg);border-bottom:1px solid var(--line);
  padding:.7rem 1.25rem;display:flex;flex-wrap:wrap;gap:.75rem 1.5rem;align-items:center}
header.top h1{font-size:1rem;margin:0;font-weight:700;color:var(--accent)}
header.top .meta{display:flex;flex-wrap:wrap;gap:.2rem 1.2rem;font-size:.82rem}
header.top .meta .k{color:var(--muted)}
header.top .meta b{color:var(--ink)}
header.top .tools{margin-left:auto;display:flex;gap:.5rem;align-items:center}
input[type=search]{font:inherit;padding:.35rem .6rem;min-width:15rem;border:1px solid var(--line);
  border-radius:3px;background:var(--bg);color:var(--ink)}
button{font:inherit;padding:.35rem .7rem;border:1px solid var(--line);border-radius:3px;
  background:var(--bg);color:var(--ink);cursor:pointer}
button:hover,input[type=search]:hover{border-color:var(--accent)}
:focus-visible{outline:2px solid var(--accent);outline-offset:2px}
main{max-width:92rem;margin:0 auto;padding:1.25rem}
.notice{color:var(--warn);border:1px solid var(--warn);border-radius:3px;
  padding:.6rem .9rem;margin-bottom:1rem;font-size:.85rem}
nav.races{display:flex;flex-wrap:wrap;gap:.4rem;margin-bottom:1.25rem}
nav.races a{color:var(--accent);border:1px solid var(--line);padding:.1rem .6rem;
  border-radius:3px;text-decoration:none;font-size:.82rem}
nav.races a:hover{border-color:var(--accent)}
section.mapsec,section.race{margin-bottom:2rem}
section.mapsec>h2,section.race>h2{font-size:1.1rem;margin:0 0 .6rem;font-weight:700;color:var(--accent);
  display:flex;align-items:baseline;gap:.6rem}
h2 .count{font-size:.8rem;font-weight:400;color:var(--muted)}
.mapbox,details.civ{background:var(--bg);border:1px solid var(--line);border-radius:3px}
.mapbox{padding:.6rem}
.mapscroll{overflow-x:auto}
pre.map{margin:0;font:13.8px/1.15 var(--font);letter-spacing:2.3px;white-space:pre}
pre.map i{font-style:normal}
.maplegend,.civlegend{margin-top:.6rem;padding-top:.5rem;border-top:1px solid var(--line);font-size:.8rem}
.maplegend{display:flex;flex-wrap:wrap;gap:.3rem 1.1rem}
.maplegend b{margin-right:.3rem}
.racelegend{display:flex;flex-wrap:wrap;gap:.3rem 1.1rem;margin-top:.35rem;font-size:.8rem}
.racelegend b{margin-right:.3rem}
.racelegend .rl{color:var(--muted)}
.civlegend{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:.25rem 1.2rem}
.civlegend div{display:flex;gap:.45rem;align-items:baseline}
.civlegend .cn{min-width:0;overflow-wrap:anywhere}
.civlegend .racehead{grid-column:1/-1;margin:.5rem 0 0;font-size:.85rem;font-weight:700;
  border-bottom:1px solid var(--line);padding-bottom:.15rem}
.civlegend .racehead:first-child{margin-top:0}
.civlegend .racehead span{color:var(--muted);font-weight:400}
.civlegend .sw{flex:none;font-size:.95rem}
.civlegend .cn{font-weight:700}
.civlegend .cs{color:var(--muted)}
details.civ{margin-bottom:.5rem}
details.civ>summary{cursor:pointer;padding:.5rem .85rem;display:flex;flex-wrap:wrap;
  gap:.2rem .8rem;align-items:baseline;list-style-position:inside}
details.civ>summary:hover{background:var(--hover)}
summary .civname{font-weight:700}
summary .sym{color:var(--ink);font-size:.85rem}
summary .n{margin-left:auto;color:var(--muted);font-size:.78rem}
.civ-body{padding:0 .85rem .7rem 1.6rem;border-top:1px solid var(--line)}
.civ-body h3{font-size:.85rem;margin:.8rem 0 .25rem;color:var(--ink);font-weight:700;text-decoration:underline;text-decoration-color:var(--line);text-underline-offset:3px}
ul.entries{list-style:none;margin:0;padding:0}
li.entry,li.colhead{display:grid;grid-template-columns:minmax(10rem,1.2fr) minmax(0,2.4fr) minmax(4rem,.8fr);
  gap:.1rem 1rem;padding:.25rem 0}
li.entry{border-bottom:1px dotted var(--line)}
li.entry:last-child{border-bottom:0}
li.colhead{color:var(--muted);font-size:.72rem;text-transform:uppercase;letter-spacing:.08em;
  border-bottom:1px solid var(--line)}
li.entry .name{font-weight:700;color:var(--ink)}
li.entry .sym{font-size:.82rem;color:var(--ink)}
li.entry .gl{font-size:.95rem;letter-spacing:.15em;color:var(--ink)}
li.entry.missing .sym{color:var(--warn)}
summary .gl{font-size:.95rem;letter-spacing:.15em}
.hidden{display:none!important}
footer{color:var(--muted);font-size:.78rem;text-align:center;padding:1rem}
@media (max-width:600px){input[type=search]{min-width:0;width:100%}header.top .tools{margin-left:0;width:100%}}
]]

local JS = [[
(function(){
  var q=document.getElementById('q');
  var entries=[].slice.call(document.querySelectorAll('li.entry'));
  var civs=[].slice.call(document.querySelectorAll('details.civ'));
  var races=[].slice.call(document.querySelectorAll('section.race'));
  var groups=[].slice.call(document.querySelectorAll('.typegroup'));
  function filter(){
    var s=q.value.trim().toLowerCase();
    entries.forEach(function(li){
      li.classList.toggle('hidden', s && li.textContent.toLowerCase().indexOf(s)<0);
    });
    groups.forEach(function(g){
      g.classList.toggle('hidden', !g.querySelector('li.entry:not(.hidden)'));
    });
    civs.forEach(function(d){
      var head=(d.querySelector('summary').textContent||'').toLowerCase();
      var hit=d.querySelector('li.entry:not(.hidden)')||(s&&head.indexOf(s)>=0);
      d.classList.toggle('hidden', s && !hit);
      if(s&&hit) d.open=true;
    });
    races.forEach(function(r){
      r.classList.toggle('hidden', s && !r.querySelector('details.civ:not(.hidden)'));
    });
  }
  q.addEventListener('input',filter);
  document.getElementById('expand').onclick=function(){civs.forEach(function(d){if(!d.classList.contains('hidden'))d.open=true;});};
  document.getElementById('collapse').onclick=function(){civs.forEach(function(d){d.open=false;});};
})();
]]

-- ---------------------------------------------------------------------------
-- physical map (read straight from the loaded world, no legends export needed)
-- ---------------------------------------------------------------------------

-- key = { symbol, css colour, label }
local TERRAIN = {
    grassland     = { "τ", "#4CAF50", "Grassland" },
    hills         = { "∩", "#00CC44", "Hills" },
    forest        = { "╞", "#00CC44", "Forest" },
    desert        = { "≈", "#D4B106", "Desert" },
    tundra        = { ".", "#CCCCCC", "Tundra" },
    glacier       = { "#", "#FFFFFF", "Glacier" },
    wetland       = { '"', "#CC33CC", "Wetland" },
    mountains     = { "^", "#CCCCCC", "Mountains" },
    ocean         = { "~", "#3366FF", "Ocean" },
    lake          = { "-", "#00E5FF", "Lake" },
    default       = { "≡", "#999999", "Other Land" },
    mountain_peak = { "▲", "#FFFFFF", "Mountain Peak" },
    volcano       = { "▲", "#FF3333", "Volcano" },
}
local TERRAIN_ORDER = { 'grassland', 'hills', 'forest', 'desert', 'tundra', 'glacier', 'wetland',
    'mountains', 'ocean', 'lake', 'default', 'mountain_peak', 'volcano' }

-- older DF region type names -> legends names
local TYPE_ALIAS = { steppe = 'grassland', swamp = 'wetland', jungle = 'forest', mountain = 'mountains' }

-- escape without the CP437 conversion (our map symbols are already UTF-8)
local function html_plain(s)
    return (tostring(s):gsub('[&<>"\']', ESC))
end

local function commas(n, decimals)
    local s = ('%.' .. (decimals or 0) .. 'f'):format(n)
    local int, frac = s:match('^(-?%d+)(.*)$')
    int = int:reverse():gsub('(%d%d%d)', '%1,'):reverse():gsub('^,', ''):gsub('^%-,', '-')  -- keeps the sign when the digit count is a multiple of 3
    return int .. frac
end

-- civ_info: [entity id] = { name = ..., symbol = ... (may be nil) }
local function build_map_html(civ_info)
    civ_info = civ_info or {}
    local wd = df.global.world.world_data
    local W, H = wd.world_width, wd.world_height

    local function tile_at(x, y)
        local col = wd.region_map[x]
        return safe(function() return col:_displace(y) end) or col[y]
    end

    -- region id -> terrain key (cached)
    local key_cache = {}
    local function region_key(id)
        if id == nil or id < 0 then return 'default' end
        local k = key_cache[id]
        if not k then
            local r = safe(function() return wd.regions[id] end)
            local nm = r and safe(function() return df.world_region_type[r.type] end)
            nm = nm and tostring(nm):lower() or 'default'
            nm = TYPE_ALIAS[nm] or nm
            k = TERRAIN[nm] and nm or 'default'
            key_cache[id] = k
        end
        return k
    end

    -- mountain peaks, indexed by "x,y"
    local peaks = {}
    for _, p in ipairs(wd.mountain_peaks) do
        local pos = p.pos
        local nm = safe(dfhack.translation.translateName, p.name, true)
        if not nm or nm == '' then nm = 'Unnamed Peak' end
        local pk = {
            name = nm,
            height = p.height,
            volcano = safe(function() return p.flags.is_volcano end) and true or false,
            x = pos.x, y = pos.y,
        }
        peaks[pk.x .. ',' .. pk.y] = pk
    end

    -- sites: resolve the civilization each one belongs to
    local function to_civ(id)
        if not id or id < 0 then return nil end
        if civ_info[id] then return id end
        local e = safe(df.historical_entity.find, id)
        if e then
            for _, link in ipairs(e.entity_links) do
                if civ_info[link.target] then return link.target end
            end
        end
    end

    local sites_at, civ_sites = {}, {}
    for _, s in ipairs(wd.sites) do
        local civ = to_civ(s.cur_owner_id) or to_civ(s.civ_id)
        if civ then
            civ_sites[civ] = (civ_sites[civ] or 0) + 1
            local sname = safe(dfhack.translation.translateName, s.name, true)
            if not sname or sname == '' then sname = 'Unnamed site' end
            local stype = safe(function() return df.world_site_type[s.type] end) or 'Site'
            local key = s.pos.x .. ',' .. s.pos.y
            sites_at[key] = sites_at[key] or {}
            table.insert(sites_at[key], { civ = civ, name = sname, type = stype })
        end
    end

    -- one colour per civ that owns sites (golden-angle hues, stable by civ name)
    local civ_ids = {}
    for id in pairs(civ_sites) do civ_ids[#civ_ids + 1] = id end
    table.sort(civ_ids, function(a, b)
        if civ_info[a].name ~= civ_info[b].name then return civ_info[a].name < civ_info[b].name end
        return a < b
    end)
    -- marker = the civ's glyph, or its race shape if it has none; colour = civ (distinct among the civs of the same race)
    local RACE_SHAPE = { Dwarf = "■", Human = "□", Elf = "X", Goblin = "○", Kobold = "●" }
    local EXTRA_SHAPES = { "◆", "▲", "▼", "★", "◇", "△" }
    local by_race_ids, race_names = {}, {}
    for _, id in ipairs(civ_ids) do
        local r = civ_info[id].race or 'Unknown race'
        if not by_race_ids[r] then
            by_race_ids[r] = {}
            race_names[#race_names + 1] = r
        end
        table.insert(by_race_ids[r], id)
    end
    table.sort(race_names)
    -- civ colours: first red/blue/purple/pink/cyan tones, which are not used by the terrain;
    -- yellow, orange, green and gray only once those run out
    local PREFERRED = {
        'hsl(0,85%,58%)',    -- red
        'hsl(205,90%,60%)',  -- azure
        'hsl(310,85%,62%)',  -- magenta
        'hsl(180,85%,52%)',  -- cyan
        'hsl(265,85%,72%)',  -- violet
        'hsl(340,90%,72%)',  -- pink
        'hsl(235,75%,66%)',  -- indigo
    }
    local LAST_RESORT = {
        'hsl(58,95%,58%)',   -- yellow
        'hsl(28,95%,58%)',   -- orange
        'hsl(85,75%,55%)',   -- lime
        'hsl(135,70%,52%)',  -- green
        'hsl(0,0%,72%)',     -- light gray
        'hsl(0,0%,50%)',     -- gray
    }
    local function pick_color(ri, k)
        if k <= #PREFERRED then
            return PREFERRED[(k - 1 + ri - 1) % #PREFERRED + 1]  -- rotate so each race starts differently
        end
        local j = k - #PREFERRED
        if j <= #LAST_RESORT then return LAST_RESORT[j] end
        return ('hsl(%d,85%%,62%%)'):format(math.floor(((j - #LAST_RESORT) * 137.508) % 360))
    end
    -- marker = the civ's own glyph (first one found in glyph.txt)
    local function first_glyph(glyphs)
        for g in tostring(glyphs or ''):gmatch('%S+') do
            if g ~= '–' then return g end
        end
    end
    local civ_color, civ_shape, race_shape, extra = {}, {}, {}, 0
    for ri, race in ipairs(race_names) do
        local shape = RACE_SHAPE[race]
        if not shape then
            shape = EXTRA_SHAPES[extra % #EXTRA_SHAPES + 1]
            extra = extra + 1
        end
        race_shape[race] = shape
        local list = by_race_ids[race]  -- already sorted by civ name
        for k, id in ipairs(list) do
            civ_color[id] = pick_color(ri, k)
            civ_shape[id] = first_glyph(civ_info[id].glyphs) or shape
        end
    end

    local used = {}
    local rows = {}
    for y = 0, H - 1 do
        local out, cur_key, cur_n = {}, nil, 0
        local function emit()
            if cur_n > 0 then
                out[#out + 1] = ('<i class="t-%s">%s</i>'):format(cur_key, TERRAIN[cur_key][1]:rep(cur_n))
                cur_n, cur_key = 0, nil
            end
        end
        for x = 0, W - 1 do
            local t = tile_at(x, y)
            local pk = peaks[x .. ',' .. y]
            local st = sites_at[x .. ',' .. y]
            if st then
                emit()
                local lines = {}
                for _, s in ipairs(st) do
                    local ci = civ_info[s.civ]
                    lines[#lines + 1] = ('%s (%s) - %s%s'):format(s.name, s.type, ci.name,
                        ci.symbol and (' - symbol: ' .. ci.symbol) or '')
                end
                local title = table.concat(lines, '\n')
                out[#out + 1] = ('<i style="color:%s" title="%s">%s</i>')
                    :format(civ_color[st[1].civ], html_plain(safe(dfhack.df2utf, title) or title),
                        html_plain(civ_shape[st[1].civ]))
            elseif pk then
                emit()
                local key = pk.volcano and 'volcano' or 'mountain_peak'
                used[key] = true
                local rid = t and t.region_id
                local rname = rid and rid >= 0 and safe(function()
                    return dfhack.translation.translateName(wd.regions[rid].name, true)
                end) or nil
                local title = ('%s - %s m%s%s'):format(pk.name, commas(pk.height),
                    pk.volcano and ' (Volcano)' or '', rname and (' - ' .. rname) or '')
                out[#out + 1] = ('<i class="t-%s" title="%s">%s</i>')
                    :format(key, html_plain(safe(dfhack.df2utf, title) or title), TERRAIN[key][1])
            else
                local key = region_key(t and t.region_id)
                used[key] = true
                if key ~= cur_key then emit(); cur_key = key end
                cur_n = cur_n + 1
            end
        end
        emit()
        rows[#rows + 1] = table.concat(out)
    end

    local h = {}
    local function add(s) h[#h + 1] = s end

    add('<section class="mapsec" id="map">')
    local css = {}
    for _, k in ipairs(TERRAIN_ORDER) do
        css[#css + 1] = ('.mapbox .t-%s{color:%s}'):format(k, TERRAIN[k][2])
    end
    add('<style>' .. table.concat(css) .. '</style>')
    add('<div class="mapbox"><div class="mapscroll"><pre class="map">')
    add(table.concat(rows, '\n'))
    add('</pre></div><div class="maplegend">')
    for _, k in ipairs(TERRAIN_ORDER) do
        if used[k] then
            add(('<span><b class="t-%s">%s</b>%s</span>'):format(k, html_plain(TERRAIN[k][1]), TERRAIN[k][3]))
        end
    end
    add('</div>')
    do
        local items = {}
        for _, r in ipairs({ 'Dwarf', 'Human', 'Elf', 'Goblin', 'Kobold' }) do
            items[#items + 1] = { RACE_SHAPE[r], r }
        end
        for _, r in ipairs(race_names) do  -- other races present on this map
            if not RACE_SHAPE[r] then items[#items + 1] = { race_shape[r], r } end
        end
        add('<div class="racelegend"><span class="rl">Absent Glyph:</span>')
        for _, it in ipairs(items) do
            add(('<span><b>%s</b>%s</span>'):format(html_plain(it[1]), html_plain(it[2])))
        end
        add('</div>')
    end
    if #civ_ids > 0 then
        add('<div class="civlegend">')
        for _, race in ipairs(race_names) do
            local list = by_race_ids[race]
            add(('<h4 class="racehead">%s <span>(%d)</span></h4>'):format(html_plain(race), #list))
            for _, id in ipairs(list) do
                local ci = civ_info[id]
                local txt = ('%s</span> <span class="cs">%s (%d site%s)'):format(
                    html_plain(safe(dfhack.df2utf, ci.name) or ci.name),
                    html_plain(safe(dfhack.df2utf, ci.symbol or 'no symbol') or ci.symbol or 'no symbol'),
                    civ_sites[id], civ_sites[id] == 1 and '' or 's')
                add(('<div><span class="sw" style="color:%s">%s</span><span class="cn">%s</span></div>')
                    :format(civ_color[id], html_plain(civ_shape[id]), txt))
            end
        end
        add('</div>')
    end
    add('</div></section>')
    return table.concat(h, '\n'), civ_color
end

local function entry_html(en)
    local cls = en.missing and 'entry missing' or 'entry'
    return ('<li class="%s"><span class="name">%s</span><span class="sym">%s</span><span class="gl">%s</span></li>')
        :format(cls, esc(en.name), esc(en.symbol), html_plain(en.glyphs or ''))
end

local function slug(s)
    return (tostring(s):gsub('[^%w]', '_'))
end

local function count_entries(race_group)
    local n = 0
    for _, g in pairs(race_group) do
        if g.civ then n = n + 1 end
        for _, list in pairs(g.types) do n = n + #list end
    end
    return n
end

local function build_html(by_race, races, world, stats, civ_info)
    local h = {}
    local function add(s) h[#h + 1] = s end

    add('<!DOCTYPE html>')
    add('<html lang="en"><head><meta charset="utf-8">')
    add('<meta name="viewport" content="width=device-width, initial-scale=1">')
    add(('<title>Civilization symbols - %s</title>'):format(esc(world)))
    add('<style>' .. CSS .. '</style></head><body>')

    add('<header class="top">')
    add(('<h1>%s</h1>'):format(esc(world)))
    add('<span class="meta">')
    for _, st in ipairs({
        { 'Races', #races },
        { 'Civilizations', stats.civs },
        { 'Symbols', stats.decoded + stats.missing },
        { 'Decoded', stats.decoded },
        { 'Not Decodable', stats.missing },
    }) do
        add(('<span class="stat"><span class="k">%s</span> <b>%d</b></span>'):format(st[1], st[2]))
    end
    add('</span>')
    add('<div class="tools">')
    add('<input id="q" type="search" placeholder="Filter by name or symbol" aria-label="Filter">')
    add('<button id="expand" type="button">Expand all</button>')
    add('<button id="collapse" type="button">Collapse all</button>')
    add('</div></header><main>')

    local ok, map_html, civ_color = pcall(build_map_html, civ_info)
    if ok then
        add(map_html)
    else
        add('<div class="notice">The physical map could not be built: ' .. html_plain(map_html) .. '</div>')
        print('civ_sym_dump: map error: ' .. tostring(map_html))
    end

    add('<nav class="races" aria-label="Races">')
    for _, race in ipairs(races) do
        add(('<a href="#race-%s">%s</a>'):format(slug(race), esc(race)))
    end
    add('</nav>')

    for _, race in ipairs(races) do
        local race_group = by_race[race]
        local total = count_entries(race_group)

        add(('<section class="race" id="race-%s">'):format(slug(race)))
        add(('<h2>%s <span class="count">%d entr%s</span></h2>')
            :format(esc(race), total, total == 1 and 'y' or 'ies'))

        -- group keys: alphabetical, "Independent" strictly last
        local group_keys = {}
        for gkey in pairs(race_group) do group_keys[#group_keys + 1] = gkey end
        table.sort(group_keys, function(a, b)
            if a == "Independent" then return false end
            if b == "Independent" then return true end
            return a < b
        end)

        for _, gkey in ipairs(group_keys) do
            local g = race_group[gkey]
            local n = (g.civ and 1 or 0)
            for _, list in pairs(g.types) do n = n + #list end

            add('<details class="civ"><summary>')
            if gkey == "Independent" then
                add('<span class="civname">Independent</span>')
            else
                -- same colour as in the map legend (civs without sites have none: they stay white)
                local col = ok and civ_color and g.civ and civ_color[g.civ.id]
                add(('<span class="civname"%s>%s</span>'):format(
                    col and (' style="color:' .. col .. '"') or '', esc(g.civ and g.civ.name or gkey)))
                if g.civ then
                    add(('<span class="sym%s">%s</span>')
                        :format(g.civ.missing and ' missing' or '', esc(g.civ.symbol)))
                    if g.civ.glyphs and g.civ.glyphs ~= '' then
                        add(('<span class="gl">%s</span>'):format(html_plain(g.civ.glyphs)))
                    end
                end
            end
            add(('<span class="n">%d</span></summary><div class="civ-body">'):format(n))

            local tnames = {}
            for tname in pairs(g.types) do tnames[#tnames + 1] = tname end
            table.sort(tnames)

            for _, tname in ipairs(tnames) do
                local list = g.types[tname]
                table.sort(list, function(a, b)
                    if a.name ~= b.name then return a.name < b.name end
                    return a.symbol < b.symbol
                end)
                add(('<div class="typegroup"><h3>%s (%d)</h3><ul class="entries">'):format(esc(tname), #list))
                add('<li class="colhead"><span>Name</span><span>Symbol</span><span>Glyph</span></li>')
                for _, en in ipairs(list) do add(entry_html(en)) end
                add('</ul></div>')
            end
            add('</div></details>')
        end
        add('</section>')
    end

    add('</main>')
    add(('<footer>Generated by civ_sym_dump (%s)</footer>'):format(esc(os.date('%Y-%m-%d %H:%M'))))
    add('<script>' .. JS .. '</script></body></html>')
    return table.concat(h, '\n')
end

-- ---------------------------------------------------------------------------
-- dump
-- ---------------------------------------------------------------------------

-- writes the file, returns number of entities that could not be decoded
local function dump(filter)
    if glyph_rows == nil then glyph_rows = load_glyphs() end
    local by_race = {}
    local stats = { decoded = 0, missing = 0, civs = 0, missing_chunks = {} }

    -- lookup map of all Civilizations by ID
    local civ_map, civ_info = {}, {}
    for _, ent in ipairs(df.global.world.entities.all) do
        if ent.type == df.historical_entity_type.Civilization and ent.name.has_name then
            civ_map[ent.id] = dfhack.translation.translateName(ent.name, true)
            civ_info[ent.id] = { name = civ_map[ent.id], race = civ_race_name(ent) }
        end
    end

    for _, ent in ipairs(df.global.world.entities.all) do
        if #ent.resources.art_image_ids > 0 and ent.name.has_name then
            local cname = dfhack.translation.translateName(ent.name, true)
            local race = civ_race_name(ent)
            local tname = entity_type_name(ent)
            local parent_civ = find_parent_civ_name(ent, civ_map)

            local id = ent.resources.art_image_ids[0]
            local sub = ent.resources.art_image_subids[0]
            local img = find_image(id, sub)
            local en = { name = cname, id = ent.id }
            if img then
                stats.decoded = stats.decoded + 1
                local parts, glyphs = {}, {}
                for _, e in ipairs(img.elements) do
                    local txt, keys = describe(e)
                    parts[#parts + 1] = txt
                    glyphs[#glyphs + 1] = glyph_for(keys)
                end
                en.symbol = table.concat(parts, ' + ')
                en.glyphs = table.concat(glyphs, ' ')
            else
                stats.missing = stats.missing + 1
                stats.missing_chunks[id] = true
                en.missing = true
                en.symbol = ('(symbol chunk %d not loaded)'):format(id)
            end

            by_race[race] = by_race[race] or {}
            local race_group = by_race[race]

            -- grouping key: the civ itself, its parent civ, or "Independent"
            local group_key
            local is_civ = ent.type == df.historical_entity_type.Civilization
            if is_civ then
                group_key = cname
            elseif parent_civ ~= "Independent" then
                group_key = parent_civ
            else
                group_key = "Independent"
            end

            race_group[group_key] = race_group[group_key] or { types = {} }
            local bucket = race_group[group_key]

            if is_civ then
                bucket.civ = en
                stats.civs = stats.civs + 1
                civ_info[ent.id].symbol = img and en.symbol or nil
                civ_info[ent.id].glyphs = img and en.glyphs or nil
            else
                bucket.types[tname] = bucket.types[tname] or {}
                table.insert(bucket.types[tname], en)
            end
        end
    end

    local races = {}
    for race in pairs(by_race) do races[#races + 1] = race end
    table.sort(races)

    -- one file per world so results never mix
    local world = safe(dfhack.world.ReadWorldFolder)
        or safe(function() return dfhack.translation.translateName(df.global.world.world_data.name, true) end)
        or 'world'
    world = tostring(world):gsub('[^%w_%-]', '_')
    local path = ('%s/civ_symbols_%s.html'):format(dfhack.getDFPath(), world)

    local f = assert(io.open(path, 'w'))
    f:write(build_html(by_race, races, world, stats, civ_info), '\n')
    f:close()

    print(('civ_sym_dump: %d entities decoded, %d not decodable, %d races. Saved to %s')
        :format(stats.decoded, stats.missing, #races, path))
    if stats.missing > 0 then
        local ids = {}
        for id in pairs(stats.missing_chunks) do ids[#ids + 1] = tostring(id) end
        table.sort(ids)
        print('Missing symbol chunk(s): ' .. table.concat(ids, ', '))
    end
    return stats.missing
end

-- poll about once a second (in frames, so it also runs in menus)
local function watch(last_sig)
    dfhack.timeout(60, 'frames', function()
        if not dfhack.isWorldLoaded() then return end
        local sig = loaded_signature()
        if sig ~= last_sig then
            print('civ_sym_dump: new symbol data loaded, updating file...')
            if dump('') == 0 then
                print('civ_sym_dump: all symbols decoded, done watching.')
                return
            end
        end
        watch(sig)
    end)
end

-- ===========================================================================
-- PASTE GLYPH TABLE: put the whole content of glyph.txt between the two lines
-- below (save this file as UTF-8). Lines that do not start with a number are ignored.
-- ===========================================================================
GLYPH_TEXT = [==[
000  	Used for background tiles in the intro CMV and background tiles of interface screens
001 ☺	Civilian dwarves#, various status indicators
002 ☻	Military dwarves#
003 ♥	Dimple cups*
004 ♦	Cut gems, large gems
005 ♣	Quarry bush leaves*, blossoms*, various forest trees*
006 ♠	Broadleaf forest, various forest trees*, various leaf items*, Plump helmets*
007 •	Mined-out stone*, solid workshop tile for several workshops like the magma smelter, filled nest box building, river sources on world map, caves on world map, lairs on world map, moon on travel map, flower buds*
008 ◘	Solid workshop tile for several other workshops like the magma forge, tanner's shop, catapult cup, nest box tool*, empty nest box building, codices, dice
009 ○	Well, vermin colony, millstone, quern, vertical axle, fortress walls on travel map, sun behind clouds on travel map, castles on world map, monasteries on world map, creeping eye out of view (adventure mode)*, staring eyeball*, bubble bulb*
010 ◙	trunk interior$, forts on world map
011 ♂	Male sign, bags, various cephalopods#
012 ♀	Female sign, amulet
013 ♪	Ladles*, dancers dancing
014 ♫	Armor stands, playing instruments
015 ☼	Masterpiece quality tags, unmined gem cluster*, Rough gems and Raw glass, unmined bituminous coal*, mined bituminous coal*, currency symbol, spider webs, pond turtle*, sun, gear assemblies, paralyzed indicator, fireballs, bandit camps on travel map, towns on world map, night creature senses, artifact gem doors¢
016 ►	Head of Ballista arrow facing east, manta ray#
017 ◄	Head of Ballista arrow facing west
018 ↕	
019 ‼	Cages¢, on-fire tags, vertical bars
020 ¶	Mugs, drinking in-progress, largest forest retreats, cumulonimbus clouds on travel map, Highwood forests*
021 §	Restraints, whip vine*
022 ▬	Logs, hive tool*, hive building
023 ↨	Cedar forest*
024 ↑	Interface text (bridge direction), conifer forests, various forest trees*
025 ↓	Interface text (bridge direction), Various status indicators
026 →	Interface text (bridge direction)
027 ←	Interface text (bridge direction)
028 ∟	
029 ↔	Interface text (military patrol button)
030 ▲	Head of Ballista arrow facing north, ramp, track ramp up$, mountain on world map
031 ▼	Head of Ballista arrow facing south, ramp on level below, trackramp on level below$
032  	Spaces in text messages, Unexplored underground, black background on the title screen and interface menu
033 !	Text, various status icons, sound indicator in sneaking mode, tracks (footprints) in sneaking mode
034 "	Text, shrub*, various status icons, quotation marks, Carpenter's workshop tile, kobold out of view*, goblin out of view*, blizzard man out of view*, tracks (bent vegetation) in sneaking mode, various stones*, savanna, swamp, shrubland, marsh
035 #	Text, floor grates, various stones*, smoothed branches in elven forest retreats, labyrinths on travel map, towns on world map
036 $	Coins
037 %	Prepared meal, unexplored underground, screw pump in action, footprints in sneaking mode, various fruits*, various buds*, various stones*, Bismuthinite*, Floating guts#
038 &	Demons#
039 '	Text, rough floors, unexplored underground, various stones, one eyed creatures with GLOWTILE " (kobold, goblins, and blizzard in vanilla), various grasses*
040 (	Text, foreign object opening tag, tile in bowyer's workshop, waning moon on travel map
041 )	Text, foreign object closing tag, waxing moon on travel map
042 *	Interface text, superior quality tags, Unmined ore*, glowing pits, key reference, working gear assembly, gem floodgate, various stones*, chestnut fruit*, other fruits and flowers*, moving armies on quick travel map, towns on world map
043 +	Text, finely-crafted quality tags, Smooth/constructed floors, block/bar bridge or road, Bauxite*, injury indicator, towns on world map, mining designation
044 ,	Text, rough floors, Claystone*, unexplored underground, various grasses*
045 -	Text, well-crafted quality tags, Scepters, keyboard reference, various stones*, overlapping creatures animation
046 .	Text, rough floors, various stones*, unexplored underground, various grasses*
047 /	Text, weapons, bolts, Ballista tile, Pestle, overlapping creatures animation, stone axev0.43.01, active windmill blade
048 0	Text, coffins, tombs on world map
049 1	Text, designation priorities, adventurer mode conversation targets, fluids if SHOW_FLOW_AMOUNTS is YES in d_init.txt
050 2	Text, designation priorities, adventurer mode conversation targets, fluids if SHOW_FLOW_AMOUNTS is YES in d_init.txt
051 3	Text, designation priorities, adventurer mode conversation targets, fluids if SHOW_FLOW_AMOUNTS is YES in d_init.txt
052 4	Text, designation priorities, adventurer mode conversation targets, fluids if SHOW_FLOW_AMOUNTS is YES in d_init.txt
053 5	Text, designation priorities, adventurer mode conversation targets, fluids if SHOW_FLOW_AMOUNTS is YES in d_init.txt
054 6	Text, designation priorities, adventurer mode conversation targets, fluids if SHOW_FLOW_AMOUNTS is YES in d_init.txt
055 7	Text, designation priorities, adventurer mode conversation targets, fluids if SHOW_FLOW_AMOUNTS is YES in d_init.txt
056 8	Text, Fortress gates on travel map
057 9	Text
058 :	Interface text, strawberry*, prickle berry*, fisher berry*, sun berry*, snowstorms, underground shrubs*
059 ;	Interface text (command menu Movies key), Mason's workshop, Kitchen, Selenite*, twigs$
060 <	Interface text (trading screen "Less than 1 unit weight"), brackets around squad names, Stairs up, west move indicator (adventure mode)
061 =	Empty Stockpiles, hamlets on world map, various stones*, middle-left tile of Furnaces, up-right tile of Carpenter's workshop
062 >	Brackets around squad names, Stairs down, east move indicator (adventure mode)
063 ?	Text, various status icons
064 @	berserk dwarf#, adventurer#, dwarven merchants#, dwarven caravan guards#, dwarven diplomat#, adventurer's location on map
065 A	Text, various creatures#, Tile in Farm Workshop
066 B	Text, various creatures#
067 C	Text, various creatures#, construction designations
068 D	Text, various creatures#, Depot Access Display
069 E	Text, various creatures#
070 F	Text, various creatures#
071 G	Text, various creatures#
072 H	Text, various creatures#, high traffic designation
073 I	Text, various creatures#, support, Necromancer's tower on world map
074 J	Text, various creatures#
075 K	Text, various creatures#
076 L	Text, various creatures#, low traffic designation
077 M	Text, various creatures#
078 N	Text, various creatures#
079 O	Text, various creatures#, trade depot post, glass portal, Tile in Farm Workshop, column$, wall construction, full moon on travel map and dwarf mode, trunk$, staring eyeball*, bubble bulb*, windmill hub
080 P	Text, various creatures#
081 Q	Text
082 R	Text, various creatures#, restricted traffic designation
083 S	Text, various creatures#
084 T	Text, various creatures#
085 U	Text, various creatures#
086 V	Text, Badlands on map
087 W	Text, various creatures#, Depot Access Display
088 X	Text, wear tags, keyboard cursor, Bin¢, floodgate¢, shop post, building footprint, Depot Access Display, up/down stairs, Tile in Ashery, Archery target, various status indicators
089 Y	Text, Yak#, Yeti#
090 Z	Text, Sleep indicator
091 [	Text, Floor tile in workshops, Clothing, armor, item stack opening tag, moon on travel map, tracks (bootprints) in sneaking mode
092 \	Overlapping creatures animation, Ballista tile, helves*v0.43.01, active windmill blade
093 ]	Text, Floor tile in workshops and furnaces, item stack closing tag
094 ^	Trap, Alabaster*, Aluminum*, Volcano on world map, north move indicator (adventure mode), Mechanic Workshop center-south tile (in light cyan)
095 _	Text, Channel designation
096 `	Rough floors, unexplored underground*, various stones*, various grasses*
097 a	Text, various creatures#
098 b	Text, various creatures#
099 c	Text, various creatures#
100 d	Text, various creatures#
101 e	Text, various creatures#
102 f	Text, various creatures#
103 g	Text, various creatures#
104 h	Text, various creatures#
105 i	Text, various creatures#
106 j	Text, various creatures#
107 k	Text, various creatures#
108 l	Text, various creatures#
109 m	Text, various creatures#
110 n	Text, various creatures#, Hills on map
111 o	Text, various creatures#, Graphite*, well construction, bridge construction, millstone in action, vertical axle in action, floor tile in magma furnaces, staring eyeball*, bubble bulb*, winter melon*, watermelon*
112 p	Text, various creatures#
113 q	Text
114 r	Text, various creatures#
115 s	Text, various creatures#
116 t	Text, various creatures#
117 u	Text
118 v	Text, various creatures#, various stones*, south move indicator (adventure mode)
119 w	Text, various creatures#
120 x	Text, wear tags, Saltpeter*
121 y	Text
122 z	Text
123 {	Forbidden opening tag, tile in jeweler's workshop, vermin, purring maggot#
124 |	Talc*, pipe sections, overlapping creatures animation
125 }	Forbidden closing tag, vermin, purring maggot alternate*
126 ~	Unfinished rough stone road, flowing water, dirt road, farm plot under construction, sand, furrowed soil, blood smear, guts, Various creatures#, Magnetite*
127 ⌂	Animal trap, low mountains on world map, part of mechanic's workshop, trunk$
128 Ç	Text, Mechanisms
129 ü	Text
130 é	Text
131 â	Text
132 ä	Text, Angels
133 à	Text
134 å	Text
135 ç	Text, Totems
136 ê	Text
137 ë	Text, military elves
138 è	Text
139 ï	Text, Pedestal*
140 î	Text, Elven forest retreat
141 ì	Text
142 Ä	Text, Angels
143 Å	Text, Figurines, shrines on travel map
144 É	Text, altars
145 æ	Toys, hamlets on world map
146 Æ	Chests, quivers, backpacks, hamlets on world map
147 ô	Text, Cauldrons*
148 ö	Text, Rings
149 ò	Text, Unactivated levers, Various creatures#
150 û	Text, Buckets
151 ù	Text
152 ÿ	Text, Valley herb*
153 Ö	Bracelets, wheelbarrows*
154 Ü	Military humans
155 ¢	Hatch covers¢, musical instrument piecesv0.42.01
156 £	Various stones*, most unmined ores*,
157 ¥	Cave lobster*
158 ₧	Stepladder*, largest forest retreat ruins
159 ƒ	Rope reed*, splints, arrow bamboo*, golden bamboo*, hedge bamboo*	
160 á	Text
161 í	Text
162 ó	Text, Activated levers
163 ú	Text
164 ñ	Text, Bogeyman
165 Ñ	Night creatures
166 ª	dark pit ruins
167 º	Cloth, dark pit
168 ¿	Musical Instruments
169 ⌐	Withered plants*, wormy tendril*
170 ¬	wormy tendril*
171 ½	
172 ¼	Roc nests, roots$, branches$
173 ¡	Flask, waterskin, Pouch
174 «	Tail of Ballista arrow facing west, item with decoration tags
175 »	Tail of Ballista arrow facing east, item with decoration tags
176 ░	Partially dug rock, various flows (miasma, cave-in dust, steam, smoke, etc.), Fishery, fog on travel map, Semi-molten Rock, various stones*, various soils*, Workshop wall tiles (craftdwarf's, bowyer's, mason's, mechanic's, jeweler's, clothier's, kitchen, and leather works), fallen leaves, vermin swarm
177 ▒	Partially dug rock, various flows (miasma, cave-in dust, steam, smoke, etc.), side tiles for catapult, window, fog on travel map, various stones*, various kinds of soil*, fallen leaves, vermin swarm
178 ▓	Partially dug rock, various flows (miasma, cave-in dust, steam, smoke, etc.), floor tile for ice, tanner's shop, butcher's shop, Wagon body, fog on travel map, various kinds of stones*, various kinds of soil*, sky$, fallen leaves
179 │	Overworld rivers, well chain/rope, bolts in flight, rotating horizontal axles, branches$, active EW water wheel, active windmill blade, upright weapon trap
180 ┤	Overworld rivers, top-right tile for Loom, branches$, Glumprong forests*
181 ╡	Blood thorn trees*, bridges, catapult tile, tracks$
182 ╢	Branches$, east roller
183 ╖	Ends of smooth walls
184 ╕	Ends of smooth walls
185 ╣	Smooth/constructed walls, tracks$, trunk$
186 ║	Smooth/constructed walls, bridges, wooden doors¢, center catapult tile, center Ballista tile, axles, tracks$, fortress walls on travel map, trunk$, NS water wheel, windmill blade
187 ╗	Smooth/constructed walls, bridges, tracks$, trunk$
188 ╝	Smooth/constructed walls, bridges, tracks$, trunk$
189 ╜	Ends of smooth walls
190 ╛	Ends of smooth walls
191 ┐	Overworld rivers, branches$, northeast move indicator (adventure mode)
192 └	Overworld rivers/Roads, branches$, southwest move indicator (adventure mode)
193 ┴	Overworld rivers/Roads, branches$
194 ┬	Overworld rivers/Roads, crutches, branches$
195 ├	Overworld rivers/Roads, top-left tile for Loom, branches$
196 ─	Overworld rivers/Roads, bolts in flight, rotating axles, branches$, active NS water wheel, active windmill blade
197 ┼	Doors¢, overworld rivers/Roads, floor engraving in progress, branches$
198 ╞	Bridges, trees in winter, (un)dead trees*, Saguaro*, catapult tile, tracks$, branches$
199 ╟	branches$, west roller
200 ╚	Smooth/constructed walls, bridges, tracks$, fortress walls on travel map, trunk$
201 ╔	Smooth/constructed walls, bridges, tracks$, fortress walls on travel map, trunk$
202 ╩	Smooth/constructed walls, tracks$, trunk$
203 ╦	Smooth/constructed walls, tracks$, fortress walls on travel map, trunk$
204 ╠	Smooth/constructed walls, tracks$, trunk$
205 ═	Smooth/constructed walls, bridges, planted crops, center catapult tile, center Ballista tile, axles, tracks$, fortress walls on travel map, trunk$, EW water wheel, windmill blade
206 ╬	Smooth/constructed walls, bridges, fortifications, (flashing) wall engraving/fortifying in progress, tracks$, trunk$
207 ╧	Tail of Ballista arrow facing north, screw press building, branches$, south roller
208 ╨	Bridges, catapult tile, tracks$
209 ╤	Table, tail of Ballista arrow facing south, branches$, north roller
210 ╥	Chairs, bridges, catapult tile, farmer's workshop bottom-middle tile, tracks$
211 ╙	Ends of smooth walls
212 ╘	Ends of smooth walls
213 ╒	Ends of smooth walls
214 ╓	Ends of smooth walls
215 ╫	Wooden floodgates, bone floodgates, wall grates
216 ╪	Door designation
217 ┘	Overworld rivers, branches$, southeast move indicator (adventure mode)
218 ┌	Overworld rivers, branches$, northwest move indicator (adventure mode)
219 █	Interface window border, trade depot tile, ice wall and dig-designated tiles, Mist
220 ▄	Ballista tile, Siege engine parts
221 ▌	Ballista tile
222 ▐	Ballista tile
223 ▀	Ballista tile
224 α	Various fish#, top-center fishery tile, meat, altocumulus clouds on travel map
225 ß	Leather, cumulus clouds on travel map
226 Γ	Weight symbol, various forest trees, tropical forests
227 π	Cabinet, Display cases÷*, dark fortresses
228 Σ	Trap component
229 σ	Anvil, metalsmith's and magma forge bottom-middle tile, jugs*
230 µ	Crown, ruins on world map, shop signs (adventure mode)
231 τ	Tree sapling*, pig tail*, cave wheat*, Longland grass*, rat weed*, hide root*, muck root*, blade weed*, sliver barb*, shrubland, arrow bamboo*, golden bamboo*, hedge bamboo*
232 Φ	Sweet pod*, bloated tuber*, kobold bulb*, traction benches, (Large) pots*
233 Θ	Beds, Puddingstone*
234 Ω	Statues, dwarven cities on map, sea nettle jellyfish*
235 δ	Earrings, kennel tile
236 ∞	Boulder, dry brook, middle-right butcher's shop tile, various stones*, sea foam, images of clouds, fortress gates on travel map, honeycomb*, scrolls*v0.42.01
237 φ	Thread, loom bottom left tile, farmer's workshop bottom right tile
238 ε	Bowyer's workshop middle-right tile
239 ∩	Hills on world map, slab building
240 ≡	Bars, exceptional quality tags, activity zones, metal doors¢, floor bars, track stops, cirrus clouds on travel map, hamlets on world map, quire*v0.42.01, bookcase*÷v0.42.01
241 ±	Unfinished road
242 ≥	Debris (spent ammo, ballista bolts, and catapult stones), ashes, wormy tendril*
243 ≤	Debris (spent ammo, ballista bolts, and catapult stones), ashes, wormy tendril*
244 ⌠	swamps on world map, Willow forest/swamp*
245 ⌡	sheetsv0.42.01
246 ÷	Barrel¢, screw pump, upper left tile of still, center tile of ashery, upper left tile of kitchen, scroll rollers*v0.42.01, book binding*v0.42.01
247 ≈	Rough stone road or bridge, water, magma, snow, glob (fat/tallow), farm plot, furrowed soil, vomit, blood pools, sea foam, sand, various stones*
248 °	Sea foam, eggs, staring eyeball*, bubble bulb*, Bowl, Mortar, dark pits on world map
249 ∙	Vermin*, Boulders at lower elevation, trees at lower elevation, tundra on world map, move indicator frame 2 (adventure mode)
250 ·	Seeds, micro-vermin, open space, terrain at lower elevation, plants at lower elevation, tundra on world map, move indicator frame 1 (adventure mode)
251 √	Weapon racks, badlands in main map, check mark (selecting production materials, confirmed items on manager window)
252 ⁿ	Savanna, marsh, grassland, badlands
253 ²	Body parts, vermin remains
254 ■	Blocks, minecarts*÷, vaults on world map, human houses/shops on travel map, progress bars, move indicator frame 3 (adventure mode)
255  	

011 ♂ Cuttlefish Nautilus, Squid
015 ☼ Pond turtle
016 ► manta ray
037 % Floating guts
042 * Creepy crawler
064 @ Non-citizen dwarf in Fortress Mode, Adventurer in Adventure Mode
065 A Alligator, Alligator man, Anaconda, Anaconda man, Giant aardvark, Giant adder, Giant albatross, Giant alligator, Giant anaconda, Giant anole, Giant armadillo, Giant axolotl, Giant aye-aye
066 B Beak dog, Black bear, Black bear man, Blind cave bear, Giant badger, Giant barn owl, Giant bat, Giant beaver, Giant beetle, Giant black bear, Giant bluejay, Giant bobcat, Giant bushtit, Giant buzzard, Giant grizzly bear, Giant honey badger, Giant monarch butterfly, Giant polar bear, Giant sloth bear, Giant wild boar, Grizzly bear, Grizzly bear man, Polar bear, Polar bear man, Sloth bear, Sloth bear man, Wild boar, Wild boar man
067 C Bronze colossus, Cave crocodile, Centaur, Chimera, Coelacanth, Cow, Cyclops, Giant capuchin, Giant capybara, Giant cardinal, Giant cassowary, Giant cave swallow, Giant chameleon, Giant cheetah, Giant chinchilla, Giant chipmunk, Giant coati, Giant cockatiel, Giant cougar, Giant coyote, Giant crab, Giant crow, Giant cuttlefish, Giant horseshoe crab, Giant one-humped camel, Giant saltwater crocodile, Giant two-humped camel, Magma crab, One-humped camel, One-humped camel man, Saltwater crocodile, Saltwater crocodile man, Two-humped camel, Two-humped camel man, Voracious cave crawler
068 D Cave dragon, Deer, Donkey, Dragon, Draltha, Giant deer, Giant dingo, Giant dragonfly
069 E Elephant, Elephant man, Elk, Elk bird, Elk man, Emu, Emu man, Ettin, Giant eagle, Giant echidna, Giant elephant, Giant elk, Giant emu
070 F Giant firefly, Giant fly, Giant fox, Giant green tree frog
071 G Giant, Giant gazelle, Giant gila monster, Giant giraffe, Giant grackle, Giant grasshopper, Giant groundhog, Giant grouper, Giant leopard gecko, Giant mountain goat, Giraffe, Giraffe man, Gorilla, Green devourer, Griffon
072 H Giant hamster, Giant hare, Giant harp seal, Giant hedgehog, Giant hippo, Giant hornbill, Giant hyena, Harp seal, Hippo, Hippo man, Horse, Hydra
073 I Giant ibex, Giant iguana, Giant impala
074 J Giant jackal, Giant jaguar, Giant jumping spider, Jabberer, Jaguar, Jaguar man
075 K Giant kakapo, Giant kangaroo, Giant kea, Giant kestrel, Giant king cobra, Giant kingsnake, Giant kiwi, Giant koala, Kangaroo, Kangaroo man
076 L Giant gray langur, Giant leech, Giant leopard, Giant leopard seal, Giant lion, Giant lion tamarin, Giant lizard, Giant loon, Giant lorikeet, Giant louse, Giant lynx, Giant masked lovebird, Giant peach-faced lovebird, Leopard seal, Leopard seal man, Lion, Lion man, Llama
077 M Amethyst man, Blizzard man, Blood man, Fire man, Gabbro man, Giant hoary marmot, Giant magpie, Giant mandrill, Giant mantis, Giant mink, Giant mongoose, Giant monitor lizard, Giant moose, Giant mosquito, Giant moth, Giant muskox, Giant rhesus macaque, Giant spider monkey, Iron man, Magma man, Merperson, Minotaur, Molemarian, Monitor lizard, Monitor lizard man, Moose, Moose man, Mud man, Mule, Muskox, Muskox man, Sea monster
078 N Giant narwhal, Giant nautilus, Narwhal, Narwhal man, Nightwing
079 O Blind cave ogre, Giant great horned owl, Giant ocelot, Giant octopus, Giant olm, Giant opossum, Giant orca, Giant oriole, Giant osprey, Giant ostrich, Giant otter, Giant snowy owl, Ogre, Orangutan, Orca, Orca man, Ostrich, Ostrich man
080 P Giant grey parrot, Giant pangolin, Giant parakeet, Giant penguin, Giant peregrine falcon, Giant platypus, Giant porcupine, Giant puffin, Giant red panda, Gigantic panda, Panda, Panda man
082 R Giant raccoon, Giant rat, Giant raven, Giant red-winged blackbird, Giant rhinoceros, Giant roach, Reacher, Reindeer, Rhinoceros, Rhinoceros man, Roc, Rutherer
083 S Basking shark, Blue shark, Bull shark, Elephant seal, Elephant seal man, Giant bark scorpion, Giant black mamba, Giant brown recluse spider, Giant bushmaster, Giant cave spider, Giant copperhead snake, Giant elephant seal, Giant flying squirrel, Giant gray squirrel, Giant moon snail, Giant python, Giant rattlesnake, Giant red squirrel, Giant skink, Giant skunk, Giant sloth, Giant slug, Giant snail, Giant sparrow, Giant sponge, Giant stoat, Giant swan, Giant white stork, Gigantic squid, Great white shark, Hammerhead shark, Longfin mako shark, Nurse shark, Python, Python man, Sasquatch, Sea serpent, Shortfin mako shark, Spotted wobbegong, Tiger shark
084 T Alligator snapping turtle, Giant cave toad, Giant desert tortoise, Giant pond turtle, Giant snapping turtle, Giant tapir, Giant thrips, Giant tick, Giant tiger, Giant toad, Giant tortoise, Giant tortoise man, Gigantic tortoise, Tapir, Tapir man, Tiger, Tiger man, Troll
085 U Human, Unicorn
086 V Giant vulture
087 W Giant earthworm, Giant sperm whale, Giant walrus, Giant warthog, Giant weasel, Giant wolf, Giant wolverine, Giant wombat, Giant wren, Sperm whale, Sperm whale man, Wagon, Walrus, Walrus man, Warthog, Warthog man, Water buffalo, Whale shark
089 Y Yak, Yeti
097 a Aardvark, Aardvark man, Adder, Adder man, Albatross, Albatross man, Alpaca, Amphibian man, Anole man, Antman, Armadillo, Armadillo man, Axolotl man, Aye-aye, Aye-aye man
098 b Badger, Badger man, Barn owl, Barn owl man, Bat man, Beaver, Beaver man, Beetle man, Bluejay man, Bobcat, Bobcat man, Bonobo, Bugbat, Bushtit man, Buzzard, Buzzard man, Foul blendec, Great barracuda, Honey badger, Honey badger man, Monarch butterfly man
099 c Capuchin, Capuchin man, Capybara, Capybara man, Cardinal man, Cassowary, Cassowary man, Cat, Cavy, Chameleon man, Cheetah, Cheetah man, Chicken, Chimpanzee, Chinchilla, Chinchilla man, Chipmunk man, Coati, Coati man, Cockatiel man, Cougar, Cougar man, Coyote, Coyote man, Crab, Crab man, Crow man, Crundle, Cuttlefish man, Horseshoe crab, Horseshoe crab man
100 d Damselfly man, Deer man, Dingo, Dingo man, Dog, Dragonfly man, Drunian, Duck
101 e Creeping eye, Eagle, Eagle man, Echidna, Echidna man, Elf
102 f Cave fish man, Cave floater, Firefly man, Fly man, Fox, Fox man, Green tree frog man
103 g Bilou, Black-crested gibbon, Black-handed gibbon, Dark gnome, Gazelle, Gazelle man, Gila monster, Gila monster man, Goat, Goblin, Goose, Gorlak, Grackle man, Grasshopper man, Gray gibbon, Gremlin, Grimeling, Groundhog, Groundhog man, Guineafowl, Leopard gecko man, Longnose gar, Mountain gnome, Mountain goat, Mountain goat man, Pileated gibbon, Silvery gibbon, White-browed gibbon, White-handed gibbon
104 h Hamster man, Hare, Hare man, Harp seal man, Harpy, Hedgehog man, Hornbill, Hornbill man, Hungry head, Hyena, Hyena man
105 i Fire imp, Ibex, Ibex man, Iguana, Iguana man, Impala, Impala man
106 j Jackal, Jackal man, Jumping spider man
107 k Kakapo, Kakapo man, Kea, Kea man, Kestrel, Kestrel man, King cobra, King cobra man, Kingsnake, Kingsnake man, Kiwi, Kiwi man, Koala, Koala man, Kobold
108 l Gray langur, Gray langur man, Leech man, Leopard, Leopard man, Lion tamarin man, Lizard man, Loon, Loon man, Lorikeet man, Louse man, Lynx, Lynx man, Masked lovebird man, Peach-faced lovebird man
109 m Giant mole, Hoary marmot, Hoary marmot man, Magpie man, Mandrill, Mandrill man, Manera, Mantis man, Mink, Mink man, Mongoose, Mongoose man, Mosquito man, Moth man, Mussel, Plump helmet man, Rhesus macaque, Rhesus macaque man, Spider monkey, Spider monkey man
110 n Naked mole dog, Nautilus man
111 o Cave blob, Flesh ball, Great horned owl, Great horned owl man, Ocelot, Ocelot man, Octopus, Octopus man, Olm man, Opossum, Opossum man, Oriole man, Osprey, Osprey man, Otter man, Oyster, River otter, Sea otter, Snowy owl, Snowy owl man
112 p Blue peafowl, Emperor penguin, Grey parrot, Grey parrot man, Little penguin, Pangolin, Pangolin man, Parakeet man, Penguin, Penguin man, Peregrine falcon, Peregrine falcon man, Pig, Platypus, Platypus man, Pond grabber, Porcupine, Porcupine man, Puffin, Puffin man, Red panda, Red panda man
114 r Large rat, Rabbit, Raccoon, Raccoon man, Rat man, Raven, Raven man, Red-winged blackbird man, Reptile man, Roach man, Rodent man
115 s Angelshark, Bark scorpion man, Black mamba, Black mamba man, Blacktip reef shark, Brown recluse spider man, Bushmaster, Bushmaster man, Cave swallow man, Copperhead snake, Copperhead snake man, Flying squirrel man, Frill shark, Gray squirrel man, Helmet snake, Moon snail man, Rattlesnake, Rattlesnake man, Red squirrel man, Satyr, Serpent man, Sheep, Siamang, Skink man, Skunk, Skunk man, Sloth, Sloth man, Slug man, Snail man, Sparrow man, Spiny dogfish, Sponge, Sponge man, Squid man, Stoat, Stoat man, Strangler, Swan, Swan man, White stork, White stork man, Whitetip reef shark
116 t Common snapping turtle, Desert tortoise, Desert tortoise man, Pond turtle man, Snapping turtle man, Thrips man, Tick man, Toad man, Troglodyte, Turkey
118 v Vulture, Vulture man
119 w Ice wolf, Weasel, Weasel man, Wolf, Wolf man, Wolverine, Wolverine man, Wombat, Wombat man, Worm man, Wren man
123 { Purring maggot
126 ~ Brook lamprey, Conger eel, Hagfish, Knuckle worm, Leech, Sea lamprey, Slug, Worm
149 ò Bat ray, Common skate, Stingray, Thornback ray
157 ¥ Cave lobster
224 α Anchovy, Banded knifefish, Black bullhead, Bluefin tuna, Bluefish, Brown bullhead, Carp, Cave fish, Char, Clown loach, Clownfish, Cod, Flounder, Glasseye, Guppy, Hake, Halibut, Herring, Lungfish, Mackerel, Marlin, Milkfish, Ocean sunfish, Opah, Perch, Pike, Rainbow trout, Sailfin molly, Salmon, Seahorse, Shad, Sole, Spotted ratfish, Steelhead trout, Sturgeon, Swordfish, Tigerfish, White-spotted puffer, Yellow bullhead
234 Ω Sea nettle jellyfish

249 ∙ Anole, Ant, Axolotl, Bark scorpion, Bat, Blue jay, Brown recluse spider, Bushtit, Cap hopper, Cardinal, Cave spider, Cave swallow, Chameleon, Chipmunk, Cockatiel, Crow, Damselfly, Demon rat, Dragonfly, Fairy, Fire snake, Firefly, Fluffy wambler, Flying squirrel, Fox squirrel, Giant damselfly, Grackle, Gray squirrel, Green tree frog, Hamster, Hedgehog, Large roach, Leopard gecko, Lion tamarin, Lizard, Lorikeet, Magpie, Masked lovebird, Moghopper, Moon snail, Olm, Oriole, Parakeet, Peach-faced lovebird, Phantom spider, Rat, Red squirrel, Red-winged blackbird, Skink, Snail, Sparrow, Toad, Two-legged rhino lizard, Wren
250 · Acorn fly, Beetle, Blood gnat, Bumblebee, Fly, Grasshopper, Honey bee, Jumping spider, Louse, Mantis, Mosquito, Pixie, Termite, Thrips, Tick
]==]
-- ===========================================================================

glyph_debug = ((({...})[1] or ''):lower() == 'glyphdebug')
local missing = dump((({...})[1] or ''):lower())
if missing > 0 then
    print('civ_sym_dump: watching for symbol chunks to load; the file updates automatically.')
    watch(loaded_signature())
end

-- END OF civ_sym_dump.lua
