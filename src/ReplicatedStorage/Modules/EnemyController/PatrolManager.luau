--[[
	PatrolManager.luau
	------------------
	Mengelola sistem patroli monster: pengumpulan waypoint,
	navigasi antar waypoint, dan fallback waypoint otomatis.

	RESOLUSI WAYPOINT (hybrid, urutan dari paling spesifik):
	  1. workspace.<Config.WaypointFolder>.<tag>  -- tag dari Attribute
	     "WaypointSet" pada rig (default: rig.Name). Ini jalur utama baru;
	     memisahkan waypoint dari rig supaya aman di-drag di Studio.
	  2. rig.<Config.WaypointFolder>              -- folder nested lama di
	     dalam rig (backward compat untuk `ServerStorage.Phase1Monster.Clown`
	     punya tim yang masih menyimpan Waypoints di dalam template).
	  3. workspace.<Config.WaypointFolder>        -- folder global yang isinya
	     LANGSUNG BasePart (behavior legacy; dipakai saat hanya ada satu
	     monster di map). Dikenali bila tidak ada child Folder/Configuration.
	  4. Fallback 4-titik square 20 stud di sekitar HumanoidRootPart.

	CATATAN:
	  - Drag rig di Studio tidak lagi menggeser waypoint eksternal karena
	    folder-nya bukan descendant rig; tidak perlu guard save/restore CFrame.
	  - Rename rig memutus resolusi (1) kalau tidak pakai Attribute
	    WaypointSet; set Attribute agar imun dari rename.
	  - Satu set waypoint boleh dipakai banyak rig: cukup samakan tag.
	  - TargetFinder.computeBodyExtents sudah mengecualikan Folder di dalam
	    rig, jadi fallback (2) tidak membuat jangkauan serang membengkak.
--]]

local Config = require(script.Parent.Config)

local PatrolManager = {}
PatrolManager.__index = PatrolManager

-- Rig yang sudah dilaporkan sumber waypoint-nya (anti-spam warn/info).
-- Weak key supaya tidak menghalangi GC saat rig dihapus.
local reported: { [Model]: boolean } = setmetatable({}, { __mode = "k" }) :: any

--- Tag waypoint untuk rig: Attribute "WaypointSet" (string, non-kosong)
--- di-override oleh rig.Name saat Attribute tidak di-set.
local function resolveTag(model: Model): string
	local attr = model:GetAttribute("WaypointSet")
	if typeof(attr) == "string" and #attr > 0 then
		return attr
	end
	return model.Name
end

--- true jika folder adalah "container of folders" (anak-anaknya minimal
--- satu Folder/Configuration). Dipakai untuk membedakan container baru
--- (`workspace.Waypoints` berisi folder per-rig) vs legacy
--- (`workspace.Waypoints` berisi langsung BasePart).
local function looksLikeContainer(folder: Instance): boolean
	for _, child in folder:GetChildren() do
		if child:IsA("Folder") or child:IsA("Configuration") then
			return true
		end
	end
	return false
end

--- Ambil BasePart dari folder, diurutkan berdasar nama (Waypoint1,
--- Waypoint2, ...). Mengembalikan daftar posisi; kosong jika folder
--- tidak berisi BasePart.
local function collectFromFolder(folder: Instance): { Vector3 }
	local out: { Vector3 } = {}
	local children = folder:GetChildren()
	table.sort(children, function(a, b)
		return a.Name < b.Name
	end)
	for _, child in children do
		if child:IsA("BasePart") then
			table.insert(out, child.Position)
		end
	end
	return out
end

--- Membuat instance PatrolManager baru untuk sebuah monster.
function PatrolManager.new(monsterModel: Model)
	local self = setmetatable({}, PatrolManager)
	self._model = monsterModel
	self._waypoints = {} :: { Vector3 }
	self._currentIndex = 1
	self._source = "none" :: string -- "external" | "nested" | "legacy" | "fallback" | "none"

	self:_collectWaypoints()

	return self
end

--- Mengumpulkan waypoint sesuai urutan resolusi di komentar modul.
function PatrolManager:_collectWaypoints()
	self._waypoints = {}
	self._source = "none"

	local folderName = Config.WaypointFolder
	local tag = resolveTag(self._model)

	-- (1) workspace.<folder>.<tag>
	local container = workspace:FindFirstChild(folderName)
	if container then
		local perRig = container:FindFirstChild(tag)
		if perRig then
			self._waypoints = collectFromFolder(perRig)
			if #self._waypoints > 0 then
				self._source = "external"
			end
		end
	end

	-- (2) rig.<folder>  (backward compat tim: Clown template)
	if #self._waypoints == 0 then
		local nested = self._model:FindFirstChild(folderName)
		if nested then
			self._waypoints = collectFromFolder(nested)
			if #self._waypoints > 0 then
				self._source = "nested"
			end
		end
	end

	-- (3) workspace.<folder>  (legacy: isi langsung BasePart, bukan container)
	if #self._waypoints == 0 and container and not looksLikeContainer(container) then
		self._waypoints = collectFromFolder(container)
		if #self._waypoints > 0 then
			self._source = "legacy"
		end
	end

	-- (4) Fallback 4-titik square di sekitar spawn.
	if #self._waypoints == 0 then
		local rootPart = self._model:FindFirstChild("HumanoidRootPart") :: BasePart?
		if rootPart then
			local origin = rootPart.Position
			table.insert(self._waypoints, origin + Vector3.new(20, 0, 20))
			table.insert(self._waypoints, origin + Vector3.new(-20, 0, 20))
			table.insert(self._waypoints, origin + Vector3.new(-20, 0, -20))
			table.insert(self._waypoints, origin + Vector3.new(20, 0, -20))
			self._source = "fallback"
		end
	end

	-- Laporan SEKALI per rig: supaya ketahuan folder mana yang kepilih
	-- (dan terdeteksi cepat kalau Attribute WaypointSet salah ketik).
	if not reported[self._model] then
		reported[self._model] = true
		if self._source == "external" then
			print(string.format(
				"[PatrolManager] %s -> workspace.%s.%s (%d titik)",
				self._model:GetFullName(), folderName, tag, #self._waypoints))
		elseif self._source == "nested" then
			print(string.format(
				"[PatrolManager] %s -> rig.%s (nested, %d titik) -- pertimbangkan pindah ke workspace.%s.%s",
				self._model:GetFullName(), folderName, #self._waypoints, folderName, tag))
		elseif self._source == "legacy" then
			print(string.format(
				"[PatrolManager] %s -> workspace.%s (legacy flat, %d titik)",
				self._model:GetFullName(), folderName, #self._waypoints))
		elseif self._source == "fallback" then
			warn(string.format(
				"[PatrolManager] %s tidak punya folder waypoint (tag '%s'); pakai 4-titik square. "
					.. "Buat workspace.%s.%s berisi BasePart Waypoint1..N untuk patroli nyata.",
				self._model:GetFullName(), tag, folderName, tag))
		else
			warn(string.format(
				"[PatrolManager] %s tidak punya HumanoidRootPart; waypoint kosong.",
				self._model:GetFullName()))
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

--- Sumber waypoint saat ini: "external" | "nested" | "legacy" | "fallback" | "none".
--- Dipakai oleh harness verifikasi dan debugging in-game.
function PatrolManager:getSource(): string
	return self._source
end

--- Refresh waypoint (jika waypoint berubah saat runtime).
function PatrolManager:refresh()
	-- Reset laporan supaya perubahan sumber (mis. Attribute WaypointSet
	-- diubah di Studio runtime) terlihat di log.
	reported[self._model] = nil
	self:_collectWaypoints()
	self._currentIndex = 1
end

return PatrolManager
