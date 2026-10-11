-- HUD de necessidades (NeedsService) e de assaltos (RobberyService).
-- Os Remotes são criados em runtime; se o serviço ainda não existir, o trecho fica inativo.
local RS = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Catalog = require(RS:WaitForChild("Shared"):WaitForChild("ShopCatalog"))
local Remotes = RS:WaitForChild("Remotes")
local gui = script.Parent
local me = Players.LocalPlayer

local function make(class, props, children)
	local o = Instance.new(class)
	for k, v in pairs(props) do
		o[k] = v
	end
	for _, c in ipairs(children or {}) do
		c.Parent = o
	end
	return o
end
local function corner()
	return make("UICorner", { CornerRadius = UDim.new(0, 6) })
end

-- Barras de fome e energia ------------------------------------------------
local box = make("Frame", {
	Size = UDim2.fromOffset(230, 52),
	Position = UDim2.fromOffset(10, 260),
	BackgroundColor3 = Color3.fromRGB(20, 20, 20),
	BackgroundTransparency = 0.3,
	Visible = false,
	Parent = gui,
}, { corner() })
local function bar(y, label, color)
	local back = make("Frame", {
		Size = UDim2.new(1, -10, 0, 20),
		Position = UDim2.fromOffset(5, y),
		BackgroundColor3 = Color3.fromRGB(60, 60, 60),
		Parent = box,
	}, { corner() })
	local fill = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = color, Parent = back }, { corner() })
	local text = make("TextLabel", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		TextScaled = true,
		TextColor3 = Color3.new(1, 1, 1),
		Text = label,
		Parent = back,
		ZIndex = 2,
	})
	return function(v)
		v = math.clamp(tonumber(v) or 0, 0, 100)
		fill.Size = UDim2.fromScale(v / 100, 1)
		text.Text = ("%s %d%%"):format(label, v)
	end
end
local setHunger = bar(4, "🍔 Fome", Color3.fromRGB(230, 120, 30))
local setEnergy = bar(28, "⚡ Energia", Color3.fromRGB(0, 156, 59))

task.spawn(function()
	local r = Remotes:WaitForChild("NeedsChanged", 60)
	if not r then
		return
	end
	r.OnClientEvent:Connect(function(hunger, energy)
		box.Visible = true
		setHunger(hunger)
		setEnergy(energy)
	end)
end)

-- Toasts ------------------------------------------------------------------
local function toast(text, color)
	local t = make("TextLabel", {
		Size = UDim2.fromOffset(360, 44),
		Position = UDim2.new(0.5, -180, 0, 20),
		BackgroundColor3 = color or Color3.fromRGB(180, 30, 30),
		TextColor3 = Color3.new(1, 1, 1),
		TextScaled = true,
		Text = text,
		Parent = gui,
	}, { corner() })
	task.delay(4, function()
		t:Destroy()
	end)
end

local function nameOf(userId)
	local p = Players:GetPlayerByUserId(userId)
	return p and p.DisplayName or "alguém"
end

-- Assaltos ----------------------------------------------------------------
local wanted = make("TextLabel", {
	Size = UDim2.fromOffset(230, 30),
	Position = UDim2.fromOffset(10, 318),
	BackgroundColor3 = Color3.fromRGB(180, 30, 30),
	TextColor3 = Color3.new(1, 1, 1),
	TextScaled = true,
	Text = "🚨 PROCURADO",
	Visible = false,
	Parent = gui,
}, { corner() })
local timers = make("TextLabel", {
	Size = UDim2.fromOffset(230, 22),
	Position = UDim2.fromOffset(10, 352),
	BackgroundTransparency = 1,
	TextColor3 = Color3.fromRGB(220, 220, 220),
	TextScaled = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	Text = "",
	Parent = gui,
})

local state = {}
-- o celular lê isto via atributo, sem depender do RobberyService
local function fmt(s)
	return ("%d:%02d"):format(s // 60, s % 60)
end

task.spawn(function()
	local rs = Remotes:WaitForChild("RobberyState", 60)
	if rs then
		rs.OnClientEvent:Connect(function(s)
			if type(s) == "table" then
				state = s
			end
		end)
	end
end)
task.spawn(function()
	local r = Remotes:WaitForChild("Robbed", 60)
	if r then
		r.OnClientEvent:Connect(function(byUserId, amount)
			toast(("Você foi assaltado por %s: -%s"):format(nameOf(byUserId), Catalog.FormatReais(amount)))
		end)
	end
end)
task.spawn(function()
	local r = Remotes:WaitForChild("RobberyResult", 60)
	if r then
		local ERR = {
			TooFar = "Chegue mais perto",
			Cooldown = "Espere o cooldown",
			TargetProtected = "Vítima protegida",
			TargetEmpty = "Carteira vazia",
			SameTeamPolice = "Policial não rouba",
			RateLimited = "Calma aí",
			TargetGone = "O alvo saiu do servidor",
			ServerError = "Erro, tente de novo",
		}
		r.OnClientEvent:Connect(function(success, value, targetUserId)
			if success then
				toast(
					("Você levou %s de %s"):format(Catalog.FormatReais(value), nameOf(targetUserId)),
					Color3.fromRGB(0, 120, 50)
				)
			else
				toast(ERR[value] or tostring(value), Color3.fromRGB(90, 90, 90))
			end
		end)
	end
end)

-- relógio da UI (só exibição; o servidor é quem decide)
task.spawn(function()
	while true do
		local now = os.time()
		local isWanted = state.Wanted == true and (state.WantedUntil or 0) > now
		wanted.Visible = isWanted
		if isWanted then
			wanted.Text = "🚨 PROCURADO " .. fmt((state.WantedUntil or now) - now)
		end
		local parts = {}
		if (state.RobCooldownUntil or 0) > now then
			table.insert(parts, "Assalto em " .. fmt(state.RobCooldownUntil - now))
		end
		if (state.ProtectedUntil or 0) > now then
			table.insert(parts, "Protegido " .. fmt(state.ProtectedUntil - now))
		end
		timers.Text = table.concat(parts, "  •  ")
		me:SetAttribute("RobCooldownLeft", math.max(0, (state.RobCooldownUntil or 0) - now))
		task.wait(1)
	end
end)
