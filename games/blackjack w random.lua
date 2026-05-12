-- ============================================================================
-- rbj.lua
-- Asynchronous Random (Dice-Based) Blackjack with Smart Chat & Auto-Mode
-- ============================================================================

if RBJ == nil then
  RBJ = {
    phase = "idle",
    info = "Click New Round to begin.",

    players = {},
    order = {},
    active_index = 1,

    dealer = {
      cards = {},
      hidden = nil,
      finished = false,
    },

    round_active = false,

    draw = {
      channel = "party",
      delay_ms = 120,
      timeout_ms = 1500,
      pending = {},
      active = nil,
      inflight = false,
      sent_ms = 0,
      next_ms = 0,
    },

    config = {
      min_bet = 10,
      max_bet = 10000,
      hit_soft_17 = true,
      allow_double = true,
      allow_double_after_split = true,
      max_splits = 2,
      split_aces = false,
      blackjack_payout_x100 = 150,
    },

    chat_templates = {
      round_started = "Round starts with <total> players.",
      turn_start = "<player>'s turn starts.",
      player_total = "<player> total <total>.",
      player_hit = "<player> hits <card> (total <total>).",
      player_stand = "<player> stands (total <total>).",
      player_double = "<player> doubles and draws <card> (total <total>).",
      player_split = "<player> splits. Bet <bet>. Bank <bank>.",
      player_bust = "<player> busts.",
      dealer_turn_start = "Dealer's turn starts.",
      dealer_up = "Dealer shows <card>.",
      dealer_hole = "Dealer takes a hidden card.",
      dealer_reveal = "Dealer reveals <card> (total <total>).",
      dealer_draw = "Dealer draws <card> (total <total>).",
      dealer_bust = "Dealer busts (total <total>).",
      dealer_stand = "Dealer stands (total <total>).",
      result = "<player> <result> (<total> vs dealer <dealer_total>). Bet <bet>. Bank <bank>.",
    },

    chat_hint = nil,
    auto_pending = nil,
  }
end

-- ============================================================================
-- Utility Functions
-- ============================================================================

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
  local t = RBJ.chat_templates or {}
  local template = t[key]
  if template == nil or template == "" then return end
  table_announce(fmt(template, ctx))
end

local function rank_name(v)
  if v == 1 then return "A" end
  if v == 11 then return "J" end
  if v == 12 then return "Q" end
  if v == 13 then return "K" end
  return tostring(v)
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

local function is_soft_total(cards)
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
  return aces > 0
end

local function is_natural_blackjack(hand)
  if hand == nil or hand.cards == nil then return false end
  if #hand.cards ~= 2 then return false end
  if hand.from_split == true then return false end
  return hand_total(hand.cards) == 21
end

local function active_player_name()
  if RBJ.active_index < 1 or RBJ.active_index > #RBJ.order then return "" end
  return RBJ.order[RBJ.active_index] or ""
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

local function ensure_player_state(name)
  if RBJ.players[name] == nil then
    RBJ.players[name] = {
      hands = {},
      hand_index = 1,
      wager = 0,
      splits_used = 0,
    }
  end
  return RBJ.players[name]
end

-- ============================================================================
-- Async Dice & Logic Queue
-- ============================================================================

local function effective_draw_delay_ms()
  local v = tonumber(RBJ.draw.delay_ms) or 120
  if v < 25 then v = 25 end
  if v > 5000 then v = 5000 end
  RBJ.draw.delay_ms = math.floor(v)
  return RBJ.draw.delay_ms
end

local function effective_draw_timeout_ms()
  local t = tonumber(RBJ.draw.timeout_ms) or 1500
  local minByDelay = effective_draw_delay_ms() * 4
  if t < minByDelay then t = minByDelay end
  if t < 900 then t = 900 end
  if t > 6000 then t = 6000 end
  RBJ.draw.timeout_ms = math.floor(t)
  return RBJ.draw.timeout_ms
end

local function enqueue_draw(on_card)
  if on_card == nil then return end
  table.insert(RBJ.draw.pending, on_card)
end

local function apply_card_to_hand(hand, c)
  table.insert(hand.cards, c)
  local total = hand_total(hand.cards)
  if total > 21 then
    hand.bust = true
    hand.finished = true
  end
  return total
end

local function can_double(name, p, h)
  if not RBJ.config.allow_double then return false end
  if p == nil or h == nil then return false end
  if #h.cards ~= 2 or h.doubled then return false end
  if h.from_split == true and not RBJ.config.allow_double_after_split then return false end
  local bank = (dealer_get_bank ~= nil) and (tonumber(dealer_get_bank(name)) or 0) or 0
  return bank >= (tonumber(h.wager) or 0)
end

local function can_split(name, p, h)
  if p == nil or h == nil then return false end
  if p.splits_used >= (RBJ.config.max_splits or 0) then return false end
  if #h.cards ~= 2 then return false end
  local c1 = tonumber(h.cards[1]) or 0
  local c2 = tonumber(h.cards[2]) or 0
  local sameRank = (c1 == c2)
  local bothTenValue = (card_value(c1) == 10 and card_value(c2) == 10)
  if not sameRank and not bothTenValue then return false end
  if tonumber(h.cards[1]) == 1 and not RBJ.config.split_aces then return false end
  local bank = (dealer_get_bank ~= nil) and (tonumber(dealer_get_bank(name)) or 0) or 0
  return bank >= (tonumber(h.wager) or 0)
end

local function advance_to_next_hand_or_player()
  while RBJ.active_index <= #RBJ.order do
    local name = RBJ.order[RBJ.active_index]
    local p = RBJ.players[name]
    if p == nil then
      RBJ.active_index = RBJ.active_index + 1
    else
      while p.hand_index <= #p.hands do
        local h = p.hands[p.hand_index]
        if h ~= nil and not h.finished then return end
        p.hand_index = p.hand_index + 1
      end
      RBJ.active_index = RBJ.active_index + 1
    end
  end
end

-- ============================================================================
-- Settle & Resolution
-- ============================================================================

local function settle_results(dealer_total, dealer_natural, dealer_bust)
  for i = 1, #RBJ.order do
    local name = RBJ.order[i]
    local p = RBJ.players[name]
    if p ~= nil then
      for hi = 1, #p.hands do
        local h = p.hands[hi]
        if h ~= nil then
          local pt = hand_total(h.cards)
          local wager = tonumber(h.wager or p.wager) or 0
          local player_natural = is_natural_blackjack(h)

          local result = "push"
          local delta = 0

          if h.bust then
            result = "bust / lose"
            delta = -wager
          elseif player_natural and dealer_natural then
            result = "push"
          elseif dealer_natural then
            result = "lose (dealer blackjack)"
            delta = -wager
          elseif player_natural then
            result = "blackjack"
            delta = math.floor((wager * (RBJ.config.blackjack_payout_x100 or 150)) / 100)
          elseif dealer_bust then
            result = "win (dealer bust)"
            delta = wager
          elseif pt > dealer_total then
            result = "win"
            delta = wager
          elseif pt < dealer_total then
            result = "lose"
            delta = -wager
          else
            result = "push"
          end

          if delta ~= 0 and dealer_add_bank ~= nil then
            dealer_add_bank(name, delta)
          end

          local bank = (dealer_get_bank ~= nil) and (tonumber(dealer_get_bank(name)) or 0) or 0
          announce("result", {
            player = label_for(name, p, hi),
            result = result,
            total = pt,
            dealer_total = dealer_total,
            bet = wager,
            bank = bank,
          })
        end
      end
    end
  end

  RBJ.phase = "settled"
  RBJ.round_active = false
  RBJ.info = "Round complete. Dealer " .. tostring(dealer_total)
end

local function settle_round_step()
  local dt = hand_total(RBJ.dealer.cards)
  if dt < 17 or (dt == 17 and RBJ.config.hit_soft_17 and is_soft_total(RBJ.dealer.cards)) then
    enqueue_draw(function(c)
      table.insert(RBJ.dealer.cards, c)
      announce("dealer_draw", { card = rank_name(c), total = hand_total(RBJ.dealer.cards) })
      settle_round_step()
    end)
    RBJ.info = "Dealer rolling /dice party 13..."
    return
  end

  if dt > 21 then
    announce("dealer_bust", { total = dt })
  else
    announce("dealer_stand", { total = dt })
  end
  local dealer_total = hand_total(RBJ.dealer.cards)
  local dealer_bust = dealer_total > 21
  local dealer_natural = (#RBJ.dealer.cards == 2 and dealer_total == 21)
  settle_results(dealer_total, dealer_natural, dealer_bust)
end

local function settle_round()
  RBJ.phase = "dealer_turn"
  announce("dealer_turn_start", {})

  if RBJ.dealer.hidden == nil then
    RBJ.info = "Dealer rolling /dice party 13..."
    enqueue_draw(function(hole)
      RBJ.dealer.hidden = hole
      table.insert(RBJ.dealer.cards, RBJ.dealer.hidden)
      announce("dealer_reveal", { card = rank_name(RBJ.dealer.hidden), total = hand_total(RBJ.dealer.cards) })
      RBJ.dealer.hidden = nil
      settle_round_step()
    end)
    return
  end

  table.insert(RBJ.dealer.cards, RBJ.dealer.hidden)
  announce("dealer_reveal", { card = rank_name(RBJ.dealer.hidden), total = hand_total(RBJ.dealer.cards) })
  RBJ.dealer.hidden = nil
  settle_round_step()
end

-- ============================================================================
-- Player Actions
-- ============================================================================

local function start_active_player_turn_if_needed()
  advance_to_next_hand_or_player()
  local name = active_player_name()
  if name == "" then
    settle_round()
    return
  end

  local p = RBJ.players[name]
  local h = active_hand(p)
  if p == nil or h == nil then
    settle_round()
    return
  end

  if #h.cards == 0 then
    if h.deal_started == true then
      return
    end

    h.deal_started = true
    h.cards = {}
    h.finished = false
    h.bust = false
    h.standing = false

    announce("turn_start", { player = label_for(name, p, p.hand_index) })
    RBJ.phase = "dealing"
    RBJ.info = label_for(name, p, p.hand_index) .. " rolling /dice party 13..."

    enqueue_draw(function(c1)
      apply_card_to_hand(h, c1)

      enqueue_draw(function(c2)
        local t2 = apply_card_to_hand(h, c2)
        h.deal_started = false

        if t2 >= 21 then
          if t2 > 21 then
            announce("player_bust", { player = label_for(name, p, p.hand_index) })
          else
            h.standing = true
            h.finished = true
            announce("player_stand", { player = label_for(name, p, p.hand_index), total = t2 })
          end
          p.hand_index = p.hand_index + 1
          start_active_player_turn_if_needed()
          return
        end

        RBJ.phase = "player_turn"
        announce("player_total", { player = label_for(name, p, p.hand_index), total = t2 })
        RBJ.info = label_for(name, p, p.hand_index) .. " to act."
      end)
    end)
    return
  end

  if #h.cards == 1 and h.from_split == true then
    if h.deal_started == true then
      return
    end

    h.deal_started = true
    announce("turn_start", { player = label_for(name, p, p.hand_index) })
    RBJ.phase = "dealing"
    RBJ.info = label_for(name, p, p.hand_index) .. " rolling /dice party 13..."

    enqueue_draw(function(c)
      local total = apply_card_to_hand(h, c)
      h.deal_started = false
      announce("player_hit", { player = label_for(name, p, p.hand_index), card = rank_name(c), total = total })

      if tonumber(h.cards[1]) == 1 or total >= 21 then
        h.standing = (not h.bust)
        h.finished = true
        if h.bust then
          announce("player_bust", { player = label_for(name, p, p.hand_index) })
        else
          announce("player_stand", { player = label_for(name, p, p.hand_index), total = total })
        end
        p.hand_index = p.hand_index + 1
        start_active_player_turn_if_needed()
        return
      end

      RBJ.phase = "player_turn"
      RBJ.info = label_for(name, p, p.hand_index) .. " to act."
    end)
    return
  end

  RBJ.phase = "player_turn"
  announce("turn_start", { player = label_for(name, p, p.hand_index) })
  RBJ.info = label_for(name, p, p.hand_index) .. " to act."
end

local function do_hit()
  if RBJ.phase ~= "player_turn" then return end
  local name = active_player_name()
  local p = RBJ.players[name]
  local h = active_hand(p)
  if p == nil or h == nil or h.finished then return end

  RBJ.chat_hint = nil -- Clear the UI highlight

  RBJ.phase = "dealing"
  RBJ.info = label_for(name, p, p.hand_index) .. " rolling /dice party 13..."

  enqueue_draw(function(c)
    local total = apply_card_to_hand(h, c)
    announce("player_hit", { player = label_for(name, p, p.hand_index), card = rank_name(c), total = total })

    if h.bust then
      announce("player_bust", { player = label_for(name, p, p.hand_index) })
      p.hand_index = p.hand_index + 1
      start_active_player_turn_if_needed()
      return
    end

    RBJ.phase = "player_turn"
    RBJ.info = label_for(name, p, p.hand_index) .. " to act."
  end)
end

local function do_stand()
  if RBJ.phase ~= "player_turn" then return end
  local name = active_player_name()
  local p = RBJ.players[name]
  local h = active_hand(p)
  if p == nil or h == nil or h.finished then return end

  RBJ.chat_hint = nil -- Clear the UI highlight

  h.standing = true
  h.finished = true
  announce("player_stand", { player = label_for(name, p, p.hand_index), total = hand_total(h.cards) })

  p.hand_index = p.hand_index + 1
  start_active_player_turn_if_needed()
end

local function do_double()
  if RBJ.phase ~= "player_turn" then return end

  local name = active_player_name()
  local p = RBJ.players[name]
  local h = active_hand(p)
  if p == nil or h == nil or h.finished then return end
  if not can_double(name, p, h) then return end

  RBJ.chat_hint = nil -- Clear the UI highlight

  h.wager = (tonumber(h.wager) or 0) * 2
  h.doubled = true

  RBJ.phase = "dealing"
  RBJ.info = label_for(name, p, p.hand_index) .. " rolling /dice party 13..."

  enqueue_draw(function(c)
    local total = apply_card_to_hand(h, c)
    h.finished = true
    h.standing = not h.bust

    announce("player_double", { player = label_for(name, p, p.hand_index), card = rank_name(c), total = total })
    if h.bust then announce("player_bust", { player = label_for(name, p, p.hand_index) }) end

    p.hand_index = p.hand_index + 1
    start_active_player_turn_if_needed()
  end)
end

local function do_split()
  if RBJ.phase ~= "player_turn" then return end

  local name = active_player_name()
  local p = RBJ.players[name]
  local h = active_hand(p)
  if p == nil or h == nil or h.finished then return end
  if not can_split(name, p, h) then return end

  RBJ.chat_hint = nil -- Clear the UI highlight

  local c1 = h.cards[1]
  local c2 = h.cards[2]
  h.cards = { c1 }
  h.finished = false
  h.bust = false
  h.standing = false
  h.doubled = false
  h.from_split = true
  h.deal_started = false

  local h2 = {
    cards = { c2 },
    finished = false,
    bust = false,
    standing = false,
    doubled = false,
    from_split = true,
    deal_started = false,
    wager = h.wager,
  }

  table.insert(p.hands, p.hand_index + 1, h2)
  p.splits_used = (p.splits_used or 0) + 1

  announce("player_split", {
    player = label_for(name, p, p.hand_index),
    bet = h.wager,
    bank = (dealer_get_bank ~= nil) and (tonumber(dealer_get_bank(name)) or 0) or 0,
  })

  RBJ.phase = "dealing"
  RBJ.info = label_for(name, p, p.hand_index) .. " rolling /dice party 13..."

  enqueue_draw(function(cA)
    local tA = apply_card_to_hand(h, cA)
    announce("player_hit", { player = label_for(name, p, p.hand_index), card = rank_name(cA), total = tA })

    enqueue_draw(function(cB)
      local tB = apply_card_to_hand(h2, cB)
      announce("player_hit", { player = label_for(name, p, p.hand_index + 1), card = rank_name(cB), total = tB })

      if tonumber(c1) == 1 then
        h.finished = true
        h.standing = true
        h2.finished = true
        h2.standing = true
        p.hand_index = p.hand_index + 2
        start_active_player_turn_if_needed()
        return
      end

      if hand_total(h.cards) >= 21 then
        h.finished = true
        h.standing = true
        p.hand_index = p.hand_index + 1
        start_active_player_turn_if_needed()
        return
      end

      RBJ.phase = "player_turn"
      RBJ.info = label_for(name, p, p.hand_index) .. " to act."
    end)
  end)
end

-- ============================================================================
-- Chat Parsing Engine & Auto Actions
-- ============================================================================

local function execute_pending_auto_action()
  if RBJ.auto_pending == nil then return end
  if RBJ.phase ~= "player_turn" then 
    RBJ.auto_pending = nil 
    return 
  end
  
  local now = (time_ms ~= nil) and time_ms() or 0
  if now < RBJ.auto_pending.execute_at then return end

  local action = RBJ.auto_pending.action
  RBJ.auto_pending = nil

  if action == "hit" then do_hit()
  elseif action == "stand" then do_stand()
  elseif action == "double" then do_double()
  elseif action == "split" then do_split()
  end
end

local function normalize_action_word(message)
  local m = string.lower((message or ""))
  if m == "" then return nil end

  local words = {}
  for w in string.gmatch(m, "%a+") do
    table.insert(words, w)
  end

  local foundHit = false
  local foundStand = false
  local foundDouble = false
  local foundSplit = false

  for i = 1, #words do
    local w = words[i]
    if w == "hit" then foundHit = true end
    if w == "stand" or w == "stay" then foundStand = true end
    if w == "double" then foundDouble = true end
    if w == "split" then foundSplit = true end

    if #words == 1 then
      if w == "h" then foundHit = true end
      if w == "s" then foundStand = true end
      if w == "dd" then foundDouble = true end
    end
  end

  if foundDouble then return "double" end
  if foundSplit then return "split" end
  if foundStand then return "stand" end
  if foundHit then return "hit" end
  return nil
end

local function process_chat_inputs()
  if chat_poll == nil or RBJ.phase ~= "player_turn" then return end
  local activeName = active_player_name()
  if activeName == "" then return end

  for _ = 1, 10 do
    local packet = chat_poll()
    if packet == nil or packet == "" then break end

    local name, _, _, message = string.match(packet, "^([^|]*)|([^|]*)|([^|]*)|(.*)$")
    if name ~= nil and message ~= nil and string.lower(name) == string.lower(activeName) then
      
      local action = normalize_action_word(message)
      if action ~= nil then
        -- 1. Always highlight the dealer button as a hint
        RBJ.chat_hint = action
        
        -- 2. Execute automatically ONLY if auto_mode is ON
        local is_auto = false
        if auto_mode ~= nil and auto_mode() then is_auto = true end
        
        if is_auto then
           local delay = 0
           if auto_delay_ms ~= nil then delay = math.max(0, auto_delay_ms()) end
           RBJ.auto_pending = {
               action = action,
               execute_at = ((time_ms ~= nil) and time_ms() or 0) + delay
           }
        end
        
        return -- Action parsed, stop reading chat for this tick
      end
    end
  end
end

-- ============================================================================
-- Async Draw Processing
-- ============================================================================

local function process_pending_draws()
  local d = RBJ.draw
  if d == nil then return end

  effective_draw_timeout_ms()

  if d.active == nil and #d.pending > 0 then
    d.active = table.remove(d.pending, 1)
    d.inflight = false
    d.sent_ms = 0
  end

  if d.active == nil then return end

  local now = (time_ms ~= nil) and time_ms() or 0

  if d.inflight and (now - (d.sent_ms or 0)) >= effective_draw_timeout_ms() then
    d.inflight = false
    d.next_ms = now + 60
  end

  if (not d.inflight) and now >= (d.next_ms or 0) then
    local ch = tostring(d.channel or "party")
    if dice_command == nil or not dice_command(ch, 13) then
      RBJ.info = "Dice command unavailable (/dice " .. ch .. " 13)."
      RBJ.phase = "idle"
      d.pending = {}
      d.active = nil
      d.inflight = false
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
        d.next_ms = ((time_ms ~= nil) and time_ms() or now) + effective_draw_delay_ms()
        if cb ~= nil then cb(rolled) end
        break
      end
    end
  end
end

-- ============================================================================
-- Round Entry & Initialization
-- ============================================================================

function rbj_new_round()
  RBJ.players = {}
  RBJ.order = {}
  RBJ.active_index = 1
  RBJ.dealer.cards = {}
  RBJ.dealer.hidden = nil
  RBJ.dealer.finished = false
  RBJ.round_active = false
  RBJ.draw.pending = {}
  RBJ.draw.active = nil
  RBJ.draw.inflight = false
  RBJ.draw.sent_ms = 0
  RBJ.draw.next_ms = 0
  RBJ.chat_hint = nil
  RBJ.auto_pending = nil

  local count = dealer_player_count()
  for i = 1, count do
    local name = dealer_player_name(i)
    if name ~= nil and name ~= "" and dealer_is_eligible(name) then
      table.insert(RBJ.order, name)
      local p = ensure_player_state(name)
      local wager = (dealer_get_wager ~= nil) and (tonumber(dealer_get_wager(name)) or 0) or 0
      if wager <= 0 then wager = RBJ.config.min_bet end
      if wager < RBJ.config.min_bet then wager = RBJ.config.min_bet end
      if wager > RBJ.config.max_bet then wager = RBJ.config.max_bet end
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
          deal_started = false,
          wager = wager,
        }
      }
    end
  end

  if #RBJ.order == 0 then
    RBJ.phase = "idle"
    RBJ.info = "No eligible players in dealer roster."
    return
  end

  RBJ.round_active = true
  RBJ.phase = "dealing"
  RBJ.info = "Dealer rolling /dice party 13..."

  enqueue_draw(function(up)
    table.insert(RBJ.dealer.cards, up)
    announce("dealer_up", { card = rank_name(up) })

    start_active_player_turn_if_needed()
  end)
end

-- ============================================================================
-- User Interface & Drawing
-- ============================================================================

function draw_config_ui()
  ui_text_colored("Rand BJ Config", 0.8, 0.95, 0.8, 1.0)
  ui_separator()

  RBJ.config.min_bet = math.max(0, ui_input_int("Min Bet##rbj_min", RBJ.config.min_bet))
  RBJ.config.max_bet = math.max(RBJ.config.min_bet, ui_input_int("Max Bet##rbj_max", RBJ.config.max_bet))
  RBJ.config.hit_soft_17 = ui_checkbox("Dealer Hits Soft 17##rbj_hs17", RBJ.config.hit_soft_17)
  RBJ.config.allow_double = ui_checkbox("Allow Double Down##rbj_double", RBJ.config.allow_double)
  RBJ.config.allow_double_after_split = ui_checkbox("Allow Double After Split##rbj_das", RBJ.config.allow_double_after_split)
  RBJ.config.max_splits = math.max(0, ui_input_int("Max Splits##rbj_split_max", RBJ.config.max_splits))
  RBJ.config.split_aces = ui_checkbox("Allow Split Aces##rbj_split_aces", RBJ.config.split_aces)
  RBJ.config.blackjack_payout_x100 = math.max(100, ui_input_int("Blackjack Payout % ##rbj_bjpay", RBJ.config.blackjack_payout_x100))

  RBJ.draw.delay_ms = ui_input_int("Dice delay (ms)##rbj_dice_delay", effective_draw_delay_ms())
  RBJ.draw.timeout_ms = ui_input_int("Dice timeout (ms)##rbj_dice_timeout", effective_draw_timeout_ms())
  effective_draw_timeout_ms()

  ui_text("Cards are dealt by /dice party 13 and parsed from chat output.")
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
  process_chat_inputs()
  execute_pending_auto_action()

  ui_text_colored("Rand BJ", 1.0, 0.9, 0.4, 1.0)
  ui_separator()

  if ui_button("New Round##rbj_new") then rbj_new_round() end

  ui_text("Status: " .. tostring(RBJ.phase) .. " | " .. tostring(RBJ.info))

  local active = active_player_name()
  if active ~= "" then
    local ap = RBJ.players[active]
    local ah = active_hand(ap)
    local hi = (ap and ap.hand_index) or 1
    if ap ~= nil and ah ~= nil then
      ui_text("Active: " .. label_for(active, ap, hi) .. " (" .. tostring(hand_total(ah.cards)) .. ")")
    else
      ui_text("Active player: " .. active)
    end
  end

  ui_separator()
  ui_text_colored("Dealer", 1.0, 0.92, 0.35, 1.0)
  draw_cards(RBJ.dealer.cards, "rbj_dealer")
  if RBJ.round_active and RBJ.dealer.hidden ~= nil then
    ui_same_line()
    ui_button_colored_sized("[?]##rbj_hole", 42, 0, 0.18, 0.18, 0.22, 1.0)
  end

  if RBJ.round_active and RBJ.dealer.hidden ~= nil then
    ui_text("Dealer total: " .. tostring(hand_total(RBJ.dealer.cards)) .. "+")
  else
    ui_text("Dealer total: " .. tostring(hand_total(RBJ.dealer.cards)))
  end

  ui_separator()
  ui_text_colored("Players", 0.9, 0.95, 1.0, 1.0)

  if #RBJ.order == 0 then
    ui_text("(no active round)")
  else
    for i = 1, #RBJ.order do
      local name = RBJ.order[i]
      local p = RBJ.players[name]
      if p ~= nil then
        ui_text(name .. " | base wager " .. tostring(p.wager))
        for hi = 1, #p.hands do
          local h = p.hands[hi]
          local state = h.bust and "BUST" or (h.finished and "STAND" or "ACT")
          if h.doubled then state = state .. " DOUBLE" end
          if h.from_split then state = state .. " SPLIT" end
          ui_text("  Hand " .. tostring(hi) .. " | wager " .. tostring(h.wager) .. " | total " .. tostring(hand_total(h.cards)) .. " | " .. state)
          draw_cards(h.cards, "rbj_" .. name .. "_h" .. tostring(hi))
        end
      end
      ui_separator()
    end
  end

  if RBJ.phase == "player_turn" then
    local name = active_player_name()
    local p = RBJ.players[name]
    local h = active_hand(p)
    if p ~= nil and h ~= nil and not h.finished then
      
      -- Helper function to color the button if it matches the chat hint
      local function action_btn(label, action_id)
        if RBJ.chat_hint == action_id and ui_button_colored ~= nil then
          return ui_button_colored(label .. "##rbj_" .. action_id, 0.2, 0.8, 0.2, 1.0)
        end
        return ui_button(label .. "##rbj_" .. action_id)
      end

      if action_btn("Hit", "hit") then do_hit() end
      ui_same_line()
      if action_btn("Stand", "stand") then do_stand() end
      
      if can_double(name, p, h) then
         ui_same_line()
         if action_btn("Double", "double") then do_double() end
      end
      
      if can_split(name, p, h) then
         ui_same_line()
         if action_btn("Split", "split") then do_split() end
      end
    end
  end
end
