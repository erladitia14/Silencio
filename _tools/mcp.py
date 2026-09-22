"""Helper MCP HTTP langsung ke Roblox Studio (jalur terbukti, bukan tool_call)."""
import json, os, urllib.request, base64, pathlib

AUTH = open(os.path.expanduser("~/.robloxstudio-mcp/auth-token")).read().strip()
URL = "http://127.0.0.1:58741/mcp"
_id = [0]

def call(tool, args=None, timeout=180):
    _id[0] += 1
    body = json.dumps({
        "jsonrpc": "2.0", "id": _id[0], "method": "tools/call",
        "params": {"name": tool, "arguments": args or {}},
    }).encode()
    req = urllib.request.Request(URL, data=body, headers={
        "Content-Type": "application/json",
        "Accept": "application/json, text/event-stream",
        "X-MCP-Auth": AUTH,
    })
    raw = urllib.request.urlopen(req, timeout=timeout).read().decode("utf-8", "replace")
    out = []
    for line in raw.splitlines():
        if line.startswith("data:"):
            out.append(line[5:].strip())
    payload = "\n".join(out) if out else raw
    try:
        return json.loads(payload)
    except Exception:
        return {"_raw": payload}

def luau(code, timeout=180):
    """Jalankan Luau di server VM, kembalikan teks hasilnya."""
    r = call("execute_luau", {"code": code}, timeout=timeout)
    try:
        blocks = r["result"]["content"]
        return "\n".join(b.get("text", "") for b in blocks)
    except Exception:
        return json.dumps(r)[:4000]

def push(path, source_path):
    """Push file lokal -> Script di Studio via set_script_source (baca dari disk)."""
    src = pathlib.Path(source_path).read_text(encoding="utf-8")
    r = call("set_script_source", {"instancePath": path, "source": src})
    try:
        blocks = r["result"]["content"]
        return "\n".join(b.get("text", "") for b in blocks)
    except Exception:
        return json.dumps(r)[:2000]

def push_b64(path, source_path):
    """(cadangan) Push lewat base64 chunk kalau set_script_source timeout."""
    src = pathlib.Path(source_path).read_text(encoding="utf-8")
    b64 = base64.b64encode(src.encode("utf-8")).decode()
    n = 60000
    chunks = [b64[i:i+n] for i in range(0, len(b64), n)]
    prelude = (
        "_G.__BUF = ''\n"
        f"local parts = {{ {','.join(json.dumps(c) for c in chunks)} }}\n"
        "for _,p in parts do _G.__BUF ..= p end\n"
        "local b='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'\n"
        "local dec=_G.__BUF:gsub('[^'..b..'=]','')\n"
        "local out=dec:gsub('.',function(x)\n"
        "  if x=='=' then return '' end\n"
        "  local r,f='',(b:find(x)-1)\n"
        "  for i=6,1,-1 do r=r..(f%2^i-f%2^(i-1)>0 and '1' or '0') end\n"
        "  return r\n"
        "end):gsub('%d%d%d?%d?%d?%d?%d?%d?',function(x)\n"
        "  if #x~=8 then return '' end\n"
        "  local c=0\n"
        "  for i=1,8 do c=c+(x:sub(i,i)=='1' and 2^(8-i) or 0) end\n"
        "  return string.char(c)\n"
        "end)\n"
        f"local m = {path}\n"
        "m.Source = out\n"
        "return #m.Source\n"
    )
    return luau(prelude)
