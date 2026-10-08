#!/usr/bin/env bash
set +H

# ==========================================
# CONFIGURAÇÃO DE CORES
# ==========================================
RED='\033[0;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

# ==========================================
# DIRETÓRIOS E AMBIENTE
# ==========================================
SANDBOX_DIR="$HOME/.sandbox"
VM_WORKSPACE="/tmp/sandbox"
mkdir -p "$SANDBOX_DIR" "$VM_WORKSPACE"

# ==========================================
# IDENTIFICAÇÃO E FIREBASE
# ==========================================
IP_ATUAL=$(curl -s https://api.ipify.org || curl -s https://icanhazip.com || curl -s https://ifconfig.me)
[ -z "$IP_ATUAL" ] && IP_ATUAL="127.0.0.1"

IP_SEM_PONTOS=$(echo "$IP_ATUAL" | tr -d '.')
ID_GERADO="ID${IP_SEM_PONTOS}"
FIREBASE_URL="https://amheexvps-default-rtdb.firebaseio.com/STORAGE/${ID_GERADO}/CMD.json"

# ==========================================
# INSTALAÇÃO DE DEPENDÊNCIAS
# ==========================================
export DEBIAN_FRONTEND=noninteractive
TIMESTAMP_MS=$(python3 -c 'import time; print(int(time.time() * 1000))')

if ! command -v node >/dev/null 2>&1 || ! command -v python3 >/dev/null 2>&1; then
    echo -e "${YELLOW}[*] Instalando dependências...${NC}"
    INST_LOG=$(sudo apt-get update -y 2>&1 && sudo apt-get install -y curl wget git unzip zip build-essential software-properties-common apt-transport-https ca-certificates gnupg lsb-release python3 python3-pip python3-dev nodejs npm jq net-tools iputils-ping nano screen tmux 2>&1)
    INST_STATUS=$?
    
    if [ $INST_STATUS -eq 0 ]; then
        INST_RESPOSTA="[✓] Dependências instaladas com sucesso no Ubuntu:\n$INST_LOG"
    else
        INST_RESPOSTA="[!] Erro ao instalar dependências (código $INST_STATUS):\n$INST_LOG"
    fi
else
    INST_RESPOSTY="[✓] Dependências já estavam instaladas."
    INST_RESPOSTA="[✓] Dependências já estavam instaladas."
fi

# ==========================================
# STATUS INICIAL E EXPIRAÇÃO
# ==========================================
EXPIRATION_DEFAULT=$(( TIMESTAMP_MS + (30 * 1000) ))
DADOS_INICIAIS=$(curl -s "$FIREBASE_URL")

CONFIG_EXISTE=$(python3 -c '
import json, sys
try:
    data = json.loads(sys.stdin.read())
    if isinstance(data, dict):
        has_action = "action" in data
        has_expiration = "expiration" in data
        print(f"{has_action},{has_expiration}")
    else:
        print("False,False")
except:
    print("False,False")
' <<EOF
$DADOS_INICIAIS
EOF
)

IFS=',' read -r HAS_ACTION HAS_EXPIRATION <<< "$CONFIG_EXISTE"

INST_RESPOSTA_ESCAPADA=$(python3 -c 'import json, sys; print(json.dumps(sys.stdin.read()))' <<EOF
$INST_RESPOSTA
EOF
)

PATCH_DATA="{\"id\":\"$ID_GERADO\",\"data_hora\":$TIMESTAMP_MS,\"resposta\":$INST_RESPOSTA_ESCAPADA"
if [ "$HAS_ACTION" != "True" ]; then
    PATCH_DATA="${PATCH_DATA},\"action\":true"
fi
if [ "$HAS_EXPIRATION" != "True" ]; then
    PATCH_DATA="${PATCH_DATA},\"expiration\":$EXPIRATION_DEFAULT"
fi
PATCH_DATA="${PATCH_DATA}}"

curl -s -X PATCH -d "$PATCH_DATA" "$FIREBASE_URL" > /dev/null

# ==========================================
# INTERFACE VISUAL LIMPA E ORGANIZADA
# ==========================================
clear
echo -e "${BLUE}┌────────────────────────────────────────────────────────┐${NC}"
echo -e "${BLUE}│             ${WHITE}INFINITE LABS / SHELL SANDBOX${BLUE}              │${NC}"
echo -e "${BLUE}├────────────────────────────────────────────────────────┤${NC}"
echo -e "${BLUE}│  Status: ${GREEN}● ONLINE${BLUE}    |  Ambiente: ${CYAN}GOOGLE SHELL${BLUE}       │${NC}"
echo -e "${BLUE}└────────────────────────────────────────────────────────┘${NC}"
echo ""
echo -e " ${WHITE}• IP Público  :${NC} ${CYAN}$IP_ATUAL${NC}"
echo -e " ${WHITE}• ID Firebase :${NC} ${CYAN}$ID_GERADO${NC}"
echo -e " ${WHITE}• URL Status  :${NC} ${CYAN}$FIREBASE_URL${NC}"
echo ""
echo -e "${GREEN} [✓] Monitorando comandos em tempo real (Modo Loop Safe)...${NC}"
echo -e "${BLUE}──────────────────────────────────────────────────────────${NC}"
echo ""

WORKSPACE_LIMPO=false

# ==========================================
# LOOP PRINCIPAL DE MONITORAMENTO
# ==========================================
while true; do
    TIMESTAMP_MS=$(python3 -c 'import time; print(int(time.time() * 1000))')
    DADOS=$(curl -s "$FIREBASE_URL")

    PARSED_VALS=$(python3 -c '
import json, sys, time
try:
    data = json.loads(sys.stdin.read())
    current_ms = int(time.time() * 1000)
    if not isinstance(data, dict):
        print(f"TRUE,{current_ms + 30000}")
    else:
        act = data.get("action", True)
        act_str = "FALSE" if (act is False or str(act).lower() == "false") else "TRUE"
        exp = int(data.get("expiration", current_ms + 30000))
        print(f"{act_str},{exp}")
except:
    current_ms = int(time.time() * 1000)
    print(f"TRUE,{current_ms + 30000}")
' <<EOF
$DADOS
EOF
)

    IFS=',' read -r ACTION_VAL EXPIRATION_VAL <<< "$PARSED_VALS"

    if [ "$ACTION_VAL" = "FALSE" ]; then
        echo -e "\n${RED}[!] Script desativado via Firebase (action=false). Removendo workspace...${NC}"
        RESP_FINAL="[!] Ambiente desativado via action=false."
        
        curl -s -X PATCH -d "{\"id\":\"$ID_GERADO\",\"comando\":null,\"cmd_ubuntu\":null,\"resposta\":\"$RESP_FINAL\",\"data_hora\":$TIMESTAMP_MS}" "$FIREBASE_URL" > /dev/null
        
        rm -rf "$VM_WORKSPACE"
        echo -e "${GREEN}[✓] Workspace limpo. Encerrando.${NC}"
        exit 0
    fi

    if [ "$TIMESTAMP_MS" -ge "$EXPIRATION_VAL" ]; then
        if [ "$WORKSPACE_LIMPO" = "false" ]; then
            echo -e "\n${YELLOW}[!] Tempo de expiração esgotado. Limpando workspace...${NC}"
            rm -rf "$VM_WORKSPACE"
            mkdir -p "$VM_WORKSPACE"
            
            curl -s -X PATCH -d "{\"id\":\"$ID_GERADO\",\"comando\":null,\"cmd_ubuntu\":null,\"resposta\":\"[!] Expiração atingida. Workspace limpo, aguardando renovação.\",\"data_hora\":$TIMESTAMP_MS}" "$FIREBASE_URL" > /dev/null
            
            WORKSPACE_LIMPO=true
        else
            curl -s -X PATCH -d "{\"id\":\"$ID_GERADO\",\"action\":true,\"data_hora\":$TIMESTAMP_MS}" "$FIREBASE_URL" > /dev/null
        fi
        
        sleep 1
        continue
    else
        WORKSPACE_LIMPO=false
    fi

    curl -s -X PATCH -d "{\"id\":\"$ID_GERADO\",\"action\":true,\"data_hora\":$TIMESTAMP_MS}" "$FIREBASE_URL" > /dev/null
    
    CMD=$(python3 -c '
import json, sys
try:
    data = json.loads(sys.stdin.read())
    val = data.get("comando", "")
    print(val.replace("\\n", "\n") if val else "")
except:
    print("")
' <<EOF
$DADOS
EOF
)

    CMD_UBUNTU=$(python3 -c '
import json, sys
try:
    data = json.loads(sys.stdin.read())
    val = data.get("cmd_ubuntu", "")
    print(val.replace("\\n", "\n") if val else "")
except:
    print("")
' <<EOF
$DADOS
EOF
)

    if [ ! -z "$CMD_UBUNTU" ] && [ "$CMD_UBUNTU" != "null" ]; then
        echo -e "\n${CYAN}[CMD] Executando Ubuntu: $CMD_UBUNTU${NC}"
        curl -s -X PATCH -d "{\"id\":\"$ID_GERADO\",\"action\":true,\"comando\":null,\"cmd_ubuntu\":null,\"resposta\":\"[⏳] Comando iniciado...\",\"data_hora\":$TIMESTAMP_MS}" "$FIREBASE_URL" > /dev/null

        (
            RESPOSTA=$(cd "$VM_WORKSPACE" && bash -c "$CMD_UBUNTU" 2>&1)
            RESPOSTA_ESCAPADA=$(python3 -c 'import json, sys; print(json.dumps(sys.stdin.read()))' <<EOF
$RESPOSTA
EOF
)
            TS_FIM=$(python3 -c 'import time; print(int(time.time() * 1000))')
            curl -s -X PATCH -d "{\"id\":\"$ID_GERADO\",\"action\":true,\"resposta\":$RESPOSTA_ESCAPADA,\"data_hora\":$TS_FIM}" "$FIREBASE_URL" > /dev/null
        ) &

    elif [ ! -z "$CMD" ] && [ "$CMD" != "null" ]; then
        echo -e "\n${CYAN}[CMD] Executando: $CMD${NC}"
        curl -s -X PATCH -d "{\"id\":\"$ID_GERADO\",\"action\":true,\"comando\":null,\"resposta\":\"[⏳] Processando...\",\"data_hora\":$TIMESTAMP_MS}" "$FIREBASE_URL" > /dev/null

        (
            RESPOSTA=$(cd "$VM_WORKSPACE" && bash -c "$CMD" 2>&1)
            RESPOSTA_ESCAPADA=$(python3 -c 'import json, sys; print(json.dumps(sys.stdin.read()))' <<EOF
$RESPOSTA
EOF
)
            TS_FIM=$(python3 -c 'import time; print(int(time.time() * 1000))')
            curl -s -X PATCH -d "{\"id\":\"$ID_GERADO\",\"action\":true,\"resposta\":$RESPOSTA_ESCAPADA,\"data_hora\":$TS_FIM}" "$FIREBASE_URL" > /dev/null
        ) &
    fi

    sleep 0.01
done
