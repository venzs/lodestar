-- Lodestar_Guide: class trainers of the 1-30 world and the levels at which each class has new spells.
--
-- Guide.TrainerData[classFile] lists NPC ids of class trainers in the starting zones, the leveling
-- towns and the capitals. Positions come from Data/Vanilla.lua (npcs[id].c); NPCs the harvest has
-- seen open a class trainer window are used too (LodestarScanDB.npcs[id].kind.trainer, tagged with
-- the class in Engine.lua), so trainers that are new on Forever — Undead paladins, for one — are
-- picked up as soon as the character has talked to them once.
--
-- Towns with no class trainer in the Vanilla data (nothing to list): Sen'jin Village, The Crossroads,
-- The Sepulcher, Tarren Mill, Auberdine, Astranaar, Lakeshire, Sentinel Hill, Darkshire.
-- Undead paladin trainers (Forever only, e.g. "Shan Stillwell <Paladin Trainer>" in Brill) are not in
-- the Vanilla data; the harvest fills them in.
local Guide = _G.Lodestar:GetModule("Guide")

Guide.TrainerData = {
	WARRIOR = {
		-- Horde
		2119,             -- Dannal Stern, Deathknell
		2131,             -- Austil de Mon, Brill
		4594, 4593, 4595, -- Angela Curthas, Christoph Walker, Baltus Fowler — Undercity
		3153,             -- Frang, Valley of Trials
		3169,             -- Tarshaw Jaggedscar, Razor Hill
		3353, 3354, 3408, -- Grezz Ragefist, Sorek, Zel'mak — Orgrimmar
		3059,             -- Harutt Thunderhorn, Camp Narache
		3063,             -- Krang Stonehoof, Bloodhoof Village
		3042, 3041, 3043, -- Sark, Torm, Ker Ragetotem — Thunder Bluff
		-- Alliance
		911,              -- Llane Beshere, Northshire
		913,              -- Lyria Du Lac, Goldshire
		5480, 5479, 914,  -- Ilsa Corbin, Wu Shen, Ander Germaine — Stormwind
		912,              -- Thran Khorman, Coldridge Valley
		1229,             -- Granis Swiftaxe, Kharanos
		5114, 5113, 1901, -- Bilban Tosslespanner, Kelv Sternhammer, Kelstrum Stonebreaker — Ironforge
		3593,             -- Alyissia, Shadowglen
		3598,             -- Kyra Windblade, Dolanaar
		4087, 7315, 4089, -- Arias'ta Bladesinger, Darnath Bladesinger, Sildanair — Darnassus
	},
	PALADIN = {
		-- Alliance (Horde paladins are Forever-only: Undead trainers such as Shan Stillwell in Brill come from the harvest)
		925,              -- Brother Sammuel, Northshire
		927,              -- Brother Wilhelm, Goldshire
		5491, 5492, 928, 6171, -- Arthur the Faithful, Katherine the Pure, Lord Grayson Shadowbreaker, Duthorian Rall — Stormwind
		926,              -- Bromos Grummner, Coldridge Valley
		1232,             -- Azar Stronghammer, Kharanos
		5148, 5149, 5147, -- Beldruk Doombrow, Brandur Ironhammer, Valgar Highforge — Ironforge
	},
	HUNTER = {
		-- Horde
		3154,             -- Jen'shan, Valley of Trials
		3171,             -- Thotar, Razor Hill
		3352, 3407, 3406, -- Ormak Grimshot, Sian'dur, Xor'juul — Orgrimmar
		3061,             -- Lanka Farshot, Camp Narache
		3065,             -- Yaw Sharpmane, Bloodhoof Village
		3039, 3038, 3040, -- Holt, Kary, Urek Thunderhorn — Thunder Bluff
		-- Alliance
		895,              -- Thorgas Grimson, Coldridge Valley
		1231,             -- Grif Wildheart, Kharanos
		5115, 5116, 5117, -- Daera Brightspear, Olmin Burningbeard, Regnus Thundergranite — Ironforge
		5515, 5516, 5517, -- Einris Brightspear, Ulfir Ironbeard, Thorfin Stoneshield — Stormwind
		3596,             -- Ayanna Everstride, Shadowglen
		3601,             -- Dazalar, Dolanaar
		4146, 10089,      -- Jocaste, Silvaria — Darnassus
	},
	ROGUE = {
		-- Horde
		2122,             -- David Trias, Deathknell
		2130,             -- Marion Call, Brill
		2132,             -- Carolai Anise, Brill/Undercity
		3155,             -- Rwag, Valley of Trials
		3170,             -- Kaplak, Razor Hill
		3327, 3328, 3401, -- Gest, Ormok, Shenthul — Orgrimmar
		-- Alliance
		917,              -- Keryn Sylvius, Goldshire
		918, 13283,       -- Osborne the Night Man, Lord Tony Romano — Stormwind
		916,              -- Solm Hargrin, Coldridge Valley
		1234,             -- Hogral Bakkan, Kharanos
		5167, 5165, 5166, -- Fenthwick, Hulfdan Blackbeard, Ormyr Flinteye — Ironforge
		3594,             -- Frahun Shadewhisper, Shadowglen
		3599,             -- Jannok Breezesong, Dolanaar
		4214, 4215, 4163, -- Erion Shadewhisper, Anishar, Syurna — Darnassus
	},
	PRIEST = {
		-- Horde
		2123,             -- Dark Cleric Duesten, Deathknell
		2129,             -- Dark Cleric Beryl, Brill
		4606, 4607, 4608, -- Aelthalyste, Father Lankester, Father Lazarus — Undercity
		3707,             -- Ken'jai, Valley of Trials
		3706,             -- Tai'jin, Razor Hill
		6018, 6014,       -- Ur'kyo, X'yera — Orgrimmar
		5888,             -- Seer Ravenfeather, Camp Narache
		2984,             -- Seer Wiserunner, Mulgore
		3046, 3044, 3045, -- Father Cobb, Miles Welsh, Malakai Cross — Thunder Bluff
		-- Alliance
		375,              -- Priestess Anetta, Northshire
		377,              -- Priestess Josetta, Goldshire
		376, 5484, 5489,  -- High Priestess Laurena, Brother Benjamin, Brother Joshua — Stormwind
		837,              -- Branstock Khalder, Coldridge Valley
		1226,             -- Maxan Anvol, Kharanos
		5142, 5143, 5141, -- Braenna Flintcrag, Toldren Deepiron, Theodrus Frostbeard — Ironforge
		3595,             -- Shanda, Shadowglen
		3600,             -- Laurna Morninglight, Dolanaar
		4090, 4092, 4091, -- Astarii Starseeker, Lariia, Jandria — Darnassus
	},
	SHAMAN = {
		-- Horde only (Alliance shamans are not in the Vanilla data)
		3157,             -- Shikrik, Valley of Trials
		3173,             -- Swart, Razor Hill
		3344, 13417, 3403, -- Kardris Dreamseeker, Sagorne Creststrider, Sian'tsu — Orgrimmar
		3062,             -- Meela Dawnstrider, Camp Narache
		3066,             -- Narm Skychaser, Bloodhoof Village
		3030, 5906, 3031, 3032, -- Siln Skychaser, Xanis Flameweaver, Tigor Skychaser, Beram Skychaser — Thunder Bluff
	},
	MAGE = {
		-- Horde
		2124,             -- Isabella, Deathknell
		2128,             -- Cain Firesong, Brill
		4568, 4566, 4567, -- Anastasia Hartwell, Kaelystia Hatebringer, Pierce Shackleton — Undercity
		5884,             -- Mai'ah, Valley of Trials
		5880,             -- Un'Thuwa, Razor Hill (Sen'jin side)
		5885, 5883, 7311, -- Deino, Enyo, Uthel'nay — Orgrimmar
		-- Alliance
		198,              -- Khelden Bremen, Northshire
		328,              -- Zaldimar Wefhellt, Goldshire
		5498, 5497, 331,  -- Elsharin, Jennea Cannon, Maginor Dumas — Stormwind
		944,              -- Marryk Nurribit, Coldridge Valley
		1228,             -- Magis Sparkmantle, Kharanos
		5144, 5145, 5146, -- Bink, Juli Stormkettle, Nittlebur Sparkfizzle — Ironforge
	},
	WARLOCK = {
		-- Horde
		2126,             -- Maximillion, Deathknell
		2127,             -- Rupert Boch, Brill
		5675, 4564, 4565, -- Carendin Halgar, Luther Pickman, Richard Kerwin — Undercity
		3156,             -- Nartok, Valley of Trials
		3172,             -- Dhugru Gorelust, Razor Hill
		3324, 3325, 3326, -- Grol'dar, Mirket, Zevrost — Orgrimmar
		-- Alliance
		459,              -- Drusilla La Salle, Northshire
		906,              -- Maximillian Crowe, Goldshire
		461, 6122, 5496, 5495, -- Demisette Cloyce, Gakin the Darkbinder, Sandahl, Ursula Deline — Stormwind
		460,              -- Alamar Grimm, Coldridge Valley
		5612,             -- Gimrizz Shadowcog, Kharanos
		5172, 5171,       -- Briarthorn, Thistleheart — Ironforge
	},
	DRUID = {
		-- Horde
		3060,             -- Gart Mistrunner, Camp Narache
		3064,             -- Gennia Runetotem, Bloodhoof Village
		3033, 3036, 3034, -- Turak Runetotem, Kym Wildmane, Sheal Runetotem — Thunder Bluff
		-- Alliance
		3597,             -- Mardant Strongoak, Shadowglen
		3602,             -- Kal, Dolanaar
		4218, 4219, 4217, -- Denatharion, Fylerian Nightwing, Mathrengyl Bearwalker — Darnassus
		-- Both
		12042,            -- Loganaar, Moonglade
	},
}

-- Levels 1-30 at which a class has new spells or ranks to buy. In Classic every class trains on
-- even levels; the odd-level abilities (totems, forms, pets, poisons) come from class quests, which
-- the guides carry as .class steps.
Guide.SpellLevels = {}
for classFile in pairs(Guide.TrainerData) do
	local levels = {}
	for level = 4, 30, 2 do levels[level] = true end
	Guide.SpellLevels[classFile] = levels
end
