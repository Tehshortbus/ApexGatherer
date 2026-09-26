--[[
	Node sharing between players, over addon messages (AceComm splits and throttles them).

	Person to person: send your nodes to a player, or ask a player for theirs (whispers).
	Guild: send your nodes to the whole guild, ask the guild for theirs (each guildmate who
	answers whispers their nodes back, so the guild channel only carries the question), and
	optionally share every node with the guild the moment you gather it.

	A full send is announced with an offer first. Replies to our own request are accepted
	right away; anything else asks first (always for whispers, optionally for the guild).
	Received nodes are merged: one we already have (the same kind within the cleanup range)
	is skipped. Learned nodes travel by name, since their ids differ between players.
	Answering a player's request leaves out the nodes swapped with them this session (sent to
	them, or received from them), so what they gave us doesn't go straight back.

	Addon messages can go missing on the way, so a full send is numbered: each part fits one
	addon message, and at its end the receiver asks for any lost parts again (a couple of
	times) before reporting what arrived, and how much was lost if any still is.

	Messages ("|" is avoided, fields are split on ";"):
	  N;2;type;zone;xy;key               a node just gathered (guild)
	  Q;2;req;types                      please send me your nodes of these types
	  R;2;req;reason                     no nodes coming for that request
	  O;2;batch;count;req;parts          a full send of count nodes in parts parts follows (req: the request it answers, or -)
	  D;2;batch;part;type;zone;xy:key,…  part number part of a full send
	  E;2;batch;parts                    end of a full send (sent again after a resend)
	  M;2;batch;part,part,…              the receiver lost these parts: please send them again (whisper)
	type: M H F T. xy: the packed coordinate. key: catalog id, or @name for a learned node.
]]
local Apex = ApexGatherer
local Catalog = Apex.Catalog
local Sharing = Apex:NewModule("Sharing", "AceEvent-3.0", "AceComm-3.0")

local floor, random, time, date = math.floor, math.random, time, date
local tinsert, tconcat, tremove = table.insert, table.concat, table.remove

local PREFIX = "ApexGatherer"
local VERSION = "2"
local PART_BYTES = 250         -- a data message's size: one addon message, never split up
local LIVE_LIMIT = 30          -- live nodes taken from one sender per minute
local BUFFER_LIMIT = 50000     -- nodes held while an offer waits for an answer
local REQUEST_WINDOW = 600     -- seconds during which answers to our request come straight in
local OFFER_TIMEOUT = 600      -- an offer that stops arriving is dropped after this long
local RESEND_KEEP = 300        -- seconds our full sends stay at hand, to send lost parts again
local RESEND_TRIES = 2         -- times a receiver asks again for lost parts
local RESEND_WAIT = 30         -- seconds a receiver waits for them before asking again or giving up
-- keeping addon traffic light on the realm
local ASK_COOLDOWN = 300         -- ask the same guild or player at most this often
local GUILD_SEND_COOLDOWN = 300  -- send the whole collection to the guild at most this often
local ANSWER_COOLDOWN = 1800     -- answer the same guildmate's request at most this often
local LOG_SIZE = 12

local TYPES = Apex.KINDS
local TYPE_CODE = { Mining = "M", Herbalism = "H", Fishing = "F", Treasure = "T" }
local CODE_TYPE = { M = "Mining", H = "Herbalism", F = "Fishing", T = "Treasure" }

local batches = {}      -- incoming full sends, keyed sender .. ":" .. batch id
local requests = {}     -- our open requests: req id -> { target, time }
local liveSeen = {}     -- sender -> { minute, count }
local liveNews = {}     -- sender -> nodes added since the last announcement
local lastAsked = {}    -- "GUILD" or a player -> when we last asked them
local lastAnswered = {} -- guildmate -> when we last answered their request
local lastGuildSend = -math.huge
local askingPopup = {}  -- sender -> true while their request popup is up
local exchanged = {}    -- player (lower case) -> { "kind:zone:coord" = true } swapped with them this session
local sentBatches = {}  -- our recent full sends: batch -> { messages = { O, D 1, D 2, …, E }, time }
local log = {}
local outgoing          -- the full send in progress
local status = ""

local function options()
	return Apex.db.profile.sharing
end

local function newID()
	return ("%x%x"):format(time() % 65536, random(0, 65535))
end

local function shortName(name)
	return (Ambiguate(name, "none"))
end

local function sameName(a, b)
	return a:lower():gsub("%-.*", "") == b:lower():gsub("%-.*", "")
end

-- whether a message came from the player. On WoW Forever names are region-wide "First Last":
-- messages come from the whole name, which UnitName doesn't give (the surname comes apart).
local function isMe(sender)
	local first, last = (UnitNameUnmodified or UnitName)("player")
	if first and last and last ~= "" and sameName(sender, first .. " " .. last) then return true end
	local name = UnitName("player")
	return name ~= nil and sameName(sender, name)
end

local function exchangedWith(player)
	local key = player:lower()
	exchanged[key] = exchanged[key] or {}
	return exchanged[key]
end

local function refresh()
	local acr = LibStub("AceConfigRegistry-3.0", true)
	if acr and acr:GetOptionsTable("ApexGatherer/Sharing") then acr:NotifyChange("ApexGatherer/Sharing") end
end

local function addLog(text)
	tinsert(log, 1, date("%H:%M") .. "  " .. text)
	if #log > LOG_SIZE then tremove(log) end
	refresh()
end

local function setStatus(text)
	status = text
	refresh()
end

-- Midnight blocks addon messages in some situations (e.g. instance combat)
local function messagingLocked()
	local lockdown = C_ChatInfo and C_ChatInfo.InChatMessagingLockdown
	return lockdown and lockdown() or false
end

local function escape(s)
	return (s:gsub("[%%;,:%c]", function(c) return ("%%%02X"):format(c:byte()) end))
end
local function unescape(s)
	return (s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
end

-- how a node travels: its catalog id, or its name if it was learned (those ids differ between players)
local function nodeKey(id)
	local node = Catalog:Get(id)
	if not node then return end
	if node.learned then return "@" .. escape(node.name) end
	return tostring(id)
end

local function resolveKey(kind, key)
	if key:sub(1, 1) == "@" then
		local name = unescape(key:sub(2))
		if name == "" or #name > 60 or name:find("%c") then return end
		return Catalog:Find(kind, name) or Apex:LearnNode(kind, name)
	end
	local id = tonumber(key)
	local node = id and Catalog:Get(id)
	if node and node.kind == kind and not node.learned then return id end
end

local function typeCodes(types)
	local out = {}
	for _, t in ipairs(TYPES) do
		if types[t] then out[#out + 1] = TYPE_CODE[t] end
	end
	return tconcat(out)
end



-- Sending

function Sharing:OnEnable()
	self:RegisterComm(PREFIX)
	self:RegisterMessage("APEX_NODE_GATHERED", "OnNodeGathered")
end

-- live sharing: every node the player gathers goes to the guild
function Sharing:OnNodeGathered(_, kind, zone, coord, id)
	local opts = options()
	if not opts.liveGuild or not opts.types[kind] or not IsInGuild() or messagingLocked() then return end
	local key = nodeKey(id)
	if key then
		self:SendCommMessage(PREFIX, ("N;%s;%s;%d;%d;%s"):format(VERSION, TYPE_CODE[kind], zone, coord, key), "GUILD")
	end
end

function Sharing:IsSending()
	return outgoing ~= nil
end

local function describe(channel, target)
	return channel == "GUILD" and "your guild" or target
end

-- sends every node of the chosen types; channel "GUILD" or "WHISPER" (with target). Answering a
-- request (req), nodes already swapped with that player are left out.
function Sharing:SendNodes(channel, target, types, req)
	if outgoing then return false, "Already sending; wait for it to finish." end
	if channel == "GUILD" and not IsInGuild() then return false, "You're not in a guild." end
	if messagingLocked() then return false, "The game is blocking addon messages right now; try again in a moment." end
	if channel == "GUILD" and GetTime() - lastGuildSend < GUILD_SEND_COOLDOWN then
		return false, ("You sent your nodes to the guild a few minutes ago; you can again in %d min."):format(
			math.ceil((GUILD_SEND_COOLDOWN - (GetTime() - lastGuildSend)) / 60))
	end
	types = types or options().types

	local batch = newID()
	local parts, count = {}, 0   -- { type code, zone, items }
	local swapped = channel == "WHISPER" and exchangedWith(target)
	local skip = req and swapped
	for _, nodeType in ipairs(TYPES) do
		if types[nodeType] then
			local code = TYPE_CODE[nodeType]
			for zone, data in pairs(Apex.nodeData.kinds[nodeType]) do
				-- the room a part's items have, after its fields (the part number at its widest)
				local room = PART_BYTES - #("D;%s;%s;9999;%s;%d;"):format(VERSION, batch, code, zone)
				local items, size = {}, 0
				for coord, id in pairs(data) do
					local key = nodeKey(id)
					local spot = code .. ":" .. zone .. ":" .. coord
					if key and not (skip and skip[spot]) then
						local item = coord .. ":" .. key
						if #items > 0 and size + 1 + #item > room then
							parts[#parts + 1] = { code, zone, tconcat(items, ",") }
							items, size = {}, 0
						end
						items[#items + 1] = item
						size = size + 1 + #item
						count = count + 1
						if swapped then swapped[spot] = true end
					end
				end
				if #items > 0 then parts[#parts + 1] = { code, zone, tconcat(items, ",") } end
			end
		end
	end
	if count == 0 and skip then return false, "They already have all your nodes of those types.", "same" end
	if count == 0 then return false, "You have no nodes of those types to send.", "empty" end
	local messages = { ("O;%s;%s;%d;%s;%d"):format(VERSION, batch, count, req or "-", #parts) }
	for i, part in ipairs(parts) do
		messages[#messages + 1] = ("D;%s;%s;%d;%s;%d;%s"):format(VERSION, batch, i, part[1], part[2], part[3])
	end
	messages[#messages + 1] = ("E;%s;%s;%d"):format(VERSION, batch, #parts)
	for old, kept in pairs(sentBatches) do
		if GetTime() - kept.time > RESEND_KEEP then sentBatches[old] = nil end
	end
	sentBatches[batch] = { messages = messages, time = GetTime() }

	local total = 0
	for i = 1, #messages do total = total + #messages[i] end
	outgoing = { channel = channel, target = target, count = count, total = total, sent = 0 }
	if channel == "GUILD" then lastGuildSend = GetTime() end
	local who = describe(channel, target)
	setStatus(("Sending %d nodes to %s..."):format(count, who))

	local lastShown = 0
	for i = 1, #messages do
		local size, last = #messages[i], i == #messages
		self:SendCommMessage(PREFIX, messages[i], channel, target, "BULK", function(_, sent, len)
			if sent < len then return end
			outgoing.sent = outgoing.sent + size
			if last then
				outgoing = nil
				setStatus(("Sent %d nodes to %s."):format(count, who))
				addLog(("Sent %d nodes to %s"):format(count, who))
			elseif GetTime() - lastShown > 1 then
				lastShown = GetTime()
				setStatus(("Sending %d nodes to %s... %d%%"):format(count, who, outgoing.sent * 100 / outgoing.total))
			end
		end)
	end
	return true
end

-- asks a player (WHISPER) or the guild for their nodes; answers come in as full sends
function Sharing:RequestNodes(channel, target, types)
	if channel == "GUILD" and not IsInGuild() then return false, "You're not in a guild." end
	if messagingLocked() then return false, "The game is blocking addon messages right now; try again in a moment." end
	types = types or options().types
	local codes = typeCodes(types)
	if codes == "" then return false, "Pick at least one node kind." end
	local asked = channel == "GUILD" and "GUILD" or target:lower()
	if lastAsked[asked] and GetTime() - lastAsked[asked] < ASK_COOLDOWN then
		return false, ("You asked %s a few minutes ago; answers may still be arriving. You can ask again in %d min."):format(
			describe(channel, target), math.ceil((ASK_COOLDOWN - (GetTime() - lastAsked[asked])) / 60))
	end
	lastAsked[asked] = GetTime()
	local req = newID()
	requests[req] = { target = channel == "GUILD" and "GUILD" or target, time = GetTime() }
	self:SendCommMessage(PREFIX, ("Q;%s;%s;%s"):format(VERSION, req, codes), channel, target)
	local who = describe(channel, target)
	setStatus(("Asked %s for their nodes. Answers arrive over the next minutes."):format(who))
	addLog("Asked " .. who .. " for their nodes")
	return true
end


-- Receiving

StaticPopupDialogs["APEXGATHERER_SHARE_OFFER"] = {
	text = "%s wants to send you %s gathering nodes. Accept them?",
	button1 = ACCEPT,
	button2 = DECLINE,
	OnAccept = function(_, key) Sharing:AnswerOffer(key, true) end,
	OnCancel = function(_, key) Sharing:AnswerOffer(key, false) end,
	timeout = 120,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}
StaticPopupDialogs["APEXGATHERER_SHARE_REQUEST"] = {
	text = "%s asks for your gathering nodes (%s). Send them?",
	button1 = YES,
	button2 = NO,
	OnAccept = function(_, data) Sharing:AnswerRequest(data, true) end,
	OnCancel = function(_, data) Sharing:AnswerRequest(data, false) end,
	timeout = 120,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

local function processItems(b, nodeType, zone, items)
	local swapped = exchangedWith(b.sender)
	for item in items:gmatch("[^,]+") do
		local xy, key = item:match("^(%d+):(.+)$")
		local coord = tonumber(xy)
		local id = coord and Apex:ValidLocation(zone, coord) and resolveKey(nodeType, key)
		if id then swapped[TYPE_CODE[nodeType] .. ":" .. zone .. ":" .. coord] = true end
		if id and Apex:MergeNode(nodeType, zone, coord, id, true) then
			b.added = b.added + 1
		elseif id then
			b.known = b.known + 1
		else
			b.bad = b.bad + 1
		end
	end
end

local function finish(key)
	local b = batches[key]
	batches[key] = nil
	local text = ("Got %d new nodes from %s"):format(b.added, b.sender)
	if b.known > 0 then text = text .. (" (%d you already had)"):format(b.known) end
	if b.bad > 0 then text = text .. (", %d unknown to this version skipped"):format(b.bad) end
	local lost = b.count - b.added - b.known - b.bad - b.ignored
	if lost > 0 then text = text .. (", %d of the %d lost on the way"):format(lost, b.count) end
	addLog(text)
	if options().announce then Apex:Print(text .. ".") end
	Apex:SendMessage("APEX_NODES_CHANGED")
end

function Sharing:AnswerOffer(key, accepted)
	local b = batches[key]
	if not b or b.state ~= "asking" then return end
	if not accepted then
		b.state = "declined"
		b.buffer = nil
		addLog(("Declined %d nodes from %s"):format(b.count, b.sender))
		return
	end
	b.state = "accepted"
	for _, part in ipairs(b.buffer) do processItems(b, part[1], part[2], part[3]) end
	b.buffer = nil
	if b.complete then finish(key) end
end

function Sharing:AnswerRequest(data, accepted)
	if not data then return end
	askingPopup[data.sender] = nil
	if accepted then
		local ok, err, reason = self:SendNodes("WHISPER", data.sender, data.types, data.req)
		if not ok then
			Apex:Print(err)
			self:SendCommMessage(PREFIX, ("R;%s;%s;%s"):format(VERSION, data.req, reason or "busy"), "WHISPER", data.sender)
		end
	else
		self:SendCommMessage(PREFIX, ("R;%s;%s;declined"):format(VERSION, data.req), "WHISPER", data.sender)
	end
end

-- the types both asked for and allowed by our own settings
local function wantedTypes(codes)
	local mine, out, any = options().types, {}, false
	for code in codes:gmatch("[MHFT]") do
		local t = CODE_TYPE[code]
		if mine[t] then out[t], any = true, true end
	end
	return any and out
end

local handlers = {}

function handlers.N(sender, channel, code, zone, xy, key)
	local opts = options()
	local nodeType = CODE_TYPE[code]
	if channel ~= "GUILD" or not opts.acceptGuild or not nodeType or not opts.types[nodeType] then return end
	local minute = floor(GetTime() / 60)
	local seen = liveSeen[sender]
	if not seen or seen.minute ~= minute then
		seen = { minute = minute, count = 0 }
		liveSeen[sender] = seen
	end
	seen.count = seen.count + 1
	if seen.count > LIVE_LIMIT then return end
	zone, xy = tonumber(zone), tonumber(xy)
	local id = xy and key and Apex:ValidLocation(zone, xy) and resolveKey(nodeType, key)
	if id and Apex:MergeNode(nodeType, zone, xy, id) then
		if not next(liveNews) then
			C_Timer.After(30, function()
				local parts, total = {}, 0
				for who, n in pairs(liveNews) do
					parts[#parts + 1] = who .. " " .. n
					total = total + n
				end
				wipe(liveNews)
				addLog(("Guild shared %d new nodes (%s)"):format(total, tconcat(parts, ", ")))
				if options().announce then
					Apex:Print(("Your guild shared %d new nodes (%s)."):format(total, tconcat(parts, ", ")))
				end
			end)
		end
		liveNews[sender] = (liveNews[sender] or 0) + 1
	end
end

function handlers.Q(sender, channel, req, codes)
	local opts = options()
	local types = req and codes and wantedTypes(codes)
	if not types then return end
	if channel == "GUILD" then
		local last = lastAnswered[sender]
		if opts.answerGuild and not outgoing and not (last and GetTime() - last < ANSWER_COOLDOWN) then
			lastAnswered[sender] = GetTime()
			-- stagger the answers so a whole guild doesn't reply in the same instant
			C_Timer.After(1 + random() * 4, function()
				local ok = Sharing:SendNodes("WHISPER", sender, types, req)
				if ok then addLog("Answered " .. sender .. "'s request") end
			end)
		end
	elseif channel == "WHISPER" then
		if not opts.allowWhisper then
			Sharing:SendCommMessage(PREFIX, ("R;%s;%s;off"):format(VERSION, req), "WHISPER", sender)
		elseif outgoing then
			Sharing:SendCommMessage(PREFIX, ("R;%s;%s;busy"):format(VERSION, req), "WHISPER", sender)
		elseif not askingPopup[sender] then
			askingPopup[sender] = true
			local names = {}
			for _, t in ipairs(TYPES) do
				if types[t] then names[#names + 1] = Apex.KIND_LABEL[t] end
			end
			StaticPopup_Show("APEXGATHERER_SHARE_REQUEST", sender, tconcat(names, ", "),
				{ sender = sender, types = types, req = req })
		end
	end
end

local REASONS = { empty = "has no nodes of those types", same = "has nothing you don't already have", declined = "declined",
	off = "doesn't accept requests", busy = "is busy sending, try again later" }
function handlers.R(sender, channel, req, reason)
	if channel ~= "WHISPER" or not requests[req] then return end
	addLog(sender .. " " .. (REASONS[reason] or "sent nothing"))
	setStatus(sender .. " " .. (REASONS[reason] or "sent nothing") .. ".")
end

function handlers.O(sender, channel, batch, count, req, parts)
	local opts = options()
	count, parts = tonumber(count), tonumber(parts)
	if not batch or not count or count < 1 or not parts or parts < 1 then return end
	local key = sender .. ":" .. batch
	local b = { sender = sender, count = count, parts = parts, got = {}, tries = 0, added = 0, known = 0, bad = 0,
		ignored = 0, time = GetTime(), buffer = {}, held = 0 }

	local r = req and requests[req]
	if r and GetTime() - r.time < REQUEST_WINDOW and (r.target == "GUILD" or sameName(r.target, sender)) then
		b.state = "accepted"
	elseif channel == "GUILD" and opts.acceptGuild then
		b.state = opts.askGuild and "asking" or "accepted"
	elseif channel == "WHISPER" and opts.allowWhisper then
		b.state = "asking"
	else
		return
	end
	if b.state == "asking" then
		for _, other in pairs(batches) do
			if other.sender == sender and other.state == "asking" then return end   -- one question at a time
		end
	end
	batches[key] = b
	if b.state == "asking" then
		StaticPopup_Show("APEXGATHERER_SHARE_OFFER", sender, tostring(count), key)
	end
end

function handlers.D(sender, channel, batch, part, code, zone, items)
	local b = batches[sender .. ":" .. (batch or "")]
	part = tonumber(part)
	if not b or b.state == "declined" or not part or b.got[part] or part < 1 or part > b.parts or not items then return end
	b.got[part] = true
	b.time = GetTime()
	local nodeType = CODE_TYPE[code or ""]
	zone = tonumber(zone)
	if not nodeType or not options().types[nodeType] or not zone or not Apex:ValidLocation(zone, 0) then
		-- a kind we don't take, or a zone we don't know: left out, and not counted as lost
		for _ in items:gmatch("[^,]+") do b.ignored = b.ignored + 1 end
		return
	end
	if b.state == "accepted" then
		processItems(b, nodeType, zone, items)
	elseif b.held < BUFFER_LIMIT then
		b.buffer[#b.buffer + 1] = { nodeType, zone, items }
		for _ in items:gmatch("[^,]+") do b.held = b.held + 1 end
	end
end

-- at the end of a full send: ask the sender again for lost parts (a couple of times, a message's
-- worth of part numbers at a time), then wrap it up
local function checkParts(key)
	local b = batches[key]
	if not b then return end
	if b.state == "declined" then batches[key] = nil return end
	local missing = {}
	for i = 1, b.parts do
		if not b.got[i] then missing[#missing + 1] = i end
	end
	if #missing > 0 and b.tries < RESEND_TRIES then
		b.tries = b.tries + 1
		local list, size = {}, 0
		for _, i in ipairs(missing) do
			local text = tostring(i)
			if size + #text + 1 > PART_BYTES - 20 then break end
			list[#list + 1] = text
			size = size + #text + 1
		end
		Sharing:SendCommMessage(PREFIX, ("M;%s;%s;%s"):format(VERSION, key:match(":(.*)$"), tconcat(list, ",")), "WHISPER", b.sender)
		-- in case the parts sent again, or their end, go missing too: look again once nothing has
		-- arrived for a while
		b.time = GetTime()
		local tries = b.tries
		local function wait()
			if batches[key] ~= b or b.complete or b.tries ~= tries then return end
			local left = RESEND_WAIT - (GetTime() - b.time)
			if left > 0 then C_Timer.After(left, wait) else checkParts(key) end
		end
		C_Timer.After(RESEND_WAIT, wait)
		return
	end
	b.complete = true
	if b.state == "accepted" then finish(key) end
end

function handlers.E(sender, channel, batch)
	local key = sender .. ":" .. (batch or "")
	if batches[key] then checkParts(key) end
end

-- a receiver lost parts of our full send: send them again (to them only), then its end again
function handlers.M(sender, channel, batch, list)
	local kept = sentBatches[batch or ""]
	if channel ~= "WHISPER" or not kept or not list then return end
	local messages = kept.messages
	for part in list:gmatch("%d+") do
		local message = messages[tonumber(part) + 1]
		if message and message:sub(1, 1) == "D" then
			Sharing:SendCommMessage(PREFIX, message, "WHISPER", sender, "BULK")
		end
	end
	Sharing:SendCommMessage(PREFIX, messages[#messages], "WHISPER", sender, "BULK")
end

function Sharing:OnCommReceived(prefix, text, channel, sender)
	if prefix ~= PREFIX or (issecretvalue and (issecretvalue(text) or issecretvalue(sender))) then return end
	if channel ~= "GUILD" and channel ~= "WHISPER" then return end
	sender = shortName(sender)
	if isMe(sender) then return end
	local kind, version, a, b, c, d, e = strsplit(";", text)
	local handler = handlers[kind]
	if not handler or version ~= VERSION then return end
	handler(sender, channel, a, b, c, d, e)

	-- forget offers that stopped arriving
	local now = GetTime()
	for key, batch in pairs(batches) do
		if now - batch.time > OFFER_TIMEOUT then batches[key] = nil end
	end
end

function Sharing:CountNodes(types)
	local n = 0
	for _, t in ipairs(TYPES) do
		if types[t] then n = n + Apex:CountNodes(t) end
	end
	return n
end

function Sharing:GetStatus()
	return status
end

function Sharing:GetLog()
	return log
end
