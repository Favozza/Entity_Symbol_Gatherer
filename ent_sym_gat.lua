-- ent_sym_gat: dump all civilization and entity symbols of the loaded world to a civ_symbols_<worldname>.html file in the DF folder
-- Usage: Embark -> Smooth stone wall/floor -> Detail -> Specify image -> Existing image -> Click on DFHack -> ent_sym_gat

-- Glyph table: paste it at the END of this file (search for "PASTE GLYPH TABLE").
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

-- lookup keys for the glyph table: full name, last word (usually the noun), then the other words
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
        
        -- Check if the creature name or raw token contains "were" (werebeast)
        local is_werebeast = false
        if cr and cr.creature_id and cr.creature_id:lower():find('were') then
            is_werebeast = true
        elseif nm and nm:lower():find('were') then
            is_werebeast = true
        end

        if is_werebeast then
            add_keys(keys, nm)
            -- Return a custom description and force the glyph Ñ by including a unique key or handling it in glyph_for
            return (nm or ('werebeast#' .. e.race)) .. cnt, { 'Ñ', 'werebeast', nm }
        end

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
        local sh = safe(function() return df.global.world.raws.descriptors.shapes[e.shape_id] end)
        local nm = sh and safe(function() return sh.name end)
        add_keys(keys, nm)
        return (nm and ('shape: ' .. nm) or ('shape#' .. e.shape_id)) .. cnt, keys
    end
    return t, keys
end

-- glyph table: lines like "001 ☺<TAB>Civilian dwarves#, ..." (ID, space, glyph, TAB, usage), pasted at
-- the end of the script. The older "ID<TAB>Glyph<TAB>Usage" layout is accepted too.
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
                rest = rest:gsub('^ +', '')
                if rest:sub(1, 1) ~= '\t' then
                    glyph = rest:match('^' .. utf8.charpattern)
                    usage = glyph and rest:sub(#glyph + 1):gsub('^%s+', '')
                end
            end
            if glyph and glyph ~= '' then
                usage = usage:lower()
                local items, heads = {}, {}
                for item in usage:gmatch('[^,;]+') do
                    item = item:gsub('%b()', ''):gsub('^[%s%p]+', ''):gsub('[%s%p]+$', '')
                    if item ~= '' then
                        items[item] = true
                        heads[item:match('(%S+)$')] = true
                    end
                end
                rows[#rows + 1] = { id = id, glyph = glyph, usage = usage, items = items, heads = heads }
            end
        end
    end
    return rows, numbered
end

local function load_glyphs()
    local rows, numbered = parse_glyph_lines(GLYPH_TEXT:gmatch('[^\n]+'))
    if #rows > 0 then
        return rows
    end
    print(string.rep('-', 60))
    print('  [WARNING] Entity_Symbol_Gatherer: No glyph table found at the end of script.')
    print('            The glyph column will appear empty.')
    print(string.rep('-', 60))
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

local glyph_debug = false

local function glyph_for(keys)
    -- Check if any of the keys indicate a werebeast
    for _, k in ipairs(keys) do
        if type(k) == 'string' and (k:find('were') or k == 'Ñ') then
            return 'Ñ'
        end
    end
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
                    if r.items[form] then score = 0 break end
                end
                if not score then
                    for _, form in ipairs(forms) do
                        if r.heads[form] then score = 1000 break end
                    end
                end
                if not score then
                    for _, pat in ipairs(pats) do
                        local pos = r.usage:find(pat)
                        if pos and (not score or 2000 + pos < score) then score = 2000 + pos end
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
                    print(('ent_sym_gat glyph: "%s" -> %s  (line %s: %s)'):format(k, hit.glyph, hit.id, hit.usage:sub(1, 60)))
                else
                    print(('ent_sym_gat glyph: "%s" -> no match'):format(k))
                end
            end
        end
        if hit then return hit.glyph end
    end
    return '–'
end

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

local function entity_type_name(ent)
    local nm = safe(function() return df.historical_entity_type[ent.type] end)
    return nm or ('type#' .. tostring(ent.type))
end

local function find_parent_civ_name(ent, civ_info)
    for _, link in ipairs(ent.entity_links) do
        local ci = civ_info[link.target]
        if ci then return ci.name end
    end
    return "Independent"
end

-- ---------------------------------------------------------------------------
-- Startup Banner Integration
-- ---------------------------------------------------------------------------
print(string.rep('=', 60))
print('  Entity Symbol Gatherer: Search and find all the symbols')
print(string.rep('=', 60))

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
button[aria-pressed="true"]{border-color:var(--accent)}
:focus-visible{outline:2px solid var(--accent);outline-offset:2px}
main{max-width:92rem;margin:0 auto;padding:1.25rem}
.notice{color:var(--warn);border:1px solid var(--warn);border-radius:3px;
  padding:.6rem .9rem;margin-bottom:1rem;font-size:.85rem}
nav.races{display:flex;flex-wrap:wrap;gap:.4rem;margin-bottom:1.25rem}
nav.races a{color:var(--accent);border:1px solid var(--line);padding:.1rem .6rem;
  border-radius:3px;text-decoration:none;font-size:.82rem}
nav.races a:hover{border-color:var(--accent)}
h2.worldname{font-size:1.4rem;margin:0 0 .5rem;font-weight:700}
.note{margin:0 0 1.25rem;padding:.8rem 1rem;border:1px solid var(--line);border-radius:3px;
  color:var(--ink);font-size:.88rem}
.note h2{font-size:1.1rem;margin:0 0 .5rem;font-weight:700}
.note p{margin:.5rem 0 0}
.note .orange{color:#ff8c1a}
.note code{background:#111;border:1px solid var(--line);border-radius:3px;padding:0 .3rem}
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
/* a compact table: every column is as wide as its longest entry (the rows are "display:contents") */
ul.entries{list-style:none;margin:0;padding:0;display:grid;grid-template-columns:repeat(4,max-content);
  column-gap:1rem;justify-content:start;max-width:100%;overflow-x:auto}
ul.entries.five{grid-template-columns:repeat(5,max-content)}
li.entry,li.colhead{display:contents}
li.entry>span,li.colhead>span{padding:.2rem 0;border-bottom:1px dotted var(--line);white-space:nowrap}
li.colhead>span{color:var(--muted);font-size:.72rem;text-transform:uppercase;letter-spacing:.08em;
  border-bottom:1px solid var(--line)}
li.entry .name{font-weight:700;color:var(--ink)}
li.entry .sym{font-size:.82rem;color:var(--ink)}
li.entry .gl{font-size:.95rem;letter-spacing:.15em;color:var(--ink)}
li.entry.missing .sym{color:var(--warn)}
li.entry.four .site{font-weight:700}
li.entry.four .name{font-weight:400}
summary .gl{font-size:.95rem;letter-spacing:.15em}
li.entry .sn{font-size:.82rem}
summary .sn{color:var(--muted);font-size:.85rem}
.hidden{display:none!important}
footer{color:var(--muted);font-size:.78rem;text-align:center;padding:1rem}
@media (max-width:600px){input[type=search]{min-width:0;width:100%}header.top .tools{margin-left:0;width:100%}}
]]

local JS = [[
(function(){
  var q=document.getElementById('q');
  var btn=document.getElementById('decoded');
  var only=false; // true = hide everything whose symbol could not be decoded
  var entries=[].slice.call(document.querySelectorAll('li.entry'));
  var civs=[].slice.call(document.querySelectorAll('details.civ'));
  var races=[].slice.call(document.querySelectorAll('section.race'));
  var groups=[].slice.call(document.querySelectorAll('.typegroup'));
  function filter(){
    var s=q.value.trim().toLowerCase();
    entries.forEach(function(li){
      var hide=(s&&li.textContent.toLowerCase().indexOf(s)<0)||(only&&li.classList.contains('missing'));
      li.classList.toggle('hidden',!!hide);
    });
    groups.forEach(function(g){
      g.classList.toggle('hidden', !g.querySelector('li.entry:not(.hidden)'));
    });
    civs.forEach(function(d){
      var head=(d.querySelector('summary').textContent||'').toLowerCase();
      var vis=d.querySelector('li.entry:not(.hidden)');
      var hide=false;
      if(s&&!(vis||head.indexOf(s)>=0)) hide=true;
      // a civ whose own symbol is undecoded (or that has none) stays only while something inside is shown
      if(only&&!vis&&(d.querySelector('summary .sym.missing')||!d.querySelector('summary .sym'))) hide=true;
      d.classList.toggle('hidden',hide);
      if(s&&!hide) d.open=true;
    });
    races.forEach(function(r){
      r.classList.toggle('hidden', (s||only)&&!r.querySelector('details.civ:not(.hidden)'));
    });
  }
  q.addEventListener('input',filter);
  btn.onclick=function(){
    only=!only;
    btn.setAttribute('aria-pressed',only?'true':'false');
    btn.textContent=only?'Show undecoded':'Hide undecoded';
    filter();
  };
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

-- site types that get the "@" marker when they are not owned by a civ of the list
-- (compared without case, spaces or underscores)
local FALLEN_TYPES = {
    town = true, hamlet = true, mountainhalls = true, hillocks = true,
    forestretreat = true, darkfortress = true, darkpits = true,
}
local function is_settlement(type_name)
    return FALLEN_TYPES[(tostring(type_name):lower():gsub('[^%a]', ''))] or false
end

-- civ_info: [entity id] = { name = ..., symbol = ... (may be nil) }
local function build_map_html(civ_info, occupier)
    occupier = occupier or {}
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

    -- mountain peaks, indexed by "x,y": true = volcano (drawn without a tooltip)
    local peaks = {}
    for _, p in ipairs(wd.mountain_peaks) do
        peaks[p.pos.x .. ',' .. p.pos.y] = safe(function() return p.flags.is_volcano end) and true or false
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

    -- A site counts for a civ only through its current owner. A site without one is drawn as "@",
    -- but only if it is a settlement (town, hamlet, mountain halls, ...); other types are skipped.
    local sites_at, civ_sites = {}, {}
    for _, s in ipairs(wd.sites) do
        -- current owner: the site's own, else the government living there (see "occupier" in dump())
        local owner_id = s.cur_owner_id
        if not owner_id or owner_id < 0 then owner_id = occupier[s.id] end
        local civ = to_civ(owner_id)
        local stype = safe(function() return df.world_site_type[s.type] end) or 'Site'
        if civ then civ_sites[civ] = (civ_sites[civ] or 0) + 1 end
        if civ or is_settlement(stype) then
            local sname = safe(dfhack.translation.translateName, s.name, true)
            if not sname or sname == '' then sname = 'Unnamed site' end
            -- owner = name of the government when there is one but no civ ("Fallen to"); nil = "Ruin"
            local owner
            if owner_id and owner_id >= 0 then
                owner = safe(function()
                    return dfhack.translation.translateName(df.historical_entity.find(owner_id).name, true)
                end)
                if not owner or owner == '' then owner = '?' end
            end
            local key = s.pos.x .. ',' .. s.pos.y
            sites_at[key] = sites_at[key] or {}
            table.insert(sites_at[key], { civ = civ, name = sname, type = stype, owner = owner })
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
    -- marker = the civ's own glyph (first one found in the glyph table)
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
            local peak = peaks[x .. ',' .. y]  -- nil = no peak, false = peak, true = volcano
            local st = sites_at[x .. ',' .. y]
            if st then
                emit()
                local lines, owned, marker = {}, nil, '@'  -- @ = ruin, ? = fallen to a government without civ
                for _, s in ipairs(st) do
                    if s.civ then
                        local ci = civ_info[s.civ]
                        lines[#lines + 1] = ('%s (%s) - %s%s'):format(s.name, s.type, ci.name,
                            ci.symbol and (' - symbol: ' .. ci.symbol) or '')
                        owned = owned or s
                    else
                        lines[#lines + 1] = ('%s (%s) - %s'):format(
                            s.name, s.type, s.owner and ('Fallen to ' .. s.owner) or 'Ruin')
                        if s.owner then marker = '?' end
                    end
                end
                local title = table.concat(lines, '\n')
                out[#out + 1] = ('<i style="color:%s" title="%s">%s</i>'):format(
                    owned and civ_color[owned.civ] or '#fff', html_plain(safe(dfhack.df2utf, title) or title),
                    owned and html_plain(civ_shape[owned.civ]) or marker)
            elseif peak ~= nil then
                emit()
                local key = peak and 'volcano' or 'mountain_peak'
                used[key] = true
                out[#out + 1] = ('<i class="t-%s">%s</i>'):format(key, TERRAIN[key][1])
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
        add('<div class="racelegend"><span class="rl">Symbol for Civilizations with absent Glyph:</span>')
        for _, it in ipairs(items) do
            add(('<span><b>%s</b>%s</span>'):format(html_plain(it[1]), html_plain(it[2])))
        end
        add('</div>')
    end
    add('<div class="racelegend"><span><b>@</b>Ruin</span>'
        .. '<span><b>?</b>Fallen to a government without a civilization</span></div>')
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

-- with_site: SiteGovernment rows get the site they belong to as a first column
local function entry_html(en, with_site)
    local cls = (en.missing and 'entry missing' or 'entry') .. (with_site and ' four' or '')
    local site = with_site and ('<span class="site">%s</span>'):format(esc(en.site or '-')) or ''
    return ('<li class="%s">%s<span class="name">%s</span><span class="sym">%s</span><span class="gl">%s</span>'
        .. '<span class="sn">%s</span></li>')
        :format(cls, site, esc(en.name), esc(en.symbol), html_plain(en.glyphs or ''), esc(en.symbol_name or ''))
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
    add('<button id="decoded" type="button" aria-pressed="false">Hide undecoded</button>')
    add('</div></header><main>')

    -- introduction, followed by the world name as the map title
    add('<div class="note"><h2>Entity Symbol Gatherer</h2>')
    add('<p>In Dwarf Fortress, intelligent creatures can form organized groups called '
        .. 'Entities. These include civilizations, site governments, religions, guilds, '
        .. 'nomadic groups, and more. Each Entity is procedurally assigned a name '
        .. '(e.g. "The Fair Kingdom"), a symbol (e.g. a coin), a symbol name '
        .. '(e.g. "The Strong Flower"), and a glyph (e.g. "$").</p>')

    if stats.missing > 0 then
        add(('<p><strong>Some symbols could not be decoded.</strong> '
            .. 'This means that not all symbol images were available in memory during '
            .. 'your game session. Dwarf Fortress loads only a portion of its symbol '
            .. 'images (art image chunks) at a time, so this script can only retrieve '
            .. 'symbols from chunks that are currently loaded. Entities with unavailable '
            .. 'symbols are listed as "symbol chunk # not loaded". '
            .. 'Currently, %d symbols are affected. Use the "Hide undecoded" button '
            .. 'to hide these entries in the list.</p>'
            .. '<p><span class="orange"><strong>How to find missing symbols:</strong> '
            .. 'Some undecoded symbols, particularly those belonging to civilizations, '
            .. 'may become available after embarking with a different civilization and '
            .. 'running the engraving procedure again. You can also use the DFHack command '
            .. '<code>embark-anyone</code> to embark with a dead civilization '
            .. 'or a newly generated goblin civilizations to gather their symbols. '
            .. 'In the meantime, do not delete the <code>.cache</code> file.</span></p>'):format(stats.missing))
    end

    add('</div>')

    local title = safe(dfhack.translation.translateName, df.global.world.world_data.name, true)
    if not title or title == '' then title = world end
    add(('<h2 class="worldname">%s</h2>'):format(esc(title)))

    local ok, map_html, civ_color = pcall(build_map_html, civ_info, stats.occupier)
    if ok then
        add(map_html)
    else
        add('<div class="notice">The physical map could not be built: ' .. html_plain(map_html) .. '</div>')
        print('ent_sym_gat: map error: ' .. tostring(map_html))
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
                    if g.civ.symbol_name then
                        add(('<span class="sn">%s</span>'):format(esc(g.civ.symbol_name)))
                    end
                end
            end
            add(('<span class="n">%d</span></summary><div class="civ-body">'):format(n))

            local tnames = {}
            for tname in pairs(g.types) do tnames[#tnames + 1] = tname end
            table.sort(tnames)

            for _, tname in ipairs(tnames) do
                local list = g.types[tname]
                local with_site = tname == 'SiteGovernment'
                table.sort(list, function(a, b)
                    if with_site and a.site ~= b.site then  -- governments without a site go last
                        if not a.site then return false end
                        if not b.site then return true end
                        return a.site < b.site
                    end
                    if a.name ~= b.name then return a.name < b.name end
                    return a.symbol < b.symbol
                end)
                add(('<div class="typegroup"><h3>%s (%d)</h3><ul class="entries%s">'):format(
                    esc(tname), #list, with_site and ' five' or ''))
                add(with_site
                    and '<li class="colhead four"><span>Site</span><span>Name</span><span>Symbol</span><span>Glyph</span><span>Symbol Name</span></li>'
                    or '<li class="colhead"><span>Name</span><span>Symbol</span><span>Glyph</span><span>Symbol Name</span></li>')
                for _, en in ipairs(list) do add(entry_html(en, with_site)) end
                add('</ul></div>')
            end
            add('</div></details>')
        end
        add('</section>')
    end

    add('</main>')
    add(('<footer>Generated by ent_sym_gat (%s)</footer>'):format(esc(os.date('%Y-%m-%d %H:%M'))))
    add('<script>' .. JS .. '</script></body></html>')
    return table.concat(h, '\n')
end

-- ---------------------------------------------------------------------------
-- dump
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- cache of decoded symbols
-- DF loads a symbol image only while the civilizations that use it are in contact with the player's
-- civilization, so each session shows a different subset. Every decoded symbol is therefore saved in
-- civ_symbols_<world>.cache and reused in later sessions, so the results add up over sessions.
-- ---------------------------------------------------------------------------

-- one line per entity (tab separated): id, chunk, sub, symbol name, number of elements, then for each
-- element: text, (unused), glyph lookup keys (separated by |)
local function clean(s) return (tostring(s or ''):gsub('[\t\r\n|]', ' ')) end

local function cache_save(path, sig, cache)
    local f = io.open(path, 'w')
    if not f then return end
    f:write('#world\t', sig, '\n')
    local ids = {}
    for id in pairs(cache) do ids[#ids + 1] = id end
    table.sort(ids)
    for _, id in ipairs(ids) do
        local rec = cache[id]
        local fields = { id, rec.chunk, rec.sub, clean(rec.name), #rec.elems }
        for _, e in ipairs(rec.elems) do
            local keys = {}
            for _, k in ipairs(e.keys) do keys[#keys + 1] = clean(k) end
            fields[#fields + 1] = clean(e.text)
            fields[#fields + 1] = ''  -- unused column, kept so older cache files still load
            fields[#fields + 1] = table.concat(keys, '|')
        end
        f:write(table.concat(fields, '\t'), '\n')
    end
    f:close()
end

-- returns {entity id = record}; a cache of another world (different signature) is ignored
local function cache_load(path, sig)
    local cache = {}
    local f = io.open(path, 'r')
    if not f then return cache end
    if f:read('*l') ~= '#world\t' .. sig then f:close() return cache end
    for line in f:lines() do
        local fields = {}
        for field in (line .. '\t'):gmatch('([^\t]*)\t') do fields[#fields + 1] = field end
        local id, chunk, sub, n = tonumber(fields[1]), tonumber(fields[2]), tonumber(fields[3]), tonumber(fields[5])
        if id and chunk and sub and n then
            local elems = {}
            for k = 0, n - 1 do
                local text, keystr = fields[6 + 3 * k], fields[8 + 3 * k]  -- fields[7 + 3 * k] is unused
                if not (text and keystr) then elems = nil break end
                local keys = {}
                for key in (keystr .. '|'):gmatch('([^|]*)|') do
                    if key ~= '' then keys[#keys + 1] = key end
                end
                elems[#elems + 1] = { text = text, keys = keys }
            end
            if elems then
                cache[id] = { chunk = chunk, sub = sub, name = fields[4] ~= '' and fields[4] or nil, elems = elems }
            end
        end
    end
    f:close()
    return cache
end

-- symbol text and glyphs of a list of elements (the glyphs are looked up again each time,
-- so a changed glyph table also applies to cached symbols)
local function render_symbol(elems)
    local parts, glyphs = {}, {}
    for _, e in ipairs(elems) do
        parts[#parts + 1] = e.text
        glyphs[#glyphs + 1] = glyph_for(e.keys)
    end
    return table.concat(parts, ' + '), table.concat(glyphs, ' ')
end

-- writes the file, returns number of entities that could not be decoded
local function dump()
    if glyph_rows == nil then glyph_rows = load_glyphs() end
    local by_race = {}
    local stats = { decoded = 0, missing = 0, cached = 0, civs = 0, missing_chunks = {} }

    -- one file per world so results never mix
    local world = safe(dfhack.world.ReadWorldFolder)
        or safe(function() return dfhack.translation.translateName(df.global.world.world_data.name, true) end)
        or 'world'
    world = tostring(world):gsub('[^%w_%-]', '_')
    local path = ('%s/civ_symbols_%s.html'):format(dfhack.getDFPath(), world)
    local cache_path = ('%s/civ_symbols_%s.cache'):format(dfhack.getDFPath(), world)
    -- save folders such as "region1" are reused by new worlds, so the cache also checks the world's name and size
    local wd = df.global.world.world_data
    local sig = clean(('%s/%s/%dx%d'):format(
        safe(dfhack.translation.translateName, wd.name, true) or '?',
        safe(dfhack.translation.translateName, wd.name, false) or '?', wd.world_width, wd.world_height))
    local cache = cache_load(cache_path, sig)

    -- all named civilizations by entity id (symbol/glyphs are filled in below)
    local civ_info = {}
    for _, ent in ipairs(df.global.world.entities.all) do
        if ent.type == df.historical_entity_type.Civilization and ent.name.has_name then
            civ_info[ent.id] = { name = dfhack.translation.translateName(ent.name, true), race = civ_race_name(ent) }
        end
    end

    -- Some sites have no cur_owner_id although a government rules them. That government is only stored on its
    -- own side, as a site link whose flags contain "residence" (former governments have it as former_flag).
    -- site id -> that government (only if unique)
    local occupier, ambiguous = {}, {}
    for _, ent in ipairs(df.global.world.entities.all) do
        if ent.type == df.historical_entity_type.SiteGovernment then
            for _, link in ipairs(safe(function() return ent.site_links end) or {}) do
                if safe(function() return link.flags.residence end) then
                    if occupier[link.target] and occupier[link.target] ~= ent.id then
                        ambiguous[link.target] = true
                    else
                        occupier[link.target] = ent.id
                    end
                end
            end
        end
    end
    for id in pairs(ambiguous) do occupier[id] = nil end
    stats.occupier = occupier

    -- the site each site government belongs to: the site it currently owns (or occupies)
    local site_of = {}
    for _, site in ipairs(df.global.world.world_data.sites) do
        local owner = site.cur_owner_id
        if not owner or owner < 0 then owner = occupier[site.id] end
        if owner and owner >= 0 and not site_of[owner] then
            local nm = safe(dfhack.translation.translateName, site.name, true)
            site_of[owner] = (nm and nm ~= '') and nm or 'Unnamed site'
        end
    end
    -- only the site a government currently owns counts: its site_links also list claimed and
    -- former sites, which gave several governments the same (wrong) site
    for _, ent in ipairs(df.global.world.entities.all) do
        if #ent.resources.art_image_ids > 0 and ent.name.has_name then
            local cname = dfhack.translation.translateName(ent.name, true)
            local race = civ_race_name(ent)
            local tname = entity_type_name(ent)

            -- governments that rule no site are left out of the list
            local site = tname == 'SiteGovernment' and site_of[ent.id] or nil
            if tname == 'SiteGovernment' and not site then goto next_entity end

            local id = ent.resources.art_image_ids[0]
            local sub = ent.resources.art_image_subids[0]
            local img = find_image(id, sub)
            local en = { name = cname, id = ent.id }
            en.site = site

            -- the symbol: decoded now, or taken from the results saved by an earlier session
            local rec
            if img then
                local elems = {}
                for _, e in ipairs(img.elements) do
                    local txt, keys = describe(e)
                    elems[#elems + 1] = { text = txt, keys = keys }
                end
                local nm = safe(function() return dfhack.translation.translateName(img.name, true) end)
                rec = { chunk = id, sub = sub, name = (nm and nm ~= '') and nm or nil, elems = elems }
                cache[ent.id] = rec
            else
                local old = cache[ent.id]
                if old and old.chunk == id and old.sub == sub then
                    rec = old
                    stats.cached = stats.cached + 1
                end
            end
            if rec then
                stats.decoded = stats.decoded + 1
                en.symbol, en.glyphs = render_symbol(rec.elems)
                en.symbol_name = rec.name
            else
                stats.missing = stats.missing + 1
                stats.missing_chunks[id] = true
                en.missing = true
                en.symbol = ('(symbol chunk %d not loaded)'):format(id)
            end

            by_race[race] = by_race[race] or {}
            local race_group = by_race[race]

            -- grouping key: the civ itself, its parent civ, or "Independent"
            local is_civ = ent.type == df.historical_entity_type.Civilization
            local group_key = is_civ and cname or find_parent_civ_name(ent, civ_info)

            race_group[group_key] = race_group[group_key] or { types = {} }
            local bucket = race_group[group_key]

            if is_civ then
                bucket.civ = en
                stats.civs = stats.civs + 1
                if rec then
                    civ_info[ent.id].symbol = en.symbol
                    civ_info[ent.id].glyphs = en.glyphs
                end
            else
                bucket.types[tname] = bucket.types[tname] or {}
                table.insert(bucket.types[tname], en)
            end
        end
        ::next_entity::
    end

    local races = {}
    for race in pairs(by_race) do races[#races + 1] = race end
    table.sort(races)

    cache_save(cache_path, sig, cache)

	local f = assert(io.open(path, 'w'))
    f:write(build_html(by_race, races, world, stats, civ_info), '\n')
    f:close()
    
    print((
        'Symbols Decoded : %d (%d from earlier sessions)\n' ..
        'Not Decodable   : %d\n\n' ..
        'Saved to %s'
    ):format(stats.decoded, stats.cached, stats.missing, path))
    if stats.missing > 0 then
        local ids = {}
        for id in pairs(stats.missing_chunks) do ids[#ids + 1] = tostring(id) end
        table.sort(ids)
    end
    return stats.missing
end

-- poll about once a second (in frames, so it also runs in menus)
local function watch(last_sig)
    dfhack.timeout(60, 'frames', function()
        if not dfhack.isWorldLoaded() then return end
        local sig = loaded_signature()
        if sig ~= last_sig then
            print('ent_sym_gat: new symbol data loaded, updating file...')
            if dump() == 0 then
                print('ent_sym_gat: all symbols decoded, done watching.')
                return
            end
        end
        watch(sig)
    end)
end

-- ===========================================================================
-- PASTE GLYPH TABLE: put the whole glyph table between the two lines
-- below (save this file as UTF-8). Lines that do not start with a number are ignored.
-- ===========================================================================
GLYPH_TEXT = [==[
000  	
001 ☺	Civilian dwarves
002 ☻	Military dwarves
003 ♥	Dimple cups
004 ♦	Cut gems, large gems
005 ♣	Quarry bush leaves, blossoms, various forest trees
006 ♠	Broadleaf forest, various forest trees, various leaf items, Plump helmets
007 •	caves, lairs, moon, flower buds
008 ◘	catapult cup, nest box tool, empty nest box building, codices, dice, book
009 ○	Well, vermin colony, millstone, quern, vertical axle, bubble bulb
010 ◙	
011 ♂	bags
012 ♀	amulet
013 ♪	Ladles, dancers dancing
014 ♫	ARMORSTAND, playing instruments
015 ☼	unmined gem cluster, Rough gems and Raw glass, spider webs, pond turtle, sun, gear assemblies, fireballs, night creature senses, artifact gem doors
016 ►	manta ray
017 ◄	
018 ↕	
019 ‼	Cages, vertical bars
020 ¶	GOBLET
021 §	Restraints, whip vine
022 ▬	Logs, hive tool, hive building
023 ↨	Cedar forest
024 ↑	conifer forests, various forest trees
025 ↓	
026 →	
027 ←	
028 ∟	
029 ↔	
030 ▲	BALLISTAARROWHEAD
031 ▼	
032  	
033 !	
034 "	shrub
035 #	floor grates, various stones
036 $	Coins
037 %	Prepared meal, Bismuthinite, Floating guts
038 &	Demons
039 '	rough floors, unexplored underground, various stones
040 (	
041 )	
042 *	glowing pits, gem floodgate, various stones, chestnut fruit
043 +	Bauxite
044 ,	rough floors, Claystone
045 -	Scepters
046 .	rough floors
047 /	Battle Axe, Short Sword, Spear, War Hammer, Mace, Pick, Crossbow, Training Axe, Training Sword, Training Spear, Great Axe, Two-Handed Sword, Long Sword, Scimitar, Halberd, Dagger, Large Dagger, Knife, Boning Knife, Slicing Knife, Stone Axe, Flail, Maul, Whip, Morningstar, Scourge, Pike, Bow, Blowgun, bolts, Pestle, stone axe
048 0	coffins, tombs
049 1	
050 2	
051 3	
052 4	
053 5	
054 6	
055 7	
056 8	
057 9	
058 :	strawberry, prickle berry, fisher berry, sun berry, snowstorms, underground shrubs
059 ;	Kitchen, Selenite, twigs
060 <	
061 =	
062 >	
063 ?	
064 @	
065 A	
066 B	
067 C	
068 D	
069 E	
070 F	
071 G	
072 H	
073 I	support
074 J	 
075 K	
076 L	
077 M	
078 N	
079 O	portal, column, bubble bulb
080 P	
081 Q	
082 R	
083 S	
084 T	
085 U	
086 V	
087 W	
088 X	Bin, floodgate, shop post, building footprint, Archery target
089 Y	Yak, Yeti
090 Z	Sleep indicator
091 [	Floor tile in workshops, Helm, Cap, Hood, Crown, Turban, Mail Shirt, Breastplate, Leather Armor, Dress, Robe, Tunic, Vest, Shirt, Cloak, Coat, Cape, Toga, Dress, Apron, Thong, Loincloth, Skirt, Trousers, Leggings, Greaves, Chausses, High Boots, Low Boots, Shoes, Sandals, Socks, Gauntlets, Mittens, Gloves, Shield, Buckler, SKIN_TANNED
092 \	helves
093 ]	
094 ^	Trap, Alabaster, Aluminum, Volcano
095 _	catapultparts, ballistaparts
096 `	
097 a	
098 b	
099 c	
100 d	
101 e	
102 f	
103 g	
104 h	
105 i	
106 j	
107 k	
108 l	
109 m	
110 n	
111 o	Graphite, bridge construction, staring eyeball, bubble bulb, winter melon, watermelon
112 p	
113 q	
114 r	
115 s	
116 t	
117 u	
118 v	
119 w	
120 x	Saltpeter
121 y	
122 z	
123 {	vermin, purring maggot
124 |	Talc, pipe sections, overlapping creatures animation
125 }	vermin, purring maggot alternate
126 ~	dirt road, farm plot under construction, sand, furrowed soil, blood smear, guts, Magnetite
127 ⌂	ANIMALTRAP
128 Ç	Mechanisms
129 ü	
130 é	
131 â	
132 ä	Angels
133 à	
134 å	
135 ç	Totems
136 ê	
137 ë	military elves
138 è	
139 ï	Pedestal
140 î	
141 ì	
142 Ä	Angels
143 Å	Figurines
144 É	altars
145 æ	Toys
146 Æ	Chests, quivers, backpacks
147 ô	Cauldrons
148 ö	Rings
149 ò	Unactivated levers, Various creatures#
150 û	Buckets
151 ù	
152 ÿ	Valley herb
153 Ö	Bracelets, wheelbarrows
154 Ü	Military humans
155 ¢	Hatch covers¢, musical instrument piecesv0.42.01
156 £	Various stones, most unmined ores,
157 ¥	Cave lobster
158 ₧	Stepladder, largest forest retreat ruins
159 ƒ	Rope reed, splints, arrow bamboo, golden bamboo, hedge bamboo, ORTHOPEDIC_CAST
160 á	
161 í	
162 ó	Activated levers
163 ú	
164 ñ	Bogeyman
165 Ñ	Night creatures, nightmare
166 ª	dark pit ruins
167 º	Cloth, dark pit
168 ¿	Musical Instruments
169 ⌐	Withered plants, wormy tendril
170 ¬	wormy tendril
171 ½	
172 ¼	Roc nests
173 ¡	Flask, waterskin, Pouch
174 «	
175 »	
176 ░	Partially dug rock, various flows (miasma, cave-in dust, steam, smoke, etc.), Fishery, Semi-molten Rock, various stones, various soils, Workshop wall tiles (craftdwarf's, bowyer's, mason's, mechanic's, jeweler's, clothier's, kitchen, and leather works)
177 ▒	window, vermin swarm
178 ▓	sky, fallen leaves
179 │	
180 ┤	
181 ╡	
182 ╢	
183 ╖	
184 ╕	
185 ╣	
186 ║	wooden doors, water wheel, windmill blade
187 ╗	
188 ╝	
189 ╜	
190 ╛	
191 ┐	
192 └	
193 ┴	
194 ┬	crutches
195 ├	
196 ─	
197 ┼	Doors
198 ╞	Saguaro
199 ╟	
200 ╚	
201 ╔	
202 ╩	
203 ╦	
204 ╠	
205 ═	planted crops, axles, windmill blade
206 ╬	fortifications
207 ╧	
208 ╨	
209 ╤	Table
210 ╥	Chair
211 ╙	
212 ╘	
213 ╒	
214 ╓	
215 ╫	Wooden floodgates, bone floodgates, wall grates
216 ╪	
217 ┘	
218 ┌	
219 █	Mist
220 ▄	Siege engine parts
221 ▌	
222 ▐	
223 ▀	
224 α	meat
225 ß	Leather
226 Γ	Weight
227 π	Cabinet, display cases
228 Σ	TRAPPARTS, spike
229 σ	Anvil, jugs
230 µ	Crown
231 τ	Tree sapling, pig tail, cave wheat, Longland grass, rat weed, hide root, muck root, blade weed, sliver barb, shrubland, arrow bamboo, golden bamboo, hedge bamboo
232 Φ	Sweet pod, bloated tuber, kobold bulb, traction benches, pots, thread
233 Θ	Beds, Puddingstone
234 Ω	Statues, sea nettle jellyfish
235 δ	Earrings, kennel tile
236 ∞	Boulder, dry brook, sea foam, honeycomb, scrolls
237 φ	
238 ε	
239 ∩	Slab
240 ≡	Bars, exceptional quality tags, activity zones, metal doors, floor bars, track stops
241 ±	
242 ≥	
243 ≤	
244 ⌠	
245 ⌡	sheets
246 ÷	Barrel, screw pump
247 ≈	water, magma, snow, glob, farm plot, furrowed soil, vomit, blood pools, sea foam, sand, various stones
248 °	Sea foam, eggs, bubble bulb, Bowl, Mortar
249 ∙	Vermin,
250 ·	Seeds, micro-vermin
251 √	WEAPONRACK
252 ⁿ	
253 ²	Body parts, vermin remains
254 ■	Blocks, minecarts,
255  	

011 ♂ Cuttlefish Nautilus, Squid
015 ☼ Pond turtle
016 ► manta ray
037 % Floating guts, cheese
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

0 * STAR, star
1 ( CRESCENT, crescent
2 + CROSS, cross
3 ■ SQUARE, square
4 ○ CIRCLE, circle
5 ♦ DIAMOND, diamond
6 ☼ SUN, sun
7 • MOON, moon
8 ≈ WAVE, wave
9 ▲ MOUNTAIN, mountain
10 ∞ CLOUD, cloud
11 ○ GIZZARD_STONE, gizzard stone
12 ○ SMOOTH_PEBBLE, pebble
13 ○ OVAL_CABOCHON, cabochon
14 ○ ROUND_CABOCHON, cabochon
15 ■ CUSHION_CABOCHON, cabochon
16 ■ RECTANGULAR_CABOCHON, cabochon
17 ♦ POINT_CUT_GEM, gem, SMALLGEM
18 ♦ TABLE_CUT_GEM, gem
19 ♦ SINGLE_CUT_GEM, gem
20 ○ ROSE_CUT_GEM, gem
21 ○ BRIOLETTE_CUT_GEM, gem
22 ♦ EMERALD_CUT_GEM, gem
23 ♦ MARQUISE_CUT_GEM, gem
24 ♦ OVAL_CUT_GEM, gem
25 ○ PEAR_CUT_GEM, gem
26 ♦ SQUARE_BRILLIANT_CUT_GEM, gem
27 ♦ RADIANT_CUT_GEM, gem
28 ♦ TRILLION_CUT_GEM, gem
29 ♦ ROUND_BRILLIANT_CUT_GEM, gem
30 ♦ BAGUETTE_CUT_GEM, gem
31 ♦ TAPERED_BAGUETTE_CUT_GEM, gem
32 ♦ CUSHION_CUT_GEM, gem
33 ♦ OCTAGON_CUT_GEM, gem
34 ♦ SQUARE_CUT_GEM, gem
35 ▲ PLATONIC_TETRAHEDRON, tetrahedron
36 ■ PLATONIC_CUBE, cube
37 ♦ PLATONIC_OCTAHEDRON, octahedron
38 ♦ PLATONIC_DODECAHEDRON, dodecahedron
39 ♦ PLATONIC_ICOSAHEDRON, icosahedron
40 - LONG_DIE_4, four-sided prism
41 - LONG_DIE_6, six-sided prism
42 - LONG_DIE_8, eight-sided prism

0 S forgotten beast
]==]
-- ===========================================================================

glyph_debug = ((({...})[1] or ''):lower() == 'glyphdebug')
local missing = dump()
if missing > 0 then
    watch(loaded_signature())
end

-- END OF ent_sym_gat.lua
