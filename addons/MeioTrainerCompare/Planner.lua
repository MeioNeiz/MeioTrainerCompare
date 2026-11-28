-- The planner window: what your class trainer teaches now and at later levels with costs (the
-- shared MeioSpellList), warlock demon tomes (Tomes.lua) and profession recipes with where each
-- comes from (Recipes.lua). /mtc, the button on the class trainer or spell book, the addon
-- compartment.
--   MeioTrainerCompareDB = { costs = MeioSpellList store, pos, options, showKnown, tab }
local _, T = ...
local S = function() return MeioSpellList end

T.TITLE = "MeioTrainerCompare"
T.loaders = {} -- fn() once the SavedVariables are in
local W, H, ROW = 440, 540, 18
local GOLD, WHITE, MUTED, GOOD, BAD = "|cffffd100", "|cffffffff", "|cff999999", "|cff80ff80",
  "|cffff8080"

function T.Usable(v) return v ~= nil and (not canaccessvalue or canaccessvalue(v)) end

function T.Coins(c)
  if not c then return MUTED .. "?|r" end
  local g, s, k = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
  local parts = {}
  if g > 0 then parts[#parts + 1] = "|cffffd700" .. g .. "g|r" end
  if s > 0 and #parts < 2 then parts[#parts + 1] = "|cffc7c7cf" .. s .. "s|r" end
  if k > 0 and #parts < 2 and g == 0 then parts[#parts + 1] = "|cffeda55f" .. k .. "c|r" end
  return #parts > 0 and table.concat(parts, " ") or "|cffeda55f0c|r"
end

function T.Print(msg) print("|cffb090ff" .. T.TITLE .. ":|r " .. msg) end

------------------------------------------------------------------------------- tabs' rows
-- a row: { head = text, right = text } or { icon, text, right, color, tip = fn(tooltip) }

local function SpellTip(id) return function(tip) tip:SetSpellByID(id) end end

local function ClassRows(db)
  local level = UnitLevel("player")
  local now, quests, later, known = {}, {}, {}, {}
  for _, e in ipairs(S().List()) do
    local state = S().State(e, level)
    if state == "train" then now[#now + 1] = e
    elseif state == "quest" then quests[#quests + 1] = e
    elseif state == "later" then later[#later + 1] = e
    elseif state == "known" then known[#known + 1] = e end
  end
  local rows = {}
  local function Spell(e, color, right)
    local name, rank, icon = S().Info(e)
    rows[#rows + 1] = { icon = icon, text = color .. name .. "|r" .. (rank and (MUTED .. " " .. rank .. "|r") or ""),
      right = right, tip = SpellTip(e.id) }
  end
  local total = S().Total(now)
  local money = GetMoney()
  rows[#rows + 1] = { head = ("Train now (%d)"):format(#now),
    right = #now > 0 and (total > money and BAD or "") .. T.Coins(total)
      .. (total > money and "|r" or "") or "" }
  if #now == 0 then rows[#rows + 1] = { text = MUTED .. "Nothing to train at level " .. level .. "|r" } end
  for _, e in ipairs(now) do Spell(e, WHITE, MUTED .. e.level .. "|r  " .. T.Coins(S().Cost(e))) end
  if #quests > 0 then
    rows[#rows + 1] = { head = "From class quests" }
    for _, e in ipairs(quests) do
      Spell(e, e.quest <= level and WHITE or MUTED, MUTED .. "quest at " .. e.quest .. "|r")
    end
  end
  local lastLevel
  for _, e in ipairs(later) do
    if e.level ~= lastLevel then
      lastLevel = e.level
      local same = {}
      for _, x in ipairs(later) do if x.level == e.level then same[#same + 1] = x end end
      local priced = S().Cost(e) ~= nil
      rows[#rows + 1] = { head = "Level " .. e.level, right = T.Coins(priced and S().Total(same) or nil) }
    end
    Spell(e, MUTED, T.Coins(S().Cost(e)))
  end
  if db.showKnown and #known > 0 then
    rows[#rows + 1] = { head = ("Learned (%d)"):format(#known) }
    for i = #known, 1, -1 do Spell(known[i], GOOD, MUTED .. known[i].level .. "|r") end
  end
  local note
  if not S().HasCosts() then
    note = "Visit your class trainer once to see what each spell costs."
  end
  return rows, note
end

T.TABS = {
  { key = "class", label = "Class", rows = ClassRows },
}

------------------------------------------------------------------------------------ window
local frame, rowPool = nil, {}

local function Row(i)
  local r = rowPool[i]
  if r then return r end
  r = CreateFrame("Button", nil, frame.content)
  r:SetSize(W - 50, ROW)
  r.icon = r:CreateTexture(nil, "ARTWORK")
  r.icon:SetSize(16, 16)
  r.icon:SetPoint("LEFT", 2, 0)
  r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  r.text:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
  r.text:SetJustifyH("LEFT")
  r.right = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  r.right:SetPoint("RIGHT", -4, 0)
  r.right:SetJustifyH("RIGHT")
  r.text:SetPoint("RIGHT", r.right, "LEFT", -6, 0)
  r.text:SetWordWrap(false)
  r.hl = r:CreateTexture(nil, "HIGHLIGHT")
  r.hl:SetAllPoints()
  r.hl:SetColorTexture(1, 1, 1, 0.08)
  r:SetScript("OnEnter", function(self)
    if not self.tip then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    local ok, err = pcall(self.tip, GameTooltip)
    if not ok then geterrorhandler()(err) end
    GameTooltip:Show()
  end)
  r:SetScript("OnLeave", function() GameTooltip:Hide() end)
  rowPool[i] = r
  return r
end

function T.Refresh()
  if not (frame and frame:IsShown()) then return end
  local db = T.db
  local tab = T.TABS[frame.tab] or T.TABS[1]
  for i, b in ipairs(frame.tabs) do
    if PanelTemplates_SetTab and i == frame.tab then PanelTemplates_SetTab(frame, i) end
    b:SetShown(T.TABS[i] ~= nil and (not T.TABS[i].shown or T.TABS[i].shown()))
  end
  local ok, rows, note = pcall(tab.rows, db)
  if not ok then
    geterrorhandler()(rows)
    rows, note = {}, nil
  end
  local y = 0
  for i, d in ipairs(rows) do
    local r = Row(i)
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", 0, -y)
    r.tip = d.tip
    if d.head then
      r.icon:SetTexture(nil)
      r.icon:SetWidth(1)
      r.text:SetText(GOLD .. d.head .. "|r")
      r.text:SetFontObject("GameFontNormal")
      y = y + (i > 1 and 6 or 0)
      r:ClearAllPoints()
      r:SetPoint("TOPLEFT", 0, -y)
    else
      r.icon:SetWidth(16)
      r.icon:SetTexture(d.icon)
      r.text:SetText(d.text or "")
      r.text:SetFontObject("GameFontHighlightSmall")
    end
    r.right:SetText(d.right or "")
    r:Show()
    y = y + ROW
  end
  for i = #rows + 1, #rowPool do rowPool[i]:Hide() end
  frame.content:SetHeight(math.max(y, 1))
  frame.note:SetText(note and (MUTED .. note .. "|r") or "")
  frame.known:SetChecked(db.showKnown and true or false)
  frame.knownLabel:SetText(tab.knownLabel or "Show learned")
end

local function SavePos()
  local p, _, rp, x, y = frame:GetPoint(1)
  T.db.pos = { p, rp, x, y }
end

local function Place()
  frame:ClearAllPoints()
  local pos = T.db.pos
  if pos then
    frame:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
  elseif ClassTrainerFrame and ClassTrainerFrame:IsShown() then
    frame:SetPoint("TOPLEFT", ClassTrainerFrame, "TOPRIGHT", 12, 0)
  else
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
  end
end

local function Build()
  if frame then return frame end
  frame = CreateFrame("Frame", "MeioTrainerCompareFrame", UIParent, "ButtonFrameTemplate")
  frame:SetSize(W, H)
  frame:SetFrameStrata("HIGH")
  frame:SetToplevel(true)
  frame:EnableMouse(true)
  frame:SetMovable(true)
  frame:SetClampedToScreen(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() SavePos() end)
  if ButtonFrameTemplate_HidePortrait then ButtonFrameTemplate_HidePortrait(frame) end
  if frame.SetTitle then frame:SetTitle(T.TITLE) end
  tinsert(UISpecialFrames, "MeioTrainerCompareFrame")

  local inset = frame.Inset or frame
  local scroll = CreateFrame("ScrollFrame", "MeioTrainerCompareScroll", inset, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 8, -8)
  scroll:SetPoint("BOTTOMRIGHT", -28, 8)
  frame.content = CreateFrame("Frame", nil, scroll)
  frame.content:SetSize(W - 50, 1)
  scroll:SetScrollChild(frame.content)
  frame.scroll = scroll

  frame.known = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
  frame.known:SetSize(22, 22)
  frame.known:SetPoint("TOPLEFT", 60, -28)
  frame.knownLabel = frame.known:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  frame.knownLabel:SetPoint("LEFT", frame.known, "RIGHT", 2, 0)
  frame.known:SetScript("OnClick", function(self)
    T.db.showKnown = self:GetChecked() and true or nil
    T.Refresh()
  end)
  frame.note = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  frame.note:SetPoint("BOTTOMLEFT", 12, 6)
  frame.note:SetPoint("BOTTOMRIGHT", -12, 6)
  frame.note:SetHeight(28)
  frame.note:SetJustifyH("LEFT")
  frame.note:SetJustifyV("MIDDLE")
  if frame.Inset then frame.Inset:SetPoint("BOTTOMRIGHT", -6, 36) end

  frame.tabs = {}
  for i, tab in ipairs(T.TABS) do
    local b = CreateFrame("Button", "MeioTrainerCompareFrameTab" .. i, frame,
      PanelTabButtonMixin and "PanelTabButtonTemplate" or "CharacterFrameTabButtonTemplate")
    b:SetID(i)
    b:SetText(tab.label)
    if i == 1 then b:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 12, 2)
    else b:SetPoint("LEFT", frame.tabs[i - 1], "RIGHT", 4, 0) end
    if PanelTemplates_TabResize then PanelTemplates_TabResize(b, 0) end
    b:SetScript("OnClick", function()
      frame.tab = i
      T.db.tab = tab.key
      frame.scroll:SetVerticalScroll(0)
      T.Refresh()
    end)
    frame.tabs[i] = b
  end
  if PanelTemplates_SetNumTabs then PanelTemplates_SetNumTabs(frame, #T.TABS) end
  frame.tab = 1
  for i, tab in ipairs(T.TABS) do if tab.key == T.db.tab then frame.tab = i end end

  frame:SetScript("OnShow", T.Refresh)
  frame:Hide()
  return frame
end

function T.Show(tabKey)
  Build()
  local was = frame.tab
  if tabKey then
    for i, tab in ipairs(T.TABS) do if tab.key == tabKey then frame.tab = i end end
  end
  local tab = T.TABS[frame.tab]
  if tab and tab.shown and not tab.shown() then frame.tab = 1 end
  if frame.tab ~= was then frame.scroll:SetVerticalScroll(0) end
  Place()
  frame:Show()
  T.Refresh()
end

function T.Toggle(tabKey)
  if frame and frame:IsShown() and (not tabKey or T.TABS[frame.tab].key == tabKey) then
    frame:Hide()
  else
    T.Show(tabKey)
  end
end

function T.ResetPosition()
  T.db.pos = nil
  if frame and frame:IsShown() then Place() end
end

function MeioTrainerCompare_OnAddonCompartmentClick() T.Toggle() end

--------------------------------------------------------------------- buttons on Blizzard's
-- a plain button parented to the trainer window and the spell book (not protected frames)
local function OpenButton(parent, name, tabKey, point)
  if not parent or _G[name] then return end
  local b = CreateFrame("Button", name, parent, "UIPanelButtonTemplate")
  b:SetSize(110, 20)
  b:SetText("All spells")
  b:SetPoint(unpack(point))
  b:SetScript("OnClick", function() T.Toggle(tabKey) end)
  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine(T.TITLE)
    GameTooltip:AddLine("Every spell your class trainer teaches, now and at later levels,"
      .. " with costs; demon tomes and profession recipes.", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  b:SetShown(T.Option("button"))
  return b
end

function T.Buttons()
  -- between the portrait and the filter dropdown
  OpenButton(ClassTrainerFrame, "MeioTrainerCompareTrainerButton", "class",
    { "TOPLEFT", ClassTrainerFrame, "TOPLEFT", 66, -32 })
  local book = PlayerSpellsFrame and PlayerSpellsFrame.SpellBookFrame
  OpenButton(book, "MeioTrainerCompareBookButton", "class",
    { "TOPRIGHT", book, "TOPRIGHT", -40, -30 })
  local trainer = _G.MeioTrainerCompareTrainerButton
  if trainer then
    -- profession trainers have their skill bar there, and no class spells
    local trade = IsTradeskillTrainer and IsTradeskillTrainer()
    trainer:SetShown(T.Option("button") and not (T.Usable(trade) and trade))
  end
  local bookButton = _G.MeioTrainerCompareBookButton
  if bookButton then bookButton:SetShown(T.Option("button")) end
end

------------------------------------------------------------------------------------ events
local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("TRAINER_SHOW")
events:RegisterEvent("PLAYER_LEVEL_UP")
events:RegisterEvent("SPELLS_CHANGED")
events:RegisterEvent("PLAYER_MONEY")
events:SetScript("OnEvent", function(_, event, name)
  if event == "ADDON_LOADED" then
    if name == "MeioTrainerCompare" then
      MeioTrainerCompareDB = MeioTrainerCompareDB or {}
      MeioTrainerCompareCharDB = MeioTrainerCompareCharDB or {}
      T.db, T.char = MeioTrainerCompareDB, MeioTrainerCompareCharDB
      T.db.costs = T.db.costs or {}
      T.db.options = T.db.options or {}
      S().Attach(T.db.costs)
      S().OnScan(T.Refresh)
      for _, fn in ipairs(T.loaders) do fn() end
    end
    pcall(T.Buttons)
  elseif event == "TRAINER_SHOW" then
    pcall(T.Buttons)
  else
    T.Refresh()
  end
end)
