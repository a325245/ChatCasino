local Crystal = {}

local MULT = {
  [1]  = {1.01, 1.02, 1.1, 1.2, 1.3, 1.44, 1.6, 1.8, 2.05, 2.4, 2.88, 3.6, 4.2, 6.4, 11.2},
  [2]  = {1.02, 1.18, 1.38, 1.63, 1.96, 2.4, 3.0, 3.85, 4.5, 6.4, 9.6, 14.0, 24.0, 40.0},
  [3]  = {1.1, 1.38, 1.76, 2.29, 3.05, 3.7, 5.3, 8.0, 9.6, 16.8, 22.0, 56.0, 65.0},
  [4]  = {1.2, 1.63, 2.29, 3.3, 4.4, 6.9, 8.6, 15.6, 20.0, 40.0, 73.0, 100.0},
  [5]  = {1.3, 1.96, 3.05, 4.4, 7.5, 10.4, 20.8, 31.0, 65.0, 88.0, 150.0},
  [6]  = {1.44, 2.4, 3.7, 6.9, 10.4, 22.8, 38.0, 81.0, 120.0, 250.0},
  [7]  = {1.6, 3.0, 5.3, 8.6, 20.8, 38.0, 85.0, 140.0, 357.0},
  [8]  = {1.8, 3.85, 8.0, 15.6, 31.0, 81.0, 140.0, 400.0},
  [9]  = {2.05, 4.5, 9.6, 20.0, 65.0, 120.0, 357.0},
  [10] = {2.4, 6.4, 16.8, 40.0, 88.0, 250.0},
  [11] = {2.88, 9.6, 22.0, 72.0, 150.0},
  [12] = {3.6, 14.0, 56.0, 100.0},
  [13] = {4.2, 24.0, 65.0},
  [14] = {6.4, 40.0},
  [15] = {11.2},
}

local DEFAULT_STRINGS = {
  initial_info = "Use /casino crystalstart",
  round_complete = "Round complete",
  turn_choose_info = "<name>, time to choose your bomb (1-15)",
  turn_ready_roll_info = "<name> ready to roll /dice <run>",
  turn_wait_roll_info = "<name> waiting for /dice <run> result",
  turn_decision_info = "<name> choose: take the gil or continue",
  roll_timed_out_info = "<name> roll timed out; roll again",
  roll_timed_out_announce = "<name> roll timed out (no valid /dice <run> result parsed). Roll again.",
  roll_result_announce = "<name> run <run>: rolled <rolled> vs bomb <bomb>",
  survive_continue_info = "<name> survived. Take x<mult> or continue to run <next_run> for x<next_mult>",
  survive_continue_announce = "<name> survives run <run> at x<mult>. Take the gil or continue to run <next_run> for x<next_mult>",
  survive_take_info = "<name> survived. Take x<mult> (no further run)",
  survive_take_announce = "<name> survives run <run> at x<mult>. Take the gil now (no further run available)",
  bust_announce = "<name> busted and lost <wager>",
  no_eligible_players = "No eligible players",
  crystal_started = "Crystal started",
  bomb_out_of_range = "Bomb must be 1-15",
  bomb_chosen_info = "<name> chose bomb <bomb>",
  bomb_chosen_announce = "<name> chooses bomb <bomb>",
  choose_bomb_first = "Choose bomb first",
  not_ready_roll = "Not ready to roll",
  roll_already_pending = "Roll already pending",
  unable_send_dice = "Unable to send /dice",
  unable_send_dice_announce = "Unable to send /dice command",
  no_pending_take = "No pending take decision",
  take_win_announce = "<name> takes x<mult> = <payout>",
  no_pending_continue = "No pending continue decision",
  no_further_run = "No further run; take win",
  no_multiplier_next_run = "No multiplier for next run; take win",
  continuing_run_info = "<name> continuing to run <next_run>",
  cfg_title = "Crystal Config",
  cfg_roll_delay_label = "Roll chat delay (ms)##cr_delay",
  cfg_roll_timeout_label = "Roll timeout (ms)##cr_timeout",
  cfg_commands_header = "Commands:",
  cfg_cmd_start = "/casino crystalstart",
  cfg_cmd_pick = "/casino crystalpick <1-15>",
  cfg_cmd_roll = "/casino crystalroll",
  cfg_cmd_take = "/casino crystaltake",
  cfg_cmd_continue = "/casino crystalcontinue",
  cfg_flow = "Flow: pick bomb -> roll at 16,15,14... -> take or continue",
  cfg_strings_header = "Crystal Strings",
  ui_title = "Crystal",
  ui_btn_start = "Start Crystal Round##cr_start",
  ui_roll_default = "Roll##cr_roll",
  ui_roll_for = "Roll for <name> (d<run>)##cr_roll",
  ui_btn_take = "Take Win##cr_take",
  ui_btn_continue = "Continue##cr_continue",
  ui_pick_input_label = "Bomb Pick##cr_pick",
  ui_pick_for = "Choose Bomb For <name>##cr_pick_btn",
  ui_pick_default = "Choose Bomb##cr_pick_btn",
  ui_status_line = "Status: <phase> | <info>",
  ui_current_player = "Current Player: <name>",
  ui_bomb_run_wager = "Bomb: <bomb> | Run: <run> | Wager: <wager>",
  ui_last_roll_mult = "Last roll: <rolled> | Last mult: x<mult>",
  ui_no_active_player = "No active player",
  ui_multiplier_preview = "Multiplier Preview",
  ui_multiplier_hint = "(highlighted cells indicate player positions)",
  ui_bomb_r_header = "Bomb\\R",
}

local STRING_EDIT_ORDER = {
  "initial_info",
  "round_complete",
  "turn_choose_info",
  "turn_ready_roll_info",
  "turn_wait_roll_info",
  "turn_decision_info",
  "roll_timed_out_info",
  "roll_timed_out_announce",
  "roll_result_announce",
  "survive_continue_info",
  "survive_continue_announce",
  "survive_take_info",
  "survive_take_announce",
  "bust_announce",
  "no_eligible_players",
  "crystal_started",
  "bomb_out_of_range",
  "bomb_chosen_info",
  "bomb_chosen_announce",
  "choose_bomb_first",
  "not_ready_roll",
  "roll_already_pending",
  "unable_send_dice",
  "unable_send_dice_announce",
  "no_pending_take",
  "take_win_announce",
  "no_pending_continue",
  "no_further_run",
  "no_multiplier_next_run",
  "continuing_run_info",
  "cfg_title",
  "cfg_roll_delay_label",
  "cfg_roll_timeout_label",
  "cfg_commands_header",
  "cfg_cmd_start",
  "cfg_cmd_pick",
  "cfg_cmd_roll",
  "cfg_cmd_take",
  "cfg_cmd_continue",
  "cfg_flow",
  "cfg_strings_header",
  "ui_title",
  "ui_btn_start",
  "ui_roll_default",
  "ui_roll_for",
  "ui_btn_take",
  "ui_btn_continue",
  "ui_pick_input_label",
  "ui_pick_for",
  "ui_pick_default",
  "ui_status_line",
  "ui_current_player",
  "ui_bomb_run_wager",
  "ui_last_roll_mult",
  "ui_no_active_player",
  "ui_multiplier_preview",
  "ui_multiplier_hint",
  "ui_bomb_r_header",
}

Crystal.state = Crystal.state or {
  phase = "idle",
  info = DEFAULT_STRINGS.initial_info,
  players = {},
  order = {},
  active_index = 1,
  pick_input = 6,
  roll_delay_ms = 2000,
  roll_timeout_ms = 15000,
  roll_request = nil,
  suggest_take_until = 0,
  suggest_continue_until = 0,
  outbox = {},
  next_announce_at = 0,
  strings = {},
}

if Crystal.state.suggest_take_until == nil then Crystal.state.suggest_take_until = 0 end
if Crystal.state.suggest_continue_until == nil then Crystal.state.suggest_continue_until = 0 end
if Crystal.state.outbox == nil then Crystal.state.outbox = {} end
if Crystal.state.next_announce_at == nil then Crystal.state.next_announce_at = 0 end
if Crystal.state.strings == nil then Crystal.state.strings = {} end
if Crystal.state.config_status == nil then Crystal.state.config_status = "Crystal config not loaded yet." end
for key, value in pairs(DEFAULT_STRINGS) do
  if Crystal.state.strings[key] == nil then
    Crystal.state.strings[key] = value
  end

-- Function: config_file_name
-- Purpose: Handles config file name logic for the Crystal script.
local function config_file_name()
  return "Crystal.config.json"
end

-- Function: config_export_blob
-- Purpose: Handles config export blob logic for the Crystal script.
local function config_export_blob()
  local s = "return {roll_delay_ms=" .. tostring(math.floor(tonumber(Crystal.state.roll_delay_ms) or 2000))
    .. ",roll_timeout_ms=" .. tostring(math.floor(tonumber(Crystal.state.roll_timeout_ms) or 15000))
    .. ",show_help=" .. tostring(Crystal.state.show_help ~= false)
    .. ",strings={"
  for k, v in pairs(Crystal.state.strings or {}) do
    s = s .. tostring(k) .. "=[=[" .. tostring(v or "") .. "]=],"
  end
  s = s .. "}}"
  return s
end

-- Function: apply_config_table
-- Purpose: Handles apply config table logic for the Crystal script.
local function apply_config_table(data)
  if type(data) ~= "table" then return false end
  if data.roll_delay_ms ~= nil then Crystal.state.roll_delay_ms = tonumber(data.roll_delay_ms) or Crystal.state.roll_delay_ms end
  if data.roll_timeout_ms ~= nil then Crystal.state.roll_timeout_ms = tonumber(data.roll_timeout_ms) or Crystal.state.roll_timeout_ms end
  if data.show_help ~= nil then Crystal.state.show_help = (data.show_help == true) end
  if type(data.strings) == "table" then
    for k, v in pairs(data.strings) do
      Crystal.state.strings[tostring(k)] = tostring(v or "")
    end
  end
  return true
end

-- Function: save_config_file
-- Purpose: Saves config file data from runtime state.
local function save_config_file()
  if script_write_text == nil then
    Crystal.state.config_status = "Crystal config save failed (host file API unavailable)."
    if chat_send ~= nil then chat_send("echo", Crystal.state.config_status) end
    return false
  end
  local ok = script_write_text(config_file_name(), config_export_blob()) == true
  if ok then
    Crystal.state.config_status = "Crystal config saved."
  else
    Crystal.state.config_status = "Crystal config save failed."
  end
  if chat_send ~= nil then chat_send("echo", Crystal.state.config_status) end
  return ok
end

-- Function: load_config_file
-- Purpose: Loads config file data into runtime state.
local function load_config_file()
  if script_read_text == nil then
    Crystal.state.config_status = "Crystal config load skipped (host file API unavailable)."
    return false
  end
  local raw = script_read_text(config_file_name())
  if raw == nil or raw == "" then
    Crystal.state.config_status = "Crystal config file not found."
    return false
  end
  local loader = loadstring or load
  local fn, err = loader(tostring(raw))
  if not fn then
    Crystal.state.config_status = "Crystal config syntax error: " .. tostring(err)
    return false
  end
  local ok, data = pcall(fn)
  if not ok then
    Crystal.state.config_status = "Crystal config runtime error: " .. tostring(data)
    return false
  end
  if not apply_config_table(data) then
    Crystal.state.config_status = "Crystal config invalid payload."
    return false
  end
  Crystal.state.config_status = "Crystal config loaded."
  return true
end

if Crystal.state._config_loaded ~= true then
  load_config_file()
  Crystal.state._config_loaded = true
end
end

-- Function: txt
-- Purpose: Handles txt logic for the Crystal script.
local function txt(key, vars)
  local s = tostring((Crystal.state.strings and Crystal.state.strings[key]) or DEFAULT_STRINGS[key] or key)
  local values = {
    ["<name>"] = tostring((vars and vars.name) or ""),
    ["<run>"] = tostring((vars and vars.run) or ""),
    ["<bomb>"] = tostring((vars and vars.bomb) or ""),
    ["<mult>"] = tostring((vars and vars.mult) or ""),
    ["<next_run>"] = tostring((vars and vars.next_run) or ""),
    ["<next_mult>"] = tostring((vars and vars.next_mult) or ""),
    ["<rolled>"] = tostring((vars and vars.rolled) or ""),
    ["<wager>"] = tostring((vars and vars.wager) or ""),
    ["<payout>"] = tostring((vars and vars.payout) or ""),
    ["<phase>"] = tostring((vars and vars.phase) or ""),
    ["<info>"] = tostring((vars and vars.info) or ""),
  }
  for token, value in pairs(values) do
    s = string.gsub(s, token, value)
  end
  return s
end

-- Function: now_ms
-- Purpose: Handles now ms logic for the Crystal script.
local function now_ms()
  return (time_ms ~= nil) and tonumber(time_ms()) or 0
end

-- Function: output_channel_name
-- Purpose: Resolves the chat channel that this script should use for output.
local function output_channel_name()
  if default_chat_channel ~= nil then
    local ch = default_chat_channel()
    if ch == "echo" or ch == "say" or ch == "party" then return ch end
  end
  return "party"
end

-- Function: announce
-- Purpose: Builds and sends a formatted chat announcement for the current event.
local function announce(msg)
  local text = tostring(msg or "")
  if text == "" then return end
  table.insert(Crystal.state.outbox, text)
end

-- Function: process_announce_queue
-- Purpose: Processes announce queue updates for the current game state.
local function process_announce_queue()
  if Crystal.state.outbox == nil or #Crystal.state.outbox == 0 then return end
  local now = now_ms()
  if now < (tonumber(Crystal.state.next_announce_at) or 0) then return end

  local msg = table.remove(Crystal.state.outbox, 1)
  if chat_send ~= nil then chat_send(output_channel_name(), msg) else dealer_party(msg) end
  local gap = tonumber(Crystal.state.roll_delay_ms) or 2000
  if gap < 0 then gap = 0 end
  Crystal.state.next_announce_at = now + gap
end

-- Function: send_public_dice
-- Purpose: Handles send public dice logic for the Crystal script.
local function send_public_dice(upper)
  local u = tonumber(upper) or 16
  if u < 2 then u = 2 end
  local ch = output_channel_name()
  if dice_command ~= nil then
    return dice_command(ch, u) == true
  end
  if chat_command ~= nil then
    return chat_command("/dice " .. tostring(ch) .. " " .. tostring(u)) == true
  end
  return false
end

-- Function: get_multiplier
-- Purpose: Handles get multiplier logic for the Crystal script.
local function get_multiplier(bomb, run)
  local row = MULT[tonumber(bomb) or -1]
  if row == nil then return nil end
  local idx = 17 - (tonumber(run) or 0)
  return row[idx]
end

-- Function: current_name
-- Purpose: Handles current name logic for the Crystal script.
local function current_name()
  local i = tonumber(Crystal.state.active_index) or 1
  return Crystal.state.order[i] or ""
end

-- Function: current_player
-- Purpose: Handles current player logic for the Crystal script.
local function current_player()
  local n = current_name()
  if n == "" then return nil, "" end
  return Crystal.state.players[n], n
end

local set_turn_info

-- Function: clear_suggestions
-- Purpose: Handles clear suggestions logic for the Crystal script.
local function clear_suggestions()
  Crystal.state.suggest_take_until = 0
  Crystal.state.suggest_continue_until = 0
end

-- Function: advance_player
-- Purpose: Handles advance player logic for the Crystal script.
local function advance_player()
  Crystal.state.active_index = (tonumber(Crystal.state.active_index) or 1) + 1
  clear_suggestions()
  set_turn_info()
end

set_turn_info = function()
  local p, name = current_player()
  if p == nil then
    Crystal.state.phase = "done"
    Crystal.state.info = txt("round_complete")
    return
  end

  if p.status == "choose" then
    Crystal.state.phase = "player_turn"
    Crystal.state.info = txt("turn_choose_info", { name = name })
    announce(txt("turn_choose_info", { name = name }))
  elseif p.status == "ready_roll" then
    Crystal.state.phase = "player_turn"
    Crystal.state.info = txt("turn_ready_roll_info", { name = name, run = p.run })
  elseif p.status == "waiting_roll" then
    Crystal.state.phase = "player_turn"
    Crystal.state.info = txt("turn_wait_roll_info", { name = name, run = p.run })
  elseif p.status == "decision" then
    Crystal.state.phase = "player_turn"
    Crystal.state.info = txt("turn_decision_info", { name = name })
  end
end

-- Function: process_chat_hints
-- Purpose: Processes chat hints updates for the current game state.
local function process_chat_hints()
  if Crystal.state.roll_request ~= nil then return end
  if chat_poll == nil then return end

  local p, active_name = current_player()
  if p == nil or p.status ~= "decision" then return end

  local now = now_ms()
  for _ = 1, 24 do
    local packet = chat_poll()
    if packet == nil or packet == "" then break end

    local sender, _, _, message = string.match(packet, "^([^|]*)|([^|]*)|([^|]*)|(.*)$")
    if sender ~= nil and message ~= nil and string.lower(tostring(sender)) == string.lower(tostring(active_name)) then
      local msg = string.lower(tostring(message))
      if string.find(msg, "continue", 1, true) or string.find(msg, "keep going", 1, true) or string.find(msg, "keepgoing", 1, true) then
        Crystal.state.suggest_continue_until = now + 6000
      end
      if string.find(msg, "take", 1, true) or string.find(msg, "stop", 1, true) or string.find(msg, "cash", 1, true) then
        Crystal.state.suggest_take_until = now + 6000
      end
    end
  end
end

-- Function: process_pending_roll
-- Purpose: Processes pending roll updates for the current game state.
local function process_pending_roll()
  local req = Crystal.state.roll_request
  if req == nil then return end

  local p = Crystal.state.players[req.player]
  if p == nil then
    Crystal.state.roll_request = nil
    return
  end

  local now = now_ms()
  if now >= (tonumber(req.timeout_at) or 0) then
    Crystal.state.roll_request = nil
    p.status = "ready_roll"
    Crystal.state.info = txt("roll_timed_out_info", { name = req.player })
    announce(txt("roll_timed_out_announce", { name = req.player, run = req.run }))
    return
  end

  if now < (tonumber(req.parse_after) or 0) then return end
  if chat_poll == nil or dice_roll_value == nil or dice_roll_upper == nil then return end

  for _ = 1, 32 do
    local packet = chat_poll()
    if packet == nil or packet == "" then break end

    local _, _, _, message = string.match(packet, "^([^|]*)|([^|]*)|([^|]*)|(.*)$")
    if message ~= nil then
      local rolled = tonumber(dice_roll_value(message) or 0) or 0
      local parsed_upper = tonumber(dice_roll_upper(message) or 0) or 0
      if parsed_upper == tonumber(req.run) and rolled >= 1 and rolled <= parsed_upper then
        Crystal.state.roll_request = nil
        p.last_roll = rolled
        announce(txt("roll_result_announce", { name = req.player, run = req.run, rolled = rolled, bomb = p.bomb }))

        if rolled > p.bomb then
          local mult = get_multiplier(p.bomb, req.run)
          local next_run = (tonumber(req.run) or 16) - 1
          local next_mult = get_multiplier(p.bomb, next_run)
          p.last_mult = mult
          p.status = "decision"
          if next_mult ~= nil and next_run >= 2 then
            Crystal.state.info = txt("survive_continue_info", { name = req.player, mult = tostring(mult or "?"), next_run = next_run, next_mult = next_mult })
            announce(txt("survive_continue_announce", { name = req.player, run = req.run, mult = tostring(mult or "?"), next_run = next_run, next_mult = next_mult }))
          else
            Crystal.state.info = txt("survive_take_info", { name = req.player, mult = tostring(mult or "?") })
            announce(txt("survive_take_announce", { name = req.player, run = req.run, mult = tostring(mult or "?") }))
          end
        else
          p.status = "bust"
          if dealer_add_bank ~= nil then dealer_add_bank(req.player, -math.floor(tonumber(p.wager) or 0)) end
          announce(txt("bust_announce", { name = req.player, wager = math.floor(tonumber(p.wager) or 0) }))
          advance_player()
        end
        return
      end
    end
  end
end

-- Function: Crystal.start_round
-- Purpose: Starts round for the current game flow.
function Crystal.start_round()
  Crystal.state.players = {}
  Crystal.state.order = {}
  Crystal.state.active_index = 1
  clear_suggestions()

  local count = (dealer_player_count ~= nil) and tonumber(dealer_player_count()) or 0
  for i = 1, count do
    local name = dealer_player_name(i)
    if name ~= nil and name ~= "" and (dealer_is_eligible == nil or dealer_is_eligible(name)) then
      local wager = (dealer_get_wager ~= nil) and (tonumber(dealer_get_wager(name)) or 0) or 0
      if wager <= 0 then wager = 10 end
      Crystal.state.players[name] = {
        wager = wager,
        bomb = nil,
        run = 16,
        last_roll = nil,
        last_mult = nil,
        status = "choose",
      }
      table.insert(Crystal.state.order, name)
    end
  end

  if #Crystal.state.order == 0 then
    Crystal.state.phase = "idle"
    Crystal.state.info = txt("no_eligible_players")
    return false
  end

  Crystal.state.phase = "player_turn"
  Crystal.state.info = txt("crystal_started")
  set_turn_info()
  return true
end

-- Function: Crystal.choose_bomb
-- Purpose: Handles choose bomb logic for the Crystal script.
function Crystal.choose_bomb(bomb)
  local p, name = current_player()
  if p == nil then return false end
  local b = tonumber(bomb)
  if b == nil or b < 1 or b > 15 then
    Crystal.state.info = txt("bomb_out_of_range")
    return false
  end

  p.bomb = math.floor(b)
  p.run = 16
  p.last_roll = nil
  p.last_mult = nil
  p.status = "ready_roll"
  Crystal.state.info = txt("bomb_chosen_info", { name = name, bomb = p.bomb })
  announce(txt("bomb_chosen_announce", { name = name, bomb = p.bomb }))
  return true
end

-- Function: Crystal.roll_once
-- Purpose: Handles roll once logic for the Crystal script.
function Crystal.roll_once()
  local p, name = current_player()
  if p == nil then return false end
  if p.bomb == nil then
    Crystal.state.info = txt("choose_bomb_first")
    return false
  end
  if p.status ~= "ready_roll" then
    Crystal.state.info = txt("not_ready_roll")
    return false
  end
  if Crystal.state.roll_request ~= nil then
    Crystal.state.info = txt("roll_already_pending")
    return false
  end

  local upper = tonumber(p.run) or 16
  if upper < 2 then upper = 2 end
  if not send_public_dice(upper) then
    Crystal.state.info = txt("unable_send_dice")
    announce(txt("unable_send_dice_announce"))
    return false
  end

  p.status = "waiting_roll"
  Crystal.state.roll_request = {
    player = name,
    run = upper,
    parse_after = now_ms() + (tonumber(Crystal.state.roll_delay_ms) or 2000),
    timeout_at = now_ms() + (tonumber(Crystal.state.roll_timeout_ms) or 15000),
  }
  Crystal.state.info = txt("turn_wait_roll_info", { name = name, run = upper })
  return true
end

-- Function: Crystal.take_win
-- Purpose: Handles take win logic for the Crystal script.
function Crystal.take_win()
  local p, name = current_player()
  if p == nil then return false end
  if p.status ~= "decision" then
    Crystal.state.info = txt("no_pending_take")
    return false
  end

  local mult = tonumber(p.last_mult) or 0
  local wager = math.floor(tonumber(p.wager) or 0)
  local payout = math.floor(wager * mult)
  if dealer_add_bank ~= nil then dealer_add_bank(name, payout) end

  announce(txt("take_win_announce", { name = name, mult = mult, payout = payout }))
  p.status = "cashed"
  clear_suggestions()
  advance_player()
  return true
end

-- Function: Crystal.continue_run
-- Purpose: Handles continue run logic for the Crystal script.
function Crystal.continue_run()
  local p, name = current_player()
  if p == nil then return false end
  if p.status ~= "decision" then
    Crystal.state.info = txt("no_pending_continue")
    return false
  end

  local next_run = (tonumber(p.run) or 16) - 1
  if next_run < 2 then
    Crystal.state.info = txt("no_further_run")
    return false
  end

  if get_multiplier(p.bomb, next_run) == nil then
    Crystal.state.info = txt("no_multiplier_next_run")
    return false
  end

  p.run = next_run
  p.status = "ready_roll"
  Crystal.state.info = txt("continuing_run_info", { name = name, next_run = next_run })
  clear_suggestions()
  return Crystal.roll_once()
end

-- Function: on_command
-- Purpose: Routes script commands and executes command-specific game actions.
function on_command(cmd, ...)
  local c = string.lower(tostring(cmd or ""))
  local a1 = tostring(select(1, ...) or "")

  if c == "crystalstart" then
    Crystal.start_round()
    return "ok"
  end

  if c == "crystalpick" then
    Crystal.choose_bomb(a1)
    return "ok"
  end

  if c == "crystalroll" then
    Crystal.roll_once()
    return "ok"
  end

  if c == "crystaltake" then
    Crystal.take_win()
    return "ok"
  end

  if c == "crystalcontinue" then
    Crystal.continue_run()
    return "ok"
  end

  if c == "crystalstatus" then
    local p, name = current_player()
    if p == nil then return "done" end
    return string.format("%s bomb=%s run=%s wager=%s status=%s", name, tostring(p.bomb), tostring(p.run), tostring(p.wager), tostring(p.status))
  end

  return "unknown"
end

-- Function: draw_config_ui
-- Purpose: Renders the configuration panel where the dealer edits script settings.
function draw_config_ui()
  ui_text_colored(txt("cfg_title"), 0.8, 0.95, 0.8, 1.0)
  ui_separator()
  ui_text("Config status: " .. tostring(Crystal.state.config_status or ""))
  Crystal.state.roll_delay_ms = math.max(0, ui_input_int(txt("cfg_roll_delay_label"), tonumber(Crystal.state.roll_delay_ms) or 2000))
  Crystal.state.roll_timeout_ms = math.max(1000, ui_input_int(txt("cfg_roll_timeout_label"), tonumber(Crystal.state.roll_timeout_ms) or 15000))
  ui_separator()
  ui_text(txt("cfg_commands_header"))
  ui_text(txt("cfg_cmd_start"))
  ui_text(txt("cfg_cmd_pick"))
  ui_text(txt("cfg_cmd_roll"))
  ui_text(txt("cfg_cmd_take"))
  ui_text(txt("cfg_cmd_continue"))
  ui_text(txt("cfg_flow"))

  ui_separator()
  ui_text_colored(txt("cfg_strings_header"), 0.9, 0.95, 1.0, 1.0)
  if ui_input_text ~= nil then
    for i = 1, #STRING_EDIT_ORDER do
      local key = STRING_EDIT_ORDER[i]
      local current = tostring((Crystal.state.strings and Crystal.state.strings[key]) or DEFAULT_STRINGS[key] or "")
      Crystal.state.strings[key] = ui_input_text(key .. "##cr_str_" .. key, current, 2048)
    end
  else
    ui_text("ui_input_text host function unavailable")
  end

  ui_separator()
  if ui_button("Save Config##cr_cfg_save") then
    save_config_file()
  end
  ui_same_line()
  if ui_button("Load Config##cr_cfg_load") then
    load_config_file()
  end
end

-- Function: draw_ui
-- Purpose: Renders the main game UI and runs the per-frame update flow.
function draw_ui()
  process_pending_roll()
  process_chat_hints()
  process_announce_queue()

  ui_text_colored(txt("ui_title"), 0.7, 0.95, 1.0, 1.0)
  ui_separator()

  if ui_button(txt("ui_btn_start")) then on_command("crystalstart") end
  ui_same_line()
  local p_for_roll, n_for_roll = current_player()
  local roll_label = txt("ui_roll_default")
  if p_for_roll ~= nil and p_for_roll.status == "ready_roll" then
    roll_label = txt("ui_roll_for", { name = n_for_roll, run = p_for_roll.run or 16 })
  end
  if ui_button(roll_label) then on_command("crystalroll") end
  ui_same_line()
  local now = now_ms()
  local take_hot = now <= (tonumber(Crystal.state.suggest_take_until) or 0)
  local continue_hot = now <= (tonumber(Crystal.state.suggest_continue_until) or 0)
  if take_hot and ui_button_colored ~= nil then
    if ui_button_colored(txt("ui_btn_take"), 0.2, 0.55, 0.2, 1.0) then on_command("crystaltake") end
  else
    if ui_button(txt("ui_btn_take")) then on_command("crystaltake") end
  end
  ui_same_line()
  if continue_hot and ui_button_colored ~= nil then
    if ui_button_colored(txt("ui_btn_continue"), 0.2, 0.4, 0.75, 1.0) then on_command("crystalcontinue") end
  else
    if ui_button(txt("ui_btn_continue")) then on_command("crystalcontinue") end
  end

  Crystal.state.pick_input = math.max(1, math.min(15, ui_input_int(txt("ui_pick_input_label"), tonumber(Crystal.state.pick_input) or 6)))
  local pick_name = current_name()
  local pick_label = (pick_name ~= "") and txt("ui_pick_for", { name = pick_name }) or txt("ui_pick_default")
  if ui_button(pick_label) then
    on_command("crystalpick", tostring(Crystal.state.pick_input))
  end

  ui_separator()
  ui_text(txt("ui_status_line", { phase = Crystal.state.phase, info = Crystal.state.info }))

  local p, name = current_player()
  if p ~= nil then
    ui_text(txt("ui_current_player", { name = name }))
    ui_text(txt("ui_bomb_run_wager", { bomb = tostring(p.bomb or "(none)"), run = tostring(p.run or "-"), wager = tostring(p.wager or 0) }))
    ui_text(txt("ui_last_roll_mult", { rolled = tostring(p.last_roll or "-"), mult = tostring(p.last_mult or "-") }))
  else
    ui_text(txt("ui_no_active_player"))
  end

  ui_separator()
  ui_text_colored(txt("ui_multiplier_preview"), 0.9, 0.95, 1.0, 1.0)
  ui_text(txt("ui_multiplier_hint"))

  local occupied = {}
  local active_name = current_name()
  for n, pl in pairs(Crystal.state.players) do
    if pl.bomb ~= nil and pl.run ~= nil and pl.status ~= "cashed" and pl.status ~= "bust" then
      local key = tostring(pl.bomb) .. ":" .. tostring(pl.run)
      if n == active_name then
        occupied[key] = "active"
      else
        occupied[key] = "other"
      end
    end
  end

  ui_text(txt("ui_bomb_r_header"))
  ui_same_line()
  for run = 16, 2, -1 do
    ui_button_colored_sized(tostring(run) .. "##cr_hdr_" .. tostring(run), 44, 0, 0.2, 0.35, 0.55, 1.0)
    if run > 2 then ui_same_line() end
  end

  for bomb = 1, 15 do
    ui_button_colored_sized(tostring(bomb) .. "##cr_bomb_lbl_" .. tostring(bomb), 64, 0, 0.45, 0.12, 0.12, 1.0)
    ui_same_line()

    for run = 16, 2, -1 do
      local m = get_multiplier(bomb, run)
      local text = (m ~= nil) and tostring(m) or "-"
      local key = tostring(bomb) .. ":" .. tostring(run)
      local marker = occupied[key]
      local r, g, b, a = 0.15, 0.15, 0.18, 1.0
      if marker == "active" then
        r, g, b, a = 0.95, 0.75, 0.2, 1.0
      elseif marker == "other" then
        r, g, b, a = 0.15, 0.65, 0.25, 1.0
      elseif m ~= nil then
        r, g, b, a = 0.2, 0.2, 0.25, 1.0
      end
      ui_button_colored_sized(text .. "##cr_cell_" .. tostring(bomb) .. "_" .. tostring(run), 44, 0, r, g, b, a)
      if run > 2 then ui_same_line() end
    end
  end

  ui_separator()
  Crystal.state.show_help = Crystal.state.show_help ~= false
  if ui_collapsing_header ~= nil then
    Crystal.state.show_help = ui_collapsing_header("Crystal Help##cr_help")
  end
  if Crystal.state.show_help == true then
    ui_text_colored("Commands", 0.9, 0.95, 1.0, 1.0)
    ui_text("/casino crystalstart")
    ui_text("/casino crystalpick <1-15>")
    ui_text("/casino crystalroll")
    ui_text("/casino crystaltake")
    ui_text("/casino crystalcontinue")
    ui_separator()
    ui_text_colored("Flow", 0.9, 0.95, 1.0, 1.0)
    ui_text("Pick bomb -> roll run 16 downward -> survive to choose Take/Continue.")
    ui_text("Busting loses wager; taking win pays wager x multiplier.")
  end
end

return Crystal
