-- The two giants. A giant is an "actor": a scaled-up character (a player's, or an AI bot's)
-- with its own HP, cooldowns and abilities. Hits launch the other giant, and a launched giant
-- crashes through every wall in its path.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(script.Parent.Net)
local Destruction = require(script.Parent.Destruction)

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
	desc.WidthScale = 1.05
	desc.DepthScale = 1.05
	return desc
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
	local hs, ts = head.Size, torso.Size
	if role == "hulk" then
		-- shaggy black hair, heavy brow, angry eyes, torn shorts (skin on the shins)
		weldTo(model, head, { Name = "Hair", Size = Vector3.new(hs.X * 1.05, hs.Y * 0.35, hs.Z * 1.05), CFrame = head.CFrame * CFrame.new(0, hs.Y * 0.38, 0.05), Color = Color3.fromRGB(20, 20, 18), Material = Enum.Material.Fabric })
		weldTo(model, head, { Name = "Brow", Size = Vector3.new(hs.X * 0.85, hs.Y * 0.12, 0.15), CFrame = head.CFrame * CFrame.new(0, hs.Y * 0.18, -hs.Z / 2 - 0.05), Color = costume.skin:Lerp(Color3.new(0, 0, 0), 0.4) })
		for _, side in ipairs({ -1, 1 }) do
			weldTo(model, head, { Name = "Eye", Size = Vector3.new(hs.X * 0.18, hs.Y * 0.08, 0.06), CFrame = head.CFrame * CFrame.new(side * hs.X * 0.2, hs.Y * 0.06, -hs.Z / 2 - 0.03) * CFrame.Angles(0, 0, side * -0.25), Color = Color3.fromRGB(255, 255, 230), Material = Enum.Material.Neon })
		end
		for _, name in ipairs({ "LeftLowerLeg", "RightLowerLeg", "LeftFoot", "RightFoot" }) do
			local p = model:FindFirstChild(name)
			if p then
				p.Color = costume.skin
			end
		end
		if costume.armor then
			for _, side in ipairs({ -1, 1 }) do
				weldTo(model, torso, { Name = "Pauldron", Size = Vector3.new(ts.X * 0.4, ts.Y * 0.2, ts.Z * 1.2), CFrame = torso.CFrame * CFrame.new(side * ts.X * 0.55, ts.Y * 0.45, 0), Color = costume.armor, Material = Enum.Material.Metal })
			end
			weldTo(model, torso, { Name = "Strap", Size = Vector3.new(ts.X * 0.18, ts.Y * 1.2, ts.Z * 1.05), CFrame = torso.CFrame * CFrame.Angles(0, 0, math.rad(35)), Color = Color3.fromRGB(90, 60, 30), Material = Enum.Material.Fabric })
		end
	else
		-- spined back, bony ridges, finned skull, glowing eyes
		local spikeMaterial = if costume.glow then Enum.Material.Neon else Enum.Material.Slate
		for k = 0, 4 do
			local spike = weldTo(model, torso, { class = "WedgePart", Name = "Spine", Size = Vector3.new(0.2, ts.Y * 0.25, ts.Z * 0.45), CFrame = torso.CFrame * CFrame.new(0, ts.Y * (0.4 - k * 0.2), ts.Z / 2 + ts.Z * 0.2) * CFrame.Angles(0, math.pi, 0), Color = costume.spikes, Material = spikeMaterial })
			spike.Name = "Spine"
		end
		local lower = model:FindFirstChild("LowerTorso")
		if lower then
			weldTo(model, lower, { class = "WedgePart", Name = "Spine", Size = Vector3.new(0.2, lower.Size.Y * 0.8, lower.Size.Z * 0.45), CFrame = lower.CFrame * CFrame.new(0, 0, lower.Size.Z / 2 + lower.Size.Z * 0.2) * CFrame.Angles(0, math.pi, 0), Color = costume.spikes, Material = spikeMaterial })
		end
		for _, name in ipairs({ "LeftUpperArm", "RightUpperArm", "LeftLowerLeg", "RightLowerLeg" }) do
			local p = model:FindFirstChild(name)
			if p then
				weldTo(model, p, { class = "WedgePart", Name = "Barb", Size = Vector3.new(0.2, p.Size.Y * 0.5, p.Size.Z * 0.5), CFrame = p.CFrame * CFrame.new(0, 0, p.Size.Z / 2 + p.Size.Z * 0.2) * CFrame.Angles(0, math.pi, 0), Color = costume.spikes, Material = spikeMaterial })
			end
		end
		weldTo(model, head, { class = "WedgePart", Name = "SkullFin", Size = Vector3.new(0.25, hs.Y * 0.5, hs.Z * 1.1), CFrame = head.CFrame * CFrame.new(0, hs.Y * 0.55, 0.1), Color = costume.spikes, Material = spikeMaterial })
		weldTo(model, head, { Name = "Brow", Size = Vector3.new(hs.X * 1.02, hs.Y * 0.14, hs.Z * 0.3), CFrame = head.CFrame * CFrame.new(0, hs.Y * 0.16, -hs.Z * 0.4), Color = costume.spikes, Material = spikeMaterial })
		for _, side in ipairs({ -1, 1 }) do
			local eye = weldTo(model, head, { Name = "Eye", Size = Vector3.new(hs.X * 0.2, hs.Y * 0.1, 0.06), CFrame = head.CFrame * CFrame.new(side * hs.X * 0.21, hs.Y * 0.04, -hs.Z / 2 - 0.03) * CFrame.Angles(0, 0, side * 0.35), Color = costume.eyes, Material = Enum.Material.Neon })
			if side == 1 then
				local glow = Instance.new("PointLight")
				glow.Color = costume.eyes
				glow.Range = 12
				glow.Brightness = 1.2
				glow.Parent = eye
			end
		end
		weldTo(model, head, { Name = "Jaw", Size = Vector3.new(hs.X * 0.7, hs.Y * 0.08, 0.06), CFrame = head.CFrame * CFrame.new(0, -hs.Y * 0.22, -hs.Z / 2 - 0.03), Color = Color3.fromRGB(20, 15, 10) })
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
