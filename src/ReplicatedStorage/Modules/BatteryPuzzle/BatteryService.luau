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
-- PROMPT GLOBAL UPDATE (harus di atas agar bisa dipanggil fungsi lain)
-- ============================================================

local function updateAllPickupPrompts()
	local anyCarrying = false
	for _, plr in ipairs(Players:GetPlayers()) do
		if carriedBy[plr] then
			anyCarrying = true
			break
		end
	end

	-- 1. Matikan/nyalakan prompt pada semua baterai di table
	for b, rec in pairs(batteries) do
		local p = b:FindFirstChild("BatteryPickupPrompt")
		if p and p:IsA("ProximityPrompt") then
			if rec.inserted or rec.carrier ~= nil then
				p.Enabled = false
			elseif anyCarrying then
				p.Enabled = false
			else
				p.Enabled = true
			end
		end
	end

	-- 2. Fallback untuk semua part bertag "BatteryPickup" di workspace
	for _, b in ipairs(CollectionService:GetTagged(Config.PickupTag)) do
		if b:IsA("BasePart") then
			local p = b:FindFirstChild("BatteryPickupPrompt")
			if p and p:IsA("ProximityPrompt") then
				local rec = batteries[b]
				if rec and (rec.inserted or rec.carrier ~= nil) then
					p.Enabled = false
				elseif anyCarrying then
					p.Enabled = false
				elseif not rec or not rec.inserted then
					p.Enabled = true
				end
			end
		end
	end
end

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

local function getHand(player: Player): BasePart?
	local c = characterOf(player)
	if not c then
		return nil
	end
	-- R15: RightHand, R6: Right Arm, fallback: HumanoidRootPart
	return (c:FindFirstChild("RightHand") or c:FindFirstChild("Right Arm") or c:FindFirstChild("HumanoidRootPart")) :: BasePart?
end

local function showCarriedVisual(player: Player, battery: BasePart): BasePart?
	local hand = getHand(player)
	if not hand then
		Config.log("showCarriedVisual: no hand/root for", player.Name)
		return nil
	end

	-- Salinan visual: pastikan prompt DIBUANG, transparansi 0, dan SEMUA tag dicabut
	local vis = battery:Clone()
	vis.Name = "CarriedBattery"
	vis.Transparency = 0 -- JANGAN ikutan transparan dari part asli
	vis.Anchored = false
	vis.CanCollide = false
	vis.CanTouch = false
	vis.CanQuery = false
	vis.Massless = true

	-- KRUSIAL: Cabut semua tag CollectionService dari clone!
	-- Kalau tag "BatteryPickup" terbawa clone, CollectionService akan mentrigger
	-- registerBattery() baru pada part ini, sehingga muncul ProximityPrompt kedua
	-- yang menempel di badan/tangan pemain!
	for _, tag in ipairs(CollectionService:GetTags(vis)) do
		CollectionService:RemoveTag(vis, tag)
	end

	-- Hapus semua prompt agar tidak melayang di badan pemain
	for _, d in ipairs(vis:GetDescendants()) do
		if d:IsA("ProximityPrompt") then
			d:Destroy()
		end
	end

	-- Weld ke tangan kanan pemain
	local w = Instance.new("Weld")
	w.Name = "CarryWeld"
	w.Part0 = hand
	w.Part1 = vis
	-- Offset pas di genggaman tangan kanan
	w.C0 = CFrame.new(0, -0.3, -0.2) * CFrame.Angles(math.rad(90), 0, 0)
	w.Parent = vis

	vis.CFrame = hand.CFrame * w.C0
	vis.Parent = player.Character -- Parent ke Character Model, BUKAN ke Part

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

	-- visual: buat salinan visual di tangan DULUAN sebelum part asli disembunyikan
	if Config.HideOriginalWhileCarried then
		local vis = showCarriedVisual(player, battery)
		if not vis then
			Config.log("pickup: visual gagal untuk", player.Name, "— batalkan? tidak, tetap pickup")
		end

		battery.Transparency = 1
		battery.CanCollide = false
		battery.CanQuery = false
		battery.CanTouch = false
		local prompt = battery:FindFirstChild("BatteryPickupPrompt")
		if prompt and prompt:IsA("ProximityPrompt") then
			prompt.Enabled = false
		end
	end

	if notifyCarryChanged then
		notifyCarryChanged(player, true)
	end
	updateAllPickupPrompts()
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
		battery.CanTouch = true
	end

	-- Nyalakan prompt lagi supaya bisa diambil kembali
	local prompt = battery:FindFirstChild("BatteryPickupPrompt")
	if prompt and prompt:IsA("ProximityPrompt") then
		prompt.Enabled = true
	end

	clearCarryEffects(player)
	updateAllPickupPrompts()
	if notifyCarryChanged then
		notifyCarryChanged(player, false)
	end
	Config.log("drop", player.Name, reason or "")
	return true
end

-- Recovery: kembalikan ke spawn point asli baterai
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
		battery.CanTouch = true
	end

	-- Nyalakan prompt lagi supaya bisa diambil kembali
	local prompt = battery:FindFirstChild("BatteryPickupPrompt")
	if prompt and prompt:IsA("ProximityPrompt") then
		prompt.Enabled = true
	end

	clearCarryEffects(player)
	updateAllPickupPrompts()
	if notifyCarryChanged then
		notifyCarryChanged(player, false)
	end
	Config.log("returnHome", player.Name, reason or "")
	return true
end

-- Dipanggil CaseService saat baterai berhasil dipasang
function BatteryService.markInserted(player: Player, battery: BasePart, slotCFrame: CFrame?)
	local rec = batteries[battery]
	carriedBy[player] = nil
	if rec then
		rec.carrier = nil
		rec.inserted = true
		clearCarriedVisual(battery)
		-- Baterai asal di folder disembunyikan permanen (sudah terwakili di case)
		battery.Transparency = 1
		battery.CanCollide = false
		battery.CanQuery = false
		battery.CanTouch = false
		battery.Anchored = true
		local prompt = battery:FindFirstChild("BatteryPickupPrompt")
		if prompt and prompt:IsA("ProximityPrompt") then
			prompt.Enabled = false
		end
	end
	clearCarryEffects(player)
	updateAllPickupPrompts()
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
	-- Jangan daftarkan visual tiruan atau part yang sudah dipegang karakter
	if battery.Name == "CarriedBattery" then
		return
	end
	if battery:FindFirstAncestorOfClass("Model") and battery:FindFirstAncestorOfClass("Model"):FindFirstChildOfClass("Humanoid") then
		return
	end
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

function BatteryService.attachDamageListener(player: Player, hum: Humanoid)
	hum.HealthChanged:Connect(function(health)
		if health <= 0 then
			return
		end
		if not carriedBy[player] then
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