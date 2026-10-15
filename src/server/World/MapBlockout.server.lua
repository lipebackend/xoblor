-- Blockout do Rio: gera Workspace/Map só se ainda não existir (o mapa final substitui).
-- Também cria placeholders em ServerStorage/Vehicles e Outfits para testes.
local CollectionService = game:GetService("CollectionService")
local ServerStorage = game:GetService("ServerStorage")
local RS = game:GetService("ReplicatedStorage")
local Catalog = require(RS.Shared.ShopCatalog)

local function part(parent, name, size, pos, color, props)
	local p = Instance.new("Part")
	p.Name, p.Size, p.Position, p.Anchored = name, size, pos, true
	p.Color = color or Color3.fromRGB(163, 162, 165)
	for k, v in pairs(props or {}) do
		p[k] = v
	end
	p.Parent = parent
	return p
end

local function tagged(parent, name, pos, tag, attrs)
	local p = part(parent, name, Vector3.new(6, 1, 6), pos, Color3.fromRGB(255, 200, 0), { Transparency = 0.3 })
	CollectionService:AddTag(p, tag)
	for k, v in pairs(attrs or {}) do
		p:SetAttribute(k, v)
	end
	return p
end

local function house(parent, id, pos)
	local m = Instance.new("Model")
	m.Name = id
	m:SetAttribute("HouseId", id)
	part(
		m,
		"Walls",
		Vector3.new(20, 12, 20),
		pos + Vector3.new(0, 6, 0),
		Color3.fromRGB(230, 220, 200),
		{ Transparency = 0.5, CanCollide = false }
	)
	part(m, "Door", Vector3.new(4, 8, 1), pos + Vector3.new(0, 4, 10.5), Color3.fromRGB(120, 70, 30))
	part(m, "Inside", Vector3.new(4, 1, 4), pos + Vector3.new(0, 0.5, 0), nil, { Transparency = 1, CanCollide = false })
	m.Parent = parent
	CollectionService:AddTag(m, "House")
end

-- bairro: centro, cor do chão, conteúdo
local BAIRROS = {
	Copacabana = {
		Vector3.new(0, 0, 0),
		Color3.fromRGB(240, 220, 160),
		function(b, c)
			part(
				b,
				"Mar",
				Vector3.new(300, 1, 80),
				c + Vector3.new(0, -0.4, 140),
				Color3.fromRGB(40, 120, 200),
				{ Material = Enum.Material.Water }
			)
			tagged(b, "Quiosque_Mate", c + Vector3.new(-40, 1, 60), "JobStation", { JobId = "mate" })
			tagged(b, "Entrega_Copacabana", c + Vector3.new(-60, 1, -40), "RideDropoff")
			tagged(b, "Loja_Praia", c + Vector3.new(20, 1, 60), "Shop", { Category = "Comida" })
			house(b, "copa_1", c + Vector3.new(60, 0, -40))
		end,
	},
	Centro = {
		Vector3.new(0, 0, -300),
		Color3.fromRGB(150, 150, 150),
		function(b, c)
			tagged(b, "Delegacia", c + Vector3.new(-50, 1, 0), "JobStation", { JobId = "policial" })
			tagged(b, "Hospital", c + Vector3.new(50, 1, 0), "JobStation", { JobId = "medico" })
			tagged(b, "Banco_ATM", c + Vector3.new(0, 1, 40), "Shop", { Category = "Banco" })
			tagged(b, "Spawn_Viatura", c + Vector3.new(-50, 1, 30), "VehicleSpawn")
			tagged(b, "Entrega_Centro", c + Vector3.new(0, 1, -60), "RideDropoff")
		end,
	},
	["Zona Norte"] = {
		Vector3.new(300, 0, -300),
		Color3.fromRGB(170, 140, 110),
		function(b, c)
			tagged(b, "Oficina", c + Vector3.new(-30, 1, 0), "JobStation", { JobId = "mecanico" })
			tagged(b, "Mercado", c + Vector3.new(30, 1, 0), "Shop", { Category = "Comida" })
			house(b, "zn_1", c + Vector3.new(0, 0, 60))
			tagged(b, "Entrega_ZonaNorte", c + Vector3.new(-60, 1, -60), "RideDropoff")
		end,
	},
	Morro = {
		Vector3.new(300, 20, 0),
		Color3.fromRGB(140, 100, 70),
		function(b, c)
			tagged(b, "Ponto_Mototaxi", c + Vector3.new(0, 1, 50), "JobStation", { JobId = "mototaxi" })
			tagged(b, "Spawn_Moto", c + Vector3.new(15, 1, 50), "VehicleSpawn")
			house(b, "morro_1", c + Vector3.new(-30, 0, -30))
			tagged(b, "Entrega_Morro", c + Vector3.new(50, 1, -50), "RideDropoff")
		end,
	},
	Barra = {
		Vector3.new(-350, 0, 0),
		Color3.fromRGB(200, 230, 200),
		function(b, c)
			tagged(b, "Concessionaria", c + Vector3.new(0, 1, 0), "Shop", { Category = "Veiculo" })
			tagged(b, "Spawn_Concessionaria", c + Vector3.new(20, 1, 0), "VehicleSpawn")
			house(b, "barra_1", c + Vector3.new(0, 0, 70))
			tagged(b, "Entrega_Barra", c + Vector3.new(-50, 1, -50), "RideDropoff")
		end,
	},
}

if not workspace:FindFirstChild("Map") then
	local map = Instance.new("Folder")
	map.Name = "Map"
	for name, def in pairs(BAIRROS) do
		local b = Instance.new("Model")
		b.Name = name
		local c = def[1]
		part(
			b,
			"Chao",
			Vector3.new(200, 1, 200),
			c + Vector3.new(0, -0.5, 0),
			def[2],
			{ Material = Enum.Material.Concrete }
		)
		def[3](b, c)
		b.Parent = map
	end
	map.Parent = workspace
end

-- placeholders de veículo (PrimaryPart + VehicleSeat) e roupa
local vehicles = ServerStorage:FindFirstChild("Vehicles")
local outfits = ServerStorage:FindFirstChild("Outfits")
for id, item in pairs(Catalog.Items) do
	if item.Category == "Veiculo" and vehicles and not vehicles:FindFirstChild(id) then
		local m = Instance.new("Model")
		m.Name = id
		local body =
			part(m, "Body", Vector3.new(6, 2, 10), Vector3.zero, Color3.fromRGB(80, 80, 200), { Anchored = false })
		local seat = Instance.new("VehicleSeat")
		seat.Size = Vector3.new(2, 1, 2)
		seat.CFrame = body.CFrame + Vector3.new(0, 1.5, 0)
		seat.Parent = m
		local w = Instance.new("WeldConstraint")
		w.Part0, w.Part1, w.Parent = body, seat, body
		m.PrimaryPart = body
		m.Parent = vehicles
	elseif item.Category == "Roupa" and outfits and not outfits:FindFirstChild(id) then
		local f = Instance.new("Folder")
		f.Name = id
		f.Parent = outfits
	end
end
