-- The planner's "Professions" tab: for each profession you have, the recipes you can learn at
-- your skill and those coming up, with where each comes from (trainer and its cost, vendor and
-- the zones, drop, quest). Data: Recipes.lua (What's Training's tables, MIT).
local _, T = ...
local GOLD, WHITE, MUTED, GOOD = "|cffffd100", "|cffffffff", "|cff999999", "|cff80ff80"
local AHEAD = 50 -- skill points ahead shown without "Show learned and later"
local LINES = { Alchemy = 171, Blacksmithing = 164, Cooking = 185, Enchanting = 333,
  Engineering = 202, ["First Aid"] = 129, Fishing = 356, Herbalism = 182, Leatherworking = 165,
  Mining = 186, Skinning = 393, Tailoring = 197 }
local SOURCE = { { 1, "Trainer" }, { 2, "Vendor" }, { 8, "Quest" }, { 4, "Drop" }, { 16, "Object" },
  { 32, "Crafted" } }

-- { line, name, rank, max } for every profession with recipes in our data
function T.Professions()
  local out = {}
  if GetProfessions and GetProfessionInfo then
    for _, idx in ipairs({ GetProfessions() }) do
      local name, _, rank, max, _, _, line = GetProfessionInfo(idx)
      if T.Usable(line) and line and T.Recipes[line] then
        out[#out + 1] = { line = line, name = name, rank = rank or 0, max = max or 0 }
      end
    end
  end
  if #out == 0 and GetNumSkillLines and GetSkillLineInfo then
    for i = 1, GetNumSkillLines() do
      local name, header, _, rank, _, _, max = GetSkillLineInfo(i)
      local line = not header and LINES[name]
      if line and T.Recipes[line] then
        out[#out + 1] = { line = line, name = name, rank = rank or 0, max = max or 0 }
      end
    end
  end
  table.sort(out, function(a, b) return a.name < b.name end)
  return out
end

local function Faction()
  local f = UnitFactionGroup("player")
  return f == "Alliance" and 1 or f == "Horde" and 2 or 0
end

local function Sources(r)
  local parts = {}
  for _, s in ipairs(SOURCE) do
    if bit.band(r[3], s[1]) ~= 0 then
      parts[#parts + 1] = s[1] == 1 and r[4] > 0 and ("Trainer " .. T.Coins(r[4])) or s[2]
    end
  end
  return #parts > 0 and table.concat(parts, MUTED .. " / |r") or MUTED .. "?|r"
end

local function Zone(id)
  local name = C_Map and C_Map.GetAreaInfo and C_Map.GetAreaInfo(id)
  return T.Usable(name) and name or nil
end

local function RecipeTip(r)
  return function(tip)
    if r[5] > 0 then tip:SetItemByID(r[5]) else tip:SetSpellByID(r[1]) end
    tip:AddLine(" ")
    tip:AddDoubleLine("Skill needed", tostring(r[2]), 1, 0.82, 0, 1, 1, 1)
    tip:AddDoubleLine("From", Sources(r), 1, 0.82, 0, 1, 1, 1)
    local zones = {}
    for _, id in ipairs(Faction() == 2 and r[10] or r[9]) do zones[#zones + 1] = Zone(id) end
    if #zones > 0 then
      tip:AddLine("Sold in " .. table.concat(zones, ", "), 1, 1, 1, true)
    end
    if r[8] == 1 then tip:AddLine("Needs reputation with the seller", 1, 0.5, 0.5) end
  end
end

local function Known(spell)
  local ok, v = pcall(IsPlayerSpell, spell)
  if ok and T.Usable(v) and v then return true end
  if C_SpellBook and C_SpellBook.IsSpellKnown then
    ok, v = pcall(C_SpellBook.IsSpellKnown, spell)
    if ok and T.Usable(v) and v then return true end
  end
  return false
end

-- a higher profession rank (Expert) takes the lower ones (Journeyman) out of the spell book
local function RankKnown(list)
  local best = 0
  for _, r in ipairs(list) do
    if r[11] == 1 and r[2] > best and Known(r[1]) then best = r[2] end
  end
  return best
end

local function RecipeRows(db)
  local rows, fac = {}, Faction()
  local profs = T.Professions()
  for _, p in ipairs(profs) do
    local now, soon, known = {}, {}, {}
    local rank = RankKnown(T.Recipes[p.line])
    for _, r in ipairs(T.Recipes[p.line]) do
      if r[7] == 0 or r[7] == fac then
        if Known(r[1]) or r[11] == 1 and r[2] <= rank then known[#known + 1] = r
        elseif r[2] <= p.rank then now[#now + 1] = r
        elseif db.showKnown or r[2] <= p.rank + AHEAD then soon[#soon + 1] = r end
      end
    end
    rows[#rows + 1] = { head = p.name, right = MUTED .. p.rank .. " / " .. p.max .. "|r" }
    local function Add(r, color)
      local name = C_Spell.GetSpellName(r[1])
      name = T.Usable(name) and name or ("Recipe " .. r[1])
      if r[11] == 1 then
        local rank = C_Spell.GetSpellSubtext and C_Spell.GetSpellSubtext(r[1])
        if T.Usable(rank) and rank and rank ~= "" then name = rank .. " " .. name end
      end
      local icon = r[6] > 0 and C_Item.GetItemIconByID and C_Item.GetItemIconByID(r[6])
        or C_Spell.GetSpellTexture(r[1])
      rows[#rows + 1] = { icon = icon, text = color .. name .. "|r " .. MUTED .. r[2] .. "|r",
        right = Sources(r), tip = RecipeTip(r) }
    end
    if #now == 0 and #soon == 0 then
      rows[#rows + 1] = { text = MUTED .. "Nothing new within " .. AHEAD .. " skill|r" }
    end
    for _, r in ipairs(now) do Add(r, WHITE) end
    for _, r in ipairs(soon) do Add(r, MUTED) end
    if db.showKnown then for _, r in ipairs(known) do Add(r, GOOD) end end
  end
  local note = #profs == 0 and "No profession with recipes yet."
    or ("White: learn now. Grey: the next %d skill points."):format(AHEAD)
  if #profs == 0 then rows[#rows + 1] = { text = MUTED .. "Learn a profession at its trainer first.|r" } end
  return rows, note
end

table.insert(T.TABS, { key = "recipes", label = "Professions", rows = RecipeRows,
  knownLabel = "Show learned and all later" })
