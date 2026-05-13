if BINGO == nil then
  BINGO = {
    phase = "idle",
    info = "Set card counts, then click New Round.",

    room_words = { "alpha", "bravo", "charlie" },
    room_name = "",

    players = {},
    cards = {},
    player_seed = {},
    player_codes = {},
    cards_bought = {},
    winners = {},
    winner_lookup = {},
    claimable_lookup = {},

    mode = "single", -- single | progressive
    single_condition = "1_line",
    progressive_playlist = { "1_line", "2_line", "4_corners", "blackout" },
    progressive_round_index = 1,
    progressive_results = {},
    progressive_carryover_enabled = false,
    progressive_carryover_percent = 20,

    pot_size = 100000,
    suggested_payouts = {},

    call_sequence = {},
    cipher_words = {},
    catchup_requests = {},
    catchup_limit_per_player = 1,
    called_lookup = {},
    call_history = {},
    next_call_index = 1,

    selected_player = 1,
    selected_card = 1,

    condition_picker_single = 1,
    condition_picker_progressive = 1,

    web_base_url = "https://a325245.github.io/WebBingo/",

    chat_templates = {
      start = "Bingo round started for <total> players.",
      room = "Bingo room seed: <result>",
      call = "<result>",
      winner = "BINGO! <player> wins.",
      links_sent = "Bingo links sent by tell: <total>",
      catchup = "Catchup sent to <player>.", -- Fixed: No longer broadcasts the code publicly
    }
  }
end

local WORDS = { "abandon","ability","able","about","above","absent","absorb","abstract","absurd","abuse","access","accident","account","accuse","achieve","acid","acoustic","acquire","across","act","action","actor","actress","actual","adapt","add","addict","address","adjust","admit","adult","advance","advice","aerobic","affair","afford","afraid","again","age","agent","agree","ahead","aim","air","airport","aisle","alarm","album","alcohol","alert","alien","all","alley","allow","almost","alone","alpha","already","also","alter","always","amateur","amazing","among","amount","amused","analyst","anchor","ancient","anger","angle","angry","animal","ankle","announce","annual","another","answer","antenna","antique","anxiety","any","apart","apology","appear","apple","approve","april","arch","arctic","area","arena","argue","arm","armed","armor","army","around","arrange","arrest","arrive","arrow","art","artefact","artist","artwork","ask","aspect","assault","asset","assist","assume","asthma","athlete","atom","attack","attend","attitude","attract","auction","audit","august","aunt","author","auto","autumn","average","avocado","avoid","awake","aware","away","awesome","awful","awkward","axis","baby","bachelor","bacon","badge","bag","balance","balcony","ball","bamboo","banana","banner","bar","barely","bargain","barrel","base","basic","basket","battle","beach","bean","beauty","because","become","beef","before","begin","behave","behind","believe","below","belt","bench","benefit","best","betray","better","between","beyond","bicycle","bid","bike","bind","biology","bird","birth","bitter","black","blade","blame","blanket","blast","bleak","bless","blind","blood","blossom","blouse","blue","blur","blush","board","boat","body","boil","bomb","bone","bonus","book","boost","border","boring","borrow","boss","bottom","bounce","box","boy","bracket","brain","brand","brass","brave","bread","breeze","brick","bridge","brief","bright","bring","brisk","broccoli","broken","bronze","broom","brother","brown","brush","bubble","buddy","budget","buffalo","build","bulb","bulk","bullet","bundle","bunker","burden","burger","burst","bus","business","busy","butter","buyer","buzz","cabbage","cabin","cable","cactus","cage","cake","call","calm","camera","camp","can","canal","cancel","candy","cannon","canoe","canvas","canyon","capable","capital","captain","car","carbon","card","cargo","carpet","carry","cart","case","cash","casino","castle","casual","cat","catalog","catch","category","cattle","caught","cause","caution","cave","ceiling","celery","cement","census","century","cereal","certain","chair","chalk","champion","change","chaos","chapter","charge","chase","chat","cheap","check","cheese","chef","cherry","chest","chicken","chief","child","chimney","choice","choose","chronic","chuckle","chunk","churn","cigar","cinnamon","circle","citizen","city","civil","claim","clap","clarify","claw","clay","clean","clerk","clever","click","client","cliff","climb","clinic","clip","clock","clog","close","cloth","cloud","clown","club","clump","cluster","clutch","coach","coast","coconut","code","coffee","coil","coin","collect","color","column","combine","come","comfort","comic","common","company","concert","conduct","confirm","congress","connect","consider","control","convince","cook","cool","copper","copy","coral","core","corn","correct","cost","cotton","couch","country","couple","course","cousin","cover","coyote","crack","cradle","craft","cram","crane","crash","crater","crawl","crazy","cream","credit","creek","crew","cricket","crime","crisp","critic","crop","cross","crouch","crowd","crucial","cruel","cruise","crumble","crunch","crush","cry","crystal","cube","culture","cup","cupboard","curious","current","curtain","curve","cushion","custom","cute","cycle","dad","damage","damp","dance","danger","daring","dash","daughter","dawn","day","deal","debate","debris","decade","december","decide","decline","decorate","decrease","deer","defense","define","defy","degree","delay","deliver","demand","demise","denial","dentist","deny","depart","depend","deposit","depth","deputy","derive","describe","desert","design","desk","despair","destroy","detail","detect","develop","device","devote","diagram","dial","diamond","diary","dice","diesel","diet","differ","digital","dignity","dilemma","dinner","dinosaur","direct","dirt","disagree","discover","disease","dish","dismiss","disorder","display","distance","divert","divide","divorce","dizzy","doctor","document","dog","doll","dolphin","domain","donate","donkey","donor","door","dose","double","dove","draft","dragon","drama","drastic","draw","dream","dress","drift","drill","drink","drip","drive","drop","drum","dry","duck","dumb","dune","during","dust","dutch","duty","dwarf","dynamic","eager","eagle","early","earn","earth","easily","east","easy","echo","ecology","economy","edge","edit","educate","effort","egg","eight","either","elbow","elder","electric","elegant","element","elephant","elevator","elite","else","embark","embody","embrace","emerge","emotion","employ","empower","empty","enable","enact","end","endless","endorse","enemy","energy","enforce","engage","engine","enhance","enjoy","enlist","enough","enrich","enroll","ensure","enter","entire","entry","envelope","episode","equal","equip","era","erase","erode","erosion","error","erupt","escape","essay","essence","estate","eternal","ethics","evidence","evil","evoke","evolve","exact","example","excess","exchange","excite","exclude","excuse","execute","exercise","exhaust","exhibit","exile","exist","exit","exotic","expand","expect","expire","explain","expose","express","extend","extra","eye","eyebrow","fabric","face","faculty","fade","faint","faith","fall","false","fame","family","famous","fan","fancy","fantasy","farm","fashion","fat","fatal","father","fatigue","fault","favorite","feature","february","federal","fee","feed","feel","female","fence","festival","fetch","fever","few","fiber","fiction","field","figure","file","film","filter","final","find","fine","finger","finish","fire","firm","first","fiscal","fish","fit","fitness","fix","flag","flame","flash","flat","flavor","flee","flight","flip","float","flock","floor","flower","fluid","flush","fly","foam","focus","fog","foil","fold","follow","food","foot","force","forest","forget","fork","fortune","forum","forward","fossil","foster","found","fox","fragile","frame","frequent","fresh","friend","fringe","frog","front","frost","frown","frozen","fruit","fuel","fun","funny","furnace","fury","future","gadget","gain","galaxy","gallery","game","gap","garage","garbage","garden","garlic","garment","gas","gasp","gate","gather","gauge","gaze","general","genius","genre","gentle","genuine","gesture","ghost","giant","gift","giggle","ginger","giraffe","girl","give","glad","glance","glare","glass","glide","glimpse","globe","gloom","glory","glove","glow","glue","goat","goddess","gold","good","goose","gorilla","gospel","gossip","govern","gown","grab","grace","grain","grant","grape","grass","gravity","great","green","grid","grief","grit","grocery","group","grow","grunt","guard","guess","guide","guilt","guitar","gun","gym","habit","hair","half","hammer","hamster","hand","happy","harbor","hard","harsh","harvest","hat","have","hawk","hazard","head","health","heart","heavy","hedgehog","height","hello","helmet","help","hen","hero","hidden","high","hill","hint","hip","hire","history","hobby","hockey","hold","hole","holiday","hollow","home","honey","hood","hope","horn","horror","horse","hospital","host","hotel","hour","hover","hub","huge","human","humble","humor","hundred","hungry","hunt","hurdle","hurry","hurt","husband","hybrid","ice","icon","idea","identify","idle","ignore","ill","illegal","illness","image","imitate","immense","immune","impact","impose","improve","impulse","inch","include","income","increase","index","indicate","indoor","industry","infant","inflict","inform","inhale","inherit","initial","inject","injury","inmate","inner","innocent","input","inquiry","insane","insect","inside","inspire","install","intact","interest","into","invest","invite","involve","iron","island","isolate","issue","item","ivory","jacket","jaguar","jar","jazz","jealous","jeans","jelly","jewel","job","join","joke","journey","joy","judge","juice","jump","jungle","junior","junk","just","kangaroo","keen","keep","ketchup","key","kick","kid","kidney","kind","kingdom","kiss","kit","kitchen","kite","kitten","kiwi","knee","knife","knock","know","lab","label","labor","ladder","lady","lake","lamp","language","laptop","large","later","latin","laugh","laundry","lava","law","lawn","lawsuit","layer","lazy","leader","leaf","learn","leave","lecture","left","leg","legal","legend","leisure","lemon","lend","length","lens","leopard","lesson","letter","level","liar","liberty","library","license","life","lift","light","like","limb","limit","link","lion","liquid","list","little","live","lizard","load","loan","lobster","local","lock","logic","lonely","long","loop","lottery","loud","lounge","love","loyal","lucky","luggage","lumber","lunar","lunch","luxury","lyrics","machine","mad","magic","magnet","maid","mail","main","major","make","mammal","man","manage","mandate","mango","mansion","manual","maple","marble","march","margin","marine","market","marriage","mask","mass","master","match","material","math","matrix","matter","maximum","maze","meadow","mean","measure","meat","mechanic","medal","media","melody","melt","member","memory","mention","menu","mercy","merge","merit","merry","mesh","message","metal","method","middle","midnight","milk","million","mimic","mind","minimum","minor","minute","miracle","mirror","misery","miss","mistake","mix","mixed","mixture","mobile","model","modify","mom","moment","monitor","monkey","monster","month","moon","moral","more","morning","mosquito","mother","motion","motor","mountain","mouse","move","movie","much","muffin","mule","multiply","muscle","museum","mushroom","music","must","mutual","myself","mystery","myth","naive","name","napkin","narrow","nasty","nation","nature","near","neck","need","negative","neglect","neither","nephew","nerve","nest","net","network","neutral","never","news","next","nice","night","noble","noise","nominee","noodle","normal","north","nose","notable","note","nothing","notice","novel","now","nuclear","number","nurse","nut","oak","obey","object","oblige","obscure","observe","obtain","obvious","occur","ocean","october","odor","off","offer","office","often","oil","okay","old","olive","olympic","omit","once","one","onion","online","only","open","opera","opinion","oppose","option","orange","orbit","orchard","order","ordinary","organ","orient","original","orphan","ostrich","other","outdoor","outer","output","outside","oval","oven","over","own","owner","oxygen","oyster","ozone","pact","paddle","page","pair","palace","palm","panda","panel","panic","panther","paper","parade","parent","park","parrot","party","pass","patch","path","patient","patrol","pattern","pause","pave","payment","peace","peanut","pear","peasant","pelican","pen","penalty","pencil","people","pepper","perfect","permit","person","pet","phone","photo","phrase","physical","piano","picnic","picture","piece","pig","pigeon","pill","pilot","pink","pioneer","pipe","pistol","pitch","pizza","place","planet","plastic","plate","play","please","pledge","pluck","plug","plunge","poem","poet","point","polar","pole","police","pond","pony","pool","popular","portion","position","possible","post","potato","pottery","poverty","powder","power","practice","praise","predict","prefer","prepare","present","pretty","prevent","price","pride","primary","print","priority","prison","private","prize","problem","process","produce","profit","program","project","promote","proof","property","prosper","protect","proud","provide","public","pudding","pull","pulp","pulse","pumpkin","punch","pupil","puppy","purchase","purity","purpose","purse","push","put","puzzle","pyramid","quality","quantum","quarter","question","quick","quit","quiz","quote","rabbit","raccoon","race","rack","radar","radio","rail","rain","raise","rally","ramp","ranch","random","range","rapid","rare","rate","rather","raven","raw","razor","ready","real","reason","rebel","rebuild","recall","receive","recipe","record","recycle","reduce","reflect","reform","refuse","region","regret","regular","reject","relax","release","relief","rely","remain","remember","remind","remove","render","renew","rent","reopen","repair","repeat","replace","report","require","rescue","resemble","resist","resource","response","result","retire","retreat","return","reunion","reveal","review","reward","rhythm","rib","ribbon","rice","rich","ride","ridge","rifle","right","rigid","ring","riot","ripple","risk","ritual","rival","river","road","roast","robot","robust","rocket","romance","roof","rookie","room","rose","rotate","rough","round","route","royal","rubber","rude","rug","rule","run","runway","rural","sad","saddle","sadness","safe","sail","salad","salmon","salon","salt","salute","same","sample","sand","satisfy","satoshi","sauce","sausage","save","say","scale","scan","scare","scatter","scene","scheme","school","science","scissors","scorpion","scout","scrap","screen","script","scrub","sea","search","season","seat","second","secret","section","security","seed","seek","segment","select","sell","seminar","senior","sense","sentence","series","service","session","settle","setup","seven","shadow","shaft","shallow","share","shed","shell","sheriff","shield","shift","shine","ship","shiver","shock","shoe","shoot","shop","short","shoulder","shove","shrimp","shrug","shuffle","shy","sibling","sick","side","siege","sight","sign","silent","silk","silly","silver","similar","simple","since","sing","siren","sister","situate","six","size","skate","sketch","ski","skill","skin","skirt","skull","slab","slam","sleep","slender","slice","slide","slight","slim","slogan","slot","slow","slush","small","smart","smile","smoke","smooth","snack","snake","snap","sniff","snow","soap","soccer","social","sock","soda","soft","solar","soldier","solid","solution","solve","someone","song","soon","sorry","sort","soul","sound","soup","source","south","space","spare","spatial","spawn","speak","special","speed","spell","spend","sphere","spice","spider","spike","spin","spirit","split","spoil","sponsor","spoon","sport","spot","spray","spread","spring","spy","square","squeeze","squirrel","stable","stadium","staff","stage","stairs","stamp","stand","start","state","stay","steak","steel","stem","step","stereo","stick","still","sting","stock","stomach","stone","stool","story","stove","strategy","street","strike","strong","struggle","student","stuff","stumble","style","subject","submit","subway","success","such","sudden","suffer","sugar","suggest","suit","summer","sun","sunny","sunset","super","supply","supreme","sure","surface","surge","surprise","surround","survey","suspect","sustain","swallow","swamp","swap","swarm","swear","sweet","swift","swim","swing","switch","sword","symbol","symptom","syrup","system","table","tackle","tag","tail","talent","talk","tank","tape","target","task","taste","tattoo","taxi","teach","team","tell","ten","tenant","tennis","tent","term","test","text","thank","that","theme","then","theory","there","they","thing","this","thought","three","thrive","throw","thumb","thunder","ticket","tide","tiger","tilt","timber","time","tiny","tip","tired","tissue","title","toast","tobacco","today","toddler","toe","together","toilet","token","tomato","tomorrow","tone","tongue","tonight","tool","tooth","top","topic","topple","torch","tornado","tortoise","toss","total","tourist","toward","tower","town","toy","track","trade","traffic","tragic","train","transfer","trap","trash","travel","tray","treat","tree","trend","trial","tribe","trick","trigger","trim","trip","trophy","trouble","truck","true","truly","trumpet","trust","truth","try","tube","tuition","tumble","tuna","tunnel","turkey","turn","turtle","twelve","twenty","twice","twin","twist","two","type","typical","ugly","umbrella","unable","unaware","uncle","uncover","under","undo","unfair","unfold","unhappy","uniform","unique","unit","universe","unknown","unlock","until","unusual","unveil","update","upgrade","uphold","upon","upper","upset","urban","urge","usage","use","used","useful","useless","usual","utility","vacant","vacuum","vague","valid","valley","valve","van","vanish","vapor","various","vast","vault","vehicle","velvet","vendor","venture","venue","verb","verify","version","very","vessel","veteran","viable","vibrant","vicious","victory","video","view","village","vintage","violin","virtual","virus","visa","visit","visual","vital","vivid","vocal","voice","void","volcano","volume","vote","voyage","wage","wagon","wait","walk","wall","walnut","want","warfare","warm","warrior","wash","wasp","waste","water","wave","way","wealth","weapon","wear","weasel","weather","web","wedding","weekend","weird","welcome","west","wet","whale","what","wheat","wheel","when","where","whip","whisper","wide","width","wife","wild","will","win","window","wine","wing","wink","winner","winter","wire","wisdom","wise","wish","witness","wolf","woman","wonder","wood","wool","word","work","world","worry","worth","wrap","wreck","wrestle","wrist","write","wrong","yard","year","yellow","you","young","youth","zebra","zero","zone","zoo" }

local CONDITION_KEYS = { "1_line", "2_line", "4_corners", "inside_square", "outside_square", "blackout", "blitz_5" }
local assign_player_codes, build_cipher_words
local draw_mode_controls, draw_purchase_controls
local hash_string, create_prng

local function normalize_player_key(name)
  local n = string.lower(tostring(name or ""))
  n = string.gsub(n, "[^%w]+", "-")
  n = string.gsub(n, "%-+", "-")
  n = string.gsub(n, "^%-", "")
  n = string.gsub(n, "%-$", "")
  if n == "" then n = "player" end
  return n
end

local function room_seed_text()
  if BINGO.room_words == nil or #BINGO.room_words < 3 then return "" end
  return table.concat(BINGO.room_words, " ")
end

local function player_phrase(name)
  return room_seed_text()
end

assign_player_codes = function(players)
  BINGO.player_codes = {}
  
  -- Use the room seed to initialize the PRNG for stable unique generation
  local base = room_seed_text()
  local rng = create_prng(hash_string(base .. "-players"))
  local used_phrases = {}

  for i = 1, #players do
    local p = players[i]
    local unique_phrase = ""

    -- Keep generating until we find a 3-word combo that no one else has
    while unique_phrase == "" do
      local w1 = WORDS[math.floor(rng() * #WORDS) + 1]
      local w2 = WORDS[math.floor(rng() * #WORDS) + 1]
      local w3 = WORDS[math.floor(rng() * #WORDS) + 1]
      
      local candidate = w1 .. " " .. w2 .. " " .. w3

      if not used_phrases[candidate] then
        used_phrases[candidate] = true
        unique_phrase = candidate
      end
    end

    BINGO.player_codes[p] = unique_phrase
  end
end

build_cipher_words = function(roomName)
  -- Fixed: Removed "-cipher" to perfectly match the HTML math
  local rng = create_prng(hash_string(roomName))
  local result = {}
  local used = {}
  while #result < 75 do
    local idx = math.floor(rng() * #WORDS) + 1
    local w = WORDS[idx]
    if not used[w] then
      used[w] = true
      table.insert(result, w)
    end
  end
  return result
end

-- Safety stubs in case UI is invoked before full script initialization completes.
draw_mode_controls = function() end
draw_purchase_controls = function() end

local function log_info(msg)
  if log ~= nil then log("[Bingo] " .. tostring(msg or "")) end
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
  local msg = tostring(message or "")
  if msg == "" then return end

  if chat_send ~= nil then
    chat_send(output_channel_name(), msg)
  else
    dealer_party(msg)
  end
end

local function fmt(template, ctx)
  local msg = tostring(template or "")
  if chat_format ~= nil then
    return chat_format(
      msg,
      tostring((ctx and ctx.player) or ""),
      tonumber((ctx and ctx.bet) or 0) or 0,
      tonumber((ctx and ctx.bank) or 0) or 0,
      tostring((ctx and ctx.card) or ""),
      tonumber((ctx and ctx.total) or 0) or 0,
      tonumber((ctx and ctx.dealer_total) or 0) or 0,
      tostring((ctx and ctx.result) or "")
    )
  end

  local values = {
    ["<player>"] = tostring((ctx and ctx.player) or ""),
    ["<total>"] = tostring((ctx and ctx.total) or ""),
    ["<result>"] = tostring((ctx and ctx.result) or ""),
  }
  for token, value in pairs(values) do
    msg = string.gsub(msg, token, value)
  end
  return msg
end

local function announce(key, ctx)
  local t = BINGO.chat_templates or {}
  local template = t[key]
  if template == nil or template == "" then return end
  table_announce(fmt(template, ctx))
end

local function condition_label(key)
  if key == "1_line" then return "1 line" end
  if key == "2_line" then return "2 line" end
  if key == "4_corners" then return "4 corners" end
  if key == "inside_square" then return "inside square" end
  if key == "outside_square" then return "outside square" end
  if key == "blackout" then return "blackout" end
  if key == "blitz_5" then return "blitz (any 5)" end
  return tostring(key or "")
end

local function active_condition_key()
  if BINGO.mode == "progressive" then
    local idx = tonumber(BINGO.progressive_round_index) or 1
    if idx < 1 then idx = 1 end
    if idx > #BINGO.progressive_playlist then idx = #BINGO.progressive_playlist end
    return BINGO.progressive_playlist[idx]
  end
  return BINGO.single_condition
end

local function to_u32(x)
  return (tonumber(x) or 0) % 4294967296
end

local function to_i32(x)
  local u = to_u32(x)
  if u >= 2147483648 then return u - 4294967296 end
  return u
end

local function u32_mul(a, b)
  local a0 = a % 65536
  local a1 = math.floor(a / 65536)
  local b0 = b % 65536
  local b1 = math.floor(b / 65536)

  local low = a0 * b0
  local mid = a1 * b0 + a0 * b1
  return to_u32(low + ((mid % 65536) * 65536))
end

local function bit_rshift(x, n)
  return math.floor(to_u32(x) / (2 ^ n))
end

local function bit_bor(a, b)
  local x = to_u32(a)
  local y = to_u32(b)
  local out = 0
  local bit = 1
  for _ = 1, 32 do
    local xb = x % 2
    local yb = y % 2
    if xb == 1 or yb == 1 then out = out + bit end
    x = math.floor(x / 2)
    y = math.floor(y / 2)
    bit = bit * 2
  end
  return to_u32(out)
end

local function bit_bxor(a, b)
  local x = to_u32(a)
  local y = to_u32(b)
  local out = 0
  local bit = 1
  for _ = 1, 32 do
    local xb = x % 2
    local yb = y % 2
    if xb ~= yb then out = out + bit end
    x = math.floor(x / 2)
    y = math.floor(y / 2)
    bit = bit * 2
  end
  return to_u32(out)
end

hash_string = function(str)
  local h = 0
  local s = tostring(str or "")
  for i = 1, #s do
    h = to_i32((h * 31) + string.byte(s, i))
  end
  return math.abs(h)
end

create_prng = function(seed)
  local state = to_u32(seed)
  return function()
    state = to_u32(state + 0x6D2B79F5)
    local t = state
    local x = bit_bxor(t, bit_rshift(t, 15))
    t = u32_mul(x, bit_bor(t, 1))
    local y = bit_bxor(t, bit_rshift(t, 7))
    t = bit_bxor(t, to_u32(t + u32_mul(y, bit_bor(t, 61))))
    local out = bit_bxor(t, bit_rshift(t, 14))
    return to_u32(out) / 4294967296
  end
end

local function shuffled_range(rng, minv, maxv)
  local pool = {}
  for n = minv, maxv do table.insert(pool, n) end

  local out = {}
  while #pool > 0 do
    local idx = math.floor(rng() * #pool) + 1
    table.insert(out, pool[idx])
    table.remove(pool, idx)
  end
  return out
end

local function generate_bingo_card(masterPhrase, cardIndex)
  local random = create_prng(hash_string(tostring(masterPhrase) .. "-" .. tostring(cardIndex)))
  local ranges = {
    { letter = "B", min = 1, max = 15 },
    { letter = "I", min = 16, max = 30 },
    { letter = "N", min = 31, max = 45 },
    { letter = "G", min = 46, max = 60 },
    { letter = "O", min = 61, max = 75 },
  }

  local values = {}
  local marks = {}

  for _, col in ipairs(ranges) do
    values[col.letter] = {}
    marks[col.letter] = {}

    local pool = {}
    for n = col.min, col.max do table.insert(pool, n) end

    for row = 1, 5 do
      if col.letter == "N" and row == 3 then
        values[col.letter][row] = "FREE"
        marks[col.letter][row] = true
      else
        local randIndex = math.floor(random() * #pool) + 1
        values[col.letter][row] = pool[randIndex]
        marks[col.letter][row] = false
        table.remove(pool, randIndex)
      end
    end
  end

  return { values = values, marks = marks }
end

local function pick_room_words()
  local base = (time_ms ~= nil and time_ms() or os.time())
  local rng = create_prng(hash_string(tostring(base)))
  local words = {}
  local used = {}

  while #words < 3 do
    local idx = math.floor(rng() * #WORDS) + 1
    local w = WORDS[idx]
    if not used[w] then
      used[w] = true
      table.insert(words, w)
    end
  end

  return words
end

local function build_call_sequence(roomName)
  return shuffled_range(create_prng(hash_string(roomName)), 1, 75)
end

local function ball_label(n)
  local v = tonumber(n) or 0
  if v <= 15 then return "B-" .. tostring(v) end
  if v <= 30 then return "I-" .. tostring(v) end
  if v <= 45 then return "N-" .. tostring(v) end
  if v <= 60 then return "G-" .. tostring(v) end
  return "O-" .. tostring(v)
end

local function url_encode(s)
  local str = tostring(s or "")
  str = string.gsub(str, "\n", "\r\n")
  str = string.gsub(str, "([^%w %-_%.~])", function(c)
    return string.format("%%%02X", string.byte(c))
  end)
  str = string.gsub(str, " ", "%%20")
  return str
end

local function mark_ball_for_card(card, ball)
  if card == nil then return end

  local col = "O"
  if ball <= 15 then col = "B"
  elseif ball <= 30 then col = "I"
  elseif ball <= 45 then col = "N"
  elseif ball <= 60 then col = "G"
  end

  for row = 1, 5 do
    if card.values[col][row] == ball then
      card.marks[col][row] = true
      return
    end
  end
end

local function mark_count(card)
  local cols = { "B", "I", "N", "G", "O" }
  local c = 0
  for x = 1, 5 do
    for y = 1, 5 do
      if card.marks[cols[x]][y] then c = c + 1 end
    end
  end
  return c
end

local function line_count(card)
  local cols = { "B", "I", "N", "G", "O" }
  local lines = 0

  for row = 1, 5 do
    local ok = true
    for col = 1, 5 do
      if not card.marks[cols[col]][row] then ok = false break end
    end
    if ok then lines = lines + 1 end
  end

  for col = 1, 5 do
    local ok = true
    for row = 1, 5 do
      if not card.marks[cols[col]][row] then ok = false break end
    end
    if ok then lines = lines + 1 end
  end

  local diagA = true
  local diagB = true
  for i = 1, 5 do
    if not card.marks[cols[i]][i] then diagA = false end
    if not card.marks[cols[i]][6 - i] then diagB = false end
  end
  if diagA then lines = lines + 1 end
  if diagB then lines = lines + 1 end

  return lines
end

local function card_satisfies_condition(card, condition)
  if card == nil then return false end

  if condition == "1_line" then
    return line_count(card) >= 1
  elseif condition == "2_line" then
    return line_count(card) >= 2
  elseif condition == "4_corners" then
    return card.marks.B[1] and card.marks.B[5] and card.marks.O[1] and card.marks.O[5]
  elseif condition == "inside_square" then
    local cols = { "B", "I", "N", "G", "O" }
    for col = 2, 4 do
      for row = 2, 4 do
        if not card.marks[cols[col]][row] then return false end
      end
    end
    return true
  elseif condition == "outside_square" then
    local cols = { "B", "I", "N", "G", "O" }
    for col = 1, 5 do
      for row = 1, 5 do
        local border = (row == 1 or row == 5 or col == 1 or col == 5)
        if border and not card.marks[cols[col]][row] then return false end
      end
    end
    return true
  elseif condition == "blackout" then
    return mark_count(card) >= 25
  elseif condition == "blitz_5" then
    return mark_count(card) >= 5
  end

  return false
end

local function player_has_condition(name, condition)
  local list = BINGO.cards[name] or {}
  for i = 1, #list do
    if card_satisfies_condition(list[i], condition) then return true end
  end
  return false
end

local function recalc_suggested_payouts()
  BINGO.suggested_payouts = {}
  if BINGO.mode ~= "progressive" then return end

  local rounds = #BINGO.progressive_playlist
  if rounds < 1 then return end

  local pot = tonumber(BINGO.pot_size) or 0
  if pot < 0 then pot = 0 end

  if BINGO.progressive_carryover_enabled then
    local carryPct = tonumber(BINGO.progressive_carryover_percent) or 0
    if carryPct < 0 then carryPct = 0 end
    if carryPct > 90 then carryPct = 90 end

    local remaining = pot
    for i = 1, rounds do
      if i == rounds then
        BINGO.suggested_payouts[i] = remaining
      else
        local pay = math.floor(remaining * (100 - carryPct) / 100)
        if pay < 0 then pay = 0 end
        BINGO.suggested_payouts[i] = pay
        remaining = remaining - pay
        if remaining < 0 then remaining = 0 end
      end
    end
    return
  end

  local weightMap = {
    ["1_line"] = 1,
    ["2_line"] = 1.4,
    ["4_corners"] = 1.7,
    ["inside_square"] = 2.0,
    ["outside_square"] = 2.3,
    ["blackout"] = 3.0,
    ["blitz_5"] = 0.8,
  }

  local totalWeight = 0
  for i = 1, rounds do
    totalWeight = totalWeight + (weightMap[BINGO.progressive_playlist[i]] or 1)
  end
  if totalWeight <= 0 then totalWeight = rounds end

  local assigned = 0
  for i = 1, rounds do
    local w = weightMap[BINGO.progressive_playlist[i]] or 1
    local amount = math.floor((pot * w) / totalWeight)
    BINGO.suggested_payouts[i] = amount
    assigned = assigned + amount
  end

  local remainder = pot - assigned
  if remainder > 0 then
    BINGO.suggested_payouts[rounds] = (BINGO.suggested_payouts[rounds] or 0) + remainder
  end
end

local function reset_round_state()
  BINGO.players = {}
  BINGO.cards = {}
  BINGO.player_seed = {}
  BINGO.player_codes = {}
  BINGO.winners = {}
  BINGO.winner_lookup = {}
  BINGO.claimable_lookup = {}
  BINGO.call_sequence = {}
  BINGO.cipher_words = {}
  BINGO.catchup_requests = {}
  BINGO.called_lookup = {}
  BINGO.call_history = {}
  BINGO.next_call_index = 1
  BINGO.selected_player = 1
  BINGO.selected_card = 1
  BINGO.progressive_results = {}

  if BINGO.mode == "progressive" then
    BINGO.progressive_round_index = 1
  end
end

local function sync_buyers_from_roster()
  local count = dealer_player_count()
  for i = 1, count do
    local name = dealer_player_name(i)
    if name ~= nil and name ~= "" and dealer_is_eligible(name) then
      local existing = tonumber(BINGO.cards_bought[name]) or 0
      if existing < 1 then BINGO.cards_bought[name] = 1 end
    end
  end
end

local function send_tell(player, world, message)
  local msg = tostring(message or "")
  if msg == "" then return false end

  local playerName = tostring(player or "")
  if playerName == "" then return false end

  local targetWorld = tostring(world or "")
  if (targetWorld == "" or targetWorld == "Unknown") and dealer_get_world ~= nil then
    targetWorld = tostring(dealer_get_world(playerName) or targetWorld)
  end
  if targetWorld == "" then targetWorld = "Unknown" end

  -- Prefer host dealer_tell because it already builds a valid tell command.
  if dealer_tell ~= nil then
    dealer_tell(playerName, targetWorld, msg)
    log_info("dealer_tell => " .. playerName .. "@" .. targetWorld .. " | " .. msg)
    return true
  end

  if chat_command ~= nil then
    local cmd = ""
    if targetWorld == "Unknown" then
      cmd = "/tell " .. playerName .. " " .. msg
    else
      cmd = "/tell " .. playerName .. "@" .. targetWorld .. " " .. msg
    end
    local sent = chat_command(cmd) == true
    log_info("tell cmd => " .. cmd .. " | sent=" .. tostring(sent))
    return sent
  end

  return false
end

local function send_links_to_players()
  if #BINGO.players == 0 then return end

  local sent = 0
  for i = 1, #BINGO.players do
    local p = BINGO.players[i]
    local seed = BINGO.player_seed[p] or BINGO.player_codes[p] or room_seed_text()
    local count = #(BINGO.cards[p] or {})
    if count < 1 then count = 1 end

    local base = tostring(BINGO.web_base_url or "")
    local sep = "?"
    if string.find(base, "?", 1, true) then sep = "&" end
    local link = base .. sep .. "phrase=" .. url_encode(seed) .. "&count=" .. tostring(count)

    local world = (dealer_get_world ~= nil) and tostring(dealer_get_world(p) or "Unknown") or "Unknown"
    if send_tell(p, world, "Your Bingo cards: " .. link) then sent = sent + 1 end
  end

  announce("links_sent", { total = sent })
  BINGO.info = "Sent links: " .. tostring(sent) .. " / " .. tostring(#BINGO.players)
end

local function start_round()
  reset_round_state()
  sync_buyers_from_roster()
  recalc_suggested_payouts()

  BINGO.room_words = pick_room_words()
  BINGO.room_name = room_seed_text()

  local count = dealer_player_count()
  for i = 1, count do
    local name = dealer_player_name(i)
    if name ~= nil and name ~= "" and dealer_is_eligible(name) then
      table.insert(BINGO.players, name)
    end
  end

  if #BINGO.players == 0 then
    BINGO.phase = "idle"
    BINGO.info = "No eligible players in dealer roster."
    return
  end

  assign_player_codes(BINGO.players)
  BINGO.call_sequence = build_call_sequence(BINGO.room_name)
  BINGO.cipher_words = build_cipher_words(BINGO.room_name)

  for i = 1, #BINGO.players do
    local p = BINGO.players[i]
    local bought = tonumber(BINGO.cards_bought[p]) or 1
    if bought < 1 then bought = 1 end
    if bought > 20 then bought = 20 end

    local seed = BINGO.player_codes[p] or room_seed_text()
    BINGO.player_seed[p] = seed
    BINGO.cards[p] = {}

    for cardIndex = 1, bought do
      table.insert(BINGO.cards[p], generate_bingo_card(seed, cardIndex))
    end
  end

  BINGO.phase = "running"
  BINGO.info = "Bingo ready: " .. condition_label(active_condition_key()) .. ". Draw the first ball."

  announce("start", { total = #BINGO.players })
  announce("room", { result = BINGO.room_name })
  send_links_to_players()
end

local function draw_next_call()
  if BINGO.phase ~= "running" then return end

  local idx = tonumber(BINGO.next_call_index) or 1
  if idx > #BINGO.call_sequence then
    BINGO.phase = "finished"
    BINGO.info = "All balls have been called."
    return
  end

  local ball = BINGO.call_sequence[idx]
  BINGO.next_call_index = idx + 1
  BINGO.called_lookup[ball] = true
  table.insert(BINGO.call_history, ball)

  local label = ball_label(ball)
  announce("call", { result = label })

  local condition = active_condition_key()

  for i = 1, #BINGO.players do
    local p = BINGO.players[i]
    local list = BINGO.cards[p] or {}
    for k = 1, #list do mark_ball_for_card(list[k], ball) end

    if (not BINGO.winner_lookup[p]) and player_has_condition(p, condition) then
      BINGO.claimable_lookup[p] = true
    end
  end

  local pending = {}
  for i = 1, #BINGO.players do
    local p = BINGO.players[i]
    if BINGO.claimable_lookup[p] and not BINGO.winner_lookup[p] then
      table.insert(pending, p)
    end
  end

  if #pending > 0 then
    BINGO.info = "Last ball: " .. label .. " | waiting bingo call from: " .. table.concat(pending, ", ")
  else
    BINGO.info = "Last ball: " .. label .. " | target: " .. condition_label(condition)
  end
end

local function trim(s)
  return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function split_chat_packet(packet)
  local text = tostring(packet or "")
  if text == "" then return nil, nil, nil, nil end

  local parts = {}
  local from = 1
  for _ = 1, 3 do
    local s, e = string.find(text, "|", from, true)
    if not s then break end
    table.insert(parts, string.sub(text, from, s - 1))
    from = e + 1
  end
  table.insert(parts, string.sub(text, from))

  if #parts < 4 then return nil, nil, nil, nil end
  return parts[1], parts[2], parts[3], parts[4]
end

local function is_catchup_command(message)
  local m = string.lower(trim(message))
  return m == "catchup" or m == "!catchup" or m == "/catchup" or m == ">catchup"
end

local function is_bingo_command(message)
  local m = string.lower(trim(message))
  m = string.gsub(m, "[!%.%?]+$", "")
  return m == "bingo" or m == "/bingo" or m == ">bingo" or m == "!bingo"
end

local function find_player_name(rawName)
  for i = 1, #BINGO.players do
    local p = BINGO.players[i]
    if string.lower(p) == string.lower(tostring(rawName or "")) then
      return p
    end
  end
  return nil
end

local function current_catchup_code()
  if BINGO.room_name == nil or BINGO.room_name == "" then return "" end

  local turn = (tonumber(BINGO.next_call_index) or 1) - 1
  if turn < 1 then
    return tostring(BINGO.room_name) .. " ready"
  end

  local turnWord = (BINGO.cipher_words or {})[turn]
  if turnWord == nil or turnWord == "" then
    return tostring(BINGO.room_name) .. " done"
  end

  return tostring(BINGO.room_name) .. " " .. tostring(turnWord)
end

local function maybe_process_chat()
  if chat_poll == nil or BINGO.phase ~= "running" then return end

  for _ = 1, 12 do
    local packet = chat_poll()
    if packet == nil or packet == "" then return end

    local name, world, _, message = split_chat_packet(packet)
    if name ~= nil and message ~= nil then
      local player = find_player_name(name)
      if player ~= nil then
        local worldName = trim(world)
        if worldName == "" and dealer_get_world ~= nil then
          worldName = tostring(dealer_get_world(player) or "Unknown")
        end
        if worldName == "" then worldName = "Unknown" end

        if is_catchup_command(message) then
          local used = tonumber(BINGO.catchup_requests[player]) or 0
          local limit = tonumber(BINGO.catchup_limit_per_player) or 1
          if limit < 0 then limit = 0 end

          if used >= limit then
            send_tell(player, worldName, "Catchup limit reached for this round.")
          else
            local code = current_catchup_code()
            if code == "" then
              send_tell(player, worldName, "Catchup unavailable right now.")
            else
              if send_tell(player, worldName, "Catchup code: " .. code) then
                BINGO.catchup_requests[player] = used + 1
              end
            end
          end
        elseif is_bingo_command(message) then
          local condition = active_condition_key()
          if (not BINGO.winner_lookup[player]) and BINGO.claimable_lookup[player] and player_has_condition(player, condition) then
            BINGO.winner_lookup[player] = true
            BINGO.claimable_lookup[player] = nil
            table.insert(BINGO.winners, player)
            announce("winner", { player = player })

            if BINGO.mode == "single" then
              BINGO.phase = "finished"
              BINGO.info = "Round over. Winner(s): " .. table.concat(BINGO.winners, ", ")
            elseif BINGO.mode == "progressive" then
              local roundIdx = tonumber(BINGO.progressive_round_index) or 1
              local payout = tonumber(BINGO.suggested_payouts[roundIdx]) or 0

              table.insert(BINGO.progressive_results, {
                round = roundIdx,
                condition = condition,
                winners = player,
                payout = payout,
              })

              BINGO.progressive_round_index = roundIdx + 1
              if BINGO.progressive_round_index > #BINGO.progressive_playlist then
                BINGO.phase = "finished"
                BINGO.info = "Progressive complete. Winner(s): " .. table.concat(BINGO.winners, ", ")
              else
                BINGO.winners = {}
                BINGO.winner_lookup = {}
                BINGO.claimable_lookup = {}
                BINGO.info = "Progressive advanced to: " .. condition_label(active_condition_key())
              end
            end
          else
            send_tell(player, worldName, "No valid bingo to claim yet.")
          end
        end
      end
    end
  end
end

function draw_ui()
  maybe_process_chat()

  ui_text_colored("Bingo", 1.0, 0.9, 0.4, 1.0)
  ui_separator()

  draw_mode_controls()
  ui_separator()
  draw_purchase_controls()
  ui_separator()

  if ui_button("New Round##new") then start_round() end
  ui_same_line()
  if ui_button("Draw Next Ball##draw") then draw_next_call() end
  ui_same_line()
  if ui_button("Resend Links##resend") then send_links_to_players() end

  ui_text("Status: " .. tostring(BINGO.phase) .. " | " .. tostring(BINGO.info))
  ui_text("Catchup code: " .. tostring(current_catchup_code()))

  local called = (tonumber(BINGO.next_call_index) or 1) - 1
  if called < 0 then called = 0 end
  ui_text("Called: " .. tostring(called) .. " / 75")

  if BINGO.mode == "progressive" then
    ui_text("Progressive round: " .. tostring(BINGO.progressive_round_index) .. " / " .. tostring(#BINGO.progressive_playlist))
    if #BINGO.progressive_playlist > 0 then
      ui_text("Current target: " .. condition_label(active_condition_key()))
    end
  end

  ui_text("Catchup requests per player this round: " .. tostring(BINGO.catchup_limit_per_player))

  local pending = {}
  for i = 1, #BINGO.players do
    local p = BINGO.players[i]
    if BINGO.claimable_lookup[p] and not BINGO.winner_lookup[p] then
      table.insert(pending, p)
    end
  end
  if #pending > 0 then
    ui_text("Claimable (waiting for bingo): " .. table.concat(pending, ", "))
  end

  if #BINGO.winners > 0 then
    ui_text_colored("Winner(s): " .. table.concat(BINGO.winners, ", "), 0.45, 1.0, 0.45, 1.0)
  end

  if #BINGO.progressive_results > 0 then
    ui_separator()
    ui_text_colored("Progressive Results", 1.0, 1.0, 0.8, 1.0)
    for i = 1, #BINGO.progressive_results do
      local r = BINGO.progressive_results[i]
      ui_text("R" .. tostring(r.round) .. " " .. condition_label(r.condition) .. " -> " .. tostring(r.winners) .. " | suggested " .. tostring(r.payout))
    end
  end

  ui_separator()
  ui_text_colored("Dealer Card View", 0.9, 0.95, 1.0, 1.0)

  if #BINGO.players == 0 then
    ui_text("(no active round)")
    return
  end

  if BINGO.selected_player < 1 then BINGO.selected_player = 1 end
  if BINGO.selected_player > #BINGO.players then BINGO.selected_player = #BINGO.players end

  if ui_button("< Prev Player##prev_player") then
    BINGO.selected_player = BINGO.selected_player - 1
    if BINGO.selected_player < 1 then BINGO.selected_player = #BINGO.players end
    BINGO.selected_card = 1
  end
  ui_same_line()
  if ui_button("Next Player >##next_player") then
    BINGO.selected_player = BINGO.selected_player + 1
    if BINGO.selected_player > #BINGO.players then BINGO.selected_player = 1 end
    BINGO.selected_card = 1
  end

  local p = BINGO.players[BINGO.selected_player]
  local list = BINGO.cards[p] or {}
  ui_text("Viewing: " .. tostring(p) .. " (" .. tostring(BINGO.selected_player) .. "/" .. tostring(#BINGO.players) .. ")")
  ui_text("Player seed: " .. tostring(BINGO.player_seed[p] or ""))

  if #list == 0 then
    ui_text("(no cards)")
    return
  end

  if BINGO.selected_card < 1 then BINGO.selected_card = 1 end
  if BINGO.selected_card > #list then BINGO.selected_card = #list end

  if ui_button("< Prev Card##prev_card") then
    BINGO.selected_card = BINGO.selected_card - 1
    if BINGO.selected_card < 1 then BINGO.selected_card = #list end
  end
  ui_same_line()
  if ui_button("Next Card >##next_card") then
    BINGO.selected_card = BINGO.selected_card + 1
    if BINGO.selected_card > #list then BINGO.selected_card = 1 end
  end

  ui_text("Card " .. tostring(BINGO.selected_card) .. " / " .. tostring(#list))
  local card = list[BINGO.selected_card]
  if draw_card ~= nil then
    draw_card(card, p, BINGO.selected_card)
  else
    local cols = { "B", "I", "N", "G", "O" }
    for row = 1, 5 do
      local rowParts = {}
      for col = 1, 5 do
        local key = cols[col]
        local v = card.values[key][row]
        local marked = card.marks[key][row] and "*" or " "
        table.insert(rowParts, string.format("%s%3s", marked, tostring(v)))
      end
      ui_text(table.concat(rowParts, "  "))
    end
  end
end

function draw_config_ui()
  ui_text_colored("Bingo Config", 0.8, 0.95, 0.8, 1.0)
  ui_separator()
  ui_text("Web URL base for tells")
  ui_text(BINGO.web_base_url)

  local lim = tonumber(BINGO.catchup_limit_per_player) or 1
  lim = ui_input_int("Catchup requests per player##catchup_limit", lim)
  if lim < 0 then lim = 0 end
  if lim > 20 then lim = 20 end
  BINGO.catchup_limit_per_player = lim
end

draw_purchase_controls = function()
  sync_buyers_from_roster()

  ui_text_colored("Card Purchases", 0.9, 0.95, 1.0, 1.0)
  ui_text("Player                          Cards  Controls")

  local count = dealer_player_count()
  local shown = 0
  for i = 1, count do
    local p = dealer_player_name(i)
    if p ~= nil and p ~= "" and dealer_is_eligible(p) then
      shown = shown + 1
      local cards = tonumber(BINGO.cards_bought[p]) or 1
      if cards < 1 then cards = 1 end
      if cards > 20 then cards = 20 end
      BINGO.cards_bought[p] = cards

      ui_text(string.format("%-28s %2d", p, cards))
      ui_same_line()
      if ui_button("-##bingo_buy_minus_" .. tostring(i)) then
        cards = cards - 1
        if cards < 1 then cards = 1 end
        BINGO.cards_bought[p] = cards
      end
      ui_same_line()
      if ui_button("+##bingo_buy_plus_" .. tostring(i)) then
        cards = cards + 1
        if cards > 20 then cards = 20 end
        BINGO.cards_bought[p] = cards
      end
    end
  end

  if shown == 0 then ui_text("(no eligible players)") end
end

local function ensure_playlist_defaults()
  if BINGO.progressive_playlist == nil or #BINGO.progressive_playlist == 0 then
    BINGO.progressive_playlist = { "1_line", "2_line", "4_corners", "blackout" }
  end
end

local function apply_progressive_preset(preset)
  if preset == "fast" then
    BINGO.progressive_playlist = { "1_line", "4_corners", "blackout" }
    BINGO.progressive_carryover_enabled = false
    BINGO.progressive_carryover_percent = 20
  elseif preset == "balanced" then
    BINGO.progressive_playlist = { "1_line", "2_line", "inside_square", "outside_square", "blackout" }
    BINGO.progressive_carryover_enabled = false
    BINGO.progressive_carryover_percent = 20
  elseif preset == "jackpot" then
    BINGO.progressive_playlist = { "1_line", "2_line", "4_corners", "inside_square", "outside_square", "blackout" }
    BINGO.progressive_carryover_enabled = true
    BINGO.progressive_carryover_percent = 50
  end

  BINGO.progressive_round_index = 1
  recalc_suggested_payouts()
end

draw_mode_controls = function()
  ensure_playlist_defaults()

  ui_text_colored("Game Type", 0.9, 0.95, 1.0, 1.0)
  if ui_button("Single##bingo_mode_single") then
    BINGO.mode = "single"
    recalc_suggested_payouts()
  end
  ui_same_line()
  if ui_button("Progressive##bingo_mode_prog") then
    BINGO.mode = "progressive"
    recalc_suggested_payouts()
  end

  ui_text("Mode: " .. BINGO.mode)

  ui_separator()
  ui_text("Single condition")

  local currentSingleIndex = 1
  for i = 1, #CONDITION_KEYS do
    if CONDITION_KEYS[i] == BINGO.single_condition then
      currentSingleIndex = i
      break
    end
  end

  if ui_button("<##single_prev") then
    currentSingleIndex = currentSingleIndex - 1
    if currentSingleIndex < 1 then currentSingleIndex = #CONDITION_KEYS end
    BINGO.single_condition = CONDITION_KEYS[currentSingleIndex]
  end
  ui_same_line()
  ui_text("[ " .. condition_label(BINGO.single_condition) .. " ]")
  ui_same_line()
  if ui_button(">##single_next") then
    currentSingleIndex = currentSingleIndex + 1
    if currentSingleIndex > #CONDITION_KEYS then currentSingleIndex = 1 end
    BINGO.single_condition = CONDITION_KEYS[currentSingleIndex]
  end

  if BINGO.mode == "progressive" then
    ui_separator()
    ui_text("Progressive presets")
    if ui_button("Fast##preset_fast") then apply_progressive_preset("fast") end
    ui_same_line()
    if ui_button("Balanced##preset_bal") then apply_progressive_preset("balanced") end
    ui_same_line()
    if ui_button("Jackpot-heavy##preset_jp") then apply_progressive_preset("jackpot") end

    ui_separator()
    ui_text("Playlist")
    for i = 1, #BINGO.progressive_playlist do
      ui_text(tostring(i) .. ") " .. condition_label(BINGO.progressive_playlist[i]))
      ui_same_line()
      if ui_button("x##pl_rm_" .. tostring(i)) then
        table.remove(BINGO.progressive_playlist, i)
        ensure_playlist_defaults()
        recalc_suggested_payouts()
        break
      end
    end

    ui_text("Add to playlist")
    local addIdx = tonumber(BINGO.condition_picker_progressive) or 1
    if addIdx < 1 then addIdx = 1 end
    if addIdx > #CONDITION_KEYS then addIdx = #CONDITION_KEYS end

    if ui_button("<##pl_pick_prev") then
      addIdx = addIdx - 1
      if addIdx < 1 then addIdx = #CONDITION_KEYS end
      BINGO.condition_picker_progressive = addIdx
    end
    ui_same_line()
    ui_text("[ " .. condition_label(CONDITION_KEYS[addIdx]) .. " ]")
    ui_same_line()
    if ui_button(">##pl_pick_next") then
      addIdx = addIdx + 1
      if addIdx > #CONDITION_KEYS then addIdx = 1 end
      BINGO.condition_picker_progressive = addIdx
    end
    ui_same_line()
    if ui_button("Add##pl_add") then
      table.insert(BINGO.progressive_playlist, CONDITION_KEYS[addIdx])
      recalc_suggested_payouts()
    end

    ui_separator()
    local carry = BINGO.progressive_carryover_enabled == true
    carry = ui_checkbox("Use Carryover Payout Model", carry)
    BINGO.progressive_carryover_enabled = carry

    local pct = tonumber(BINGO.progressive_carryover_percent) or 20
    pct = ui_input_int("Carryover % per round##carry_pct", pct)
    if pct < 0 then pct = 0 end
    if pct > 90 then pct = 90 end
    BINGO.progressive_carryover_percent = pct
  end

  ui_separator()
  local pot = tonumber(BINGO.pot_size) or 0
  pot = ui_input_int("Pot Size##pot", pot)
  if pot < 0 then pot = 0 end
  BINGO.pot_size = pot
  recalc_suggested_payouts()

  ui_text_colored("Suggested Payouts", 0.85, 1.0, 0.85, 1.0)
  if BINGO.mode ~= "progressive" then
    ui_text("(shown for progressive rounds only)")
  else
    for i = 1, #BINGO.progressive_playlist do
      local label = condition_label(BINGO.progressive_playlist[i])
      local amount = tonumber(BINGO.suggested_payouts[i]) or 0
      ui_text(string.format("R%-2d %-16s %d", i, label, amount))
    end
  end
end
