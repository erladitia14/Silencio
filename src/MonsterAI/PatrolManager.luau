--[[
	PatrolManager.luau
	------------------
	Mengelola sistem patroli monster: pengumpulan waypoint,
	navigasi antar waypoint, dan fallback waypoint otomatis.
--]]

local Config = require(script.Parent.Config)

local PatrolManager = {}
PatrolManager.__index = PatrolManager

--- Membuat instance PatrolManager baru untuk sebuah monster.
function PatrolManager.new(monsterModel: Model)
	local self = setmetatable({}, PatrolManager)
	self._model = monsterModel
	self._waypoints = {} :: { Vector3 }
	self._currentIndex = 1

	self:_collectWaypoints()

	return self
end

--- Mengumpulkan waypoint dari folder di dalam monster model
--- atau dari Workspace. Jika tidak ditemukan, buat fallback
--- waypoint melingkar di sekitar posisi spawn.
function PatrolManager:_collectWaypoints()
	self._waypoints = {}

	-- Cari folder waypoint di dalam model monster atau di Workspace
	local folder = self._model:FindFirstChild(Config.WaypointFolder)
		or workspace:FindFirstChild(Config.WaypointFolder)

	if folder then
		local children = folder:GetChildren()

		-- Sort berdasarkan nama (Waypoint1, Waypoint2, dst.)
		table.sort(children, function(a, b)
			return a.Name < b.Name
		end)

		for _, child in children do
			if child:IsA("BasePart") then
				table.insert(self._waypoints, child.Position)
			end
		end
	end

	-- Fallback: buat titik patroli otomatis jika tidak ada waypoint
	if #self._waypoints == 0 then
		local rootPart = self._model:FindFirstChild("HumanoidRootPart") :: BasePart?
		if rootPart then
			local origin = rootPart.Position
			table.insert(self._waypoints, origin + Vector3.new(20, 0, 20))
			table.insert(self._waypoints, origin + Vector3.new(-20, 0, 20))
			table.insert(self._waypoints, origin + Vector3.new(-20, 0, -20))
			table.insert(self._waypoints, origin + Vector3.new(20, 0, -20))
		end
	end
end

--- Mendapatkan posisi waypoint berikutnya dan memajukan index.
function PatrolManager:getNextWaypoint(): Vector3?
	if #self._waypoints == 0 then
		return nil
	end

	local pos = self._waypoints[self._currentIndex]
	self._currentIndex = (self._currentIndex % #self._waypoints) + 1

	return pos
end

--- Mendapatkan posisi waypoint saat ini tanpa memajukan index.
function PatrolManager:getCurrentWaypoint(): Vector3?
	if #self._waypoints == 0 then
		return nil
	end
	return self._waypoints[self._currentIndex]
end

--- Mendapatkan jumlah waypoint yang tersedia.
function PatrolManager:getWaypointCount(): number
	return #self._waypoints
end

--- Refresh waypoint (jika waypoint berubah saat runtime).
function PatrolManager:refresh()
	self:_collectWaypoints()
	self._currentIndex = 1
end

return PatrolManager
