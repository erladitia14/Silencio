--[[ verify_build.lua — pemeriksa status place ASLI "BUILD Chapter 1" (placeId 99701743439969).
     Jalankan: cd _tools && python -c "import mcp,json,pathlib;print(json.loads(mcp.luau(pathlib.Path('verify_build.lua').read_text(encoding='utf-8'), instance_id='instance:925-6w7')).get('returnValue'))"

     KENAPA ADA: place BUILD adalah sumber kebenaran dan TIDAK boleh disentuh tanpa perintah Aer.
     Harness ini = daftar periksa "apa yang masih tertinggal di BUILD", supaya saat Aer minta
     menyusul, kita tahu persis selisihnya. Harness ini TIDAK menuntut BUILD sudah bersih —
     jadi kalau ada yang masih ada, itu PASS (status tercatat), bukan FAIL.

     ⚠️ SEJAK 23 Sep 2026, KnockSystem milik Aer DIHAPUS dari place Script (lihat KNOCK_SYSTEM.md).
     Di BUILD ia kemungkinan masih ada — dan itu memang kondisi yang ingin kita catat.
     Kalau nanti BUILD disusulkan (KnockSystem dibuang + TargetFinder baca IsKnocked),
     angka-angka di bawah akan berubah; perbarui ekspektasinya saat itu.
]]
local out, pass, fail = {}, 0, 0
local function ck(n, c, e)
	if c then pass += 1; table.insert(out, "PASS " .. n)
	else fail += 1; table.insert(out, "FAIL " .. n .. (e and (" :: " .. tostring(e)) or "")) end
end
local function has(s, sub) return string.find(s, sub, 1, true) ~= nil end

local RS  = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")
local SPS = game:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts")
local M   = RS:FindFirstChild("Modules")

table.insert(out, "PLACE placeId=" .. game.PlaceId .. " (" .. game.Name .. ")")

-- ---------- A. Status KnockSystem Aer di BUILD (dicatat, bukan dituntut) ----------
local ks = M and M:FindFirstChild("KnockSystem")
if ks then
	local MODS = {"Config","Signal","DownedState","CrawlController",
		"ReviveManager","KnockAnimator","KnockService","KnockHud"}
	local nOk = 0
	for _, n in ipairs(MODS) do
		local m = ks:FindFirstChild(n)
		if m and m:IsA("ModuleScript") and loadstring(m.Source) ~= nil then nOk += 1 end
	end
	table.insert(out, string.format(
		"STATUS KnockSystem MASIH ADA di BUILD (%d/%d modul compile) — belum disusulkan",
		nOk, #MODS))
	ck("KnockSystem di BUILD masih lengkap (kondisi lama, bukan kerusakan)", nOk == #MODS)
else
	table.insert(out, "STATUS KnockSystem SUDAH BERSIH di BUILD (sudah disusulkan)")
	ck("KnockSystem sudah tidak ada di BUILD", true)
end
for _, n in ipairs({"KnockController", "KnockUI", "RevivePromptFilter"}) do
	local where = (n == "KnockController") and SSS or SPS
	local found = where and where:FindFirstChild(n)
	table.insert(out, string.format("STATUS %s: %s", n,
		found and ("MASIH ADA (" .. found:GetFullName() .. ")") or "sudah bersih"))
	ck(n .. " status terbaca", true)
end

-- ---------- B. Sistem MILIK TIM harus utuh di BUILD ----------
local reviveMgr = SSS:FindFirstChild("SilencioServer")
	and SSS.SilencioServer:FindFirstChild("ReviveManager")
ck("SSS.SilencioServer.ReviveManager utuh", reviveMgr ~= nil)
ck("ReviveManager compile", reviveMgr ~= nil and loadstring(reviveMgr.Source) ~= nil)
local reviveCtrl = SPS and SPS:FindFirstChild("SilencioClient")
	and SPS.SilencioClient:FindFirstChild("ReviveController")
ck("SPS.SilencioClient.ReviveController utuh", reviveCtrl ~= nil)

-- ---------- C. TargetFinder: apakah sudah baca IsKnocked? ----------
local tf = M and M.EnemyController and M.EnemyController:FindFirstChild("TargetFinder")
ck("TargetFinder ada", tf ~= nil)
if tf then
	table.insert(out, string.format("BYTES TargetFinder=%d", #tf.Source))
	local bacaKnocked = has(tf.Source, 'GetAttribute("Knocked")')
	local bacaIsKnocked = has(tf.Source, 'GetAttribute("IsKnocked")')
	table.insert(out, string.format(
		"STATUS TargetFinder: Knocked=%s IsKnocked=%s",
		tostring(bacaKnocked), tostring(bacaIsKnocked)))
	ck("TargetFinder compile", loadstring(tf.Source) ~= nil)
	if not bacaIsKnocked then
		table.insert(out,
			"CATATAN: di BUILD monster MASIH mengejar pemain tumbang (belum baca IsKnocked). "
			.. "Ini sesuai kondisi saat ini — tunggu perintah Aer sebelum menyusulkan.")
	end
end

-- ---------- D. Modul & script LAIN tidak tersentuh ----------
for _, r in ipairs({
	{"KeySystem.DoorManager",      M and M.KeySystem and M.KeySystem.DoorManager},
	{"KeySystem.KeyPickupManager", M and M.KeySystem and M.KeySystem.KeyPickupManager},
	{"SafeZone.ZoneService",       M and M.SafeZone and M.SafeZone.ZoneService},
	{"SafeZone.Anchors",           M and M.SafeZone and M.SafeZone.Anchors},
	{"SafeZone.BreathBar",         M and M.SafeZone and M.SafeZone.BreathBar},
	{"BatteryPuzzle.Config",       M and M.BatteryPuzzle and M.BatteryPuzzle.Config},
	{"GeneratorSFX",               M and M.GeneratorSFX},
	{"TeleportData (tim)",         M and M.TeleportData},
	{"CustomPromptHelper (tim)",   M and M.CustomPromptHelper},
}) do
	ck(r[1] .. " masih ada", r[2] ~= nil and r[2]:IsA("ModuleScript"))
end
for _, n in ipairs({"EnemyController","KeySystemController","SafeZoneController",
	"AssemblyController","BatteryPuzzleController","GeneratorSFXController"}) do
	ck("SSS." .. n .. " utuh", SSS:FindFirstChild(n) ~= nil)
end
local Feat = SSS:FindFirstChild("Feature")
ck("SSS.Feature (tim) + TeleprotHandler utuh",
	Feat ~= nil and Feat:FindFirstChild("TeleprotHandler") ~= nil)
for _, n in ipairs({"SafeZoneUI","PuzzleInputClient","JumpscareHandler","SilencioClient"}) do
	ck("SPS." .. n .. " utuh", SPS and SPS:FindFirstChild(n) ~= nil)
end
-- "CustomPrompt Handler" dulu LocalScript terpisah; tim memindahkannya jadi ModuleScript
-- di dalam SilencioClient. Cek lokasi BARU, bukan menuntut lokasi lama.
local silencioClient = SPS and SPS:FindFirstChild("SilencioClient")
ck("SPS.SilencioClient.CustomPromptController utuh (pindahan tim)",
	silencioClient ~= nil and silencioClient:FindFirstChild("CustomPromptController") ~= nil)

table.insert(out, string.format("=== AD-HOC edit-mode (bukan suite green): %d PASS / %d FAIL ===", pass, fail))
return table.concat(out, "\n")
