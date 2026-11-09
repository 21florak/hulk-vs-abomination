-- Remotes shared by every service.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = {}

local folder = Instance.new("Folder")
folder.Name = "Remotes"

-- client -> server: abilities and actions (fire-and-forget)
Net.Input = Instance.new("RemoteEvent")
Net.Input.Name = "Input"
Net.Input.Parent = folder

-- client -> server: shop actions that need a reply
Net.Shop = Instance.new("RemoteFunction")
Net.Shop.Name = "Shop"
Net.Shop.Parent = folder

-- server -> client: everything else (kind, ...)
Net.ToClient = Instance.new("RemoteEvent")
Net.ToClient.Name = "ToClient"
Net.ToClient.Parent = folder

folder.Parent = ReplicatedStorage

function Net.send(player, kind, ...)
	if player and player.Parent then
		Net.ToClient:FireClient(player, kind, ...)
	end
end

function Net.all(kind, ...)
	Net.ToClient:FireAllClients(kind, ...)
end

return Net
