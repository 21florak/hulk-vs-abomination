-- The two giants. A giant is an "actor": a scaled-up character (a player's, or an AI bot's)
-- with its own HP, cooldowns and abilities. Hits launch the other giant, and a launched giant
-- crashes through every wall in its path.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(script.Parent.Net)
local Destruction = require(script.Parent.Destruction)
local BodyMeshes = require(script.Parent.BodyMeshes)

local Giants = {}
Giants.actors = {} -- model -> actor
Giants.byRole = {} -- "hulk" | "abomination" -> actor
Giants.rage = false
Giants.onCatchAttempt = nil -- set by Main: function(actor, point, radius)
Giants.onRoar = nil -- set by Main: function(actor)

local function cfgFor(role)
	return if role == "hulk" then Config.Hulk else Config.Abomination
end

local function flat(v)
	local f = v * Vector3.new(1, 0, 1)
	return if f.Magnitude > 0.01 then f.Unit else Vector3.new(0, 0, -1)
end

---------------------------------------------------------------------------
-- Looks
---------------------------------------------------------------------------
local function weldTo(model, anchor, props)
	local p = Instance.new(props.class or "Part")
	props.class = nil
	p.CanCollide = false
	p.CanQuery = false
	p.Massless = true
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
	local w = Instance.new("WeldConstraint")
	w.Part0 = anchor
	w.Part1 = p
	w.Parent = p
	p.Parent = model
	return p
end

local function describe(role, costume)
	local desc = Instance.new("HumanoidDescription")
	local skin = costume.skin
	desc.HeadColor = skin
	desc.TorsoColor = skin
	desc.LeftArmColor = skin
	desc.RightArmColor = skin
	local legs = if role == "hulk" then costume.pants else skin
	desc.LeftLegColor = legs
	desc.RightLegColor = legs
	if role == "hulk" then
		desc.WidthScale = 1.1
		desc.DepthScale = 1.05
	else
		desc.HeightScale = 1.12 -- the Abomination towers over the Hulk but is leaner and wirier
		desc.WidthScale = 0.95
		desc.DepthScale = 0.95
	end
	return desc
end

-- Muscle/bone shapes welded onto the rig before it's scaled up. They're stretched ellipsoids
-- (a block with a sphere mesh, added by finishLook after scaling), not round balls: Roblox balls
-- are always perfect spheres, which is what made the bodies look like lumpy blobs. `scale` multiplies the
-- body part's size; `offset` is relative to the part's center (in units of its size).
local function mass(model, p, scale, offset, props)
	local spec = {
		Name = "Muscle",
		Size = p.Size * scale,
		CFrame = p.CFrame * CFrame.new(p.Size * (offset or Vector3.zero)),
		Color = p.Color,
		Material = p.Material,
	}
	for k, v in pairs(props or {}) do
		spec[k] = v
	end
	local m = weldTo(model, p, spec)
	m:SetAttribute("Ellipsoid", true)
	return m
end

-- A spike/claw/fang: a wedge whose point aims along `direction` (in the part's space)
local function spike(model, p, size, offset, rotation, color, material)
	return weldTo(model, p, {
		class = "WedgePart",
		Name = "Spike",
		Size = size,
		CFrame = p.CFrame * CFrame.new(p.Size * offset) * rotation,
		Color = color,
		Material = material,
	})
end

-- Hot breath steaming out of the mouth in slow, heavy puffs
local function breath(head, color)
	local mouth = Instance.new("Attachment")
	mouth.Name = "Mouth"
	mouth.Position = Vector3.new(0, -head.Size.Y * 0.3, -head.Size.Z * 0.6)
	mouth.Parent = head
	local steam = Instance.new("ParticleEmitter")
	steam.Name = "Breath"
	steam.Texture = "rbxasset://textures/particles/smoke_main.dds"
	steam.Color = ColorSequence.new(color)
	steam.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) })
	steam.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1.4) })
	steam.Lifetime = NumberRange.new(0.8, 1.4)
	steam.Speed = NumberRange.new(1.5, 3)
	steam.EmissionDirection = Enum.NormalId.Front
	steam.SpreadAngle = Vector2.new(20, 20)
	steam.Rate = 6
	steam.LightInfluence = 0.6
	steam.Parent = mouth
end

-- A thin raised line (vein, scar, fissure) lying on a body part's surface
local function streak(model, p, from, to, width, color, material)
	local a = p.CFrame * (p.Size * from)
	local b = p.CFrame * (p.Size * to)
	local mid = (a + b) / 2
	return weldTo(model, p, {
		Name = "Streak",
		Size = Vector3.new(width, width, (b - a).Magnitude),
		CFrame = CFrame.lookAt(mid, b),
		Color = color,
		Material = material or Enum.Material.SmoothPlastic,
	})
end

local function decorateHulk(model, costume)
	local get = function(name)
		return model:FindFirstChild(name)
	end
	local head, torso, lower = get("Head"), get("UpperTorso"), get("LowerTorso")
	local skin, shorts = costume.skin, costume.pants
	local dark = skin:Lerp(Color3.new(0, 0, 0), 0.25)
	for _, d in ipairs(model:GetChildren()) do
		if d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" then
			d.Material = Enum.Material.SmoothPlastic
		end
	end
	for _, name in ipairs({ "LeftFoot", "RightFoot" }) do
		local p = get(name)
		if p then
			p.Color = skin -- torn trousers end mid-shin; bare feet
		end
	end

	-- Torso: traps, delts, pecs, abs, lats
	mass(model, torso, Vector3.new(1.15, 0.55, 0.95), Vector3.new(0, 0.45, 0.05)) -- traps / thick neck
	for _, side in ipairs({ -1, 1 }) do
		mass(model, torso, Vector3.new(0.75, 0.75, 1.25), Vector3.new(side * 0.55, 0.32, 0)) -- delts
		mass(model, torso, Vector3.new(0.6, 0.5, 0.6), Vector3.new(side * 0.22, 0.15, -0.38)) -- pecs
		for row = 0, 2 do
			mass(model, torso, Vector3.new(0.2, 0.17, 0.3), Vector3.new(side * 0.1, -0.12 - row * 0.15, -0.5), { Color = dark }) -- abs
		end
	end
	mass(model, torso, Vector3.new(1.25, 0.9, 0.8), Vector3.new(0, 0.05, 0.3)) -- lats / back
	if lower then
		mass(model, lower, Vector3.new(1.15, 1.6, 1.15), Vector3.new(0, 0, 0), { Color = shorts, Material = Enum.Material.Fabric })
	end

	-- Arms: biceps, forearms, giant fists
	for _, side in ipairs({ "Left", "Right" }) do
		local upper, fore, hand = get(side .. "UpperArm"), get(side .. "LowerArm"), get(side .. "Hand")
		if upper then
			mass(model, upper, Vector3.new(1.55, 1.0, 1.45), Vector3.new(0, 0.05, -0.08))
		end
		if fore then
			mass(model, fore, Vector3.new(1.55, 1.05, 1.45), Vector3.new(0, 0.1, 0))
		end
		if hand then
			mass(model, hand, Vector3.new(1.9, 5, 1.8), Vector3.new(0, -0.6, 0)) -- fist
		end
		-- Legs: quads in torn shorts, big calves
		local thigh, shin, foot = get(side .. "UpperLeg"), get(side .. "LowerLeg"), get(side .. "Foot")
		if thigh then
			mass(model, thigh, Vector3.new(1.5, 1.0, 1.4), Vector3.new(0, 0.05, 0), { Color = shorts, Material = Enum.Material.Fabric })
			-- a rip up the side of the thigh showing skin
			streak(model, thigh, Vector3.new(0.72, 0.2, 0), Vector3.new(0.7, -0.35, -0.1), 0.25, skin)
		end
		if shin then
			mass(model, shin, Vector3.new(1.35, 0.85, 1.35), Vector3.new(0, 0.15, 0.05), { Color = shorts, Material = Enum.Material.Fabric })
			-- shredded hem with bare skin underneath
			weldTo(model, shin, { Name = "Calf", Size = Vector3.new(shin.Size.X * 1.1, shin.Size.Y * 0.35, shin.Size.Z * 1.1), CFrame = shin.CFrame * CFrame.new(0, -shin.Size.Y * 0.35, 0), Color = skin, Material = Enum.Material.SmoothPlastic })
			for k = -1, 1 do
				for _, face in ipairs({ -0.62, 0.62 }) do
					spike(model, shin, Vector3.new(0.3, shin.Size.Y * 0.3, 0.2), Vector3.new(k * 0.35, -0.05, face), CFrame.Angles(math.pi, 0, 0), shorts, Enum.Material.Fabric)
				end
			end
		end
		if foot then
			mass(model, foot, Vector3.new(1.4, 2.4, 1.5), Vector3.new(0, 0, -0.1))
		end
	end

	-- Head: wide jaw, scowl, teeth, heavy brow, shaggy hair, pale angry eyes
	local hs = head.Size
	mass(model, head, Vector3.new(1.1, 0.45, 0.95), Vector3.new(0, -0.38, -0.05)) -- jaw
	weldTo(model, head, { Name = "Brow", Size = Vector3.new(hs.X * 0.95, hs.Y * 0.16, hs.Z * 0.25), CFrame = head.CFrame * CFrame.new(0, hs.Y * 0.18, -hs.Z * 0.45), Color = dark })
	weldTo(model, head, { Name = "Mouth", Size = Vector3.new(hs.X * 0.6, hs.Y * 0.12, 0.08), CFrame = head.CFrame * CFrame.new(0, -hs.Y * 0.28, -hs.Z * 0.55), Color = Color3.fromRGB(35, 10, 10) })
	weldTo(model, head, { Name = "Teeth", Size = Vector3.new(hs.X * 0.5, hs.Y * 0.05, 0.09), CFrame = head.CFrame * CFrame.new(0, -hs.Y * 0.25, -hs.Z * 0.555), Color = Color3.fromRGB(235, 230, 210) })
	for _, side in ipairs({ -1, 1 }) do
		weldTo(model, head, { Name = "Eye", Size = Vector3.new(hs.X * 0.2, hs.Y * 0.07, 0.06), CFrame = head.CFrame * CFrame.new(side * hs.X * 0.21, hs.Y * 0.07, -hs.Z / 2 - 0.04) * CFrame.Angles(0, 0, side * -0.3), Color = Color3.fromRGB(200, 255, 160), Material = Enum.Material.Neon })
	end
	local hair = Color3.fromRGB(18, 18, 16)
	weldTo(model, head, { Name = "Hair", Size = Vector3.new(hs.X * 1.04, hs.Y * 0.22, hs.Z * 1.04), CFrame = head.CFrame * CFrame.new(0, hs.Y * 0.42, 0.03), Color = hair, Material = Enum.Material.Fabric })
	weldTo(model, head, { Name = "HairBack", Size = Vector3.new(hs.X * 1.04, hs.Y * 0.45, hs.Z * 0.2), CFrame = head.CFrame * CFrame.new(0, hs.Y * 0.2, hs.Z * 0.45), Color = hair, Material = Enum.Material.Fabric })
	for k = -2, 2 do
		spike(model, head, Vector3.new(hs.X * 0.18, hs.Y * 0.14, hs.Z * 0.3), Vector3.new(k * 0.2, 0.56, -0.25), CFrame.Angles(math.rad(-10), 0, 0), hair, Enum.Material.Fabric) -- short cropped fringe
	end
	-- heavy cheekbones and a thick, furrowed scowl
	for _, side in ipairs({ -1, 1 }) do
		mass(model, head, Vector3.new(0.3, 0.2, 0.25), Vector3.new(side * 0.33, -0.08, -0.42))
		streak(model, head, Vector3.new(side * 0.06, 0.32, -0.62), Vector3.new(side * 0.02, 0.18, -0.62), 0.05, dark) -- furrow lines between the brows
	end

	-- Raised veins across the arms and neck, battle scars, and shackles torn off the wrists
	local vein = skin:Lerp(Color3.fromRGB(20, 60, 20), 0.45)
	local scar = Color3.fromRGB(110, 45, 40)
	for _, side in ipairs({ "Left", "Right" }) do
		local upper, fore, hand = get(side .. "UpperArm"), get(side .. "LowerArm"), get(side .. "Hand")
		if upper then
			streak(model, upper, Vector3.new(0.1, 0.45, -0.72), Vector3.new(-0.15, -0.4, -0.7), 0.09, vein)
			streak(model, upper, Vector3.new(-0.1, 0.1, -0.72), Vector3.new(0.3, -0.35, -0.68), 0.07, vein)
		end
		if fore then
			streak(model, fore, Vector3.new(0, 0.45, -0.72), Vector3.new(0.1, -0.5, -0.7), 0.09, vein)
			streak(model, fore, Vector3.new(0.25, 0.3, -0.7), Vector3.new(-0.2, -0.3, -0.72), 0.06, vein)
		end
		if hand then
			-- split knuckles
			streak(model, hand, Vector3.new(-0.7, -1, -0.9), Vector3.new(0.7, -1, -0.9), 0.08, scar)
		end
	end
	streak(model, torso, Vector3.new(-0.35, 0.35, -0.62), Vector3.new(0.1, -0.15, -0.62), 0.08, scar) -- chest scar
	streak(model, torso, Vector3.new(0.3, 0.3, -0.62), Vector3.new(0.4, -0.05, -0.62), 0.06, scar)
	streak(model, torso, Vector3.new(-0.2, 0.55, -0.45), Vector3.new(-0.15, 0.85, -0.3), 0.1, vein) -- neck veins
	streak(model, torso, Vector3.new(0.2, 0.55, -0.45), Vector3.new(0.15, 0.85, -0.3), 0.1, vein)
	for _, side in ipairs({ -1, 1 }) do
		for k = 0, 2 do -- serratus ridges along the ribs
			streak(model, torso, Vector3.new(side * 0.42, 0.05 - k * 0.14, -0.45), Vector3.new(side * 0.3, -0.02 - k * 0.14, -0.55), 0.1, dark)
		end
	end
	breath(head, Color3.fromRGB(230, 235, 230))

	if costume.armor then
		for _, side in ipairs({ -1, 1 }) do
			weldTo(model, torso, { Name = "Pauldron", Shape = Enum.PartType.Ball, Size = Vector3.new(torso.Size.X * 0.55, torso.Size.Y * 0.4, torso.Size.Z * 1.4), CFrame = torso.CFrame * CFrame.new(side * torso.Size.X * 0.6, torso.Size.Y * 0.5, 0), Color = costume.armor, Material = Enum.Material.Metal })
		end
		weldTo(model, torso, { Name = "Strap", Size = Vector3.new(torso.Size.X * 0.2, torso.Size.Y * 1.3, torso.Size.Z * 1.35), CFrame = torso.CFrame * CFrame.Angles(0, 0, math.rad(35)), Color = Color3.fromRGB(90, 60, 30), Material = Enum.Material.Fabric })
	end
end

local function decorateAbomination(model, costume)
	local get = function(name)
		return model:FindFirstChild(name)
	end
	local head, torso, lower = get("Head"), get("UpperTorso"), get("LowerTorso")
	local skin = costume.skin
	local bone = if costume.glow then costume.spikes else Color3.fromRGB(215, 205, 180):Lerp(costume.spikes, 0.25)
	local spikeMat = if costume.glow then Enum.Material.Neon else Enum.Material.Slate
	local ridge = if costume.glow then costume.spikes else bone:Lerp(costume.spikes, 0.35)
	for _, d in ipairs(model:GetChildren()) do
		if d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" then
			d.Material = Enum.Material.Slate -- raw, sinewy hide
		end
	end
	-- Bony vertebrae running down the spine between the spikes
	for k = 0, 6 do
		mass(model, torso, Vector3.new(0.16, 0.1, 0.16), Vector3.new(0, 0.6 - k * 0.2, 0.62), { Name = "Vertebra", Color = bone, Material = spikeMat })
	end

	-- Hunched back: a massive hump and two rows of big spines
	mass(model, torso, Vector3.new(1.3, 1.1, 1.0), Vector3.new(0, 0.35, 0.45)) -- hump
	mass(model, torso, Vector3.new(1.2, 0.7, 1.0), Vector3.new(0, 0.5, -0.05)) -- neck bulk
	for k = 0, 5 do
		for _, side in ipairs({ -0.18, 0.18 }) do
			local height = torso.Size.Y * (0.55 - k * 0.05)
			spike(model, torso, Vector3.new(0.25, height, torso.Size.Z * 0.6), Vector3.new(side, 0.65 - k * 0.22, 0.85), CFrame.Angles(math.rad(-25), 0, 0) * CFrame.Angles(0, math.pi, 0), ridge, spikeMat)
		end
	end
	if lower then
		spike(model, lower, Vector3.new(0.25, lower.Size.Y * 1.6, lower.Size.Z * 0.7), Vector3.new(0, 0, 0.8), CFrame.Angles(0, math.pi, 0), ridge, spikeMat)
	end
	-- Shoulder horns
	for _, side in ipairs({ -1, 1 }) do
		mass(model, torso, Vector3.new(0.8, 0.8, 1.2), Vector3.new(side * 0.58, 0.35, 0))
		for k = 0, 2 do
			spike(model, torso, Vector3.new(0.3, torso.Size.Y * 0.45, torso.Size.Z * 0.35), Vector3.new(side * (0.45 + k * 0.12), 0.75, 0.1 - k * 0.15), CFrame.Angles(0, 0, side * math.rad(-35)), bone, spikeMat)
		end
	end
	-- Exposed ribcage on the front
	for row = 0, 3 do
		for _, side in ipairs({ -1, 1 }) do
			weldTo(model, torso, { Name = "Rib", Size = Vector3.new(torso.Size.X * 0.32, torso.Size.Y * 0.06, 0.12), CFrame = torso.CFrame * CFrame.new(side * torso.Size.X * 0.2, torso.Size.Y * (0.15 - row * 0.14), -torso.Size.Z * 0.52) * CFrame.Angles(0, 0, side * math.rad(-12)), Color = ridge, Material = spikeMat })
		end
	end

	-- Arms: thick, bladed forearms, long claws
	for _, side in ipairs({ "Left", "Right" }) do
		local upper, fore, hand = get(side .. "UpperArm"), get(side .. "LowerArm"), get(side .. "Hand")
		if upper then
			mass(model, upper, Vector3.new(1.45, 1.0, 1.4), Vector3.new(0, 0.05, 0))
			spike(model, upper, Vector3.new(0.25, upper.Size.Y * 0.5, upper.Size.Z * 0.7), Vector3.new(0, -0.35, 0.7), CFrame.Angles(math.rad(-20), math.pi, 0), bone, spikeMat) -- elbow spike
		end
		if fore then
			mass(model, fore, Vector3.new(1.45, 1.05, 1.4), Vector3.new(0, 0.05, 0))
			for k = 0, 2 do
				spike(model, fore, Vector3.new(0.22, fore.Size.Y * 0.4, fore.Size.Z * 0.6), Vector3.new(0, 0.3 - k * 0.3, 0.75), CFrame.Angles(math.rad(-30), math.pi, 0), ridge, spikeMat) -- forearm blades
			end
		end
		if hand then
			mass(model, hand, Vector3.new(1.6, 3.6, 1.5), Vector3.new(0, -0.3, 0))
			for k = -1, 1 do
				spike(model, hand, Vector3.new(0.18, hand.Size.Y * 3.5, hand.Size.Z * 0.3), Vector3.new(k * 0.32, -2.6, -0.25), CFrame.Angles(math.rad(180 - 15), 0, 0), bone, spikeMat) -- claws
			end
		end
		-- Legs: heavy thighs, spiked knees, clawed feet
		local thigh, shin, foot = get(side .. "UpperLeg"), get(side .. "LowerLeg"), get(side .. "Foot")
		if thigh then
			mass(model, thigh, Vector3.new(1.45, 1.0, 1.4), Vector3.new(0, 0.05, 0))
		end
		if shin then
			mass(model, shin, Vector3.new(1.3, 0.9, 1.3), Vector3.new(0, 0.1, 0.05))
			spike(model, shin, Vector3.new(0.25, shin.Size.Y * 0.45, shin.Size.Z * 0.6), Vector3.new(0, 0.4, -0.6), CFrame.Angles(math.rad(15), 0, 0), bone, spikeMat) -- knee spike
		end
		if foot then
			mass(model, foot, Vector3.new(1.4, 2.4, 1.6), Vector3.new(0, 0, -0.15))
			for k = -1, 1 do
				spike(model, foot, Vector3.new(0.2, foot.Size.Y * 1.6, foot.Size.Z * 0.45), Vector3.new(k * 0.35, -0.2, -0.85), CFrame.Angles(math.rad(-90), 0, 0), bone, spikeMat) -- toe claws
			end
		end
	end

	-- Head: crest, ear fins, brow ridge, fanged open jaw, glowing slanted eyes
	local hs = head.Size
	head.Color = skin:Lerp(Color3.new(0, 0, 0), 0.15)
	mass(model, head, Vector3.new(1.1, 0.5, 1.05), Vector3.new(0, -0.35, -0.08), { Color = head.Color }) -- jaw
	weldTo(model, head, { Name = "Maw", Size = Vector3.new(hs.X * 0.75, hs.Y * 0.2, 0.08), CFrame = head.CFrame * CFrame.new(0, -hs.Y * 0.32, -hs.Z * 0.58), Color = Color3.fromRGB(25, 5, 5) })
	for k = -3, 3 do
		if k ~= 0 then
			spike(model, head, Vector3.new(0.08, hs.Y * 0.16, 0.12), Vector3.new(k * 0.1, -0.24, -0.6), CFrame.Angles(math.pi, 0, 0), Color3.fromRGB(235, 230, 210), Enum.Material.SmoothPlastic) -- upper fangs
			spike(model, head, Vector3.new(0.08, hs.Y * 0.12, 0.12), Vector3.new(k * 0.1, -0.4, -0.6), CFrame.identity, Color3.fromRGB(235, 230, 210), Enum.Material.SmoothPlastic) -- lower fangs
		end
	end
	weldTo(model, head, { Name = "Brow", Size = Vector3.new(hs.X * 1.05, hs.Y * 0.18, hs.Z * 0.35), CFrame = head.CFrame * CFrame.new(0, hs.Y * 0.18, -hs.Z * 0.38) * CFrame.Angles(math.rad(10), 0, 0), Color = ridge, Material = spikeMat })
	weldTo(model, head, { Name = "SkullRidge", Size = Vector3.new(0.2, hs.Y * 0.18, hs.Z * 1.0), CFrame = head.CFrame * CFrame.new(0, hs.Y * 0.52, 0.05), Color = bone, Material = spikeMat })
	for _, side in ipairs({ -1, 1 }) do
		mass(model, head, Vector3.new(0.28, 0.18, 0.3), Vector3.new(side * 0.36, -0.05, -0.38), { Color = bone, Material = spikeMat }) -- jutting cheekbones
		weldTo(model, head, { Name = "SunkenSocket", Size = Vector3.new(hs.X * 0.3, hs.Y * 0.18, 0.05), CFrame = head.CFrame * CFrame.new(side * hs.X * 0.22, hs.Y * 0.06, -hs.Z / 2 - 0.02), Color = Color3.fromRGB(20, 8, 6) })
	end
	for _, side in ipairs({ -1, 1 }) do
		spike(model, head, Vector3.new(0.15, hs.Y * 0.35, hs.Z * 0.95), Vector3.new(side * 0.55, 0.12, 0.35), CFrame.Angles(math.rad(-25), side * math.rad(-25), 0), head.Color, Enum.Material.Slate) -- long pointed ears swept back
		local eye = weldTo(model, head, { Name = "Eye", Size = Vector3.new(hs.X * 0.13, hs.Y * 0.07, 0.06), CFrame = head.CFrame * CFrame.new(side * hs.X * 0.22, hs.Y * 0.06, -hs.Z / 2 - 0.05) * CFrame.Angles(0, 0, side * 0.4), Color = costume.eyes, Material = Enum.Material.Neon })
		if side == 1 then
			local glow = Instance.new("PointLight")
			glow.Color = costume.eyes
			glow.Range = 14
			glow.Brightness = 1.5
			glow.Parent = eye
		end
	end
end

local function abominationExtras(model, costume)
	local get = function(name)
		return model:FindFirstChild(name)
	end
	local head, torso = get("Head"), get("UpperTorso")
	local bone = if costume.glow then costume.spikes else Color3.fromRGB(215, 205, 180):Lerp(costume.spikes, 0.25)
	local spikeMat = if costume.glow then Enum.Material.Neon else Enum.Material.Slate
	-- Exposed, sinewy muscle: dark striations everywhere (glowing on the Toxic costume)
	local line = if costume.glow then costume.eyes else costume.skin:Lerp(Color3.fromRGB(40, 5, 5), 0.55)
	local lineMat = if costume.glow then Enum.Material.Neon else Enum.Material.SmoothPlastic
	for k = 0, 3 do
		for _, side in ipairs({ -1, 1 }) do
			streak(model, torso, Vector3.new(side * 0.08, 0.4 - k * 0.2, -0.55), Vector3.new(side * 0.45, 0.25 - k * 0.2, -0.5), 0.06, line, lineMat)
		end
	end
	for _, side in ipairs({ "Left", "Right" }) do
		for _, name in ipairs({ "UpperArm", "LowerArm", "UpperLeg" }) do
			local part = get(side .. name)
			if part then
				for k = -1, 1 do
					streak(model, part, Vector3.new(k * 0.3, 0.45, -0.72), Vector3.new(k * 0.3 + 0.1, -0.45, -0.7), 0.05, line, lineMat)
				end
			end
		end
		-- bone breaking through the elbows and knees
		local upper, shin = get(side .. "UpperArm"), get(side .. "LowerLeg")
		if upper then
			mass(model, upper, Vector3.new(0.5, 0.25, 0.5), Vector3.new(0, -0.45, 0.4), { Name = "Spur", Color = bone, Material = spikeMat })
		end
		if shin then
			mass(model, shin, Vector3.new(0.55, 0.25, 0.5), Vector3.new(0, 0.45, -0.45), { Name = "Spur", Color = bone, Material = spikeMat })
		end
	end
	-- Bony plates over the collarbones and sternum
	for _, side in ipairs({ -1, 1 }) do
		weldTo(model, torso, { Name = "Collarbone", Size = Vector3.new(torso.Size.X * 0.45, 0.2, 0.25), CFrame = torso.CFrame * CFrame.new(side * torso.Size.X * 0.25, torso.Size.Y * 0.45, -torso.Size.Z * 0.45) * CFrame.Angles(0, 0, side * math.rad(-10)), Color = bone, Material = spikeMat })
	end
	weldTo(model, torso, { Name = "Sternum", Size = Vector3.new(0.25, torso.Size.Y * 0.6, 0.2), CFrame = torso.CFrame * CFrame.new(0, torso.Size.Y * 0.05, -torso.Size.Z * 0.56), Color = bone, Material = spikeMat })
	breath(head, Color3.fromRGB(190, 200, 190))
end

---------------------------------------------------------------------------
-- Sculpted bodies: models/HulkBody.obj and models/AbominationBody.obj, imported into Studio.
-- Each mesh is welded over its R15 body part (which is then hidden), so the body still animates.
---------------------------------------------------------------------------
local BODY_NAMES = { hulk = "HulkBody", abomination = "AbominationBody" }
local META_KEYS = { hulk = "Hulk", abomination = "Abomination" }
local bodyCache = {}

local function findBody(role)
	local cached = bodyCache[role]
	if cached and cached.model.Parent then
		return cached
	end
	local name = BODY_NAMES[role]
	local found
	for _, container in ipairs({ game:GetService("ServerStorage"), ReplicatedStorage, Workspace }) do
		found = container:FindFirstChild(name, true)
		if found then
			break
		end
	end
	if not found then
		return nil
	end
	if found:IsDescendantOf(Workspace) then
		found.Parent = game:GetService("ServerStorage") -- keep the spare copy out of the map
	end
	local meshes = {}
	for _, d in ipairs(found:GetDescendants()) do
		if d:IsA("MeshPart") then
			meshes[d.Name] = d
		end
	end
	local meta = BodyMeshes[META_KEYS[role]]
	local lt, head, lh, rh = meshes.LowerTorso, meshes.Head, meshes.LeftHand, meshes.RightHand
	if not (lt and head and lh and rh) then
		warn("[Lockdown] " .. name .. " is missing body parts; using the built-in look")
		return nil
	end
	-- Work out how the importer placed the file (scale and rotation), from the head, hips and hands
	local upRef = meta.Head.center - meta.LowerTorso.center
	local sideRef = meta.LeftHand.center - meta.RightHand.center
	local upImp = head.Position - lt.Position
	local sideImp = lh.Position - rh.Position
	local scale = upImp.Magnitude / upRef.Magnitude
	local function basis(up, side)
		local u = up.Unit
		local x = (side - u * side:Dot(u)).Unit
		return CFrame.fromMatrix(Vector3.zero, x, u)
	end
	local rotation = basis(upImp, sideImp) * basis(upRef, sideRef):Inverse() -- reference -> imported
	cached = { model = found, meshes = meshes, meta = meta, scale = scale, unrotate = rotation:Inverse() }
	bodyCache[role] = cached
	return cached
end

local HULK_PANTS = { LowerTorso = true, LeftUpperLeg = true, RightUpperLeg = true, LeftLowerLeg = true, RightLowerLeg = true }

local function layerLook(role, costume, partName, layer)
	local bone = if costume.glow then costume.spikes else Color3.fromRGB(215, 205, 180):Lerp(costume.spikes or Color3.new(1, 1, 1), 0.25)
	if layer == "Eyes" then
		return (if role == "hulk" then Color3.fromRGB(200, 255, 160) else costume.eyes), Enum.Material.Neon
	elseif layer == "Mouth" then
		return Color3.fromRGB(30, 8, 8), Enum.Material.SmoothPlastic
	elseif layer == "Teeth" then
		return Color3.fromRGB(230, 222, 200), Enum.Material.SmoothPlastic
	elseif layer == "Hair" then
		return Color3.fromRGB(20, 20, 18), Enum.Material.SmoothPlastic
	elseif layer == "Bone" then
		return bone, if costume.glow then Enum.Material.Neon else Enum.Material.SmoothPlastic
	elseif role == "hulk" and HULK_PANTS[partName] then
		return costume.pants, Enum.Material.SmoothPlastic
	end
	return costume.skin, Enum.Material.SmoothPlastic
end

-- Returns true if the sculpted body was applied
local function applyBody(model, role, costume)
	local body = findBody(role)
	if not body then
		return false
	end
	local ref = BodyMeshes.ref
	local rot = body.unrotate
	for meshName, source in pairs(body.meshes) do
		local partName, layer = string.match(meshName, "^(%w+)_?(%w*)$")
		local part = partName and model:FindFirstChild(partName)
		local m = body.meta[meshName]
		local r = ref[partName or ""]
		if part and part:IsA("BasePart") and m and r then
			local ratio = part.Size / r.size
			local mesh = source:Clone()
			for _, child in ipairs(mesh:GetChildren()) do
				if not child:IsA("SurfaceAppearance") then
					child:Destroy()
				end
			end
			mesh.Name = "Body_" .. meshName
			mesh.Anchored = false
			mesh.CanCollide = false
			mesh.CanQuery = false
			mesh.CanTouch = false
			mesh.Massless = true
			mesh.CastShadow = true
			mesh.Color, mesh.Material = layerLook(role, costume, partName, layer)
			-- orientation that undoes the importer's rotation; size along the mesh's own axes
			local orient = rot * source.CFrame.Rotation
			local target = m.size * ratio
			local function along(axis)
				local v = orient:VectorToWorldSpace(axis)
				return math.abs(v.X) * target.X + math.abs(v.Y) * target.Y + math.abs(v.Z) * target.Z
			end
			mesh.Size = Vector3.new(along(Vector3.xAxis), along(Vector3.yAxis), along(Vector3.zAxis))
			mesh.CFrame = part.CFrame * CFrame.new((m.center - r.center) * ratio) * orient
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = part
			weld.Part1 = mesh
			weld.Parent = mesh
			mesh.Parent = model
			if layer == "Eyes" then
				local glow = Instance.new("PointLight")
				glow.Color = mesh.Color
				glow.Range = 12
				glow.Brightness = 1.4
				glow.Parent = mesh
			end
		end
	end
	for name in pairs(ref) do
		local part = model:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			part.Transparency = 1
		end
	end
	return true
end

local function decorate(model, role, costume)
	local head = model:FindFirstChild("Head")
	local torso = model:FindFirstChild("UpperTorso")
	if not (head and torso) then
		return
	end
	local face = head:FindFirstChildOfClass("Decal")
	if face then
		face:Destroy()
	end
	if applyBody(model, role, costume) then
		breath(head, Color3.fromRGB(225, 230, 225))
		if role == "hulk" and costume.armor then -- Gladiator costume
			for _, side in ipairs({ -1, 1 }) do
				weldTo(model, torso, { Name = "Pauldron", Shape = Enum.PartType.Ball, Size = Vector3.new(torso.Size.X * 0.55, torso.Size.Y * 0.4, torso.Size.Z * 1.4), CFrame = torso.CFrame * CFrame.new(side * torso.Size.X * 0.68, torso.Size.Y * 0.62, 0), Color = costume.armor, Material = Enum.Material.Metal })
			end
		end
	elseif role == "hulk" then
		decorateHulk(model, costume)
	else
		decorateAbomination(model, costume)
		abominationExtras(model, costume)
	end
end

---------------------------------------------------------------------------
-- Actors
---------------------------------------------------------------------------
local function register(model, role, player)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local cfg = cfgFor(role)
	local actor = {
		model = model,
		humanoid = humanoid,
		root = model:FindFirstChild("HumanoidRootPart"),
		role = role,
		player = player,
		hp = cfg.hp,
		maxHp = cfg.hp,
		cooldowns = {},
		stunUntil = 0,
		koUntil = 0,
		flyUntil = 0,
		nextFlyBlast = 0,
		dead = false,
	}
	model:SetAttribute("Role", role)
	model:SetAttribute("HP", actor.hp)
	model:SetAttribute("MaxHP", actor.maxHp)
	Giants.actors[model] = actor
	Giants.byRole[role] = actor
	humanoid.MaxHealth = 1e6
	humanoid.Health = 1e6
	humanoid.WalkSpeed = cfg.walkSpeed
	humanoid.UseJumpPower = true
	humanoid.JumpPower = 75
	humanoid.BreakJointsOnDeath = false
	Net.all("GiantHP", role, actor.hp, actor.maxHp, "ok")
	return actor
end

-- After scaling: round off the muscles into ellipsoids, then make the silhouette readable in the
-- dark with a faint rim outline and a dim light that shows the body's shapes
local function finishLook(model, role, costume)
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") and p:GetAttribute("Ellipsoid") then
			local mesh = Instance.new("SpecialMesh")
			mesh.MeshType = Enum.MeshType.Sphere
			mesh.Parent = p
		end
	end
	local rim = Instance.new("Highlight")
	rim.Name = "Rim"
	rim.DepthMode = Enum.HighlightDepthMode.Occluded -- never seen through walls
	rim.FillTransparency = 1
	rim.OutlineColor = (costume.eyes or costume.skin):Lerp(Color3.new(1, 1, 1), 0.3)
	rim.OutlineTransparency = 0.55
	rim.Parent = model
	local torso = model:FindFirstChild("UpperTorso")
	if torso then
		local a = Instance.new("Attachment")
		a.Name = "BodyLight"
		a.Position = Vector3.new(0, torso.Size.Y * 0.3, -torso.Size.Z * 2.5)
		a.Parent = torso
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 235, 215)
		light.Range = 11
		light.Brightness = 0.9
		light.Shadows = false
		light.Parent = a
	end
end

-- Turn a player's character into a giant
function Giants.transformPlayer(player, role, costume)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return nil
	end
	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Accessory") or child:IsA("Clothing") or child:IsA("ShirtGraphic") then
			child:Destroy()
		end
	end
	pcall(humanoid.ApplyDescription, humanoid, describe(role, costume))
	decorate(character, role, costume)
	character:ScaleTo(Config.GiantScale)
	finishLook(character, role, costume)
	return register(character, role, player)
end

-- An AI-controlled giant (when there aren't enough players)
function Giants.spawnBot(role, costume, position)
	local ok, model = pcall(Players.CreateHumanoidModelFromDescription, Players, describe(role, costume), Enum.HumanoidRigType.R15)
	if not ok or not model then
		warn("[Lockdown] Couldn't create bot:", model)
		return nil
	end
	model.Name = Config.Names[role] .. " (AI)"
	decorate(model, role, costume)
	model:ScaleTo(Config.GiantScale)
	finishLook(model, role, costume)
	model:PivotTo(CFrame.new(position + Vector3.new(0, 8, 0)))
	model.Parent = Workspace
	model.HumanoidRootPart:SetNetworkOwner(nil)
	local actor = register(model, role, nil)
	actor.bot = true
	return actor
end

function Giants.alive(actor)
	return actor ~= nil and actor.model.Parent ~= nil and not actor.dead
end

function Giants.active(actor)
	local now = os.clock()
	return Giants.alive(actor) and now >= actor.koUntil and now >= actor.stunUntil
end

local function ready(actor, key, seconds)
	local now = os.clock()
	if (actor.cooldowns[key] or 0) > now then
		return false
	end
	actor.cooldowns[key] = now + seconds
	if actor.player then
		Net.send(actor.player, "Cooldown", key, seconds)
	end
	return true
end

---------------------------------------------------------------------------
-- Damage, knockouts and launches
---------------------------------------------------------------------------
function Giants.damage(target, amount, attacker)
	if not Giants.alive(target) or os.clock() < target.koUntil then
		return
	end
	target.hp = math.max(0, target.hp - amount)
	target.model:SetAttribute("HP", target.hp)
	target.lastHitBy = attacker
	target.lastHitAt = os.clock()
	local state = "ok"
	if target.hp <= 0 then
		if target.role == "hulk" then
			target.dead = true
			state = "dead"
			target.humanoid.Health = 0
			Net.all("Announce", "💀 " .. Config.Names.hulk .. " HAS FALLEN. No one is coming to save you.", "bad")
		else
			-- The Abomination goes down... for now
			local cfg = Config.Abomination
			target.koUntil = os.clock() + cfg.koSeconds
			target.koCount = (target.koCount or 0) + 1
			state = "ko"
			target.humanoid.PlatformStand = true
			Net.all("Announce", "💥 " .. Config.Names.abomination .. " is DOWN! It won't stay down for long...", "good")
			if attacker then
				attacker.koBonus = (attacker.koBonus or 0) + 1
			end
			task.delay(cfg.koSeconds, function()
				if Giants.alive(target) then
					target.hp = math.floor(target.maxHp * cfg.koRecoverHp)
					target.model:SetAttribute("HP", target.hp)
					target.humanoid.PlatformStand = false
					Net.all("GiantHP", target.role, target.hp, target.maxHp, "ok")
					Net.all("Announce", "⚠️ " .. Config.Names.abomination .. " is back on its feet.", "bad")
					Net.all("Roar", target.root.Position)
				end
			end)
		end
	end
	Net.all("GiantHP", target.role, target.hp, target.maxHp, state)
end

-- Launch a giant; while flying it smashes through whatever it hits
function Giants.launch(target, direction, power)
	local root = target.root
	if not root then
		return
	end
	local attachment = Instance.new("Attachment")
	attachment.Parent = root
	local push = Instance.new("LinearVelocity")
	push.Attachment0 = attachment
	push.MaxForce = math.huge
	push.VectorVelocity = direction * power + Vector3.new(0, power * 0.25, 0)
	push.Parent = root
	target.flyUntil = os.clock() + 1.1
	task.delay(0.35, function()
		push:Destroy()
		attachment:Destroy()
	end)
end

---------------------------------------------------------------------------
-- Abilities
---------------------------------------------------------------------------
function Giants.smash(actor)
	if not Giants.active(actor) then
		return
	end
	local cfg = cfgFor(actor.role)
	if not ready(actor, "smash", cfg.smashCooldown) then
		return
	end
	local look = flat(actor.root.CFrame.LookVector)
	local point = actor.root.Position + look * cfg.smashRange * 0.55
	Net.all("Smash", actor.role, point)

	local opponent = Giants.byRole[if actor.role == "hulk" then "abomination" else "hulk"]
	local hitGiant = false
	if Giants.alive(opponent) and os.clock() >= opponent.koUntil then
		local offset = opponent.root.Position - actor.root.Position
		local distance = (offset * Vector3.new(1, 0, 1)).Magnitude
		if distance <= cfg.smashRange + 5 and (distance < 9 or flat(offset):Dot(look) > 0.2) then
			hitGiant = true
			Giants.damage(opponent, cfg.smashDamage, actor)
			Giants.launch(opponent, flat(offset), Config.Knockback)
			Destruction.addChaos(Config.Chaos.perGiantHit)
		end
	end
	Destruction.blast(point, 10, { fight = hitGiant })
	if actor.role == "abomination" and Giants.onCatchAttempt then
		Giants.onCatchAttempt(actor, point, cfg.smashRange * 0.6)
	end
end

function Giants.roar(actor)
	if actor.role ~= "abomination" or not Giants.active(actor) then
		return
	end
	local cd = Config.Abomination.roarCooldown * (if Giants.rage then 0.5 else 1)
	if not ready(actor, "roar", cd) then
		return
	end
	Net.all("Roar", actor.root.Position)
	if Giants.onRoar then
		Giants.onRoar(actor)
	end
end

function Giants.clap(actor)
	if actor.role ~= "hulk" or not Giants.active(actor) then
		return
	end
	local cfg = Config.Hulk
	if not ready(actor, "clap", cfg.clapCooldown) then
		return
	end
	Net.all("Clap", actor.root.Position)
	local foe = Giants.byRole.abomination
	local hit = false
	if Giants.alive(foe) and (foe.root.Position - actor.root.Position).Magnitude <= cfg.clapRadius then
		hit = true
		foe.stunUntil = os.clock() + cfg.clapStun
		Giants.damage(foe, cfg.clapDamage, actor)
		Destruction.addChaos(Config.Chaos.perGiantHit)
	end
	Destruction.blast(actor.root.Position, 16, { fight = hit })
end

-- Leap: players jump themselves (client); this lands the ground pound. Bots get launched here.
function Giants.leap(actor)
	if not Giants.active(actor) then
		return
	end
	local cfg = cfgFor(actor.role)
	if not ready(actor, "leap", cfg.leapCooldown) then
		return
	end
	if actor.bot then
		Giants.launch(actor, flat(actor.root.CFrame.LookVector), 70)
	end
	task.delay(1.1, function()
		if Giants.alive(actor) then
			Net.all("Stomp", actor.root.Position)
			Destruction.blast(actor.root.Position - Vector3.new(0, 4, 0), 10, { fight = false })
		end
	end)
end

---------------------------------------------------------------------------
-- Per-frame: speeds, stuns, crashing through walls while flying
---------------------------------------------------------------------------
function Giants.update()
	local now = os.clock()
	for model, actor in pairs(Giants.actors) do
		if not model.Parent then
			Giants.actors[model] = nil
		elseif not actor.dead then
			local cfg = cfgFor(actor.role)
			local speed = cfg.walkSpeed
			if actor.role == "abomination" and Giants.rage then
				speed = Config.Abomination.rageSpeed
			end
			if now < actor.stunUntil or now < actor.koUntil or actor.frozen then
				speed = 0
			end
			actor.humanoid.WalkSpeed = speed
			if now < actor.flyUntil and now >= actor.nextFlyBlast then
				actor.nextFlyBlast = now + 0.1
				Destruction.blast(actor.root.Position, 8, { fight = true })
			elseif speed > 0 and now >= (actor.nextRam or 0) then
				-- Rampage: running into a wall, door or anything breakable plows straight through it
				local velocity = flat(actor.root.AssemblyLinearVelocity)
				if velocity.Magnitude > 8 then
					actor.nextRam = now + 0.15
					local ahead = actor.root.Position + velocity.Unit * Config.Rampage.reach
					if Destruction.anyBreakable(ahead, Config.Rampage.radius) then
						Destruction.blast(ahead, Config.Rampage.radius, { fight = false })
					end
				end
			end
		end
	end
end

function Giants.clear()
	for model, actor in pairs(Giants.actors) do
		if actor.bot and model.Parent then
			model:Destroy()
		end
	end
	table.clear(Giants.actors)
	table.clear(Giants.byRole)
	Giants.rage = false
end

function Giants.ofPlayer(player)
	for _, actor in pairs(Giants.actors) do
		if actor.player == player then
			return actor
		end
	end
	return nil
end

return Giants
