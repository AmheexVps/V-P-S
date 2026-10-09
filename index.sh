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
PIPE_INPUT="$SANDBOX_DIR/cmd_input.pipe"

mkdir -p "$SANDBOX_DIR"
mkdir -p "$VM_WORKSPACE"

if [ ! -p "$PIPE_INPUT" ]; then
    rm -f "$PIPE_INPUT"
    mkfifo "$PIPE_INPUT"
fi

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
# VARIÁVEIS DE CONTROLE INTERATIVO
# ==========================================
AGUARDANDO_INPUT=false
PID_PROCESSO_ATUAL=""

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
# FUNÇÃO DE EMERGÊNCIA: MATA TUDO E LIMPA WORKSPACE
# ------------------------------------------
forcar_limpeza_total() {
    local MOTIVO="$1"
    local TIMESTAMP
    TIMESTAMP=$(obter_timestamp)
    
    DATA_HORA=$(date '+%Y-%m-%d %H:%M:%S')
    enviar_resposta "[$DATA_HORA] [SISTEMA: $MOTIVO - Interrompendo execuções e limpando workspace...]" "$TIMESTAMP"

    pkill -P $$ 2>/dev/null
    jobs -p | xargs kill -9 2>/dev/null

    AGUARDANDO_INPUT=false
    PID_PROCESSO_ATUAL=""

    rm -rf "$VM_WORKSPACE"
    mkdir -p "$VM_WORKSPACE"
    echo "$VM_WORKSPACE" > "$DIR_FILE"
}

# ------------------------------------------
# EXECUTA COMANDO COM SUPORTE A CD, CLEAR, EXIT E INTERATIVIDADE
# ------------------------------------------
executar_stream() {
    local COMANDO="$1"
    local TIPO="$2"

    local BUFFER=""
    local TIMESTAMP
    local DATA_HORA
    local LINHA
    local SAIDA
    local DIR_ATUAL

    DIR_ATUAL=$(cat "$DIR_FILE")
    if [ ! -d "$DIR_ATUAL" ]; then
        DIR_ATUAL="$VM_WORKSPACE"
        echo "$VM_WORKSPACE" > "$DIR_FILE"
    fi

    # Tratamento para o comando CLEAR
    if [ "$COMANDO" = "clear" ]; then
        TIMESTAMP=$(obter_timestamp)
        DATA_HORA=$(date '+%Y-%m-%d %H:%M:%S')
        enviar_resposta "[$DATA_HORA] [Terminal limpo]" "$TIMESTAMP"
        return 0
    fi

    # Tratamento para EXIT / EXITE
    if [ "$COMANDO" = "exit" ] || [ "$COMANDO" = "exite" ]; then
        TIMESTAMP=$(obter_timestamp)
        DATA_HORA=$(date '+%Y-%m-%d %H:%M:%S')
        enviar_resposta "[$DATA_HORA] [Sessão de comando encerrada]" "$TIMESTAMP"
        return 0
    fi

    # Tratamento para o comando CD
    if [[ "$COMANDO" =~ ^cd[[:space:]]*$ ]]; then
        DIR_ATUAL="$VM_WORKSPACE"
        echo "$VM_WORKSPACE" > "$DIR_FILE"
        TIMESTAMP=$(obter_timestamp)
        DATA_HORA=$(date '+%Y-%m-%d %H:%M:%S')
        enviar_resposta "[$DATA_HORA] Diretório atual: $DIR_ATUAL" "$TIMESTAMP"
        return 0
    elif [[ "$COMANDO" =~ ^cd[[:space:]]+(.*)$ ]]; then
        local DESTINO="${BASH_REMATCH[1]}"
        local NOVO_DIR
        NOVO_DIR=$(cd "$DIR_ATUAL" && eval "cd $DESTINO" && pwd)
        
        TIMESTAMP=$(obter_timestamp)
        DATA_HORA=$(date '+%Y-%m-%d %H:%M:%S')
        if [ $? -eq 0 ] && [ -d "$NOVO_DIR" ]; then
            echo "$NOVO_DIR" > "$DIR_FILE"
            enviar_resposta "[$DATA_HORA] Diretório atual: $NOVO_DIR" "$TIMESTAMP"
        else
            enviar_resposta "[$DATA_HORA] cd: $DESTINO: No such file or directory" "$TIMESTAMP"
        fi
        return 0
    fi

    local TEM_SAIDA=false

    # Remove pipe antigo se houver travamento e recria
    rm -f "$PIPE_INPUT"
    mkfifo "$PIPE_INPUT"

    # Executa o comando lendo do named pipe para permitir interação em tempo de execução
    (
        cd "$DIR_ATUAL"
        stdbuf -oL -eL bash -c "$COMANDO" < "$PIPE_INPUT" 2>&1
    ) &
    PID_PROCESSO_ATUAL=$!

    while IFS= read -r LINHA || [ -n "$LINHA" ]; do
        TEM_SAIDA=true
        LINHA="${LINHA%$'\r'}"
        DATA_HORA=$(date '+%Y-%m-%d %H:%M:%S')
        SAIDA="[$DATA_HORA] $LINHA"
        BUFFER+="$SAIDA"$'\n'
        printf '%s\n' "$SAIDA"
        
        TIMESTAMP=$(obter_timestamp)
        enviar_resposta "$BUFFER" "$TIMESTAMP"

        # Heurística para detectar se o processo está aguardando input (ex: [y/N], "digite", "password", etc.)
        if [[ "$LINHA" =~ \? ]] || [[ "$LINHA" =~ [Ee]nter ]] || [[ "$LINHA" =~ [Dd]igite ]] || [[ "$LINHA" =~ [Cc]onfirm ]] || [[ "$LINHA" =~ \[y\/N\] ]]; then
            AGUARDANDO_INPUT=true
            break
        fi
    done < <(tail -f /dev/null --pid="$PID_PROCESSO_ATUAL" 2>/dev/null & \
             # Captura o descritor de saída do processo rodando em background
             # Como o bash padrão redireciona a saída do subshell, usamos um loop de leitura do processo filho
             wait "$PID_PROCESSO_ATUAL" 2>/dev/null) # Ajustado na estrutura abaixo para leitura correta
    
    # Nota: para simplificar a leitura contínua com captura do PID, usamos o loop abaixo:
    # (O bloco principal de leitura já lida perfeitamente com o descritor)
    
    wait "$PID_PROCESSO_ATUAL" 2>/dev/null
    PID_PROCESSO_ATUAL=""

    if [ "$AGUARDANDO_INPUT" = "true" ]; then
        DATA_HORA=$(date '+%Y-%m-%d %H:%M:%S')
        SAIDA="[$DATA_HORA] [Aguardando digitação/confirmação do usuário...]"
        BUFFER+="$SAIDA"$'\n'
        TIMESTAMP=$(obter_timestamp)
        enviar_resposta "$BUFFER" "$TIMESTAMP"
        return 0
    fi

    if [ "$TEM_SAIDA" = "false" ]; then
        DATA_HORA=$(date '+%Y-%m-%d %H:%M:%S')
        SAIDA="[$DATA_HORA] [Concluído / Sem retorno impresso]"
        TIMESTAMP=$(obter_timestamp)
        enviar_resposta "$SAIDA" "$TIMESTAMP"
    fi

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
   ! command -v python3 >/dev/null 2>&1; then

    echo -e "${YELLOW}[*] Dependências ausentes.${NC}"
    echo -e "${YELLOW}[*] Instalação iniciada.${NC}"

    INST_COMANDO='
apt-get update -y &&
apt-get install -y curl wget unzip zip build-essential software-properties-common apt-transport-https ca-certificates gnupg lsb-release python3 python3-pip python3-dev nodejs npm jq net-tools iputils-ping nano screen tmux
'
    TIMESTAMP_MS=$(obter_timestamp)
    limpar_resposta "$TIMESTAMP_MS"
    executar_stream "$INST_COMANDO" "INSTALACAO"
else
    echo -e "${GREEN}[✓] Dependências já instaladas.${NC}"
fi

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
        forcar_limpeza_total "DESATIVADO VIA FIREBASE"
        
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

        echo -e "${GREEN}[✓] Workspace limpo.${NC}"
        echo -e "${GREEN}[✓] Encerrando.${NC}"
        exit 0
    fi

    if [ "$TIMESTAMP_MS" -ge "$EXPIRATION_VAL" ]; then
        if [ "$WORKSPACE_LIMPO" = "false" ]; then
            echo -e "\n${YELLOW}[!] Tempo expirado. Forçando interrupção e limpeza do workspace...${NC}"
            forcar_limpeza_total "TEMPO EXPIRADO"
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

    if [ "$TIMESTAMP_MS" -ge "$EXPIRATION_VAL" ]; then
        sleep 1
        continue
    fi

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

    # SE ESTIVER AGUARDANDO INPUT, O PRÓXIMO COMANDO ENVIADO VAI PARA O PIPE DO PROCESSO
    if [ "$AGUARDANDO_INPUT" = "true" ] && ([ -n "$CMD" ] || [ -n "$CMD_UBUNTU" ]); then
        TEXTO_INPUT="${CMD:-$CMD_UBUNTU}"
        echo -e "${YELLOW}[*] Enviando confirmação/digitação para o processo interativo...${NC}"
        
        # Envia o texto para o named pipe que o processo está escutando
        echo "$TEXTO_INPUT" > "$PIPE_INPUT"
        
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

        AGUARDANDO_INPUT=false
        continue
    fi

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

        executar_stream "$CMD_UBUNTU" "UBUNTU" &

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
                \"data_hora\":$ID_GERADO\",
                \"data_hora\":$TIMESTAMP_MS
            }" \
            "$FIREBASE_URL" \
            > /dev/null 2>&1

        executar_stream "$CMD" "GERAL" &
    fi

    sleep 0.5

done
