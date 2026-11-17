-- The civilians' way to fight back:
--   * Keycards are scattered through the rooms. Enough of them unlocks the armory vault.
--   * Inside the vault is the containment cannon: one direct hit kills the Abomination.
--     It takes a moment to charge, so you have to stand your ground while it comes at you.
--   * Adrenaline shots turn up in the corridors (only a couple at a time) for a short speed burst.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(script.Parent.Net)
local Giants = require(script.Parent.Giants)
local Hiding = require(script.Parent.Hiding)
local Destruction = require(script.Parent.Destruction)

local Objectives = {}
Objectives.collected = 0
Objectives.needed = Config.Objectives.keycardsNeeded
Objectives.vaultOpen = false
Objectives.onKeycard = nil -- set by Main: function(player)
Objectives.onKill = nil -- set by Main: function(player)

local info -- the current map's info from Facility.build
local folder -- everything this module spawns
local active = false
local holder -- player carrying the cannon
local readyAt = 0 -- when the cannon can fire again
local charging = false
local adrenalineCount = 0

local function make(props, class)
	local p = Instance.new(class or "Part")
	p.Anchored = true
	p.CanCollide = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props) do
		p[k] = v
	end
	return p
end

local function glow(p, color, range, brightness)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Parent = p
	return l
end

local function prompt(p, name, action, object, hold)
	local pr = Instance.new("ProximityPrompt")
	pr.Name = name
	pr.ActionText = action
	pr.ObjectText = object
	pr.HoldDuration = hold or 0.3
	pr.MaxActivationDistance = 9
	pr.RequiresLineOfSight = false
	pr.Parent = p
	return pr
end

local function isFreeCivilian(player)
	return player and player:GetAttribute("Role") == "civilian" and not Hiding.isHidden(player)
end

local function updateReader()
	local armory = info and info.armory
	if not armory then
		return
	end
	if Objectives.collected >= Objectives.needed then
		armory.readerText.Text = if Objectives.vaultOpen then "OPEN" else "READY"
		armory.readerText.TextColor3 = Color3.fromRGB(90, 255, 120)
		armory.light.Color = Color3.fromRGB(90, 255, 120)
		armory.light:FindFirstChildOfClass("PointLight").Color = armory.light.Color
	else
		armory.readerText.Text = Objectives.collected .. "/" .. Objectives.needed
	end
end

local function broadcast()
	Net.all("Objectives", {
		keycards = Objectives.collected,
		needed = Objectives.needed,
		vaultOpen = Objectives.vaultOpen,
		holder = holder and holder.DisplayName or nil,
	})
end

---------------------------------------------------------------------------
-- Keycards
---------------------------------------------------------------------------
local function spawnKeycard(position)
	local card = make({ Name = "Keycard", Size = Vector3.new(1.6, 0.12, 1.1), CFrame = CFrame.new(position + Vector3.new(0, 0.6, 0)) * CFrame.Angles(0, math.random() * 6, math.rad(20)), Color = Color3.fromRGB(60, 170, 255), Material = Enum.Material.Neon, Parent = folder })
	glow(card, card.Color, 9, 1.2)
	prompt(card, "KeycardPrompt", "Take Keycard", "Access card", 0.3)
end

local function takeKeycard(player, card)
	if not isFreeCivilian(player) or not card.Parent then
		return
	end
	card:Destroy()
	Objectives.collected += 1
	updateReader()
	broadcast()
	Net.all("Toast", "🔑 " .. player.DisplayName .. " found a keycard (" .. Objectives.collected .. "/" .. Objectives.needed .. ")", "good")
	Net.all("Pickup", "keycard", player.Character and player.Character:GetPivot().Position)
	if Objectives.onKeycard then
		Objectives.onKeycard(player)
	end
	if Objectives.collected == Objectives.needed then
		Net.all("Announce", "🔓 Enough keycards! Open the vault in the " .. (info.armoryName or "armory") .. ".", "good")
	end
end

---------------------------------------------------------------------------
-- The vault and the cannon
---------------------------------------------------------------------------
local cannonPickup -- the model lying around (pedestal or dropped)

local function buildCannonHandle()
	local handle = make({ Name = "Handle", Size = Vector3.new(0.9, 0.9, 4), Color = Color3.fromRGB(60, 65, 70), Material = Enum.Material.Metal })
	handle.Anchored = false
	handle.Massless = true
	local core = make({ Name = "Core", Size = Vector3.new(0.5, 0.5, 3.2), Color = Color3.fromRGB(110, 255, 140), Material = Enum.Material.Neon })
	core.Anchored = false
	core.Massless = true
	core.CFrame = handle.CFrame * CFrame.new(0, 0.35, -0.2)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = handle
	weld.Part1 = core
	weld.Parent = core
	core.Parent = handle
	glow(core, core.Color, 8, 1)
	return handle
end

local function placeCannonPickup(cframe)
	if cannonPickup then
		cannonPickup:Destroy()
	end
	local display = buildCannonHandle()
	display.Name = "CannonPickup"
	display.Anchored = true
	display.CFrame = cframe
	display.Parent = folder
	glow(display, Color3.fromRGB(110, 255, 140), 16, 1.5)
	prompt(display, "CannonPrompt", "Take " .. Config.Cannon.name, "One shot kills it", 0.6)
	cannonPickup = display
end

local function openVault(player)
	if Objectives.vaultOpen then
		return
	end
	if Objectives.collected < Objectives.needed then
		Net.send(player, "Toast", "🔒 Needs " .. (Objectives.needed - Objectives.collected) .. " more keycard(s)", "warn")
		return
	end
	Objectives.vaultOpen = true
	local door = info.armory.door
	door.CanCollide = false
	TweenService:Create(door, TweenInfo.new(2.5, Enum.EasingStyle.Quad), { CFrame = door.CFrame + Vector3.new(0, door.Size.Y - 0.5, 0) }):Play()
	local vp = door:FindFirstChild("VaultPrompt")
	if vp then
		vp:Destroy()
	end
	updateReader()
	placeCannonPickup(info.armory.weaponCFrame)
	Net.all("VaultOpen", door.Position)
	Net.all("Announce", "⚡ THE VAULT IS OPEN. Grab the " .. Config.Cannon.name .. " — one hit kills it.", "good")
	broadcast()
	-- the Abomination always knows where the vault is once it opens
	local abom = Giants.byRole.abomination
	if abom and abom.player then
		Net.send(abom.player, "Reveal", { door.Position }, 4)
	end
end

local function giveCannon(player)
	if not isFreeCivilian(player) or holder then
		return
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	if cannonPickup then
		cannonPickup:Destroy()
		cannonPickup = nil
	end
	local tool = Instance.new("Tool")
	tool.Name = Config.Cannon.name
	tool.ToolTip = "Click to charge and fire. One hit kills the " .. Config.Names.abomination .. "."
	tool.CanBeDropped = false
	tool.GripPos = Vector3.new(0, -0.2, 0.6)
	local handle = buildCannonHandle()
	handle.Parent = tool
	tool.Parent = player.Backpack
	humanoid:EquipTool(tool)
	holder = player
	player:SetAttribute("HasCannon", true)
	readyAt = os.clock() + 0.5
	Net.all("Announce", "🔫 " .. player.DisplayName .. " has the " .. Config.Cannon.name .. "!", "good")
	broadcast()
end

-- The holder was caught, died or left: the cannon falls where they stood
function Objectives.dropCannon(player, position)
	if holder ~= player then
		return
	end
	holder = nil
	charging = false
	if player.Parent then
		player:SetAttribute("HasCannon", nil)
		for _, container in ipairs({ player.Character, player:FindFirstChild("Backpack") }) do
			local tool = container and container:FindFirstChild(Config.Cannon.name)
			if tool then
				tool:Destroy()
			end
		end
	end
	if active and position then
		placeCannonPickup(CFrame.new(position * Vector3.new(1, 0, 1) + Vector3.new(0, 1, 0)) * CFrame.Angles(0, math.random() * 6, math.rad(90)))
		Net.all("Toast", "The " .. Config.Cannon.name .. " was dropped!", "warn")
	end
	broadcast()
end

-- Closest distance from a point to a ray segment
local function rayDistance(origin, dir, length, point)
	local t = math.clamp((point - origin):Dot(dir), 0, length)
	return (origin + dir * t - point).Magnitude, t
end

function Objectives.fire(player, aim)
	if holder ~= player or charging or not isFreeCivilian(player) or typeof(aim) ~= "Vector3" then
		return
	end
	local character = player.Character
	local tool = character and character:FindFirstChild(Config.Cannon.name)
	local head = character and character:FindFirstChild("Head")
	if not (tool and head) then
		return
	end
	local now = os.clock()
	if now < readyAt then
		Net.send(player, "Toast", "⏳ Recharging... " .. math.ceil(readyAt - now) .. "s", "warn")
		return
	end
	charging = true
	Net.all("CannonCharge", character, Config.Cannon.chargeTime)
	task.delay(Config.Cannon.chargeTime, function()
		charging = false
		if holder ~= player or not isFreeCivilian(player) or not head.Parent then
			return
		end
		readyAt = os.clock() + Config.Cannon.recharge
		local origin = head.Position
		local toAim = aim - origin
		if toAim.Magnitude < 1 then
			return
		end
		local dir = toAim.Unit
		local range = Config.Cannon.range
		-- Did it pass close enough to the Abomination's body?
		local abom = Giants.byRole.abomination
		local hit, hitDistance = false, range
		if Giants.alive(abom) then
			local scale = Config.GiantScale
			for _, point in ipairs({ abom.root.Position, abom.root.Position + Vector3.new(0, 2.5 * scale, 0), abom.root.Position - Vector3.new(0, 1.5 * scale, 0) }) do
				local d, t = rayDistance(origin, dir, range, point)
				if d <= Config.Cannon.hitRadius * scale / 2 and t < hitDistance then
					hit, hitDistance = true, t
				end
			end
		end
		-- Walls in the way stop the blast
		local ignore = { character }
		for model in pairs(Giants.actors) do
			table.insert(ignore, model)
		end
		local root = Workspace:FindFirstChild("Facility")
		local debris = root and root:FindFirstChild("Debris")
		if debris then
			table.insert(ignore, debris)
		end
		for _, other in ipairs(Players:GetPlayers()) do
			if other.Character then
				table.insert(ignore, other.Character)
			end
		end
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = ignore
		local block = Workspace:Raycast(origin, dir * (if hit then hitDistance else range), params)
		local endPoint = if block then block.Position elseif hit then origin + dir * hitDistance else origin + dir * range
		if block then
			hit = false
			Destruction.blast(block.Position, 7, { fight = false })
		end
		Net.all("CannonFire", origin, endPoint, hit)
		if hit then
			Giants.kill(abom, player)
			if Objectives.onKill then
				Objectives.onKill(player)
			end
		else
			Net.send(player, "Toast", "Missed! Recharging for " .. Config.Cannon.recharge .. "s", "bad")
		end
	end)
end

---------------------------------------------------------------------------
-- Adrenaline
---------------------------------------------------------------------------
local function spawnAdrenaline()
	local spots = info and info.adrenalineSpots
	if not (spots and #spots > 0) then
		return
	end
	local position = spots[math.random(1, #spots)]
	local shot = make({ Name = "Adrenaline", Size = Vector3.new(0.35, 0.35, 1.6), CFrame = CFrame.new(position + Vector3.new(0, 0.5, 0)) * CFrame.Angles(0, math.random() * 6, 0), Color = Color3.fromRGB(255, 60, 90), Material = Enum.Material.Neon, Parent = folder })
	glow(shot, shot.Color, 8, 1.2)
	prompt(shot, "AdrenalinePrompt", "Take Adrenaline", "Speed boost", 0.25)
	adrenalineCount += 1
end

local function takeAdrenaline(player, shot)
	if not isFreeCivilian(player) or not shot.Parent then
		return
	end
	if player:GetAttribute("Adrenaline") then
		Net.send(player, "Toast", "You can only carry one adrenaline shot.", "warn")
		return
	end
	shot:Destroy()
	adrenalineCount -= 1
	player:SetAttribute("Adrenaline", true)
	Net.send(player, "Toast", "💉 Adrenaline! Press G to use it.", "good")
	Net.all("Pickup", "adrenaline", player.Character and player.Character:GetPivot().Position)
	task.delay(Config.Adrenaline.respawn, function()
		if active and adrenalineCount < Config.Adrenaline.maxOnMap then
			spawnAdrenaline()
		end
	end)
end

function Objectives.useAdrenaline(player)
	if not isFreeCivilian(player) or not player:GetAttribute("Adrenaline") then
		return
	end
	player:SetAttribute("Adrenaline", nil)
	player:SetAttribute("BoostUntil", Workspace:GetServerTimeNow() + Config.Adrenaline.duration)
	Net.all("Pickup", "boost", player.Character and player.Character:GetPivot().Position)
end

---------------------------------------------------------------------------
-- Round lifecycle
---------------------------------------------------------------------------
function Objectives.setup(mapInfo)
	Objectives.clear()
	info = mapInfo
	active = true
	folder = Instance.new("Folder")
	folder.Name = "Objectives"
	folder.Parent = mapInfo.root
	Objectives.needed = Config.Objectives.keycardsNeeded
	-- shuffle the candidate spots and drop the keycards
	local spots = table.clone(mapInfo.keycardSpots)
	for i = #spots, 2, -1 do
		local j = math.random(1, i)
		spots[i], spots[j] = spots[j], spots[i]
	end
	for k = 1, math.min(Config.Objectives.keycardsSpawned, #spots) do
		spawnKeycard(spots[k])
	end
	Objectives.needed = math.min(Objectives.needed, math.min(Config.Objectives.keycardsSpawned, #spots))
	for _ = 1, Config.Adrenaline.maxOnMap do
		spawnAdrenaline()
	end
	updateReader()
	broadcast()
end

function Objectives.clear()
	active = false
	if holder then
		Objectives.dropCannon(holder, nil)
	end
	holder = nil
	charging = false
	cannonPickup = nil
	adrenalineCount = 0
	Objectives.collected = 0
	Objectives.vaultOpen = false
	for _, player in ipairs(Players:GetPlayers()) do
		player:SetAttribute("Adrenaline", nil)
		player:SetAttribute("BoostUntil", nil)
		player:SetAttribute("HasCannon", nil)
	end
	if folder then
		folder:Destroy()
		folder = nil
	end
end

function Objectives.holder()
	return holder
end

-- Returns true if the prompt was one of ours
function Objectives.onPrompt(p, player)
	if not active then
		return false
	end
	if p.Name == "KeycardPrompt" then
		takeKeycard(player, p.Parent)
	elseif p.Name == "VaultPrompt" then
		if isFreeCivilian(player) then
			openVault(player)
		end
	elseif p.Name == "CannonPrompt" then
		giveCannon(player)
	elseif p.Name == "AdrenalinePrompt" then
		takeAdrenaline(player, p.Parent)
	else
		return false
	end
	return true
end

return Objectives
