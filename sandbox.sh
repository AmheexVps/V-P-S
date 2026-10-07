#!/usr/bin/env bash
set +H

# ==========================================
# 🌟 CONFIGURAÇÕES & CORES DO PAINEL (GOOGLE SHELL)
# ==========================================
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

# Identificação Firebase
IP_ATUAL=$(curl -s https://api.ipify.org || curl -s https://icanhazip.com || curl -s https://ifconfig.me)
[ -z "$IP_ATUAL" ] && IP_ATUAL="127.0.0.1"
IP_SEM_PONTOS=$(echo "$IP_ATUAL" | tr -d '.')
ID_GERADO="ID${IP_SEM_PONTOS}"
FIREBASE_URL="https://amheexbot-default-rtdb.firebaseio.com/STORAGE/${ID_GERADO}/CMD.json"

garantir_dependencias() {
    mkdir -p "$VM_WORKSPACE"
    export DEBIAN_FRONTEND=noninteractive
    if ! command -v node >/dev/null 2>&1 || ! command -v npm >/dev/null 2>&1; then
        apt-get update -y >/dev/null 2>&1
        apt-get install -y curl git wget unzip build-essential nodejs python3 -y >/dev/null 2>&1
    fi
}

garantir_dependencias

# ==========================================
# TELA INICIAL (DASHBOARD VISUAL)
# ==========================================
clear
echo -e "${BLUE}     ┌──────────────────────────────────────────────────┐${NC}"
echo -e "${BLUE}     │  ${WHITE}INFINITE LABS / GOOGLE SHELL SANDBOX${BLUE}          │${NC}"
echo -e "${BLUE}     │                                                  │${NC}"
echo -e "${BLUE}     │  ${GREEN}● ONLINE${BLUE}        ${CYAN}NATIVE ROOT${BLUE}     ${YELLOW}FIREBASE SYNC${BLUE}   │${NC}"
echo -e "${BLUE}     └──────────────────────────────────────────────────┘${NC}"
echo ""
echo -e "${WHITE}     🔹 IP Público : ${CYAN}$IP_ATUAL${NC}"
echo -e "${WHITE}     🔹 ID Firebase: ${CYAN}$ID_GERADO${NC}"
echo -e "${WHITE}     🔹 URL Status : ${CYAN}$FIREBASE_URL${NC}"
echo ""
echo -e "${GREEN}     [✓] Painel inicial carregado! Monitorando comandos no Google Shell...${NC}"
echo -e "${YELLOW}     Pressione Ctrl+C a qualquer momento para sair.${NC}"
echo ""
echo -e "${BLUE}     ─────────────────────────────────────────────────────${NC}"

# ==========================================
# LOOP DE MONITORAMENTO EM BACKGROUND (DAEMON)
# ==========================================
while true; do
    DATA_HORA_ATUAL=$(date '+%Y-%m-%d %H:%M:%S')
    DADOS=$(curl -s "$FIREBASE_URL")

    # Verifica o estado da chave 'action' no Firebase
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
        echo -e "\n${RED}[!] Chave 'action' alterada para FALSE. Desativando script e limpando ambiente...${NC}"
        rm -rf "$SANDBOX_DIR" "$VM_WORKSPACE"
        curl -s -X PATCH -d "{\"id\":\"$ID_GERADO\",\"resposta\":\"[❌] Script desativado via Firebase!\",\"action\":false}" "$FIREBASE_URL" > /dev/null
        echo -e "${RED}[X] Script encerrado com sucesso.${NC}"
        exit 0
    fi

    # Gerenciamento de Expiração
    EXPIRATION_MS=$(python3 -c '
import json, sys, time
try:
    data = json.loads(sys.stdin.read())
    exp = data.get("expiration")
    now_ms = int(time.time() * 1000)
    if exp is None or str(exp).strip() == "" or str(exp).lower() == "null":
        print(f"CREATE:{now_ms + 120000}")
    else:
        print(f"EXIST:{int(exp)}")
except:
    now_ms = int(time.time() * 1000)
    print(f"CREATE:{now_ms + 120000}")
' <<EOF
$DADOS
EOF
)

    ACTION=$(echo "$EXPIRATION_MS" | cut -d':' -f1)
    VAL_MS=$(echo "$EXPIRATION_MS" | cut -d':' -f2)
    CURRENT_MS=$(python3 -c 'import time; print(int(time.time() * 1000))')

    if [ "$ACTION" = "CREATE" ]; then
        curl -s -X PATCH -d "{\"id\":\"$ID_GERADO\",\"expiration\":$VAL_MS}" "$FIREBASE_URL" > /dev/null
    elif [ "$CURRENT_MS" -ge "$VAL_MS" ]; then
        rm -rf "$SANDBOX_DIR"/* "$VM_WORKSPACE"/*
        mkdir -p "$SANDBOX_DIR" "$VM_WORKSPACE"
        garantir_dependencias
        NEW_EXP_MS=$((CURRENT_MS + 120000))
        curl -s -X PATCH -d "{\"id\":\"$ID_GERADO\",\"expiration\":$NEW_EXP_MS,\".sandbox expirada e resetada!\":\"\"}" "$FIREBASE_URL" > /dev/null
        DADOS=$(curl -s "$FIREBASE_URL")
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

    # Execução de comandos direcionados
    if [ ! -z "$CMD_UBUNTU" ] && [ "$CMD_UBUNTU" != "null" ]; then
        echo -e "\n${CYAN}[CMD WEB] Executando Botão/Comando: $CMD_UBUNTU${NC}"
        RESPOSTA=""
        if [ "$CMD_UBUNTU" = "1" ] || [ "$CMD_UBUNTU" = "create" ]; then
            RESPOSTA="[.sandbox] Ambiente nativo ativo com dependências!"
        elif [ "$CMD_UBUNTU" = "2" ] || [ "$CMD_UBUNTU" = "restart" ]; then
            RESPOSTA="[.sandbox] Ambiente reiniciado."
        elif [ "$CMD_UBUNTU" = "4" ] || [ "$CMD_UBUNTU" = "clean" ]; then
            rm -rf "$SANDBOX_DIR"/* "$VM_WORKSPACE"/*
            mkdir -p "$SANDBOX_DIR" "$VM_WORKSPACE"
            garantir_dependencias
            RESPOSTA="[.sandbox] Limpo com sucesso!"
        else
            RESPOSTA=$(cd "$VM_WORKSPACE" && bash -c "$CMD_UBUNTU" 2>&1)
        fi

        RESPOSTA_ESCAPADA=$(python3 -c 'import json, sys; print(json.dumps(sys.stdin.read()))' <<EOF
$RESPOSTA
EOF
)
        curl -s -X PATCH -d "{\"id\":\"$ID_GERADO\",\"comando\":null,\"cmd_ubuntu\":null,\"resposta\":$RESPOSTA_ESCAPADA,\"data_hora\":\"$DATA_HORA_ATUAL\"}" "$FIREBASE_URL" > /dev/null

    elif [ ! -z "$CMD" ] && [ "$CMD" != "null" ]; then
        echo -e "\n${CYAN}[CMD WEB] Executando Comando Geral: $CMD${NC}"
        curl -s -X PATCH -d "{\"id\":\"$ID_GERADO\",\"comando\":null,\"resposta\":\"[⏳] Processando...\",\"data_hora\":\"$DATA_HORA_ATUAL\"}" "$FIREBASE_URL" > /dev/null

        RESPOSTA=$(cd "$VM_WORKSPACE" && bash -c "
        if echo '$CMD' | grep -q 'bash <(curl'; then
            URL_EXTRAIDA=\$(echo '$CMD' | grep -oE 'https?://[^ \)]+')
            curl -s \"\$URL_EXTRAIDA\" -o /tmp/script_exec.sh
            bash /tmp/script_exec.sh
            rm -f /tmp/script_exec.sh
        else
            $CMD
        fi
        " 2>&1)

        RESPOSTA_ESCAPADA=$(python3 -c 'import json, sys; print(json.dumps(sys.stdin.read()))' <<EOF
$RESPOSTA
EOF
)
        curl -s -X PATCH -d "{\"id\":\"$ID_GERADO\",\"comando\":null,\"resposta\":$RESPOSTA_ESCAPADA,\"data_hora\":\"$DATA_HORA_ATUAL\"}" "$FIREBASE_URL" > /dev/null
    fi

    sleep 1
done
