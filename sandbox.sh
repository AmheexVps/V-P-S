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
mkdir -p "$SANDBOX_DIR" "$VM_WORKSPACE"

# ==========================================
# IDENTIFICAÇÃO E FIREBASE
# ==========================================
IP_ATUAL=$(curl -s https://api.ipify.org || curl -s https://icanhazip.com || curl -s https://ifconfig.me)
[ -z "$IP_ATUAL" ] && IP_ATUAL="127.0.0.1"

IP_SEM_PONTOS=$(echo "$IP_ATUAL" | tr -d '.')
ID_GERADO="ID${IP_SEM_PONTOS}"
FIREBASE_URL="https://amheexbot-default-rtdb.firebaseio.com/STORAGE/${ID_GERADO}/CMD.json"

# ==========================================
# INSTALAÇÃO DE DEPENDÊNCIAS
# ==========================================
export DEBIAN_FRONTEND=noninteractive
if ! command -v node >/dev/null 2>&1 || ! command -v python3 >/dev/null 2>&1; then
    sudo apt-get update -y >/dev/null 2>&1
    sudo apt-get install -y curl git wget unzip build-essential nodejs python3 -y >/dev/null 2>&1
fi

# ==========================================
# VERIFICAÇÃO E STATUS INICIAL (FIREBASE)
# ==========================================
DATA_HORA_ATUAL=$(date '+%Y-%m-%d %H:%M:%S')
DADOS_INICIAIS=$(curl -s "$FIREBASE_URL")

# Verifica se a chave 'action' e 'tempo' já existem no Firebase
CONFIG_EXISTE=$(python3 -c '
import json, sys
try:
    data = json.loads(sys.stdin.read())
    if isinstance(data, dict):
        has_action = "action" in data
        has_tempo = "tempo" in data
        print(f"{has_action},{has_tempo}")
    else:
        print("False,False")
except:
    print("False,False")
' <<EOF
$DADOS_INICIAIS
EOF
)

IFS=',' read -r HAS_ACTION HAS_TEMPO <<< "$CONFIG_EXISTE"

# Configura valores iniciais caso faltem no Firebase
PATCH_DATA="{\"id\":\"$ID_GERADO\",\"data_hora\":\"$DATA_HORA_ATUAL\""
if [ "$HAS_ACTION" != "True" ]; then
    PATCH_DATA="${PATCH_DATA},\"action\":true"
fi
if [ "$HAS_TEMPO" != "True" ]; then
    PATCH_DATA="${PATCH_DATA},\"tempo\":120"
fi
PATCH_DATA="${PATCH_DATA}}"

curl -s -X PATCH -d "$PATCH_DATA" "$FIREBASE_URL" > /dev/null

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
echo -e "${GREEN}     [✓] Monitorando comandos no Google Shell...${NC}"
echo ""

# ==========================================
# LOOP PRINCIPAL DE MONITORAMENTO
# ==========================================
while true; do
    DATA_HORA_ATUAL=$(date '+%Y-%m-%d %H:%M:%S')
    DADOS=$(curl -s "$FIREBASE_URL")

    # Extrai dados do Firebase (action e tempo)
    PARSED_VALS=$(python3 -c '
import json, sys
try:
    data = json.loads(sys.stdin.read())
    if not isinstance(data, dict):
        print("TRUE,120")
    else:
        act = data.get("action", True)
        if act is False or str(act).lower() == "false":
            act_str = "FALSE"
        else:
            act_str = "TRUE"
        
        tmp = data.get("tempo", 120)
        try:
            tmp = int(tmp)
        except:
            tmp = 120
        
        print(f"{act_str},{tmp}")
except:
    print("TRUE,120")
' <<EOF
$DADOS
EOF
)

    IFS=',' read -r ACTION_VAL TEMPO_VAL <<< "$PARSED_VALS"

    # Se action for FALSE ou o tempo expirar ( <= 0 ), limpa a raiz e encerra
    if [ "$ACTION_VAL" = "FALSE" ] || [ "$TEMPO_VAL" -le 0 ]; then
        if [ "$ACTION_VAL" = "FALSE" ]; then
            echo -e "\n${RED}[!] Script desativado via Firebase (action=false). Removendo workspace...${NC}"
            RESP_FINAL="[!] Ambiente desativado via action=false."
        else
            echo -e "\n${RED}[!] Tempo de sessão esgotado ($TEMPO_VAL seg). Removendo workspace...${NC}"
            RESP_FINAL="[!] Tempo expirado. Limpando ambiente."
        fi
        
        curl -s -X PATCH -d "{\"id\":\"$ID_GERADO\",\"comando\":null,\"cmd_ubuntu\":null,\"resposta\":\"$RESP_FINAL\",\"data_hora\":\"$DATA_HORA_ATUAL\"}" "$FIREBASE_URL" > /dev/null
        
        # Apaga raiz do sandbox onde está o arquivo/workspace
        rm -rf "$VM_WORKSPACE"
        
        echo -e "${GREEN}[✓] Workspace limpo. Encerrando.${NC}"
        exit 0
    fi

    # Decrementa o tempo localmente e atualiza no Firebase a cada ciclo se necessário, ou mantém ativo
    # Mantém o status ativo atualizando o timestamp
    curl -s -X PATCH -d "{\"id\":\"$ID_GERADO\",\"action\":true,\"data_hora\":\"$DATA_HORA_ATUAL\"}" "$FIREBASE_URL" > /dev/null
    
    # Extrai comando genérico
    CMD=$(python3 -c '
import json, sys
try:
    data = json.loads(sys.stdin.read())
    val = data.get("comando", "")
    print(val.replace("\\n", "\n") if val else "")
except:
    print("")
' <<EOF
$DADOS
EOF
)

    # Extrai comando específico do Ubuntu
    CMD_UBUNTU=$(python3 -c '
import json, sys
try:
    data = json.loads(sys.stdin.read())
    val = data.get("cmd_ubuntu", "")
    print(val.replace("\\n", "\n") if val else "")
except:
    print("")
' <<EOF
$DADOS
EOF
)

    # Execução de comandos do Ubuntu
    if [ ! -z "$CMD_UBUNTU" ] && [ "$CMD_UBUNTU" != "null" ]; then
        echo -e "\n${CYAN}[CMD] Executando: $CMD_UBUNTU${NC}"
        RESPOSTA=$(cd "$VM_WORKSPACE" && bash -c "$CMD_UBUNTU" 2>&1)
        
        RESPOSTA_ESCAPADA=$(python3 -c 'import json, sys; print(json.dumps(sys.stdin.read()))' <<EOF
$RESPOSTA
EOF
)
        curl -s -X PATCH -d "{\"id\":\"$ID_GERADO\",\"action\":true,\"comando\":null,\"cmd_ubuntu\":null,\"resposta\":$RESPOSTA_ESCAPADA,\"data_hora\":\"$DATA_HORA_ATUAL\"}" "$FIREBASE_URL" > /dev/null

    # Execução de comandos gerais
    elif [ ! -z "$CMD" ] && [ "$CMD" != "null" ]; then
        echo -e "\n${CYAN}[CMD] Executando: $CMD${NC}"
        curl -s -X PATCH -d "{\"id\":\"$ID_GERADO\",\"action\":true,\"comando\":null,\"resposta\":\"[⏳] Processando...\",\"data_hora\":\"$DATA_HORA_ATUAL\"}" "$FIREBASE_URL" > /dev/null

        RESPOSTA=$(cd "$VM_WORKSPACE" && bash -c "$CMD" 2>&1)
        
        RESPOSTA_ESCAPADA=$(python3 -c 'import json, sys; print(json.dumps(sys.stdin.read()))' <<EOF
$RESPOSTA
EOF
)
        curl -s -X PATCH -d "{\"id\":\"$ID_GERADO\",\"action\":true,\"comando\":null,\"resposta\":$RESPOSTA_ESCAPADA,\"data_hora\":\"$DATA_HORA_ATUAL\"}" "$FIREBASE_URL" > /dev/null
    fi

    sleep 1
done
