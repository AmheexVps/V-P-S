#!/usr/bin/env bash
set +H

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

SANDBOX_DIR="$HOME/.sandbox"
VM_WORKSPACE="/tmp/sandbox"
mkdir -p "$SANDBOX_DIR" "$VM_WORKSPACE"

IP_ATUAL=$(curl -s https://api.ipify.org || curl -s https://icanhazip.com || curl -s https://ifconfig.me)
[ -z "$IP_ATUAL" ] && IP_ATUAL="127.0.0.1"
IP_SEM_PONTOS=$(echo "$IP_ATUAL" | tr -d '.')
ID_GERADO="ID${IP_SEM_PONTOS}"
FIREBASE_URL="https://amheexbot-default-rtdb.firebaseio.com/STORAGE/${ID_GERADO}/CMD.json"

export DEBIAN_FRONTEND=noninteractive
if ! command -v node >/dev/null 2>&1 || ! command -v python3 >/dev/null 2>&1; then
    sudo apt-get update -y >/dev/null 2>&1
    sudo apt-get install -y curl git wget unzip build-essential nodejs python3 -y >/dev/null 2>&1
fi

clear
echo -e "${BLUE}     ┌──────────────────────────────────────────────────┐${NC}"
echo -e "${BLUE}     │  ${WHITE}INFINITE LABS / GOOGLE SHELL SANDBOX${BLUE}          │${NC}"
echo -e "${BLUE}     │                                                  │${NC}"
echo -e "${BLUE}     │  ${GREEN}● ONLINE${BLUE}        ${CYAN}GOOGLE SHELL${BLUE}    ${YELLOW}FIREBASE SYNC${BLUE}   │${NC}"
echo -e "${BLUE}     └──────────────────────────────────────────────────┘${NC}"
echo ""
echo -e "${WHITE}     🔹 IP Público : ${CYAN}$IP_ATUAL${NC}"
echo -e "${WHITE}     🔹 ID Firebase: ${CYAN}$ID_GERADO${NC}"
echo -e "${WHITE}     🔹 URL Status : ${CYAN}$FIREBASE_URL${NC}"
echo ""
echo -e "${GREEN}     [✓] Monitorando comandos no Google Shell...${NC}"
echo ""

while true; do
    DATA_HORA_ATUAL=$(date '+%Y-%m-%d %H:%M:%S')
    DADOS=$(curl -s "$FIREBASE_URL")

    ACTION_VAL=$(python3 -c '
import json, sys
try:
    data = json.loads(sys.stdin.read())
    act = data.get("action")
    if act is False or str(act).lower() == "false":
        print("FALSE")
    else:
        print("TRUE")
except:
    print("TRUE")
' <<EOF
$DADOS
EOF
)

    if [ "$ACTION_VAL" = "FALSE" ]; then
        echo -e "\n${RED}[!] Script desativado via Firebase.${NC}"
        exit 0
    fi

    curl -s -X PATCH -d "{\"id\":\"$ID_GERADO\",\"data_hora\":\"$DATA_HORA_ATUAL\"}" "$FIREBASE_URL" > /dev/null
    
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
        echo -e "\n${CYAN}[CMD] Executando: $CMD_UBUNTU${NC}"
        RESPOSTA=$(cd "$VM_WORKSPACE" && bash -c "$CMD_UBUNTU" 2>&1)
        RESPOSTA_ESCAPADA=$(python3 -c 'import json, sys; print(json.dumps(sys.stdin.read()))' <<EOF
$RESPOSTA
EOF
)
        curl -s -X PATCH -d "{\"id\":\"$ID_GERADO\",\"comando\":null,\"cmd_ubuntu\":null,\"resposta\":$RESPOSTA_ESCAPADA,\"data_hora\":\"$DATA_HORA_ATUAL\"}" "$FIREBASE_URL" > /dev/null

    elif [ ! -z "$CMD" ] && [ "$CMD" != "null" ]; then
        echo -e "\n${CYAN}[CMD] Executando: $CMD${NC}"
        curl -s -X PATCH -d "{\"id\":\"$ID_GERADO\",\"comando\":null,\"resposta\":\"[⏳] Processando...\",\"data_hora\":\"$DATA_HORA_ATUAL\"}" "$FIREBASE_URL" > /dev/null

        RESPOSTA=$(cd "$VM_WORKSPACE" && bash -c "$CMD" 2>&1)
        RESPOSTA_ESCAPADA=$(python3 -c 'import json, sys; print(json.dumps(sys.stdin.read()))' <<EOF
$RESPOSTA
EOF
)
        curl -s -X PATCH -d "{\"id\":\"$ID_GERADO\",\"comando\":null,\"resposta\":$RESPOSTA_ESCAPADA,\"data_hora\":\"$DATA_HORA_ATUAL\"}" "$FIREBASE_URL" > /dev/null
    fi

    sleep 1
done
