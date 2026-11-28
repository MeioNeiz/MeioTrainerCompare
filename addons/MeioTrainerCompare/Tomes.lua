-- Warlock demon tomes (Grimoires the demon trainer sells): which your demons know, which you
-- can buy now and which come later. The game only tells what the demon that is out knows, so
-- each demon's abilities are recorded while it is summoned:
--   MeioTrainerCompareCharDB.petSpells[pet spell ID] = true, .petSeen[demon] = true
-- The planner gets a "Demon tomes" tab; the merchant marks tomes already known.
local _, T = ...
local GOLD, WHITE, MUTED, GOOD = "|cffffd100", "|cffffffff", "|cff999999", "|cff80ff80"
local SUMMON = { Imp = 688, Voidwalker = 697, Succubus = 712, Felhunter = 691 }
-- the two Sayaad share their tomes, listed as the Succubus's
local FAMILY = { Incubus = "Succubus" }

local tomes, byItem
local function Tomes()
  if tomes then return tomes end
  tomes, byItem = {}, {}
  for _, r in ipairs(MeioSpellListData and MeioSpellListData.tomes or {}) do
    local t = { item = r[1], level = r[2], cost = r[3], spell = r[4], demon = r[5] }
    tomes[#tomes + 1] = t
    byItem[t.item] = byItem[t.item] or {}
    table.insert(byItem[t.item], t)
  end
  return tomes
end

local function Warlock() return select(2, UnitClass("player")) == "WARLOCK" end

local function InPetBook(id)
  if not (C_SpellBook and C_SpellBook.IsSpellInSpellBook and Enum.SpellBookSpellBank) then return false end
  local ok, v = pcall(C_SpellBook.IsSpellInSpellBook, id, Enum.SpellBookSpellBank.Pet, false)
  return ok and T.Usable(v) and v or false
end

local function SpellName(id)
  local n = C_Spell.GetSpellName(id)
  return T.Usable(n) and n or nil
end

-- the pet's spell book holds only the highest rank: a higher tome of the same ability for the
-- same demon known means this one is too
local function Known(t)
  local known = T.char and T.char.petSpells or {}
  if known[t.spell] then return true end
  local name = SpellName(t.spell)
  for _, o in ipairs(Tomes()) do
    if o.demon == t.demon and o.level > t.level and known[o.spell] and SpellName(o.spell) == name then
      return true
    end
  end
  return false
end
T.TomeKnown = Known

function T.ScanPet()
  if not (T.char and Warlock() and UnitExists("pet")) then return end
  local fam = UnitCreatureFamily and UnitCreatureFamily("pet")
  if T.Usable(fam) and fam then T.char.petSeen[FAMILY[fam] or fam] = true end
  for _, t in ipairs(Tomes()) do
    if InPetBook(t.spell) then T.char.petSpells[t.spell] = true end
  end
end

-- What's Training's record of learned tomes (item IDs, "SUC:"/"INC:" for the two Sayaad)
local function ImportWhatsTraining()
  local wt = rawget(_G, "WT_LearnedPetAbilities")
  if type(wt) ~= "table" or T.char.wtImported then return end
  Tomes()
  for key, on in pairs(wt) do
    local item = tonumber(key) or tonumber(tostring(key):match("^%a+:(%d+)$"))
    if on and item and byItem[item] then
      for _, t in ipairs(byItem[item]) do T.char.petSpells[t.spell] = true end
    end
  end
  T.char.wtImported = true
end

------------------------------------------------------------------------------- planner tab
local function ItemTip(id) return function(tip) tip:SetItemByID(id) end end

local function Knows(id)
  local ok, v = pcall(IsPlayerSpell, id)
  return ok and T.Usable(v) and v or false
end

local function HasDemon(demon)
  local id = SUMMON[demon]
  if not id then return true end
  return Knows(id) or demon == "Succubus" and Knows(713)
end

local function TomeRows(db)
  local level = UnitLevel("player")
  local now, later, known = {}, {}, {}
  for _, t in ipairs(Tomes()) do
    if HasDemon(t.demon) or t.level > level then
      if Known(t) then known[#known + 1] = t
      elseif t.level <= level then now[#now + 1] = t
      else later[#later + 1] = t end
    end
  end
  local rows = {}
  local function Add(t, color, right)
    local name = C_Item.GetItemNameByID and C_Item.GetItemNameByID(t.item)
    name = T.Usable(name) and name or ("Item " .. t.item)
    name = name:gsub("^Grimoire of ", "")
    rows[#rows + 1] = { icon = C_Item.GetItemIconByID and C_Item.GetItemIconByID(t.item) or 133738,
      text = color .. name .. "|r " .. MUTED .. t.demon .. "|r", right = right, tip = ItemTip(t.item) }
  end
  local total = 0
  for _, t in ipairs(now) do total = total + t.cost end
  rows[#rows + 1] = { head = ("Buy now (%d)"):format(#now), right = #now > 0 and T.Coins(total) or "" }
  if #now == 0 then rows[#rows + 1] = { text = MUTED .. "Nothing new for your demons at level " .. level .. "|r" } end
  for _, t in ipairs(now) do Add(t, WHITE, MUTED .. t.level .. "|r  " .. T.Coins(t.cost)) end
  local last
  for _, t in ipairs(later) do
    if t.level ~= last then
      last = t.level
      rows[#rows + 1] = { head = "Level " .. t.level }
    end
    Add(t, MUTED, T.Coins(t.cost))
  end
  if db.showKnown and #known > 0 then
    rows[#rows + 1] = { head = ("Known (%d)"):format(#known) }
    for _, t in ipairs(known) do Add(t, GOOD, MUTED .. t.level .. "|r") end
  end
  local unseen = {}
  for demon in pairs(SUMMON) do
    if HasDemon(demon) and not T.char.petSeen[demon] then unseen[#unseen + 1] = demon end
  end
  table.sort(unseen)
  local note = #unseen > 0 and ("Summon your %s once so this knows what %s already know%s.")
    :format(table.concat(unseen, ", "), #unseen == 1 and "it" or "they", #unseen == 1 and "s" or "")
    or "Sold by your demon trainer, beside the class trainer."
  return rows, note
end

table.insert(T.TABS, { key = "tomes", label = "Demon tomes", rows = TomeRows, shown = Warlock,
  knownLabel = "Show known" })

---------------------------------------------------------------------------------- merchant
local function MarkMerchant()
  if not (T.Option("tomes") and Warlock() and MerchantFrame and MerchantFrame:IsShown()) then return end
  local per = MERCHANT_ITEMS_PER_PAGE or 10
  local page = MerchantFrame.page or 1
  local buying = (MerchantFrame.selectedTab or 1) == 1
  Tomes()
  for i = 1, per do
    local button = _G["MerchantItem" .. i]
    if button then
      local label = button.meioTomeKnown
      local id = buying and GetMerchantItemID((page - 1) * per + i)
      local list = id and byItem[id]
      local known = false
      if list then
        known = true
        for _, t in ipairs(list) do if not Known(t) then known = false end end
      end
      if known and not label then
        local icon = _G["MerchantItem" .. i .. "ItemButton"] or button
        label = icon:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("BOTTOM", icon, "BOTTOM", 0, 2)
        label:SetText(GOOD .. "Known|r")
        button.meioTomeKnown = label
      end
      if label then label:SetShown(known) end
    end
  end
end

table.insert(T.loaders, function()
  T.char.petSpells = T.char.petSpells or {}
  T.char.petSeen = T.char.petSeen or {}
  ImportWhatsTraining()
end)

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("UNIT_PET")
events:RegisterEvent("PET_BAR_UPDATE")
events:RegisterEvent("SPELLS_CHANGED")
events:SetScript("OnEvent", function(_, event, unit)
  if event == "UNIT_PET" and unit ~= "player" then return end
  if event == "PLAYER_LOGIN" then
    if MerchantFrame_Update then hooksecurefunc("MerchantFrame_Update", function()
      local ok, err = pcall(MarkMerchant)
      if not ok then geterrorhandler()(err) end
    end) end
  end
  local ok, err = pcall(T.ScanPet)
  if not ok then geterrorhandler()(err) end
end)
