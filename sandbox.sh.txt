#!/usr/bin/env bash
set +H

# ==========================================
# CONFIGURAÇÃO DE CORES
# ==========================================
RED='\033[0;31m'
GREEN='\033[0;32m'
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

mkdir -p "$SANDBOX_DIR"
mkdir -p "$VM_WORKSPACE"

# ==========================================
# IDENTIFICAÇÃO
# ==========================================
IP_ATUAL=$(curl -s --max-time 10 https://api.ipify.org)

if [ -z "$IP_ATUAL" ]; then
    IP_ATUAL=$(curl -s --max-time 10 https://icanhazip.com)
fi

if [ -z "$IP_ATUAL" ]; then
    IP_ATUAL=$(curl -s --max-time 10 https://ifconfig.me)
fi

[ -z "$IP_ATUAL" ] && IP_ATUAL="127.0.0.1"

IP_SEM_PONTOS=$(echo "$IP_ATUAL" | tr -d '.')
ID_GERADO="ID${IP_SEM_PONTOS}"

FIREBASE_URL="https://amheexvps-default-rtdb.firebaseio.com/STORAGE/${ID_GERADO}/CMD.json"

# ==========================================
# FUNÇÕES
# ==========================================

obter_timestamp() {
    python3 -c 'import time; print(int(time.time() * 1000))'
}

# ------------------------------------------
# ESCAPA TEXTO PARA JSON
# ------------------------------------------
json_escape() {
    python3 -c '
import json
import sys
print(json.dumps(sys.stdin.read()))
'
}

# ------------------------------------------
# ENVIA SOMENTE RESPOSTA
# ------------------------------------------
enviar_resposta() {

    local TEXTO="$1"
    local TIMESTAMP="$2"
    local JSON_TEXTO

    JSON_TEXTO=$(printf '%s' "$TEXTO" | json_escape)

    curl -s \
        --connect-timeout 5 \
        --max-time 15 \
        -X PATCH \
        -H "Content-Type: application/json" \
        -d "{
            \"id\":\"$ID_GERADO\",
            \"action\":true,
            \"resposta\":$JSON_TEXTO,
            \"data_hora\":$TIMESTAMP
        }" \
        "$FIREBASE_URL" \
        > /dev/null 2>&1
}

# ------------------------------------------
# LIMPA SOMENTE A RESPOSTA
# ------------------------------------------
limpar_resposta() {

    local TIMESTAMP="$1"

    curl -s \
        --connect-timeout 5 \
        --max-time 15 \
        -X PATCH \
        -H "Content-Type: application/json" \
        -d "{
            \"id\":\"$ID_GERADO\",
            \"action\":true,
            \"resposta\":\"\",
            \"data_hora\":$TIMESTAMP
        }" \
        "$FIREBASE_URL" \
        > /dev/null 2>&1
}

# ------------------------------------------
# EXECUTA COMANDO COM SAÍDA EM TEMPO REAL
#
# resposta =
#
# [2026-10-07 23:59:01] saída
# [2026-10-07 23:59:02] saída
# [2026-10-07 23:59:03] saída
#
# SOMENTE SAÍDA REAL DO COMANDO.
# ------------------------------------------
executar_stream() {

    local COMANDO="$1"
    local TIPO="$2"

    local BUFFER=""
    local TIMESTAMP
    local DATA_HORA
    local LINHA
    local SAIDA
    local PID

    # ======================================
    # EXECUTA NO WORKSPACE
    # ======================================
    coproc PROCESSO {

        cd "$VM_WORKSPACE" || exit 1

        stdbuf -oL -eL bash -c "$COMANDO" 2>&1

    }

    PID="$PROCESSO_PID"

    # ======================================
    # CAPTURA CADA LINHA EM TEMPO REAL
    # ======================================
    while IFS= read -r LINHA <&"${PROCESSO[0]}"; do

        # Remove CR
        LINHA="${LINHA%$'\r'}"

        # ==================================
        # DATA/HORA EXATA DA SAÍDA
        # ==================================
        DATA_HORA=$(date '+%Y-%m-%d %H:%M:%S')

        # ==================================
        # FORMATO FINAL
        # ==================================
        SAIDA="[$DATA_HORA] $LINHA"

        # ==================================
        # GUARDA HISTÓRICO COMPLETO
        # ==================================
        BUFFER+="$SAIDA"$'\n'

        # ==================================
        # MOSTRA NO TERMINAL
        # ==================================
        printf '%s\n' "$SAIDA"

        # ==================================
        # ENVIA PARA FIREBASE IMEDIATAMENTE
        # ==================================
        TIMESTAMP=$(obter_timestamp)

        enviar_resposta "$BUFFER" "$TIMESTAMP"

    done

    # ======================================
    # ESPERA PROCESSO TERMINAR
    #
    # NÃO ENVIA STATUS.
    # NÃO ENVIA CÓDIGO.
    # NÃO ENVIA "CONCLUÍDO".
    # ======================================
    wait "$PID" 2>/dev/null

    return 0
}

# ==========================================
# AMBIENTE
# ==========================================
export DEBIAN_FRONTEND=noninteractive

# ==========================================
# TIMESTAMP INICIAL
# ==========================================
TIMESTAMP_MS=$(obter_timestamp)

# ==========================================
# EXPIRAÇÃO
# ==========================================
EXPIRATION_DEFAULT=$((TIMESTAMP_MS + (30 * 1000)))

# ==========================================
# REGISTRO INICIAL
#
# IMPORTANTE:
# NÃO COLOCA MENSAGEM EM "resposta".
# ==========================================
curl -s \
    -X PATCH \
    -H "Content-Type: application/json" \
    -d "{
        \"id\":\"$ID_GERADO\",
        \"action\":true,
        \"expiration\":$EXPIRATION_DEFAULT,
        \"data_hora\":$TIMESTAMP_MS
    }" \
    "$FIREBASE_URL" \
    > /dev/null 2>&1

# ==========================================
# INSTALAÇÃO DE DEPENDÊNCIAS
# ==========================================
if ! command -v node >/dev/null 2>&1 || \
   ! command -v python3 >/dev/null 2>&1; then

    echo -e "${YELLOW}[*] Dependências ausentes.${NC}"
    echo -e "${YELLOW}[*] Instalação iniciada.${NC}"

    INST_COMANDO='
apt-get update -y &&
apt-get install -y \
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
tmux
'

    # ======================================
    # LIMPA RESPOSTA ANTES DA INSTALAÇÃO
    # ======================================
    TIMESTAMP_MS=$(obter_timestamp)

    limpar_resposta "$TIMESTAMP_MS"

    # ======================================
    # SAÍDA DO APT VAI DIRETO PARA RESPOSTA
    # ======================================
    executar_stream "$INST_COMANDO" "INSTALACAO"

else

    echo -e "${GREEN}[✓] Dependências já instaladas.${NC}"
fi

# ==========================================
# OBTÉM CONFIGURAÇÃO ATUAL
# ==========================================
DADOS_INICIAIS=$(curl -s "$FIREBASE_URL")

CONFIG_EXISTE=$(python3 -c '
import json
import sys

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

# ==========================================
# GARANTE ACTION / EXPIRATION
# ==========================================
TIMESTAMP_MS=$(obter_timestamp)

PATCH_DATA="{
\"id\":\"$ID_GERADO\",
\"action\":true,
\"data_hora\":$TIMESTAMP_MS
"

if [ "$HAS_EXPIRATION" != "True" ]; then

    PATCH_DATA="$PATCH_DATA,\"expiration\":$EXPIRATION_DEFAULT"

fi

PATCH_DATA="$PATCH_DATA}"

curl -s \
    -X PATCH \
    -H "Content-Type: application/json" \
    -d "$PATCH_DATA" \
    "$FIREBASE_URL" \
    > /dev/null 2>&1

# ==========================================
# INTERFACE VISUAL
# ==========================================
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
echo -e "${GREEN}     [✓] Monitorando comandos em tempo real...${NC}"
echo ""

WORKSPACE_LIMPO=false

# ==========================================
# LOOP PRINCIPAL
# ==========================================
while true; do

    TIMESTAMP_MS=$(obter_timestamp)

    # ======================================
    # LÊ FIREBASE
    # ======================================
    DADOS=$(curl -s "$FIREBASE_URL")

    # ======================================
    # ACTION / EXPIRATION
    # ======================================
    PARSED_VALS=$(python3 -c '
import json
import sys
import time

try:

    data = json.loads(sys.stdin.read())

    current_ms = int(time.time() * 1000)

    if not isinstance(data, dict):

        print(f"TRUE,{current_ms + 30000}")

    else:

        act = data.get("action", True)

        if act is False or str(act).lower() == "false":
            act_str = "FALSE"
        else:
            act_str = "TRUE"

        exp = data.get(
            "expiration",
            current_ms + 30000
        )

        try:
            exp = int(exp)
        except:
            exp = current_ms + 30000

        print(f"{act_str},{exp}")

except:

    current_ms = int(time.time() * 1000)

    print(
        f"TRUE,{current_ms + 30000}"
    )

' <<EOF
$DADOS
EOF
)

    IFS=',' read -r ACTION_VAL EXPIRATION_VAL <<< "$PARSED_VALS"

    # ======================================
    # ACTION FALSE
    # ======================================
    if [ "$ACTION_VAL" = "FALSE" ]; then

        echo -e "\n${RED}[!] Script desativado via Firebase.${NC}"

        # NÃO coloca mensagem em resposta
        TIMESTAMP_MS=$(obter_timestamp)

        curl -s \
            -X PATCH \
            -H "Content-Type: application/json" \
            -d "{
                \"id\":\"$ID_GERADO\",
                \"action\":false,
                \"data_hora\":$TIMESTAMP_MS
            }" \
            "$FIREBASE_URL" \
            > /dev/null 2>&1

        rm -rf "$VM_WORKSPACE"

        echo -e "${GREEN}[✓] Workspace limpo.${NC}"
        echo -e "${GREEN}[✓] Encerrando.${NC}"

        exit 0
    fi

    # ======================================
    # EXPIRAÇÃO
    # ======================================
    if [ "$TIMESTAMP_MS" -ge "$EXPIRATION_VAL" ]; then

        if [ "$WORKSPACE_LIMPO" = "false" ]; then

            echo -e "\n${YELLOW}[!] Tempo expirado. Limpando workspace...${NC}"

            rm -rf "$VM_WORKSPACE"
            mkdir -p "$VM_WORKSPACE"

            # NÃO altera resposta
            curl -s \
                -X PATCH \
                -H "Content-Type: application/json" \
                -d "{
                    \"id\":\"$ID_GERADO\",
                    \"action\":true,
                    \"data_hora\":$TIMESTAMP_MS
                }" \
                "$FIREBASE_URL" \
                > /dev/null 2>&1

            WORKSPACE_LIMPO=true

        else

            curl -s \
                -X PATCH \
                -H "Content-Type: application/json" \
                -d "{
                    \"id\":\"$ID_GERADO\",
                    \"action\":true,
                    \"data_hora\":$TIMESTAMP_MS
                }" \
                "$FIREBASE_URL" \
                > /dev/null 2>&1

        fi

        sleep 1
        continue

    else

        WORKSPACE_LIMPO=false

    fi

    # ======================================
    # HEARTBEAT
    # ======================================
    curl -s \
        -X PATCH \
        -H "Content-Type: application/json" \
        -d "{
            \"id\":\"$ID_GERADO\",
            \"action\":true,
            \"data_hora\":$TIMESTAMP_MS
        }" \
        "$FIREBASE_URL" \
        > /dev/null 2>&1

    # ======================================
    # EXTRAI COMANDO
    # ======================================
    CMD=$(python3 -c '
import json
import sys

try:

    data = json.loads(sys.stdin.read())

    val = data.get("comando", "")

    if val:
        print(
            val.replace("\\n", "\n")
        )

except:

    pass

' <<EOF
$DADOS
EOF
)

    # ======================================
    # EXTRAI CMD UBUNTU
    # ======================================
    CMD_UBUNTU=$(python3 -c '
import json
import sys

try:

    data = json.loads(sys.stdin.read())

    val = data.get("cmd_ubuntu", "")

    if val:
        print(
            val.replace("\\n", "\n")
        )

except:

    pass

' <<EOF
$DADOS
EOF
)

    # ======================================
    # CMD UBUNTU
    # ======================================
    if [ -n "$CMD_UBUNTU" ] && \
       [ "$CMD_UBUNTU" != "null" ]; then

        echo ""
        echo -e "${CYAN}╔══════════════════════════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║               NOVO COMANDO UBUNTU                       ║${NC}"
        echo -e "${CYAN}╚══════════════════════════════════════════════════════════╝${NC}"
        echo -e "${WHITE}$CMD_UBUNTU${NC}"
        echo ""

        # ==================================
        # LIMPA RESPOSTA ANTERIOR
        # ==================================
        TIMESTAMP_MS=$(obter_timestamp)

        limpar_resposta "$TIMESTAMP_MS"

        # ==================================
        # REMOVE COMANDO DO FIREBASE
        # ==================================
        curl -s \
            -X PATCH \
            -H "Content-Type: application/json" \
            -d "{
                \"id\":\"$ID_GERADO\",
                \"action\":true,
                \"comando\":null,
                \"cmd_ubuntu\":null,
                \"data_hora\":$TIMESTAMP_MS
            }" \
            "$FIREBASE_URL" \
            > /dev/null 2>&1

        # ==================================
        # EXECUTA EM BACKGROUND
        # ==================================
        executar_stream "$CMD_UBUNTU" "UBUNTU" &

    # ======================================
    # CMD GERAL
    # ======================================
    elif [ -n "$CMD" ] && \
         [ "$CMD" != "null" ]; then

        echo ""
        echo -e "${CYAN}╔══════════════════════════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║                  NOVO COMANDO                           ║${NC}"
        echo -e "${CYAN}╚══════════════════════════════════════════════════════════╝${NC}"
        echo -e "${WHITE}$CMD${NC}"
        echo ""

        # ==================================
        # LIMPA RESPOSTA ANTERIOR
        # ==================================
        TIMESTAMP_MS=$(obter_timestamp)

        limpar_resposta "$TIMESTAMP_MS"

        # ==================================
        # REMOVE COMANDO DO FIREBASE
        # ==================================
        curl -s \
            -X PATCH \
            -H "Content-Type: application/json" \
            -d "{
                \"id\":\"$ID_GERADO\",
                \"action\":true,
                \"comando\":null,
                \"data_hora\":$TIMESTAMP_MS
            }" \
            "$FIREBASE_URL" \
            > /dev/null 2>&1

        # ==================================
        # EXECUTA EM BACKGROUND
        # ==================================
        executar_stream "$CMD" "GERAL" &

    fi

    # ======================================
    # LOOP
    # ======================================
    sleep 0.01

done