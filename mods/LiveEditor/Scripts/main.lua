--[[
    LiveEditor — UE4SS Lua Mod for Palworld
    File-based IPC: reads commands.json, executes, writes responses.json
    Polls every 2 seconds via LoopAsync.
]]

local ModName = "LiveEditor"
local ModVersion = "2.0.0"

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

-- ── Chat command dispatch (triggers AdminCommands mod) ───────────────────────
-- AdminCommands hooks PalPlayerState:EnterChat_Receive and processes messages
-- starting with "!". We simulate an admin chat message to trigger those commands.

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

    -- Construct FPalChatMessage with admin credentials
    local chatMsg = {
        Category = 1,                                                -- EPalChatCategory::Global
        Sender = "Admin",
        SenderPlayerUId = { A = AdminUidA, B = 0, C = 0, D = 0 },
        Message = message,
        ReceiverPlayerUIds = {},
        MessageId = FName("None"),
        MessageArgKeys = {},
        MessageArgValues = {}
    }

    local ok, err = pcall(function()
        ExecuteInGameThread(function()
            targetPS:EnterChat_Receive(chatMsg)
        end)
    end)

    if ok then
        return true, string.format("Dispatched: %s", message)
    else
        return false, string.format("Dispatch failed: %s", tostring(err))
    end
end

-- ── Command: give_item ─────────────────────────────────────────────────────────
-- Dispatches !give / !giveme via AdminCommands mod chat hook.

local function CmdGiveItem(params)
    local target = params.target_player
    local itemId = params.item_id
    local qty = params.quantity or 1

    if not itemId then
        return false, "Missing item_id"
    end

    -- Build AdminCommands chat command
    -- !giveme <ItemID>:<Qty>   — give to admin (self)
    -- !give <Player> <ItemID>:<Qty> — give to another player
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

    if not palId then
        return false, "Missing pal_id"
    end

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

-- ── Command: give_exp ────────────────────────────────────────────────────────

local function CmdGiveExp(params)
    local target = params.target_player
    local amount = params.amount

    if not amount then
        return false, "Missing amount"
    end

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
    local chatCmd = string.format("!goto %s,%s,%s", tostring(x), tostring(y), tostring(z))
    return DispatchChatCommand(chatCmd)
end

-- ── Command: bring_player ────────────────────────────────────────────────────

local function CmdBringPlayer(params)
    local target = params.target_player
    if not target or target == "" then
        return false, "Missing target_player"
    end
    local chatCmd = string.format("!bring %s", target)
    return DispatchChatCommand(chatCmd)
end

-- ── Command: bring_all ───────────────────────────────────────────────────────

local function CmdBringAll()
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

    -- Step 1: Admin goto coords
    local gotoCmd = string.format("!goto %s,%s,%s", tostring(x), tostring(y), tostring(z))
    local ok1, msg1 = DispatchChatCommand(gotoCmd)
    if not ok1 then
        return false, "Goto failed: " .. tostring(msg1)
    end

    -- Step 2: Delayed bring (1s via LoopAsync, return true = stop)
    LoopAsync(1000, function()
        local bringCmd = string.format("!bring %s", target)
        DispatchChatCommand(bringCmd)
        Log(string.format("Teleport: brought %s to (%s,%s,%s)", target, tostring(x), tostring(y), tostring(z)))
        return true
    end)

    return true, string.format("Teleporting %s to (%s,%s,%s)...", target, tostring(x), tostring(y), tostring(z))
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
    teleport_player  = CmdTeleportPlayer,
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
LoopAsync(2000, function()
    PollCommands()
    return false
end)

Log("IPC polling started (2s interval). Command file: " .. CmdFile)
Log("Mod initialisation complete.")
