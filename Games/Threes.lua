if TH == nil then
  TH = {
    phase = "idle",
    info = "Click New Round to begin.",

    order = {},
    scores = {},
    results = {},
    active_index = 1,

    dice = {},
    awaiting_rolls = false,
    pending_slots = {},
    must_hold_after_roll = false,
    roll_inflight = false,
    next_roll_ms = 0,
    roll_sent_ms = 0,
    roll_timeout_ms = 2500,
    roll_delay_ms = 125,
    turn_roll_count = 0,
    ready_to_end_turn = false,
    auto_held_this_batch = 0,
    retry_cooldown_ms = 250,
    retry_next_ms = 0,

    play_vs_dealer = true,
    dealer_score = nil,
    dealer_dice = {},
    dealer_ai = nil,

    dice_channel = "party",
    dealer_rolls_for_players = true,

    chat_templates = {
      round_start = "Threes begins with <total> players.",
      turn_start = "<player>'s turn starts.",
      turn_score = "<player> locks in a score of <total>.",
      -- default instructs to use party channel; user can edit in config
      roll_request = "<player>, roll <total> dice using \"/dice party 6\".",
      roll_count = "Rolling <total> dice for <player>.",
      roll_result = "",
      roll_hold_and_count = "<player> running total so far: <total>. Rolling <result> dice.",
      winner = "Threes winner: <result> with <total>.",
    },

    show_help = true,
  }
end

-- Function: output_channel_name
-- Purpose: Resolves the chat channel that this script should use for output.
local function output_channel_name()
  if default_chat_channel ~= nil then
    local ch = default_chat_channel()
    if ch == "echo" or ch == "say" or ch == "party" then
      return ch
    end
  end
  return "party"
end

-- Function: normalize_channel
-- Purpose: Normalizes channel into a consistent format for comparisons.
local function normalize_channel(ch)
  local c = string.lower(tostring(ch or "party"))
  if c ~= "echo" and c ~= "say" and c ~= "party" and c ~= "shout" and c ~= "yell" then
    return "party"
  end
  return c
end

-- Function: normalize_player_name
-- Purpose: Normalizes player name into a consistent format for comparisons.
local function normalize_player_name(name)
  local n = string.lower(tostring(name or ""))
  n = string.gsub(n, "@.*$", "")
  n = string.gsub(n, "^%s+", "")
  n = string.gsub(n, "%s+$", "")
  -- remove non-alphanumeric to better match variants (brackets, punctuation, Random! bot, etc.)
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

-- Function: table_announce
-- Purpose: Queues or sends a message to the configured chat output channel.
local function table_announce(message)
  local msg = message or ""
  if msg == "" then return end
  if chat_send ~= nil then
    chat_send(output_channel_name(), msg)
  else
    dealer_party(msg)
  end
end

-- Function: fmt
-- Purpose: Formats a chat template by replacing tokens with runtime values.
local function fmt(template, ctx)
  if chat_format ~= nil then
    return chat_format(
      template or "",
      tostring((ctx and ctx.player) or ""),
      tonumber((ctx and ctx.bet) or 0) or 0,
      tonumber((ctx and ctx.bank) or 0) or 0,
      tostring((ctx and ctx.card) or ""),
      tonumber((ctx and ctx.total) or 0) or 0,
      tonumber((ctx and ctx.dealer_total) or 0) or 0,
      tostring((ctx and ctx.result) or "")
    )
  end

  local msg = template or ""
  local values = {
    ["<player>"] = tostring((ctx and ctx.player) or ""),
    ["<bet>"] = tostring((ctx and ctx.bet) or 0),
    ["<bank>"] = tostring((ctx and ctx.bank) or 0),
    ["<card>"] = tostring((ctx and ctx.card) or ""),
    ["<total>"] = tostring((ctx and ctx.total) or ""),
    ["<dealer_total>"] = tostring((ctx and ctx.dealer_total) or ""),
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
  local t = TH.chat_templates or {}
  local template = t[key]
  if template == nil or template == "" then return end
  local msg = fmt(template, ctx)
  -- Prefer the per-game dice_channel when available
  local ch = (TH and TH.dice_channel) and normalize_channel(TH.dice_channel) or nil
  if ch ~= nil and chat_send ~= nil then
    chat_send(ch, msg)
  else
    table_announce(msg)
  end
end

-- Function: active_player_name
-- Purpose: Handles active player name logic for the Threes script.
local function active_player_name()
  if TH.active_index < 1 or TH.active_index > #TH.order then return "" end
  return TH.order[TH.active_index] or ""
end

-- Function: reset_turn_dice
-- Purpose: Handles reset turn dice logic for the Threes script.
local function reset_turn_dice()
  TH.dice = {}
  for i = 1, 5 do
    TH.dice[i] = {
      value = 0,
      rolled = false,
      held = false,
      forced = false,
      auto_recent = false,
    }
  end
  TH.awaiting_rolls = false
  TH.pending_slots = {}
  TH.must_hold_after_roll = false
  TH.roll_inflight = false
  TH.next_roll_ms = 0
  TH.roll_sent_ms = 0
  TH.turn_roll_count = 0
  TH.ready_to_end_turn = false
  TH.auto_held_this_batch = 0
  TH.retry_next_ms = 0
  TH.dealer_ai = nil
end

-- Function: effective_roll_delay_ms
-- Purpose: Handles effective roll delay ms logic for the Threes script.
local function effective_roll_delay_ms()
  TH.roll_delay_ms = 1000
  return TH.roll_delay_ms
end

-- Function: effective_roll_timeout_ms
-- Purpose: Handles effective roll timeout ms logic for the Threes script.
local function effective_roll_timeout_ms()
  local t = tonumber(TH.roll_timeout_ms) or 2500
  local minByDelay = effective_roll_delay_ms() * 20
  if t < minByDelay then t = minByDelay end
  if t < 2000 then t = 2000 end
  if t > 10000 then t = 10000 end
  TH.roll_timeout_ms = math.floor(t)
  return TH.roll_timeout_ms
end

-- Function: all_held
-- Purpose: Handles all held logic for the Threes script.
local function all_held()
  for i = 1, 5 do
    if not TH.dice[i].held then return false end
  end
  return true
end

-- Function: held_count
-- Purpose: Handles held count logic for the Threes script.
local function held_count()
  local c = 0
  for i = 1, 5 do
    if TH.dice[i].held then c = c + 1 end
  end
  return c
end

-- Function: held_score_so_far
-- Purpose: Handles held score so far logic for the Threes script.
local function held_score_so_far()
  local total = 0
  for i = 1, 5 do
    local d = TH.dice[i]
    if d ~= nil and d.held then
      local v = tonumber(d.value) or 0
      if v ~= 3 then total = total + v end
    end
  end
  return total
end

-- Function: is_slot_pending
-- Purpose: Handles is slot pending logic for the Threes script.
local function is_slot_pending(index)
  for i = 1, #TH.pending_slots do
    if TH.pending_slots[i] == index then return true end
  end
  return false
end

-- Function: dice_word
-- Purpose: Handles dice word logic for the Threes script.
local function dice_word(n)
  return (tonumber(n) or 0) == 1 and "die" or "dice"
end

-- Function: score_from_dice
-- Purpose: Handles score from dice logic for the Threes script.
local function score_from_dice(dice)
  local total = 0
  for i = 1, 5 do
    local v = tonumber((dice[i] and dice[i].value) or 0) or 0
    if v ~= 3 then total = total + v end
  end
  return total
end

-- Function: turn_score
-- Purpose: Handles turn score logic for the Threes script.
local function turn_score()
  return score_from_dice(TH.dice)
end

-- Function: finalize_vs_dealer_round
-- Purpose: Handles finalize vs dealer round logic for the Threes script.
local function finalize_vs_dealer_round()
  table_announce("Dealer locks a score of " .. tostring(TH.dealer_score) .. ".")

  for i = 1, #TH.order do
    local p = TH.order[i]
    local s = tonumber(TH.scores[p]) or 999
    local outcome = "pushes"
    if s < TH.dealer_score then outcome = "wins" end
    if s > TH.dealer_score then outcome = "loses" end
    TH.results[p] = outcome

    local wager = (dealer_get_wager ~= nil) and (tonumber(dealer_get_wager(p)) or 0) or 0
    local delta = 0
    local payoutLabel = ""
    local payoutReason = ""

    if wager > 0 then
      if outcome == "wins" then
        if s == 0 then
          delta = wager * 5
          payoutLabel = "5:1"
          payoutReason = "Triple Zero bonus"
        elseif s >= 1 and s <= 3 then
          delta = math.floor((wager * 3) / 2)
          payoutLabel = "3:2"
          payoutReason = "Low-Roll incentive"
        else
          delta = wager
          payoutLabel = "1:1"
          payoutReason = "Standard Win"
        end
      elseif outcome == "loses" then
        delta = -wager
      end
    end

    local bankText = ""
    if delta ~= 0 and dealer_add_bank ~= nil then
      dealer_add_bank(p, delta)
      local bankNow = (dealer_get_bank ~= nil) and (tonumber(dealer_get_bank(p)) or 0) or 0
      local sign = delta > 0 and "+" or ""
      bankText = " | bank " .. sign .. tostring(delta) .. " => " .. tostring(bankNow)
    end

    if outcome == "wins" and payoutLabel ~= "" then
      table_announce(p .. " wins " .. payoutLabel .. " (" .. payoutReason .. ").")
    elseif outcome == "pushes" then
      table_announce(p .. " pushes (tie = push).")
    end

    table_announce(p .. " " .. outcome .. " vs dealer (" .. tostring(s) .. " vs " .. tostring(TH.dealer_score) .. ")." .. bankText)
  end

  TH.phase = "finished"
  TH.info = "Round over. Dealer scored " .. tostring(TH.dealer_score) .. "."
end

-- Function: start_dealer_ai_turn
-- Purpose: Starts dealer ai turn for the current game flow.
local function start_dealer_ai_turn()
  local dice = {}
  for i = 1, 5 do
    dice[i] = { value = 0, rolled = false, held = false, forced = false }
  end

  TH.dealer_ai = {
    dice = dice,
    phase = "roll_prepare",
    rolled_now = {},
    pending_slots = {},
    eval_index = 1,
    held_this_pass = false,
    next_action_ms = (time_ms ~= nil) and time_ms() or 0,
    roll_inflight = false,
    roll_sent_ms = 0,
  }

  TH.phase = "dealer_turn"
  TH.info = "Dealer is taking a turn..."
  table_announce("Dealer turn starts.")
end

-- Function: process_dealer_ai_turn
-- Purpose: Processes dealer ai turn updates for the current game state.
local function process_dealer_ai_turn()
  local ai = TH.dealer_ai
  if TH.phase ~= "dealer_turn" or ai == nil then return end

  -- Function: ai_unheld_count
  -- Purpose: Handles ai unheld count logic for the Threes script.
  local function ai_unheld_count()
    local n = 0
    for i = 1, 5 do
      if not ai.dice[i].held then n = n + 1 end
    end
    return n
  end

  -- Function: ai_rolled_snapshot
  -- Purpose: Handles ai rolled snapshot logic for the Threes script.
  local function ai_rolled_snapshot()
    local parts = {}
    for _, i in ipairs(ai.rolled_now) do
      local d = ai.dice[i]
      local mark = d.held and "*" or ""
      table.insert(parts, "d" .. tostring(i) .. "=" .. tostring(d.value) .. mark)
    end
    return table.concat(parts, "  ")
  end

  local now = (time_ms ~= nil) and time_ms() or 0
  if now < (ai.next_action_ms or 0) then return end

  if ai.phase == "roll_prepare" then
    local remaining = ai_unheld_count()
    if remaining <= 0 then
      TH.dealer_dice = ai.dice
      TH.dealer_score = score_from_dice(ai.dice)
      TH.dealer_ai = nil
      finalize_vs_dealer_round()
      return
    end

    ai.pending_slots = {}
    ai.rolled_now = {}
    for i = 1, 5 do
      if not ai.dice[i].held then
        table.insert(ai.pending_slots, i)
      end
    end

    ai.roll_inflight = false
    ai.roll_sent_ms = 0
    ai.phase = "roll_wait"
    ai.next_action_ms = now
    table_announce("Dealer rolls " .. tostring(#ai.pending_slots) .. " " .. dice_word(#ai.pending_slots) .. ".")
    return
  end

  if ai.phase == "roll_wait" then
    if ai.roll_inflight and (now - (ai.roll_sent_ms or 0)) >= effective_roll_timeout_ms() then
      ai.roll_inflight = false
      ai.next_action_ms = now + 120
    end

    if (not ai.roll_inflight) and #ai.pending_slots > 0 and now >= (ai.next_action_ms or 0) then
      local channel = normalize_channel(TH.dice_channel)
      if dice_command == nil or not dice_command(channel, 6) then
        TH.info = "Dealer dice command unavailable."
        TH.dealer_ai = nil
        TH.phase = "finished"
        return
      end
      ai.roll_inflight = true
      ai.roll_sent_ms = now
    end

    for _ = 1, 24 do
      if #ai.pending_slots == 0 then break end

      local packet = (chat_poll ~= nil) and chat_poll() or ""
      if packet == nil or packet == "" then break end

      local _, _, _, message = string.match(packet, "^([^|]*)|([^|]*)|([^|]*)|(.*)$")
      if message ~= nil then
        local rolled = (dice_roll_value ~= nil) and dice_roll_value(message) or 0
        local upper = (dice_roll_upper ~= nil) and dice_roll_upper(message) or 0

        if rolled >= 1 and rolled <= 6 and upper == 6 then
          local slot = table.remove(ai.pending_slots, 1)
          local d = ai.dice[slot]
          d.value = rolled
          d.rolled = true
          if rolled == 3 then
            d.held = true
            d.forced = true
          else
            d.held = false
            d.forced = false
          end

          table.insert(ai.rolled_now, slot)
          ai.roll_inflight = false
          ai.roll_sent_ms = 0
          ai.next_action_ms = ((time_ms ~= nil) and time_ms() or now) + effective_roll_delay_ms()
          break
        end
      end
    end

    if #ai.pending_slots > 0 then
      return
    end

    ai.phase = "announce_roll"
    ai.next_action_ms = now + effective_roll_delay_ms()
    return
  end

  if ai.phase == "announce_roll" then
    ai.eval_index = 1
    ai.held_this_pass = false
    ai.phase = "evaluate"
    ai.next_action_ms = now + effective_roll_delay_ms()
    return
  end

  if ai.phase == "evaluate" then
    local forcedParts = {}
    local heldParts = {}

    while ai.eval_index <= #ai.rolled_now do
      local i = ai.rolled_now[ai.eval_index]
      ai.eval_index = ai.eval_index + 1
      local d = ai.dice[i]

      if d.forced then
        table.insert(forcedParts, "3")
      elseif (not d.held) and d.value <= 2 then
        d.held = true
        ai.held_this_pass = true
        table.insert(heldParts, tostring(d.value))
      end
    end

    local holdSummary = {}
    if #forcedParts > 0 then
      table.insert(holdSummary, table.concat(forcedParts, ", "))
    end
    if #heldParts > 0 then
      table.insert(holdSummary, table.concat(heldParts, ", "))
    end
    if #holdSummary > 0 then
      table_announce("Dealer holds " .. table.concat(holdSummary, " | ") .. ".")
    end

    ai.phase = "choose_best"
    ai.next_action_ms = now + effective_roll_delay_ms()
    return
  end

  if ai.phase == "choose_best" then
    if not ai.held_this_pass then
      local best_idx = nil
      local best_val = 99
      for _, i in ipairs(ai.rolled_now) do
        local d = ai.dice[i]
        if not d.held and d.value < best_val then
          best_val = d.value
          best_idx = i
        end
      end
      if best_idx ~= nil then
        ai.dice[best_idx].held = true
        table_announce("Dealer chooses to hold d" .. tostring(best_idx) .. " (" .. tostring(ai.dice[best_idx].value) .. ").")
      end
    end

    ai.phase = "reroll_or_finish"
    ai.next_action_ms = now + effective_roll_delay_ms()
    return
  end

  if ai.phase == "reroll_or_finish" then
    if ai_unheld_count() > 0 then
      ai.phase = "roll_prepare"
      ai.next_action_ms = now + effective_roll_delay_ms()
      return
    end

    TH.dealer_dice = ai.dice
    TH.dealer_score = score_from_dice(ai.dice)
    TH.dealer_ai = nil
    finalize_vs_dealer_round()
    return
  end
end

-- Function: finish_round
-- Purpose: Handles finish round logic for the Threes script.
local function finish_round()
  TH.phase = "finished"

  if TH.play_vs_dealer then
    TH.results = {}
    start_dealer_ai_turn()
    return
  end

  local best = nil
  local winners = {}
  for i = 1, #TH.order do
    local p = TH.order[i]
    local s = tonumber(TH.scores[p]) or 999
    if best == nil or s < best then
      best = s
      winners = { p }
    elseif s == best then
      table.insert(winners, p)
    end
  end

  local who = table.concat(winners, ", ")
  TH.info = "Round over. Winner: " .. who .. " (" .. tostring(best or 0) .. ")"
  announce("winner", { result = who, total = best or 0 })
end

local request_roll_for_unheld

-- Function: finish_turn
-- Purpose: Handles finish turn logic for the Threes script.
local function finish_turn()
  local player = active_player_name()
  if player == "" then return end

  local score = turn_score()
  TH.scores[player] = score
  announce("turn_score", { player = player, total = score })

  TH.active_index = TH.active_index + 1
  if TH.active_index > #TH.order then
    finish_round()
    return
  end

  reset_turn_dice()
  TH.phase = "turn_active"
  local nextPlayer = active_player_name()
  TH.info = nextPlayer .. " to roll."
  announce("turn_start", { player = nextPlayer })
end

-- Function: start_round
-- Purpose: Starts round for the current game flow.
local function start_round()
  TH.order = {}
  TH.scores = {}
  TH.results = {}
  TH.dealer_score = nil
  TH.dealer_dice = {}
  TH.active_index = 1

  local count = dealer_player_count()
  for i = 1, count do
    local name = dealer_player_name(i)
    if name ~= nil and name ~= "" and dealer_is_eligible(name) then
      table.insert(TH.order, name)
    end
  end

  if #TH.order == 0 then
    TH.phase = "idle"
    TH.info = "No eligible players in dealer roster."
    return
  end

  reset_turn_dice()
  TH.phase = "turn_active"
  TH.info = active_player_name() .. " to roll."
  announce("round_start", { total = #TH.order })
  announce("turn_start", { player = active_player_name() })
  -- Immediately prompt the active player to roll
  request_roll_for_unheld()
end

request_roll_for_unheld = function()
  if TH.phase ~= "turn_active" then
    TH.info = "Round is not in an active turn."
    return
  end

  -- If already waiting on rolls, treat button press as a retry nudge with cooldown.
  if TH.awaiting_rolls then
    local now = (time_ms ~= nil) and time_ms() or 0
    local retryAt = tonumber(TH.retry_next_ms) or 0
    if now < retryAt then
      local remain = math.floor((retryAt - now) / 1000)
      if remain < 1 then remain = 1 end
      TH.info = "Retry on cooldown (" .. tostring(remain) .. "s)."
      return
    end

    TH.roll_inflight = false
    TH.roll_sent_ms = 0
    TH.next_roll_ms = now
    local cd = tonumber(TH.retry_cooldown_ms) or 250
    if cd < 100 then cd = 100 end
    if cd > 5000 then cd = 5000 end
    TH.retry_next_ms = now + cd
    TH.info = "Retrying roll dispatch..."
    return
  end

  if TH.must_hold_after_roll and held_count() == 0 then
    TH.info = "You must hold at least one die before rolling again."
    return
  end

  for i = 1, 5 do
    local d = TH.dice[i]
    if d ~= nil and d.auto_recent then
      d.auto_recent = false
    end
  end

  effective_roll_timeout_ms()

  TH.pending_slots = {}
  for i = 1, 5 do
    if not TH.dice[i].held then
      table.insert(TH.pending_slots, i)
    end
  end

  if #TH.pending_slots == 0 then
    TH.ready_to_end_turn = true
    TH.info = "All dice locked. Click End Turn."
    return
  end

  TH.awaiting_rolls = true
  TH.roll_inflight = false
  TH.next_roll_ms = (time_ms ~= nil) and time_ms() or 0
  TH.roll_sent_ms = 0
  TH.turn_roll_count = (tonumber(TH.turn_roll_count) or 0) + 1
  TH.auto_held_this_batch = 0
  TH.ready_to_end_turn = false
  TH.info = active_player_name() .. " rolling " .. tostring(#TH.pending_slots) .. " dice..."

  local heldTotalNow = held_score_so_far()
  local rollNo = tonumber(TH.turn_roll_count) or 0

  -- Keep chat quieter:
  -- - first roll: no extra roll line (round_start + turn_start already announced)
  -- - later rolls: one line only, then wait 1s before first die dispatch
  if rollNo >= 2 then
    if heldTotalNow > 0 then
      announce("roll_hold_and_count", { player = active_player_name(), total = heldTotalNow, result = #TH.pending_slots })
    else
      announce("roll_count", { player = active_player_name(), total = #TH.pending_slots })
    end
    TH.next_roll_ms = ((time_ms ~= nil) and time_ms() or 0) + effective_roll_delay_ms()
  end
end

-- Function: process_dice_chat
-- Purpose: Processes dice chat updates for the current game state.
local function process_dice_chat()
  if chat_poll == nil then return end
  if not TH.awaiting_rolls then
    return
  end

  if #TH.pending_slots == 0 then
    TH.awaiting_rolls = false
    if all_held() then
      TH.ready_to_end_turn = true
      TH.info = "All dice locked. Click End Turn."
      return
    end
  end

  local now = (time_ms ~= nil) and time_ms() or 0

  if TH.roll_inflight and (now - (TH.roll_sent_ms or 0)) >= effective_roll_timeout_ms() then
    TH.roll_inflight = false
    TH.next_roll_ms = now + 120
  end

  if (not TH.roll_inflight) and #TH.pending_slots > 0 and now >= (TH.next_roll_ms or 0) then
    local channel = normalize_channel(TH.dice_channel)
    if dice_command == nil or not dice_command(channel, 6) then
      TH.info = "Dice command unavailable."
      TH.awaiting_rolls = false
      TH.pending_slots = {}
      TH.roll_inflight = false
      return
    end
    TH.roll_inflight = true
    TH.roll_sent_ms = now
  end

  for _ = 1, 24 do
    if #TH.pending_slots == 0 then break end

    local packet = chat_poll()
    if packet == nil or packet == "" then break end

    local name, world, channel, message = string.match(packet, "^([^|]*)|([^|]*)|([^|]*)|(.*)$")
    if message ~= nil then
      local rolled = (dice_roll_value ~= nil) and dice_roll_value(message) or 0
      local upper = (dice_roll_upper ~= nil) and dice_roll_upper(message) or 0
      -- If the Random! bot embeds the player name in the message like "(Player) Random! (1-6) 3",
      -- prefer that embedded name for attribution instead of the sender (Random!).
      local embedded = string.match(message, "^%s*%(([^)]+)%)%s*Random!") or string.match(message, "^%s*%(([^)]+)%)")
      local senderForMatch = name
      if embedded and embedded ~= "" then
        senderForMatch = embedded
      end

      if rolled >= 1 and rolled <= 6 and upper == 6 then
        local slot = table.remove(TH.pending_slots, 1)
        local d = TH.dice[slot]
        d.value = rolled
        d.rolled = true

        if rolled == 3 then
          d.held = true
          d.forced = true
          d.auto_recent = true
          TH.auto_held_this_batch = (TH.auto_held_this_batch or 0) + 1
        else
          d.held = false
          d.forced = false
          d.auto_recent = false
          if held_count() == 4 then
            d.held = true
          end
        end

        TH.roll_inflight = false
        TH.roll_sent_ms = 0
        TH.next_roll_ms = ((time_ms ~= nil) and time_ms() or now) + effective_roll_delay_ms()
        break
      end
    end

    ::continue_packet::
  end

  if #TH.pending_slots > 0 then
    return
  end

  TH.awaiting_rolls = false
  TH.roll_inflight = false
  TH.roll_sent_ms = 0

  if all_held() then
    TH.ready_to_end_turn = true
    TH.info = "All dice locked. Click End Turn."
    return
  end

  TH.ready_to_end_turn = false
  TH.must_hold_after_roll = ((TH.auto_held_this_batch or 0) == 0)
  local heldNow = held_count()
  local heldTotal = held_score_so_far()
  local showHeldTotal = ((tonumber(TH.turn_roll_count) or 0) >= 2) and (heldNow > 0)

  if showHeldTotal then
    local prefix = "Held total so far: " .. tostring(heldTotal) .. ". "
    if TH.must_hold_after_roll then
      TH.info = prefix .. "Hold at least one die, then roll remaining dice."
    else
      TH.info = prefix .. "Roll again or hold more dice."
    end
  else
    if TH.must_hold_after_roll then
      TH.info = "Hold at least one die, then roll remaining dice."
    else
      TH.info = "A 3 was auto-held. Roll again or hold more dice."
    end
  end
end

-- Function: hold_die
-- Purpose: Handles hold die logic for the Threes script.
local function hold_die(index)
  if TH.phase ~= "turn_active" then return end
  if TH.awaiting_rolls then return end
  local d = TH.dice[index]
  if d == nil or not d.rolled then return end

  if d.held then
    if d.forced then return end
    d.held = false
    d.auto_recent = false
    local heldNow = held_count()
    if heldNow == 0 then
      TH.must_hold_after_roll = true
      TH.ready_to_end_turn = false
      TH.info = "Hold at least one die, then roll remaining dice."
    else
      TH.must_hold_after_roll = false
      TH.ready_to_end_turn = false
      TH.info = "Held total so far: " .. tostring(held_score_so_far()) .. ". Roll again or hold more dice."
    end
    return
  end

  d.held = true
  d.forced = (d.value == 3)
  d.auto_recent = false
  TH.must_hold_after_roll = false

  if all_held() then
    TH.ready_to_end_turn = true
    TH.info = "All dice locked. Click End Turn."
    return
  end

  TH.ready_to_end_turn = false
  TH.info = "Held total so far: " .. tostring(held_score_so_far()) .. ". Roll again or hold more dice."
end

-- Function: fixed_button_label
-- Purpose: Handles fixed button label logic for the Threes script.
local function fixed_button_label(text, id)
  local t = tostring(text or "")
  local width = 6
  local pad = width - string.len(t)
  if pad < 0 then pad = 0 end
  local left = math.floor(pad / 2)
  local right = pad - left
  return string.rep(" ", left + 1) .. t .. string.rep(" ", right + 1) .. "##" .. id
end

-- Function: draw_die_face
-- Purpose: Handles draw die face logic for the Threes script.
local function draw_die_face(index)
  local d = TH.dice[index]
  local txt = "-"
  if d.rolled then txt = tostring(d.value) end

  local r, g, b = 0.28, 0.28, 0.32
  if d.held then
    if d.forced and d.auto_recent then
      r, g, b = 0.55, 0.35, 0.12
    else
      r, g, b = 0.2, 0.45, 0.22
    end
  elseif d.rolled and d.value == 3 then
    r, g, b = 0.35, 0.42, 0.2
  end

  ui_button_colored_sized("[" .. txt .. "]##die_face_" .. tostring(index), 56, 0, r, g, b, 1.0)
end

-- Function: draw_die_control
-- Purpose: Handles draw die control logic for the Threes script.
local function draw_die_control(index)
  local d = TH.dice[index]

  if TH.awaiting_rolls and is_slot_pending(index) then
    ui_button_colored_sized("[...]##hold_wait_roll_" .. tostring(index), 56, 0, 0.22, 0.22, 0.26, 1.0)
    return
  end

  if d.held then
    local label = d.forced and "[*]" or "[U]"
    local r, g, b = d.forced and 0.2 or 0.3, 0.45, d.forced and 0.22 or 0.25
    if ui_button_colored_sized(label .. "##held_" .. tostring(index), 56, 0, r, g, b, 1.0) then
      hold_die(index)
    end
  elseif d.rolled then
    if ui_button_colored_sized("[H]##hold_" .. tostring(index), 56, 0, 0.55, 0.45, 0.2, 1.0) then
      hold_die(index)
    end
  else
    ui_button_colored_sized("[-]##hold_wait_" .. tostring(index), 56, 0, 0.2, 0.2, 0.24, 1.0)
  end
end

-- Function: draw_config_ui
-- Purpose: Renders the configuration panel where the dealer edits script settings.
function draw_config_ui()
  ui_text_colored("Threes Config", 0.8, 0.95, 0.8, 1.0)
  ui_separator()
  ui_text("Config status: " .. tostring(TH.config_status or ""))

  TH.dice_channel = normalize_channel(TH.dice_channel)
  ui_text("Dice channel: " .. TH.dice_channel)
  if ui_button("Use Echo##th_cfg_echo") then TH.dice_channel = "echo" end
  ui_same_line()
  if ui_button("Use Say##th_cfg_say") then TH.dice_channel = "say" end
  ui_same_line()
  if ui_button("Use Party##th_cfg_party") then TH.dice_channel = "party" end
  ui_same_line()
  if ui_button("Use Shout##th_cfg_shout") then TH.dice_channel = "shout" end
  ui_same_line()
  if ui_button("Use Yell##th_cfg_yell") then TH.dice_channel = "yell" end

  TH.dealer_rolls_for_players = true
  ui_text("Dealer rolls all dice for players.")
  ui_text("Roll pacing is fixed at 1 second between each die roll.")

  local vsDealer = TH.play_vs_dealer ~= false
  vsDealer = ui_checkbox("Players vs Dealer AI", vsDealer)
  TH.play_vs_dealer = vsDealer

  ui_text("Rules: Roll 5 dice. Keep at least one each roll. 3s auto-hold and score 0. Lowest total wins.")

  ui_separator()
  ui_text_colored("Chat templates (editable)", 0.8, 0.95, 0.8, 1.0)
  local t = TH.chat_templates or {}
  t.round_start = ui_input_text("Round start template##th_tpl_round_start", t.round_start or "", 256)
  t.turn_start = ui_input_text("Turn start template##th_tpl_turn_start", t.turn_start or "", 256)
  t.turn_score = ui_input_text("Turn score template##th_tpl_turn_score", t.turn_score or "", 256)
  t.roll_request = ui_input_text("Roll request template##th_tpl_rollreq", t.roll_request or "", 256)
  t.roll_count = ui_input_text("Roll count template##th_tpl_rollcount", t.roll_count or "", 256)
  t.roll_result = ui_input_text("Roll result template##th_tpl_rollres", t.roll_result or "", 256)
  t.roll_hold_and_count = ui_input_text("Roll hold+count template##th_tpl_roll_hold_count", t.roll_hold_and_count or "", 256)
  t.winner = ui_input_text("Winner template##th_tpl_winner", t.winner or "", 256)
  TH.chat_templates = t

  ui_separator()
  if ui_button("Save Config##th_cfg_save") then
    save_config_file()
  end
  ui_same_line()
  if ui_button("Load Config##th_cfg_load") then
    load_config_file()
  end
end

-- Function: draw_ui
-- Purpose: Renders the main game UI and runs the per-frame update flow.
function draw_ui()
  if TH.dice == nil or #TH.dice < 5 then
    reset_turn_dice()
  end

  process_dice_chat()
  process_dealer_ai_turn()

  ui_text_colored("Threes", 1.0, 0.9, 0.4, 1.0)
  ui_separator()

  ui_text_colored("--- INSTRUCTIONS ---", 0.7, 1.0, 0.7, 1.0)
  ui_text("1) Click New Round to start.")
  ui_text("2) On your turn, the dealer clicks Roll Unheld Dice.")
  ui_text("3) Hold at least one die between rolls.")
  ui_text("4) 3s auto-hold and count as 0 points.")
  ui_text("5) End Turn when all 5 dice are locked.")
  ui_text("6) Lowest total wins.")
  ui_separator()

  if ui_button("New Round##th_new") then
    start_round()
  end
  ui_same_line()
  if ui_button("Roll Unheld Dice##th_roll") then
    request_roll_for_unheld()
  end
  if TH.phase == "turn_active" and TH.ready_to_end_turn then
    ui_same_line()
    if ui_button("End Turn##th_end_turn") then
      finish_turn()
    end
  end

  ui_text("Status: " .. tostring(TH.phase) .. " | " .. tostring(TH.info))

  local current = active_player_name()
  if current ~= "" then
    ui_text("Active player: " .. current)
    if TH.phase == "turn_active" and TH.awaiting_rolls then
      ui_text("Dealer is rolling dice for " .. current .. "...")
    end
  end

  ui_separator()
  ui_text_colored("Dice", 0.9, 0.95, 1.0, 1.0)

  for i = 1, 5 do
    draw_die_face(i)
    if i < 5 then ui_same_line() end
  end

  for i = 1, 5 do
    draw_die_control(i)
    if i < 5 then ui_same_line() end
  end

  ui_text("[H]=hold  [U]=unhold  [*]=forced hold (3)")
  ui_separator()
  ui_text_colored("Scores", 1.0, 1.0, 0.8, 1.0)

  if TH.play_vs_dealer and TH.dealer_score ~= nil then
    ui_text("Dealer -> " .. tostring(TH.dealer_score))
  end

  if #TH.order == 0 then
    ui_text("(no active round)")
  else
    for i = 1, #TH.order do
      local p = TH.order[i]
      local s = TH.scores[p]
      if s == nil then
        ui_text(p .. " -> (pending)")
      else
        local extra = ""
        if TH.play_vs_dealer and TH.results[p] ~= nil then
          extra = " [" .. tostring(TH.results[p]) .. "]"
        end
        ui_text(p .. " -> " .. tostring(s) .. extra)
      end
    end
  end

  ui_separator()
  if ui_collapsing_header ~= nil then
    TH.show_help = ui_collapsing_header("Threes Help##th_help")
  end
  if TH.show_help == true then
    ui_text_colored("Commands", 0.9, 0.95, 1.0, 1.0)
    ui_text("/casino start  - Start a new Threes round.")
    ui_text("/casino roll   - Roll unheld dice for active player.")
    ui_text("/casino end    - End active turn when all dice are locked.")
    ui_separator()
    ui_text_colored("Tips", 0.9, 0.95, 1.0, 1.0)
    ui_text("3s are auto-held and score 0.")
    ui_text("Lowest total wins; with Dealer AI enabled each player result is W/L/Push.")
  end
end
