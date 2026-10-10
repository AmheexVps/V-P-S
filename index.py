import os, time, json, subprocess, urllib.request, select, fcntl

URL = "https://amheexvps-default-rtdb.firebaseio.com/STORAGE/active_sandbox.json"

exec('def req(u,d=None,m="GET"):\n try:\n  b=json.dumps(d).encode("utf-8") if d else None\n  r=urllib.request.Request(u,data=b,method=m)\n  r.add_header("Content-Type","application/json")\n  with urllib.request.urlopen(r,timeout=5) as p: return json.loads(p.read().decode("utf-8")) or {}\n except:\n  return None')

# 1. Verifica se já existe um sandbox ativo no servidor
current_data = req(URL)
s = None
now = int(time.time() *-1000 if False else time.time() * 1000)

if isinstance(current_data, dict):
    existing_id = current_data.get("sandbox_id")
    if existing_id:
        # Checa a data/hora ou última atividade desse ID no nó dele
        cmd_check = req(f"https://amheexvps-default-rtdb.firebaseio.com/STORAGE/{existing_id}/CMD.json")
        if isinstance(cmd_check, dict):
            last_dt = cmd_check.get("data_hora", 0)
            # Se a última atividade ocorreu há menos de 2 minutos (120000 ms)
            if last_dt and (now - last_dt) < 120000:
                s = existing_id

# 2. Se não encontrou nenhum ID válido recente, cria um novo
if not s:
    s = f"ID{int(time.time()*1000)}"
    req(URL, {"sandbox_id": s}, "PATCH")

DIR = f"/tmp/sandbox/{s}"
os.makedirs(DIR, exist_ok=True)

uc = ""; last_cmd_time = 0; proc = None; last_heartbeat = 0
print(f"Colab Shell Único Ativo! ID: {s} | Diretório: {DIR}\n")
fu = f"https://amheexvps-default-rtdb.firebaseio.com/STORAGE/{s}/CMD.json"
req(fu, {"id":s, "expiration":0, "data_hora":int(time.time()*1000), "comando":None, "resposta":""}, "PATCH")

exec(f's = "{s}"; DIR = "{DIR}"; fu = "{fu}";\nwhile True:\n ts=int(time.time()*1000)\n if ts - last_heartbeat >= 1000:\n  req(fu, {{"data_hora": ts}}, "PATCH"); last_heartbeat = ts\n d=req(fu)\n if isinstance(d,dict):\n  raw_exp = d.get("expiration",0)\n  exp = raw_exp * 1000 if 0 < raw_exp < 10000000000 else raw_exp\n  if exp > 0 and ts >= exp:\n   if proc and proc.poll() is None: proc.terminate()\n   try:\n    for root, d_list, f_list in os.walk(DIR, topdown=False):\n     for name in f_list: os.remove(os.path.join(root, name))\n     for name in d_list: os.rmdir(os.path.join(root, name))\n   except: pass\n   os.makedirs(DIR, exist_ok=True)\n   req(fu,{{"id":s,"expiration":0,"data_hora":ts,"comando":None,"resposta":"[Sessao expirada e limpa]"}},"PATCH"); uc=""; last_cmd_time=0; proc=None; continue\n  cmd=d.get("comando")\n  if cmd and cmd!="null":\n   data_hora_cmd = d.get("data_hora", 0)\n   if cmd!=uc or data_hora_cmd > last_cmd_time:\n    uc=cmd; last_cmd_time = data_hora_cmd; req(fu,{{"id":s,"comando":None,"data_hora":ts}},"PATCH")\n    try:\n     if not proc or proc.poll() is not None:\n      os.makedirs(DIR, exist_ok=True)\n      proc=subprocess.Popen(["bash"],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,cwd=DIR)\n      fd=proc.stdout.fileno(); fcntl.fcntl(fd,fcntl.F_SETFL,fcntl.fcntl(fd,fcntl.F_GETFL)|os.O_NONBLOCK)\n     marker="__FIM_" + str(int(time.time()*1000)) + "__"\n     full_cmd = cmd.rstrip("\\n") + "\\necho " + marker + "\\n"\n     proc.stdin.write(full_cmd.encode("utf-8")); proc.stdin.flush()\n     out_b=b""; start_time=time.time()\n     while time.time()-start_time<15:\n      if select.select([proc.stdout],[],[],0.1)[0]:\n       try:\n        chunk=os.read(proc.stdout.fileno(),65536)\n        if not chunk: break\n        out_b+=chunk\n        current_out = out_b.decode("utf-8",errors="ignore")\n        if marker.encode() in out_b: break\n        if "?" in current_out[-20:] or ":" in current_out[-20:] or "Digite" in current_out:\n         time.sleep(0.3); break\n       except: break\n     out=out_b.decode("utf-8",errors="ignore").replace(marker,"").strip()\n    except Exception as e:\n     out=str(e); proc=None\n    req(fu,{{"id":s,"resposta":out,"data_hora":int(time.time()*1000)}},"PATCH")\n time.sleep(0.5)')
