--[[
	SafeZoneManager.luau
	--------------------
	Mengelola deteksi Safe Zone menggunakan dua metode:
	  1. CollectionService Tag ("SafeZone")
	  2. Folder "SafeZones" di Workspace
	
	Menggunakan OBB (Oriented Bounding Box) check yang akurat
	untuk menentukan apakah karakter berada di dalam area aman.
--]]

local CollectionService = game:GetService("CollectionService")

local Config = require(script.Parent.Config)

local SafeZoneManager = {}

--- Mengumpulkan semua BasePart yang dianggap Safe Zone
--- dari CollectionService tag dan folder Workspace.
function SafeZoneManager:_gatherZoneParts(): { BasePart }
	-- Ambil dari tag
	local parts = CollectionService:GetTagged(Config.SafeZoneTag)

	-- Ambil dari folder/part bernama "SafeZones" di Workspace (jika ada)
	local safeZoneInstance = workspace:FindFirstChild(Config.SafeZoneFolder)
	if safeZoneInstance then
		-- Jika instance itu sendiri adalah BasePart, masukkan langsung
		if safeZoneInstance:IsA("BasePart") and not table.find(parts, safeZoneInstance) then
			table.insert(parts, safeZoneInstance)
		end
		-- Jika punya children (Folder berisi Part-Part), masukkan juga
		for _, child in safeZoneInstance:GetChildren() do
			if child:IsA("BasePart") and not table.find(parts, child) then
				table.insert(parts, child)
			end
		end
	end

	return parts
end

--- Cek apakah sebuah posisi (Vector3) berada di dalam
--- Oriented Bounding Box dari sebuah BasePart.
function SafeZoneManager:_isPointInsidePart(point: Vector3, part: BasePart): boolean
	-- Quick distance culling
	local dist = (part.Position - point).Magnitude
	local maxRadius = (part.Size.Magnitude / 2) + 2
	if dist > maxRadius then
		return false
	end

	-- OBB check — transform point ke local space part
	local localPos = part.CFrame:PointToObjectSpace(point)
	local half = part.Size / 2

	return math.abs(localPos.X) <= half.X
		and math.abs(localPos.Y) <= half.Y
		and math.abs(localPos.Z) <= half.Z
end

--- Cek apakah sebuah karakter (Model dengan HumanoidRootPart)
--- sedang berada di dalam Safe Zone mana pun.
function SafeZoneManager:isInSafeZone(character: Model): boolean
	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not rootPart then
		return false
	end

	local point = rootPart.Position
	local zoneParts = self:_gatherZoneParts()

	for _, zonePart in zoneParts do
		if zonePart:IsA("BasePart") and self:_isPointInsidePart(point, zonePart) then
			return true
		end
	end

	return false
end

return SafeZoneManager
