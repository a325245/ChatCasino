-- ============================================================================
-- blackjack.lua
-- ============================================================================
-- ChatCasino dealer-scripted Blackjack implementation.
-- Includes:
--   - split hands
--   - double down
--   - configurable dealer/rules panel via draw_config_ui()
-- ============================================================================

if BJ == nil then
  BJ = {
    shoe_ready = false,
    dealer = {
      cards = {},
      hidden = nil,
      finished = false,
      peek_checked = false,
    },

    players = {},
    order = {},
    active = 1,
    round_active = false,
    phase = "idle",
    info = "Click New Round to begin.",

    -- Pending deal queue for paced dealing
    deal_queue = nil,
    next_deal_ms = 0,
    turn_prompted_key = nil,

    chat_hint = { player = "", action = "", turn_key = "", expires_ms = 0 },
    auto_pending = nil,

    chat_templates = {
      seat = "<player> joins this round. Bet <bet>. Bank <bank>.",
      round_started = "Round started.",
      deal_player_card = "<player> is dealt <card> (total <total>).",
      deal_dealer_upcard = "Dealer shows <card>.",
      deal_dealer_hole = "Dealer takes a hidden card.",
      dealer_reveal_hole = "Dealer reveals <card> (total <total>).",
      dealer_draw = "Dealer draws <card> (total <total>).",
      dealer_stand = "Dealer stands (total <total>).",
      player_hit = "<player> hits <card> (total <total>).",
      player_stand = "<player> stands (total <total>).",
      player_double = "<player> doubles and draws <card> (total <total>).",
      player_split = "<player> splits. Bet <bet>. Bank <bank>.",
      player_bust = "<player> busts.",
      turn_prompt = "<player> to act. Total <total>.",
      result = "<player> <result> (<total> vs dealer <dealer_total>). Bet <bet>. Bank <bank>.",
    },

    config = {
      min_bet = 10,
      max_bet = 10000,
      deal_reveal_delay_ms = 350,
      max_splits = 2,
      split_aces = false,
      hit_soft_17 = true,
      allow_double = true,
      allow_double_after_split = true,
      dealer_peek_blackjack = true,
      blackjack_payout_x100 = 150,
    }
  }
end

local execute_pending_auto_action
local card_compact
local current_turn_key
local draw_dealer_section
local draw_player_row

local function output_channel_name()
  if default_chat_channel ~= nil then
    local ch = default_chat_channel()
    if ch == "echo" or ch == "say" or ch == "party" then
      return ch
    end
  end
  return "party"
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

local function format_tokens(template, ctx)
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

local function announce_template(key, ctx)
  local t = BJ.chat_templates or {}
  local template = t[key]
  if template == nil or template == "" then return end
  table_announce(format_tokens(template, ctx))
end

local function normalize_action_word(message)
  local m = string.lower((message or ""))
  if m == "" then return nil end

  -- Tokenize by non-letters so we can match words inside sentences.
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

    -- short aliases only when the entire message is exactly the alias
    if #words == 1 then
      if w == "h" then foundHit = true end
      if w == "s" then foundStand = true end
      if w == "dd" then foundDouble = true end
    end
  end

  -- Priority order if multiple words appear in a sentence.
  if foundDouble then return "double" end
  if foundSplit then return "split" end
  if foundStand then return "stand" end
  if foundHit then return "hit" end
  return nil
end

local function active_player_label(name, p, handIndex)
  if p == nil then return name end
  local hi = handIndex or p.hand_index or 1
  if hi < 1 then hi = 1 end
  if #p.hands > 1 then
    return name .. " [H" .. tostring(hi) .. "]"
  end
  return name
end

local function is_natural_blackjack(hand)
  if hand == nil or hand.cards == nil then return false end
  if #hand.cards ~= 2 then return false end
  if hand.from_split == true then return false end
  return hand_total(hand.cards) == 21
end

local function process_chat_inputs()
  if chat_poll == nil then return end
  if BJ.phase ~= "player_turn" then return end

  for _ = 1, 12 do
    local packet = chat_poll()
    if packet == nil or packet == "" then break end

    local name, world, channel, message = string.match(packet, "^([^|]*)|([^|]*)|([^|]*)|(.*)$")
    if name ~= nil and message ~= nil then
      local action = normalize_action_word(message)
      if action ~= nil then
        local activeName = (BJ.active >= 1 and BJ.active <= #BJ.order) and BJ.order[BJ.active] or ""
        if string.lower(activeName or "") == string.lower(name or "") then
          local p = BJ.players[activeName]
          local h = nil
          local turnKey = ""
          if p ~= nil and p.hands ~= nil then
            local idx = p.hand_index or 1
            if idx < 1 then idx = 1 end
            h = p.hands[idx]
            turnKey = activeName .. "#" .. tostring(idx)
          end

          if p ~= nil and h ~= nil and not h.finished and #h.cards >= 2 and turnKey ~= "" and current_turn_key() == turnKey then
            BJ.chat_hint.player = activeName
            BJ.chat_hint.action = action
            BJ.chat_hint.turn_key = turnKey
            BJ.chat_hint.expires_ms = 0
            BJ.info = activeName .. " said '" .. action .. "' in " .. (channel or "chat")

            if auto_mode ~= nil and auto_mode() and deal_queue_complete() then
              local delay = 0
              if auto_delay_ms ~= nil then delay = math.max(0, auto_delay_ms()) end
              BJ.auto_pending = {
                player = activeName,
                action = action,
                turn_key = turnKey,
                execute_at = time_ms() + delay,
              }
            end
          end
        end
      end
    end
  end
end

local function echo_alert(message)
  local msg = message or ""
  if msg == "" then return end

  if chat_send ~= nil then
    chat_send("echo", msg)

    local out = output_channel_name()
    if out ~= "echo" then
      chat_send(out, msg)
    end
  elseif dealer_party ~= nil then
    dealer_party(msg)
  end

  if log ~= nil then
    log(msg)
  end
end

local function is_action_highlighted(name, action)
  if BJ.chat_hint == nil then return false end
  if BJ.chat_hint.player ~= name or BJ.chat_hint.action ~= action then return false end
  if (BJ.chat_hint.turn_key or "") == "" or BJ.chat_hint.turn_key ~= current_turn_key() then return false end

  -- If expiry is set, honor it.
  if (BJ.chat_hint.expires_ms or 0) > 0 and time_ms() > BJ.chat_hint.expires_ms then
    return false
  end

  -- Persist highlight for active turn when no explicit expiry is set.
  if (BJ.chat_hint.expires_ms or 0) <= 0 then
    local activeName = (BJ.active >= 1 and BJ.active <= #BJ.order) and BJ.order[BJ.active] or ""
    return activeName == name
  end

  return true
end

local function action_button(name, handIndex, action, label)
  local id = label .. "##" .. name .. "_" .. tostring(handIndex)
  if is_action_highlighted(name, action) and ui_button_colored ~= nil then
    return ui_button_colored(id, 0.2, 0.55, 0.2, 1.0)
  end
  return ui_button(id)
end

local function card_rank(card_text)
  return string.match(card_text or "", "^(%a+)") or ""
end

local function rank_short(rank)
  if rank == "Ace" then return "A" end
  if rank == "King" then return "K" end
  if rank == "Queen" then return "Q" end
  if rank == "Jack" then return "J" end
  if rank == "Ten" then return "10" end
  if rank == "Nine" then return "9" end
  if rank == "Eight" then return "8" end
  if rank == "Seven" then return "7" end
  if rank == "Six" then return "6" end
  if rank == "Five" then return "5" end
  if rank == "Four" then return "4" end
  if rank == "Three" then return "3" end
  if rank == "Two" then return "2" end
  return "?"
end

local function suit_symbol(card_text)
  if string.find(card_text or "", "Spades", 1, true) then return "♠" end
  if string.find(card_text or "", "Hearts", 1, true) then return "♥" end
  if string.find(card_text or "", "Diamonds", 1, true) then return "♦" end
  if string.find(card_text or "", "Clubs", 1, true) then return "♣" end
  return "?"
end

local function card_value(card_text)
  local rank = card_rank(card_text)
  if rank == "Ace" then return 11 end
  if rank == "King" or rank == "Queen" or rank == "Jack" or rank == "Ten" then return 10 end
  if rank == "Two" then return 2 end
  if rank == "Three" then return 3 end
  if rank == "Four" then return 4 end
  if rank == "Five" then return 5 end
  if rank == "Six" then return 6 end
  if rank == "Seven" then return 7 end
  if rank == "Eight" then return 8 end
  if rank == "Nine" then return 9 end
  return 0
end

local function hand_total(cards)
  local total = 0
  local aces = 0
  for i = 1, #cards do
    local c = cards[i]
    total = total + card_value(c)
    if card_rank(c) == "Ace" then aces = aces + 1 end
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
    local c = cards[i]
    total = total + card_value(c)
    if card_rank(c) == "Ace" then aces = aces + 1 end
  end
  while total > 21 and aces > 0 do
    total = total - 10
    aces = aces - 1
  end
  return aces > 0
end

local function draw_hand(cards)
  if cards == nil or #cards == 0 then
    ui_text("(none)")
    return
  end

  for i = 1, #cards do
    local c = cards[i]
    local rank = rank_short(card_rank(c))
    local suit = suit_symbol(c)
    local red = (suit == "♥" or suit == "♦")
    ui_card(rank, suit, red)
    if i < #cards then ui_same_line() end
  end
end

local function ensure_player_state(name, world)
  if BJ.players[name] == nil then
    BJ.players[name] = {
      world = world or "Unknown",
      hands = {},      -- each hand: { cards={}, finished=false, bust=false, standing=false, doubled=false }
      hand_index = 1,
      wager = 0,
      splits_used = 0,
    }
    table.insert(BJ.order, name)
  else
    BJ.players[name].world = world or BJ.players[name].world or "Unknown"
  end
end

local function active_hand(p)
  if p == nil then return nil end
  if p.hand_index < 1 then p.hand_index = 1 end
  return p.hands[p.hand_index]
end

local function reset_round_state()
  BJ.dealer.cards = {}
  BJ.dealer.hidden = nil
  BJ.dealer.finished = false
  BJ.dealer.peek_checked = false
  BJ.active = 1
  BJ.round_active = false
  BJ.phase = "idle"

  for i = 1, #BJ.order do
    local name = BJ.order[i]
    local p = BJ.players[name]
    if p ~= nil then
      p.hands = {}
      p.hand_index = 1
      p.splits_used = 0
    end
  end
end

local function rebuild_roster_from_dealer()
  local count = dealer_player_count()
  local seen = {}
  local new_order = {}

  for i = 1, count do
    local name = dealer_player_name(i)
    local world = dealer_player_world(i)
    if name ~= nil and name ~= "" then
      ensure_player_state(name, world)
      seen[name] = true
      table.insert(new_order, name)
    end
  end

  for name, _ in pairs(BJ.players) do
    if not seen[name] then BJ.players[name] = nil end
  end

  BJ.order = new_order
end

local function deal_card_to_hand(hand)
  local c = deck_draw()
  table.insert(hand.cards, c)
  local t = hand_total(hand.cards)
  if t > 21 then
    hand.bust = true
    hand.finished = true
  end
  return c, t
end

local function settle_dealer()
  if BJ.dealer.hidden ~= nil then
    table.insert(BJ.dealer.cards, BJ.dealer.hidden)
    announce_template("dealer_reveal_hole", {
      card = card_compact(BJ.dealer.hidden),
      total = hand_total(BJ.dealer.cards),
    })
    BJ.dealer.hidden = nil
  end

  while true do
    local total = hand_total(BJ.dealer.cards)
    if total < 17 then
      local c = deck_draw()
      table.insert(BJ.dealer.cards, c)
      announce_template("dealer_draw", {
        card = card_compact(c),
        total = hand_total(BJ.dealer.cards),
      })
    elseif total == 17 and BJ.config.hit_soft_17 and is_soft_total(BJ.dealer.cards) then
      local c = deck_draw()
      table.insert(BJ.dealer.cards, c)
      announce_template("dealer_draw", {
        card = card_compact(c),
        total = hand_total(BJ.dealer.cards),
      })
    else
      announce_template("dealer_stand", { total = total })
      break
    end
  end

  BJ.dealer.finished = true
end

local function advance_to_next_hand_or_player()
  while BJ.active <= #BJ.order do
    local name = BJ.order[BJ.active]
    local p = BJ.players[name]
    if p == nil then
      BJ.active = BJ.active + 1
    else
      local moved = false
      while p.hand_index <= #p.hands do
        local h = p.hands[p.hand_index]
        if h ~= nil and not h.finished then
          return
        end
        p.hand_index = p.hand_index + 1
        moved = true
      end
      if moved or p.hand_index > #p.hands then
        BJ.active = BJ.active + 1
      end
    end
  end
end

local function settle_results_and_announce()
  BJ.phase = "dealer_turn"
  settle_dealer()
  local dealer_total = hand_total(BJ.dealer.cards)
  local dealer_bust = dealer_total > 21
  local dealer_natural = (#BJ.dealer.cards == 2 and dealer_total == 21)

  for i = 1, #BJ.order do
    local name = BJ.order[i]
    local p = BJ.players[name]
    if p ~= nil then
      for hi = 1, #p.hands do
        local h = p.hands[hi]
        if h ~= nil then
          local wager = h.wager or p.wager
          local pt = hand_total(h.cards)
          local player_natural = is_natural_blackjack(h)
          local result = "push"
          local delta = 0

          if h.bust then
            result = "bust / lose"
            delta = -wager
          elseif player_natural and dealer_natural then
            result = "push"
            delta = 0
          elseif dealer_natural then
            result = "lose (dealer blackjack)"
            delta = -wager
          elseif player_natural then
            result = "blackjack"
            delta = math.floor((wager * (BJ.config.blackjack_payout_x100 or 150)) / 100)
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
            delta = 0
          end

          if delta ~= 0 then dealer_add_bank(name, delta) end

          local who = active_player_label(name, p, hi)
          local bank = dealer_get_bank(name)
          local msg = format_tokens(BJ.chat_templates.result, {
            player = who,
            bet = wager,
            bank = bank,
            total = pt,
            dealer_total = dealer_total,
            result = result,
          })

          table_announce(msg)
          if p.world ~= nil and p.world ~= "" then dealer_tell(name, p.world, msg) end
        end
      end
    end
  end

  BJ.round_active = false
  BJ.phase = "settled"
  BJ.info = "Round complete. Dealer " .. tostring(dealer_total)
end

function bj_new_shoe()
  deck_reset()
  BJ.shoe_ready = true
  BJ.info = "New shoe ready."
  table_announce("New shuffled shoe ready.")
  return tostring(deck_remaining())
end

card_compact = function(card_text)
  local r = rank_short(card_rank(card_text))
  local s = suit_symbol(card_text)
  return (r or "?") .. (s or "?")
end

function bj_new_round()
  ensure_runtime_state()
  if not BJ.shoe_ready then bj_new_shoe() end

  rebuild_roster_from_dealer()

  local eligible = {}
  for i = 1, #BJ.order do
    local name = BJ.order[i]
    if dealer_is_eligible(name) then table.insert(eligible, name) end
  end

  if #eligible == 0 then
    BJ.info = "No eligible players. (AFK/Kicked players are skipped)"
    return "no players"
  end

  BJ.order = eligible
  reset_round_state()
  BJ.chat_hint = { player = "", action = "", turn_key = "", expires_ms = 0 }
  BJ.auto_pending = nil
  BJ.turn_prompted_key = nil

  for i = 1, #BJ.order do
    local name = BJ.order[i]
    local p = BJ.players[name]
    local originalWager = tonumber(dealer_get_wager(name)) or 0
    local wager = originalWager
    if wager <= 0 then wager = BJ.config.min_bet end
    wager = math.max(BJ.config.min_bet, math.min(BJ.config.max_bet, wager))

    if originalWager < BJ.config.min_bet or originalWager > BJ.config.max_bet then
      local alert = "Invalid wager for " .. name .. ": " .. tostring(originalWager) .. ". Clamped to " .. tostring(wager) .. ". Allowed range " .. tostring(BJ.config.min_bet) .. "-" .. tostring(BJ.config.max_bet) .. "."
      echo_alert(alert)
      BJ.info = alert
    end

    dealer_set_wager(name, wager)
    p.wager = wager
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
    p.hand_index = 1
    p.splits_used = 0

    announce_template("seat", {
      player = name,
      bet = wager,
      bank = dealer_get_bank(name),
    })
  end

  BJ.deal_queue = {}

  -- Round start deals only dealer cards; each player receives opening cards on their own turn.
  table.insert(BJ.deal_queue, { t = "dealer", name = "dealer", open = true })
  table.insert(BJ.deal_queue, { t = "dealer", name = "dealer", open = false })

  BJ.next_deal_ms = time_ms() + math.max(0, BJ.config.deal_reveal_delay_ms)
  BJ.round_active = true
  BJ.phase = "dealing"
  if BJ.info == nil or BJ.info == "" or string.find(BJ.info, "Invalid wager", 1, true) == nil then
    BJ.info = "Dealing opening cards..."
  end
  announce_template("round_started", {})
  return "ok"
end

function bj_hit()
  ensure_runtime_state()
  if not BJ.round_active then return "no round" end
  if BJ.phase ~= "player_turn" then return "not player turn" end
  if not deal_queue_complete() then return "still dealing" end

  advance_to_next_hand_or_player()
  if BJ.active > #BJ.order then
    settle_results_and_announce()
    return "settled"
  end

  local actor = BJ.order[BJ.active]
  local p = BJ.players[actor]
  local h = active_hand(p)
  if p == nil or h == nil then return "no hand" end
  if #h.cards < 2 then return "hand not dealt" end
  if hand_total(h.cards) >= 21 then return "cannot hit" end

  local actorLabel = active_player_label(actor, p, p.hand_index)
  local card, nowTotal = deal_card_to_hand(h)
  announce_template("player_hit", {
    player = actorLabel,
    card = card_compact(card),
    total = nowTotal,
    bet = h.wager,
    bank = dealer_get_bank(actor),
  })

  if h.bust then
    announce_template("player_bust", {
      player = actorLabel,
      bet = h.wager,
      bank = dealer_get_bank(actor),
    })
    p.hand_index = p.hand_index + 1
    advance_to_next_hand_or_player()
    BJ.turn_prompted_key = nil
    if BJ.active > #BJ.order then
      settle_results_and_announce()
    else
      BJ.phase = "dealing"
      BJ.info = BJ.order[BJ.active] .. " to act."
    end
  end

  return "ok"
end

function bj_stand()
  if not BJ.round_active then return "no round" end
  if BJ.phase ~= "player_turn" then return "not player turn" end
  if not deal_queue_complete() then return "still dealing" end

  advance_to_next_hand_or_player()
  if BJ.active > #BJ.order then
    settle_results_and_announce()
    return "settled"
  end

  local actor = BJ.order[BJ.active]
  local p = BJ.players[actor]
  local h = active_hand(p)
  if p == nil or h == nil then return "no hand" end
  if #h.cards < 2 then return "hand not dealt" end

  local actorLabel = active_player_label(actor, p, p.hand_index)
  h.standing = true
  h.finished = true
  announce_template("player_stand", {
    player = actorLabel,
    total = hand_total(h.cards),
    bet = h.wager,
    bank = dealer_get_bank(actor),
  })

  p.hand_index = p.hand_index + 1
  advance_to_next_hand_or_player()
  BJ.turn_prompted_key = nil
  BJ.chat_hint = { player = "", action = "", turn_key = "", expires_ms = 0 }

  if BJ.active > #BJ.order then
    settle_results_and_announce()
  else
    BJ.phase = "dealing"
    BJ.info = BJ.order[BJ.active] .. " to act."
  end

  return "ok"
end

function bj_double()
  ensure_runtime_state()
  if not BJ.round_active then return "no double" end
  if BJ.phase ~= "player_turn" then return "not player turn" end
  if not deal_queue_complete() then return "still dealing" end

  advance_to_next_hand_or_player()
  if BJ.active > #BJ.order then return "settled" end

  local name = BJ.order[BJ.active]
  local p = BJ.players[name]
  local h = active_hand(p)
  if p == nil or h == nil then return "no hand" end
  if not can_double(name, p, h) then return "invalid double" end

  h.wager = h.wager * 2
  h.doubled = true

  local actorLabel = active_player_label(name, p, p.hand_index)
  local card, total = deal_card_to_hand(h)
  h.finished = true
  announce_template("player_double", {
    player = actorLabel,
    card = card_compact(card),
    total = total,
    bet = h.wager,
    bank = dealer_get_bank(name),
  })

  p.hand_index = p.hand_index + 1
  advance_to_next_hand_or_player()
  BJ.turn_prompted_key = nil
  BJ.chat_hint = { player = "", action = "", turn_key = "", expires_ms = 0 }

  if BJ.active > #BJ.order then
    settle_results_and_announce()
  else
    BJ.phase = "dealing"
    BJ.info = BJ.order[BJ.active] .. " to act."
  end

  return "ok"
end

function bj_split()
  ensure_runtime_state()
  if not BJ.round_active then return "no round" end
  if BJ.phase ~= "player_turn" then return "not player turn" end
  if not deal_queue_complete() then return "still dealing" end

  advance_to_next_hand_or_player()
  if BJ.active > #BJ.order then return "settled" end

  local name = BJ.order[BJ.active]
  local p = BJ.players[name]
  local h = active_hand(p)
  if p == nil or h == nil then return "no hand" end
  if not can_split(name, p, h) then return "invalid split" end

  local r1 = card_rank(h.cards[1])
  local c1 = h.cards[1]
  local c2 = h.cards[2]

  h.cards = { c1, deck_draw() }
  h.finished = false
  h.bust = false
  h.standing = false
  h.doubled = false
  h.from_split = true

  table.insert(p.hands, p.hand_index + 1, {
    cards = { c2, deck_draw() },
    finished = false,
    bust = false,
    standing = false,
    doubled = false,
    from_split = true,
    wager = h.wager,
  })

  p.splits_used = p.splits_used + 1
  announce_template("player_split", {
    player = active_player_label(name, p, p.hand_index),
    bet = h.wager,
    bank = dealer_get_bank(name),
  })
  BJ.turn_prompted_key = nil
  BJ.chat_hint = { player = "", action = "", turn_key = "", expires_ms = 0 }

  if r1 == "Ace" then
    h.finished = true
    h.standing = true
    local h2 = p.hands[p.hand_index + 1]
    if h2 ~= nil then
      h2.finished = true
      h2.standing = true
    end

    p.hand_index = p.hand_index + 2
    advance_to_next_hand_or_player()
    if BJ.active > #BJ.order then
      settle_results_and_announce()
    else
      BJ.phase = "dealing"
      BJ.info = BJ.order[BJ.active] .. " to act."
    end
  end

  return "ok"
end

function queue_deal(action_type, target_name, open_card)
  if BJ.deal_queue == nil then BJ.deal_queue = {} end
  table.insert(BJ.deal_queue, { t = action_type, name = target_name, open = open_card })
end

current_turn_key = function()
  if not BJ.round_active then return "" end
  if BJ.active < 1 or BJ.active > #BJ.order then return "" end
  local name = BJ.order[BJ.active]
  local p = BJ.players[name]
  if p == nil then return "" end
  return name .. "#" .. tostring(p.hand_index or 1)
end

local function announce_turn_prompt_if_needed()
  if BJ.phase ~= "player_turn" then return end
  if not deal_queue_complete() then return end

  local key = current_turn_key()
  if key == "" then return end
  if BJ.turn_prompted_key == key then return end

  local name = BJ.order[BJ.active]
  local p = BJ.players[name]
  local h = active_hand(p)
  if p == nil or h == nil then return end
  if #h.cards < 2 then return end

  announce_template("turn_prompt", {
    player = active_player_label(name, p, p.hand_index),
    total = hand_total(h.cards),
    bet = h.wager or p.wager or 0,
    bank = dealer_get_bank(name),
  })

  BJ.turn_prompted_key = key
end

local function queue_active_opening_hand_if_needed()
  if not BJ.round_active then return false end
  if not deal_queue_complete() then return false end

  advance_to_next_hand_or_player()
  if BJ.active < 1 or BJ.active > #BJ.order then return false end

  local name = BJ.order[BJ.active]
  local p = BJ.players[name]
  local h = active_hand(p)
  if p == nil or h == nil or h.finished then return false end

  local missing = 2 - #h.cards
  if missing <= 0 then return false end

  for _ = 1, missing do
    queue_deal("player", name, true)
    BJ.deal_queue[#BJ.deal_queue].hand = h
  end

  BJ.phase = "dealing"
  BJ.next_deal_ms = time_ms() + math.max(0, BJ.config.deal_reveal_delay_ms)
  BJ.turn_prompted_key = nil
  BJ.info = "Dealing opening cards for " .. active_player_label(name, p, p.hand_index) .. "..."
  return true
end

local function handle_dealer_peek_if_needed()
  if not BJ.round_active then return false end
  if BJ.phase ~= "dealing" then return false end
  if not deal_queue_complete() then return false end
  if BJ.dealer.peek_checked then return false end
  if BJ.dealer.hidden == nil then return false end

  BJ.dealer.peek_checked = true
  if not BJ.config.dealer_peek_blackjack then return false end

  local peekCards = { BJ.dealer.cards[1], BJ.dealer.hidden }
  if hand_total(peekCards) == 21 then
    settle_results_and_announce()
    return true
  end

  return false
end

function process_deal_step()
  if BJ.deal_queue == nil or #BJ.deal_queue == 0 then return false end
  local now = time_ms()
  if now < (BJ.next_deal_ms or 0) then return false end

  local step = table.remove(BJ.deal_queue, 1)
  if step.t == "player" then
    if step.hand ~= nil then
      local card, total = deal_card_to_hand(step.hand)
      announce_template("deal_player_card", {
        player = step.name,
        card = card_compact(card),
        total = total,
        bet = step.hand.wager or 0,
        bank = dealer_get_bank(step.name or ""),
      })
    end
  elseif step.t == "dealer" then
    local c = deck_draw()
    if step.open then
      table.insert(BJ.dealer.cards, c)
      announce_template("deal_dealer_upcard", { card = card_compact(c) }) 
    else
      BJ.dealer.hidden = c
      announce_template("deal_dealer_hole", {})
    end
  end

  BJ.next_deal_ms = now + math.max(0, BJ.config.deal_reveal_delay_ms)
  return true
end

function deal_queue_complete()
  return BJ.deal_queue == nil or #BJ.deal_queue == 0
end

draw_dealer_section = function()
  ensure_runtime_state()

  ui_text_colored("Dealer", 1.0, 0.92, 0.35, 1.0)
  if BJ.dealer.cards == nil or #BJ.dealer.cards == 0 then
    ui_text("Cards: (none)")
  else
    ui_text("Cards:")
    draw_hand(BJ.dealer.cards)
    if BJ.round_active and BJ.dealer.hidden ~= nil then
      ui_same_line()
      if ui_card_back ~= nil then ui_card_back() else ui_card("?", "?", false) end
    end
  end

  if BJ.round_active and BJ.dealer.hidden ~= nil then
    local up = hand_total(BJ.dealer.cards)
    ui_text("Total: " .. tostring(up) .. "+")
  else
    ui_text("Total: " .. tostring(hand_total(BJ.dealer.cards)))
  end
end

draw_player_row = function(name, p)
  ui_text(name .. " @" .. (p.world or "Unknown") .. " | Bank: " .. tostring(dealer_get_bank(name)))

  for hi = 1, #p.hands do
    local h = p.hands[hi]
    local total = hand_total(h.cards)

    local state = ""
    if h.bust then state = "BUST" end
    if h.standing then state = "STAND" end
    if h.doubled then state = state .. " DOUBLE" end

    ui_text("  Hand " .. tostring(hi) .. " | Wager: " .. tostring(h.wager) .. " | " .. state)
    draw_hand(h.cards)
    ui_text("  Total: " .. tostring(total))

    local currentPlayer = (BJ.round_active and BJ.active <= #BJ.order and BJ.order[BJ.active] == name)
    local currentHand = (p.hand_index == hi)
    if currentPlayer and currentHand and not h.finished then
      local shown = false
      if total < 21 then
        if action_button(name, hi, "hit", "Hit") then bj_hit() end
        shown = true
      end

      if shown then ui_same_line() end
      if action_button(name, hi, "stand", "Stand") then bj_stand() end
      shown = true

      if can_double(name, p, h) then
        if shown then ui_same_line() end
        if action_button(name, hi, "double", "Double") then bj_double() end
        shown = true
      end

      if can_split(name, p, h) then
        if shown then ui_same_line() end
        if action_button(name, hi, "split", "Split") then bj_split() end
      end
    end

    ui_separator()
  end
end

function draw_config_ui()
  ensure_runtime_state()

  ui_text_colored("Blackjack Config", 0.8, 0.9, 1.0, 1.0)
  ui_separator()

  BJ.config.min_bet = math.max(0, ui_input_int("Min Bet", BJ.config.min_bet))
  BJ.config.max_bet = math.max(BJ.config.min_bet, ui_input_int("Max Bet", BJ.config.max_bet))
  BJ.config.deal_reveal_delay_ms = math.max(0, ui_input_int("Card Reveal Delay (ms)", BJ.config.deal_reveal_delay_ms or BJ.config.deal_delay_ms or 150))
  BJ.config.max_splits = math.max(0, ui_input_int("Max Splits", BJ.config.max_splits))
  BJ.config.split_aces = ui_checkbox("Allow Split Aces", BJ.config.split_aces)
  BJ.config.hit_soft_17 = ui_checkbox("Dealer Hits Soft 17", BJ.config.hit_soft_17)
  BJ.config.allow_double = ui_checkbox("Allow Double Down", BJ.config.allow_double)
  BJ.config.allow_double_after_split = ui_checkbox("Allow Double After Split", BJ.config.allow_double_after_split)
  BJ.config.dealer_peek_blackjack = ui_checkbox("Dealer Peek for Blackjack", BJ.config.dealer_peek_blackjack)
  BJ.config.blackjack_payout_x100 = math.max(100, ui_input_int("Blackjack Payout x100", BJ.config.blackjack_payout_x100))

  ui_separator()
  ui_text("Chat tokens: <player> <bet> <bank> <card> <total> <dealer_total> <result>")
end

function draw_ui()
  ensure_runtime_state()
  rebuild_roster_from_dealer()
  process_chat_inputs()

  if not deal_queue_complete() then
    process_deal_step()
    if not deal_queue_complete() then
      BJ.phase = "dealing"
      BJ.info = "Dealing..."
    end
  end

  if deal_queue_complete() and BJ.round_active then
    if not handle_dealer_peek_if_needed() then
      if not queue_active_opening_hand_if_needed() then
        if BJ.active <= #BJ.order then
          local p = BJ.players[BJ.order[BJ.active]]
          local h = active_hand(p)
          if p ~= nil and h ~= nil and #h.cards >= 2 and not h.finished then
            BJ.phase = "player_turn"
            BJ.info = active_player_label(BJ.order[BJ.active], p, p.hand_index) .. " to act."
          end
        end
      end
    end
  end

  announce_turn_prompt_if_needed()
  execute_pending_auto_action()

  ui_text_colored("Blackjack Dealer Table", 1.0, 0.9, 0.3, 1.0)
  ui_separator()

  if ui_button("New Shoe") then bj_new_shoe() end
  ui_same_line()
  if ui_button("New Round") then bj_new_round() end

  ui_text(BJ.info .. " | Phase: " .. tostring(BJ.phase or "idle") .. " | Card Reveal Delay: " .. tostring(BJ.config.deal_reveal_delay_ms or 0) .. "ms | Out: " .. tostring(output_channel_name()))

  for i = 1, #BJ.order do
    local name = BJ.order[i]
    local p = BJ.players[name]
    if p ~= nil and draw_player_row ~= nil then
      draw_player_row(name, p)
    end
  end

  if draw_dealer_section ~= nil then
    draw_dealer_section()
  end

  ui_separator()
  ui_text_colored("Chat", 1.0, 1.0, 0.8, 1.0)
  ui_separator()
end

function ensure_runtime_state()
  BJ._missing_host = BJ._missing_host or {}

  local function patch_host(name, fallback)
    if _G[name] == nil then
      _G[name] = fallback
      if not BJ._missing_host[name] then
        BJ._missing_host[name] = true
        if log ~= nil then log("Missing host function: " .. name) end
      end
    end
  end

  patch_host("time_ms", function() return 0 end)
  patch_host("default_chat_channel", function() return "party" end)
  patch_host("ui_text", function(_) end)
  patch_host("ui_text_colored", function(text, _, _, _, _) ui_text(text) end)
  patch_host("ui_button", function(_) return false end)
  patch_host("ui_button_colored", function(label, _, _, _, _) return ui_button(label) end)
  patch_host("ui_same_line", function() end)
  patch_host("ui_separator", function() end)
  patch_host("ui_input_int", function(_, v) return v end)
  patch_host("ui_checkbox", function(_, v) return v end)
  patch_host("ui_card", function(rank, suit, _) ui_text((rank or "?") .. (suit or "?")) end)
  patch_host("ui_card_back", function() ui_card("?", "?", false) end)

  if BJ.dealer == nil then
    BJ.dealer = { cards = {}, hidden = nil, finished = false, peek_checked = false }
  end
  BJ.dealer.cards = BJ.dealer.cards or {}
  BJ.dealer.peek_checked = BJ.dealer.peek_checked == true

  BJ.players = BJ.players or {}
  BJ.order = BJ.order or {}
  BJ.active = BJ.active or 1
  BJ.round_active = BJ.round_active or false
  BJ.phase = BJ.phase or "idle"
  BJ.info = BJ.info or "Ready."
  BJ.deal_queue = BJ.deal_queue or {}
  BJ.next_deal_ms = BJ.next_deal_ms or 0
  BJ.chat_hint = BJ.chat_hint or { player = "", action = "", turn_key = "", expires_ms = 0 }
  BJ.chat_hint.turn_key = BJ.chat_hint.turn_key or ""
  BJ.auto_pending = BJ.auto_pending or nil

  BJ.config = BJ.config or {}
  BJ.config.min_bet = BJ.config.min_bet or 10
  BJ.config.max_bet = BJ.config.max_bet or 10000
  BJ.config.deal_reveal_delay_ms = BJ.config.deal_reveal_delay_ms or BJ.config.deal_delay_ms or 350
  BJ.config.deal_delay_ms = BJ.config.deal_reveal_delay_ms
  BJ.config.max_splits = BJ.config.max_splits or 2
  BJ.config.split_aces = BJ.config.split_aces == true
  BJ.config.hit_soft_17 = BJ.config.hit_soft_17 ~= false
  BJ.config.allow_double = BJ.config.allow_double ~= false
  BJ.config.allow_double_after_split = BJ.config.allow_double_after_split ~= false
  BJ.config.dealer_peek_blackjack = BJ.config.dealer_peek_blackjack ~= false
  BJ.config.blackjack_payout_x100 = BJ.config.blackjack_payout_x100 or 150
  BJ.turn_prompted_key = BJ.turn_prompted_key or nil

  for name, p in pairs(BJ.players) do
    p.world = p.world or "Unknown"
    p.wager = p.wager or dealer_get_wager(name) or 0
    p.splits_used = p.splits_used or 0

    -- Legacy migration: previous versions stored single-hand data directly on player.
    if p.hands == nil then
      local legacyCards = p.cards or {}
      p.hands = {
        {
          cards = legacyCards,
          finished = p.finished == true,
          bust = p.bust == true,
          standing = p.standing == true,
          doubled = false,
          from_split = false,
          wager = p.wager or 0,
        }
      }
      p.cards = nil
      p.finished = nil
      p.bust = nil
      p.standing = nil
    end

    if #p.hands == 0 then
      table.insert(p.hands, {
        cards = {}, finished = false, bust = false, standing = false, doubled = false, from_split = false, wager = p.wager or 0
      })
    end

    p.hand_index = p.hand_index or 1
    if p.hand_index < 1 then p.hand_index = 1 end

    for i = 1, #p.hands do
      local h = p.hands[i]
      h.cards = h.cards or {}
      h.finished = h.finished == true
      h.bust = h.bust == true
      h.standing = h.standing == true
      h.doubled = h.doubled == true
      h.from_split = h.from_split == true
      h.wager = h.wager or p.wager or 0
    end
  end
end

function can_double(name, p, h)
  if not BJ.config.allow_double then return false end
  if p == nil or h == nil then return false end
  if #h.cards ~= 2 or h.doubled then return false end
  if h.from_split == true and not BJ.config.allow_double_after_split then return false end
  local bank = dealer_get_bank(name)
  return bank >= (h.wager or 0)
end

function can_split(name, p, h)
  if p == nil or h == nil then return false end
  if p.splits_used >= BJ.config.max_splits then return false end
  if #h.cards ~= 2 then return false end

  local r1 = card_rank(h.cards[1])
  local r2 = card_rank(h.cards[2])
  if r1 ~= r2 then return false end
  if r1 == "Ace" and not BJ.config.split_aces then return false end

  local bank = dealer_get_bank(name)
  return bank >= (h.wager or 0)
end

execute_pending_auto_action = function()
  local pending = BJ.auto_pending
  if pending == nil then return end
  if not BJ.round_active then BJ.auto_pending = nil return end
  if BJ.phase ~= "player_turn" then return end
  if not deal_queue_complete() then return end
  if time_ms() < (pending.execute_at or 0) then return end

  local activeName = (BJ.active >= 1 and BJ.active <= #BJ.order) and BJ.order[BJ.active] or ""
  if pending.player ~= activeName then
    BJ.auto_pending = nil
    return
  end
  if (pending.turn_key or "") == "" or pending.turn_key ~= current_turn_key() then
    BJ.auto_pending = nil
    return
  end

  local p = BJ.players[activeName]
  local h = active_hand(p)
  if p == nil or h == nil or h.finished then
    BJ.auto_pending = nil
    return
  end

  local action = pending.action
  if action == "hit" and hand_total(h.cards) < 21 then
    bj_hit()
  elseif action == "stand" then
    bj_stand()
  elseif action == "double" and can_double(activeName, p, h) then
    bj_double()
  elseif action == "split" and can_split(activeName, p, h) then
    bj_split()
  end

  BJ.auto_pending = nil
end
