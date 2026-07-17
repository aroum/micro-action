local config = import("micro/config")
local shell = import("micro/shell")
local micro = import("micro")
local filepath = import("path/filepath")
local os = import("os")

local stateFile = config.ConfigDir .. "/action-state.json"
local runningOnSave = false

-- Pure Lua JSON Parser for parsing settings.json (since gopher-lua maps Go structures directly)
local function parseJson(str)
    local pos = 1
    local function skip_whitespace()
        pos = str:find("[^%s]", pos) or #str + 1
    end
    local function parse_value()
        skip_whitespace()
        local char = str:sub(pos, pos)
        if char == '"' then
            local end_pos = str:find('"', pos + 1)
            while end_pos and str:sub(end_pos - 1, end_pos - 1) == '\\' do
                end_pos = str:find('"', end_pos + 1)
            end
            if not end_pos then error("Unterminated string") end
            local s = str:sub(pos + 1, end_pos - 1)
            s = s:gsub('\\"', '"'):gsub('\\\\', '\\'):gsub('\\n', '\n'):gsub('\\t', '\t')
            pos = end_pos + 1
            return s
        elseif char == '{' then
            local obj = {}
            pos = pos + 1
            skip_whitespace()
            if str:sub(pos, pos) == '}' then
                pos = pos + 1
                return obj
            end
            while true do
                local key = parse_value()
                if type(key) ~= "string" then error("Key must be a string") end
                skip_whitespace()
                if str:sub(pos, pos) ~= ':' then error("Expected ':' at " .. pos) end
                pos = pos + 1
                local val = parse_value()
                obj[key] = val
                skip_whitespace()
                local next_char = str:sub(pos, pos)
                if next_char == '}' then
                    pos = pos + 1
                    return obj
                elseif next_char == ',' then
                    pos = pos + 1
                else
                    error("Expected ',' or '}' at " .. pos)
                end
            end
        elseif char == '[' then
            local arr = {}
            pos = pos + 1
            skip_whitespace()
            if str:sub(pos, pos) == ']' then
                pos = pos + 1
                return arr
            end
            while true do
                local val = parse_value()
                table.insert(arr, val)
                skip_whitespace()
                local next_char = str:sub(pos, pos)
                if next_char == ']' then
                    pos = pos + 1
                    return arr
                elseif next_char == ',' then
                    pos = pos + 1
                else
                    error("Expected ',' or ']' at " .. pos)
                end
            end
        elseif str:sub(pos, pos + 3) == "true" then
            pos = pos + 4
            return true
        elseif str:sub(pos, pos + 4) == "false" then
            pos = pos + 5
            return false
        elseif str:sub(pos, pos + 3) == "null" then
            pos = pos + 4
            return nil
        else
            local next_pos = str:find("[^%d%.%-eE%+]", pos) or #str + 1
            local num_str = str:sub(pos, next_pos - 1)
            local num = tonumber(num_str)
            if not num then error("Invalid value at " .. pos) end
            pos = next_pos
            return num
        end
    end
    
    local ok, val = pcall(parse_value)
    if ok then return val else return nil end
end

-- Simple custom JSON encoder/decoder for flat dictionary
local function parseSimpleJson(str)
    local tbl = {}
    if not str then return tbl end
    for k, v in string.gmatch(str, '"([^"]+)"%s*:%s*"([^"]+)"') do
        tbl[k] = v
    end
    return tbl
end

local function formatSimpleJson(tbl)
    local parts = {}
    for k, v in pairs(tbl) do
        table.insert(parts, string.format('  "%s": "%s"', k, v))
    end
    return "{\n" .. table.concat(parts, ",\n") .. "\n}"
end

function getActions(bp)
    local f = io.open(config.ConfigDir .. "/settings.json", "r")
    if not f then return {} end
    local content = f:read("*all")
    f:close()

    local settings = parseJson(content)
    if not settings then return {} end

    local filetype = bp.Buf:FileType()
    local absPath, _ = filepath.Abs(bp.Buf.Path)

    local actions = {}

    -- 1. Load filetype actions
    local allFiletypes = settings["action-filetypes"]
    if allFiletypes and allFiletypes[filetype] then
        for k, v in pairs(allFiletypes[filetype]) do
            actions[k] = v
        end
    end

    -- 2. Load file-specific actions (overrides or extensions)
    local allFiles = settings["action-files"]
    if allFiles then
        for pattern, spec in pairs(allFiles) do
            local matched = false
            if absPath == pattern then
                matched = true
            elseif string.find(absPath, pattern, 1, true) then
                matched = true
            else
                local ok, matchRes = pcall(filepath.Match, pattern, absPath)
                if ok and matchRes then
                    matched = true
                end
            end

            if matched then
                if spec.mode == "override" then
                    actions = {}
                end
                if spec.actions then
                    for k, v in pairs(spec.actions) do
                        actions[k] = v
                    end
                end
            end
        end
    end

    return actions
end

function getPlaceholders(bp)
    local absPath, _ = filepath.Abs(bp.Buf.Path)
    local dir = filepath.Dir(absPath)
    local base = filepath.Base(absPath)
    local stem = base:match("^(.*)%.[^%.]+$") or base
    return {
        file = absPath,
        stem = stem,
        dir = dir
    }
end

function applyPlaceholders(cmd, placeholders)
    local newCmd = cmd
    newCmd = string.gsub(newCmd, "{file}", function() return placeholders.file end)
    newCmd = string.gsub(newCmd, "{stem}", function() return placeholders.stem end)
    newCmd = string.gsub(newCmd, "{dir}", function() return placeholders.dir end)
    return newCmd
end

function loadState()
    local f = io.open(stateFile, "r")
    if not f then return {} end
    local content = f:read("*all")
    f:close()
    return parseSimpleJson(content)
end

function saveState(key, label)
    local state = loadState()
    state[key] = label
    local f = io.open(stateFile, "w")
    if f then
        f:write(formatSimpleJson(state))
        f:close()
    end
end

function runAction(bp, label, action)
    local actionCmd = ""
    local saveBeforeRun = true
    local reloadAfterRun = false
    local runInBuiltinTerm = false
    local runSilent = false

    if type(action) == "table" then
        actionCmd = action.cmd or ""
        if action.saveBeforeRun ~= nil then saveBeforeRun = action.saveBeforeRun end
        if action.reloadAfterRun ~= nil then reloadAfterRun = action.reloadAfterRun end
        if action.runInBuiltinTerm ~= nil then runInBuiltinTerm = action.runInBuiltinTerm end
        if action.runSilent ~= nil then runSilent = action.runSilent end
    elseif type(action) == "string" then
        actionCmd = action
    end

    if saveBeforeRun and not runningOnSave then
        bp:Save()
    end

    local placeholders = getPlaceholders(bp)
    local cmd = applyPlaceholders(actionCmd, placeholders)

    if not runSilent then
        if type(action) ~= "table" or action.runInBuiltinTerm == nil then
            local globalTerm = config.GetGlobalOption("actionRunInBuiltinTerm")
            if globalTerm ~= nil then
                runInBuiltinTerm = globalTerm
            end
        end
    end

    local isWindows = (package.config:sub(1,1) == "\\")

    if runSilent then
        micro.InfoBar():Message("Running " .. label .. " (silent)...")
        local shellCmd
        if isWindows then
            shellCmd = 'cmd /c "' .. cmd:gsub('"', '\\"') .. '"'
        else
            shellCmd = "bash -c '" .. cmd:gsub("'", "'\\''") .. "'"
        end
        local output, err = shell.RunCommand(shellCmd)
        if err ~= nil then
            micro.InfoBar():Error("Failed " .. label .. ": " .. (output or "") .. " (" .. tostring(err) .. ")")
        else
            micro.InfoBar():Message("Succeeded: " .. label)
        end
    elseif runInBuiltinTerm then
        micro.InfoBar():Message("Running " .. label .. " in terminal: " .. cmd)
        bp:HandleCommand("hsplit")
        if isWindows then
            local escapedCmd = cmd:gsub('"', '\\"')
            bp:HandleCommand('term cmd /c "' .. escapedCmd .. '"')
        else
            local escapedCmd = cmd:gsub("'", "'\\''")
            bp:HandleCommand("term bash -c '" .. escapedCmd .. "'")
        end
    else
        micro.InfoBar():Message("Running " .. label .. ": " .. cmd)
        shell.RunInteractiveShell(cmd, true, false)
    end

    if reloadAfterRun then
        bp.Buf:ReOpen()
    end
end

function actionPick(bp)
    local filetype = bp.Buf:FileType()
    local actions = getActions(bp)
    if not actions then
        micro.InfoBar():Message("No actions configured.")
        return
    end

    local labels = {}
    for label, _ in pairs(actions) do
        table.insert(labels, label)
    end
    table.sort(labels)

    if #labels == 0 then
        micro.InfoBar():Message("No actions defined.")
        return
    end

    local stay = config.GetGlobalOption("actionFzfStay")
    if stay == nil then stay = false end

    local fzfCmd = config.GetGlobalOption("fzfcmd") or "fzf"
    local tempPath = "/tmp/action_input"

    repeat
        local input = table.concat(labels, "\n")
        
        local f = io.open(tempPath, "w")
        if f then
            f:write(input)
            f:close()
        else
            micro.InfoBar():Message("Error: Could not write temporary file " .. tempPath)
            break
        end
        
        local runCmd = "sh -c '" .. fzfCmd .. " < " .. tempPath .. "'"
        local output, err = shell.RunInteractiveShell(runCmd, false, true)
        
        os.Remove(tempPath)

        if err ~= nil or not output or output == "" then
            break
        end

        local selectedLabel = string.gsub(output, "[\r\n]+$", "")
        if selectedLabel == "" then
            break
        end

        local action = actions[selectedLabel]
        if action then
            runAction(bp, selectedLabel, action)
            saveState(filetype, selectedLabel)
        else
            break
        end
    until not stay
end

function actionLast(bp, args)
    local filetype = bp.Buf:FileType()
    local actions = getActions(bp)
    if not actions then
        micro.InfoBar():Message("No action configurations found.")
        return
    end

    local labels = {}
    for label, _ in pairs(actions) do
        table.insert(labels, label)
    end
    table.sort(labels)

    if #labels == 0 then
        micro.InfoBar():Message("No actions defined.")
        return
    end

    local state = loadState()
    local lastLabel = state[filetype]

    local action = nil
    if lastLabel then
        action = actions[lastLabel]
    end

    if not action then
        lastLabel = labels[1]
        action = actions[lastLabel]
    end

    if action then
        micro.InfoBar():Message("Running last selected action: " .. lastLabel)
        runAction(bp, lastLabel, action)
    else
        micro.InfoBar():Message("Could not find any actions to run.")
    end
end

function actionRun(bp, args)
    if not args or #args == 0 then
        micro.InfoBar():Message("Usage: actionrun <action-name>")
        return
    end
    
    local actionName = args[1]
    local actions = getActions(bp)
    local action = actions[actionName]
    
    if action then
        runAction(bp, actionName, action)
    else
        micro.InfoBar():Message("Action '" .. actionName .. "' not found for this buffer.")
    end
end

function onSave(bp)
    if runningOnSave then return true end

    local actions = getActions(bp)
    if not actions then return true end

    runningOnSave = true
    for label, action in pairs(actions) do
        if type(action) == "table" and action.runOnSave == true then
            runAction(bp, label, action)
        end
    end
    runningOnSave = false
    
    return true
end

function init()
    config.MakeCommand("actionlast", actionLast, config.NoComplete)
    config.MakeCommand("actionpick", actionPick, config.NoComplete)
    config.MakeCommand("actionrun", actionRun, config.NoComplete)
end
