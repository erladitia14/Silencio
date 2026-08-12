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

return Config
