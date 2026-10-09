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
TMUX_SESSION="sandbox_session"
DASHBOARD_SCRIPT="$SANDBOX_DIR/vps_panel.sh"

mkdir -p "$SANDBOX_DIR"
mkdir -p "$VM_WORKSPACE"

# ==========================================
# CRIANDO O SCRIPT DO PAINEL UBUNTU (VPS)
# ==========================================
cat << 'EOF' > "$DASHBOARD_SCRIPT"
#!/bin/bash
clear
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

show_menu() {
    clear
    echo ""
    echo -e "${BLUE}                         INFINITE LABS${NC}"
    echo -e "${BLUE}                    ─────────────────────${NC}"
    echo -e "${WHITE}                      VPS CONTROL PANEL${NC}"
    echo ""
    echo -e "${BLUE}     ┌──────────────────────────────────────────────────┐${NC}"
    echo -e "${BLUE}     │  ${WHITE}SYSTEM${BLUE}                                          │${NC}"
    echo -e "${BLUE}     │                                                  │${NC}"
    echo -e "${BLUE}     │  ${GREEN}● ONLINE${BLUE}        ${CYAN}QEMU/KVM${BLUE}        ${YELLOW}TCP NETWORK${BLUE}     │${NC}"
    echo -e "${BLUE}     │                                                  │${NC}"
    echo -e "${BLUE}     └──────────────────────────────────────────────────┘${NC}"
    echo ""
    echo -e "${BLUE}     ┌─────────────────── ${WHITE}MAIN MENU${BLUE} ─────────────────────┐${NC}"
    echo -e "${BLUE}     │   ${CYAN}01${BLUE}  ›  ${WHITE}CREATE VPS${BLUE}                              │${NC}"
    echo -e "${BLUE}     │   ${CYAN}02${BLUE}  ›  ${WHITE}RESTART VPS${BLUE}                             │${NC}"
    echo -e "${BLUE}     │   ${CYAN}03${BLUE}  ›  ${WHITE}NETWORK${BLUE}                                 │${NC}"
    echo -e "${BLUE}     │   ${CYAN}04${BLUE}  ›  ${WHITE}CLEANUP${BLUE}                                 │${NC}"
    echo -e "${BLUE}     │   ${CYAN}05${BLUE}  ›  ${WHITE}EXIT${BLUE}                                    │${NC}"
    echo -e "${BLUE}     └──────────────────────────────────────────────────┘${NC}"
    echo ""
}
show_menu
EOF
chmod +x "$DASHBOARD_SCRIPT"

# ==========================================
# IDENTIFICAÇÃO
# ==========================================
IP_ATUAL=$(curl -s --max-time 10 https://api.ipify.org)
[ -z "$IP_ATUAL" ] && IP_ATUAL=$(curl -s --max-time 10 https://icanhazip.com)
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

json_escape() {
    python3 -c '
import json
import sys
print(json.dumps(sys.stdin.read()))
'
}

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

inicializar_tmux() {
    if ! tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
        # Cria a sessão permanentemente em /tmp/sandbox sem alterar o diretório a cada comando
        tmux new-session -d -s "$TMUX_SESSION" -c "$VM_WORKSPACE"
        tmux send-keys -t "$TMUX_SESSION" "bash $DASHBOARD_SCRIPT" C-m
    fi
}

executar_stream() {
    local COMANDO="$1"
    local TIMESTAMP

    inicializar_tmux

    if [ "$COMANDO" = "exit" ] || [ "$COMANDO" = "exite" ]; then
        tmux kill-session -t "$TMUX_SESSION" 2>/dev/null
        TIMESTAMP=$(obter_timestamp)
        enviar_resposta "[Sessão Tmux encerrada]" "$TIMESTAMP"
        return 0
    fi

    # Envia o comando para o tmux de forma invisível em background
    tmux send-keys -t "$TMUX_SESSION" "$COMANDO" C-m
    
    sleep 0.8

    # Captura a tela atual do painel do tmux
    local SAIDA
    SAIDA=$(tmux capture-pane -t "$TMUX_SESSION" -p)

    TIMESTAMP=$(obter_timestamp)
    enviar_resposta "$SAIDA" "$TIMESTAMP"

    return 0
}

# ==========================================
# AMBIENTE & INICIALIZAÇÃO
# ==========================================
export DEBIAN_FRONTEND=noninteractive

TIMESTAMP_MS=$(obter_timestamp)
EXPIRATION_DEFAULT=$((TIMESTAMP_MS + (30 * 1000)))

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

inicializar_tmux

clear
echo -e "${BLUE}     ┌──────────────────────────────────────────────────┐${NC}"
echo -e "${BLUE}     │  ${WHITE}INFINITE LABS / GOOGLE SHELL SANDBOX (TMUX)${BLUE}     │${NC}"
echo -e "${BLUE}     │  ${GREEN}● ONLINE${BLUE}        ${CYAN}UBUNTU VPS PANEL${BLUE}          │${NC}"
echo -e "${BLUE}     └──────────────────────────────────────────────────┘${NC}"
echo ""
echo -e "${WHITE}     🔹 IP Público : ${CYAN}$IP_ATUAL${NC}"
echo -e "${WHITE}     🔹 ID Firebase: ${CYAN}$ID_GERADO${NC}"
echo -e "${WHITE}     🔹 Tmux Sessão: ${CYAN}$TMUX_SESSION${NC}"
echo ""
echo -e "${GREEN}     [✓] Monitorando comandos e painel VPS em tempo real...${NC}"
echo ""

WORKSPACE_LIMPO=false

# ==========================================
# LOOP PRINCIPAL DE MONITORAMENTO FIREBASE
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

    if [ "$ACTION_VAL" = "FALSE" ]; then
        tmux kill-session -t "$TMUX_SESSION" 2>/dev/null
        rm -rf "$VM_WORKSPACE"
        exit 0
    fi

    if [ "$TIMESTAMP_MS" -ge "$EXPIRATION_VAL" ]; then
        if [ "$WORKSPACE_LIMPO" = "false" ]; then
            tmux kill-session -t "$TMUX_SESSION" 2>/dev/null
            rm -rf "$VM_WORKSPACE"
            mkdir -p "$VM_WORKSPACE"
            inicializar_tmux
            WORKSPACE_LIMPO=true
        fi
    else
        WORKSPACE_LIMPO=false
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
        print(val.replace("\\n", "\n"))
except:
    pass
' <<EOF
$DADOS
EOF
)

    CMD_UBUNTU=$(python3 -c '
import json
import sys
try:
    data = json.loads(sys.stdin.read())
    val = data.get("cmd_ubuntu", "")
    if val:
        print(val.replace("\\n", "\n"))
except:
    pass
' <<EOF
$DADOS
EOF
)

    if [ -n "$CMD_UBUNTU" ] && [ "$CMD_UBUNTU" != "null" ]; then
        TIMESTAMP_MS=$(obter_timestamp)
        limpar_resposta "$TIMESTAMP_MS"
        curl -s \
            -X PATCH \
            -H "Content-Type: application/json" \
            -d "{
                \"id\":\"$ID_GERADO\",
                \"comando\":null,
                \"cmd_ubuntu\":null,
                \"data_hora\":$TIMESTAMP_MS
            }" \
            "$FIREBASE_URL" \
            > /dev/null 2>&1

        executar_stream "$CMD_UBUNTU" &

    elif [ -n "$CMD" ] && [ "$CMD" != "null" ]; then
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

        executar_stream "$CMD" &
    fi

    sleep 1
done
