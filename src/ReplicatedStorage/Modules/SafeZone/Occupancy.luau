--[[
	Occupancy.luau
	--------------
	Memindahkan karakter pemain MASUK ke bilik dan MENGELUARKANNYA.
	Semua ini urusan server (posisi karakter itu server-authoritative).

	Yang dikerjakan saat masuk:
	  1. Simpan CFrame & WalkSpeed/JumpPower asli
	  2. Pindahkan karakter ke titik `hide`
	  3. Kunci di tempat (Anchored, plus WalkSpeed/JumpPower 0)
	  4. Matikan collision karakter terhadap monster? TIDAK — dinding bilik
	     yang mengurus itu (Barrier). Di sini kita tidak menyentuh
	     CollisionGroup supaya tidak bentrok dengan sistem lain.

	Saat keluar: kebalikannya, lalu lempar ke titik `exit`.

	CATATAN PENTING soal Anchored: meng-anchor HumanoidRootPart menghentikan
	SEMUA physics karakter — ini sengaja. Tanpa itu, monster raksasa yang
	menempel di pintu masih bisa mendorong pemain keluar lewat celah.
	Yang di-anchor hanya root; part lain dibiarkan supaya animasi tetap jalan.
--]]

local Config  = require(script.Parent.Config)
local Anchors = require(script.Parent.Anchors)

local Occupancy = {}

type Saved = {
	walkSpeed: number,
	jumpPower: number,
	jumpHeight: number,
	autoRotate: boolean,
	anchored: boolean,
}

-- player -> keadaan asli sebelum masuk
local saved: { [any]: Saved } = {}

---------------------------------------------------------------------
-- HELPER
---------------------------------------------------------------------

local function rootOf(character: Model?): BasePart?
	if not character then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return character.PrimaryPart
end

local function humanoidOf(character: Model?): Humanoid?
	return character and character:FindFirstChildOfClass("Humanoid") or nil
end

---------------------------------------------------------------------
-- MASUK / KELUAR
---------------------------------------------------------------------

--- Sembunyikan pemain di dalam bilik.
--- @return boolean, string?  berhasil, alasan gagal
function Occupancy.enter(player: any, character: Model, zonePart: BasePart): (boolean, string?)
	local root = rootOf(character)
	local humanoid = humanoidOf(character)

	if not root then
		return false, "NO_ROOT"
	end
	if humanoid and humanoid.Health <= 0 then
		return false, "DEAD"
	end
	if saved[player] then
		return false, "ALREADY_HIDDEN"
	end

	saved[player] = {
		walkSpeed  = humanoid and humanoid.WalkSpeed or 16,
		jumpPower  = humanoid and humanoid.JumpPower or 50,
		jumpHeight = humanoid and humanoid.JumpHeight or 7.2,
		autoRotate = humanoid and humanoid.AutoRotate or true,
		anchored   = root.Anchored,
	}

	-- Pindahkan dulu, kunci sesudahnya: kalau di-anchor lebih dulu,
	-- PivotTo/CFrame tetap jalan tapi karakter bisa tersangkut geometri
	-- lama untuk satu frame.
	local target = Anchors.hide(zonePart)
	character:PivotTo(target)

	if humanoid then
		-- Hentikan pergerakan aktif agar script Animate tahu karakter berhenti
		pcall(function()
			humanoid:Move(Vector3.zero)
		end)

		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0
		humanoid.JumpHeight = 0
		humanoid.AutoRotate = false

		-- Hentikan semua animasi lari/jalan yang sedang nyangkut (bug playtest Aer)
		local animator = humanoid:FindFirstChildOfClass("Animator")
		if animator then
			for _, track in animator:GetPlayingAnimationTracks() do
				local name = track.Name:lower()
				local anim = track.Animation
				local animName = anim and anim.Name:lower() or ""
				-- Hentikan animasi gerakan (run, walk, sprint, jump, fall)
				if name:find("run") or name:find("walk") or name:find("sprint")
					or animName:find("run") or animName:find("walk")
					or track.Priority == Enum.AnimationPriority.Movement then
					track:Stop(0.15)
				end
			end
		end
	end
	if Config.HideAnchor then
		root.Anchored = true
	end

	return true
end

--- Keluarkan pemain dari bilik dan pulihkan kendali.
--- @param zonePart  bilik asal (untuk menghitung titik keluar); boleh nil
---                  kalau bilik sudah hilang — pemain dilepas di tempat.
function Occupancy.exit(player: any, character: Model?, zonePart: BasePart?)
	local state = saved[player]
	saved[player] = nil

	local root = rootOf(character)
	local humanoid = humanoidOf(character)

	-- Lepas kunci LEBIH DULU, baru pindahkan: memindahkan part yang masih
	-- Anchored membuat karakter melayang tanpa gravitasi sampai frame
	-- berikutnya.
	if root then
		root.Anchored = state and state.anchored or false
	end
	if humanoid and state then
		humanoid.WalkSpeed  = state.walkSpeed
		humanoid.JumpPower  = state.jumpPower
		humanoid.JumpHeight = state.jumpHeight
		humanoid.AutoRotate = state.autoRotate
	end

	if character and zonePart and zonePart.Parent then
		character:PivotTo(Anchors.exit(zonePart))
	end
end

--- Apakah pemain ini sedang dalam keadaan "disembunyikan" oleh modul ini.
function Occupancy.isHidden(player: any): boolean
	return saved[player] ~= nil
end

--- Lupakan catatan seorang pemain. Dipakai saat pemain mati / keluar
--- server: memulihkan WalkSpeed pada karakter yang akan diganti Roblox
--- tidak ada guna.
---
--- TAPI kunci fisiknya TETAP dilepas kalau karakternya masih ada. Kalau
--- tidak: `Anchored = true` tertinggal di karakter, lalu `enter()`
--- berikutnya MENYIMPAN true itu sebagai "keadaan asli" — dan pemain
--- terkunci permanen setelah keluar bilik. Terukur di uji perilaku:
--- mati saat sembunyi -> masuk lagi -> keluar -> masih Anchored.
--- @param character  karakter yang masih hidup, kalau ada
function Occupancy.forget(player: any, character: Model?)
	local state = saved[player]
	saved[player] = nil

	if not state or not character then
		return
	end

	local root = rootOf(character)
	if root then
		root.Anchored = state.anchored
	end
end

--- KHUSUS UJI: kosongkan seluruh catatan.
function Occupancy._reset()
	saved = {}
end

return Occupancy
