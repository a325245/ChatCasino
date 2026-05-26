-- ============================================================================
-- Porxie By Irie
-- Players roll a d6 hoping to reach 15 before rolling a 1, earning a 2x win
-- they are then given the option to push for 25 to earn a 3x win!
-- ============================================================================
if PORXIE == nil then
  PORXIE = {
    phase = "idle",          -- State Machine: "idle", "waiting_roll", or "milestone_choice"
    status_text = "Queue a player to begin Porxie!",
    config_status = "Porxie config not loaded yet.",
    
    queue = {},              -- Holds players waiting to play: { name, wager }
    active_player = nil,     -- Name of the person currently rolling
    active_wager = 0,        -- The bet amount for the current round
    current_score = 0,       -- Cumulative score for the active turn
    has_chosen_ride = false, -- TRACKER: True if player already accepted the gamble to 25

    target_score = 15,       -- Points needed to win
    bonus_score = 25,        -- Threshold for the 3x super payout bonus
    pacing_delay_ms = 1200,  -- Slight buffer between text prints
    next_chat_at = 0,        -- Anti-spam tracking
    show_help = true,

    -- Live Win Rate Tracker Stats
    games_played = 0,
    games_won = 0,

    -- Customizable Chat Templates
    chat_templates = {
      queued      = "<player> queued for Porxie! Bet: <bet> gil.",
      prompt      = "<player>, roll /dice party 6 now! (Current Score: <total>/15. Don't roll a 1!)",
      ride_prompt = "  <player>, roll /dice party 6 now! (Current Jackpot Score: <total>/25. Risk it all!)",
      safe        = "<player> rolled a <roll>! New score: <total>/15. Keep going!",
      ride_safe   = "  <player> rolled a <roll>! Pushing the limits: <total>/25! Keep going!",
      milestone   = "  <player> hit <total> points and fed the Porxie! You have secured a 2x payout... but it still looks hungry! Do you want to Cash Out now, or roll for the 3x Jackpot at 25? (Don't roll a 1!)",
      win         = "  <player> cashed out at <total> points! Fed the Porxie and paid <payout> gil (2x). New Bank: <bank>.",
      bonus_win   = "  SUPER WIN! <player> pushed their luck and smashed the bonus threshold with <total> points! Paid <payout> gil (3x)! New Bank: <bank>.",
      lose        = "  <player> rolled a 1! The Porxie flies away hungry! Lost <bet> gil. Remaining Bank: <bank>.",
      skipped     = "<player> removed from Porxie queue (invalid wager or insufficient bank).",
      booted      = "[Porxie Table Admin] <player> has been kicked from the table seat."
    }
  }
end

-- ============================================================================
-- Utility & Token Formatting Helpers
-- ============================================================================

local function config_file_name()
  return "Porxie.config.json"
end

-- Formats a chat template by replacing tokens with live game data
local function fmt(template, ctx)
  local msg = tostring(template or "")
  local values = {
    ["<player>"] = tostring((ctx and ctx.player) or ""),
    ["<bet>"]    = tostring((ctx and ctx.bet) or 0),
    ["<bank>"]   = tostring((ctx and ctx.bank) or 0),
    ["<roll>"]   = tostring((ctx and ctx.roll) or 0),
    ["<payout>"] = tostring((ctx and ctx.payout) or 0),
    ["<total>"]  = tostring((ctx and ctx.total) or 0),
  }
  for token, value in pairs(values) do
    msg = string.gsub(msg, token, value)
  end
  return msg
end

-- Safely formats and sends text to the engine's active channel (Supports dynamic routing targets)
local function send_table_chat(key, ctx, target_override)
  local t = PORXIE.chat_templates or {}
  local template = t[key]
  if template == nil or template == "" then return end
  
  local text = fmt(template, ctx)
  local now = (time_ms ~= nil) and tonumber(time_ms()) or 0
  local route = target_override or "party"
  
  if PORXIE.next_chat_at < now then 
    PORXIE.next_chat_at = now 
  end
  
  if chat_send ~= nil then
    chat_send(route, text)
  elseif route == "echo" and dealer_echo ~= nil then
    dealer_echo(text)
  elseif dealer_party ~= nil then
    dealer_party(text)
  end
  
  PORXIE.next_chat_at = PORXIE.next_chat_at + PORXIE.pacing_delay_ms
end

local function flush_old_rolls()
  if chat_poll == nil then return end
  for _ = 1, 100 do
    local packet = chat_poll()
    if packet == nil or packet == "" then break end
  end
end

local function parse_dice_d6(message)
  if message == nil then return nil end
  if dice_roll_value ~= nil and dice_roll_upper ~= nil then
    local val = tonumber(dice_roll_value(message)) or 0
    local max = tonumber(dice_roll_upper(message)) or 0
    if val >= 1 and max == 6 then return val end
  end

  local fallback = tonumber(string.match(tostring(message), "[Rr]olls?%s+(%d+)%s*%(%s*1%-%s*6%s*%)"))
  if fallback ~= nil and fallback >= 1 and fallback <= 6 then 
    return fallback 
  end
  return nil
end

local function clean_name(name)
  local n = string.lower(tostring(name or ""))
  n = string.gsub(n, "@.*$", "") 
  return string.gsub(n, "[^%a%d]", "") 
end

-- ============================================================================
-- Config Save/Load Architecture
-- ============================================================================

local function export_config_blob()
  local t = PORXIE.chat_templates or {}
  return "return {"
    .. "pacing_delay_ms=" .. tostring(math.floor(tonumber(PORXIE.pacing_delay_ms) or 1200)) .. ","
    .. "show_help=" .. tostring(PORXIE.show_help == true) .. ","
    .. "chat_templates={"
    .. "queued=[=[" .. tostring(t.queued or "") .. "]=],"
    .. "prompt=[=[" .. tostring(t.prompt or "") .. "]=],"
    .. "ride_prompt=[=[" .. tostring(t.ride_prompt or "") .. "]=],"
    .. "safe=[=[" .. tostring(t.safe or "") .. "]=],"
    .. "ride_safe=[=[" .. tostring(t.ride_safe or "") .. "]=],"
    .. "milestone=[=[" .. tostring(t.milestone or "") .. "]=],"
    .. "win=[=[" .. tostring(t.win or "") .. "]=],"
    .. "bonus_win=[=[" .. tostring(t.bonus_win or "") .. "]=],"
    .. "lose=[=[" .. tostring(t.lose or "") .. "]=],"
    .. "skipped=[=[" .. tostring(t.skipped or "") .. "]=],"
    .. "booted=[=[" .. tostring(t.booted or "") .. "]=],"
    .. "}"
    .. "}"
end

local function save_config()
  if script_write_text == nil then
    PORXIE.config_status = "Porxie config save failed (API unavailable)."
    return false
  end

  local ok = script_write_text(config_file_name(), export_config_blob()) == true
  PORXIE.config_status = ok and "Porxie config saved." or "Porxie config save failed."
  return ok
end

local function load_config()
  if script_read_text == nil then
    PORXIE.config_status = "Porxie config load skipped (API unavailable)."
    return false
  end

  local raw = script_read_text(config_file_name())
  if raw == nil or raw == "" then
    PORXIE.config_status = "Porxie config file not found."
    return false
  end

  local loader = loadstring or load
  local fn, err = loader(tostring(raw))
  if not fn then
    PORXIE.config_status = "Porxie config syntax error: " .. tostring(err)
    return false
  end

  local ok, data = pcall(fn)
  if not ok or type(data) ~= "table" then
    PORXIE.config_status = "Porxie config runtime error."
    return false
  end

  if data.pacing_delay_ms ~= nil then PORXIE.pacing_delay_ms = tonumber(data.pacing_delay_ms) or PORXIE.pacing_delay_ms end
  if data.show_help ~= nil then PORXIE.show_help = (data.show_help == true) end
  if type(data.chat_templates) == "table" then
    for k, v in pairs(data.chat_templates) do
      if PORXIE.chat_templates[tostring(k)] ~= nil then
        PORXIE.chat_templates[tostring(k)] = tostring(v or "")
      end
    end
  end

  PORXIE.config_status = "Porxie config loaded successfully."
  return true
end

-- Initialize configuration on first startup
if PORXIE._config_loaded ~= true then
  load_config()
  PORXIE._config_loaded = true
end

-- ============================================================================
-- Core Game Flow Actions
-- ============================================================================

local function start_next_player()
  if #PORXIE.queue == 0 then
    PORXIE.phase = "idle"
    PORXIE.active_player = nil
    PORXIE.status_text = "Queue empty. Open for new players!"
    return
  end

  local next_up = table.remove(PORXIE.queue, 1)
  local player = next_up.name
  local wager = next_up.wager
  local current_bank = (dealer_get_bank ~= nil) and (tonumber(dealer_get_bank(player)) or 0) or 0

  if wager <= 0 or current_bank < wager then
    send_table_chat("skipped", { player = player })
    start_next_player()
    return
  end

  if dealer_add_bank ~= nil then
    dealer_add_bank(player, -wager)
  end

  PORXIE.active_player = player
  PORXIE.active_wager = wager
  PORXIE.current_score = 0
  PORXIE.has_chosen_ride = false 
  PORXIE.phase = "waiting_roll"
  PORXIE.status_text = player .. " is active! Current score: 0/15"

  flush_old_rolls()
  send_table_chat("prompt", { player = player, total = 0, bet = wager })
end

local function execute_cash_out()
  local player = PORXIE.active_player
  local wager = PORXIE.active_wager
  local payout = math.floor(wager * 2)

  if dealer_add_bank ~= nil then dealer_add_bank(player, payout) end
  local bank = (dealer_get_bank ~= nil) and (tonumber(dealer_get_bank(player)) or 0) or 0
  
  send_table_chat("win", { player = player, total = PORXIE.current_score, payout = payout, bet = wager, bank = bank })
  
  PORXIE.games_played = PORXIE.games_played + 1
  PORXIE.games_won = PORXIE.games_won + 1
  start_next_player()
end

local function handle_score_update(roll)
  local player = PORXIE.active_player
  local wager = PORXIE.active_wager

  -- CRITICAL LOSS CONDITION: Rolled a 1
  if roll == 1 then
    local bank = (dealer_get_bank ~= nil) and (tonumber(dealer_get_bank(player)) or 0) or 0
    send_table_chat("lose", { player = player, roll = roll, bet = wager, bank = bank })
    
    PORXIE.games_played = PORXIE.games_played + 1
    start_next_player()
    return
  end

  PORXIE.current_score = PORXIE.current_score + roll

  -- ULTIMATE JACKPOT CONDITION: Reached 25+ points
  if PORXIE.current_score >= PORXIE.bonus_score then
    local payout = math.floor(wager * 3)
    if dealer_add_bank ~= nil then dealer_add_bank(player, payout) end
    local bank = (dealer_get_bank ~= nil) and (tonumber(dealer_get_bank(player)) or 0) or 0
    
    send_table_chat("bonus_win", { player = player, total = PORXIE.current_score, payout = payout, bet = wager, bank = bank })
    
    PORXIE.games_played = PORXIE.games_played + 1
    PORXIE.games_won = PORXIE.games_won + 1
    start_next_player()
    return
  end

  -- FIRST MILESTONE CHOICE: Reached 15+ points AND hasn't already decided to let it ride
  if PORXIE.current_score >= PORXIE.target_score and not PORXIE.has_chosen_ride then
    PORXIE.phase = "milestone_choice"
    PORXIE.status_text = player .. " hit milestone (" .. PORXIE.current_score .. "/15)! Awaiting decision."
    send_table_chat("milestone", { player = player, total = PORXIE.current_score, bet = wager })
    return
  end

  -- SAFE CONTINUATION ROUND: Still climbing.
  PORXIE.status_text = player .. " is at " .. PORXIE.current_score .. "/15 (Jackpot Goal: 25)"
  
  if PORXIE.has_chosen_ride then
    send_table_chat("ride_safe", { player = player, roll = roll, total = PORXIE.current_score, bet = wager })
  else
    send_table_chat("safe", { player = player, roll = roll, total = PORXIE.current_score, bet = wager })
  end
end

local function process_live_chat()
  if PORXIE.phase ~= "waiting_roll" or PORXIE.active_player == nil or chat_poll == nil then return end

  for _ = 1, 32 do
    local packet = chat_poll()
    if packet == nil or packet == "" then break end

    local speaker, _, _, msg = string.match(packet, "^([^|]*)|([^|]*)|([^|]*)|(.*)$")
    if speaker ~= nil and msg ~= nil then
      if clean_name(speaker) == clean_name(PORXIE.active_player) then
        local roll = parse_dice_d6(msg)
        if roll ~= nil then
          handle_score_update(roll)
          return
        end
      end
    end
  end
end

-- ============================================================================
-- Config GUI Tab Definition
-- ============================================================================
function draw_config_ui()
  ui_text_colored("Porxie Game Settings & Chat Templates", 0.5, 0.8, 1.0, 1.0)
  ui_separator()
  ui_text("File Status: " .. tostring(PORXIE.config_status))

  PORXIE.pacing_delay_ms = math.max(100, ui_input_int("Chat Pacing Delay (ms)##px_delay", tonumber(PORXIE.pacing_delay_ms) or 1200))
  
  ui_separator()
  ui_text_colored("Text Template Editor (Available: <player>, <bet>, <bank>, <roll>, <total>, <payout>)", 0.9, 0.9, 0.6, 1.0)
  
  local t = PORXIE.chat_templates or {}
  t.queued      = ui_input_text("Player Queued##px_tpl_q", t.queued or "", 512)
  t.prompt      = ui_input_text("Roll Invitation##px_tpl_p", t.prompt or "", 512)
  t.ride_prompt = ui_input_text("Jackpot Roll invitation##px_tpl_rp", t.ride_prompt or "", 512)
  t.safe        = ui_input_text("Standard Roll Outcome##px_tpl_s", t.safe or "", 512)
  t.ride_safe   = ui_input_text("Jackpot Sprint Roll##px_tpl_rs", t.ride_safe or "", 512)
  t.milestone   = ui_input_text("Milestone Reached (15+)##px_tpl_m", t.milestone or "", 512)
  t.win         = ui_input_text("Standard Cashout (2x)##px_tpl_w", t.win or "", 512)
  t.bonus_win   = ui_input_text("Super Payout Win (3x)##px_tpl_bw", t.bonus_win or "", 512)
  t.lose        = ui_input_text("Porxie Out Loss##px_tpl_l", t.lose or "", 512)
  t.skipped     = ui_input_text("Skipped Player##px_tpl_sk", t.skipped or "", 512)
  t.booted      = ui_input_text("Booted Player (Local Echo Only)##px_tpl_b", t.booted or "", 512)
  PORXIE.chat_templates = t

  ui_separator()
  if ui_button("Save Porxie Custom Config##px_save") then save_config() end
  ui_same_line()
  if ui_button("Reload Defaults/Saved File##px_load") then load_config() end
end

-- ============================================================================
-- Main Game Dealer Window Panel Hook
-- ============================================================================
function draw_ui()
  process_live_chat()

  local win_rate = 0
  if PORXIE.games_played > 0 then
    win_rate = math.floor((PORXIE.games_won / PORXIE.games_played) * 100)
  end

  -- FIXED: Truncated space buffer string down from ~80 characters to ~40 characters 
  -- This accurately slices the horizontal padding offset in half.
  local pad = "                                        "

  -- 1) MAIN TITLE
  ui_text(pad) 
  ui_same_line()
  ui_text_colored("  PORXIE - Sudden Death Dice Game", 1.0, 0.6, 0.8, 1.0)
  ui_separator()
  
  -- 2) ENGINE STATUS & LIVE WIN COUNTER
  ui_text(pad) 
  ui_same_line()
  ui_text("Status: " .. PORXIE.status_text)
  ui_same_line()
  ui_text_colored("  |  Win Rate: " .. win_rate .. "% (" .. PORXIE.games_won .. "/" .. PORXIE.games_played .. ")", 1.0, 0.85, 0.4, 1.0)
  ui_separator()

  -- 3) ACTIVE MATCH PANEL
  if PORXIE.active_player ~= nil then
    ui_text(pad)
    ui_same_line()
    ui_text_colored("Active Match Status:", 0.4, 0.8, 1.0, 1.0)
    
    ui_text(pad)
    ui_same_line()
    ui_text("Feeder: " .. PORXIE.active_player)
    
    ui_text(pad)
    ui_same_line()
    ui_text("Wager: " .. PORXIE.active_wager .. " gil")
    
    ui_text(pad)
    ui_same_line()
    ui_text("Porxie Satisfaction: " .. PORXIE.current_score .. " / " .. PORXIE.target_score .. " (Jackpot Goal: " .. PORXIE.bonus_score .. ")")
    
    -- DYNAMIC DECISION BUTTONS FOR THE DEALER
    if PORXIE.phase == "milestone_choice" then
      ui_text(pad)
      ui_same_line()
      ui_text_colored("  CHOOSE PLAYER PATH:", 1.0, 0.5, 0.2, 1.0)
      
      ui_text(pad)
      ui_same_line()
      if ui_button("Cash Out Player (2x)##px_co") then
        execute_cash_out()
      end
      ui_same_line()
      if ui_button("Let It Ride! (Push to 25)##px_ride") then
        PORXIE.has_chosen_ride = true 
        PORXIE.phase = "waiting_roll"
        PORXIE.status_text = PORXIE.active_player .. " chose to risk it all for 25 points!"
        flush_old_rolls()
        send_table_chat("ride_prompt", { player = PORXIE.active_player, total = PORXIE.current_score, bet = PORXIE.active_wager })
      end
    end

    ui_text(pad)
    ui_same_line()
    if ui_button("Boot Current Player##px_boot") then
      send_table_chat("booted", { player = PORXIE.active_player }, "echo")
      start_next_player()
    end
    ui_separator()
  end

  -- 4) VENUE GUEST ROSTER
  ui_text(pad)
  ui_same_line()
  ui_text_colored("Venue Guest List:", 0.7, 1.0, 0.7, 1.0)
  
  local count = (dealer_player_count ~= nil) and (tonumber(dealer_player_count()) or 0) or 0
  if count == 0 then
    ui_text(pad)
    ui_same_line()
    ui_text("(No players tracked in dealer roster window)")
  else
    for i = 1, count do
      local name = dealer_player_name(i)
      if name ~= nil and name ~= "" then
        local wager = (dealer_get_wager ~= nil) and (tonumber(dealer_get_wager(name)) or 0) or 0
        local bank = (dealer_get_bank ~= nil) and (tonumber(dealer_get_bank(name)) or 0) or 0
        
        ui_text(pad)
        ui_same_line()
        ui_text(name .. " | Bet: " .. wager .. " | Bank: " .. bank)
        ui_same_line()
        if ui_button("Queue##px_q_" .. name) then
          table.insert(PORXIE.queue, { name = name, wager = wager })
          send_table_chat("queued", { player = name, bet = wager, bank = bank })
          PORXIE.status_text = name .. " added to the menu wait list."
          
          if PORXIE.phase == "idle" then
            start_next_player()
          end
        end
      end
    end
  end

  ui_separator()
  
  -- 5) PORXIE QUEUE LINE
  ui_text(pad)
  ui_same_line()
  ui_text_colored("Porxie Queue Line:", 1.0, 1.0, 0.7, 1.0)
  if #PORXIE.queue == 0 then
    ui_text(pad)
    ui_same_line()
    ui_text("  (No players waiting to feed the Porxie)")
  else
    for idx, queued in ipairs(PORXIE.queue) do
      ui_text(pad)
      ui_same_line()
      ui_text("  " .. idx .. ") " .. queued.name .. " [Wager: " .. queued.wager .. "]")
    end
    
    ui_text(pad)
    ui_same_line()
    if ui_button("Flush Queue Line##clear_px_q") then
      PORXIE.queue = {}
      PORXIE.status_text = "Queue line cleared."
    end
  end
end

function on_command(cmd, ...)
  local c = string.lower(tostring(cmd or ""))
  if c == "porxiereset" then
    PORXIE.queue = {}
    PORXIE.active_player = nil
    PORXIE.phase = "idle"
    PORXIE.games_played = 0
    PORXIE.games_won = 0
    PORXIE.status_text = "Game table and session win rate stats hard-reset."
    return "ok"
  end
  return "unknown"
end

return PORXIE
