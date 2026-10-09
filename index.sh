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

clear
echo -e "${BLUE}     ┌──────────────────────────────────────────────────┐${NC}"
echo -e "${BLUE}     │  ${WHITE}INFINITE LABS / GOOGLE SHELL SANDBOX${BLUE}          │${NC}"
echo -e "${BLUE}     └──────────────────────────────────────────────────┘${NC}"
echo ""

# Pergunta quantas sandboxes deseja abrir (configuração inicial)
read -p "$(echo -e "${YELLOW}Quantas sandboxes deseja abrir? (Padrão: 1): ${NC}")" QTD_SANDBOX
QTD_SANDBOX=${QTD_SANDBOX:-1}

echo -e "${GREEN}[✓] Configuração definida: ${QTD_SANDBOX} sandbox(es)...${NC}"
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

# ==========================================
# FUNÇÃO PARA CRIAR/INICIALIZAR SANDBOXES
# ==========================================
iniciar_novas_sandboxes() {
    TIMESTAMP_INICIAL=$(obter_timestamp)
    ID_GERADO="ID${TIMESTAMP_INICIAL}"

    IP_ATUAL=$(curl -s --max-time 10 https://api.ipify.org)
    [ -z "$IP_ATUAL" ] && IP_ATUAL=$(curl -s --max-time 10 https://icanhazip.com)
    [ -z "$IP_ATUAL" ] && IP_ATUAL="127.0.0.1"

    FIREBASE_URL="https://amheexvps-default-rtdb.firebaseio.com/STORAGE/${ID_GERADO}/CMD.json"

    declare -a ARRAY_SANDBOX_IDS=()

    # Criação das sandboxes respeitando o limite configurado
    for ((i=1; i<=QTD_SANDBOX; i++)); do
        TMUX_SESSION="sandbox_ubuntu_$i"
        
        if ! tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
            tmux new-session -d -s "$TMUX_SESSION" -c "$VM_WORKSPACE"
            tmux send-keys -t "$TMUX_SESSION" "export PS1='root@AMHEEX-VPS-$i ~# '" Enter
        fi
        
        ARRAY_SANDBOX_IDS+=("$ID_GERADO-$i")
    done

    JSON_IDS=$(python3 -c '
import json
import sys
ids = sys.argv[1:]
print(json.dumps(ids))
' "${ARRAY_SANDBOX_IDS[@]}")

    EXPIRATION_DEFAULT=$((TIMESTAMP_INICIAL + (30 * 1000)))

    # Envia dados principais para o Firebase
    curl -s \
        -X PATCH \
        -H "Content-Type: application/json" \
        -d "{
            \"id\":\"$ID_GERADO\",
            \"expiration\":$EXPIRATION_DEFAULT,
            \"data_hora\":$TIMESTAMP_INICIAL,
            \"qtd_sandbox\":$QTD_SANDBOX
        }" \
        "$FIREBASE_URL" \
        > /dev/null 2>&1

    # Atualiza a lista unificada de sandbox_id ativas
    curl -s \
        -X PATCH \
        -H "Content-Type: application/json" \
        -d "{\"sandbox_id\": $JSON_IDS, \"servidor_ativo\": \"$ID_GERADO\"}" \
        "$FIREBASE_LISTA_URL" \
        > /dev/null 2>&1

    clear
    echo -e "${BLUE}     ┌──────────────────────────────────────────────────┐${NC}"
    echo -e "${BLUE}     │  ${WHITE}INFINITE LABS / GOOGLE SHELL SANDBOX${BLUE}          │${NC}"
    echo -e "${BLUE}     │                                                  │${NC}"
    echo -e "${BLUE}     │  ${GREEN}● ONLINE${BLUE}        ${CYAN}QTD: ${QTD_SANDBOX}${BLUE}    ${YELLOW}TMUX ATIVAS${BLUE}         │${NC}"
    echo -e "${BLUE}     └──────────────────────────────────────────────────┘${NC}"
    echo ""
    echo -e "${WHITE}     🔹 IP Público : ${CYAN}$IP_ATUAL${NC}"
    echo -e "${WHITE}     🔹 ID Atual   : ${CYAN}$ID_GERADO${NC}"
    echo -e "${WHITE}     🔹 Lista Ativa: ${CYAN}$JSON_IDS${NC}"
    echo ""
    echo -e "${GREEN}     [✓] Monitoramento ativo...${NC}"
    echo ""
}

# ==========================================
# FUNÇÕES DE RESPOSTA E LIMPEZA
# ==========================================
enviar_resposta() {
    local TEXTO="$1"
    local TIMESTAMP="$2"
    local JSON_TEXTO

    JSON_TEXTO=$(printf '%s' "$TEXTO" | json_escape)

    curl -s \
        --connect-timeout 2 \
        --max-time 5 \
        -X PATCH \
        -H "Content-Type: application/json" \
        -d "{
            \"id\":\"$ID_GERADO\",
            \"resposta\":$JSON_TEXTO,
            \"data_hora\":$TIMESTAMP
        }" \
        "$FIREBASE_URL" \
        > /dev/null 2>&1
}

limpar_resposta() {
    local TIMESTAMP="$1"

    curl -s \
        --connect-timeout 2 \
        --max-time 5 \
        -X PATCH \
        -H "Content-Type: application/json" \
        -d "{
            \"id\":\"$ID_GERADO\",
            \"resposta\":\"\",
            \"data_hora\":$TIMESTAMP
        }" \
        "$FIREBASE_URL" \
        > /dev/null 2>&1
}

forcar_limpeza_total() {
    local MOTIVO="$1"
    local TIMESTAMP
    TIMESTAMP=$(obter_timestamp)
    
    enviar_resposta "[SISTEMA: $MOTIVO - Apagando sessões e limpando arquivos...]" "$TIMESTAMP"

    # Mata todas as sessões do tmux e limpa arquivos completamente
    tmux kill-server 2>/dev/null
    pkill -9 tmux 2>/dev/null
    rm -rf "$VM_WORKSPACE"
    rm -rf "$SANDBOX_DIR"
    mkdir -p "$SANDBOX_DIR"
    mkdir -p "$VM_WORKSPACE"
}

# Inicializa o primeiro ciclo de sandboxes
iniciar_novas_sandboxes

# ==========================================
# LOOP PRINCIPAL DO SERVIDOR (100ms)
# ==========================================
while true; do
    TIMESTAMP_MS=$(obter_timestamp)
    DADOS=$(curl -s "$FIREBASE_URL")

    PARSED_VALS=$(python3 -c '
import json
import sys
import time
try:
    data = json.loads(sys.stdin.read())
    current_ms = int(time.time() * 1000)
    if not isinstance(data, dict):
        print(f"{current_ms + 30000}")
    else:
        exp = data.get("expiration", current_ms + 30000)
        try:
            exp = int(exp)
        except:
            exp = current_ms + 30000
        print(f"{exp}")
except:
    current_ms = int(time.time() * 1000)
    print(f"{current_ms + 30000}")
' <<EOF
$DADOS
EOF
)

    EXPIRATION_VAL="$PARSED_VALS"

    # Se o tempo expirou: Apaga todas as sessões/arquivos e cria a próxima sandbox sem parar o script
    if [ "$TIMESTAMP_MS" -ge "$EXPIRATION_VAL" ]; then
        echo -e "\n${YELLOW}[!] Tempo expirado. Apagando sessões antigas e criando nova sandbox...${NC}"
        forcar_limpeza_total "TEMPO EXPIRADO"
        iniciar_novas_sandboxes
        continue
    fi

    # Atualiza o data_hora do servidor
    curl -s \
        -X PATCH \
        -H "Content-Type: application/json" \
        -d "{
            \"id\":\"$ID_GERADO\",
            \"data_hora\":$TIMESTAMP_MS
        }" \
        "$FIREBASE_URL" \
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
$DADOS
EOF
)

    if [ -n "$CMD" ] && [ "$CMD" != "null" ]; then
        TIMESTAMP_MS=$(obter_timestamp)
        limpar_resposta "$TIMESTAMP_MS"

        curl -s \
            -X PATCH \
            -H "Content-Type: application/json" \
            -d "{
                \"id\":\"$ID_GERADO\",
                \"comando\":null,
                \"data_hora\":$TIMESTAMP_MS
            }" \
            "$FIREBASE_URL" \
            > /dev/null 2>&1

        echo -e "${GREEN}[✓] Comando executado nas sandboxes.${NC}"

        TMUX_SESSION="sandbox_ubuntu_1"
        if ! tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
            tmux new-session -d -s "$TMUX_SESSION" -c "$VM_WORKSPACE"
            tmux send-keys -t "$TMUX_SESSION" "export PS1='root@AMHEEX-VPS-1 ~# '" Enter
        fi

        tmux send-keys -t "$TMUX_SESSION" "$CMD" Enter
        
        sleep 0.3

        SAIDA_LIMPA=$(python3 -c '
import subprocess
import re

try:
    out = subprocess.check_output(["tmux", "capture-pane", "-t", "sandbox_ubuntu_1", "-p", "-S", "-30"]).decode("utf-8")
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
')

        TIMESTAMP_MS=$(obter_timestamp)
        enviar_resposta "$SAIDA_LIMPA" "$TIMESTAMP_MS"
    fi

    sleep 0.1

done
