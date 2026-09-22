--[[
	ReviveManager.luau
	------------------
	ProximityPrompt "Revive" di badan pemain yang tumbang + logika menahan
	tombol. Nol konfigurasi: prompt dibuat/dihapus otomatis mengikuti kondisi
	tumbang, tidak perlu tag manual.

	CATATAN UJI (dari SafeZone): ProximityPrompt.Triggered itu RBXScriptSignal,
	bukan BindableEvent -> tidak bisa :Fire() dari script. Untuk uji perilaku,
	panggil ReviveManager._testTrigger / logika progres langsung, jangan
	simulasikan penekanan prompt.

	Progres revive dihitung SERVER (PromptButtonHoldBegan/Ended), jadi
	server-authoritative. HoldDuration prompt hanya dipakai sebagai UI hint;
	kita memakai hold-began/ended manual supaya bisa membatalkan saat reviver
	kena damage / bergerak jauh / target sudah tidak tumbang.
--]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Config = require(script.Parent.Config)
local DownedState = require(script.Parent.DownedState)
local CrawlController = require(script.Parent.CrawlController)

local ReviveManager = {}

--- [character] = { prompt, holders = { [reviverPlayer] = startClock }, progress }
local prompts: { [Model]: any } = {}

-- Callback dipasang controller: revive(character), onReviveWarning dsb.
local onRevive: ((Model, Player) -> ())? = nil

function ReviveManager.setReviveCallback(fn: (Model, Player) -> ())
	onRevive = fn
end

-----------------------------------------------------------------
-- PROMPT LIFECYCLE
-----------------------------------------------------------------
--- Buat ProximityPrompt di badan pemain tumbang (idempotent).
function ReviveManager.attach(character: Model)
	if prompts[character] then
		return
	end
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "RevivePrompt"
	prompt.ActionText = Config.ReviveActionText
	prompt.ObjectText = Config.ReviveObjectText
	prompt.HoldDuration = Config.ReviveHoldTime
	prompt.MaxActivationDistance = Config.ReviveDistance
	prompt.RequiresLineOfSight = Config.ReviveRequiresLineOfSight
	prompt.KeyboardKeyCode = Config.ReviveKey
	prompt.Parent = root

	local rec = {
		prompt   = prompt,
		holders  = {},
		progress = 0,
		conns    = {},
	}
	prompts[character] = rec

	-- Server-authoritative hold: track began/ended per reviver.
	table.insert(rec.conns, prompt.PromptButtonHoldBegan:Connect(function(reviver)
		ReviveManager._beginHold(character, reviver)
	end))
	table.insert(rec.conns, prompt.PromptButtonHoldEnded:Connect(function(reviver)
		ReviveManager._endHold(character, reviver)
	end))
	-- HoldDuration selesai -> Triggered. Ini jalur normal (client menahan penuh).
	table.insert(rec.conns, prompt.Triggered:Connect(function(reviver)
		ReviveManager._complete(character, reviver)
	end))
end

--- Cabut prompt (revive selesai / mati / respawn).
function ReviveManager.detach(character: Model?)
	if not character then
		return
	end
	local rec = prompts[character]
	prompts[character] = nil
	if not rec then
		return
	end
	for _, c in rec.conns do
		c:Disconnect()
	end
	if rec.prompt and rec.prompt.Parent then
		rec.prompt:Destroy()
	end
end

-----------------------------------------------------------------
-- VALIDASI REVIVER
-----------------------------------------------------------------
--- Apakah reviver ini boleh menolong karakter tumbang?
function ReviveManager.canRevive(character: Model, reviver: Player?): boolean
	if not reviver then
		return false
	end
	if not DownedState.isDowned(character) then
		return false
	end
	-- Tidak bisa menolong diri sendiri.
	if reviver.Character == character then
		return false
	end
	-- Pemain yang sedang tumbang tidak boleh menolong.
	if Config.DownedCannotRevive and DownedState.isPlayerDowned(reviver) then
		return false
	end
	return true
end

--- Jarak reviver -> target (studs). math.huge kalau salah satu root hilang.
function ReviveManager._distance(character: Model, reviver: Player): number
	local downedRoot = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local reviverChar = reviver.Character
	local reviverRoot = reviverChar and reviverChar:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not downedRoot or not reviverRoot then
		return math.huge
	end
	return (downedRoot.Position - reviverRoot.Position).Magnitude
end

-----------------------------------------------------------------
-- HOLD LOGIC (server-authoritative)
-----------------------------------------------------------------
function ReviveManager._beginHold(character: Model, reviver: Player)
	local rec = prompts[character]
	if not rec then
		return
	end
	if not ReviveManager.canRevive(character, reviver) then
		return
	end
	rec.holders[reviver] = os.clock()
end

function ReviveManager._endHold(character: Model, reviver: Player)
	local rec = prompts[character]
	if not rec then
		return
	end
	rec.holders[reviver] = nil
end

--- Prompt selesai ditahan penuh (jalur Triggered). Verifikasi ulang di server.
function ReviveManager._complete(character: Model, reviver: Player)
	if not ReviveManager.canRevive(character, reviver) then
		return
	end
	if ReviveManager._distance(character, reviver) > Config.ReviveBreakDistance then
		return
	end
	if onRevive then
		onRevive(character, reviver)
	end
end

--- Dipanggil tiap ReviveTick oleh controller: hitung progres, batalkan yang
--- tidak valid, terbitkan progres ke Attribute untuk UI tim.
function ReviveManager.step(character: Model)
	local rec = prompts[character]
	if not rec then
		return
	end

	local holdTime = math.max(0.01, Config.get(
		Players:GetPlayerFromCharacter(character), "ReviveHoldTime"
	))

	local best = 0
	local toRemove = {}
	for reviver, startClock in rec.holders do
		-- Batalkan holder yang tidak lagi valid (mati/tumbang/jauh).
		if not ReviveManager.canRevive(character, reviver)
			or ReviveManager._distance(character, reviver) > Config.ReviveBreakDistance
		then
			table.insert(toRemove, reviver)
		else
			local held = os.clock() - startClock
			best = math.max(best, held / holdTime)
		end
	end
	for _, reviver in toRemove do
		rec.holders[reviver] = nil
	end

	rec.progress = math.clamp(best, 0, 1)
	character:SetAttribute(Config.ReviveProgressAttribute, rec.progress)

	-- Jalur cadangan: kalau ada holder yang sudah menahan penuh tapi event
	-- Triggered belum sempat terbit (jarang), selesaikan di sini.
	if rec.progress >= 1 then
		for reviver in rec.holders do
			ReviveManager._complete(character, reviver)
			break
		end
	end
end

--- Batalkan tahanan seorang reviver dari luar (mis. reviver kena damage).
function ReviveManager.cancelReviver(reviver: Player)
	for _, rec in prompts do
		rec.holders[reviver] = nil
	end
end

function ReviveManager.getProgress(character: Model?): number
	if not character then
		return 0
	end
	local rec = prompts[character]
	return rec and rec.progress or 0
end

--- Khusus uji: memicu penyelesaian revive tanpa ProximityPrompt asli.
function ReviveManager._testComplete(character: Model, reviver: Player)
	ReviveManager._complete(character, reviver)
end

function ReviveManager.reset()
	for character in prompts do
		ReviveManager.detach(character)
	end
	prompts = {}
	onRevive = nil
end

return ReviveManager
