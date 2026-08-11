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
--]]

local Players = game:GetService("Players")

local Config          = require(script.Parent.Config)
local SafeZoneManager = require(script.Parent.SafeZoneManager)

local TargetFinder = {}

--- Cek apakah target berada dalam Field of View monster.
function TargetFinder:_isInFieldOfView(monsterRoot: BasePart, targetPos: Vector3): boolean
	local direction = (targetPos - monsterRoot.Position)
	local lookDir = monsterRoot.CFrame.LookVector
	local dirToTarget = direction.Unit

	local dotProduct = math.clamp(lookDir:Dot(dirToTarget), -1, 1)
	local angle = math.deg(math.acos(dotProduct))

	return angle <= (Config.FieldOfView / 2)
end

--- Raycast dari monster ke target untuk memastikan tidak ada
--- obstacle yang menghalangi pandangan (Line of Sight).
function TargetFinder:_hasLineOfSight(monsterModel: Model, monsterRoot: BasePart, targetChar: Model): boolean
	local targetRoot = targetChar:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not targetRoot then return false end

	local origin = monsterRoot.Position + Vector3.new(0, 1.5, 0)
	local direction = (targetRoot.Position - origin)

	-- Distance check
	if direction.Magnitude > Config.DetectionRadius then
		return false
	end

	-- FOV check
	if not self:_isInFieldOfView(monsterRoot, targetRoot.Position) then
		return false
	end

	-- Raycast
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { monsterModel }
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
function TargetFinder:findNearest(monsterModel: Model): (Player?, Model?)
	local monsterRoot = monsterModel:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not monsterRoot then
		return nil, nil
	end

	local closestDist = Config.DetectionRadius
	local bestPlayer: Player? = nil
	local bestChar: Model? = nil

	for _, player in Players:GetPlayers() do
		local char = player.Character
		if char and self:isValidTarget(char) then
			local targetRoot = char:FindFirstChild("HumanoidRootPart") :: BasePart
			local dist = (monsterRoot.Position - targetRoot.Position).Magnitude

			if dist < closestDist and self:_hasLineOfSight(monsterModel, monsterRoot, char) then
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

	return (monsterRoot.Position - targetRoot.Position).Magnitude <= Config.LoseTargetRadius
end

--- Cek apakah target berada dalam jangkauan serang.
function TargetFinder:isInAttackRange(monsterModel: Model, targetChar: Model): boolean
	local monsterRoot = monsterModel:FindFirstChild("HumanoidRootPart") :: BasePart?
	local targetRoot = targetChar:FindFirstChild("HumanoidRootPart") :: BasePart?

	if not monsterRoot or not targetRoot then
		return false
	end

	return (monsterRoot.Position - targetRoot.Position).Magnitude <= Config.AttackRadius
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
--- Mengembalikan (Player?, Model?) — nil jika tidak ada holder yang terlihat.
function TargetFinder:findItemHolder(monsterModel: Model): (Player?, Model?)
	local monsterRoot = monsterModel:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not monsterRoot then
		return nil, nil
	end

	local closestDist = Config.DetectionRadius
	local bestPlayer: Player? = nil
	local bestChar: Model? = nil

	for _, player in Players:GetPlayers() do
		local char = player.Character
		if char and self:isValidTarget(char) and self:holdsTargetItem(char) then
			local targetRoot = char:FindFirstChild("HumanoidRootPart") :: BasePart
			local dist = (monsterRoot.Position - targetRoot.Position).Magnitude

			if dist < closestDist and self:_hasLineOfSight(monsterModel, monsterRoot, char) then
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
function TargetFinder:acquireTarget(monsterModel: Model, mode: string): (Player?, Model?)
	if mode == "ITEM_HOLDER" then
		local p, c = self:findItemHolder(monsterModel)
		if p and c then
			return p, c
		end
		-- Fallback: tidak ada pemegang item -> kejar yang terdekat
		return self:findNearest(monsterModel)
	end

	-- PERSISTENT & NEAREST sama-sama akuisisi awal = terdekat
	return self:findNearest(monsterModel)
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
