#!/bin/bash

URL="https://amheexvps-default-rtdb.firebaseio.com/STORAGE/active_sandbox.json"

# Função auxiliar para obter o timestamp atual em milissegundos
get_time_ms() {
    python3 -c 'import time; print(int(time.time()*1000))'
}

# Inicialização de variáveis e diretórios
S="ID$(get_time_ms)"
DIR="/tmp/sandbox/$S"
mkdir -p "$DIR"

FU="https://amheexvps-default-rtdb.firebaseio.com/STORAGE/$S/CMD.json"

# Requisição inicial PATCH para o CMD.json
INIT_PAYLOAD=$(jq -n \
    --arg id "$S" \
    --argjson exp 0 \
    --argjson dh "$(get_time_ms)" \
    '{id: $id, expiration: $exp, data_hora: $dh, comando: null, resposta: ""}')
curl -s -X PATCH -H "Content-Type: application/json" -d "$INIT_PAYLOAD" "$FU" > /dev/null

# Requisição inicial PATCH para active_sandbox.json
ACTIVE_PAYLOAD=$(jq -n --arg sb "$S" '{sandbox_id: $sb}')
curl -s -X PATCH -H "Content-Type: application/json" -d "$ACTIVE_PAYLOAD" "$URL" > /dev/null

echo "Colab Shell Único Ativo! ID fixado: $S | Diretório: $DIR"

UC=""
LAST_CMD_TIME=0
LAST_HEARTBEAT=0

# Loop principal
while true; do
    TS=$(get_time_ms)
    
    # Heartbeat a cada 1 segundo
    if (( TS - LAST_HEARTBEAT >= 1000 )); then
        HB_PAYLOAD=$(jq -n --argjson dh "$TS" '{data_hora: $dh}')
        curl -s -X PATCH -H "Content-Type: application/json" -d "$HB_PAYLOAD" "$FU" > /dev/null
        LAST_HEARTBEAT=$TS
    fi
    
    # Busca dados do Firebase
    D=$(curl -s "$FU")
    
    if [[ -n "$D" && "$D" != "null" ]]; then
        RAW_EXP=$(echo "$D" | jq -r '.expiration // 0')
        EXP=$RAW_EXP
        if (( RAW_EXP > 0 && RAW_EXP < 10000000000 )); then
            EXP=$(( RAW_EXP * 1000 ))
        fi
        
        # Verifica expiração da sessão
        if (( EXP > 0 && TS >= EXP )); then
            rm -rf "$DIR"
            mkdir -p "$DIR"
            EXPIRED_PAYLOAD=$(jq -n \
                --arg id "$S" \
                --argjson exp 0 \
                --argjson dh "$TS" \
                '{id: $id, expiration: $exp, data_hora: $dh, comando: null, resposta: "[Sessao expirada e limpa]"}')
            curl -s -X PATCH -H "Content-Type: application/json" -d "$EXPIRED_PAYLOAD" "$FU" > /dev/null
            UC=""
            LAST_CMD_TIME=0
            continue
        fi
        
        CMD=$(echo "$D" | jq -r '.comando // empty')
        
        if [[ -n "$CMD" && "$CMD" != "null" ]]; then
            DATA_HORA_CMD=$(echo "$D" | jq -r '.data_hora // 0')
            
            if [[ "$CMD" != "$UC" || "$DATA_HORA_CMD" -gt "$LAST_CMD_TIME" ]]; then
                UC="$CMD"
                LAST_CMD_TIME="$DATA_HORA_CMD"
                
                # Limpa o comando no Firebase indicando processamento
                CLEAR_PAYLOAD=$(jq -n --arg id "$S" --argjson dh "$TS" '{id: $id, comando: null, data_hora: $dh}')
                curl -s -X PATCH -H "Content-Type: application/json" -d "$CLEAR_PAYLOAD" "$FU" > /dev/null
                
                mkdir -p "$DIR"
                MARKER="__FIM_$(get_time_ms)__"
                
                # Executa o comando no diretório restrito com limite de 15 segundos
                OUT=$(cd "$DIR" && timeout 15 bash -c "$CMD; echo '$MARKER'") 2>&1
                
                # Remove a marcação do final da saída
                OUT="${OUT//$MARKER/}"
                
                # Envia a resposta de volta ao Firebase
                RESP_PAYLOAD=$(jq -n \
                    --arg id "$S" \
                    --arg resp "$OUT" \
                    --argjson dh "$(get_time_ms)" \
                    '{id: $id, resposta: $resp, data_hora: $dh}')
                curl -s -X PATCH -H "Content-Type: application/json" -d "$RESP_PAYLOAD" "$FU" > /dev/null
            fi
        fi
    fi
    
    sleep 0.5
done
