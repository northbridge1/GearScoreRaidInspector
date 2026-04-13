
-- ------------------------------------------------
-- Localization (Spanish for esES/esMX, English otherwise)
-- ------------------------------------------------
local LOCALE = GetLocale and GetLocale() or "enUS"
local IS_ES = (LOCALE == "esES" or LOCALE == "esMX")

local L = {}
if IS_ES then
    L.TITLE = "GearScore - Raid Inspector"
    L.MIN_GS = "GS mínimo:"
    L.RECALC = "Recalcular"
    L.SUMMARY = "Bajo:%d  PvP:%d  Sin:%d"

    L.INSPECT_INACTIVE = "|cffaaaaaaInspect: inactivo|r"
    L.INSPECT_DONE     = "|cff00ff00Inspect: terminado|r"
    L.INSPECT_QUEUE    = "|cffffff00Inspect: cola %d|r"
    L.INSPECT_COMBAT   = "|cffff0000Inspect: en combate|r"
    L.INSPECT_NORANGE  = "|cffaaaaaaInspect: nadie a rango|r"

    L.COL_NAME   = "Nombre"
    L.COL_GS     = "GS"
    L.COL_PVP    = "PvP"
    L.COL_STATUS = "Estado"

    L.STATUS_OK     = "OK"
    L.STATUS_LOW    = "BAJO"
    L.STATUS_NODATA = "SIN"
    L.NOT_IN_RAID = "No estás en una raid."
else
    L.TITLE = "GearScore - Raid Inspector"
    L.MIN_GS = "Min GS:"
    L.RECALC = "Recalculate"
    L.SUMMARY = "Low:%d  PvP:%d  NoData:%d"

    L.INSPECT_INACTIVE = "|cffaaaaaaInspect: inactive|r"
    L.INSPECT_DONE     = "|cff00ff00Inspect: done|r"
    L.INSPECT_QUEUE    = "|cffffff00Inspect: queue %d|r"
    L.INSPECT_COMBAT   = "|cffff0000Inspect: in combat|r"
    L.INSPECT_NORANGE  = "|cffaaaaaaInspect: nobody in range|r"

    L.COL_NAME   = "Name"
    L.COL_GS     = "GS"
    L.COL_PVP    = "PvP"
    L.COL_STATUS = "Status"

    L.STATUS_OK     = "OK"
    L.STATUS_LOW    = "LOW"
    L.STATUS_NODATA = "NO"
    L.NOT_IN_RAID = "You are not in a raid."
end

-- GearScore - Raid Inspector (integrated module)
-- Adds a raid GS window that uses GearScore's own calculation (NotifyInspect + GearScore_GetScore)

GS_RaidInspectorDB = GS_RaidInspectorDB or {}

local DEFAULTS = {
    minGS = 5000,
    autoScan = true,
    autoInspect = true,
    inspectDelay = 0.25,   -- seconds between NotifyInspect and GearScore_GetScore
    stepDelay = 0.35,      -- seconds between players in the queue
    point = "CENTER",
    relativePoint = "CENTER",
    xOfs = 0,
    yOfs = 0,
    height = 440,
}

local function ApplyDefaults()
    for k, v in pairs(DEFAULTS) do
        if GS_RaidInspectorDB[k] == nil then
            GS_RaidInspectorDB[k] = v
        end
    end
end

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[GS Raid]|r " .. (msg or ""))
end


local THEME_OUTER_BG = { 0.06, 0.07, 0.10, 0.92 }
local THEME_OUTER_BORDER = { 0.44, 0.44, 0.50, 0.92 }
local THEME_PANEL_BG = { 0.11, 0.12, 0.16, 0.86 }
local THEME_PANEL_BORDER = { 0.46, 0.46, 0.52, 0.85 }
local THEME_HEADER_BG = { 0.09, 0.10, 0.14, 0.95 }
local THEME_HEADER_BORDER = { 0.42, 0.42, 0.48, 0.92 }
local THEME_ROW_BG_A = { 0.11, 0.12, 0.16, 0.94 }
local THEME_ROW_BG_B = { 0.14, 0.15, 0.19, 0.94 }
local THEME_ROW_BORDER = { 0.34, 0.34, 0.40, 0.88 }
local TITLE_R, TITLE_G, TITLE_B = 1.00, 0.82, 0.10

local function ApplyThemeBackdrop(frame, bg, border, edgeSize, inset)
    edgeSize = edgeSize or 12
    inset = inset or 3
    frame:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = edgeSize,
        insets = { left = inset, right = inset, top = inset, bottom = inset }
    })
    bg = bg or THEME_PANEL_BG
    border = border or THEME_PANEL_BORDER
    frame:SetBackdropColor(bg[1], bg[2], bg[3], bg[4])
    if frame.SetBackdropBorderColor then
        frame:SetBackdropBorderColor(border[1], border[2], border[3], border[4])
    end
end

local function InCombat()
    -- GearScore uses GS_PlayerIsInCombat, but keep safe fallback
    if GS_PlayerIsInCombat ~= nil then
        return GS_PlayerIsInCombat
    end
    return InCombatLockdown and InCombatLockdown()
end

local function InInspectRange(unit)
    if not CheckInteractDistance then return true end
    return CheckInteractDistance(unit, 1) == 1
end

local function CanInspectUnit(unit)
    if not UnitExists(unit) then return false end
    if not UnitIsPlayer(unit) then return false end
    if UnitIsUnit(unit, "player") then return false end
    if UnitIsDeadOrGhost(unit) then return false end
    if UnitIsConnected(unit) == false then return false end
    if UnitIsVisible(unit) == false then return false end
    if InCombat() then return false end
    if CanInspect and CanInspect(unit) == false then return false end
    if not InInspectRange(unit) then return false end
    return true
end

local function GetCachedGS(name)
    if not name then return 0, 0 end
    if not GS_Data or not GS_Data[GetRealmName()] or not GS_Data[GetRealmName()].Players then
        return 0, 0
    end
    local p = GS_Data[GetRealmName()].Players[name]
    if not p then return 0, 0 end
    return tonumber(p.GearScore) or 0, tonumber(p.Average) or 0
end

local function CountPvPItems(unit)
    if not UnitExists(unit) then return 0 end
    local cnt = 0
    for slot = 1, 19 do
        local link = GetInventoryItemLink(unit, slot)
        if link then
            local stats = GetItemStats(link)
            if stats then
                local resil = stats["ITEM_MOD_RESILIENCE_RATING_SHORT"]
                           or stats["ITEM_MOD_RESILIENCE_RATING"]
                           or stats["ITEM_MOD_RESILIENCE_RATING_MELEE"]
                if resil and resil > 0 then
                    cnt = cnt + 1
                end
            end
        end
    end
    return cnt
end

-- Layout constants (keep aligned)
-- Window is intentionally narrow (about 40% narrower than the original).
-- Column X positions are tuned to avoid text going outside the frame.
local COL_X_NAME = 5
local COL_X_GS   = 125
local COL_X_PVP  = 165
local COL_X_INFO = 205

-- Widths (keep in sync with frame:SetSize below)
local FRAME_W = 276
local FRAME_H = 440
local MIN_FRAME_H = 316
local MAX_FRAME_H = 556
local INNER_W = FRAME_W - 40 -- safe width for header/text areas (accounts for margins + scrollbar)


-- Data for window
local results = {}
local resultsByName = {}

-- Frame
local frame = CreateFrame("Frame", "GearScoreRaidInspectorFrame", UIParent)
frame:SetSize(FRAME_W, GS_RaidInspectorDB.height or FRAME_H)
frame:SetMinResize(FRAME_W, MIN_FRAME_H)
frame:SetMaxResize(FRAME_W, MAX_FRAME_H)
frame:SetResizable(true)
frame:Hide()

frame:SetMovable(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
frame:SetScript("OnDragStart", frame.StartMoving)
frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    self:SetWidth(FRAME_W)
    local point, _, relativePoint, xOfs, yOfs = self:GetPoint(1)
    GS_RaidInspectorDB.point = point or DEFAULTS.point
    GS_RaidInspectorDB.relativePoint = relativePoint or DEFAULTS.relativePoint
    GS_RaidInspectorDB.xOfs = xOfs or 0
    GS_RaidInspectorDB.yOfs = yOfs or 0
    GS_RaidInspectorDB.height = math.floor(self:GetHeight() + 0.5)
end)

if frame.SetBackdrop then
    ApplyThemeBackdrop(frame, THEME_OUTER_BG, THEME_OUTER_BORDER, 16, 4)
end

frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
frame.title:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -14)
frame.title:SetText(L.TITLE)
frame.title:SetTextColor(TITLE_R, TITLE_G, TITLE_B)

local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -6, -6)

local minGSLable = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
minGSLable:SetPoint("TOPLEFT", frame, "TOPLEFT", 15, -40)
minGSLable:SetText(L.MIN_GS)

local minGSEditBox = CreateFrame("EditBox", "GearScoreRaidInspectorMinGSEditBox", frame, "InputBoxTemplate")
minGSEditBox:SetAutoFocus(false)
minGSEditBox:SetSize(60, 20)
minGSEditBox:SetPoint("LEFT", minGSLable, "RIGHT", 10, 0)
minGSEditBox:SetNumeric(true)
minGSEditBox:SetMaxLetters(4)
minGSEditBox:SetTextInsets(6, 6, 0, 0)
minGSEditBox:SetScript("OnEnterPressed", function(self)
    self:ClearFocus()
    local v = tonumber(self:GetText()) or DEFAULTS.minGS
    GS_RaidInspectorDB.minGS = v
    self:SetText(tostring(v))
end)

-- Simplified UI: Auto & Inspect are always ON (no checkboxes)

local recalcButton = CreateFrame("Button", nil, frame, "GameMenuButtonTemplate")
recalcButton:SetPoint("LEFT", minGSEditBox, "RIGHT", 6, 0)
recalcButton:SetSize(100, 22)
recalcButton:SetText(L.RECALC)
recalcButton:SetNormalFontObject(GameFontNormalSmall)
recalcButton:SetHighlightFontObject(GameFontHighlightSmall)

local resultText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
resultText:SetPoint("TOPLEFT", minGSLable, "BOTTOMLEFT", 0, -18)
resultText:SetJustifyH("LEFT")
resultText:SetWidth(INNER_W)
resultText:SetText("")
resultText:SetTextColor(0.92, 0.92, 0.92)

local inspectStatusText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
inspectStatusText:SetPoint("TOPLEFT", resultText, "BOTTOMLEFT", 0, -4)
inspectStatusText:SetJustifyH("LEFT")
inspectStatusText:SetWidth(INNER_W)
inspectStatusText:SetText(L.INSPECT_INACTIVE)
inspectStatusText:SetTextColor(0.76, 0.76, 0.80)

-- Header
local header = CreateFrame("Frame", nil, frame)
header:SetSize(INNER_W, 18)
header:SetPoint("TOPLEFT", inspectStatusText, "BOTTOMLEFT", 0, -12)
if header.SetBackdrop then
    ApplyThemeBackdrop(header, THEME_HEADER_BG, THEME_HEADER_BORDER, 10, 2)
end

local headerName = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
headerName:SetPoint("LEFT", header, "LEFT", COL_X_NAME, 0)
headerName:SetTextColor(TITLE_R, TITLE_G, TITLE_B)
headerName:SetText(L.COL_NAME)

local headerGS = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
headerGS:SetPoint("LEFT", header, "LEFT", COL_X_GS, 0)
headerGS:SetTextColor(TITLE_R, TITLE_G, TITLE_B)
headerGS:SetText("GS")

local headerPvP = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
headerPvP:SetPoint("LEFT", header, "LEFT", COL_X_PVP, 0)
headerPvP:SetTextColor(TITLE_R, TITLE_G, TITLE_B)
headerPvP:SetText("PvP")

local headerInfo = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
headerInfo:SetPoint("LEFT", header, "LEFT", COL_X_INFO, 0)
headerInfo:SetTextColor(TITLE_R, TITLE_G, TITLE_B)
headerInfo:SetText(L.COL_STATUS)

-- Scroll
local ROW_HEIGHT = 16
local VISIBLE_ROWS = 14
local MAX_ROWS = 25
local scrollFrame

local function GetVisibleRows()
    local h = (scrollFrame and scrollFrame:GetHeight()) or (VISIBLE_ROWS * ROW_HEIGHT)
    local rows = math.floor(((h - 2) / ROW_HEIGHT) + 0.0001)
    if rows < 1 then rows = 1 end
    if rows > MAX_ROWS then rows = MAX_ROWS end
    return rows
end

scrollFrame = CreateFrame("ScrollFrame", "GearScoreRaidInspectorScrollFrame", frame, "FauxScrollFrameTemplate")
scrollFrame:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -2)
scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -30, 15)

local rows = {}
local function CreateRow(index)
    local row = CreateFrame("Frame", nil, frame)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -2 - (index - 1) * ROW_HEIGHT)
    row:SetPoint("RIGHT", frame, "RIGHT", -10, 0)

    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    row.bg:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
    if (index % 2) == 0 then
        row.bg:SetTexture(THEME_ROW_BG_B[1], THEME_ROW_BG_B[2], THEME_ROW_BG_B[3], THEME_ROW_BG_B[4])
    else
        row.bg:SetTexture(THEME_ROW_BG_A[1], THEME_ROW_BG_A[2], THEME_ROW_BG_A[3], THEME_ROW_BG_A[4])
    end

    row.topLine = row:CreateTexture(nil, "BORDER")
    row.topLine:SetTexture(THEME_ROW_BORDER[1], THEME_ROW_BORDER[2], THEME_ROW_BORDER[3], 0.45)
    row.topLine:SetHeight(1)
    row.topLine:SetPoint("TOPLEFT", row, "TOPLEFT", 2, 0)
    row.topLine:SetPoint("TOPRIGHT", row, "TOPRIGHT", -2, 0)

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.name:SetPoint("LEFT", row, "LEFT", COL_X_NAME, 0)

    row.gs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.gs:SetPoint("LEFT", row, "LEFT", COL_X_GS, 0)

    row.pvp = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.pvp:SetPoint("LEFT", row, "LEFT", COL_X_PVP, 0)

    row.info = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.info:SetPoint("LEFT", row, "LEFT", COL_X_INFO, 0)
    -- Constrain the info column so text never renders outside the window.
    row.info:SetJustifyH("LEFT")
    row.info:SetWidth((FRAME_W - 10) - COL_X_INFO - 8)

    return row
end

for i = 1, MAX_ROWS do
    rows[i] = CreateRow(i)
end

local function SortResults()
    table.sort(results, function(a, b)
        local aNo = (a.gs or 0) == 0
        local bNo = (b.gs or 0) == 0
        if aNo ~= bNo then return aNo and not bNo end
        if a.belowMin ~= b.belowMin then return a.belowMin and not b.belowMin end
        return (a.gs or 0) < (b.gs or 0)
    end)
end

local function UpdateSummary()
    local minGS = GS_RaidInspectorDB.minGS or DEFAULTS.minGS
    local belowCount, pvpAnyCount, noDataCount = 0, 0, 0
    for _, e in ipairs(results) do
        local gs = tonumber(e.gs) or 0
        if gs == 0 then noDataCount = noDataCount + 1
        elseif gs < minGS then belowCount = belowCount + 1 end
        if (tonumber(e.pvpPieces) or 0) > 0 then pvpAnyCount = pvpAnyCount + 1 end
    end
    -- Short text to fit the narrow window
    resultText:SetText(string.format(L.SUMMARY, belowCount, pvpAnyCount, noDataCount))
end

local function UpdateList()
    local total = #results
    local visibleRows = GetVisibleRows()
    FauxScrollFrame_Update(scrollFrame, total, visibleRows, ROW_HEIGHT)
    local offset = FauxScrollFrame_GetOffset(scrollFrame)

    for i = 1, MAX_ROWS do
        local row = rows[i]
        local index = i + offset
        local data = results[index]

        if i > visibleRows then
            row.name:SetText("")
            row.gs:SetText("")
            row.pvp:SetText("")
            row.info:SetText("")
            row:Hide()
        elseif data then
            local classColor = RAID_CLASS_COLORS[data.classFile or "PRIEST"] or { r = 1, g = 1, b = 1 }
            local cname = string.format("|cff%02x%02x%02x%s|r",
                classColor.r * 255, classColor.g * 255, classColor.b * 255, data.name or "???")
            row.name:SetText(cname)

            if (data.gs or 0) > 0 then
                row.gs:SetText((data.belowMin and "|cffff0000" or "|cff00ff00") .. tostring(data.gs) .. "|r")
            else
                row.gs:SetText("|cffaaaaaa—|r")
            end

            local p = tonumber(data.pvpPieces) or 0
            if p == 0 then
                row.pvp:SetText("|cffaaaaaa0|r")
            elseif p <= 2 then
                row.pvp:SetText("|cffffff001-2|r")
            else
                row.pvp:SetText("|cffffa500" .. tostring(p) .. "|r")
            end

            -- Keep status short so it fits the narrow window.
            local statusText
            if (data.gs or 0) == 0 then
                statusText = "|cffaaaaaa" .. L.STATUS_NODATA .. "|r"
            elseif data.belowMin then
                statusText = "|cffff0000" .. L.STATUS_LOW .. "|r"
            else
                statusText = "|cff00ff00" .. L.STATUS_OK .. "|r"
            end

            if p > 0 then
                statusText = statusText .. " " .. (p <= 2 and "|cffffff00PvP|r" or "|cffffa500PvP+|r")
            end
            row.info:SetText(statusText)

            row:Show()
        else
            row.name:SetText("")
            row.gs:SetText("")
            row.pvp:SetText("")
            row.info:SetText("")
            row:Hide()
        end
    end
end

scrollFrame:SetScript("OnVerticalScroll", function(self, offset)
    FauxScrollFrame_OnVerticalScroll(self, offset, ROW_HEIGHT, UpdateList)
end)


frame:SetScript("OnSizeChanged", function(self, width, height)
    if width ~= FRAME_W then
        self:SetWidth(FRAME_W)
    end
    if height < MIN_FRAME_H then
        self:SetHeight(MIN_FRAME_H)
        height = MIN_FRAME_H
    elseif height > MAX_FRAME_H then
        self:SetHeight(MAX_FRAME_H)
        height = MAX_FRAME_H
    end
    GS_RaidInspectorDB.height = math.floor(height + 0.5)
    UpdateList()
end)

local resizeGrip = CreateFrame("Button", nil, frame)
resizeGrip:SetSize(16, 16)
resizeGrip:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -4, 4)
resizeGrip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
resizeGrip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
resizeGrip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
resizeGrip:SetScript("OnMouseDown", function(self, button)
    if button == "LeftButton" then
        frame:StartSizing("BOTTOMRIGHT")
    end
end)
resizeGrip:SetScript("OnMouseUp", function(self)
    frame:StopMovingOrSizing()
    frame:SetWidth(FRAME_W)
    GS_RaidInspectorDB.height = math.floor(frame:GetHeight() + 0.5)
    UpdateList()
end)

-- Scan
local function ScanRaid()
    wipe(results)
    wipe(resultsByName)

    local minGS = tonumber(minGSEditBox:GetText()) or DEFAULTS.minGS
    GS_RaidInspectorDB.minGS = minGS

    local members = GetNumRaidMembers()
    if members == 0 then
        Print(L.NOT_IN_RAID)
        resultText:SetText("|cffff0000" .. L.NOT_IN_RAID .. "|r")
        UpdateList()
        return
    end

    for i = 1, members do
        local name, _, subgroup, _, _, fileName = GetRaidRosterInfo(i)
        if name and subgroup and subgroup <= 8 and #results < MAX_ROWS then
            local unit = "raid" .. i
            local gs = select(1, GetCachedGS(name))
            local pvpPieces = CountPvPItems(unit)
            local belowMin = (gs > 0 and gs < minGS) or false

            local entry = {
                name = name,
                unit = unit,
                classFile = fileName,
                gs = gs,
                pvpPieces = pvpPieces,
                belowMin = belowMin,
            }

            table.insert(results, entry)
            resultsByName[name] = entry
        end
    end

    SortResults()
    UpdateList()
    UpdateSummary()
end


-------------------------------------------------
-- Recalc Queue (SMART mode)
-- Objetivo: rapidez cuando los links de equipo llegan rápido (como manual),
-- pero con fallback automático a modo seguro si hay lag / no llegan los links.
-------------------------------------------------
local inspectQueue = {}
local queued = {}

-- Estados:
-- idle  : elegir siguiente unit y lanzar NotifyInspect
-- probe : comprobar si los links de equipo ya están disponibles (fast path)
-- score : llamar a GearScore_GetScore y refrescar UI (safe path / retries)
local state = "idle"
local curUnit, curName = nil, nil
local curPrevGS = 0
local curAttempt = 0

-- Tiempos
local tNext = 0
local tProbeEnd = 0
local tScoreAt = 0

-- Parámetros (modo inteligente)
local PROBE_INTERVAL = 0.05      -- cada cuánto comprobamos si ya hay links
local AGGRESSIVE_MAX = 0.35      -- máximo tiempo "rápido" esperando links
local SAFE_DELAY_1  = 0.25       -- espera extra antes de calcular (intento 1 fallback)
local SAFE_DELAY_2  = 0.40       -- espera extra antes de recalcular (intento 2)
local FAST_SETTLE  = 0.18       -- espera corta incluso en fast-path (transmog-safe)
local STEP_FAST     = 0.15       -- delay entre jugadores si todo va bien
local STEP_SAFE     = 0.35       -- delay entre jugadores si hubo fallback / reintento
local MAX_ATTEMPTS  = 4          -- 1: notify+probe, 2: safe rescore, 3: re-notify

local function QueueUnit(unit)
    local name = UnitName(unit)
    if not name or queued[name] then return end
    queued[name] = true
    table.insert(inspectQueue, unit)
end

local function LinksReady(unit)
    -- Heurística barata: cuando el cliente tiene datos de inspección,
    -- suelen aparecer varios links de golpe.
    if not unit or not UnitExists(unit) then return false end
    local ready = 0
    -- slots más representativos
    local slots = {1,3,5,7,8,9,10,11,12,13,14,15,16,17,18}
    for i=1,#slots do
        if GetInventoryItemLink(unit, slots[i]) then
            ready = ready + 1
            if ready >= 8 then
                return true
            end
        end
    end
    return false
end

local function BuildRecalcQueue()
    wipe(inspectQueue)
    wipe(queued)

    local bucketNoData, bucketBelow, bucketRest = {}, {}, {}
    for _, e in ipairs(results) do
        if e.unit and CanInspectUnit(e.unit) then
            if (e.gs or 0) == 0 then
                table.insert(bucketNoData, e.unit)
            elseif e.belowMin then
                table.insert(bucketBelow, e.unit)
            else
                table.insert(bucketRest, e.unit)
            end
        end
    end

    for _, u in ipairs(bucketNoData) do QueueUnit(u) end
    for _, u in ipairs(bucketBelow)  do QueueUnit(u) end
    for _, u in ipairs(bucketRest)   do QueueUnit(u) end

    if #inspectQueue > 0 then
        inspectStatusText:SetText("|cffffff00Inspect: RECALC " .. tostring(#inspectQueue) .. "|r")
    else
        inspectStatusText:SetText(L.INSPECT_NORANGE)
    end

    state = "idle"
    curUnit, curName = nil, nil
    curAttempt = 0
    tNext = GetTime() + 0.05
end


recalcButton:SetScript("OnClick", function()
    ScanRaid() -- asegura que la ventana muestra el cache actual
    BuildRecalcQueue()
end)

-- Auto scan on roster changes (only when window open)
local lastAuto = 0
local function MaybeAutoScan()
    if not frame:IsShown() then return end
    local now = GetTime()
    if (now - lastAuto) < 2.0 then return end
    lastAuto = now
    ScanRaid()
end

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("RAID_ROSTER_UPDATE")

frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == "GearScore" then
        ApplyDefaults()
        minGSEditBox:SetText(tostring(GS_RaidInspectorDB.minGS or DEFAULTS.minGS))

        local savedH = GS_RaidInspectorDB.height or FRAME_H
        if savedH < MIN_FRAME_H then savedH = MIN_FRAME_H end
        if savedH > MAX_FRAME_H then savedH = MAX_FRAME_H end
        frame:SetSize(FRAME_W, savedH)

        frame:ClearAllPoints()
        frame:SetPoint(
            GS_RaidInspectorDB.point or DEFAULTS.point,
            UIParent,
            GS_RaidInspectorDB.relativePoint or DEFAULTS.relativePoint,
            GS_RaidInspectorDB.xOfs or 0,
            GS_RaidInspectorDB.yOfs or 0
        )

        Print("módulo Raid Inspector cargado. Usa /rgs para abrir.")
    elseif event == "RAID_ROSTER_UPDATE" then
        MaybeAutoScan()
    end
end)

frame:SetScript("OnUpdate", function(self, elapsed)
    if not frame:IsShown() then return end
    if InCombat() then return end
    if GetTime() < (tNext or 0) then return end

    -- No hay cola
    if state == "idle" and #inspectQueue == 0 then
        return
    end

    if state == "idle" then
        -- Pop siguiente unit aún inspectable
        local unit
        while #inspectQueue > 0 do
            unit = table.remove(inspectQueue, 1)
            if unit and CanInspectUnit(unit) then break end
            unit = nil
        end
        if not unit then
            inspectStatusText:SetText("|cffaaaaaaInspect: nada a rango|r")
            return
        end

        curUnit = unit
        curName = UnitName(unit)
        curPrevGS = select(1, GetCachedGS(curName))
        curAttempt = 1

        NotifyInspect(curUnit)
        tProbeEnd = GetTime() + AGGRESSIVE_MAX
        state = "probe"
        inspectStatusText:SetText("|cffffff00Inspect: " .. (curName or "?") .. " (" .. tostring(#inspectQueue) .. " en cola)|r")
        tNext = GetTime() + PROBE_INTERVAL
        return
    end

    if state == "probe" then
        if not curUnit or not curName or not UnitExists(curUnit) then
            state = "idle"
            tNext = GetTime() + STEP_SAFE
            return
        end

        -- Fast path: si los links ya están, calculamos YA
        if LinksReady(curUnit) then
            tScoreAt = GetTime() + FAST_SETTLE
            state = "score"
            tNext = GetTime() + 0.01
            return
        end

        -- Si se agota el tiempo "agresivo", pasamos a modo seguro
        if GetTime() >= tProbeEnd then
            tScoreAt = GetTime() + SAFE_DELAY_1
            state = "score"
            tNext = GetTime() + 0.05
            return
        end

        tNext = GetTime() + PROBE_INTERVAL
        return
    end

    if state == "score" then
        if GetTime() < (tScoreAt or 0) then
            tNext = GetTime() + 0.05
            return
        end

        if not curUnit or not curName or not UnitExists(curUnit) then
            state = "idle"
            tNext = GetTime() + STEP_SAFE
            return
        end

        -- Pedimos a GearScore que calcule
        if GearScore_GetScore and type(GearScore_GetScore) == "function" then
            pcall(GearScore_GetScore, curName, curUnit)
        end

        local newGS = select(1, GetCachedGS(curName))

        -- Transmog-safe: a veces los links llegan primero con items de "apariencia" (GS bajo)
        -- y el GS real tarda un poco más. Si vemos una caída grande vs el GS previo, esperamos y re-score.
        if (newGS > 0) and (curPrevGS and curPrevGS > 0) and ((curPrevGS - newGS) >= 350) and (curAttempt == 1) then
            curAttempt = 2
            tScoreAt = GetTime() + (SAFE_DELAY_2 + 0.25)
            tNext = GetTime() + 0.05
            return
        end


        -- Si no hay datos aún, reintentos inteligentes
        if (newGS == 0) and (curAttempt < MAX_ATTEMPTS) then
            curAttempt = curAttempt + 1

            if curAttempt == 2 then
                -- Re-score sin re-notify, esperando un poco más
                tScoreAt = GetTime() + SAFE_DELAY_2
                tNext = GetTime() + 0.05
                return
            else
                -- Último intento: re-notify y volver a probe (útil con lag)
                NotifyInspect(curUnit)
                tProbeEnd = GetTime() + (AGGRESSIVE_MAX + 0.25)
                state = "probe"
                tNext = GetTime() + PROBE_INTERVAL
                return
            end
        end

        -- Actualizar UI (aunque el GS no cambie, refresca PvP / estado)
        local entry = resultsByName[curName]
        if entry then
            entry.gs = newGS
            entry.pvpPieces = CountPvPItems(curUnit)
            local minGS = GS_RaidInspectorDB.minGS or DEFAULTS.minGS
            entry.belowMin = (newGS > 0 and newGS < minGS) or false
            SortResults()
            UpdateList()
            UpdateSummary()
        end

        -- Siguiente jugador: step dinámico
        local step = (curAttempt > 1) and STEP_SAFE or STEP_FAST

        curUnit, curName = nil, nil
        state = "idle"
        tNext = GetTime() + step

        if #inspectQueue == 0 then
            inspectStatusText:SetText(L.INSPECT_DONE)
        end
        return
    end
end)

-- Slash command: open window
SLASH_GSRAIDINSPECTOR1 = "/rgs"
SLASH_GSRAIDINSPECTOR2 = "/gsraid"
SlashCmdList["GSRAIDINSPECTOR"] = function(msg)
    if frame:IsShown() then
        frame:Hide()
    else
        frame:Show()
        ScanRaid()
    end
end
