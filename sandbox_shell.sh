#!/usr/bin/env bash
set +H

# Obtém estritamente o IP público da conexão e remove os pontos
IP_ATUAL=$(curl -s https://api.ipify.org || curl -s https://icanhazip.com || curl -s https://ifconfig.me)
if [ -z "$IP_ATUAL" ]; then
    IP_ATUAL="127.0.0.1"
fi
IP_SEM_PONTOS=$(echo "$IP_ATUAL" | tr -d '.')

ID_GERADO="ID${IP_SEM_PONTOS}"
SERVIDOR="https://amheexbot-default-rtdb.firebaseio.com"
FIREBASE_URL="${SERVIDOR}/STORAGE/${ID_GERADO}/CMD.json"

echo "IP Público detectado: $IP_ATUAL"
echo "ID gerado: $ID_GERADO"
echo "Monitorando Firebase: $FIREBASE_URL..."

SANDBOX_DIR="$HOME/.sandbox"
mkdir -p "$SANDBOX_DIR"

# Função para garantir dependências no Google Shell (direto no sistema)
garantir_dependencias() {
    mkdir -p "$SANDBOX_DIR/root"
    export HOME="$SANDBOX_DIR/root"
    if ! command -v node >/dev/null 2>&1 || ! command -v npm >/dev/null 2>&1 || ! command -v git >/dev/null 2>&1; then
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -y >/dev/null 2>&1
        apt-get install -y curl git wget unzip build-essential nodejs npm >/dev/null 2>&1
    fi
}

echo "Verificando e configurando dependências..."
garantir_dependencias

while true; do
    DATA_HORA_ATUAL=$(date '+%Y-%m-%d %H:%M:%S')
    DADOS=$(curl -s "$FIREBASE_URL")

    EXPIRATION_MS=$(python3 -c '
import json, sys, time
try:
    data = json.loads(sys.stdin.read())
    exp = data.get("expiration")
    now_ms = int(time.time() * 1000)
    if exp is None or str(exp).strip() == "" or str(exp).lower() == "null":
        print(f"CREATE:{now_ms + 120000}")
    else:
        print(f"EXIST:{int(exp)}")
except:
    print(f"CREATE:{int(time.time() * 1000) + 120000}")
' <<EOF
$DADOS
EOF
)

    ACTION=$(echo "$EXPIRATION_MS" | cut -d':' -f1)
    VAL_MS=$(echo "$EXPIRATION_MS" | cut -d':' -f2)
    CURRENT_MS=$(python3 -c 'import time; print(int(time.time() * 1000))')

    if [ "$ACTION" = "CREATE" ]; then
        curl -s -X PATCH -d "{\"id\":\"$ID_GERADO\",\"expiration\":$VAL_MS}" "$FIREBASE_URL" > /dev/null
    elif [ "$CURRENT_MS" -ge "$VAL_MS" ]; then
        echo "Tempo de expiração atingido! Resetando a sandbox..."
        rm -rf "$SANDBOX_DIR"/*
        mkdir -p "$SANDBOX_DIR"
        garantir_dependencias
        
        NEW_EXP_MS=$((CURRENT_MS + 120000))
        curl -s -X PATCH -d "{\"id\":\"$ID_GERADO\",\"expiration\":$NEW_EXP_MS,\"resposta\":\".sandbox expirada e resetada com sucesso!\"}" "$FIREBASE_URL" > /dev/null
        DADOS=$(curl -s "$FIREBASE_URL")
    fi

    curl -s -X PATCH -d "{\"id\":\"$ID_GERADO\",\"data_hora\":\"$DATA_HORA_ATUAL\"}" "$FIREBASE_URL" > /dev/null
    
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
        echo "Executando ação do Botão: $CMD_UBUNTU"
        garantir_dependencias
        RESPOSTA=""
        
        if [ "$CMD_UBUNTU" = "1" ] || [ "$CMD_UBUNTU" = "create" ]; then
            RESPOSTA="[Google Shell] Ambiente ativo com Node.js, npm e git!"
        elif [ "$CMD_UBUNTU" = "2" ] || [ "$CMD_UBUNTU" = "restart" ]; then
            RESPOSTA="[Google Shell] Ambiente reiniciado com sucesso."
        elif [ "$CMD_UBUNTU" = "4" ] || [ "$CMD_UBUNTU" = "clean" ]; then
            rm -rf "$SANDBOX_DIR"/*
            mkdir -p "$SANDBOX_DIR"
            garantir_dependencias
            RESPOSTA="[Google Shell] Armazenamento limpo e reinicializado!"
        else
            cd "$SANDBOX_DIR"
            RESPOSTA=$(bash -c "$CMD_UBUNTU" 2>&1)
        fi

        RESPOSTA_ESCAPADA=$(python3 -c 'import json, sys; print(json.dumps(sys.stdin.read()))' <<EOF
$RESPOSTA
EOF
)
        curl -s -X PATCH -d "{\"id\":\"$ID_GERADO\",\"comando\":null,\"cmd_ubuntu\":null,\"resposta\":$RESPOSTA_ESCAPADA,\"data_hora\":\"$DATA_HORA_ATUAL\"}" "$FIREBASE_URL" > /dev/null

    elif [ ! -z "$CMD" ] && [ "$CMD" != "null" ]; then
        echo "Executando comando: $CMD"
        garantir_dependencias
        
        curl -s -X PATCH -d "{\"id\":\"$ID_GERADO\",\"comando\":null,\"resposta\":\"[⏳] Processando comando...\",\"data_hora\":\"$DATA_HORA_ATUAL\"}" "$FIREBASE_URL" > /dev/null

        cd "$SANDBOX_DIR"
        RESPOSTA=$(bash -c "$CMD" 2>&1)

        RESPOSTA_ESCAPADA=$(python3 -c 'import json, sys; print(json.dumps(sys.stdin.read()))' <<EOF
$RESPOSTA
EOF
)
        curl -s -X PATCH -d "{\"id\":\"$ID_GERADO\",\"comando\":null,\"resposta\":$RESPOSTA_ESCAPADA,\"data_hora\":\"$DATA_HORA_ATUAL\"}" "$FIREBASE_URL" > /dev/null
    fi

    sleep 0.90
done
