-- Painel das lojas e caixas eletrônicos do mapa (InteractService). Só exibe; o servidor decide tudo.
local RS = game:GetService("ReplicatedStorage")
local Catalog = require(RS:WaitForChild("Shared"):WaitForChild("ShopCatalog"))
local Remotes = RS:WaitForChild("Remotes")
local gui = script.Parent
local R = Catalog.FormatReais

local openEvent = Remotes:WaitForChild("InteractOpen", 60)
if not openEvent then
	return
end
local storeBuy = Remotes:WaitForChild("StoreBuy", 10)
local atmAction = Remotes:WaitForChild("AtmAction", 10)
local closeRemote = Remotes:WaitForChild("InteractClose", 10)

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
	return make("UICorner", { CornerRadius = UDim.new(0, 8) })
end

local ERR = {
	InsufficientFunds = "Sem grana",
	WrongJob = "Emprego errado",
	AlreadyOwned = "Já tem",
	WrongStore = "Não vende aqui",
	Jailed = "Você está preso",
	TooFar = "Chegue mais perto",
	Expired = "Abra de novo",
	NoSession = "Abra de novo",
	WrongPlace = "Abra de novo",
	RateLimited = "Calma aí",
	Invalid = "Valor inválido",
	ServerError = "Erro, tente de novo",
}
local function err(res)
	return ERR[res] or tostring(res)
end

local frame = make("ScrollingFrame", {
	Name = "Interacao",
	Size = UDim2.fromOffset(300, 420),
	Position = UDim2.new(0.5, -150, 0.5, -210),
	BackgroundColor3 = Color3.fromRGB(30, 30, 30),
	Visible = false,
	CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	Parent = gui,
}, {
	corner(),
	make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
	make("UIPadding", { PaddingTop = UDim.new(0, 8), PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }),
})

local order = 0
local function add(class, props)
	order += 1
	props.LayoutOrder = order
	props.Parent = frame
	if class ~= "TextBox" then
		props.TextScaled = true
	end
	return make(class, props, class ~= "TextLabel" and { corner() } or nil)
end
local function label(text, color)
	return add("TextLabel", {
		Size = UDim2.new(1, 0, 0, 28),
		BackgroundTransparency = 1,
		TextColor3 = color or Color3.new(1, 1, 1),
		Text = text,
	})
end
local function button(text, cb, color)
	local b = add("TextButton", {
		Size = UDim2.new(1, 0, 0, 34),
		BackgroundColor3 = color or Color3.fromRGB(0, 156, 59),
		TextColor3 = Color3.new(1, 1, 1),
		Text = text,
	})
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

local function close()
	frame.Visible = false
	if closeRemote then
		closeRemote:InvokeServer()
	end
end

local function reset(titleText)
	for _, c in frame:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	order = 0
	label(titleText)
	frame.Visible = true
end

local function renderShop(data)
	reset("🛒 " .. tostring(data.Name))
	for _, id in ipairs(type(data.Items) == "table" and data.Items or {}) do
		local item = Catalog.Get(id)
		if item then
			local text = ("%s  %s%s"):format(
				item.Name,
				item.Price > 0 and R(item.Price) or "Grátis",
				item.RequiredJob and (" (" .. item.RequiredJob .. ")") or ""
			)
			button(text, function(b)
				local ok, res = storeBuy:InvokeServer(id)
				flash(b, ok and "Comprado!" or err(res), text)
			end)
		end
	end
	button("Fechar", close, Color3.fromRGB(90, 90, 90))
end

local function renderAtm(data)
	reset("🏧 " .. tostring(data.Name))
	local walletLabel = label("", Color3.fromRGB(255, 223, 0))
	local bankLabel = label("", Color3.fromRGB(120, 200, 255))
	local function show(w, b)
		walletLabel.Text = "Carteira: " .. R(tonumber(w) or 0)
		bankLabel.Text = "Banco: " .. R(tonumber(b) or 0)
	end
	show(data.Wallet, data.Bank)
	local box = add("TextBox", {
		Size = UDim2.new(1, 0, 0, 30),
		PlaceholderText = "Valor (R$)",
		Text = "",
		TextScaled = true,
		ClearTextOnFocus = false,
	})
	local function act(action, b, original)
		local n = tonumber(box.Text)
		local ok, res = atmAction:InvokeServer(action, n and math.floor(n) or nil)
		if ok and type(res) == "table" then
			show(res.Wallet, res.Bank)
			flash(b, "Feito!", original)
		else
			flash(b, err(res), original)
		end
	end
	button("Depositar", function(b)
		act("deposit", b, "Depositar")
	end)
	button("Sacar", function(b)
		act("withdraw", b, "Sacar")
	end)
	button("Ver saldo", function(b)
		act("balance", b, "Ver saldo")
	end, Color3.fromRGB(0, 90, 160))
	button("Fechar", close, Color3.fromRGB(90, 90, 90))
end

openEvent.OnClientEvent:Connect(function(data)
	if type(data) ~= "table" then
		return
	end
	if data.Kind == "Shop" then
		renderShop(data)
	elseif data.Kind == "ATM" then
		renderAtm(data)
	end
end)
