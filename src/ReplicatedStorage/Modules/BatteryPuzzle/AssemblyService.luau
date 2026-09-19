--!strict
--[[
	AssemblyService — perakitan fisik genset (Engine + 2 Panel)
	Pola: sama persis BatteryService/CaseService, NOL koordinat hardcode.

	Konvensi tag:
	- "AssemblySlot"   -> BasePart placeholder di dalam Model Generator
	                      Attribute: Kind = "Engine" | "Panel"
	- "AssemblyPickup" -> BasePart yang diambil pemain di ruangan
	                      Attribute: Kind = "Engine" | "Panel"

	Alur:
	1. Game jalan: semua slot placeholder disembunyikan (Transparency = 1).
	2. Pemain ambil part (pickup) -> di-weld ke tangan, walkspeed turun (berat).
	3. Prompt install di slot HANYA nyala kalau:
	   - Pemain membawa part dengan Kind yang COCOK
	   - Untuk Panel: Engine HARUS sudah terpasang duluan (gating urutan)
	   - Hanya slot kosong yang prompt-nya aktif
	4. Tahan prompt 2 detik -> part di tangan Destroy(), slot placeholder muncul (Transparency = 0).
	5. 3/3 terpasang -> Generator Model diberi Attribute "GeneratorAssembled" = true.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local Config = require(script.Parent.Config)

local AssemblyService = {}

-- State
local carriedPart: { [Player]: BasePart } = {}
local carriedKind: { [Player]: string } = {}
local savedSpeed: { [Player]: { walk: number, jump: number } } = {}

-- Registrasi slot & pickup
type SlotRecord = {
	part: BasePart,
	kind: string,
	filled: boolean,
	prompt: ProximityPrompt,
}
local slots: { [BasePart]: SlotRecord } = {}
local pickups: { [BasePart]: { kind: string, prompt: ProximityPrompt, homeCF: CFrame } } = {}

-- Model generator pemilik (dideteksi dari parent slot)
local generatorModel: Model? = nil

local onAssembledCallback: ((genModel: Model) -> ())? = nil

-- ----------------------------------------------------------------------
-- Helpers
-- ----------------------------------------------------------------------

local function getHand(player: Player): BasePart?
	local char = player.Character
	if not char then return nil end
	return (char:FindFirstChild("RightHand")
		or char:FindFirstChild("Right Arm")
		or char:FindFirstChild("HumanoidRootPart")) :: BasePart?
end

local function getHumanoid(player: Player): Humanoid?
	local char = player.Character
	if not char then return nil end
	return char:FindFirstChildOfClass("Humanoid")
end

local function isEngineInstalled(): boolean
	for _, rec in pairs(slots) do
		if rec.kind == "Engine" and rec.filled then
			return true
		end
	end
	return false
end

local function countFilled(): (number, number)
	local filled, total = 0, 0
	for _, rec in pairs(slots) do
		total += 1
		if rec.filled then filled += 1 end
	end
	return filled, total
end

-- ----------------------------------------------------------------------
-- Refresh Prompts (Inti Gating)
-- ----------------------------------------------------------------------

function AssemblyService.refreshPrompts()
	local anyCarrying = false
	for _ in pairs(carriedPart) do
		anyCarrying = true
		break
	end

	-- 1. Refresh prompt pickup:
	-- Jika ada pemain yang sedang bawa part assembly, matikan semua pickup lain.
	for part, info in pairs(pickups) do
		if part.Parent == nil then
			pickups[part] = nil
		elseif anyCarrying then
			info.prompt.Enabled = false
		else
			info.prompt.Enabled = true
		end
	end

	-- 2. Refresh prompt slot install:
	-- - Harus ada pemain yang bawa part dengan Kind yang cocok
	-- - Untuk Panel: Engine harus sudah terpasang
	-- - Jika slot sudah filled: prompt mati
	-- - Untuk Panel ganda: hanya SATU slot panel kosong yang prompt-nya aktif (sequential)
	local engineIn = isEngineInstalled()

	-- cari kind apa saja yang sedang dibawa
	local carriedKinds: { [string]: boolean } = {}
	for _, k in pairs(carriedKind) do
		carriedKinds[k] = true
	end

	local firstEmptyPanelHandled = false
	for _, rec in pairs(slots) do
		if rec.filled then
			rec.prompt.Enabled = false
		elseif rec.kind == "Engine" then
			-- Engine prompt: nyala HANYA kalau ada yang bawa Engine
			rec.prompt.Enabled = (carriedKinds["Engine"] == true)
		elseif rec.kind == "Panel" then
			-- Panel prompt: nyala HANYA kalau Engine sudah masuk, bawa Panel, dan slot depan
			if engineIn and carriedKinds["Panel"] == true and not firstEmptyPanelHandled then
				rec.prompt.Enabled = true
				firstEmptyPanelHandled = true
			else
				rec.prompt.Enabled = false
			end
		else
			rec.prompt.Enabled = false
		end
	end
end

-- ----------------------------------------------------------------------
-- Pickup & Drop
-- ----------------------------------------------------------------------

function AssemblyService.getCarried(player: Player): BasePart?
	return carriedPart[player]
end

function AssemblyService.canPickup(player: Player, part: BasePart): boolean
	if carriedPart[player] ~= nil then return false end
	if pickups[part] == nil then return false end
	for _, p in pairs(carriedPart) do
		if p == part then return false end
	end
	return true
end

function AssemblyService.pickup(player: Player, part: BasePart): boolean
	if not AssemblyService.canPickup(player, part) then
		return false
	end

	local info = pickups[part]
	if not info then return false end

	local hand = getHand(player)
	local hum = getHumanoid(player)
	if not hand or not hum then return false end

	carriedPart[player] = part
	carriedKind[player] = info.kind

	if not savedSpeed[player] then
		savedSpeed[player] = { walk = hum.WalkSpeed, jump = hum.JumpPower }
	end
	hum.WalkSpeed = Config.CarryWalkSpeed
	hum.JumpPower = Config.CarryJumpPower

	if player.Character then
		player.Character:SetAttribute("CarryingAssemblyPart", info.kind)
	end

	info.prompt.Enabled = false

	part.Anchored = false
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false

	for _, child in ipairs(part:GetChildren()) do
		if child:IsA("Weld") or child:IsA("Motor6D") or child:IsA("WeldConstraint") then
			child:Destroy()
		end
	end

	local weld = Instance.new("Weld")
	weld.Name = "AssemblyCarryWeld"
	weld.Part0 = hand
	weld.Part1 = part
	weld.C0 = CFrame.new(0, -0.6, -0.4) * CFrame.Angles(math.rad(90), 0, 0)
	weld.Parent = part

	part.CFrame = hand.CFrame * weld.C0

	AssemblyService.refreshPrompts()
	return true
end

function AssemblyService.drop(player: Player)
	local part = carriedPart[player]
	if not part then return end

	carriedPart[player] = nil
	carriedKind[player] = nil

	local hum = getHumanoid(player)
	if hum and savedSpeed[player] then
		hum.WalkSpeed = savedSpeed[player].walk
		hum.JumpPower = savedSpeed[player].jump
	end
	savedSpeed[player] = nil

	if player.Character then
		player.Character:SetAttribute("CarryingAssemblyPart", nil)
	end

	for _, child in ipairs(part:GetChildren()) do
		if child:IsA("Weld") or child:IsA("Motor6D") or child:IsA("WeldConstraint") then
			child:Destroy()
		end
	end

	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		part.CFrame = root.CFrame * CFrame.new(0, -1.5, -3)
	elseif pickups[part] then
		part.CFrame = pickups[part].homeCF
	end

	part.Anchored = true
	part.CanCollide = true
	part.CanTouch = true
	part.CanQuery = true

	AssemblyService.refreshPrompts()
end

-- ----------------------------------------------------------------------
-- Insert / Pasang ke Slot
-- ----------------------------------------------------------------------

local function tryInsert(player: Player, slotPart: BasePart): boolean
	local rec = slots[slotPart]
	if not rec or rec.filled then return false end

	local carried = carriedPart[player]
	local kind = carriedKind[player]
	if not carried or kind ~= rec.kind then return false end

	-- Engine gating: Panel tidak bisa dipasang sebelum Engine
	if rec.kind == "Panel" and not isEngineInstalled() then
		return false
	end

	-- Jarak pemain ke slot
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		if (root.Position - slotPart.Position).Magnitude > (Config.InsertPromptDistance + 6) then
			return false
		end
	end

	-- KUNCI SLOT
	rec.filled = true

	-- Tampilkan placeholder slot
	slotPart.Transparency = 0
	slotPart.CanCollide = true
	slotPart.CanQuery = false
	slotPart.CanTouch = false
	rec.prompt.Enabled = false

	-- Bersihkan part bawaan
	carriedPart[player] = nil
	carriedKind[player] = nil
	pickups[carried] = nil

	local hum = getHumanoid(player)
	if hum and savedSpeed[player] then
		hum.WalkSpeed = savedSpeed[player].walk
		hum.JumpPower = savedSpeed[player].jump
	end
	savedSpeed[player] = nil

	if player.Character then
		player.Character:SetAttribute("CarryingAssemblyPart", nil)
	end

	carried:Destroy()

	-- Update progress
	local filled, total = countFilled()
	if generatorModel then
		generatorModel:SetAttribute("AssemblyProgress", string.format("%d/%d", filled, total))
		if filled >= total then
			generatorModel:SetAttribute("GeneratorAssembled", true)
			if onAssembledCallback then
				onAssembledCallback(generatorModel)
			end
		end
	end

	AssemblyService.refreshPrompts()
	return true
end

-- ----------------------------------------------------------------------
-- Registrasi Slot & Pickup
-- ----------------------------------------------------------------------

local function registerSlot(part: BasePart)
	if slots[part] then return end

	local kindAttr = part:GetAttribute("Kind")
	local kind = typeof(kindAttr) == "string" and kindAttr or "Engine"

	-- deteksi generator model
	if not generatorModel then
		local anc = part:FindFirstAncestorOfClass("Model")
		if anc and anc.Name == "Generator" then
			generatorModel = anc
		end
	end

	-- Sembunyikan placeholder di runtime (bukan dihapus)
	part.Transparency = 1
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Anchored = true

	local prompt = part:FindFirstChild("AssemblyInsertPrompt") :: ProximityPrompt?
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.Name = "AssemblyInsertPrompt"
		prompt.Parent = part
	end
	prompt.ActionText = "Install"
	prompt.ObjectText = kind
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.MaxActivationDistance = Config.InsertPromptDistance
	prompt.HoldDuration = Config.InsertDuration
	prompt.RequiresLineOfSight = Config.RequireLineOfSight
	prompt.Enabled = false

	prompt.Triggered:Connect(function(player)
		tryInsert(player, part)
	end)

	slots[part] = {
		part = part,
		kind = kind,
		filled = false,
		prompt = prompt,
	}
end

local function registerPickup(part: BasePart)
	if pickups[part] then return end

	local kindAttr = part:GetAttribute("Kind")
	local kind = typeof(kindAttr) == "string" and kindAttr or "Engine"

	part.Anchored = true

	local prompt = part:FindFirstChild("AssemblyPickupPrompt") :: ProximityPrompt?
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.Name = "AssemblyPickupPrompt"
		prompt.Parent = part
	end
	prompt.ActionText = Config.PickupPromptText
	prompt.ObjectText = kind
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.MaxActivationDistance = Config.PickupPromptDistance
	prompt.HoldDuration = 0
	prompt.RequiresLineOfSight = Config.RequireLineOfSight
	prompt.Enabled = true

	prompt.Triggered:Connect(function(player)
		AssemblyService.pickup(player, part)
	end)

	pickups[part] = {
		kind = kind,
		prompt = prompt,
		homeCF = part.CFrame,
	}
end

-- ----------------------------------------------------------------------
-- Query Status
-- ----------------------------------------------------------------------

function AssemblyService.isAssembled(): boolean
	local filled, total = countFilled()
	return total > 0 and filled >= total
end

function AssemblyService.getProgress(): (number, number)
	return countFilled()
end

-- ----------------------------------------------------------------------
-- START
-- ----------------------------------------------------------------------

function AssemblyService.start(opts: {
	onAssembled: ((genModel: Model) -> ())?,
}?)
	if opts and opts.onAssembled then
		onAssembledCallback = opts.onAssembled
	end

	-- Bind existing tagged slots
	for _, p in ipairs(CollectionService:GetTagged("AssemblySlot")) do
		if p:IsA("BasePart") then
			registerSlot(p)
		end
	end
	CollectionService:GetInstanceAddedSignal("AssemblySlot"):Connect(function(p)
		if p:IsA("BasePart") then registerSlot(p) end
	end)

	-- Bind existing tagged pickups
	for _, p in ipairs(CollectionService:GetTagged("AssemblyPickup")) do
		if p:IsA("BasePart") then
			registerPickup(p)
		end
	end
	CollectionService:GetInstanceAddedSignal("AssemblyPickup"):Connect(function(p)
		if p:IsA("BasePart") then registerPickup(p) end
	end)

	-- Inisialisasi progress attribute
	local filled, total = countFilled()
	if generatorModel then
		generatorModel:SetAttribute("AssemblyProgress", string.format("%d/%d", filled, total))
		generatorModel:SetAttribute("GeneratorAssembled", false)
	end

	-- Lifecycle player drop on death
	local function bindChar(player: Player)
		player.CharacterAdded:Connect(function(char)
			local hum = char:WaitForChild("Humanoid", 10) :: Humanoid?
			if hum then
				hum.Died:Connect(function()
					AssemblyService.drop(player)
				end)
			end
		end)
	end
	Players.PlayerAdded:Connect(bindChar)
	for _, p in ipairs(Players:GetPlayers()) do
		bindChar(p)
	end
	Players.PlayerRemoving:Connect(function(p)
		AssemblyService.drop(p)
		savedSpeed[p] = nil
	end)

	AssemblyService.refreshPrompts()
end

return AssemblyService
