-- Catálogo do xoblor. Preços em R$ (inteiros). Preço vale SÓ no servidor.
-- Category: Comida | Roupa | Veiculo | Casa | GamePass
local Catalog = {
	Items = {
		acai = { Id = "acai", Name = "Açaí", Price = 12, Category = "Comida", Hunger = 25, Energy = 30 },
		pastel = { Id = "pastel", Name = "Pastel de Feira", Price = 8, Category = "Comida", Hunger = 35, Energy = 10 },
		mate_gelado = {
			Id = "mate_gelado",
			Name = "Mate Gelado",
			Price = 5,
			Category = "Comida",
			Hunger = 5,
			Energy = 20,
		},
		uniforme_policia = {
			Id = "uniforme_policia",
			Name = "Uniforme de Policial",
			Price = 0,
			Category = "Roupa",
			Unique = true,
			RequiredJob = "policial",
		},
		jaleco = {
			Id = "jaleco",
			Name = "Jaleco de Médico",
			Price = 0,
			Category = "Roupa",
			Unique = true,
			RequiredJob = "medico",
		},
		camisa_flamengo = {
			Id = "camisa_flamengo",
			Name = "Camisa Rubro-Negra",
			Price = 150,
			Category = "Roupa",
			Unique = true,
		},
		bike = { Id = "bike", Name = "Bicicleta", Price = 300, Category = "Veiculo", Unique = true },
		moto_cg = { Id = "moto_cg", Name = "Moto 160", Price = 4500, Category = "Veiculo", Unique = true },
		fusca = { Id = "fusca", Name = "Fusca", Price = 9000, Category = "Veiculo", Unique = true },
		viatura = {
			Id = "viatura",
			Name = "Viatura",
			Price = 0,
			Category = "Veiculo",
			Unique = true,
			RequiredJob = "policial",
		},
	},
	-- Casas: Rent = R$ por período; RentMinutes = tempo de jogo; Price = compra.
	Houses = {
		morro_1 = {
			Id = "morro_1",
			Name = "Casa no Morro",
			Bairro = "Morro",
			Rent = 80,
			RentMinutes = 60,
			Price = 3000,
		},
		zn_1 = {
			Id = "zn_1",
			Name = "Casa na Zona Norte",
			Bairro = "Zona Norte",
			Rent = 150,
			RentMinutes = 60,
			Price = 8000,
		},
		copa_1 = {
			Id = "copa_1",
			Name = "Apê em Copacabana",
			Bairro = "Copacabana",
			Rent = 400,
			RentMinutes = 60,
			Price = 25000,
		},
		barra_1 = {
			Id = "barra_1",
			Name = "Mansão na Barra",
			Bairro = "Barra",
			Rent = 1000,
			RentMinutes = 60,
			Price = 80000,
		},
	},
}
function Catalog.Get(id)
	return Catalog.Items[id]
end
function Catalog.GetHouse(id)
	return Catalog.Houses[id]
end
function Catalog.FormatReais(n)
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1."):reverse()
	return "R$ " .. out:gsub("^%.", "")
end
return Catalog
