--[[
	TargetClaims.luau
	-----------------
	Registry "SATU MONSTER = SATU KORBAN".

	Masalah yang dipecahkan: begitu ada beberapa monster, semuanya memakai
	logika yang sama (kejar yang terdekat) sehingga SEMUA monster menumpuk
	di satu player. Modul ini jadi papan klaim bersama: monster yang sudah
	mengunci seorang player "memiliki" player itu, dan monster lain akan
	melewatinya saat mencari target.

	Cara pakai (dari sisi core AI):
	  - saat lock target  -> TargetClaims:claim(model, player, mode)
	  - saat lepas target -> TargetClaims:releaseMonster(model)
	  - saat mencari target -> TargetClaims:canTake(model, player, dist, isPriority)
	  - tiap tick saat mengejar -> TargetClaims:holds(model, player)
	      false = klaim direbut monster lain -> cari korban lain.

	ATURAN PEREBUTAN (steal):
	  - PERSISTENT  : klaimnya kunci mati. Tidak bisa direbut siapa pun.
	  - ITEM_HOLDER : pemburu mode ini boleh MENYAMBAR pembawa bait dari
	                  monster non-ITEM_HOLDER tanpa syarat jarak (prioritas
	                  item mutlak, konsisten dengan evaluateRetarget).
	  - sisanya     : boleh merebut hanya bila SIGNIFIKAN lebih dekat
	                  (Config.RetargetHysteresis / RetargetMinGap), dan hanya
	                  bila Config.AllowClaimSteal = true.

	OPT-OUT per NPC: Attribute "ShareTarget" = true pada Model monster.
	  Monster itu jadi "bebas": tidak mencatat klaim dan tidak menghormati
	  klaim orang lain. Cocok untuk bos yang harus selalu mengejar.
	  Matikan sistem global lewat Config.ExclusiveTargets = false.

	CATATAN STATE: tabel klaim ini hidup di VM tempat modul di-require.
	Semua monster diorkestrasi satu Script server, jadi satu tabel bersama.
	Modul ini TIDAK di-require client mana pun.

	Kunci tabel sengaja tidak ditipe-paksa `Player` supaya uji perilaku
	statis bisa memakai tabel palsu {Parent=..., Character=...} tanpa player
	nyata (Studio edit mode tidak punya player).
--]]

local Config = require(script.Parent.Config)

local TargetClaims = {}

type Claim = {
	monster: Model,
	mode:    string,
	since:   number,
}

-- Dua arah supaya lepas-klaim O(1) dari sisi mana pun.
local byPlayer:  { [any]: Claim }  = {}
local byMonster: { [Model]: any }  = {}

---------------------------------------------------------------------
-- HELPER LOKAL
---------------------------------------------------------------------

--- Ambil part acuan posisi sebuah Model (rig monster atau character player).
local function rootOf(model: Instance?): BasePart?
	if not model then
		return nil
	end
	local root = model:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root :: BasePart
	end
	if model:IsA("Model") then
		return model.PrimaryPart
	end
	return nil
end

--- Jarak monster -> character player. math.huge bila salah satu tak berposisi.
--- Dihitung lokal (bukan lewat TargetFinder) untuk menghindari require sirkular.
local function distance(monster: Model?, player: any): number
	local a = rootOf(monster)
	local b = rootOf(player and player.Character)
	if not a or not b then
		return math.huge
	end
	return (a.Position - b.Position).Magnitude
end

--- Monster masih layak memegang klaim? (belum dihancurkan & belum mati)
local function monsterAlive(model: Model?): boolean
	if not model or not model.Parent then
		return false
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health <= 0 then
		return false
	end
	return true
end

--- Player masih ada di server?
local function playerPresent(player: any): boolean
	return player ~= nil and player.Parent ~= nil
end

--- Hapus klaim atas seorang player (internal, tanpa validasi).
local function drop(player: any)
	local rec = byPlayer[player]
	if not rec then
		return
	end
	byPlayer[player] = nil
	if byMonster[rec.monster] == player then
		byMonster[rec.monster] = nil
	end
end

---------------------------------------------------------------------
-- API
---------------------------------------------------------------------

--- Monster ini dikecualikan dari sistem klaim?
--- true = bebas mengejar siapa saja & tidak memblokir monster lain.
function TargetClaims:isExempt(monsterModel: Model?): boolean
	if not Config.ExclusiveTargets then
		return true
	end
	return monsterModel ~= nil and monsterModel:GetAttribute("ShareTarget") == true
end

--- Monster mana yang sedang memegang player ini? (nil = bebas)
--- Klaim basi (monster hancur/mati, player keluar) dibersihkan di sini.
function TargetClaims:owner(player: any): Model?
	local rec = byPlayer[player]
	if not rec then
		return nil
	end
	if not playerPresent(player) or not monsterAlive(rec.monster) then
		drop(player)
		return nil
	end
	return rec.monster
end

--- Player yang sedang dipegang monster ini (nil = tidak memegang siapa pun).
function TargetClaims:heldBy(monsterModel: Model): any
	local player = byMonster[monsterModel]
	if player == nil then
		return nil
	end
	if not playerPresent(player) then
		drop(player)
		return nil
	end
	return player
end

--- Apakah monster ini masih pemegang klaim atas player tersebut?
--- Dipakai tiap tick saat mengejar: false = klaim direbut -> cari korban lain.
function TargetClaims:holds(monsterModel: Model, player: any): boolean
	if player == nil then
		return true          -- tidak punya target = tidak ada yang bisa hilang
	end
	if self:isExempt(monsterModel) then
		return true          -- monster bebas tidak pernah "kehilangan klaim"
	end
	local rec = byPlayer[player]
	return rec ~= nil and rec.monster == monsterModel
end

--- Boleh kah monster ini mengambil player tersebut sebagai target?
--- @param myDist      jarak monster -> player (dihitung ulang bila nil)
--- @param isPriority  kandidat ini pembawa item bait & pemburu mode ITEM_HOLDER
function TargetClaims:canTake(monsterModel: Model, player: any, myDist: number?, isPriority: boolean?): boolean
	if self:isExempt(monsterModel) then
		return true
	end
	if player == nil then
		return false
	end

	local rec = byPlayer[player]
	if not rec then
		return true          -- belum ada yang klaim
	end
	if rec.monster == monsterModel then
		return true          -- klaim milik sendiri
	end
	if not monsterAlive(rec.monster) then
		drop(player)         -- pemegang lama sudah hancur/mati
		return true
	end

	-- PERSISTENT: kunci mati, tidak bisa direbut siapa pun.
	if rec.mode == "PERSISTENT" then
		return false
	end

	-- Prioritas item mutlak: sambar pembawa bait dari monster non-ITEM_HOLDER.
	if isPriority and rec.mode ~= "ITEM_HOLDER" then
		return true
	end

	if not Config.AllowClaimSteal then
		return false
	end

	-- Rebut hanya bila SIGNIFIKAN lebih dekat (anti tarik-menarik target).
	local incumbentDist = distance(rec.monster, player)
	if incumbentDist == math.huge then
		return true
	end
	local dist = myDist or distance(monsterModel, player)

	return dist <= incumbentDist * (1 - Config.RetargetHysteresis)
		or dist <= (incumbentDist - Config.RetargetMinGap)
end

--- Catat klaim monster atas seorang player.
--- Klaim lama monster ini dilepas otomatis (kasus retarget), dan klaim
--- monster lain atas player ini diambil alih (pemanggil sudah lolos canTake).
function TargetClaims:claim(monsterModel: Model, player: any, mode: string?): boolean
	local previous = byMonster[monsterModel]

	if self:isExempt(monsterModel) then
		-- Monster bebas: tidak mencatat apa pun, tapi tetap bersihkan sisa
		-- klaim lama (mis. Attribute ShareTarget baru dinyalakan saat runtime).
		if previous ~= nil then
			drop(previous)
		end
		return true
	end

	if player == nil then
		return false
	end

	if previous ~= nil and previous ~= player then
		drop(previous)
	end
	drop(player)

	byPlayer[player] = {
		monster = monsterModel,
		mode    = mode or Config.ChaseMode,
		since   = tick(),
	}
	byMonster[monsterModel] = player
	return true
end

--- Lepas klaim yang dipegang monster ini (dipanggil saat kehilangan target/mati).
function TargetClaims:releaseMonster(monsterModel: Model): boolean
	local player = byMonster[monsterModel]
	if player == nil then
		return false
	end
	drop(player)
	byMonster[monsterModel] = nil
	return true
end

--- Lepas klaim atas seorang player (dipanggil saat player keluar server).
function TargetClaims:releasePlayer(player: any): boolean
	if byPlayer[player] == nil then
		return false
	end
	drop(player)
	return true
end

--- Bersihkan klaim basi. Dipanggil berkala oleh orchestrator sebagai jaring
--- pengaman; jalur normal sudah melepas klaim sendiri.
function TargetClaims:prune(): number
	local removed = 0
	for player, rec in pairs(byPlayer) do
		if not playerPresent(player) or not monsterAlive(rec.monster) then
			drop(player)
			removed += 1
		end
	end
	return removed
end

--- Jumlah klaim aktif.
function TargetClaims:count(): number
	local n = 0
	for _ in pairs(byPlayer) do
		n += 1
	end
	return n
end

--- Potret isi registry (debug / verifikasi): { {player=, monster=, mode=, since=} }
function TargetClaims:snapshot(): { any }
	local out = {}
	for player, rec in pairs(byPlayer) do
		table.insert(out, {
			player  = player,
			monster = rec.monster,
			mode    = rec.mode,
			since   = rec.since,
		})
	end
	return out
end

--- Kosongkan seluruh registry (dipakai uji perilaku; jangan dipakai runtime).
function TargetClaims:reset()
	byPlayer = {}
	byMonster = {}
end

return TargetClaims
