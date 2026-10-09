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
DIR_FILE="$SANDBOX_DIR/current_dir"
SESSION_NAME="sandbox_persistent_session"
OUTPUT_LOG="$SANDBOX_DIR/output.log"
INPUT_FIFO="$SANDBOX_DIR/input_fifo"

mkdir -p "$SANDBOX_DIR"
mkdir -p "$VM_WORKSPACE"

if [ ! -f "$DIR_FILE" ]; then
    echo "$VM_WORKSPACE" > "$DIR_FILE"
fi

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
# INICIALIZA SESSÃO PERSISTENTE (SCREEN)
# ------------------------------------------
iniciar_sessao_persistente() {
    if ! screen -list | grep -q "$SESSION_NAME"; then
        DIR_ATUAL=$(cat "$DIR_FILE")
        [ ! -d "$DIR_ATUAL" ] && DIR_ATUAL="$VM_WORKSPACE"
        
        # Cria uma sessão screen desacoplada rodando bash no diretório correto
        screen -d -m -S "$SESSION_NAME" bash -c "cd '$DIR_ATUAL' && exec bash"
        sleep 0.5
    fi
}

# ------------------------------------------
# EXECUTA COMANDO NA SESSÃO ÚNICA PERSISTENTE
# ------------------------------------------
executar_stream() {
    local COMANDO="$1"
    local TIPO="$2"
    local TIMESTAMP

    iniciar_sessao_persistente

    # Tratamento para o comando CLEAR
    if [ "$COMANDO" = "clear" ]; then
        TIMESTAMP=$(obter_timestamp)
        enviar_resposta "[Terminal limpo]" "$TIMESTAMP"
        return 0
    fi

    # Tratamento para EXIT / EXITE
    if [ "$COMANDO" = "exit" ] || [ "$COMANDO" = "exite" ]; then
        screen -S "$SESSION_NAME" -X quit 2>/dev/null
        TIMESTAMP=$(obter_timestamp)
        enviar_resposta "[Sessão de comando encerrada]" "$TIMESTAMP"
        return 0
    fi

    # Tratamento especial para comandos 'cd' para atualizar o arquivo de controle de diretório
    if [[ "$COMANDO" =~ ^cd([[:space:]]+.*)?$ ]]; then
        screen -S "$SESSION_NAME" -X stuff "$COMANDO; pwd > \"$DIR_FILE\"$(printf \\r)"
        sleep 0.5
        local NOVO_DIR
        NOVO_DIR=$(cat "$DIR_FILE")
        TIMESTAMP=$(obter_timestamp)
        enviar_resposta "Diretório atual: $NOVO_DIR" "$TIMESTAMP"
        return 0
    fi

    # Envia o comando para a sessão screen existente sem abrir novas sessões
    # Captura a saída redirecionando ou lendo o buffer/log se necessário
    screen -S "$SESSION_NAME" -X stuff "$COMANDO$(printf \\r)"

    # Dá um breve tempo para o comando processar e lê o estado/resposta recente
    sleep 1
    TIMESTAMP=$(obter_timestamp)
    enviar_resposta "[Comando enviado para a sessão interativa]" "$TIMESTAMP"

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
EXPIRATION_DEFAULT=$((TIMESTAMP_MS + (30 * 1000)))

# ==========================================
# REGISTRO INICIAL
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
   ! command -v python3 >/dev/null 2>&1 || \
   ! command -v screen >/dev/null 2>&1; then

    echo -e "${YELLOW}[*] Dependências ausentes.${NC}"
    echo -e "${YELLOW}[*] Instalação iniciada.${NC}"

    apt-get update -y && \
    apt-get install -y curl wget unzip zip build-essential software-properties-common apt-transport-https ca-certificates gnupg lsb-release python3 python3-pip python3-dev nodejs npm jq net-tools iputils-ping nano screen tmux
else
    echo -e "${GREEN}[✓] Dependências já instaladas.${NC}()"
fi

# Inicializa a sessão screen principal logo no início
iniciar_sessao_persistente

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
echo -e "${GREEN}     [✓] Monitorando comandos em tempo real (Sessão Única Interativa)...${NC}"
echo ""

WORKSPACE_LIMPO=false

# ==========================================
# LOOP PRINCIPAL
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
        echo -e "\n${RED}[!] Script desativado via Firebase.${NC}"
        screen -S "$SESSION_NAME" -X quit 2>/dev/null
        rm -rf "$VM_WORKSPACE"
        echo -e "${GREEN}[✓] Workspace limpo.${NC}"
        echo -e "${GREEN}[✓] Encerrando.${NC}"
        exit 0
    fi

    if [ "$TIMESTAMP_MS" -ge "$EXPIRATION_VAL" ]; then
        if [ "$WORKSPACE_LIMPO" = "false" ]; then
            echo -e "\n${YELLOW}[!] Tempo expirado. Limpando workspace...${NC}"
            screen -S "$SESSION_NAME" -X quit 2>/dev/null
            rm -rf "$VM_WORKSPACE"
            mkdir -p "$VM_WORKSPACE"
            echo "$VM_WORKSPACE" > "$DIR_FILE"
            iniciar_sessao_persistente
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
        echo ""
        echo -e "${CYAN}╔══════════════════════════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║               NOVO COMANDO UBUNTU                       ║${NC}"
        echo -e "${CYAN}╚══════════════════════════════════════════════════════════╝${NC}"
        echo -e "${WHITE}$CMD_UBUNTU${NC}"
        echo ""

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

        executar_stream "$CMD_UBUNTU" "UBUNTU"

    elif [ -n "$CMD" ] && [ "$CMD" != "null" ]; then
        echo ""
        echo -e "${CYAN}╔══════════════════════════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║                  NOVO COMANDO                           ║${NC}"
        echo -e "${CYAN}╚══════════════════════════════════════════════════════════╝${NC}"
        echo -e "${WHITE}$CMD${NC}"
        echo ""

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

        executar_stream "$CMD" "GERAL"
    fi

    sleep 1
done
