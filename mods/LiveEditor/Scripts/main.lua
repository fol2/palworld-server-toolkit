--[[
    LiveEditor — UE4SS Lua Mod for Palworld
    File-based IPC: reads commands.json, executes, writes responses.json
    Polls every 2 seconds via LoopAsync.
]]

local ModName = "LiveEditor"
local ModVersion = "1.0.0"

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

-- ── Command dispatch ───────────────────────────────────────────────────────────

local CommandHandlers = {
    give_item    = CmdGiveItem,
    spawn_pal    = CmdSpawnPal,
    list_players = function(params) return CmdListPlayers() end,
    echo         = CmdEcho,
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
