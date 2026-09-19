--!strict
--[[
	CarryAnimator — memainkan animasi "pose angkat 2 tangan" HANYA saat membawa PANEL.

	Baterai (kecil) & Engine TIDAK pakai animasi ini — cukup weld ke tangan.
	Dipakai AssemblyService (bukan BatteryService).

	Cara kerja:
	- play(player): load + mainkan Config.PanelCarryAnimId (priority Action ->
	  numpuk di atas walk, hanya tulang lengan yang di-key sehingga kaki tetap
	  jalan dari walk engine).
	- stop(player): hentikan animasi saat panel ditaruh / dipasang / mati.

	Aman dipanggil berkali-kali; track per pemain di-cache.
]]

local Config = require(script.Parent.Config)

local CarryAnimator = {}

local tracks: { [Player]: AnimationTrack } = {}

local function getAnimator(player: Player): Animator?
	local char = player.Character
	if not char then return nil end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum then return nil end
	-- Animator ada di dalam Humanoid (server & client sama-sama bisa load di sini)
	local animator = hum:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = hum
	end
	return animator
end

function CarryAnimator.play(player: Player)
	local animId = Config.PanelCarryAnimId
	if not animId or animId == "" then
		return
	end

	local animator = getAnimator(player)
	if not animator then return end

	-- kalau track lama masih ada (respawn), buang dulu
	if tracks[player] then
		tracks[player]:Stop(0.1)
		tracks[player] = nil
	end

	local anim = Instance.new("Animation")
	anim.AnimationId = animId

	local ok, track = pcall(function()
		return animator:LoadAnimation(anim)
	end)
	if not ok or not track then
		return
	end

	track.Priority = Enum.AnimationPriority.Action
	track.Looped = true
	track:Play(0.15)
	tracks[player] = track
end

function CarryAnimator.stop(player: Player)
	local track = tracks[player]
	if track then
		track:Stop(0.15)
		tracks[player] = nil
	end
end

function CarryAnimator.cleanup(player: Player)
	CarryAnimator.stop(player)
	tracks[player] = nil
end

return CarryAnimator
