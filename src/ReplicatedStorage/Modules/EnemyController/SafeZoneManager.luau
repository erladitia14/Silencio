--[[
	SafeZoneManager.luau
	--------------------
	JEMBATAN antara core AI (EnemyController) dan sistem Safe Zone.

	Dulu modul ini menghitung sendiri "apakah karakter di dalam Part
	ber-tag SafeZone". Sekarang Safe Zone punya state (napas, kapasitas,
	cooldown) yang dimiliki ZoneService di ServerScriptService, jadi
	pertanyaan yang benar bukan lagi "di dalam?" tapi "DILINDUNGI?".

	Bedanya nyata: pemain yang berdiri di bilik dengan napas habis, atau
	di bilik yang sudah dipakai orang lain, TIDAK terlindungi — monster
	tetap boleh menargetnya.

	API-nya sengaja tidak berubah (`isInSafeZone`) supaya TargetFinder dan
	EnemyController tidak perlu disentuh.

	FALLBACK: kalau modul SafeZone tidak ada di place (mis. tim memakai
	EnemyController tanpa sistem bilik), modul ini jatuh ke perilaku lama
	— deteksi geometris murni, tanpa timer. Jadi menghapus folder SafeZone
	tidak mematikan AI.
--]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(script.Parent.Config)

local SafeZoneManager = {}

---------------------------------------------------------------------
-- SAMBUNGAN KE SISTEM SAFE ZONE (opsional)
---------------------------------------------------------------------

local zoneService: any = nil
local resolved = false

--- Cari ZoneService sekali saja. Tidak memakai WaitForChild supaya
--- tidak menahan AI kalau sistem bilik memang tidak dipasang.
local function getZoneService(): any
	if resolved then
		return zoneService
	end
	resolved = true

	local modules = ReplicatedStorage:FindFirstChild("Modules")
	local folder = modules and modules:FindFirstChild("SafeZone")
	local module = folder and folder:FindFirstChild("ZoneService")

	if module and module:IsA("ModuleScript") then
		local ok, result = pcall(require, module)
		if ok then
			zoneService = result
		else
			warn("[SafeZone] ZoneService gagal dimuat -> pakai deteksi geometris saja: " .. tostring(result))
		end
	end

	return zoneService
end

---------------------------------------------------------------------
-- FALLBACK GEOMETRIS (perilaku lama)
---------------------------------------------------------------------

--- Kumpulkan Part Safe Zone. Mengembalikan tabel baru — tidak memutasi
--- hasil GetTagged (bug #6 lama, sekarang benar-benar ditutup).
function SafeZoneManager:_gatherZoneParts(): { BasePart }
	local parts: { BasePart } = {}
	local seen: { [Instance]: boolean } = {}

	local function add(inst: Instance)
		if inst:IsA("BasePart") and not seen[inst] then
			seen[inst] = true
			table.insert(parts, inst)
		end
	end

	for _, tagged in CollectionService:GetTagged(Config.SafeZoneTag) do
		add(tagged)
	end

	local container = workspace:FindFirstChild(Config.SafeZoneFolder)
	if container then
		add(container)
		for _, child in container:GetDescendants() do
			add(child)
		end
	end

	return parts
end

--- Cek titik di dalam Oriented Bounding Box sebuah Part.
function SafeZoneManager:_isPointInsidePart(point: Vector3, part: BasePart): boolean
	if (part.Position - point).Magnitude > (part.Size.Magnitude / 2) + 2 then
		return false
	end

	local localPos = part.CFrame:PointToObjectSpace(point)
	local half = part.Size / 2

	return math.abs(localPos.X) <= half.X
		and math.abs(localPos.Y) <= half.Y
		and math.abs(localPos.Z) <= half.Z
end

--- Deteksi geometris murni (tanpa napas/kapasitas). Dipakai sebagai
--- fallback, dan tetap berguna untuk sistem lain yang cuma butuh tahu
--- posisi.
function SafeZoneManager:isInsideZoneGeometry(character: Model): boolean
	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not rootPart then
		return false
	end

	for _, zonePart in self:_gatherZoneParts() do
		if zonePart.Parent and self:_isPointInsidePart(rootPart.Position, zonePart) then
			return true
		end
	end

	return false
end

---------------------------------------------------------------------
-- API YANG DIPAKAI CORE AI
---------------------------------------------------------------------

--- Apakah karakter ini terlindungi Safe Zone?
--- Nama fungsi dipertahankan agar TargetFinder & EnemyController tidak
--- perlu diubah; artinya sekarang "dilindungi", bukan sekadar "di dalam".
function SafeZoneManager:isInSafeZone(character: Model): boolean
	if not character then
		return false
	end

	local service = getZoneService()
	if service then
		return service:isProtected(character)
	end

	return self:isInsideZoneGeometry(character)
end

--- KHUSUS UJI: lupakan sambungan supaya bisa diuji dua-duanya
--- (dengan & tanpa ZoneService) dalam satu sesi.
function SafeZoneManager:_resetBinding()
	zoneService = nil
	resolved = false
end

return SafeZoneManager
