-- Uso: lune run tests/run.luau
local process = require("@lune/process")
local T = require("./TestRunner")

for _, name in { "RideLogic.spec", "InteractLogic.spec", "ArrestLogic.spec", "MedicLogic.spec" } do
	require("./" .. name)(T)
end

for _, f in T.failures do
	print("FALHOU  " .. f)
end
print(("%d passaram, %d falharam"):format(T.passed, T.failed))
process.exit(T.failed == 0 and 0 or 1)
