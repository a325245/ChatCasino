

-- ============================================================================
-- Slots 3x3 1.1
-- updates: fixed "0" roll being ignored

-- Slots 3x3 1.0
-- players roll 3 randoms
-- each random maps to a strip symbol index (1-10)
-- three strips of 3 symbols are printed to chat as the "grid"
-- 8 lines are evaluated for wins: 3 horizontal, 3 vertical, 2 diagonal
-- payouts are based on bet per line, which is total wager divided by 8
-- configurable options include reel stop delay and dealer auto-roll mode 
-- where the dealer issues /dice party rolls on behalf of the player and reads results from chat
-- ============================================================================

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
    show_help = true,

    strip = {
      "[ ♠ ]", -- 1
      "[  ]", -- 2 (hq)
      "[  ]", -- 3 (hq)
      "[  ]", -- 4 flower
      "[  ]", -- 5 flower
      "[  ]", -- 6 flower
      "[  ]", -- 7 7 symbol
      "[ ♥ ]", -- 8
      "[ ♦ ]", -- 9
      "[ ♣ ]"  -- 10
    },

    config = {
      reel_stop_delay_ms = 400, 
      dealer_rolls_for_player = false,
      dealer_roll_spacing_ms = 800,
      pay_777 = 150,      
      pay_bar = 25,       
      pay_cash = 5,       
      pay_3_suits = 20,   
      pay_any_two_7 = 4,  
      pay_any_one_7 = 1, 
    },

    chat_templates = {
      queued = "<player> queued up!",
      turn_prompt = "<player>, you're up! Type this <roll_text>: \"/dice party\"",
      spin_start = "<player> rolls: <reason>. Spinning...",
      result_win = "<player> won <total_win>! <reason>",
      result_lose = "No hit for <player>. Better luck next time!",
    }
  }
end

-- Function: normalize_win_template
-- Purpose: Normalizes legacy win template text to the newer total-win format.
local function normalize_win_template()
  local t = SLOTS.chat_templates or {}
  local winTpl = tostring(t.result_win or "")
  if winTpl == "<player> won <payout> on <lines_won> lines! (<reason>)" then
    t.result_win = "<player> won <total_win>! <reason>"
  end
  SLOTS.chat_templates = t
end

normalize_win_template()

-- ============================================================================
-- UTILITIES & CHAT MESSAGING
-- ============================================================================

-- Function: trim_text
-- Purpose: Handles trim text logic for the Slots script.
local function trim_text(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end

-- Function: output_channel_name
-- Purpose: Resolves the chat channel that this script should use for output.
local function output_channel_name()
  if default_chat_channel ~= nil then
    local ch = default_chat_channel()
    if ch == "echo" or ch == "say" or ch == "party" then return ch end
  end
  return "party"
end

-- Function: table_announce
-- Purpose: Queues or sends a message to the configured chat output channel.
local function table_announce(msg)
  local text = msg or ""
  if text == "" then return end
  if chat_send ~= nil then chat_send(output_channel_name(), text) else dealer_party(text) end
end

-- Function: send_tell_logged
-- Purpose: Handles send tell logged logic for the Slots script.
local function send_tell_logged(player, message)
  local p, m = trim_text(player), trim_text(message)
  if p == "" or m == "" then return end
  local world = "Unknown"
  if dealer_get_world ~= nil then world = tostring(dealer_get_world(p) or "Unknown") end
  if dealer_tell ~= nil then dealer_tell(p, world, m) end
end

-- Function: announce
-- Purpose: Builds and sends a formatted chat announcement for the current event.
local function announce(key, ctx)
  local template = SLOTS.chat_templates[key]
  if not template then return end
  local msg = template
  local vals = {
    ["<player>"] = tostring(ctx.player or ""),
    ["<lines>"] = tostring(ctx.lines or 0),
    ["<total_bet>"] = tostring(ctx.total_bet or 0),
    ["<payout>"] = tostring(ctx.payout or 0),
    ["<total_win>"] = tostring(ctx.total_win or ctx.payout or 0),
    ["<lines_won>"] = tostring(ctx.lines_won or 0),
    ["<reason>"] = tostring(ctx.reason or ""),
    ["<roll>"] = tostring(ctx.roll or 0),
    ["<roll_text>"] = tostring(ctx.roll_text or "")
  }
  for k, v in pairs(vals) do msg = msg:gsub(k, v) end
  table_announce(msg)
end

-- Function: config_file_name
-- Purpose: Handles config file name logic for the Slots script.
local function config_file_name()
  return "Slots.config.json"
end

-- Function: spin_log_file_name
-- Purpose: Returns the CSV log filename used for per-spin audit output.
local function spin_log_file_name()
  return "Slots.spinlog.csv"
end

-- Function: csv_escape
-- Purpose: Escapes a value so it can be safely written as a CSV field.
local function csv_escape(v)
  local s = tostring(v or "")
  s = string.gsub(s, '"', '""')
  return '"' .. s .. '"'
end

-- Function: append_spin_log_row
-- Purpose: Appends one spin audit row to the CSV file after each settled spin.
local function append_spin_log_row(res)
  if script_read_text == nil or script_write_text == nil then return false end
  if type(res) ~= "table" then return false end

  local timestamp = tonumber(time_ms and time_ms() or 0) or 0
  local player = tostring(res.player or "")
  local totalWager = tonumber(res.total_bet) or 0
  local payout = tonumber(res.payout) or 0
  local net = payout - totalWager
  local outcome = "push"
  local outcomeAmount = 0
  if net > 0 then
    outcome = "won"
    outcomeAmount = net
  elseif net < 0 then
    outcome = "lost"
    outcomeAmount = math.abs(net)
  end
  local reason = tostring(res.reason or "")

  local header = "timestamp_ms,player,total_wager,payout,net,outcome,amount,reason\n"
  local row = table.concat({
    tostring(math.floor(timestamp)),
    csv_escape(player),
    tostring(math.floor(totalWager)),
    tostring(math.floor(payout)),
    tostring(math.floor(net)),
    csv_escape(outcome),
    tostring(math.floor(outcomeAmount)),
    csv_escape(reason),
  }, ",") .. "\n"

  local existing = script_read_text(spin_log_file_name()) or ""
  if existing == "" then
    return script_write_text(spin_log_file_name(), header .. row) == true
  end

  return script_write_text(spin_log_file_name(), existing .. row) == true
end

-- Function: echo_notice
-- Purpose: Handles echo notice logic for the Slots script.
local function echo_notice(msg)
  local text = tostring(msg or "")
  if text == "" then return end
  if chat_send ~= nil then
    chat_send("echo", text)
  elseif dealer_party ~= nil then
    dealer_party(text)
  end
end

-- Function: export_config_blob
-- Purpose: Handles export config blob logic for the Slots script.
local function export_config_blob()
  local c = SLOTS.config or {}
  local s = "return {"
    .. "reel_stop_delay_ms=" .. tostring(math.floor(tonumber(c.reel_stop_delay_ms) or 400)) .. ","
    .. "dealer_rolls_for_player=" .. tostring(c.dealer_rolls_for_player == true) .. ","
    .. "dealer_roll_spacing_ms=" .. tostring(math.floor(tonumber(c.dealer_roll_spacing_ms) or 800)) .. ","
    .. "show_help=" .. tostring(SLOTS.show_help == true)
    .. "}"
  return s
end

-- Function: apply_config_table
-- Purpose: Handles apply config table logic for the Slots script.
local function apply_config_table(data)
  if type(data) ~= "table" then return false end
  SLOTS.config = SLOTS.config or {}
  if data.reel_stop_delay_ms ~= nil then SLOTS.config.reel_stop_delay_ms = tonumber(data.reel_stop_delay_ms) or SLOTS.config.reel_stop_delay_ms end
  if data.dealer_rolls_for_player ~= nil then SLOTS.config.dealer_rolls_for_player = (data.dealer_rolls_for_player == true) end
  if data.dealer_roll_spacing_ms ~= nil then SLOTS.config.dealer_roll_spacing_ms = tonumber(data.dealer_roll_spacing_ms) or SLOTS.config.dealer_roll_spacing_ms end
  if data.show_help ~= nil then SLOTS.show_help = (data.show_help == true) end
  if SLOTS.config.dealer_roll_spacing_ms == nil then SLOTS.config.dealer_roll_spacing_ms = 800 end
  if SLOTS.config.dealer_roll_spacing_ms < 100 then SLOTS.config.dealer_roll_spacing_ms = 100 end
  return true
end

-- Function: effective_dealer_roll_spacing_ms
-- Purpose: Normalizes dealer auto-roll spacing into a safe millisecond range.
local function effective_dealer_roll_spacing_ms()
  SLOTS.config = SLOTS.config or {}
  local v = tonumber(SLOTS.config.dealer_roll_spacing_ms) or 800
  if v < 100 then v = 100 end
  if v > 10000 then v = 10000 end
  SLOTS.config.dealer_roll_spacing_ms = math.floor(v)
  return SLOTS.config.dealer_roll_spacing_ms
end

-- Function: save_config_file
-- Purpose: Saves config file data from runtime state.
local function save_config_file()
  if script_write_text == nil then
    SLOTS.config_status = "Slots config save failed (host file API unavailable)."
    echo_notice(SLOTS.config_status)
    return false
  end
  local ok = script_write_text(config_file_name(), export_config_blob()) == true
  if ok then
    SLOTS.config_status = "Slots config saved."
  else
    SLOTS.config_status = "Slots config save failed."
  end
  echo_notice(SLOTS.config_status)
  return ok
end

-- Function: load_config_file
-- Purpose: Loads config file data into runtime state.
local function load_config_file()
  if script_read_text == nil then
    SLOTS.config_status = "Slots config load skipped (host file API unavailable)."
    return false
  end
  local raw = script_read_text(config_file_name())
  if raw == nil or raw == "" then
    SLOTS.config_status = "Slots config file not found."
    return false
  end
  local loader = loadstring or load
  local fn, err = loader(tostring(raw))
  if not fn then
    SLOTS.config_status = "Slots config syntax error: " .. tostring(err)
    return false
  end
  local ok, data = pcall(fn)
  if not ok then
    SLOTS.config_status = "Slots config runtime error: " .. tostring(data)
    return false
  end
  if not apply_config_table(data) then
    SLOTS.config_status = "Slots config invalid payload."
    return false
  end
  SLOTS.config_status = "Slots config loaded."
  return true
end

if SLOTS.config_status == nil then SLOTS.config_status = "Slots config not loaded yet." end
if SLOTS._config_loaded ~= true then
  load_config_file()
  SLOTS._config_loaded = true
end

-- ============================================================================
-- GRID OUTPUT LOGIC 
-- ============================================================================

-- Function: queue_grid_announce
-- Purpose: Queues grid announce so it can be handled in turn order.
local function queue_grid_announce(grid, result)
  if grid == nil then return end
  local now = tonumber(time_ms()) or 0
  SLOTS.pending_grid_lines = {
    (grid.t1 or "[ - ]") .. " " .. (grid.t2 or "[ - ]") .. " " .. (grid.t3 or "[ - ]"),
    (grid.m1 or "[ - ]") .. " " .. (grid.m2 or "[ - ]") .. " " .. (grid.m3 or "[ - ]"),
    (grid.b1 or "[ - ]") .. " " .. (grid.b2 or "[ - ]") .. " " .. (grid.b3 or "[ - ]")
  }
  SLOTS.pending_grid_index = 1
  SLOTS.pending_grid_next_at = now
  SLOTS.pending_result = result
end

-- Function: process_pending_announcements
-- Purpose: Processes pending announcements updates for the current game state.
local function process_pending_announcements()
  local lines = SLOTS.pending_grid_lines
  if lines == nil then return end
  
  local now = tonumber(time_ms()) or 0
  if now < (tonumber(SLOTS.pending_grid_next_at) or 0) then return end

  local idx = tonumber(SLOTS.pending_grid_index) or 1
  if lines[idx] then
    table_announce(lines[idx])
    SLOTS.pending_grid_index = idx + 1
    SLOTS.pending_grid_next_at = now + 250 -- 250ms delay between printing each row
  else
    SLOTS.pending_grid_lines = nil
    local res = SLOTS.pending_result
    SLOTS.pending_result = nil
    if res then
      if (tonumber(res.payout) or 0) > 0 then
        if dealer_add_bank ~= nil then dealer_add_bank(res.player, res.payout) end
        SLOTS.stats_paid = SLOTS.stats_paid + res.payout
        announce("result_win", res)
      else
        announce("result_lose", { player = res.player })
      end
      append_spin_log_row(res)
    end
  end
end

-- ============================================================================
-- FFXIV NAME PARSER & ELIGIBILITY
-- ============================================================================

-- Function: normalize_player_name
-- Purpose: Normalizes player name into a consistent format for comparisons.
local function normalize_player_name(name)
  local n = string.lower(tostring(name or ""))
  n = n:gsub("[^\32-\126]", "")
  local worlds = {"leviathan", "behemoth", "excalibur", "sargatanas", "hyperion", "ultros", "balmung", "gilgamesh", "faerie"}
  for _, w in ipairs(worlds) do n = n:gsub(w, "") end
  n = n:gsub("^%b()", ""):gsub("^%b[]", "")
  n = n:gsub("[%s%p]+", " "):gsub("^%s+", ""):gsub("%s+$", "")
  return n
end

-- Function: resolve_eligible_player
-- Purpose: Handles resolve eligible player logic for the Slots script.
local function resolve_eligible_player(raw_name)
  local speaker = normalize_player_name(raw_name)
  if speaker == "" then return nil end
  if dealer_player_count ~= nil then
    local count = tonumber(dealer_player_count()) or 0
    for i = 1, count do
      local p = dealer_player_name(i)
      if p then
        local normP = normalize_player_name(p)
        if normP ~= "" and (speaker:find(normP, 1, true) or normP:find(speaker, 1, true)) then return p end
      end
    end
  end
  return (dealer_is_eligible and dealer_is_eligible(raw_name)) and raw_name or nil
end

-- Function: message_is_from_expected_roller
-- Purpose: Handles message is from expected roller logic for the Slots script.
local function message_is_from_expected_roller(name, message)
  if SLOTS.active_spin == nil then return false end
  local expected = normalize_player_name(SLOTS.active_spin.player)
  local speaker = normalize_player_name(name)

  if expected == "" then return true end
  if speaker == expected then return true end
  if speaker ~= "" and (speaker:find(expected, 1, true) or expected:find(speaker, 1, true)) then return true end

  if speaker == "" then
    local m = string.lower(tostring(message or ""))
    if m:find("random") or m:find("roll") or m:find("dice") then return true end
  end
  return false
end

-- Function: parse_slots_roll
-- Purpose: Parses a roll from chat, safely supporting 0.
local function parse_slots_roll(msg)
  local m = tostring(msg or "")
  
  -- Prioritize specific bot strings "Random! X"
  local n = m:match("[Rr]andom!%s*(%d+)")
  if n then return tonumber(n) end

  -- Fallback to host API to capture genuine system rolls "rolls a X."
  if dice_roll_value ~= nil then
    local val = tonumber(dice_roll_value(m))
    if val ~= nil and val >= 0 then
      return val
    end
  end

  return nil
end

-- ============================================================================
-- CORE MATH & SYMBOL LOGIC
-- ============================================================================

-- Function: canonical_symbol
-- Purpose: Handles canonical symbol logic for the Slots script.
local function canonical_symbol(sym)
  local s = tostring(sym or "")
  if s:find("") or s:find("7") then return "7" end
  if s:find("") or s:find("%$") then return "$" end
  if s:find("") then return "BAR" end
  if s:find("♠") then return "SPADE" end
  if s:find("♥") then return "HEART" end
  if s:find("♦") then return "DIAMOND" end
  if s:find("♣") then return "CLUB" end
  return "EMPTY"
end

-- Function: eval_line
-- Purpose: Handles eval line logic for the Slots script.
local function eval_line(sym1, sym2, sym3, bet)
  local c1, c2, c3 = canonical_symbol(sym1), canonical_symbol(sym2), canonical_symbol(sym3)
  local count_7 = 0
  if c1 == "7" then count_7 = count_7 + 1 end
  if c2 == "7" then count_7 = count_7 + 1 end
  if c3 == "7" then count_7 = count_7 + 1 end

  if c1 == "7" and c2 == "7" and c3 == "7" then return bet * SLOTS.config.pay_777, "7-7-7", SLOTS.config.pay_777 end
  if c1 == "BAR" and c2 == "BAR" and c3 == "BAR" then return bet * SLOTS.config.pay_bar, "3 BAR", SLOTS.config.pay_bar end
  if c1 == "$" and c2 == "$" and c3 == "$" then return bet * SLOTS.config.pay_cash, "3 ", SLOTS.config.pay_cash end
  
  local suits = {SPADE=true, HEART=true, DIAMOND=true, CLUB=true}
  if c1 == c2 and c2 == c3 and suits[c1] then return bet * SLOTS.config.pay_3_suits, "3 Suits", SLOTS.config.pay_3_suits end

  if count_7 == 2 then return bet * SLOTS.config.pay_any_two_7, "Two 7s", SLOTS.config.pay_any_two_7 end
  if count_7 == 1 then return bet * SLOTS.config.pay_any_one_7, "One 7", SLOTS.config.pay_any_one_7 end

  return 0, "", 0
end

-- ============================================================================
-- ENGINE LOGIC
-- ============================================================================

-- Function: execute_spin
-- Purpose: Handles execute spin logic for the Slots script.
local function execute_spin(player_name, lines, bet, rolls)
  local now = tonumber(time_ms()) or 0
  local delay = SLOTS.config.reel_stop_delay_ms
  local req = 3
  local rows = {}

  local function roll_to_indices(v)
    local n = math.floor(tonumber(v) or 0)
    if n < 0 then n = 0 end
    if n > 1000 then n = 1000 end

    local text = string.format("%03d", n % 1000)
    local d1 = tonumber(string.sub(text, 1, 1)) or 0
    local d2 = tonumber(string.sub(text, 2, 2)) or 0
    local d3 = tonumber(string.sub(text, 3, 3)) or 0

    local function digit_to_strip_index(d)
      if d == 0 then return 10 end
      return d
    end

    return {
      digit_to_strip_index(d1),
      digit_to_strip_index(d2),
      digit_to_strip_index(d3),
    }
  end

  for i = 1, req do
    rows[i] = roll_to_indices(rolls[i])
  end
  SLOTS.active_spin = { player = player_name, lines = lines, bet = bet, rows = rows, stop_1 = now+delay, stop_2 = now+(delay*2), stop_3 = now+(delay*3) }
  SLOTS.phase = "spinning"
end

-- Function: process_dealer_auto_rolls
-- Purpose: Performs dealer-driven random rolls while waiting for a queued player's spin seed.
local function process_dealer_auto_rolls()
  if SLOTS.phase ~= "waiting_roll" then return end
  if SLOTS.active_spin == nil then return end
  local autoMode = (SLOTS.config and SLOTS.config.dealer_rolls_for_player == true) or (SLOTS.active_spin.force_auto_roll == true)
  if not autoMode then return end

  local now = tonumber(time_ms()) or 0
  SLOTS.active_spin.next_auto_roll_at = tonumber(SLOTS.active_spin.next_auto_roll_at) or now

  -- Step 1: issue dealer /dice party command.
  if SLOTS.active_spin.auto_roll_inflight ~= true then
    if now < SLOTS.active_spin.next_auto_roll_at then return end

    local issued = false
    if chat_command ~= nil then
      local ok = pcall(function() chat_command("/dice party") end)
      issued = ok
    elseif dice_command ~= nil then
      issued = (dice_command("party", 1000) == true)
    end

    if issued then
      SLOTS.active_spin.auto_roll_inflight = true
      SLOTS.active_spin.auto_roll_sent_at = now
    else
      SLOTS.active_spin.next_auto_roll_at = now + effective_dealer_roll_spacing_ms()
    end
    return
  end

  -- Step 2: read back the next dice result from chat.
  for _ = 1, 24 do
    local pkt = (chat_poll ~= nil) and chat_poll() or ""
    if pkt == "" then break end

    local _, _, _, message = string.match(pkt, "^([^|]*)|([^|]*)|([^|]*)|(.*)$")
    local msg = tostring(message or "")
    local rolled = parse_slots_roll(msg)

    if rolled ~= nil and rolled >= 0 and rolled <= 1000 then
      table.insert(SLOTS.active_spin.rolls, rolled)
      SLOTS.active_spin.auto_roll_inflight = false

      if #SLOTS.active_spin.rolls >= (tonumber(SLOTS.active_spin.required_rolls) or 3) then
        execute_spin(SLOTS.active_spin.player, SLOTS.active_spin.lines, SLOTS.active_spin.bet, SLOTS.active_spin.rolls)
        return
      end

      SLOTS.active_spin.next_auto_roll_at = now + effective_dealer_roll_spacing_ms()
      return
    end
  end

  -- If we issued /dice but never observed a result, retry after a short timeout.
  local sentAt = tonumber(SLOTS.active_spin.auto_roll_sent_at) or now
  if now - sentAt > math.max(1500, effective_dealer_roll_spacing_ms()) then
    SLOTS.active_spin.auto_roll_inflight = false
    SLOTS.active_spin.next_auto_roll_at = now + 200
  end
end

-- Function: process_active_spin
-- Purpose: Processes active spin updates for the current game state.
local function process_active_spin()
  if SLOTS.phase ~= "spinning" or not SLOTS.active_spin then return end
  local now = tonumber(time_ms()) or 0
  local s = SLOTS.active_spin
  local final = (#s.rows <= 1) and s.stop_1 or s.stop_3
  if now >= final then
    -- Function: get_s
    -- Purpose: Handles get s logic for the Slots script.
    local function get_s(r_idx, c_idx) return SLOTS.strip[s.rows[r_idx][c_idx]] end
    local t, m, b = {}, {}, {}
    if #s.rows <= 1 then
      for i=1,3 do m[i] = get_s(1,i) end
      for i=1,3 do t[i] = SLOTS.strip[((s.rows[1][i]-2)%10)+1] end
      for i=1,3 do b[i] = SLOTS.strip[(s.rows[1][i]%10)+1] end
    else
      for i=1,3 do t[i]=get_s(1,i); m[i]=get_s(2,i); b[i]=get_s(3,i) end
    end
    local grid = {t1=t[1],t2=t[2],t3=t[3], m1=m[1],m2=m[2],m3=m[3], b1=b[1],b2=b[2],b3=b[3]}
    local win, l_won, reasons = 0, 0, {}
    -- Function: check
    -- Purpose: Handles check logic for the Slots script.
    local function check(s1,s2,s3,label)
      local p, r, mult = eval_line(s1,s2,s3,s.bet)
      if p > 0 then
        win = win + p
        l_won = l_won + 1
        table.insert(reasons, label .. ": " .. r .. " (" .. tostring(p) .. ")")
      end
    end
    if s.lines >= 1 then check(grid.t1, grid.t2, grid.t3, "R1") end
    if s.lines >= 2 then check(grid.m1, grid.m2, grid.m3, "R2") end
    if s.lines >= 3 then check(grid.b1, grid.b2, grid.b3, "R3") end
    if s.lines >= 4 then check(grid.t1, grid.m2, grid.b3, "D1") end
    if s.lines >= 5 then check(grid.b1, grid.m2, grid.t3, "D2") end
    if s.lines >= 6 then check(grid.t1, grid.m1, grid.b1, "C1") end
    if s.lines >= 7 then check(grid.t2, grid.m2, grid.b2, "C2") end
    if s.lines >= 8 then check(grid.t3, grid.m3, grid.b3, "C3") end
    
    queue_grid_announce(grid, {
      player=s.player,
      payout=win,
      total_win=win,
      total_bet=(tonumber(s.bet) or 0) * 8,
      lines_won=l_won,
      reason=table.concat(reasons, "; ")
    })
    
    SLOTS.last_grid = {t=t, m=m, b=b}
    SLOTS.active_spin, SLOTS.phase = nil, "idle"
  end
end

-- ============================================================================
-- INPUT PROCESSING & QUEUE
-- ============================================================================

-- Function: process_chat_inputs
-- Purpose: Processes chat inputs updates for the current game state.
local function process_chat_inputs()
  -- In dealer auto-roll mode, preserve chat_poll packets for process_dealer_auto_rolls().
  if SLOTS.phase == "waiting_roll" and SLOTS.active_spin ~= nil and ((SLOTS.config and SLOTS.config.dealer_rolls_for_player == true) or SLOTS.active_spin.force_auto_roll == true) then
    return
  end

  for _ = 1, 15 do
    local pkt = (chat_poll ~= nil) and chat_poll() or ""
    if pkt == "" then break end
    
    local name, _, _, message = string.match(pkt, "^([^|]*)|([^|]*)|([^|]*)|(.*)$")
    if name and message then
      local player = resolve_eligible_player(name)
      
      if player then
        local m = trim_text(message):lower()
        if m:find("^spin") then
          local lines = 8
          
          local total_wager = (dealer_get_wager ~= nil) and tonumber(dealer_get_wager(player)) or 0
          local wager = math.floor(math.max(0, total_wager) / 8)
          local bank = (dealer_get_bank ~= nil) and tonumber(dealer_get_bank(player)) or 0
          local cost = wager * 8
          
          if wager > 0 and bank >= cost then
            local already = false
            for i=1, #SLOTS.queue do if SLOTS.queue[i].player == player then already = true end end
            if SLOTS.active_spin and SLOTS.active_spin.player == player then already = true end
            
            if not already then
              table.insert(SLOTS.queue, { player=player, lines=lines, bet=wager })
              if SLOTS.phase ~= "idle" then announce("queued", {player=player, lines=8, total_bet=cost}) end
            else
              send_tell_logged(player, "You are already spinning or queued!")
            end
          else
            send_tell_logged(player, "Not enough gil! Slots uses 8 lines: total wager is split 8 ways.")
          end
        end
      end

      if SLOTS.phase == "waiting_roll" and not (SLOTS.config and SLOTS.config.dealer_rolls_for_player == true) and message_is_from_expected_roller(name, message) then
        local r = parse_slots_roll(message)
        if r ~= nil and r >= 0 and r <= 1000 then
          table.insert(SLOTS.active_spin.rolls, r)
          if #SLOTS.active_spin.rolls >= SLOTS.active_spin.required_rolls then
            execute_spin(SLOTS.active_spin.player, SLOTS.active_spin.lines, SLOTS.active_spin.bet, SLOTS.active_spin.rolls)
          end
        end
      end
    end
  end
end

-- ============================================================================
-- UI RENDERING
-- ============================================================================

-- Function: draw_config_ui
-- Purpose: Renders the configuration panel where the dealer edits script settings.
function draw_config_ui()
  ui_text("Config status: " .. tostring(SLOTS.config_status or ""))
  ui_text("Bet limits come from global dealer settings.")
  ui_text("Wins are determined by 8 line directions - horizontal, vertical, and diagonal.")
  ui_text("Player total wager is divided by 8 (rounded down per line).")
  SLOTS.config.reel_stop_delay_ms = math.max(100, ui_input_int("Delay (ms)", SLOTS.config.reel_stop_delay_ms))
  SLOTS.config.dealer_rolls_for_player = ui_checkbox("Dealer rolls for player", SLOTS.config.dealer_rolls_for_player == true)
  SLOTS.config.dealer_roll_spacing_ms = math.max(100, ui_input_int("Dealer roll spacing (ms)", effective_dealer_roll_spacing_ms()))
  ui_separator()
  if ui_button("Save Config##slots_cfg_save") then
    save_config_file()
  end
  ui_same_line()
  if ui_button("Load Config##slots_cfg_load") then
    load_config_file()
  end
end

-- Function: draw_ui
-- Purpose: Renders the main game UI and runs the per-frame update flow.
function draw_ui()
  process_chat_inputs()
  process_pending_announcements() 
  
  if SLOTS.phase == "idle" and SLOTS.pending_grid_lines == nil and #SLOTS.queue > 0 then
    SLOTS.active_spin = table.remove(SLOTS.queue, 1)
    SLOTS.active_spin.lines = 8
    SLOTS.phase = "waiting_roll"
    SLOTS.active_spin.rolls = {}
    SLOTS.active_spin.required_rolls = 3
    SLOTS.active_spin.auto_roll_inflight = false
    SLOTS.active_spin.next_auto_roll_at = (tonumber(time_ms()) or 0) + effective_dealer_roll_spacing_ms()
    local cost = SLOTS.active_spin.bet * 8
    if dealer_add_bank then dealer_add_bank(SLOTS.active_spin.player, -cost) end
    SLOTS.stats_wagered, SLOTS.stats_spins = SLOTS.stats_wagered + cost, SLOTS.stats_spins + 1
    if SLOTS.config and SLOTS.config.dealer_rolls_for_player == true then
      table_announce("Dealer auto-roll is enabled: rolling 3 randoms for " .. tostring(SLOTS.active_spin.player) .. ".")
    else
      announce("turn_prompt", {player=SLOTS.active_spin.player, roll=3, roll_text="3 times"})
    end
  end

  process_dealer_auto_rolls()
  process_active_spin()

  ui_text_colored("ChatCasino: 3x3 Slots", 0.9, 0.7, 1.0, 1.0)
  ui_separator()
  ui_text("Status: " .. SLOTS.phase .. " | Queue: " .. #SLOTS.queue)

  local g = { t={"[ - ]","[ - ]","[ - ]"}, m={"[ - ]","[ - ]","[ - ]"}, b={"[ - ]","[ - ]","[ - ]"} }
  if SLOTS.phase == "spinning" and SLOTS.active_spin then
    local s, n = SLOTS.active_spin, tonumber(time_ms()) or 0
    -- Function: anim
    -- Purpose: Handles anim logic for the Slots script.
    local function anim(row, d, r_idx) 
      if n < d then 
        local a=(math.floor(n/50)%10)+1 
        row[1],row[2],row[3]=SLOTS.strip[a],SLOTS.strip[(a%10)+1],SLOTS.strip[((a+1)%10)+1] 
      else 
        row[1],row[2],row[3]=SLOTS.strip[s.rows[r_idx][1]],SLOTS.strip[s.rows[r_idx][2]],SLOTS.strip[s.rows[r_idx][3]] 
      end 
    end
    if #s.rows == 1 then 
      anim(g.m, s.stop_1, 1) 
      if n >= s.stop_1 then
        for i=1,3 do g.t[i] = SLOTS.strip[((s.rows[1][i]-2)%10)+1] end
        for i=1,3 do g.b[i] = SLOTS.strip[(s.rows[1][i]%10)+1] end
      end
    else anim(g.t, s.stop_1, 1); anim(g.m, s.stop_2, 2); anim(g.b, s.stop_3, 3) end
  elseif SLOTS.last_grid then
    g.t, g.m, g.b = SLOTS.last_grid.t, SLOTS.last_grid.m, SLOTS.last_grid.b
  end

  local row_data = { {g.t, "top"}, {g.m, "mid"}, {g.b, "bot"} }
  for _, item in ipairs(row_data) do
    local r, pfx = item[1], item[2]
    ui_button_colored_sized(r[1].."##"..pfx.."1", 80, 40, 0.2, 0.2, 0.3, 1) ui_same_line()
    ui_button_colored_sized(r[2].."##"..pfx.."2", 80, 40, 0.2, 0.2, 0.3, 1) ui_same_line()
    ui_button_colored_sized(r[3].."##"..pfx.."3", 80, 40, 0.2, 0.2, 0.3, 1)
  end

  ui_separator()

  if SLOTS.phase == "waiting_roll" and SLOTS.active_spin then
    if ui_button_colored("Force Roll for Player", 0.8, 0.4, 0.2, 1.0) then
      SLOTS.active_spin.force_auto_roll = true
      SLOTS.active_spin.auto_roll_inflight = false
      SLOTS.active_spin.next_auto_roll_at = tonumber(time_ms()) or 0
      table_announce("Rolling for " .. tostring(SLOTS.active_spin.player) .. ".")
    end
  elseif SLOTS.phase == "idle" then
    ui_text_colored("Queue a Player:", 0.7, 0.7, 0.7, 1.0)
    ui_separator()
    ui_text(" ")
    local count = tonumber(dealer_player_count and dealer_player_count() or 0)
    for i = 1, count do
      local n = dealer_player_name(i)
      if dealer_is_eligible(n) then
        local totalWager = tonumber(dealer_get_wager and dealer_get_wager(n) or 0) or 0
        local perLine = math.floor(math.max(0, totalWager) / 8)
        local totalCost = perLine * 8
        ui_text(n .. " | Total Wager " .. tostring(totalWager) .. " | Per Line " .. tostring(perLine)); ui_same_line()
        if ui_button("Queue##"..n.."q") then
          if perLine > 0 then
            table.insert(SLOTS.queue, { player=n, lines=8, bet=perLine })

          else
            send_tell_logged(n, "Your total wager is too low for 8-line Slots.")
          end
        end
        ui_text(" ")
      end
    end
    ui_text(" ")
  end
  

  if ui_collapsing_header ~= nil then
    SLOTS.show_help = ui_collapsing_header("Pay Table##Pay Table_bottom")
  end
  if SLOTS.show_help == true then
      ui_text_colored("Pay Table", 0.95, 0.9, 0.7, 1.0)
      ui_text("7-7-7: x" .. tostring(SLOTS.config.pay_777))
      ui_text("--: x" .. tostring(SLOTS.config.pay_bar))
      ui_text("--: x" .. tostring(SLOTS.config.pay_cash))
      ui_text("3 matching suits: x" .. tostring(SLOTS.config.pay_3_suits))
      ui_text("Any two 7s: x" .. tostring(SLOTS.config.pay_any_two_7))
      ui_text("Any one 7: x" .. tostring(SLOTS.config.pay_any_one_7))
   end

  ui_separator()
  if ui_collapsing_header ~= nil then
    SLOTS.show_help = ui_collapsing_header("Slots Help##slots_help_bottom")
  end
  if SLOTS.show_help == true then
    ui_text_colored("How It Works", 0.9, 0.95, 1.0, 1.0)
    ui_text("--- Wins are determined by 8 line directions - horizontal, vertical, and diagonal.")
    ui_text("--- Player total wager is split across 8 lines (rounded down per line).")
    ui_text("--- Players may queue themselves up by saying \"spin\" or via the dealer Queue button")
    ui_text("--- Player rolls /dice party 3 times to seed  the R1/R2/R3 rows before dealer outputs Symbol view.")
    ui_separator()
    ui_text_colored("Dealer Tips", 0.9, 0.95, 1.0, 1.0)
    ui_text("--- A config option exists to autoroll for players.")
    ui_text("--- You may also Force Roll for players unable to roll.")
  end
  ui_separator()
  ui_text(string.format(
    "Return To Player: %.2f%% | Spins: %d | Gil In: %d | Gil Out: %d",
    (SLOTS.stats_wagered > 0 and (SLOTS.stats_paid/SLOTS.stats_wagered)*100 or 0),
    SLOTS.stats_spins,
    math.floor(tonumber(SLOTS.stats_wagered) or 0),
    math.floor(tonumber(SLOTS.stats_paid) or 0)
  ))
end
