-- Every tunable number and name for Monster Lockdown lives here.
local Config = {}

-- Display names. These are Marvel characters: if Roblox moderation or a copyright claim
-- becomes a problem, rename them here (e.g. "The Brute" / "The Horror") and nothing else changes.
Config.Names = {
	hulk = "Hulk",
	abomination = "Abomination",
	civilian = "Civilian",
	game = "Hulk vs Abomination: Lockdown",
}

Config.Round = {
	intermission = 20, -- seconds in the lobby between rounds
	hide = 25, -- civilians hide while the Abomination is locked up
	hunt = 240, -- the hunt
	results = 10,
}

-- Players can only be civilians or the Abomination. The Hulk is never a player.
Config.PlayableHulk = false

-- When there aren't enough players, AI bots play the giants
Config.Bots = {
	abomination = true, -- a bot Abomination if fewer than 2 players
	hulk = true, -- an AI Hulk protects the civilians every round (false = no Hulk at all)
}

---------------------------------------------------------------------------
-- Giants
---------------------------------------------------------------------------
Config.GiantScale = 2 -- characters are scaled up this much (about 10 studs tall: twice a civilian, too tall for doors)

-- How thick the sculpted giant bodies are (1 = as sculpted). Lower = leaner, higher = bulkier.
Config.BodyBulk = 0.82

-- Giants plow through walls, doors and furniture just by running into them
Config.Rampage = {
	reach = 5, -- how far ahead of the giant's center it checks
	radius = 6, -- how much it tears out each time
}

Config.Abomination = {
	hp = 3000,
	walkSpeed = 27,
	rageSpeed = 33, -- once chaos is high
	smashDamage = 160,
	smashRange = 11,
	smashCooldown = 0.6,
	catchRange = 7, -- grabs any civilian (not hidden) this close
	roarCooldown = 25,
	roarRadius = 70, -- civilians in range are revealed to the Abomination for a moment
	roarReveal = 2.5,
	leapCooldown = 3,
	searchTime = 1.2, -- hold time to search a hiding spot
	searchRange = 14,
	koSeconds = 18, -- knocked out this long when Hulk drops his HP to 0
	koRecoverHp = 0.5,
	noiseRadius = 90, -- hears civilians sprinting within this range
}

Config.Hulk = {
	hp = 2600,
	walkSpeed = 30,
	smashDamage = 230,
	smashRange = 11,
	smashCooldown = 0.55,
	clapCooldown = 16,
	clapRadius = 28,
	clapStun = 3,
	clapDamage = 120,
	leapCooldown = 3,
}

-- Fighting back: keycards open the armory vault, which holds a cannon that kills the
-- Abomination in one hit. Adrenaline shots give civilians a short burst of speed.
Config.Objectives = {
	keycardsSpawned = 6, -- scattered through the rooms
	keycardsNeeded = 4, -- to open the vault
}
Config.Cannon = {
	name = "Containment Cannon",
	chargeTime = 1.2, -- seconds of glowing wind-up before it fires (stand your ground!)
	recharge = 20, -- after a shot
	range = 260,
	hitRadius = 6, -- how close the beam has to pass (scaled with the giant's size)
}
Config.Adrenaline = {
	maxOnMap = 2, -- only a couple lying around at a time
	respawn = 30, -- seconds before a taken shot is replaced somewhere else
	duration = 5,
	speed = 34, -- walk speed while boosted (sprint is 23)
}

-- Maps rotate every round (never the same one twice in a row)
Config.Maps = { "facility", "hospital", "subway", "city" }

-- The Abomination's rage meter (0-100). Full rage unlocks a super sprint (Shift).
Config.Rage = {
	perSecond = 1.4, -- while hunting
	perSmash = 3,
	perHitTaken = 6, -- when the Hulk hits it
	perCatch = 20,
	sprintSpeed = 52,
	sprintSeconds = 5,
}

Config.Knockback = 140 -- how hard a giant gets launched by a hit (they crash through walls)

Config.Civilian = {
	walkSpeed = 13,
	sprintSpeed = 23,
	stamina = 100,
	sprintDrain = 22, -- per second
	staminaRegen = 14,
	flashlightBattery = 100,
	flashlightDrain = 4,
	flashlightRecharge = 6,
	-- flashlight beam (raise these to make it brighter / reach further)
	flashlightBrightness = 7,
	flashlightRange = 75,
	flashlightAngle = 60,
}

---------------------------------------------------------------------------
-- The facility
---------------------------------------------------------------------------
Config.Facility = {
	cols = 6,
	rows = 4,
	room = 36, -- room size (studs)
	hall = 16, -- hallway width (giants fit, barely)
	height = 26, -- ceiling height
	panel = 6, -- breakable wall panel width/height
	doorWidth = 6,
	doorHeight = 10, -- people fit through doors; giants have to smash
	-- flickering hallway tube lights (raise these to make the hallways brighter)
	hallLightBrightness = 2.2,
	hallLightRange = 46,
	hallLightsMiddle = 10, -- extra tubes over random intersections, besides the hallway ends
}

-- Chaos: rises with every smash and hit. Each threshold triggers something worse.
Config.Chaos = {
	perPanel = 0.35,
	perGiantHit = 2.5,
	thresholds = {
		{ at = 20, event = "blackout", text = "The emergency lights are failing..." },
		{ at = 45, event = "collapse", text = "The ceiling is coming down!" },
		{ at = 70, event = "rage", text = "The Abomination is ENRAGED." },
		{ at = 100, event = "failing", text = "STRUCTURE FAILING — nowhere is safe." },
	},
	collapseEvery = 9, -- seconds between random collapses once "failing"
	spotStrength = 3, -- fight shockwaves nearby crack a hiding spot; this many and it breaks
	shockwaveRadius = 34,
}

---------------------------------------------------------------------------
-- Coins and costumes
---------------------------------------------------------------------------
Config.Rewards = {
	abominationWin = 120,
	abominationPerCatch = 15,
	hulkWin = 100,
	hulkKoBonus = 40,
	survivor = 60,
	caught = 10,
	participation = 5,
	cannonKill = 150, -- the civilian who blasts the Abomination
}

-- Costumes recolor the character. Owned costumes are saved; price 0 = free default.
Config.CostumeOrder = {
	hulk = { "hulk_classic", "hulk_gray", "hulk_red", "hulk_gladiator" },
	abomination = { "abom_classic", "abom_crimson", "abom_bone", "abom_toxic", "abom_nightmare" },
	civilian = { "civ_office", "civ_scientist", "civ_guard", "civ_janitor", "civ_hoodie", "civ_hazmat", "civ_paramedic" },
}
Config.Costumes = {
	hulk_classic = { role = "hulk", name = "Classic Green", price = 0, skin = Color3.fromRGB(76, 138, 46), pants = Color3.fromRGB(58, 46, 84) },
	hulk_gray = { role = "hulk", name = "Gray Brute", price = 200, skin = Color3.fromRGB(130, 135, 140), pants = Color3.fromRGB(30, 30, 35) },
	hulk_red = { role = "hulk", name = "Red Rage", price = 400, skin = Color3.fromRGB(180, 35, 30), pants = Color3.fromRGB(40, 40, 45) },
	hulk_gladiator = { role = "hulk", name = "Gladiator", price = 700, skin = Color3.fromRGB(80, 150, 45), pants = Color3.fromRGB(120, 40, 30), armor = Color3.fromRGB(200, 170, 80) },

	abom_classic = { role = "abomination", name = "Classic Horror", price = 0, skin = Color3.fromRGB(112, 122, 108), spikes = Color3.fromRGB(170, 160, 140), eyes = Color3.fromRGB(255, 160, 50) },
	abom_crimson = { role = "abomination", name = "Crimson Horror", price = 250, skin = Color3.fromRGB(110, 30, 30), spikes = Color3.fromRGB(25, 15, 15), eyes = Color3.fromRGB(255, 60, 40) },
	abom_bone = { role = "abomination", name = "Bone White", price = 450, skin = Color3.fromRGB(215, 210, 195), spikes = Color3.fromRGB(80, 75, 70), eyes = Color3.fromRGB(120, 200, 255) },
	abom_toxic = { role = "abomination", name = "Toxic", price = 800, skin = Color3.fromRGB(40, 70, 45), spikes = Color3.fromRGB(80, 255, 90), eyes = Color3.fromRGB(80, 255, 90), glow = true },

	civ_office = { role = "civilian", name = "Office Worker", price = 0, shirt = Color3.fromRGB(235, 235, 235), pants = Color3.fromRGB(70, 70, 80) },
	civ_scientist = { role = "civilian", name = "Scientist", price = 100, shirt = Color3.fromRGB(245, 245, 245), pants = Color3.fromRGB(40, 60, 100), coat = true },
	civ_guard = { role = "civilian", name = "Security Guard", price = 150, shirt = Color3.fromRGB(30, 45, 80), pants = Color3.fromRGB(25, 30, 45) },
	civ_janitor = { role = "civilian", name = "Janitor", price = 150, shirt = Color3.fromRGB(230, 120, 30), pants = Color3.fromRGB(60, 70, 60) },
	civ_hoodie = { role = "civilian", name = "Black Hoodie", price = 250, shirt = Color3.fromRGB(25, 25, 28), pants = Color3.fromRGB(35, 35, 40) },

	-- Daily login exclusives (can't be bought)
	civ_hazmat = { role = "civilian", name = "Hazmat Suit", daily = 3, shirt = Color3.fromRGB(235, 200, 40), pants = Color3.fromRGB(225, 190, 35) },
	civ_paramedic = { role = "civilian", name = "Paramedic", daily = 5, shirt = Color3.fromRGB(40, 90, 170), pants = Color3.fromRGB(30, 35, 50) },
	abom_nightmare = { role = "abomination", name = "Nightmare", daily = 7, skin = Color3.fromRGB(45, 35, 60), spikes = Color3.fromRGB(190, 70, 255), eyes = Color3.fromRGB(210, 90, 255), glow = true },
}

-- Progression: XP and levels, daily login rewards, and the wins leaderboard in the lobby
Config.XP = {
	played = 20,
	survived = 60,
	abominationWin = 80,
	perCatch = 25,
	keycard = 15,
	cannonKill = 200,
	levelBase = 100, -- XP for level 1 -> 2; each level after needs levelStep more
	levelStep = 50,
	coinsPerLevel = 25, -- bonus coins on level up (times the new level)
}
-- Day 1..7 of a login streak (it loops after day 7). Missing a day restarts at day 1.
Config.DailyRewards = {
	{ coins = 50 },
	{ coins = 75 },
	{ coins = 50, costume = "civ_hazmat" },
	{ coins = 100 },
	{ coins = 100, costume = "civ_paramedic" },
	{ coins = 150 },
	{ coins = 200, costume = "abom_nightmare" },
}

-- Sounds: original effects made by tools/make_sounds.py live in the sounds/ folder.
-- Upload each .ogg in the Creator Dashboard (Creations → Development Items → Audio), then paste
-- its id here as "rbxassetid://1234567". Empty strings are skipped, so the game works without them.
Config.Sounds = {
	ambience = "", -- sounds/ambience.ogg  (looping drone, vents, distant metal groans)
	heartbeat = "", -- sounds/heartbeat.ogg (loops faster as the Abomination gets close)
	roar = "", -- sounds/roar.ogg
	smash = "", -- sounds/smash.ogg
	stomp = "", -- sounds/stomp.ogg     (giant footsteps, heard from far away)
	alarm = "", -- sounds/alarm.ogg     (structure failing)
	scream = "", -- sounds/scream.ogg    (jump-scare stinger when you're caught or exposed)
	thunder = "", -- sounds/thunder.ogg   (after each lightning flash)
	taunt = "", -- sounds/taunt.ogg     (the Abomination's snarl in the catch jump scare; or upload your own voice line)
	pickup = "", -- sounds/pickup.ogg    (keycards, adrenaline)
	cannon = "", -- sounds/cannon.ogg    (charge-up and blast)
}

return Config
