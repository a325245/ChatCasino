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

Crystal.state = Crystal.state or {
  phase = "idle",
  info = "Use /casino crystalstart",
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
}

if Crystal.state.suggest_take_until == nil then Crystal.state.suggest_take_until = 0 end
if Crystal.state.suggest_continue_until == nil then Crystal.state.suggest_continue_until = 0 end
if Crystal.state.outbox == nil then Crystal.state.outbox = {} end
if Crystal.state.next_announce_at == nil then Crystal.state.next_announce_at = 0 end

local function now_ms()
  return (time_ms ~= nil) and tonumber(time_ms()) or 0
end

local function output_channel_name()
  if default_chat_channel ~= nil then
    local ch = default_chat_channel()
    if ch == "echo" or ch == "say" or ch == "party" then return ch end
  end
  return "party"
end

local function announce(msg)
  local text = tostring(msg or "")
  if text == "" then return end
  table.insert(Crystal.state.outbox, text)
end

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

local function get_multiplier(bomb, run)
  local row = MULT[tonumber(bomb) or -1]
  if row == nil then return nil end
  local idx = 17 - (tonumber(run) or 0)
  return row[idx]
end

local function current_name()
  local i = tonumber(Crystal.state.active_index) or 1
  return Crystal.state.order[i] or ""
end

local function current_player()
  local n = current_name()
  if n == "" then return nil, "" end
  return Crystal.state.players[n], n
end

local set_turn_info

local function clear_suggestions()
  Crystal.state.suggest_take_until = 0
  Crystal.state.suggest_continue_until = 0
end

local function advance_player()
  Crystal.state.active_index = (tonumber(Crystal.state.active_index) or 1) + 1
  clear_suggestions()
  set_turn_info()
end

set_turn_info = function()
  local p, name = current_player()
  if p == nil then
    Crystal.state.phase = "done"
    Crystal.state.info = "Round complete"
    return
  end

  if p.status == "choose" then
    Crystal.state.phase = "player_turn"
    Crystal.state.info = name .. ", time to choose your bomb (1-15)"
    announce(name .. ", time to choose your bomb (1-15)")
  elseif p.status == "ready_roll" then
    Crystal.state.phase = "player_turn"
    Crystal.state.info = name .. " ready to roll /dice " .. tostring(p.run)
  elseif p.status == "waiting_roll" then
    Crystal.state.phase = "player_turn"
    Crystal.state.info = name .. " waiting for /dice " .. tostring(p.run) .. " result"
  elseif p.status == "decision" then
    Crystal.state.phase = "player_turn"
    Crystal.state.info = name .. " choose: take the gil or continue"
  end
end

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
    Crystal.state.info = req.player .. " roll timed out; roll again"
    announce(req.player .. " roll timed out (no valid /dice " .. tostring(req.run) .. " result parsed). Roll again.")
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
        announce(req.player .. " run " .. tostring(req.run) .. ": rolled " .. tostring(rolled) .. " vs bomb " .. tostring(p.bomb))

        if rolled > p.bomb then
          local mult = get_multiplier(p.bomb, req.run)
          local next_run = (tonumber(req.run) or 16) - 1
          local next_mult = get_multiplier(p.bomb, next_run)
          p.last_mult = mult
          p.status = "decision"
          if next_mult ~= nil and next_run >= 2 then
            Crystal.state.info = req.player .. " survived. Take x" .. tostring(mult or "?") .. " or continue to run " .. tostring(next_run) .. " for x" .. tostring(next_mult)
            announce(req.player .. " survives run " .. tostring(req.run) .. " at x" .. tostring(mult or "?") .. ". Take the gil or continue to run " .. tostring(next_run) .. " for x" .. tostring(next_mult))
          else
            Crystal.state.info = req.player .. " survived. Take x" .. tostring(mult or "?") .. " (no further run)"
            announce(req.player .. " survives run " .. tostring(req.run) .. " at x" .. tostring(mult or "?") .. ". Take the gil now (no further run available)")
          end
        else
          p.status = "bust"
          if dealer_add_bank ~= nil then dealer_add_bank(req.player, -math.floor(tonumber(p.wager) or 0)) end
          announce(req.player .. " busted and lost " .. tostring(math.floor(tonumber(p.wager) or 0)))
          advance_player()
        end
        return
      end
    end
  end
end

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
    Crystal.state.info = "No eligible players"
    return false
  end

  Crystal.state.phase = "player_turn"
  Crystal.state.info = "Crystal started"
  set_turn_info()
  return true
end

function Crystal.choose_bomb(bomb)
  local p, name = current_player()
  if p == nil then return false end
  local b = tonumber(bomb)
  if b == nil or b < 1 or b > 15 then
    Crystal.state.info = "Bomb must be 1-15"
    return false
  end

  p.bomb = math.floor(b)
  p.run = 16
  p.last_roll = nil
  p.last_mult = nil
  p.status = "ready_roll"
  Crystal.state.info = name .. " chose bomb " .. tostring(p.bomb)
  announce(name .. " chooses bomb " .. tostring(p.bomb))
  return true
end

function Crystal.roll_once()
  local p, name = current_player()
  if p == nil then return false end
  if p.bomb == nil then
    Crystal.state.info = "Choose bomb first"
    return false
  end
  if p.status ~= "ready_roll" then
    Crystal.state.info = "Not ready to roll"
    return false
  end
  if Crystal.state.roll_request ~= nil then
    Crystal.state.info = "Roll already pending"
    return false
  end

  local upper = tonumber(p.run) or 16
  if upper < 2 then upper = 2 end
  if not send_public_dice(upper) then
    Crystal.state.info = "Unable to send /dice"
    announce("Unable to send /dice command")
    return false
  end

  p.status = "waiting_roll"
  Crystal.state.roll_request = {
    player = name,
    run = upper,
    parse_after = now_ms() + (tonumber(Crystal.state.roll_delay_ms) or 2000),
    timeout_at = now_ms() + (tonumber(Crystal.state.roll_timeout_ms) or 15000),
  }
  Crystal.state.info = name .. " waiting for /dice " .. tostring(upper) .. " result"
  return true
end

function Crystal.take_win()
  local p, name = current_player()
  if p == nil then return false end
  if p.status ~= "decision" then
    Crystal.state.info = "No pending take decision"
    return false
  end

  local mult = tonumber(p.last_mult) or 0
  local wager = math.floor(tonumber(p.wager) or 0)
  local payout = math.floor(wager * mult)
  if dealer_add_bank ~= nil then dealer_add_bank(name, payout) end

  announce(name .. " takes x" .. tostring(mult) .. " = " .. tostring(payout))
  p.status = "cashed"
  clear_suggestions()
  advance_player()
  return true
end

function Crystal.continue_run()
  local p, name = current_player()
  if p == nil then return false end
  if p.status ~= "decision" then
    Crystal.state.info = "No pending continue decision"
    return false
  end

  local next_run = (tonumber(p.run) or 16) - 1
  if next_run < 2 then
    Crystal.state.info = "No further run; take win"
    return false
  end

  if get_multiplier(p.bomb, next_run) == nil then
    Crystal.state.info = "No multiplier for next run; take win"
    return false
  end

  p.run = next_run
  p.status = "ready_roll"
  Crystal.state.info = name .. " continuing to run " .. tostring(next_run)
  clear_suggestions()
  return Crystal.roll_once()
end

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

function draw_config_ui()
  ui_text_colored("Crystal Config", 0.8, 0.95, 0.8, 1.0)
  ui_separator()
  Crystal.state.roll_delay_ms = math.max(0, ui_input_int("Roll chat delay (ms)##cr_delay", tonumber(Crystal.state.roll_delay_ms) or 2000))
  Crystal.state.roll_timeout_ms = math.max(1000, ui_input_int("Roll timeout (ms)##cr_timeout", tonumber(Crystal.state.roll_timeout_ms) or 15000))
  ui_separator()
  ui_text("Commands:")
  ui_text("/casino crystalstart")
  ui_text("/casino crystalpick <1-15>")
  ui_text("/casino crystalroll")
  ui_text("/casino crystaltake")
  ui_text("/casino crystalcontinue")
  ui_text("Flow: pick bomb -> roll at 16,15,14... -> take or continue")
end

function draw_ui()
  process_pending_roll()
  process_chat_hints()
  process_announce_queue()

  ui_text_colored("Crystal", 0.7, 0.95, 1.0, 1.0)
  ui_separator()

  if ui_button("Start Crystal Round##cr_start") then on_command("crystalstart") end
  ui_same_line()
  local p_for_roll, n_for_roll = current_player()
  local roll_label = "Roll##cr_roll"
  if p_for_roll ~= nil and p_for_roll.status == "ready_roll" then
    roll_label = "Roll for " .. tostring(n_for_roll) .. " (d" .. tostring(p_for_roll.run or 16) .. ")##cr_roll"
  end
  if ui_button(roll_label) then on_command("crystalroll") end
  ui_same_line()
  local now = now_ms()
  local take_hot = now <= (tonumber(Crystal.state.suggest_take_until) or 0)
  local continue_hot = now <= (tonumber(Crystal.state.suggest_continue_until) or 0)
  if take_hot and ui_button_colored ~= nil then
    if ui_button_colored("Take Win##cr_take", 0.2, 0.55, 0.2, 1.0) then on_command("crystaltake") end
  else
    if ui_button("Take Win##cr_take") then on_command("crystaltake") end
  end
  ui_same_line()
  if continue_hot and ui_button_colored ~= nil then
    if ui_button_colored("Continue##cr_continue", 0.2, 0.4, 0.75, 1.0) then on_command("crystalcontinue") end
  else
    if ui_button("Continue##cr_continue") then on_command("crystalcontinue") end
  end

  Crystal.state.pick_input = math.max(1, math.min(15, ui_input_int("Bomb Pick##cr_pick", tonumber(Crystal.state.pick_input) or 6)))
  local pick_name = current_name()
  local pick_label = (pick_name ~= "") and ("Choose Bomb For " .. tostring(pick_name) .. "##cr_pick_btn") or "Choose Bomb##cr_pick_btn"
  if ui_button(pick_label) then
    on_command("crystalpick", tostring(Crystal.state.pick_input))
  end

  ui_separator()
  ui_text("Status: " .. tostring(Crystal.state.phase) .. " | " .. tostring(Crystal.state.info))

  local p, name = current_player()
  if p ~= nil then
    ui_text("Current Player: " .. tostring(name))
    ui_text("Bomb: " .. tostring(p.bomb or "(none)") .. " | Run: " .. tostring(p.run or "-") .. " | Wager: " .. tostring(p.wager or 0))
    ui_text("Last roll: " .. tostring(p.last_roll or "-") .. " | Last mult: x" .. tostring(p.last_mult or "-"))
  else
    ui_text("No active player")
  end

  ui_separator()
  ui_text_colored("Multiplier Preview", 0.9, 0.95, 1.0, 1.0)
  ui_text("(highlighted cells indicate player positions)")

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

  ui_text("Bomb\\Rn")
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
end

return Crystal
