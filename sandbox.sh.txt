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
# DIRETÓRIOS E AMBIENTE (TERMUX)
# ==========================================
SANDBOX_DIR="$HOME/.termux/sandbox"
VM_WORKSPACE="$HOME/.termux/workspace"
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
# INSTALAÇÃO DE DEPENDÊNCIAS NO TERMUX
# ==========================================
if ! command -v python3 >/dev/null 2>&1 || ! command -v curl >/dev/null 2>&1; then
    echo -e "${YELLOW}[*] Instalando dependências no Termux...${NC}"
    pkg update -y >/dev/null 2>&1
    pkg install -y curl python git wget unzip nodejs -y >/dev/null 2>&1
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
echo -e "${BLUE}     │  ${WHITE}INFINITE LABS / TERMUX ANDROID SANDBOX${BLUE}        │${NC}"
echo -e "${BLUE}     │                                                  │${NC}"
echo -e "${BLUE}     │  ${GREEN}● ONLINE${BLUE}        ${CYAN}TERMUX SHELL${BLUE}    ${YELLOW}FIREBASE SYNC${BLUE}   │${NC}"
echo -e "${BLUE}     └──────────────────────────────────────────────────┘${NC}"
echo ""
echo -e "${WHITE}     🔹 IP Público : ${CYAN}$IP_ATUAL${NC}"
echo -e "${WHITE}     🔹 ID Firebase: ${CYAN}$ID_GERADO${NC}"
echo -e "${WHITE}     🔹 URL Status : ${CYAN}$FIREBASE_URL${NC}"
echo ""
echo -e "${GREEN}     [✓] Monitorando comandos no Termux (Timeout: 30s)...${NC}"
echo ""

WORKSPACE_LIMPO=false

# ==========================================
# FUNÇÃO DE EXECUÇÃO COM ATUALIZAÇÃO EM TEMPO REAL
# ==========================================
executar_e_enviar() {
    local comando_para_rodar="$1"
    echo -e "\n${CYAN}[CMD] Executando: $comando_para_rodar${NC}"
    
    TIMESTAMP_MS=$(python3 -c 'import time; print(int(time.time() * 1000))')
    curl -s -X PATCH -d "{\"id\":\"$ID_GERADO\",\"action\":true,\"comando\":null,\"cmd_ubuntu\":null,\"resposta\":\"[⏳] Executando no Termux...\",\"data_hora\":$TIMESTAMP_MS}" "$FIREBASE_URL" > /dev/null

    local TEMP_OUT="$SANDBOX_DIR/cmd_output_$$.txt"
    > "$TEMP_OUT"

    (cd "$VM_WORKSPACE" && bash -c "$comando_para_rodar" > "$TEMP_OUT" 2>&1) &
    local CMD_PID=$!

    while kill -0 "$CMD_PID" 2>/dev/null; do
        if [ -f "$TEMP_OUT" ]; then
            local PARCIAL
            PARCIAL=$(cat "$TEMP_OUT")
            if [ -n "$PARCIAL" ]; then
                local PARCIAL_ESCAPADA
                PARCIAL_ESCAPADA=$(python3 -c 'import json, sys; print(json.dumps(sys.stdin.read()))' <<EOF
$PARCIAL
EOF
)
                TIMESTAMP_MS=$(python3 -c 'import time; print(int(time.time() * 1000))')
                curl -s -X PATCH -d "{\"id\":\"$ID_GERADO\",\"action\":true,\"resposta\":$PARCIAL_ESCAPADA,\"data_hora\":$TIMESTAMP_MS}" "$FIREBASE_URL" > /dev/null
            fi
        fi
        sleep 1
    done

    if [ -f "$TEMP_OUT" ]; then
        local RESPOSTA_FINAL
        RESPOSTA_FINAL=$(cat "$TEMP_OUT")
        rm -f "$TEMP_OUT"
        
        local RESPOSTA_ESCAPADA
        RESPOSTA_ESCAPADA=$(python3 -c 'import json, sys; print(json.dumps(sys.stdin.read()))' <<EOF
$RESPOSTA_FINAL
EOF
)
        TIMESTAMP_MS=$(python3 -c 'import time; print(int(time.time() * 1000))')
        curl -s -X PATCH -d "{\"id\":\"$ID_GERADO\",\"action\":true,\"comando\":null,\"cmd_ubuntu\":null,\"resposta\":$RESPOSTA_ESCAPADA,\"data_hora\":$TIMESTAMP_MS}" "$FIREBASE_URL" > /dev/null
    fi
}

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

    if [ "$ACTION_VAL" = "FALSE" ]; then
        echo -e "\n${RED}[!] Script desativado via Firebase (action=false). Removendo workspace...${NC}"
        RESP_FINAL="[!] Ambiente Termux desativado via action=false."
        
        curl -s -X PATCH -d "{\"id\":\"$ID_GERADO\",\"comando\":null,\"cmd_ubuntu\":null,\"resposta\":\"$RESP_FINAL\",\"data_hora\":$TIMESTAMP_MS}" "$FIREBASE_URL" > /dev/null
        
        rm -rf "$VM_WORKSPACE"
        echo -e "${GREEN}[✓] Workspace limpo. Encerrando.${NC}"
        exit 0
    fi

    if [ "$TIMESTAMP_MS" -ge "$EXPIRATION_VAL" ]; then
        if [ "$WORKSPACE_LIMPO" = "false" ]; then
            echo -e "\n${YELLOW}[!] Tempo de expiração esgotado (30s). Limpando workspace e aguardando renovação...${NC}"
            rm -rf "$VM_WORKSPACE"
            mkdir -p "$VM_WORKSPACE"
            
            curl -s -X PATCH -d "{\"id\":\"$ID_GERADO\",\"comando\":null,\"cmd_ubuntu\":null,\"resposta\":\"[!] Expiração atingida. Workspace limpo, aguardando renovação de tempo.\",\"data_hora\":$TIMESTAMP_MS}" "$FIREBASE_URL" > /dev/null
            
            WORKSPACE_LIMPO=true
        fi
        sleep 2
        continue
    else
        WORKSPACE_LIMPO=false
    fi

    curl -s -X PATCH -d "{\"id\":\"$ID_GERADO\",\"action\":true,\"data_hora\":$TIMESTAMP_MS}" "$FIREBASE_URL" > /dev/null
    
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

    if [ ! -z "$CMD_UBUNTU" ] && [ "$CMD_UBUNTU" != "null" ]; then
        executar_e_enviar "$CMD_UBUNTU"
    elif [ ! -z "$CMD" ] && [ "$CMD" != "null" ]; then
        executar_e_enviar "$CMD"
    fi

    sleep 1
done
