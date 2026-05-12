if CR == nil then
  CR = {
    phase = "idle",
    info = "Generate a field to begin.",

    full_pool = {},
    field = {},
    bets = {},
    dealer_pick_player = "",

    race_start_ms = 0,
    race_duration_ms = 30000,
    commentary_interval_ms = 5000,
    last_segment = 0,
    last_leader_id = nil,
    track_max_progress = 1,

    chat_templates = {
      bet = "<player> backs #<total> (<result>) for <bet>.",
      race_start = "And they're OFF! 30 seconds to glory!",
      segment = "<result>",
      finish = "Finish! Winner: #<total> <player>.",
      payout = "<player> <result>. Bet <bet>. Bank <bank>.",
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
  local t = CR.chat_templates or {}
  local template = t[key]
  if template == nil or template == "" then return end
  table_announce(fmt(template, ctx))
end

local function seed_once()
  if CR._seeded then return end
  local seed = 12345
  if time_ms ~= nil then seed = tonumber(time_ms()) or seed end
  math.randomseed(seed)
  CR._seeded = true
end

local prefixes = { "Gilded", "Storm", "Ivory", "Cinder", "Velvet", "Dawn" }
local suffixes = { "Gale", "Feather", "Comet", "Talon", "Sprint", "Drifter" }

local first_names = {
  "Aether", "Amber", "Arc", "Ash", "Azure", "Blaze", "Bramble", "Brass", "Breeze", "Cinder",
  "Cloud", "Comet", "Copper", "Coral", "Crimson", "Dawn", "Dusk", "Echo", "Ember", "Fable",
  "Frost", "Gale", "Glimmer", "Gold", "Hazel", "Indigo", "Ivory", "Jade", "Jet", "Juniper",
  "Lapis", "Lilac", "Lumen", "Marble", "Mica", "Mistral", "Nimbus", "Nova", "Onyx", "Opal",
  "Pine", "Plume", "Quartz", "Raven", "River", "Ruby", "Sable", "Saffron", "Satin", "Scarlet",
  "Shadow", "Silver", "Solar", "Spark", "Star", "Storm", "Sunset", "Thorn", "Velvet", "Whisper"
}

local last_names = {
  "Arrow", "Banner", "Beat", "Blitz", "Bloom", "Bolt", "Bound", "Burst", "Cadence", "Chaser",
  "Circuit", "Claw", "Comet", "Crest", "Crown", "Dash", "Drift", "Ember", "Feather", "Flash",
  "Flare", "Flight", "Gale", "Glider", "Groove", "Heart", "Hoof", "Jet", "Lancer", "Leap",
  "Light", "March", "Mirage", "Needle", "Nova", "Pace", "Pulse", "Quill", "Racer", "Ridge",
  "Rush", "Saber", "Shade", "Shine", "Skipper", "Spark", "Sprint", "Stride", "Surge", "Talon",
  "Tempo", "Thunder", "Trail", "Twist", "Vortex", "Wave", "Whirl", "Wing", "Wisp", "Zephyr"
}

local style_tags = {
  "loves the rail", "floats wide on corners", "hunts late speed", "jumps out fast", "keeps a cool rhythm",
  "likes clean lanes", "thrives in traffic", "wears down the pack", "waits for one huge move", "keeps steady cadence",
  "breaks hot", "fades then rallies", "locks in behind leaders", "presses the pace", "saves energy early",
  "turns hard and clean", "likes outside lanes", "powers through clutter", "finds a second wind", "responds to crowd noise"
}

local leader_lines = {
  "<A> bursts ahead as <B> digs in behind.",
  "<A> owns the straight while <B> stalks from just off the shoulder.",
  "<A> snatches the lead by a beak over <B>.",
  "<A> controls the tempo; <B> refuses to blink.",
  "<A> swings clear and <B> answers instantly.",
  "<A> takes command with <B> in relentless pursuit.",
  "<A> steals a length and <B> keeps it honest.",
  "<A> runs sharp lines while <B> edges closer.",
  "<A> turns on pace and <B> mirrors every stride.",
  "<A> glides to the front as <B> prowls the gap.",
  "<A> leads the charge; <B> is right there waiting.",
  "<A> grabs daylight, but <B> won’t let it breathe."
}

local pack_lines = {
  "<C> and <D> are trading paint in the middle pack.",
  "<C> muscles through traffic while <D> skirts the outside.",
  "<C> tries the inside seam; <D> answers with a wider arc.",
  "<C> finds room, and <D> follows through the gap.",
  "<C> shakes loose; <D> gets boxed for a heartbeat.",
  "<C> and <D> are stride-for-stride through the turn.",
  "<C> surges up a lane while <D> claws back.",
  "<C> bumps into pressure; <D> slides past cleanly.",
  "<C> holds center track and <D> probes the rail.",
  "<C> gets a clean step; <D> rallies right back.",
  "<C> commits early and <D> counters late.",
  "<C> and <D> are locked in a private duel."
}

local trailer_lines = {
  "<E> is searching for daylight, and <F> refuses to fade.",
  "<E> is still in touch; <F> gathers for a late push.",
  "<E> shakes off a stumble while <F> claws up ground.",
  "<E> drifts back a step, but <F> is coming alive.",
  "<E> keeps contact as <F> starts to roll.",
  "<E> is boxed in; <F> finds a lane outside.",
  "<E> loses a beat and <F> snaps to attention.",
  "<E> resets posture while <F> gathers momentum.",
  "<E> is not done yet, and <F> is suddenly dangerous.",
  "<E> hangs tough while <F> takes a gamble wide.",
  "<E> drifts and recovers; <F> slips through inside.",
  "<E> keeps chasing with <F> right on that wake."
}

local finale_lines = {
  "Final bend! <A> and <B> are all-out now!",
  "The last corner snaps tight—<A> barely holds <B> off!",
  "Wire in sight! <A> fights to keep <B> behind!",
  "It’s chaos at the front: <A> vs <B> in a dead sprint!",
  "The crowd erupts as <A> and <B> rip down the lane!",
  "No room for mistakes—<A> and <B> are neck-and-neck!",
  "Everything left on the track: <A> and <B> unleash!",
  "Here comes the final drive—<A> and <B> refuse to yield!",
  "Last strides! <A> leans in and <B> answers immediately!",
  "The finish is looming and <A> just inches over <B>!",
  "Pure sprint now: <A> and <B> tear toward the wire!",
  "Late drama! <A> and <B> are separated by feathers!"
}

local function pick(list)
  return list[math.random(1, #list)]
end

local function shuffle(list)
  if list == nil then return end
  for i = #list, 2, -1 do
    local j = math.random(1, i)
    list[i], list[j] = list[j], list[i]
  end
end

local function fill_tokens(line, racers)
  local out = line
  out = string.gsub(out, "<A>", racers[1].name)
  out = string.gsub(out, "<B>", racers[2].name)
  out = string.gsub(out, "<C>", racers[3].name)
  out = string.gsub(out, "<D>", racers[4].name)
  out = string.gsub(out, "<E>", racers[5].name)
  out = string.gsub(out, "<F>", racers[6].name)
  return out
end

local function odds_text(r)
  return tostring(r.odds_to_one or 1) .. ":1"
end

local function sort_by_progress_desc(a, b)
  local ap = (a and tonumber(a.progress)) or 0
  local bp = (b and tonumber(b.progress)) or 0
  if ap ~= bp then
    return ap > bp
  end

  local aid = (a and tonumber(a.id)) or 0
  local bid = (b and tonumber(b.id)) or 0
  return aid < bid
end

local lead_change_lines = {
  "<new> storms past <old> to take the lead!",
  "Lead change! <new> slips in front of <old>!",
  "<new> finds another gear and clears <old>!",
  "<new> steals the front from <old>!",
  "<new> edges by <old> and now sets the pace!",
  "Big move from <new> — past <old> for first!",
}

local function lead_change_text(newLeader, oldLeader)
  if newLeader == nil then return "" end
  if oldLeader == nil then return "" end
  local t = pick(lead_change_lines)
  t = string.gsub(t, "<new>", newLeader.name or "")
  t = string.gsub(t, "<old>", oldLeader.name or "")
  return t
end

local function build_track_line(sortedDesc)
  local width = 75
  local chars = {}
  for i = 1, width do chars[i] = "-" end

  local maxP = math.max(1, tonumber(CR.track_max_progress) or 1)

  local asc = {}
  for i = #sortedDesc, 1, -1 do
    asc[#asc + 1] = sortedDesc[i]
  end

  for i = 1, #asc do
    local r = asc[i]
    local ratio = (r.progress or 0) / maxP
    if ratio < 0 then ratio = 0 end
    if ratio > 1 then ratio = 1 end

    local pos = 1 + math.floor(ratio * (width - 1))
    if pos < 1 then pos = 1 end
    if pos > width then pos = width end

    local mark = tostring(r.number or "?")
    if chars[pos] ~= "-" then
      if pos < width and chars[pos + 1] == "-" then
        pos = pos + 1
      elseif pos > 1 and chars[pos - 1] == "-" then
        pos = pos - 1
      end
    end

    chars[pos] = mark
  end

  return table.concat(chars, "")
end

local function build_full_pool()
  seed_once()
  CR.full_pool = {}

  local used = {}
  local id = 1
  while #CR.full_pool < 36 do
    local name = first_names[math.random(1, #first_names)] .. " " .. last_names[math.random(1, #last_names)]
    if not used[name] then
      used[name] = true

      local surge = math.random(2, 6)
      local slow = math.random(2, 6)
      while slow == surge do slow = math.random(2, 6) end

      table.insert(CR.full_pool, {
        id = id,
        name = name,
        style_tag = pick(style_tags),
        speed = math.random(55, 100),
        endurance = math.random(50, 100),
        burst = math.random(8, 25),
        tempo = math.random(5, 20),
        surge_segment = surge,
        slow_segment = slow,
      })
      id = id + 1
    end
  end
end

local function precompute_field_segments()
  local max_total = 1
  for i = 1, #CR.field do
    local r = CR.field[i]
    r.progress = 0
    r.segment_gain = {}

    local total = 0
    for seg = 1, 6 do
      local t = (seg - 1) / 5.0
      local pace = (r.speed * (1.0 - t)) + (r.endurance * t)
      local gain = (pace * 0.55) + math.random(10, 24)

      if seg == r.surge_segment then
        gain = gain + r.burst + math.random(8, 18)
      end

      if seg == r.slow_segment then
        gain = gain - math.random(10, 22) + math.floor(r.tempo / 3)
      end

      if gain < 6 then gain = 6 end
      r.segment_gain[seg] = gain
      total = total + gain
    end

    if total > max_total then max_total = total end
  end

  CR.track_max_progress = max_total
end

local function generate_field()
  build_full_pool()
  local tmp = {}
  for i = 1, #CR.full_pool do
    tmp[i] = CR.full_pool[i]
  end

  shuffle(tmp)
  CR.field = {}
  for i = 1, 6 do
    local src = tmp[i]
    CR.field[i] = {
      number = i,
      id = src.id,
      name = src.name,
      style_tag = src.style_tag,
      speed = src.speed,
      endurance = src.endurance,
      burst = src.burst,
      tempo = src.tempo,
      surge_segment = src.surge_segment,
      slow_segment = src.slow_segment,
      odds_to_one = 1,
      progress = 0,
      segment_gain = {},
    }
  end

  local odds_pool = { 2, 3, 4, 5, 6, 7, 8, 9, 10, 12, 14, 16 }
  shuffle(odds_pool)
  for i = 1, #CR.field do
    CR.field[i].odds_to_one = odds_pool[i]
  end

  precompute_field_segments()
  CR.phase = "idle"
  CR.bets = {}
  CR.last_segment = 0
  CR.info = "Field generated. Open betting when ready."
end

local function announce_betting_board()
  table_announce("Betting is now OPEN.")
  for i = 1, #CR.field do
    local r = CR.field[i]
    table_announce("#" .. tostring(r.number) .. " " .. r.name .. " | Odds " .. odds_text(r) .. " | " .. (r.style_tag or ""))
  end
end

local function find_racer_by_number(num)
  for i = 1, #CR.field do
    if CR.field[i].number == num then
      return CR.field[i]
    end
  end
  return nil
end

local function normalize_text(s)
  return string.lower(((s or ""):gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " ")))
end

local function find_racer_by_name(name_text)
  local q = normalize_text(name_text)
  if q == "" then return nil end

  local partial = nil
  for i = 1, #CR.field do
    local r = CR.field[i]
    local n = normalize_text(r.name)
    if n == q then return r end
    if string.find(n, q, 1, true) ~= nil then
      if partial ~= nil then
        return nil
      end
      partial = r
    end
  end

  return partial
end

local function extract_bet(message)
  local m = normalize_text(message)
  if m == "" then return nil, nil end

  if string.sub(m, 1, 6) == "[race]" then return nil, nil end

  local amountText, targetText = string.match(m, "^bet%s+(%d+)%s+on%s+(.+)$")
  if amountText == nil then
    amountText, targetText = string.match(m, "^bet%s+(%d+)%s+(.+)$")
  end
  if amountText == nil or targetText == nil then return nil, nil end

  local amount = tonumber(amountText)
  if amount == nil or amount <= 0 then return nil, nil end

  local pick = tonumber(targetText)
  if pick ~= nil then
    if pick >= 1 and pick <= 6 then
      return amount, pick
    end
    return nil, nil
  end

  local racer = find_racer_by_name(targetText)
  if racer == nil then return nil, nil end
  return amount, racer.number
end

local function place_bet_for_player(name, pick, amount)
  if name == nil or name == "" then return false end
  if pick == nil or pick < 1 or pick > 6 then return false end
  if not dealer_is_eligible(name) then return false end

  local racer = find_racer_by_number(pick)
  if racer == nil then return false end

  if amount ~= nil and amount > 0 then
    dealer_set_wager(name, amount)
  end

  local wager = dealer_get_wager(name)
  CR.bets[name] = pick
  announce("bet", {
    player = name,
    total = pick,
    result = racer.name,
    bet = wager,
  })
  CR.info = name .. " backs #" .. tostring(pick) .. " for " .. tostring(wager) .. "."
  return true
end

local function process_chat_bets()
  if chat_poll == nil then return end
  if CR.phase ~= "betting" then return end

  for _ = 1, 16 do
    local packet = chat_poll()
    if packet == nil or packet == "" then break end

    local name, world, channel, message = string.match(packet, "^([^|]*)|([^|]*)|([^|]*)|(.*)$")
    if name ~= nil and message ~= nil and dealer_is_eligible(name) then
      local amount, pick = extract_bet(message)
      if pick ~= nil then
        place_bet_for_player(name, pick, amount)
      end
    end
  end
end

local function open_betting()
  if #CR.field ~= 6 then
    generate_field()
  end

  CR.phase = "betting"
  CR.bets = {}
  CR.info = "Betting open. Players may type 'bet #'."
  announce_betting_board()
end

local function start_race()
  if #CR.field ~= 6 then
    generate_field()
  end

  if CR.phase ~= "betting" and CR.phase ~= "idle" and CR.phase ~= "finished" then
    return
  end

  for i = 1, #CR.field do
    CR.field[i].progress = 0
  end

  CR.race_start_ms = (time_ms ~= nil) and time_ms() or 0
  CR.last_segment = 0
  CR.last_leader_id = nil
  CR.phase = "racing"
  CR.info = "Race underway!"
  announce("race_start", {})
end

local function apply_segment(seg)
  for i = 1, #CR.field do
    local r = CR.field[i]
    r.progress = (r.progress or 0) + (r.segment_gain[seg] or 0)
  end
end

local position_tones = {
  [1] = {
    "out front", "setting the pace", "in command", "at the head of the field", "showing the way"
  },
  [2] = {
    "in pursuit", "right on the leader", "pressing the front", "shadowing the lead", "keeping pressure on"
  },
  [3] = {
    "upper-mid pack", "just behind the front pair", "in striking range", "holding third lane", "tracking the leaders"
  },
  [4] = {
    "mid pack", "in the thick of it", "in traffic", "holding center field", "boxed in the middle"
  },
  [5] = {
    "rear pack", "near the back", "chasing from behind", "trying to close late", "working from the tail"
  },
  [6] = {
    "on the tail end", "bringing up the rear", "off the back marker", "last but still moving", "anchoring the field"
  },
}

local function place_tone(place)
  local tones = position_tones[place] or position_tones[6]
  return pick(tones)
end

local function segment_commentary(seg)
  local racers = {}
  for i = 1, #CR.field do racers[i] = CR.field[i] end
  table.sort(racers, sort_by_progress_desc)

  local pairs = {
    { 3, 4 },
    { 4, 5 },
    { 3, 5 },
    { 5, 6 },
  }
  local pair = pairs[((seg - 1) % #pairs) + 1]

  local p1 = racers[1]
  local p2 = racers[2]
  local pA = racers[pair[1]]
  local pB = racers[pair[2]]

  local race_flavor = {
    "The pace stays hot through the lane.",
    "The pack compresses into the turn.",
    "Momentum shifts across the middle.",
    "Every stride is costing more now.",
    "The tempo spikes heading into the bend.",
    "Pressure builds all across the field.",
  }

  local line =
    p1.name .. " " .. place_tone(1) .. ", " .. p2.name .. " " .. place_tone(2) .. ". "
    .. pA.name .. " " .. place_tone(pair[1]) .. ", " .. pB.name .. " " .. place_tone(pair[2]) .. ". "
    .. pick(race_flavor)

  local oldLeader = nil
  if CR.last_leader_id ~= nil then
    for i = 1, #racers do
      if racers[i].id == CR.last_leader_id then
        oldLeader = racers[i]
        break
      end
    end
  end

  if oldLeader ~= nil and oldLeader.id ~= p1.id then
    line = line .. " " .. lead_change_text(p1, oldLeader)
  end

  if seg >= 6 then
    line = line .. " Final stretch—no room for mistakes."
  elseif seg == 3 then
    line = line .. " Midpoint and the order is still volatile."
  end

  CR.last_leader_id = p1.id
  announce("segment", { result = line })
  table_announce(build_track_line(racers))
end

local function finish_race()
  local racers = {}
  for i = 1, #CR.field do racers[i] = CR.field[i] end
  table.sort(racers, sort_by_progress_desc)

  local winner = racers[1]
  announce("finish", { total = winner.number, player = winner.name })

  if next(CR.bets) ~= nil then
    for name, pickNum in pairs(CR.bets) do
      local wager = dealer_get_wager(name)
      if wager < 0 then wager = 0 end

      local picked = find_racer_by_number(pickNum)
      local odds = (picked ~= nil and picked.odds_to_one) or 1

      local win = pickNum == winner.number
      local delta = win and (wager * odds) or -wager
      dealer_add_bank(name, delta)

      announce("payout", {
        player = name,
        result = win and ("wins on #" .. tostring(pickNum) .. " at " .. tostring(odds) .. ":1") or ("loses on #" .. tostring(pickNum)),
        bet = wager,
        bank = dealer_get_bank(name),
      })
    end
  else
    table_announce("No bets were placed this race.")
  end

  CR.phase = "finished"
  CR.info = "Race complete. Winner: #" .. tostring(winner.number) .. " " .. winner.name
end

local function process_race_tick()
  if CR.phase ~= "racing" then return end

  local now = (time_ms ~= nil) and time_ms() or 0
  local elapsed = math.max(0, now - (CR.race_start_ms or 0))
  local segment = math.floor(elapsed / CR.commentary_interval_ms)
  if segment > 6 then segment = 6 end

  while CR.last_segment < segment do
    CR.last_segment = CR.last_segment + 1
    apply_segment(CR.last_segment)
    segment_commentary(CR.last_segment)
  end

  if elapsed >= CR.race_duration_ms then
    finish_race()
  end
end

function draw_config_ui()
  ui_text_colored("Chocobo Racing Config", 0.8, 0.95, 0.8, 1.0)
  ui_separator()
  ui_text("Race duration: 30 seconds")
  ui_text("Commentary interval: every 5 seconds")
  ui_text("Field size: 6 racers from a generated pool of 36")
end

function draw_ui()
  if #CR.field ~= 6 then
    generate_field()
  end

  process_chat_bets()
  process_race_tick()

  ui_text_colored("Chocobo Racing", 1.0, 0.9, 0.4, 1.0)
  ui_separator()

  if ui_button("Generate Field") then generate_field() end
  ui_same_line()
  if ui_button("Open Betting") then open_betting() end
  ui_same_line()
  if ui_button("Start Race") then start_race() end

  ui_text("Status: " .. tostring(CR.phase) .. " | " .. tostring(CR.info))

  local remaining = 0
  if CR.phase == "racing" then
    local now = (time_ms ~= nil) and time_ms() or 0
    remaining = math.max(0, CR.race_duration_ms - (now - (CR.race_start_ms or 0)))
  end
  ui_text("Time left: " .. tostring(math.floor(remaining / 1000)) .. "s")

  ui_separator()
  ui_text_colored("Today's Racers", 0.9, 0.95, 1.0, 1.0)

  for i = 1, #CR.field do
    local r = CR.field[i]
    ui_text(
      "#" .. tostring(r.number) .. " " .. r.name
      .. " | Odds " .. odds_text(r)
      .. " | SPD " .. tostring(r.speed)
      .. " END " .. tostring(r.endurance)
      .. " BRS " .. tostring(r.burst)
      .. " TMP " .. tostring(r.tempo)
      .. " | " .. tostring(r.style_tag or "")
      .. " | Dist " .. string.format("%.1f", r.progress or 0)
    )
  end

  if CR.phase == "betting" then
    ui_separator()
    ui_text_colored("Dealer Bet Controls", 1.0, 0.95, 0.7, 1.0)

    local candidates = {}
    local count = dealer_player_count()
    for i = 1, count do
      local name = dealer_player_name(i)
      if name ~= nil and name ~= "" and dealer_is_eligible(name) then
        table.insert(candidates, name)
      end
    end

    if #candidates > 0 then
      local selected = CR.dealer_pick_player or ""
      local found = false
      for i = 1, #candidates do
        if candidates[i] == selected then found = true break end
      end
      if not found then
        selected = candidates[1]
        CR.dealer_pick_player = selected
      end

      ui_text("Selected player: " .. selected)
      for i = 1, #candidates do
        local name = candidates[i]
        if ui_button("Pick " .. name .. "##pick_" .. name) then
          CR.dealer_pick_player = name
        end
        if i < #candidates then ui_same_line() end
      end

      for i = 1, 6 do
        if ui_button("Bet #" .. tostring(i) .. "##dealer_bet_" .. tostring(i)) then
          place_bet_for_player(CR.dealer_pick_player, i)
        end
        if i < 6 then ui_same_line() end
      end
    else
      ui_text("No eligible players in dealer roster.")
    end
  end

  ui_separator()
  ui_text_colored("Bets", 1.0, 1.0, 0.8, 1.0)

  local hasBets = false
  for name, pick in pairs(CR.bets) do
    hasBets = true
    local r = find_racer_by_number(pick)
    local racerName = (r ~= nil) and r.name or ("#" .. tostring(pick))
    local odds = (r ~= nil) and odds_text(r) or "?"
    ui_text(name .. " -> #" .. tostring(pick) .. " " .. racerName .. " (" .. odds .. ", wager " .. tostring(dealer_get_wager(name)) .. ")")
  end

  if not hasBets then
    ui_text("(no bets yet)")
  end
end
