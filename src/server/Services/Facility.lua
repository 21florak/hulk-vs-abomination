-- Builds the dark research facility (rebuilt fresh every round) and the lit lobby.
-- Every wall inside the building is made of breakable panels; hiding spots are models with
-- prompts. Layout: a grid of rooms, each an island surrounded by hallways.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)

local Facility = {}

-- Layout numbers come from Config.Facility, adjusted per map (see THEMES below)
local F, PITCH, WIDTH, DEPTH
local THEME

local LOBBY = Vector3.new(0, 400, 0)
Facility.LOBBY = LOBBY


local function part(props, class)
	local p = Instance.new(class or "Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props) do
		if k == "Shape" then
			p.Shape = v
		end
	end
	for k, v in pairs(props) do
		if k ~= "Shape" then
			p[k] = v
		end
	end
	return p
end

local function roomCenter(i, j)
	return Vector3.new(-WIDTH / 2 + F.hall + F.room / 2 + (i - 1) * PITCH, 0, -DEPTH / 2 + F.hall + F.room / 2 + (j - 1) * PITCH)
end

local function hallPoint(rng)
	-- a random point in the hallway grid
	if rng:NextNumber() < 0.5 then
		local k = rng:NextInteger(0, F.cols)
		return Vector3.new(-WIDTH / 2 + F.hall / 2 + k * PITCH, 0, rng:NextNumber(-DEPTH / 2 + 8, DEPTH / 2 - 8))
	end
	local k = rng:NextInteger(0, F.rows)
	return Vector3.new(rng:NextNumber(-WIDTH / 2 + 8, WIDTH / 2 - 8), 0, -DEPTH / 2 + F.hall / 2 + k * PITCH)
end
Facility.hallPoint = hallPoint

---------------------------------------------------------------------------
-- Breakable walls
---------------------------------------------------------------------------
-- A wall of panels from a to b (horizontal, along X or Z) with optional door openings
-- (offsets from the wall's start). Everything gets the Breakable attribute.
local function panelWall(parent, a, b, doors, color)
	local alongX = math.abs(b.X - a.X) > math.abs(b.Z - a.Z)
	local length = (b - a).Magnitude
	local dir = (b - a).Unit
	local columns = math.max(1, math.floor(length / F.panel + 0.5))
	local width = length / columns
	for c = 0, columns - 1 do
		local mid = a + dir * (c + 0.5) * width
		local isDoor = false
		for _, d in ipairs(doors or {}) do
			if math.abs((c + 0.5) * width - d) < width / 2 then
				isDoor = true
			end
		end
		local rows = {}
		if isDoor then
			table.insert(rows, { F.doorHeight, F.height })
		else
			table.insert(rows, { 0, F.panel })
			table.insert(rows, { F.panel, F.panel * 2 })
			table.insert(rows, { F.panel * 2, F.height })
		end
		for _, r in ipairs(rows) do
			local h = r[2] - r[1]
			local size = if alongX then Vector3.new(width, h, 1) else Vector3.new(1, h, width)
			local p = part({ Name = "Panel", Size = size, Position = mid + Vector3.new(0, r[1] + h / 2, 0), Color = color or THEME.wall, Material = THEME.wallMaterial, Parent = parent })
			p:SetAttribute("Breakable", true)
		end
		if isDoor then
			-- door frame + exit sign above the door
			local sign = part({ Name = "ExitSign", Size = if alongX then Vector3.new(2.6, 0.9, 1.4) else Vector3.new(1.4, 0.9, 2.6), Position = mid + Vector3.new(0, F.doorHeight + 1.2, 0), Color = Color3.fromRGB(40, 200, 90), Material = Enum.Material.Neon, CanCollide = false, Parent = parent })
			local glow = Instance.new("PointLight")
			glow.Color = Color3.fromRGB(60, 255, 120)
			glow.Range = 12
			glow.Brightness = 0.6
			glow.Parent = sign
			sign:SetAttribute("Breakable", true)
		end
	end
end

---------------------------------------------------------------------------
-- Hiding spots
---------------------------------------------------------------------------
-- Each spot: a model with HidingSpot = true, HideCFrame (where the hidden player goes),
-- PeekCFrame (their camera), Strength (shockwaves crack it), and two prompts:
-- "Hide" (civilians) and "Search" (the Abomination). Clients hide prompts that aren't theirs.
local function addPrompts(model, anchor)
	local hide = Instance.new("ProximityPrompt")
	hide.Name = "HidePrompt"
	hide.ActionText = "Hide"
	hide.ObjectText = model.Name
	hide.HoldDuration = 0.4
	hide.MaxActivationDistance = 7
	hide.RequiresLineOfSight = false
	hide.KeyboardKeyCode = Enum.KeyCode.E
	hide.Parent = anchor
	local search = Instance.new("ProximityPrompt")
	search.Name = "SearchPrompt"
	search.ActionText = "Search"
	search.ObjectText = model.Name
	search.HoldDuration = Config.Abomination.searchTime
	search.MaxActivationDistance = Config.Abomination.searchRange
	search.RequiresLineOfSight = false
	search.KeyboardKeyCode = Enum.KeyCode.E
	search.Parent = anchor
end

local function spot(parent, name, cframe, hideOffset, peekOffset, parts)
	local model = Instance.new("Model")
	model.Name = name
	local anchor
	for i, spec in ipairs(parts) do
		local class = spec.class
		spec.class = nil
		local localCF = spec.CFrame or CFrame.new(spec.offset or Vector3.zero)
		spec.offset = nil
		spec.CFrame = cframe * localCF
		spec.Parent = model
		local p = part(spec, class)
		p:SetAttribute("Breakable", true)
		if i == 1 then
			anchor = p
		end
	end
	model.PrimaryPart = anchor
	model:SetAttribute("HidingSpot", true)
	model:SetAttribute("Strength", Config.Chaos.spotStrength)
	model:SetAttribute("HideCFrame", cframe * hideOffset)
	model:SetAttribute("PeekCFrame", cframe * peekOffset)
	addPrompts(model, anchor)
	model.Parent = parent
	return model
end

local METAL = Color3.fromRGB(90, 100, 110)
local WOOD = Color3.fromRGB(95, 70, 50)

-- cframe: floor position, facing -Z (the side you open / peek from)
local SPOT_BUILDERS = {
	locker = function(parent, cf)
		return spot(parent, "Locker", cf, CFrame.new(0, 3, 0), CFrame.new(0, 4.6, -0.6), {
			{ Size = Vector3.new(2.6, 7.4, 2.4), offset = Vector3.new(0, 3.7, 0), Color = METAL, Material = Enum.Material.Metal },
			{ Size = Vector3.new(2.2, 0.15, 0.1), offset = Vector3.new(0, 5.6, -1.22), Color = Color3.fromRGB(20, 20, 20) },
			{ Size = Vector3.new(2.2, 0.15, 0.1), offset = Vector3.new(0, 5.2, -1.22), Color = Color3.fromRGB(20, 20, 20) },
			{ Size = Vector3.new(0.2, 0.6, 0.2), offset = Vector3.new(0.9, 3.8, -1.25), Color = Color3.fromRGB(180, 180, 180) },
		})
	end,
	cabinet = function(parent, cf)
		return spot(parent, "Wardrobe", cf, CFrame.new(0, 3, 0), CFrame.new(0, 4.4, -0.9), {
			{ Size = Vector3.new(4.4, 7.6, 2.6), offset = Vector3.new(0, 3.8, 0), Color = WOOD, Material = Enum.Material.Wood },
			{ Size = Vector3.new(0.1, 7, 0.1), offset = Vector3.new(0, 3.8, -1.32), Color = Color3.fromRGB(30, 20, 15) },
		})
	end,
	desk = function(parent, cf)
		return spot(parent, "Desk", cf, CFrame.new(0, 1.2, 0.3) * CFrame.Angles(0, 0, 0), CFrame.new(0, 1.6, -1.4), {
			{ Size = Vector3.new(6, 0.4, 3.2), offset = Vector3.new(0, 3, 0), Color = Color3.fromRGB(110, 85, 60), Material = Enum.Material.Wood },
			{ Size = Vector3.new(6, 2.8, 0.2), offset = Vector3.new(0, 1.4, 1.5), Color = Color3.fromRGB(100, 75, 55), Material = Enum.Material.Wood },
			{ Size = Vector3.new(0.3, 2.8, 3.2), offset = Vector3.new(-2.85, 1.4, 0), Color = Color3.fromRGB(100, 75, 55) },
			{ Size = Vector3.new(0.3, 2.8, 3.2), offset = Vector3.new(2.85, 1.4, 0), Color = Color3.fromRGB(100, 75, 55) },
			{ Size = Vector3.new(1.6, 1.1, 0.15), offset = Vector3.new(0.8, 3.75, 0.6), Color = Color3.fromRGB(25, 25, 30) }, -- monitor
		})
	end,
	stall = function(parent, cf)
		return spot(parent, "Bathroom Stall", cf, CFrame.new(0, 3, 0.8), CFrame.new(0, 4.6, -1.2), {
			{ Size = Vector3.new(0.3, 7, 5), offset = Vector3.new(-2.2, 3.8, 0), Color = Color3.fromRGB(120, 130, 125) },
			{ Size = Vector3.new(0.3, 7, 5), offset = Vector3.new(2.2, 3.8, 0), Color = Color3.fromRGB(120, 130, 125) },
			{ Size = Vector3.new(4.2, 6.4, 0.2), offset = Vector3.new(0, 3.9, -2.5), Color = Color3.fromRGB(110, 120, 115) },
			{ Size = Vector3.new(1.6, 1.6, 2.2), offset = Vector3.new(0, 0.8, 1.6), Color = Color3.fromRGB(230, 230, 225) }, -- toilet
		})
	end,
	crate = function(parent, cf)
		return spot(parent, "Crate", cf, CFrame.new(0, 1.5, 0), CFrame.new(0, 3.6, -1.6), {
			{ Size = Vector3.new(5, 4.6, 5), offset = Vector3.new(0, 2.3, 0), Color = Color3.fromRGB(130, 100, 60), Material = Enum.Material.WoodPlanks },
			{ CFrame = CFrame.new(0, 4.8, 0.4) * CFrame.Angles(math.rad(-12), 0, 0), Size = Vector3.new(5.2, 0.3, 5.2), Color = Color3.fromRGB(120, 90, 55), Material = Enum.Material.WoodPlanks },
		})
	end,
	vent = function(parent, cf)
		return spot(parent, "Air Vent", cf, CFrame.new(0, 1.2, 1.5), CFrame.new(0, 1.4, -0.2), {
			{ Size = Vector3.new(4, 2.6, 5), offset = Vector3.new(0, 1.3, 2), Color = Color3.fromRGB(110, 115, 120), Material = Enum.Material.DiamondPlate },
			{ Size = Vector3.new(3.4, 2, 0.1), offset = Vector3.new(0, 1.3, -0.52), Color = Color3.fromRGB(40, 40, 45), Material = Enum.Material.Metal },
		})
	end,
	fridge = function(parent, cf)
		return spot(parent, "Walk-in Fridge", cf, CFrame.new(0, 3, 0.3), CFrame.new(0, 4.5, -1.2), {
			{ Size = Vector3.new(4.4, 8, 3.4), offset = Vector3.new(0, 4, 0), Color = Color3.fromRGB(200, 205, 210), Material = Enum.Material.Metal },
			{ Size = Vector3.new(0.25, 2, 0.3), offset = Vector3.new(1.6, 4.5, -1.8), Color = Color3.fromRGB(60, 60, 60) },
		})
	end,
	rack = function(parent, cf)
		return spot(parent, "Server Rack", cf, CFrame.new(0, 3, 0.6), CFrame.new(0, 4.4, -1), {
			{ Size = Vector3.new(3.4, 8, 3.4), offset = Vector3.new(0, 4, 0.2), Color = Color3.fromRGB(25, 25, 30), Material = Enum.Material.Metal },
			{ Size = Vector3.new(3, 0.15, 0.05), offset = Vector3.new(0, 6, -1.52), Color = Color3.fromRGB(40, 255, 120), Material = Enum.Material.Neon },
			{ Size = Vector3.new(3, 0.15, 0.05), offset = Vector3.new(0, 4.6, -1.52), Color = Color3.fromRGB(255, 160, 40), Material = Enum.Material.Neon },
		})
	end,
}

-- Spots for the other maps
local WHITE = Color3.fromRGB(225, 228, 225)
SPOT_BUILDERS.bed = function(parent, cf)
	return spot(parent, "Hospital Bed", cf, CFrame.new(0, 1, 0), CFrame.new(0, 1.2, -3.8), {
		{ Size = Vector3.new(3.8, 0.6, 7.4), offset = Vector3.new(0, 2.2, 0), Color = Color3.fromRGB(170, 175, 180), Material = Enum.Material.Metal },
		{ Size = Vector3.new(3.6, 0.5, 7), offset = Vector3.new(0, 2.75, 0), Color = WHITE, Material = Enum.Material.Fabric },
		{ Size = Vector3.new(4, 1.8, 7.6), offset = Vector3.new(0, 1.4, 0), Color = Color3.fromRGB(150, 190, 200), Material = Enum.Material.Fabric, Transparency = 0.05 }, -- sheet hanging to the floor
		{ Size = Vector3.new(3.8, 2.4, 0.3), offset = Vector3.new(0, 3.6, 3.7), Color = Color3.fromRGB(170, 175, 180), Material = Enum.Material.Metal }, -- headboard
	})
end
SPOT_BUILDERS.morgue = function(parent, cf)
	return spot(parent, "Morgue Drawer", cf, CFrame.new(0, 3, 0.5), CFrame.new(0, 3.4, -1.6), {
		{ Size = Vector3.new(6, 7.2, 3.4), offset = Vector3.new(0, 3.6, 0), Color = Color3.fromRGB(160, 165, 170), Material = Enum.Material.DiamondPlate },
		{ Size = Vector3.new(2.6, 2, 0.12), offset = Vector3.new(-1.5, 5.4, -1.74), Color = Color3.fromRGB(190, 195, 200), Material = Enum.Material.Metal },
		{ Size = Vector3.new(2.6, 2, 0.12), offset = Vector3.new(1.5, 5.4, -1.74), Color = Color3.fromRGB(190, 195, 200), Material = Enum.Material.Metal },
		{ Size = Vector3.new(2.6, 2, 0.12), offset = Vector3.new(-1.5, 2.8, -1.74), Color = Color3.fromRGB(190, 195, 200), Material = Enum.Material.Metal },
		{ Size = Vector3.new(2.6, 2, 0.12), offset = Vector3.new(1.5, 2.8, -1.74), Color = Color3.fromRGB(190, 195, 200), Material = Enum.Material.Metal },
	})
end
local CAR_COLORS = { Color3.fromRGB(150, 30, 30), Color3.fromRGB(30, 60, 130), Color3.fromRGB(200, 200, 205), Color3.fromRGB(25, 25, 28), Color3.fromRGB(230, 180, 30), Color3.fromRGB(60, 90, 60) }
SPOT_BUILDERS.car = function(parent, cf)
	local color = CAR_COLORS[math.random(1, #CAR_COLORS)]
	local taxi = math.random() < 0.25
	if taxi then
		color = Color3.fromRGB(240, 190, 20)
	end
	local parts = {
		{ Size = Vector3.new(6, 2.4, 12.5), offset = Vector3.new(0, 1.9, 0), Color = color, Material = Enum.Material.SmoothPlastic, Reflectance = 0.1 },
		{ Size = Vector3.new(5.4, 2.2, 6.4), offset = Vector3.new(0, 4.1, 0.6), Color = Color3.fromRGB(20, 25, 35), Material = Enum.Material.Glass, Transparency = 0.15 },
		{ Size = Vector3.new(5.2, 0.25, 6), offset = Vector3.new(0, 5.3, 0.6), Color = color, Material = Enum.Material.SmoothPlastic },
		{ Size = Vector3.new(1.2, 0.6, 0.2), offset = Vector3.new(-2.1, 2.2, -6.3), Color = Color3.fromRGB(255, 250, 220), Material = Enum.Material.Neon },
		{ Size = Vector3.new(1.2, 0.6, 0.2), offset = Vector3.new(2.1, 2.2, -6.3), Color = Color3.fromRGB(255, 250, 220), Material = Enum.Material.Neon },
		{ Size = Vector3.new(1.2, 0.5, 0.2), offset = Vector3.new(-2.1, 2.2, 6.3), Color = Color3.fromRGB(200, 20, 20), Material = Enum.Material.Neon },
		{ Size = Vector3.new(1.2, 0.5, 0.2), offset = Vector3.new(2.1, 2.2, 6.3), Color = Color3.fromRGB(200, 20, 20), Material = Enum.Material.Neon },
	}
	for _, w in ipairs({ { -3, -4 }, { 3, -4 }, { -3, 4 }, { 3, 4 } }) do
		table.insert(parts, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.9, 2.4, 2.4), CFrame = CFrame.new(w[1], 1.2, w[2]), Color = Color3.fromRGB(20, 20, 20) })
	end
	if taxi then
		table.insert(parts, { Size = Vector3.new(2, 0.6, 1), offset = Vector3.new(0, 5.7, 0.6), Color = Color3.fromRGB(255, 240, 150), Material = Enum.Material.Neon })
	end
	local model = spot(parent, if taxi then "Taxi" else "Car", cf, CFrame.new(0, 3, 0.5), CFrame.new(0, 4.4, -1.8), parts)
	model:SetAttribute("Vehicle", true)
	return model
end
SPOT_BUILDERS.train = function(parent, cf)
	local parts = {
		{ Size = Vector3.new(9, 8.5, 28), offset = Vector3.new(0, 5, 0), Color = Color3.fromRGB(150, 155, 160), Material = Enum.Material.DiamondPlate },
		{ Size = Vector3.new(9.1, 1.6, 24), offset = Vector3.new(0, 6.6, 0), Color = Color3.fromRGB(25, 30, 40), Material = Enum.Material.Glass },
		{ Size = Vector3.new(9.15, 0.6, 28), offset = Vector3.new(0, 3.2, 0), Color = Color3.fromRGB(30, 80, 160), Material = Enum.Material.SmoothPlastic },
		{ Size = Vector3.new(2.4, 1, 0.2), offset = Vector3.new(0, 8, -14.05), Color = Color3.fromRGB(255, 160, 40), Material = Enum.Material.Neon },
	}
	local model = spot(parent, "Abandoned Train Car", cf, CFrame.new(0, 3, 4), CFrame.new(0, 6.6, -6), parts)
	model:SetAttribute("Vehicle", true)
	return model
end
SPOT_BUILDERS.dumpster = function(parent, cf)
	return spot(parent, "Dumpster", cf, CFrame.new(0, 1.5, 0), CFrame.new(0, 4.6, -1.4), {
		{ Size = Vector3.new(7, 4.4, 4.2), offset = Vector3.new(0, 2.2, 0), Color = Color3.fromRGB(35, 80, 45), Material = Enum.Material.Metal },
		{ CFrame = CFrame.new(0, 4.6, 0.6) * CFrame.Angles(math.rad(-15), 0, 0), Size = Vector3.new(7.2, 0.25, 4.4), Color = Color3.fromRGB(25, 25, 25) },
	})
end
SPOT_BUILDERS.booth = function(parent, cf)
	return spot(parent, "Ticket Booth", cf, CFrame.new(0, 3, 0.4), CFrame.new(0, 4.6, -1.8), {
		{ Size = Vector3.new(5, 8, 5), offset = Vector3.new(0, 4, 0), Color = Color3.fromRGB(110, 70, 40), Material = Enum.Material.Wood },
		{ Size = Vector3.new(4.2, 2.4, 0.15), offset = Vector3.new(0, 5, -2.55), Color = Color3.fromRGB(40, 50, 60), Material = Enum.Material.Glass, Transparency = 0.3 },
	})
end

-- Room types per map: which hiding spots they get (furnish() adds props by name)
local ROOM_TYPES = {
	{ name = "Office", spots = { "desk", "desk", "cabinet", "locker" }, color = Color3.fromRGB(150, 150, 140) },
	{ name = "Lab", spots = { "cabinet", "crate", "locker" }, color = Color3.fromRGB(170, 175, 175) },
	{ name = "Storage", spots = { "crate", "crate", "cabinet" }, color = Color3.fromRGB(120, 115, 105) },
	{ name = "Restroom", spots = { "stall", "stall", "stall" }, color = Color3.fromRGB(160, 175, 170) },
	{ name = "Break Room", spots = { "fridge", "cabinet", "desk" }, color = Color3.fromRGB(150, 140, 120) },
	{ name = "Server Room", spots = { "rack", "rack", "vent" }, color = Color3.fromRGB(90, 95, 105) },
	{ name = "Locker Room", spots = { "locker", "locker", "locker", "locker" }, color = Color3.fromRGB(130, 135, 140) },
}

local HOSPITAL_ROOMS = {
	{ name = "Patient Room", spots = { "bed", "bed", "cabinet" }, color = Color3.fromRGB(175, 200, 190) },
	{ name = "Operating Room", spots = { "cabinet", "locker", "crate" }, color = Color3.fromRGB(160, 195, 190) },
	{ name = "Morgue", spots = { "morgue", "morgue", "morgue" }, color = Color3.fromRGB(150, 165, 175) },
	{ name = "Pharmacy", spots = { "cabinet", "cabinet", "crate" }, color = Color3.fromRGB(190, 195, 185) },
	{ name = "Waiting Room", spots = { "desk", "locker", "cabinet" }, color = Color3.fromRGB(185, 180, 165) },
	{ name = "Restroom", spots = { "stall", "stall", "stall" }, color = Color3.fromRGB(170, 185, 180) },
	{ name = "Nurse Station", spots = { "desk", "fridge", "cabinet" }, color = Color3.fromRGB(180, 195, 200) },
}

local SUBWAY_ROOMS = {
	{ name = "Ticket Hall", spots = { "booth", "locker", "desk" }, color = Color3.fromRGB(175, 165, 130) },
	{ name = "Maintenance", spots = { "crate", "locker", "vent" }, color = Color3.fromRGB(120, 115, 100) },
	{ name = "Platform Shop", spots = { "fridge", "cabinet", "crate" }, color = Color3.fromRGB(160, 140, 110) },
	{ name = "Restroom", spots = { "stall", "stall" }, color = Color3.fromRGB(150, 160, 150) },
	{ name = "Control Room", spots = { "rack", "desk", "rack" }, color = Color3.fromRGB(95, 100, 110) },
	{ name = "Storage", spots = { "crate", "crate", "locker" }, color = Color3.fromRGB(115, 110, 95) },
}

local CITY_ROOMS = {
	{ name = "Diner", spots = { "desk", "fridge", "stall" }, color = Color3.fromRGB(150, 60, 55) },
	{ name = "Corner Store", spots = { "fridge", "cabinet", "crate" }, color = Color3.fromRGB(120, 90, 70) },
	{ name = "Laundromat", spots = { "cabinet", "locker", "locker" }, color = Color3.fromRGB(110, 120, 140) },
	{ name = "Garage", spots = { "car", "crate", "locker" }, color = Color3.fromRGB(95, 95, 100) },
	{ name = "Apartment Lobby", spots = { "desk", "cabinet", "stall" }, color = Color3.fromRGB(140, 100, 80) },
	{ name = "Pawn Shop", spots = { "cabinet", "crate", "desk" }, color = Color3.fromRGB(130, 110, 75) },
}

-- Maps. Every map is the same idea (rooms as islands in a grid of corridors) dressed differently.
local THEMES = {
	facility = {
		display = "The Research Facility",
		wall = Color3.fromRGB(150, 150, 145), wallMaterial = Enum.Material.Concrete,
		floor = Color3.fromRGB(70, 72, 75), floorMaterial = Enum.Material.Concrete,
		ceiling = Color3.fromRGB(40, 40, 42), outer = Color3.fromRGB(70, 70, 72),
		light = Color3.fromRGB(205, 225, 255),
		rooms = ROOM_TYPES, cell = "Containment", armory = "Weapons Lab",
		hallSpots = { "vent", "vent", "vent", "vent", "vent", "vent" },
	},
	hospital = {
		display = "St. Mercy Hospital",
		wall = Color3.fromRGB(195, 210, 200), wallMaterial = Enum.Material.SmoothPlastic,
		floor = Color3.fromRGB(150, 160, 155), floorMaterial = Enum.Material.Marble,
		ceiling = Color3.fromRGB(170, 175, 170), outer = Color3.fromRGB(120, 130, 125),
		light = Color3.fromRGB(220, 255, 235),
		rooms = HOSPITAL_ROOMS, cell = "Quarantine Ward", armory = "Secure Lab",
		hallSpots = { "bed", "bed", "bed", "locker", "locker", "cabinet" },
	},
	subway = {
		display = "The Subway Tunnels",
		wall = Color3.fromRGB(170, 165, 140), wallMaterial = Enum.Material.Brick,
		floor = Color3.fromRGB(45, 45, 45), floorMaterial = Enum.Material.Concrete,
		ceiling = Color3.fromRGB(28, 28, 30), outer = Color3.fromRGB(55, 50, 45),
		light = Color3.fromRGB(255, 180, 90),
		facility = { hall = 22 },
		rooms = SUBWAY_ROOMS, cell = "Maintenance Cage", armory = "Transit Police Office",
		hallSpots = { "booth", "dumpster", "dumpster" },
		trains = 6, rails = true,
	},
	city = {
		display = "Downtown",
		wall = Color3.fromRGB(140, 90, 75), wallMaterial = Enum.Material.Brick,
		floor = Color3.fromRGB(32, 32, 35), floorMaterial = Enum.Material.Asphalt,
		ceiling = nil, outer = Color3.fromRGB(40, 40, 48),
		light = Color3.fromRGB(255, 200, 120),
		facility = { hall = 26 },
		rooms = CITY_ROOMS, cell = "Military Containment Bunker", armory = "Military Outpost",
		hallSpots = { "dumpster", "dumpster", "dumpster" },
		cars = 14, streets = true, burningCars = 3,
	},
}
Facility.THEMES = THEMES

local function useTheme(name)
	THEME = THEMES[name] or THEMES.facility
	F = setmetatable(THEME.facility or {}, { __index = Config.Facility })
	PITCH = F.room + F.hall
	WIDTH = F.cols * F.room + (F.cols + 1) * F.hall
	DEPTH = F.rows * F.room + (F.rows + 1) * F.hall
	Facility.WIDTH, Facility.DEPTH, Facility.HEIGHT = WIDTH, DEPTH, F.height
	Facility.theme = THEME
end
useTheme("facility")

-- Plain props (also breakable) to make rooms feel lived-in and abandoned
local function prop(parent, name, cframe, size, color, material)
	local p = part({ Name = name, Size = size, CFrame = cframe, Color = color, Material = material or Enum.Material.SmoothPlastic, Parent = parent })
	p:SetAttribute("Breakable", true)
	return p
end

local function furnish(parent, c, roomType, rng)
	local half = F.room / 2
	if roomType.name == "Office" or roomType.name == "Break Room" then
		for _ = 1, 3 do
			local pos = c + Vector3.new(rng:NextNumber(-half + 4, half - 4), 0, rng:NextNumber(-half + 4, half - 4))
			-- toppled office chairs
			prop(parent, "Chair", CFrame.new(pos + Vector3.new(0, 1, 0)) * CFrame.Angles(math.rad(rng:NextInteger(0, 90)), math.rad(rng:NextInteger(0, 360)), 0), Vector3.new(2, 2, 2), Color3.fromRGB(35, 35, 40))
		end
		prop(parent, "FilingCabinet", CFrame.new(c + Vector3.new(half - 1.5, 2.5, -half + 6)), Vector3.new(2, 5, 3), METAL, Enum.Material.Metal)
	elseif roomType.name == "Lab" then
		prop(parent, "LabBench", CFrame.new(c + Vector3.new(0, 1.6, 0)), Vector3.new(14, 3.2, 4), Color3.fromRGB(200, 200, 205), Enum.Material.Metal)
		prop(parent, "Beakers", CFrame.new(c + Vector3.new(2, 3.6, 0)), Vector3.new(3, 0.9, 1), Color3.fromRGB(120, 255, 140), Enum.Material.Neon).Transparency = 0.4
	elseif roomType.name == "Storage" then
		for k = -1, 1 do
			prop(parent, "Shelf", CFrame.new(c + Vector3.new(k * 9, 4, half - 2)), Vector3.new(7, 8, 2), METAL, Enum.Material.Metal)
		end
	elseif roomType.name == "Server Room" then
		for k = -1, 1 do
			prop(parent, "Rack", CFrame.new(c + Vector3.new(-half + 3, 4, k * 7)), Vector3.new(3, 8, 3), Color3.fromRGB(25, 25, 30), Enum.Material.Metal)
		end
	end
	if roomType.name == "Patient Room" then
		prop(parent, "IVStand", CFrame.new(c + Vector3.new(rng:NextNumber(-8, 8), 3, rng:NextNumber(-8, 8))), Vector3.new(0.3, 6, 0.3), Color3.fromRGB(190, 190, 195), Enum.Material.Metal)
		prop(parent, "Curtain", CFrame.new(c + Vector3.new(0, 4.5, 0)), Vector3.new(0.2, 7, 14), Color3.fromRGB(120, 170, 175), Enum.Material.Fabric)
	elseif roomType.name == "Operating Room" then
		prop(parent, "OperatingTable", CFrame.new(c + Vector3.new(0, 1.8, 0)), Vector3.new(4, 3.6, 8), Color3.fromRGB(150, 160, 165), Enum.Material.Metal)
		local lamp = prop(parent, "SurgicalLamp", CFrame.new(c + Vector3.new(0, F.height - 4, 0)), Vector3.new(4, 0.8, 4), Color3.fromRGB(230, 240, 255), Enum.Material.Neon)
		local l = Instance.new("SpotLight")
		l.Face = Enum.NormalId.Bottom
		l.Range = 20
		l.Brightness = 1.5
		l.Angle = 70
		l.Parent = lamp
	elseif roomType.name == "Morgue" then
		local lamp = prop(parent, "ColdLight", CFrame.new(c + Vector3.new(0, F.height - 0.5, 0)), Vector3.new(6, 0.4, 1.4), Color3.fromRGB(150, 200, 255), Enum.Material.Neon)
		local l = Instance.new("PointLight")
		l.Color = Color3.fromRGB(150, 200, 255)
		l.Range = 20
		l.Brightness = 0.6
		l.Parent = lamp
	elseif roomType.name == "Waiting Room" then
		for k = -2, 2 do
			prop(parent, "Seats", CFrame.new(c + Vector3.new(k * 5, 1.2, 4)), Vector3.new(4, 2.4, 2), Color3.fromRGB(60, 90, 130), Enum.Material.Fabric)
		end
	elseif roomType.name == "Pharmacy" or roomType.name == "Corner Store" or roomType.name == "Pawn Shop" then
		for k = -1, 1 do
			prop(parent, "Shelf", CFrame.new(c + Vector3.new(k * 9, 3.5, 0)), Vector3.new(2, 7, 12), METAL, Enum.Material.Metal)
		end
	elseif roomType.name == "Ticket Hall" then
		for k = -2, 2 do
			prop(parent, "Turnstile", CFrame.new(c + Vector3.new(k * 4, 1.6, 6)), Vector3.new(0.6, 3.2, 3), Color3.fromRGB(150, 150, 155), Enum.Material.Metal)
		end
	elseif roomType.name == "Diner" then
		prop(parent, "Counter", CFrame.new(c + Vector3.new(0, 1.8, -8)), Vector3.new(20, 3.6, 3), Color3.fromRGB(180, 40, 40), Enum.Material.SmoothPlastic)
		for k = -2, 2 do
			prop(parent, "Stool", CFrame.new(c + Vector3.new(k * 4, 1.3, -5)), Vector3.new(1.4, 2.6, 1.4), Color3.fromRGB(200, 200, 205), Enum.Material.Metal)
		end
	elseif roomType.name == "Laundromat" then
		for k = -2, 2 do
			prop(parent, "Washer", CFrame.new(c + Vector3.new(k * 5, 2, -12)), Vector3.new(4, 4, 4), WHITE, Enum.Material.SmoothPlastic)
		end
	end
	-- scattered papers and debris
	for _ = 1, 4 do
		local pos = c + Vector3.new(rng:NextNumber(-half + 2, half - 2), 0.05, rng:NextNumber(-half + 2, half - 2))
		local paper = part({ Name = "Paper", Size = Vector3.new(1, 0.05, 1.3), CFrame = CFrame.new(pos) * CFrame.Angles(0, rng:NextNumber(0, 6), 0), Color = Color3.fromRGB(220, 220, 210), CanCollide = false, Parent = parent })
		paper:SetAttribute("Breakable", true)
	end
end

---------------------------------------------------------------------------
-- Build
---------------------------------------------------------------------------
function Facility.clear()
	local old = Workspace:FindFirstChild("Facility")
	if old then
		old:Destroy()
	end
end

-- The armory: unbreakable walls (giants can't get in), one low vault door that opens once the
-- civilians bring enough keycards, and the cannon on a pedestal inside
local function buildArmory(parent, c, side, info)
	local half = F.room / 2
	local corners = {
		Vector3.new(c.X - half, 0, c.Z - half), Vector3.new(c.X + half, 0, c.Z - half),
		Vector3.new(c.X + half, 0, c.Z + half), Vector3.new(c.X - half, 0, c.Z + half),
	}
	local steel = Color3.fromRGB(70, 75, 82)
	local doorWidth, doorHeight = 8, 8.5 -- people fit; a giant doesn't
	for k = 1, 4 do
		local a, b = corners[k], corners[k % 4 + 1]
		local mid = (a + b) / 2
		local alongX = math.abs(b.X - a.X) > 1
		local function slab(center, length, y0, y1)
			local size = if alongX then Vector3.new(length, y1 - y0, 2) else Vector3.new(2, y1 - y0, length)
			part({ Name = "VaultWall", Size = size, Position = center + Vector3.new(0, (y0 + y1) / 2, 0), Color = steel, Material = Enum.Material.DiamondPlate, Parent = parent })
		end
		if k == side then
			local dir = (b - a).Unit
			local seg = (F.room - doorWidth) / 2
			slab(a + dir * seg / 2, seg, 0, F.height)
			slab(b - dir * seg / 2, seg, 0, F.height)
			slab(mid, doorWidth, doorHeight, F.height)
			local door = part({ Name = "VaultDoor", Size = if alongX then Vector3.new(doorWidth, doorHeight, 1.4) else Vector3.new(1.4, doorHeight, doorWidth), Position = mid + Vector3.new(0, doorHeight / 2, 0), Color = Color3.fromRGB(120, 125, 130), Material = Enum.Material.Metal, Parent = parent })
			local stripe = part({ Name = "VaultLight", Size = if alongX then Vector3.new(doorWidth, 0.4, 1.6) else Vector3.new(1.6, 0.4, doorWidth), Position = mid + Vector3.new(0, doorHeight + 0.4, 0), Color = Color3.fromRGB(255, 40, 30), Material = Enum.Material.Neon, CanCollide = false, Parent = parent })
			local glow = Instance.new("PointLight")
			glow.Color = stripe.Color
			glow.Range = 18
			glow.Brightness = 1.2
			glow.Parent = stripe
			-- keycard reader beside the door, facing out
			local outward = (mid - c) * Vector3.new(1, 0, 1)
			outward = outward.Unit
			local readerPos = mid + outward * 1.3 + (if alongX then Vector3.new(doorWidth / 2 + 2, 0, 0) else Vector3.new(0, 0, doorWidth / 2 + 2)) + Vector3.new(0, 4.5, 0)
			local reader = part({ Name = "KeycardReader", Size = Vector3.new(2.4, 3, 2.4), CFrame = CFrame.lookAt(readerPos, readerPos + outward), Color = Color3.fromRGB(30, 30, 35), Material = Enum.Material.Metal, Parent = parent })
			local gui = Instance.new("SurfaceGui")
			gui.Face = Enum.NormalId.Front
			gui.LightInfluence = 0
			gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
			gui.PixelsPerStud = 40
			local text = Instance.new("TextLabel")
			text.Name = "Text"
			text.Size = UDim2.fromScale(1, 1)
			text.BackgroundColor3 = Color3.fromRGB(10, 10, 12)
			text.Font = Enum.Font.GothamBlack
			text.TextScaled = true
			text.TextColor3 = Color3.fromRGB(255, 70, 60)
			text.Text = "🔒"
			text.Parent = gui
			gui.Parent = reader
			local prompt = Instance.new("ProximityPrompt")
			prompt.Name = "VaultPrompt"
			prompt.ActionText = "Open Vault"
			prompt.ObjectText = THEME.armory
			prompt.HoldDuration = 1
			prompt.MaxActivationDistance = 10
			prompt.RequiresLineOfSight = false
			prompt.Parent = door
			info.armory = { door = door, light = stripe, readerText = text, center = c, outward = outward, entrance = mid + outward * 6 }
		else
			slab(mid, F.room + 2, 0, F.height)
		end
	end
	part({ Name = "VaultCeiling", Size = Vector3.new(F.room + 2, 1, F.room + 2), Position = c + Vector3.new(0, F.height, 0), Color = steel, Material = Enum.Material.DiamondPlate, Parent = parent })
	-- pedestal and the cannon on display
	local pedestal = part({ Name = "WeaponPedestal", Size = Vector3.new(4, 3.4, 4), Position = c + Vector3.new(0, 1.7, 0), Color = Color3.fromRGB(40, 40, 46), Material = Enum.Material.Metal, Parent = parent })
	local lamp = part({ Name = "ArmoryLight", Size = Vector3.new(6, 0.4, 6), Position = c + Vector3.new(0, F.height - 0.6, 0), Color = Color3.fromRGB(150, 255, 170), Material = Enum.Material.Neon, CanCollide = false, Parent = parent })
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(150, 255, 170)
	light.Range = 30
	light.Brightness = 1.6
	light.Parent = lamp
	info.armory.pedestal = pedestal
	info.armory.weaponCFrame = CFrame.new(c + Vector3.new(0, 4.4, 0))
end

-- Streets, sidewalks, parked cars, trains, rails: whatever the map puts in its corridors
local function hallSegments()
	-- the middle of every corridor stretch between two intersections: { position, alongX }
	local list = {}
	for k = 0, F.cols do
		local x = -WIDTH / 2 + F.hall / 2 + k * PITCH
		for j = 1, F.rows do
			table.insert(list, { Vector3.new(x, 0, roomCenter(1, j).Z), false })
		end
	end
	for k = 0, F.rows do
		local z = -DEPTH / 2 + F.hall / 2 + k * PITCH
		for i = 1, F.cols do
			table.insert(list, { Vector3.new(roomCenter(i, 1).X, 0, z), true })
		end
	end
	return list
end

local function dressCorridors(root, spots, decor, lights, rng, info, armoryCenter)
	local segments = hallSegments()
	-- shuffle so vehicles land in random places
	for i = #segments, 2, -1 do
		local j = rng:NextInteger(1, i)
		segments[i], segments[j] = segments[j], segments[i]
	end
	local function nearArmory(pos)
		return armoryCenter and (pos - armoryCenter).Magnitude < F.room * 0.9
	end
	local used = 0
	local function nextSegment()
		while used < #segments do
			used += 1
			local seg = segments[used]
			if not nearArmory(seg[1]) then
				return seg
			end
		end
		return nil
	end

	if THEME.rails then
		for k = 0, F.cols do
			local x = -WIDTH / 2 + F.hall / 2 + k * PITCH
			for _, dx in ipairs({ -2.4, 2.4 }) do
				part({ Name = "Rail", Size = Vector3.new(0.4, 0.3, DEPTH), Position = Vector3.new(x + dx, 0.15, 0), Color = Color3.fromRGB(110, 100, 90), Material = Enum.Material.Metal, CanCollide = false, Parent = decor })
			end
		end
		for k = 0, F.rows do
			local z = -DEPTH / 2 + F.hall / 2 + k * PITCH
			for _, dz in ipairs({ -2.4, 2.4 }) do
				part({ Name = "Rail", Size = Vector3.new(WIDTH, 0.3, 0.4), Position = Vector3.new(0, 0.15, z + dz), Color = Color3.fromRGB(110, 100, 90), Material = Enum.Material.Metal, CanCollide = false, Parent = decor })
			end
		end
	end
	for _ = 1, THEME.trains or 0 do
		local seg = nextSegment()
		if seg then
			local cf = CFrame.new(seg[1]) * (if seg[2] then CFrame.Angles(0, math.pi / 2, 0) else CFrame.identity)
			table.insert(info.spots, SPOT_BUILDERS.train(spots, cf))
		end
	end

	if THEME.streets then
		-- sidewalks around every building, a dashed center line and crosswalk stripes
		for i = 1, F.cols do
			for j = 1, F.rows do
				local c = roomCenter(i, j)
				-- a 4-stud sidewalk ring around the outside of the building
				local h = F.room / 2 + 2
				for _, strip in ipairs({
					{ Vector3.new(F.room + 8, 0.5, 4), Vector3.new(0, 0.25, -h) },
					{ Vector3.new(F.room + 8, 0.5, 4), Vector3.new(0, 0.25, h) },
					{ Vector3.new(4, 0.5, F.room), Vector3.new(-h, 0.25, 0) },
					{ Vector3.new(4, 0.5, F.room), Vector3.new(h, 0.25, 0) },
				}) do
					part({ Name = "Sidewalk", Size = strip[1], Position = c + strip[2], Color = Color3.fromRGB(95, 95, 98), Material = Enum.Material.Concrete, Parent = decor })
				end
				-- a streetlight at two corners of each block
				for _, corner in ipairs({ Vector3.new(-1, 0, -1), Vector3.new(1, 0, 1) }) do
					local base = c + corner * (F.room / 2 + 2.5)
					local pole = part({ Name = "StreetlightPole", Size = Vector3.new(0.6, 18, 0.6), Position = base + Vector3.new(0, 9, 0), Color = Color3.fromRGB(40, 45, 45), Material = Enum.Material.Metal, Parent = decor })
					pole:SetAttribute("Breakable", true)
					local lamp = part({ Name = "HallLight", Size = Vector3.new(2.4, 0.6, 1.4), Position = base + Vector3.new(0, 18, 0) + corner * 1.2, Color = THEME.light, Material = Enum.Material.Neon, CanCollide = false, Parent = lights })
					local glow = Instance.new("PointLight")
					glow.Color = THEME.light
					glow.Range = F.hallLightRange
					glow.Brightness = F.hallLightBrightness
					glow.Shadows = true
					glow.Parent = lamp
					lamp:SetAttribute("Breakable", true)
				end
			end
		end
		for _, seg in ipairs(segments) do
			local p, alongX = seg[1], seg[2]
			for k = -2, 2 do
				local offset = if alongX then Vector3.new(k * 7, 0.05, 0) else Vector3.new(0, 0.05, k * 7)
				part({ Name = "LaneLine", Size = if alongX then Vector3.new(4, 0.1, 0.4) else Vector3.new(0.4, 0.1, 4), Position = p + offset, Color = Color3.fromRGB(230, 190, 40), Material = Enum.Material.SmoothPlastic, CanCollide = false, Parent = decor })
			end
		end
		-- parked cars along the curbs, some of them burning
		local burning = THEME.burningCars or 0
		for _ = 1, THEME.cars or 0 do
			local seg = nextSegment()
			if seg then
				local side = if rng:NextNumber() < 0.5 then -1 else 1
				local offset = side * (F.hall / 2 - 7.5)
				local pos = seg[1] + (if seg[2] then Vector3.new(rng:NextNumber(-8, 8), 0, offset) else Vector3.new(offset, 0, rng:NextNumber(-8, 8)))
				local cf = CFrame.new(pos) * CFrame.Angles(0, (if seg[2] then math.pi / 2 else 0) + (if rng:NextNumber() < 0.5 then math.pi else 0), 0)
				local car = SPOT_BUILDERS.car(spots, cf)
				table.insert(info.spots, car)
				if burning > 0 then
					burning -= 1
					car:SetAttribute("Burning", true)
					local fire = Instance.new("Fire")
					fire.Size = 9
					fire.Heat = 12
					fire.Parent = car.PrimaryPart
					local glow = Instance.new("PointLight")
					glow.Color = Color3.fromRGB(255, 120, 40)
					glow.Range = 26
					glow.Brightness = 2
					glow.Parent = car.PrimaryPart
					car.PrimaryPart:FindFirstChild("HidePrompt"):Destroy() -- nobody hides in a burning car
				end
			end
		end
	end

	-- loose corridor hiding spots (vents in the lab, beds in the hospital, dumpsters outside...)
	for _, kind in ipairs(THEME.hallSpots or {}) do
		local seg = nextSegment()
		if seg then
			local side = if rng:NextNumber() < 0.5 then -1 else 1
			local offset = side * (F.hall / 2 - 2.6)
			local pos = seg[1] + (if seg[2] then Vector3.new(rng:NextNumber(-10, 10), 0, offset) else Vector3.new(offset, 0, rng:NextNumber(-10, 10)))
			-- face into the corridor
			local facing = if seg[2] then (if side < 0 then 0 else math.pi) else (if side < 0 then -math.pi / 2 else math.pi / 2)
			if THEME.streets then
				pos += (if seg[2] then Vector3.new(0, 0.5, 0) else Vector3.new(0, 0.5, 0))
			end
			table.insert(info.spots, SPOT_BUILDERS[kind](spots, CFrame.new(pos) * CFrame.Angles(0, facing, 0)))
		end
	end
end

function Facility.build(seed, mapName)
	Facility.clear()
	useTheme(mapName or "facility")
	local rng = Random.new(seed or os.time())
	local root = Instance.new("Folder")
	root.Name = "Facility"
	local walls = Instance.new("Folder")
	walls.Name = "Walls"
	walls.Parent = root
	local spots = Instance.new("Folder")
	spots.Name = "HidingSpots"
	spots.Parent = root
	local decor = Instance.new("Folder")
	decor.Name = "Decor"
	decor.Parent = root
	local lights = Instance.new("Folder")
	lights.Name = "Lights"
	lights.Parent = root
	local debris = Instance.new("Folder")
	debris.Name = "Debris"
	debris.Parent = root
	local vault = Instance.new("Folder")
	vault.Name = "Armory"
	vault.Parent = root

	-- Shell: floor, ceiling (not outdoors), outer walls (unbreakable)
	part({ Name = "Floor", Size = Vector3.new(WIDTH + 4, 1, DEPTH + 4), Position = Vector3.new(0, -0.5, 0), Color = THEME.floor, Material = THEME.floorMaterial, Parent = root })
	if THEME.ceiling then
		part({ Name = "Ceiling", Size = Vector3.new(WIDTH + 4, 2, DEPTH + 4), Position = Vector3.new(0, F.height + 1, 0), Color = THEME.ceiling, Material = Enum.Material.Concrete, Parent = root })
	end
	local outerHeight = if THEME.streets then 80 else F.height
	for _, spec in ipairs({
		{ Vector3.new(WIDTH + 4, outerHeight, 2), Vector3.new(0, outerHeight / 2, -DEPTH / 2 - 1) },
		{ Vector3.new(WIDTH + 4, outerHeight, 2), Vector3.new(0, outerHeight / 2, DEPTH / 2 + 1) },
		{ Vector3.new(2, outerHeight, DEPTH + 4), Vector3.new(-WIDTH / 2 - 1, outerHeight / 2, 0) },
		{ Vector3.new(2, outerHeight, DEPTH + 4), Vector3.new(WIDTH / 2 + 1, outerHeight / 2, 0) },
	}) do
		part({ Name = "OuterWall", Size = spec[1], Position = spec[2], Color = THEME.outer, Material = if THEME.streets then Enum.Material.Brick else Enum.Material.Concrete, Parent = root })
	end
	if THEME.streets then
		-- tall buildings all around: a few lit windows in the dark skyline
		for _ = 1, 140 do
			local onX = rng:NextNumber() < 0.5
			local sign = if rng:NextNumber() < 0.5 then -1 else 1
			local pos = if onX
				then Vector3.new(rng:NextNumber(-WIDTH / 2 + 6, WIDTH / 2 - 6), rng:NextNumber(20, 74), sign * (DEPTH / 2 - 0.05))
				else Vector3.new(sign * (WIDTH / 2 - 0.05), rng:NextNumber(20, 74), rng:NextNumber(-DEPTH / 2 + 6, DEPTH / 2 - 6))
			local lit = rng:NextNumber() < 0.35
			part({ Name = "Window", Size = if onX then Vector3.new(3, 4, 0.3) else Vector3.new(0.3, 4, 3), Position = pos, Color = if lit then Color3.fromRGB(255, 210, 140) else Color3.fromRGB(20, 25, 35), Material = if lit then Enum.Material.Neon else Enum.Material.Glass, CanCollide = false, Parent = decor })
		end
	elseif THEME.ceiling then
		-- rain-streaked windows (lightning flashes through them, client-side)
		for x = -WIDTH / 2 + 20, WIDTH / 2 - 20, 40 do
			for _, z in ipairs({ -DEPTH / 2 - 0.05, DEPTH / 2 + 0.05 }) do
				local w = part({ Name = "Window", Size = Vector3.new(10, 6, 0.3), Position = Vector3.new(x, 16, z), Color = Color3.fromRGB(30, 40, 60), Material = Enum.Material.Glass, Transparency = 0.2, CanCollide = false, Parent = lights })
				w:SetAttribute("Lightning", true)
			end
		end
	end

	-- Rooms
	local info = { spots = {}, rooms = {}, civilianSpawns = {}, keycardSpots = {}, adrenalineSpots = {}, map = THEME.display }
	local cellI, cellJ = 1, 1 -- containment cell in one corner, the armory in the opposite half
	local armI, armJ = rng:NextInteger(math.ceil(F.cols / 2) + 1, F.cols), rng:NextInteger(1, F.rows)
	local armoryCenter = roomCenter(armI, armJ)
	for i = 1, F.cols do
		for j = 1, F.rows do
			local c = roomCenter(i, j)
			local half = F.room / 2
			local isCell = i == cellI and j == cellJ
			local isArmory = i == armI and j == armJ
			if isArmory then
				buildArmory(vault, c, rng:NextInteger(1, 4), info)
				table.insert(info.rooms, { center = c, type = THEME.armory })
				continue
			end
			local roomType = if isCell then { name = THEME.cell, spots = {}, color = Color3.fromRGB(60, 65, 70) } else THEME.rooms[rng:NextInteger(1, #THEME.rooms)]
			local roomFolder = Instance.new("Folder")
			roomFolder.Name = roomType.name .. " " .. i .. "-" .. j
			roomFolder.Parent = walls
			if THEME.streets and not isCell then
				-- buildings have their own roofs (it's open sky outside)
				local roof = part({ Name = "Roof", Size = Vector3.new(F.room, 1, F.room), Position = c + Vector3.new(0, F.height + 0.5, 0), Color = Color3.fromRGB(45, 45, 50), Material = Enum.Material.Concrete, Parent = roomFolder })
				roof:SetAttribute("Breakable", true)
			elseif THEME.streets and isCell then
				part({ Name = "Roof", Size = Vector3.new(F.room, 1, F.room), Position = c + Vector3.new(0, F.height + 0.5, 0), Color = Color3.fromRGB(45, 50, 45), Material = Enum.Material.DiamondPlate, Parent = root })
			end
			local doorSides = {}
			-- door offsets sit on panel column centers (never the corner columns)
			local function doorOffset()
				return (rng:NextInteger(1, math.floor(F.room / F.panel) - 2) + 0.5) * F.panel
			end
			doorSides[rng:NextInteger(1, 4)] = { doorOffset() }
			if rng:NextNumber() < 0.5 then
				doorSides[rng:NextInteger(1, 4)] = { doorOffset() }
			end
			if isCell then
				doorSides = {}
			end
			local corners = {
				Vector3.new(c.X - half, 0, c.Z - half), Vector3.new(c.X + half, 0, c.Z - half),
				Vector3.new(c.X + half, 0, c.Z + half), Vector3.new(c.X - half, 0, c.Z + half),
			}
			for side = 1, 4 do
				local a, b = corners[side], corners[side % 4 + 1]
				if isCell and side == 2 then
					-- the east wall is a huge reinforced glass window that shatters at hunt start
					local glass = part({ Name = "ContainmentGlass", Size = Vector3.new(1.5, F.height, F.room), Position = (a + b) / 2 + Vector3.new(0, F.height / 2, 0), Color = Color3.fromRGB(150, 200, 230), Material = Enum.Material.Glass, Transparency = 0.5, Parent = root })
					info.containmentGlass = glass
				else
					panelWall(roomFolder, a, b, doorSides[side], roomType.color)
				end
			end
			-- hiding spots placed along the inside of the walls, facing into the room
			local used = {}
			for _, kind in ipairs(roomType.spots) do
				local tries = 0
				while tries < 8 do
					tries += 1
					local side = rng:NextInteger(1, 4)
					local along = rng:NextInteger(-2, 2) * 6
					local key = side .. ":" .. along
					local blocksDoor = false
					for _, d in ipairs(doorSides[side] or {}) do
						if math.abs((d - F.room / 2) - along) < (if kind == "car" then 9 else 5) then
							blocksDoor = true
						end
					end
					if not used[key] and not blocksDoor then
						used[key] = true
						local inset = half - (if kind == "car" then 4 else 2.4)
						local placements = {
							CFrame.new(c + Vector3.new(along, 0, -inset)) * CFrame.Angles(0, math.pi, 0), -- north wall, facing +Z
							CFrame.new(c + Vector3.new(inset, 0, along)) * CFrame.Angles(0, math.pi / 2, 0), -- east wall, facing -X
							CFrame.new(c + Vector3.new(along, 0, inset)), -- south wall, facing -Z
							CFrame.new(c + Vector3.new(-inset, 0, along)) * CFrame.Angles(0, -math.pi / 2, 0), -- west wall, facing +X
						}
						local placement = placements[side]
						if kind == "car" then
							placement *= CFrame.Angles(0, math.pi / 2, 0) -- park along the wall
						end
						local model = SPOT_BUILDERS[kind](spots, placement)
						table.insert(info.spots, model)
						break
					end
				end
			end
			furnish(decor, c, roomType, rng)
			if not isCell then
				-- keycards can turn up anywhere in a room
				table.insert(info.keycardSpots, c + Vector3.new(rng:NextNumber(-half + 6, half - 6), 0, rng:NextNumber(-half + 6, half - 6)))
			end
			-- sometimes a flickering red emergency light
			if rng:NextNumber() < 0.45 then
				local e = part({ Name = "EmergencyLight", Size = Vector3.new(1.4, 0.6, 1.4), Position = c + Vector3.new(rng:NextNumber(-10, 10), F.height - 0.4, rng:NextNumber(-10, 10)), Color = Color3.fromRGB(255, 40, 30), Material = Enum.Material.Neon, CanCollide = false, Parent = lights })
				local glow = Instance.new("PointLight")
				glow.Color = Color3.fromRGB(255, 40, 30)
				glow.Range = 22
				glow.Brightness = 0.8
				glow.Parent = e
				e:SetAttribute("Breakable", true)
			end
			table.insert(info.rooms, { center = c, type = roomType.name })
			if isCell then
				info.abominationSpawn = c + Vector3.new(0, 4, 0)
			end
		end
	end

	dressCorridors(root, spots, decor, lights, rng, info, armoryCenter)

	-- Corridor lights (indoor maps): flickering tubes at the ends of every corridor and over
	-- some intersections. Outdoors the streetlights do this job.
	if not THEME.streets then
		local function tube(position, alongX)
			local t = part({ Name = "HallLight", Size = if alongX then Vector3.new(7, 0.5, 1.4) else Vector3.new(1.4, 0.5, 7), Position = position + Vector3.new(0, F.height - 0.6, 0), Color = THEME.light, Material = Enum.Material.Neon, CanCollide = false, Parent = lights })
			part({ Name = "TubeHousing", Size = (if alongX then Vector3.new(7.6, 0.4, 2) else Vector3.new(2, 0.4, 7.6)), Position = position + Vector3.new(0, F.height - 0.2, 0), Color = Color3.fromRGB(60, 60, 62), Material = Enum.Material.Metal, CanCollide = false, Parent = lights })
			local glow = Instance.new("PointLight")
			glow.Color = THEME.light
			glow.Range = F.hallLightRange
			glow.Brightness = F.hallLightBrightness
			glow.Shadows = true
			glow.Parent = t
			t:SetAttribute("Breakable", true)
		end
		for k = 0, F.cols do
			local x = -WIDTH / 2 + F.hall / 2 + k * PITCH
			tube(Vector3.new(x, 0, -DEPTH / 2 + 5), false)
			tube(Vector3.new(x, 0, DEPTH / 2 - 5), false)
		end
		for k = 0, F.rows do
			local z = -DEPTH / 2 + F.hall / 2 + k * PITCH
			tube(Vector3.new(-WIDTH / 2 + 5, 0, z), true)
			tube(Vector3.new(WIDTH / 2 - 5, 0, z), true)
		end
		for _ = 1, F.hallLightsMiddle do
			local x = -WIDTH / 2 + F.hall / 2 + rng:NextInteger(1, F.cols - 1) * PITCH
			local z = -DEPTH / 2 + F.hall / 2 + rng:NextInteger(1, F.rows - 1) * PITCH
			tube(Vector3.new(x, 0, z), rng:NextNumber() < 0.5)
		end
	end

	-- Corridor emergency lights
	for _ = 1, 10 do
		local p = hallPoint(rng)
		local e = part({ Name = "EmergencyLight", Size = Vector3.new(1.4, 0.6, 1.4), Position = p + Vector3.new(0, (if THEME.ceiling then F.height else 14) - 0.4, 0), Color = Color3.fromRGB(255, 40, 30), Material = Enum.Material.Neon, CanCollide = false, Parent = lights })
		local glow = Instance.new("PointLight")
		glow.Color = Color3.fromRGB(255, 40, 30)
		glow.Range = 26
		glow.Brightness = 0.7
		glow.Parent = e
	end

	-- Spawns: civilians around the corridors, Hulk in the far corner; adrenaline spots in corridors
	for _ = 1, 16 do
		table.insert(info.civilianSpawns, hallPoint(rng) + Vector3.new(0, 3, 0))
	end
	for _ = 1, 14 do
		table.insert(info.adrenalineSpots, hallPoint(rng))
	end
	info.hulkSpawn = Vector3.new(WIDTH / 2 - F.hall / 2, 6, DEPTH / 2 - F.hall / 2)
	info.width, info.depth, info.height = WIDTH, DEPTH, F.height
	info.outdoor = THEME.ceiling == nil
	info.armoryName = THEME.armory
	info.root = root
	info.debris = debris
	root.Parent = Workspace
	Facility.info = info
	return info
end

---------------------------------------------------------------------------
-- Lobby: a lit, safe room high above the facility
---------------------------------------------------------------------------
function Facility.buildLobby()
	if Workspace:FindFirstChild("Lobby") then
		return
	end
	local lobby = Instance.new("Folder")
	lobby.Name = "Lobby"
	local o = LOBBY
	part({ Name = "LobbyFloor", Size = Vector3.new(90, 1, 70), Position = o + Vector3.new(0, -0.5, 0), Color = Color3.fromRGB(40, 42, 50), Material = Enum.Material.Marble, Parent = lobby })
	part({ Name = "LobbyCeiling", Size = Vector3.new(90, 1, 70), Position = o + Vector3.new(0, 24.5, 0), Color = Color3.fromRGB(25, 25, 30), Parent = lobby })
	for _, spec in ipairs({
		{ Vector3.new(90, 24, 1), Vector3.new(0, 12, -35) }, { Vector3.new(90, 24, 1), Vector3.new(0, 12, 35) },
		{ Vector3.new(1, 24, 70), Vector3.new(-45, 12, 0) }, { Vector3.new(1, 24, 70), Vector3.new(45, 12, 0) },
	}) do
		part({ Name = "LobbyWall", Size = spec[1], Position = o + spec[2], Color = Color3.fromRGB(30, 32, 40), Parent = lobby })
	end
	for x = -30, 30, 20 do
		for z = -20, 20, 20 do
			local lamp = part({ Name = "LobbyLight", Size = Vector3.new(6, 0.3, 6), Position = o + Vector3.new(x, 24, z), Color = Color3.fromRGB(255, 240, 220), Material = Enum.Material.Neon, CanCollide = false, Parent = lobby })
			local light = Instance.new("PointLight")
			light.Range = 30
			light.Brightness = 2
			light.Parent = lamp
		end
	end
	-- Green and red accent strips (team colors)
	part({ Name = "Strip", Size = Vector3.new(90, 0.4, 0.4), Position = o + Vector3.new(0, 0.2, -34.6), Color = Color3.fromRGB(90, 200, 60), Material = Enum.Material.Neon, Parent = lobby })
	part({ Name = "Strip", Size = Vector3.new(90, 0.4, 0.4), Position = o + Vector3.new(0, 0.2, 34.6), Color = Color3.fromRGB(200, 50, 40), Material = Enum.Material.Neon, Parent = lobby })

	-- Costume shop booth
	local booth = part({ Name = "CostumeShop", Size = Vector3.new(14, 8, 4), Position = o + Vector3.new(0, 4, -28), Color = Color3.fromRGB(60, 40, 90), Material = Enum.Material.SmoothPlastic, Parent = lobby })
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "ShopPrompt"
	prompt.ActionText = "Costume Shop"
	prompt.ObjectText = "Spend your coins"
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = booth
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Back
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 30
	gui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 220, 90)
	label.Text = "🎭 COSTUME SHOP"
	label.Parent = gui
	gui.Parent = booth

	-- Big status screen
	local screen = part({ Name = "StatusScreen", Size = Vector3.new(40, 12, 1), Position = o + Vector3.new(0, 14, 34), Color = Color3.fromRGB(10, 10, 14), Parent = lobby })
	local sgui = Instance.new("SurfaceGui")
	sgui.Name = "Status"
	sgui.Face = Enum.NormalId.Front
	sgui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sgui.PixelsPerStud = 20
	sgui.LightInfluence = 0
	local text = Instance.new("TextLabel")
	text.Name = "Text"
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.GothamBlack
	text.TextScaled = true
	text.TextColor3 = Color3.fromRGB(230, 230, 235)
	text.Text = Config.Names.game
	text.Parent = sgui
	sgui.Parent = screen

	-- All-time wins leaderboard on the west wall (filled in by Main)
	local board = part({ Name = "Leaderboard", Size = Vector3.new(1, 18, 24), Position = o + Vector3.new(-44, 12, 0), Color = Color3.fromRGB(12, 12, 16), Parent = lobby })
	local bgui = Instance.new("SurfaceGui")
	bgui.Face = Enum.NormalId.Right
	bgui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	bgui.PixelsPerStud = 25
	bgui.LightInfluence = 0
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = bgui
	Facility.leaderboardRows = {}
	for k = 0, 10 do
		local row = Instance.new("TextLabel")
		row.LayoutOrder = k
		row.Size = UDim2.new(1, 0, 1 / 11, 0)
		row.BackgroundTransparency = 1
		row.Font = if k == 0 then Enum.Font.GothamBlack else Enum.Font.GothamBold
		row.TextScaled = true
		row.TextColor3 = if k == 0 then Color3.fromRGB(255, 210, 80) else Color3.fromRGB(230, 230, 235)
		row.Text = if k == 0 then "🏆 MOST WINS" else ""
		row.Parent = bgui
		if k > 0 then
			Facility.leaderboardRows[k] = row
		end
	end
	bgui.Parent = board

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "LobbySpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(12, 1, 12)
	spawn.Position = o + Vector3.new(0, 0.5, 10)
	spawn.Color = Color3.fromRGB(90, 200, 60)
	spawn.Material = Enum.Material.Neon
	spawn.Duration = 0
	spawn.Parent = lobby

	lobby.Parent = Workspace
	Facility.statusText = text
end

function Facility.setStatus(text)
	if Facility.statusText then
		Facility.statusText.Text = text
	end
end

function Facility.lobbySpawn()
	return CFrame.new(LOBBY + Vector3.new(math.random(-20, 20), 4, math.random(-10, 20)))
end

return Facility
