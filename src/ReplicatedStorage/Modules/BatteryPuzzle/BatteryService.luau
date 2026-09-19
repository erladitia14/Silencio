--!strict
--[[
	BatteryService — v2 rebuild (pragmatic, direct, no cloning)

	Aturan penanganan baterai:
	1. Baterai asli di-weld LANGSUNG ke tangan pemain (RightHand / Right Arm).
	   TIDAK ada cloning (karena clone mewarisi tag & bikin prompt duplikat).
	2. Saat pemain membawa baterai:
	   - Prompt pada baterai yang dibawa = MATI.
	   - Prompt pada baterai lain di lantai = MATI (agar tidak bisa ambil 2).
	   - WalkSpeed pemain turun (beban berat).
	3. Saat baterai dipasang ke slot:
	   - Baterai di tangan di-Destroy().
	   - WalkSpeed pemain pulih.
	   - Prompt pada baterai tersisa di lantai = NYALA lagi.
	4. Saat pemain mati:
	   - Baterai lepas, jatuh di tempat, prompt nyala lagi.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local Config = require(script.Parent.Config)

local BatteryService = {}

-- State
local batteries: { [BasePart]: { homeCF: CFrame, prompt: ProximityPrompt } } = {}
local carriedBy: { [Player]: BasePart } = {}
local savedSpeed: { [Player]: { walk: number, jump: number } } = {}

-- Dipasang orchestrator: dipanggil tiap status bawa baterai berubah,
-- supaya prompt Insert di case ikut ter-refresh (nyala hanya saat bawa baterai).
local onCarryChanged: (() -> ())? = nil

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

local function isCarriedBySomeone(battery: BasePart): boolean
	for _, b in pairs(carriedBy) do
		if b == battery then return true end
	end
	return false
end

-- Refresh visibilitas prompt pickup:
-- Jika ADA pemain yang sedang membawa baterai, matikan semua prompt pickup
-- agar pemain tidak melihat / menekan prompt baterai lain saat tangannya penuh.
function BatteryService.refreshPickupPrompts()
	local anyCarrying = false
	for _ in pairs(carriedBy) do
		anyCarrying = true
		break
	end

	for part, info in pairs(batteries) do
		if part.Parent == nil then
			batteries[part] = nil
		elseif anyCarrying or isCarriedBySomeone(part) then
			info.prompt.Enabled = false
		else
			info.prompt.Enabled = true
		end
	end

	-- beritahu CaseService supaya prompt Insert ikut nyala/mati
	if onCarryChanged then
		onCarryChanged()
	end
end

-- ----------------------------------------------------------------------
-- Pickup & Consume & Drop
-- ----------------------------------------------------------------------

function BatteryService.getCarried(player: Player): BasePart?
	return carriedBy[player]
end

-- Dibaca CaseService untuk menentukan apakah prompt Insert boleh muncul.
-- Cek tabel carriedBy LANGSUNG (bukan iterasi Players) supaya andal.
function BatteryService.isAnyoneCarrying(): boolean
	for _ in pairs(carriedBy) do
		return true
	end
	return false
end

function BatteryService.setCarryChangedCallback(cb: () -> ())
	onCarryChanged = cb
end

function BatteryService.canPickup(player: Player, battery: BasePart): boolean
	if carriedBy[player] ~= nil then return false end
	if batteries[battery] == nil then return false end
	if isCarriedBySomeone(battery) then return false end
	return true
end

function BatteryService.pickup(player: Player, battery: BasePart): boolean
	if not BatteryService.canPickup(player, battery) then
		return false
	end

	local hand = getHand(player)
	local hum = getHumanoid(player)
	if not hand or not hum then
		return false
	end

	carriedBy[player] = battery

	-- Baterai KECIL: masih bisa lari, cuma 0.9x kecepatan normal.
	-- Simpan kecepatan asli DULU, lalu kali 0.9 (bukan angka tetap).
	if not savedSpeed[player] then
		savedSpeed[player] = { walk = hum.WalkSpeed, jump = hum.JumpPower }
	end
	hum.WalkSpeed = savedSpeed[player].walk * Config.CarryWalkSpeedMultiplier
	-- Jump dibiarkan normal (baterai ringan)

	if player.Character then
		player.Character:SetAttribute(Config.CarryingAttribute, true)
	end

	-- Matikan prompt baterai ini
	local info = batteries[battery]
	if info then
		info.prompt.Enabled = false
	end

	-- Weld langsung part baterai ke tangan
	battery.Anchored = false
	battery.CanCollide = false
	battery.CanTouch = false
	battery.CanQuery = false

	for _, child in ipairs(battery:GetChildren()) do
		if child:IsA("Weld") or child:IsA("Motor6D") or child:IsA("WeldConstraint") then
			child:Destroy()
		end
	end

	local weld = Instance.new("Weld")
	weld.Name = "CarryWeld"
	weld.Part0 = hand
	weld.Part1 = battery
	weld.C0 = CFrame.new(0, -0.4, -0.2) * CFrame.Angles(math.rad(90), 0, 0)
	weld.Parent = battery

	battery.CFrame = hand.CFrame * weld.C0

	BatteryService.refreshPickupPrompts()
	return true
end

-- Dipanggil CaseService saat baterai berhasil dimasukkan ke slot.
-- Baterai di tangan DIHANCURKAN (slot punya representasi visual sendiri).
function BatteryService.consume(player: Player): BasePart?
	local battery = carriedBy[player]
	if not battery then
		return nil
	end

	carriedBy[player] = nil
	batteries[battery] = nil

	-- Pulihkan kecepatan
	local hum = getHumanoid(player)
	if hum and savedSpeed[player] then
		hum.WalkSpeed = savedSpeed[player].walk
		hum.JumpPower = savedSpeed[player].jump
	end
	savedSpeed[player] = nil

	if player.Character then
		player.Character:SetAttribute(Config.CarryingAttribute, false)
	end

	battery:Destroy()

	BatteryService.refreshPickupPrompts()
	return battery
end

function BatteryService.drop(player: Player)
	local battery = carriedBy[player]
	if not battery then return end

	carriedBy[player] = nil

	local hum = getHumanoid(player)
	if hum and savedSpeed[player] then
		hum.WalkSpeed = savedSpeed[player].walk
		hum.JumpPower = savedSpeed[player].jump
	end
	savedSpeed[player] = nil

	if player.Character then
		player.Character:SetAttribute(Config.CarryingAttribute, false)
	end

	for _, child in ipairs(battery:GetChildren()) do
		if child:IsA("Weld") or child:IsA("Motor6D") or child:IsA("WeldConstraint") then
			child:Destroy()
		end
	end

	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		battery.CFrame = root.CFrame * CFrame.new(0, -2, -3)
	elseif batteries[battery] then
		battery.CFrame = batteries[battery].homeCF
	end

	battery.Anchored = true
	battery.CanCollide = true
	battery.CanTouch = true
	battery.CanQuery = true

	BatteryService.refreshPickupPrompts()
end

-- ----------------------------------------------------------------------
-- Registrasi
-- ----------------------------------------------------------------------

local function registerBattery(b: BasePart)
	if batteries[b] then return end

	local p = b:FindFirstChild("BatteryPickupPrompt") :: ProximityPrompt?
	if not p then
		p = Instance.new("ProximityPrompt")
		p.Name = "BatteryPickupPrompt"
		p.Parent = b
	end
	p.ActionText = Config.PickupPromptText
	p.ObjectText = "Battery"
	p.KeyboardKeyCode = Config.PickupPromptKey
	p.MaxActivationDistance = Config.PickupPromptDistance
	p.RequiresLineOfSight = Config.RequireLineOfSight
	p.HoldDuration = 0
	p.Enabled = true

	batteries[b] = {
		homeCF = b.CFrame,
		prompt = p,
	}

	p.Triggered:Connect(function(player)
		BatteryService.pickup(player, b)
	end)
end

function BatteryService.start()
	for _, b in ipairs(CollectionService:GetTagged(Config.PickupTag)) do
		if b:IsA("BasePart") then
			registerBattery(b)
		end
	end

	CollectionService:GetInstanceAddedSignal(Config.PickupTag):Connect(function(b)
		if b:IsA("BasePart") then
			registerBattery(b)
		end
	end)

	local function bindCharacter(player: Player)
		player.CharacterAdded:Connect(function(char)
			local hum = char:WaitForChild("Humanoid", 10) :: Humanoid?
			if hum then
				hum.Died:Connect(function()
					BatteryService.drop(player)
				end)
			end
		end)
	end

	Players.PlayerAdded:Connect(bindCharacter)
	for _, plr in ipairs(Players:GetPlayers()) do
		bindCharacter(plr)
	end

	Players.PlayerRemoving:Connect(function(plr)
		BatteryService.drop(plr)
		savedSpeed[plr] = nil
	end)

	BatteryService.refreshPickupPrompts()
end

return BatteryService