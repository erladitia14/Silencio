--[[
	KnockAnimator.luau
	------------------
	Memainkan animasi POSE TUMBANG saat pemain knocked, dan menghentikannya
	saat revive / mati.

	STATUS: animasi SEMENTARA pakai aset bawaan Roblox (permintaan Aer).
	Roblox TIDAK punya animasi "crawl" bawaan — daftar resmi default R15 cuma
	idle/walk/run/jump/fall/climb/sit/tool/emote. Yang paling mendekati pose
	tumbang = `SitV2` (asset 2506281703, milik Roblox, sudah diverifikasi lewat
	MarketplaceService:GetProductInfo -> Name="SitV2", Creator=Roblox).

	CARA GANTI dengan animasi beneran nanti:
	  Config.KnockAnimId = "rbxassetid://<ID_ANIMASI_LO>"
	Nol perubahan kode lain. Kalau diisi "" -> tidak ada animasi (mekanis tetap
	jalan, tidak error).

	Pola sama dengan BatteryPuzzle/CarryAnimator: track per pemain di-cache,
	aman dipanggil berkali-kali. Diputar dari SERVER supaya otomatis
	terepilkasi ke semua client (server-authoritative).
--]]

local Config = require(script.Parent.Config)

local KnockAnimator = {}

local tracks: { [Player]: AnimationTrack } = {}

local PRIORITY = Enum.AnimationPriority.Action4
local FADE = 0.2

local function getAnimator(player: Player): Animator?
	local char = player.Character
	if not char then
		return nil
	end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum then
		return nil
	end
	local animator = hum:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = hum
	end
	return animator
end

local function normalizeId(id: string): string
	if id == "" then
		return ""
	end
	if not string.find(id, "://") then
		return "rbxassetid://" .. id
	end
	return id
end

--- Mainkan pose tumbang. `animId` opsional (default Config.KnockAnimId).
function KnockAnimator.play(player: Player, animId: string?)
	local id = normalizeId(animId or Config.KnockAnimId)
	if id == "" then
		return
	end

	KnockAnimator.stop(player)

	local animator = getAnimator(player)
	if not animator then
		return
	end

	local anim = Instance.new("Animation")
	anim.AnimationId = id

	local ok, track = pcall(function()
		return animator:LoadAnimation(anim)
	end)
	if not ok or not track then
		warn("[KnockSystem] gagal memuat animasi tumbang '" .. id .. "': " .. tostring(track))
		return
	end

	track.Priority = PRIORITY
	track.Looped = true
	track:Play(FADE)
	tracks[player] = track
end

--- Hentikan pose tumbang (revive / mati / respawn).
function KnockAnimator.stop(player: Player)
	local track = tracks[player]
	if track then
		pcall(function()
			track:Stop(FADE)
		end)
		tracks[player] = nil
	end
end

--- Bersihkan total (pemain keluar / respawn).
function KnockAnimator.cleanup(player: Player)
	KnockAnimator.stop(player)
	tracks[player] = nil
end

--- Khusus uji: apakah pemain ini sedang punya track pose tumbang?
function KnockAnimator.isPlaying(player: Player?): boolean
	if not player then
		return false
	end
	return tracks[player] ~= nil
end

function KnockAnimator.reset()
	tracks = {}
end

return KnockAnimator
