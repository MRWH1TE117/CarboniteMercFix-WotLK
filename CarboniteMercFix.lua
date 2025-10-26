-- Carbonite Mercenary Fix (WotLK 3.3.5a)
-- Cel:
--  • Zablokować wywołania GetNumSkillLines / GetSkillLineInfo w krytycznych momentach (wejście na BG, morph),
--    kiedy dane skilli potrafią być “puste”/niestabilne → Carbonite potrafi wtedy pytać o złe indeksy i wysypać klienta.
--  • Nigdy nie ingerujemy w samego Carbonite – tylko “otulamy” API i zwracamy bezpieczne wartości.

local Orig_GetNumSkillLines     = _G.GetNumSkillLines
local Orig_GetSkillLineInfo     = _G.GetSkillLineInfo

-- Prosty znacznik “bezpiecznie/niebezpiecznie”
local SAFE_READY   = false
local lastWorldTS  = 0
local enterDelay   = 4.0   -- tyle sekund po wejściu/zmianie strefy wstrzymujemy dostęp do danych skilli
local frame        = CreateFrame("Frame")

-- Czy jesteśmy w BG?
local function InBG()
  local inInst, instType = IsInInstance()
  return inInst and instType == "pvp"
end

-- Czy minęło już okienko rozgrzewki po wejściu?
local function TimeReady()
  return (GetTime() - lastWorldTS) > enterDelay
end

-- Ostateczny warunek “można czytać skille”
local function SkillsReady()
  -- w BG + świeżo po wejściu → NIE
  if InBG() and not TimeReady() then
    return false
  end
  -- klient czasem sygnalizuje zmiany skilli (SKILL_LINES_CHANGED);
  -- jeśli niedawno weszliśmy – poczekaj enterDelay.
  return SAFE_READY and TimeReady()
end

-- Eventy, po których robimy “ok, spróbuj czytać”
frame:SetScript("OnEvent", function(_, evt)
  if evt == "PLAYER_LOGIN" then
    lastWorldTS = GetTime()
    SAFE_READY  = true
  elseif evt == "PLAYER_ENTERING_WORLD" or evt == "ZONE_CHANGED_NEW_AREA" then
    lastWorldTS = GetTime()
    -- chwilowo “nie gotowe” (po morphie dane potrafią być puste)
    SAFE_READY  = false
    -- mały timer, po którym znowu pozwalamy czytać
    frame:Hide()
    frame.elapsed = 0
    frame:SetScript("OnUpdate", function(self, e)
      self.elapsed = (self.elapsed or 0) + e
      if self.elapsed >= enterDelay then
        SAFE_READY = true
        self:Hide()
      end
    end)
    frame:Show()
  elseif evt == "SKILL_LINES_CHANGED" then
    -- sygnał od klienta: dane skilli są zaktualizowane → pozwól po krótkiej chwili
    lastWorldTS = GetTime()
    SAFE_READY  = false
    C_TimerAfter = C_TimerAfter or function(t, f)
      -- prosta emulacja C_Timer.After dla 3.3.5a
      local tF = CreateFrame("Frame")
      local acc = 0
      tF:SetScript("OnUpdate", function(self, dt)
        acc = acc + dt
        if acc >= t then
          pcall(f)
          self:SetScript("OnUpdate", nil)
          self:Hide()
        end
      end)
    end
    C_TimerAfter(0.3, function() SAFE_READY = true end)
  end
end)
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
frame:RegisterEvent("SKILL_LINES_CHANGED")

-- BEZPIECZNY GetNumSkillLines
_G.GetNumSkillLines = function()
  local ok = pcall(Orig_GetNumSkillLines)
  if not ok then
    return 0
  end
  if not SkillsReady() then
    return 0
  end
  return Orig_GetNumSkillLines()
end

-- BEZPIECZNY GetSkillLineInfo
_G.GetSkillLineInfo = function(index)
  -- odfiltruj złe indeksy / brak gotowości
  if type(index) ~= "number" or index < 1 then
    return nil
  end
  if not SkillsReady() then
    return nil
  end
  local n = Orig_GetNumSkillLines()
  if not n or index > n then
    return nil
  end
  -- wywołaj oryginał w pcall; jeżeli Blizzard API zwróci błąd, oddamy nil zamiast rozkrzaczyć klienta
  local ok, name, isHeader, expanded, skillRank, _, _, _, _, _, _, _, _, _, maxRank =
    pcall(Orig_GetSkillLineInfo, index)
  if not ok then
    return nil
  end
  return name, isHeader, expanded, skillRank, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, maxRank
end
