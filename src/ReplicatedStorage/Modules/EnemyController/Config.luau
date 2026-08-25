--[[
	Config.luau
	-----------
	Konfigurasi terpusat untuk seluruh sistem Monster AI.
	Semua nilai tuning disimpan di sini agar mudah diubah
	tanpa menyentuh logic script lainnya.
--]]

local Config = {}

-----------------------------------------------------------------
-- MOVEMENT
-----------------------------------------------------------------
Config.PatrolSpeed      = 10    -- WalkSpeed saat patroli
Config.ChaseSpeed       = 18    -- WalkSpeed saat mengejar player

-----------------------------------------------------------------
-- DETECTION
-----------------------------------------------------------------
Config.DetectionRadius  = 45    -- Jarak maksimum deteksi player (studs)
Config.LoseTargetRadius = 58    -- Jarak dimana monster kehilangan target (1.3x detection)
Config.FieldOfView      = 160   -- Sudut pandang deteksi (derajat, dari arah hadap)

-----------------------------------------------------------------
-- CHASE MODE
-----------------------------------------------------------------
-- Mode pengejaran default. Bisa di-override per-monster lewat
-- Attribute "ChaseMode" (string) pada Model monster di Studio.
--   "PERSISTENT"  = kunci 1 target sampai MATI (abaikan jarak/LOS)
--   "NEAREST"     = kejar terdekat, boleh retarget dinamis (anti-thrash)
--   "ITEM_HOLDER" = prioritas pemegang Tool tertentu; fallback ke NEAREST
Config.ChaseMode        = "NEAREST"      -- PERSISTENT | NEAREST | ITEM_HOLDER
-- Mode ITEM_HOLDER menarget player yang memegang Tool ber-Attribute "MonsterBait" = true.
-- Cukup tag Tool-nya di Studio (Attributes > MonsterBait, tipe Bool, centang),
-- nama Tool bebas. Bisa banyak item berbeda sekaligus.
Config.BaitAttribute    = "MonsterBait"  -- Nama Attribute (Bool) penanda item pemicu

-- Give-up untuk mode PERSISTENT: 0 = kejar selamanya sampai target mati.
-- Jika >0, monster menyerah setelah sekian detik tak bisa menyentuh target.
Config.PersistentGiveUpTime = 0          -- detik (0 = tanpa give-up)

-----------------------------------------------------------------
-- ANTI-THRASH (retargeting) — mencegah monster "di-main-mainin"
-- oleh beberapa player yang gantian jadi umpan.
-- Berlaku untuk mode NEAREST & ITEM_HOLDER (tidak untuk PERSISTENT).
-----------------------------------------------------------------
Config.RetargetCommitTime = 2.5   -- Wajib komit ke target minimal sekian detik sebelum boleh switch
Config.RetargetInterval   = 1.0   -- Jeda evaluasi ganti-target (detik); bukan tiap tick
Config.RetargetHysteresis = 0.30  -- Kandidat baru harus >= sekian persen lebih dekat (0.30 = 30%)
Config.RetargetMinGap     = 8     -- ATAU minimal sekian studs lebih dekat

-----------------------------------------------------------------
-- COMBAT
-----------------------------------------------------------------
Config.AttackRadius     = 4     -- Jarak jangkauan serangan (studs)
Config.AttackCooldown   = 1.5   -- Cooldown antar serangan (detik)
Config.Damage           = 25    -- Damage per serangan

-----------------------------------------------------------------
-- PATROL
-----------------------------------------------------------------
Config.PatrolWaitTime   = 2     -- Waktu idle di setiap waypoint (detik)
Config.WaypointFolder   = "Waypoints" -- Nama folder waypoint

-----------------------------------------------------------------
-- SAFE ZONE
-----------------------------------------------------------------
Config.SafeZoneTag      = "SafeZone"  -- CollectionService tag untuk Safe Zone
Config.SafeZoneFolder   = "SafeZones" -- Nama folder Safe Zone di Workspace

-----------------------------------------------------------------
-- PATHFINDING
-----------------------------------------------------------------
Config.AgentRadius      = 2.5
Config.AgentHeight      = 5
Config.AgentCanJump     = true
Config.AgentJumpHeight  = 10
Config.WaypointSpacing  = 4
Config.PathTimeout      = 8     -- Timeout pathfinding (detik)

-----------------------------------------------------------------
-- MONSTER TAG (untuk CollectionService spawning)
-----------------------------------------------------------------
Config.MonsterTag       = "Monster"  -- Tag untuk auto-assign AI ke monster

-----------------------------------------------------------------
-- OVERRIDE PER-NPC (Attribute di Model monster)
-----------------------------------------------------------------
--[[
	Tiap NPC boleh punya spesifikasi berbeda TANPA mengubah script ini.
	Caranya: tambah Attribute di Properties Model monster, NAMA-nya sama
	persis dengan field di bawah, tipenya Number. Kalau Attribute tidak
	diisi -> pakai default global di atas.

	Contoh: monster bos ingin lebih cepat + lebih sakit ->
	  di Properties Model: ChaseSpeed = 26, Damage = 40.
	Monster lain tetap pakai default. Tidak perlu sentuh script apa pun.

	Field yang bisa di-override (semua Number):
	  PatrolSpeed, ChaseSpeed, DetectionRadius, LoseTargetRadius,
	  FieldOfView, AttackCooldown, Damage, PatrolWaitTime

	Catatan:
	  - AttackRadius TIDAK di sini: sudah dihitung adaptif dari ukuran NPC
	    (lihat TargetFinder.getAttackReach), Attribute "AttackRadius" tetap
	    jadi override khusus jalur itu.
	  - Nilai valid = number >= 0. Negatif / bukan number diabaikan (pakai
	    default) dan dilaporkan sekali via validateOverrides saat init.
--]]
local OVERRIDABLE: { [string]: true } = {
	PatrolSpeed      = true,
	ChaseSpeed       = true,
	DetectionRadius  = true,
	LoseTargetRadius = true,
	FieldOfView      = true,
	AttackCooldown   = true,
	Damage           = true,
	PatrolWaitTime   = true,
}

--- Ambil nilai config untuk sebuah monster: Attribute per-NPC > default global.
--- Dipakai di hot loop, jadi SILENT (tidak warn). Validasi & laporan sekali
--- dilakukan oleh validateOverrides() saat init.
--- @param model  Model monster (boleh nil -> selalu default)
--- @param key    Nama field Config
function Config.get(model: Instance?, key: string): any
	if model and OVERRIDABLE[key] then
		local attr = model:GetAttribute(key)
		-- number >= 0 dipakai; 0 sah (mis. Damage 0 = monster jinak).
		if typeof(attr) == "number" and attr >= 0 then
			return attr
		end
	end
	return Config[key]
end

--- Validasi SEKALI (saat init) semua Attribute override sebuah monster.
--- Melaporkan Attribute yang salah tipe / negatif lewat warn — supaya tim
--- tahu kenapa override-nya "tidak berefek", tanpa spam warn tiap tick.
--- Mengembalikan daftar pesan (kosong = semua benar / tidak ada override).
function Config.validateOverrides(model: Instance): { string }
	local problems = {}
	for key in OVERRIDABLE do
		local attr = model:GetAttribute(key)
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
	return problems
end

return Config
