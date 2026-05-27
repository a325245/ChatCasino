----------------------------------------
-- Slots 777 1.0
-- Players wager and roll a /dice party
-- 565 or higher, 2x win
-- 950 or higher, 3x win
-- 999 4x win, 777 5x win
----------------------------------------

if S777 == nil then
  -- Persistent script state table.
  -- This survives frame-to-frame while the script stays loaded.
  S777 = {
    -- High-level game state:
    -- idle         = no active spinner
    -- waiting_roll = one spinner is active, waiting for player's /dice result
    phase = "idle",
    info = "Queue a player to begin.",

    -- Queue of pending spins (dealer queues players via button).
    queue = {},
    -- Current active spin payload: { player = <name>, bet = <wager> }
    active_spin = nil,

    -- Standard pacing delay used for queued chat and between spin handoffs.
    -- Default requested: 2000ms.
    pacing_delay_ms = 2000,
    pending_chat = {},
    next_chat_at = 0,
    next_spin_at = 0,

    -- Payout thresholds.
    -- Multipliers are TOTAL payout multipliers (not net profit multipliers).
    -- Example: bet=100 and x2 => +200 payout after bet was already deducted.
    min_win_roll = 565,
    high_win_roll = 950,
    ultra_roll = 999,
    jackpot_roll = 777,

    -- Reserved UI state.
    selected_player = "",
    show_help = true,
    config_status = "Slots777 config not loaded yet.",

    -- Chat templates (editable in config UI).
    chat_templates = {
      queued = "<player> queued for Slots777. Bet <bet>.",
      prompt = "<player>, roll /dice party now for Slots777!",
      win = "<player> rolled <roll> and hit x<mult>! Paid <payout>. Bank <bank>.",
      lose = "<player> rolled <roll>. No hit. Lost <bet>. Bank <bank>.",
      skipped = "<player> removed from queue (invalid wager or insufficient bank).",
      booted = "<player> was booted from Slots777 queue/turn.",
    },
    
    -- RTP Tracking
    rtp_rounds = 0,
    rtp_wagered = 0,
    rtp_paid = 0,
    rtp_last_round_id = 0,
  }
end

-- ============================================================================
-- CONFIG PERSISTENCE (JSON-like save blob)
-- ============================================================================

-- Function: config_file_name
-- Purpose: Handles config file name logic for the Slots777 script.
local function config_file_name()
  return "Slots777.config.json"
end

-- Function: bool_to_json
-- Purpose: Handles bool to json logic for the Slots777 script.
local function bool_to_json(v)
  return (v == true) and "true" or "false"
end

-- Function: echo_notice
-- Purpose: Handles echo notice logic for the Slots777 script.
local function echo_notice(msg)
  local text = tostring(msg or "")
  if text == "" then return end
  if chat_send ~= nil then
    chat_send("echo", text)
  elseif dealer_party ~= nil then
    dealer_party(text)
  end
end

-- Function: esc_json
-- Purpose: Handles esc json logic for the Slots777 script.
local function esc_json(s)
  local t = tostring(s or "")
  t = string.gsub(t, "\\", "\\\\")
  t = string.gsub(t, '"', '\\"')
  t = string.gsub(t, "\r", "\\r")
  t = string.gsub(t, "\n", "\\n")
  return t
end

-- Function: json_get_number
-- Purpose: Handles json get number logic for the Slots777 script.
local function json_get_number(src, key)
  local p = '"' .. key .. '"%s*:%s*(-?%d+)' 
  local n = string.match(src or "", p)
  return tonumber(n)
end

-- Function: json_get_bool
-- Purpose: Handles json get bool logic for the Slots777 script.
local function json_get_bool(src, key)
  local p = '"' .. key .. '"%s*:%s*(true|false)'
  local b = string.match(src or "", p)
  if b == "true" then return true end
  if b == "false" then return false end
  return nil
end

-- Function: json_get_string
-- Purpose: Handles json get string logic for the Slots777 script.
local function json_get_string(src, key)
  local p = '"' .. key .. '"%s*:%s*"(.-)"'
  local raw = string.match(src or "", p)
  if raw == nil then return nil end
  raw = string.gsub(raw, "\\n", "\n")
  raw = string.gsub(raw, "\\r", "\r")
  raw = string.gsub(raw, '\\"', '"')
  raw = string.gsub(raw, "\\\\", "\\")
  return raw
end

-- Function: build_config_json
-- Purpose: Handles build config json logic for the Slots777 script.
local function build_config_json()
  local t = S777.chat_templates or {}
  local parts = {
    "{",
    '"pacing_delay_ms":' .. tostring(math.floor(tonumber(S777.pacing_delay_ms) or 2000)) .. ",",
    '"min_win_roll":' .. tostring(math.floor(tonumber(S777.min_win_roll) or 565)) .. ",",
    '"high_win_roll":' .. tostring(math.floor(tonumber(S777.high_win_roll) or 950)) .. ",",
    '"ultra_roll":' .. tostring(math.floor(tonumber(S777.ultra_roll) or 999)) .. ",",
    '"jackpot_roll":' .. tostring(math.floor(tonumber(S777.jackpot_roll) or 777)) .. ",",
    '"show_help":' .. bool_to_json(S777.show_help == true) .. ",",
    '"chat_templates":{',
    '"queued":"' .. esc_json(t.queued or "") .. '",',
    '"prompt":"' .. esc_json(t.prompt or "") .. '",',
    '"win":"' .. esc_json(t.win or "") .. '",',
    '"lose":"' .. esc_json(t.lose or "") .. '",',
    '"skipped":"' .. esc_json(t.skipped or "") .. '",',
    '"booted":"' .. esc_json(t.booted or "") .. '"',
    "}",
    "}"
  }
  return table.concat(parts, "")
end

-- Function: save_config
-- Purpose: Saves config data from runtime state.
local function save_config()
  if script_write_text == nil then
    S777.info = "Slots777 config save failed (host file API unavailable)."
    S777.config_status = S777.info
    return false
  end
  local ok = script_write_text(config_file_name(), build_config_json()) == true
  if ok then
    S777.info = "Slots777 config saved."
    S777.config_status = S777.info
    echo_notice(S777.info)
  else
    S777.info = "Slots777 config save failed (unable to write file)."
    S777.config_status = S777.info
    echo_notice(S777.info)
  end
  return ok
end

-- Function: load_config
-- Purpose: Loads config data into runtime state.
local function load_config()
  if script_read_text == nil then
    S777.config_status = "Slots777 config load skipped (host file API unavailable)."
    return false
  end
  local raw = script_read_text(config_file_name())
  if raw == nil or raw == "" then
    S777.config_status = "Slots777 config file not found."
    return false
  end

  local pacing = json_get_number(raw, "pacing_delay_ms")
  if pacing ~= nil then S777.pacing_delay_ms = pacing end
  local minWin = json_get_number(raw, "min_win_roll")
  if minWin ~= nil then S777.min_win_roll = minWin end
  local highWin = json_get_number(raw, "high_win_roll")
  if highWin ~= nil then S777.high_win_roll = highWin end
  local ultra = json_get_number(raw, "ultra_roll")
  if ultra ~= nil then S777.ultra_roll = ultra end
  local jackpot = json_get_number(raw, "jackpot_roll")
  if jackpot ~= nil then S777.jackpot_roll = jackpot end
  local showHelp = json_get_bool(raw, "show_help")
  if showHelp ~= nil then S777.show_help = showHelp end

  local t = S777.chat_templates or {}
  local v
  v = json_get_string(raw, "queued"); if v ~= nil then t.queued = v end
  v = json_get_string(raw, "prompt"); if v ~= nil then t.prompt = v end
  v = json_get_string(raw, "win"); if v ~= nil then t.win = v end
  v = json_get_string(raw, "lose"); if v ~= nil then t.lose = v end
  v = json_get_string(raw, "skipped"); if v ~= nil then t.skipped = v end
  v = json_get_string(raw, "booted"); if v ~= nil then t.booted = v end
  S777.chat_templates = t

  -- Normalize loaded values into safe ranges.
  local pd = tonumber(S777.pacing_delay_ms) or 2000
  if pd < 100 then pd = 100 end
  if pd > 15000 then pd = 15000 end
  S777.pacing_delay_ms = math.floor(pd)
  S777.min_win_roll = math.max(1, math.min(1000, tonumber(S777.min_win_roll) or 565))
  S777.high_win_roll = math.max(S777.min_win_roll, math.min(1000, tonumber(S777.high_win_roll) or 950))
  S777.ultra_roll = math.max(1, math.min(1000, tonumber(S777.ultra_roll) or 999))
  S777.jackpot_roll = math.max(1, math.min(1000, tonumber(S777.jackpot_roll) or 777))

  S777.info = "Slots777 config loaded."
  S777.config_status = S777.info
  echo_notice(S777.info)
  return true
end

if S777._config_loaded ~= true then
  load_config()
  S777._config_loaded = true
end

-- ============================================================================
-- RTP LOGGING
-- ============================================================================

-- Function: rtp_log_file_name
-- Purpose: Returns the CSV log filename used for Slots777 settlement output.
local function rtp_log_file_name()
  return "Slots777.rtp.csv"
end

-- Function: csv_escape
-- Purpose: Escapes CSV field values for safe append operations.
local function csv_escape(v)
  local s = tostring(v or "")
  s = string.gsub(s, '"', '""')
  return '"' .. s .. '"'
end

-- Function: append_rtp_log_row
-- Purpose: Appends one settled Slots777 player result to RTP CSV.
local function append_rtp_log_row(row)
  if script_read_text == nil or script_write_text == nil then return false end
  if type(row) ~= "table" then return false end

  local header = "timestamp_ms,round_id,player,wager,payout,net,result,roll,multiplier\n"
  local line = table.concat({
    tostring(math.floor(tonumber(row.timestamp_ms) or 0)),
    tostring(math.floor(tonumber(row.round_id) or 0)),
    csv_escape(row.player),
    tostring(math.floor(tonumber(row.wager) or 0)),
    tostring(math.floor(tonumber(row.payout) or 0)),
    tostring(math.floor(tonumber(row.net) or 0)),
    csv_escape(row.result),
    tostring(math.floor(tonumber(row.roll) or 0)),
    tostring(math.floor(tonumber(row.multiplier) or 0))
  }, ",") .. "\n"

  local existing = script_read_text(rtp_log_file_name()) or ""
  if existing == "" then
    return script_write_text(rtp_log_file_name(), header .. line) == true
  end
  return script_write_text(rtp_log_file_name(), existing .. line) == true
end

-- Function: record_rtp_result
-- Purpose: Updates RTP counters and writes one CSV row for a settled player result.
local function record_rtp_result(player, wager, payout, result, roll, multiplier)
  local w = math.floor(math.max(0, tonumber(wager) or 0))
  local p = math.floor(math.max(0, tonumber(payout) or 0))
  S777.rtp_wagered = math.floor((tonumber(S777.rtp_wagered) or 0) + w)
  S777.rtp_paid = math.floor((tonumber(S777.rtp_paid) or 0) + p)

  append_rtp_log_row({
    timestamp_ms = (time_ms ~= nil) and (tonumber(time_ms()) or 0) or 0,
    round_id = tonumber(S777.rtp_last_round_id) or 0,
    player = tostring(player or ""),
    wager = w,
    payout = p,
    net = p - w,
    result = tostring(result or ""),
    roll = tonumber(roll) or 0,
    multiplier = tonumber(multiplier) or 0
  })
end


-- Drain any already-buffered chat packets.
-- This is called when a new active spinner is selected so old/stale /dice lines
-- from before queue time cannot be consumed as that player's current roll.
-- Function: flush_chat_buffer
-- Purpose: Handles flush chat buffer logic for the Slots777 script.
local function flush_chat_buffer()
  if chat_poll == nil then return end
  for _ = 1, 500 do
    local packet = chat_poll()
    if packet == nil or packet == "" then break end
  end
end

-- Resolve which channel should be used for outgoing script messages.
-- Function: output_channel_name
-- Purpose: Resolves the chat channel that this script should use for output.
local function output_channel_name()
  if default_chat_channel ~= nil then
    local ch = default_chat_channel()
    if ch == "echo" or ch == "say" or ch == "party" or ch == "shout" or ch == "yell" then
      return ch
    end
  end
  return "party"
end

-- Clamp pacing delay to a sane range and cache the cleaned value.
-- Function: effective_pacing_delay_ms
-- Purpose: Handles effective pacing delay ms logic for the Slots777 script.
local function effective_pacing_delay_ms()
  local v = tonumber(S777.pacing_delay_ms) or 2000
  if v < 100 then v = 100 end
  if v > 15000 then v = 15000 end
  S777.pacing_delay_ms = math.floor(v)
  return S777.pacing_delay_ms
end

-- Queue a chat line to be emitted later.
-- We use delayed queued chat to avoid flooding and to keep lines readable.
-- Function: table_announce
-- Purpose: Queues or sends a message to the configured chat output channel.
local function table_announce(message)
  local msg = tostring(message or "")
  if msg == "" then return end
  local now = (time_ms ~= nil) and time_ms() or 0
  local at = tonumber(S777.next_chat_at) or now
  if at < now then at = now end
  table.insert(S777.pending_chat, { msg = msg, at = at })
  S777.next_chat_at = at + effective_pacing_delay_ms()
end

-- Emit one pending queued chat line when its due time arrives.
-- Function: process_pending_chat
-- Purpose: Processes pending chat updates for the current game state.
local function process_pending_chat()
  if S777.pending_chat == nil or #S777.pending_chat == 0 then return end
  local now = (time_ms ~= nil) and time_ms() or 0
  local item = S777.pending_chat[1]
  if item == nil or now < (tonumber(item.at) or 0) then return end
  table.remove(S777.pending_chat, 1)

  local msg = tostring(item.msg or "")
  if msg == "" then return end
  if chat_send ~= nil then
    chat_send(output_channel_name(), msg)
  else
    dealer_party(msg)
  end
end

-- Lightweight token formatter for template messages.
-- Supported tokens: <player> <bet> <bank> <roll> <mult> <payout>
-- Function: fmt
-- Purpose: Formats a chat template by replacing tokens with runtime values.
local function fmt(template, ctx)
  local msg = tostring(template or "")
  local values = {
    ["<player>"] = tostring((ctx and ctx.player) or ""),
    ["<bet>"] = tostring((ctx and ctx.bet) or 0),
    ["<bank>"] = tostring((ctx and ctx.bank) or 0),
    ["<roll>"] = tostring((ctx and ctx.roll) or 0),
    ["<mult>"] = tostring((ctx and ctx.mult) or 0),
    ["<payout>"] = tostring((ctx and ctx.payout) or 0),
  }
  for token, value in pairs(values) do
    msg = string.gsub(msg, token, value)
  end
  return msg
end

-- Render and enqueue one named template line.
-- Function: announce
-- Purpose: Builds and sends a formatted chat announcement for the current event.
local function announce(key, ctx)
  local t = S777.chat_templates or {}
  local template = t[key]
  if template == nil or template == "" then return end
  table_announce(fmt(template, ctx))
end

-- Normalize player names from chat/roster so we can loosely match sender names.
-- Removes world suffix and punctuation to make matching tolerant.
-- Function: normalize_player_name
-- Purpose: Normalizes player name into a consistent format for comparisons.
local function normalize_player_name(name)
  local n = string.lower(tostring(name or ""))
  n = string.gsub(n, "@.*$", "")
  n = string.gsub(n, "^%s+", "")
  n = string.gsub(n, "%s+$", "")
  n = string.gsub(n, "[^%a%d]", "")
  return n
end

-- Loose name match helper used for chat sender validation.
-- Function: names_match_loose
-- Purpose: Compares two player names using relaxed matching rules.
local function names_match_loose(a, b)
  local na = normalize_player_name(a)
  local nb = normalize_player_name(b)
  if na == "" or nb == "" then return false end
  if na == nb then return true end
  return string.find(na, nb, 1, true) ~= nil or string.find(nb, na, 1, true) ~= nil
end

-- Prevent duplicate queue entries and duplicate active spin assignment.
-- Function: is_already_queued
-- Purpose: Handles is already queued logic for the Slots777 script.
local function is_already_queued(name)
  if S777.active_spin ~= nil and names_match_loose(S777.active_spin.player, name) then return true end
  for i = 1, #S777.queue do
    if names_match_loose(S777.queue[i].player, name) then return true end
  end
  return false
end

-- Resolve a player name against dealer roster.
-- Returns exact match immediately.
-- Returns one unique loose match.
-- Returns empty string on none/ambiguous.
-- Function: find_player_exact_or_loose
-- Purpose: Handles find player exact or loose logic for the Slots777 script.
local function find_player_exact_or_loose(name)
  local count = (dealer_player_count ~= nil) and tonumber(dealer_player_count()) or 0
  local query = tostring(name or "")
  local found = ""
  for i = 1, count do
    local n = dealer_player_name(i)
    if n ~= nil and n ~= "" and dealer_is_eligible(n) then
      if string.lower(n) == string.lower(query) then return n end
      if names_match_loose(n, query) then
        if found ~= "" then return "" end
        found = n
      end
    end
  end
  return found
end

-- Queue a player for spinning.
-- Validates:
-- 1) player exists and is eligible
-- 2) not already queued/active
-- 3) wager > 0
-- Function: queue_player
-- Purpose: Queues player so it can be handled in turn order.
local function queue_player(name)
  local resolved = find_player_exact_or_loose(name)
  if resolved == "" then
    S777.info = "Queue failed: player not found or ambiguous."
    return false
  end

  if is_already_queued(resolved) then
    S777.info = resolved .. " is already queued or spinning."
    return false
  end

  local wager = (dealer_get_wager ~= nil) and (tonumber(dealer_get_wager(resolved)) or 0) or 0
  if wager <= 0 then
    S777.info = "Queue failed: wager must be above 0."
    return false
  end

  table.insert(S777.queue, { player = resolved, bet = math.floor(wager) })
  announce("queued", { player = resolved, bet = math.floor(wager) })
  S777.info = resolved .. " queued."
  return true
end

-- Determine payout multiplier from rolled d1000 value.
-- Priority/precedence:
-- 1) exact jackpot (777) => x5
-- 2) exact ultra (999)   => x4
-- 3) >= high threshold   => x3
-- 4) >= min threshold    => x2
-- 5) otherwise            => loss
-- Function: calc_multiplier
-- Purpose: Handles calc multiplier logic for the Slots777 script.
local function calc_multiplier(roll)
  local r = tonumber(roll) or 0
  if r == S777.jackpot_roll then return 5 end
  if r == S777.ultra_roll then return 4 end
  if r >= S777.high_win_roll then return 3 end
  if r >= S777.min_win_roll then return 2 end
  return 0
end

-- Settle one completed spin.
-- Assumes bet was already deducted when spin started.
-- Function: settle_spin
-- Purpose: Settles spin outcomes and applies payouts/state changes.
local function settle_spin(player, bet, roll)
  S777.rtp_last_round_id = (tonumber(S777.rtp_last_round_id) or 0) + 1
  S777.rtp_rounds = (tonumber(S777.rtp_rounds) or 0) + 1

  local mult = calc_multiplier(roll)
  local payout = 0

  if mult > 0 then
    -- Total return model: payout = bet * multiplier.
    payout = math.floor((tonumber(bet) or 0) * mult)
    if dealer_add_bank ~= nil then dealer_add_bank(player, payout) end
    local bank = (dealer_get_bank ~= nil) and (tonumber(dealer_get_bank(player)) or 0) or 0
    announce("win", { player = player, bet = bet, roll = roll, mult = mult, payout = payout, bank = bank })
    S777.info = player .. " hit x" .. tostring(mult) .. " on " .. tostring(roll) .. "."
    record_rtp_result(player, bet, payout, "wins", roll, mult)
  else
    -- Loss path: no payout (bet already deducted), only announce outcome.
    local bank = (dealer_get_bank ~= nil) and (tonumber(dealer_get_bank(player)) or 0) or 0
    announce("lose", { player = player, bet = bet, roll = roll, bank = bank })
    S777.info = player .. " missed on " .. tostring(roll) .. "."
    record_rtp_result(player, bet, 0, "loses", roll, 0)
  end

  S777.active_spin = nil
  S777.phase = "idle"
  local now = (time_ms ~= nil) and time_ms() or 0
  S777.next_spin_at = now + effective_pacing_delay_ms()
end

-- Start next queued spin if idle.
-- Deducts bet immediately when the spin becomes active.
-- Function: start_next_spin
-- Purpose: Starts next spin for the current game flow.
local function start_next_spin()
  local now = (time_ms ~= nil) and time_ms() or 0
  if now < (tonumber(S777.next_spin_at) or 0) then return end
  if S777.active_spin ~= nil then return end
  if S777.queue == nil or #S777.queue == 0 then return end

  local nextItem = table.remove(S777.queue, 1)
  if nextItem == nil then return end

  local player = tostring(nextItem.player or "")
  local bet = math.floor(tonumber(nextItem.bet) or 0)
  -- Re-validate queued payload in case roster/bank changed while waiting.
  if player == "" or bet <= 0 or (dealer_is_eligible ~= nil and not dealer_is_eligible(player)) then
    announce("skipped", { player = player })
    record_rtp_result(player, bet, 0, "skipped", 0, 0)
    S777.next_spin_at = now + effective_pacing_delay_ms()
    start_next_spin()
    return
  end

  local bank = (dealer_get_bank ~= nil) and (tonumber(dealer_get_bank(player)) or 0) or 0
  if bank < bet then
    announce("skipped", { player = player })
    record_rtp_result(player, bet, 0, "skipped", 0, 0)
    S777.info = player .. " skipped (insufficient bank)."
    S777.next_spin_at = now + effective_pacing_delay_ms()
    start_next_spin()
    return
  end

  if dealer_add_bank ~= nil then dealer_add_bank(player, -bet) end

  -- Important anti-stale step:
  -- clear pre-existing chat lines before opening this spin window.
  -- Only rolls posted after this point will be considered for the active player.
  flush_chat_buffer()

  S777.active_spin = { player = player, bet = bet }
  S777.phase = "waiting_roll"
  S777.info = "Waiting for " .. player .. " to roll."
  announce("prompt", { player = player, bet = bet })
end

-- Boot helper.
-- If name is blank: boot active spinner (if any).
-- If name is provided: remove that player from active spin or queue.
-- Function: boot_player
-- Purpose: Removes player from the active flow or pending queue.
local function boot_player(name)
  local target = tostring(name or "")

  if target == "" and S777.active_spin ~= nil then
    local activeName = tostring(S777.active_spin.player or "")
    S777.active_spin = nil
    S777.phase = "idle"
    S777.info = "Booted active player: " .. activeName
    announce("booted", { player = activeName })
    local now = (time_ms ~= nil) and time_ms() or 0
    S777.next_spin_at = now + effective_pacing_delay_ms()
    return true
  end

  if target ~= "" and S777.active_spin ~= nil and names_match_loose(S777.active_spin.player, target) then
    local activeName = tostring(S777.active_spin.player or "")
    S777.active_spin = nil
    S777.phase = "idle"
    S777.info = "Booted active player: " .. activeName
    announce("booted", { player = activeName })
    local now = (time_ms ~= nil) and time_ms() or 0
    S777.next_spin_at = now + effective_pacing_delay_ms()
    return true
  end

  for i = #S777.queue, 1, -1 do
    local q = S777.queue[i]
    if q ~= nil and names_match_loose(q.player, target) then
      local queuedName = tostring(q.player or "")
      table.remove(S777.queue, i)
      S777.info = "Booted queued player: " .. queuedName
      announce("booted", { player = queuedName })
      return true
    end
  end

  if target == "" then
    S777.info = "Boot failed: no active player to boot."
  else
    S777.info = "Boot failed: player not in active spin or queue."
  end
  return false
end

-- Parse a valid d1000 roll from chat message.
-- Prefers host dice parsers; falls back to raw numeric extraction for resilience.
-- Function: extract_roll_from_message
-- Purpose: Extracts roll from message from incoming chat text.
local function extract_roll_from_message(message)
  local rolled = (dice_roll_value ~= nil) and tonumber(dice_roll_value(message) or 0) or 0
  local upper = (dice_roll_upper ~= nil) and tonumber(dice_roll_upper(message) or 0) or 0

  if rolled <= 0 then
    for n in tostring(message or ""):gmatch("%d+") do
      rolled = tonumber(n) or rolled
    end
  end

  if rolled < 1 or rolled > 1000 then return nil end
  -- If an upper bound was parsed, enforce d1000 specifically.
  if upper > 0 and upper ~= 1000 then return nil end

  return rolled
end

-- Poll inbound chat while waiting for active player's roll.
-- Ignores non-active senders and non-d1000 rolls.
-- Function: process_chat_inputs
-- Purpose: Processes chat inputs updates for the current game state.
local function process_chat_inputs()
  if S777.phase ~= "waiting_roll" then return end
  if S777.active_spin == nil then return end
  if chat_poll == nil then return end

  for _ = 1, 32 do
    local packet = chat_poll()
    if packet == nil or packet == "" then break end

    local name, _, _, message = string.match(packet, "^([^|]*)|([^|]*)|([^|]*)|(.*)$")
    if name ~= nil and message ~= nil and names_match_loose(name, S777.active_spin.player) then
      local roll = extract_roll_from_message(message)
      if roll ~= nil then
        settle_spin(S777.active_spin.player, S777.active_spin.bet, roll)
        return
      end
    end
  end
end

-- Command entrypoint for script routing.
-- /casino s777queue <name>
-- /casino s777boot [name]
-- /casino s777reset
-- /casino s777status
-- Function: on_command
-- Purpose: Routes script commands and executes command-specific game actions.
function on_command(cmd, ...)
  local c = string.lower(tostring(cmd or ""))
  local a1 = tostring(select(1, ...) or "")

  if c == "s777queue" then
    queue_player(a1)
    return "ok"
  end

  if c == "s777boot" then
    boot_player(a1)
    return "ok"
  end

  if c == "s777reset" then
    S777.queue = {}
    S777.active_spin = nil
    S777.phase = "idle"
    S777.info = "Slots777 reset."
    return "ok"
  end

  if c == "s777status" then
    local active = (S777.active_spin and S777.active_spin.player) or "(none)"
    return "phase=" .. tostring(S777.phase) .. " active=" .. tostring(active) .. " queue=" .. tostring(#S777.queue)
  end

  if c == "s777save" then
    save_config()
    return "ok"
  end

  if c == "s777load" then
    load_config()
    return "ok"
  end

  return "unknown"
end

-- Script config panel.
-- Exposes pacing/thresholds and chat template editing.
-- Function: draw_config_ui
-- Purpose: Renders the configuration panel where the dealer edits script settings.
function draw_config_ui()
  ui_text_colored("Slots777 Config", 0.8, 0.95, 0.8, 1.0)
  ui_separator()
  ui_text("Config status: " .. tostring(S777.config_status or ""))

  S777.pacing_delay_ms = math.max(100, ui_input_int("Standard delay (ms)##s777_delay", tonumber(S777.pacing_delay_ms) or 2000))
  S777.min_win_roll = math.max(1, math.min(1000, ui_input_int("2x threshold##s777_min", tonumber(S777.min_win_roll) or 565)))
  S777.high_win_roll = math.max(S777.min_win_roll, math.min(1000, ui_input_int("3x threshold##s777_high", tonumber(S777.high_win_roll) or 950)))

  ui_separator()
  ui_text_colored("Templates", 0.9, 0.95, 1.0, 1.0)
  local t = S777.chat_templates or {}
  t.queued = ui_input_text("queued##s777_tpl_q", t.queued or "", 512)
  t.prompt = ui_input_text("prompt##s777_tpl_p", t.prompt or "", 512)
  t.win = ui_input_text("win##s777_tpl_w", t.win or "", 512)
  t.lose = ui_input_text("lose##s777_tpl_l", t.lose or "", 512)
  t.skipped = ui_input_text("skipped##s777_tpl_s", t.skipped or "", 512)
  t.booted = ui_input_text("booted##s777_tpl_b", t.booted or "", 512)
  S777.chat_templates = t

  ui_separator()
  if ui_button("Save Config##s777_cfg_save") then
    save_config()
  end
  ui_same_line()
  if ui_button("Reload Config##s777_cfg_reload") then
    load_config()
  end
end

-- Main UI loop.
-- Order is important:
-- 1) process chat (possibly settles current spin)
-- 2) emit pending announcements
-- 3) start next queued spin if idle
-- Function: draw_ui
-- Purpose: Renders the main game UI and runs the per-frame update flow.
function draw_ui()
  process_chat_inputs()
  process_pending_chat()
  start_next_spin()

  ui_text_colored("Slots777", 1.0, 0.9, 0.4, 1.0)
  ui_separator()

  ui_text("Status: " .. tostring(S777.phase) .. " | " .. tostring(S777.info))
  ui_text("Rules: >=565 => 2x, >=950 => 3x, 999 => 4x, 777 => 5x.")

  if S777.active_spin ~= nil then
    ui_separator()
    ui_text_colored("Active Spin", 0.9, 0.95, 1.0, 1.0)
    ui_text("Player: " .. tostring(S777.active_spin.player) .. " | Bet: " .. tostring(S777.active_spin.bet))
  end

  ui_separator()
  ui_text_colored("Dealer Queue", 0.9, 0.95, 1.0, 1.0)

  local count = (dealer_player_count ~= nil) and tonumber(dealer_player_count()) or 0
  for i = 1, count do
    local name = dealer_player_name(i)
    -- Only allow eligible roster members to be queued.
    if name ~= nil and name ~= "" and (dealer_is_eligible == nil or dealer_is_eligible(name)) then
      local wager = (dealer_get_wager ~= nil) and (tonumber(dealer_get_wager(name)) or 0) or 0
      local bank = (dealer_get_bank ~= nil) and (tonumber(dealer_get_bank(name)) or 0) or 0
      ui_text(name .. " | Wager " .. tostring(wager) .. " | Bank " .. tostring(bank))
      ui_same_line()
      if ui_button("Queue##s777_q_" .. name) then
        queue_player(name)
      end
    end
  end

  ui_separator()
  ui_text_colored("Queued", 1.0, 1.0, 0.8, 1.0)
  if #S777.queue == 0 then
    ui_text("(no queued players)")
  else
    for i = 1, #S777.queue do
      local q = S777.queue[i]
      ui_text(tostring(i) .. ". " .. tostring(q.player) .. " | Bet " .. tostring(q.bet))
    end
  end

  if ui_button("Clear Queue##s777_clear") then
    S777.queue = {}
    S777.info = "Queue cleared."
  end

  ui_same_line()
  if ui_button("Boot Active##s777_boot_active") then
    boot_player("")
  end

  ui_separator()
  if ui_collapsing_header ~= nil then
    S777.show_help = ui_collapsing_header("Slots777 Help##s777_help")
  end
  if S777.show_help == true then
    ui_text_colored("Flow", 0.9, 0.95, 1.0, 1.0)
    ui_text("1) Dealer clicks Queue next to a player.")
    ui_text("2) Player rolls /dice party")
    ui_text("3) Bet is withdrawn at spin start; payout is added on win.")
    ui_text("4) Use /casino s777boot [name] to remove stalled players from active/queue.")
    ui_separator()
    ui_text_colored("Payout Table", 0.9, 0.95, 1.0, 1.0)
    ui_text("565-949: x2")
    ui_text("950-998: x3")
    ui_text("999: x4")
    ui_text("777: x5 jackpot")
    ui_text("Below 565: loss")
  end

  ui_separator()
  local wagered = tonumber(S777.rtp_wagered) or 0
  local paid = tonumber(S777.rtp_paid) or 0
  local rounds = tonumber(S777.rtp_rounds) or 0
  local rtp = (wagered > 0) and ((paid / wagered) * 100.0) or 0
  ui_text(string.format(
    "Return To Player: %.2f%% | Rounds: %d | Gil In: %d | Gil Out: %d",
    rtp,
    math.floor(rounds),
    math.floor(wagered),
    math.floor(paid)
  ))
end

-- Return module table for consistency with other scripts.
return S777
