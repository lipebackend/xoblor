-- Configuração da detecção de AFK (só servidor). Usada para não pagar salário a quem está parado.
return {
	TIMEOUT = 300, -- segundos sem atividade para ser AFK (5 min)
	MOVE_THRESHOLD = 4, -- studs de deslocamento desde a última âncora para contar como movimento
	SAMPLE_INTERVAL = 2, -- segundos entre amostras de posição
	-- interação sem movimento conta por no máximo isto depois do último movimento (anti-spam de prompt)
	INTERACTION_ONLY_MAX = 600,
	-- ProximityPrompts que contam como atividade (ver AfkService.Classify). Remotes genéricos não contam.
	INTERACTIONS = {
		JobPrompt = true, -- estação de emprego (JobService)
		InteractPrompt = true, -- loja e caixa eletrônico (InteractService)
		HouseDoor = true, -- porta de casa (HouseService)
	},
}
