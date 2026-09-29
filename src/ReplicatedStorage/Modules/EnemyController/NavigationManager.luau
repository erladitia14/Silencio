--[[
	NavigationManager.luau
	----------------------
	Mengelola navigasi NPC menggunakan PathfindingService.
	
	Fitur:
	  - Pathfinding dengan parameter agent yang bisa dikonfigurasi
	  - Fallback ke MoveTo langsung jika path gagal dikomputasi
	  - Interrupt check selama navigasi (untuk pembatalan chase)
	  - Jump handling otomatis
	  - Anggaran waktu ADAPTIF mengikuti jarak + kecepatan
	  - Deteksi MACET berbasis kemajuan, bukan jam dinding
--]]

local PathfindingService = game:GetService("PathfindingService")

local Config = require(script.Parent.Config)

local NavigationManager = {}

--- Membuat path agent parameters dari Config.
function NavigationManager:_createPathParams(): { [string]: any }
	return {
		AgentRadius     = Config.AgentRadius,
		AgentHeight     = Config.AgentHeight,
		AgentCanJump    = Config.AgentCanJump,
		AgentJumpHeight = Config.AgentJumpHeight,
		WaypointSpacing = Config.WaypointSpacing,
	}
end

--- Hitung anggaran waktu tempuh untuk sebuah jarak pada kecepatan tertentu.
---
--- KENAPA INI ADA: dulu pemanggil mengirim timeout tetap (5 detik). Itu cukup
--- hanya untuk 50 stud @WalkSpeed 10, padahal jarak nyata bisa 200+ stud
--- (spawn monster -> Waypoint1) dan 110 stud (W6->W7). Akibatnya moveTo selalu
--- gagal, state langsung pindah IDLE, dan waypoint DI-SKIP -> monster tampak
--- diam di tempat. Sekarang anggarannya tumbuh mengikuti jarak.
---
--- @param speed     WalkSpeed yang berlaku SAAT INI (patroli vs chase beda)
--- @param distance  jarak lurus ke tujuan (stud)
--- @return number   anggaran waktu (detik)
function NavigationManager:getTravelBudget(speed: number, distance: number): number
	local margin = Config.PathTimeMargin or 3
	local slack  = Config.PathTimeSlack or 10
	local base   = Config.PathTimeout or 8

	-- Hindari pembagian nol kalau WalkSpeed belum di-set.
	local effectiveSpeed = (speed and speed > 0.1) and speed or 10

	-- Jalur hasil pathfinding selalu lebih panjang dari garis lurus (berbelok,
	-- memutar sudut). `margin` menutup selisih itu, `slack` menutup percepatan
	-- awal & jeda animasi.
	local byDistance = (distance / effectiveSpeed) * margin + slack

	return math.max(base, byDistance)
end

--- Navigasi monster ke posisi tujuan menggunakan PathfindingService.
--- 
--- @param humanoid      Humanoid milik monster
--- @param rootPart      HumanoidRootPart milik monster
--- @param destination   Posisi tujuan
--- @param shouldAbort   Fungsi callback yang dipanggil setiap tick.
---                      Jika return true, navigasi dibatalkan.
--- @param timeout       Lantai anggaran waktu (opsional). BUKAN batas mati:
---                      anggaran sebenarnya = max(timeout, jarak/kecepatan * margin + slack).
---                      Ini menjaga pemanggil lama (mis. EnemyController yang
---                      mengirim 5) tidak lagi memotong perjalanan panjang.
--- @return boolean      true jika berhasil sampai tujuan
function NavigationManager:moveTo(
	humanoid: Humanoid,
	rootPart: BasePart,
	destination: Vector3,
	shouldAbort: (() -> boolean)?,
	timeout: number?
): boolean
	local distance = (destination - rootPart.Position).Magnitude

	-- Anggaran dihitung dari KECEPATAN AKTUAL, bukan Config.PatrolSpeed: saat
	-- mengejar, monster memakai ChaseSpeed yang jauh lebih tinggi.
	local budget = self:getTravelBudget(humanoid.WalkSpeed, distance)
	if timeout then
		budget = math.max(budget, timeout)
	end

	-- Compute path
	local path = PathfindingService:CreatePath(self:_createPathParams())

	local success = pcall(function()
		path:ComputeAsync(rootPart.Position, destination)
	end)

	if not success or path.Status ~= Enum.PathStatus.Success then
		-- Fallback: MoveTo langsung jika pathfinding gagal
		humanoid:MoveTo(destination)
		return false
	end

	-- Follow waypoints
	local waypoints = path:GetWaypoints()
	local startTime = tick()

	-- Deteksi macet: kalau posisi tidak bergerak sama sekali selama
	-- Config.PathStuckTime, monster benar-benar nyangkut (nabrak dinding,
	-- terperangkap) -> keluar lebih cepat daripada menunggu anggaran penuh.
	local stuckTime = Config.PathStuckTime or 4
	local lastPos = rootPart.Position
	local lastProgress = tick()

	for _, wp in ipairs(waypoints) do
		-- Abort check
		if shouldAbort and shouldAbort() then
			return false
		end

		-- Jump jika diperlukan
		if wp.Action == Enum.PathWaypointAction.Jump then
			humanoid.Jump = true
		end

		-- FIX bug E: pasang listener MoveToFinished SEBELUM MoveTo, supaya
		-- untuk waypoint yang sangat dekat event-nya tidak keburu fire & terlewat
		-- (yang bikin monster nunggu sampai timeout).
		local reached = false
		local connection = humanoid.MoveToFinished:Connect(function(didReach)
			reached = didReach
		end)

		humanoid:MoveTo(wp.Position)

		-- Tunggu sampai mencapai waypoint, macet, atau anggaran habis.
		--
		-- PENTING: loop ini TIDAK dibatasi jam dinding per-waypoint. Dulu ia
		-- membandingkan (tick() - startTime) dengan batas tetap, sehingga jalur
		-- yang panjang selalu "gagal" walau monster berjalan normal. Sekarang
		-- yang menghentikan hanya anggaran TOTAL (sudah memperhitungkan jarak)
		-- dan deteksi macet.
		while not reached do
			task.wait(0.1)

			-- Distance check langsung
			if (rootPart.Position - wp.Position).Magnitude < 3.5 then
				reached = true
				break
			end

			-- Abort check mid-navigation
			if shouldAbort and shouldAbort() then
				connection:Disconnect()
				return false
			end

			local now = tick()

			-- Kemajuan nyata? (bergerak > 0.5 stud sejak cek terakhir)
			if (rootPart.Position - lastPos).Magnitude > 0.5 then
				lastPos = rootPart.Position
				lastProgress = now
			elseif (now - lastProgress) > stuckTime then
				-- Nyangkut: tidak bergerak sama sekali -> menyerah, biar
				-- state machine bisa memilih tindakan lain (mis. re-path).
				connection:Disconnect()
				return false
			end

			-- Anggaran total habis
			if (now - startTime) > budget then
				connection:Disconnect()
				return false
			end
		end

		connection:Disconnect()
		if not reached then
			return false
		end
	end

	return true
end

--- Navigasi sederhana tanpa pathfinding — langsung MoveTo.
--- Digunakan untuk chase mode agar lebih responsif.
function NavigationManager:directMoveTo(humanoid: Humanoid, position: Vector3)
	humanoid:MoveTo(position)
end

return NavigationManager
