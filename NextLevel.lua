-- NextLevel.lua – standalone, fully optimized

--[[-----------------------------------------------------------------------------
    1. Core constants & state
------------------------------------------------------------------------------]]
local GetTime, UnitStat, UnitHealthMax = GetTime, UnitStat, UnitHealthMax
local math_sin, math_ceil, math_min, math_floor, math_max, math_pi = math.sin, math.ceil, math.min, math.floor, math.max, math.pi
local tinsert, tremove, tlen = table.insert, table.remove, table.getn
local ipairs, pairs = ipairs, pairs

local GOLD, WHITE, GREEN = {r=1,g=0.8,b=0}, {r=1,g=1,b=1}, {r=0,g=1,b=0}
local EaseOut = function(p) return 1 - (1 - p)^2 end  -- cubic ease-out

local STAT_ROW_HEIGHT, STAT_ROW_WIDTH, STAT_FONT_SIZE = 25, 300, 11
local UNLOCK_ROW_HEIGHT, UNLOCK_ROW_WIDTH, UNLOCK_FONT_SIZE = 30, 300, 11
local UNLOCK_ICON_SIZE, UNLOCK_GAP, UNLOCK_ROW_SPACING, UNLOCK_ROWS_PER_PAGE = 20, 6, 30, 6

local unlockState = { page = 1, total = 1, data = {} }  -- pagination state

local STAT_DEFS = {
    { key = "str", name = "Strength",  index = 1 },
    { key = "agi", name = "Agility",   index = 2 },
    { key = "sta", name = "Stamina",   index = 3 },
    { key = "int", name = "Intellect", index = 4 },
    { key = "spi", name = "Spirit",    index = 5 },
}

-- Pre‑level snapshot (updated every 0.1s)
local preLevelStats, preLevelHealth = {}, 0
local snapshotTimer = CreateFrame("Frame")
local nextSnapshot = 0
snapshotTimer:SetScript("OnUpdate", function()
    nextSnapshot = nextSnapshot - arg1
    if nextSnapshot <= 0 then
        for _, s in ipairs(STAT_DEFS) do preLevelStats[s.key] = UnitStat("player", s.index) or 0 end
        preLevelHealth = UnitHealthMax("player") or 0
        nextSnapshot = 0.1
    end
end)
snapshotTimer:Show()

--[[-----------------------------------------------------------------------------
    2. Trainer scanner (persistent)
     – Scans class trainer services and stores skill name + icon per level.
     – Prevents duplicates by checking existing entries.
------------------------------------------------------------------------------]]
local _, playerClass = UnitClass("player")
if not NextLevel_TrainerDB then NextLevel_TrainerDB = {} end

local function ScanTrainer()
    local fAv = GetTrainerServiceTypeFilter("available") or 1
    local fUn = GetTrainerServiceTypeFilter("unavailable") or 1
    local fUs = GetTrainerServiceTypeFilter("used") or 1
    SetTrainerServiceTypeFilter("available",1); SetTrainerServiceTypeFilter("unavailable",1); SetTrainerServiceTypeFilter("used",1)
    ExpandTrainerSkillLine(0)
    local num = GetNumTrainerServices()
    if num and num > 0 then
        local classDB = NextLevel_TrainerDB[playerClass] or {}
        NextLevel_TrainerDB[playerClass] = classDB
        for i=1,num do
            local name, sub, st, _,_,_,_,_,_,_, isTrade = GetTrainerServiceInfo(i)
            local req = GetTrainerServiceLevelReq(i)
            local icon = GetTrainerServiceIcon(i)
            if st~="header" and st~="used" and not isTrade and name and req then
                req = tonumber(req)
                local levelList = classDB[req] or {}
                classDB[req] = levelList
                local full = sub and sub~="" and (name.." ("..sub..")") or name
                local exists = false
                for _,e in ipairs(levelList) do if e.name==full then exists=true break end end
                if not exists then tinsert(levelList, { name=full, icon=icon }) end
            end
        end
    end
    SetTrainerServiceTypeFilter("available",fAv); SetTrainerServiceTypeFilter("unavailable",fUn); SetTrainerServiceTypeFilter("used",fUs)
end

--[[-----------------------------------------------------------------------------
    3. Animation system
     – Manual counter for animations (avoids table.getn).
     – StartAnimation, Animate, Delay helpers.
------------------------------------------------------------------------------]]
local animations, animCount, animFrame = {}, 0, CreateFrame("Frame")
animFrame:Hide()
animFrame:SetScript("OnUpdate", function()
    local now = GetTime()
    local i = 1
    while i <= animCount do
        local a = animations[i]
        if now >= a.endTime then
            a.func(1)
            if a.complete then a.complete() end
            animations[i] = animations[animCount]  -- move last to current slot
            animations[animCount] = nil
            animCount = animCount - 1
        else
            a.func((now - a.startTime)/a.duration)
            i = i + 1
        end
    end
    if animCount == 0 then animFrame:Hide() end
end)

local function StartAnimation(dur, func, complete)
    if animCount == 0 then animFrame:Show() end
    local now = GetTime()
    animCount = animCount + 1
    animations[animCount] = { startTime=now, endTime=now+dur, duration=dur, func=func, complete=complete }
end

local function StopAllAnimations() animations={}; animCount=0; animFrame:Hide() end

local noop = function() end
local function Delay(t, func) StartAnimation(t, noop, func) end  -- delay with no update
local function Animate(dur, update, done) StartAnimation(dur, update, done) end

-- Helpers for setting two frames at once (common in banner animations)
local function SetWidth2(f1, f2, w) f1:SetWidth(w); f2:SetWidth(w) end
local function SetAlpha2(f1, f2, a) f1:SetAlpha(a); f2:SetAlpha(a) end

--[[-----------------------------------------------------------------------------
    4. THEME SYSTEM
     – Centralized colors, font, and gradient creation.
     – SplitGradient creates left/right halves with optional top/bottom offsets.
------------------------------------------------------------------------------]]
local THEME = {}
THEME.colors = { backdrop={r=0,g=0,b=0,a=0.7}, border={r=1,g=0.95,b=0.7}, statBorder={r=0.6,g=0.6,b=0.6} }
THEME.font = "Fonts\\FRIZQT__.TTF"
THEME.backdropTopOffset, THEME.backdropBottomOffset = 0.8, -0.8

local function CreateGradient(p, r,g,b, a1,a2)
    local tex = p:CreateTexture(nil,"ARTWORK")
    tex:SetTexture(r,g,b,1)
    tex:SetGradientAlpha("HORIZONTAL", r,g,b, a1, r,g,b, a2)
    return tex
end

function THEME:SplitGradient(f, r,g,b, a1,a2, to, bo)
    to = to or 0; bo = bo or 0
    local l = CreateGradient(f, r,g,b, 0, a1)
    l:SetPoint("LEFT",f,"LEFT"); l:SetPoint("RIGHT",f,"CENTER"); l:SetPoint("TOP",f,"TOP",0,to); l:SetPoint("BOTTOM",f,"BOTTOM",0,bo)
    local rgt = CreateGradient(f, r,g,b, a2, 0)
    rgt:SetPoint("LEFT",f,"CENTER"); rgt:SetPoint("RIGHT",f,"RIGHT"); rgt:SetPoint("TOP",f,"TOP",0,to); rgt:SetPoint("BOTTOM",f,"BOTTOM",0,bo)
end

function THEME:ApplyBackdrop(f) local c=self.colors.backdrop; self:SplitGradient(f,c.r,c.g,c.b, c.a,c.a, self.backdropTopOffset,self.backdropBottomOffset) end
function THEME:ApplyBorderLine(f,color) self:SplitGradient(f,color.r,color.g,color.b, 1,1,0,0) end

function THEME:CreateStyledFrame(parent,w,h,borderColor,thick)
    local f = CreateFrame("Frame", nil, parent)
    f:SetWidth(w); f:SetHeight(h)
    self:ApplyBackdrop(f)
    local top = CreateFrame("Frame", nil, f)
    top:SetPoint("TOP",f,"TOP"); top:SetWidth(w); top:SetHeight(thick or 1); top:SetFrameLevel(f:GetFrameLevel()+5)
    self:ApplyBorderLine(top, borderColor)
    local bot = CreateFrame("Frame", nil, f)
    bot:SetPoint("BOTTOM",f,"BOTTOM"); bot:SetWidth(w); bot:SetHeight(thick or 1); bot:SetFrameLevel(f:GetFrameLevel()+5)
    self:ApplyBorderLine(bot, borderColor)
    return f
end

-- Font and texture factories (simplify creation)
local function CreateFont(parent, size, point, relTo, relPoint, x, y)
    local f = parent:CreateFontString(nil, "OVERLAY")
    f:SetFont(THEME.font, size)
    f:SetPoint(point, relTo, relPoint, x or 0, y or 0)
    return f
end

local function CreateTexture(parent, w, h, point, relTo, relPoint, x, y)
    local tex = parent:CreateTexture(nil, "OVERLAY")
    tex:SetWidth(w); tex:SetHeight(h)
    tex:SetPoint(point, relTo, relPoint, x or 0, y or 0)
    return tex
end

--[[-----------------------------------------------------------------------------
    5. UI creation (main banner)
------------------------------------------------------------------------------]]
local container = CreateFrame("Frame", nil, UIParent)
container:SetWidth(350); container:SetHeight(60)
container:SetPoint("CENTER", UIParent, "CENTER", 0, 250)
container:SetFrameStrata("DIALOG"); container:SetBackdrop(nil); container:Hide()

local borderFrame = CreateFrame("Frame", nil, container)
borderFrame:SetAllPoints(container); borderFrame:SetFrameLevel(2)

local backdropFrame = CreateFrame("Frame", nil, container)
backdropFrame:SetWidth(350); backdropFrame:SetHeight(60)
backdropFrame:SetPoint("BOTTOM", container, "BOTTOM", 0, 0)
backdropFrame:SetFrameLevel(1)
THEME:ApplyBackdrop(backdropFrame)

-- Thin top/bottom borders
local topBorderFrame = CreateFrame("Frame", nil, borderFrame)
topBorderFrame:SetPoint("CENTER", borderFrame, "CENTER", 0, borderFrame:GetHeight()/2 - 0.5)
topBorderFrame:SetWidth(0); topBorderFrame:SetHeight(0.5); topBorderFrame:SetFrameLevel(3)
local bottomBorderFrame = CreateFrame("Frame", nil, borderFrame)
bottomBorderFrame:SetPoint("CENTER", borderFrame, "CENTER", 0, -borderFrame:GetHeight()/2 + 0.5)
bottomBorderFrame:SetWidth(0); bottomBorderFrame:SetHeight(0.5); bottomBorderFrame:SetFrameLevel(3)
THEME:ApplyBorderLine(topBorderFrame, THEME.colors.border)
THEME:ApplyBorderLine(bottomBorderFrame, THEME.colors.border)

local textFrame = CreateFrame("Frame", nil, container)
textFrame:SetAllPoints(container); textFrame:SetFrameLevel(5)

local headerText = textFrame:CreateFontString(nil, "OVERLAY")
headerText:SetPoint("TOP", textFrame, "TOP", 0, -10)
headerText:SetFont(THEME.font, 14); headerText:SetText("|cFFFFFFFFYou've reached|r")

local levelText = textFrame:CreateFontString(nil, "OVERLAY")
levelText:SetPoint("BOTTOM", textFrame, "BOTTOM", 0, 10)
levelText:SetFont(THEME.font, 20)

-- Shimmer effect (gold beam sweeping)
local shimmerFrame = CreateFrame("Frame", nil, container)
shimmerFrame:SetFrameLevel(textFrame:GetFrameLevel() + 10); shimmerFrame:Hide()
local beamWidth, centerWidth = 200, 10
local beamHeight = container:GetHeight() or 60
local edgeWidth = (beamWidth - centerWidth) / 2
shimmerFrame:SetWidth(beamWidth); shimmerFrame:SetHeight(beamHeight)

if edgeWidth > 0 then
    local left = CreateGradient(shimmerFrame, 1,0.8,0, 0,0.3)
    left:SetWidth(edgeWidth); left:SetHeight(beamHeight)
    left:SetPoint("LEFT", shimmerFrame, "LEFT", 0, 0)
end
local center = shimmerFrame:CreateTexture(nil, "OVERLAY")
center:SetWidth(centerWidth); center:SetHeight(beamHeight)
center:SetPoint("LEFT", shimmerFrame, "LEFT", edgeWidth, 0)
center:SetTexture(1,1,1,0.25)
if edgeWidth > 0 then
    local right = CreateGradient(shimmerFrame, 1,0.8,0, 0.3,0)
    right:SetWidth(edgeWidth); right:SetHeight(beamHeight)
    right:SetPoint("LEFT", shimmerFrame, "LEFT", edgeWidth + centerWidth, 0)
end

-- Row containers (positioned below banner text)
local statRowsContainer = CreateFrame("Frame", nil, textFrame); statRowsContainer:Hide()
local unlockRowsContainer = CreateFrame("Frame", nil, textFrame); unlockRowsContainer:Hide()

--[[-----------------------------------------------------------------------------
    6. Row pools & factories (generic)
     – Reusable rows to avoid recreation.
     – CreateStatRow / CreateUnlockRow build once, then reused.
------------------------------------------------------------------------------]]
local statRowPool, unlockRowPool = {}, {}
local statRowFrames, unlockRowFrames = {}, {}

local function CreateRowBase(w,h,color) return THEME:CreateStyledFrame(nil, w, h, color, 0) end

local function CreateStatRow()
    local row = CreateRowBase(STAT_ROW_WIDTH, STAT_ROW_HEIGHT, THEME.colors.statBorder)
    row.arrowTexture = CreateTexture(row, 12, 12, "LEFT", row, "LEFT", 164, 0)
    row.arrowTexture:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
    row.oldValueText = CreateFont(row, STAT_FONT_SIZE, "RIGHT", row, "LEFT", 160, 0)
    row.label = CreateFont(row, STAT_FONT_SIZE, "RIGHT", row.oldValueText, "LEFT", -2, 0)
    row.newValueText = CreateFont(row, STAT_FONT_SIZE, "LEFT", row.arrowTexture, "RIGHT", 4, 0)
    row.gainText = CreateFont(row, STAT_FONT_SIZE, "LEFT", row, "LEFT", 210, 0)
    row.gainText:SetTextColor(0,1,0)
    return row
end

local function CreateUnlockRow()
    local row = CreateRowBase(UNLOCK_ROW_WIDTH, UNLOCK_ROW_HEIGHT-2, THEME.colors.statBorder)
    row.icon = CreateTexture(row, UNLOCK_ICON_SIZE, UNLOCK_ICON_SIZE, "LEFT", row, "LEFT", 10, 0)
    row.line1 = CreateFont(row, UNLOCK_FONT_SIZE-2, "TOPLEFT", row.icon, "TOPRIGHT", UNLOCK_GAP, 0)
    row.line2 = CreateFont(row, UNLOCK_FONT_SIZE, "TOPLEFT", row.line1, "BOTTOMLEFT", 0, -1)
    return row
end

local function GetRow(pool, createFunc)
    if pool[1] then return tremove(pool) end
    return createFunc()
end

local function GetStatRow() return GetRow(statRowPool, CreateStatRow) end
local function GetUnlockRow() return GetRow(unlockRowPool, CreateUnlockRow) end

local function ReleaseRow(row, pool, resetFunc)
    row:Hide()
    resetFunc(row)
    tinsert(pool, row)
end

local function ResetStatRow(row)
    row.label:SetText("")
    row.oldValueText:SetText("")
    row.newValueText:SetText("")
    row.gainText:SetText("")
    -- Reset font and color in case the pop animation left them modified
    row.newValueText:SetFont(THEME.font, STAT_FONT_SIZE)
    row.newValueText:SetTextColor(1,1,1)
end

local function ResetUnlockRow(row)
    row.icon:SetTexture(nil)
    row.line1:SetText("")
    row.line2:SetText("")
    row:SetAlpha(1)
end

local function ReleaseAllRows()
    for _, r in ipairs(statRowFrames) do ReleaseRow(r, statRowPool, ResetStatRow) end
    for _, r in ipairs(unlockRowFrames) do ReleaseRow(r, unlockRowPool, ResetUnlockRow) end
    statRowFrames = {}; unlockRowFrames = {}
end

--[[-----------------------------------------------------------------------------
    7. Generic row reveal
     – Reveals rows sequentially with a custom animation function and delay.
------------------------------------------------------------------------------]]
local function RevealRows(rows, animateFunc, delayBetween, onDone)
    local function step(i)
        if i > tlen(rows) then
            if onDone then onDone() end
            return
        end
        local row = rows[i]
        row:Show()
        animateFunc(row)
        Delay(delayBetween, function() step(i+1) end)
    end
    step(1)
end

--[[-----------------------------------------------------------------------------
    8. Animation sequences
     – Banner appearance, shimmer, fade, stat row animation, unlock row animation.
------------------------------------------------------------------------------]]
local function PlayMainBannerAnimation(cb)
    SetWidth2(topBorderFrame, bottomBorderFrame, 0)
    SetAlpha2(backdropFrame, textFrame, 0)
    local dur = 0.4
    StartAnimation(dur, function(p)
        topBorderFrame:SetWidth(350*p); bottomBorderFrame:SetWidth(350*p)
        backdropFrame:SetAlpha(p); textFrame:SetAlpha(p)
    end, function()
        SetWidth2(topBorderFrame, bottomBorderFrame, 350)
        SetAlpha2(backdropFrame, textFrame, 1)
        if cb then cb() end
    end)
end

local function PlayGoldShimmer()
    local cW = container:GetWidth()
    local bW = shimmerFrame:GetWidth()
    local sX = -bW/2; local eX = cW - bW/2
    local lastX
    shimmerFrame:SetPoint("LEFT", container, "LEFT", sX, 0)
    shimmerFrame:SetAlpha(0); shimmerFrame:Show()
    StartAnimation(0.5, function(p)
        local x = sX + (eX - sX)*p
        if x ~= lastX then shimmerFrame:SetPoint("LEFT", container, "LEFT", x, 0); lastX = x end
        shimmerFrame:SetAlpha(math_sin(p*math_pi)^0.7)
    end, function() shimmerFrame:Hide() end)
end

local function StartFade()
    local fadeDur = 4.0
    local statAlphas = {}
    for i, row in ipairs(statRowFrames) do statAlphas[i] = row:GetAlpha() end
    StartAnimation(fadeDur, function(p)
        local a = 1 - p
        container:SetAlpha(a)
        for i, row in ipairs(statRowFrames) do if statAlphas[i] then row:SetAlpha(statAlphas[i] * a) end end
    end, function()
        container:Hide(); container:SetAlpha(1)
        SetWidth2(topBorderFrame, bottomBorderFrame, 0)
        backdropFrame:SetHeight(60); backdropFrame:SetAlpha(1)
        textFrame:SetAlpha(1)
        ReleaseAllRows()
    end)
end

-- Main stat row animation: fade + slide in, arrow slide, new value slide & count
local function AnimateRowAppear(row, dur, onDone)
    row:SetAlpha(0)
    local point, relativeTo, relativePoint, x, y = row:GetPoint()
    local startY = y - 10
    local p, rt, rp = point, relativeTo, relativePoint
    row:SetPoint(p, rt, rp, x, startY)

    Animate(dur, function(t)
        local e = EaseOut(t)
        row:SetAlpha(e)
        row:SetPoint(p, rt, rp, x, startY + 10*e)
    end, function()
        row:SetPoint(p, rt, rp, x, y)

        local arrow = row.arrowTexture
        local newVal = row.newValueText
        local oldVal, newValNum = row.oldValue, row.newValue

        -- Arrow slide
        arrow:SetAlpha(0)
        local lastArrowX
        Animate(0.5, function(t)
            local e = EaseOut(t)
            local xPos = 159 + (164 - 159)*e
            if xPos ~= lastArrowX then arrow:SetPoint("LEFT", row, "LEFT", xPos, 0); lastArrowX = xPos end
            arrow:SetAlpha(e^0.7)
        end, function()
            arrow:SetPoint("LEFT", row, "LEFT", 164, 0); arrow:SetAlpha(1)
        end)

        -- Stat slide & counting (start after a short delay)
        Delay(0.1, function()
            newVal:SetText(oldVal)
            newVal:SetAlpha(0)
            local lastNewX
            Animate(0.8, function(t)
                local e = EaseOut(t)
                local xPos = 170 + (180 - 170)*e
                if xPos ~= lastNewX then newVal:SetPoint("LEFT", row, "LEFT", xPos, 0); lastNewX = xPos end
                newVal:SetAlpha(e^0.7)
            end, function()
                newVal:SetPoint("LEFT", row, "LEFT", 180, 0); newVal:SetAlpha(1)
            end)
            Animate(0.8, function(t)
                newVal:SetText(math_floor(oldVal + (newValNum - oldVal)*t))
            end, function()
                newVal:SetText(newValNum)
                Animate(0.25, function(t)
                    local s = math_sin(t*math_pi)
                    newVal:SetFont(THEME.font, STAT_FONT_SIZE + 6*s)
                    local r = WHITE.r + (GOLD.r - WHITE.r)*s
                    local g = WHITE.g + (GOLD.g - WHITE.g)*s
                    local b = WHITE.b + (GOLD.b - WHITE.b)*s
                    newVal:SetTextColor(r,g,b)
                end, function()
                    newVal:SetFont(THEME.font, STAT_FONT_SIZE)
                    newVal:SetTextColor(1,1,1)
                    if onDone then Delay(0.3, onDone) end
                end)
            end)
        end)
    end)
end

-- Green gain text pop
local function AnimateGainText(row, cb)
    local gain = row.gainText
    gain:SetAlpha(0)
    gain:SetFont(THEME.font, STAT_FONT_SIZE)
    StartAnimation(0.3, function(p)
        local s = math_sin(p*math_pi)
        gain:SetFont(THEME.font, STAT_FONT_SIZE + 8*s)
        gain:SetAlpha(p < 0.2 and p/0.2 or 1)
        local r = WHITE.r + (GREEN.r - WHITE.r)*s
        local g = WHITE.g + (GREEN.g - WHITE.g)*s
        local b = WHITE.b + (GREEN.b - WHITE.b)*s
        gain:SetTextColor(r,g,b)
    end, function()
        gain:SetFont(THEME.font, STAT_FONT_SIZE)
        gain:SetAlpha(1); gain:SetTextColor(0,1,0)
        if cb then cb() end
    end)
end

-- Unlock row animation (icon slides in, text fades in)
local function AnimateUnlockRow(row, dur, cb)
    local icon, line1, line2 = row.icon, row.line1, row.line2
    if not icon then return AnimateRowAppear(row, dur, cb) end
    icon:SetAlpha(0); line1:SetAlpha(0); line2:SetAlpha(0)
    local startX = -20
    local lastIconX
    icon:SetPoint("LEFT", row, "LEFT", 10 + startX, 0)
    StartAnimation(dur, function(p)
        local e = EaseOut(p)
        row:SetAlpha(e)
        icon:SetAlpha(e)
        local newX = 10 + startX + (-startX*e)
        if newX ~= lastIconX then icon:SetPoint("LEFT", row, "LEFT", newX, 0); lastIconX = newX end
        local t = math_max(0, p-0.25)/0.75
        line1:SetAlpha(t); line2:SetAlpha(t)
    end, function()
        icon:SetPoint("LEFT", row, "LEFT", 10, 0)
        line1:SetAlpha(1); line2:SetAlpha(1)
        if cb then cb() end
    end)
end

function BuildUnlockPage(page)
    for _, r in ipairs(unlockRowFrames) do ReleaseRow(r, unlockRowPool, ResetUnlockRow) end
    unlockRowFrames = {}
    local start = (page - 1) * UNLOCK_ROWS_PER_PAGE + 1
    local last = math_min(start + UNLOCK_ROWS_PER_PAGE - 1, tlen(unlockState.data))
    for i = start, last do
        local d = unlockState.data[i]
        local row = GetUnlockRow()
        row:SetParent(unlockRowsContainer)
        row:SetPoint("TOP", unlockRowsContainer, "TOP", 0, -(i-start)*UNLOCK_ROW_SPACING)
        row:SetFrameLevel(textFrame:GetFrameLevel()+2)
        row:Hide()
        row.icon:SetTexture(d.icon)
        row.line1:SetText(d.line1)
        row.line2:SetText(d.line2)
        tinsert(unlockRowFrames, row)
    end
    unlockRowsContainer:SetHeight((tlen(unlockRowFrames)-1)*UNLOCK_ROW_SPACING + UNLOCK_ROW_HEIGHT)
end

local function ShowUnlockSection()
    if tlen(unlockState.data) > 0 then
        for _, r in ipairs(statRowFrames) do r:Hide() end
        PlayGoldShimmer()
        headerText:SetAlpha(0); levelText:SetAlpha(0)
        headerText:SetText("|cFFFFFFFFNew|r")
        levelText:SetText("|cFFFFD700Unlocks|r")
        StartAnimation(0.5, function(p) headerText:SetAlpha(p); levelText:SetAlpha(p) end, function()
            unlockState.page = 1
            BuildUnlockPage(unlockState.page)
            unlockRowsContainer:Show()
            local function revealPage()
                RevealRows(unlockRowFrames, function(row) AnimateUnlockRow(row, 0.85) end, 0.6, function()
                    if unlockState.page < unlockState.total then
                        Delay(6, function()
                            unlockState.page = unlockState.page + 1
                            BuildUnlockPage(unlockState.page)
                            unlockRowsContainer:Show()
                            revealPage()
                        end)
                    else
                        Delay(6, StartFade)
                    end
                end)
            end
            revealPage()
        end)
    else
        StartFade()
    end
end

local function GetLearnableSkills(level)
    local classDB = NextLevel_TrainerDB[playerClass]
    return classDB and classDB[level]
end

--[[-----------------------------------------------------------------------------
    9. Main entry & event handling
     – ShowLevelUp builds stat rows and unlock data, triggers animations.
------------------------------------------------------------------------------]]
local function ShowLevelUp(level, oldHealth, fakeGains, oldStatsSnapshot, attempt)
    attempt = attempt or 0
    StopAllAnimations()
    local statData = {}
    ReleaseAllRows()
    container:Hide(); container:SetAlpha(1)
    headerText:SetText("|cFFFFFFFFYou've reached|r")
    levelText:SetText("|cFFFFD700Level "..level.."|r")

    -- Compute stat gains
    local newStats, computedOldStats, gains = {}, {}, {}
    for _, s in ipairs(STAT_DEFS) do
        local newVal = UnitStat("player", s.index) or 0
        newStats[s.key] = newVal
        local oldVal = fakeGains and (newVal - (fakeGains[s.key] or 0)) or (oldStatsSnapshot[s.key] or newVal)
        computedOldStats[s.key] = oldVal
        gains[s.key] = newVal - oldVal
    end

    local newHealth = UnitHealthMax("player") or 0
    local healthGain
    if fakeGains and fakeGains.Health then
        healthGain = fakeGains.Health
    else
        healthGain = newHealth - oldHealth
    end
    if healthGain > 0 then
        tinsert(statData, { name="Health", old=oldHealth, gain=healthGain, new=oldHealth + healthGain })
    end
    for _, s in ipairs(STAT_DEFS) do
        local g = gains[s.key]
        if g > 0 then
            tinsert(statData, { name=s.name, old=computedOldStats[s.key], gain=g, new=newStats[s.key] })
        end
    end

    if tlen(statData) == 0 and attempt == 0 then
        Delay(0.2, function() ShowLevelUp(level, oldHealth, fakeGains, oldStatsSnapshot, 1) end)
        return
    end

    -- Create stat rows
    statRowsContainer:Hide()
    statRowsContainer:SetPoint("TOP", textFrame, "BOTTOM", 0, -5)
    statRowsContainer:SetPoint("LEFT", textFrame, "CENTER", -STAT_ROW_WIDTH/2, 0)
    statRowsContainer:SetWidth(STAT_ROW_WIDTH)
    statRowsContainer:SetHeight(tlen(statData) * (STAT_ROW_HEIGHT + 2))
    statRowFrames = {}
    for i, d in ipairs(statData) do
        local row = GetStatRow()
        row:SetParent(statRowsContainer)
        row:SetPoint("TOP", statRowsContainer, "TOP", 0, -(i-1)*(STAT_ROW_HEIGHT+2))
        row:SetFrameLevel(textFrame:GetFrameLevel()+2)
        row:Hide()
        row.label:SetText(d.name..": ")
        row.oldValueText:SetText(d.old)
        row.gainText:SetText("|cFF00FF00+"..d.gain.."|r")
        row.gainText:SetAlpha(0)
        row.newValueText:SetText("")
        row.newValueText:SetAlpha(0)
        row.arrowTexture:SetAlpha(0)
        row.oldValue, row.newValue = d.old, d.new
        tinsert(statRowFrames, row)
    end
    statRowsContainer:Show()

    -- Build unlock data (talent point, skills)
    unlockState.data = {}
    if level >= 10 and level <= 60 then
        tinsert(unlockState.data, { icon="Interface\\Icons\\INV_Misc_Book_08", line1="|cFF00FF00Your power increased!|r", line2="|cFFFFD700New Talent Point available|r" })
    end
    local skills = GetLearnableSkills(level)
    if skills and tlen(skills) > 0 then
        for _, sk in ipairs(skills) do
            tinsert(unlockState.data, { icon=sk.icon or "Interface\\Icons\\INV_Misc_QuestionMark", line1="|cFF00FF00New ability available!|r", line2="|cFFFFD700"..sk.name.."|r" })
        end
    elseif level >= 10 then
        tinsert(unlockState.data, { icon="Interface\\Icons\\INV_Misc_Book_08", line1="|cFF00FF00New abilities available!|r", line2="|cFFFFD700Visit your class trainer|r" })
    end

    unlockState.total = math_ceil(tlen(unlockState.data) / UNLOCK_ROWS_PER_PAGE)
    unlockState.page = 1
    unlockRowsContainer:Hide()
    unlockRowsContainer:SetPoint("TOP", textFrame, "BOTTOM", 0, -5)
    unlockRowsContainer:SetPoint("LEFT", textFrame, "CENTER", -UNLOCK_ROW_WIDTH/2, 0)
    unlockRowsContainer:SetWidth(UNLOCK_ROW_WIDTH)

    container:Show()

    -- Start stat row animations, then unlock section
    if tlen(statData) > 0 then
        local totalRows = tlen(statData)
        local gainsDone = 0
        local function onGain()
            gainsDone = gainsDone + 1
            if gainsDone == totalRows then Delay(4.0, ShowUnlockSection) end
        end
        PlayMainBannerAnimation(function()
            Delay(0.5, function()
                RevealRows(statRowFrames, function(row)
                    AnimateRowAppear(row, 0.4, function()
                        AnimateGainText(row, onGain)
                    end)
                end, 2.8, nil)
            end)
        end)
    else
        PlayMainBannerAnimation(function()
            Delay(0.5, ShowUnlockSection)
        end)
    end
end

-- Event frame – listen for level‑up and trainer window
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LEVEL_UP")
eventFrame:RegisterEvent("TRAINER_SHOW")
eventFrame:SetScript("OnEvent", function()
    if event == "PLAYER_LEVEL_UP" then
        local level = arg1
        local oldStats = {}
        for _, s in ipairs(STAT_DEFS) do oldStats[s.key] = preLevelStats[s.key] or 0 end
        Delay(0.5, function() ShowLevelUp(level, preLevelHealth, nil, oldStats) end)
    elseif event == "TRAINER_SHOW" then
        ScanTrainer()
    end
end)

-- Slash command for testing and resetting
SLASH_NEXTLEVEL1 = "/nextlevel"
SlashCmdList["NEXTLEVEL"] = function(msg)
    if msg then
        msg = string.gsub(msg, "^%s*(.-)%s*$", "%1")
    end
    if msg == "reset" then
        NextLevel_TrainerDB[playerClass] = {}
        print("|cFFFFD700NextLevel:|r Trainer database reset for " .. playerClass .. ".")
    else
        local level = tonumber(msg) or 60
        ShowLevelUp(level, 100, {str=3, agi=0, sta=2, int=0, spi=0, Health=85})
    end
end

print("|cFF00FF00NextLevel|r loaded successfully. Use /nextlevel [level] to test, or /nextlevel reset to reset trainer data.|r")