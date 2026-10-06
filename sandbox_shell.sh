#!/bin/bash
set +H

# Obtém estritamente o IP público da conexão e remove os pontos
IP_ATUAL=$(curl -s https://api.ipify.org || curl -s https://icanhazip.com || curl -s https://ifconfig.me)
if [ -z "$IP_ATUAL" ]; then
    IP_ATUAL="127.0.0.1"
fi
IP_SEM_PONTOS=$(echo "$IP_ATUAL" | tr -d '.')

# Define o ID dinâmico combinando "ID" + IP sem pontos
ID_GERADO="ID${IP_SEM_PONTOS}"

# Define a base do servidor e monta a URL dinâmica
SERVIDOR="https://amheexbot-default-rtdb.firebaseio.com"
FIREBASE_URL="${SERVIDOR}/STORAGE/${ID_GERADO}/CMD.json"

echo "IP Público detectado: $IP_ATUAL"
echo "ID gerado: $ID_GERADO"
echo "Monitorando Firebase: $FIREBASE_URL..."

# Diretório base exclusivo da sandbox na VPS
SANDBOX_DIR="/root/.sandbox"
CURRENT_SANDBOX_DIR="$SANDBOX_DIR"
mkdir -p "$CURRENT_SANDBOX_DIR"

# Função unificada para garantir que todas as dependências padrão estejam sempre instaladas e atualizadas na VPS
garantir_dependencias() {
    mkdir -p /root/sandbox
    export DEBIAN_FRONTEND=noninteractive
    if ! command -v node >/dev/null 2>&1 || ! command -v npm >/dev/null 2>&1 || ! command -v git >/dev/null 2>&1; then
        apt-get update -y >/dev/null 2>&1
        apt-get install -y curl wget unzip build-essential -y >/dev/null 2>&1
        curl -fsSL https://deb.nodesource.com/setup_20.x | bash - >/dev/null 2>&1
        apt-get install -y nodejs -y >/dev/null 2>&1
    fi
}

echo "Verificando e configurando dependências padrão..."
garantir_dependencias

while true; do
    # Obtém a data e hora atual (formato: AAAA-MM-DD HH:MM:SS)
    DATA_HORA_ATUAL=$(date '+%Y-%m-%d %H:%M:%S')

    # Faz o download dos dados atuais do Firebase para checagem e envio
    DADOS=$(curl -s "$FIREBASE_URL")

    # Verifica e gerencia o tempo de expiração em milissegundos
    EXPIRATION_MS=$(python3 -c '
import json, sys, time
try:
    data = json.loads(sys.stdin.read())
    exp = data.get("expiration")
    now_ms = int(time.time() * 1000)
    
    if exp is None or str(exp).strip() == "" or str(exp).lower() == "null":
        exp_val = now_ms + 120000
        print(f"CREATE:{exp_val}")
    else:
        print(f"EXIST:{int(exp)}")
except Exception as e:
    now_ms = int(time.time() * 1000)
    print(f"CREATE:{now_ms + 120000}")
' <<EOF
$DADOS
EOF
)

    ACTION=$(echo "$EXPIRATION_MS" | cut -d':' -f1)
    VAL_MS=$(echo "$EXPIRATION_MS" | cut -d':' -f2)
    CURRENT_MS=$(python3 -c 'import time; print(int(time.time() * 1000))')

    if [ "$ACTION" = "CREATE" ]; then
        PAYLOAD_EXP="{\"id\":\"$ID_GERADO\",\"expiration\":$VAL_MS}"
        curl -s -X PATCH -d "$PAYLOAD_EXP" "$FIREBASE_URL" > /dev/null
    elif [ "$CURRENT_MS" -ge "$VAL_MS" ]; then
        echo "Tempo de expiração atingido! Resetando a sandbox..."
        rm -rf "$SANDBOX_DIR"/*
        rm -rf /root/sandbox/*
        mkdir -p "$SANDBOX_DIR"
        mkdir -p /root/sandbox
        garantir_dependencias
        
        NEW_EXP_MS=$((CURRENT_MS + 120000))
        PAYLOAD_RESET="{\"id\":\"$ID_GERADO\",\"expiration\":$NEW_EXP_MS,\".resposta\":\".sandbox expirada e resetada com sucesso!\"}"
        curl -s -X PATCH -d "$PAYLOAD_RESET" "$FIREBASE_URL" > /dev/null
        
        DADOS=$(curl -s "$FIREBASE_URL")
    fi

    PAYLOAD_STATUS="{\"id\":\"$ID_GERADO\",\"data_hora\":\"$DATA_HORA_ATUAL\"}"
    curl -s -X PATCH -d "$PAYLOAD_STATUS" "$FIREBASE_URL" > /dev/null
    
    CMD=$(python3 -c '
import json, sys
try:
    data = json.loads(sys.stdin.read())
    val = data.get("comando", "")
    if val:
        val = val.replace("\\n", "\n")
    print(val if val is not None else "")
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
    if val:
        val = val.replace("\\n", "\n")
    print(val if val is not None else "")
except:
    print("")
' <<EOF
$DADOS
EOF
)

    COR_CMD=$(python3 -c '
import json, sys
try:
    data = json.loads(sys.stdin.read())
    val = data.get("cor", "") or data.get("color", "")
    print(val if val is not None else "")
except:
    print("")
' <<EOF
$DADOS
EOF
)

    # 1. Captura e processa alteração de cor/tema vinda do Firebase
    if [ ! -z "$COR_CMD" ] && [ "$COR_CMD" != "null" ]; then
        echo "Alteração de cor/tema recebida do Firebase: $COR_CMD"
        echo "$COR_CMD" > "$SANDBOX_DIR/.current_color"

        RESPOSTA="Cor/Tema alterado com sucesso para: $COR_CMD"
        RESPOSTA_ESCAPADA=$(python3 -c 'import json, sys; print(json.dumps(sys.stdin.read()))' <<EOF
$RESPOSTA
EOF
)

        PAYLOAD_COR="{\"id\":\"$ID_GERADO\",\"cor\":null,\"color\":null,\"resposta\":$RESPOSTA_ESCAPADA,\"data_hora\":\"$DATA_HORA_ATUAL\"}"
        curl -s -X PATCH -d "$PAYLOAD_COR" "$FIREBASE_URL" > /dev/null

    # 2. Execução via Botão Ubuntu do Painel Web dentro da .sandbox
    elif [ ! -z "$CMD_UBUNTU" ] && [ "$CMD_UBUNTU" != "null" ]; then
        echo "Executando ação do Botão Ubuntu na .sandbox: $CMD_UBUNTU"
        
        garantir_dependencias
        RESPOSTA=""
        if [ "$CMD_UBUNTU" = "1" ] || [ "$CMD_UBUNTU" = "create" ]; then
            RESPOSTA="[sandbox] Ambiente Ubuntu ativo com Node.js, npm, git e dependências padrão!"
        elif [ "$CMD_UBUNTU" = "2" ] || [ "$CMD_UBUNTU" = "restart" ]; then
            RESPOSTA="[sandbox] Ambiente reiniciado e dependências verificadas."
        elif [ "$CMD_UBUNTU" = "4" ] || [ "$CMD_UBUNTU" = "clean" ]; then
            rm -rf "$SANDBOX_DIR"/*
            rm -rf /root/sandbox/*
            mkdir -p "$SANDBOX_DIR"
            mkdir -p /root/sandbox
            garantir_dependencias
            RESPOSTA="[sandbox] Armazenamento isolado limpo e reinicializado com sucesso!"
        else
            RESPOSTA=$(cd /root/sandbox && export HOME=/root && bash -c "$CMD_UBUNTU" 2>&1)
        fi

        RESPOSTA_ESCAPADA=$(python3 -c 'import json, sys; print(json.dumps(sys.stdin.read()))' <<EOF
$RESPOSTA
EOF
)
        PAYLOAD="{\"id\":\"$ID_GERADO\",\"comando\":null,\"cmd_ubuntu\":null,\"resposta\":$RESPOSTA_ESCAPADA,\"data_hora\":\"$DATA_HORA_ATUAL\"}"
        curl -s -X PATCH -d "$PAYLOAD" "$FIREBASE_URL" > /dev/null

    # 3. Execução de comandos gerais
    elif [ ! -z "$CMD" ] && [ "$CMD" != "null" ]; then
        echo "Executando comando na VPS:"
        echo "$CMD"
        
        garantir_dependencias

        PAYLOAD_INICIAL="{\"id\":\"$ID_GERADO\",\"comando\":null,\"resposta\":\"[⏳] Processando comando na VPS...\",\"data_hora\":\"$DATA_HORA_ATUAL\"}"
        curl -s -X PATCH -d "$PAYLOAD_INICIAL" "$FIREBASE_URL" > /dev/null

        RESPOSTA=$(cd /root/sandbox && export HOME=/root && bash -c "
        if echo '$CMD' | grep -q 'bash <(curl'; then
            URL_EXTRAIDA=\$(echo '$CMD' | grep -oE 'https?://[^ \)]+')
            curl -s \"\$URL_EXTRAIDA\" -o /tmp/script_exec.sh
            bash /tmp/script_exec.sh
            rm -f /tmp/script_exec.sh
        else
            eval '$CMD'
        fi
        " 2>&1)

        RESPOSTA_ESCAPADA=$(python3 -c 'import json, sys; print(json.dumps(sys.stdin.read()))' <<EOF
$RESPOSTA
EOF
)

        PAYLOAD="{\"id\":\"$ID_GERADO\",\"comando\":null,\"resposta\":$RESPOSTA_ESCAPADA,\"data_hora\":\"$DATA_HORA_ATUAL\"}"
        curl -s -X PATCH -d "$PAYLOAD" "$FIREBASE_URL" > /dev/null

        echo "Resposta do comando enviada com sucesso!"
    fi

    sleep 0.90
done
