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
FIREBASE_URL="https://amheexvps-default-rtdb.firebaseio.com/STORAGE/${ID_GERADO}/CMD.json"

# ==========================================
# INSTALAÇÃO DE DEPENDÊNCIAS
# ==========================================
export DEBIAN_FRONTEND=noninteractive
if ! command -v node >/dev/null 2>&1 || ! command -v python3 >/dev/null 2>&1; then
    sudo apt-get update -y >/dev/null 2>&1
    sudo apt-get install -y curl git wget unzip build-essential nodejs python3 -y >/dev/null 2>&1
fi

# ==========================================
# STATUS INICIAL E EXPIRAÇÃO (EM MILISSEGUNDOS)
# ==========================================
TIMESTAMP_MS=$(python3 -c 'import time; print(int(time.time() * 1000))')
EXPIRATION_DEFAULT=$(( TIMESTAMP_MS + (30 * 1000) ))

DADOS_INICIAIS=$(curl -s "$FIREBASE_URL")

CONFIG_EXISTE=$(python3 -c '
import json, sys
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

PATCH_DATA="{\"id\":\"$ID_GERADO\",\"data_hora\":$TIMESTAMP_MS"
if [ "$HAS_ACTION" != "True" ]; then
    PATCH_DATA="${PATCH_DATA},\"action\":true"
fi
if [ "$HAS_EXPIRATION" != "True" ]; then
    PATCH_DATA="${PATCH_DATA},\"expiration\":$EXPIRATION_DEFAULT"
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
echo -e "${GREEN}     [✓] Monitorando comandos em tempo real...${NC}"
echo ""

# Variável de controle para gerenciar avisos de expiração
WORKSPACE_LIMPO=false

# ==========================================
# LOOP PRINCIPAL DE MONITORAMENTO
# ==========================================
while true; do
    TIMESTAMP_MS=$(python3 -c 'import time; print(int(time.time() * 1000))')
    DADOS=$(curl -s "$FIREBASE_URL")

    PARSED_VALS=$(python3 -c '
import json, sys, time
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

    # 1. Se action for FALSE: limpa a raiz, avisa e ENCERRA o script (exit 0)
    if [ "$ACTION_VAL" = "FALSE" ]; then
        echo -e "\n${RED}[!] Script desativado via Firebase (action=false). Removendo workspace...${NC}"
        RESP_FINAL="[!] Ambiente desativado via action=false."
        
        curl -s -X PATCH -d "{\"id\":\"$ID_GERADO\",\"comando\":null,\"cmd_ubuntu\":null,\"resposta\":\"$RESP_FINAL\",\"data_hora\":$TIMESTAMP_MS}" "$FIREBASE_URL" > /dev/null
        
        rm -rf "$VM_WORKSPACE"
        echo -e "${GREEN}[✓] Workspace limpo. Encerrando.${NC}"
        exit 0
    fi

    # 2. Se o tempo de expiração esgotar: limpa o workspace, mas CONTINUA atualizando a data_hora a cada 1s sem parar
    if [ "$TIMESTAMP_MS" -ge "$EXPIRATION_VAL" ]; then
        if [ "$WORKSPACE_LIMPO" = "false" ]; then
            echo -e "\n${YELLOW}[!] Tempo de expiração esgotado. Limpando workspace e mantendo conexão ativa...${NC}"
            rm -rf "$VM_WORKSPACE"
            mkdir -p "$VM_WORKSPACE"
            
            curl -s -X PATCH -d "{\"id\":\"$ID_GERADO\",\"comando\":null,\"cmd_ubuntu\":null,\"resposta\":\"[!] Expiração atingida. Workspace limpo, aguardando renovação de tempo.\",\"data_hora\":$TIMESTAMP_MS}" "$FIREBASE_URL" > /dev/null
            
            WORKSPACE_LIMPO=true
        else
            # Continua atualizando data_hora a cada 1 segundo enquanto estiver expirado, sem parar
            curl -s -X PATCH -d "{\"id\":\"$ID_GERADO\",\"action\":true,\"data_hora\":$TIMESTAMP_MS}" "$FIREBASE_URL" > /dev/null
        fi
        
        sleep 1
        continue
    else
        # Se o tempo foi renovado externamente, reseta a flag
        WORKSPACE_LIMPO=false
    fi

    # Atualiza o timestamp atual em ms no Firebase (com o script rodando normalmente)
    curl -s -X PATCH -d "{\"id\":\"$ID_GERADO\",\"action\":true,\"data_hora\":$TIMESTAMP_MS}" "$FIREBASE_URL" > /dev/null
    
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
        curl -s -X PATCH -d "{\"id\":\"$ID_GERADO\",\"action\":true,\"comando\":null,\"cmd_ubuntu\":null,\"resposta\":$RESPOSTA_ESCAPADA,\"data_hora\":$TIMESTAMP_MS}" "$FIREBASE_URL" > /dev/null

    # Execução de comandos gerais
    elif [ ! -z "$CMD" ] && [ "$CMD" != "null" ]; then
        echo -e "\n${CYAN}[CMD] Executando: $CMD${NC}"
        curl -s -X PATCH -d "{\"id\":\"$ID_GERADO\",\"action\":true,\"comando\":null,\"resposta\":\"[⏳] Processando...\",\"data_hora\":$TIMESTAMP_MS}" "$FIREBASE_URL" > /dev/null

        RESPOSTA=$(cd "$VM_WORKSPACE" && bash -c "$CMD" 2>&1)
        
        RESPOSTA_ESCAPADA=$(python3 -c 'import json, sys; print(json.dumps(sys.stdin.read()))' <<EOF
$RESPOSTA
EOF
)
        curl -s -X PATCH -d "{\"id\":\"$ID_GERADO\",\"action\":true,\"comando\":null,\"resposta\":$RESPOSTA_ESCAPADA,\"data_hora\":$TIMESTAMP_MS}" "$FIREBASE_URL" > /dev/null
    fi

    # Intervalo rápido de 10ms (0.01 segundos) quando ativo
    sleep 0.01
done
