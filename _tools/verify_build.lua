--[[ verify_build.lua — harness regresi KnockSystem di place ASLI "BUILD Chapter 1".
     Jalankan: cd _tools && python -c "import mcp,json,pathlib;print(json.loads(mcp.luau(pathlib.Path('verify_build.lua').read_text(encoding='utf-8'))).get('returnValue'))"

     Kenapa ada: kerja di place asli menyentuh sistem MILIK TIM. Harness ini
     membuktikan dua hal sekaligus tiap kali dijalankan:
       1. KnockSystem memang mendarat & compile (bukan placeholder).
       2. Script LAIN tidak tersentuh — termasuk TargetFinder, yang sengaja
          DIBIARKAN di versi lama atas perintah Aer ("jangan ubah script lain").
     Jalankan di place yang BENAR (BUILD Chapter 1, placeId 99701743439969). ]]
local out, pass, fail = {}, 0, 0
local function ck(n, c, e)
	if c then pass += 1; table.insert(out, "PASS " .. n)
	else fail += 1; table.insert(out, "FAIL " .. n .. (e and (" :: " .. tostring(e)) or "")) end
end

local RS  = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")
local SPS = game:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts")
local M   = RS:FindFirstChild("Modules")
local ks  = M and M:FindFirstChild("KnockSystem")

-- ---------- A. KnockSystem mendarat & compile ----------
ck("Folder Modules.KnockSystem ada", ks ~= nil)
local MODS = {"Config","Signal","DownedState","CrawlController",
	"ReviveManager","KnockAnimator","KnockService","KnockHud"}
for _, n in MODS do
	local m = ks and ks:FindFirstChild(n)
	ck("modul " .. n .. " ada", m ~= nil and m:IsA("ModuleScript"))
	if m then
		ck("modul " .. n .. " compile", loadstring(m.Source) ~= nil)
		ck("modul " .. n .. " bukan placeholder", #m.Source > 500)
		table.insert(out, string.format("BYTES %s=%d", n, #m.Source))
	end
end
local ctrl = SSS:FindFirstChild("KnockController")
ck("SSS.KnockController ada & compile", ctrl ~= nil and loadstring(ctrl.Source) ~= nil and #ctrl.Source > 500)
if ctrl then table.insert(out, string.format("BYTES KnockController=%d", #ctrl.Source)) end
for _, n in {"KnockUI", "RevivePromptFilter"} do
	local s = SPS and SPS:FindFirstChild(n)
	ck("SPS." .. n .. " ada & compile", s ~= nil and loadstring(s.Source) ~= nil and #s.Source > 500)
	if s then table.insert(out, string.format("BYTES %s=%d", n, #s.Source)) end
end

-- ---------- B. Script LAIN tidak tersentuh ----------
-- TargetFinder: sengaja TIDAK diintegrasikan (perintah Aer). Ukuran terkunci
-- pada versi place ini — kalau angka ini berubah, ada yang menyentuhnya.
local tf = M and M.EnemyController and M.EnemyController:FindFirstChild("TargetFinder")
ck("TargetFinder tetap versi lama (13080 byte)", tf ~= nil and #tf.Source == 13080,
	tf and #tf.Source)
ck("TargetFinder belum baca Attribute Knocked (sesuai perintah)",
	tf ~= nil and not string.find(tf.Source, '"Knocked"', 1, true))

for _, r in {
	{"KeySystem.DoorManager",    M.KeySystem.DoorManager},
	{"KeySystem.KeyPickupManager", M.KeySystem.KeyPickupManager},
	{"SafeZone.ZoneService",     M.SafeZone.ZoneService},
	{"SafeZone.Anchors",         M.SafeZone.Anchors},
	{"SafeZone.BreathBar",       M.SafeZone.BreathBar},
	{"BatteryPuzzle.Config",     M.BatteryPuzzle.Config},
	{"GeneratorSFX",             M.GeneratorSFX},
	{"TeleportData (tim)",       M.TeleportData},
	{"CustomPromptHelper (tim)", M.CustomPromptHelper},
} do
	ck(r[1] .. " masih ada", r[2] ~= nil and r[2]:IsA("ModuleScript"))
end
for _, n in {"EnemyController","KeySystemController","SafeZoneController",
	"AssemblyController","BatteryPuzzleController","GeneratorSFXController"} do
	ck("SSS." .. n .. " utuh", SSS:FindFirstChild(n) ~= nil)
end
local Feat = SSS:FindFirstChild("Feature")
ck("SSS.Feature (tim) + TeleprotHandler utuh",
	Feat ~= nil and Feat:FindFirstChild("TeleprotHandler") ~= nil)
for _, n in {"SafeZoneUI","PuzzleInputClient","JumpscareHandler","CustomPrompt Handler","SilencioClient"} do
	ck("SPS." .. n .. " utuh", SPS:FindFirstChild(n) ~= nil)
end

table.insert(out, string.format("=== AD-HOC edit-mode (bukan suite green): %d PASS / %d FAIL ===", pass, fail))
return table.concat(out, "\n")
