--[[
	Geometry.luau
	-------------
	Perhitungan ruang untuk Safe Zone. Murni matematika + pencarian
	instance — TIDAK menyimpan state apa pun, jadi aman dipakai server
	maupun client.

	Dua cara menandai bilik di Studio (pilih salah satu, boleh dicampur):
	  1. Tag CollectionService "SafeZone" pada Part
	  2. Part di dalam Folder "SafeZones" di Workspace

	Folder bersarang juga dibaca (GetDescendants), jadi tim bebas
	mengelompokkan bilik per-lantai / per-ruangan tanpa aturan tambahan.
--]]

local CollectionService = game:GetService("CollectionService")

local Config = require(script.Parent.Config)

local Geometry = {}

--- Kumpulkan semua BasePart yang dianggap Safe Zone.
--- Mengembalikan tabel BARU (tidak memutasi hasil GetTagged — bug #6 lama).
function Geometry.gatherZoneParts(): { BasePart }
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

	-- Folder (atau Part) bernama "SafeZones" di Workspace.
	-- GetDescendants: sedalam apa pun, nama bebas.
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
--- Menghormati rotasi Part (bilik toilet jarang lurus sumbu dunia).
function Geometry.isPointInside(point: Vector3, part: BasePart): boolean
	-- Culling cepat sebelum transform matriks.
	if (part.Position - point).Magnitude > (part.Size.Magnitude / 2) + 2 then
		return false
	end

	local localPos = part.CFrame:PointToObjectSpace(point)
	local half = part.Size / 2

	return math.abs(localPos.X) <= half.X
		and math.abs(localPos.Y) <= half.Y
		and math.abs(localPos.Z) <= half.Z
end

--- Ambil part acuan posisi sebuah karakter.
--- Fallback ke PrimaryPart lalu BasePart pertama, supaya rig non-standar
--- (NPC import, dummy) tidak diam-diam dianggap "tidak ada".
function Geometry.rootOf(character: Model?): BasePart?
	if not character or not character.Parent then
		return nil
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end

	if character.PrimaryPart then
		return character.PrimaryPart
	end

	return character:FindFirstChildWhichIsA("BasePart", true)
end

--- Cari bilik yang memuat sebuah karakter (yang pertama ketemu).
--- @param zoneParts  hasil gatherZoneParts (dilewatkan supaya pemanggil
---                   bisa meng-cache; scan tag 10x/detik itu pemborosan)
function Geometry.findContainingZone(character: Model, zoneParts: { BasePart }): BasePart?
	local root = Geometry.rootOf(character)
	if not root then
		return nil
	end

	for _, part in zoneParts do
		if part.Parent and Geometry.isPointInside(root.Position, part) then
			return part
		end
	end

	return nil
end

return Geometry
