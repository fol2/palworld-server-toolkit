--[[
    LiveEditor — UE4SS Lua Mod for Palworld
    File-based IPC: reads commands.json, executes, writes responses.json
    Polls every 2 seconds via LoopAsync.
]]

local ModName = "LiveEditor"
local ModVersion = "2.0.0"
local BootTime = os.clock()  -- for minimum startup delay before auto-discovery

-- ── Paths ──────────────────────────────────────────────────────────────────────
-- Derive absolute project root from this script's own path via debug.getinfo.
-- Script lives at: <ProjectRoot>\server\Pal\Binaries\Win64\ue4ss\Mods\LiveEditor\Scripts\main.lua
-- Navigate up 9 directory levels to reach <ProjectRoot>.
local function GetProjectRoot()
    local src = debug.getinfo(1, "S").source
    src = src:match("^@(.+)$") or src          -- strip leading '@'
    local dir = src
    for i = 1, 9 do                             -- main.lua→Scripts→LiveEditor→Mods→ue4ss→Win64→Binaries→Pal→server→ProjectRoot
        dir = dir:match("^(.+)\\[^\\]+$")
        if not dir then return nil end
    end
    return dir
end

local ProjectRoot = GetProjectRoot()
if not ProjectRoot then
    print(string.format("[%s] ERROR: Cannot resolve project root from script path.\n", ModName))
    return
end

local IpcDir = ProjectRoot .. "\\scripts\\live-editor"
local CmdFile = IpcDir .. "\\commands.json"
local CmdTmpFile = IpcDir .. "\\commands.json.tmp"
local RspFile = IpcDir .. "\\responses.json"
local RspTmpFile = IpcDir .. "\\responses.json.tmp"
local DiscoveryLogFile = IpcDir .. "\\discovery-log.json"

-- ── Configuration ──────────────────────────────────────────────────────────────
-- Read admin UID from config.json in the project root.
-- Fallback to 0x00000000 if not found (commands will not authenticate).
local function LoadAdminUid()
    local configPath = ProjectRoot .. "\\config.json"
    local f = io.open(configPath, "r")
    if not f then
        print(string.format("[%s] WARN: config.json not found, admin UID not set.\n", ModName))
        return 0x00000000
    end
    local content = f:read("*a")
    f:close()
    -- Simple pattern match for "admin_uid": "HEXVALUE..."
    local uid = content:match('"admin_uid"%s*:%s*"(%x+)')
    if uid and #uid >= 8 then
        local hex8 = uid:sub(1, 8)
        local val = tonumber(hex8, 16)
        if val then
            print(string.format("[%s] Admin UID loaded: 0x%08X\n", ModName, val))
            return val
        end
    end
    print(string.format("[%s] WARN: Could not parse admin_uid from config.json.\n", ModName))
    return 0x00000000
end

-- ── JSON library ───────────────────────────────────────────────────────────────
-- Json.lua is in this mod's Scripts directory (copied from AdminCommands/libs)
local jsonOk, json = pcall(function()
    return require("Json")
end)

if not jsonOk then
    print(string.format("[%s] ERROR: Could not load JSON library: %s\n", ModName, tostring(json)))
    print(string.format("[%s] Mod will not function without JSON support.\n", ModName))
    return
end

print(string.format("[%s] v%s loaded. JSON library ready.\n", ModName, ModVersion))
print(string.format("[%s] Project root: %s\n", ModName, ProjectRoot))
print(string.format("[%s] IPC dir: %s\n", ModName, IpcDir))

-- Load admin UID from config
local AdminUidA = LoadAdminUid()

-- ── Utility ────────────────────────────────────────────────────────────────────

local function Log(msg)
    print(string.format("[%s] %s\n", ModName, msg))
end

local function ReadFile(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local content = f:read("*a")
    f:close()
    if not content or content == "" then return nil end
    return content
end

local function WriteFile(path, content)
    -- Atomic write: write to .tmp then rename
    local tmpPath = path .. ".tmp"
    local f = io.open(tmpPath, "w")
    if not f then
        Log("ERROR: Cannot write to " .. tmpPath)
        return false
    end
    f:write(content)
    f:close()
    -- Remove existing target then rename
    os.remove(path)
    os.rename(tmpPath, path)
    return true
end

local function WriteResponse(id, success, message)
    local rsp = {
        id = id,
        success = success,
        message = message
    }
    local encoded = json.encode(rsp)
    WriteFile(RspFile, encoded)
    Log(string.format("Response: %s → %s", id, message))
end

-- ── Player discovery ───────────────────────────────────────────────────────────

local function GetAllPlayers()
    local players = {}
    local success, err = pcall(function()
        local playerStates = FindAllOf("PalPlayerState")
        if not playerStates then return end
        for _, ps in ipairs(playerStates) do
            if ps:IsValid() then
                local name = ""
                local pcSuccess, pcErr = pcall(function()
                    -- Try to get player name from PalPlayerState
                    local nameObj = ps.PlayerNamePrivate
                    if nameObj then
                        name = nameObj:ToString()
                    end
                end)
                if not pcSuccess then
                    -- Fallback: try SavedPlayerName
                    pcall(function()
                        name = ps.SavedPlayerName:ToString()
                    end)
                end
                if name and name ~= "" then
                    table.insert(players, {
                        name = name,
                        state = ps
                    })
                end
            end
        end
    end)
    if not success then
        Log("ERROR getting players: " .. tostring(err))
    end
    return players
end

local function FindPlayerByName(targetName)
    local players = GetAllPlayers()
    local lowerTarget = string.lower(targetName)
    for _, p in ipairs(players) do
        if string.lower(p.name) == lowerTarget then
            return p
        end
    end
    -- Partial match fallback
    for _, p in ipairs(players) do
        if string.find(string.lower(p.name), lowerTarget, 1, true) then
            return p
        end
    end
    return nil
end

-- ── Chat broadcast suppression ────────────────────────────────────────────────
-- Hook BroadCastChatMessage to suppress ! commands dispatched by LiveEditor.
-- UE4SS RegisterHook cannot cancel the original function, and cannot set FString
-- params. But we CAN read the message and try to modify the Category (enum/int)
-- to a value the broadcast logic might skip.

local _suppressingBroadcast = false

pcall(function()
    RegisterHook("/Script/Pal.PalGameStateInGame:BroadCastChatMessage",
        function(self, ChatMessage)
            -- Pre-hook: fires BEFORE the actual broadcast
            if not _suppressingBroadcast then return end

            -- Try to read the message and verify it's our ! command
            local readOk, msgText = pcall(function()
                local msg = ChatMessage:get()
                return msg.Message:ToString()
            end)

            if readOk and msgText and msgText:sub(1, 1) == "!" then
                -- Try to change Category to an invalid value to prevent broadcast.
                -- Category is an enum (int) — Param:set() should work for non-string types.
                pcall(function()
                    local msg = ChatMessage:get()
                    msg.Category = 255  -- invalid category — broadcast logic should skip
                end)
                Log("Suppressed broadcast: " .. msgText:sub(1, 40))
            end
        end,
        function() end  -- post-hook: no-op
    )
    Log("BroadCastChatMessage hook registered for chat suppression.")
end)

-- ── Chat command dispatch (triggers AdminCommands mod) ───────────────────────
-- AdminCommands hooks PalPlayerState:EnterChat_Receive and processes messages
-- starting with "!". We simulate an admin chat message to trigger those commands.
-- The broadcast hook above attempts to suppress the command text from appearing
-- in other players' chat.

local function DispatchChatCommand(message)
    -- Find any valid PalPlayerState to call EnterChat_Receive on
    local playerStates = FindAllOf("PalPlayerState")
    if not playerStates then
        return false, "No players connected"
    end

    local targetPS = nil
    for _, ps in ipairs(playerStates) do
        if ps:IsValid() then
            targetPS = ps
            break
        end
    end
    if not targetPS then
        return false, "No valid PalPlayerState found"
    end

    -- Construct FPalChatMessage with admin credentials.
    -- Category = 0 and Sender = "" as baseline; the BroadCastChatMessage hook
    -- will further attempt to suppress the broadcast by changing Category to 255.
    local chatMsg = {
        Category = 0,                                                -- EPalChatCategory::System
        Sender = "",
        SenderPlayerUId = { A = AdminUidA, B = 0, C = 0, D = 0 },
        Message = message,
        ReceiverPlayerUIds = {},
        MessageId = FName("None"),
        MessageArgKeys = {},
        MessageArgValues = {}
    }

    local ok, err = pcall(function()
        _suppressingBroadcast = true
        ExecuteInGameThread(function()
            targetPS:EnterChat_Receive(chatMsg)
            -- Small delay then release flag (LoopAsync with 100ms, return true = stop)
            LoopAsync(100, function()
                _suppressingBroadcast = false
                return true
            end)
        end)
    end)

    if not ok then
        _suppressingBroadcast = false
        return false, string.format("Dispatch failed: %s", tostring(err))
    end

    return true, string.format("Dispatched: %s", message)
end

-- ── Direct UE4SS Function Calls (Silent) ────────────────────────────────────
-- These helpers call Palworld UFunctions directly via UE4SS, bypassing the
-- AdminCommands chat hook entirely. Result: zero chat output to any player.
-- Each returns (true, message) on success or (nil, reason) on failure.
-- Callers should fall back to chat dispatch on failure.
--
-- Key insight: functions prefixed with "Request" are client→server RPCs and
-- do nothing when called server-side. We must use server-side equivalents:
--   AddItem_ServerInternal  (not RequestAddItem)
--   SpawnMonsterForPlayer   (on PalCheatManager, not PalPlayerState Request*)
--   AddPlayerExp            (already on PalCheatManager, server-side)

-- Cache: once we confirm a UFunction is NOT callable, skip it on future calls.
local _directCallAvailable = {
    give_item = nil,   -- nil = untested, true = works, false = broken
    spawn_pal = nil,
    give_exp = nil,
    goto_coords = nil,
    bring_player = nil,
    set_time = nil,
}

-- Helper: find PalCheatManager via multiple access paths
local function GetCheatManager()
    -- Path 1: FindAllOf (straightforward)
    local cms = nil
    pcall(function() cms = FindAllOf("PalCheatManager") end)
    if cms and #cms > 0 then
        local cm = cms[1]
        local ok, valid = pcall(function() return cm:IsValid() end)
        if ok and valid then return cm end
    end

    -- Path 2: via PlayerController → CheatManager property
    local pcs = nil
    pcall(function() pcs = FindAllOf("PalPlayerController") end)
    if pcs then
        for _, pc in ipairs(pcs) do
            local ok, cm = pcall(function() return pc.CheatManager end)
            if ok and cm then
                local vOk, valid = pcall(function() return cm:IsValid() end)
                if vOk and valid then return cm end
            end
        end

        -- Path 3: Enable cheats on PlayerController to create CheatManager
        for _, pc in ipairs(pcs) do
            local enableOk = pcall(function()
                ExecuteInGameThread(function()
                    pc:EnableCheats()
                end)
            end)
            if enableOk then
                -- Try reading CheatManager again after enabling
                local ok, cm = pcall(function() return pc.CheatManager end)
                if ok and cm then
                    local vOk, valid = pcall(function() return cm:IsValid() end)
                    if vOk and valid then
                        Log("GetCheatManager: created via EnableCheats()")
                        return cm
                    end
                end
            end
        end
    end

    return nil
end

local function DirectGiveItem(targetName, itemId, count)
    if _directCallAvailable.give_item == false then
        return nil, "DirectGiveItem previously failed — skipping"
    end

    local player = FindPlayerByName(targetName)
    if not player then return nil, "Player not found" end

    local ps = player.state

    -- Step 1: Get inventory data object
    local invOk, invData = pcall(function() return ps:GetInventoryData() end)
    if not invOk then
        Log("DirectGiveItem: GetInventoryData() threw: " .. tostring(invData))
        _directCallAvailable.give_item = false
        return nil, "GetInventoryData not callable: " .. tostring(invData)
    end
    if not invData then
        return nil, "GetInventoryData returned nil"
    end

    -- Step 2: Use AddItem_ServerInternal (server-side, not client-side RequestAddItem)
    -- Signature: EPalItemOperationResult AddItem_ServerInternal(FName StaticItemId, int32 Count, bool IsAssignPassive, float LogDelay)
    Log(string.format("DirectGiveItem: calling AddItem_ServerInternal(%s, %d, false, 0.0)", itemId, count))

    local callOk, callErr = pcall(function()
        ExecuteInGameThread(function()
            invData:AddItem_ServerInternal(FName(itemId), count, false, 0.0)
        end)
    end)
    if not callOk then
        Log("DirectGiveItem: AddItem_ServerInternal threw: " .. tostring(callErr))
        _directCallAvailable.give_item = false
        return nil, "AddItem_ServerInternal failed: " .. tostring(callErr)
    end

    _directCallAvailable.give_item = true
    return true, string.format("Gave %d x %s to %s (silent)", count, itemId, targetName)
end

local function DirectSpawnPal(targetName, palId, level)
    if _directCallAvailable.spawn_pal == false then
        return nil, "DirectSpawnPal previously failed — skipping"
    end

    -- Path 1: Use GetCheatManager() (may find via FindAllOf or PlayerController property)
    local cm = GetCheatManager()
    if cm then
        Log(string.format("DirectSpawnPal: calling CheatManager:SpawnMonsterForPlayer(%s, 1, %d)", palId, level))
        local callOk, callErr = pcall(function()
            ExecuteInGameThread(function()
                cm:SpawnMonsterForPlayer(FName(palId), 1, level)
            end)
        end)
        if callOk then
            _directCallAvailable.spawn_pal = true
            return true, string.format("Spawned %s Lv%d (silent)", palId, level)
        end
        Log("DirectSpawnPal: CheatManager path threw: " .. tostring(callErr))
    end

    -- Path 2: All-in-one game thread — EnableCheats + spawn in same tick
    local pcs = nil
    pcall(function() pcs = FindAllOf("PalPlayerController") end)
    if not pcs or #pcs == 0 then return nil, "No PlayerController found" end

    local spawned = false
    local spawnErr = "unknown"
    pcall(function()
        ExecuteInGameThread(function()
            for _, pc in ipairs(pcs) do
                pcall(function() pc:EnableCheats() end)
                local ok2, cm2 = pcall(function() return pc.CheatManager end)
                if ok2 and cm2 then
                    local vOk, valid = pcall(function() return cm2:IsValid() end)
                    if vOk and valid then
                        Log(string.format("DirectSpawnPal: EnableCheats path — SpawnMonsterForPlayer(%s, 1, %d)", palId, level))
                        cm2:SpawnMonsterForPlayer(FName(palId), 1, level)
                        spawned = true
                        return
                    end
                end
            end
            spawnErr = "CheatManager nil after EnableCheats on all controllers"
        end)
    end)

    if spawned then
        _directCallAvailable.spawn_pal = true
        return true, string.format("Spawned %s Lv%d via EnableCheats (silent)", palId, level)
    end

    Log("DirectSpawnPal: all paths failed — " .. tostring(spawnErr))
    return nil, "Spawn failed: " .. tostring(spawnErr)
end

local function DirectGiveExp(targetName, amount)
    if _directCallAvailable.give_exp == false then
        return nil, "DirectGiveExp previously failed — skipping"
    end

    -- Path 1: PalCheatManager:AddPlayerExp (server-side)
    local cm = GetCheatManager()
    if cm then
        Log(string.format("DirectGiveExp: calling CheatManager:AddPlayerExp(%d)", amount))
        local callOk, callErr = pcall(function()
            ExecuteInGameThread(function()
                cm:AddPlayerExp(amount)
            end)
        end)
        if callOk then
            _directCallAvailable.give_exp = true
            return true, string.format("Added %d exp via CheatManager (silent)", amount)
        end
        Log("DirectGiveExp: CheatManager path failed: " .. tostring(callErr))
    end

    -- Path 2: PalPlayerState:Debug_AddExpForALLPlayer_ToServer (no CheatManager needed)
    local player = nil
    if targetName and targetName ~= "" then
        player = FindPlayerByName(targetName)
    else
        local all = GetAllPlayers()
        if #all > 0 then player = all[1] end
    end
    if not player then return nil, "No player found for exp" end

    Log(string.format("DirectGiveExp: trying PlayerState:Debug_AddExpForALLPlayer_ToServer(%d)", amount))
    local callOk2, callErr2 = pcall(function()
        ExecuteInGameThread(function()
            player.state:Debug_AddExpForALLPlayer_ToServer(amount)
        end)
    end)
    if callOk2 then
        _directCallAvailable.give_exp = true
        return true, string.format("Added %d exp via Debug function (silent)", amount)
    end
    Log("DirectGiveExp: Debug path failed: " .. tostring(callErr2))

    _directCallAvailable.give_exp = false
    return nil, "All exp methods failed"
end

-- Helper: get a player's pawn (AActor) from their PalPlayerState
local function GetPlayerPawn(playerState)
    -- Try common property names for the pawn reference
    local candidates = { "PawnPrivate", "Pawn", "CachedCharacter", "CharacterPawn" }
    for _, prop in ipairs(candidates) do
        local ok, pawn = pcall(function() return playerState[prop] end)
        if ok and pawn then
            local vOk, valid = pcall(function() return pawn:IsValid() end)
            if vOk and valid then return pawn end
        end
    end
    return nil
end

-- Helper: get the admin player (first player, or match by admin UID)
local function GetAdminPlayer()
    local players = GetAllPlayers()
    if #players == 0 then return nil end
    -- On private server, admin is typically the first (or only) player
    return players[1]
end

local function DirectGotoCoords(x, y, z)
    if _directCallAvailable.goto_coords == false then
        return nil, "DirectGotoCoords previously failed — skipping"
    end

    -- Find admin's pawn and use K2_TeleportTo directly (no CheatManager needed)
    local admin = GetAdminPlayer()
    if not admin then return nil, "No admin player found" end

    local pawn = GetPlayerPawn(admin.state)
    if not pawn then return nil, "Cannot access admin pawn" end

    -- K2_TeleportTo(FVector DestLocation, FRotator DestRotation) — AActor method
    Log(string.format("DirectGotoCoords: calling pawn:K2_TeleportTo({X=%s, Y=%s, Z=%s})", tostring(x), tostring(y), tostring(z)))

    local callOk, callErr = pcall(function()
        ExecuteInGameThread(function()
            pawn:K2_TeleportTo({ X = x, Y = y, Z = z }, { Pitch = 0, Yaw = 0, Roll = 0 })
        end)
    end)
    if not callOk then
        Log("DirectGotoCoords: K2_TeleportTo threw: " .. tostring(callErr))
        _directCallAvailable.goto_coords = false
        return nil, "K2_TeleportTo failed: " .. tostring(callErr)
    end

    _directCallAvailable.goto_coords = true
    return true, string.format("Teleported to (%s, %s, %s) (silent)", tostring(x), tostring(y), tostring(z))
end

local function DirectBringPlayer(targetName)
    if _directCallAvailable.bring_player == false then
        return nil, "DirectBringPlayer previously failed — skipping"
    end

    -- Strategy: read admin pawn's location, K2_TeleportTo target pawn there
    local admin = GetAdminPlayer()
    if not admin then return nil, "No admin player found" end

    local adminPawn = GetPlayerPawn(admin.state)
    if not adminPawn then return nil, "Cannot access admin pawn" end

    local target = FindPlayerByName(targetName)
    if not target then return nil, "Player not found: " .. targetName end

    local targetPawn = GetPlayerPawn(target.state)
    if not targetPawn then return nil, "Cannot access target pawn" end

    -- Read admin's location via K2_GetActorLocation (returns FVector)
    local adminLoc = nil
    local locOk, locErr = pcall(function()
        adminLoc = adminPawn:K2_GetActorLocation()
    end)
    if not locOk or not adminLoc then
        return nil, "Cannot read admin location: " .. tostring(locErr)
    end

    Log(string.format("DirectBringPlayer: teleporting %s to admin at (%s, %s, %s)",
        targetName, tostring(adminLoc.X), tostring(adminLoc.Y), tostring(adminLoc.Z)))

    local callOk, callErr = pcall(function()
        ExecuteInGameThread(function()
            targetPawn:K2_TeleportTo(
                { X = adminLoc.X, Y = adminLoc.Y, Z = adminLoc.Z },
                { Pitch = 0, Yaw = 0, Roll = 0 }
            )
        end)
    end)
    if not callOk then
        Log("DirectBringPlayer: K2_TeleportTo threw: " .. tostring(callErr))
        _directCallAvailable.bring_player = false
        return nil, "K2_TeleportTo (bring) failed: " .. tostring(callErr)
    end

    _directCallAvailable.bring_player = true
    return true, string.format("Brought %s to admin (silent)", targetName)
end

local function DirectBringAll()
    -- Get admin's location, then K2_TeleportTo every other player there
    local admin = GetAdminPlayer()
    if not admin then return nil, "No admin player found" end

    local adminPawn = GetPlayerPawn(admin.state)
    if not adminPawn then return nil, "Cannot access admin pawn" end

    local adminLoc = nil
    local locOk, locErr = pcall(function()
        adminLoc = adminPawn:K2_GetActorLocation()
    end)
    if not locOk or not adminLoc then
        return nil, "Cannot read admin location: " .. tostring(locErr)
    end

    local allPlayers = GetAllPlayers()
    local moved = 0
    for _, p in ipairs(allPlayers) do
        if p.name ~= admin.name then
            local pawn = GetPlayerPawn(p.state)
            if pawn then
                pcall(function()
                    ExecuteInGameThread(function()
                        pawn:K2_TeleportTo(
                            { X = adminLoc.X, Y = adminLoc.Y, Z = adminLoc.Z },
                            { Pitch = 0, Yaw = 0, Roll = 0 }
                        )
                    end)
                end)
                moved = moved + 1
            end
        end
    end

    return true, string.format("Brought %d players to admin (silent)", moved)
end

local function DirectSendPlayerToPlayer(sourceName, destName)
    -- Step 1: Read destination player's location
    local dest = FindPlayerByName(destName)
    if not dest then return nil, "Destination player not found: " .. destName end

    local destPawn = GetPlayerPawn(dest.state)
    if not destPawn then return nil, "Cannot access destination pawn" end

    local destLoc = nil
    local locOk, locErr = pcall(function()
        destLoc = destPawn:K2_GetActorLocation()
    end)
    if not locOk or not destLoc then
        return nil, "Cannot read destination location: " .. tostring(locErr)
    end

    -- Step 2: Teleport source player to that location
    local source = FindPlayerByName(sourceName)
    if not source then return nil, "Source player not found: " .. sourceName end

    local sourcePawn = GetPlayerPawn(source.state)
    if not sourcePawn then return nil, "Cannot access source pawn" end

    Log(string.format("DirectSendPlayerToPlayer: teleporting %s to %s at (%s, %s, %s)",
        sourceName, destName, tostring(destLoc.X), tostring(destLoc.Y), tostring(destLoc.Z)))

    local callOk, callErr = pcall(function()
        ExecuteInGameThread(function()
            sourcePawn:K2_TeleportTo(
                { X = destLoc.X, Y = destLoc.Y, Z = destLoc.Z },
                { Pitch = 0, Yaw = 0, Roll = 0 }
            )
        end)
    end)
    if not callOk then
        return nil, "K2_TeleportTo failed: " .. tostring(callErr)
    end

    return true, string.format("Sent %s to %s (silent)", sourceName, destName)
end

local function DirectSetTime(hour)
    if _directCallAvailable.set_time == false then
        return nil, "DirectSetTime previously failed — skipping"
    end

    -- PalTimeManager is a world subsystem — should always exist, no CheatManager needed
    local tms = nil
    pcall(function() tms = FindAllOf("PalTimeManager") end)
    if not tms or #tms == 0 then return nil, "No PalTimeManager found" end

    local tm = tms[1]
    local validOk, isValid = pcall(function() return tm:IsValid() end)
    if not validOk or not isValid then return nil, "PalTimeManager not valid" end

    -- SetGameTime_FixDay(int32 NextHour) — sets in-game time to specified hour
    Log(string.format("DirectSetTime: calling PalTimeManager:SetGameTime_FixDay(%d)", hour))

    local callOk, callErr = pcall(function()
        ExecuteInGameThread(function()
            tm:SetGameTime_FixDay(hour)
        end)
    end)
    if not callOk then
        Log("DirectSetTime: SetGameTime_FixDay threw: " .. tostring(callErr))
        _directCallAvailable.set_time = false
        return nil, "SetGameTime_FixDay failed: " .. tostring(callErr)
    end

    _directCallAvailable.set_time = true
    return true, string.format("Set time to %d:00 (silent)", hour)
end

-- ── Command: give_item ─────────────────────────────────────────────────────────
-- Tries direct UE4SS call first (silent), falls back to AdminCommands chat hook.

local function CmdGiveItem(params)
    local target = params.target_player
    local itemId = params.item_id
    local qty = params.quantity or 1

    if not itemId or itemId == "" then
        return false, "Missing item_id"
    end

    -- Try direct UE4SS call first (silent — no chat output)
    if target and target ~= "" then
        local ok, msg = DirectGiveItem(target, itemId, qty)
        if ok then return true, msg end
        Log("DirectGiveItem failed: " .. tostring(msg) .. " — falling back to chat")
    end

    -- Fallback: chat dispatch (existing behaviour)
    local chatCmd
    if not target or target == "" then
        chatCmd = string.format("!giveme %s:%d", itemId, qty)
    else
        chatCmd = string.format("!give %s %s:%d", target, itemId, qty)
    end

    return DispatchChatCommand(chatCmd)
end

-- ── Command: spawn_pal ─────────────────────────────────────────────────────────
-- Dispatches !spawn via AdminCommands mod chat hook.

local function CmdSpawnPal(params)
    local palId = params.pal_id
    local level = params.level or 1

    if not palId or palId == "" then
        return false, "Missing pal_id"
    end

    -- Try direct UE4SS call first (silent — no chat output)
    local ok, msg = DirectSpawnPal(nil, palId, level)
    if ok then return true, msg end
    Log("DirectSpawnPal failed: " .. tostring(msg) .. " — falling back to chat")

    -- Fallback: chat dispatch
    local chatCmd = string.format("!spawn %s %d", palId, level)
    return DispatchChatCommand(chatCmd)
end

-- ── Command: list_players ──────────────────────────────────────────────────────

local function CmdListPlayers()
    local players = GetAllPlayers()
    local names = {}
    for _, p in ipairs(players) do
        table.insert(names, p.name)
    end
    return true, json.encode(names)
end

-- ── Command: echo (test/debug) ─────────────────────────────────────────────────

local function CmdEcho(params)
    local msg = params.message or "pong"
    return true, msg
end

-- ── Command: get_admin_location ──────────────────────────────────────────────
-- Returns admin's precise X,Y,Z from the pawn (REST API only has X,Y — no Z).

local function CmdGetAdminLocation()
    local admin = GetAdminPlayer()
    if not admin then
        return false, "No admin player found"
    end

    local pawn = GetPlayerPawn(admin.state)
    if not pawn then
        return false, "Cannot access admin pawn"
    end

    local locOk, loc = pcall(function() return pawn:K2_GetActorLocation() end)
    if not locOk or not loc then
        return false, "Cannot read admin location: " .. tostring(loc)
    end

    return true, json.encode({
        name = admin.name,
        x = loc.X,
        y = loc.Y,
        z = loc.Z,
    })
end

-- ── Command: give_exp ────────────────────────────────────────────────────────

local function CmdGiveExp(params)
    local target = params.target_player
    local amount = params.amount

    if not amount then
        return false, "Missing amount"
    end

    -- Try direct UE4SS call first (silent — no chat output)
    -- Note: DirectGiveExp uses PalCheatManager which may not always be available
    local ok, msg = DirectGiveExp(target, amount)
    if ok then return true, msg end
    Log("DirectGiveExp failed: " .. tostring(msg) .. " — falling back to chat")

    -- Fallback: chat dispatch
    local chatCmd
    if not target or target == "" then
        chatCmd = string.format("!giveexp %d", amount)
    else
        chatCmd = string.format("!exp %s %d", target, amount)
    end

    return DispatchChatCommand(chatCmd)
end

-- ── Command: fly_toggle ──────────────────────────────────────────────────────

local function CmdFlyToggle(params)
    local enable = params.enable
    if enable == nil then
        return false, "Missing enable (true/false)"
    end
    local chatCmd = string.format("!fly %s", enable and "enable" or "disable")
    return DispatchChatCommand(chatCmd)
end

-- ── Command: goto_coords ─────────────────────────────────────────────────────

local function CmdGotoCoords(params)
    local x = params.x
    local y = params.y
    local z = params.z
    if not x or not y or not z then
        return false, "Missing x, y, or z coordinates"
    end

    local nx, ny, nz = tonumber(x), tonumber(y), tonumber(z)

    -- Try direct call first (silent)
    local ok, msg = DirectGotoCoords(nx, ny, nz)
    if ok then return true, msg end
    Log("DirectGotoCoords failed: " .. tostring(msg) .. " — falling back to chat")

    -- Fallback: chat dispatch
    local chatCmd = string.format("!goto %s,%s,%s", tostring(nx), tostring(ny), tostring(nz))
    return DispatchChatCommand(chatCmd)
end

-- ── Command: bring_player ────────────────────────────────────────────────────

local function CmdBringPlayer(params)
    local target = params.target_player
    if not target or target == "" then
        return false, "Missing target_player"
    end

    -- Try direct call first (silent)
    local ok, msg = DirectBringPlayer(target)
    if ok then return true, msg end
    Log("DirectBringPlayer failed: " .. tostring(msg) .. " — falling back to chat")

    -- Fallback: chat dispatch
    local chatCmd = string.format("!bring %s", target)
    return DispatchChatCommand(chatCmd)
end

-- ── Command: bring_all ───────────────────────────────────────────────────────

local function CmdBringAll()
    -- Try direct call first (silent)
    local ok, msg = DirectBringAll()
    if ok then return true, msg end
    Log("DirectBringAll failed: " .. tostring(msg) .. " — falling back to chat")

    -- Fallback: chat dispatch
    return DispatchChatCommand("!bringall")
end

-- ── Command: unstuck ─────────────────────────────────────────────────────────

local function CmdUnstuck()
    return DispatchChatCommand("!unstuck")
end

-- ── Command: set_time ────────────────────────────────────────────────────────

local function CmdSetTime(params)
    local hour = params.hour
    if not hour then
        return false, "Missing hour (0-23)"
    end

    -- Try direct call first (silent)
    local ok, msg = DirectSetTime(tonumber(hour))
    if ok then return true, msg end
    Log("DirectSetTime failed: " .. tostring(msg) .. " — falling back to chat")

    -- Fallback: chat dispatch
    local chatCmd = string.format("!settime %d", hour)
    return DispatchChatCommand(chatCmd)
end

-- ── Command: get_time (fire-and-forget) ──────────────────────────────────────

local function CmdGetTime()
    return DispatchChatCommand("!time")
end

-- ── Command: announce ────────────────────────────────────────────────────────

local function CmdAnnounce(params)
    local message = params.message
    if not message or message == "" then
        return false, "Missing message"
    end
    local chatCmd = string.format("!announce %s", message)
    return DispatchChatCommand(chatCmd)
end

-- ── Command: slay_player ─────────────────────────────────────────────────────

local function CmdSlayPlayer(params)
    local target = params.target_player
    if not target or target == "" then
        return false, "Missing target_player"
    end
    local chatCmd = string.format("!slay %s", target)
    return DispatchChatCommand(chatCmd)
end

-- ── Command: freeze_player ───────────────────────────────────────────────────

local function CmdFreezePlayer(params)
    local target = params.target_player
    if not target or target == "" then
        return false, "Missing target_player"
    end
    local chatCmd = string.format("!freeze %s", target)
    return DispatchChatCommand(chatCmd)
end

-- ── Command: unfreeze_player ─────────────────────────────────────────────────

local function CmdUnfreezePlayer(params)
    local target = params.target_player
    if not target or target == "" then
        return false, "Missing target_player"
    end
    local chatCmd = string.format("!unfreeze %s", target)
    return DispatchChatCommand(chatCmd)
end

-- ── Command: spectate ────────────────────────────────────────────────────────

local function CmdSpectate()
    return DispatchChatCommand("!spectate")
end

-- ── Command: kick_player ─────────────────────────────────────────────────────

local function CmdKickPlayer(params)
    local target = params.target_player
    if not target or target == "" then
        return false, "Missing target_player"
    end
    local chatCmd = string.format("!kick %s", target)
    return DispatchChatCommand(chatCmd)
end

-- ── Command: ban_player ──────────────────────────────────────────────────────

local function CmdBanPlayer(params)
    local target = params.target_player
    if not target or target == "" then
        return false, "Missing target_player"
    end
    local reason = params.reason or ""
    local chatCmd
    if reason ~= "" then
        chatCmd = string.format("!ban %s %s", target, reason)
    else
        chatCmd = string.format("!ban %s", target)
    end
    return DispatchChatCommand(chatCmd)
end

-- ── Command: unban_player ────────────────────────────────────────────────────

local function CmdUnbanPlayer(params)
    local target = params.target_player
    if not target or target == "" then
        return false, "Missing target_player"
    end
    local chatCmd = string.format("!unban %s", target)
    return DispatchChatCommand(chatCmd)
end

-- ── Command: get_pos (fire-and-forget) ───────────────────────────────────────

local function CmdGetPos(params)
    local target = params.target_player
    if not target or target == "" then
        return false, "Missing target_player"
    end
    local chatCmd = string.format("!getpos %s", target)
    return DispatchChatCommand(chatCmd)
end

-- ── Command: teleport_player (compound: goto + bring) ────────────────────────

local function CmdTeleportPlayer(params)
    local target = params.target_player
    local x = params.x
    local y = params.y
    local z = params.z
    if not target or target == "" then
        return false, "Missing target_player"
    end
    if not x or not y or not z then
        return false, "Missing x, y, or z coordinates"
    end

    local nx, ny, nz = tonumber(x), tonumber(y), tonumber(z)

    -- Try fully silent path: direct goto + delayed direct bring
    local gotoOk, gotoMsg = DirectGotoCoords(nx, ny, nz)
    if gotoOk then
        -- Step 2: Delayed bring (1s via LoopAsync)
        LoopAsync(1000, function()
            local bringOk, bringMsg = DirectBringPlayer(target)
            if not bringOk then
                -- Fallback bring via chat
                Log("DirectBringPlayer failed in teleport: " .. tostring(bringMsg) .. " — falling back to chat")
                DispatchChatCommand(string.format("!bring %s", target))
            end
            Log(string.format("Teleport: brought %s to (%s,%s,%s)", target, tostring(x), tostring(y), tostring(z)))
            return true
        end)
        return true, string.format("Teleporting %s to (%s,%s,%s) (silent)...", target, tostring(x), tostring(y), tostring(z))
    end

    Log("DirectGotoCoords failed in teleport: " .. tostring(gotoMsg) .. " — falling back to chat")

    -- Fallback: chat dispatch (existing behaviour)
    local gotoCmd = string.format("!goto %s,%s,%s", tostring(x), tostring(y), tostring(z))
    local ok1, msg1 = DispatchChatCommand(gotoCmd)
    if not ok1 then
        return false, "Goto failed: " .. tostring(msg1)
    end

    LoopAsync(1000, function()
        local bringCmd = string.format("!bring %s", target)
        DispatchChatCommand(bringCmd)
        Log(string.format("Teleport: brought %s to (%s,%s,%s)", target, tostring(x), tostring(y), tostring(z)))
        return true
    end)

    return true, string.format("Teleporting %s to (%s,%s,%s)...", target, tostring(x), tostring(y), tostring(z))
end

-- ── Command: send_player_to_player ──────────────────────────────────────────
-- Teleport player A directly to player B's location (no admin movement needed)

local function CmdSendPlayerToPlayer(params)
    local source = params.source_player
    local dest = params.target_player
    if not source or source == "" then
        return false, "Missing source_player"
    end
    if not dest or dest == "" then
        return false, "Missing target_player"
    end
    if source == dest then
        return false, "Source and destination are the same player"
    end

    local ok, msg = DirectSendPlayerToPlayer(source, dest)
    if ok then return true, msg end

    return false, "Send player to player failed: " .. tostring(msg)
end

-- ── Command: dump_properties (Phase A — property discovery) ──────────────────
-- Enumerates UObject properties for interactive exploration via the Explorer page.
-- Uses FindAllOf + ForEachProperty + GetSuperStruct chain, inspired by dump_object.lua.

local function CmdDumpProperties(params)
    local className = params.class_name
    if not className or className == "" then
        return false, "Missing class_name"
    end
    local instIdx = params.instance_index or 0
    local propPath = params.property_path or ""
    local maxItems = params.max_items or 50
    if maxItems > 200 then maxItems = 200 end

    -- Step 1: Find all instances of the class
    local instances = nil
    local findOk, findErr = pcall(function()
        instances = FindAllOf(className)
    end)
    if not findOk or not instances then
        return false, "FindAllOf('" .. className .. "') failed: " .. tostring(findErr or "no instances found")
    end

    local instCount = 0
    for _ in ipairs(instances) do instCount = instCount + 1 end
    if instCount == 0 then
        return false, "No instances of '" .. className .. "' found"
    end

    -- Step 2: Pick instance (Lua 1-indexed)
    local luaIdx = instIdx + 1
    if luaIdx < 1 or luaIdx > instCount then
        return false, string.format("instance_index %d out of range (0..%d)", instIdx, instCount - 1)
    end
    local obj = instances[luaIdx]
    if not obj or not obj:IsValid() then
        return false, "Instance at index " .. instIdx .. " is not valid"
    end

    -- Step 3: Navigate property_path (dot-separated)
    local pathParts = {}
    if propPath ~= "" then
        for part in propPath:gmatch("[^%.]+") do
            table.insert(pathParts, part)
        end
    end
    local currentPath = className .. "[" .. instIdx .. "]"
    for _, part in ipairs(pathParts) do
        local navOk, navResult = pcall(function()
            return obj[part]
        end)
        if not navOk or navResult == nil then
            return false, "Cannot navigate to '" .. part .. "' from " .. currentPath .. ": " .. tostring(navResult)
        end
        -- Check validity if it's a UObject
        local validOk, isValid = pcall(function()
            return navResult.IsValid and navResult:IsValid()
        end)
        if validOk and not isValid then
            return false, "Object at '" .. part .. "' is not valid (from " .. currentPath .. ")"
        end
        obj = navResult
        currentPath = currentPath .. "." .. part
    end

    -- Step 4: Enumerate properties via ForEachProperty + GetSuperStruct chain
    local properties = {}
    local propCount = 0

    local function EnumProperties(classObj)
        if not classObj or propCount >= maxItems then return end
        local classValid = false
        pcall(function() classValid = classObj:IsValid() end)
        if not classValid then return end

        local feOk, feErr = pcall(function()
            classObj:ForEachProperty(function(prop)
                if propCount >= maxItems then return true end  -- stop iteration

                local entry = { name = "?", type = "?", offset = 0, value = "?" }

                -- Property name
                pcall(function()
                    entry.name = prop:GetFName():ToString()
                end)

                -- Property type (class name)
                pcall(function()
                    entry.type = prop:GetClass():GetFName():ToString()
                end)

                -- Offset
                pcall(function()
                    entry.offset = prop:GetOffset_Internal()
                end)

                -- Read value based on type, all in pcall
                local valOk, valStr = pcall(function()
                    local propName = entry.name
                    local propType = entry.type
                    local v = obj[propName]

                    if v == nil then return "nil" end

                    -- Numeric types
                    if propType == "IntProperty" or propType == "Int64Property"
                        or propType == "FloatProperty" or propType == "ByteProperty"
                        or propType == "Int8Property" or propType == "Int16Property"
                        or propType == "DoubleProperty" or propType == "UInt16Property"
                        or propType == "UInt32Property" or propType == "UInt64Property" then
                        return tostring(v)

                    -- String types
                    elseif propType == "StrProperty" or propType == "NameProperty" or propType == "TextProperty" then
                        if type(v) == "string" then return v end
                        local tsOk, ts = pcall(function() return v:ToString() end)
                        if tsOk then return ts end
                        return tostring(v)

                    -- Bool
                    elseif propType == "BoolProperty" then
                        return v and "true" or "false"

                    -- Object references
                    elseif propType == "ObjectProperty" or propType == "ClassProperty" then
                        local fnOk, fn = pcall(function() return v:GetFullName() end)
                        if fnOk then return fn end
                        return "Object (cannot read full name)"

                    -- Array
                    elseif propType == "ArrayProperty" then
                        local numOk, num = pcall(function() return v:GetArrayNum() end)
                        if numOk then return "Array[" .. num .. "]" end
                        return "Array[?]"

                    -- Struct
                    elseif propType == "StructProperty" then
                        local fnOk, fn = pcall(function() return v:GetFullName() end)
                        if fnOk then return fn end
                        return "Struct"

                    -- Enum
                    elseif propType == "EnumProperty" then
                        -- Try to get the enum name
                        local enumOk, enumStr = pcall(function()
                            local enumObj = prop:GetEnum()
                            local enumName = enumObj:GetNameByValue(v):ToString()
                            return enumName .. "(" .. tostring(v) .. ")"
                        end)
                        if enumOk then return enumStr end
                        return tostring(v)

                    -- Map
                    elseif propType == "MapProperty" then
                        return "UNHANDLED_MAP"

                    -- Weak object
                    elseif propType == "WeakObjectProperty" then
                        return "UNHANDLED_WEAK"

                    -- Soft object
                    elseif propType == "SoftObjectProperty" then
                        return "UNHANDLED_SOFT"

                    -- Delegate
                    elseif propType == "DelegateProperty" or propType == "MulticastDelegateProperty"
                        or propType == "MulticastInlineDelegateProperty"
                        or propType == "MulticastSparseDelegateProperty" then
                        return "DELEGATE"

                    -- Interface
                    elseif propType == "InterfaceProperty" then
                        return "INTERFACE"

                    else
                        -- Fallback: try ToString, then tostring
                        local tsOk, ts = pcall(function() return v:ToString() end)
                        if tsOk then return ts end
                        local fnOk, fn = pcall(function() return v:GetFullName() end)
                        if fnOk then return fn end
                        return tostring(v)
                    end
                end)

                if valOk then
                    entry.value = valStr
                else
                    entry.value = "ERROR: " .. tostring(valStr)
                end

                table.insert(properties, entry)
                propCount = propCount + 1
            end)
        end)

        -- Walk up the class hierarchy
        local superOk, superClass = pcall(function() return classObj:GetSuperStruct() end)
        if superOk and superClass then
            EnumProperties(superClass)
        end
    end

    -- Get the class of the current object and enumerate
    local classOk, objClass = pcall(function() return obj:GetClass() end)
    if not classOk or not objClass then
        -- Maybe obj itself is a struct — try enumerating directly
        pcall(function() EnumProperties(obj) end)
    else
        EnumProperties(objClass)
    end

    -- Build response
    local result = {
        class = currentPath,
        instance_count = instCount,
        instance_index = instIdx,
        property_count = propCount,
        properties = properties
    }
    return true, json.encode(result)
end

-- ── Command: dump_functions — enumerate UFunctions on a class ────────────────
-- Similar to dump_properties but lists callable functions instead of data fields.
-- For each function: name, parameters (name + type), return type, flags.

local function CmdDumpFunctions(params)
    local className = params.class_name
    if not className or className == "" then
        return false, "Missing class_name"
    end
    local instIdx = params.instance_index or 0
    local propPath = params.property_path or ""
    local maxItems = params.max_items or 100
    if maxItems > 300 then maxItems = 300 end
    local filter = params.filter or ""  -- optional name filter (case-insensitive substring)
    filter = filter:lower()

    -- Step 1: Find instances
    local instances = nil
    pcall(function() instances = FindAllOf(className) end)
    if not instances then
        return false, "FindAllOf('" .. className .. "') failed or no instances"
    end

    local instCount = 0
    for _ in ipairs(instances) do instCount = instCount + 1 end
    if instCount == 0 then
        return false, "No instances of '" .. className .. "'"
    end

    local luaIdx = instIdx + 1
    if luaIdx < 1 or luaIdx > instCount then
        return false, string.format("instance_index %d out of range (0..%d)", instIdx, instCount - 1)
    end
    local obj = instances[luaIdx]
    if not obj or not obj:IsValid() then
        return false, "Instance at index " .. instIdx .. " is not valid"
    end

    -- Step 2: Navigate property_path
    local currentPath = className .. "[" .. instIdx .. "]"
    if propPath ~= "" then
        for part in propPath:gmatch("[^%.]+") do
            local navOk, navResult = pcall(function() return obj[part] end)
            if not navOk or navResult == nil then
                return false, "Cannot navigate to '" .. part .. "' from " .. currentPath
            end
            obj = navResult
            currentPath = currentPath .. "." .. part
        end
    end

    -- Step 3: Enumerate functions via ForEachFunction + GetSuperStruct chain
    local functions = {}
    local funcCount = 0

    local function EnumFunctions(classObj)
        if not classObj or funcCount >= maxItems then return end
        local classValid = false
        pcall(function() classValid = classObj:IsValid() end)
        if not classValid then return end

        -- Try ForEachFunction (UE4SS API)
        local feOk = pcall(function()
            classObj:ForEachFunction(function(func)
                if funcCount >= maxItems then return true end

                local entry = { name = "?", params = {}, return_type = "", flags = "" }

                -- Function name
                pcall(function()
                    entry.name = func:GetFName():ToString()
                end)

                -- Apply filter
                if filter ~= "" and not entry.name:lower():find(filter, 1, true) then
                    return false  -- skip, continue iteration
                end

                -- Function flags
                pcall(function()
                    local flagVal = func:GetFunctionFlags()
                    local flagNames = {}
                    -- Common FUNC_ flag bits
                    if flagVal & 0x00000001 ~= 0 then table.insert(flagNames, "Final") end
                    if flagVal & 0x00000400 ~= 0 then table.insert(flagNames, "Native") end
                    if flagVal & 0x00000800 ~= 0 then table.insert(flagNames, "Event") end
                    if flagVal & 0x00004000 ~= 0 then table.insert(flagNames, "BlueprintEvent") end
                    if flagVal & 0x00020000 ~= 0 then table.insert(flagNames, "Net") end
                    if flagVal & 0x00200000 ~= 0 then table.insert(flagNames, "BlueprintCallable") end
                    if flagVal & 0x04000000 ~= 0 then table.insert(flagNames, "HasOutParms") end
                    if flagVal & 0x40000000 ~= 0 then table.insert(flagNames, "Static") end
                    entry.flags = table.concat(flagNames, ", ")
                end)

                -- Enumerate parameters (each param is an FProperty with CPF_Parm flag)
                pcall(function()
                    func:ForEachProperty(function(param)
                        local pEntry = { name = "?", type = "?", direction = "in" }
                        pcall(function() pEntry.name = param:GetFName():ToString() end)
                        pcall(function() pEntry.type = param:GetClass():GetFName():ToString() end)

                        -- Check if it's a return value or out param
                        pcall(function()
                            local pflags = param:GetPropertyFlags()
                            if pEntry.name == "ReturnValue" then
                                entry.return_type = pEntry.type
                                return  -- don't add to params list
                            end
                            if pflags & 0x0000000000000100 ~= 0 then  -- CPF_OutParm
                                pEntry.direction = "out"
                            end
                        end)

                        if pEntry.name ~= "ReturnValue" then
                            table.insert(entry.params, pEntry)
                        end
                    end)
                end)

                table.insert(functions, entry)
                funcCount = funcCount + 1
            end)
        end)

        if not feOk then
            -- Fallback: try iterating Children linked list
            pcall(function()
                local child = classObj:GetChildren()
                while child and funcCount < maxItems do
                    local childClassName = ""
                    pcall(function() childClassName = child:GetClass():GetFName():ToString() end)
                    if childClassName == "Function" then
                        local entry = { name = "?", params = {}, return_type = "", flags = "" }
                        pcall(function() entry.name = child:GetFName():ToString() end)
                        if filter == "" or entry.name:lower():find(filter, 1, true) then
                            table.insert(functions, entry)
                            funcCount = funcCount + 1
                        end
                    end
                    child = child:GetNext()
                end
            end)
        end

        -- Walk up class hierarchy
        local superOk, superClass = pcall(function() return classObj:GetSuperStruct() end)
        if superOk and superClass then
            EnumFunctions(superClass)
        end
    end

    local classOk, objClass = pcall(function() return obj:GetClass() end)
    if classOk and objClass then
        EnumFunctions(objClass)
    end

    local result = {
        class = currentPath,
        instance_count = instCount,
        instance_index = instIdx,
        function_count = funcCount,
        functions = functions
    }
    return true, json.encode(result)
end

-- ── Command: generate_sdk — trigger CXXHeaderDump ───────────────────────────
-- Calls UE4SS's built-in GenerateSDK() to dump all C++ headers to disk.
-- Output goes to ue4ss/CXXHeaderDump/. This is a one-shot operation.

local function CmdGenerateSDK(params)
    local genOk, genErr = pcall(function()
        GenerateSDK()
    end)
    if genOk then
        local dumpDir = ProjectRoot .. "\\server\\Pal\\Binaries\\Win64\\ue4ss\\CXXHeaderDump"
        return true, "SDK generation triggered. Output: " .. dumpDir
    else
        return false, "GenerateSDK() failed: " .. tostring(genErr)
    end
end

-- ── Phase B: Auto-Discovery + Live Player Data ──────────────────────────────
-- Property names are auto-discovered at runtime via UObject reflection.
-- The first call to any Phase B command triggers discovery if not done yet.
-- No hardcoded property name guesses — the system finds the right names itself.

-- Helper: safely read a nested property chain from an object
local function SafeRead(obj, ...)
    local current = obj
    for _, key in ipairs({...}) do
        if current == nil then return nil end
        local ok, val = pcall(function() return current[key] end)
        if not ok or val == nil then return nil end
        current = val
    end
    return current
end

-- Helper: safely convert to string
local function SafeToString(val)
    if val == nil then return nil end
    local ok, str = pcall(function()
        if type(val) == "string" then return val end
        if type(val) == "number" or type(val) == "boolean" then return tostring(val) end
        local tsOk, ts = pcall(function() return val:ToString() end)
        if tsOk then return ts end
        return tostring(val)
    end)
    if ok then return str end
    return nil
end

-- Helper: safely read a numeric value
local function SafeNum(obj, ...)
    local val = SafeRead(obj, ...)
    if val == nil then return nil end
    if type(val) == "number" then return val end
    -- Try tonumber on the string representation first
    local ok, n = pcall(function() return tonumber(tostring(val)) end)
    if ok and n then return n end
    -- Palworld wraps many numeric stats in FFixedPoint64 / struct UObjects.
    -- Drill into common sub-property names to extract the actual number.
    for _, sub in ipairs({"Value", "value", "Int", "Float"}) do
        local sOk, sVal = pcall(function() return val[sub] end)
        if sOk and sVal ~= nil then
            if type(sVal) == "number" then return sVal end
            local nOk, nVal = pcall(function() return tonumber(tostring(sVal)) end)
            if nOk and nVal then return nVal end
        end
    end
    return nil
end

-- ── Auto-Discovery System ───────────────────────────────────────────────────
-- Probes UObject class hierarchies via ForEachProperty to find actual property
-- names at runtime. Caches results so subsequent calls are fast direct reads.

local DiscoveryCache = {
    probed = false,       -- true = full discovery completed (incl. pawn sub-objects)
    attempted = false,    -- true = discovery was attempted (prevents retry-hammering)
    last_attempt = 0,     -- os.clock() of last attempt (for retry cooldown)
    -- PalPlayerState properties
    ps_level = nil,       -- IntProperty for player level
    ps_pawn = nil,        -- ObjectProperty for pawn/character reference
    -- Pawn/Character properties
    pawn_hp = nil,
    pawn_max_hp = nil,
    pawn_params = nil,    -- parameter/stats component
    pawn_inventory = nil, -- inventory component
    pawn_pal_storage = nil, -- pal party/storage component
    -- Parameter component sub-properties
    param_hp = nil,
    param_max_hp = nil,
    param_attack = nil,
    param_defense = nil,
    -- Inventory sub-properties
    inv_slots = nil,
    -- Report of everything found (for probe_properties response)
    report = {},
}

-- Load cached discovery from disk (survives server restarts)
pcall(function()
    local raw = ReadFile(DiscoveryLogFile)
    if not raw then return end
    local cached = json.decode(raw)
    if not cached or not cached.properties then return end

    -- Map from report keys back to DiscoveryCache fields
    local keyMap = {
        ps_level = "ps_level", ps_pawn = "ps_pawn",
        pawn_hp = "pawn_hp", pawn_max_hp = "pawn_max_hp",
        pawn_params = "pawn_params", pawn_inventory = "pawn_inventory",
        pawn_pal_storage = "pawn_pal_storage",
        param_hp = "param_hp", param_max_hp = "param_max_hp",
        param_attack = "param_attack", param_defense = "param_defense",
        inv_slots = "inv_slots",
    }

    local loaded = 0
    for key, field in pairs(keyMap) do
        local val = cached.properties[key]
        if val and val ~= "NOT_FOUND" then
            DiscoveryCache[field] = val
            loaded = loaded + 1
        end
    end
    DiscoveryCache.report = cached.properties
    if loaded > 0 then
        DiscoveryCache.probed = true
        Log(string.format("Discovery cache loaded from disk: %d/%d properties (%s)",
            loaded, cached.total_count or 0, cached.timestamp or "?"))
    end
end)

-- Reset all discovered property names to nil (for clean re-probe)
local function ResetDiscoveryCache()
    DiscoveryCache.probed = false
    DiscoveryCache.attempted = false
    DiscoveryCache.last_attempt = 0
    DiscoveryCache.ps_level = nil
    DiscoveryCache.ps_pawn = nil
    DiscoveryCache.pawn_hp = nil
    DiscoveryCache.pawn_max_hp = nil
    DiscoveryCache.pawn_params = nil
    DiscoveryCache.pawn_inventory = nil
    DiscoveryCache.pawn_pal_storage = nil
    DiscoveryCache.param_hp = nil
    DiscoveryCache.param_max_hp = nil
    DiscoveryCache.param_attack = nil
    DiscoveryCache.param_defense = nil
    DiscoveryCache.inv_slots = nil
    DiscoveryCache.report = {}
end

-- Collect all properties from an object's class hierarchy
local function CollectProperties(obj)
    local allProps = {}
    if not obj then return allProps end

    local function collectFromClass(cls)
        if not cls then return end
        pcall(function()
            cls:ForEachProperty(function(prop)
                local name, propType = "", ""
                pcall(function() name = prop:GetFName():ToString() end)
                pcall(function() propType = prop:GetClass():GetFName():ToString() end)
                if name ~= "" then
                    table.insert(allProps, { name = name, type = propType })
                end
            end)
            local sOk, s = pcall(function() return cls:GetSuperStruct() end)
            if sOk and s then collectFromClass(s) end
        end)
    end

    pcall(function()
        local cls = obj:GetClass()
        collectFromClass(cls)
    end)
    return allProps
end

-- Search collected properties for the first name matching any candidate pattern.
-- candidates: ordered list — most specific first (e.g. {"PawnPrivate", "Pawn"}).
-- typeFilter: string or {string} of allowed property types, or nil for any.
-- Returns: matched property name (string) or nil.
local function FindMatchingProperty(allProps, candidates, typeFilter)
    local typeSet = {}
    if type(typeFilter) == "string" then
        typeSet[typeFilter] = true
    elseif type(typeFilter) == "table" then
        for _, t in ipairs(typeFilter) do typeSet[t] = true end
    end
    local hasTypeFilter = next(typeSet) ~= nil

    -- Pass 1: exact match (case-insensitive)
    for _, candidate in ipairs(candidates) do
        local lc = candidate:lower()
        for _, p in ipairs(allProps) do
            if hasTypeFilter and not typeSet[p.type] then
                -- skip
            elseif p.name:lower() == lc then
                return p.name
            end
        end
    end

    -- Pass 2: substring match (case-insensitive)
    for _, candidate in ipairs(candidates) do
        local lc = candidate:lower()
        for _, p in ipairs(allProps) do
            if hasTypeFilter and not typeSet[p.type] then
                -- skip
            elseif p.name:lower():find(lc, 1, true) then
                return p.name
            end
        end
    end

    return nil
end

-- Run full auto-discovery on PalPlayerState and its sub-objects.
-- Uses DIRECT PROPERTY READS (obj[name] via pcall) instead of ForEachProperty.
-- ForEachProperty walks UClass metadata structures and causes native crashes
-- that pcall cannot catch. Direct reads use the same safe mechanism as
-- GetAllPlayers() which is proven stable.
local function RunDiscovery()
    Log("Auto-discovery: probing PalPlayerState properties (direct read)...")

    -- Mark as attempted with timestamp to enable cooldown-based retry
    DiscoveryCache.attempted = true
    DiscoveryCache.last_attempt = os.clock()

    local instances = nil
    pcall(function() instances = FindAllOf("PalPlayerState") end)
    if not instances then
        Log("Auto-discovery: No PalPlayerState instances — need at least one player connected")
        return false
    end

    -- Find a valid, readable instance (verify with a known-safe property read)
    local ps = nil
    for _, inst in ipairs(instances) do
        local ok, valid = pcall(function() return inst:IsValid() end)
        if ok and valid then
            -- Verify we can read a known property (same pattern as GetAllPlayers)
            local nameOk = pcall(function() local _ = inst.PlayerNamePrivate end)
            if nameOk then
                ps = inst
                break
            end
        end
    end
    if not ps then
        Log("Auto-discovery: No readable PalPlayerState instance — will retry")
        return false
    end

    -- Clear all stale property names before re-scanning
    ResetDiscoveryCache()
    DiscoveryCache.attempted = true  -- re-set after reset
    DiscoveryCache.last_attempt = os.clock()
    local function record(key, val)
        DiscoveryCache.report[key] = val or "NOT_FOUND"
        if val then
            Log(string.format("  + %s = '%s'", key, val))
        else
            Log(string.format("  - %s = not found", key))
        end
    end

    -- Try to read a property by name. Returns the name if readable (non-nil), nil otherwise.
    -- This is safe: same obj[key] pattern used by GetAllPlayers / SafeRead.
    local function findFirst(obj, candidates)
        for _, name in ipairs(candidates) do
            local ok, val = pcall(function() return obj[name] end)
            if ok and val ~= nil then return name end
        end
        return nil
    end

    -- 1. Level on PlayerState
    DiscoveryCache.ps_level = findFirst(ps,
        { "Level", "SavedLevel", "PlayerLevel", "CharacterLevel", "Exp_Level" })
    record("ps_level", DiscoveryCache.ps_level)

    -- 2. Pawn reference
    DiscoveryCache.ps_pawn = findFirst(ps,
        { "PawnPrivate", "Pawn", "MyPawn", "PalPlayerCharacter", "Character",
          "CharacterPrivate", "OwnedPawn" })
    record("ps_pawn", DiscoveryCache.ps_pawn)

    -- Navigate to pawn for deeper discovery
    local pawn = nil
    if DiscoveryCache.ps_pawn then
        pawn = SafeRead(ps, DiscoveryCache.ps_pawn)
    end

    if pawn then
        -- 3. HP directly on pawn
        DiscoveryCache.pawn_hp = findFirst(pawn,
            { "HP", "Health", "CurrentHP", "HitPoints", "CurrentHealth" })
        record("pawn_hp", DiscoveryCache.pawn_hp)

        DiscoveryCache.pawn_max_hp = findFirst(pawn,
            { "MaxHP", "MaxHealth", "MaxHitPoints" })
        record("pawn_max_hp", DiscoveryCache.pawn_max_hp)

        -- 4. Parameter/stats component
        DiscoveryCache.pawn_params = findFirst(pawn,
            { "CharacterParameterComponent", "ParameterComponent", "CharacterParameter",
              "StatusComponent", "StatsComponent", "IndividualParameter" })
        record("pawn_params", DiscoveryCache.pawn_params)

        -- 5. Inventory component
        DiscoveryCache.pawn_inventory = findFirst(pawn,
            { "InventoryComponent", "ItemContainer", "InventoryData", "Inventory",
              "ItemInventory", "PlayerInventory" })
        record("pawn_inventory", DiscoveryCache.pawn_inventory)

        -- 6. Pal storage / party component
        DiscoveryCache.pawn_pal_storage = findFirst(pawn,
            { "PalStorageComponent", "OtomoHolder", "PartyPals", "PalHolder",
              "OtomoComponent", "PalPartyComponent", "OtomoSlot" })
        record("pawn_pal_storage", DiscoveryCache.pawn_pal_storage)

        -- 7. Probe parameter component deeper
        if DiscoveryCache.pawn_params then
            local params = SafeRead(pawn, DiscoveryCache.pawn_params)
            if params then
                DiscoveryCache.param_hp = findFirst(params, { "HP", "Health", "CurrentHP" })
                record("param_hp", DiscoveryCache.param_hp)

                DiscoveryCache.param_max_hp = findFirst(params, { "MaxHP", "MaxHealth" })
                record("param_max_hp", DiscoveryCache.param_max_hp)

                DiscoveryCache.param_attack = findFirst(params,
                    { "Attack", "MeleeAttack", "AttackPower", "Atk", "Power" })
                record("param_attack", DiscoveryCache.param_attack)

                DiscoveryCache.param_defense = findFirst(params,
                    { "Defense", "Defence", "Def" })
                record("param_defense", DiscoveryCache.param_defense)
            end
        end

        -- 8. Probe inventory deeper
        if DiscoveryCache.pawn_inventory then
            local inv = SafeRead(pawn, DiscoveryCache.pawn_inventory)
            if inv then
                DiscoveryCache.inv_slots = findFirst(inv,
                    { "ItemSlots", "Slots", "Items", "ItemArray", "ContainerSlots",
                      "InventorySlots" })
                record("inv_slots", DiscoveryCache.inv_slots)
            end
        end
    else
        Log("Auto-discovery: Could not navigate to pawn — will retry on next call")
        -- Don't set probed=true so EnsureDiscovery retries when a pawn becomes available
        -- But attempted=true prevents hammering on every poll tick
        return false
    end

    DiscoveryCache.probed = true

    local foundCount = 0
    for _, v in pairs(DiscoveryCache.report) do
        if v ~= "NOT_FOUND" then foundCount = foundCount + 1 end
    end
    local totalCount = 0
    for _ in pairs(DiscoveryCache.report) do totalCount = totalCount + 1 end
    Log(string.format("Auto-discovery complete: %d/%d properties mapped",
        foundCount, totalCount))

    -- Persist discovery results to disk for debugging across restarts
    pcall(function()
        local logData = {
            timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
            found_count = foundCount,
            total_count = totalCount,
            properties = DiscoveryCache.report,
        }
        WriteFile(DiscoveryLogFile, json.encode(logData))
        Log("Discovery log saved to " .. DiscoveryLogFile)
    end)

    return true
end

-- Ensure discovery has run before any Phase B read.
-- Retries every 30s if not yet probed (e.g. waiting for first player to connect).
-- Boot delay: wait 60s after mod load before first attempt — gives UObjects time
-- to fully initialise and avoids native crashes from partially-constructed state.
local DISCOVERY_RETRY_INTERVAL = 30  -- seconds between retry attempts
local DISCOVERY_BOOT_DELAY = 60      -- seconds after mod load before first probe
local function EnsureDiscovery()
    if DiscoveryCache.probed then return end
    local now = os.clock()
    -- Don't probe too soon after server start — objects may not be fully initialised
    if (now - BootTime) < DISCOVERY_BOOT_DELAY then return end
    -- Cooldown: don't retry more than once per interval
    if DiscoveryCache.attempted and (now - DiscoveryCache.last_attempt) < DISCOVERY_RETRY_INTERVAL then
        return
    end
    RunDiscovery()
end

-- ── Command: probe_properties ───────────────────────────────────────────────
-- Triggers (or re-triggers) auto-discovery and returns the full report.

local function CmdProbeProperties(params)
    local force = params and params.force
    if force or not DiscoveryCache.probed then
        ResetDiscoveryCache()  -- clear all stale names before re-scanning
        local ok = RunDiscovery()
        if not ok then
            return false, "Discovery failed — is a player connected?"
        end
    end

    return true, json.encode({
        probed = DiscoveryCache.probed,
        properties = DiscoveryCache.report,
    })
end

-- Helper: count how many properties discovery found vs total
local function DiscoveryFoundCount()
    local found, total = 0, 0
    for _, v in pairs(DiscoveryCache.report) do
        total = total + 1
        if v ~= "NOT_FOUND" then found = found + 1 end
    end
    return found, total
end

-- ── Command: get_players_live ────────────────────────────────────────────────
-- Lightweight summary for auto-refresh: name, level, HP, party count.
-- Uses auto-discovered property names from DiscoveryCache.

local function CmdGetPlayersLive()
    EnsureDiscovery()

    local result = {}
    local players = GetAllPlayers()

    for _, p in ipairs(players) do
        local entry = { name = p.name }

        pcall(function()
            local ps = p.state
            if not ps then return end

            -- Navigate to pawn via discovered property name
            local pawn = nil
            if DiscoveryCache.ps_pawn then
                pawn = SafeRead(ps, DiscoveryCache.ps_pawn)
            end

            if pawn then
                -- Use getter FUNCTIONS on CharacterParameterComponent.
                -- These return plain int32/float values, not FFixedPoint64 wrappers.
                -- Access chain: pawn → CharacterParameterComponent → GetLevel() etc.
                local paramComp = SafeRead(pawn, "CharacterParameterComponent")
                if paramComp then
                    pcall(function() entry.level = paramComp:GetLevel() end)
                    pcall(function() entry.hp_rate = paramComp:GetHPRate() end)
                    pcall(function() entry.attack = paramComp:GetMeleeAttack() end)
                    pcall(function() entry.defense = paramComp:GetDefense() end)
                    pcall(function() entry.fullstomach = paramComp:GetFullStomach() end)
                    pcall(function() entry.max_fullstomach = paramComp:GetMaxFullStomach() end)
                    pcall(function() entry.sanity = paramComp:GetSanity() end)
                    pcall(function() entry.max_sanity = paramComp:GetMaxSanity() end)
                end
            end
        end)

        table.insert(result, entry)
    end

    -- Debug: log summary of what was read (once per call, not per player)
    if #result > 0 then
        local sample = result[1]
        Log(string.format("get_players_live: %d players, sample[%s]: level=%s hp_rate=%s atk=%s def=%s",
            #result,
            tostring(sample.name),
            tostring(sample.level or "nil"),
            tostring(sample.hp_rate or "nil"),
            tostring(sample.attack or "nil"),
            tostring(sample.defense or "nil")))
    end

    local dFound, dTotal = DiscoveryFoundCount()
    return true, json.encode({
        players = result,
        source = "lua_mod",
        discovery = DiscoveryCache.probed and "ok" or "pending",
        discovery_found = dFound,
        discovery_total = dTotal,
    })
end

-- ── Command: get_player_detail ───────────────────────────────────────────────
-- Rich data for a selected player: stats, inventory items, party pals.
-- Uses auto-discovered property names from DiscoveryCache.

local function CmdGetPlayerDetail(params)
    local targetName = params.target_player
    if not targetName or targetName == "" then
        return false, "Missing target_player"
    end

    EnsureDiscovery()

    local player = FindPlayerByName(targetName)
    if not player then
        return false, "Player not found: " .. targetName
    end

    local detail = { name = player.name }

    pcall(function()
        local ps = player.state
        if not ps then return end

        -- Navigate to pawn via discovered property name
        local pawn = nil
        if DiscoveryCache.ps_pawn then
            pawn = SafeRead(ps, DiscoveryCache.ps_pawn)
        end
        if not pawn then return end

        -- Use getter FUNCTIONS on CharacterParameterComponent.
        -- These return plain int32/float values, not FFixedPoint64 wrappers.
        local paramComp = SafeRead(pawn, "CharacterParameterComponent")
        if paramComp then
            pcall(function() detail.level = paramComp:GetLevel() end)
            pcall(function() detail.hp_rate = paramComp:GetHPRate() end)
            pcall(function() detail.attack = paramComp:GetMeleeAttack() end)
            pcall(function() detail.defense = paramComp:GetDefense() end)
            pcall(function() detail.shot_attack = paramComp:GetShotAttack() end)
            pcall(function() detail.craft_speed = paramComp:GetCraftSpeed() end)
            pcall(function() detail.fullstomach = paramComp:GetFullStomach() end)
            pcall(function() detail.max_fullstomach = paramComp:GetMaxFullStomach() end)
            pcall(function() detail.sanity = paramComp:GetSanity() end)
            pcall(function() detail.max_sanity = paramComp:GetMaxSanity() end)
        end

        -- Inventory & Party pals: skipped — native iteration crashes.
        detail.inventory = {}
        detail.party_pals = {}
    end)

    -- Debug: log what was extracted
    Log(string.format("get_player_detail[%s]: level=%s hp=%s atk=%s def=%s shot=%s craft=%s food=%.0f/%.0f san=%.0f/%.0f",
        tostring(detail.name),
        tostring(detail.level or "nil"),
        tostring(detail.hp_rate or "nil"),
        tostring(detail.attack or "nil"),
        tostring(detail.defense or "nil"),
        tostring(detail.shot_attack or "nil"),
        tostring(detail.craft_speed or "nil"),
        detail.fullstomach or 0, detail.max_fullstomach or 0,
        detail.sanity or 0, detail.max_sanity or 0))

    return true, json.encode(detail)
end

-- ── Helper: navigate to a pal's IndividualParameter by index ─────────────────
-- Chain: PlayerState → pawn → OtomoHolderComponent → GetOtomoIndividualCharacterSlot(i)
--        → GetHandle() → TryGetIndividualParameter()
-- Returns (param, holderComp, count) on success, or (nil, nil, 0, errorMsg)
local function GetPalParam(playerState, palIndex)
    -- Step 1: get pawn
    local pawn = nil
    if DiscoveryCache.ps_pawn then
        pawn = SafeRead(playerState, DiscoveryCache.ps_pawn)
    end
    if not pawn then
        -- Fallback to known property names
        for _, prop in ipairs({"PawnPrivate", "Pawn"}) do
            local ok, val = pcall(function() return playerState[prop] end)
            if ok and val then pawn = val; break end
        end
    end
    if not pawn then return nil, nil, 0, "Cannot access player pawn" end

    -- Step 2: get OtomoHolderComponent
    local holder = nil
    for _, prop in ipairs({"OtomoHolderComponent", "OtomoHolder", "PalStorageComponent"}) do
        local ok, val = pcall(function() return pawn[prop] end)
        if ok and val then holder = val; break end
    end
    if not holder then return nil, nil, 0, "Cannot find OtomoHolderComponent" end

    -- Step 3: get count
    local count = 0
    local cntOk, cntVal = pcall(function() return holder:GetOtomoCount() end)
    if cntOk and cntVal then count = cntVal end
    if count == 0 then return nil, holder, 0, "No pals in party" end

    if palIndex >= count then
        return nil, holder, count, string.format("Pal index %d out of range (0..%d)", palIndex, count - 1)
    end

    -- Step 4: navigate to individual parameter
    local param = nil
    local navOk, navErr = pcall(function()
        local slot = holder:GetOtomoIndividualCharacterSlot(palIndex)
        if not slot then error("GetOtomoIndividualCharacterSlot returned nil") end
        local handle = slot:GetHandle()
        if not handle then error("GetHandle returned nil") end
        param = handle:TryGetIndividualParameter()
    end)
    if not navOk then
        return nil, holder, count, "Navigation failed at index " .. palIndex .. ": " .. tostring(navErr)
    end
    if not param then
        return nil, holder, count, "TryGetIndividualParameter returned nil at index " .. palIndex
    end

    return param, holder, count, nil
end

-- ── Helper: read all stats from a pal's IndividualParameter ──────────────────
-- Reusable by CmdGetPlayerPals, CmdGetAllPals, etc.

-- Convert UE4SS FName/FString/enum/RemoteUnrealParam to Lua string.
-- Handles: string, number, FName userdata, RemoteUnrealParam wrappers.
local function UEStringify(val)
    if val == nil then return nil end
    if type(val) == "string" then
        if val == "" then return nil end
        -- Filter obvious garbage representations
        if string.find(val, "UObject:") or string.find(val, "RemoteUnrealParam:") then return nil end
        return val
    end
    if type(val) == "number" then return tostring(val) end

    -- For userdata: try :get() unwrap first (RemoteUnrealParam → inner value)
    local inner = val
    pcall(function()
        local unwrapped = val:get()
        if unwrapped ~= nil then inner = unwrapped end
    end)

    -- Try :ToString() on the unwrapped value (works for FName)
    local ok1, s1 = pcall(function() return inner:ToString() end)
    if ok1 and type(s1) == "string" and s1 ~= "" then
        if not string.find(s1, "UObject:") and not string.find(s1, "RemoteUnrealParam:") then
            return s1
        end
    end

    -- Try :ToString() on original val (in case :get() changed type)
    if inner ~= val then
        local ok2, s2 = pcall(function() return val:ToString() end)
        if ok2 and type(s2) == "string" and s2 ~= "" then
            if not string.find(s2, "UObject:") and not string.find(s2, "RemoteUnrealParam:") then
                return s2
            end
        end
    end

    -- Last resort: tostring()
    local ok3, s3 = pcall(function() return tostring(inner) end)
    if ok3 and type(s3) == "string" and s3 ~= "" then
        if not string.find(s3, "UObject:") and not string.find(s3, "RemoteUnrealParam:")
           and not string.find(s3, "userdata:") then
            return s3
        end
    end
    return nil
end

-- Read a TArray<FName> or TArray<Enum> from a UFunction return value.
-- UE4SS issue #397: UFunction TArray returns are stack-allocated, causing
-- dangling pointers. We must read elements IMMEDIATELY before Lua GC.
-- Tries 7 methods in order, returns (results_table, debug_string).
local function UEArrayToStrings(arr, debugLabel)
    if not arr then return {}, "nil" end
    local results = {}
    local dbg = {}
    local arrType = type(arr)
    table.insert(dbg, "type=" .. arrType)

    -- Method 1: Already a plain Lua table (TArray outparam unwrap)
    if arrType == "table" then
        for _, v in ipairs(arr) do
            local s = UEStringify(v)
            if s then table.insert(results, s) end
        end
        table.insert(dbg, "table#=" .. #results)
        return results, table.concat(dbg, ",")
    end

    -- Method 2: ForEach with :get() unwrap (best for UFunction returns)
    -- elem:get() unwraps RemoteUnrealParam → FName, then :ToString()
    pcall(function()
        arr:ForEach(function(index, elem)
            pcall(function()
                local inner = elem:get()
                if inner then
                    local s = nil
                    pcall(function() s = inner:ToString() end)
                    if s and s ~= "" and not string.find(s, "RemoteUnrealParam:") then
                        table.insert(results, s)
                    end
                end
            end)
        end)
    end)
    if #results > 0 then
        table.insert(dbg, "ForEach#=" .. #results)
        return results, table.concat(dbg, ",")
    end
    table.insert(dbg, "ForEach=0")

    -- Method 3: #arr (UE4SS __len) + arr[i] with :get() unwrap
    results = {}
    pcall(function()
        local len = #arr
        table.insert(dbg, "len=" .. len)
        for i = 0, len - 1 do
            pcall(function()
                local elem = arr[i]
                local s = UEStringify(elem)
                if s then table.insert(results, s) end
            end)
        end
    end)
    if #results > 0 then
        table.insert(dbg, "idx#=" .. #results)
        return results, table.concat(dbg, ",")
    end

    -- Method 4: :GetArrayNum() + arr[i]
    results = {}
    local ganOk, ganVal = pcall(function() return arr:GetArrayNum() end)
    if ganOk and type(ganVal) == "number" and ganVal > 0 then
        table.insert(dbg, "GAN=" .. ganVal)
        for i = 0, ganVal - 1 do
            pcall(function()
                local elem = arr[i]
                local s = UEStringify(elem)
                if s then table.insert(results, s) end
            end)
        end
        if #results > 0 then
            table.insert(dbg, "GAN#=" .. #results)
            return results, table.concat(dbg, ",")
        end
    end

    -- Method 5: ipairs on userdata
    results = {}
    pcall(function()
        for _, v in ipairs(arr) do
            local s = UEStringify(v)
            if s then table.insert(results, s) end
        end
    end)
    if #results > 0 then
        table.insert(dbg, "ipairs#=" .. #results)
        return results, table.concat(dbg, ",")
    end

    -- Method 6: pairs() to discover structure
    local pairsInfo = {}
    pcall(function()
        local n = 0
        for k, v in pairs(arr) do
            n = n + 1
            if n <= 3 then
                local s = UEStringify(v)
                table.insert(pairsInfo, tostring(k) .. "=" .. (s or tostring(v)))
                if s then table.insert(results, s) end
            end
        end
        table.insert(dbg, "pairs=" .. n)
    end)
    if #results > 0 then return results, table.concat(dbg, ",") end

    table.insert(dbg, "EMPTY")
    return results, table.concat(dbg, ",")
end

local function ReadPalStats(param)
    local entry = {}

    -- ── Identity via UFunction calls ONLY (no SaveParameter — causes native crash) ──
    -- NOTE: param.SaveParameter direct struct access causes unrecoverable C++ crash
    -- that pcall cannot catch. NEVER access it. Use UFunction getters only.

    -- CharacterID (FName → string via UEStringify)
    pcall(function()
        local s = UEStringify(param:GetCharacterID())
        if s then entry.character_id = s end
    end)

    -- Nickname — GetNickname() takes FString& outparam, not safe from Lua.
    -- Skip entirely. Frontend uses palDb species name as fallback.

    -- Gender
    pcall(function()
        local gt = param:GetGenderType()
        if type(gt) == "number" then entry.gender = gt
        else entry.gender = UEStringify(gt) end
    end)

    -- ── Passive skills (TArray<FName>) ──
    -- UE4SS issue #397: UFunction TArray returns are dangling pointers.
    -- Try chained ForEach (no intermediate variable) first, then fallback.
    local passiveDbg = "not-called"
    pcall(function()
        -- Method A: Chained ForEach on return value (stack still valid)
        local skills = {}
        local chainOk = pcall(function()
            param:GetPassiveSkillList():ForEach(function(index, elem)
                pcall(function()
                    local inner = elem:get()
                    if inner then
                        local s = nil
                        pcall(function() s = inner:ToString() end)
                        if s and s ~= "" and not string.find(s, "RemoteUnrealParam:") then
                            table.insert(skills, s)
                        end
                    end
                end)
            end)
        end)
        if chainOk and #skills > 0 then
            entry.passives = skills
            passiveDbg = "chain#=" .. #skills
        else
            -- Method B: Store then iterate (may have dangling pointer issue)
            local rawArr = param:GetPassiveSkillList()
            local list, dbg = UEArrayToStrings(rawArr, "passives")
            passiveDbg = (chainOk and "chain=0," or "chain=FAIL,") .. dbg
            if #list > 0 then entry.passives = list end
        end
    end)

    -- ── Equipped waza (TArray<EPalWazaID>) ──
    local wazaDbg = "not-called"
    pcall(function()
        local skills = {}
        local chainOk = pcall(function()
            param:GetEquipWaza():ForEach(function(index, elem)
                pcall(function()
                    local inner = elem:get()
                    if inner then
                        local s = nil
                        pcall(function() s = inner:ToString() end)
                        if not s or s == "" then
                            -- Enum values might be numbers
                            pcall(function() s = tostring(inner) end)
                        end
                        if s and s ~= "" and not string.find(s, "RemoteUnrealParam:") then
                            table.insert(skills, s)
                        end
                    end
                end)
            end)
        end)
        if chainOk and #skills > 0 then
            entry.equip_waza = skills
            wazaDbg = "chain#=" .. #skills
        else
            local rawArr = param:GetEquipWaza()
            local list, dbg = UEArrayToStrings(rawArr, "equip_waza")
            wazaDbg = (chainOk and "chain=0," or "chain=FAIL,") .. dbg
            if #list > 0 then entry.equip_waza = list end
        end
    end)

    -- ── Mastered waza ──
    pcall(function()
        local skills = {}
        local chainOk = pcall(function()
            param:GetMasteredWaza():ForEach(function(index, elem)
                pcall(function()
                    local inner = elem:get()
                    if inner then
                        local s = nil
                        pcall(function() s = inner:ToString() end)
                        if not s or s == "" then
                            pcall(function() s = tostring(inner) end)
                        end
                        if s and s ~= "" and not string.find(s, "RemoteUnrealParam:") then
                            table.insert(skills, s)
                        end
                    end
                end)
            end)
        end)
        if chainOk and #skills > 0 then
            entry.mastered_waza = skills
        else
            local rawArr = param:GetMasteredWaza()
            local list = UEArrayToStrings(rawArr, "mastered_waza")
            if #list > 0 then entry.mastered_waza = list end
        end
    end)

    -- Debug info (logged in CmdGetAllPals for first pal)
    entry._passiveDbg = passiveDbg
    entry._wazaDbg = wazaDbg

    -- ── Work Suitability ranks ──
    -- EPalWorkSuitability enum values (0-12)
    local workTypes = {
        {id = 0,  key = "EmitFlame",          name = "Kindling"},
        {id = 1,  key = "Watering",           name = "Watering"},
        {id = 2,  key = "Seeding",            name = "Planting"},
        {id = 3,  key = "GenerateElectricity", name = "Electricity"},
        {id = 4,  key = "Handcraft",          name = "Handiwork"},
        {id = 5,  key = "Collection",         name = "Gathering"},
        {id = 6,  key = "Deforest",           name = "Lumbering"},
        {id = 7,  key = "Mining",             name = "Mining"},
        {id = 8,  key = "OilExtraction",      name = "Oil Extraction"},
        {id = 9,  key = "ProductMedicine",    name = "Medicine"},
        {id = 10, key = "Cool",               name = "Cooling"},
        {id = 11, key = "Transport",          name = "Transporting"},
        {id = 12, key = "MonsterFarm",        name = "Farming"},
    }
    local wsRanks = {}
    for _, wt in ipairs(workTypes) do
        pcall(function()
            local rank = param:GetWorkSuitabilityRank(wt.id)
            if type(rank) == "number" and rank > 0 then
                table.insert(wsRanks, { id = wt.id, key = wt.key, name = wt.name, rank = rank })
            end
        end)
    end
    if #wsRanks > 0 then entry.work_suitability = wsRanks end

    -- ── Core stats (UFunction getters — return simple int/float, always reliable) ──
    pcall(function() entry.level = param:GetLevel() end)
    pcall(function() entry.exp = param:GetExp() end)
    pcall(function() entry.max_hp = param:GetMaxHP() end)
    pcall(function() entry.melee_attack = param:GetMeleeAttack_withBuff() end)
    pcall(function() entry.defense = param:GetDefense_withBuff() end)
    pcall(function() entry.craft_speed = param:GetCraftSpeed_withBuff() end)

    -- Condensation (rank stars)
    pcall(function() entry.rank = param:GetRank() end)
    pcall(function() entry.hp_rank = param:GetHPRank() end)
    pcall(function() entry.attack_rank = param:GetAttackRank() end)
    pcall(function() entry.defence_rank = param:GetDefenceRank() end)

    -- Stat points
    pcall(function() entry.hp_points = param:GetStatusPoint(FName("HP")) end)
    pcall(function() entry.atk_points = param:GetStatusPoint(FName("Attack")) end)
    pcall(function() entry.def_points = param:GetStatusPoint(FName("Defense")) end)
    pcall(function() entry.unused_points = param:GetUnusedStatusPoint() end)

    -- Status
    pcall(function() entry.is_dead = param:IsDead() end)
    pcall(function()
        local ph = param:GetPhysicalHealth()
        if type(ph) == "number" then entry.physical_health = ph
        else entry.physical_health = UEStringify(ph) end
    end)
    pcall(function() entry.friendship_rank = param:GetFriendshipRank() end)
    pcall(function() entry.friendship_point = param:GetFriendshipPoint() end)
    pcall(function() entry.fullstomach_rate = param:GetFullStomachRate() end)
    pcall(function() entry.sanity_rate = param:GetSanityRate() end)

    return entry
end

-- ── Helper: navigate to pal box param by page + slot ──────────────────────────
-- Chain: PlayerState → PalStorage → GetSlot(page, slotIdx) → GetHandle() →
--        TryGetIndividualParameter()
-- Returns (param, storage, totalSlots, errorMsg) or (nil, nil, 0, errMsg)
local function GetBoxPalParam(playerState, boxPage, slotIdx)
    -- Step 1: get PalStorage from PlayerState
    local storage = nil
    for _, prop in ipairs({"PalStorage", "PalStorageData", "OtomoPalStorage"}) do
        local ok, val = pcall(function() return playerState[prop] end)
        if ok and val then storage = val; break end
    end
    if not storage then return nil, nil, 0, "Cannot find PalStorage on PlayerState" end

    -- Step 2: get page count
    local pageCount = 0
    pcall(function() pageCount = storage:GetPageNum() end)
    if pageCount == 0 then return nil, storage, 0, "PalStorage has 0 pages" end

    if boxPage >= pageCount then
        return nil, storage, 0, string.format("Box page %d out of range (0..%d)", boxPage, pageCount - 1)
    end

    -- Step 3: get slot
    local param = nil
    local navOk, navErr = pcall(function()
        local slot = storage:GetSlot(boxPage, slotIdx)
        if not slot then error("GetSlot returned nil") end
        local handle = slot:GetHandle()
        if not handle then error("GetHandle returned nil") end
        param = handle:TryGetIndividualParameter()
    end)
    if not navOk then
        return nil, storage, 0, string.format("Box navigation failed (page=%d, slot=%d): %s", boxPage, slotIdx, tostring(navErr))
    end
    if not param then
        return nil, storage, 0, string.format("Empty slot (page=%d, slot=%d)", boxPage, slotIdx)
    end

    return param, storage, pageCount, nil
end

-- ── Command: get_player_pals (Phase C rewrite v2) ───────────────────────────
-- Reads real party pal data. Tries multiple approaches:
--   1. FindAllOf("PalOtomoHolderComponentBase") + match owner to player pawn
--   2. Direct property access on pawn
--   3. Brute-force: try reading slots 0-4 even if count=0

local function CmdGetPlayerPals(params)
    local targetName = params.target_player
    if not targetName or targetName == "" then
        return false, "Missing target_player"
    end

    EnsureDiscovery()

    local player = FindPlayerByName(targetName)
    if not player then
        return false, "Player not found: " .. targetName
    end

    local ps = player.state
    local pals = {}
    local debug = {}

    -- Step 1: get pawn
    local pawn = nil
    if DiscoveryCache.ps_pawn then
        pawn = SafeRead(ps, DiscoveryCache.ps_pawn)
    end
    if not pawn then
        for _, prop in ipairs({"PawnPrivate", "Pawn"}) do
            local ok, val = pcall(function() return ps[prop] end)
            if ok and val then pawn = val; break end
        end
    end
    if not pawn then
        return true, json.encode({ pals = {}, total = 0, note = "Cannot access player pawn" })
    end
    table.insert(debug, "pawn=ok")

    -- Step 2: find OtomoHolderComponent
    local holder = nil
    local holderMethod = nil

    -- Method A: FindAllOf to locate the correct holder component by owner
    pcall(function()
        local allHolders = FindAllOf("PalOtomoHolderComponentBase")
        if allHolders then
            table.insert(debug, "FindAllOf=" .. #allHolders)
            for _, h in ipairs(allHolders) do
                local ownerOk, owner = pcall(function() return h:GetOwner() end)
                if ownerOk and owner and owner == pawn then
                    holder = h
                    holderMethod = "FindAllOf"
                    break
                end
            end
        else
            table.insert(debug, "FindAllOf=nil")
        end
    end)

    -- Method B: direct property access on pawn (fallback)
    if not holder then
        for _, prop in ipairs({"OtomoHolderComponent", "OtomoHolder"}) do
            local ok, val = pcall(function() return pawn[prop] end)
            if ok and val then
                holder = val
                holderMethod = "prop:" .. prop
                break
            end
        end
    end

    if not holder then
        table.insert(debug, "holder=NONE")
        Log(string.format("get_player_pals[%s]: %s", targetName, table.concat(debug, " | ")))
        return true, json.encode({ pals = {}, total = 0, note = "Cannot find OtomoHolder (" .. table.concat(debug, ", ") .. ")" })
    end
    table.insert(debug, "holder=" .. holderMethod)

    -- Step 3: get count
    local count = 0
    local countOk, countErr = pcall(function() count = holder:GetOtomoCount() end)
    if not countOk then
        table.insert(debug, "GetOtomoCount=FAIL:" .. tostring(countErr))
    else
        table.insert(debug, "count=" .. tostring(count))
    end
    if count > 5 then count = 5 end

    -- Step 4: if count=0, brute-force try slots 0-4 (GetOtomoCount may have failed)
    local maxSlots = count > 0 and count or 5
    for i = 0, maxSlots - 1 do
        local palEntry = { index = i, source = "party" }
        local stepOk, stepErr = pcall(function()
            local slot = holder:GetOtomoIndividualCharacterSlot(i)
            if not slot then error("slot nil") end
            local handle = slot:GetHandle()
            if not handle then error("handle nil") end
            local param = handle:TryGetIndividualParameter()
            if not param then error("param nil") end

            local stats = ReadPalStats(param)
            for k, v in pairs(stats) do palEntry[k] = v end
        end)

        -- Only add if we got real data (has character_id), or if count > 0 (known slot)
        if palEntry.character_id then
            table.insert(pals, palEntry)
        elseif i < count then
            -- Known slot from count but failed to read
            table.insert(debug, "slot" .. i .. "=FAIL:" .. tostring(stepErr))
            table.insert(pals, palEntry)
        end
    end

    Log(string.format("get_player_pals[%s]: %d pals (%s)", targetName, #pals, table.concat(debug, " | ")))
    local result = { pals = pals, total = #pals }
    if #debug > 0 then result.debug = table.concat(debug, " | ") end
    return true, json.encode(result)
end

-- ── Command: get_all_pals (Party + Pal Box) ──────────────────────────────────
-- Returns ALL pals for a player — party pals + paginated pal box.
-- Params: target_player, page (0-based, default 0), page_size (default 30)

local function CmdGetAllPals(params)
    local targetName = params.target_player
    if not targetName or targetName == "" then
        return false, "Missing target_player"
    end
    local boxPage = tonumber(params.page) or 0
    local pageSize = tonumber(params.page_size) or 30
    if pageSize > 60 then pageSize = 60 end

    EnsureDiscovery()

    local player = FindPlayerByName(targetName)
    if not player then
        return false, "Player not found: " .. targetName
    end

    local ps = player.state
    local partyPals = {}
    local boxPals = {}
    local boxPageCount = 0
    local boxTotal = 0

    -- ── Party pals (same approach as CmdGetPlayerPals v2) ──
    local partyDebug = {}
    local pawn = nil
    if DiscoveryCache.ps_pawn then
        pawn = SafeRead(ps, DiscoveryCache.ps_pawn)
        if pawn then table.insert(partyDebug, "pawn=discovery:" .. DiscoveryCache.ps_pawn)
        else table.insert(partyDebug, "pawn=discovery-nil:" .. DiscoveryCache.ps_pawn) end
    else
        table.insert(partyDebug, "pawn=no-discovery")
    end
    if not pawn then
        for _, prop in ipairs({"PawnPrivate", "Pawn", "MyPawn", "PalPlayerCharacter"}) do
            local ok, val = pcall(function() return ps[prop] end)
            if ok and val then
                pawn = val
                table.insert(partyDebug, "pawn=prop:" .. prop)
                break
            end
        end
    end
    -- NOTE: ps:GetPawn() removed — causes native crash that pcall cannot catch
    if not pawn then
        table.insert(partyDebug, "pawn=NONE")
    end

    -- ── Method A: FindAllOf holders, match by owner name ──
    if pawn then
        local pawnName = nil
        pcall(function() pawnName = pawn:GetFullName() end)
        table.insert(partyDebug, "pawnName=" .. tostring(pawnName))

        local holder = nil
        pcall(function()
            local allHolders = FindAllOf("PalOtomoHolderComponentBase")
            if allHolders then
                table.insert(partyDebug, "FindAllOf=" .. #allHolders)
                for idx, h in ipairs(allHolders) do
                    local ownerOk, owner = pcall(function() return h:GetOwner() end)
                    if ownerOk and owner then
                        -- Try reference equality first
                        if owner == pawn then
                            holder = h
                            table.insert(partyDebug, "holder=ref-match#" .. idx)
                            break
                        end
                        -- Try name match as fallback
                        if pawnName then
                            local ownerName = nil
                            pcall(function() ownerName = owner:GetFullName() end)
                            if ownerName and ownerName == pawnName then
                                holder = h
                                table.insert(partyDebug, "holder=name-match#" .. idx)
                                break
                            end
                        end
                    end
                end
            else
                table.insert(partyDebug, "FindAllOf=nil")
            end
        end)

        -- Fallback: direct property on pawn
        if not holder then
            for _, prop in ipairs({"OtomoHolderComponent", "OtomoHolder", "PartyComponent"}) do
                local ok, val = pcall(function() return pawn[prop] end)
                if ok and val then
                    -- Validate the holder by trying a safe call
                    local countOk, countVal = pcall(function() return val:GetOtomoCount() end)
                    if countOk and type(countVal) == "number" then
                        holder = val
                        table.insert(partyDebug, "holder=prop:" .. prop .. "(count=" .. countVal .. ")")
                        break
                    else
                        table.insert(partyDebug, "holder=prop:" .. prop .. "(INVALID)")
                    end
                end
            end
        end

        if holder then
            local count = 0
            local countOk, countErr = pcall(function() count = holder:GetOtomoCount() end)
            if not countOk then
                table.insert(partyDebug, "count=ERR:" .. string.sub(tostring(countErr), 1, 80))
            else
                table.insert(partyDebug, "count=" .. tostring(count))
            end
            if count > 5 then count = 5 end
            local maxSlots = count > 0 and count or 5

            for i = 0, maxSlots - 1 do
                local palEntry = { index = i, source = "party" }
                local slotOk, slotErr = pcall(function()
                    local slot = holder:GetOtomoIndividualCharacterSlot(i)
                    if not slot then error("slot nil") end
                    local handle = slot:GetHandle()
                    if not handle then error("handle nil") end
                    local param = handle:TryGetIndividualParameter()
                    if not param then error("param nil") end

                    local stats = ReadPalStats(param)
                    for k, v in pairs(stats) do palEntry[k] = v end
                end)
                if palEntry.character_id then
                    table.insert(partyPals, palEntry)
                elseif i < count then
                    table.insert(partyDebug, "slot" .. i .. "=FAIL:" .. tostring(slotErr))
                end
            end
        else
            table.insert(partyDebug, "holder=NONE")
        end
    end

    -- ── Method B: OtomoData → CharacterContainerManager (alternative path) ──
    if #partyPals == 0 then
        local containerDebug = {}
        pcall(function()
            local otomoData = ps.OtomoData
            if not otomoData then table.insert(containerDebug, "OtomoData=nil"); return end
            table.insert(containerDebug, "OtomoData=ok")

            local containerId = otomoData.OtomoCharacterContainerId
            if not containerId then table.insert(containerDebug, "containerId=nil"); return end
            table.insert(containerDebug, "containerId=ok")

            -- Find the container manager
            local managers = FindAllOf("PalCharacterContainerManager")
            if not managers or #managers == 0 then
                table.insert(containerDebug, "ContainerMgr=nil")
                return
            end
            table.insert(containerDebug, "ContainerMgr=" .. #managers)

            local mgr = managers[1]
            -- Try GetContainer(containerId) UFunction
            local container = nil
            pcall(function() container = mgr:GetContainer(containerId) end)
            if not container then
                table.insert(containerDebug, "GetContainer=nil")
                return
            end
            table.insert(containerDebug, "container=ok")

            local num = 0
            pcall(function() num = container:Num() end)
            table.insert(containerDebug, "num=" .. tostring(num))

            for i = 0, num - 1 do
                local palEntry = { index = i, source = "party" }
                pcall(function()
                    local slot = container:Get(i)
                    if not slot then return end
                    local handle = slot:GetHandle()
                    if not handle then return end
                    local param = handle:TryGetIndividualParameter()
                    if not param then return end
                    local stats = ReadPalStats(param)
                    for k, v in pairs(stats) do palEntry[k] = v end
                end)
                if palEntry.character_id then
                    table.insert(partyPals, palEntry)
                end
            end
            table.insert(containerDebug, "pals=" .. #partyPals)
        end)
        if #containerDebug > 0 then
            table.insert(partyDebug, "MethodB:" .. table.concat(containerDebug, "|"))
        end
    end

    Log(string.format("get_all_pals[%s] party: %s", targetName, table.concat(partyDebug, " | ")))

    -- ── Pal Box pals ──
    local storage = nil
    -- Use GetPalStorage() method (CXXHeaderDump-verified on APalPlayerState)
    pcall(function() storage = ps:GetPalStorage() end)
    if not storage then
        for _, prop in ipairs({"PalStorage", "PalStorageData", "OtomoPalStorage"}) do
            local ok, val = pcall(function() return ps[prop] end)
            if ok and val then storage = val; break end
        end
    end

    if storage then
        pcall(function() boxPageCount = storage:GetPageNum() end)
        Log(string.format("get_all_pals: PalStorage found, %d pages", boxPageCount))

        -- Count total pals across all pages (scan page headers)
        -- Each page has up to 30 slots (standard Palworld pal box page size)
        local slotsPerPage = 30

        -- Read requested page
        if boxPage < boxPageCount then
            local startSlot = 0
            local endSlot = slotsPerPage - 1

            for slotIdx = startSlot, endSlot do
                local palEntry = { source = "box", box_page = boxPage, slot_index = slotIdx }
                local hasData = false
                pcall(function()
                    local slot = storage:GetSlot(boxPage, slotIdx)
                    if not slot then return end
                    local handle = slot:GetHandle()
                    if not handle then return end
                    local param = handle:TryGetIndividualParameter()
                    if not param then return end

                    local stats = ReadPalStats(param)
                    for k, v in pairs(stats) do palEntry[k] = v end
                    hasData = true
                end)
                if hasData then
                    table.insert(boxPals, palEntry)
                    boxTotal = boxTotal + 1
                end
            end
        end
    else
        Log("get_all_pals: PalStorage not found on PlayerState")
    end

    -- Log passives/waza debug from first box pal (for diagnostics)
    if #boxPals > 0 and boxPals[1]._passiveDbg then
        Log(string.format("get_all_pals: passives_dbg=%s | waza_dbg=%s",
            tostring(boxPals[1]._passiveDbg), tostring(boxPals[1]._wazaDbg)))
    end

    Log(string.format("get_all_pals[%s]: %d party, %d box (page %d/%d)",
        targetName, #partyPals, #boxPals, boxPage, boxPageCount))

    return true, json.encode({
        party = partyPals,
        box = boxPals,
        box_pages = boxPageCount,
        box_page = boxPage,
        box_count = #boxPals,
        party_debug = table.concat(partyDebug, " | "),
    })
end

-- ── Command: get_player_inventory (v2 — CXXHeaderDump-verified) ─────────────
-- Chain: PlayerState → InventoryData → InventoryMultiHelper → Containers[]
--        → each UPalItemContainer → Num()/Get(i) → UPalItemSlot
--        → slot.ItemId.StaticId + slot.StackCount

local function CmdGetPlayerInventory(params)
    -- NOTE: Inventory reading disabled — nested struct access (slot.ItemId.StaticId)
    -- causes native C++ crash that pcall cannot catch. Return empty for now.
    local targetName = params.target_player or "?"
    Log(string.format("get_player_inventory[%s]: disabled (native crash safety)", targetName))
    return true, json.encode({ items = {}, debug = "disabled-crash-safety" })
end

-- ── Command: edit_pal (Phase C + Pal Manager) ───────────────────────────────
-- Edits a specific pal by source (party/box) + index. Re-navigates the
-- appropriate chain, then dispatches the requested action on the param.

local function CmdEditPal(params)
    local targetName = params.target_player
    local action = params.action
    local source = params.source or "party"

    if not targetName or targetName == "" then return false, "Missing target_player" end
    if not action or action == "" then return false, "Missing action" end

    EnsureDiscovery()

    local player = FindPlayerByName(targetName)
    if not player then return false, "Player not found: " .. targetName end

    -- Navigate to the pal's IndividualParameter based on source
    local param = nil
    local navErr = nil

    if source == "box" then
        local boxPage = tonumber(params.box_page) or 0
        local slotIdx = tonumber(params.slot_index) or 0
        param, _, _, navErr = GetBoxPalParam(player.state, boxPage, slotIdx)
        if not param then
            return false, navErr or string.format("Cannot access box pal (page=%d, slot=%d)", boxPage, slotIdx)
        end
    else
        local palIndex = tonumber(params.pal_index) or 0
        param, _, _, navErr = GetPalParam(player.state, palIndex)
        if not param then
            return false, navErr or "Cannot access party pal at index " .. palIndex
        end
    end

    local resultMsg = "Unknown action: " .. action
    local ok = false

    -- ── Stable actions (direct on IndividualParameter) ──────────────────

    if action == "rename" then
        local nickname = params.nickname
        if not nickname then return false, "Missing nickname" end
        local callOk, callErr = pcall(function()
            ExecuteInGameThread(function()
                -- Try setting NickName property directly (FString)
                param.NickName = nickname
            end)
        end)
        if callOk then ok = true; resultMsg = "Renamed pal to: " .. nickname
        else resultMsg = "Rename failed: " .. tostring(callErr) end

    elseif action == "heal" then
        local callOk, callErr = pcall(function()
            ExecuteInGameThread(function()
                param:FullRecoveryHP()
            end)
        end)
        if callOk then ok = true; resultMsg = "Pal healed (full HP recovery)"
        else resultMsg = "FullRecoveryHP failed: " .. tostring(callErr) end

    elseif action == "set_physical_health" then
        local value = tonumber(params.value) or 0
        local callOk, callErr = pcall(function()
            ExecuteInGameThread(function()
                param:SetPhysicalHealth(value)
            end)
        end)
        if callOk then ok = true; resultMsg = "Physical health set to " .. value
        else resultMsg = "SetPhysicalHealth failed: " .. tostring(callErr) end

    elseif action == "add_passive" then
        local skillId = params.skill_id
        local overrideId = params.override_id or ""
        if not skillId or skillId == "" then return false, "Missing skill_id" end
        local callOk, callErr = pcall(function()
            ExecuteInGameThread(function()
                param:AddPassiveSkill(FName(skillId), FName(overrideId ~= "" and overrideId or "None"))
            end)
        end)
        if callOk then ok = true; resultMsg = "Added passive: " .. skillId
        else resultMsg = "AddPassiveSkill failed: " .. tostring(callErr) end

    elseif action == "remove_passive" then
        local skillId = params.skill_id
        if not skillId or skillId == "" then return false, "Missing skill_id" end
        local callOk, callErr = pcall(function()
            ExecuteInGameThread(function()
                param:RemovePassiveSkill(FName(skillId))
            end)
        end)
        if callOk then ok = true; resultMsg = "Removed passive: " .. skillId
        else resultMsg = "RemovePassiveSkill failed: " .. tostring(callErr) end

    elseif action == "add_move" then
        local wazaId = params.waza_id
        if not wazaId or wazaId == "" then return false, "Missing waza_id" end
        local callOk, callErr = pcall(function()
            ExecuteInGameThread(function()
                param:AddEquipWaza(FName(wazaId))
            end)
        end)
        if callOk then ok = true; resultMsg = "Added move: " .. wazaId
        else resultMsg = "AddEquipWaza failed: " .. tostring(callErr) end

    elseif action == "remove_move" then
        local wazaId = params.waza_id
        if not wazaId or wazaId == "" then return false, "Missing waza_id" end
        local callOk, callErr = pcall(function()
            ExecuteInGameThread(function()
                param:RemoveEquipWaza(FName(wazaId))
            end)
        end)
        if callOk then ok = true; resultMsg = "Removed move: " .. wazaId
        else resultMsg = "RemoveEquipWaza failed: " .. tostring(callErr) end

    elseif action == "clear_moves" then
        local callOk, callErr = pcall(function()
            ExecuteInGameThread(function()
                param:ClearEquipWaza()
            end)
        end)
        if callOk then ok = true; resultMsg = "All moves cleared"
        else resultMsg = "ClearEquipWaza failed: " .. tostring(callErr) end

    elseif action == "set_status_point" then
        local statName = params.stat_name
        local value = tonumber(params.value) or 0
        if not statName or statName == "" then return false, "Missing stat_name" end
        local callOk, callErr = pcall(function()
            ExecuteInGameThread(function()
                param:SetStatusPoint(FName(statName), value)
            end)
        end)
        if callOk then ok = true; resultMsg = "Set " .. statName .. " points to " .. value
        else resultMsg = "SetStatusPoint failed: " .. tostring(callErr) end

    elseif action == "add_friendship" then
        local value = tonumber(params.value) or 0
        local callOk, callErr = pcall(function()
            ExecuteInGameThread(function()
                param:AddFriendShip(value)
            end)
        end)
        if callOk then ok = true; resultMsg = "Added " .. value .. " friendship"
        else resultMsg = "AddFriendShip failed: " .. tostring(callErr) end

    -- ── Experimental actions (via CheatManager — may only target first pal) ──

    elseif action == "set_rank" then
        local value = tonumber(params.value) or 0
        local cm = GetCheatManager()
        if not cm then return false, "No PalCheatManager found" end
        local callOk, callErr = pcall(function()
            ExecuteInGameThread(function() cm:SetOtomoPalRank(value) end)
        end)
        if callOk then ok = true; resultMsg = "Set condense rank to " .. value .. " (experimental)"
        else resultMsg = "SetOtomoPalRank failed: " .. tostring(callErr) end

    elseif action == "set_hp_rank" then
        local value = tonumber(params.value) or 0
        local cm = GetCheatManager()
        if not cm then return false, "No PalCheatManager found" end
        local callOk, callErr = pcall(function()
            ExecuteInGameThread(function() cm:SetOtomoPalHPRank(value) end)
        end)
        if callOk then ok = true; resultMsg = "Set HP rank to " .. value .. " (experimental)"
        else resultMsg = "SetOtomoPalHPRank failed: " .. tostring(callErr) end

    elseif action == "set_atk_rank" then
        local value = tonumber(params.value) or 0
        local cm = GetCheatManager()
        if not cm then return false, "No PalCheatManager found" end
        local callOk, callErr = pcall(function()
            ExecuteInGameThread(function() cm:SetOtomoPalAttackRank(value) end)
        end)
        if callOk then ok = true; resultMsg = "Set ATK rank to " .. value .. " (experimental)"
        else resultMsg = "SetOtomoPalAttackRank failed: " .. tostring(callErr) end

    elseif action == "set_def_rank" then
        local value = tonumber(params.value) or 0
        local cm = GetCheatManager()
        if not cm then return false, "No PalCheatManager found" end
        local callOk, callErr = pcall(function()
            ExecuteInGameThread(function() cm:SetOtomoPalDefenceRank(value) end)
        end)
        if callOk then ok = true; resultMsg = "Set DEF rank to " .. value .. " (experimental)"
        else resultMsg = "SetOtomoPalDefenceRank failed: " .. tostring(callErr) end

    elseif action == "set_ws_rank" then
        local value = tonumber(params.value) or 0
        local cm = GetCheatManager()
        if not cm then return false, "No PalCheatManager found" end
        local callOk, callErr = pcall(function()
            ExecuteInGameThread(function() cm:SetOtomoPalWorkSpeedRank(value) end)
        end)
        if callOk then ok = true; resultMsg = "Set WorkSpeed rank to " .. value .. " (experimental)"
        else resultMsg = "SetOtomoPalWorkSpeedRank failed: " .. tostring(callErr) end

    elseif action == "set_level" then
        local value = tonumber(params.value) or 1
        if value < 1 then value = 1 end
        if value > 65 then value = 65 end
        local callOk, callErr = pcall(function()
            ExecuteInGameThread(function()
                param:SetOverrideLevel(value)
            end)
        end)
        if callOk then ok = true; resultMsg = "Set level to " .. value
        else resultMsg = "SetOverrideLevel failed: " .. tostring(callErr) end

    elseif action == "set_work_suitability" then
        -- Set work suitability add rank for a specific work type
        -- params: work_type (EPalWorkSuitability enum int 0-12), value (int rank)
        local workType = tonumber(params.work_type)
        local value = tonumber(params.value) or 0
        if not workType then return false, "Missing work_type (0-12)" end
        local callOk, callErr = pcall(function()
            ExecuteInGameThread(function()
                param:SetWorkSuitabilityAddRank(workType, value)
            end)
        end)
        local workNames = {"Kindling","Watering","Planting","Electricity","Handiwork",
            "Gathering","Lumbering","Mining","Oil","Medicine","Cooling","Transporting","Farming"}
        local wName = workNames[(workType or 0) + 1] or tostring(workType)
        if callOk then ok = true; resultMsg = "Set " .. wName .. " suitability rank to " .. value
        else resultMsg = "SetWorkSuitabilityAddRank failed: " .. tostring(callErr) end
    end

    local palIdStr = source == "box"
        and string.format("box p%d s%d", tonumber(params.box_page) or 0, tonumber(params.slot_index) or 0)
        or string.format("party %d", tonumber(params.pal_index) or 0)
    Log(string.format("edit_pal[%s][%s] %s: %s", targetName, palIdStr, action, resultMsg))
    return ok, resultMsg
end

-- ── Command: edit_player_stats (Phase C) ─────────────────────────────────────
-- Edits player stats via PalCheatManager functions.

local function CmdEditPlayerStats(params)
    local action = params.action
    if not action or action == "" then return false, "Missing action" end

    local cm = GetCheatManager()
    if not cm then return false, "No PalCheatManager found" end

    local resultMsg = "Unknown action: " .. action
    local ok = false

    if action == "set_hp" then
        local value = tonumber(params.value) or 0
        local callOk, callErr = pcall(function()
            ExecuteInGameThread(function() cm:SetPlayerHP(value) end)
        end)
        if callOk then ok = true; resultMsg = "Set player HP to " .. value
        else resultMsg = "SetPlayerHP failed: " .. tostring(callErr) end

    elseif action == "set_sp" then
        local value = tonumber(params.value) or 0
        local callOk, callErr = pcall(function()
            ExecuteInGameThread(function() cm:SetPlayerSP(value) end)
        end)
        if callOk then ok = true; resultMsg = "Set player SP to " .. value
        else resultMsg = "SetPlayerSP failed: " .. tostring(callErr) end

    elseif action == "add_money" then
        local value = tonumber(params.value) or 0
        local callOk, callErr = pcall(function()
            ExecuteInGameThread(function() cm:AddMoney(value) end)
        end)
        if callOk then ok = true; resultMsg = "Added " .. value .. " gold"
        else resultMsg = "AddMoney failed: " .. tostring(callErr) end

    elseif action == "add_tech_points" then
        local value = tonumber(params.value) or 0
        local callOk, callErr = pcall(function()
            ExecuteInGameThread(function() cm:AddTechnologyPoints(value) end)
        end)
        if callOk then ok = true; resultMsg = "Added " .. value .. " technology points"
        else resultMsg = "AddTechnologyPoints failed: " .. tostring(callErr) end

    elseif action == "add_boss_tech" then
        local value = tonumber(params.value) or 0
        local callOk, callErr = pcall(function()
            ExecuteInGameThread(function() cm:AddBossTechnologyPoints(value) end)
        end)
        if callOk then ok = true; resultMsg = "Added " .. value .. " boss tech points"
        else resultMsg = "AddBossTechnologyPoints failed: " .. tostring(callErr) end

    elseif action == "full_power" then
        local callOk, callErr = pcall(function()
            ExecuteInGameThread(function() cm:FullPowerForPlayer() end)
        end)
        if callOk then ok = true; resultMsg = "Full power applied"
        else resultMsg = "FullPowerForPlayer failed: " .. tostring(callErr) end

    elseif action == "set_inventory_size" then
        local value = tonumber(params.value) or 0
        local callOk, callErr = pcall(function()
            ExecuteInGameThread(function() cm:SetInventorySize(value) end)
        end)
        if callOk then ok = true; resultMsg = "Set inventory size to " .. value
        else resultMsg = "SetInventorySize failed: " .. tostring(callErr) end
    end

    Log(string.format("edit_player_stats: %s → %s", action, resultMsg))
    return ok, resultMsg
end

-- ── Command dispatch ─────────────────────────────────────────────────────────

local CommandHandlers = {
    give_item        = CmdGiveItem,
    spawn_pal        = CmdSpawnPal,
    list_players     = function(params) return CmdListPlayers() end,
    echo             = CmdEcho,
    give_exp         = CmdGiveExp,
    fly_toggle       = CmdFlyToggle,
    goto_coords      = CmdGotoCoords,
    bring_player     = CmdBringPlayer,
    bring_all        = function(params) return CmdBringAll() end,
    unstuck          = function(params) return CmdUnstuck() end,
    set_time         = CmdSetTime,
    get_time         = function(params) return CmdGetTime() end,
    announce         = CmdAnnounce,
    slay_player      = CmdSlayPlayer,
    freeze_player    = CmdFreezePlayer,
    unfreeze_player  = CmdUnfreezePlayer,
    spectate         = function(params) return CmdSpectate() end,
    kick_player      = CmdKickPlayer,
    ban_player       = CmdBanPlayer,
    unban_player     = CmdUnbanPlayer,
    get_pos          = CmdGetPos,
    teleport_player      = CmdTeleportPlayer,
    send_player_to_player = CmdSendPlayerToPlayer,
    dump_properties       = CmdDumpProperties,
    probe_properties  = CmdProbeProperties,
    get_players_live  = function(params) return CmdGetPlayersLive() end,
    get_player_detail = CmdGetPlayerDetail,
    get_player_pals       = CmdGetPlayerPals,
    get_all_pals          = CmdGetAllPals,
    get_player_inventory  = CmdGetPlayerInventory,
    edit_pal              = CmdEditPal,
    edit_player_stats     = CmdEditPlayerStats,
    dump_functions    = CmdDumpFunctions,
    generate_sdk      = function(params) return CmdGenerateSDK(params) end,
    get_admin_location = function(params) return CmdGetAdminLocation() end,
}

local function ProcessCommand(cmdData)
    local id = cmdData.id or "unknown"
    local cmdType = cmdData.type
    local params = cmdData.params or {}

    Log(string.format("Command: %s (type=%s)", id, tostring(cmdType)))

    local handler = CommandHandlers[cmdType]
    if not handler then
        WriteResponse(id, false, "Unknown command type: " .. tostring(cmdType))
        return
    end

    local ok, successOrErr, message = pcall(handler, params)
    if ok then
        -- handler returned (success, message)
        WriteResponse(id, successOrErr, message)
    else
        -- handler threw an error
        WriteResponse(id, false, "Error: " .. tostring(successOrErr))
    end
end

-- ── Polling loop ───────────────────────────────────────────────────────────────

local function PollCommands()
    -- Check if command file exists and has content
    local content = ReadFile(CmdFile)
    if not content then return end

    -- Parse JSON
    local cmdData, pos, err = json.decode(content)
    if not cmdData then
        Log("ERROR parsing command JSON: " .. tostring(err))
        -- Clear the bad command file
        os.remove(CmdFile)
        return
    end

    -- Clear command file immediately to prevent re-processing
    os.remove(CmdFile)

    -- Process the command
    ProcessCommand(cmdData)
end

-- ── Register polling callback ──────────────────────────────────────────────────

-- Ensure the IPC directory exists (best effort)
os.execute('mkdir "' .. IpcDir .. '" 2>nul')

-- Clean up any stale files from previous session
os.remove(CmdFile)
os.remove(RspFile)
os.remove(CmdTmpFile)
os.remove(RspTmpFile)

-- Poll every 2000ms using LoopAsync (return false = keep looping)
-- IMPORTANT: IPC polling and auto-discovery run on SEPARATE timers so that a
-- slow or hanging discovery probe can never block command processing.
LoopAsync(2000, function()
    PollCommands()
    return false
end)

-- Auto-discovery: separate timer, retries every 30s after boot delay.
-- Returns true (stop) once discovery succeeds; returns false (continue) otherwise.
LoopAsync(5000, function()
    if DiscoveryCache.probed then return true end  -- done — stop this timer
    pcall(EnsureDiscovery)
    if DiscoveryCache.probed then return true end  -- succeeded — stop
    return false  -- keep retrying
end)

Log("IPC polling started (2s interval). Command file: " .. CmdFile)
Log("Mod initialisation complete.")
