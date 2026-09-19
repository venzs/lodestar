-- Lodestar_Guide: a session's harvest, short enough to paste into a chat message.
--
-- The file route asks a contributor to /reload, then find WTF\Account\<THEIR ACCOUNT>\SavedVariables\
-- Lodestar_Guide.lua in a folder the client will not name for them, then attach it. Every one of
-- those steps loses people, and the middle one loses most of them: an addon cannot be told its own
-- account folder, so the best instruction available is "search your World of Warcraft folder".
-- Someone doing you a favour should not have to go looking for anything.
--
-- So: the same information as a string. Ctrl+A, Ctrl+C, paste. No reload -- this reads the live
-- table rather than waiting for the client to write it -- and no file browsing at all. Discord turns
-- a long paste into an attachment by itself, so length stops being the contributor's problem.
--
-- What goes in is only what is SCARCE. Quest titles, objective text and descriptions are already in
-- the shipped databases for the old world, and for new content one contributor supplies them once;
-- sending them from everybody is most of the bytes for almost none of the value. Positions are the
-- scarce thing -- where an NPC actually stands, which NPC gives and ends which quest, where the
-- flight points are -- because nothing but playing produces them.
local Lodestar = _G.Lodestar
local Guide = Lodestar:GetModule("Guide")

local FORMAT = 1               -- bump when the row grammar changes; the importer checks it
local SOFT_LIMIT = 24000       -- characters before the export is split, well under an edit box's limit
local MARKER_ROOM = 32         -- room for the part marker a split export adds to every piece

local function deflate()
	return _G.LibStub and _G.LibStub("LibDeflate", true) or _G.LibDeflate
end

--- One decimal place, as a plain string. Coordinates are percentages of the map; a second decimal
--- is under a yard in most zones and costs a character per number on every row.
local function pos(n)
	return string.format("%.1f", tonumber(n) or 0)
end

--- The rows worth sending, grouped by kind. Deliberately flat text: it compresses far better than
--- any structured encoding, because the ids in a session cluster and DEFLATE finds that by itself.
---
--- n  npcID,mapID,x,y            an NPC seen at an exact position
--- o  objectID,mapID,x,y         a world object, same
--- q  questID,giverNpcID,enderNpcID   who hands it out and who takes it back (0 when unknown)
--- f  nodeID,mapID,x,y           a flight point
--- l  level,xpRequired           the XP a level costs, which the client will not tell an addon
function Guide:HarvestRows()
	local db = self:HarvestDB()
	local rows = {}
	for id, e in pairs(db.npcs or {}) do
		if e.exact and e.map and e.x and e.y then
			rows[#rows + 1] = ("n%d,%d,%s,%s"):format(id, e.map, pos(e.x), pos(e.y))
		end
	end
	for id, e in pairs(db.objects or {}) do
		if e.map and e.x and e.y then
			rows[#rows + 1] = ("o%d,%d,%s,%s"):format(id, e.map, pos(e.x), pos(e.y))
		end
	end
	for id, q in pairs(db.quests or {}) do
		local giver = type(q.giver) == "table" and q.giver.npc or q.giver
		local ender = type(q.ender) == "table" and q.ender.npc or q.ender
		if tonumber(giver) or tonumber(ender) then
			rows[#rows + 1] = ("q%d,%d,%d"):format(id, tonumber(giver) or 0, tonumber(ender) or 0)
		end
	end
	for id, e in pairs(db.taxi or {}) do
		if e.map and e.x and e.y then
			rows[#rows + 1] = ("f%d,%d,%s,%s"):format(id, e.map, pos(e.x), pos(e.y))
		end
	end
	for level, xp in pairs(db.levels or {}) do
		if tonumber(level) and tonumber(xp) then
			rows[#rows + 1] = ("l%d,%d"):format(level, xp)
		end
	end
	table.sort(rows)   -- stable order: the same session exports the same string twice
	return rows
end

--- Who recorded this, as one row.
---
--- The saved-variable export has carried a contributor block since the harvest split; a pasted one
--- did not -- so the format almost everybody actually uses was the anonymous one. Over a beta that
--- is a fortnight of contributions nobody can tell apart: not who to thank, not which zones are
--- genuinely covered rather than only looking covered, and not whose character to ask when a
--- recorded position turns out to be wrong.
---
--- What travels is an ID, not a name. `/lode share`, the README and the packaged INSTALL.txt all
--- tell a contributor the harvest does not contain their character name, and a paste that carried
--- one would make that false for the format most people use. A hash of name-realm is enough for
--- everything the attribution is actually for -- telling one contributor's sessions apart, seeing
--- which zones are covered by whom, noticing that every position in a zone came from one person --
--- without the paste containing the name itself.
---
--- It is a stable pseudonym and not anonymity: with a short list of candidate names anyone can hash
--- them and compare. That is fine for what this is, and it is why the ID is not presented as making
--- a contributor untraceable.
---
--- About fifty characters against a part's twenty-four thousand. Anyone who would rather send
--- nothing at all can delete this row from the paste and every other row still imports.
--- The hash itself lives in Core/Utils, because the saved-variable harvest keys its contributors by
--- the same value. Two implementations would drift, and a contributor who sent a file one week and a
--- paste the next would arrive as two people.
---
--- Deliberately NOT a format bump. The importer checks the header version for exact equality, so
--- raising it would reject every export from a contributor still on the current build -- and this
--- needs no such break, because an importer that does not know `c` skips it like any other
--- unrecognised row.
local function identityRow()
	local name = UnitName and UnitName("player")
	if not name or name == "" then return nil end
	local realm = (GetRealmName and GetRealmName()) or ""
	local race = UnitRace and (UnitRace("player")) or "?"
	-- Written out rather than `local _, class = UnitClass and UnitClass("player")`: an `and`
	-- expression yields exactly one value, so the class TOKEN -- the second return, and the one the
	-- saved-variable exporter records -- was silently dropped and every contributor came back "?".
	local class = "?"
	if UnitClass then
		local _, token = UnitClass("player")
		class = token or "?"
	end
	local faction = (UnitFactionGroup and UnitFactionGroup("player")) or "?"
	local level = (UnitLevel and UnitLevel("player")) or 0
	-- Hashed from the same "Name-Realm" the saved-variable side keys its contributors by, so one
	-- character has one ID wherever their data arrives from. The hash is hex, so it cannot contain a
	-- comma or a semicolon and nothing needs escaping.
	local full = realm ~= "" and (name .. "-" .. realm:gsub("%s+", "")) or name
	local id = Lodestar.ContributorID(full)
	if not id then return nil end
	return ("c%s,%s,%s,%s,%d,%d"):format(id, race or "?", class or "?", faction or "?",
		tonumber(level) or 0, (time and time()) or 0)
end

--- One slice of the rows, packed as a complete export string: its own header, its own DEFLATE
--- stream, decodable with nothing else in hand. Returns nil if the library refuses.
---
--- Each part is packed separately because a part has to survive being pasted on its own, out of
--- order, or with somebody's "here you go!" typed around it. The first version of this cut the
--- finished string into fixed lengths instead, which made every piece after the first a headless
--- fragment of a stream -- and nothing anywhere rejected it. The separator between the pieces
--- contributed eight letters that are in the encoding alphabet, so they were absorbed into the
--- payload and the decoder carried on emitting plausible rubbish. Measured on a 4,000-row session
--- pasted back in the right order: 2,541 positions correct, 1,437 silently lost, 22 real NPCs
--- moved to coordinates nobody had recorded, and 117 NPC ids that were never in the session given
--- positions of their own. All of it bound for the shipped route data, none of it raising anything.
local function packPart(lib, build, rows, from, to, index, total, who)
	local slice = {}
	-- The identity rides on EVERY part, not just the first. These parts are deliberately
	-- self-describing -- own header, own stream, pasteable in any order -- and an identity carried
	-- only by part one breaks exactly that property: a contributor who sends parts two and three is
	-- anonymous. Fifty characters against a part's twenty-four thousand, and the importer folds the
	-- repeats back into one session by their shared timestamp.
	if who then slice[#slice + 1] = who end
	for i = from, to do slice[#slice + 1] = rows[i] end
	-- A part marker, so the far end can say "you pasted 1 and 3 of 3" rather than quietly merging
	-- two thirds of somebody's evening. Importers skip row kinds they do not know, including the
	-- one already in the wild, so adding it costs no compatibility.
	if total and total > 1 then slice[#slice + 1] = ("p%d,%d"):format(index, total) end
	local body = table.concat(slice, ";")
	local ok, packed = pcall(function()
		return lib:EncodeForPrint(lib:CompressDeflate(body, { level = 9 }))
	end)
	if not (ok and packed) then return nil end
	return ("LODE%d:%s:%s"):format(FORMAT, tostring(build), packed), #body
end

--- Row ranges that each pack to something an edit box will hold.
---
--- Compression means the only honest way to know how long a part comes out is to pack it, so a
--- range that lands over the limit is halved and tried again rather than guessed at from the raw
--- byte count -- which would be wrong by whatever the session happened to compress to.
local function ranges(lib, build, rows, who)
	local budget = SOFT_LIMIT - MARKER_ROOM
	local out, pending = {}, { { 1, #rows } }
	while #pending > 0 do
		local span = table.remove(pending, 1)
		local from, to = span[1], span[2]
		-- Sized WITH the identity row, since the real part will carry one: measuring without it
		-- would let a part land over the limit by exactly the thing this forgot to count.
		local text = packPart(lib, build, rows, from, to, nil, nil, who)
		if not text then return nil end
		if #text <= budget or from >= to then
			out[#out + 1] = { from, to }
		else
			-- Both halves go to the front, left first, so the parts stay in row order.
			local mid = from + math.floor((to - from) / 2)
			table.insert(pending, 1, { mid + 1, to })
			table.insert(pending, 1, { from, mid })
		end
	end
	return out
end

--- The pasteable parts, or nil plus a reason. Always a table, even for a session that fits in one.
---
--- The header travels uncompressed so a malformed or truncated paste can be recognised as one of
--- ours and rejected with a useful message, rather than failing somewhere inside the decoder.
function Guide:ExportHarvest()
	local lib = deflate()
	if not lib then return nil, "the compression library did not load" end
	local rows = self:HarvestRows()
	if #rows == 0 then return nil, "nothing has been recorded yet" end
	local _, build = GetBuildInfo()
	-- Built once, not per part. The row carries a timestamp and that is what the importer folds a
	-- split export's repeated identities back together by, so it has to be the same on every part --
	-- calling this inside the loop would tick over a second boundary and turn one session into two.
	local who = identityRow()
	local spans = ranges(lib, build, rows, who)
	if not spans then return nil, "could not compress the recording" end
	local parts, raw = {}, 0
	for i, span in ipairs(spans) do
		local text, n = packPart(lib, build, rows, span[1], span[2], i, #spans, who)
		if not text then return nil, "could not compress the recording" end
		parts[#parts + 1], raw = text, raw + n
	end
	return parts, #rows, raw
end

--- `/lode export`: the copy box, with the string already in it and selected.
function Guide:ShowHarvestExport()
	local parts, rowsOrErr, rawLen = self:ExportHarvest()
	if not parts then
		Lodestar:Say("Nothing to export: %s. Play for a while with Lodestar running and try again.", tostring(rowsOrErr))
		return
	end
	local shown, total = {}, 0
	for i, part in ipairs(parts) do
		total = total + #part
		if #parts > 1 then shown[#shown + 1] = ("--- part %d of %d ---"):format(i, #parts) end
		shown[#shown + 1] = part
	end
	local header
	if #parts == 1 then
		header = ("%d recordings · %d characters — Ctrl+A then Ctrl+C, and paste it to %s")
			:format(rowsOrErr, total, Lodestar.CONTACT)
	else
		header = ("%d recordings · %d characters in %d parts — send all %d; each one stands on its own, so order does not matter")
			:format(rowsOrErr, total, #parts, #parts)
	end
	Lodestar:ShowCopyBox(table.concat(shown, "\n\n"), header)
	Lodestar:Say("Recording exported: |cffffffff%d|r positions and links, |cffffffff%d|r characters (from %d raw). Paste it to %s.",
		rowsOrErr, total, rawLen or 0, Lodestar.CONTACT)
end
