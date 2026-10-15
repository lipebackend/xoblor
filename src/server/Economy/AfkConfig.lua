-- Configuração da detecção de AFK (só servidor). Usada para não pagar salário a quem está parado.
return {
	TIMEOUT = 300, -- segundos sem atividade para ser AFK (5 min)
	MOVE_THRESHOLD = 4, -- studs de deslocamento desde a última âncora para contar como movimento
	SAMPLE_INTERVAL = 2, -- segundos entre amostras de posição
}
