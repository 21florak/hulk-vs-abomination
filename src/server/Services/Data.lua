-- Coins and costumes, saved between sessions.
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local Data = {}

local store
pcall(function()
	store = DataStoreService:GetDataStore("MonsterLockdown_v1")
end)

local profiles = {}

local function default()
	return {
		coins = 0,
		owned = { hulk_classic = true, abom_classic = true, civ_office = true },
		equipped = { hulk = "hulk_classic", abomination = "abom_classic", civilian = "civ_office" },
		wins = 0,
		catches = 0,
	}
end

function Data.load(player)
	local data
	if store then
		local ok, result = pcall(store.GetAsync, store, "p_" .. player.UserId)
		if ok and type(result) == "table" then
			data = result
		end
	end
	local profile = default()
	if data then
		for k, v in pairs(data) do
			profile[k] = v
		end
	end
	profiles[player] = profile
	return profile
end

function Data.get(player)
	return profiles[player]
end

function Data.save(player)
	local profile = profiles[player]
	if store and profile then
		pcall(store.SetAsync, store, "p_" .. player.UserId, profile)
	end
end

function Data.release(player)
	Data.save(player)
	profiles[player] = nil
end

function Data.addCoins(player, amount)
	local profile = profiles[player]
	if profile and amount > 0 then
		profile.coins += amount
		local stats = player:FindFirstChild("leaderstats")
		if stats then
			stats.Coins.Value = profile.coins
		end
	end
end

function Data.costumeFor(player, role)
	local profile = profiles[player]
	local id = profile and profile.equipped[role]
	return Config.Costumes[id] or Config.Costumes[Config.CostumeOrder[role][1]]
end

-- Shop actions: { action = "buy" | "equip", id }
function Data.shop(player, action, id)
	local profile = profiles[player]
	local costume = Config.Costumes[id]
	if not (profile and costume) then
		return false, "Unknown costume."
	end
	if action == "buy" then
		if profile.owned[id] then
			return false, "You already own it."
		end
		if profile.coins < costume.price then
			return false, "Not enough coins."
		end
		profile.coins -= costume.price
		profile.owned[id] = true
		profile.equipped[costume.role] = id
		Data.addCoins(player, 0)
		local stats = player:FindFirstChild("leaderstats")
		if stats then
			stats.Coins.Value = profile.coins
		end
		return true, "Unlocked " .. costume.name .. "!"
	elseif action == "equip" then
		if not profile.owned[id] then
			return false, "Buy it first."
		end
		profile.equipped[costume.role] = id
		return true, "Equipped " .. costume.name .. "."
	end
	return false, "Unknown action."
end

function Data.all()
	return profiles
end

return Data
