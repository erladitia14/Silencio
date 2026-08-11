--[[
	NavigationManager.luau
	----------------------
	Mengelola navigasi NPC menggunakan PathfindingService.
	
	Fitur:
	  - Pathfinding dengan parameter agent yang bisa dikonfigurasi
	  - Fallback ke MoveTo langsung jika path gagal dikomputasi
	  - Interrupt check selama navigasi (untuk pembatalan chase)
	  - Jump handling otomatis
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

--- Navigasi monster ke posisi tujuan menggunakan PathfindingService.
--- 
--- @param humanoid      Humanoid milik monster
--- @param rootPart      HumanoidRootPart milik monster
--- @param destination   Posisi tujuan
--- @param shouldAbort   Fungsi callback yang dipanggil setiap tick.
---                      Jika return true, navigasi dibatalkan.
--- @param timeout       Timeout navigasi (opsional, default dari Config)
--- @return boolean      true jika berhasil sampai tujuan
function NavigationManager:moveTo(
	humanoid: Humanoid,
	rootPart: BasePart,
	destination: Vector3,
	shouldAbort: (() -> boolean)?,
	timeout: number?
): boolean
	local maxTime = timeout or Config.PathTimeout

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

		-- Tunggu sampai mencapai waypoint atau timeout

		while not reached and (tick() - startTime) < maxTime do
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
