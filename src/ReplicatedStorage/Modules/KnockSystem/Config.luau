--[[
	Config.luau  (KnockSystem)
	--------------------------
	Konfigurasi terpusat sistem KNOCK & REVIVE (co-op downed state).

	KONSEP:
	  Saat Health pemain habis karena SERANGAN MONSTER, ia TIDAK langsung
	  mati. Ia "knocked" (tumbang): bisa merangkak pelan, tidak bisa lompat,
	  dan monster mengabaikannya (klaim dilepas -> cari korban lain). Teman
	  harus menahan tombol E untuk membangunkan. Kalau tidak ada yang menolong
	  sampai timer bleed-out habis, barulah ia mati beneran (respawn normal).

	CARA KERJA ANTI-MATI (TERBUKTI EMPIRIS di runtime Studio, bukan tebakan):
	  State DEAD Humanoid dimatikan (SetStateEnabled(Dead, false)) SEBELUM
	  Health menyentuh 0. Hasil uji runtime nyata:
	    - SetStateEnabled(Dead,false) + TakeDamage(500)
	        -> Health -400, Died TIDAK terbit, state tetap Running
	    - Health dipaksa 0 -> tetap hidup
	    - Health dinaikkan lagi -> pulih normal (revive)
	    - state Dead dikembalikan true + Health 0 -> Died terbit normal
	  Jadi pemain bisa ditahan di 0 HP tanpa ragdoll, dan tetap bisa mati
	  beneran saat memang diinginkan.

	SISTEM INI BERDIRI SENDIRI. Ia tidak mengubah EnemyController/KeySystem/
	SafeZone/BatteryPuzzle. Satu-satunya titik sentuh ke core AI: atribut
	"Knocked" dibaca TargetFinder supaya monster melepas korban yang tumbang.

	SEMUA nilai di bawah bisa di-override PER PEMAIN lewat Attribute pada
	objek Player (nama Attribute = nama field di sini).
--]]

local Config = {}

-----------------------------------------------------------------
-- PENANDA DI KARAKTER (replikasi otomatis -> dibaca UI/SFX tim)
-----------------------------------------------------------------
Config.DownedAttribute         = "Knocked"              -- Bool   : sedang tumbang
Config.BleedOutAttribute       = "KnockBleedOut"        -- Number : sisa bleed-out (detik)
Config.ReviveProgressAttribute = "KnockReviveProgress"  -- Number : progres revive 0..1

-----------------------------------------------------------------
-- KAPAN TUMBANG (bukan mati)
-----------------------------------------------------------------
-- true  = HANYA serangan monster yang bikin tumbang. Mati karena jatuh /
--         kehabisan oksigen / sebab lain tetap mati biasa. (Sesuai spec Aer.)
-- false = SEMUA damage lethal bikin tumbang.
Config.KnockOnlyFromMonster = true

-- Jeda kecil sebelum memutuskan tumbang/mati. Monster menerbitkan sinyal
-- "Attack" TEPAT SETELAH damage diterapkan, jadi tanpa jeda ini keputusan
-- diambil sebelum sinyalnya sempat tercatat.
Config.KnockDecisionDelay = 0.2

-- Berapa lama cap "baru dipukul monster" masih dianggap berlaku (detik).
Config.MonsterHitWindow = 2.0

-----------------------------------------------------------------
-- BLEED-OUT (jam pasir menuju mati beneran)
-----------------------------------------------------------------
Config.BleedOutTime        = 30  -- detik sampai mati beneran bila tak ditolong
Config.BleedOutWarningTime = 10  -- sisa waktu <= ini -> sinyal "Warning" ke tim

-----------------------------------------------------------------
-- MERANGKAK (perilaku saat tumbang)
-----------------------------------------------------------------
Config.CrawlSpeed  = 6     -- WalkSpeed saat merangkak (pemain normal 16)
Config.DisableJump = true  -- lompat dimatikan selama tumbang
Config.DropTools   = true  -- Tool yang sedang di-equip dilepas saat tumbang

-- Pemain tumbang tidak bisa mati oleh damage lanjutan (state DEAD sudah mati,
-- jadi Health negatif pun tidak mematikan). Ini hanya penjaga tampilan.
Config.ClampHealthWhileDowned = true

-----------------------------------------------------------------
-- REVIVE (tolong oleh teman)
-----------------------------------------------------------------
Config.ReviveHoldTime = 5    -- detik menahan tombol
Config.ReviveHealth   = 50   -- Health setelah dibangunkan
Config.ReviveDistance = 9    -- MaxActivationDistance ProximityPrompt (studs)
Config.ReviveActionText = "Revive"
Config.ReviveObjectText = "" -- kosong = tidak menampilkan nama objek
Config.ReviveKey = Enum.KeyCode.E
-- Badan pemain yang tumbang sering menghalangi raycast prompt -> default false.
Config.ReviveRequiresLineOfSight = false

-- Reviver yang kena damage saat menolong -> tahanan dibatalkan.
Config.CancelReviveOnDamage = true

-- Pemain yang sedang tumbang TIDAK boleh menolong pemain tumbang lain.
Config.DownedCannotRevive = true

-- Berapa jauh reviver boleh bergeser sebelum tahanan dibatalkan (studs di
-- atas ReviveDistance). Mencegah "tolong dari jauh" saat prompt tersangkut.
Config.ReviveBreakDistance = Config.ReviveDistance + 4

-----------------------------------------------------------------
-- ANIMASI POSE TUMBANG (SEMENTARA pakai aset bawaan Roblox)
-----------------------------------------------------------------
-- Roblox TIDAK punya animasi "crawl" bawaan. Daftar resmi default R15:
-- idle/walk/run/jump/fall/climb/sit/tool/emote. Yang paling mendekati pose
-- tumbang = SitV2 (asset 2506281703, milik Roblox — terverifikasi lewat
-- MarketplaceService:GetProductInfo).
--
-- GANTI dengan animasi beneran nanti: isi KnockAnimId dengan ID animasi lo.
-- Isi "" -> tidak ada animasi (mekanis tetap jalan, tidak error).
Config.KnockAnimId = "rbxassetid://2506281703"  -- SitV2 (sementara)
Config.PlayKnockAnimation = true

-----------------------------------------------------------------
-- KANAL SINYAL (untuk SFX/UI tim — sistem ini tidak memaksa UI apa pun)
-----------------------------------------------------------------
-- BindableEvent di ReplicatedStorage, dibuat otomatis (idempotent):
--   Fire("Downed",   player)
--   Fire("Revived",  player, reviverPlayer)
--   Fire("BleedOut", player)
--   Fire("Warning",  player, secondsLeft)
Config.SignalName = "KnockSignal"
Config.SignalEvent = {
	DOWNED    = "Downed",
	REVIVED   = "Revived",
	BLEED_OUT = "BleedOut",
	WARNING   = "Warning",
}

-----------------------------------------------------------------
-- DETEKSI MONSTER
-----------------------------------------------------------------
-- Tag monster (sama dengan EnemyController) + nama BindableEvent sinyal AI
-- yang sudah diterbitkan EnemyController. Dipakai untuk tahu bahwa pemain
-- baru saja dipukul monster (lihat KnockOnlyFromMonster).
Config.MonsterTag     = "Monster"
Config.MonsterSignal  = "AISignal"
Config.MonsterAttackEvent = "Attack"
Config.MonsterSignalTimeout = 10 -- detik menunggu AISignal muncul di Model

-----------------------------------------------------------------
-- DETAK INTERNAL
-----------------------------------------------------------------
Config.BleedOutTick  = 0.2  -- interval pengurangan bleed-out (detik)
Config.CrawlTick     = 0.25 -- interval penjaga kecepatan merangkak (detik)
Config.ReviveTick    = 0.1  -- interval pembaruan progres revive (detik)

-----------------------------------------------------------------
-- OVERRIDE PER PEMAIN (Attribute pada objek Player)
-----------------------------------------------------------------
Config.NumberOverrides = {
	BleedOutTime   = true,
	ReviveHoldTime = true,
	ReviveHealth   = true,
	CrawlSpeed     = true,
}

Config.BoolOverrides = {
	DisableJump             = true,
	ClampHealthWhileDowned  = true,
}

--- Resolver: Attribute Player menang, kalau kosong pakai default global.
--- Silent (dipanggil tiap tick); laporan salah tipe ada di validateOverrides.
function Config.get(player: Player?, key: string)
	local default = Config[key]
	if not player then
		return default
	end
	local attr = player:GetAttribute(key)
	if attr == nil then
		return default
	end
	if typeof(attr) ~= typeof(default) then
		return default
	end
	return attr
end

--- Laporkan Attribute pemain yang salah tipe/negatif SEKALI saat pemain masuk.
--- Prinsip project ini: satu salah ketik tidak boleh menjatuhkan seluruh sistem.
function Config.validateOverrides(player: Player): { string }
	local problems = {}

	for key in Config.NumberOverrides do
		local attr = player:GetAttribute(key)
		if attr ~= nil then
			if typeof(attr) ~= "number" then
				table.insert(problems, key .. " harus number (dapat " .. typeof(attr) .. ") -> diabaikan")
			elseif attr < 0 then
				table.insert(problems, key .. " tidak boleh negatif -> diabaikan")
			end
		end
	end

	for key in Config.BoolOverrides do
		local attr = player:GetAttribute(key)
		if attr ~= nil and typeof(attr) ~= "boolean" then
			table.insert(problems, key .. " harus boolean (dapat " .. typeof(attr) .. ") -> diabaikan")
		end
	end

	return problems
end

return Config
