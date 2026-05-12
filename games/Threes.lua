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

    play_vs_dealer = true,
    dealer_score = nil,
    dealer_dice = {},
    dealer_ai = nil,

    dice_channel = "party",

    chat_templates = {
      round_start = "Threes begins with <total> players.",
      turn_start = "<player>'s turn starts.",
      turn_score = "<player> locks in a score of <total>.",
      winner = "Threes winner: <result> with <total>.",
    }
  }
end

local function output_channel_name()
  if default_chat_channel ~= nil then
    local ch = default_chat_channel()
    if ch == "echo" or ch == "say" or ch == "party" then
      return ch
    end
  end
  return "party"
end

local function normalize_channel(ch)
  local c = string.lower(tostring(ch or "party"))
  if c ~= "echo" and c ~= "say" and c ~= "party" then
    return "party"
  end
  return c
end

local function table_announce(message)
  local msg = message or ""
  if msg == "" then return end

  if chat_send ~= nil then
    chat_send(output_channel_name(), msg)
  else
    dealer_party(msg)
  end
end

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

local function announce(key, ctx)
  local t = TH.chat_templates or {}
  local template = t[key]
  if template == nil or template == "" then return end
  table_announce(fmt(template, ctx))
end

local function active_player_name()
  if TH.active_index < 1 or TH.active_index > #TH.order then return "" end
  return TH.order[TH.active_index] or ""
end

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
  TH.dealer_ai = nil
end

local function effective_roll_delay_ms()
  local v = tonumber(TH.roll_delay_ms) or 125
  if v < 50 then v = 50 end
  if v > 5000 then v = 5000 end
  TH.roll_delay_ms = math.floor(v)
  return TH.roll_delay_ms
end

local function effective_roll_timeout_ms()
  local t = tonumber(TH.roll_timeout_ms) or 2500
  local minByDelay = effective_roll_delay_ms() * 20
  if t < minByDelay then t = minByDelay end
  if t < 2000 then t = 2000 end
  if t > 10000 then t = 10000 end
  TH.roll_timeout_ms = math.floor(t)
  return TH.roll_timeout_ms
end

local function all_held()
  for i = 1, 5 do
    if not TH.dice[i].held then return false end
  end
  return true
end

local function held_count()
  local c = 0
  for i = 1, 5 do
    if TH.dice[i].held then c = c + 1 end
  end
  return c
end

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

local function is_slot_pending(index)
  for i = 1, #TH.pending_slots do
    if TH.pending_slots[i] == index then return true end
  end
  return false
end

local function dice_word(n)
  return (tonumber(n) or 0) == 1 and "die" or "dice"
end

local function score_from_dice(dice)
  local total = 0
  for i = 1, 5 do
    local v = tonumber((dice[i] and dice[i].value) or 0) or 0
    if v ~= 3 then total = total + v end
  end
  return total
end

local function turn_score()
  return score_from_dice(TH.dice)
end

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
    local payout_mult = 0
    local margin = (tonumber(TH.dealer_score) or 0) - s
    
    if wager > 0 then
      if outcome == "wins" then
        if s == 0 then
          payout_mult = 25
        elseif margin >= 20 then
          payout_mult = 10
        elseif margin >= 15 then
          payout_mult = 5
        elseif margin >= 10 then
          payout_mult = 3
        elseif margin >= 5 then
          payout_mult = 2
        else
          payout_mult = 1
        end
        delta = wager * payout_mult
      elseif outcome == "loses" then
        delta = -wager
      end
    end

    local bankText = ""
    if delta ~= 0 and dealer_add_bank ~= nil then
      dealer_add_bank(p, delta)
      local bankNow = (dealer_get_bank ~= nil) and (tonumber(dealer_get_bank(p)) or 0) or 0
      local sign = delta > 0 and "+" or ""
      bankText = " | bank " .. sign .. tostring(delta) .. ") => " .. tostring(bankNow)
    end

    if outcome == "wins" and payout_mult > 0 then
      if payout_mult == 25 then
        table_announce(p .. " hits the JACKPOT (0 vs dealer) at 25:1!")
      else
        table_announce(p .. " wins at " .. tostring(payout_mult) .. ":1 (margin " .. tostring(margin) .. ").")
      end
    end

    table_announce(p .. " " .. outcome .. " vs dealer (" .. tostring(s) .. " vs " .. tostring(TH.dealer_score) .. ")." .. bankText)
  end

  TH.phase = "finished"
  TH.info = "Round over. Dealer scored " .. tostring(TH.dealer_score) .. "."
end

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

local function process_dealer_ai_turn()
  local ai = TH.dealer_ai
  if TH.phase ~= "dealer_turn" or ai == nil then return end

  local function ai_unheld_count()
    local n = 0
    for i = 1, 5 do
      if not ai.dice[i].held then n = n + 1 end
    end
    return n
  end

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
      if dice_command == nil or not dice_command("party", 6) then
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
end

local function request_roll_for_unheld()
  if TH.phase ~= "turn_active" then return end
  if TH.awaiting_rolls then return end
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
end

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
        TH.next_roll_ms = ((time_ms ~= nil) and time_ms() or now) + 20
        break
      end
    end
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
    table_announce(active_player_name() .. " held total so far: " .. tostring(heldTotal) .. ".")
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

local function fixed_button_label(text, id)
  local t = tostring(text or "")
  local width = 6
  local pad = width - string.len(t)
  if pad < 0 then pad = 0 end
  local left = math.floor(pad / 2)
  local right = pad - left
  return string.rep(" ", left + 1) .. t .. string.rep(" ", right + 1) .. "##" .. id
end

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

function draw_config_ui()
  ui_text_colored("Threes Config", 0.8, 0.95, 0.8, 1.0)
  ui_separator()

  TH.dice_channel = normalize_channel(TH.dice_channel)
  ui_text("Dice channel: " .. TH.dice_channel)
  if ui_button("Use Echo##th_cfg_echo") then TH.dice_channel = "echo" end
  ui_same_line()
  if ui_button("Use Say##th_cfg_say") then TH.dice_channel = "say" end
  ui_same_line()
  if ui_button("Use Party##th_cfg_party") then TH.dice_channel = "party" end

  local rollDelay = effective_roll_delay_ms()
  rollDelay = ui_input_int("Roll delay (ms)##th_roll_delay", rollDelay)
  TH.roll_delay_ms = rollDelay
  effective_roll_delay_ms()
  ui_text("Used for player roll pacing and dealer narration pacing.")

  local vsDealer = TH.play_vs_dealer ~= false
  vsDealer = ui_checkbox("Players vs Dealer AI", vsDealer)
  TH.play_vs_dealer = vsDealer

  ui_text("Rules: Roll 5 dice. Keep at least one each roll. 3s auto-hold and score 0. Lowest total wins.")
end

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
  ui_text("2) On your turn, click Roll Unheld Dice.")
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
end
