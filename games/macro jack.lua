-- --- Hardcoded Defaults Fallback ---
local default_templates = {
  start = "Macro blackjack round started for <total> players.",
  dealer_draw = "Dealer draws <card> (total <total>).",
  dealer_first = "Dealer draws a <card>.",
  player_draw2 = "<player> draws a <card>,",
  player_draw = "<player> draws <card> (total <total>).",
  player_hit = "<player> hits <card> (total <total>).",
  player_stand = "<player> stands (total <total>).",
  player_double = "<player> doubles and draws <card> (total <total>).",
  player_split = "<player> splits. Bet <bet>. Bank <bank>.",
  player_bust = "<player> busts.",
  result_push = "<player> push (<total> vs dealer <dealer_total>). Bet <bet>. Bank <bank>.",
  result_lose_bj = "<player> loses (dealer blackjack) (<total> vs dealer <dealer_total>). Bet <bet>. Bank <bank>.",
  result_bj = "<player> blackjack! (<total> vs dealer <dealer_total>). Bet <bet>. Bank <bank>.",
  result_win_bust = "<player> wins! (dealer bust) (<total> vs dealer <dealer_total>). Bet <bet>. Bank <bank>.",
  result_win = "<player> wins! (<total> vs dealer <dealer_total>). Bet <bet>. Bank <bank>.",
  result_lose = "<player> loses (<total> vs dealer <dealer_total>). Bet <bet>. Bank <bank>.",
  err_dd_disabled = "Double down is disabled in settings.",
  err_dd_cards = "Can only double down on an initial 2-card hand.",
  err_dd_das = "Double down after split is disabled.",
  err_dd_funds = "Insufficient bank balance to double down (Needs <bet>, Has <bank>).",
  err_split_max = "Maximum split limit reached (<total>).",
  err_split_cards = "Can only split on an initial 2-card hand.",
  err_split_aces = "Splitting Aces is disabled.",
  err_split_value = "Cards must be equal rank or value to split.",
  err_split_funds = "Insufficient bank balance to split (Needs <bet>, Has <bank>).",
}

if MBJ == nil then
  MBJ = {
    phase = "idle",
    info = "Use /casino bjstart to begin.",
    import_status = "No string imported yet.",
    players = {},
    order = {},
    active_index = 1,
    dealer = { cards = {} },
    round_active = false,
    action_history = {},
    config = {
      min_bet = 10,
      max_bet = 10000,
      allow_double = true,
      allow_double_after_split = true,
      max_splits = 2,
      split_aces = false,
      blackjack_payout_x100 = 150,
    },
    draw = {
      channel = "party",
      delay_ms = 1000,
      initial_deal_delay_ms = 1000,
      reveal_delay_ms = 1000,
      timeout_ms = 1500,
      pending = {},
      active = nil,
      inflight = false,
      sent_ms = 0,
      next_ms = 0,
      next_delay_ms = nil,
      resolved_cb = nil,
      resolved_roll = nil,
      resolved_at = 0,
    },
    chat_templates = {},
    share_blob = ""
  }
end

-- Ensure memory structures exist
if not MBJ.config then MBJ.config = {} end
if not MBJ.chat_templates then MBJ.chat_templates = {} end

-- Restore missing chat templates to memory if they got wiped
for k, v in pairs(default_templates) do
  if MBJ.chat_templates[k] == nil or MBJ.chat_templates[k] == "" then 
    MBJ.chat_templates[k] = v 
  end
end

-- ==========================================
-- IMPORT / EXPORT LOGIC
-- ==========================================
local function export_blob()
  local s = "return {config={"
  for k, v in pairs(MBJ.config) do
    if type(v) == "boolean" then
      s = s .. k .. "=" .. tostring(v) .. ","
    else
      s = s .. k .. "=" .. tostring(tonumber(v) or 0) .. ","
    end
  end
  s = s .. "},chat_templates={"
  for k, v in pairs(MBJ.chat_templates) do
    -- Uses [=[ ]=] to completely bypass FFXIV string destruction
    s = s .. k .. "=[=[" .. tostring(v or "") .. "]=],"
  end
  s = s .. "}}"
  
  -- Flattening the string so it's easy to triple-click and copy
  s = string.gsub(s, "\n", "")
  s = string.gsub(s, "\r", "")
  return s
end

local function import_blob(str)
  if not str or str == "" then return "Error: Input text box is empty." end
  
  local loader = loadstring or load
  local fn, err = loader(tostring(str))
  if not fn then return "Error (Syntax): " .. tostring(err) end
  
  local success, data = pcall(fn)
  if not success then return "Error (Runtime): " .. tostring(data) end
  if type(data) ~= "table" then return "Error: Valid string, but did not contain config table." end
  
  if data.config then
    for k, v in pairs(data.config) do MBJ.config[k] = v end
  end
  if data.chat_templates then
    for k, v in pairs(data.chat_templates) do MBJ.chat_templates[k] = v end
  end
  
  return "SUCCESS: Configuration applied successfully!"
end

-- ==========================================
-- FLUSH CHAT QUEUE: Prevents reading old rolls
-- ==========================================
local function flush_chat()
  if chat_poll ~= nil then
    for _ = 1, 500 do
      local p = chat_poll()
      if p == nil or p == "" then break end
    end
  end
end

-- ==========================================
-- GAME LOGIC
-- ==========================================
local function output_channel_name()
  if default_chat_channel ~= nil then
    local ch = default_chat_channel()
    if ch == "echo" or ch == "say" or ch == "party" then return ch end
  end
  return "party"
end

local function table_announce(msg)
  local text = tostring(msg or "")
  if text == "" then return end
  if chat_send ~= nil then chat_send(output_channel_name(), text) else dealer_party(text) end
end

local function fmt(template, ctx)
  if chat_format ~= nil then
    return chat_format(template or "", tostring((ctx and ctx.player) or ""), tonumber((ctx and ctx.bet) or 0) or 0, tonumber((ctx and ctx.bank) or 0) or 0, tostring((ctx and ctx.card) or ""), tonumber((ctx and ctx.total) or 0) or 0, tonumber((ctx and ctx.dealer_total) or 0) or 0, tostring((ctx and ctx.result) or ""))
  end

  local msg = tostring(template or "")
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
  local template = (MBJ.chat_templates or {})[key]
  if template == nil or template == "" then 
    template = default_templates[key]
  end
  if template == nil or template == "" then return end
  table_announce(fmt(template, ctx))
end

local function rank_name(v)
  local n = tonumber(v) or 0
  if n == 1 then return "A" end
  if n == 11 then return "J" end
  if n == 12 then return "Q" end
  if n == 13 then return "K" end
  return tostring(n)
end

local function card_value(v)
  local n = tonumber(v) or 0
  if n == 1 then return 11 end
  if n >= 10 then return 10 end
  return n
end

local function hand_total(cards)
  local total = 0
  local aces = 0
  for i = 1, #cards do
    local v = tonumber(cards[i]) or 0
    total = total + card_value(v)
    if v == 1 then aces = aces + 1 end
  end
  while total > 21 and aces > 0 do
    total = total - 10
    aces = aces - 1
  end
  return total
end

local function is_natural_blackjack(hand)
  if hand == nil or hand.cards == nil then return false end
  if #hand.cards ~= 2 then return false end
  if hand.from_split == true then return false end
  return hand_total(hand.cards) == 21
end

local function active_player_name()
  if MBJ.active_index < 1 or MBJ.active_index > #MBJ.order then return "" end
  return MBJ.order[MBJ.active_index] or ""
end

local function ensure_player(name)
  if MBJ.players[name] == nil then
    MBJ.players[name] = { hands = {}, hand_index = 1, wager = 0, splits_used = 0 }
  end
  return MBJ.players[name]
end

local function active_hand(p)
  if p == nil then return nil end
  local hi = p.hand_index or 1
  if hi < 1 then hi = 1 end
  return p.hands[hi]
end

local function label_for(name, p, handIndex)
  local hi = handIndex or (p and p.hand_index) or 1
  if p ~= nil and p.hands ~= nil and #p.hands > 1 then
    return name .. " [H" .. tostring(hi) .. "]"
  end
  return name
end

local function next_active_hand()
  while MBJ.active_index <= #MBJ.order do
    local name = MBJ.order[MBJ.active_index]
    local p = MBJ.players[name]
    if p == nil then
      MBJ.active_index = MBJ.active_index + 1
    else
      while p.hand_index <= #p.hands do
        local h = p.hands[p.hand_index]
        if h ~= nil and not h.finished then return end
        p.hand_index = p.hand_index + 1
      end
      MBJ.active_index = MBJ.active_index + 1
    end
  end
end

local function get_double_restriction(name, p, h)
  if not MBJ.config.allow_double then return "err_dd_disabled" end
  if p == nil or h == nil then return nil end
  if #h.cards ~= 2 or h.doubled then return "err_dd_cards" end
  if h.from_split == true and not MBJ.config.allow_double_after_split then return "err_dd_das" end
  local bank = (dealer_get_bank ~= nil) and (tonumber(dealer_get_bank(name)) or 0) or 0
  if bank < (tonumber(h.wager) or 0) then return "err_dd_funds" end
  return nil
end

local function can_double(name, p, h)
  return get_double_restriction(name, p, h) == nil
end

local function get_split_restriction(name, p, h)
  if p == nil or h == nil then return nil end
  if p.splits_used >= (tonumber(MBJ.config.max_splits) or 0) then return "err_split_max" end
  if #h.cards ~= 2 then return "err_split_cards" end
  local c1 = tonumber(h.cards[1]) or 0
  local c2 = tonumber(h.cards[2]) or 0
  local sameRank = (c1 == c2)
  local bothTenValue = (card_value(c1) == 10 and card_value(c2) == 10)
  if not sameRank and not bothTenValue then return "err_split_value" end
  if tonumber(h.cards[1]) == 1 and not MBJ.config.split_aces then return "err_split_aces" end
  local bank = (dealer_get_bank ~= nil) and (tonumber(dealer_get_bank(name)) or 0) or 0
  if bank < (tonumber(h.wager) or 0) then return "err_split_funds" end
  return nil
end

local function can_split(name, p, h)
  return get_split_restriction(name, p, h) == nil
end

local function effective_draw_delay_ms()
  local v = tonumber(MBJ.draw.delay_ms) or 350
  if v < 25 then v = 25 end
  if v > 5000 then v = 5000 end
  MBJ.draw.delay_ms = math.floor(v)
  return MBJ.draw.delay_ms
end

local function effective_initial_deal_delay_ms()
  local v = tonumber(MBJ.draw.initial_deal_delay_ms) or 1000
  if v < 100 then v = 100 end
  if v > 5000 then v = 5000 end
  MBJ.draw.initial_deal_delay_ms = math.floor(v)
  return MBJ.draw.initial_deal_delay_ms
end

local function effective_draw_timeout_ms()
  local t = tonumber(MBJ.draw.timeout_ms) or 1500
  local minByDelay = effective_draw_delay_ms() * 4
  if t < minByDelay then t = minByDelay end
  if t < 900 then t = 900 end
  if t > 6000 then t = 6000 end
  MBJ.draw.timeout_ms = math.floor(t)
  return MBJ.draw.timeout_ms
end

local function effective_reveal_delay_ms()
  local v = tonumber(MBJ.draw.reveal_delay_ms) or 1000
  if v < 100 then v = 100 end
  if v > 5000 then v = 5000 end
  MBJ.draw.reveal_delay_ms = math.floor(v)
  return MBJ.draw.reveal_delay_ms
end

local function enqueue_draw(on_card)
  if on_card == nil then return end
  table.insert(MBJ.draw.pending, on_card)
end

local function process_pending_draws()
  local d = MBJ.draw
  if d == nil then return end

  effective_draw_timeout_ms()
  effective_initial_deal_delay_ms()
  effective_reveal_delay_ms()

  local now = (time_ms ~= nil) and time_ms() or 0

  if d.resolved_cb ~= nil and now >= (d.resolved_at or 0) then
    local cb = d.resolved_cb
    local rolled = d.resolved_roll
    d.resolved_cb = nil
    d.resolved_roll = nil
    d.resolved_at = 0
    if cb ~= nil then cb(rolled) end
    now = (time_ms ~= nil) and time_ms() or now
  end

  if d.active == nil and d.resolved_cb == nil and #d.pending > 0 then
    d.active = table.remove(d.pending, 1)
    d.inflight = false
    d.sent_ms = 0
  end

  if d.active == nil then return end

  if d.inflight and (now - (d.sent_ms or 0)) >= effective_draw_timeout_ms() then
    d.inflight = false
    d.next_ms = now + 60
  end

  if (not d.inflight) and now >= (d.next_ms or 0) then
    local ch = tostring(d.channel or "party")
    if dice_command == nil or not dice_command(ch, 13) then
      MBJ.info = "Dice command unavailable (/dice " .. ch .. " 13)."
      MBJ.phase = "idle"
      d.pending = {}
      d.active = nil
      d.inflight = false
      d.resolved_cb = nil
      d.resolved_roll = nil
      d.resolved_at = 0
      return
    end
    d.inflight = true
    d.sent_ms = now
  end

  for _ = 1, 24 do
    local packet = (chat_poll ~= nil) and chat_poll() or ""
    if packet == nil or packet == "" then break end

    local _, _, _, message = string.match(packet, "^([^|]*)|([^|]*)|([^|]*)|(.*)$")
    if message ~= nil then
      local rolled = (dice_roll_value ~= nil) and dice_roll_value(message) or 0
      local upper = (dice_roll_upper ~= nil) and dice_roll_upper(message) or 0
      if rolled >= 1 and rolled <= 13 and upper == 13 then
        local cb = d.active
        d.active = nil
        d.inflight = false
        d.sent_ms = 0
        local nextDelay = tonumber(d.next_delay_ms) or effective_draw_delay_ms()
        d.next_delay_ms = nil
        d.next_ms = ((time_ms ~= nil) and time_ms() or now) + nextDelay
        if cb ~= nil then
          d.resolved_cb = cb
          d.resolved_roll = rolled
          d.resolved_at = ((time_ms ~= nil) and time_ms() or now) + effective_reveal_delay_ms()
        end
        break
      end
    end
  end
end

local function settle_results()
  local dealer_total = hand_total(MBJ.dealer.cards)
  local dealer_natural = (#MBJ.dealer.cards == 2 and dealer_total == 21)
  local dealer_bust = dealer_total > 21

  for i = 1, #MBJ.order do
    local name = MBJ.order[i]
    local p = MBJ.players[name]
    if p ~= nil then
      for hi = 1, #p.hands do
        local h = p.hands[hi]
        if h ~= nil then
          local pt = hand_total(h.cards)
          local wager = tonumber(h.wager or p.wager) or 0
          local player_natural = is_natural_blackjack(h)

          local template_key = "result_push"
          local delta = 0

          if h.bust then
            template_key = "player_bust"
            delta = -wager
          elseif player_natural and dealer_natural then
            template_key = "result_push"
          elseif dealer_natural then
            template_key = "result_lose_bj"
            delta = -wager
          elseif player_natural then
            template_key = "result_bj"
            delta = math.floor((wager * (MBJ.config.blackjack_payout_x100 or 150)) / 100)
          elseif dealer_bust then
            template_key = "result_win_bust"
            delta = wager
          elseif pt > dealer_total then
            template_key = "result_win"
            delta = wager
          elseif pt < dealer_total then
            template_key = "result_lose"
            delta = -wager
          else
            template_key = "result_push"
          end

          if delta ~= 0 and dealer_add_bank ~= nil then dealer_add_bank(name, delta) end

          local bank = (dealer_get_bank ~= nil) and (tonumber(dealer_get_bank(name)) or 0) or 0
          announce(template_key, {
            player = label_for(name, p, hi),
            total = pt,
            dealer_total = dealer_total,
            bet = wager,
            bank = bank,
          })
        end
      end
    end
  end

  MBJ.phase = "settled"
  MBJ.round_active = false
  MBJ.info = "Resolved. Dealer total " .. tostring(dealer_total)
end

local function start_round()
  flush_chat() -- Empties old dice rolls from previous tests/games
  
  MBJ.players = {}
  MBJ.order = {}
  MBJ.active_index = 1
  MBJ.dealer.cards = {}
  MBJ.round_active = true
  MBJ.draw.pending = {}
  MBJ.draw.active = nil
  MBJ.draw.inflight = false
  MBJ.draw.sent_ms = 0
  MBJ.draw.next_ms = 0
  MBJ.draw.resolved_cb = nil
  MBJ.draw.resolved_roll = nil
  MBJ.draw.resolved_at = 0

  local count = dealer_player_count()
  for i = 1, count do
    local name = dealer_player_name(i)
    if name ~= nil and name ~= "" and dealer_is_eligible(name) then
      table.insert(MBJ.order, name)
      local p = ensure_player(name)
      local wager = (dealer_get_wager ~= nil) and (tonumber(dealer_get_wager(name)) or 0) or 0
      if wager <= 0 then wager = tonumber(MBJ.config.min_bet) or 10 end
      if wager < (tonumber(MBJ.config.min_bet) or 10) then wager = tonumber(MBJ.config.min_bet) or 10 end
      if wager > (tonumber(MBJ.config.max_bet) or 10000) then wager = tonumber(MBJ.config.max_bet) or 10000 end
      if dealer_set_wager ~= nil then dealer_set_wager(name, wager) end
      p.wager = wager
      p.hand_index = 1
      p.splits_used = 0
      p.hands = {
        {
          cards = {},
          finished = false,
          bust = false,
          standing = false,
          doubled = false,
          from_split = false,
          wager = wager,
        }
      }
    end
  end

  if #MBJ.order == 0 then
    MBJ.phase = "idle"
    MBJ.info = "No eligible players in dealer roster."
    MBJ.round_active = false
    return
  end

  MBJ.phase = "awaiting_dealer"
  MBJ.info = "Round ready. Use /casino bjstart2 for dealer upcard, then /casino deal2."
  announce("start", { total = #MBJ.order })
end

local function draw_for_active(kind)
  next_active_hand()
  local name = active_player_name()
  if name == "" then
    MBJ.phase = "awaiting_dealer"
    MBJ.info = "All player hands complete. Use /casino dealer2 to draw dealer cards, then /casino resolve2."
    return
  end

  local p = MBJ.players[name]
  local h = active_hand(p)
  if p == nil or h == nil or h.finished then
    next_active_hand()
    MBJ.info = "Advanced to next hand."
    return
  end

  MBJ.phase = "dealing"
  MBJ.info = label_for(name, p, p.hand_index) .. " rolling /dice party 13..."

  enqueue_draw(function(c)
    if h.finished then return end

    table.insert(h.cards, c)
    local total = hand_total(h.cards)

    if kind == "hit" then
      announce("player_hit", { player = label_for(name, p, p.hand_index), card = rank_name(c), total = total })
    elseif kind == "deal_first" then
      announce("player_draw2", { player = label_for(name, p, p.hand_index), card = rank_name(c) })
    else
      announce("player_draw", { player = label_for(name, p, p.hand_index), card = rank_name(c), total = total })
    end

    if total > 21 then
      h.bust = true
      h.finished = true
      announce("player_bust", { player = label_for(name, p, p.hand_index) })
      p.hand_index = p.hand_index + 1
      next_active_hand()
    end

    if active_player_name() == "" then
      MBJ.phase = "awaiting_dealer"
      MBJ.info = "Players complete. Use /casino dealer2, then /casino resolve2."
    else
      MBJ.phase = "player_turn"
      MBJ.info = label_for(active_player_name(), MBJ.players[active_player_name()], (MBJ.players[active_player_name()] or {}).hand_index) .. " to act."
    end
  end)
end

local function do_stand()
  next_active_hand()
  local name = active_player_name()
  if name == "" then
    MBJ.phase = "awaiting_dealer"
    MBJ.info = "No active player."
    return
  end

  local p = MBJ.players[name]
  local h = active_hand(p)
  if p == nil or h == nil or h.finished then return end

  h.standing = true
  h.finished = true
  announce("player_stand", { player = label_for(name, p, p.hand_index), total = hand_total(h.cards) })
  p.hand_index = p.hand_index + 1
  next_active_hand()

  if active_player_name() == "" then
    MBJ.phase = "awaiting_dealer"
    MBJ.info = "Players complete. Use /casino dealer2, then /casino resolve2."
  else
    MBJ.phase = "player_turn"
    MBJ.info = label_for(active_player_name(), MBJ.players[active_player_name()], (MBJ.players[active_player_name()] or {}).hand_index) .. " to act."
  end
end

local function do_double()
  next_active_hand()
  local name = active_player_name()
  local p = MBJ.players[name]
  local h = active_hand(p)
  if name == "" or p == nil or h == nil then return end
  
  local restriction = get_double_restriction(name, p, h)
  if restriction then
    local wager = tonumber(h.wager) or 0
    local bank = (dealer_get_bank ~= nil) and (tonumber(dealer_get_bank(name)) or 0) or 0
    local tpl = (MBJ.chat_templates or {})[restriction] or "Double down not allowed."
    local formatted_err = fmt(tpl, { bet = wager, bank = bank })
    MBJ.info = formatted_err
    table_announce(name .. " cannot double down: " .. formatted_err)
    return
  end

  h.wager = (tonumber(h.wager) or 0) * 2
  h.doubled = true

  MBJ.phase = "dealing"
  MBJ.info = label_for(name, p, p.hand_index) .. " doubling, rolling /dice party 13..."

  enqueue_draw(function(c)
    table.insert(h.cards, c)
    local total = hand_total(h.cards)
    h.finished = true
    h.standing = total <= 21
    h.bust = total > 21

    announce("player_double", { player = label_for(name, p, p.hand_index), card = rank_name(c), total = total })
    if h.bust then announce("player_bust", { player = label_for(name, p, p.hand_index) }) end

    p.hand_index = p.hand_index + 1
    next_active_hand()
    if active_player_name() == "" then
      MBJ.phase = "awaiting_dealer"
      MBJ.info = "Players complete. Use /casino dealer2, then /casino resolve2."
    else
      MBJ.phase = "player_turn"
      MBJ.info = label_for(active_player_name(), MBJ.players[active_player_name()], (MBJ.players[active_player_name()] or {}).hand_index) .. " to act."
    end
  end)
end

local function do_split()
  next_active_hand()
  local name = active_player_name()
  local p = MBJ.players[name]
  local h = active_hand(p)
  if name == "" or p == nil or h == nil then return end
  
  local restriction = get_split_restriction(name, p, h)
  if restriction then
    local wager = tonumber(h.wager) or 0
    local bank = (dealer_get_bank ~= nil) and (tonumber(dealer_get_bank(name)) or 0) or 0
    local tpl = (MBJ.chat_templates or {})[restriction] or "Split not allowed."
    local formatted_err = fmt(tpl, { total = tonumber(MBJ.config.max_splits) or 0, bet = wager, bank = bank })
    MBJ.info = formatted_err
    table_announce(name .. " cannot split: " .. formatted_err)
    return
  end

  local c1 = h.cards[1]
  local c2 = h.cards[2]
  h.cards = { c1 }
  h.finished = false
  h.bust = false
  h.standing = false
  h.doubled = false
  h.from_split = true

  local h2 = {
    cards = { c2 },
    finished = false,
    bust = false,
    standing = false,
    doubled = false,
    from_split = true,
    wager = h.wager,
  }

  table.insert(p.hands, p.hand_index + 1, h2)
  p.splits_used = (p.splits_used or 0) + 1

  announce("player_split", {
    player = label_for(name, p, p.hand_index),
    bet = h.wager,
    bank = (dealer_get_bank ~= nil) and (tonumber(dealer_get_bank(name)) or 0) or 0,
  })

  MBJ.phase = "player_turn"
  MBJ.info = "Split complete. Use /casino deal2 or /casino hit2 for " .. label_for(name, p, p.hand_index) .. "."
end

local function dealer_draw_one()
  if not MBJ.round_active then
    MBJ.info = "No active round. Use /casino bjstart2 first."
    return
  end

  MBJ.phase = "dealing"
  MBJ.info = "Dealer rolling /dice party 13..."

  enqueue_draw(function(c)
    local wasEmpty = (#MBJ.dealer.cards == 0)
    table.insert(MBJ.dealer.cards, c)
    local total = hand_total(MBJ.dealer.cards)
    if wasEmpty then
      announce("dealer_first", { card = rank_name(c) })
    else
      announce("dealer_draw", { card = rank_name(c), total = total })
    end
    MBJ.phase = "awaiting_dealer"
    MBJ.info = "Dealer total " .. tostring(total) .. ". Draw again or /casino resolve2."
  end)

  table.insert(MBJ.action_history, {
    action = "dealer_draw",
    timestamp = time_ms ~= nil and time_ms() or 0
  })
end

local function undo_last_action()
  if #MBJ.action_history == 0 then
    MBJ.info = "No actions to undo."
    return
  end

  local last = table.remove(MBJ.action_history)
  if last.action == "dealer_draw" then
    if #MBJ.dealer.cards > 0 then
      table.remove(MBJ.dealer.cards)
      local total = hand_total(MBJ.dealer.cards)
      if #MBJ.dealer.cards == 0 then
        MBJ.info = "Dealer card removed. Ready for next action."
      else
        MBJ.info = "Dealer card removed. New total: " .. tostring(total)
      end
      table_announce("(Dealer action undone)")
    end
  elseif last.action == "player_draw" or last.action == "player_hit" then
    local name = last.player_name
    local hand_idx = last.hand_idx
    if name and MBJ.players[name] and MBJ.players[name].hands[hand_idx] then
      local h = MBJ.players[name].hands[hand_idx]
      if #h.cards > 0 then
        table.remove(h.cards)
        h.bust = false
        h.finished = false
        local total = hand_total(h.cards)
        MBJ.info = "Card removed from " .. name .. ". New total: " .. tostring(total)
        table_announce("(" .. name .. " card removed)")
      end
    end
  end
end

function on_command(cmd, ...)
  local command = string.lower(tostring(cmd or ""))

  if command == "bjstart2" then
    start_round()
    if MBJ.round_active then dealer_draw_one() end
    return "ok"
  end

  if command == "deal2" then
    if not MBJ.round_active then MBJ.info = "No active round." return "no_round" end

    next_active_hand()
    local name = active_player_name()
    local p = MBJ.players[name]
    local h = active_hand(p)
    if h == nil then
      MBJ.info = "No active hand to deal."
      return "no_hand"
    end

    if #h.cards == 0 then
      draw_for_active("deal_first")
      MBJ.draw.next_delay_ms = effective_initial_deal_delay_ms()
      draw_for_active("deal")
    else
      draw_for_active("deal")
    end

    table.insert(MBJ.action_history, {
      action = "player_draw",
      player_name = name,
      hand_idx = p.hand_index,
      timestamp = time_ms ~= nil and time_ms() or 0
    })

    return "ok"
  end

  if command == "hit" or command == "hit2" then
    if not MBJ.round_active then MBJ.info = "No active round." return "no_round" end
    local name = active_player_name()
    draw_for_active("hit")

    table.insert(MBJ.action_history, {
      action = "player_hit",
      player_name = name,
      hand_idx = (MBJ.players[name] and MBJ.players[name].hand_index) or 1,
      timestamp = time_ms ~= nil and time_ms() or 0
    })
    return "ok"
  end

  if command == "stand" or command == "stand2" then
    if not MBJ.round_active then MBJ.info = "No active round." return "no_round" end
    do_stand()
    return "ok"
  end

  if command == "dd" or command == "dd2" then
    if not MBJ.round_active then MBJ.info = "No active round." return "no_round" end
    do_double()
    return "ok"
  end

  if command == "split" or command == "split2" then
    if not MBJ.round_active then MBJ.info = "No active round." return "no_round" end
    do_split()
    return "ok"
  end

  if command == "dealer" or command == "dealer2" then
    dealer_draw_one()
    return "ok"
  end

  if command == "resolve" or command == "resolve2" then
    if not MBJ.round_active then MBJ.info = "No active round." return "no_round" end
    settle_results()
    return "ok"
  end

  if command == "undo" then
    undo_last_action()
    return "ok"
  end

  return "unknown"
end

function draw_config_ui()
  ui_text_colored("Macro Blackjack Config", 0.8, 0.95, 0.8, 1.0)
  ui_separator()

  MBJ.config.min_bet = math.max(0, ui_input_int("Min Bet##mbj_min", tonumber(MBJ.config.min_bet) or 10))
  MBJ.config.max_bet = math.max(tonumber(MBJ.config.min_bet) or 10, ui_input_int("Max Bet##mbj_max", tonumber(MBJ.config.max_bet) or 10000))
  MBJ.config.allow_double = ui_checkbox("Allow Double Down##mbj_double", MBJ.config.allow_double)
  MBJ.config.allow_double_after_split = ui_checkbox("Allow Double After Split##mbj_das", MBJ.config.allow_double_after_split)
  MBJ.config.max_splits = math.max(0, ui_input_int("Max Splits##mbj_split_max", tonumber(MBJ.config.max_splits) or 2))
  MBJ.config.split_aces = ui_checkbox("Allow Split Aces##mbj_split_aces", MBJ.config.split_aces)
  MBJ.config.blackjack_payout_x100 = math.max(100, ui_input_int("Blackjack Payout % ##mbj_bjpay", tonumber(MBJ.config.blackjack_payout_x100) or 150))

  MBJ.draw.delay_ms = ui_input_int("Dice delay (ms)##mbj_dice_delay", effective_draw_delay_ms())
  MBJ.draw.initial_deal_delay_ms = ui_input_int("dealing delay (ms)##mbj_initial_deal_delay", effective_initial_deal_delay_ms())
  MBJ.draw.reveal_delay_ms = ui_input_int("Result reveal delay (ms)##mbj_reveal_delay", effective_reveal_delay_ms())
  MBJ.draw.timeout_ms = ui_input_int("Dice timeout (ms)##mbj_dice_timeout", effective_draw_timeout_ms())
  effective_draw_timeout_ms()
  effective_initial_deal_delay_ms()
  effective_reveal_delay_ms()

  ui_separator()
  ui_text_colored("Chat Templates", 0.9, 0.95, 1.0, 1.0)
  MBJ.chat_templates.start = ui_input_text("Round Start##mbj_tpl_start", MBJ.chat_templates.start or "", 512)
  MBJ.chat_templates.dealer_first = ui_input_text("Dealer First Card##mbj_tpl_dealer_first", MBJ.chat_templates.dealer_first or "", 512)
  MBJ.chat_templates.dealer_draw = ui_input_text("Dealer Draw##mbj_tpl_dealer_draw", MBJ.chat_templates.dealer_draw or "", 512)
  MBJ.chat_templates.player_draw2 = ui_input_text("Player Deal First Card##mbj_tpl_player_draw2", MBJ.chat_templates.player_draw2 or "", 512)
  MBJ.chat_templates.player_draw = ui_input_text("Player Draw / Deal Final##mbj_tpl_player_draw", MBJ.chat_templates.player_draw or "", 512)
  MBJ.chat_templates.player_hit = ui_input_text("Player Hit##mbj_tpl_player_hit", MBJ.chat_templates.player_hit or "", 512)
  MBJ.chat_templates.player_stand = ui_input_text("Player Stand##mbj_tpl_player_stand", MBJ.chat_templates.player_stand or "", 512)
  MBJ.chat_templates.player_double = ui_input_text("Player Double##mbj_tpl_player_double", MBJ.chat_templates.player_double or "", 512)
  MBJ.chat_templates.player_split = ui_input_text("Player Split##mbj_tpl_player_split", MBJ.chat_templates.player_split or "", 512)
  MBJ.chat_templates.player_bust = ui_input_text("Player Bust Notification##mbj_tpl_player_bust", MBJ.chat_templates.player_bust or "", 512)
  
  ui_text_colored("Payout Outcomes", 0.7, 0.85, 1.0, 1.0)
  MBJ.chat_templates.result_push = ui_input_text("Push Outcome##mbj_tpl_res_push", MBJ.chat_templates.result_push or "", 512)
  MBJ.chat_templates.result_lose_bj = ui_input_text("Dealer BJ Outcome##mbj_tpl_res_lose_bj", MBJ.chat_templates.result_lose_bj or "", 512)
  MBJ.chat_templates.result_bj = ui_input_text("Player BJ Outcome##mbj_tpl_res_res_bj", MBJ.chat_templates.result_bj or "", 512)
  MBJ.chat_templates.result_win_bust = ui_input_text("Dealer Bust Outcome##mbj_tpl_res_win_bust", MBJ.chat_templates.result_win_bust or "", 512)
  MBJ.chat_templates.result_win = ui_input_text("Standard Win Outcome##mbj_tpl_res_win", MBJ.chat_templates.result_win or "", 512)
  MBJ.chat_templates.result_lose = ui_input_text("Standard Lose Outcome##mbj_tpl_res_lose", MBJ.chat_templates.result_lose or "", 512)

  ui_text_colored("Action Restriction Messages", 0.9, 0.7, 0.7, 1.0)
  MBJ.chat_templates.err_dd_disabled = ui_input_text("DD Disabled##mbj_err_dd_dis", MBJ.chat_templates.err_dd_disabled or "", 512)
  MBJ.chat_templates.err_dd_cards = ui_input_text("DD Card Count##mbj_err_dd_crd", MBJ.chat_templates.err_dd_cards or "", 512)
  MBJ.chat_templates.err_dd_das = ui_input_text("DD After Split Error##mbj_err_dd_das", MBJ.chat_templates.err_dd_das or "", 512)
  MBJ.chat_templates.err_dd_funds = ui_input_text("DD Bank Balance Error##mbj_err_dd_fnd", MBJ.chat_templates.err_dd_funds or "", 512)
  MBJ.chat_templates.err_split_max = ui_input_text("Split Max Reached##mbj_err_sp_max", MBJ.chat_templates.err_split_max or "", 512)
  MBJ.chat_templates.err_split_cards = ui_input_text("Split Card Count##mbj_err_sp_crd", MBJ.chat_templates.err_split_cards or "", 512)
  MBJ.chat_templates.err_split_aces = ui_input_text("Split Aces Blocked##mbj_err_sp_ace", MBJ.chat_templates.err_split_aces or "", 512)
  MBJ.chat_templates.err_split_value = ui_input_text("Split Card Mismatch##mbj_err_sp_val", MBJ.chat_templates.err_split_value or "", 512)
  MBJ.chat_templates.err_split_funds = ui_input_text("Split Bank Balance Error##mbj_err_sp_fnd", MBJ.chat_templates.err_split_funds or "", 512)

  ui_separator()
  ui_text_colored("Import / Export Configuration Blob", 0.4, 0.8, 1.0, 1.0)
  
  if MBJ.share_blob == nil then MBJ.share_blob = "" end
  MBJ.share_blob = ui_input_text("Data String##mbj_blob_field", MBJ.share_blob, 8192)
  
  if ui_button("Generate Export Blob##mbj_btn_exp") then
    MBJ.share_blob = export_blob()
    MBJ.import_status = "SUCCESS: Generated export string!"
  end
  ui_same_line()
  if ui_button("Import From Blob##mbj_btn_imp") then
    MBJ.import_status = import_blob(MBJ.share_blob)
  end
  
  if MBJ.import_status and MBJ.import_status ~= "" then
    if string.find(MBJ.import_status, "SUCCESS") then
      ui_text_colored("Transfer Status: " .. MBJ.import_status, 0.3, 1.0, 0.3, 1.0)
    else
      ui_text_colored("Transfer Status: " .. MBJ.import_status, 1.0, 0.3, 0.3, 1.0)
    end
  end
end

local function draw_cards(values, idPrefix)
  if values == nil or #values == 0 then
    ui_text("(none)")
    return
  end

  for i = 1, #values do
    ui_button_colored_sized("[" .. rank_name(values[i]) .. "]##" .. tostring(idPrefix) .. "_" .. tostring(i), 42, 0, 0.25, 0.3, 0.36, 1.0)
    if i < #values then ui_same_line() end
  end
end

function draw_ui()
  process_pending_draws()

  ui_text_colored("Macro Blackjack", 1.0, 0.9, 0.4, 1.0)
  ui_separator()

  if ui_button("BJ Start##mbj_start") then on_command("bjstart2") end
  ui_same_line()
  if ui_button("Deal##mbj_deal") then on_command("deal2") end
  ui_same_line()
  if ui_button("Hit##mbj_hit") then on_command("hit2") end
  ui_same_line()
  if ui_button("Stand##mbj_stand") then on_command("stand2") end
  ui_same_line()
  if ui_button("DD##mbj_dd") then on_command("dd2") end
  ui_same_line()
  if ui_button("Split##mbj_split") then on_command("split2") end
  ui_same_line()
  if ui_button("Dealer##mbj_dealer") then on_command("dealer2") end
  ui_same_line()
  if ui_button("Resolve##mbj_resolve") then on_command("resolve2") end
  ui_same_line()
  if ui_button("Undo##mbj_undo") then on_command("undo") end

  ui_text("Status: " .. tostring(MBJ.phase) .. " | " .. tostring(MBJ.info))

  local active = active_player_name()
  if active ~= "" then
    local ap = MBJ.players[active]
    local ah = active_hand(ap)
    local hi = (ap and ap.hand_index) or 1
    if ap ~= nil and ah ~= nil then
      ui_text("Active: " .. label_for(active, ap, hi) .. " (" .. tostring(hand_total(ah.cards)) .. ")")
    end
  end

  ui_separator()
  ui_text_colored("Dealer", 1.0, 0.92, 0.35, 1.0)
  draw_cards(MBJ.dealer.cards, "mbj_dealer")
  ui_text("Dealer total: " .. tostring(hand_total(MBJ.dealer.cards)))

  ui_separator()
  ui_text_colored("Players", 0.9, 0.95, 1.0, 1.0)
  if #MBJ.order == 0 then
    ui_text("(no active round)")
    return
  end

  for i = 1, #MBJ.order do
    local name = MBJ.order[i]
    local p = MBJ.players[name]
    if p ~= nil then
      ui_text(name .. " | base wager " .. tostring(p.wager))
      for hi = 1, #p.hands do
        local h = p.hands[hi]
        local state = h.bust and "BUST" or (h.finished and "DONE" or "ACT")
        if h.doubled then state = state .. " DOUBLE" end
        if h.from_split then state = state .. " SPLIT" end
        ui_text("  Hand " .. tostring(hi) .. " | wager " .. tostring(h.wager) .. " | total " .. tostring(hand_total(h.cards)) .. " | " .. state)
        draw_cards(h.cards, "mbj_" .. name .. "_h" .. tostring(hi))
      end
    end
    ui_separator()
  end
end
