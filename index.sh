#!/usr/bin/env bash
set +H

# ==========================================
# CONFIGURAÇÃO FIXA (EDITE AQUI SE QUISER MUDAR)
# ==========================================
QTD_SANDBOX_FIXA=5

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

clear
echo -e "${BLUE}     ┌──────────────────────────────────────────────────┐${NC}"
echo -e "${BLUE}     │  ${WHITE}INFINITE LABS / GOOGLE SHELL SANDBOX${BLUE}          │${NC}"
echo -e "${BLUE}     └──────────────────────────────────────────────────┘${NC}"
echo ""

QTD_SANDBOX=${QTD_SANDBOX_FIXA}

echo -e "${GREEN}[✓] Configuração automática definida: ${QTD_SANDBOX} sandbox(es) aguardando expiration...${NC}"
sleep 1

# ==========================================
# DIRETÓRIOS E AMBIENTE
# ==========================================
SANDBOX_DIR="$HOME/.sandbox"
VM_WORKSPACE="/tmp/sandbox"
DIR_FILE="$SANDBOX_DIR/current_dir"

mkdir -p "$SANDBOX_DIR"
mkdir -p "$VM_WORKSPACE"

if [ ! -f "$DIR_FILE" ]; then
    echo "$VM_WORKSPACE" > "$DIR_FILE"
fi

obter_timestamp() {
    python3 -c 'import time; print(int(time.time() * 1000))'
}

json_escape() {
    python3 -c '
import json
import sys
print(json.dumps(sys.stdin.read()))
'
}

FIREBASE_LISTA_URL="https://amheexvps-default-rtdb.firebaseio.com/STORAGE/active_sandboxes.json"

export DEBIAN_FRONTEND=noninteractive

if ! command -v tmux >/dev/null 2>&1; then
    apt-get update -y && apt-get install -y tmux >/dev/null 2>&1
fi

# Arrays globais para rastrear os IDs próprios e sessões individualmente
declare -a ARRAY_SANDBOX_IDS=()

# ==========================================
# FUNÇÃO PARA CRIAR TODAS AS SANDBOXES INICIAIS
# ==========================================
iniciar_todas_sandboxes() {
    IP_ATUAL=$(curl -s --max-time 10 https://api.ipify.org)
    [ -z "$IP_ATUAL" ] && IP_ATUAL=$(curl -s --max-time 10 https://icanhazip.com)
    [ -z "$IP_ATUAL" ] && IP_ATUAL="127.0.0.1"

    ARRAY_SANDBOX_IDS=()
    TIMESTAMP_NOW=$(obter_timestamp)

    for ((i=1; i<=QTD_SANDBOX; i++)); do
        TMUX_SESSION="sandbox_ubuntu_$i"
        
        TS_UNICO=$(obter_timestamp)
        SANDBOX_ID="ID${TS_UNICO}-$i"
        
        if ! tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
            tmux new-session -d -s "$TMUX_SESSION" -c "$VM_WORKSPACE"
            tmux send-keys -t "$TMUX_SESSION" "export PS1='root@AMHEEX-VPS-$i ~# '" Enter
        fi
        
        ARRAY_SANDBOX_IDS+=("$SANDBOX_ID")

        # Inicia com expiration = 0 (aguardando o sistema externo definir o tempo)
        local FIREBASE_SB_URL="https://amheexvps-default-rtdb.firebaseio.com/STORAGE/${SANDBOX_ID}/CMD.json"
        curl -s \
            -X PATCH \
            -H "Content-Type: application/json" \
            -d "{
                \"id\":\"$SANDBOX_ID\",
                \"expiration\":0,
                \"data_hora\":$TS_UNICO,
                \"comando\":null,
                \"resposta\":\"\"
            }" \
            "$FIREBASE_SB_URL" \
            > /dev/null 2>&1
            
        sleep 0.05
    done

    JSON_IDS=$(python3 -c '
import json
import sys
ids = sys.argv[1:]
print(json.dumps(ids))
' "${ARRAY_SANDBOX_IDS[@]}")

    curl -s \
        -X PATCH \
        -H "Content-Type: application/json" \
        -d "{\"sandbox_id\": $JSON_IDS}" \
        "$FIREBASE_LISTA_URL" \
        > /dev/null 2>&1

    clear
    echo -e "${BLUE}     ┌──────────────────────────────────────────────────┐${NC}"
    echo -e "${BLUE}     │  ${WHITE}INFINITE LABS / GOOGLE SHELL SANDBOX${BLUE}          │${NC}"
    echo -e "${BLUE}     │                                                  │${NC}"
    echo -e "${BLUE}     │  ${GREEN}● ONLINE${BLUE}        ${CYAN}QTD: ${QTD_SANDBOX}${BLUE}    ${YELLOW}AGUARDANDO EXPIRATION${BLUE}│${NC}"
    echo -e "${BLUE}     └──────────────────────────────────────────────────┘${NC}"
    echo ""
    echo -e "${WHITE}     🔹 IP Público : ${CYAN}$IP_ATUAL${NC}"
    echo -e "${WHITE}     🔹 Lista Ativa: ${CYAN}$JSON_IDS${NC}"
    echo ""
    echo -e "${GREEN}     [✓] Aguardando definição de expiration no Firebase...${NC}"
    echo ""
}

# ==========================================
# FUNÇÕES DE RESPOSTA E LIMPEZA INDIVIDUAL
# ==========================================
enviar_resposta() {
    local SB_ID="$1"
    local TEXTO="$2"
    local TIMESTAMP="$3"
    local JSON_TEXTO

    JSON_TEXTO=$(printf '%s' "$TEXTO" | json_escape)
    local FIREBASE_SB_URL="https://amheexvps-default-rtdb.firebaseio.com/STORAGE/${SB_ID}/CMD.json"

    curl -s \
        --connect-timeout 2 \
        --max-time 5 \
        -X PATCH \
        -H "Content-Type: application/json" \
        -d "{
            \"id\":\"$SB_ID\",
            \"resposta\":$JSON_TEXTO,
            \"data_hora\":$TIMESTAMP
        }" \
        "$FIREBASE_SB_URL" \
        > /dev/null 2>&1
}

limpar_resposta() {
    local SB_ID="$1"
    local TIMESTAMP="$2"
    local FIREBASE_SB_URL="https://amheexvps-default-rtdb.firebaseio.com/STORAGE/${SB_ID}/CMD.json"

    curl -s \
        --connect-timeout 2 \
        --max-time 5 \
        -X PATCH \
        -H "Content-Type: application/json" \
        -d "{
            \"id\":\"$SB_ID\",
            \"resposta\":\"\",
            \"data_hora\":$TIMESTAMP
        }" \
        "$FIREBASE_SB_URL" \
        > /dev/null 2>&1
}

# Reseta e recria APENAS a sandbox específica com expiration 0 (aguardando novo tempo)
reiniciar_sandbox_isolada() {
    local INDEX="$1"
    local OLD_SB_ID="${ARRAY_SANDBOX_IDS[$INDEX]}"
    local SB_NUM=$((INDEX + 1))
    local TIMESTAMP_NOW
    TIMESTAMP_NOW=$(obter_timestamp)
    
    local NEW_SB_ID="ID${TIMESTAMP_NOW}-$SB_NUM"
    local TMUX_SESSION="sandbox_ubuntu_$SB_NUM"

    echo -e "\n${YELLOW}[!] Sandbox $SB_NUM ($OLD_SB_ID) expirou. Recriando e aguardando novo expiration...${NC}"

    curl -s -X DELETE "https://amheexvps-default-rtdb.firebaseio.com/STORAGE/${OLD_SB_ID}.json" > /dev/null 2>&1

    # Mata apenas se a sessão tmux existir
    if tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
        tmux kill-session -t "$TMUX_SESSION" 2>/dev/null
    fi
    
    tmux new-session -d -s "$TMUX_SESSION" -c "$VM_WORKSPACE"
    tmux send-keys -t "$TMUX_SESSION" "export PS1='root@AMHEEX-VPS-$SB_NUM ~# '" Enter

    ARRAY_SANDBOX_IDS[$INDEX]="$NEW_SB_ID"

    # Inicializa com expiration = 0 aguardando
    local FIREBASE_SB_URL="https://amheexvps-default-rtdb.firebaseio.com/STORAGE/${NEW_SB_ID}/CMD.json"
    curl -s \
        -X PATCH \
        -H "Content-Type: application/json" \
        -d "{
            \"id\":\"$NEW_SB_ID\",
            \"expiration\":0,
            \"data_hora\":$TIMESTAMP_NOW,
            \"comando\":null,
            \"resposta\":\"\"
        }" \
        "$FIREBASE_SB_URL" \
        > /dev/null 2>&1

    JSON_IDS=$(python3 -c '
import json
import sys
ids = sys.argv[1:]
print(json.dumps(ids))
' "${ARRAY_SANDBOX_IDS[@]}")

    curl -s \
        -X PATCH \
        -H "Content-Type: application/json" \
        -d "{\"sandbox_id\": $JSON_IDS}" \
        "$FIREBASE_LISTA_URL" \
        > /dev/null 2>&1
}

# Inicializa todas as sandboxes aguardando no começo
iniciar_todas_sandboxes

# ==========================================
# LOOP PRINCIPAL DO SERVIDOR (100ms)
# ==========================================
while true; do
    TIMESTAMP_MS=$(obter_timestamp)

    for i in "${!ARRAY_SANDBOX_IDS[@]}"; do
        SB_ID="${ARRAY_SANDBOX_IDS[$i]}"
        SB_NUM=$((i + 1))
        TMUX_SESSION="sandbox_ubuntu_$SB_NUM"
        SB_FIREBASE_URL="https://amheexvps-default-rtdb.firebaseio.com/STORAGE/${SB_ID}/CMD.json"

        SB_DADOS=$(curl -s "$SB_FIREBASE_URL")

        EXPIRATION_VAL=$(python3 -c '
import json
import sys
try:
    data = json.loads(sys.stdin.read())
    if not isinstance(data, dict):
        print("0")
    else:
        exp = data.get("expiration", 0)
        print(str(int(exp)))
except:
    print("0")
' <<EOF
$SB_DADOS
EOF
)

        # Só expira se expiration for maior que 0 E o tempo atual passou do expiration
        if [ "$EXPIRATION_VAL" -gt 0 ] && [ "$TIMESTAMP_MS" -ge "$EXPIRATION_VAL" ]; then
            reiniciar_sandbox_isolada "$i"
            continue
        fi

        curl -s \
            -X PATCH \
            -H "Content-Type: application/json" \
            -d "{
                \"id\":\"$SB_ID\",
                \"data_hora\":$TIMESTAMP_MS
            }" \
            "$SB_FIREBASE_URL" \
            > /dev/null 2>&1

        CMD=$(python3 -c '
import json
import sys
try:
    data = json.loads(sys.stdin.read())
    val = data.get("comando", "")
    if val:
        print(val)
except:
    pass
' <<EOF
$SB_DADOS
EOF
)

        if [ -n "$CMD" ] && [ "$CMD" != "null" ]; then
            limpar_resposta "$SB_ID" "$TIMESTAMP_MS"

            curl -s \
                -X PATCH \
                -H "Content-Type: application/json" \
                -d "{
                    \"id\":\"$SB_ID\",
                    \"comando\":null,
                    \"data_hora\":$TIMESTAMP_MS
                }" \
                "$SB_FIREBASE_URL" \
                > /dev/null 2>&1

            echo -e "${GREEN}[✓] Comando executado na partição isolada ${SB_ID}.${NC}"

            if ! tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
                tmux new-session -d -s "$TMUX_SESSION" -c "$VM_WORKSPACE"
                tmux send-keys -t "$TMUX_SESSION" "export PS1='root@AMHEEX-VPS-$SB_NUM ~# '" Enter
            fi

            tmux send-keys -t "$TMUX_SESSION" "$CMD" Enter
            
            sleep 0.3

            SAIDA_LIMPA=$(python3 -c '
import subprocess
import sys

session_name = sys.argv[1]
try:
    out = subprocess.check_output(["tmux", "capture-pane", "-t", session_name, "-p", "-S", "-30"]).decode("utf-8")
    linhas = out.splitlines()
    
    linhas_limpas = []
    for l in linhas:
        stripped = l.strip()
        if "root@AMHEEX-VPS" in stripped or not stripped:
            continue
        linhas_limpas.append(l)
        
    print("\n".join(linhas_limpas).strip())
except Exception as e:
    print(str(e))
' "$TMUX_SESSION")

            TIMESTAMP_FIM=$(obter_timestamp)
            enviar_resposta "$SB_ID" "$SAIDA_LIMPA" "$TIMESTAMP_FIM"
        fi
    done

    sleep 0.1

done
