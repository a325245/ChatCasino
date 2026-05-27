-- ============================================================================
-- Gobble 1.0
-- by Irie
-- Three random birds are rolled, the player has 5 chances to roll higher than 
-- those numbers.
-- ============================================================================

if GOBBLE == nil then
  GOBBLE = {
    phase = "idle",          -- States: "idle", "hatching", "waiting_roll"
    status_text = "Queue a player to open the stables!",
    config_status = "Gobble config not loaded yet.",
    
    queue = {},              -- Holds players waiting to play: { name, wager }
    active_player = nil,     -- Name of the person currently rolling
    active_wager = 0,        -- The bet amount for the current round
    stable = {},             -- Array of active bird hunger numbers (e.g. {5, 12, 17})
    chances_left = 5,        -- Total rolls allowed per round

    pacing_delay_ms = 1200,  -- Slight buffer between text prints
    next_chat_at = 0,        -- Anti-spam tracking
    show_help = true,

    -- Asynchronous Chat Automation State Tracking
    auto_hatch_queue = 0,    -- Tracks remaining automated setup rolls to fire
    next_auto_roll_at = 0,   -- Millisecond timestamp for the next paced roll
    expecting_proxy_roll = false, -- Safety tracking variable

    -- Live Win Rate Tracker Stats
    games_played = 0,
    games_won = 0,

    -- RTP Tracking
    rtp_rounds = 0,
    rtp_wagered = 0,
    rtp_paid = 0,
    rtp_last_round_id = 0,

    chat_templates = {
      queued       = "  <player> queued up for Gobble! Bet: <bet> gil.",
      setup_prompt = "  Preparing the stables for <player>! Hatching three Chocobos...",
      prompt       = "  Stables Open! Chocobos: <birds> | ⏳ Chances: <chances> | <player>, roll /dice party 18 to feed them! Target or ABOVE hits!",
      hit          = "  Yum! <player> rolled a <roll> and stuffed the [<target>] Chocobo! Remaining: <birds> | ⏳ Chances: <chances>.",
      miss         = "  Oof! <player> rolled a <roll>. Too low to feed anyone! Remaining: <birds> | ⏳ Chances: <chances> left!",
      win          = "  STABLE CLEARED! <player> fed all the Chocobos and cashed out! Paid <payout> gil (2x)! New Bank: <bank>.",
      lose         = "  Out of chances! The hungry Chocobos chased <player> out of the stable! Lost <bet> gil. New Bank: <bank>.",
      skipped      = "<player> removed from stable queue (invalid wager or insufficient bank).",
      booted       = "[Gobble Admin] <player> has been escorted out of the active Chocobo stable."
    }
  }
end

-- ============================================================================
-- Configuration & File IO
-- ============================================================================

local function config_file_name()
  return "Gobble.config.json"
end

local function export_config_blob()
  local t = GOBBLE.chat_templates or {}
  return "return {"
    .. "pacing_delay_ms=" .. tostring(math.floor(tonumber(GOBBLE.pacing_delay_ms) or 1200)) .. ","
    .. "show_help=" .. tostring(GOBBLE.show_help == true) .. ","
    .. "chat_templates={"
    .. "queued=[=[" .. tostring(t.queued or "") .. "]=],"
    .. "setup_prompt=[=[" .. tostring(t.setup_prompt or "") .. "]=],"
    .. "prompt=[=[" .. tostring(t.prompt or "") .. "]=],"
    .. "hit=[=[" .. tostring(t.hit or "") .. "]=],"
    .. "miss=[=[" .. tostring(t.miss or "") .. "]=],"
    .. "win=[=[" .. tostring(t.win or "") .. "]=],"
    .. "lose=[=[" .. tostring(t.lose or "") .. "]=],"
    .. "skipped=[=[" .. tostring(t.skipped or "") .. "]=],"
    .. "booted=[=[" .. tostring(t.booted or "") .. "]=],"
    .. "}"
    .. "}"
end

local function apply_config_table(data)
  if type(data) ~= "table" then return false end

  if data.pacing_delay_ms ~= nil then GOBBLE.pacing_delay_ms = tonumber(data.pacing_delay_ms) or GOBBLE.pacing_delay_ms end
  if data.show_help ~= nil then GOBBLE.show_help = (data.show_help == true) end

  if type(data.chat_templates) == "table" then
    local t = GOBBLE.chat_templates or {}
    for k, v in pairs(data.chat_templates) do
      t[tostring(k)] = tostring(v or "")
    end
    GOBBLE.chat_templates = t
  end
  return true
end

local function save_config()
  if script_write_text == nil then
    GOBBLE.config_status = "Config save skipped (host API unavailable)."
    return false
  end
  local ok = script_write_text(config_file_name(), export_config_blob()) == true
  if ok then
    GOBBLE.config_status = "Gobble config saved successfully!"
  else
    GOBBLE.config_status = "Error writing out config file."
  end
  if chat_send ~= nil then chat_send("echo", GOBBLE.config_status) end
  return ok
end

local function load_config()
  if script_read_text == nil then
    GOBBLE.config_status = "Config load skipped (host API unavailable)."
    return false
  end
  local raw = script_read_text(config_file_name())
  if raw == nil or raw == "" then
    GOBBLE.config_status = "Config file not found."
    return false
  end
  local loader = loadstring or load
  local fn, err = loader(tostring(raw))
  if not fn then
    GOBBLE.config_status = "Config syntax error: " .. tostring(err)
    return false
  end
  local ok, data = pcall(fn)
  if not ok then
    GOBBLE.config_status = "Config runtime error: " .. tostring(data)
    return false
  end
  if not apply_config_table(data) then
    GOBBLE.config_status = "Config invalid payload."
    return false
  end
  GOBBLE.config_status = "Gobble config loaded successfully."
  if chat_send ~= nil then chat_send("echo", GOBBLE.config_status) end
  return true
end

if GOBBLE._config_loaded ~= true then
  load_config()
  GOBBLE._config_loaded = true
end

-- ============================================================================
-- RTP Logging
-- ============================================================================

local function rtp_log_file_name()
  return "Gobble.rtp.csv"
end

local function csv_escape(v)
  local s = tostring(v or "")
  s = string.gsub(s, '"', '""')
  return '"' .. s .. '"'
end

local function append_rtp_log_row(row)
  if script_read_text == nil or script_write_text == nil then return false end
  if type(row) ~= "table" then return false end

  local header = "timestamp_ms,round_id,player,wager,payout,net,result\n"
  local line = table.concat({
    tostring(math.floor(tonumber(row.timestamp_ms) or 0)),
    tostring(math.floor(tonumber(row.round_id) or 0)),
    csv_escape(row.player),
    tostring(math.floor(tonumber(row.wager) or 0)),
    tostring(math.floor(tonumber(row.payout) or 0)),
    tostring(math.floor(tonumber(row.net) or 0)),
    csv_escape(row.result)
  }, ",") .. "\n"

  local existing = script_read_text(rtp_log_file_name()) or ""
  if existing == "" then
    return script_write_text(rtp_log_file_name(), header .. line) == true
  end
  return script_write_text(rtp_log_file_name(), existing .. line) == true
end

local function record_rtp_result(player, wager, payout, result)
  local w = math.floor(math.max(0, tonumber(wager) or 0))
  local p = math.floor(math.max(0, tonumber(payout) or 0))
  GOBBLE.rtp_wagered = math.floor((tonumber(GOBBLE.rtp_wagered) or 0) + w)
  GOBBLE.rtp_paid = math.floor((tonumber(GOBBLE.rtp_paid) or 0) + p)

  append_rtp_log_row({
    timestamp_ms = (time_ms ~= nil) and (tonumber(time_ms()) or 0) or 0,
    round_id = tonumber(GOBBLE.rtp_last_round_id) or 0,
    player = tostring(player or ""),
    wager = w,
    payout = p,
    net = p - w,
    result = tostring(result or "")
  })
end


-- ============================================================================
-- Utility & Token Formatting Helpers
-- ============================================================================

local function get_stable_string()
  if #GOBBLE.stable == 0 then return "None" end
  local formatted = {}
  for _, v in ipairs(GOBBLE.stable) do
    table.insert(formatted, "[" .. v .. "]")
  end
  return table.concat(formatted, " ")
end

local function fmt(template, ctx)
  local msg = tostring(template or "")
  local values = {
    ["<player>"]      = tostring((ctx and ctx.player) or ""),
    ["<bet>"]         = tostring((ctx and ctx.bet) or 0),
    ["<bank>"]        = tostring((ctx and ctx.bank) or 0),
    ["<roll>"]        = tostring((ctx and ctx.roll) or 0),
    ["<payout>"]      = tostring((ctx and ctx.payout) or 0),
    ["<birds>"]       = get_stable_string(),
    ["<chances>"]     = tostring(GOBBLE.chances_left),
    ["<target>"]      = tostring((ctx and ctx.target) or 0),
  }
  for token, value in pairs(values) do
    msg = string.gsub(msg, token, value)
  end
  return msg
end

local function execute_chat_out(route, text)
  if chat_send ~= nil then
    chat_send(route, text)
  elseif route == "echo" and dealer_echo ~= nil then
    dealer_echo(text)
  elseif dealer_party ~= nil then
    dealer_party(text)
  end
end

local function send_table_chat(key, ctx, target_override)
  local t = GOBBLE.chat_templates or {}
  local template = t[key]
  if template == nil or template == "" then return end
  
  local text = fmt(template, ctx)
  local now = (time_ms ~= nil) and tonumber(time_ms()) or 0
  local route = target_override or "party"
  
  if GOBBLE.next_chat_at < now then 
    GOBBLE.next_chat_at = now 
  end
  
  execute_chat_out(route, text)
  GOBBLE.next_chat_at = GOBBLE.next_chat_at + GOBBLE.pacing_delay_ms
end

local function flush_old_rolls()
  if chat_poll == nil then return end
  for _ = 1, 100 do
    local packet = chat_poll()
    if packet == nil or packet == "" then break end
  end
end

local function parse_dice_d18(message)
  if message == nil then return nil end
  if dice_roll_value ~= nil and dice_roll_upper ~= nil then
    local val = tonumber(dice_roll_value(message)) or 0
    local max = tonumber(dice_roll_upper(message)) or 0
    if val >= 1 and max == 18 then return val end
  end

  local fallback = tonumber(string.match(tostring(message), "[Rr]olls?%s+(%d+)%s*%(%s*1%-%s*18%s*%)"))
  if fallback ~= nil and fallback >= 1 and fallback <= 18 then 
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
-- Core Game Flow Actions
-- ============================================================================

local function execute_raw_roll()
  GOBBLE.expecting_proxy_roll = true

  if chat_command ~= nil then
    chat_command("/dice party 18")
    return
  end

  if dice_roll ~= nil then
    local success = pcall(function() dice_roll(1, 18) end)
    if success then return end

    success = pcall(function() dice_roll("party", 1, 18) end)
    if success then return end
  end

  if chat_send ~= nil then
    chat_send("party", "/dice party 18")
  end
end

local function start_next_player()
  if #GOBBLE.queue == 0 then
    GOBBLE.phase = "idle"
    GOBBLE.active_player = nil
    GOBBLE.status_text = "Stable empty. Ready for new feeders!"
    return
  end

  local next_up = table.remove(GOBBLE.queue, 1)
  local player = next_up.name
  local wager = next_up.wager
  local current_bank = (dealer_get_bank ~= nil) and (tonumber(dealer_get_bank(player)) or 0) or 0

  if wager <= 0 or current_bank < wager then
    send_table_chat("skipped", { player = player })
    record_rtp_result(player, wager, 0, "skipped")
    start_next_player()
    return
  end

  if dealer_add_bank ~= nil then
    dealer_add_bank(player, -wager)
  end

  GOBBLE.stable = {}
  GOBBLE.active_player = player
  GOBBLE.active_wager = wager
  GOBBLE.chances_left = 5
  
  GOBBLE.auto_hatch_queue = 0
  GOBBLE.next_auto_roll_at = 0
  GOBBLE.expecting_proxy_roll = false

  GOBBLE.phase = "hatching"
  GOBBLE.status_text = "Preparing the stables..."

  flush_old_rolls()
  send_table_chat("setup_prompt", { player = player, bet = wager })
end

local function handle_stable_feed(roll)
  local player = GOBBLE.active_player
  local wager = GOBBLE.active_wager
  GOBBLE.chances_left = GOBBLE.chances_left - 1

  local matched_idx = nil
  local target_hunger = 0

  for i = #GOBBLE.stable, 1, -1 do
    if roll >= GOBBLE.stable[i] then
      matched_idx = i
      target_hunger = GOBBLE.stable[i]
      break
    end
  end

  if matched_idx ~= nil then
    table.remove(GOBBLE.stable, matched_idx)
    
    if #GOBBLE.stable == 0 then
      GOBBLE.rtp_last_round_id = (tonumber(GOBBLE.rtp_last_round_id) or 0) + 1
      GOBBLE.rtp_rounds = (tonumber(GOBBLE.rtp_rounds) or 0) + 1

      local payout = math.floor(wager * 2)
      if dealer_add_bank ~= nil then dealer_add_bank(player, payout) end
      local bank = (dealer_get_bank ~= nil) and (tonumber(dealer_get_bank(player)) or 0) or 0
      
      send_table_chat("win", { player = player, payout = payout, bank = bank })
      GOBBLE.games_played = GOBBLE.games_played + 1
      GOBBLE.games_won = GOBBLE.games_won + 1
      record_rtp_result(player, wager, payout, "wins")
      
      start_next_player()
      return
    else
      GOBBLE.status_text = player .. " fed a [" .. target_hunger .. "]! Remaining Chocobos: " .. get_stable_string()
      send_table_chat("hit", { player = player, roll = roll, target = target_hunger })
    end
  else
    GOBBLE.status_text = "Miss! Roll " .. roll .. " was too weak. Remaining Chocobos: " .. get_stable_string()
    send_table_chat("miss", { player = player, roll = roll })
  end

  if GOBBLE.chances_left <= 0 and #GOBBLE.stable > 0 then
    GOBBLE.rtp_last_round_id = (tonumber(GOBBLE.rtp_last_round_id) or 0) + 1
    GOBBLE.rtp_rounds = (tonumber(GOBBLE.rtp_rounds) or 0) + 1

    local bank = (dealer_get_bank ~= nil) and (tonumber(dealer_get_bank(player)) or 0) or 0
    send_table_chat("lose", { player = player, bet = wager, bank = bank })
    GOBBLE.games_played = GOBBLE.games_played + 1
    record_rtp_result(player, wager, 0, "loses")
    
    start_next_player()
    return
  end
end

-- ============================================================================
-- Chat Engine Processing Loop
-- ============================================================================

local function process_live_chat()
  local now = (time_ms ~= nil) and tonumber(time_ms()) or 0

  if GOBBLE.auto_hatch_queue > 0 and now >= GOBBLE.next_auto_roll_at then
    GOBBLE.auto_hatch_queue = GOBBLE.auto_hatch_queue - 1
    GOBBLE.next_auto_roll_at = now + 1200 -- 1200ms delay to safely space them out
    execute_raw_roll()
  end

  if GOBBLE.phase == "idle" or chat_poll == nil then return end

  for _ = 1, 32 do
    local packet = chat_poll()
    if packet == nil or packet == "" then break end

    local speaker, _, _, msg = string.match(packet, "^([^|]*)|([^|]*)|([^|]*)|(.*)$")
    if speaker ~= nil and msg ~= nil then
      local roll = parse_dice_d18(msg)

      if roll ~= nil then
        if GOBBLE.phase == "hatching" then
          table.insert(GOBBLE.stable, roll)
          GOBBLE.status_text = "Hatching stables... (" .. #GOBBLE.stable .. "/3)"
          
          if #GOBBLE.stable >= 3 then
            table.sort(GOBBLE.stable)
            
            -- Stop any lingering auto queues cleanly
            GOBBLE.auto_hatch_queue = 0 
            GOBBLE.expecting_proxy_roll = false
            
            GOBBLE.phase = "waiting_roll"
            GOBBLE.status_text = GOBBLE.active_player .. " is inside the stable! d18 Chocobo targets set."
            send_table_chat("prompt", { player = GOBBLE.active_player, bet = GOBBLE.active_wager })
          end
          return

        elseif GOBBLE.phase == "waiting_roll" then
          local clean_speaker = clean_name(speaker)
          local clean_guest = clean_name(GOBBLE.active_player)
          
          local is_guest = (clean_speaker == clean_guest)
          local is_dealer = false
          
          if GOBBLE.expecting_proxy_roll == true then
            is_dealer = true
          else
            if dealer_player_name ~= nil then
              local self_name = dealer_player_name(0) or dealer_player_name("self")
              if self_name ~= nil and self_name ~= "" then
                if clean_speaker == clean_name(self_name) then
                  is_dealer = true
                end
              end
            end
          end

          if is_guest or is_dealer then
            GOBBLE.expecting_proxy_roll = false
            handle_stable_feed(roll)
            return
          else
            if log ~= nil then
              log("[Gobble Guard] Ignored unauthenticated d18 roll from: " .. speaker)
            end
          end
        end
      end
      
    end
  end
end

-- ============================================================================
-- Config GUI Tab Definition
-- ============================================================================
function draw_config_ui()
  ui_text_colored("Gobble Settings & Chat Templates", 0.5, 0.8, 1.0, 1.0)
  ui_separator()
  ui_text("File Status: " .. tostring(GOBBLE.config_status))

  GOBBLE.pacing_delay_ms = math.max(100, ui_input_int("Chat Pacing Delay (ms)##gb_delay", tonumber(GOBBLE.pacing_delay_ms) or 1200))
  
  ui_separator()
  ui_text_colored("Text Template Editor (Available: <player>, <bet>, <bank>, <roll>, <birds>, <chances>, <target>, <payout>)", 0.9, 0.9, 0.6, 1.0)
  
  local t = GOBBLE.chat_templates or {}
  t.queued       = ui_input_text("Player Queued##gb_tpl_q", t.queued or "", 512)
  t.setup_prompt = ui_input_text("Dealer Setup Request##gb_tpl_sp", t.setup_prompt or "", 512)
  t.prompt       = ui_input_text("Stable Invitation##gb_tpl_p", t.prompt or "", 512)
  t.hit          = ui_input_text("Successful Feed##gb_tpl_h", t.hit or "", 512)
  t.miss         = ui_input_text("Failed Feed (Miss)##gb_tpl_m", t.miss or "", 512)
  t.win          = ui_input_text("Clean Sweep Win (2x)##gb_tpl_w", t.win or "", 512)
  t.lose         = ui_input_text("Out of Turns Loss##gb_tpl_l", t.lose or "", 512)
  t.skipped      = ui_input_text("Skipped Player##gb_tpl_sk", t.skipped or "", 512)
  t.booted       = ui_input_text("Booted Player (Local Echo)##gb_tpl_b", t.booted or "", 512)
  GOBBLE.chat_templates = t

  ui_separator()
  if ui_button("Save Gobble Custom Config##gb_save") then save_config() end
  ui_same_line()
  if ui_button("Reload Defaults/Saved File##gb_load") then load_config() end
end

-- ============================================================================
-- Main Game Dealer Window Panel Hook
-- ============================================================================
function draw_ui()
  process_live_chat()

  local win_rate = 0
  if GOBBLE.games_played > 0 then
    win_rate = math.floor((GOBBLE.games_won / GOBBLE.games_played) * 100)
  end

  local pad = "                                        "

  -- 1) MAIN TITLE
  ui_text(pad) 
  ui_same_line()
  ui_text_colored(" GOBBLE", 1.0, 0.8, 0.2, 1.0)
  ui_separator()
  
  -- 2) ENGINE STATUS & LIVE STATS
  ui_text(pad) 
  ui_same_line()
  ui_text("Status: " .. GOBBLE.status_text)
  ui_same_line()
  ui_text_colored("  |  Win Rate: " .. win_rate .. "% (" .. GOBBLE.games_won .. "/" .. GOBBLE.games_played .. ")", 1.0, 0.85, 0.4, 1.0)
  ui_separator()

  -- 3) ACTIVE MATCH PANEL
  if GOBBLE.active_player ~= nil then
    ui_text(pad)
    ui_same_line()
    ui_text_colored("Chocobo Stable Status:", 0.4, 0.8, 1.0, 1.0)
    
    ui_text(pad)
    ui_same_line()
    ui_text("Active Feeder: " .. GOBBLE.active_player)
    
    ui_text(pad)
    ui_same_line()
    ui_text("Wager: " .. GOBBLE.active_wager .. " gil")
    
    ui_text(pad)
    ui_same_line()
    if GOBBLE.phase == "hatching" then
      ui_text_colored("Hatching Progress: " .. get_stable_string() .. " (" .. #GOBBLE.stable .. "/3 Complete)", 1.0, 0.5, 0.2, 1.0)
      
      ui_text(pad)
      ui_same_line()
      if ui_button(" Auto-Hatch Stables##gb_macro") then
        local now = (time_ms ~= nil) and tonumber(time_ms()) or 0
        -- Triggers 3 total rolls spaced cleanly out at 1200ms
        GOBBLE.auto_hatch_queue = 2 
        GOBBLE.next_auto_roll_at = now + 1200
        execute_raw_roll() 
      end
    else
      ui_text("Hungry Chocobos Left: " .. get_stable_string())
      ui_text(pad)
      ui_same_line()
      ui_text("Dice Rolls Remaining: " .. GOBBLE.chances_left .. " / 5")
      
      ui_text(pad)
      ui_same_line()
      if ui_button("  Inject d18 Roll On Behalf of " .. GOBBLE.active_player .. "##gb_proxy") then
        execute_raw_roll()
      end
    end
    
    ui_text(pad)
    ui_same_line()
    if ui_button("Boot Current Feeder##gb_boot") then
      send_table_chat("booted", { player = GOBBLE.active_player }, "echo")
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
        if ui_button("Queue##gb_q_" .. name) then
          table.insert(GOBBLE.queue, { name = name, wager = wager })
          send_table_chat("queued", { player = name, bet = wager, bank = bank })
          GOBBLE.status_text = name .. " queued up for the stables."
          
          if GOBBLE.phase == "idle" then
            start_next_player()
          end
        end
      end
    end
  end

  ui_separator()
  
  -- 5) STABLE QUEUE LINE
  ui_text(pad)
  ui_same_line()
  ui_text_colored("Stable Queue Line:", 1.0, 1.0, 0.7, 1.0)
  if #GOBBLE.queue == 0 then
    ui_text(pad)
    ui_same_line()
    ui_text("  (No players waiting outside the pen)")
  else
    for idx, queued in ipairs(GOBBLE.queue) do
      ui_text(pad)
      ui_same_line()
      ui_text("  " .. idx .. ") " .. queued.name .. " [Wager: " .. queued.wager .. "]")
    end
    
    ui_text(pad)
    ui_same_line()
    if ui_button("Flush Stable Queue##clear_gb_q") then
      GOBBLE.queue = {}
      GOBBLE.status_text = "Queue line cleared."
    end
  end

  ui_separator()
  
  -- 6) RTP READOUT
  local wagered = tonumber(GOBBLE.rtp_wagered) or 0
  local paid = tonumber(GOBBLE.rtp_paid) or 0
  local rounds = tonumber(GOBBLE.rtp_rounds) or 0
  local rtp = (wagered > 0) and ((paid / wagered) * 100.0) or 0
  ui_text(string.format(
    "Return To Player: %.2f%% | Rounds: %d | Gil In: %d | Gil Out: %d",
    rtp,
    math.floor(rounds),
    math.floor(wagered),
    math.floor(paid)
  ))
end

function on_command(cmd, ...)
  local c = string.lower(tostring(cmd or ""))
  if c == "gobblereset" then
    GOBBLE.queue = {}
    GOBBLE.active_player = nil
    GOBBLE.phase = "idle"
    GOBBLE.games_played = 0
    GOBBLE.games_won = 0
    GOBBLE.status_text = "Stable tables and tracking session cleared."
    return "ok"
  end
  return "unknown"
end
