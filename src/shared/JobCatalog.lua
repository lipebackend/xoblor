-- Empregos do xoblor. Salary = R$ por ciclo (60s) ou por corrida (PayPerRide).
local JobCatalog = {
	PAY_INTERVAL = 60,
	XP_PER_LEVEL = 100,
	LEVEL_BONUS = 0.10,
	Jobs = {
		mate = { Id = "mate", Name = "Vendedor de Mate", Salary = 15, Team = "Civis" },
		mototaxi = { Id = "mototaxi", Name = "Mototaxista", Salary = 25, Team = "Mototaxistas", PayPerRide = true },
		mecanico = { Id = "mecanico", Name = "Mecânico", Salary = 30, Team = "Civis" },
		policial = { Id = "policial", Name = "Policial", Salary = 35, Team = "Polícia" },
		medico = { Id = "medico", Name = "Médico", Salary = 40, Team = "Saúde" },
	},
	Teams = {
		Civis = BrickColor.new("Medium stone grey"),
		["Polícia"] = BrickColor.new("Really blue"),
		["Saúde"] = BrickColor.new("White"),
		Mototaxistas = BrickColor.new("Bright yellow"),
	},
}

function JobCatalog.Get(id)
	return JobCatalog.Jobs[id]
end

function JobCatalog.Level(xp)
	return math.floor((xp or 0) / JobCatalog.XP_PER_LEVEL) + 1
end

function JobCatalog.SalaryFor(id, xp, multiplier)
	local job = JobCatalog.Jobs[id]
	if not job then
		return 0
	end
	local bonus = 1 + (JobCatalog.Level(xp) - 1) * JobCatalog.LEVEL_BONUS
	return math.floor(job.Salary * bonus * (multiplier or 1))
end

return JobCatalog
