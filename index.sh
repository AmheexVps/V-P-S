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
SESSION_NAME="firebase_persistent_session"

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

# Garante que a sessão screen única existe
inicializar_sessao() {
    if ! screen -list | grep -q "$SESSION_NAME"; then
        DIR_ATUAL=$(cat "$DIR_FILE")
        screen -d -m -S "$SESSION_NAME" bash
        screen -S "$SESSION_NAME" -X eval "stuff 'cd $DIR_ATUAL\n'"
    fi
}

executar_stream() {
    local COMANDO="$1"
    local TIMESTAMP
    local DIR_ATUAL

    DIR_ATUAL=$(cat "$DIR_FILE")

    if [ "$COMANDO" = "clear" ]; then
        TIMESTAMP=$(obter_timestamp)
        enviar_resposta "[Terminal limpo]" "$TIMESTAMP"
        return 0
    fi

    if [ "$COMANDO" = "exit" ] || [ "$COMANDO" = "exite" ]; then
        TIMESTAMP=$(obter_timestamp)
        enviar_resposta "[Sessão de comando encerrada]" "$TIMESTAMP"
        return 0
    fi

    # Tratamento específico para CD para persistir o diretório
    if [[ "$COMANDO" =~ ^cd[[:space:]]+(.*)$ ]]; then
        local DESTINO="${BASH_REMATCH[1]}"
        local NOVO_DIR
        NOVO_DIR=$(cd "$DIR_ATUAL" && eval "cd $DESTINO" && pwd)
        
        if [ $? -eq 0 ] && [ -d "$NOVO_DIR" ]; then
            echo "$NOVO_DIR" > "$DIR_FILE"
            screen -S "$SESSION_NAME" -X eval "stuff 'cd $NOVO_DIR\n'"
            TIMESTAMP=$(obter_timestamp)
            enviar_resposta "Diretório atual: $NOVO_DIR" "$TIMESTAMP"
        else
            TIMESTAMP=$(obter_timestamp)
            enviar_resposta "cd: $DESTINO: No such file or directory" "$TIMESTAMP"
        fi
        return 0
    fi

    # Envia o comando para a sessão única do screen e captura a saída recente
    screen -S "$SESSION_NAME" -X eval "stuff '$COMANDO\n'"
    
    # Pequena pausa para o comando processar e gerar log/resposta
    sleep 0.8
    
    TIMESTAMP=$(obter_timestamp)
    enviar_resposta "[Comando enviado para a sessão única: $COMANDO]" "$TIMESTAMP"
    return 0
}

# ==========================================
# AMBIENTE E INICIALIZAÇÃO
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

# Instalação de dependências (garantindo screen)
if ! command -v node >/dev/null 2>&1 || ! command -v python3 >/dev/null 2>&1 || ! command -v screen >/dev/null 2>&1; then
    apt-get update -y && apt-get install -y curl wget python3 python3-pip nodejs npm screen procps
fi

# Inicializa a sessão única persistente
inicializar_sessao

clear
echo -e "${BLUE}     ┌──────────────────────────────────────────────────┐${NC}"
echo -e "${BLUE}     │  ${WHITE}INFINITE LABS / SESSÃO ÚNICA PERSISTENTE${BLUE}      │${NC}"
echo -e "${BLUE}     └──────────────────────────────────────────────────┘${NC}"
echo -e "${GREEN}     [✓] Sessão única pronta e monitorando...${NC}"

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
        screen -X -S "$SESSION_NAME" quit 2>/dev/null
        rm -rf "$VM_WORKSPACE"
        exit 0
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
    val = data.get("comando", "") or data.get("cmd_ubuntu", "")
    if val:
        print(val.replace("\\n", "\n"))
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
                \"cmd_ubuntu\":null,
                \"data_hora\":$TIMESTAMP_MS
            }" \
            "$FIREBASE_URL" \
            > /dev/null 2>&1

        executar_stream "$CMD"
    fi

    sleep 1
done
