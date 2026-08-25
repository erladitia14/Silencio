--[[
	EnemyController.server.luau
	-----------------------------
	Script utama yang mengorkestrasi semua modul Monster AI.
	
	Script ini:
	  1. Menginisialisasi semua sub-modul (Config, StateMachine, dll)
	  2. Mendaftarkan state IDLE, PATROL, CHASING, ATTACKING
	  3. Menjalankan game loop untuk setiap monster
	
	SETUP:
	  - Letakkan script ini di ServerScriptService
	  - Folder "EnemyController" berisi semua ModuleScript harus ada
	    di ReplicatedStorage/Modules
	  - Beri tag "Monster" pada setiap Model NPC monster di Workspace
	    ATAU letakkan script ini langsung di dalam Model monster
	
	ARSITEKTUR:
	  ServerScriptService/
	  EnemyController  (Script ini)
	  ReplicatedStorage/Modules/
	  EnemyController/   (Folder)
	      Config
	      StateMachine
	      SafeZoneManager
	      TargetFinder
	      NavigationManager
	      CombatManager
	      PatrolManager
--]]

local CollectionService = game:GetService("CollectionService")

---------------------------------------------------------------------
-- REQUIRE MODULES
---------------------------------------------------------------------
local modulesFolder   = game:GetService("ReplicatedStorage")
	:WaitForChild("Modules", 10)
	:WaitForChild("EnemyController", 10)

assert(modulesFolder, "[EnemyController] Folder 'EnemyController' tidak ditemukan di ReplicatedStorage.Modules!")

local Config            = require(modulesFolder:WaitForChild("Config"))
local StateMachine      = require(modulesFolder:WaitForChild("StateMachine"))
local SafeZoneManager   = require(modulesFolder:WaitForChild("SafeZoneManager"))
local TargetFinder      = require(modulesFolder:WaitForChild("TargetFinder"))
local NavigationManager = require(modulesFolder:WaitForChild("NavigationManager"))
local CombatManager     = require(modulesFolder:WaitForChild("CombatManager"))
local PatrolManager     = require(modulesFolder:WaitForChild("PatrolManager"))
local AnimationManager  = require(modulesFolder:WaitForChild("AnimationManager"))
local SkinBinder        = require(modulesFolder:WaitForChild("SkinBinder"))

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
	chaseMode:      string,   -- PERSISTENT | NEAREST | ITEM_HOLDER (per-monster)
	lockTime:       number,   -- tick() saat target sekarang di-lock (untuk commit time)
	lastRetarget:   number,   -- tick() evaluasi retarget terakhir
	unreachSince:   number,   -- tick() sejak target PERSISTENT tak terjangkau (0 = terjangkau)
	signal:         BindableEvent?,  -- publikasi event AI ke script NPC (animasi dsb)
}

---------------------------------------------------------------------
-- PUBLIKASI STATE & EVENT (animation-agnostic)
---------------------------------------------------------------------
--[[
	PRINSIP: core AI TIDAK PERNAH menyentuh Animator / memutar animasi.
	Ia hanya MELAPORKAN apa yang sedang terjadi, lewat 2 kanal:

	  1. Attribute "AIState" di Model monster
	     -> "IDLE" | "PATROL" | "CHASING" | "ATTACKING" | "DEAD"
	     Untuk KEADAAN (bisa dibaca kapan saja, juga dari client).

	  2. BindableEvent "AISignal" (otomatis dibuat di dalam Model)
	     -> Fire("Attack", targetChar)
	        Fire("TargetAcquired", targetChar)
	        Fire("TargetLost")
	        Fire("Died")
	     Untuk KEJADIAN sekejap. Attribute tidak dipakai di sini karena
	     set nilai yang sama tidak memicu sinyal (serangan ke-2 jadi senyap).

	Jadi tiap NPC boleh punya animasi sendiri: cukup pasang script animasi
	di dalam Model NPC yang membaca "AIState" + mendengar "AISignal".
	TIDAK perlu mengubah script AI ini sama sekali.
--]]

--- Pastikan BindableEvent "AISignal" ada di dalam Model monster.
local function ensureSignal(monsterModel: Model): BindableEvent
	local existing = monsterModel:FindFirstChild("AISignal")
	if existing and existing:IsA("BindableEvent") then
		return existing
	end

	local signal = Instance.new("BindableEvent")
	signal.Name = "AISignal"
	signal.Parent = monsterModel
	return signal
end

--- Kirim event AI ke script NPC. Aman dipanggil walau signal belum ada.
local function emit(ctx: MonsterContext, eventName: string, ...)
	if ctx.signal then
		ctx.signal:Fire(eventName, ...)
	end
end

--- Publikasi state AI ke Attribute Model (dipanggil di setiap onEnter).
local function publishState(ctx: MonsterContext, stateName: string)
	ctx.model:SetAttribute("AIState", stateName)
end

--- Helper: catat lock target baru (reset timer commit & give-up).
local function lockTarget(ctx: MonsterContext, player: Player?, char: Model?)
	local isNewTarget = (char ~= nil and char ~= ctx.targetChar)

	ctx.targetPlayer = player
	ctx.targetChar = char
	ctx.lockTime = tick()
	ctx.lastRetarget = tick()
	ctx.unreachSince = 0

	if isNewTarget then
		emit(ctx, "TargetAcquired", char)
	end
end

--- Helper: lepas target + kabari NPC (supaya animasi bisa turun ke idle/walk).
local function clearTarget(ctx: MonsterContext)
	local had = ctx.targetChar ~= nil
	ctx.targetPlayer = nil
	ctx.targetChar = nil
	if had then
		emit(ctx, "TargetLost")
	end
end

--- Helper anti-thrash: evaluasi apakah harus GANTI target saat mengejar.
--- Dipakai mode NEAREST & ITEM_HOLDER. Mengembalikan (newPlayer?, newChar?)
--- HANYA jika kandidat baru layak menggantikan target sekarang; jika tidak,
--- mengembalikan target sekarang (tidak berubah).
---
--- Saat mengejar, monster sudah "berburu" -> deteksi 360 derajat (ignoreFOV).
---
--- Aturan mode ITEM_HOLDER (PRIORITAS ITEM di atas jarak):
---   - target sekarang BUKAN holder, tapi ADA holder terlihat -> SWITCH INSTAN
---     (abaikan commit time & hysteresis; item = prioritas mutlak)
---   - target sekarang holder, ada holder lain -> pakai hysteresis (anti-thrash)
---   - tidak ada holder -> fallback NEAREST + hysteresis
--- Aturan mode NEAREST:
---   - (1) hormati commit time, (2) tiap RetargetInterval,
---     (3) kandidat baru harus lebih dekat >= hysteresis persen ATAU >= MinGap studs.
local function evaluateRetarget(ctx: MonsterContext): (Player?, Model?)
	local now = tick()

	-- Mode ITEM_HOLDER: cek prioritas item DULU (bypass commit time/hysteresis)
	if ctx.chaseMode == "ITEM_HOLDER" then
		local curIsHolder = TargetFinder:holdsTargetItem(ctx.targetChar)
		-- Cari holder terdekat (360 derajat karena sedang berburu)
		local holderP, holderC = TargetFinder:findItemHolder(ctx.model, true)

		if not curIsHolder and holderC then
			-- Target sekarang bukan pembawa item, tapi ada pembawa item terlihat
			-- -> LANGSUNG alihkan (item = prioritas mutlak, abaikan jarak).
			return holderP, holderC
		end
		-- Kalau target sekarang SUDAH holder, lanjut ke logika hysteresis di bawah
		-- (biar dua pemegang item tidak bikin monster kejang-kejang).
	end

	-- (1) Commit time: wajib komit dulu sebelum boleh mikir switch
	if (now - ctx.lockTime) < Config.RetargetCommitTime then
		return ctx.targetPlayer, ctx.targetChar
	end

	-- (2) Throttle evaluasi
	if (now - ctx.lastRetarget) < Config.RetargetInterval then
		return ctx.targetPlayer, ctx.targetChar
	end
	ctx.lastRetarget = now

	-- Cari kandidat sesuai mode (360 derajat, sedang berburu)
	local candP, candC
	if ctx.chaseMode == "ITEM_HOLDER" then
		candP, candC = TargetFinder:findItemHolder(ctx.model, true)
		if not (candP and candC) then
			-- Tidak ada holder -> fallback nearest
			candP, candC = TargetFinder:findNearest(ctx.model, true)
		end
	else -- NEAREST
		candP, candC = TargetFinder:findNearest(ctx.model, true)
	end

	if not (candP and candC) then
		return ctx.targetPlayer, ctx.targetChar
	end

	-- Kandidat sama dengan target sekarang -> tidak berubah
	if candC == ctx.targetChar then
		return ctx.targetPlayer, ctx.targetChar
	end

	-- (3) Hysteresis: kandidat harus SIGNIFIKAN lebih dekat
	local curDist = TargetFinder:distanceTo(ctx.model, ctx.targetChar)
	local candDist = TargetFinder:distanceTo(ctx.model, candC)

	local closerByPct = candDist <= curDist * (1 - Config.RetargetHysteresis)
	local closerByGap = candDist <= (curDist - Config.RetargetMinGap)

	if closerByPct or closerByGap then
		return candP, candC
	end

	return ctx.targetPlayer, ctx.targetChar
end

--- Fix jeda pasca-kill: ketika target hilang/mati, JANGAN langsung patroli.
--- Coba akuisisi ulang seketika dengan deteksi 360 derajat (monster masih
--- "panas" dari berburu). Kalau ketemu korban lain dalam jangkauan -> lock
--- & kembali CHASING tanpa jeda. Kalau tidak ada -> baru PATROL.
--- Mengembalikan true jika berhasil mengunci target baru.
local function reacquireOrPatrol(fsm: any, ctx: MonsterContext): boolean
	local p, c = TargetFinder:acquireTarget(ctx.model, ctx.chaseMode, true)  -- ignoreFOV = 360
	if p and c then
		lockTarget(ctx, p, c)
		fsm:setState("CHASING", ctx)
		return true
	end

	clearTarget(ctx)
	fsm:setState("PATROL", ctx)
	return false
end

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
			ctx.humanoid.WalkSpeed = Config.get(ctx.model, "PatrolSpeed")
			publishState(ctx, "IDLE")
		end,

		onUpdate = function()
			-- Polling target selama masa idle agar tidak "buta" terhadap player
			-- yang lewat (FIX bug A: sebelumnya task.wait memblok deteksi).
			local elapsed = 0
			local waitTime = Config.get(ctx.model, "PatrolWaitTime")
			while elapsed < waitTime do
				local player, char = TargetFinder:acquireTarget(ctx.model, ctx.chaseMode)
				if player and char then
					lockTarget(ctx, player, char)
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
			ctx.humanoid.WalkSpeed = Config.get(ctx.model, "PatrolSpeed")
			publishState(ctx, "PATROL")
		end,

		onUpdate = function()
			-- Cek target dulu sebelum bergerak
			local player, char = TargetFinder:acquireTarget(ctx.model, ctx.chaseMode)
			if player and char then
				lockTarget(ctx, player, char)
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
					local p, c = TargetFinder:acquireTarget(ctx.model, ctx.chaseMode)
					if p and c then
						lockTarget(ctx, p, c)
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
			ctx.humanoid.WalkSpeed = Config.get(ctx.model, "ChaseSpeed")
			publishState(ctx, "CHASING")
			if ctx.targetPlayer then
				print("[MonsterAI] " .. ctx.model.Name .. " mengejar " .. ctx.targetPlayer.Name)
			end
		end,

		onUpdate = function()
			-- Validasi target masih layak.
			-- PERSISTENT: hanya menyerah kalau target MATI / hilang dari world
			-- (Safe Zone tetap dihormati sebagai aturan game, tidak bisa ditembus).
			-- NEAREST/ITEM_HOLDER: menyerah bila target tak valid (mati/safezone/hilang).
			if not TargetFinder:isValidTarget(ctx.targetChar) then
				if ctx.targetChar and SafeZoneManager:isInSafeZone(ctx.targetChar) then
					print("[MonsterAI] " .. ctx.model.Name .. ": Target masuk Safe Zone!")
				else
					print("[MonsterAI] " .. ctx.model.Name .. ": Target hilang/mati.")
				end
				-- Fix jeda pasca-kill: langsung cari korban lain (360) sebelum patroli.
				reacquireOrPatrol(fsm, ctx)
				return
			end

			-- Cek jangkauan serang
			if TargetFinder:isInAttackRange(ctx.model, ctx.targetChar :: Model) then
				fsm:setState("ATTACKING", ctx)
				return
			end

			if ctx.chaseMode == "PERSISTENT" then
				-- PERSISTENT: kejar terus tanpa peduli chase range / LOS.
				-- Target hanya lepas kalau mati/safezone (sudah dicek di atas).
				-- Opsional give-up bila terlalu lama tak terjangkau.
				if Config.PersistentGiveUpTime > 0 then
					if not TargetFinder:isInChaseRange(ctx.model, ctx.targetChar :: Model) then
						if ctx.unreachSince == 0 then
							ctx.unreachSince = tick()
						elseif (tick() - ctx.unreachSince) >= Config.PersistentGiveUpTime then
							print("[MonsterAI] " .. ctx.model.Name .. ": Menyerah (target terlalu lama tak terjangkau).")
							clearTarget(ctx)
							fsm:setState("PATROL", ctx)
							return
						end
					else
						ctx.unreachSince = 0
					end
				end
			else
				-- NEAREST / ITEM_HOLDER: hormati chase range + boleh retarget (anti-thrash)
				if not TargetFinder:isInChaseRange(ctx.model, ctx.targetChar :: Model) then
					print("[MonsterAI] " .. ctx.model.Name .. ": Target keluar dari jangkauan.")
					clearTarget(ctx)
					fsm:setState("PATROL", ctx)
					return
				end

				-- Evaluasi ganti target (dengan commit time + hysteresis + interval)
				local newP, newC = evaluateRetarget(ctx)
				if newC and newC ~= ctx.targetChar then
					print("[MonsterAI] " .. ctx.model.Name .. ": Ganti target -> " .. (newP and newP.Name or "?"))
					lockTarget(ctx, newP, newC)
				end
			end

			-- Kejar target langsung (tanpa pathfinding untuk responsivitas)
			local targetRoot = (ctx.targetChar :: Model):FindFirstChild("HumanoidRootPart") :: BasePart
			NavigationManager:directMoveTo(ctx.humanoid, targetRoot.Position)
			task.wait(0.2)
		end,

		onExit = function()
			ctx.humanoid.WalkSpeed = Config.get(ctx.model, "PatrolSpeed")
		end,
	})

	------------------------------------------------------------
	-- ATTACKING: Menyerang target dalam jangkauan.
	------------------------------------------------------------
	fsm:addState("ATTACKING", {
		onEnter = function()
			ctx.humanoid.WalkSpeed = 0  -- Berhenti saat menyerang
			publishState(ctx, "ATTACKING")
		end,

		onUpdate = function()
			-- Validasi target
			if not TargetFinder:isValidTarget(ctx.targetChar) then
				-- Fix jeda pasca-kill: target baru saja mati -> langsung cari
				-- korban berikutnya (360 derajat) tanpa lewat patroli dulu.
				reacquireOrPatrol(fsm, ctx)
				return
			end

			-- FIX bug B: kalau target keluar attack range, balik ke CHASING.
			-- Selama masih in-range, TETAP di ATTACKING (cegah ping-pong state
			-- yang bikin WalkSpeed & animasi flicker tiap cooldown).
			if not TargetFinder:isInAttackRange(ctx.model, ctx.targetChar :: Model) then
				fsm:setState("CHASING", ctx)
				return
			end

			-- Serang jika cooldown selesai.
			-- Animasi TIDAK diputar di sini: cukup emit event "Attack",
			-- script animasi milik NPC yang memutuskan animasi apa yang jalan.
			if ctx.combat:canAttack() then
				local hit = ctx.combat:attack(ctx.targetChar :: Model)
				if hit then
					emit(ctx, "Attack", ctx.targetChar)
				end
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

	-- GUARD: MaxHealth/Health = 0 bikin main loop (while Health > 0) tidak pernah
	-- jalan sekali pun -> NPC diam total tanpa error. Ini jebakan senyap yang
	-- sulit dilacak, jadi laporkan JELAS dan perbaiki otomatis.
	if humanoid.MaxHealth <= 0 then
		warn("[MonsterAI] " .. monsterModel.Name .. ": MaxHealth=0 (NPC dianggap mati -> AI tidak akan jalan). Diperbaiki otomatis ke 100. Set MaxHealth di Studio agar tidak berulang.")
		humanoid.MaxHealth = 100
		humanoid.Health = 100
	elseif humanoid.Health <= 0 then
		warn("[MonsterAI] " .. monsterModel.Name .. ": Health=0 saat init (NPC mati) -> AI tidak akan jalan. Diperbaiki otomatis ke MaxHealth.")
		humanoid.Health = humanoid.MaxHealth
	end

	print("[MonsterAI] Menginisialisasi AI untuk: " .. monsterModel.Name)

	-- OVERRIDE PER-NPC: laporkan Attribute yang salah tipe/negatif SEKALI di
	-- sini. Resolver (Config.get) sendiri silent karena dipanggil tiap tick;
	-- tanpa laporan ini, override yang salah ketik akan diam-diam diabaikan
	-- dan tim bingung kenapa "tidak ngefek".
	for _, problem in Config.validateOverrides(monsterModel) do
		warn("[MonsterAI] " .. monsterModel.Name .. ": " .. problem)
	end

	-- Setup Humanoid
	humanoid.WalkSpeed = Config.get(monsterModel, "PatrolSpeed")
	humanoid.AutoRotate = true

	-- Tentukan chase mode: Attribute per-monster > default Config.
	-- Attribute "ChaseMode" (string) di Model monster meng-override default.
	local modeAttr = monsterModel:GetAttribute("ChaseMode")
	local chaseMode = (typeof(modeAttr) == "string" and modeAttr ~= "") and modeAttr or Config.ChaseMode
	if chaseMode ~= "PERSISTENT" and chaseMode ~= "NEAREST" and chaseMode ~= "ITEM_HOLDER" then
		warn("[MonsterAI] ChaseMode '" .. tostring(chaseMode) .. "' tidak dikenal pada " .. monsterModel.Name .. ". Fallback ke NEAREST.")
		chaseMode = "NEAREST"
	end
	print("[MonsterAI] " .. monsterModel.Name .. " chase mode: " .. chaseMode)

	-- PASANG SKIN (mesh visual) bila ada.
	-- NPC bisa terdiri dari dua model di folder yang sama:
	--   rig  -> tag "Monster"      (Humanoid, gerak, damage, tabrakan)
	--   skin -> tag "MonsterSkin"  (mesh visual + animasi)
	-- SkinBinder yang mengurus weld, mematikan collision skin, menyembunyikan
	-- rig, dan mematikan script animasi lama yang berebut Animator.
	local bind = SkinBinder:bind(monsterModel)
	if bind.error then
		warn("[MonsterAI] " .. monsterModel.Name .. ": skin gagal dipasang -> " .. tostring(bind.error))
	elseif bind.skins > 0 then
		print(string.format(
			"[MonsterAI] %s: skin terpasang (%d skin, weld baru %d, sudah ada %d, collision off %d, part rig disembunyikan %d, animator %d, part diluruskan %d%s)",
			monsterModel.Name, bind.skins, bind.welded, bind.alreadyWelded,
			bind.collisionOff, bind.rigHidden, bind.animated, bind.aligned,
			#bind.scriptsDisabled > 0 and (", script dimatikan: " .. table.concat(bind.scriptsDisabled, " ")) or ""
		))
	end

	-- Kanal publikasi ke script NPC (animasi, SFX, VFX, dll)
	local signal = ensureSignal(monsterModel)

	-- ANIMASI OTOMATIS (default NYALA).
	-- Cukup tag "Monster" -> NPC langsung beranimasi. AnimationManager membaca
	-- ID animasi dari dalam Model itu sendiri (folder "Animations" custom, lalu
	-- paket "Animate" bawaan rig, lalu default Roblox), jadi tidak perlu
	-- menempel script atau mengisi ID manual.
	--
	-- OPT-OUT: beri Attribute "NoAutoAnimations" = true (Bool) pada Model bila
	-- tim ingin mengurus animasi NPC itu sendiri. Core AI tetap melaporkan
	-- keadaan lewat Attribute "AIState" + BindableEvent "AISignal", jadi script
	-- animasi buatan tim bisa mengikuti tanpa mengubah script ini.
	-- Penting: hanya SATU pihak yang boleh menyetir Animator (dua penyetir pada
	-- Animator yang sama = animasi kejang).
	local animManager = nil
	if monsterModel:GetAttribute("NoAutoAnimations") == true then
		print("[MonsterAI] " .. monsterModel.Name .. ": animasi diserahkan ke script NPC (NoAutoAnimations=true).")
	else
		local ok, mgr = pcall(function()
			return AnimationManager.new(monsterModel)
		end)
		if ok then
			animManager = mgr
		else
			warn("[MonsterAI] " .. monsterModel.Name .. ": gagal memuat animasi otomatis -> " .. tostring(mgr))
		end
	end

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
		chaseMode    = chaseMode,
		lockTime     = 0,
		lastRetarget = 0,
		unreachSince = 0,
		signal       = signal,
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
		-- Kabari script NPC bahwa monster mati (animasi death diurus NPC sendiri)
		publishState(ctx, "DEAD")
		emit(ctx, "Died")

		if animManager then
			animManager:destroy()
		end
		if ctx.combat and ctx.combat.destroy then
			ctx.combat:destroy()
		end
		-- Lepas animator skin + catatan ignore-list raycast
		SkinBinder:unbind(monsterModel)
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
