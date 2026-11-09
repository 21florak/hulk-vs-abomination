-- Round controller: lobby → role draw → hide → hunt → results, forever.
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Services = script.Parent.Services
local Net = require(Services.Net)
local Data = require(Services.Data)
local Facility = require(Services.Facility)
local Destruction = require(Services.Destruction)
local Hiding = require(Services.Hiding)
local Giants = require(Services.Giants)
local Bots = require(Services.Bots)

Players.CharacterAutoLoads = false

-- Pitch black everywhere; the lobby has its own lights
Lighting.ClockTime = 0
Lighting.Brightness = 0
Lighting.Ambient = Color3.fromRGB(6, 6, 9)
Lighting.OutdoorAmbient = Color3.fromRGB(0, 0, 0)
Lighting.EnvironmentDiffuseScale = 0
Lighting.EnvironmentSpecularScale = 0.15
Lighting.FogColor = Color3.fromRGB(2, 2, 4)
Lighting.FogStart = 8
Lighting.FogEnd = 120
Lighting.GlobalShadows = true

Facility.buildLobby()

---------------------------------------------------------------------------
-- Round state
---------------------------------------------------------------------------
local round = {
	phase = "lobby",
	endsAt = 0,
	roles = {}, -- player -> role
	civilians = {}, -- players who started as civilians
	caught = {}, -- player -> true
	info = nil,
}
local battery = {} -- player -> flashlight battery
local lastNoise = {} -- player -> time

local function setRole(player, role)
	round.roles[player] = role
	player:SetAttribute("Role", role)
end

local function aliveCivilians()
	local list = {}
	for _, player in ipairs(round.civilians) do
		if player.Parent and not round.caught[player] and round.roles[player] == "civilian" then
			table.insert(list, player)
		end
	end
	return list
end

local function abominationPlayer()
	local actor = Giants.byRole.abomination
	return actor and actor.player
end

local function sendState()
	Net.all("State", {
		phase = round.phase,
		timeLeft = math.max(0, round.endsAt - os.clock()),
		civiliansLeft = #aliveCivilians(),
		civiliansTotal = #round.civilians,
		hiding = Hiding.count(),
		chaos = Destruction.chaos,
	})
end

local function toLobby(player)
	if player.Parent then
		Hiding.forget(player)
		player:SetAttribute("Hidden", nil)
		player:LoadCharacter()
	end
end

---------------------------------------------------------------------------
-- Catching
---------------------------------------------------------------------------
local function catch(player, actor)
	if round.phase ~= "hunt" or round.caught[player] or round.roles[player] ~= "civilian" then
		return
	end
	round.caught[player] = true
	if actor then
		actor.catches = (actor.catches or 0) + 1
	end
	Hiding.leave(player)
	Net.send(player, "Caught")
	Net.all("Announce", "😱 " .. player.DisplayName .. " was caught!", "bad")
	task.delay(2.5, function()
		if player.Parent and round.caught[player] then
			setRole(player, "spectator")
			toLobby(player)
		end
	end)
end
Hiding.onCaught = catch

-- A smash can grab anyone standing in front of the Abomination
Giants.onCatchAttempt = function(actor, point, radius)
	for _, player in ipairs(aliveCivilians()) do
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root and not Hiding.isHidden(player) and (root.Position - point).Magnitude <= radius + 4 then
			catch(player, actor)
		end
	end
end

-- Roar: every civilian in range (even hidden ones) flashes on the Abomination's screen
Giants.onRoar = function(actor)
	local positions = {}
	for _, player in ipairs(aliveCivilians()) do
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root and (root.Position - actor.root.Position).Magnitude <= Config.Abomination.roarRadius then
			table.insert(positions, root.Position)
			Bots.hear(root.Position, 10)
			Net.send(player, "Roared")
		end
	end
	if actor.player then
		Net.send(actor.player, "Reveal", positions, Config.Abomination.roarReveal)
	end
end

-- A hiding spot got smashed: the Abomination glimpses who fell out
Hiding.onReveal = function(player)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	Bots.hear(root.Position, 6)
	local abom = abominationPlayer()
	if abom then
		Net.send(abom, "Reveal", { root.Position }, 2)
	end
end

Destruction.onSpotDestroyed = Hiding.destroySpot
Destruction.onEvent = function(event)
	if event == "rage" then
		Giants.rage = true
	elseif event == "blackout" then
		-- exit signs die too
		local root = workspace:FindFirstChild("Facility")
		for _, d in ipairs(root and root:GetDescendants() or {}) do
			if d:IsA("PointLight") and d.Parent and d.Parent.Name == "ExitSign" and math.random() < 0.7 then
				d.Enabled = false
				d.Parent.Material = Enum.Material.SmoothPlastic
				d.Parent.Color = Color3.fromRGB(20, 40, 25)
			end
		end
	end
end

---------------------------------------------------------------------------
-- Players
---------------------------------------------------------------------------
local function costumeCivilian(character, costume)
	for _, c in ipairs(character:GetChildren()) do
		if c:IsA("Shirt") or c:IsA("Pants") or c:IsA("ShirtGraphic") then
			c:Destroy()
		end
	end
	for _, name in ipairs({ "UpperTorso", "LeftUpperArm", "RightUpperArm", "LeftLowerArm", "RightLowerArm", "Torso", "Left Arm", "Right Arm" }) do
		local p = character:FindFirstChild(name)
		if p then
			p.Color = costume.shirt
		end
	end
	for _, name in ipairs({ "LowerTorso", "LeftUpperLeg", "RightUpperLeg", "LeftLowerLeg", "RightLowerLeg", "Left Leg", "Right Leg" }) do
		local p = character:FindFirstChild(name)
		if p then
			p.Color = costume.pants
		end
	end
	local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
	if costume.coat and torso then
		local coat = Instance.new("Part")
		coat.Name = "LabCoat"
		coat.Size = torso.Size * Vector3.new(1.08, 1.6, 1.12)
		coat.CFrame = torso.CFrame * CFrame.new(0, -torso.Size.Y * 0.25, 0)
		coat.Color = Color3.new(1, 1, 1)
		coat.Material = Enum.Material.Fabric
		coat.CanCollide = false
		coat.Massless = true
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = torso
		weld.Part1 = coat
		weld.Parent = coat
		coat.Parent = character
	end
end

local function giveFlashlight(character)
	local head = character:FindFirstChild("Head")
	if not head then
		return
	end
	local light = Instance.new("SpotLight")
	light.Name = "Flashlight"
	light.Range = 45
	light.Angle = 50
	light.Brightness = 3
	light.Shadows = true
	light.Color = Color3.fromRGB(255, 245, 220)
	light.Face = Enum.NormalId.Front
	light.Enabled = false
	light.Parent = head
end

local function onPlayerAdded(player)
	local profile = Data.load(player)
	local stats = Instance.new("Folder")
	stats.Name = "leaderstats"
	local coins = Instance.new("IntValue")
	coins.Name = "Coins"
	coins.Value = profile.coins
	coins.Parent = stats
	stats.Parent = player
	player:SetAttribute("Role", "lobby")
	player.CharacterAdded:Connect(function(character)
		local humanoid = character:WaitForChild("Humanoid")
		humanoid.Died:Connect(function()
			task.wait(3)
			if not player.Parent then
				return
			end
			local role = round.roles[player]
			if round.phase ~= "lobby" and (role == "hulk" or role == "civilian") then
				-- out for the rest of the round
				if role == "civilian" then
					round.caught[player] = true
				end
				setRole(player, "spectator")
			end
			toLobby(player)
		end)
	end)
	player:LoadCharacter()
	Net.send(player, "Profile", profile)
	if round.phase ~= "lobby" then
		player:SetAttribute("Role", "spectator")
	end
end
Players.PlayerAdded:Connect(onPlayerAdded)
for _, p in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, p)
end
Players.PlayerRemoving:Connect(function(player)
	Hiding.forget(player)
	round.roles[player] = nil
	battery[player] = nil
	lastNoise[player] = nil
	Data.release(player)
end)

---------------------------------------------------------------------------
-- Input from clients
---------------------------------------------------------------------------
Net.Input.OnServerEvent:Connect(function(player, kind)
	local actor = Giants.ofPlayer(player)
	if actor and round.phase == "hunt" then
		if kind == "smash" then
			Giants.smash(actor)
		elseif kind == "roar" then
			Giants.roar(actor)
		elseif kind == "clap" then
			Giants.clap(actor)
		elseif kind == "leap" then
			Giants.leap(actor)
		end
		return
	end
	if round.roles[player] == "civilian" then
		if kind == "flashlight" then
			local head = player.Character and player.Character:FindFirstChild("Head")
			local light = head and head:FindFirstChild("Flashlight")
			if light and not Hiding.isHidden(player) then
				light.Enabled = not light.Enabled and (battery[player] or 0) > 2
			end
		elseif kind == "leave" then
			Hiding.leave(player)
		end
	end
end)

ProximityPromptService.PromptTriggered:Connect(function(prompt, player)
	local spot = prompt.Parent and prompt.Parent:FindFirstAncestorOfClass("Model")
	if prompt.Name == "HidePrompt" and spot and round.phase ~= "lobby" then
		Hiding.hide(player, spot)
	elseif prompt.Name == "SearchPrompt" and spot and round.phase == "hunt" then
		local actor = Giants.ofPlayer(player)
		if actor and actor.role == "abomination" and Giants.active(actor) then
			Hiding.search(actor, spot)
		end
	elseif prompt.Name == "ShopPrompt" then
		Net.send(player, "OpenShop")
	end
end)

Net.Shop.OnServerInvoke = function(player, action, id)
	local ok, message = Data.shop(player, action, id)
	Net.send(player, "Profile", Data.get(player))
	return ok, message
end

---------------------------------------------------------------------------
-- The round
---------------------------------------------------------------------------
local function shuffle(list)
	for i = #list, 2, -1 do
		local j = math.random(1, i)
		list[i], list[j] = list[j], list[i]
	end
	return list
end

local function costumeFor(player, role)
	if player then
		return Data.costumeFor(player, role)
	end
	return Config.Costumes[Config.CostumeOrder[role][1]]
end

local function startRound()
	local players = shuffle(Players:GetPlayers())
	if #players == 0 then
		return false
	end
	round.roles = {}
	round.civilians = {}
	round.caught = {}
	Destruction.reset()
	Hiding.reset()
	Bots.reset()
	Giants.clear()
	local info = Facility.build(math.random(1, 1e6))
	round.info = info

	-- Roles: a random player is the Abomination (2+ players), another the Hulk (3+);
	-- bots fill in, and everyone else is a civilian
	local abomPlayer = if #players >= 2 then players[1] else nil
	local hulkPlayer = if #players >= 3 then players[2] else nil
	for _, player in ipairs(players) do
		if player == abomPlayer then
			setRole(player, "abomination")
		elseif player == hulkPlayer then
			setRole(player, "hulk")
		else
			setRole(player, "civilian")
			table.insert(round.civilians, player)
		end
	end

	-- Spawn everyone
	for k, player in ipairs(players) do
		task.spawn(function()
			player:LoadCharacter()
			local character = player.Character
			if not character then
				return
			end
			local role = round.roles[player]
			if role == "civilian" then
				costumeCivilian(character, costumeFor(player, "civilian"))
				giveFlashlight(character)
				battery[player] = Config.Civilian.flashlightBattery
				character:FindFirstChildOfClass("Humanoid").WalkSpeed = Config.Civilian.walkSpeed
				character:PivotTo(CFrame.new(info.civilianSpawns[(k - 1) % #info.civilianSpawns + 1]))
			elseif role == "hulk" then
				character:PivotTo(CFrame.new(info.hulkSpawn))
				Giants.transformPlayer(player, "hulk", costumeFor(player, "hulk"))
				character:PivotTo(CFrame.new(info.hulkSpawn + Vector3.new(0, 10, 0)))
			elseif role == "abomination" then
				character:PivotTo(CFrame.new(info.abominationSpawn))
				local actor = Giants.transformPlayer(player, "abomination", costumeFor(player, "abomination"))
				character:PivotTo(CFrame.new(info.abominationSpawn + Vector3.new(0, 10, 0)))
				if actor then
					actor.frozen = true
				end
			end
			Net.send(player, "RoleReveal", role)
		end)
	end
	if not abomPlayer and Config.Bots.abomination then
		local bot = Giants.spawnBot("abomination", costumeFor(nil, "abomination"), info.abominationSpawn)
		if bot then
			bot.frozen = true
		end
	end
	if not hulkPlayer and Config.Bots.hulk then
		Giants.spawnBot("hulk", costumeFor(nil, "hulk"), info.hulkSpawn)
	end
	return true
end

local function releaseAbomination()
	local glass = round.info and round.info.containmentGlass
	if glass and glass.Parent then
		glass.Anchored = false
		glass.CanCollide = false
		glass.AssemblyLinearVelocity = Vector3.new(60, 10, 0)
		task.delay(1.5, function()
			glass:Destroy()
		end)
		Net.all("Shatter", glass.Position)
	end
	local abom = Giants.byRole.abomination
	if abom then
		abom.frozen = false
		Net.all("Roar", abom.root.Position)
	end
	Net.all("Announce", "🔓 THE CONTAINMENT CELL IS OPEN. It's hunting.", "bad")
end

local function payOut(winner)
	local abom = Giants.byRole.abomination
	local hulk = Giants.byRole.hulk
	local R = Config.Rewards
	for player, role in pairs(round.roles) do
		if player.Parent then
			local amount = R.participation
			local profile = Data.get(player)
			if role == "abomination" or (abom and abom.player == player) then
				local catches = abom and abom.catches or 0
				amount += catches * R.abominationPerCatch + (if winner == "abomination" then R.abominationWin else 0)
				if profile then
					profile.catches += catches
				end
			elseif role == "hulk" or (hulk and hulk.player == player) then
				amount += (if winner == "hulk" then R.hulkWin else 0) + (hulk and hulk.koBonus or 0) * R.hulkKoBonus
			elseif role == "civilian" and not round.caught[player] then
				amount += if winner == "hulk" then R.survivor else 0
			else
				amount += R.caught
			end
			local won = (winner == "abomination" and role == "abomination") or (winner == "hulk" and (role == "hulk" or (role == "civilian" and not round.caught[player])))
			if won and profile then
				profile.wins += 1
			end
			Data.addCoins(player, amount)
			Net.send(player, "Reward", amount, won)
			Net.send(player, "Profile", profile)
			task.spawn(Data.save, player)
		end
	end
end

local function endRound(winner, text)
	round.phase = "results"
	round.endsAt = os.clock() + Config.Round.results
	Destruction.stop()
	Net.all("Results", winner, text)
	payOut(winner)
	sendState()
	task.wait(Config.Round.results)
	for player in pairs(round.roles) do
		setRole(player, "lobby")
		toLobby(player)
	end
	for _, player in ipairs(Players:GetPlayers()) do
		player:SetAttribute("Role", "lobby")
	end
	Giants.clear()
	Hiding.reset()
	Facility.clear()
	round.roles = {}
	round.civilians = {}
	round.phase = "lobby"
end

-- Things that happen every tick during a round
local function tick()
	Giants.update()
	Bots.step(aliveCivilians(), round.phase == "hunt")
	if round.phase ~= "hunt" then
		return
	end
	local abom = Giants.byRole.abomination
	local now = os.clock()
	for _, player in ipairs(aliveCivilians()) do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and not Hiding.isHidden(player) then
			-- Grabbed if the Abomination gets close
			if Giants.active(abom) then
				local offset = root.Position - abom.root.Position
				if (offset * Vector3.new(1, 0, 1)).Magnitude <= Config.Abomination.catchRange and math.abs(offset.Y) < 16 then
					catch(player, abom)
				end
			end
			-- Sprinting makes noise the Abomination can hear
			local speed = (root.AssemblyLinearVelocity * Vector3.new(1, 0, 1)).Magnitude
			if speed > Config.Civilian.walkSpeed + 3 and now - (lastNoise[player] or 0) > 0.8 then
				lastNoise[player] = now
				if abom and (abom.root.Position - root.Position).Magnitude <= Config.Abomination.noiseRadius then
					Bots.hear(root.Position, 6)
					if abom.player then
						Net.send(abom.player, "Noise", root.Position)
					end
				end
			end
		end
	end
end

-- Flashlight batteries drain while on, recharge while off (once a second)
task.spawn(function()
	while true do
		task.wait(1)
		for player, charge in pairs(battery) do
			local head = player.Character and player.Character:FindFirstChild("Head")
			local light = head and head:FindFirstChild("Flashlight")
			if light then
				if light.Enabled then
					charge = math.max(0, charge - Config.Civilian.flashlightDrain)
					if charge <= 0 then
						light.Enabled = false
					end
				else
					charge = math.min(Config.Civilian.flashlightBattery, charge + Config.Civilian.flashlightRecharge)
				end
				battery[player] = charge
				Net.send(player, "Battery", charge)
			end
		end
	end
end)

-- Main loop
task.spawn(function()
	while true do
		-- Lobby / intermission
		round.phase = "lobby"
		local intermissionEnds = os.clock() + Config.Round.intermission
		while os.clock() < intermissionEnds do
			round.endsAt = intermissionEnds
			Facility.setStatus("Next lockdown in " .. math.ceil(intermissionEnds - os.clock()) .. "s")
			sendState()
			task.wait(1)
		end
		if not startRound() then
			continue
		end

		-- Hide
		round.phase = "hide"
		round.endsAt = os.clock() + Config.Round.hide
		Facility.setStatus("LOCKDOWN IN PROGRESS")
		Net.all("Announce", "🏃 HIDE! The " .. Config.Names.abomination .. " gets out in " .. Config.Round.hide .. " seconds.", "warn")
		while os.clock() < round.endsAt do
			tick()
			sendState()
			task.wait(0.25)
		end

		-- Hunt
		round.phase = "hunt"
		round.endsAt = os.clock() + Config.Round.hunt
		releaseAbomination()
		local lastState = 0
		local winner, text
		while true do
			tick()
			if os.clock() - lastState > 0.5 then
				lastState = os.clock()
				sendState()
			end
			local left = #aliveCivilians()
			local abom = Giants.byRole.abomination
			if #round.civilians > 0 and left == 0 then
				winner, text = "abomination", "The " .. Config.Names.abomination .. " found everyone."
				break
			end
			if not (abom and abom.model.Parent) then
				winner, text = "hulk", "The " .. Config.Names.abomination .. " fled the building."
				break
			end
			if os.clock() >= round.endsAt then
				winner, text = "hulk", if left > 0 then left .. " civilian(s) survived the lockdown!" else "The lockdown is over."
				break
			end
			task.wait(0.2)
		end
		endRound(winner, text)
	end
end)
