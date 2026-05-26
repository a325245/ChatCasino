-- ============================================================================
-- fair_slots_3x3.lua
-- Final Fixed Version: High Security / Balanced Math / Full UI & Output
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
      "[  ]", -- 1
      "[  ]", -- 2 (BAR)
      "[  ]", -- 3 (BAR)
      "[  ]", -- 4
      "[  ]", -- 5
      "[  ]", -- 6
      "[ ♠ ]", -- 7
      "[ ♥ ]", -- 8
      "[ ♦ ]", -- 9
      "[ ♣ ]"  -- 10
    },

    config = {
      min_bet_per_line = 5,
      max_bet_per_line = 100,
      reel_stop_delay_ms = 400, 
      pay_777 = 150,      
      pay_bar = 25,       
      pay_cash = 5,       
      pay_3_suits = 20,   
      pay_any_two_7 = 4,  
      pay_any_one_7 = 1, 
    },

    chat_templates = {
      queued = "<player> queued for <lines> lines! (Total: <total_bet> chips)",
      turn_prompt = "<player>, you're up! Type this <roll_text>: \"/dice party\"",
      spin_start = "<player> rolls: <reason>. Spinning...",
      result_win = "<player> won <payout> chips on <lines_won> lines! (<reason>)",
      result_lose = "No hit for <player>. Better luck next time!",
    }
  }
end

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
  local vals = { ["<player>"] = tostring(ctx.player or ""), ["<lines>"] = tostring(ctx.lines or 0), ["<total_bet>"] = tostring(ctx.total_bet or 0), ["<payout>"] = tostring(ctx.payout or 0), ["<lines_won>"] = tostring(ctx.lines_won or 0), ["<reason>"] = tostring(ctx.reason or ""), ["<roll>"] = tostring(ctx.roll or 0), ["<roll_text>"] = tostring(ctx.roll_text or "") }
  for k, v in pairs(vals) do msg = msg:gsub(k, v) end
  table_announce(msg)
end

-- Function: config_file_name
-- Purpose: Handles config file name logic for the Slots script.
local function config_file_name()
  return "Slots.config.json"
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
    .. "min_bet_per_line=" .. tostring(math.floor(tonumber(c.min_bet_per_line) or 5)) .. ","
    .. "max_bet_per_line=" .. tostring(math.floor(tonumber(c.max_bet_per_line) or 100)) .. ","
    .. "reel_stop_delay_ms=" .. tostring(math.floor(tonumber(c.reel_stop_delay_ms) or 400)) .. ","
    .. "show_help=" .. tostring(SLOTS.show_help == true)
    .. "}"
  return s
end

-- Function: apply_config_table
-- Purpose: Handles apply config table logic for the Slots script.
local function apply_config_table(data)
  if type(data) ~= "table" then return false end
  SLOTS.config = SLOTS.config or {}
  if data.min_bet_per_line ~= nil then SLOTS.config.min_bet_per_line = tonumber(data.min_bet_per_line) or SLOTS.config.min_bet_per_line end
  if data.max_bet_per_line ~= nil then SLOTS.config.max_bet_per_line = tonumber(data.max_bet_per_line) or SLOTS.config.max_bet_per_line end
  if data.reel_stop_delay_ms ~= nil then SLOTS.config.reel_stop_delay_ms = tonumber(data.reel_stop_delay_ms) or SLOTS.config.reel_stop_delay_ms end
  if data.show_help ~= nil then SLOTS.show_help = (data.show_help == true) end
  return true
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
-- GRID OUTPUT LOGIC (RESTORED)
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
    end
  end

  ui_separator()
  if ui_collapsing_header ~= nil then
    SLOTS.show_help = ui_collapsing_header("Slots Help##slots_help")
  end
  if SLOTS.show_help == true then
    ui_text_colored("How It Works", 0.9, 0.95, 1.0, 1.0)
    ui_text("Players queue by chat command, then roll /dice for seeded spin results.")
    ui_text("1 line uses 1 roll; multi-line spins use 3 rolls.")
    ui_text("Cost = bet per line x selected lines; wager is withdrawn at spin start.")
    ui_separator()
    ui_text_colored("Dealer Tips", 0.9, 0.95, 1.0, 1.0)
    ui_text("Use Queue buttons while idle for manual queueing.")
    ui_text("Use Force Roll for AFK players when waiting for required dice.")
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

  if c1 == "7" and c2 == "7" and c3 == "7" then return bet * SLOTS.config.pay_777, "7-7-7" end
  if c1 == "BAR" and c2 == "BAR" and c3 == "BAR" then return bet * SLOTS.config.pay_bar, "3 BAR" end
  if c1 == "$" and c2 == "$" and c3 == "$" then return bet * SLOTS.config.pay_cash, "3 " end
  
  local suits = {SPADE=true, HEART=true, DIAMOND=true, CLUB=true}
  if c1 == c2 and c2 == c3 and suits[c1] then return bet * SLOTS.config.pay_3_suits, "3 Suits" end

  if count_7 == 2 then return bet * SLOTS.config.pay_any_two_7, "Two 7s" end
  if count_7 == 1 then return bet * SLOTS.config.pay_any_one_7, "One 7" end

  return 0, ""
end

-- ============================================================================
-- ENGINE LOGIC
-- ============================================================================

-- Function: execute_spin
-- Purpose: Handles execute spin logic for the Slots script.
local function execute_spin(player_name, lines, bet, rolls)
  local now = tonumber(time_ms()) or 0
  local delay = SLOTS.config.reel_stop_delay_ms
  local req = lines <= 1 and 1 or 3
  local rows = {}
  for i = 1, req do
    local rv = rolls[i] - 1
    rows[i] = { math.floor(rv/100)+1, math.floor((rv%100)/10)+1, (rv%10)+1 }
  end
  SLOTS.active_spin = { player = player_name, lines = lines, bet = bet, rows = rows, stop_1 = now+delay, stop_2 = now+(delay*2), stop_3 = now+(delay*3) }
  SLOTS.phase = "spinning"
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
      local p, r = eval_line(s1,s2,s3,s.bet)
      if p > 0 then win = win + p; l_won = l_won + 1; table.insert(reasons, label..":"..r) end
    end
    if s.lines >= 1 then check(grid.m1, grid.m2, grid.m3, "Mid") end
    if s.lines >= 2 then check(grid.t1, grid.t2, grid.t3, "Top") end
    if s.lines >= 3 then check(grid.b1, grid.b2, grid.b3, "Bot") end
    if s.lines >= 4 then check(grid.t1, grid.m2, grid.b3, "D1") end
    if s.lines >= 5 then check(grid.b1, grid.m2, grid.t3, "D2") end
    if s.lines >= 6 then check(grid.t1, grid.m1, grid.b1, "C1") end
    if s.lines >= 7 then check(grid.t2, grid.m2, grid.b2, "C2") end
    if s.lines >= 8 then check(grid.t3, grid.m3, grid.b3, "C3") end
    
    -- RESTORED: Handing off to the queue to print the grid to chat
    queue_grid_announce(grid, {player=s.player, payout=win, lines_won=l_won, reason=table.concat(reasons, ", ")})
    
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
  for _ = 1, 15 do
    local pkt = (chat_poll ~= nil) and chat_poll() or ""
    if pkt == "" then break end
    
    local name, _, _, message = string.match(pkt, "^([^|]*)|([^|]*)|([^|]*)|(.*)$")
    if name and message then
      local player = resolve_eligible_player(name)
      
      if player then
        local m = trim_text(message):lower()
        if m:find("^spin") then
          local lines = tonumber(m:match("^spin%s+(%d+)")) or 1
          lines = math.max(1, math.min(8, lines))
          
          local raw_w = (dealer_get_wager ~= nil) and tonumber(dealer_get_wager(player)) or 0
          local wager = math.max(SLOTS.config.min_bet_per_line, math.min(SLOTS.config.max_bet_per_line, (raw_w > 0 and raw_w or SLOTS.config.min_bet_per_line)))
          local bank = (dealer_get_bank ~= nil) and tonumber(dealer_get_bank(player)) or 0
          local cost = wager * lines
          
          if bank >= cost then
            local already = false
            for i=1, #SLOTS.queue do if SLOTS.queue[i].player == player then already = true end end
            if SLOTS.active_spin and SLOTS.active_spin.player == player then already = true end
            
            if not already then
              table.insert(SLOTS.queue, { player=player, lines=lines, bet=wager })
              if SLOTS.phase ~= "idle" then announce("queued", {player=player, lines=lines, total_bet=cost}) end
            else
              send_tell_logged(player, "You are already spinning or queued!")
            end
          else
            send_tell_logged(player, "Not enough chips! Costs " .. cost .. " for " .. lines .. " lines.")
          end
        end
      end

      if SLOTS.phase == "waiting_roll" and message_is_from_expected_roller(name, message) then
        local r = nil
        if dice_roll_value ~= nil then r = tonumber(dice_roll_value(message)) end
        if r == nil or r == 0 then
          for n in message:gmatch("%d+") do r = tonumber(n) end 
        end
        if r and r >= 1 and r <= 1000 then
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
  SLOTS.config.min_bet_per_line = math.max(1, ui_input_int("Min Bet", SLOTS.config.min_bet_per_line))
  SLOTS.config.max_bet_per_line = math.max(1, ui_input_int("Max Bet", SLOTS.config.max_bet_per_line))
  SLOTS.config.reel_stop_delay_ms = math.max(100, ui_input_int("Delay (ms)", SLOTS.config.reel_stop_delay_ms))
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
  process_pending_announcements() -- RESTORED: Prints the grid to chat
  
  if SLOTS.phase == "idle" and SLOTS.pending_grid_lines == nil and #SLOTS.queue > 0 then
    SLOTS.active_spin = table.remove(SLOTS.queue, 1)
    SLOTS.phase = "waiting_roll"
    SLOTS.active_spin.rolls = {}
    SLOTS.active_spin.required_rolls = (SLOTS.active_spin.lines <= 1) and 1 or 3
    local cost = SLOTS.active_spin.bet * SLOTS.active_spin.lines
    if dealer_add_bank then dealer_add_bank(SLOTS.active_spin.player, -cost) end
    SLOTS.stats_wagered, SLOTS.stats_spins = SLOTS.stats_wagered + cost, SLOTS.stats_spins + 1
    local req = tonumber(SLOTS.active_spin.required_rolls) or 1
    local rollText = (req == 1) and "1 time" or (tostring(req) .. " times")
    announce("turn_prompt", {player=SLOTS.active_spin.player, roll=req, roll_text=rollText})
  end

  process_active_spin()

  ui_text_colored("ChatCasino: Final Fixed 3x3 Slots", 0.9, 0.7, 1.0, 1.0)
  ui_separator()
  ui_text(string.format("RTP: %.2f%% | Spins: %d", (SLOTS.stats_wagered > 0 and (SLOTS.stats_paid/SLOTS.stats_wagered)*100 or 0), SLOTS.stats_spins))
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
    if ui_button_colored("Force Roll for AFK Player", 0.8, 0.4, 0.2, 1.0) then
      local req = SLOTS.active_spin.required_rolls
      local forced = {}
      for i = 1, req do forced[i] = math.random(1, 1000) end
      execute_spin(SLOTS.active_spin.player, SLOTS.active_spin.lines, SLOTS.active_spin.bet, forced)
    end
  elseif SLOTS.phase == "idle" then
    ui_text_colored("Queue a Player Manually:", 0.7, 0.7, 0.7, 1.0)
    local count = tonumber(dealer_player_count and dealer_player_count() or 0)
    for i = 1, count do
      local n = dealer_player_name(i)
      if dealer_is_eligible(n) then
        ui_text(n); ui_same_line()
        local pick = SLOTS.ui_line_pick[n] or 8
        -- Function: lp_btn
        -- Purpose: Handles lp btn logic for the Slots script.
        local function lp_btn(lbl, v)
          if pick == v and ui_button_colored then return ui_button_colored(lbl.."##"..n..v, 0.2, 0.8, 0.2, 1.0) end
          return ui_button(lbl.."##"..n..v)
        end
        if lp_btn("1L", 1) then SLOTS.ui_line_pick[n] = 1 end; ui_same_line()
        if lp_btn("3L", 3) then SLOTS.ui_line_pick[n] = 3 end; ui_same_line()
        if lp_btn("5L", 5) then SLOTS.ui_line_pick[n] = 5 end; ui_same_line()
        if lp_btn("8L", 8) then SLOTS.ui_line_pick[n] = 8 end; ui_same_line()
        
        if ui_button("Queue##"..n.."q") then
          local w = tonumber(dealer_get_wager(n)) or 5
          table.insert(SLOTS.queue, { player=n, lines=(SLOTS.ui_line_pick[n] or 8), bet=w })
        end
      end
    end
  end
end
