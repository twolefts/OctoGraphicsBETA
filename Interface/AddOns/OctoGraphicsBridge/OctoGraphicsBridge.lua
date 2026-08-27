local bridge = CreateFrame("Frame", "OctoGraphicsBridgeMarker", UIParent)
bridge:SetWidth(132)
bridge:SetHeight(8)
bridge:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, 0)
bridge:SetFrameStrata("TOOLTIP")
bridge:SetFrameLevel(127)
bridge:EnableMouse(false)

local function MakeBlock(left, red, green, blue, bottom)
  local texture = bridge:CreateTexture(nil, "OVERLAY")
  texture:SetWidth(6)
  texture:SetHeight(4)
  texture:SetPoint("BOTTOMLEFT", bridge, "BOTTOMLEFT", left, bottom or 0)
  texture:SetTexture(red / 255, green / 255, blue / 255, 1)
  return texture
end

MakeBlock(0, 239, 32, 128)
MakeBlock(6, 16, 207, 239)
local stateBlock = MakeBlock(12, 32, 64, 96)
local elevationBlock = MakeBlock(18, 251, 251, 17)
local profileBlock = MakeBlock(24, 7, 113, 211)
local zoneLowBlock = MakeBlock(30, 0, 43, 197)
local zoneHighBlock = MakeBlock(36, 0, 97, 197)
-- Keep all authoritative markers on the proven bottom row. On this client,
-- the second four-pixel row is not preserved reliably in the backbuffer
-- capture even though the bridge frame itself remains valid.
-- Encode 0..1439 game minutes as three base-12 digits. Each digit uses a
-- widely separated red value and its own fixed green/blue signature, making
-- the clock resilient to UI scaling and backbuffer conversion.
local timeLowBlock = MakeBlock(42, 7, 151, 73)
local timeHighBlock = MakeBlock(48, 7, 205, 73)
local timeValidBlock = MakeBlock(54, 7, 117, 229)
local weatherBlock = MakeBlock(60, 0, 59, 163)

local atmosphereProfiles = {
  -- Snow and cold highlands.
  ["dun morogh"] = 1, ["winterspring"] = 1, ["alterac valley"] = 1,
  ["icepoint rock"] = 1, ["northwind"] = 1,

  -- Dry, sun-baked, or industrial terrain.
  ["blackstone island"] = 2, ["durotar"] = 2, ["the barrens"] = 2,
  ["tanaris"] = 2, ["thousand needles"] = 2, ["searing gorge"] = 2,
  ["silithus"] = 2, ["zul'farrak"] = 2, ["wailing caverns"] = 2,

  -- Bright countryside and open temperate regions.
  ["elwynn forest"] = 3, ["westfall"] = 3, ["redridge mountains"] = 3,
  ["loch modan"] = 3, ["mulgore"] = 3, ["hillsbrad foothills"] = 3,
  ["arathi highlands"] = 3, ["arathi basin"] = 3,
  ["thalassian highlands"] = 3, ["alah'thalas"] = 3,

  -- Gloomy, haunted, diseased, or marshy regions.
  ["balor"] = 4, ["tirisfal glades"] = 4, ["silverpine forest"] = 4,
  ["duskwood"] = 4, ["deadwind pass"] = 4, ["western plaguelands"] = 4,
  ["eastern plaguelands"] = 4, ["swamp of sorrows"] = 4,
  ["wetlands"] = 4, ["dustwallow marsh"] = 4,
  ["gilneas"] = 4, ["scarlet enclave"] = 4,

  -- Rugged mountains, badlands, volcanic terrain, and exposed wastes.
  ["grim reaches"] = 5, ["badlands"] = 5, ["burning steppes"] = 5,
  ["blasted lands"] = 5, ["alterac mountains"] = 5,
  ["stonetalon mountains"] = 5, ["desolace"] = 5,
  ["blackrock mountain"] = 5, ["blackrock spire"] = 5,

  -- Tropical islands, jungles, and warm wetlands.
  ["lapidis isle"] = 6, ["island of doctor lapidis"] = 6,
  ["gillijim's isle"] = 6, ["tel'abim"] = 6,
  ["stranglethorn vale"] = 6, ["feralas"] = 6,
  ["un'goro crater"] = 6, ["zul'gurub"] = 6,

  -- Mystical, ancient, or corrupted forests.
  ["moonwhisper coast"] = 7, ["teldrassil"] = 7, ["darkshore"] = 7,
  ["ashenvale"] = 7, ["felwood"] = 7, ["azshara"] = 7,
  ["warsong gulch"] = 7, ["maraudon"] = 7, ["dire maul"] = 7,

  -- Sacred highlands.
  ["hyjal"] = 8, ["moonglade"] = 8
}

local function StableZoneKey(name)
  local value = 0
  name = string.lower(name or "unknown")
  for index = 1, string.len(name) do
    value = math.mod(value * 131 + string.byte(name, index), 65535)
  end
  return value + 1
end

local underwater = false
local elapsedSinceUpdate = 0

local function SafeBoolean(functionValue)
  if type(functionValue) ~= "function" then return false end
  local ok, value = pcall(functionValue)
  return ok and value and true or false
end

local function IsPlayerIndoors()
  if type(IsIndoors) == "function" then
    return SafeBoolean(IsIndoors)
  end
  if type(IsOutdoors) == "function" then
    local ok, outdoors = pcall(IsOutdoors)
    return ok and not outdoors
  end

  -- Vanilla 1.12 reports indoor/outdoor minimap changes through separate
  -- zoom CVars. OctoWoW may not expose the newer IsIndoors API.
  if Minimap and type(Minimap.GetZoom) == "function" and type(GetCVar) == "function" then
    local zoom = Minimap:GetZoom()
    local insideZoom = tonumber(GetCVar("minimapInsideZoom"))
    local outsideZoom = tonumber(GetCVar("minimapZoom"))
    if insideZoom and outsideZoom and insideZoom ~= outsideZoom then
      if zoom == insideZoom then return true end
      if zoom == outsideZoom then return false end
    end
  end

  -- Ambiguous state is treated as outdoors so height fog is never
  -- incorrectly suppressed.
  return false
end

local function UpdateMarker()
  local indoors = IsPlayerIndoors()
  if indoors and underwater then
    stateBlock:SetTexture(240 / 255, 240 / 255, 32 / 255, 1)
  elseif indoors then
    stateBlock:SetTexture(240 / 255, 64 / 255, 32 / 255, 1)
  elseif underwater then
    stateBlock:SetTexture(32 / 255, 240 / 255, 64 / 255, 1)
  else
    stateBlock:SetTexture(32 / 255, 64 / 255, 96 / 255, 1)
  end

  local elevation = nil
  if type(UnitPosition) == "function" then
    local ok, _, _, z = pcall(UnitPosition, "player")
    if ok and type(z) == "number" then elevation = z end
  end
  if elevation then
    elevation = math.max(-2048, math.min(2032, elevation))
    local encoded = math.floor((elevation + 2048) / 16 + 0.5)
    elevationBlock:SetTexture(encoded / 255, 17 / 255, 251 / 255, 1)
  else
    elevationBlock:SetTexture(251 / 255, 251 / 255, 17 / 255, 1)
  end

  local zoneName = "unknown"
  if type(GetRealZoneText) == "function" then
    local ok, value = pcall(GetRealZoneText)
    if ok and type(value) == "string" and value ~= "" then zoneName = value end
  elseif type(GetZoneText) == "function" then
    local ok, value = pcall(GetZoneText)
    if ok and type(value) == "string" and value ~= "" then zoneName = value end
  end
  local normalizedZone = string.lower(zoneName)
  local profile = atmosphereProfiles[normalizedZone] or 0
  if profile == 0 and type(IsInInstance) == "function" then
    local ok, inside = pcall(IsInInstance)
    if ok and inside then
      -- Profile 9 is the conservative unknown-instance state. The DLL retains
      -- WoW's native fog and smoothly removes Octo height fog until classified.
      profile = 9
    end
  end
  local zoneKey = StableZoneKey(normalizedZone)
  profileBlock:SetTexture((profile * 16 + 7) / 255, 113 / 255, 211 / 255, 1)
  zoneLowBlock:SetTexture(math.mod(zoneKey, 256) / 255, 43 / 255, 197 / 255, 1)
  zoneHighBlock:SetTexture(math.floor(zoneKey / 256) / 255, 97 / 255, 197 / 255, 1)

  local gameHour = 12
  local gameMinute = 0
  local timeAvailable = false
  if type(GetGameTime) == "function" then
    local ok, hour, minute = pcall(GetGameTime)
    -- Standard clients return two numbers. Some 1.12-derived clients expose
    -- the continent-local clock as a single formatted HH:MM string instead.
    if ok and type(hour) == "string" and not tonumber(hour) then
      local _, _, parsedHour, parsedMinute = string.find(hour, "(%d+):(%d+)")
      if parsedHour then
        hour = parsedHour
        minute = parsedMinute
      end
    end
    hour = tonumber(hour)
    minute = tonumber(minute)
    -- Preserve an authoritative hour-only result and use the top of the hour
    -- when this client does not provide minutes.
    if ok and hour then
      gameHour = math.mod(math.floor(hour), 24)
      gameMinute = math.mod(math.floor(minute or 0), 60)
      timeAvailable = true
    end
  end
  local encodedMinutes = timeAvailable and (gameHour * 60 + gameMinute) or 0
  local digit0 = math.mod(encodedMinutes, 12)
  local digit1 = math.mod(math.floor(encodedMinutes / 12), 12)
  local digit2 = math.floor(encodedMinutes / 144)
  if timeAvailable then
    timeLowBlock:SetTexture((digit0 * 20 + 7) / 255, 151 / 255, 73 / 255, 1)
    timeHighBlock:SetTexture((digit1 * 20 + 7) / 255, 205 / 255, 73 / 255, 1)
    timeValidBlock:SetTexture((digit2 * 20 + 7) / 255, 117 / 255, 229 / 255, 1)
  else
    timeLowBlock:SetTexture(7 / 255, 31 / 255, 73 / 255, 1)
    timeHighBlock:SetTexture(7 / 255, 45 / 255, 73 / 255, 1)
    timeValidBlock:SetTexture(7 / 255, 7 / 255, 29 / 255, 1)
  end

  -- Weather APIs differ across 1.12-derived clients. Use GetWeather only when
  -- the client exposes it, and remain neutral when its result is unavailable
  -- or unrecognized. Encoding: kind * 51 + intensity (0..50).
  local weatherKind = 0
  local weatherIntensity = 0
  if type(GetWeather) == "function" then
    local ok, weatherType, intensity = pcall(GetWeather)
    if ok then
      local label = string.lower(tostring(weatherType or ""))
      if string.find(label, "snow", 1, true) then
        weatherKind = 3
      elseif string.find(label, "rain", 1, true) or string.find(label, "storm", 1, true) then
        weatherKind = 2
      elseif string.find(label, "sand", 1, true) or string.find(label, "dust", 1, true) then
        weatherKind = 4
      elseif string.find(label, "clear", 1, true) or string.find(label, "fine", 1, true) then
        weatherKind = 1
      end
      intensity = tonumber(intensity)
      if intensity then
        weatherIntensity = math.floor(math.max(0, math.min(1, intensity)) * 50 + 0.5)
      end
    end
  end
  weatherBlock:SetTexture((weatherKind * 51 + weatherIntensity) / 255, 59 / 255, 163 / 255, 1)
end

bridge:RegisterEvent("PLAYER_ENTERING_WORLD")
bridge:RegisterEvent("ZONE_CHANGED")
bridge:RegisterEvent("ZONE_CHANGED_INDOORS")
bridge:RegisterEvent("ZONE_CHANGED_NEW_AREA")
bridge:RegisterEvent("MINIMAP_UPDATE_ZOOM")
bridge:RegisterEvent("MIRROR_TIMER_START")
bridge:RegisterEvent("MIRROR_TIMER_STOP")
bridge:SetScript("OnEvent", function()
  if event == "MIRROR_TIMER_START" and arg1 == "BREATH" then
    underwater = true
  elseif event == "MIRROR_TIMER_STOP" and arg1 == "BREATH" then
    underwater = false
  elseif event == "PLAYER_ENTERING_WORLD" then
    underwater = false
  end
  UpdateMarker()
end)
bridge:SetScript("OnUpdate", function()
  elapsedSinceUpdate = elapsedSinceUpdate + (arg1 or 0)
  if elapsedSinceUpdate >= 0.20 then
    elapsedSinceUpdate = 0
    UpdateMarker()
  end
end)

SLASH_OCTOGRAPHICSBRIDGEPROBE1 = "/octobridgeprobe"
SlashCmdList["OCTOGRAPHICSBRIDGEPROBE"] = function()
  local playerText = "UnitPosition unavailable"
  if type(UnitPosition) == "function" then
    local ok, x, y, z = pcall(UnitPosition, "player")
    if ok then
      playerText = string.format("player=(%s,%s,%s)", tostring(x), tostring(y), tostring(z))
    else
      playerText = "UnitPosition failed"
    end
  end

  local cursorText = "CursorPosition unavailable"
  if type(CursorPosition) == "function" then
    local ok, x, y, z = pcall(CursorPosition)
    if ok then
      cursorText = string.format("cursor=(%s,%s,%s)", tostring(x), tostring(y), tostring(z))
    else
      cursorText = "CursorPosition failed"
    end
  end

  local zoomText = "GetCameraZoom unavailable"
  if type(GetCameraZoom) == "function" then
    local ok, zoom = pcall(GetCameraZoom)
    if ok then zoomText = "zoom=" .. tostring(zoom) end
  end

  local gameTimeText = "GetGameTime unavailable"
  if type(GetGameTime) == "function" then
    local ok, hour, minute = pcall(GetGameTime)
    gameTimeText = string.format("GetGameTime ok=%s hour=%s minute=%s", tostring(ok), tostring(hour), tostring(minute))
  end

  local localTimeText = "local time unavailable"
  if type(date) == "function" then
    local ok, value = pcall(date, "%H:%M")
    if ok then localTimeText = "local=" .. tostring(value) end
  end

  local continentText = "continent unavailable"
  if type(GetCurrentMapContinent) == "function" then
    local ok, value = pcall(GetCurrentMapContinent)
    if ok then continentText = "continent=" .. tostring(value) end
  end

  DEFAULT_CHAT_FRAME:AddMessage("OctoBridge probe: " .. playerText .. "; " .. cursorText .. "; " .. zoomText)
  DEFAULT_CHAT_FRAME:AddMessage("OctoBridge clock: " .. gameTimeText .. "; " .. localTimeText .. "; " .. continentText)
end

UpdateMarker()
bridge:Show()
