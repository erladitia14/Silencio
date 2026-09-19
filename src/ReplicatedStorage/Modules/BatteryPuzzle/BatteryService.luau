--!strict
--[[
	BatteryService — mengelola baterai yang bisa diambil (tag "BatteryPickup").

	Tanggung jawab:
	- Membangun ProximityPrompt per baterai
	- Melacak siapa membawa baterai mana (satu baterai = satu pemain)
	- Efek "berat": WalkSpeed/JumpPower turun saat membawa
	- Efek "satu tangan": Attribute di Character, dibaca sistem lain
	- "Interupsi": baterai JATUH saat kena damage (tidak hilang)
	- "Recovery": kembali ke posisi awal saat mati/keluar/respawn

	Modul ini TIDAK menyentuh script sistem lain.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Config = require(script.Parent.Config)

local BatteryService = {}

-- state
local batteries: { [BasePart]: any } = {}       -- baterai -> record
local carriedBy: { [Player]: BasePart } = {}    -- pemain -> baterai
local savedSpeed: { [Player]: { walk: number, jump: number } } = {}
local dropCooldown: { [Player]: number } = {}
local conns: { [BasePart]: { RBXScriptConnection } } = {}

-- dipasang oleh orchestrator
local notifyCarryChanged: ((player: Player, carrying: boolean) -> ())? = nil

-- ============================================================
-- UTIL
-- ============================================================

local function characterOf(player: Player): Model?
	local c = player.Character
	if c and c.Parent then
		local hum = c:FindFirstChildOfClass("Humanoid")
		if hum and hum.Health > 0 then
			return c
		end
	end
	return nil
end

local function rootOf(player: Player): BasePart?
	local c = characterOf(player)
	if not c then
		return nil
	end
	return c:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function humanoidOf(player: Player): Humanoid?
	local c = characterOf(player)
	if not c then
		return nil
	end
	return c:FindFirstChildOfClass("Humanoid")
end

-- ============================================================
-- EFEK: BERAT + SATU TANGAN
-- ============================================================

local function applyCarryEffects(player: Player)
	local hum = humanoidOf(player)
	if not hum then
		return
	end
	-- simpan nilai asli SEKALI saja, biar tidak menimpa nilai yang sudah dimodif sistem lain
	if not savedSpeed[player] then
		savedSpeed[player] = { walk = hum.WalkSpeed, jump = hum.JumpPower }
	end
	hum.WalkSpeed = Config.CarryWalkSpeed
	hum.JumpPower = Config.CarryJumpPower

	-- Attribute di Character: sistem lain boleh baca untuk blokir item
	local c = characterOf(player)
	if c then
		c:SetAttribute(Config.CarryingAttribute, true)
	end
end

local function clearCarryEffects(player: Player)
	local hum = humanoidOf(player)
	if hum then
		local saved = savedSpeed[player]
		if saved and Config.RestoreSpeedOnDrop then
			hum.WalkSpeed = saved.walk
			hum.JumpPower = saved.jump
		end
	end
	savedSpeed[player] = nil

	local c = player.Character
	if c then
		c:SetAttribute(Config.CarryingAttribute, false)
	end
end

-- ============================================================
-- VISUAL SAAT DIBAWA
-- ============================================================

local function showCarriedVisual(player: Player, battery: BasePart): BasePart?
	local root = rootOf(player)
	if not root then
		Config.log("showCarriedVisual: no root for", player.Name)
		return nil
	end
	-- salinan visual (mesh sama, biar tetap mirip)
	local vis = battery:Clone()
	vis.Name = "CarriedBattery"
	vis.Anchored = false
	vis.CanCollide = false
	vis.CanTouch = false
	vis.CanQuery = false
	vis.Massless = true
	if Config.CarryVisualScale ~= 1 then
		vis.Size = vis.Size * Config.CarryVisualScale
	end
	-- buang prompt dari salinan
	for _, d in ipairs(vis:GetDescendants()) do
		if d:IsA("ProximityPrompt") then
			d:Destroy()
		end
	end
	-- Motor6D (bukan WeldConstraint) supaya C0 offset bisa disetel dari awal.
	-- WeldConstraint tidak punya CFrame offset — mesh akan ngambang di posisi lama.
	local m = Instance.new("Motor6D")
	m.Name = "CarryWeld"
	m.Part0 = root
	m.Part1 = vis
	m.C0 = Config.CarryOffset
	m.Parent = vis

	vis.CFrame = root.CFrame * Config.CarryOffset
	vis.Parent = root

	local rec = batteries[battery]
	if rec then
		rec.visual = vis
	end
	return vis
end

local function clearCarriedVisual(battery: BasePart)
	local rec = batteries[battery]
	if rec and rec.visual then
		rec.visual:Destroy()
		rec.visual = nil
	end
end

-- ============================================================
-- AMBIL / LEPAS
-- ============================================================

function BatteryService.canPickup(player: Player, battery: BasePart): boolean
	local rec = batteries[battery]
	if not rec then
		return false
	end
	if rec.carrier then
		return false                       -- sudah dibawa orang lain
	end
	if rec.inserted then
		return false                       -- sudah terpasang
	end
	if carriedBy[player] then
		return false                       -- sudah bawa 1 (MaxCarry = 1)
	end
	if not characterOf(player) then
		return false
	end
	return true
end

function BatteryService.pickup(player: Player, battery: BasePart): boolean
	if not BatteryService.canPickup(player, battery) then
		return false
	end
	local rec = batteries[battery]

	rec.carrier = player
	carriedBy[player] = battery

	-- efek
	applyCarryEffects(player)

	-- visual: sembunyikan asli, tampilkan salinan yang mengikuti pemain
	if Config.HideOriginalWhileCarried then
		battery.Transparency = 1
		battery.CanCollide = false
		battery.CanQuery = false
		local vis = showCarriedVisual(player, battery)
		if not vis then
			Config.log("pickup: visual gagal untuk", player.Name, "— batalkan? tidak, tetap pickup")
		end
	end

	if notifyCarryChanged then
		notifyCarryChanged(player, true)
	end
	Config.log("pickup", player.Name, battery:GetFullName())
	return true
end

-- Lepas baterai: jatuhkan di posisi pemain (bukan hilang)
function BatteryService.drop(player: Player, reason: string?): boolean
	local battery = carriedBy[player]
	if not battery then
		return false
	end
	local rec = batteries[battery]
	local root = rootOf(player)

	carriedBy[player] = nil
	if rec then
		rec.carrier = nil
		clearCarriedVisual(battery)

		-- taruh di depan pemain, sedikit di atas lantai
		if root then
			local dropCF = root.CFrame * CFrame.new(0, -2.0, -2.5)
			battery.CFrame = dropCF
		end
		battery.Transparency = 0
		battery.CanCollide = true
		battery.CanQuery = true
	end

	clearCarryEffects(player)
	if notifyCarryChanged then
		notifyCarryChanged(player, false)
	end
	Config.log("drop", player.Name, reason or "")
	return true
end

-- Kembalikan ke posisi awal (mati/keluar/respawn)
function BatteryService.returnHome(player: Player, reason: string?): boolean
	local battery = carriedBy[player]
	if not battery then
		return false
	end
	local rec = batteries[battery]

	carriedBy[player] = nil
	if rec then
		rec.carrier = nil
		clearCarriedVisual(battery)
		if rec.homeCFrame then
			battery.CFrame = rec.homeCFrame
		end
		battery.Transparency = 0
		battery.CanCollide = true
		battery.CanQuery = true
	end

	clearCarryEffects(player)
	if notifyCarryChanged then
		notifyCarryChanged(player, false)
	end
	Config.log("returnHome", player.Name, reason or "")
	return true
end

-- Dipanggil CaseService saat baterai berhasil dipasang
function BatteryService.markInserted(player: Player, battery: BasePart, slotCFrame: CFrame)
	local rec = batteries[battery]
	carriedBy[player] = nil
	if rec then
		rec.carrier = nil
		rec.inserted = true
		clearCarriedVisual(battery)
		battery.CFrame = slotCFrame
		battery.Transparency = 0
		battery.CanCollide = false
		battery.CanQuery = false
		battery.Anchored = true
	end
	clearCarryEffects(player)
	if notifyCarryChanged then
		notifyCarryChanged(player, false)
	end
end

function BatteryService.getCarried(player: Player): BasePart?
	return carriedBy[player]
end

function BatteryService.isCarried(battery: BasePart): boolean
	local rec = batteries[battery]
	return rec ~= nil and rec.carrier ~= nil
end

function BatteryService.isInserted(battery: BasePart): boolean
	local rec = batteries[battery]
	return rec ~= nil and rec.inserted == true
end

-- ============================================================
-- PROMPT
-- ============================================================

local function ensurePrompt(battery: BasePart)
	if battery:FindFirstChild("BatteryPickupPrompt") then
		return
	end
	local p = Instance.new("ProximityPrompt")
	p.Name = "BatteryPickupPrompt"
	p.ActionText = Config.PickupPromptText
	p.ObjectText = "Battery"
	p.KeyboardKeyCode = Config.PickupPromptKey
	p.MaxActivationDistance = Config.PickupPromptDistance
	p.RequiresLineOfSight = Config.RequireLineOfSight
	p.HoldDuration = 0
	p.Parent = battery
end

-- ============================================================
-- REGISTER / UNREGISTER
-- ============================================================

local function registerBattery(battery: BasePart)
	if batteries[battery] then
		return
	end
	batteries[battery] = {
		carrier = nil,
		inserted = false,
		homeCFrame = battery.CFrame,       -- titik asal untuk recovery
		visual = nil,
	}
	ensurePrompt(battery)

	local bag = conns[battery] or {}
	conns[battery] = bag

	local prompt = battery:WaitForChild("BatteryPickupPrompt", 5) :: ProximityPrompt?
	if prompt then
		table.insert(bag, prompt.Triggered:Connect(function(player)
			if BatteryService.canPickup(player, battery) then
				BatteryService.pickup(player, battery)
			end
		end))
	end
	Config.log("registered battery", battery:GetFullName())
end

local function unregisterBattery(battery: BasePart)
	local bag = conns[battery]
	if bag then
		for _, c in ipairs(bag) do
			c:Disconnect()
		end
	end
	conns[battery] = nil
	batteries[battery] = nil
end

-- ============================================================
-- INTERUPSI: kena damage -> jatuh
-- ============================================================

local function watchDamage(player: Player)
	local c = player.Character
	if not c then
		return
	end
	local hum = c:FindFirstChildOfClass("Humanoid")
	if not hum then
		return
	end
	hum.HealthChanged:Connect(function(newHealth)
		if not Config.DropOnDamage then
			return
		end
		if not carriedBy[player] then
			return
		end
		-- hanya kalau berkurang
		if newHealth >= hum.MaxHealth then
			return
		end
		local now = os.clock()
		if dropCooldown[player] and now - dropCooldown[player] < Config.DropCooldown then
			return
		end
		dropCooldown[player] = now
		BatteryService.drop(player, "damage")
	end)
end

-- ============================================================
-- RECOVERY
-- ============================================================

local function watchLifecycle(player: Player)
	player.CharacterAdded:Connect(function(c)
		local hum = c:WaitForChild("Humanoid", 10) :: Humanoid?
		if hum then
			hum.Died:Connect(function()
				if Config.KeepBatteryOnDeath then
					return
				end
				if Config.ReturnOnDeath then
					BatteryService.returnHome(player, "died")
				end
			end)
		end
		-- respawn: pastikan efek carry bersih
		clearCarryEffects(player)
	end)

	player.CharacterRemoving:Connect(function()
		-- karakter hilang: kalau masih bawa, kembalikan
		if carriedBy[player] and Config.ReturnOnRespawn then
			BatteryService.returnHome(player, "characterRemoving")
		end
	end)
end

-- ============================================================
-- INIT
-- ============================================================

function BatteryService.start(onCarryChanged: ((player: Player, carrying: boolean) -> ())?)
	notifyCarryChanged = onCarryChanged

	-- baterai yang sudah ada
	for _, b in ipairs(CollectionService:GetTagged(Config.PickupTag)) do
		if b:IsA("BasePart") then
			registerBattery(b)
		end
	end
	-- baterai yang ditambah runtime
	CollectionService:GetInstanceAddedSignal(Config.PickupTag):Connect(function(b)
		if b:IsA("BasePart") then
			registerBattery(b)
		end
	end)
	CollectionService:GetInstanceRemovedSignal(Config.PickupTag):Connect(function(b)
		if b:IsA("BasePart") then
			unregisterBattery(b)
		end
	end)

	-- lifecycle pemain
	Players.PlayerAdded:Connect(watchLifecycle)
	for _, p in ipairs(Players:GetPlayers()) do
		watchLifecycle(p)
	end
	Players.PlayerRemoving:Connect(function(p)
		if Config.ReturnOnLeave and carriedBy[p] then
			BatteryService.returnHome(p, "left")
		end
		dropCooldown[p] = nil
		savedSpeed[p] = nil
	end)

	Config.log("BatteryService started,", #CollectionService:GetTagged(Config.PickupTag), "batteries")
end

return BatteryService
