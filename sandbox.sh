#!/usr/bin/env bash
set +H

# ==========================================
# CONFIGURAÇÃO
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

# ==========================================
# FUNÇÕES
# ==========================================

agora_ms() {
    python3 -c 'import time; print(int(time.time()*1000))'
}

json_string() {
    python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))'
}

firebase_patch() {
    local JSON_DATA="$1"

    curl -fsS \
        --connect-timeout 5 \
        --max-time 30 \
        -X PATCH \
        -H "Content-Type: application/json" \
        --data-binary "$JSON_DATA" \
        "$FIREBASE_URL" \
        >/dev/null 2>&1 || true
}

enviar_resposta() {
    local RESPOSTA="$1"
    local TS="${2:-$(agora_ms)}"

    local ESCAPADA
    ESCAPADA=$(printf '%s' "$RESPOSTA" | json_string)

    firebase_patch "{
        \"id\":$(printf '%s' "$ID_GERADO" | json_string),
        \"resposta\":$ESCAPADA,
        \"data_hora\":$TS
    }"
}

# ==========================================
# IDENTIFICAÇÃO
# ==========================================

IP_ATUAL=$(
    curl -fsS --max-time 5 https://api.ipify.org 2>/dev/null ||
    curl -fsS --max-time 5 https://icanhazip.com 2>/dev/null ||
    curl -fsS --max-time 5 https://ifconfig.me 2>/dev/null
)

[ -z "$IP_ATUAL" ] && IP_ATUAL="127.0.0.1"

IP_SEM_PONTOS=$(printf '%s' "$IP_ATUAL" | tr -d '.')
ID_GERADO="ID${IP_SEM_PONTOS}"

FIREBASE_URL="https://amheexvps-default-rtdb.firebaseio.com/STORAGE/${ID_GERADO}/CMD.json"

TIMESTAMP_MS=$(agora_ms)
EXPIRATION_DEFAULT=$((TIMESTAMP_MS + 30000))

# ==========================================
# INSTALAÇÃO
# ==========================================

export DEBIAN_FRONTEND=noninteractive

INST_RESPOSTA=""

if ! command -v node >/dev/null 2>&1 ||
   ! command -v python3 >/dev/null 2>&1 ||
   ! command -v curl >/dev/null 2>&1; then

    echo -e "${YELLOW}[*] Instalando dependências...${NC}"

    INST_LOG=$(
        sudo apt-get update -y 2>&1

        UPDATE_STATUS=$?

        if [ "$UPDATE_STATUS" -eq 0 ]; then
            sudo apt-get install -y \
                curl \
                wget \
                git \
                unzip \
                zip \
                build-essential \
                software-properties-common \
                apt-transport-https \
                ca-certificates \
                gnupg \
                lsb-release \
                python3 \
                python3-pip \
                python3-dev \
                nodejs \
                npm \
                jq \
                net-tools \
                iputils-ping \
                nano \
                screen \
                tmux \
                2>&1
        else
            echo "[ERRO] apt-get update falhou com código $UPDATE_STATUS"
            exit "$UPDATE_STATUS"
        fi
    )

    INST_STATUS=$?

    if [ "$INST_STATUS" -eq 0 ]; then
        INST_RESPOSTA="[✓] Dependências instaladas com sucesso.

$INST_LOG"
    else
        INST_RESPOSTA="[!] Erro ao instalar dependências.

Código: $INST_STATUS

$INST_LOG"
    fi

else
    INST_RESPOSTA="[✓] Dependências já estavam instaladas.

Node:
$(node --version 2>&1)

Python:
$(python3 --version 2>&1)

Curl:
$(curl --version 2>&1 | head -n 1)"
fi

# ==========================================
# CONFIGURAÇÃO INICIAL
# ==========================================

DADOS_INICIAIS=$(curl -fsS --max-time 10 "$FIREBASE_URL" 2>/dev/null || echo '{}')

CONFIG_EXISTE=$(
    printf '%s' "$DADOS_INICIAIS" |
    python3 -c '
import json,sys

try:
    data=json.load(sys.stdin)

    if isinstance(data,dict):
        print(
            "True" if "action" in data else "False",
            "True" if "expiration" in data else "False"
        )
    else:
        print("False False")

except Exception:
    print("False False")
'
)

read -r HAS_ACTION HAS_EXPIRATION <<< "$CONFIG_EXISTE"

INST_RESPOSTA_ESCAPADA=$(
    printf '%s' "$INST_RESPOSTA" | json_string
)

PATCH_DATA="{
    \"id\":$(printf '%s' "$ID_GERADO" | json_string),
    \"data_hora\":$TIMESTAMP_MS,
    \"resposta\":$INST_RESPOSTA_ESCAPADA"

if [ "$HAS_ACTION" != "True" ]; then
    PATCH_DATA="$PATCH_DATA,\"action\":true"
fi

if [ "$HAS_EXPIRATION" != "True" ]; then
    PATCH_DATA="$PATCH_DATA,\"expiration\":$EXPIRATION_DEFAULT"
fi

PATCH_DATA="$PATCH_DATA}"

firebase_patch "$PATCH_DATA"

# ==========================================
# INTERFACE
# ==========================================

clear

echo -e "${BLUE}┌──────────────────────────────────────────────────┐${NC}"
echo -e "${BLUE}│ ${WHITE}INFINITE LABS / GOOGLE SHELL SANDBOX${BLUE}           │${NC}"
echo -e "${BLUE}│                                                  │${NC}"
echo -e "${BLUE}│ ${GREEN}● ONLINE${BLUE}        ${CYAN}GOOGLE SHELL${BLUE}    ${YELLOW}FIREBASE${BLUE}       │${NC}"
echo -e "${BLUE}└──────────────────────────────────────────────────┘${NC}"

echo ""
echo -e "${WHITE}IP Público : ${CYAN}$IP_ATUAL${NC}"
echo -e "${WHITE}ID Firebase: ${CYAN}$ID_GERADO${NC}"
echo -e "${WHITE}Firebase   : ${CYAN}$FIREBASE_URL${NC}"
echo ""
echo -e "${GREEN}[✓] Monitoramento iniciado.${NC}"
echo -e "${GREEN}[✓] Resposta completa habilitada.${NC}"
echo ""

WORKSPACE_LIMPO=false

# ==========================================
# LOOP
# ==========================================

while true; do

    TIMESTAMP_MS=$(agora_ms)

    DADOS=$(
        curl -fsS \
            --connect-timeout 5 \
            --max-time 15 \
            "$FIREBASE_URL" \
            2>/dev/null || echo '{}'
    )

    # ======================================
    # LÊ ESTADO
    # ======================================

    PARSED_VALS=$(
        printf '%s' "$DADOS" |
        python3 -c '
import json
import sys
import time

try:
    data=json.load(sys.stdin)

    if not isinstance(data,dict):
        data={}

    action=data.get("action",True)

    if action is False or str(action).lower()=="false":
        action="FALSE"
    else:
        action="TRUE"

    expiration=data.get(
        "expiration",
        int(time.time()*1000)+30000
    )

    try:
        expiration=int(expiration)
    except:
        expiration=int(time.time()*1000)+30000

    print(action)
    print(expiration)

except Exception:
    print("TRUE")
    print(int(time.time()*1000)+30000)
'
    )

    ACTION_VAL=$(printf '%s\n' "$PARSED_VALS" | sed -n '1p')
    EXPIRATION_VAL=$(printf '%s\n' "$PARSED_VALS" | sed -n '2p')

    # ======================================
    # ACTION FALSE
    # ======================================

    if [ "$ACTION_VAL" = "FALSE" ]; then

        echo -e "${RED}[!] action=false recebido.${NC}"

        RESP_FINAL="[!] Ambiente desativado via action=false."

        enviar_resposta "$RESP_FINAL"

        firebase_patch "{
            \"action\":false,
            \"comando\":null,
            \"cmd_ubuntu\":null,
            \"data_hora\":$(agora_ms)
        }"

        rm -rf "$VM_WORKSPACE"

        echo -e "${GREEN}[✓] Workspace removido.${NC}"

        exit 0
    fi

    # ======================================
    # EXPIRAÇÃO
    # ======================================

    if [ "$TIMESTAMP_MS" -ge "$EXPIRATION_VAL" ]; then

        if [ "$WORKSPACE_LIMPO" = "false" ]; then

            echo -e "${YELLOW}[!] Expiração atingida.${NC}"

            rm -rf "$VM_WORKSPACE"
            mkdir -p "$VM_WORKSPACE"

            enviar_resposta \
                "[!] Expiração atingida. Workspace limpo. Aguardando renovação."

            WORKSPACE_LIMPO=true
        fi

        sleep 1
        continue

    else

        WORKSPACE_LIMPO=false
    fi

    # ======================================
    # HEARTBEAT
    # ======================================

    firebase_patch "{
        \"id\":$(printf '%s' "$ID_GERADO" | json_string),
        \"action\":true,
        \"data_hora\":$TIMESTAMP_MS
    }"

    # ======================================
    # EXTRAI COMANDOS
    # ======================================

    CMD=$(
        printf '%s' "$DADOS" |
        python3 -c '
import json,sys

try:
    data=json.load(sys.stdin)
    value=data.get("comando","")

    if value is None:
        value=""

    print(value)

except:
    print("")
'
    )

    CMD_UBUNTU=$(
        printf '%s' "$DADOS" |
        python3 -c '
import json,sys

try:
    data=json.load(sys.stdin)
    value=data.get("cmd_ubuntu","")

    if value is None:
        value=""

    print(value)

except:
    print("")
'
    )

    # ======================================
    # CMD UBUNTU
    # ======================================

    if [ -n "$CMD_UBUNTU" ] && [ "$CMD_UBUNTU" != "null" ]; then

        echo -e "${CYAN}[CMD] $CMD_UBUNTU${NC}"

        # IMPORTANTE:
        # remove antes de executar para impedir
        # execução repetida pelo polling.

        firebase_patch "{
            \"comando\":null,
            \"cmd_ubuntu\":null,
            \"resposta\":\"[⏳] Comando recebido. Executando...\",
            \"data_hora\":$(agora_ms)
        }"

        (
            cd "$VM_WORKSPACE" || exit 1

            # ==================================
            # CAPTURA ABSOLUTAMENTE TUDO
            # stdout + stderr
            # ==================================

            RESPOSTA=$(
                bash -c "$CMD_UBUNTU" 2>&1
            )

            STATUS=$?

            if [ -z "$RESPOSTA" ]; then
                RESPOSTA="[✓] Comando concluído sem saída."
            fi

            RESPOSTA="
[COMANDO]
$CMD_UBUNTU

[SAÍDA COMPLETA]
$RESPOSTA

[EXIT CODE]
$STATUS"

            enviar_resposta "$RESPOSTA"

        ) &

    # ======================================
    # CMD GERAL
    # ======================================

    elif [ -n "$CMD" ] && [ "$CMD" != "null" ]; then

        echo -e "${CYAN}[CMD] $CMD${NC}"

        firebase_patch "{
            \"comando\":null,
            \"cmd_ubuntu\":null,
            \"resposta\":\"[⏳] Comando recebido. Executando...\",
            \"data_hora\":$(agora_ms)
        }"

        (
            cd "$VM_WORKSPACE" || exit 1

            RESPOSTA=$(
                bash -c "$CMD" 2>&1
            )

            STATUS=$?

            if [ -z "$RESPOSTA" ]; then
                RESPOSTA="[✓] Comando concluído sem saída."
            fi

            RESPOSTA="
[COMANDO]
$CMD

[SAÍDA COMPLETA]
$RESPOSTA

[EXIT CODE]
$STATUS"

            enviar_resposta "$RESPOSTA"

        ) &

    fi

    # ======================================
    # POLLING
    # ======================================

    # 500ms evita dezenas/centenas de requisições
    # por segundo e ainda mantém resposta rápida.

    sleep 0.5

done