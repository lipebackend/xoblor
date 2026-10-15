-- Runner mínimo: describe/it/expect, sem dependências.
local T = { passed = 0, failed = 0, failures = {} }
local prefix = ""

function T.describe(name, fn)
	local old = prefix
	prefix = old .. name .. " > "
	fn()
	prefix = old
end

function T.it(name, fn)
	local ok, err = pcall(fn)
	if ok then
		T.passed += 1
	else
		T.failed += 1
		table.insert(T.failures, prefix .. name .. ": " .. tostring(err))
	end
end

local function fmt(v)
	return type(v) == "string" and ("%q"):format(v) or tostring(v)
end

function T.eq(actual, expected, msg)
	if actual ~= expected then
		error(("%sesperado %s, veio %s"):format(msg and (msg .. ": ") or "", fmt(expected), fmt(actual)), 2)
	end
end

function T.truthy(v, msg)
	if not v then
		error(msg or "esperado verdadeiro", 2)
	end
end

return T
