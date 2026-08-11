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
