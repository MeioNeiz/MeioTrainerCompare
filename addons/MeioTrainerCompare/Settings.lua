-- Options, Settings panel and /mtc.
local _, T = ...

T.OPTIONS = {
  button = { label = "All spells button", default = true,
    tip = "An \"All spells\" button on the class trainer and the spell book opens the list (/mtc button on||off)." },
  tomes = { label = "Known tomes", default = true,
    tip = "At the demon trainer, tomes your demons already know say Known (/mtc marks on||off)." },
}

function T.Option(key)
  local v = T.db and T.db.options[key]
  if v == nil then return T.OPTIONS[key].default end
  return v
end

local function OnOff(on) return on and "|cff80ff80on|r" or "|cffff8080off|r" end
local function Cmd(text) return "|cffffd100" .. text .. "|r" end

local function SetOption(key, on)
  T.db.options[key] = on
  T.Print(T.OPTIONS[key].label:lower() .. " " .. OnOff(on))
  pcall(T.Buttons)
end

local category
local function Help()
  local function Now(key) return " (now " .. (T.Option(key) and "on" or "off") .. ")" end
  T.Print("every spell your class trainer teaches, demon tomes and profession recipes")
  print("  " .. Cmd("/mtc") .. " - open the list")
  print("  " .. Cmd("/mtc tomes") .. " - demon tomes")
  print("  " .. Cmd("/mtc recipes") .. " - profession recipes")
  print("  " .. Cmd("/mtc button on||off") .. " - All spells button on trainer and spell book" .. Now("button"))
  print("  " .. Cmd("/mtc marks on||off") .. " - mark known demon tomes at the merchant" .. Now("tomes"))
  print("  " .. Cmd("/mtc reset") .. " - put the window back")
  print("  Settings: Esc > Options > AddOns > " .. T.TITLE .. " (" .. Cmd("/mtc settings") .. ")")
end

local OPTION_WORDS = { button = "button", marks = "tomes" }

SLASH_MEIOTRAINERCOMPARE1 = "/mtc"
SLASH_MEIOTRAINERCOMPARE2 = "/meiotrainercompare"
SlashCmdList.MEIOTRAINERCOMPARE = function(msg)
  local word, arg = (msg or ""):lower():match("^%s*(%S*)%s*(%S*)")
  if word == "" then T.Toggle()
  elseif word == "tomes" or word == "recipes" or word == "class" then T.Show(word)
  elseif word == "reset" then T.ResetPosition() T.Print("window put back")
  elseif word == "settings" or word == "options" then
    if category and Settings and Settings.OpenToCategory then Settings.OpenToCategory(category:GetID()) end
  elseif OPTION_WORDS[word] and (arg == "on" or arg == "off") then SetOption(OPTION_WORDS[word], arg == "on")
  elseif word == "help" or word == "?" then Help()
  else
    T.Print(('unknown command "%s"'):format(word))
    Help()
  end
end

local function Register()
  if not (Settings and Settings.RegisterVerticalLayoutCategory) then return end
  local layout
  category, layout = Settings.RegisterVerticalLayoutCategory(T.TITLE)
  for _, key in ipairs({ "button", "tomes" }) do
    local o = T.OPTIONS[key]
    local setting = Settings.RegisterAddOnSetting(category, "MEIOTRAINERCOMPARE_" .. key:upper(), key,
      T.db.options, Settings.VarType.Boolean, o.label, o.default)
    setting:SetValueChangedCallback(function() pcall(T.Buttons) end)
    Settings.CreateCheckbox(category, setting, o.tip)
  end
  if layout and CreateSettingsButtonInitializer then
    layout:AddInitializer(CreateSettingsButtonInitializer("", "Open the list", function() T.Show() end,
      "Every spell your class trainer teaches, demon tomes and recipes.", true))
    layout:AddInitializer(CreateSettingsButtonInitializer("", "Reset position", T.ResetPosition,
      "Puts the window back beside the trainer or in the middle.", true))
  end
  Settings.RegisterAddOnCategory(category)
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function()
  local ok, err = pcall(Register)
  if not ok then geterrorhandler()(err) end
end)
