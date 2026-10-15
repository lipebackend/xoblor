-- HUD de R$, loja, menu de emprego e celular (banco, Pix, casas, garagem).
-- UI montada por código. Toda regra é validada no servidor.
local RS = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Catalog = require(RS:WaitForChild("Shared"):WaitForChild("ShopCatalog"))
local JobCatalog = require(RS.Shared:WaitForChild("JobCatalog"))
local Remotes = RS:WaitForChild("Remotes")
local me = Players.LocalPlayer
local gui = script.Parent
local R = Catalog.FormatReais

local function remote(name)
	return Remotes:WaitForChild(name, 15)
end
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
local function corner(r)
	return make("UICorner", { CornerRadius = UDim.new(0, r or 8) })
end
local function button(text, parent, cb)
	local b = make("TextButton", {
		Size = UDim2.new(1, 0, 0, 34),
		Text = text,
		TextScaled = true,
		BackgroundColor3 = Color3.fromRGB(0, 156, 59),
		TextColor3 = Color3.new(1, 1, 1),
		Parent = parent,
	}, { corner(6) })
	b.Activated:Connect(function()
		cb(b)
	end)
	return b
end
local function flash(b, msg, original)
	b.Text = msg
	task.delay(1.5, function()
		if b.Parent then
			b.Text = original
		end
	end)
end
local ERR = {
	InsufficientFunds = "Sem grana",
	WrongJob = "Emprego errado",
	AlreadyOwned = "Já tem",
	RateLimited = "Calma aí",
	PixLimit = "Limite do Pix",
	Occupied = "Ocupada",
	NoSpawnNearby = "Vá a um estacionamento",
	Jailed = "Você está preso",
	ServerError = "Erro, tente de novo",
}
local function err(res)
	return ERR[res] or tostring(res)
end

-- HUD -------------------------------------------------------------------
local hud = make("Frame", {
	Size = UDim2.fromOffset(230, 70),
	Position = UDim2.fromOffset(10, 10),
	BackgroundColor3 = Color3.fromRGB(20, 20, 20),
	BackgroundTransparency = 0.3,
	Parent = gui,
}, { corner() })
local wallet = make("TextLabel", {
	Size = UDim2.new(1, -10, 0.55, 0),
	Position = UDim2.fromOffset(5, 2),
	BackgroundTransparency = 1,
	TextScaled = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3 = Color3.fromRGB(255, 223, 0),
	Text = "R$ 0",
	Parent = hud,
})
local jobLabel = make("TextLabel", {
	Size = UDim2.new(1, -10, 0.4, 0),
	Position = UDim2.new(0, 5, 0.58, 0),
	BackgroundTransparency = 1,
	TextScaled = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3 = Color3.new(1, 1, 1),
	Text = "Desempregado",
	Parent = hud,
})

local function showWallet(v)
	wallet.Text = R(v)
end
remote("BalanceChanged").OnClientEvent:Connect(showWallet)
local ls = me:WaitForChild("leaderstats", 15)
if ls and ls:FindFirstChild("Reais") then
	showWallet(ls.Reais.Value)
end

-- Painéis ---------------------------------------------------------------
local panels = {}
local function panel(name)
	local f = make("ScrollingFrame", {
		Name = name,
		Size = UDim2.fromOffset(300, 420),
		Position = UDim2.new(1, -320, 0.5, -210),
		BackgroundColor3 = Color3.fromRGB(30, 30, 30),
		Visible = false,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Parent = gui,
	}, {
		corner(),
		make("UIListLayout", { Padding = UDim.new(0, 6) }),
		make("UIPadding", {
			PaddingTop = UDim.new(0, 8),
			PaddingLeft = UDim.new(0, 8),
			PaddingRight = UDim.new(0, 8),
		}),
	})
	panels[name] = f
	return f
end
local function open(name)
	for n, f in pairs(panels) do
		f.Visible = (n == name) and not f.Visible
	end
end
local function title(text, parent)
	make("TextLabel", {
		Size = UDim2.new(1, 0, 0, 30),
		Text = text,
		TextScaled = true,
		BackgroundTransparency = 1,
		TextColor3 = Color3.new(1, 1, 1),
		Parent = parent,
	})
end
local function clear(f)
	for _, c in f:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
end

-- Barra lateral
local bar = make(
	"Frame",
	{ Size = UDim2.fromOffset(110, 160), Position = UDim2.fromOffset(10, 90), BackgroundTransparency = 1, Parent = gui },
	{ make("UIListLayout", { Padding = UDim.new(0, 6) }) }
)

-- Loja ------------------------------------------------------------------
local shop = panel("Loja")
title("🛒 Loja", shop)
local CAT_ORDER = { "Comida", "Roupa", "Veiculo" }
for _, cat in ipairs(CAT_ORDER) do
	title(cat == "Veiculo" and "Veículos" or cat, shop)
	for id, item in pairs(Catalog.Items) do
		if item.Category == cat then
			local label = ("%s  %s%s"):format(
				item.Name,
				item.Price > 0 and R(item.Price) or "Grátis",
				item.RequiredJob and (" (" .. item.RequiredJob .. ")") or ""
			)
			button(label, shop, function(b)
				local ok, res = remote("RequestPurchase"):InvokeServer(id)
				flash(b, ok and "Comprado!" or err(res), label)
			end)
		end
	end
end

-- Empregos --------------------------------------------------------------
local jobs = panel("Emprego")
title("💼 Emprego", jobs)
make("TextLabel", {
	Size = UDim2.new(1, 0, 0, 50),
	TextWrapped = true,
	BackgroundTransparency = 1,
	TextScaled = true,
	TextColor3 = Color3.fromRGB(200, 200, 200),
	Parent = jobs,
	Text = "Vá até um posto de trabalho no mapa para se candidatar.",
})
for _, j in pairs(JobCatalog.Jobs) do
	make("TextLabel", {
		Size = UDim2.new(1, 0, 0, 26),
		BackgroundTransparency = 1,
		TextScaled = true,
		TextColor3 = Color3.new(1, 1, 1),
		Parent = jobs,
		Text = ("%s: %s%s"):format(j.Name, R(j.Salary), j.PayPerRide and "/corrida" or "/min"),
	})
end
button("Pedir demissão", jobs, function(b)
	local ok, res = remote("QuitJob"):InvokeServer()
	flash(b, ok and "Demitido" or err(res), "Pedir demissão")
end)
task.spawn(function()
	remote("JobChanged").OnClientEvent:Connect(function(jobId)
		local j = jobId and JobCatalog.Jobs[jobId]
		jobLabel.Text = j and ("💼 " .. j.Name) or "Desempregado"
	end)
end)

-- Celular ---------------------------------------------------------------
local phone = panel("Celular")
local function input(placeholder, parent)
	return make("TextBox", {
		Size = UDim2.new(1, 0, 0, 30),
		PlaceholderText = placeholder,
		Text = "",
		TextScaled = true,
		ClearTextOnFocus = false,
		Parent = parent,
	}, { corner(6) })
end
local function num(box)
	local n = tonumber(box.Text)
	return n and math.floor(n) or nil
end

local bankLabel
local function renderPhone()
	clear(phone)
	title("📱 Celular", phone)
	-- Banco
	title("🏦 Banco", phone)
	bankLabel = make("TextLabel", {
		Size = UDim2.new(1, 0, 0, 26),
		BackgroundTransparency = 1,
		TextScaled = true,
		TextColor3 = Color3.fromRGB(255, 223, 0),
		Text = "Banco: ...",
		Parent = phone,
	})
	local amt = input("Valor (R$)", phone)
	button("Depositar", phone, function(b)
		local ok, res = remote("BankDeposit"):InvokeServer(num(amt))
		flash(b, ok and "Depositado" or err(res), "Depositar")
	end)
	button("Sacar", phone, function(b)
		local ok, res = remote("BankWithdraw"):InvokeServer(num(amt))
		flash(b, ok and "Sacado" or err(res), "Sacar")
	end)
	-- Pix
	title("⚡ Pix", phone)
	local who = input("Nome do jogador", phone)
	local pixAmt = input("Valor (R$)", phone)
	button("Enviar Pix", phone, function(b)
		local target = Players:FindFirstChild(who.Text)
		if not target then
			flash(b, "Jogador não encontrado", "Enviar Pix")
			return
		end
		local ok, res = remote("Pix"):InvokeServer(target.UserId, num(pixAmt))
		flash(b, ok and "Pix enviado!" or err(res), "Enviar Pix")
	end)
	-- Casas
	title("🏠 Imóveis", phone)
	local ok, mine = remote("HouseAction"):InvokeServer("list", "")
	for id, h in pairs(Catalog.Houses) do
		local st = ok and mine and mine[id]
		local status = st
				and (st.Kind == "owned" and " (sua)" or (" (alugada %dmin)"):format(math.ceil((st.Left or 0) / 60)))
			or ""
		make("TextLabel", {
			Size = UDim2.new(1, 0, 0, 24),
			BackgroundTransparency = 1,
			TextScaled = true,
			TextColor3 = Color3.new(1, 1, 1),
			Text = h.Name .. status,
			Parent = phone,
		})
		if not st or st.Kind ~= "owned" then
			local rl = ("Alugar %s/%dmin"):format(R(h.Rent), h.RentMinutes)
			button(rl, phone, function(b)
				local k, r = remote("HouseAction"):InvokeServer("rent", id)
				flash(b, k and "Alugada!" or err(r), rl)
			end)
			local bl = "Comprar " .. R(h.Price)
			button(bl, phone, function(b)
				local k, r = remote("HouseAction"):InvokeServer("buy", id)
				flash(b, k and "Comprada!" or err(r), bl)
			end)
		end
	end
	local guest = input("Convidar jogador (nome)", phone)
	button("Convidar para minhas casas", phone, function(b)
		local t = Players:FindFirstChild(guest.Text)
		if not t or not mine then
			flash(b, "Não encontrado", "Convidar para minhas casas")
			return
		end
		for id in pairs(mine) do
			remote("HouseAction"):InvokeServer("invite", id, t.UserId)
			task.wait(0.6)
		end
		flash(b, "Convidado!", "Convidar para minhas casas")
	end)
	-- Assalto (RobberyService; o servidor valida alcance, cooldown e proteção)
	if Remotes:FindFirstChild("RobAttempt") then
		title("🦹 Assalto", phone)
		local cd = me:GetAttribute("RobCooldownLeft") or 0
		make("TextLabel", {
			Size = UDim2.new(1, 0, 0, 24),
			BackgroundTransparency = 1,
			TextScaled = true,
			TextColor3 = Color3.fromRGB(220, 220, 220),
			Parent = phone,
			Text = cd > 0 and ("Cooldown: %d:%02d"):format(cd // 60, cd % 60) or "Pronto para agir",
		})
		local victim = input("Nome do jogador (até 8 studs)", phone)
		button("Assaltar", phone, function(b)
			local t = Players:FindFirstChild(victim.Text)
			if not t then
				flash(b, "Não encontrado", "Assaltar")
				return
			end
			local okR, r = remote("RobAttempt"):InvokeServer(t.UserId)
			if not okR and (r == "RateLimited" or r == "Invalid" or r == "ServerError") then
				flash(b, err(r), "Assaltar")
			end -- sucesso chega via RobberyResult
		end)
	end
	-- Garagem
	title("🚗 Garagem", phone)
	local okV, vehicles = remote("VehicleAction"):InvokeServer("list")
	for _, id in ipairs(okV and vehicles or {}) do
		local item = Catalog.Get(id)
		local l = "Chamar " .. (item and item.Name or id)
		button(l, phone, function(b)
			local k, r = remote("VehicleAction"):InvokeServer("spawn", id)
			flash(b, k and "Chegou!" or err(r), l)
		end)
	end
	button("Guardar veículo", phone, function()
		remote("VehicleAction"):InvokeServer("despawn")
	end)
	task.spawn(function()
		local k, v = remote("BankGet"):InvokeServer()
		if k and bankLabel then
			bankLabel.Text = "Banco: " .. R(v)
		end
	end)
end
task.spawn(function()
	remote("BankChanged").OnClientEvent:Connect(function(v)
		if bankLabel and bankLabel.Parent then
			bankLabel.Text = "Banco: " .. R(v)
		end
	end)
end)

button("🛒 Loja", bar, function()
	open("Loja")
end)
button("💼 Emprego", bar, function()
	open("Emprego")
end)
button("📱 Celular", bar, function()
	if not phone.Visible then
		renderPhone()
	end
	open("Celular")
end)
