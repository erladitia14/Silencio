--[[
	MonsterController.server.luau
	-----------------------------
	Script utama yang mengorkestrasi semua modul Monster AI.
	
	Script ini:
	  1. Menginisialisasi semua sub-modul (Config, StateMachine, dll)
	  2. Mendaftarkan state IDLE, PATROL, CHASING, ATTACKING
	  3. Menjalankan game loop untuk setiap monster
	
	SETUP:
	  - Letakkan script ini di ServerScriptService
	  - Folder "MonsterAI" berisi semua ModuleScript harus ada
	    sebagai child/sibling di ServerScriptService
	  - Beri tag "Monster" pada setiap Model NPC monster di Workspace
	    ATAU letakkan script ini langsung di dalam Model monster
	
	ARSITEKTUR:
	  ServerScriptService/
	  ├── MonsterController  (Script ini)
	  └── MonsterAI/         (Folder)
	      ├── Config
	      ├── StateMachine
	      ├── SafeZoneManager
	      ├── TargetFinder
	      ├── NavigationManager
	      ├── CombatManager
	      └── PatrolManager
--]]

local CollectionService = game:GetService("CollectionService")

---------------------------------------------------------------------
-- REQUIRE MODULES
---------------------------------------------------------------------
local modulesFolder   = script.Parent:FindFirstChild("MonsterAI")
	or script.Parent:WaitForChild("MonsterAI", 10)

assert(modulesFolder, "[MonsterController] Folder 'MonsterAI' tidak ditemukan di ServerScriptService!")

local Config            = require(modulesFolder:WaitForChild("Config"))
local StateMachine      = require(modulesFolder:WaitForChild("StateMachine"))
local SafeZoneManager   = require(modulesFolder:WaitForChild("SafeZoneManager"))
local TargetFinder      = require(modulesFolder:WaitForChild("TargetFinder"))
local NavigationManager = require(modulesFolder:WaitForChild("NavigationManager"))
local CombatManager     = require(modulesFolder:WaitForChild("CombatManager"))
local PatrolManager     = require(modulesFolder:WaitForChild("PatrolManager"))
local AnimationManager  = require(modulesFolder:WaitForChild("AnimationManager"))

---------------------------------------------------------------------
-- TYPES
---------------------------------------------------------------------
export type MonsterContext = {
	model:          Model,
	humanoid:       Humanoid,
	rootPart:       BasePart,
	fsm:            any,
	patrol:         any,
	combat:         any,
	animation:      any,
	targetPlayer:   Player?,
	targetChar:     Model?,
}

---------------------------------------------------------------------
-- STATE DEFINITIONS
---------------------------------------------------------------------

--- Mendaftarkan semua state ke FSM untuk sebuah monster context.
local function registerStates(fsm: any, ctx: MonsterContext)

	------------------------------------------------------------
	-- IDLE: Diam sebentar sebelum lanjut patroli.
	------------------------------------------------------------
	fsm:addState("IDLE", {
		onEnter = function()
			ctx.humanoid.WalkSpeed = Config.PatrolSpeed
		end,

		onUpdate = function()
			-- Polling target selama masa idle agar tidak "buta" terhadap player
			-- yang lewat (FIX bug A: sebelumnya task.wait memblok deteksi).
			local elapsed = 0
			while elapsed < Config.PatrolWaitTime do
				local player, char = TargetFinder:findNearest(ctx.model)
				if player and char then
					ctx.targetPlayer = player
					ctx.targetChar = char
					fsm:setState("CHASING", ctx)
					return
				end
				task.wait(0.2)
				elapsed += 0.2
			end

			fsm:setState("PATROL", ctx)
		end,
	})

	------------------------------------------------------------
	-- PATROL: Bergerak menuju waypoint berikutnya.
	------------------------------------------------------------
	fsm:addState("PATROL", {
		onEnter = function()
			ctx.humanoid.WalkSpeed = Config.PatrolSpeed
		end,

		onUpdate = function()
			-- Cek target dulu sebelum bergerak
			local player, char = TargetFinder:findNearest(ctx.model)
			if player and char then
				ctx.targetPlayer = player
				ctx.targetChar = char
				fsm:setState("CHASING", ctx)
				return
			end

			-- Ambil waypoint berikutnya
			local destination = ctx.patrol:getNextWaypoint()
			if not destination then
				task.wait(1)
				return
			end

			-- Navigasi ke waypoint, dengan abort jika target terdeteksi
			NavigationManager:moveTo(
				ctx.humanoid,
				ctx.rootPart,
				destination,
				function()
					-- Abort navigation jika target ditemukan
					local p, c = TargetFinder:findNearest(ctx.model)
					if p and c then
						ctx.targetPlayer = p
						ctx.targetChar = c
						return true
					end
					return false
				end,
				5
			)

			-- Setelah sampai, jika target ditemukan saat navigasi
			if ctx.targetChar then
				fsm:setState("CHASING", ctx)
				return
			end

			-- Istirahat sebentar
			fsm:setState("IDLE", ctx)
		end,
	})

	------------------------------------------------------------
	-- CHASING: Mengejar target player.
	------------------------------------------------------------
	fsm:addState("CHASING", {
		onEnter = function()
			ctx.humanoid.WalkSpeed = Config.ChaseSpeed
			if ctx.targetPlayer then
				print("[MonsterAI] " .. ctx.model.Name .. " mengejar " .. ctx.targetPlayer.Name)
			end
		end,

		onUpdate = function()
			-- Validasi target masih layak
			if not TargetFinder:isValidTarget(ctx.targetChar) then
				if ctx.targetChar and SafeZoneManager:isInSafeZone(ctx.targetChar) then
					print("[MonsterAI] " .. ctx.model.Name .. ": Target masuk Safe Zone!")
				else
					print("[MonsterAI] " .. ctx.model.Name .. ": Target hilang/mati.")
				end
				ctx.targetPlayer = nil
				ctx.targetChar = nil
				fsm:setState("PATROL", ctx)
				task.wait(0.5)
				return
			end

			-- Cek jangkauan serang
			if TargetFinder:isInAttackRange(ctx.model, ctx.targetChar :: Model) then
				fsm:setState("ATTACKING", ctx)
				return
			end

			-- Cek apakah target masih dalam chase range
			if not TargetFinder:isInChaseRange(ctx.model, ctx.targetChar :: Model) then
				print("[MonsterAI] " .. ctx.model.Name .. ": Target keluar dari jangkauan.")
				ctx.targetPlayer = nil
				ctx.targetChar = nil
				fsm:setState("PATROL", ctx)
				return
			end

			-- Kejar target langsung (tanpa pathfinding untuk responsivitas)
			local targetRoot = (ctx.targetChar :: Model):FindFirstChild("HumanoidRootPart") :: BasePart
			NavigationManager:directMoveTo(ctx.humanoid, targetRoot.Position)
			task.wait(0.2)
		end,

		onExit = function()
			ctx.humanoid.WalkSpeed = Config.PatrolSpeed
		end,
	})

	------------------------------------------------------------
	-- ATTACKING: Menyerang target dalam jangkauan.
	------------------------------------------------------------
	fsm:addState("ATTACKING", {
		onEnter = function()
			ctx.humanoid.WalkSpeed = 0  -- Berhenti saat menyerang
		end,

		onUpdate = function()
			-- Validasi target
			if not TargetFinder:isValidTarget(ctx.targetChar) then
				ctx.targetPlayer = nil
				ctx.targetChar = nil
				fsm:setState("PATROL", ctx)
				return
			end

			-- FIX bug B: kalau target keluar attack range, balik ke CHASING.
			-- Selama masih in-range, TETAP di ATTACKING (cegah ping-pong state
			-- yang bikin WalkSpeed & animasi flicker tiap cooldown).
			if not TargetFinder:isInAttackRange(ctx.model, ctx.targetChar :: Model) then
				fsm:setState("CHASING", ctx)
				return
			end

			-- Serang jika cooldown selesai
			if ctx.combat:canAttack() then
				ctx.combat:attack(ctx.targetChar :: Model)
			end

			task.wait(0.3)
		end,
	})
end

---------------------------------------------------------------------
-- MONSTER INITIALIZATION
---------------------------------------------------------------------

--- Menginisialisasi AI untuk satu model monster.
local function initializeMonster(monsterModel: Model)
	-- Validasi model
	local humanoid = monsterModel:FindFirstChildOfClass("Humanoid")
	local rootPart = monsterModel:FindFirstChild("HumanoidRootPart") :: BasePart?

	if not humanoid or not rootPart then
		warn("[MonsterAI] Model '" .. monsterModel.Name .. "' tidak memiliki Humanoid/HumanoidRootPart. Skip.")
		return
	end

	print("[MonsterAI] Menginisialisasi AI untuk: " .. monsterModel.Name)

	-- Setup Humanoid
	humanoid.WalkSpeed = Config.PatrolSpeed
	humanoid.AutoRotate = true

	-- Inisialisasi AnimationManager untuk monster
	local animManager = AnimationManager.new(monsterModel)

	-- Buat context
	local ctx: MonsterContext = {
		model    = monsterModel,
		humanoid = humanoid,
		rootPart = rootPart,
		fsm      = StateMachine.new(),
		patrol   = PatrolManager.new(monsterModel),
		combat   = CombatManager.new(monsterModel, animManager),
		animation = animManager,
		targetPlayer = nil,
		targetChar   = nil,
	}

	-- Register states
	registerStates(ctx.fsm, ctx)

	-- Start di state IDLE
	ctx.fsm:setState("IDLE", ctx)

	-- Main loop
	task.spawn(function()
		while humanoid and humanoid.Health > 0 do
			ctx.fsm:update(ctx)
			task.wait(0.1)
		end
		animManager:destroy()
		print("[MonsterAI] " .. monsterModel.Name .. " telah mati. AI dihentikan.")
	end)
end

---------------------------------------------------------------------
-- STARTUP: Auto-detect monster dengan tag "Monster"
---------------------------------------------------------------------
print("[MonsterAI] === Silencio Monster AI System v2.0 ===")
print("[MonsterAI] Mencari monster dengan tag: '" .. Config.MonsterTag .. "'")

-- Inisialisasi monster yang sudah ada
for _, monster in CollectionService:GetTagged(Config.MonsterTag) do
	if monster:IsA("Model") then
		initializeMonster(monster)
	end
end

-- Listen untuk monster baru yang ditambahkan saat runtime
CollectionService:GetInstanceAddedSignal(Config.MonsterTag):Connect(function(instance)
	if instance:IsA("Model") then
		-- Tunggu sebentar agar model fully loaded
		task.wait(0.5)
		initializeMonster(instance)
	end
end)

print("[MonsterAI] Sistem siap. Beri tag '" .. Config.MonsterTag .. "' pada Model NPC untuk mengaktifkan AI.")
