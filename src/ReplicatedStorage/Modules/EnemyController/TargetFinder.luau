--[[
	TargetFinder.luau
	-----------------
	Bertanggung jawab untuk mencari dan memvalidasi target player.
	
	Fitur:
	  - Distance check dengan Detection Radius
	  - Field of View (FOV) angle check
	  - Line of Sight (LOS) raycasting
	  - Safe Zone filtering (player di safe zone tidak ditarget)
	  - Hanya menarget player yang masih hidup

	Catatan tentang FOV vs 360:
	  Parameter `ignoreFOV` (opsional) melewati pengecekan sudut pandang.
	  Dipakai saat monster SUDAH dalam mode berburu (CHASING / re-acquire
	  pasca-kill) supaya monster jadi "waspada 360 derajat". Untuk AKUISISI
	  awal (IDLE/PATROL) FOV tetap dihormati agar realistis.
--]]

local Players = game:GetService("Players")

local Config          = require(script.Parent.Config)
local SafeZoneManager = require(script.Parent.SafeZoneManager)
local SkinBinder      = require(script.Parent.SkinBinder)

local TargetFinder = {}

--- Cek apakah target berada dalam Field of View monster.
function TargetFinder:_isInFieldOfView(monsterModel: Model, monsterRoot: BasePart, targetPos: Vector3): boolean
	local direction = (targetPos - monsterRoot.Position)
	local lookDir = monsterRoot.CFrame.LookVector
	local dirToTarget = direction.Unit

	local dotProduct = math.clamp(lookDir:Dot(dirToTarget), -1, 1)
	local angle = math.deg(math.acos(dotProduct))

	return angle <= (Config.get(monsterModel, "FieldOfView") / 2)
end

--- Raycast dari monster ke target untuk memastikan tidak ada
--- obstacle yang menghalangi pandangan (Line of Sight).
--- @param ignoreFOV  Jika true, lewati pengecekan FOV (deteksi 360 derajat).
function TargetFinder:_hasLineOfSight(monsterModel: Model, monsterRoot: BasePart, targetChar: Model, ignoreFOV: boolean?): boolean
	local targetRoot = targetChar:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not targetRoot then return false end

	local origin = monsterRoot.Position + Vector3.new(0, 1.5, 0)
	local direction = (targetRoot.Position - origin)

	-- Distance check
	if direction.Magnitude > Config.get(monsterModel, "DetectionRadius") then
		return false
	end

	-- FOV check (dilewati saat ignoreFOV = true)
	if not ignoreFOV and not self:_isInFieldOfView(monsterModel, monsterRoot, targetRoot.Position) then
		return false
	end

	-- Raycast.
	-- PENTING: kecualikan rig DAN skin visualnya. Pada pola "driver + skin"
	-- mesh badan monster berada di LUAR model rig (sibling di folder yang
	-- sama), jadi kalau tidak difilter ray langsung menabrak badan monster
	-- sendiri dari jarak <1 stud -> LOS selalu gagal -> monster buta permanen.
	-- CanCollide = false tidak menolong: raycast tetap mengenai part non-collide.
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = SkinBinder:getIgnoreList(monsterModel)
	rayParams.IgnoreWater = true

	local result = workspace:Raycast(origin, direction, rayParams)
	if result and result.Instance:IsDescendantOf(targetChar) then
		return true
	end

	return false
end

--- Cek apakah sebuah karakter masih valid sebagai target:
---   - Karakter masih ada di world
---   - Memiliki HumanoidRootPart
---   - Humanoid masih hidup (Health > 0)
---   - Tidak berada di Safe Zone
function TargetFinder:isValidTarget(character: Model?): boolean
	if not character or not character.Parent then
		return false
	end

	if not character:FindFirstChild("HumanoidRootPart") then
		return false
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return false
	end

	if SafeZoneManager:isInSafeZone(character) then
		return false
	end

	return true
end

--- Mencari player terdekat yang valid sebagai target.
--- Mengembalikan Player dan Character, atau nil jika tidak ditemukan.
--- @param ignoreFOV  Jika true, deteksi 360 derajat (untuk mode berburu).
function TargetFinder:findNearest(monsterModel: Model, ignoreFOV: boolean?): (Player?, Model?)
	local monsterRoot = monsterModel:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not monsterRoot then
		return nil, nil
	end

	local closestDist = Config.get(monsterModel, "DetectionRadius")
	local bestPlayer: Player? = nil
	local bestChar: Model? = nil

	for _, player in Players:GetPlayers() do
		local char = player.Character
		if char and self:isValidTarget(char) then
			local targetRoot = char:FindFirstChild("HumanoidRootPart") :: BasePart
			local dist = (monsterRoot.Position - targetRoot.Position).Magnitude

			if dist < closestDist and self:_hasLineOfSight(monsterModel, monsterRoot, char, ignoreFOV) then
				closestDist = dist
				bestPlayer = player
				bestChar = char
			end
		end
	end

	return bestPlayer, bestChar
end

--- Cek apakah target masih dalam jangkauan pengejaran.
--- Menggunakan LoseTargetRadius (lebih besar dari DetectionRadius)
--- untuk mencegah "flickering" state.
function TargetFinder:isInChaseRange(monsterModel: Model, targetChar: Model): boolean
	local monsterRoot = monsterModel:FindFirstChild("HumanoidRootPart") :: BasePart?
	local targetRoot = targetChar:FindFirstChild("HumanoidRootPart") :: BasePart?

	if not monsterRoot or not targetRoot then
		return false
	end

	return (monsterRoot.Position - targetRoot.Position).Magnitude <= Config.get(monsterModel, "LoseTargetRadius")
end

---------------------------------------------------------------------
-- JANGKAUAN SERANG ADAPTIF
---------------------------------------------------------------------
--[[
	MASALAH: Config.AttackRadius diukur PUSAT ke PUSAT (root ke root).
	Untuk NPC raksasa itu tidak cukup — badannya lebar dan root-nya tinggi,
	jadi saat player sudah menempel di badan monster, jarak antar-pusat
	masih jauh melebihi radius. Akibatnya monster besar tidak pernah
	bisa menyerang.

	Contoh nyata (NPC tinggi 12 studs vs Config.AttackRadius = 4):
	  radius badan 3.33 + radius player 1.0 = 4.33 studs horizontal
	  selisih tinggi root                   = 4.94 studs
	  -> jarak pusat-pusat 6.56 studs, DI LUAR radius 4.

	SOLUSI: hitung jangkauan dari UKURAN NPC itu sendiri, sehingga monster
	kecil tetap harus dekat sementara monster raksasa dapat jangkauan
	proporsional. Tim bisa membuat NPC ukuran apa pun tanpa tuning manual.

	Override manual tetap tersedia: Attribute "AttackRadius" (number) pada
	Model monster mengunci nilainya, mengabaikan perhitungan otomatis.
--]]

-- Cache per-monster: ukuran model tidak berubah tiap tick, jadi jangan
-- panggil GetExtentsSize() 10x/detik untuk setiap monster.
local reachCache: { [Model]: number } = {}

--- Perkiraan radius tubuh player R15 standar (studs).
local PLAYER_RADIUS = 1.0

--- Hitung jangkauan serang efektif untuk sebuah monster.
--- Mengembalikan jarak pusat-ke-pusat maksimum yang dihitung sebagai "menempel".
function TargetFinder:getAttackReach(monsterModel: Model): number
	-- 1. Override manual per-monster
	local attr = monsterModel:GetAttribute("AttackRadius")
	if typeof(attr) == "number" and attr > 0 then
		return attr
	end

	-- 2. Cache
	local cached = reachCache[monsterModel]
	if cached then
		return cached
	end

	-- 3. Hitung dari ukuran NPC
	local reach = Config.AttackRadius

	local ok, extents = pcall(function()
		return monsterModel:GetExtentsSize()
	end)

	if ok and extents then
		local monsterRoot = monsterModel:FindFirstChild("HumanoidRootPart") :: BasePart?

		-- Komponen horizontal: setengah lebar badan + radius player
		local bodyRadius = math.max(extents.X, extents.Z) / 2
		local horizontal = bodyRadius + PLAYER_RADIUS

		-- Komponen vertikal: selisih tinggi root monster vs root player.
		-- Player R15 standar punya root ~3 studs di atas kaki; kalau root
		-- monster jauh lebih tinggi, selisih ini yang bikin jarak melonjak.
		local vertical = 0
		if monsterRoot then
			local lowest = math.huge
			for _, part in monsterModel:GetChildren() do
				if part:IsA("BasePart") then
					lowest = math.min(lowest, part.Position.Y - part.Size.Y / 2)
				end
			end
			if lowest < math.huge then
				local rootHeight = monsterRoot.Position.Y - lowest
				vertical = math.max(0, rootHeight - 3.0)
			end
		end

		local computed = math.sqrt(horizontal * horizontal + vertical * vertical)

		-- Beri sedikit kelonggaran supaya serangan tidak pas-pasan di ambang,
		-- lalu jangan sampai LEBIH KECIL dari nilai Config (monster kecil
		-- tetap memakai jangkauan minimal yang sudah di-tune).
		reach = math.max(Config.AttackRadius, computed * 1.15)
	end

	reachCache[monsterModel] = reach
	return reach
end

--- Buang cache jangkauan (dipakai bila ukuran monster berubah saat runtime).
function TargetFinder:invalidateReach(monsterModel: Model?)
	if monsterModel then
		reachCache[monsterModel] = nil
	else
		reachCache = {}
	end
end

--- Cek apakah target berada dalam jangkauan serang.
--- Jangkauan menyesuaikan ukuran monster (lihat getAttackReach).
function TargetFinder:isInAttackRange(monsterModel: Model, targetChar: Model): boolean
	local monsterRoot = monsterModel:FindFirstChild("HumanoidRootPart") :: BasePart?
	local targetRoot = targetChar:FindFirstChild("HumanoidRootPart") :: BasePart?

	if not monsterRoot or not targetRoot then
		return false
	end

	local dist = (monsterRoot.Position - targetRoot.Position).Magnitude
	return dist <= self:getAttackReach(monsterModel)
end

--- Cek apakah sebuah karakter (player) sedang membawa Tool yang di-tag
--- sebagai umpan monster, yaitu Tool dengan Attribute Config.BaitAttribute = true.
--- Nama Tool bebas; cukup di-tag di Studio. Mengecek Tool yang sedang
--- di-equip (child Character) DAN yang tersimpan di Backpack.
function TargetFinder:holdsTargetItem(character: Model?): boolean
	if not character then
		return false
	end

	local attr = Config.BaitAttribute

	-- Equipped di Character (Tool jadi child langsung saat di-equip)
	for _, child in character:GetChildren() do
		if child:IsA("Tool") and child:GetAttribute(attr) == true then
			return true
		end
	end

	-- Tersimpan di Backpack
	local player = Players:GetPlayerFromCharacter(character)
	if player then
		local backpack = player:FindFirstChildOfClass("Backpack")
		if backpack then
			for _, child in backpack:GetChildren() do
				if child:IsA("Tool") and child:GetAttribute(attr) == true then
					return true
				end
			end
		end
	end

	return false
end

--- Mencari player pemegang item terdekat yang valid.
--- Mengembalikan (Player?, Model?) - nil jika tidak ada holder yang terlihat.
--- @param ignoreFOV  Jika true, deteksi 360 derajat (untuk mode berburu).
function TargetFinder:findItemHolder(monsterModel: Model, ignoreFOV: boolean?): (Player?, Model?)
	local monsterRoot = monsterModel:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not monsterRoot then
		return nil, nil
	end

	local closestDist = Config.get(monsterModel, "DetectionRadius")
	local bestPlayer: Player? = nil
	local bestChar: Model? = nil

	for _, player in Players:GetPlayers() do
		local char = player.Character
		if char and self:isValidTarget(char) and self:holdsTargetItem(char) then
			local targetRoot = char:FindFirstChild("HumanoidRootPart") :: BasePart
			local dist = (monsterRoot.Position - targetRoot.Position).Magnitude

			if dist < closestDist and self:_hasLineOfSight(monsterModel, monsterRoot, char, ignoreFOV) then
				closestDist = dist
				bestPlayer = player
				bestChar = char
			end
		end
	end

	return bestPlayer, bestChar
end

--- Dispatcher AKUISISI target berdasarkan mode chase.
--- Dipakai di state IDLE & PATROL untuk keputusan "siapa yang dilirik".
---   PERSISTENT / NEAREST -> findNearest
---   ITEM_HOLDER          -> findItemHolder, fallback findNearest bila tak ada holder
--- @param ignoreFOV  Jika true, deteksi 360 derajat (untuk re-acquire pasca-kill).
function TargetFinder:acquireTarget(monsterModel: Model, mode: string, ignoreFOV: boolean?): (Player?, Model?)
	if mode == "ITEM_HOLDER" then
		local p, c = self:findItemHolder(monsterModel, ignoreFOV)
		if p and c then
			return p, c
		end
		-- Fallback: tidak ada pemegang item -> kejar yang terdekat
		return self:findNearest(monsterModel, ignoreFOV)
	end

	-- PERSISTENT & NEAREST sama-sama akuisisi awal = terdekat
	return self:findNearest(monsterModel, ignoreFOV)
end

--- Jarak monster -> karakter (helper untuk logika retarget).
--- Mengembalikan math.huge bila salah satu root tak ada.
function TargetFinder:distanceTo(monsterModel: Model, targetChar: Model?): number
	if not targetChar then
		return math.huge
	end
	local monsterRoot = monsterModel:FindFirstChild("HumanoidRootPart") :: BasePart?
	local targetRoot = targetChar:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not monsterRoot or not targetRoot then
		return math.huge
	end
	return (monsterRoot.Position - targetRoot.Position).Magnitude
end

return TargetFinder
