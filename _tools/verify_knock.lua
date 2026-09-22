--[[ verify_knock.lua — harness regresi KnockSystem (jalankan via _tools/mcp.py).
     Bukan suite green CI; ini verifikasi AD-HOC yang bisa diulang:
     compile semua modul + struktur + PARITAS NAMA ATTRIBUTE Config<->UI + wiring.
     Cara pakai:  python -c "import mcp,pathlib;print(mcp.luau(pathlib.Path('_tools/verify_knock.lua').read_text(encoding='utf-8')))" ]]
local out, pass, fail = {}, 0, 0
local function ck(n, c, e)
	if c then pass += 1; table.insert(out, "PASS " .. n)
	else fail += 1; table.insert(out, "FAIL " .. n .. (e and (" :: " .. tostring(e)) or "")) end
end
-- WAJIB strip komentar sebelum scan string (kata bisa nyangkut di komentar).
local function strip(s)
	s = s:gsub("%-%-%[%[.-%]%]", "")
	return (s:gsub("%-%-[^\n]*", ""))
end
local function has(s, sub) return string.find(s, sub, 1, true) ~= nil end

local ks = game.ReplicatedStorage:FindFirstChild("Modules")
	and game.ReplicatedStorage.Modules:FindFirstChild("KnockSystem")
if not ks then
	return "FATAL: folder Modules.KnockSystem tidak ada di ReplicatedStorage"
end

-- ---------- 1. Semua modul ada & compile ----------
local MODULES = {"Config","Signal","DownedState","CrawlController",
	"ReviveManager","KnockAnimator","KnockService","KnockHud"}
local S = {}
for _, n in MODULES do
	local m = ks:FindFirstChild(n)
	ck("modul " .. n .. " ada", m ~= nil)
	if m then
		S[n] = m.Source
		ck("modul " .. n .. " compile", loadstring(m.Source) ~= nil)
	end
end
local ctrl = game.ServerScriptService:FindFirstChild("KnockController")
ck("orchestrator KnockController ada & compile", ctrl ~= nil and loadstring(ctrl.Source) ~= nil)
local uiScript = game.StarterPlayer.StarterPlayerScripts:FindFirstChild("KnockUI")
ck("KnockUI ada & compile", uiScript ~= nil and loadstring(uiScript.Source) ~= nil)
local uiSrc = uiScript and uiScript.Source or ""

-- ---------- 2. Kontrak API modul UI (new titik, sisanya titik dua) ----------
for _, fn in {"new","update","tick","destroy"} do
	local decl = (fn == "new") and "function KnockHud.new(" or ("function KnockHud:" .. fn .. "(")
	ck("API KnockHud." .. fn, has(S.KnockHud or "", decl))
end
for _, fn in {"play","stop","cleanup"} do
	ck("API KnockAnimator." .. fn, has(S.KnockAnimator or "", "function KnockAnimator." .. fn))
end

-- ---------- 3. PARITAS NAMA ATTRIBUTE Config <-> UI (paling berisiko) ----------
local cfg = S.Config or ""
local rows = {
	{"Knocked",        cfg:match('DownedAttribute%s*=%s*"([^"]+)"'),         uiSrc:match('ATTR_DOWNED%s*=%s*"([^"]+)"')},
	{"BleedOut",       cfg:match('BleedOutAttribute%s*=%s*"([^"]+)"'),       uiSrc:match('ATTR_BLEEDOUT%s*=%s*"([^"]+)"')},
	{"ReviveProgress", cfg:match('ReviveProgressAttribute%s*=%s*"([^"]+)"'), uiSrc:match('ATTR_REVIVE%s*=%s*"([^"]+)"')},
}
for _, r in rows do
	ck("Attribute " .. r[1] .. " cocok Config<->UI", r[2] ~= nil and r[2] == r[3],
		string.format("cfg=%s ui=%s", tostring(r[2]), tostring(r[3])))
end

-- ---------- 4. Server benar-benar men-set ketiganya ----------
ck("set Downed (DownedState)",         has(S.DownedState or "", "SetAttribute(Config.DownedAttribute"))
ck("set BleedOut (DownedState)",       has(S.DownedState or "", "SetAttribute(Config.BleedOutAttribute"))
ck("set BleedOut live (KnockService)", has(S.KnockService or "", "SetAttribute(Config.BleedOutAttribute"))
ck("set Revive live (ReviveManager)",  has(S.ReviveManager or "", "SetAttribute(Config.ReviveProgressAttribute"))

-- ---------- 5. UI lewat Attribute, bukan RemoteEvent ----------
local uiCode = strip(uiSrc)
ck("UI pakai GetAttribute",      has(uiCode, "GetAttribute("))
ck("UI pantau AttributeChanged", has(uiCode, "AttributeChanged"))
ck("UI tanpa RemoteEvent",       not has(uiCode, "RemoteEvent"))
ck("UI detach saat pulih",       has(uiCode, "detach(character)"))
ck("UI bersih saat respawn",     has(uiCode, "CharacterRemoving"))

-- ---------- 6. Anti-mati & mati-beneran (inti sistem) ----------
ck("arm anti-death (SetStateEnabled Dead false)",
	has(S.DownedState or "", "Enum.HumanoidStateType.Dead, false"))
ck("kill pakai ChangeState(Dead) (Health sudah 0)",
	has(S.DownedState or "", "ChangeState(Enum.HumanoidStateType.Dead)"))
ck("self-revive ditolak via identitas player",
	has(S.ReviveManager or "", "GetPlayerFromCharacter(character)"))

-- ---------- 7. Wiring animasi (play saat tumbang, stop di jalur keluar) ----------
ck("play() saat tumbang", has(S.KnockService or "", "KnockAnimator.play("))
local stopCount = select(2, (S.KnockService or ""):gsub("KnockAnimator%.stop%(", ""))
ck("stop() di >=4 jalur keluar (dapat " .. stopCount .. ")", stopCount >= 4)

table.insert(out, string.format("=== AD-HOC edit-mode (bukan suite green): %d PASS / %d FAIL ===", pass, fail))
return table.concat(out, "\n")
