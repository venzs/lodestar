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

--- The pasteable string, or nil plus a reason.
---
--- The header travels uncompressed so a malformed or truncated paste can be recognised as one of
--- ours and rejected with a useful message, rather than failing somewhere inside the decoder.
function Guide:ExportHarvest()
	local lib = deflate()
	if not lib then return nil, "the compression library did not load" end
	local rows = self:HarvestRows()
	if #rows == 0 then return nil, "nothing has been recorded yet" end
	local _, build = GetBuildInfo()
	local body = table.concat(rows, ";")
	local ok, packed = pcall(function()
		return lib:EncodeForPrint(lib:CompressDeflate(body, { level = 9 }))
	end)
	if not (ok and packed) then return nil, "could not compress the recording" end
	return ("LODE%d:%s:%s"):format(FORMAT, tostring(build), packed), #rows, #body
end

--- Split at a length any edit box will hold, on the header boundary so each piece is self-describing.
local function chunks(text)
	if #text <= SOFT_LIMIT then return { text } end
	local out, i = {}, 1
	while i <= #text do
		out[#out + 1] = text:sub(i, i + SOFT_LIMIT - 1)
		i = i + SOFT_LIMIT
	end
	return out
end

--- `/lode export`: the copy box, with the string already in it and selected.
function Guide:ShowHarvestExport()
	local text, rowsOrErr, rawLen = self:ExportHarvest()
	if not text then
		Lodestar:Say("Nothing to export: %s. Play for a while with Lodestar running and try again.", tostring(rowsOrErr))
		return
	end
	local parts = chunks(text)
	local header
	if #parts == 1 then
		header = ("%d recordings · %d characters — Ctrl+A then Ctrl+C, and paste it to %s")
			:format(rowsOrErr, #text, Lodestar.CONTACT)
	else
		header = ("%d recordings · %d characters in %d parts — copy and paste each part; they can go in any order")
			:format(rowsOrErr, #text, #parts)
	end
	Lodestar:ShowCopyBox(table.concat(parts, "\n\n--- next part ---\n\n"), header)
	Lodestar:Say("Recording exported: |cffffffff%d|r positions and links, |cffffffff%d|r characters (from %d raw). Paste it to %s.",
		rowsOrErr, #text, rawLen or 0, Lodestar.CONTACT)
end
