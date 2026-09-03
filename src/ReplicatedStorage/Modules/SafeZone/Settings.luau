--[[
	Settings.luau
	-------------
	Resolver Attribute per-bilik: Attribute pada Part MENANG, kalau tidak
	ada pakai default global di Config.

	Pola ini identik dengan Config.get milik EnemyController — sengaja,
	supaya tim tidak perlu menghafal dua aturan berbeda. Nama Attribute =
	nama field Config.

	Pembagian tugas:
	  get()      dipakai di hot loop -> SILENT (tidak warn)
	  validate() dipanggil SEKALI saat bilik didaftarkan -> melaporkan
	             Attribute salah tipe/negatif lewat warn, supaya salah
	             ketik tidak senyap.
--]]

local Config = require(script.Parent.Config)

local Settings = {}

--- Ambil setelan sebuah bilik. Attribute Part > default Config.
function Settings.get(zonePart: BasePart, key: string): any
	if Config.NumberOverrides[key] then
		local attr = zonePart:GetAttribute(key)
		-- 0 sah (mis. CooldownTime = 0 = bisa langsung dipakai lagi).
		if typeof(attr) == "number" and attr >= 0 then
			return attr
		end
	elseif Config.BoolOverrides[key] then
		local attr = zonePart:GetAttribute(key)
		if typeof(attr) == "boolean" then
			return attr
		end
		-- Bool tanpa default global (NoBarrier/NoBreath) -> anggap false.
		if Config[key] == nil then
			return false
		end
	end

	return Config[key]
end

--- Kapasitas bilik sebagai integer >= 1.
--- MaxOccupants = 0 akan membuat bilik tidak berguna sama sekali, jadi
--- dibulatkan ke minimal 1 (dilaporkan oleh validate).
function Settings.capacity(zonePart: BasePart): number
	local raw = Settings.get(zonePart, "MaxOccupants")
	if typeof(raw) ~= "number" then
		raw = Config.MaxOccupants
	end
	return math.max(1, math.floor(raw))
end

--- Validasi SEKALI semua Attribute sebuah bilik.
--- @return { string }  daftar masalah (kosong = beres)
function Settings.validate(zonePart: BasePart): { string }
	local problems = {}

	for key in Config.NumberOverrides do
		local attr = zonePart:GetAttribute(key)
		if attr ~= nil then
			if typeof(attr) ~= "number" then
				table.insert(problems, string.format(
					"Attribute '%s' bertipe %s (harus Number) -> diabaikan, pakai default %s",
					key, typeof(attr), tostring(Config[key])))
			elseif attr < 0 then
				table.insert(problems, string.format(
					"Attribute '%s' = %s (negatif) -> diabaikan, pakai default %s",
					key, tostring(attr), tostring(Config[key])))
			end
		end
	end

	for key in Config.BoolOverrides do
		local attr = zonePart:GetAttribute(key)
		if attr ~= nil and typeof(attr) ~= "boolean" then
			table.insert(problems, string.format(
				"Attribute '%s' bertipe %s (harus Bool) -> diabaikan",
				key, typeof(attr)))
		end
	end

	local rawCap = zonePart:GetAttribute("MaxOccupants")
	if typeof(rawCap) == "number" and rawCap >= 0 and math.floor(rawCap) < 1 then
		table.insert(problems, string.format(
			"Attribute 'MaxOccupants' = %s -> dibulatkan ke 1 (bilik dengan kapasitas 0 tidak berguna)",
			tostring(rawCap)))
	end

	return problems
end

return Settings
