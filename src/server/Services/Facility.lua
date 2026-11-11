-- Builds the dark research facility (rebuilt fresh every round) and the lit lobby.
-- Every wall inside the building is made of breakable panels; hiding spots are models with
-- prompts. Layout: a grid of rooms, each an island surrounded by hallways.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)

local Facility = {}

local F = Config.Facility
local PITCH = F.room + F.hall
local WIDTH = F.cols * F.room + (F.cols + 1) * F.hall
local DEPTH = F.rows * F.room + (F.rows + 1) * F.hall
Facility.WIDTH, Facility.DEPTH = WIDTH, DEPTH

local LOBBY = Vector3.new(0, 400, 0)
Facility.LOBBY = LOBBY

local WALL = Color3.fromRGB(150, 150, 145)
local FLOOR = Color3.fromRGB(70, 72, 75)

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
			local p = part({ Name = "Panel", Size = size, Position = mid + Vector3.new(0, r[1] + h / 2, 0), Color = color or WALL, Material = Enum.Material.Concrete, Parent = parent })
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

-- Room types: which hiding spots and props they get
local ROOM_TYPES = {
	{ name = "Office", spots = { "desk", "desk", "cabinet", "locker" }, color = Color3.fromRGB(150, 150, 140) },
	{ name = "Lab", spots = { "cabinet", "crate", "locker" }, color = Color3.fromRGB(170, 175, 175) },
	{ name = "Storage", spots = { "crate", "crate", "cabinet" }, color = Color3.fromRGB(120, 115, 105) },
	{ name = "Restroom", spots = { "stall", "stall", "stall" }, color = Color3.fromRGB(160, 175, 170) },
	{ name = "Break Room", spots = { "fridge", "cabinet", "desk" }, color = Color3.fromRGB(150, 140, 120) },
	{ name = "Server Room", spots = { "rack", "rack", "vent" }, color = Color3.fromRGB(90, 95, 105) },
	{ name = "Locker Room", spots = { "locker", "locker", "locker", "locker" }, color = Color3.fromRGB(130, 135, 140) },
}

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

function Facility.build(seed)
	Facility.clear()
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

	-- Shell: floor, ceiling, outer walls (unbreakable) with dark windows
	part({ Name = "Floor", Size = Vector3.new(WIDTH + 4, 1, DEPTH + 4), Position = Vector3.new(0, -0.5, 0), Color = FLOOR, Material = Enum.Material.Concrete, Parent = root })
	part({ Name = "Ceiling", Size = Vector3.new(WIDTH + 4, 2, DEPTH + 4), Position = Vector3.new(0, F.height + 1, 0), Color = Color3.fromRGB(40, 40, 42), Material = Enum.Material.Concrete, Parent = root })
	for _, spec in ipairs({
		{ Vector3.new(WIDTH + 4, F.height, 2), Vector3.new(0, F.height / 2, -DEPTH / 2 - 1) },
		{ Vector3.new(WIDTH + 4, F.height, 2), Vector3.new(0, F.height / 2, DEPTH / 2 + 1) },
		{ Vector3.new(2, F.height, DEPTH + 4), Vector3.new(-WIDTH / 2 - 1, F.height / 2, 0) },
		{ Vector3.new(2, F.height, DEPTH + 4), Vector3.new(WIDTH / 2 + 1, F.height / 2, 0) },
	}) do
		part({ Name = "OuterWall", Size = spec[1], Position = spec[2], Color = Color3.fromRGB(70, 70, 72), Material = Enum.Material.Concrete, Parent = root })
	end
	-- Rain-streaked windows on the long outer walls (lightning flashes through them, client-side)
	for x = -WIDTH / 2 + 20, WIDTH / 2 - 20, 40 do
		for _, z in ipairs({ -DEPTH / 2 - 0.05, DEPTH / 2 + 0.05 }) do
			local w = part({ Name = "Window", Size = Vector3.new(10, 6, 0.3), Position = Vector3.new(x, 16, z), Color = Color3.fromRGB(30, 40, 60), Material = Enum.Material.Glass, Transparency = 0.2, CanCollide = false, Parent = lights })
			w:SetAttribute("Lightning", true)
		end
	end

	-- Rooms
	local info = { spots = {}, rooms = {}, civilianSpawns = {} }
	local cellI, cellJ = 1, 1 -- containment cell
	for i = 1, F.cols do
		for j = 1, F.rows do
			local c = roomCenter(i, j)
			local half = F.room / 2
			local isCell = i == cellI and j == cellJ
			local roomType = if isCell then { name = "Containment", spots = {}, color = Color3.fromRGB(60, 65, 70) } else ROOM_TYPES[rng:NextInteger(1, #ROOM_TYPES)]
			local roomFolder = Instance.new("Folder")
			roomFolder.Name = roomType.name .. " " .. i .. "-" .. j
			roomFolder.Parent = walls
			-- doors on 1-2 random sides (offset along the 36-stud wall)
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
					-- Containment: the east wall is a huge reinforced glass window that shatters at hunt start
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
						if math.abs((d - F.room / 2) - along) < 5 then
							blocksDoor = true
						end
					end
					if not used[key] and not blocksDoor then
						used[key] = true
						local inset = half - 2.4
						local placements = {
							CFrame.new(c + Vector3.new(along, 0, -inset)) * CFrame.Angles(0, math.pi, 0), -- north wall, facing +Z
							CFrame.new(c + Vector3.new(inset, 0, along)) * CFrame.Angles(0, math.pi / 2, 0), -- east wall, facing -X
							CFrame.new(c + Vector3.new(along, 0, inset)), -- south wall, facing -Z
							CFrame.new(c + Vector3.new(-inset, 0, along)) * CFrame.Angles(0, -math.pi / 2, 0), -- west wall, facing +X
						}
						local model = SPOT_BUILDERS[kind](spots, placements[side])
						table.insert(info.spots, model)
						break
					end
				end
			end
			furnish(decor, c, roomType, rng)
			-- a dead ceiling light and, sometimes, a flickering red emergency light
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

	-- Vents along the hallways' outer walls
	for _ = 1, 6 do
		local x = rng:NextNumber(-WIDTH / 2 + 20, WIDTH / 2 - 20)
		local north = rng:NextNumber() < 0.5
		local z = if north then -DEPTH / 2 + 2.6 else DEPTH / 2 - 2.6
		local cf = CFrame.new(x, 0, z) * (if north then CFrame.Angles(0, math.pi, 0) else CFrame.identity)
		table.insert(info.spots, SPOT_BUILDERS.vent(spots, cf))
	end

	-- Fluorescent tube lights at both ends of every hallway (they flicker, client-side)
	local function tube(position, alongX)
		local t = part({ Name = "HallLight", Size = if alongX then Vector3.new(7, 0.5, 1.4) else Vector3.new(1.4, 0.5, 7), Position = position + Vector3.new(0, F.height - 0.6, 0), Color = Color3.fromRGB(215, 235, 255), Material = Enum.Material.Neon, CanCollide = false, Parent = lights })
		part({ Name = "TubeHousing", Size = (if alongX then Vector3.new(7.6, 0.4, 2) else Vector3.new(2, 0.4, 7.6)), Position = position + Vector3.new(0, F.height - 0.2, 0), Color = Color3.fromRGB(60, 60, 62), Material = Enum.Material.Metal, CanCollide = false, Parent = lights })
		local glow = Instance.new("PointLight")
		glow.Color = Color3.fromRGB(205, 225, 255)
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
	-- and over a few intersections in the middle
	for _ = 1, F.hallLightsMiddle do
		local x = -WIDTH / 2 + F.hall / 2 + rng:NextInteger(1, F.cols - 1) * PITCH
		local z = -DEPTH / 2 + F.hall / 2 + rng:NextInteger(1, F.rows - 1) * PITCH
		tube(Vector3.new(x, 0, z), rng:NextNumber() < 0.5)
	end

	-- Hallway emergency lights
	for _ = 1, 10 do
		local p = hallPoint(rng)
		local e = part({ Name = "EmergencyLight", Size = Vector3.new(1.4, 0.6, 1.4), Position = p + Vector3.new(0, F.height - 0.4, 0), Color = Color3.fromRGB(255, 40, 30), Material = Enum.Material.Neon, CanCollide = false, Parent = lights })
		local glow = Instance.new("PointLight")
		glow.Color = Color3.fromRGB(255, 40, 30)
		glow.Range = 26
		glow.Brightness = 0.7
		glow.Parent = e
	end

	-- Spawns: civilians around the central hallway, Hulk in the far corner
	for _ = 1, 16 do
		table.insert(info.civilianSpawns, hallPoint(rng) + Vector3.new(0, 3, 0))
	end
	info.hulkSpawn = Vector3.new(WIDTH / 2 - F.hall / 2, 6, DEPTH / 2 - F.hall / 2)
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
