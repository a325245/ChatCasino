if SLOTS == nil then
  SLOTS = {
    phase = "idle",
    info = "Waiting for players to spin.",
    
    queue = {},          
    active_spin = nil,
    last_spin = nil,
    last_grid = nil,
    pending_grid_lines = nil,
    pending_grid_index = 1,
    pending_grid_next_at = 0,
    pending_result = nil,
    stats_wagered = 0,
    stats_paid = 0,
    stats_spins = 0,
    ui_line_pick = {},

    -- The physical reel strip. 
    -- Wrapping around: Symbol before 1 is 10, symbol after 10 is 1.
    strip = {
      "[ 7 ]", -- 1
      "[  ]", -- 2
      "[  ]", -- 3
      "[ $ ]", -- 4
      "[ $ ]", -- 5
      "[ $ ]", -- 6
      "[ ♠ ]", -- 7
      "[ ♥ ]", -- 8
      "[ ♦ ]", -- 9
      "[ ♣ ]"  -- 10
    },

    config = {
      min_bet_per_line = 5,
      max_bet_per_line = 100,
      reel_stop_delay_ms = 400, 
      
      pay_777 = 250,     
      pay_bar = 35,      
      pay_cash = 8,      
      pay_3_suits = 25,  
      pay_any_two_7 = 2, 
    },

    chat_templates = {
      queued = "<player> queued for <lines> lines! (Total: <total_bet> chips)",
      turn_prompt = "<player>, you're up! Roll /dice party <roll> time(s).",
      roll_progress = "<player> rolled <roll> (<lines>/<total_bet>).",
      spin_start = "<player> rolls: <reason>. Here we go!",
      result_win = "<player> won <payout> chips on <lines_won> lines! (<reason>)",
      result_lose = "No hit this round for <player>. Try another spin!",
    }
  }
end


local function output_channel_name()
  if default_chat_channel ~= nil then
    local ch = default_chat_channel()
    if ch == "echo" or ch == "say" or ch == "party" then return ch end
  end
  return "party"
end

local function table_announce(msg)
  local text = msg or ""
  if text == "" then return end
  if chat_send ~= nil then chat_send(output_channel_name(), text) else dealer_party(text) end
end

local function announce(key, ctx)
  local template = SLOTS.chat_templates[key]
  if template == nil or template == "" then return end

  local msg = template
  local values = {
    ["<player>"] = tostring((ctx and ctx.player) or ""),
    ["<lines>"] = tostring((ctx and ctx.lines) or 0),
    ["<total_bet>"] = tostring((ctx and ctx.total_bet) or 0),
    ["<payout>"] = tostring((ctx and ctx.payout) or 0),
    ["<lines_won>"] = tostring((ctx and ctx.lines_won) or 0),
    ["<roll>"] = tostring((ctx and ctx.roll) or ""),
    ["<reason>"] = tostring((ctx and ctx.reason) or ""),
  }

  for token, value in pairs(values) do msg = string.gsub(msg, token, value) end
  table_announce(msg)
end

local function announce_grid(grid)
  if grid == nil then return end
  table_announce((grid.t1 or "[ - ]") .. " " .. (grid.t2 or "[ - ]") .. " " .. (grid.t3 or "[ - ]"))
  table_announce((grid.m1 or "[ - ]") .. " " .. (grid.m2 or "[ - ]") .. " " .. (grid.m3 or "[ - ]"))
  table_announce((grid.b1 or "[ - ]") .. " " .. (grid.b2 or "[ - ]") .. " " .. (grid.b3 or "[ - ]"))
end

local function queue_grid_announce(grid, result)
  if grid == nil then return end
  local now = (time_ms ~= nil) and tonumber(time_ms()) or 0
  SLOTS.pending_grid_lines = {
    (grid.t1 or "[ - ]") .. " " .. (grid.t2 or "[ - ]") .. " " .. (grid.t3 or "[ - ]"),
    (grid.m1 or "[ - ]") .. " " .. (grid.m2 or "[ - ]") .. " " .. (grid.m3 or "[ - ]"),
    (grid.b1 or "[ - ]") .. " " .. (grid.b2 or "[ - ]") .. " " .. (grid.b3 or "[ - ]")
  }
  SLOTS.pending_grid_index = 1
  SLOTS.pending_grid_next_at = now
  SLOTS.pending_result = result
end

local function process_pending_announcements()
  local lines = SLOTS.pending_grid_lines
  if lines == nil then return end

  local now = (time_ms ~= nil) and tonumber(time_ms()) or 0
  local next_at = tonumber(SLOTS.pending_grid_next_at) or 0
  if now < next_at then return end

  local idx = tonumber(SLOTS.pending_grid_index) or 1
  local line = lines[idx]
  if line ~= nil then
    table_announce(line)
    SLOTS.pending_grid_index = idx + 1
    SLOTS.pending_grid_next_at = now + 250
  end

  if (tonumber(SLOTS.pending_grid_index) or 1) > #lines then
    SLOTS.pending_grid_lines = nil
    SLOTS.pending_grid_index = 1
    SLOTS.pending_grid_next_at = 0

    local result = SLOTS.pending_result
    SLOTS.pending_result = nil
    if result ~= nil then
      if (tonumber(result.payout) or 0) > 0 then
        if dealer_add_bank ~= nil then dealer_add_bank(result.player, result.payout) end
        SLOTS.stats_paid = (tonumber(SLOTS.stats_paid) or 0) + (tonumber(result.payout) or 0)
        announce("result_win", {
          player = result.player,
          payout = result.payout,
          lines_won = result.lines_won,
          reason = result.reason
        })
      else
        announce("result_lose", { player = result.player })
      end
    end
  end
end

local function wrap(index)
  local val = index % 10
  if val == 0 then return 10 end
  return val
end

local function map_roll_to_reels(roll)
  local val = roll - 1 
  if val < 0 then val = 0 end
  if val > 999 then val = 999 end

  local r1_idx = math.floor(val / 100) + 1
  local r2_idx = math.floor((val % 100) / 10) + 1
  local r3_idx = (val % 10) + 1

  return r1_idx, r2_idx, r3_idx
end

local function eval_line(sym1, sym2, sym3, bet)
  local count_7 = 0
  if sym1 == "[ 7 ]" then count_7 = count_7 + 1 end
  if sym2 == "[ 7 ]" then count_7 = count_7 + 1 end
  if sym3 == "[ 7 ]" then count_7 = count_7 + 1 end

  local p777 = tonumber(SLOTS.config.pay_777) or 250
  local pbar = tonumber(SLOTS.config.pay_bar) or 35
  local pcash = tonumber(SLOTS.config.pay_cash) or 8
  local psuits = tonumber(SLOTS.config.pay_3_suits) or 25
  local ptwo7 = tonumber(SLOTS.config.pay_any_two_7) or 2

  if sym1 == "[ 7 ]" and sym2 == "[ 7 ]" and sym3 == "[ 7 ]" then return bet * p777, "7-7-7" end
  if sym1 == "[  ]" and sym2 == "[  ]" and sym3 == "[  ]" then return bet * pbar, "3 " end
  if sym1 == "[ $ ]" and sym2 == "[ $ ]" and sym3 == "[ $ ]" then return bet * pcash, "3 $" end
  if sym1 == sym2 and sym2 == sym3 and (sym1 == "[ ♠ ]" or sym1 == "[ ♥ ]" or sym1 == "[ ♦ ]" or sym1 == "[ ♣ ]") then return bet * psuits, "Suits" end
  if count_7 == 2 then return bet * ptwo7, "Two 7s" end

  return 0, ""
end


local function execute_spin(player_name, lines, bet_per_line, rolls)
  local now = (time_ms ~= nil) and tonumber(time_ms()) or 0
  local delay = tonumber(SLOTS.config.reel_stop_delay_ms) or 800

  local required_rolls = ((tonumber(lines) or 1) <= 1) and 1 or 3
  local safe_rolls = rolls or {}
  local row_indices = {}
  for i = 1, required_rolls do
    local rv = tonumber(safe_rolls[i]) or 1
    if rv == 0 then rv = 1000 end
    local a, b, c = map_roll_to_reels(rv)
    row_indices[i] = { a, b, c }
  end

  SLOTS.active_spin = {
    player = player_name,
    lines = tonumber(lines) or 1,
    bet_per_line = tonumber(bet_per_line) or 5,
    required_rolls = required_rolls,
    rolls = safe_rolls,
    rows = row_indices,

    stop_1 = now + delay,
    stop_2 = now + (delay * 2),
    stop_3 = now + (delay * 3),

    resolved = false
  }

  SLOTS.phase = "spinning"
  local finalRoll = tonumber(safe_rolls[#safe_rolls]) or 1
  SLOTS.info = player_name .. " finished rolling. Spinning now..."
end

local function process_active_spin()
  if SLOTS.phase ~= "spinning" then return end
  if SLOTS.active_spin == nil or SLOTS.active_spin.resolved then return end

  local now = (time_ms ~= nil) and tonumber(time_ms()) or 0
  local s = SLOTS.active_spin
  local final_stop = ((tonumber(s.required_rolls) or 1) <= 1) and s.stop_1 or s.stop_3
  if final_stop == nil then return end

  if now >= final_stop then
    s.resolved = true

    local function row_to_symbols(row)
      if row == nil then return "[ - ]", "[ - ]", "[ - ]" end
      return SLOTS.strip[row[1]], SLOTS.strip[row[2]], SLOTS.strip[row[3]]
    end

    local t1, t2, t3 = row_to_symbols(s.rows[1])
    local m1, m2, m3
    local b1, b2, b3

    if (tonumber(s.required_rolls) or 1) <= 1 then
      m1, m2, m3 = t1, t2, t3
      b1, b2, b3 = "[ - ]", "[ - ]", "[ - ]"
      t1, t2, t3 = "[ - ]", "[ - ]", "[ - ]"
    else
      m1, m2, m3 = row_to_symbols(s.rows[2])
      b1, b2, b3 = row_to_symbols(s.rows[3])
    end

    local grid = {
      t1 = t1, t2 = t2, t3 = t3,
      m1 = m1, m2 = m2, m3 = m3,
      b1 = b1, b2 = b2, b3 = b3
    }

    local total_payout = 0
    local lines_won = 0
    local reasons = {}

    local function check_line(sym1, sym2, sym3, line_name)
      local p, r = eval_line(sym1, sym2, sym3, s.bet_per_line)
      if p > 0 then
        total_payout = total_payout + p
        lines_won = lines_won + 1
        table.insert(reasons, line_name .. ": " .. r)
      end
    end

    if s.lines >= 1 then check_line(grid.m1, grid.m2, grid.m3, "Mid") end
    if s.lines >= 2 then check_line(grid.t1, grid.t2, grid.t3, "Top") end
    if s.lines >= 3 then check_line(grid.b1, grid.b2, grid.b3, "Bottom") end
    if s.lines >= 4 then check_line(grid.t1, grid.m2, grid.b3, "Diag1") end
    if s.lines >= 5 then check_line(grid.b1, grid.m2, grid.t3, "Diag2") end
    if s.lines >= 6 then check_line(grid.t1, grid.m1, grid.b1, "Col1") end
    if s.lines >= 7 then check_line(grid.t2, grid.m2, grid.b2, "Col2") end
    if s.lines >= 8 then check_line(grid.t3, grid.m3, grid.b3, "Col3") end

    queue_grid_announce(grid, {
      player = s.player,
      payout = total_payout,
      lines_won = lines_won,
      reason = table.concat(reasons, ", ")
    })

    SLOTS.last_spin = {
      player = s.player,
      lines = s.lines,
      rolls = s.rolls,
      payout = total_payout,
      lines_won = lines_won,
      reason = table.concat(reasons, ", "),
    }

    SLOTS.last_grid = {
      t = { grid.t1, grid.t2, grid.t3 },
      m = { grid.m1, grid.m2, grid.m3 },
      b = { grid.b1, grid.b2, grid.b3 }
    }

    SLOTS.active_spin = nil
    SLOTS.phase = "idle"
  end
end

local function process_queue()
  if SLOTS.phase == "idle" and SLOTS.pending_grid_lines == nil and #SLOTS.queue > 0 then
    SLOTS.active_spin = table.remove(SLOTS.queue, 1)
    SLOTS.phase = "waiting_roll"

    local safe_bet = tonumber(SLOTS.active_spin.bet_per_line) or 5
    local safe_lines = tonumber(SLOTS.active_spin.lines) or 1
    local total_cost = safe_bet * safe_lines

    if dealer_add_bank ~= nil then dealer_add_bank(SLOTS.active_spin.player, -total_cost) end
    SLOTS.stats_wagered = (tonumber(SLOTS.stats_wagered) or 0) + total_cost
    SLOTS.stats_spins = (tonumber(SLOTS.stats_spins) or 0) + 1

    local required_rolls = (safe_lines <= 1) and 1 or 3
    SLOTS.active_spin.required_rolls = required_rolls
    SLOTS.active_spin.rolls = {}

    announce("turn_prompt", { player = SLOTS.active_spin.player, roll = required_rolls })
    SLOTS.info = "Waiting for " .. SLOTS.active_spin.player .. " to roll /dice party (1/" .. tostring(required_rolls) .. ")."
  end
end

local function parse_roll_from_message(message)
  local msg = tostring(message or "")
  local lower = string.lower(msg)

  local rolled = (dice_roll_value ~= nil) and tonumber(dice_roll_value(msg)) or 0
  local upper = (dice_roll_upper ~= nil) and tonumber(dice_roll_upper(msg)) or 0
  if rolled >= 1 and (upper == 0 or upper >= 1) then
    return rolled
  end
  if rolled == 0 and upper >= 1 then
    return 1000
  end

  -- Fallback for raw FFXIV output like: "Random! (1-1000) 16"
  if string.find(lower, "random", 1, true) ~= nil then
     local last = nil
     for n in string.gmatch(msg, "(%d+)") do
       last = tonumber(n)
     end
    if last == 0 then
      return 1000
    end
    if (last or 0) >= 1 then
       return last
     end
   end

  return nil
end

local function message_is_from_expected_roller(name, message)
  if SLOTS.active_spin == nil then return false end

  local expected = string.lower(tostring(SLOTS.active_spin.player or ""))
  local speaker = string.lower(tostring(name or ""))

  if expected == "" then return true end
  if speaker == expected then return true end
  if speaker ~= "" and string.find(speaker, expected, 1, true) ~= nil then return true end

  -- Some dice result lines may come from system-format packets without a normal speaker name.
  if speaker == "" then
    local m = string.lower(tostring(message or ""))
    if string.find(m, "random", 1, true) ~= nil then
      return true
    end
  end

  return false
end

local function process_chat_inputs()
  for _ = 1, 15 do
    local packet = (chat_poll ~= nil) and chat_poll() or ""
    if packet == nil or packet == "" then break end

    local name, _, _, message = string.match(packet, "^([^|]*)|([^|]*)|([^|]*)|(.*)$")
    if name ~= nil and message ~= nil then

      if dealer_is_eligible == nil or dealer_is_eligible(name) then
        local m = string.lower(message)
        if string.find(m, "^spin") then
          local match_lines = string.match(m, "spin (%d+)")
          local lines = 1
          if match_lines ~= nil then lines = tonumber(match_lines) or 1 end
          if lines < 1 then lines = 1 end
          if lines > 8 then lines = 8 end

          local raw_wager = (dealer_get_wager ~= nil) and tonumber(dealer_get_wager(name)) or 0
          local min_bet = tonumber(SLOTS.config.min_bet_per_line) or 5
          local max_bet = tonumber(SLOTS.config.max_bet_per_line) or 100

          local wager_per_line = min_bet
          if raw_wager > 0 then wager_per_line = raw_wager end
          if wager_per_line < min_bet then wager_per_line = min_bet end
          if wager_per_line > max_bet then wager_per_line = max_bet end

          local total_cost = wager_per_line * lines
          local bank = (dealer_get_bank ~= nil) and (tonumber(dealer_get_bank(name)) or 0) or 0

          if bank >= total_cost then
            local already_queued = false
            for i = 1, #SLOTS.queue do if SLOTS.queue[i].player == name then already_queued = true end end
            if SLOTS.active_spin ~= nil and SLOTS.active_spin.player == name then already_queued = true end

            if not already_queued then
              table.insert(SLOTS.queue, { player = name, lines = lines, bet_per_line = wager_per_line })
              if SLOTS.phase ~= "idle" then announce("queued", { player = name, lines = lines, total_bet = total_cost }) end
            else
              if dealer_tell ~= nil then dealer_tell(name, "party", "You are already spinning or queued!") end
            end
          else
            if dealer_tell ~= nil then dealer_tell(name, "party", "Not enough chips! Costs " .. total_cost .. " for " .. lines .. " lines.") end
          end
        end
      end

      if SLOTS.phase == "waiting_roll" and message_is_from_expected_roller(name, message) then
        local roll = parse_roll_from_message(message)
        if roll ~= nil then
          local collected = SLOTS.active_spin.rolls or {}
          table.insert(collected, roll)
          SLOTS.active_spin.rolls = collected

          local needed = tonumber(SLOTS.active_spin.required_rolls) or 1
          
            if #collected >= needed then
             execute_spin(SLOTS.active_spin.player, SLOTS.active_spin.lines, SLOTS.active_spin.bet_per_line, collected)
            else
              SLOTS.info = "Waiting for " .. SLOTS.active_spin.player .. " to roll /dice party (" .. tostring(#collected + 1) .. "/" .. tostring(needed) .. ")."
            end
          end
        end

    end
  end
end


function draw_config_ui()
  ui_text_colored("3x3 Multi-Line Slots Config", 0.8, 0.95, 0.8, 1.0)
  ui_separator()
  
  local safe_min = tonumber(SLOTS.config.min_bet_per_line) or 5
  local safe_max = tonumber(SLOTS.config.max_bet_per_line) or 100
  local safe_delay = tonumber(SLOTS.config.reel_stop_delay_ms) or 800

  SLOTS.config.min_bet_per_line = math.max(1, ui_input_int("Min Bet (Per Line)", safe_min))
  SLOTS.config.max_bet_per_line = math.max(1, ui_input_int("Max Bet (Per Line)", safe_max))
  SLOTS.config.reel_stop_delay_ms = math.max(100, ui_input_int("Reel Stop Delay (ms)", safe_delay))
end

function draw_ui()
  process_chat_inputs()
  process_queue()
  process_active_spin()
  process_pending_announcements()

  ui_text_colored("ChatCasino: Multi-Line Slots", 0.9, 0.7, 1.0, 1.0)
  ui_separator()

  local wagered = tonumber(SLOTS.stats_wagered) or 0
  local paid = tonumber(SLOTS.stats_paid) or 0
  local spins = tonumber(SLOTS.stats_spins) or 0
  local rtp = (wagered > 0) and ((paid / wagered) * 100.0) or 0
  ui_text(string.format("RTP Tracker | Spins: %d | Wagered: %d | Paid: %d | RTP: %.2f%%", spins, wagered, paid, rtp))
  if ui_button("Reset RTP Stats") then
    SLOTS.stats_wagered = 0
    SLOTS.stats_paid = 0
    SLOTS.stats_spins = 0
  end
  ui_separator()
  
  -- INSTRUCTIONS BLOCK FOR DEALERS AND PLAYERS
  ui_text_colored("--- INSTRUCTIONS ---", 0.7, 1.0, 0.7, 1.0)
  ui_text("1) Set your bet amount in the dealer window.")
  ui_text("2) spin 1 = middle line only.")
  ui_text("3) spin 3 = all 3 horizontal lines (top/mid/bottom).")
  ui_text("4) spin 5 = all 3 horizontal + 2 diagonals.")
  ui_text("5) spin 8 = all 3 horizontal + diagonals + 3 vertical columns.")
  ui_text("6) Roll /dice party once for spin 1, or 3 times for spin 3/5/8.")
  ui_separator()

  ui_text("Status: " .. tostring(SLOTS.phase) .. " | " .. tostring(SLOTS.info))
  
  local active_lines = (SLOTS.active_spin ~= nil) and tonumber(SLOTS.active_spin.lines) or 0
  ui_text("Active Lines: " .. tostring(active_lines) .. " | Queue: " .. tostring(#SLOTS.queue))
  
  if SLOTS.last_spin ~= nil then
    local ls = SLOTS.last_spin
    local rtxt = ""
    if ls.rolls ~= nil then
      for i = 1, #ls.rolls do
        if i > 1 then rtxt = rtxt .. ", " end
        rtxt = rtxt .. tostring(ls.rolls[i])
      end
    end
    if rtxt == "" then rtxt = "(none)" end
    ui_text("Last spin: " .. tostring(ls.player) .. " | " .. tostring(ls.lines) .. " lines | rolls " .. rtxt .. " | payout " .. tostring(ls.payout or 0))
  end
  
  ui_separator()

  local grid = { t={"[ - ]","[ - ]","[ - ]"}, m={"[ - ]","[ - ]","[ - ]"}, b={"[ - ]","[ - ]","[ - ]"} }
  local now = (time_ms ~= nil) and tonumber(time_ms()) or 0

  if SLOTS.active_spin ~= nil then
    local s = SLOTS.active_spin
    local is_spin = (SLOTS.phase == "spinning")
    local required_rolls = tonumber(s.required_rolls) or 1

    local function apply_row(target, row)
      if row ~= nil then
        target[1] = SLOTS.strip[row[1]]
        target[2] = SLOTS.strip[row[2]]
        target[3] = SLOTS.strip[row[3]]
      end
    end

    if is_spin then
      if required_rolls == 1 then
        if now < s.stop_1 then
          local anim_idx = (math.floor(now / 50) % 10) + 1
          grid.m[1], grid.m[2], grid.m[3] = SLOTS.strip[anim_idx], SLOTS.strip[wrap(anim_idx+1)], SLOTS.strip[wrap(anim_idx+2)]
        else
          apply_row(grid.m, s.rows[1])
        end
      else
        if now < s.stop_1 then
          local anim_idx = (math.floor(now / 50) % 10) + 1
          grid.t[1], grid.t[2], grid.t[3] = SLOTS.strip[anim_idx], SLOTS.strip[wrap(anim_idx+1)], SLOTS.strip[wrap(anim_idx+2)]
        else
          apply_row(grid.t, s.rows[1])
        end

        if now < s.stop_2 then
          local anim_idx = (math.floor(now / 45) % 10) + 1
          grid.m[1], grid.m[2], grid.m[3] = SLOTS.strip[anim_idx], SLOTS.strip[wrap(anim_idx+1)], SLOTS.strip[wrap(anim_idx+2)]
        else
          apply_row(grid.m, s.rows[2])
        end

        if now < s.stop_3 then
          local anim_idx = (math.floor(now / 40) % 10) + 1
          grid.b[1], grid.b[2], grid.b[3] = SLOTS.strip[anim_idx], SLOTS.strip[wrap(anim_idx+1)], SLOTS.strip[wrap(anim_idx+2)]
        else
          apply_row(grid.b, s.rows[3])
        end
      end
    elseif SLOTS.phase == "waiting_roll" then
      if required_rolls == 1 then
        grid.m[1], grid.m[2], grid.m[3] = "[ ? ]", "[ ? ]", "[ ? ]"
      else
        grid.t[1], grid.t[2], grid.t[3] = "[ ? ]", "[ ? ]", "[ ? ]"
        grid.m[1], grid.m[2], grid.m[3] = "[ ? ]", "[ ? ]", "[ ? ]"
        grid.b[1], grid.b[2], grid.b[3] = "[ ? ]", "[ ? ]", "[ ? ]"
      end
    end
  elseif SLOTS.last_grid ~= nil then
    local lg = SLOTS.last_grid
    if lg.t ~= nil then grid.t[1], grid.t[2], grid.t[3] = lg.t[1], lg.t[2], lg.t[3] end
    if lg.m ~= nil then grid.m[1], grid.m[2], grid.m[3] = lg.m[1], lg.m[2], lg.m[3] end
    if lg.b ~= nil then grid.b[1], grid.b[2], grid.b[3] = lg.b[1], lg.b[2], lg.b[3] end
   end

  local function draw_row(row_data, label, is_active)
    local r, g, b = 0.2, 0.2, 0.3
    if is_active then r, g, b = 0.3, 0.4, 0.5 end

    if ui_button_colored_sized ~= nil then
      ui_button_colored_sized(row_data[1] .. "##" .. label .. "1", 80, 40, r, g, b, 1.0)
      ui_same_line()
      ui_button_colored_sized(row_data[2] .. "##" .. label .. "2", 80, 40, r, g, b, 1.0)
      ui_same_line()
      ui_button_colored_sized(row_data[3] .. "##" .. label .. "3", 80, 40, r, g, b, 1.0)
    else
      ui_text(row_data[1] .. "   " .. row_data[2] .. "   " .. row_data[3])
    end
  end

  draw_row(grid.t, "top", active_lines >= 2)
  draw_row(grid.m, "mid", active_lines >= 1)
  draw_row(grid.b, "bottom", active_lines >= 3)

  ui_separator()

  if SLOTS.active_spin ~= nil then
    local rs = SLOTS.active_spin.rolls or {}
    local needed = tonumber(SLOTS.active_spin.required_rolls) or 1
    local rollText = ""
    if #rs == 0 then
      rollText = "(none yet)"
    else
      for i = 1, #rs do
        if i > 1 then rollText = rollText .. ", " end
        rollText = rollText .. tostring(rs[i])
      end
    end
    ui_text("Rolls so far: " .. rollText .. "  [" .. tostring(#rs) .. "/" .. tostring(needed) .. "]")
  end

  if SLOTS.phase == "waiting_roll" and SLOTS.active_spin ~= nil then
    if ui_button_colored("Force Roll for AFK Player", 0.8, 0.4, 0.2, 1.0) then
      local needed = tonumber(SLOTS.active_spin.required_rolls) or 1
      local forced_rolls = {}
      for i = 1, needed do forced_rolls[i] = math.random(1, 1000) end
      execute_spin(SLOTS.active_spin.player, SLOTS.active_spin.lines, SLOTS.active_spin.bet_per_line, forced_rolls)
    end
  elseif SLOTS.phase == "idle" then
    ui_text_colored("Queue a Player Manually:", 0.7, 0.7, 0.7, 1.0)
    local count = dealer_player_count and dealer_player_count() or 0
    for i = 1, count do
      local name = dealer_player_name(i)
      if dealer_is_eligible(name) then
        local pick = tonumber(SLOTS.ui_line_pick[name]) or 5

        local function line_pick_button(label, val)
          local active = (pick == val)
          if active and ui_button_colored ~= nil then
            return ui_button_colored(label .. "##" .. name .. "_" .. tostring(val), 0.2, 0.8, 0.2, 1.0)
          end
          return ui_button(label .. "##" .. name .. "_" .. tostring(val))
        end

        ui_text(name)
        ui_same_line()
        if line_pick_button("1L", 1) then SLOTS.ui_line_pick[name] = 1; pick = 1 end
        ui_same_line()
        if line_pick_button("3L", 3) then SLOTS.ui_line_pick[name] = 3; pick = 3 end
        ui_same_line()
        if line_pick_button("5L", 5) then SLOTS.ui_line_pick[name] = 5; pick = 5 end
        ui_same_line()
        if line_pick_button("8L", 8) then SLOTS.ui_line_pick[name] = 8; pick = 8 end
        ui_same_line()
        if ui_button("Queue##" .. name .. "_queue") then
          local wager = (dealer_get_wager ~= nil) and (tonumber(dealer_get_wager(name)) or SLOTS.config.min_bet_per_line) or SLOTS.config.min_bet_per_line
          table.insert(SLOTS.queue, { player = name, lines = pick, bet_per_line = wager })
        end
      end
    end
  end
end
