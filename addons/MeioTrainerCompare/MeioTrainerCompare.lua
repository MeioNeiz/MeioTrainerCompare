-- MeioTrainerCompare: a trainer's recipe tooltip is a "trainer service", not an item, so the game
-- never puts the equipped-item comparison beside it. When the recipe makes gear, this shows
-- what you wear in that slot (both rings, trinkets or weapon hands) in the comparison
-- tooltips, as for any item.

local SLOTS = {
    INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_BODY = { 4 },
    INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 }, INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 },
    INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 },
    INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 }, INVTYPE_CLOAK = { 15 }, INVTYPE_WEAPON = { 16, 17 },
    INVTYPE_SHIELD = { 17 }, INVTYPE_2HWEAPON = { 16 }, INVTYPE_WEAPONMAINHAND = { 16 },
    INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_HOLDABLE = { 17 }, INVTYPE_RANGED = { 18 },
    INVTYPE_RANGEDRIGHT = { 18 }, INVTYPE_THROWN = { 18 }, INVTYPE_RELIC = { 18 },
}

local EQUIPPED = _G.CURRENTLY_EQUIPPED or "Currently Equipped"
local shown = false
local tips

local function Tips()
    if tips then return tips end
    local function Make(name)
        return CreateFrame("GameTooltip", name, UIParent, "GameTooltipTemplate")
    end
    tips = { _G.ShoppingTooltip1 or Make("MeioTrainerCompareTip1"),
        _G.ShoppingTooltip2 or Make("MeioTrainerCompareTip2") }
    return tips
end

local function HideOurs()
    if not shown then return end
    shown = false
    for _, t in ipairs(Tips()) do t:Hide() end
end

-- The item the service makes: the service's item, else the recipe's output
local function ServiceItem(index)
    local ok, link = pcall(GetTrainerServiceItemLink, index)
    if ok and type(link) == "string" and link:find("item:") then return link end
    if C_TooltipInfo and C_TooltipInfo.GetTrainerService then
        local okData, data = pcall(C_TooltipInfo.GetTrainerService, index)
        if okData and type(data) == "table" then
            ---@cast data table
            local h = data.hyperlink
            if type(h) == "string" and h:find("item:") then return h end
            local output = C_TradeSkillUI and C_TradeSkillUI.GetRecipeOutputItemData
            if type(data.id) == "number" and output then
                local okOut, out = pcall(output, data.id)
                if okOut and type(out) == "table" then
                    if type(out.hyperlink) == "string" then return out.hyperlink end
                    local id = out.itemID
                    if type(id) == "number" and id > 0 then return "item:" .. id end
                end
            end
        end
    end
end

-- Forever Leveling BiS (public API v2): what the item made gains your main spec over what you
-- wear, the number its own item tooltips show. Meionomics puts the same on trainer lines.
local STEP = 0.05 -- FLBiS's smallest gain worth showing
local GOOD, BAD, MUTED = "|cff80ff80", "|cffff8080", "|cff999999"

local function VerdictText(link)
    local api = ForeverLevelingBiS_API
    if not (api and (api.version or 1) >= 2) then return end
    if C_AddOns.IsAddOnLoaded("Meionomics") then return end
    local score, loading = api.ScoreItem(link)
    if loading or not score then return end
    local gain, wait = api.GetGain(link)
    if wait then return end
    if not gain then return MUTED .. "not for your spec|r" end
    if math.abs(gain) < STEP then return MUTED .. "same as you wear|r" end
    local text = ("%+.1f"):format(gain)
    local base = score - gain
    local pct = base > 0 and gain / base * 100
    if pct and math.abs(pct) >= 1 and math.abs(pct) < 1000 then
        text = text .. (" (%+d%%)"):format(pct < 0 and math.ceil(pct - 0.5) or math.floor(pct + 0.5))
    end
    return gain > 0 and (GOOD .. text .. " upgrade|r") or (BAD .. text .. " downgrade|r")
end

local function Verdict(tooltip, link)
    local ok, text = pcall(VerdictText, link)
    if not (ok and text) then return end
    tooltip:AddLine(MUTED .. "Leveling BiS:|r " .. text)
    tooltip:Show()
end

local function Compare(tooltip, index)
    HideOurs()
    if tooltip ~= GameTooltip or (issecretvalue and issecretvalue(index)) then return end
    if type(index) ~= "number" then return end
    local link = ServiceItem(index)
    if not link then return end
    local equipLoc = select(4, C_Item.GetItemInfoInstant(link))
    local slots = equipLoc and SLOTS[equipLoc]
    if not slots then return end
    Verdict(tooltip, link)

    -- right of the recipe tooltip, or left when there's no room
    local t = Tips()
    local used = 0
    local anchorTo, onLeft = tooltip, false
    -- in screen pixels: the tooltips may be scaled differently from UIParent. Forever makes a
    -- tooltip's edges secret when it is anchored to a restricted frame: then just go right
    local right = tooltip:GetRight()
    local secret = issecretvalue and issecretvalue(right)
    local room = math.huge
    if not secret and right then
        room = UIParent:GetRight() * UIParent:GetEffectiveScale()
            - right * tooltip:GetEffectiveScale()
    end
    for _, slot in ipairs(slots) do
        if GetInventoryItemLink("player", slot) then
            used = used + 1
            local tip = t[used]
            tip:SetOwner(tooltip, "ANCHOR_NONE")
            tip:SetInventoryItem("player", slot)
            tip:AddLine(EQUIPPED, 0.5, 0.5, 0.5)
            tip:Show()
            if used == 1 then
                onLeft = room < (tip:GetWidth() + 10) * tip:GetEffectiveScale()
            end
            tip:ClearAllPoints()
            if onLeft then
                tip:SetPoint("TOPRIGHT", anchorTo, "TOPLEFT", 0, -10)
            else
                tip:SetPoint("TOPLEFT", anchorTo, "TOPRIGHT", 0, -10)
            end
            anchorTo = tip
        end
    end
    shown = used > 0
end

local function SafeCompare(tooltip, index)
    local ok, err = pcall(Compare, tooltip, index)
    if not ok then geterrorhandler()(err) end
end

if GameTooltip and GameTooltip.SetTrainerService then
    hooksecurefunc(GameTooltip, "SetTrainerService", SafeCompare)
    -- Blizzard rebuilds a tooltip (Shift, item data arriving) without calling SetTrainerService
    -- again, and the rebuild's clear hides ours
    if GameTooltip.RebuildFromTooltipInfo then
        hooksecurefunc(GameTooltip, "RebuildFromTooltipInfo", function(tooltip)
            local info = tooltip.GetPrimaryTooltipInfo and tooltip:GetPrimaryTooltipInfo()
            if info and info.getterName == "GetTrainerService" and info.getterArgs then
                SafeCompare(tooltip, info.getterArgs[1])
            end
        end)
    end
    GameTooltip:HookScript("OnHide", HideOurs)
    GameTooltip:HookScript("OnTooltipCleared", HideOurs)
end

-- Trainer filters (Available / Unavailable / Already Known) reset every visit: keep the
-- player's last choices per character and put them back when a trainer opens. Only on
-- TRAINER_SHOW, so changes during the visit stand.

-- Only choices made in the trainer's filter menu count: guide addons (RXPGuides) switch every
-- filter on from code to find a recipe, which isn't the player's preference
local function PlayerChoosing()
    local dropdown = ClassTrainerFrame and ClassTrainerFrame.FilterDropdown
    return dropdown and dropdown.IsMenuOpen and dropdown:IsMenuOpen()
end

if SetTrainerServiceTypeFilter and GetTrainerServiceTypeFilter then
    hooksecurefunc("SetTrainerServiceTypeFilter", function(filter)
        if type(filter) ~= "string" or not PlayerChoosing() then return end
        MeioTrainerCompareCharDB = MeioTrainerCompareCharDB or {}
        local db = MeioTrainerCompareCharDB
        db.filters = db.filters or {}
        -- read back rather than trust the argument: callers pass 1/nil as well as booleans
        db.filters[filter] = not not GetTrainerServiceTypeFilter(filter)
    end)

    local restore = CreateFrame("Frame")
    restore:RegisterEvent("TRAINER_SHOW")
    restore:SetScript("OnEvent", function()
        local saved = MeioTrainerCompareCharDB and MeioTrainerCompareCharDB.filters
        if type(saved) ~= "table" then return end
        for filter, on in pairs(saved) do
            if on ~= not not GetTrainerServiceTypeFilter(filter) then
                SetTrainerServiceTypeFilter(filter, on)
            end
        end
    end)
end

-- The old folder (TrainerCompare, before the Meio rename) may still be installed: both would run.
-- The player is told to disable it.
local oldFolder = CreateFrame("Frame")
oldFolder:RegisterEvent("PLAYER_LOGIN")
oldFolder:SetScript("OnEvent", function()
    if not C_AddOns.IsAddOnLoaded("TrainerCompare") then return end
    print("|cffb090ffMeioTrainerCompare:|r the old TrainerCompare addon is still enabled:"
        .. " disable it in the AddOns list (MeioTrainerCompare replaces it)")
end)
