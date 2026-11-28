-- MeioSpellList: every class trainer spell of your class (SpellData.lua, from the client's own
-- tables) as learned, to train now or later, with its cost. Shared by MeioTrainerCompare and
-- MeioDing: the same file in both, the newer version wins. Edit it in MeioTrainerCompare;
-- tools/gen-trainer-data.mjs copies it to MeioDing.
-- Costs: no client table has them. Each class trainer visit records every service's cost into
-- each attached store (account-wide SavedVariables): store[class][spellID] = copper, and
-- store[class]["L" .. level] (a class trainer charges the same for every spell of a level, so
-- one visit prices later levels too).
local VERSION = 1
local old = MeioSpellList
if old and old.version >= VERSION then return end
local L = { version = VERSION, stores = old and old.stores or {},
  listeners = old and old.listeners or {} }
MeioSpellList = L
if old and old.frame then old.frame:UnregisterAllEvents() end

local function Usable(v) return v ~= nil and (not canaccessvalue or canaccessvalue(v)) end

local class, list, byID, later
local function Build()
  if list then return list end
  local data = MeioSpellListData
  class = select(2, UnitClass("player"))
  local raceBit = 2 ^ ((select(3, UnitRace("player")) or 1) - 1)
  list, byID, later = {}, {}, {}
  for _, r in ipairs(data and data.spells[class] or {}) do
    local race = r[6] or 0
    if race == 0 or bit.band(race, raceBit) ~= 0 then
      local e = { id = r[1], level = r[2], prev = r[3], talent = r[4] ~= 0 and r[4] or nil,
        quest = r[5] ~= 0 and r[5] or nil }
      list[#list + 1] = e
      byID[e.id] = e
    end
  end
  -- the spell book keeps only the highest rank: a later rank known means this one is too
  for _, e in ipairs(list) do
    if e.prev ~= 0 and byID[e.prev] then later[e.prev] = e end
  end
  return list
end

function L.List() return Build() end
function L.Class() Build() return class end
function L.Get(id) Build() return byID[id] end

local function IsKnown(id)
  if IsPlayerSpell then
    local ok, v = pcall(IsPlayerSpell, id)
    if ok and Usable(v) and v then return true end
  end
  if C_SpellBook and C_SpellBook.IsSpellKnown then
    local ok, v = pcall(C_SpellBook.IsSpellKnown, id)
    if ok and Usable(v) and v then return true end
  end
  return false
end

function L.Known(e)
  Build()
  local n = 0
  while e and n < 20 do
    if IsKnown(e.id) then return true end
    e, n = later[e.id], n + 1
  end
  return false
end

-- "known", "train" (level reached), "later", "quest" (a class quest teaches it), "talent"
-- (a rank of a talent you don't have)
function L.State(e, level)
  if L.Known(e) then return "known" end
  if e.talent and not IsKnown(e.talent) then return "talent" end
  if e.quest then return "quest" end
  return e.level <= (level or UnitLevel("player")) and "train" or "later"
end

function L.Info(e)
  if e.name then return e.name, e.rank, e.icon end
  local name = C_Spell.GetSpellName(e.id)
  local rank = C_Spell.GetSpellSubtext and C_Spell.GetSpellSubtext(e.id)
  local icon = C_Spell.GetSpellTexture(e.id)
  if Usable(name) and name then
    e.name, e.icon = name, icon
    e.rank = Usable(rank) and rank ~= "" and rank or nil
  end
  return e.name or ("Spell " .. e.id), e.rank, e.icon
end

function L.Cost(e)
  Build()
  for _, store in ipairs(L.stores) do
    local c = store[class]
    if c and (c[e.id] or c["L" .. e.level]) then return c[e.id] or c["L" .. e.level] end
  end
end

function L.HasCosts()
  Build()
  for _, store in ipairs(L.stores) do
    if store[class] and next(store[class]) then return true end
  end
  return false
end

function L.Total(spells)
  local c = 0
  for _, e in ipairs(spells) do c = c + (L.Cost(e) or 0) end
  return c
end

-- trainer spells first trainable at exactly this level, and older ones never trained
function L.At(level)
  local new, older = {}, {}
  for _, e in ipairs(Build()) do
    if L.State(e, level) == "train" then
      if e.level == level then new[#new + 1] = e elseif e.level > 1 then older[#older + 1] = e end
    end
  end
  return new, older
end

-- the next level above this one with trainer spells, and those spells
function L.Next(level)
  local best
  for _, e in ipairs(Build()) do
    if e.level > level and (not best or e.level < best) and L.State(e, e.level) == "train" then
      best = e.level
    end
  end
  if best then return best, (L.At(best)) end
end

function L.Attach(store)
  for _, s in ipairs(L.stores) do if s == store then return end end
  L.stores[#L.stores + 1] = store
end

function L.Remember(id, level, cost)
  Build()
  if not (Usable(cost) and type(cost) == "number") then return end
  for _, store in ipairs(L.stores) do
    store[class] = store[class] or {}
    if id then store[class][id] = cost end
    if level then store[class]["L" .. level] = cost end
  end
end

local function ClassTrainer()
  if not GetNumTrainerServices then return false end
  if IsTradeskillTrainer and IsTradeskillTrainer() then return false end
  if C_Trainer and C_Trainer.GetTrainerType and Enum.TrainerType then
    local ok, kind = pcall(C_Trainer.GetTrainerType)
    if ok and kind ~= nil and kind ~= Enum.TrainerType.Class then return false end
  end
  return true
end

function L.Scan()
  if not ClassTrainer() then return end
  for i = 1, GetNumTrainerServices() or 0 do
    local name, kind, _, level = GetTrainerServiceInfo(i)
    if Usable(name) and kind ~= "header" then
      local id
      if C_TooltipInfo and C_TooltipInfo.GetTrainerService then
        local ok, data = pcall(C_TooltipInfo.GetTrainerService, i)
        id = ok and type(data) == "table" and Usable(data.id) and data.id or nil
      end
      local e = id and L.Get(id)
      local cost = GetTrainerServiceCost(i)
      -- by level only for our list's own spells: a stray service won't price a whole level
      L.Remember(id, e and not e.quest and type(level) == "number" and level or nil, cost)
    end
  end
  for _, fn in ipairs(L.listeners) do
    local ok, err = pcall(fn)
    if not ok then geterrorhandler()(err) end
  end
end

-- fn() after each trainer visit has recorded its costs
function L.OnScan(fn) L.listeners[#L.listeners + 1] = fn end

-- a list update per purchase and per filter click: read once they settle
local frame = CreateFrame("Frame")
L.frame = frame
local pending
frame:RegisterEvent("TRAINER_SHOW")
frame:RegisterEvent("TRAINER_UPDATE")
frame:SetScript("OnEvent", function()
  if pending then return end
  pending = true
  C_Timer.After(0.2, function()
    pending = false
    local ok, err = pcall(L.Scan)
    if not ok then geterrorhandler()(err) end
  end)
end)
