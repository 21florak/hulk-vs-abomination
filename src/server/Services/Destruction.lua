-- Destruction and chaos. Blasts break any Breakable part in range into flying debris,
-- crack or shatter hiding spots (exposing whoever is inside), and raise the chaos meter.
-- As chaos climbs, the building itself turns on the players: blackouts, ceiling collapses,
-- an enraged Abomination, and finally random collapses everywhere.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(script.Parent.Net)

local Destruction = {}
Destruction.chaos = 0
Destruction.onSpotDestroyed = nil -- set by Main (Hiding.destroySpot)
Destruction.onEvent = nil -- set by Main: called with the event name ("rage", ...)

local fired = {}
local failingLoop = false

local function facilityFolders()
	local root = Workspace:FindFirstChild("Facility")
	if not root then
		return nil
	end
	return root, { root:FindFirstChild("Walls"), root:FindFirstChild("HidingSpots"), root:FindFirstChild("Decor"), root:FindFirstChild("Lights") }
end

function Destruction.reset()
	Destruction.chaos = 0
	table.clear(fired)
	failingLoop = false
end

local function addChaos(amount)
	if amount <= 0 then
		return
	end
	Destruction.chaos = math.min(130, Destruction.chaos + amount)
	Net.all("Chaos", Destruction.chaos)
	for _, t in ipairs(Config.Chaos.thresholds) do
		if Destruction.chaos >= t.at and not fired[t.event] then
			fired[t.event] = true
			Net.all("ChaosEvent", t.event, t.text)
			task.spawn(Destruction.trigger, t.event) -- some events take a few seconds
		end
	end
end
Destruction.addChaos = addChaos

local function spotOf(p)
	local model = p:FindFirstAncestorOfClass("Model")
	if model and model:GetAttribute("HidingSpot") then
		return model
	end
	return nil
end

-- Break a hiding spot apart (and expose its occupant)
function Destruction.shatterSpot(model, from)
	if model:GetAttribute("Destroyed") then
		return
	end
	model:SetAttribute("Destroyed", true)
	if Destruction.onSpotDestroyed then
		Destruction.onSpotDestroyed(model)
	end
	local root = Workspace:FindFirstChild("Facility")
	local debris = root and root:FindFirstChild("Debris")
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("ProximityPrompt") then
			p:Destroy()
		elseif p:IsA("BasePart") then
			p.Anchored = false
			local dir = (p.Position - (from or p.Position)) * Vector3.new(1, 0, 1)
			dir = if dir.Magnitude > 0.1 then dir.Unit else Vector3.new(math.random() - 0.5, 0, math.random() - 0.5).Unit
			p.AssemblyLinearVelocity = dir * math.random(25, 50) + Vector3.new(0, math.random(15, 35), 0)
			if debris then
				p.Parent = debris
			end
		end
	end
	model:Destroy()
end

local function freezeLater(parts)
	task.delay(6, function()
		for _, p in ipairs(parts) do
			if p.Parent then
				p.Anchored = true
				p.CanCollide = p.Size.Magnitude > 3 -- small bits stop blocking movement
			end
		end
	end)
end

-- point: world position, radius: studs. opts.fight = true when it came from giants fighting
-- (cracks hiding spots further out). Returns how many pieces broke.
-- Is there anything breakable within `radius` of `point`? (cheap check before a blast)
function Destruction.anyBreakable(point, radius)
	local _, folders = facilityFolders()
	local include = {}
	for _, f in ipairs(folders or {}) do
		if f then
			table.insert(include, f)
		end
	end
	if #include == 0 then
		return false
	end
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = include
	for _, p in ipairs(Workspace:GetPartBoundsInRadius(point, radius, params)) do
		if p.Anchored and p:GetAttribute("Breakable") then
			return true
		end
	end
	return false
end

function Destruction.blast(point, radius, opts)
	opts = opts or {}
	local root, folders = facilityFolders()
	if not root then
		return 0
	end
	local include = {}
	for _, f in ipairs(folders) do
		if f then
			table.insert(include, f)
		end
	end
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = include
	local hits = Workspace:GetPartBoundsInRadius(point, radius, params)
	local broken = {}
	local spots = {}
	local debris = root:FindFirstChild("Debris")
	for _, p in ipairs(hits) do
		if p.Anchored and p:GetAttribute("Breakable") then
			local spot = spotOf(p)
			if spot then
				spots[spot] = true
			else
				p.Anchored = false
				p.CanCollide = true
				local dir = p.Position - point
				dir = if dir.Magnitude > 0.1 then dir.Unit else Vector3.yAxis
				p.AssemblyLinearVelocity = dir * math.random(35, 80) + Vector3.new(0, math.random(10, 30), 0)
				p.AssemblyAngularVelocity = Vector3.new(math.random(-6, 6), math.random(-6, 6), math.random(-6, 6))
				for _, light in ipairs(p:GetChildren()) do
					if light:IsA("Light") then
						light.Enabled = false
					end
				end
				if p.Material == Enum.Material.Neon then
					p.Material = Enum.Material.SmoothPlastic
					p.Color = Color3.fromRGB(40, 40, 40)
				end
				if debris then
					p.Parent = debris
				end
				table.insert(broken, p)
			end
		end
	end
	for spot in pairs(spots) do
		Destruction.shatterSpot(spot, point)
	end
	freezeLater(broken)

	-- Fight shockwaves crack hiding spots nearby; enough cracks and they give way
	if opts.fight then
		local spotsFolder = root:FindFirstChild("HidingSpots")
		for _, spot in ipairs(spotsFolder and spotsFolder:GetChildren() or {}) do
			if spot.PrimaryPart and not spot:GetAttribute("Destroyed") then
				local d = (spot.PrimaryPart.Position - point).Magnitude
				if d > radius and d < Config.Chaos.shockwaveRadius then
					local strength = (spot:GetAttribute("Strength") or 3) - 1
					spot:SetAttribute("Strength", strength)
					Net.all("SpotCracked", spot.PrimaryPart.Position, strength)
					if strength <= 0 then
						Destruction.shatterSpot(spot, point)
					end
				end
			end
		end
	end

	Net.all("Blast", point, radius, #broken)
	addChaos(#broken * Config.Chaos.perPanel)
	return #broken
end

-- A chunk of ceiling crashes down somewhere
function Destruction.collapseAt(point)
	local root = Workspace:FindFirstChild("Facility")
	if not root then
		return
	end
	local debris = root:FindFirstChild("Debris")
	local h = Config.Facility.height
	Net.all("Collapse", point)
	for k = 1, 4 do
		local slab = Instance.new("Part")
		slab.Name = "CeilingChunk"
		slab.Size = Vector3.new(math.random(4, 8), 1.5, math.random(4, 8))
		slab.Color = Color3.fromRGB(60, 60, 62)
		slab.Material = Enum.Material.Concrete
		slab.CFrame = CFrame.new(point + Vector3.new(math.random(-5, 5), h - 2 - k * 0.5, math.random(-5, 5))) * CFrame.Angles(math.random(), math.random(), math.random())
		slab.Parent = debris or root
	end
	task.delay(0.8, function()
		Destruction.blast(point + Vector3.new(0, 3, 0), 9, { fight = false })
	end)
end

local function randomInside()
	local root = Workspace:FindFirstChild("Facility")
	local spots = root and root:FindFirstChild("HidingSpots")
	local list = spots and spots:GetChildren() or {}
	-- Half the time the collapse lands near a hiding spot. Nowhere is safe.
	if #list > 0 and math.random() < 0.5 then
		local s = list[math.random(1, #list)]
		if s.PrimaryPart then
			return s.PrimaryPart.Position * Vector3.new(1, 0, 1)
		end
	end
	local W, D = Config.Facility.cols * (Config.Facility.room + Config.Facility.hall), Config.Facility.rows * (Config.Facility.room + Config.Facility.hall)
	return Vector3.new(math.random(-W / 2 + 10, W / 2 - 10), 0, math.random(-D / 2 + 10, D / 2 - 10))
end

function Destruction.trigger(event)
	if event == "collapse" then
		for _ = 1, 5 do
			Destruction.collapseAt(randomInside())
			task.wait(0.4)
		end
	elseif event == "failing" then
		if failingLoop then
			return
		end
		failingLoop = true
		task.spawn(function()
			while failingLoop and Workspace:FindFirstChild("Facility") do
				Destruction.collapseAt(randomInside())
				task.wait(Config.Chaos.collapseEvery)
			end
		end)
	end
	if Destruction.onEvent then
		Destruction.onEvent(event)
	end
end

function Destruction.stop()
	failingLoop = false
end

return Destruction
