-- ============================================================================
-- derby_ffxiv_live_auto.lua
-- Final Polish: Auto-Resolve, Shorter Tracks, & Async Force Rolls
-- ============================================================================

if DERBY == nil then
  DERBY = {
    phase = "idle",
    info = "Ready to start.",
    pot = 0,
    scratch_count = 0,
    round = 0,
    total_horses = 10,
    dice_size = 10,
    track_len = 4,
    horses = {},
    players = {}, 
    roster = {},  
    round_rolls = {},
    
    config = {
      rake_percent = 0.10,
      scratches_fixed = 4,
    },

    draw = {
      delay_ms = 1000,
      timeout_ms = 3000,
      pending = {}, -- queue for async dealer rolls
      active = nil,
      inflight = false,
      sent_ms = 0,
      next_ms = 0,
    },

    chat_templates = {
      race_init = "DERBY: Setup! Dealer scratching <scratches> horses...",
      horse_scratched = "SCRATCHED: Horse <horse>",
      assignments_start = "ASSIGNMENTS: Live horses assigned:",
      assignment_line = " - <player>: <horses>",
      round_start_manual = "ROUND <round>: Roll /dice <dice> now!",
      winner = "WINNER: Horse <horse> crossed the finish line!",
      payout = "PAYOUT: <player> wins <payout> chips!",
      house_rake = "HOUSE: Collected <rake> chips (10% rake).",
    }
  }
end

-- ============================================================================
-- Helpers
-- ============================================================================

local function table_announce(msg)
  local channel = (default_chat_channel ~= nil) and default_chat_channel() or "party"
  if chat_send ~= nil then chat_send(channel, msg) end
end

local function announce(key, ctx)
  local template = DERBY.chat_templates[key]
  if not template then return end
  local msg = template
  local values = {
    ["<player>"] = tostring((ctx and ctx.player) or ""),
    ["<horse>"] = tostring((ctx and ctx.horse) or 0),
    ["<horses>"] = tostring((ctx and ctx.horses) or ""),
    ["<scratches>"] = tostring(DERBY.config.scratches_fixed),
    ["<round>"] = tostring((ctx and ctx.round) or 0),
    ["<dice>"] = tostring(DERBY.dice_size),
    ["<payout>"] = tostring((ctx and ctx.payout) or 0),
    ["<rake>"] = tostring((ctx and ctx.rake) or 0),
  }
  for token, value in pairs(values) do msg = string.gsub(msg, token, value) end
  table_announce(msg)
end

-- ============================================================================
-- Scaling & Track
-- ============================================================================

local function setup_race_scaling()
  DERBY.roster = {}
  local p_count = (dealer_player_count ~= nil) and dealer_player_count() or 0
  local seen = {}
  for i = 0, p_count + 1 do
    local name = dealer_player_name(i)
    if name and name ~= "" and not seen[name] then
      table.insert(DERBY.roster, name)
      seen[name] = true
      local wager = (dealer_get_wager ~= nil) and dealer_get_wager(name) or 20
      DERBY.players[name] = { wager = tonumber(wager) or 20 }
    end
  end

  if #DERBY.roster < 1 then return false end

  local total = 10
  if #DERBY.roster == 4 then total = 12
  elseif #DERBY.roster >= 5 then total = 14 end

  DERBY.total_horses = total
  DERBY.dice_size = total
  
  -- Sprints: 4 base + 1 for every 2 players over 2.
  DERBY.track_len = 4 + math.floor(math.max(0, #DERBY.roster - 2) / 2)
  
  DERBY.pot = 0
  DERBY.round = 0
  DERBY.scratch_count = 0
  DERBY.horses = {}
  for i = 1, total do DERBY.horses[i] = { id = i, pos = 0, scratched = false, owners = {} } end
  return true
end

local function assign_horses()
  local live = {}
  for i = 1, DERBY.total_horses do if not DERBY.horses[i].scratched then table.insert(live, i) end end
  local per_p = math.floor(#live / #DERBY.roster)
  announce("assignments_start")
  local h_idx = 1
  for i = 1, #DERBY.roster do
    local name = DERBY.roster[i]
    local ids = {}
    for _ = 1, per_p do
      local h_id = live[h_idx]
      if h_id then
        table.insert(DERBY.horses[h_id].owners, name)
        table.insert(ids, "H" .. h_id)
        h_idx = h_idx + 1
      end
    end
    announce("assignment_line", { player = name, horses = table.concat(ids, ", ") })
  end
end

-- ============================================================================
-- Resolution & Payout
-- ============================================================================

local function resolve_round()
  for _, name in ipairs(DERBY.roster) do
    local val = DERBY.round_rolls[name]
    if val then
      local h = DERBY.horses[val]
      if h and h.scratched then
        local w = DERBY.players[name].wager
        DERBY.pot = DERBY.pot + w
        if dealer_add_bank then dealer_add_bank(name, -w) end
        table_announce("PENALTY: " .. name .. " rolled Scratched H" .. val .. ". Added " .. w .. " to pot.")
      elseif h then
        h.pos = h.pos + 1
        table_announce("MOVE: H" .. val .. " moved (Rolled by " .. name .. ")")
      end
    end
  end

  local winners = {}
  for i = 1, DERBY.total_horses do
    if not DERBY.horses[i].scratched and DERBY.horses[i].pos >= DERBY.track_len then table.insert(winners, i) end
  end

  if #winners > 0 then
    announce("winner", { horse = table.concat(winners, " & ") })
    local rake = math.floor(DERBY.pot * DERBY.config.rake_percent)
    local net = DERBY.pot - rake
    if dealer_add_bank then dealer_add_bank("House", rake) end
    announce("house_rake", { rake = rake })
    local win_owners = {}
    for _, hid in ipairs(winners) do
      for _, owner in ipairs(DERBY.horses[hid].owners) do table.insert(win_owners, owner) end
    end
    if #win_owners > 0 then
      local share = math.floor(net / #win_owners)
      for _, name in ipairs(win_owners) do
        if dealer_add_bank then dealer_add_bank(name, share) end
        announce("payout", { player = name, payout = share })
      end
    end
    DERBY.phase = "settled"
  else
    DERBY.phase = "racing_idle"
    DERBY.info = "Round resolve complete."
  end
end

-- ============================================================================
-- Logic & Processing
-- ============================================================================

function process_logic()
  local now = (time_ms ~= nil) and time_ms() or 0
  local d = DERBY.draw

  -- 1. Dealer async rolling (Scratches & Force Rolls)
  if d.active == nil and #d.pending > 0 then d.active = table.remove(d.pending, 1) end
  if d.active ~= nil then
    if (not d.inflight) and now >= d.next_ms then
      if dice_command ~= nil and dice_command(default_chat_channel(), DERBY.dice_size) then
        d.inflight = true
        d.sent_ms = now
      end
    end
  end

  -- 2. Chat Polling
  local packet = (chat_poll ~= nil) and chat_poll() or ""
  if packet ~= "" then
    local name, _, _, message = string.match(packet, "^([^|]*)|([^|]*)|([^|]*)|(.*)$")
    if message then
      local rolled = (dice_roll_value ~= nil) and dice_roll_value(message) or 0
      local upper = (dice_roll_upper ~= nil) and dice_roll_upper(message) or 0
      
      if rolled >= 1 and upper == DERBY.dice_size then
        if d.active ~= nil then
          local cb = d.active
          d.active = nil
          d.inflight = false
          d.next_ms = now + 1000
          if cb then cb(rolled, name) end
        elseif DERBY.phase == "racing_waiting" then
          for _, r_name in ipairs(DERBY.roster) do
            if r_name == name and DERBY.round_rolls[name] == nil then
              DERBY.round_rolls[name] = rolled
              
              -- Auto Resolve Check
              local collected = 0
              for _ in pairs(DERBY.round_rolls) do collected = collected + 1 end
              if collected >= #DERBY.roster then resolve_round() end
              break
            end
          end
        end
      end
    end
  end
end

-- ============================================================================
-- UI Rendering
-- ============================================================================

function draw_ui()
  process_logic()

  ui_text("DERBY: SPRINT EDITION")
  ui_text("Status: " .. tostring(DERBY.info))
  ui_separator()

  if ui_button("Start Setup") then
    if setup_race_scaling() then
      for _, name in ipairs(DERBY.roster) do
        local w = DERBY.players[name].wager
        DERBY.pot = DERBY.pot + w
        if dealer_add_bank then dealer_add_bank(name, -w) end
      end
      DERBY.phase = "scratching"
      announce("race_init")
      
      local function do_scratch()
        if DERBY.scratch_count >= DERBY.config.scratches_fixed then
          assign_horses()
          DERBY.phase = "racing_idle"
        else
          table.insert(DERBY.draw.pending, function(v)
            local h = DERBY.horses[v]
            if h and not h.scratched then
              h.scratched = true
              DERBY.scratch_count = DERBY.scratch_count + 1
              announce("horse_scratched", { horse = v })
            end
            do_scratch()
          end)
        end
      end
      do_scratch()
    end
  end

  ui_text("Pot: " .. tostring(DERBY.pot) .. " | Track: " .. tostring(DERBY.track_len))

  if DERBY.phase == "racing_idle" then
    if ui_button("Start Round " .. (DERBY.round + 1)) then
      DERBY.round = DERBY.round + 1
      DERBY.round_rolls = {}
      DERBY.phase = "racing_waiting"
      announce("round_start_manual", { round = DERBY.round })
    end
  end

  ui_separator()

  -- ROSTER & FORCE ROLL
  if #DERBY.roster > 0 then
    ui_text("ROSTER:")
    for _, name in ipairs(DERBY.roster) do
      local rolled = DERBY.round_rolls[name]
      if DERBY.phase == "racing_waiting" then
        if rolled then
          ui_text(name .. ": Rolled " .. rolled)
        else
          ui_text(name .. ": WAITING...")
          ui_same_line()
          if ui_button("Dealer Roll##" .. name) then
            table.insert(DERBY.draw.pending, function(val)
              DERBY.round_rolls[name] = val
              table_announce("Dealer rolled for " .. name .. ": " .. val)
              local collected = 0
              for _ in pairs(DERBY.round_rolls) do collected = collected + 1 end
              if collected >= #DERBY.roster then resolve_round() end
            end)
          end
        end
      else
        ui_text(name)
      end
    end
    ui_separator()
  end

  -- TRACK
  if DERBY.horses and next(DERBY.horses) then
    for i = 1, DERBY.total_horses do
      local h = DERBY.horses[i]
      local id_str = string.format("[%2d] ", i)
      if h.scratched then
        ui_text_colored(id_str .. "--- SCRATCHED ---", 0.6, 0.6, 0.6, 1.0)
      else
        local track = ""
        for s = 1, DERBY.track_len do track = track .. (h.pos == s and "> " or ". ") end
        local owners = #h.owners > 0 and (" (" .. table.concat(h.owners, ",") .. ")") or ""
        ui_text(id_str .. (h.pos == 0 and "> " or "  ") .. track .. "| FINISH" .. owners)
      end
    end
  end
end
