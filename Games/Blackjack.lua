------------------------------------------------------------------------
-- Macro Blackjack: Smart Flow Edition 1.1
-- Corrected UI Spacing, Standard Cards, Hard 17 Automation, Bank Thread Fix
------------------------------------------------------------------------

-- --- Hardcoded Defaults Fallback ---
local default_templates = {
  start = "Blackjack round started for <total> players.",
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
    rtp_rounds = 0,
    rtp_wagered = 0,
    rtp_paid = 0,
    rtp_last_round_id = 0,
    config = {
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
    share_blob = "",
    show_help = true,
  }
end

if not MBJ.config then MBJ.config = {} end
if not MBJ.chat_templates then MBJ.chat_templates = {} end
if MBJ.show_help == nil then MBJ.show_help = true end

for k, v in pairs(default_templates) do
  if MBJ.chat_templates[k] == nil or MBJ.chat_templates[k] == "" then 
    MBJ.chat_templates[k] = v 
  end
end

------------------------------------------------------------------------
-- HOST API ARMOR
------------------------------------------------------------------------
local function get_time_ms()
  if type(time_ms) == "function" then return tonumber(time_ms()) or 0 end
  return 0
end

local function safe_same_line()
  if type(ui_same_line) == "function" then ui_same_line() end
end

local function safe_separator()
  if type(ui_separator) == "function" then ui_separator() end
end

local function safe_dummy(w, h)
  if type(ui_dummy) == "function" then ui_dummy(w, h) end
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
    s = s .. k .. "=[=[" .. tostring(v or "") .. "]=],"
  end
  s = s .. "}}"
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
  
  if data.config then for k, v in pairs(data.config) do MBJ.config[k] = v end end
  if data.chat_templates then for k, v in pairs(data.chat_templates) do MBJ.chat_templates[k] = v end end
  return "SUCCESS: Configuration applied successfully!"
end

local function config_file_name() return "Blackjack.config.json" end
local function rtp_log_file_name() return "Blackjack.rtp.csv" end

local function csv_escape(v)
  local s = tostring(v or "")
  s = string.gsub(s, '"', '""')
  return '"' .. s .. '"'
end

local function append_rtp_log_row(row)
  if script_read_text == nil or script_write_text == nil or type(row) ~= "table" then return false end
  local header = "timestamp_ms,round_id,player,hand,wager,payout,net,result,dealer_total,player_total\n"
  local line = table.concat({
    tostring(math.floor(tonumber(row.timestamp_ms) or 0)),
    tostring(math.floor(tonumber(row.round_id) or 0)),
    csv_escape(row.player),
    tostring(math.floor(tonumber(row.hand) or 0)),
    tostring(math.floor(tonumber(row.wager) or 0)),
    tostring(math.floor(tonumber(row.payout) or 0)),
    tostring(math.floor(tonumber(row.net) or 0)),
    csv_escape(row.result),
    tostring(math.floor(tonumber(row.dealer_total) or 0)),
    tostring(math.floor(tonumber(row.player_total) or 0))
  }, ",") .. "\n"

  local existing = script_read_text(rtp_log_file_name()) or ""
  if existing == "" then return script_write_text(rtp_log_file_name(), header .. line) == true end
  return script_write_text(rtp_log_file_name(), existing .. line) == true
end

local function record_rtp_result(player, handIndex, wager, payout, resultKey, dealerTotal, playerTotal)
  local w = math.floor(math.max(0, tonumber(wager) or 0))
  local p = math.floor(math.max(0, tonumber(payout) or 0))
  MBJ.rtp_wagered = math.floor((tonumber(MBJ.rtp_wagered) or 0) + w)
  MBJ.rtp_paid = math.floor((tonumber(MBJ.rtp_paid) or 0) + p)
  
  append_rtp_log_row({
    timestamp_ms = get_time_ms(),
    round_id = tonumber(MBJ.rtp_last_round_id) or 0,
    player = tostring(player or ""),
    hand = tonumber(handIndex) or 0,
    wager = w, payout = p, net = p - w,
    result = tostring(resultKey or ""),
    dealer_total = tonumber(dealerTotal) or 0,
    player_total = tonumber(playerTotal) or 0,
  })
end

local function echo_notice(msg)
  local text = tostring(msg or "")
  if text == "" then return end
  if type(chat_send) == "function" then chat_send("echo", text) elseif type(dealer_party) == "function" then dealer_party(text) end
end

local function save_config_file()
  if type(script_write_text) ~= "function" then
    MBJ.import_status = "ERROR: Host file API unavailable."
    echo_notice("Blackjack config save failed.")
    return false
  end
  local ok = script_write_text(config_file_name(), export_blob()) == true
  MBJ.import_status = ok and "SUCCESS: Blackjack config saved." or "ERROR: Could not write file."
  echo_notice(ok and "Blackjack config saved." or "Blackjack config save failed.")
  return ok
end

local function load_config_file()
  if type(script_read_text) ~= "function" then return false end
  local raw = script_read_text(config_file_name())
  if raw == nil or raw == "" then return false end
  MBJ.import_status = import_blob(raw)
  return string.find(MBJ.import_status, "SUCCESS", 1, true) ~= nil
end

if MBJ._config_loaded ~= true then
  load_config_file()
  MBJ._config_loaded = true
end

-- NEW SAFE FLUSH FUNCTION
local function flush_chat()
  if type(chat_poll) == "function" then
    -- Safely bounded loop (max 200) to clear old entries without locking the thread
    for _ = 1, 200 do 
      if chat_poll() == nil then break end 
    end
  end
end

-- ==========================================
-- GAME LOGIC & MATH
-- ==========================================
local function output_channel_name()
  if type(default_chat_channel) == "function" then
    local ch = default_chat_channel()
    if ch == "echo" or ch == "say" or ch == "party" then return ch end
  end
  return "party"
end

local function table_announce(msg)
  local text = tostring(msg or "")
  if text == "" then return end
  if type(chat_send) == "function" then chat_send(output_channel_name(), text) elseif type(dealer_party) == "function" then dealer_party(text) end
end

local function fmt(template, ctx)
  if type(chat_format) == "function" then
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
  for token, value in pairs(values) do msg = string.gsub(msg, token, value) end
  return msg
end

local function announce(key, ctx)
  local template = (MBJ.chat_templates or {})[key]
  if template == nil or template == "" then template = default_templates[key] end
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

local function get_cv(card)
  if type(card) == "table" then return card.v end
  return tonumber(card) or 0
end

local function hand_total(cards)
  local total = 0
  local aces = 0
  for i = 1, #cards do
    local v = get_cv(cards[i])
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
  if hand == nil or hand.cards == nil or #hand.cards ~= 2 then return false end
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
  if p ~= nil and p.hands ~= nil and #p.hands > 1 then return name .. " [H" .. tostring(hi) .. "]" end
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

local function check_turn_state()
  next_active_hand()
  if active_player_name() == "" then
    MBJ.phase = "dealer_turn"
    local total = hand_total(MBJ.dealer.cards)
    MBJ.info = "Dealer's turn. Total: " .. tostring(total) .. (total < 17 and " (Must Hit)" or " (Must Stand)")
  else
    local name = active_player_name()
    local p = MBJ.players[name]
    MBJ.phase = "player_turn"
    MBJ.info = label_for(name, p, p.hand_index) .. " to act."
  end
end

-- ==========================================
-- RESTRICTIONS & VALIDATIONS
-- ==========================================
local function get_double_restriction(name, p, h, check_funds)
  if not MBJ.config.allow_double then return "err_dd_disabled" end
  if p == nil or h == nil then return nil end
  if #h.cards ~= 2 or h.doubled then return "err_dd_cards" end
  if h.from_split == true and not MBJ.config.allow_double_after_split then return "err_dd_das" end
  
  if check_funds then
    local bank = (type(dealer_get_bank) == "function") and (tonumber(dealer_get_bank(name)) or 0) or 0
    if bank < (tonumber(h.wager) or 0) then return "err_dd_funds" end
  end
  return nil
end

local function can_double(name, p, h, check_funds) return get_double_restriction(name, p, h, check_funds) == nil end

local function get_split_restriction(name, p, h, check_funds)
  if p == nil or h == nil then return nil end
  if p.splits_used >= (tonumber(MBJ.config.max_splits) or 0) then return "err_split_max" end
  if #h.cards ~= 2 then return "err_split_cards" end
  
  local c1 = get_cv(h.cards[1])
  local c2 = get_cv(h.cards[2])
  local sameRank = (c1 == c2)
  local bothTenValue = (card_value(c1) == 10 and card_value(c2) == 10)
  
  if not sameRank and not bothTenValue then return "err_split_value" end
  if tonumber(c1) == 1 and not MBJ.config.split_aces then return "err_split_aces" end
  
  if check_funds then
    local bank = (type(dealer_get_bank) == "function") and (tonumber(dealer_get_bank(name)) or 0) or 0
    if bank < (tonumber(h.wager) or 0) then return "err_split_funds" end
  end
  return nil
end

local function can_split(name, p, h, check_funds) return get_split_restriction(name, p, h, check_funds) == nil end

local function effective_draw_delay_ms()
  local v = tonumber(MBJ.draw.delay_ms) or 350
  local function clamp(val, minv, maxv) if val < minv then return minv elseif val > maxv then return maxv else return val end end
  MBJ.draw.delay_ms = clamp(v, 25, 5000)
  return MBJ.draw.delay_ms
end

local function effective_initial_deal_delay_ms()
  local v = tonumber(MBJ.draw.initial_deal_delay_ms) or 1000
  local function clamp(val, minv, maxv) if val < minv then return minv elseif val > maxv then return maxv else return val end end
  MBJ.draw.initial_deal_delay_ms = clamp(v, 100, 5000)
  return MBJ.draw.initial_deal_delay_ms
end

local function effective_draw_timeout_ms()
  local t = tonumber(MBJ.draw.timeout_ms) or 1500
  local function clamp(val, minv, maxv) if val < minv then return minv elseif val > maxv then return maxv else return val end end
  MBJ.draw.timeout_ms = clamp(t, math.max(900, effective_draw_delay_ms() * 4), 6000)
  return MBJ.draw.timeout_ms
end

local function effective_reveal_delay_ms()
  local v = tonumber(MBJ.draw.reveal_delay_ms) or 1000
  local function clamp(val, minv, maxv) if val < minv then return minv elseif val > maxv then return maxv else return val end end
  MBJ.draw.reveal_delay_ms = clamp(v, 100, 5000)
  return MBJ.draw.reveal_delay_ms
end

-- ==========================================
-- ASYNC ROLL DRAWING
-- ==========================================
local function enqueue_draw(on_card)
  if on_card == nil then return end
  table.insert(MBJ.draw.pending, on_card)
end

local function process_pending_draws()
  local d = MBJ.draw
  if d == nil then return end

  effective_draw_timeout_ms(); effective_initial_deal_delay_ms(); effective_reveal_delay_ms()
  local now = get_time_ms()

  if d.resolved_cb ~= nil and now >= (d.resolved_at or 0) then
    local cb, rolled = d.resolved_cb, d.resolved_roll
    d.resolved_cb, d.resolved_roll, d.resolved_at = nil, nil, 0
    if cb ~= nil then cb(rolled) end
    now = get_time_ms()
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
    
    -- Safe buffer clear right before issuing the actual command
    flush_chat() 
    
    if type(dice_command) ~= "function" or not dice_command(ch, 13) then
      MBJ.info = "Dice command unavailable (/dice " .. ch .. " 13)."
      MBJ.phase = "idle"
      d.pending, d.active, d.inflight, d.resolved_cb, d.resolved_roll, d.resolved_at = {}, nil, false, nil, nil, 0
      return
    end
    d.inflight, d.sent_ms = true, now
  end

  for _ = 1, 24 do
    local packet = (type(chat_poll) == "function") and chat_poll() or ""
    if packet == nil or packet == "" then break end

    local _, _, _, message = string.match(packet, "^([^|]*)|([^|]*)|([^|]*)|(.*)$")
    if message ~= nil then
      local rolled = (type(dice_roll_value) == "function") and dice_roll_value(message) or 0
      local upper = (type(dice_roll_upper) == "function") and dice_roll_upper(message) or 0
      if rolled >= 1 and rolled <= 13 and upper == 13 then
        local cb = d.active
        d.active, d.inflight, d.sent_ms = nil, false, 0
        local nextDelay = tonumber(d.next_delay_ms) or effective_draw_delay_ms()
        d.next_delay_ms = nil
        d.next_ms = get_time_ms() + nextDelay
        
        local suits = {"♠", "♥", "♦", "♣"}
        local s = suits[math.random(1, 4)]
        local card_obj = { v = rolled, s = s, r = (s == "♥" or s == "♦") }

        if cb ~= nil then
          d.resolved_cb = cb
          d.resolved_roll = card_obj
          d.resolved_at = get_time_ms() + effective_reveal_delay_ms()
        end
        break
      end
    end
  end
end

-- ==========================================
-- ACTIONS & SETTLEMENT
-- ==========================================
local function settle_results()
  MBJ.rtp_last_round_id = (tonumber(MBJ.rtp_last_round_id) or 0) + 1
  MBJ.rtp_rounds = (tonumber(MBJ.rtp_rounds) or 0) + 1

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

          if delta ~= 0 and type(dealer_add_bank) == "function" then dealer_add_bank(name, delta) end

          local payout_for_rtp = (tonumber(wager) or 0) + (tonumber(delta) or 0)
          if payout_for_rtp < 0 then payout_for_rtp = 0 end
          record_rtp_result(name, hi, wager, payout_for_rtp, template_key, dealer_total, pt)

          local bank = (type(dealer_get_bank) == "function") and (tonumber(dealer_get_bank(name)) or 0) or 0
          announce(template_key, {
            player = label_for(name, p, hi),
            total = pt, dealer_total = dealer_total, bet = wager, bank = bank,
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
  flush_chat()
  MBJ.players, MBJ.order, MBJ.active_index, MBJ.dealer.cards = {}, {}, 1, {}
  MBJ.round_active = true
  MBJ.draw.pending, MBJ.draw.active, MBJ.draw.inflight = {}, nil, false
  MBJ.draw.sent_ms, MBJ.draw.next_ms, MBJ.draw.resolved_at = 0, 0, 0
  MBJ.draw.resolved_cb, MBJ.draw.resolved_roll = nil, nil

  local count = 0
  if type(dealer_player_count) == "function" then count = dealer_player_count() end
  
  for i = 1, count do
    local name = ""
    if type(dealer_player_name) == "function" then name = dealer_player_name(i) end
    
    local eligible = false
    if type(dealer_is_eligible) == "function" then eligible = dealer_is_eligible(name) end
    
    if name ~= "" and eligible then
      table.insert(MBJ.order, name)
      local p = ensure_player(name)
      local wager = (type(dealer_get_wager) == "function") and (tonumber(dealer_get_wager(name)) or 0) or 0
      p.wager = wager
      p.hand_index = 1
      p.splits_used = 0
      p.hands = { { cards = {}, finished = false, bust = false, standing = false, doubled = false, from_split = false, wager = wager } }
    end
  end

  if #MBJ.order == 0 then
    MBJ.phase, MBJ.info, MBJ.round_active = "idle", "No eligible players.", false
    return
  end

  announce("start", { total = #MBJ.order })
  
  enqueue_draw(function(c)
    table.insert(MBJ.dealer.cards, c)
    announce("dealer_first", { card = rank_name(c.v) })
    check_turn_state()
  end)
  table.insert(MBJ.action_history, { action = "dealer_draw", timestamp = get_time_ms() })
end

local function draw_for_active(kind)
  next_active_hand()
  local name = active_player_name()
  if name == "" then
    MBJ.phase = "awaiting_dealer"
    MBJ.info = "All player hands complete. Draw dealer cards, then resolve."
    return
  end

  local p = MBJ.players[name]
  local h = active_hand(p)
  if p == nil or h == nil or h.finished then
    next_active_hand(); MBJ.info = "Advanced to next hand."; return
  end

  MBJ.phase = "dealing"
  MBJ.info = label_for(name, p, p.hand_index) .. " drawing..."

  enqueue_draw(function(c)
    if h.finished then return end
    table.insert(h.cards, c)
    local total = hand_total(h.cards)

    if kind == "hit" then
      announce("player_hit", { player = label_for(name, p, p.hand_index), card = rank_name(c.v), total = total })
    elseif kind == "deal_first" then
      announce("player_draw2", { player = label_for(name, p, p.hand_index), card = rank_name(c.v) })
    else
      announce("player_draw", { player = label_for(name, p, p.hand_index), card = rank_name(c.v), total = total })
    end

    if total >= 21 then
      h.bust = (total > 21)
      h.finished = true
      if h.bust then
        announce("player_bust", { player = label_for(name, p, p.hand_index) })
      else
        h.standing = true
        announce("player_stand", { player = label_for(name, p, p.hand_index), total = 21 })
      end
      p.hand_index = p.hand_index + 1
    end
    check_turn_state()
  end)
end

local function do_stand()
  local name = active_player_name()
  if name == "" then return end

  local p = MBJ.players[name]
  local h = active_hand(p)
  if p == nil or h == nil or h.finished then return end

  h.standing, h.finished = true, true
  announce("player_stand", { player = label_for(name, p, p.hand_index), total = hand_total(h.cards) })
  p.hand_index = p.hand_index + 1
  check_turn_state()
end

local function do_double()
  local name = active_player_name()
  local p = MBJ.players[name]
  local h = active_hand(p)
  if name == "" or p == nil or h == nil then return end
  
  local restriction = get_double_restriction(name, p, h, true)
  if restriction then
    local formatted_err = fmt((MBJ.chat_templates or {})[restriction] or "Double down not allowed.", { bet = tonumber(h.wager) or 0, bank = (type(dealer_get_bank) == "function") and (tonumber(dealer_get_bank(name)) or 0) or 0 })
    MBJ.info = formatted_err
    table_announce(name .. " cannot double down: " .. formatted_err)
    return
  end

  h.wager = (tonumber(h.wager) or 0) * 2
  h.doubled = true
  MBJ.info = label_for(name, p, p.hand_index) .. " doubling..."

  enqueue_draw(function(c)
    table.insert(h.cards, c)
    local total = hand_total(h.cards)
    h.finished, h.standing, h.bust = true, total <= 21, total > 21

    announce("player_double", { player = label_for(name, p, p.hand_index), card = rank_name(c.v), total = total })
    if h.bust then announce("player_bust", { player = label_for(name, p, p.hand_index) }) end

    p.hand_index = p.hand_index + 1
    check_turn_state()
  end)
end

local function do_split()
  local name = active_player_name()
  local p = MBJ.players[name]
  local h = active_hand(p)
  if name == "" or p == nil or h == nil then return end
  
  local restriction = get_split_restriction(name, p, h, true)
  if restriction then
    local formatted_err = fmt((MBJ.chat_templates or {})[restriction] or "Split not allowed.", { total = tonumber(MBJ.config.max_splits) or 0, bet = tonumber(h.wager) or 0, bank = (type(dealer_get_bank) == "function") and (tonumber(dealer_get_bank(name)) or 0) or 0 })
    MBJ.info = formatted_err
    table_announce(name .. " cannot split: " .. formatted_err)
    return
  end

  local c1, c2 = h.cards[1], h.cards[2]
  h.cards = { c1 }
  h.finished, h.bust, h.standing, h.doubled, h.from_split = false, false, false, false, true

  local h2 = { cards = { c2 }, finished = false, bust = false, standing = false, doubled = false, from_split = true, wager = h.wager }
  table.insert(p.hands, p.hand_index + 1, h2)
  p.splits_used = (p.splits_used or 0) + 1

  announce("player_split", { player = label_for(name, p, p.hand_index), bet = h.wager, bank = (type(dealer_get_bank) == "function") and (tonumber(dealer_get_bank(name)) or 0) or 0 })
  check_turn_state()
end

local function dealer_draw_one()
  MBJ.info = "Dealer drawing..."

  enqueue_draw(function(c)
    table.insert(MBJ.dealer.cards, c)
    announce("dealer_draw", { card = rank_name(c.v), total = hand_total(MBJ.dealer.cards) })
    check_turn_state()
  end)
  table.insert(MBJ.action_history, { action = "dealer_draw", timestamp = get_time_ms() })
end

local function undo_last_action()
  if #MBJ.action_history == 0 then MBJ.info = "No actions to undo."; return end
  local last = table.remove(MBJ.action_history)
  
  if last.action == "dealer_draw" then
    if #MBJ.dealer.cards > 0 then
      table.remove(MBJ.dealer.cards)
      table_announce("(Dealer action undone)")
      check_turn_state()
    end
  elseif last.action == "player_draw" or last.action == "player_hit" then
    local name, hand_idx = last.player_name, last.hand_idx
    if name and MBJ.players[name] and MBJ.players[name].hands[hand_idx] then
      local h = MBJ.players[name].hands[hand_idx]
      if #h.cards > 0 then
        table.remove(h.cards)
        h.bust, h.finished, h.standing = false, false, false
        MBJ.players[name].hand_index = hand_idx
        table_announce("(" .. name .. " card removed)")
        
        for idx, n in ipairs(MBJ.order) do if n == name then MBJ.active_index = idx end end
        check_turn_state()
      end
    end
  end
end

function on_command(cmd, ...)
  local command = string.lower(tostring(cmd or ""))
  if command == "bjstart" then start_round(); return "ok" end
  if command == "deal" then
    if not MBJ.round_active then MBJ.info = "No active round."; return "no_round" end
    local name = active_player_name()
    local p = MBJ.players[name]
    local h = active_hand(p)
    if h == nil then MBJ.info = "No active hand to deal."; return "no_hand" end

    if #h.cards == 0 then
      draw_for_active("deal_first")
      MBJ.draw.next_delay_ms = effective_initial_deal_delay_ms()
      draw_for_active("deal")
    else
      draw_for_active("deal")
    end
    table.insert(MBJ.action_history, { action = "player_draw", player_name = name, hand_idx = p.hand_index, timestamp = get_time_ms() })
    return "ok"
  end
  if command == "hit" then
    if not MBJ.round_active then return "no_round" end
    local name = active_player_name()
    draw_for_active("hit")
    table.insert(MBJ.action_history, { action = "player_hit", player_name = name, hand_idx = (MBJ.players[name] and MBJ.players[name].hand_index) or 1, timestamp = get_time_ms() })
    return "ok"
  end
  if command == "stand" then if not MBJ.round_active then return "no_round" end do_stand(); return "ok" end
  if command == "dd" then if not MBJ.round_active then return "no_round" end do_double(); return "ok" end
  if command == "split" then if not MBJ.round_active then return "no_round" end do_split(); return "ok" end
  if command == "dealer" then dealer_draw_one(); return "ok" end
  if command == "resolve" then if not MBJ.round_active then return "no_round" end settle_results(); return "ok" end
  if command == "undo" then undo_last_action(); return "ok" end
  return "unknown"
end

-- ==========================================
-- CANVAS UI DRAWING
-- ==========================================
local function draw_visual_cards(cards, x, y)
  if cards == nil or #cards == 0 then return end
  for i = 1, #cards do
    local c = cards[i]
    if type(ui_set_cursor) == "function" then ui_set_cursor(x + ((i - 1) * 25), y) end
    if type(ui_card) == "function" then
      if type(c) == "table" then
        ui_card(rank_name(c.v), c.s, c.r)
      else
        ui_card(rank_name(c), "♠", false)
      end
    end
  end
end

local function draw_game_canvas()
  local w = (type(ui_window_width) == "function") and ui_window_width() or 600
  local cx = (type(ui_cursor_x) == "function") and ui_cursor_x() or 10
  local cy = (type(ui_cursor_y) == "function") and ui_cursor_y() or 10
  local canvas_w = w - (cx * 2)
  if canvas_w < 400 then canvas_w = 400 end
  
  local base_h = (MBJ.phase == "dealer_turn" and 145 or 100)
  local canvas_h = base_h
  if #MBJ.order > 0 then
    for i = 1, #MBJ.order do
      local p = MBJ.players[MBJ.order[i]]
      if p ~= nil then
        for hi = 1, #p.hands do
          local is_active = (MBJ.order[i] == active_player_name() and hi == p.hand_index and MBJ.phase == "player_turn")
          canvas_h = canvas_h + (is_active and 150 or 85)
        end
      end
    end
  end

  if type(ui_rect_at) == "function" then
    ui_rect_at(cx, cy, canvas_w, canvas_h, 0.08, 0.22, 0.12, 0.9, true, 12)
    ui_rect_at(cx, cy, canvas_w, canvas_h, 0.15, 0.35, 0.20, 0.4, false, 12)
  elseif type(ui_set_cursor) == "function" and type(ui_rect) == "function" then
    ui_set_cursor(cx, cy)
    ui_rect(canvas_w, canvas_h, 0.08, 0.22, 0.12, 0.9, true)
  end

  if type(ui_set_cursor) == "function" then ui_set_cursor(cx + (canvas_w/2) - 40, cy + 10) end
  if type(ui_text_colored) == "function" then ui_text_colored("House Dealer (" .. tostring(hand_total(MBJ.dealer.cards)) .. ")", 0.8, 0.8, 0.8, 1.0) end
  
  local dealer_cards_w = (#MBJ.dealer.cards > 0) and (((#MBJ.dealer.cards - 1) * 25) + 40) or 40
  local dealer_start_x = cx + (canvas_w / 2) - (dealer_cards_w / 2)
  
  if #MBJ.dealer.cards > 0 then
    draw_visual_cards(MBJ.dealer.cards, dealer_start_x, cy + 30)
  else
    if type(ui_set_cursor) == "function" then ui_set_cursor(dealer_start_x, cy + 30) end
    if type(ui_card_back) == "function" then ui_card_back() end
  end

  if MBJ.phase == "dealer_turn" then
    local dtot = hand_total(MBJ.dealer.cards)
    local btn_col = type(ui_button_colored) == "function"
    
    if dtot < 17 then
      if type(ui_set_cursor) == "function" then ui_set_cursor(cx + (canvas_w/2) - 45, cy + 100) end
      if btn_col and ui_button_colored(" Dealer Hit ##mbj_act_dhit", 0.2, 0.4, 0.7, 1.0) then on_command("dealer") end
    else
      if type(ui_set_cursor) == "function" then ui_set_cursor(cx + (canvas_w/2) - 65, cy + 100) end
      if btn_col and ui_button_colored(" Resolve Payouts ##mbj_act_res", 0.8, 0.6, 0.1, 1.0) then on_command("resolve") end
    end
  end

  safe_separator()

  local current_y = cy + base_h
  if #MBJ.order == 0 then
    if type(ui_set_cursor) == "function" then ui_set_cursor(cx + 15, current_y) end
    if type(ui_text_colored) == "function" then ui_text_colored("Waiting for players...", 0.6, 0.6, 0.6, 1.0) end
  else
    for i = 1, #MBJ.order do
      local name = MBJ.order[i]
      local p = MBJ.players[name]
      
      if p ~= nil then
        local is_multi_hand = #p.hands > 1

        for hi = 1, #p.hands do
          local h = p.hands[hi]
          local is_active_hand = (name == active_player_name() and hi == p.hand_index and MBJ.phase == "player_turn")
          local row_h = is_active_hand and 150 or 85
          
          if type(ui_set_cursor) == "function" then ui_set_cursor(cx + 15, current_y) end
          local total = hand_total(h.cards)
          local title = name .. " (Total: " .. total .. ")"
          if is_multi_hand then title = name .. " [Hand " .. hi .. "] (Total: " .. total .. ")" end
          
          if type(ui_text_colored) == "function" then
             if is_active_hand then ui_text_colored(title, 1.0, 0.95, 0.6, 1.0)
             else ui_text_colored(title, 0.9, 0.9, 0.9, 1.0) end
          end
          
          draw_visual_cards(h.cards, cx + 15, current_y + 20)

          if type(ui_set_cursor) == "function" then ui_set_cursor(cx + canvas_w - 110, current_y + 20) end
          local btn_col = type(ui_button_colored) == "function"
          
          if h.bust and btn_col then ui_button_colored(" BUSTED ##b_"..hi, 0.8, 0.2, 0.2, 1.0)
          elseif is_natural_blackjack(h) and btn_col then ui_button_colored(" BLACKJACK ##b_"..hi, 0.8, 0.6, 0.1, 1.0)
          elseif h.doubled and btn_col then ui_button_colored(" DOUBLED ##b_"..hi, 0.2, 0.6, 0.8, 1.0)
          elseif h.standing and btn_col then ui_button_colored(" STAND ##b_"..hi, 0.3, 0.3, 0.3, 1.0)
          end

          if is_active_hand and not h.finished and MBJ.phase == "player_turn" then
            if type(ui_set_cursor) == "function" then ui_set_cursor(cx + 15, current_y + 110) end
            
            if #h.cards == 0 then
              if btn_col and ui_button_colored("Deal Hand##mbj_act_deal", 0.2, 0.4, 0.7, 1.0) then on_command("deal") end
            else
              if btn_col and ui_button_colored("Hit##mbj_act_hit", 0.2, 0.6, 0.2, 1.0) then on_command("hit") end
              safe_same_line()
              if btn_col and ui_button_colored("Stand##mbj_act_stand", 0.7, 0.3, 0.2, 1.0) then on_command("stand") end
              
              if can_double(name, p, h, false) then
                safe_same_line()
                if btn_col and ui_button_colored("Double##mbj_act_dd", 0.8, 0.6, 0.1, 1.0) then on_command("dd") end
              end
              
              if can_split(name, p, h, false) then
                safe_same_line()
                if btn_col and ui_button_colored("Split##mbj_act_sp", 0.5, 0.3, 0.7, 1.0) then on_command("split") end
              end
            end
          end

          current_y = current_y + row_h
        end
      end
    end
  end

  if type(ui_set_cursor) == "function" then ui_set_cursor(cx, cy + canvas_h + 10) end
  safe_dummy(canvas_w, 10)
end

function draw_config_ui()
  if type(ui_text_colored) == "function" then ui_text_colored("Macro Blackjack Config", 0.8, 0.95, 0.8, 1.0) end
  safe_separator()

  if type(ui_checkbox) == "function" then
    MBJ.config.allow_double = ui_checkbox("Allow Double Down##mbj_double", MBJ.config.allow_double)
    MBJ.config.allow_double_after_split = ui_checkbox("Allow Double After Split##mbj_das", MBJ.config.allow_double_after_split)
    MBJ.config.split_aces = ui_checkbox("Allow Split Aces##mbj_split_aces", MBJ.config.split_aces)
  end
  
  if type(ui_input_int) == "function" then
    MBJ.config.max_splits = math.max(0, ui_input_int("Max Splits##mbj_split_max", tonumber(MBJ.config.max_splits) or 2))
    MBJ.config.blackjack_payout_x100 = math.max(100, ui_input_int("Blackjack Payout % ##mbj_bjpay", tonumber(MBJ.config.blackjack_payout_x100) or 150))

    MBJ.draw.delay_ms = ui_input_int("Dice delay (ms)##mbj_dice_delay", effective_draw_delay_ms())
    MBJ.draw.initial_deal_delay_ms = ui_input_int("Dealing delay (ms)##mbj_initial_deal_delay", effective_initial_deal_delay_ms())
    MBJ.draw.reveal_delay_ms = ui_input_int("Result reveal delay (ms)##mbj_reveal_delay", effective_reveal_delay_ms())
    MBJ.draw.timeout_ms = ui_input_int("Dice timeout (ms)##mbj_dice_timeout", effective_draw_timeout_ms())
  end
  
  effective_draw_timeout_ms(); effective_initial_deal_delay_ms(); effective_reveal_delay_ms()

  if type(ui_collapsing_header) == "function" and ui_collapsing_header("Chat Templates##mbj_tpl_hdr") then
    if type(ui_input_text) == "function" then
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
      
      if type(ui_text_colored) == "function" then ui_text_colored("Payout Outcomes", 0.7, 0.85, 1.0, 1.0) end
      MBJ.chat_templates.result_push = ui_input_text("Push Outcome##mbj_tpl_res_push", MBJ.chat_templates.result_push or "", 512)
      MBJ.chat_templates.result_lose_bj = ui_input_text("Dealer BJ Outcome##mbj_tpl_res_lose_bj", MBJ.chat_templates.result_lose_bj or "", 512)
      MBJ.chat_templates.result_bj = ui_input_text("Player BJ Outcome##mbj_tpl_res_res_bj", MBJ.chat_templates.result_bj or "", 512)
      MBJ.chat_templates.result_win_bust = ui_input_text("Dealer Bust Outcome##mbj_tpl_res_win_bust", MBJ.chat_templates.result_win_bust or "", 512)
      MBJ.chat_templates.result_win = ui_input_text("Standard Win Outcome##mbj_tpl_res_win", MBJ.chat_templates.result_win or "", 512)
      MBJ.chat_templates.result_lose = ui_input_text("Standard Lose Outcome##mbj_tpl_res_lose", MBJ.chat_templates.result_lose or "", 512)
    end
  end

  safe_separator()
  if type(ui_text_colored) == "function" then ui_text_colored("Import / Export Configuration Blob", 0.4, 0.8, 1.0, 1.0) end
  
  if MBJ.share_blob == nil then MBJ.share_blob = "" end
  if type(ui_input_text) == "function" then MBJ.share_blob = ui_input_text("Data String##mbj_blob_field", MBJ.share_blob, 8192) end
  
  local btn = type(ui_button) == "function"
  if btn and ui_button("Generate Export Blob##mbj_btn_exp") then
    MBJ.share_blob = export_blob()
    MBJ.import_status = "SUCCESS: Generated export string!"
  end
  safe_same_line()
  if btn and ui_button("Import From Blob##mbj_btn_imp") then MBJ.import_status = import_blob(MBJ.share_blob) end
  safe_same_line()
  if btn and ui_button("Save Config##mbj_btn_save_file") then save_config_file() end
  safe_same_line()
  if btn and ui_button("Load Config##mbj_btn_load_file") then load_config_file() end
  
  if MBJ.import_status and MBJ.import_status ~= "" and type(ui_text_colored) == "function" then
    if string.find(MBJ.import_status, "SUCCESS") then ui_text_colored(MBJ.import_status, 0.3, 1.0, 0.3, 1.0)
    else ui_text_colored(MBJ.import_status, 1.0, 0.3, 0.3, 1.0) end
  end
end

function draw_ui()
  process_pending_draws()

  if type(ui_text_colored) == "function" then ui_text_colored("♠♥ MACRO BLACKJACK ♦♣", 1.0, 0.9, 0.4, 1.0) end
  safe_separator()

  local btn = type(ui_button) == "function"

  if btn and ui_button("Start Round##mbj_start") then on_command("bjstart") end
  safe_same_line()
  if btn and ui_button("Undo Last Roll##mbj_undo") then on_command("undo") end

  if type(ui_text) == "function" then ui_text("Status: " .. tostring(MBJ.phase) .. " | " .. tostring(MBJ.info)) end
  safe_separator()

  draw_game_canvas()

  safe_separator()
  if type(ui_text_colored) == "function" then ui_text_colored("Roster & Standings", 0.9, 0.95, 1.0, 1.0) end
  
  if #MBJ.order == 0 then
    if type(ui_text) == "function" then ui_text("(no active round)") end
  else
    for i = 1, #MBJ.order do
      local name = MBJ.order[i]
      local p = MBJ.players[name]
      if p ~= nil and type(ui_text) == "function" then
        ui_text(name .. " | Base Wager: " .. tostring(p.wager))
        for hi = 1, #p.hands do
          local h = p.hands[hi]
          local state = h.bust and "BUST" or (h.finished and "DONE" or "WAITING")
          if h.doubled then state = state .. " (x2)" end
          if h.from_split then state = state .. " (Split)" end
          ui_text("   Hand " .. tostring(hi) .. " -> Total: " .. tostring(hand_total(h.cards)) .. " [" .. state .. "]")
        end
      end
      safe_separator()
    end
  end

  local wagered = tonumber(MBJ.rtp_wagered) or 0
  local paid = tonumber(MBJ.rtp_paid) or 0
  local rounds = tonumber(MBJ.rtp_rounds) or 0
  local rtp = (wagered > 0) and ((paid / wagered) * 100.0) or 0
  if type(ui_text_colored) == "function" then
    ui_text_colored(string.format("♣ RTP: %.2f%% | Rounds: %d | Gil In: %d | Gil Out: %d", rtp, rounds, wagered, paid), 0.6, 0.8, 1.0, 1.0)
  end

  if type(ui_collapsing_header) == "function" then
    MBJ.show_help = ui_collapsing_header("Blackjack Help##mbj_help_section")
  end

  if MBJ.show_help == true then
    safe_separator()
    if type(ui_text_colored) == "function" then ui_text_colored("Commands", 0.9, 0.95, 1.0, 1.0) end
    if type(ui_text) == "function" then
      ui_text("/casino bjstart  - Starts a new round, resets players/hands, then draws dealer upcard.")
      ui_text("/casino deal     - Deals for the active hand (first call gives opening cards).")
      ui_text("/casino hit      - Draws one card for the active hand.")
      ui_text("/casino stand    - Marks active hand finished and advances to next hand/player.")
      ui_text("/casino dd       - Doubles wager, draws one final card, then auto-stands.")
      ui_text("/casino split    - Splits eligible 2-card hand into two hands with matching wager.")
      ui_text("/casino dealer   - Dealer draws one card.")
      ui_text("/casino resolve  - Compares all hands vs dealer and applies payouts.")
      ui_text("/casino undo     - Reverts last tracked draw action.")
    end
  end
end
