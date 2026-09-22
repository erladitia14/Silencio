--[[
	KnockService.luau
	-----------------
	OTAK sistem knock & revive. Menyatukan DownedState + CrawlController +
	ReviveManager, dan menjalankan:

	  1. Deteksi sumber damage: apakah pemain roboh karena MONSTER?
	     -> jam "terakhir dipukul monster" di-cap tiap monster menyerang.
	  2. Keputusan tumbang vs mati saat Health mencapai 0.
	  3. Bleed-out ticker: kurangi sisa waktu; habis -> mati beneran.
	  4. Revive ticker: perbarui progres tahanan tombol teman.

	Sinyal ke tim (SFX/UI) lewat BindableEvent Config.SignalName di
	ReplicatedStorage — sistem ini TIDAK memaksa UI apa pun sendiri.
--]]

local Players           = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config          = require(script.Parent.Config)
local Signal          = require(script.Parent.Signal)
local DownedState     = require(script.Parent.DownedState)
local CrawlController  = require(script.Parent.CrawlController)
local ReviveManager    = require(script.Parent.ReviveManager)

local KnockService = {}

-- Sinyal keluar (dipublikasikan lewat BindableEvent nyata + observer internal).
KnockService.Event = Signal.new()

-- Cap "player X terakhir dipukul monster pada clock T".
local lastMonsterHit: { [Player]: number } = {}
-- Koneksi per karakter (bersih saat respawn).
local charConns: { [Model]: { RBXScriptConnection } } = {}
-- Koneksi AISignal per monster (jangan dobel-connect).
local monsterConns: { [Instance]: RBXScriptConnection } = {}
local started = false
local bleedThread: thread? = nil

-----------------------------------------------------------------
-- BINDABLEEVENT PUBLIK (untuk tim; idempotent)
-----------------------------------------------------------------
local function getSignalEvent(): BindableEvent
	local existing = ReplicatedStorage:FindFirstChild(Config.SignalName)
	if existing and existing:IsA("BindableEvent") then
		return existing
	end
	local be = Instance.new("BindableEvent")
	be.Name = Config.SignalName
	be.Parent = ReplicatedStorage
	return be
end

local function fireSignal(eventName: string, ...)
	KnockService.Event:Fire(eventName, ...)
	local be = getSignalEvent()
	be:Fire(eventName, ...)
end

-----------------------------------------------------------------
-- DETEKSI MONSTER
-----------------------------------------------------------------
--- Catat bahwa monster baru saja menyerang sebuah karakter.
local function noteMonsterAttack(targetChar: Model?)
	if not targetChar then
		return
	end
	local player = Players:GetPlayerFromCharacter(targetChar)
	if player then
		lastMonsterHit[player] = os.clock()
	end
end

--- Apakah pemain baru saja dipukul monster dalam MonsterHitWindow detik?
local function wasHitByMonster(player: Player?): boolean
	if not player then
		return false
	end
	local t = lastMonsterHit[player]
	if not t then
		return false
	end
	return (os.clock() - t) <= Config.MonsterHitWindow
end

--- Sambungkan AISignal sebuah monster supaya kita tahu kapan ia menyerang.
--- EnemyController menerbitkan Fire("Attack", targetChar) tepat setelah damage.
local function hookMonster(monster: Instance)
	if monsterConns[monster] then
		return
	end
	if not monster:IsA("Model") then
		return
	end
	task.spawn(function()
		local signal = monster:WaitForChild(Config.MonsterSignal, Config.MonsterSignalTimeout)
		if not signal or not signal:IsA("BindableEvent") then
			return
		end
		if monsterConns[monster] then
			return
		end
		monsterConns[monster] = signal.Event:Connect(function(eventName, targetChar)
			if eventName == Config.MonsterAttackEvent then
				noteMonsterAttack(targetChar)
			end
		end)
	end)
end

local function unhookMonster(monster: Instance)
	local c = monsterConns[monster]
	if c then
		c:Disconnect()
		monsterConns[monster] = nil
	end
end

-----------------------------------------------------------------
-- KEPUTUSAN: TUMBANG ATAU MATI
-----------------------------------------------------------------
--- Dipanggil saat Health karakter mencapai 0 (dan belum tumbang).
--- Mengembalikan true bila pemain masuk kondisi tumbang.
function KnockService.handleLethal(character: Model, humanoid: Humanoid): boolean
	if DownedState.isDowned(character) then
		return true -- sudah tumbang, damage lanjutan diabaikan
	end

	local player = Players:GetPlayerFromCharacter(character)

	-- Hanya monster yang bikin tumbang? (spec Aer). Sebab lain -> mati biasa.
	if Config.KnockOnlyFromMonster and not wasHitByMonster(player) then
		-- Biarkan mati: kembalikan kemampuan mati lalu pastikan Health 0.
		DownedState.disarmAntiDeath(humanoid)
		if humanoid.Health > 0 then
			-- tak seharusnya terjadi, tapi jaga-jaga
			humanoid.Health = 0
		end
		return false
	end

	local rec = DownedState.enter(character, humanoid)
	if not rec then
		return false
	end

	CrawlController.apply(character, humanoid)
	ReviveManager.attach(character)

	fireSignal(Config.SignalEvent.DOWNED, player)
	return true
end

-----------------------------------------------------------------
-- REVIVE CALLBACK
-----------------------------------------------------------------
local function onReviveComplete(character: Model, reviver: Player)
	if not DownedState.isDowned(character) then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	ReviveManager.detach(character)
	CrawlController.restore(character, humanoid)
	DownedState.revive(character, humanoid)

	local player = Players:GetPlayerFromCharacter(character)
	fireSignal(Config.SignalEvent.REVIVED, player, reviver)
end

-----------------------------------------------------------------
-- MATI BENERAN (bleed-out habis)
-----------------------------------------------------------------
local function bleedOutKill(character: Model)
	if not DownedState.isDowned(character) then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local player = Players:GetPlayerFromCharacter(character)

	ReviveManager.detach(character)
	CrawlController.restore(character, humanoid)
	DownedState.kill(character, humanoid)

	fireSignal(Config.SignalEvent.BLEED_OUT, player)
end

-----------------------------------------------------------------
-- TICKER UTAMA
-----------------------------------------------------------------
local function tickAll()
	local now = os.clock()
	-- Iterasi salinan supaya aman menghapus di tengah.
	local records = {}
	for character, rec in DownedState.getAll() do
		records[character] = rec
	end

	for character, rec in records do
		-- Karakter hilang dari world -> bersihkan.
		if not character.Parent then
			DownedState.forget(character)
			ReviveManager.detach(character)
			CrawlController.restore(character, nil)
		else
			-- Jaga kecepatan merangkak.
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				CrawlController.enforce(character, humanoid)
				-- Jaga Health tidak menampilkan angka negatif.
				if Config.get(rec.player, "ClampHealthWhileDowned") and humanoid.Health < 0 then
					humanoid.Health = 0
				end
			end

			-- Perbarui progres revive.
			ReviveManager.step(character)

			-- Bleed-out.
			local remaining = math.max(0, rec.deadline - now)
			character:SetAttribute(Config.BleedOutAttribute, remaining)

			-- Peringatan sekali saat mendekati habis.
			if not rec.warned and remaining <= Config.BleedOutWarningTime then
				rec.warned = true
				fireSignal(Config.SignalEvent.WARNING, rec.player, remaining)
			end

			if remaining <= 0 then
				bleedOutKill(character)
			end
		end
	end
end

-----------------------------------------------------------------
-- HOOK KARAKTER (deteksi Health -> 0)
-----------------------------------------------------------------
local function hookCharacter(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	if not humanoid then
		return
	end

	-- Persenjatai anti-death SEBELUM damage apa pun bisa masuk.
	DownedState.armAntiDeath(humanoid)

	local conns = {}

	table.insert(conns, humanoid.HealthChanged:Connect(function(health)
		if health <= 0 and not DownedState.isDowned(character) then
			-- Beri jeda kecil supaya sinyal "Attack" monster sempat tercatat.
			task.delay(Config.KnockDecisionDelay, function()
				if character.Parent and humanoid.Parent and humanoid.Health <= 0
					and not DownedState.isDowned(character)
				then
					KnockService.handleLethal(character, humanoid)
				end
			end)
		end
	end))

	-- Reviver yang kena damage -> tahanannya dibatalkan.
	if Config.CancelReviveOnDamage then
		table.insert(conns, humanoid.HealthChanged:Connect(function()
			ReviveManager.cancelReviver(player)
		end))
	end

	charConns[character] = conns
end

local function cleanupCharacter(character: Model)
	local conns = charConns[character]
	if conns then
		for _, c in conns do
			c:Disconnect()
		end
		charConns[character] = nil
	end
	-- Respawn / mati: pastikan kondisi tumbang dilepas (tanpa membunuh lagi).
	DownedState.forget(character)
	ReviveManager.detach(character)
	CrawlController.restore(character, nil)
end

local function hookPlayer(player: Player)
	-- Laporkan Attribute override yang salah tipe SEKALI.
	for _, problem in Config.validateOverrides(player) do
		warn("[KnockSystem] " .. player.Name .. ": " .. problem)
	end

	player.CharacterAdded:Connect(function(character)
		hookCharacter(player, character)
	end)
	player.CharacterRemoving:Connect(function(character)
		cleanupCharacter(character)
	end)
	if player.Character then
		hookCharacter(player, player.Character)
	end
end

-----------------------------------------------------------------
-- START
-----------------------------------------------------------------
function KnockService.start()
	if started then
		return
	end
	started = true

	ReviveManager.setReviveCallback(onReviveComplete)

	-- Monster yang sudah ada + yang muncul kemudian.
	for _, monster in CollectionService:GetTagged(Config.MonsterTag) do
		hookMonster(monster)
	end
	CollectionService:GetInstanceAddedSignal(Config.MonsterTag):Connect(hookMonster)
	CollectionService:GetInstanceRemovedSignal(Config.MonsterTag):Connect(unhookMonster)

	-- Pemain.
	for _, player in Players:GetPlayers() do
		hookPlayer(player)
	end
	Players.PlayerAdded:Connect(hookPlayer)
	Players.PlayerRemoving:Connect(function(player)
		lastMonsterHit[player] = nil
	end)

	-- Ticker.
	bleedThread = task.spawn(function()
		while started do
			tickAll()
			task.wait(Config.BleedOutTick)
		end
	end)
end

--- Hentikan (khusus uji / teardown).
function KnockService.stop()
	started = false
	for monster in monsterConns do
		unhookMonster(monster)
	end
	for character in charConns do
		cleanupCharacter(character)
	end
	lastMonsterHit = {}
end

-- API tambahan untuk uji perilaku (tidak dipakai runtime normal).
KnockService._noteMonsterAttack = noteMonsterAttack
KnockService._wasHitByMonster = wasHitByMonster
KnockService._onReviveComplete = onReviveComplete
KnockService._bleedOutKill = bleedOutKill
KnockService._tickAll = tickAll

return KnockService
