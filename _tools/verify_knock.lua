--[[ verify_knock.lua — verifikasi AD-HOC integrasi Knock & Revive (jalankan via _tools/mcp.py).
     Bukan suite green CI; ini cek yang bisa diulang di EDIT MODE (tanpa playtest).

     SEJARAH: dulu harness ini menguji KnockSystem milik Aer
     (ReplicatedStorage.Modules.KnockSystem + KnockController + KnockUI + RevivePromptFilter).
     Sistem itu DIHAPUS 23 Sep 2026 karena kalah lomba set Health melawan ReviveManager
     milik Tim — lihat KNOCK_SYSTEM.md. Sekarang yang diuji adalah HAL YANG MASIH HIDUP:
       1. KnockSystem Aer benar-benar sudah bersih (tidak ada sisa instance).
       2. Sistem knock MILIK TIM masih utuh (ReviveManager + ReviveController).
       3. TargetFinder menghormati KEDUA Attribute tumbang (`Knocked` + `IsKnocked`).

     Cara pakai:
       cd _tools && python -c "import mcp,pathlib;print(mcp.luau(pathlib.Path('verify_knock.lua').read_text(encoding='utf-8'), instance_id='instance:93u-cgu'))"
]]
local out, pass, fail = {}, 0, 0
local function ck(n, c, e)
	if c then pass += 1; table.insert(out, "PASS " .. n)
	else fail += 1; table.insert(out, "FAIL " .. n .. (e and (" :: " .. tostring(e)) or "")) end
end
local function has(s, sub) return string.find(s, sub, 1, true) ~= nil end

local RS = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")
local SPS = game:GetService("StarterPlayer").StarterPlayerScripts

--- Cari instance berdasarkan nama di mana pun di bawah root (tahan perpindahan folder).
local function findByName(root, name)
	for _, d in ipairs(root:GetDescendants()) do
		if d.Name == name then return d end
	end
	return nil
end

-- ---------- 1. KnockSystem Aer sudah benar-benar dihapus ----------
ck("folder Modules.KnockSystem sudah hilang",
	RS:FindFirstChild("Modules") ~= nil and RS.Modules:FindFirstChild("KnockSystem") == nil)
ck("orchestrator KnockController sudah hilang",
	findByName(SSS, "KnockController") == nil)
ck("KnockUI sudah hilang", findByName(game.StarterPlayer, "KnockUI") == nil)
ck("RevivePromptFilter sudah hilang",
	findByName(game.StarterPlayer, "RevivePromptFilter") == nil)
ck("KnockService sudah hilang", findByName(RS, "KnockService") == nil)
ck("KnockHud sudah hilang", findByName(RS, "KnockHud") == nil)
ck("DownedState sudah hilang", findByName(RS, "DownedState") == nil)

-- ---------- 2. Sistem knock MILIK TIM masih utuh ----------
local reviveMgr = SSS:FindFirstChild("SilencioServer")
	and SSS.SilencioServer:FindFirstChild("ReviveManager")
ck("SSS.SilencioServer.ReviveManager ada", reviveMgr ~= nil)
ck("ReviveManager compile", reviveMgr ~= nil and loadstring(reviveMgr.Source) ~= nil)

local reviveCtrl = SPS:FindFirstChild("SilencioClient")
	and SPS.SilencioClient:FindFirstChild("ReviveController")
ck("SPS.SilencioClient.ReviveController ada", reviveCtrl ~= nil)
ck("ReviveController compile", reviveCtrl ~= nil and loadstring(reviveCtrl.Source) ~= nil)

if reviveMgr then
	local src = reviveMgr.Source
	-- Anti-death: set Health = 1 di handler HealthChanged -> ini yang mengalahkan sistem Aer.
	ck("ReviveManager set Health = 1 (anti-death)", has(src, "Health = 1"))
	ck("ReviveManager pakai Attribute IsKnocked", has(src, "IsKnocked"))
	ck("ReviveManager pakai Attribute IsDead", has(src, "IsDead"))
	ck("ReviveManager fire remote PlayerKnocked", has(src, "PlayerKnocked"))
	ck("ReviveManager fire remote PlayerRevived", has(src, "PlayerRevived"))
	ck("ReviveManager fire remote PlayerDiedPermanently", has(src, "PlayerDiedPermanently"))
	-- Self-revive lewat jalur TERPISAH (PromptSelfRevive + Developer Product), bukan
	-- lewat TeammateReviveComplete. Jadi prompt rekan tidak bisa dipakai reviver sendiri.
	ck("ReviveManager punya jalur self-revive terpisah (PromptSelfRevive)",
		has(src, "PromptSelfRevive"))
	ck("ReviveManager validasi jarak reviver<->korban",
		has(src, "Magnitude"))
	-- TIDAK bergantung pada AISignal (beda dari sistem Aer yang sudah dihapus).
	ck("ReviveManager TIDAK butuh AISignal", not has(src, "AISignal"))
end

if reviveCtrl then
	local src = reviveCtrl.Source
	ck("ReviveController pasang pose merangkak", has(src, "applyCrawlingPose"))
	ck("ReviveController daftar prompt revive rekan", has(src, "registerTeammateRevivePrompt"))
	ck("ReviveController pakai remote TeammateReviveComplete",
		has(src, "TeammateReviveComplete"))
end

-- ---------- 3. Konfigurasi TIM (Config.Revive) ----------
local cfgMod = RS:FindFirstChild("SilencioHoror") and RS.SilencioHoror:FindFirstChild("Config")
ck("RS.SilencioHoror.Config ada", cfgMod ~= nil)
if cfgMod then
	local ok, Config = pcall(require, cfgMod)
	ck("Config bisa di-require", ok, ok and nil or tostring(Config))
	if ok and type(Config) == "table" then
		local R = Config.Revive
		ck("Config.Revive ada", type(R) == "table")
		if type(R) == "table" then
			ck("BleedOutDuration = 45", R.BleedOutDuration == 45, "dapat " .. tostring(R.BleedOutDuration))
			ck("CrawlSpeed = 3.5", R.CrawlSpeed == 3.5, "dapat " .. tostring(R.CrawlSpeed))
			ck("RevivedHealth = 50", R.RevivedHealth == 50, "dapat " .. tostring(R.RevivedHealth))
			ck("TeammateReviveDuration = 10", R.TeammateReviveDuration == 10,
				"dapat " .. tostring(R.TeammateReviveDuration))
			ck("ReviveInteractDistance = 12", R.ReviveInteractDistance == 12,
				"dapat " .. tostring(R.ReviveInteractDistance))
		end
	end
end

-- ---------- 4. TargetFinder menghormati KEDUA Attribute tumbang ----------
local tf = RS:FindFirstChild("Modules") and RS.Modules:FindFirstChild("EnemyController")
	and RS.Modules.EnemyController:FindFirstChild("TargetFinder")
ck("TargetFinder ada", tf ~= nil)
if tf then
	local src = tf.Source
	ck("TargetFinder compile", loadstring(src) ~= nil)
	ck("TargetFinder baca Attribute \"Knocked\" (sistem Aer lama)", has(src, 'GetAttribute("Knocked")'))
	ck("TargetFinder baca Attribute \"IsKnocked\" (sistem TIM aktif)", has(src, 'GetAttribute("IsKnocked")'))
	local ok, TF = pcall(require, tf)
	ck("TargetFinder bisa di-require", ok, ok and nil or tostring(TF))
end

table.insert(out, string.format("=== AD-HOC edit-mode (bukan suite green): %d PASS / %d FAIL ===", pass, fail))
return table.concat(out, "\n")
