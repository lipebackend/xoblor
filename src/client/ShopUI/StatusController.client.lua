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
			Jailed = "Você está preso",
			TargetJailed = "Alvo está preso",
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

-- Polícia e cadeia (ArrestService) ------------------------------------------
-- Atributos do servidor: Player.Wanted (procurado) e Player.JailLeft (segundos de pena restantes).
local jailLabel = make("TextLabel", {
	Size = UDim2.fromOffset(230, 30),
	Position = UDim2.fromOffset(10, 418),
	BackgroundColor3 = Color3.fromRGB(60, 60, 90),
	TextColor3 = Color3.new(1, 1, 1),
	TextScaled = true,
	Text = "",
	Visible = false,
	Parent = gui,
}, { corner() })

local function isPolice()
	return me.Team ~= nil and me.Team.Name == "Polícia"
end

local ARREST_ERR = {
	NotPolice = "Só a polícia prende",
	Jailed = "Você está preso",
	Cooldown = "Espere para prender de novo",
	AlreadyJailed = "Já está preso",
	NotWanted = "Não está procurado",
	TooFar = "Chegue mais perto",
	TargetGone = "Saiu do servidor",
	RateLimited = "Calma aí",
	ServerError = "Erro, tente de novo",
}

-- placa 🚨 para todos e prompt "Prender" só para policiais, no personagem de cada procurado
local marks = {} -- [player] = { board, prompt }
local function clearMark(p)
	local m = marks[p]
	if m then
		m.board:Destroy()
		m.prompt:Destroy()
		marks[p] = nil
	end
end
local function refreshMark(p)
	local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
	local wantedNow = p:GetAttribute("Wanted") == true and p:GetAttribute("JailLeft") == nil
	if not wantedNow or not root then
		clearMark(p)
		return
	end
	local m = marks[p]
	if not m or m.board.Adornee ~= root then
		clearMark(p)
		local board = make("BillboardGui", {
			Size = UDim2.fromOffset(140, 36),
			StudsOffset = Vector3.new(0, 4, 0),
			AlwaysOnTop = true,
			Adornee = root,
			Parent = gui,
		}, {
			make("TextLabel", {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				TextColor3 = Color3.fromRGB(255, 60, 60),
				TextStrokeTransparency = 0,
				TextScaled = true,
				Text = "🚨 PROCURADO",
			}),
		})
		local prompt = make("ProximityPrompt", {
			ActionText = "Prender",
			ObjectText = p.DisplayName,
			HoldDuration = 1,
			MaxActivationDistance = 8,
			RequiresLineOfSight = false,
			Parent = root,
		})
		local userId = p.UserId
		prompt.Triggered:Connect(function()
			local arrest = Remotes:FindFirstChild("Arrest")
			if arrest then
				local ok, res = arrest:InvokeServer(userId)
				if not ok then
					toast(ARREST_ERR[res] or tostring(res), Color3.fromRGB(90, 90, 90))
				end
			end
		end)
		m = { board = board, prompt = prompt }
		marks[p] = m
	end
	m.prompt.Enabled = isPolice() and p ~= me
end
local function watchPlayer(p)
	p:GetAttributeChangedSignal("Wanted"):Connect(function()
		refreshMark(p)
	end)
	p:GetAttributeChangedSignal("JailLeft"):Connect(function()
		refreshMark(p)
	end)
	p.CharacterAdded:Connect(function(char)
		char:WaitForChild("HumanoidRootPart", 5)
		refreshMark(p)
	end)
	refreshMark(p)
end
Players.PlayerAdded:Connect(watchPlayer)
Players.PlayerRemoving:Connect(clearMark)
for _, p in Players:GetPlayers() do
	watchPlayer(p)
end
me:GetPropertyChangedSignal("Team"):Connect(function()
	for _, p in Players:GetPlayers() do
		refreshMark(p)
	end
end)

task.spawn(function()
	local r = Remotes:WaitForChild("Arrested", 60)
	if not r then
		return
	end
	r.OnClientEvent:Connect(function(role, info)
		info = type(info) == "table" and info or {}
		if role == "prisoner" then
			toast(
				("Preso por %s: %ds, multa %s"):format(
					nameOf(info.By),
					tonumber(info.Sentence) or 0,
					Catalog.FormatReais(tonumber(info.Fine) or 0)
				),
				Color3.fromRGB(60, 60, 90)
			)
		elseif role == "cop" then
			toast(
				("Você prendeu %s: +%s"):format(nameOf(info.Target), Catalog.FormatReais(tonumber(info.Fine) or 0)),
				Color3.fromRGB(0, 60, 160)
			)
		elseif role == "released" then
			toast("Você foi solto", Color3.fromRGB(0, 120, 50))
		end
	end)
end)

-- timer da cadeia (só exibição)
task.spawn(function()
	while true do
		local left = tonumber(me:GetAttribute("JailLeft")) or 0
		jailLabel.Visible = left > 0
		if left > 0 then
			jailLabel.Text = "🔒 PRESO " .. fmt(left)
		end
		task.wait(0.5)
	end
end)

-- Corridas de mototaxi (RideService) ---------------------------------------
-- Botão só aparece no time Mototaxistas; o servidor confere tudo de novo.
task.spawn(function()
	local start = Remotes:WaitForChild("RideStart", 60)
	local rideState = Remotes:WaitForChild("RideState", 60)
	if not (start and rideState) then
		return
	end
	local cancel = Remotes:WaitForChild("RideCancel", 10)
	local active = false
	local button = make("TextButton", {
		Size = UDim2.fromOffset(230, 32),
		Position = UDim2.fromOffset(10, 380),
		BackgroundColor3 = Color3.fromRGB(230, 180, 0),
		TextColor3 = Color3.new(0, 0, 0),
		TextScaled = true,
		Text = "🏍️ Pegar corrida",
		Visible = false,
		Parent = gui,
	}, { corner() })

	-- marcador no destino: destaque + placa visível de longe
	local highlight = make("Highlight", {
		FillColor = Color3.fromRGB(255, 200, 0),
		OutlineColor = Color3.new(1, 1, 1),
		DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
		Enabled = false,
		Parent = gui,
	})
	local board = make("BillboardGui", {
		Size = UDim2.fromOffset(200, 50),
		StudsOffset = Vector3.new(0, 6, 0),
		AlwaysOnTop = true,
		Enabled = false,
		Parent = gui,
	})
	local boardText = make("TextLabel", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		TextColor3 = Color3.fromRGB(255, 220, 0),
		TextStrokeTransparency = 0,
		TextScaled = true,
		Text = "",
		Parent = board,
	})

	local function refresh()
		button.Visible = me.Team ~= nil and me.Team.Name == "Mototaxistas"
		button.Text = active and "✖ Cancelar corrida" or "🏍️ Pegar corrida"
	end
	me:GetPropertyChangedSignal("Team"):Connect(refresh)
	refresh()

	local ERR = {
		NotMototaxi = "Só mototaxista pega corrida",
		RideActive = "Você já está numa corrida",
		Cooldown = "Espere um pouco para a próxima",
		NoCharacter = "Aguarde renascer",
		NoDropoff = "Nenhum destino disponível",
		RateLimited = "Calma aí",
		ServerError = "Erro, tente de novo",
	}
	button.Activated:Connect(function()
		if active then
			if cancel then
				cancel:InvokeServer()
			end
			return
		end
		local ok, res = start:InvokeServer()
		if not ok then
			toast(ERR[res] or tostring(res), Color3.fromRGB(90, 90, 90))
		end
	end)

	local MSG = {
		Cancelled = "Corrida cancelada",
		Expired = "Corrida expirou",
		TooFast = "Corrida anulada: chegada rápida demais",
	}
	rideState.OnClientEvent:Connect(function(s)
		if type(s) ~= "table" then
			return
		end
		active = s.Active == true
		local target = active and typeof(s.Target) == "Instance" and s.Target or nil
		highlight.Adornee = target
		highlight.Enabled = target ~= nil
		board.Adornee = target
		board.Enabled = target ~= nil
		boardText.Text = target and ("📍 " .. tostring(s.Name)) or ""
		if s.Status == "Started" then
			toast("Corrida: leve até " .. tostring(s.Name), Color3.fromRGB(0, 90, 160))
		elseif s.Status == "Arrived" then
			local amount = tonumber(s.Amount)
			toast(
				amount and ("Corrida paga: +" .. Catalog.FormatReais(amount)) or "Corrida concluída",
				Color3.fromRGB(0, 120, 50)
			)
		elseif MSG[s.Status] then
			toast(MSG[s.Status], Color3.fromRGB(90, 90, 90))
		end
		refresh()
	end)
end)
