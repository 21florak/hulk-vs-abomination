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

-- When there aren't enough players, AI bots play the giants
Config.Bots = {
	abomination = true, -- a bot Abomination if fewer than 2 players
	hulk = true, -- a bot Hulk if fewer than 3 players
}

---------------------------------------------------------------------------
-- Giants
---------------------------------------------------------------------------
Config.GiantScale = 3 -- characters are scaled up this much (about 15 studs tall)

Config.Abomination = {
	hp = 3000,
	walkSpeed = 22,
	rageSpeed = 28, -- once chaos is high
	smashDamage = 160,
	smashRange = 15,
	smashCooldown = 1.0,
	catchRange = 9, -- grabs any civilian (not hidden) this close
	roarCooldown = 25,
	roarRadius = 70, -- civilians in range are revealed to the Abomination for a moment
	roarReveal = 2.5,
	leapCooldown = 6,
	searchTime = 1.2, -- hold time to search a hiding spot
	searchRange = 18,
	koSeconds = 18, -- knocked out this long when Hulk drops his HP to 0
	koRecoverHp = 0.5,
	noiseRadius = 90, -- hears civilians sprinting within this range
}

Config.Hulk = {
	hp = 2600,
	walkSpeed = 24,
	smashDamage = 230,
	smashRange = 15,
	smashCooldown = 0.9,
	clapCooldown = 16,
	clapRadius = 32,
	clapStun = 3,
	clapDamage = 120,
	leapCooldown = 5,
}

Config.Knockback = 140 -- how hard a giant gets launched by a hit (they crash through walls)

Config.Civilian = {
	walkSpeed = 13,
	sprintSpeed = 21,
	stamina = 100,
	sprintDrain = 22, -- per second
	staminaRegen = 14,
	flashlightBattery = 100,
	flashlightDrain = 4,
	flashlightRecharge = 6,
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
}

-- Costumes recolor the character. Owned costumes are saved; price 0 = free default.
Config.CostumeOrder = {
	hulk = { "hulk_classic", "hulk_gray", "hulk_red", "hulk_gladiator" },
	abomination = { "abom_classic", "abom_crimson", "abom_bone", "abom_toxic" },
	civilian = { "civ_office", "civ_scientist", "civ_guard", "civ_janitor", "civ_hoodie" },
}
Config.Costumes = {
	hulk_classic = { role = "hulk", name = "Classic Green", price = 0, skin = Color3.fromRGB(90, 160, 50), pants = Color3.fromRGB(90, 50, 130) },
	hulk_gray = { role = "hulk", name = "Gray Brute", price = 200, skin = Color3.fromRGB(130, 135, 140), pants = Color3.fromRGB(30, 30, 35) },
	hulk_red = { role = "hulk", name = "Red Rage", price = 400, skin = Color3.fromRGB(180, 35, 30), pants = Color3.fromRGB(40, 40, 45) },
	hulk_gladiator = { role = "hulk", name = "Gladiator", price = 700, skin = Color3.fromRGB(80, 150, 45), pants = Color3.fromRGB(120, 40, 30), armor = Color3.fromRGB(200, 170, 80) },

	abom_classic = { role = "abomination", name = "Classic Horror", price = 0, skin = Color3.fromRGB(95, 115, 85), spikes = Color3.fromRGB(45, 50, 40), eyes = Color3.fromRGB(255, 220, 60) },
	abom_crimson = { role = "abomination", name = "Crimson Horror", price = 250, skin = Color3.fromRGB(110, 30, 30), spikes = Color3.fromRGB(25, 15, 15), eyes = Color3.fromRGB(255, 60, 40) },
	abom_bone = { role = "abomination", name = "Bone White", price = 450, skin = Color3.fromRGB(215, 210, 195), spikes = Color3.fromRGB(80, 75, 70), eyes = Color3.fromRGB(120, 200, 255) },
	abom_toxic = { role = "abomination", name = "Toxic", price = 800, skin = Color3.fromRGB(40, 70, 45), spikes = Color3.fromRGB(80, 255, 90), eyes = Color3.fromRGB(80, 255, 90), glow = true },

	civ_office = { role = "civilian", name = "Office Worker", price = 0, shirt = Color3.fromRGB(235, 235, 235), pants = Color3.fromRGB(70, 70, 80) },
	civ_scientist = { role = "civilian", name = "Scientist", price = 100, shirt = Color3.fromRGB(245, 245, 245), pants = Color3.fromRGB(40, 60, 100), coat = true },
	civ_guard = { role = "civilian", name = "Security Guard", price = 150, shirt = Color3.fromRGB(30, 45, 80), pants = Color3.fromRGB(25, 30, 45) },
	civ_janitor = { role = "civilian", name = "Janitor", price = 150, shirt = Color3.fromRGB(230, 120, 30), pants = Color3.fromRGB(60, 70, 60) },
	civ_hoodie = { role = "civilian", name = "Black Hoodie", price = 250, shirt = Color3.fromRGB(25, 25, 28), pants = Color3.fromRGB(35, 35, 40) },
}

-- Optional sounds: paste Roblox audio asset ids (e.g. "rbxassetid://1234567") from the Creator
-- Store. Empty strings are skipped, so the game works without them.
Config.Sounds = {
	ambience = "", -- looping dark drone
	heartbeat = "",
	roar = "",
	smash = "",
	alarm = "",
	scream = "",
}

return Config
