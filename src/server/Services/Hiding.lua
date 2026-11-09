-- Hiding spots: civilians hide inside (invisible, frozen, peeking out), the Abomination
-- searches them, and destruction throws hidden civilians back out into the open.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(script.Parent.Net)

local Hiding = {}
Hiding.onCaught = nil -- set by Main: function(player, catcherActor)
Hiding.onReveal = nil -- set by Main: tell the Abomination where an exposed civilian is

local occupantOf = {} -- spot -> player
local spotOf = {} -- player -> spot
local saved = {} -- player -> { [part] = transparency }

local function rootOf(player)
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart"), character and character:FindFirstChildOfClass("Humanoid")
end

local function setInvisible(player, invisible)
	local character = player.Character
	if not character then
		return
	end
	if invisible then
		saved[player] = {}
		for _, d in ipairs(character:GetDescendants()) do
			if d:IsA("BasePart") or d:IsA("Decal") then
				saved[player][d] = d.Transparency
				d.Transparency = 1
			elseif d:IsA("Light") then
				d.Enabled = false
			end
		end
	else
		for d, t in pairs(saved[player] or {}) do
			if d.Parent then
				d.Transparency = t
			end
		end
		saved[player] = nil
	end
end

function Hiding.isHidden(player)
	return spotOf[player] ~= nil
end

function Hiding.spotOf(player)
	return spotOf[player]
end

function Hiding.hide(player, spot)
	if player:GetAttribute("Role") ~= "civilian" or spotOf[player] then
		return
	end
	if not (spot and spot.Parent and spot.PrimaryPart) or spot:GetAttribute("Destroyed") then
		return
	end
	if occupantOf[spot] then
		Net.send(player, "Toast", "Someone's already hiding in there!", "warn")
		return
	end
	local root, humanoid = rootOf(player)
	if not (root and humanoid) or (root.Position - spot.PrimaryPart.Position).Magnitude > 10 then
		return
	end
	occupantOf[spot] = player
	spotOf[player] = spot
	player:SetAttribute("Hidden", true)
	setInvisible(player, true)
	root.Anchored = true
	root.CFrame = spot:GetAttribute("HideCFrame")
	Net.send(player, "Hidden", spot:GetAttribute("PeekCFrame"), spot.Name)
end

function Hiding.leave(player, launch)
	local spot = spotOf[player]
	if not spot then
		return
	end
	spotOf[player] = nil
	occupantOf[spot] = nil
	player:SetAttribute("Hidden", nil)
	setInvisible(player, false)
	local root = rootOf(player)
	if root then
		local base = spot:GetAttribute("HideCFrame") or root.CFrame
		root.CFrame = base * CFrame.new(0, 1.5, -4)
		root.Anchored = false
		if launch then
			root.AssemblyLinearVelocity = launch
		end
	end
	Net.send(player, "Unhidden")
end

-- Called by Destruction when a spot is smashed or collapses
function Hiding.destroySpot(spot)
	local player = occupantOf[spot]
	if not player then
		return
	end
	Hiding.leave(player, Vector3.new(math.random(-20, 20), 25, math.random(-20, 20)))
	local _, humanoid = rootOf(player)
	if humanoid then
		local speed = humanoid.WalkSpeed
		humanoid.WalkSpeed = 0
		task.delay(1.5, function()
			if humanoid.Parent then
				humanoid.WalkSpeed = math.max(speed, Config.Civilian.walkSpeed)
			end
		end)
	end
	Net.send(player, "Exposed")
	if Hiding.onReveal then
		Hiding.onReveal(player)
	end
end

-- The Abomination (player or bot) searches a spot
function Hiding.search(actor, spot)
	if not (spot and spot.Parent and spot.PrimaryPart) or spot:GetAttribute("Destroyed") then
		return false
	end
	if (actor.root.Position - spot.PrimaryPart.Position).Magnitude > Config.Abomination.searchRange + 6 then
		return false
	end
	local player = occupantOf[spot]
	Net.all("Searched", spot.PrimaryPart.Position)
	if player then
		Hiding.leave(player)
		if Hiding.onCaught then
			Hiding.onCaught(player, actor)
		end
		return true
	end
	if actor.player then
		Net.send(actor.player, "Toast", "Empty...", "info")
	end
	return false
end

function Hiding.forget(player)
	local spot = spotOf[player]
	if spot then
		occupantOf[spot] = nil
	end
	spotOf[player] = nil
	saved[player] = nil
end

function Hiding.reset()
	for player in pairs(spotOf) do
		player:SetAttribute("Hidden", nil)
	end
	table.clear(occupantOf)
	table.clear(spotOf)
	table.clear(saved)
end

-- How many civilians are hiding right now (for the HUD)
function Hiding.count()
	local n = 0
	for player in pairs(spotOf) do
		if player.Parent then
			n += 1
		end
	end
	return n
end

return Hiding
