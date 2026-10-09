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

echo -e "${GREEN}[✓] Configuração automática definida: ${QTD_SANDBOX} sandbox(es) com IDs fixos...${NC}"
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
texto = sys.stdin.read()
texto = texto.replace("/tmp/sandbox#", "root@AMHEEX-VPS ~#")
print(json.dumps(texto))
'
}

FIREBASE_LISTA_URL="https://amheexvps-default-rtdb.firebaseio.com/STORAGE/active_sandboxes.json"

export DEBIAN_FRONTEND=noninteractive

if ! command -v tmux >/dev/null 2>&1; then
    apt-get update -y && apt-get install -y tmux >/dev/null 2>&1
fi

declare -a ARRAY_SANDBOX_IDS=()

# ==========================================
# FUNÇÃO PARA CRIAR TODAS AS SANDBOXES INICIAIS
# ==========================================
iniciar_todas_sandboxes() {
    IP_ATUAL=$(curl -s --max-time 10 https://api.ipify.org)
    [ -z "$IP_ATUAL" ] && IP_ATUAL=$(curl -s --max-time 10 https://icanhazip.com)
    [ -z "$IP_ATUAL" ] && IP_ATUAL="127.0.0.1"

    ARRAY_SANDBOX_IDS=()
    TIMESTAMP_BASE=$(obter_timestamp)

    for ((i=1; i<=QTD_SANDBOX; i++)); do
        TMUX_SESSION="sandbox_ubuntu_$i"
        
        SANDBOX_ID="ID${TIMESTAMP_BASE}-$i"
        
        if ! tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
            tmux new-session -d -s "$TMUX_SESSION" -c "$VM_WORKSPACE"
            tmux send-keys -t "$TMUX_SESSION" "export PS1='root@AMHEEX-VPS-$i ~# '" Enter
        fi
        
        ARRAY_SANDBOX_IDS+=("$SANDBOX_ID")

        local FIREBASE_SB_URL="https://amheexvps-default-rtdb.firebaseio.com/STORAGE/${SANDBOX_ID}/CMD.json"
        curl -s \
            -X PATCH \
            -H "Content-Type: application/json" \
            -d "{
                \"id\":\"$SANDBOX_ID\",
                \"expiration\":0,
                \"data_hora\":$TIMESTAMP_BASE,
                \"comando\":null,
                \"resposta\":\"\"
            }" \
            "$FIREBASE_SB_URL" \
            > /dev/null 2>&1
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
    echo -e "${BLUE}     │  ${GREEN}● ONLINE${BLUE}        ${CYAN}QTD: ${QTD_SANDBOX}${BLUE}    ${YELLOW}IDS FIXOS (AGUARDANDO)${BLUE}│${NC}"
    echo -e "${BLUE}     └──────────────────────────────────────────────────┘${NC}"
    echo ""
    echo -e "${WHITE}     🔹 IP Público : ${CYAN}$IP_ATUAL${NC}"
    echo -e "${WHITE}     🔹 Lista Ativa: ${CYAN}$JSON_IDS${NC}"
    echo ""
    echo -e "${GREEN}     [✓] Monitoramento e execução de comandos ativo...${NC}"
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

reiniciar_sandbox_isolada() {
    local INDEX="$1"
    local SB_ID="${ARRAY_SANDBOX_IDS[$INDEX]}"
    local SB_NUM=$((INDEX + 1))
    local TIMESTAMP_NOW
    TIMESTAMP_NOW=$(obter_timestamp)
    
    local TMUX_SESSION="sandbox_ubuntu_$SB_NUM"

    echo -e "\n${YELLOW}[!] Sandbox $SB_NUM ($SB_ID) expirou. Resetando...${NC}"

    if tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
        tmux kill-session -t "$TMUX_SESSION" 2>/dev/null
    fi
    
    tmux new-session -d -s "$TMUX_SESSION" -c "$VM_WORKSPACE"
    tmux send-keys -t "$TMUX_SESSION" "export PS1='root@AMHEEX-VPS-$SB_NUM ~# '" Enter

    local FIREBASE_SB_URL="https://amheexvps-default-rtdb.firebaseio.com/STORAGE/${SB_ID}/CMD.json"
    curl -s \
        -X PATCH \
        -H "Content-Type: application/json" \
        -d "{
            \"id\":\"$SB_ID\",
            \"expiration\":0,
            \"data_hora\":$TIMESTAMP_NOW,
            \"comando\":null,
            \"resposta\":\"\"
        }" \
        "$FIREBASE_SB_URL" \
        > /dev/null 2>&1
}

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

            echo -e "${GREEN}[✓] Executando comando na sandbox ${SB_ID}: $CMD${NC}"

            if ! tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
                tmux new-session -d -s "$TMUX_SESSION" -c "$VM_WORKSPACE"
                tmux send-keys -t "$TMUX_SESSION" "export PS1='root@AMHEEX-VPS-$SB_NUM ~# '" Enter
            fi

            # Envia o comando respeitando as linhas e garantindo o Enter final
            ultimo_caractere="${CMD: -1}"
            
            while IFS= read -r linha_cmd || [ -n "$linha_cmd" ]; do
                if [ -n "$linha_cmd" ]; then
                    tmux send-keys -t "$TMUX_SESSION" "$linha_cmd" Enter
                else
                    tmux send-keys -t "$TMUX_SESSION" Enter
                fi
            done <<EOF
$CMD
EOF

            if [ "$ultimo_caractere" != $'\n' ] && [ "$ultimo_caractere" != $'\r' ]; then
                tmux send-keys -t "$TMUX_SESSION" Enter
            fi
            
            # Aguarda o comando processar no terminal
            sleep 0.6

            # Captura a tela do tmux limpa e trata os caminhos do prompt
            SAIDA_LIMPA=$(python3 -c '
import subprocess
import sys

session_name = sys.argv[1]
try:
    out = subprocess.check_output(["tmux", "capture-pane", "-t", session_name, "-p", "-S", "-1000"]).decode("utf-8")
    
    # Substituições corretas para manter o padrão visual limpo
    out = out.replace("/tmp/sandbox#", "root@AMHEEX-VPS ~#")
    out = out.replace("/tmp/sandbox$", "root@AMHEEX-VPS ~#")
    
    # Remove linhas vazias excessivas no topo ou base se houver
    linhas = [l.rstrip() for l in out.splitlines()]
    while linhas and not linhas[0]:
        linhas.pop(0)
    while linhas and not linhas[-1]:
        linhas.pop()
        
    print("\n".join(linhas))
except Exception as e:
    print(str(e))
' "$TMUX_SESSION")

            TIMESTAMP_FIM=$(obter_timestamp)
            enviar_resposta "$SB_ID" "$SAIDA_LIMPA" "$TIMESTAMP_FIM"
        fi
    done

    sleep 0.1

done
