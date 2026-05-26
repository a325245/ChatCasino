if RT3 == nil then
  RT3 = {
    phase = "idle", -- idle | waiting_rolls | awaiting_comment
    info = "Queue a player to begin Round Three.",

    queue = {},
    active_run = nil, -- { player=<name>, bet=<wager>, rolls={}, current_roll=1 }
    pending_step_result = nil,
    dealer_comment_draft = "",

    pending_chat = {},
    next_chat_at = 0,
    next_turn_at = 0,

    pacing_delay_ms = 1000,
    roll_sides = 12,
    required_rolls = 3,
    minimums = { 3, 4, 5 }, -- roll must be > minimum for each step

    show_help = true,
    config_status = "Round Three config not loaded yet.",

    chat_templates = {
      queued = "<player> queued for Round Three. Bet <bet>.",
      prompt = "<player>, roll /dice party 12 now! (Step <round>/3: must roll above <need>)",
      pass_step = "<player> rolled <roll> and cleared step <round>/3.",
      fail_step = "<player> rolled <roll> on step <round>/3 (needed above <need>).",
      win = "<player> cleared all 3 rolls! Paid <payout> (2x). Bank <bank>.",
      lose = "<player> failed Round Three and lost <bet>. Bank <bank>.",
      skipped = "<player> removed from Round Three queue (invalid wager or insufficient bank).",
      booted = "<player> was booted from Round Three queue/turn.",
    }
  }
end

-- ============================================================================
-- Utility helpers
-- ============================================================================

-- Function: config_file_name
-- Purpose: Handles config file name logic for the RoundThree script.
local function config_file_name()
  return "RoundThree.config.json"
end

-- Function: echo_notice
-- Purpose: Handles echo notice logic for the RoundThree script.
local function echo_notice(msg)
  local text = tostring(msg or "")
  if text == "" then return end
  if chat_send ~= nil then
    chat_send("echo", text)
  elseif dealer_party ~= nil then
    dealer_party(text)
  end
end

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

-- Function: table_announce
-- Purpose: Queues or sends a message to the configured chat output channel.
local function table_announce(message)
  local msg = tostring(message or "")
  if msg == "" then return end
  local now = (time_ms ~= nil) and tonumber(time_ms()) or 0
  local at = tonumber(RT3.next_chat_at) or now
  if at < now then at = now end
  table.insert(RT3.pending_chat, { msg = msg, at = at })
  RT3.next_chat_at = at + (tonumber(RT3.pacing_delay_ms) or 1000)
end

-- Function: process_pending_chat
-- Purpose: Processes pending chat updates for the current game state.
local function process_pending_chat()
  if RT3.pending_chat == nil or #RT3.pending_chat == 0 then return end
  local now = (time_ms ~= nil) and tonumber(time_ms()) or 0
  local item = RT3.pending_chat[1]
  if item == nil or now < (tonumber(item.at) or 0) then return end
  table.remove(RT3.pending_chat, 1)
  local msg = tostring(item.msg or "")
  if msg == "" then return end
  if chat_send ~= nil then
    chat_send(output_channel_name(), msg)
  else
    dealer_party(msg)
  end
end

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

-- Function: names_match_loose
-- Purpose: Compares two player names using relaxed matching rules.
local function names_match_loose(a, b)
  local na = normalize_player_name(a)
  local nb = normalize_player_name(b)
  if na == "" or nb == "" then return false end
  if na == nb then return true end
  return (string.find(na, nb, 1, true) ~= nil) or (string.find(nb, na, 1, true) ~= nil)
end

-- Function: fmt
-- Purpose: Formats a chat template by replacing tokens with runtime values.
local function fmt(template, ctx)
  local msg = tostring(template or "")
  local values = {
    ["<player>"] = tostring((ctx and ctx.player) or ""),
    ["<bet>"] = tostring((ctx and ctx.bet) or 0),
    ["<bank>"] = tostring((ctx and ctx.bank) or 0),
    ["<roll>"] = tostring((ctx and ctx.roll) or 0),
    ["<round>"] = tostring((ctx and ctx.round) or 0),
    ["<need>"] = tostring((ctx and ctx.need) or 0),
    ["<payout>"] = tostring((ctx and ctx.payout) or 0),
    ["<total>"] = tostring((ctx and ctx.total) or 0),
    ["<result>"] = tostring((ctx and ctx.result) or ""),
  }
  for token, value in pairs(values) do
    msg = string.gsub(msg, token, value)
  end
  return msg
end

-- Function: announce
-- Purpose: Builds and sends a formatted chat announcement for the current event.
local function announce(key, ctx)
  local t = RT3.chat_templates or {}
  local template = t[key]
  if template == nil or template == "" then return end
  table_announce(fmt(template, ctx))
end

-- Function: effective_delay_ms
-- Purpose: Handles effective delay ms logic for the RoundThree script.
local function effective_delay_ms()
  local d = tonumber(RT3.pacing_delay_ms) or 1000
  if d < 100 then d = 100 end
  if d > 15000 then d = 15000 end
  RT3.pacing_delay_ms = math.floor(d)
  return RT3.pacing_delay_ms
end

-- Function: flush_chat_buffer
-- Purpose: Handles flush chat buffer logic for the RoundThree script.
local function flush_chat_buffer()
  if chat_poll == nil then return end
  for _ = 1, 500 do
    local packet = chat_poll()
    if packet == nil or packet == "" then break end
  end
end

-- Function: extract_roll_d12
-- Purpose: Extracts roll d12 from incoming chat text.
local function extract_roll_d12(message)
  if message == nil then return nil end
  if dice_roll_value ~= nil and dice_roll_upper ~= nil then
    local value = tonumber(dice_roll_value(message)) or 0
    local upper = tonumber(dice_roll_upper(message)) or 0
    if value >= 1 and upper == 12 then
      return value
    end
  end

  -- fallback parse
  local v = tonumber(string.match(tostring(message), "[Rr]olls?%s+(%d+)%s*%(%s*1%-%s*12%s*%)"))
  if v ~= nil and v >= 1 and v <= 12 then return v end
  return nil
end

-- ============================================================================
-- Config save/load
-- ============================================================================

-- Function: export_config_blob
-- Purpose: Handles export config blob logic for the RoundThree script.
local function export_config_blob()
  local t = RT3.chat_templates or {}
  return "return {"
    .. "pacing_delay_ms=" .. tostring(math.floor(tonumber(RT3.pacing_delay_ms) or 1000)) .. ","
    .. "show_help=" .. tostring(RT3.show_help == true) .. ","
    .. "chat_templates={"
    .. "queued=[=[" .. tostring(t.queued or "") .. "]=],"
    .. "prompt=[=[" .. tostring(t.prompt or "") .. "]=],"
    .. "pass_step=[=[" .. tostring(t.pass_step or "") .. "]=],"
    .. "fail_step=[=[" .. tostring(t.fail_step or "") .. "]=],"
    .. "win=[=[" .. tostring(t.win or "") .. "]=],"
    .. "lose=[=[" .. tostring(t.lose or "") .. "]=],"
    .. "skipped=[=[" .. tostring(t.skipped or "") .. "]=],"
    .. "booted=[=[" .. tostring(t.booted or "") .. "]=],"
    .. "}"
    .. "}"
end

-- Function: apply_config_table
-- Purpose: Handles apply config table logic for the RoundThree script.
local function apply_config_table(data)
  if type(data) ~= "table" then return false end

  if data.pacing_delay_ms ~= nil then
    RT3.pacing_delay_ms = tonumber(data.pacing_delay_ms) or RT3.pacing_delay_ms
  end
  if data.show_help ~= nil then
    RT3.show_help = (data.show_help == true)
  end
  if type(data.chat_templates) == "table" then
    local t = RT3.chat_templates or {}
    for k, v in pairs(data.chat_templates) do
      t[tostring(k)] = tostring(v or "")
    end
    RT3.chat_templates = t
  end

  effective_delay_ms()
  return true
end

-- Function: save_config
-- Purpose: Saves config data from runtime state.
local function save_config()
  if script_write_text == nil then
    RT3.config_status = "Round Three config save failed (host file API unavailable)."
    echo_notice(RT3.config_status)
    return false
  end

  local ok = script_write_text(config_file_name(), export_config_blob()) == true
  if ok then
    RT3.config_status = "Round Three config saved."
  else
    RT3.config_status = "Round Three config save failed."
  end
  echo_notice(RT3.config_status)
  return ok
end

-- Function: load_config
-- Purpose: Loads config data into runtime state.
local function load_config()
  if script_read_text == nil then
    RT3.config_status = "Round Three config load skipped (host file API unavailable)."
    return false
  end

  local raw = script_read_text(config_file_name())
  if raw == nil or raw == "" then
    RT3.config_status = "Round Three config file not found."
    return false
  end

  local loader = loadstring or load
  local fn, err = loader(tostring(raw))
  if not fn then
    RT3.config_status = "Round Three config syntax error: " .. tostring(err)
    return false
  end

  local ok, data = pcall(fn)
  if not ok then
    RT3.config_status = "Round Three config runtime error: " .. tostring(data)
    return false
  end

  if not apply_config_table(data) then
    RT3.config_status = "Round Three config invalid payload."
    return false
  end

  RT3.config_status = "Round Three config loaded."
  echo_notice(RT3.config_status)
  return true
end

if RT3._config_loaded ~= true then
  load_config()
  RT3._config_loaded = true
end

-- ============================================================================
-- Game flow
-- ============================================================================

-- Function: find_queued_index
-- Purpose: Handles find queued index logic for the RoundThree script.
local function find_queued_index(name)
  for i = 1, #RT3.queue do
    if names_match_loose(RT3.queue[i].player, name) then
      return i
    end
  end
  return nil
end

-- Function: queue_player
-- Purpose: Queues player so it can be handled in turn order.
local function queue_player(name)
  local player = tostring(name or "")
  if player == "" then
    RT3.info = "No player name provided."
    return false
  end

  if dealer_is_eligible ~= nil and not dealer_is_eligible(player) then
    RT3.info = player .. " is not eligible."
    return false
  end

  if RT3.active_run ~= nil and names_match_loose(RT3.active_run.player, player) then
    RT3.info = player .. " is already active."
    return false
  end

  if find_queued_index(player) ~= nil then
    RT3.info = player .. " is already queued."
    return false
  end

  local wager = (dealer_get_wager ~= nil) and (tonumber(dealer_get_wager(player)) or 0) or 0
  local bank = (dealer_get_bank ~= nil) and (tonumber(dealer_get_bank(player)) or 0) or 0

  if wager <= 0 or bank < wager then
    announce("skipped", { player = player })
    RT3.info = player .. " skipped (invalid wager or insufficient bank)."
    return false
  end

  table.insert(RT3.queue, { player = player, bet = wager })
  announce("queued", { player = player, bet = wager, bank = bank })
  RT3.info = player .. " queued."
  return true
end

-- Function: boot_player
-- Purpose: Removes player from the active flow or pending queue.
local function boot_player(name)
  local target = tostring(name or "")

  if target == "" then
    if RT3.active_run ~= nil then
      local p = RT3.active_run.player
      RT3.active_run = nil
      RT3.phase = "idle"
      RT3.info = p .. " booted from active turn."
      announce("booted", { player = p })
      return true
    end
    RT3.info = "No active player to boot."
    return false
  end

  if RT3.active_run ~= nil and names_match_loose(RT3.active_run.player, target) then
    RT3.active_run = nil
    RT3.phase = "idle"
    RT3.info = target .. " booted from active turn."
    announce("booted", { player = target })
    return true
  end

  local idx = find_queued_index(target)
  if idx ~= nil then
    table.remove(RT3.queue, idx)
    RT3.info = target .. " booted from queue."
    announce("booted", { player = target })
    return true
  end

  RT3.info = target .. " not found in active/queue."
  return false
end

-- Function: settle_failure
-- Purpose: Settles failure outcomes and applies payouts/state changes.
local function settle_failure(player, bet, roundIndex, need, roll)
  local bank = (dealer_get_bank ~= nil) and (tonumber(dealer_get_bank(player)) or 0) or 0
  announce("fail_step", { player = player, round = roundIndex, need = need, roll = roll, bet = bet, bank = bank })
  announce("lose", { player = player, round = roundIndex, need = need, roll = roll, bet = bet, bank = bank })
  RT3.active_run = nil
  RT3.phase = "idle"
  RT3.info = player .. " failed step " .. tostring(roundIndex) .. "."
  RT3.next_turn_at = ((time_ms ~= nil) and tonumber(time_ms()) or 0) + effective_delay_ms()
end

-- Function: settle_success
-- Purpose: Settles success outcomes and applies payouts/state changes.
local function settle_success(player, bet, rolls)
  local payout = math.floor((tonumber(bet) or 0) * 2)
  if dealer_add_bank ~= nil then
    dealer_add_bank(player, payout)
  end
  local bank = (dealer_get_bank ~= nil) and (tonumber(dealer_get_bank(player)) or 0) or 0
  announce("win", { player = player, payout = payout, bet = bet, bank = bank, result = table.concat(rolls, ",") })
  RT3.active_run = nil
  RT3.phase = "idle"
  RT3.info = player .. " cleared all 3 rolls."
  RT3.next_turn_at = ((time_ms ~= nil) and tonumber(time_ms()) or 0) + effective_delay_ms()
end

-- Function: submit_dealer_comment_if_any
-- Purpose: Handles submit dealer comment if any logic for the RoundThree script.
local function submit_dealer_comment_if_any()
  local text = tostring(RT3.dealer_comment_draft or "")
  text = string.gsub(text, "^%s+", "")
  text = string.gsub(text, "%s+$", "")
  if text ~= "" then
    table_announce("Dealer: " .. text)
  end
  RT3.dealer_comment_draft = ""
end

-- Function: resolve_pending_step_result
-- Purpose: Handles resolve pending step result logic for the RoundThree script.
local function resolve_pending_step_result()
  local p = RT3.pending_step_result
  if p == nil then return end

  submit_dealer_comment_if_any()
  RT3.pending_step_result = nil

  if p.passed == true then
    if p.step >= RT3.required_rolls then
      settle_success(p.player, p.bet, p.rolls)
      return
    end

    local run = RT3.active_run
    if run == nil then return end
    run.current_roll = p.step + 1
    local nextNeed = tonumber(RT3.minimums[run.current_roll]) or 0
    announce("prompt", { player = run.player, round = run.current_roll, need = nextNeed, bet = run.bet })
    RT3.phase = "waiting_rolls"
    RT3.info = run.player .. " passed step " .. tostring(p.step) .. "."
    return
  end

  settle_failure(p.player, p.bet, p.step, p.need, p.roll)
end

-- Function: handle_roll
-- Purpose: Handles handle roll logic for the RoundThree script.
local function handle_roll(roll)
  if RT3.phase ~= "waiting_rolls" or RT3.active_run == nil then return end

  local run = RT3.active_run
  local step = tonumber(run.current_roll) or 1
  local need = tonumber(RT3.minimums[step]) or 0

  table.insert(run.rolls, roll)

  if roll > need then
    announce("pass_step", { player = run.player, round = step, need = need, roll = roll, bet = run.bet })
    RT3.pending_step_result = {
      player = run.player,
      bet = run.bet,
      rolls = run.rolls,
      step = step,
      need = need,
      roll = roll,
      passed = true,
    }
    RT3.phase = "awaiting_comment"
    RT3.info = run.player .. " passed step " .. tostring(step) .. ". Dealer comment?"
    return
  end

  announce("fail_step", { player = run.player, round = step, need = need, roll = roll, bet = run.bet })
  RT3.pending_step_result = {
    player = run.player,
    bet = run.bet,
    rolls = run.rolls,
    step = step,
    need = need,
    roll = roll,
    passed = false,
  }
  RT3.phase = "awaiting_comment"
  RT3.info = run.player .. " failed step " .. tostring(step) .. ". Dealer comment?"
end

-- Function: start_next_turn
-- Purpose: Starts next turn for the current game flow.
local function start_next_turn()
  if RT3.phase ~= "idle" then return end
  if RT3.active_run ~= nil then return end
  if RT3.queue == nil or #RT3.queue == 0 then return end

  local now = (time_ms ~= nil) and tonumber(time_ms()) or 0
  if now < (tonumber(RT3.next_turn_at) or 0) then return end

  while #RT3.queue > 0 do
    local nextUp = table.remove(RT3.queue, 1)
    local player = nextUp.player
    local bet = tonumber(nextUp.bet) or 0
    local currentBank = (dealer_get_bank ~= nil) and (tonumber(dealer_get_bank(player)) or 0) or 0

    if bet <= 0 or currentBank < bet then
      announce("skipped", { player = player, bet = bet, bank = currentBank })
      RT3.info = player .. " skipped (invalid wager or insufficient bank)."
    else
      if dealer_add_bank ~= nil then
        dealer_add_bank(player, -bet)
      end

      RT3.active_run = {
        player = player,
        bet = bet,
        rolls = {},
        current_roll = 1,
      }
      RT3.phase = "waiting_rolls"
      RT3.info = player .. " is now rolling step 1/3."

      -- Prevent stale /dice lines from being consumed for this run.
      flush_chat_buffer()

      announce("prompt", { player = player, round = 1, need = RT3.minimums[1], bet = bet })
      return
    end
  end
end

-- Function: process_chat_inputs
-- Purpose: Processes chat inputs updates for the current game state.
local function process_chat_inputs()
  if RT3.phase ~= "waiting_rolls" then return end
  if RT3.active_run == nil then return end
  if chat_poll == nil then return end

  for _ = 1, 32 do
    local packet = chat_poll()
    if packet == nil or packet == "" then break end

    local name, _, _, message = string.match(packet, "^([^|]*)|([^|]*)|([^|]*)|(.*)$")
    if name ~= nil and message ~= nil and names_match_loose(name, RT3.active_run.player) then
      local roll = extract_roll_d12(message)
      if roll ~= nil then
        handle_roll(roll)
        return
      end
    end
  end
end

-- ============================================================================
-- Entrypoints
-- ============================================================================

-- Function: on_command
-- Purpose: Routes script commands and executes command-specific game actions.
function on_command(cmd, ...)
  local c = string.lower(tostring(cmd or ""))
  local a1 = tostring(select(1, ...) or "")

  if c == "r3queue" then
    queue_player(a1)
    return "ok"
  end

  if c == "r3boot" then
    boot_player(a1)
    return "ok"
  end

  if c == "r3reset" then
    RT3.queue = {}
    RT3.active_run = nil
    RT3.phase = "idle"
    RT3.info = "Round Three reset."
    return "ok"
  end

  if c == "r3status" then
    local active = (RT3.active_run and RT3.active_run.player) or "(none)"
    return "phase=" .. tostring(RT3.phase) .. " active=" .. tostring(active) .. " queue=" .. tostring(#RT3.queue)
  end

  if c == "r3save" then
    save_config()
    return "ok"
  end

  if c == "r3load" then
    load_config()
    return "ok"
  end

  return "unknown"
end

-- Function: draw_config_ui
-- Purpose: Renders the configuration panel where the dealer edits script settings.
function draw_config_ui()
  ui_text_colored("Round Three Config", 0.8, 0.95, 0.8, 1.0)
  ui_separator()
  ui_text("Config status: " .. tostring(RT3.config_status or ""))

  RT3.pacing_delay_ms = math.max(100, ui_input_int("Standard delay (ms)##rt3_delay", tonumber(RT3.pacing_delay_ms) or 1000))
  effective_delay_ms()

  ui_text("Rule thresholds are fixed:")
  ui_text("Step 1: roll above 3")
  ui_text("Step 2: roll above 4")
  ui_text("Step 3: roll above 5")
  ui_text("Payout: 2x on full clear")

  ui_separator()
  ui_text_colored("Templates", 0.9, 0.95, 1.0, 1.0)
  local t = RT3.chat_templates or {}
  t.queued = ui_input_text("queued##rt3_tpl_q", t.queued or "", 512)
  t.prompt = ui_input_text("prompt##rt3_tpl_p", t.prompt or "", 512)
  t.pass_step = ui_input_text("pass_step##rt3_tpl_ps", t.pass_step or "", 512)
  t.fail_step = ui_input_text("fail_step##rt3_tpl_fs", t.fail_step or "", 512)
  t.win = ui_input_text("win##rt3_tpl_w", t.win or "", 512)
  t.lose = ui_input_text("lose##rt3_tpl_l", t.lose or "", 512)
  t.skipped = ui_input_text("skipped##rt3_tpl_s", t.skipped or "", 512)
  t.booted = ui_input_text("booted##rt3_tpl_b", t.booted or "", 512)
  RT3.chat_templates = t

  ui_separator()
  if ui_button("Save Config##rt3_cfg_save") then
    save_config()
  end
  ui_same_line()
  if ui_button("Reload Config##rt3_cfg_load") then
    load_config()
  end
end

-- Function: draw_ui
-- Purpose: Renders the main game UI and runs the per-frame update flow.
function draw_ui()
  process_chat_inputs()
  process_pending_chat()
  start_next_turn()

  ui_text_colored("Round Three", 1.0, 0.9, 0.4, 1.0)
  ui_separator()

  ui_text("Status: " .. tostring(RT3.phase) .. " | " .. tostring(RT3.info))
  ui_text("Rules: Roll 3 times on /dice party 12. Must be >3, >4, >5. Clear all 3 for 2x payout.")

  if RT3.active_run ~= nil then
    ui_separator()
    local run = RT3.active_run
    ui_text_colored("Active Run", 0.9, 0.95, 1.0, 1.0)
    ui_text("Player: " .. tostring(run.player) .. " | Bet: " .. tostring(run.bet) .. " | Step: " .. tostring(run.current_roll) .. "/3")
    if run.rolls ~= nil and #run.rolls > 0 then
      ui_text("Rolls: " .. table.concat(run.rolls, ", "))
    end
  end

  if RT3.phase == "awaiting_comment" and RT3.pending_step_result ~= nil then
    local p = RT3.pending_step_result
    ui_separator()
    ui_text_colored("Dealer Comment", 1.0, 0.9, 0.7, 1.0)
    ui_text(tostring(p.player) .. " | Step " .. tostring(p.step) .. "/3 | Roll " .. tostring(p.roll))
    if p.passed == true then
      ui_text("Result: PASS")
    else
      ui_text("Result: FAIL")
    end
    RT3.dealer_comment_draft = ui_input_text("Comment##rt3_dealer_comment", tostring(RT3.dealer_comment_draft or ""), 512)
    if ui_button("Send Comment + Continue##rt3_comment_continue") then
      resolve_pending_step_result()
    end
    ui_same_line()
    if ui_button("Continue Without Comment##rt3_comment_skip") then
      RT3.dealer_comment_draft = ""
      resolve_pending_step_result()
    end
  end

  ui_separator()
  ui_text_colored("Dealer Queue", 0.9, 0.95, 1.0, 1.0)

  local count = (dealer_player_count ~= nil) and (tonumber(dealer_player_count()) or 0) or 0
  for i = 1, count do
    local name = dealer_player_name(i)
    if name ~= nil and name ~= "" and (dealer_is_eligible == nil or dealer_is_eligible(name)) then
      local wager = (dealer_get_wager ~= nil) and (tonumber(dealer_get_wager(name)) or 0) or 0
      local bank = (dealer_get_bank ~= nil) and (tonumber(dealer_get_bank(name)) or 0) or 0
      ui_text(name .. " | Wager " .. tostring(wager) .. " | Bank " .. tostring(bank))
      ui_same_line()
      if ui_button("Queue##rt3_q_" .. name) then
        queue_player(name)
      end
    end
  end

  ui_separator()
  ui_text_colored("Queued", 1.0, 1.0, 0.8, 1.0)
  if #RT3.queue == 0 then
    ui_text("(no queued players)")
  else
    for i = 1, #RT3.queue do
      local q = RT3.queue[i]
      ui_text(tostring(i) .. ". " .. tostring(q.player) .. " | Bet " .. tostring(q.bet))
    end
  end

  if ui_button("Clear Queue##rt3_clear") then
    RT3.queue = {}
    RT3.info = "Queue cleared."
  end

  ui_same_line()
  if ui_button("Boot Active##rt3_boot_active") then
    boot_player("")
  end

  ui_separator()
  if ui_collapsing_header ~= nil then
    RT3.show_help = ui_collapsing_header("Round Three Help##rt3_help")
  end
  if RT3.show_help == true then
    ui_text_colored("Flow", 0.9, 0.95, 1.0, 1.0)
    ui_text("1) Dealer clicks Queue next to a player.")
    ui_text("2) Bet is withdrawn when that player becomes active.")
    ui_text("3) Player rolls /dice party 12 three times.")
    ui_text("4) Must roll above 3, then above 4, then above 5.")
    ui_text("5) Clearing all three pays 2x total payout.")
    ui_separator()
    ui_text_colored("Commands", 0.9, 0.95, 1.0, 1.0)
    ui_text("/casino r3queue <name>")
    ui_text("/casino r3boot [name]")
    ui_text("/casino r3reset")
    ui_text("/casino r3status")
  end
end

return RT3
