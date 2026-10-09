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

# Pergunta quantas sandboxes deseja abrir
read -p "$(echo -e "${YELLOW}Quantas sandboxes deseja abrir? (Padrão: 1): ${NC}")" QTD_SANDBOX
QTD_SANDBOX=${QTD_SANDBOX:-1}

echo -e "${GREEN}[✓] Configurando ${QTD_SANDBOX} sandbox(es)...${NC}"
sleep 1

# ==========================================
# DIRETÓRIOS E AMBIENTE
# ==========================================
SANDBOX_DIR="$HOME/.sandbox"
VM_WORKSPACE="/tmp/sandbox"
DIR_FILE="$SANDBOX_DIR/current_dir"
TMUX_SESSION="sandbox_ubuntu"

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

# ------------------------------------------
# FUNÇÃO PARA INICIALIZAR OU REINICIAR A SANDBOX
# ------------------------------------------
iniciar_sandbox() {
    TIMESTAMP_INICIAL=$(obter_timestamp)
    ID_GERADO="ID${TIMESTAMP_INICIAL}"

    IP_ATUAL=$(curl -s --max-time 10 https://api.ipify.org)
    [ -z "$IP_ATUAL" ] && IP_ATUAL=$(curl -s --max-time 10 https://icanhazip.com)
    [ -z "$IP_ATUAL" ] && IP_ATUAL="127.0.0.1"

    FIREBASE_URL="https://amheexvps-default-rtdb.firebaseio.com/STORAGE/${ID_GERADO}/CMD.json"

    export DEBIAN_FRONTEND=noninteractive

    if ! command -v tmux >/dev/null 2>&1; then
        apt-get update -y && apt-get install -y tmux >/dev/null 2>&1
    fi

    mkdir -p "$VM_WORKSPACE"
    mkdir -p "$SANDBOX_DIR"

    # Garante que a sessão tmux existe e define o PS1 personalizado
    if ! tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
        tmux new-session -d -s "$TMUX_SESSION" -c "$VM_WORKSPACE"
        tmux send-keys -t "$TMUX_SESSION" "export PS1='root@AMHEEX-VPS ~# '" Enter
    fi

    EXPIRATION_DEFAULT=$((TIMESTAMP_INICIAL + (30 * 1000)))

    curl -s \
        -X PATCH \
        -H "Content-Type: application/json" \
        -d "{
            \"id\":\"$ID_GERADO\",
            \"action\":true,
            \"expiration\":$EXPIRATION_DEFAULT,
            \"data_hora\":$TIMESTAMP_INICIAL,
            \"qtd_sandbox\":$QTD_SANDBOX
        }" \
        "$FIREBASE_URL" \
        > /dev/null 2>&1

    clear
    echo -e "${BLUE}     ┌──────────────────────────────────────────────────┐${NC}"
    echo -e "${BLUE}     │  ${WHITE}INFINITE LABS / GOOGLE SHELL SANDBOX${BLUE}          │${NC}"
    echo -e "${BLUE}     │                                                  │${NC}"
    echo -e "${BLUE}     │  ${GREEN}● ONLINE${BLUE}        ${CYAN}QTD: ${QTD_SANDBOX}${BLUE}    ${YELLOW}TMUX SESSÃO ATIVA${BLUE}   │${NC}"
    echo -e "${BLUE}     └──────────────────────────────────────────────────┘${NC}"
    echo ""
    echo -e "${WHITE}     🔹 IP Público : ${CYAN}$IP_ATUAL${NC}"
    echo -e "${WHITE}     🔹 ID Firebase: ${CYAN}$ID_GERADO${NC}"
    echo -e "${WHITE}     🔹 URL Status : ${CYAN}$FIREBASE_URL${NC}"
    echo ""
    echo -e "${GREEN}     [✓] Monitorando comandos e pronto para uso...${NC}"
    echo ""
}

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
            \"action\":true,
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
            \"action\":true,
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
    
    enviar_resposta "[SISTEMA: $MOTIVO - Forçando encerramento total do tmux e arquivos...]" "$TIMESTAMP"

    curl -s \
        -X PATCH \
        -H "Content-Type: application/json" \
        -d "{
            \"id\":\"$ID_GERADO\",
            \"action\":false,
            \"comando\":null,
            \"resposta\":\"\",
            \"data_hora\":$TIMESTAMP
        }" \
        "$FIREBASE_URL" \
        > /dev/null 2>&1

    tmux kill-server 2>/dev/null
    pkill -9 tmux 2>/dev/null
    rm -rf "$VM_WORKSPACE"
    rm -rf "$SANDBOX_DIR"
}

# Inicia a primeira sandbox
iniciar_sandbox

# ==========================================
# LOOP PRINCIPAL (100ms)
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
        print(f"TRUE,{current_ms + 30000}")
    else:
        act = data.get("action", True)
        act_str = "FALSE" if (act is False or str(act).lower() == "false") else "TRUE"
        exp = data.get("expiration", current_ms + 30000)
        try:
            exp = int(exp)
        except:
            exp = current_ms + 30000
        print(f"{act_str},{exp}")
except:
    current_ms = int(time.time() * 1000)
    print(f"TRUE,{current_ms + 30000}")
' <<EOF
$DADOS
EOF
)

    IFS=',' read -r ACTION_VAL EXPIRATION_VAL <<< "$PARSED_VALS"

    # Se action for FALSE: Encerra tudo e sai do script de vez
    if [ "$ACTION_VAL" = "FALSE" ]; then
        forcar_limpeza_total "DESATIVADO VIA FIREBASE"
        echo -e "\n${RED}[!] Ação FALSE identificada. Sessão encerrada e script finalizado.${NC}"
        exit 0
    fi

    # Se o tempo expirou: Limpa a sessão atual e cria uma nova sandbox automaticamente
    if [ "$TIMESTAMP_MS" -ge "$EXPIRATION_VAL" ]; then
        forcar_limpeza_total "TEMPO EXPIRADO"
        echo -e "\n${YELLOW}[!] Tempo expirado. Reiniciando nova sandbox...${NC}"
        sleep 2
        iniciar_sandbox
        continue
    fi

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

        echo -e "${GREEN}[✓] Comando executado na sandbox.${NC}"

        if ! tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
            tmux new-session -d -s "$TMUX_SESSION" -c "$VM_WORKSPACE"
            tmux send-keys -t "$TMUX_SESSION" "export PS1='root@AMHEEX-VPS ~# '" Enter
        fi

        tmux send-keys -t "$TMUX_SESSION" "$CMD" Enter
        
        sleep 0.3

        SAIDA_LIMPA=$(python3 -c '
import subprocess
import re

try:
    out = subprocess.check_output(["tmux", "capture-pane", "-t", "sandbox_ubuntu", "-p", "-S", "-30"]).decode("utf-8")
    linhas = out.splitlines()
    
    linhas_limpas = []
    for l in linhas:
        stripped = l.strip()
        if "root@AMHEEX-VPS ~#" in stripped or not stripped:
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
