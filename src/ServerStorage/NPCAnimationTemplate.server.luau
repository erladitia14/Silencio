--[[
	NPCAnimationTemplate
	--------------------
	TEMPLATE ANIMASI PER-NPC (untuk tim: KARIS x OnBlox)

	KAPAN SCRIPT INI DIPERLUKAN? BIASANYA TIDAK.

	  Secara default, cukup beri tag "Monster" pada Model NPC dan animasi
	  jalan/lari/idle SUDAH otomatis. Sistem membaca ID animasi dari dalam
	  Model itu sendiri, dengan urutan:
	    1. folder "Animations" di dalam Model   (untuk animasi custom)
	    2. paket "Animate" bawaan rig Roblox    (idle/walk/run/jump/fall)
	    3. ID default Roblox

	  Mau animasi serang / animasi khusus tanpa script? Cukup taruh
	  Animation object di folder "Animations" dalam Model, beri nama
	  "Attack" / "Idle" / "Walk" / "Run". Nama TIDAK case-sensitive.

	  Pakai script ini HANYA kalau NPC butuh logika animasi yang tidak bisa
	  diungkapkan lewat penamaan aset, misalnya: pilih animasi acak,
	  blending khusus, animasi bertahap sesuai HP, atau sinkron dengan SFX.

	CARA PAKAI:
	  1. Beri Attribute "NoAutoAnimations" = true (Bool) pada Model NPC,
	     supaya sistem TIDAK ikut menyetir Animator (hanya boleh satu penyetir,
	     dua penyetir pada Animator yang sama = animasi kejang).
	  2. Copy script ini KE DALAM Model NPC (jadi anak dari Model).
	  3. Ganti ID animasi di tabel ANIM_IDS sesuai animasi NPC kamu.
	  4. Selesai. JANGAN ubah EnemyController.

	KENAPA BISA BEGINI:
	  EnemyController (otak AI) tidak memaksakan animasi apa pun. Dia
	  MELAPORKAN apa yang sedang terjadi lewat dua kanal:

	    - Attribute "AIState" di Model  -> IDLE | PATROL | CHASING | ATTACKING | DEAD
	    - BindableEvent "AISignal"      -> "Attack", "TargetAcquired", "TargetLost", "Died"

	  Jadi kamu tinggal memutuskan: "kalau AI sedang CHASING, NPC-ku
	  mainkan animasi apa?" — tanpa menyentuh script AI-nya.
--]]

local model = script.Parent
local humanoid = model:WaitForChild("Humanoid")
local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator", humanoid)

---------------------------------------------------------------------
-- 1. ISI ID ANIMASI NPC INI (ganti sesuai animasi kamu)
---------------------------------------------------------------------
local ANIM_IDS = {
	Idle   = "rbxassetid://507766388",
	Walk   = "rbxassetid://913402848",
	Run    = "rbxassetid://913376220",
	Attack = "",  -- isi ID animasi serang NPC ini
	Death  = "",  -- opsional
}

-- Animasi mana yang dipakai untuk tiap state AI (atur bebas sesuai NPC)
local STATE_ANIM = {
	IDLE      = "Idle",
	PATROL    = "Walk",
	CHASING   = "Run",
	ATTACKING = "Idle",   -- animasi attack diputar via event, bukan state
	DEAD      = "Death",
}

---------------------------------------------------------------------
-- 2. LOAD TRACK (sekali saja, jangan LoadAnimation tiap frame)
---------------------------------------------------------------------
local tracks = {}
for name, id in pairs(ANIM_IDS) do
	if id ~= "" then
		local anim = Instance.new("Animation")
		anim.AnimationId = id
		local ok, track = pcall(function()
			return animator:LoadAnimation(anim)
		end)
		if ok and track then
			tracks[name] = track
		end
	end
end

local currentName = nil

local function playLoop(name: string?)
	if not name or currentName == name then return end
	local track = tracks[name]
	if not track then return end

	if currentName and tracks[currentName] then
		tracks[currentName]:Stop(0.2)
	end

	currentName = name
	track.Looped = true
	track:Play(0.2)
end

---------------------------------------------------------------------
-- 3. IKUTI STATE AI (keadaan: idle / patrol / chase / dead)
---------------------------------------------------------------------
local function applyState()
	local state = model:GetAttribute("AIState")
	if not state then return end
	playLoop(STATE_ANIM[state])
end

model:GetAttributeChangedSignal("AIState"):Connect(applyState)
applyState()  -- terapkan state awal kalau AI sudah jalan

---------------------------------------------------------------------
-- 4. DENGAR EVENT AI (kejadian sekejap: attack / mati / dsb)
---------------------------------------------------------------------
local signal = model:WaitForChild("AISignal", 10)
if signal then
	signal.Event:Connect(function(eventName, _arg)
		if eventName == "Attack" then
			local atk = tracks.Attack
			if atk then
				atk.Looped = false
				atk:Play(0.1)
			end

		elseif eventName == "Died" then
			for _, t in pairs(tracks) do
				t:Stop(0.1)
			end
			currentName = nil
			local death = tracks.Death
			if death then
				death.Looped = false
				death:Play(0.1)
			end

		-- "TargetAcquired" / "TargetLost" tersedia kalau NPC-mu butuh
		-- reaksi khusus (misal animasi kaget, atau SFX teriak).
		end
	end)
end
