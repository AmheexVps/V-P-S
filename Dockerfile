# ============================================================
# WHATSAPP-BOT + SANDBOX SCRIPT (QEMU VPS) + NODE 20 + PHP
# ============================================================

FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=America/Sao_Paulo

WORKDIR /var/www/html

# ============================================================
# INSTALAÇÃO DE DEPENDÊNCIAS (PHP, NODE, DROPBEAR, ANDROID UTILS E QEMU SANDBOX)
# ============================================================

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    git \
    ffmpeg \
    webp \
    procps \
    php-cli \
    php-curl \
    php-json \
    microsocks \
    openssh-client \
    dropbear \
    grep \
    gawk \
    sed \
    sudo \
    apksigner \
    zipalign \
    default-jdk-headless \
    # --- DEPENDÊNCIAS PARA A FUNÇÃO SCRIPT SANDBOX / QEMU VPS ---
    qemu-system-x86 \
    qemu-utils \
    cloud-image-utils \
    genisoimage \
    lsof \
    wget \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Configuração de Senha do Root e Dropbear SSH
RUN echo 'root:TESTE123' | chpasswd \
    && mkdir -p /etc/dropbear

# Instalação do Node.js 20 LTS
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get update \
    && apt-get install -y --no-install-recommends nodejs \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# ============================================================
# DIRETÓRIOS E VARIÁVEIS DE AMBIENTE
# ============================================================

ENV NODE_ENV=production
ENV PORT=10000
ENV PINGGY_KEY="T7gw4ddIaYE"

RUN mkdir -p /var/www/html/session /var/www/html/temp /var/www/html/database /tmp/render_vps

# ============================================================
# COPIAR ARQUIVOS E DEPENDÊNCIAS
# ============================================================

COPY . /var/www/html

RUN npm install --omit=dev
RUN chmod -R 777 /var/www/html /tmp/render_vps

EXPOSE 10000 22 2222

# ============================================================
# SCRIPT DE INICIALIZAÇÃO MULTI-PROCESSO (/index.sh)
# ============================================================

RUN echo '#!/bin/bash\n\
# 1. Inicia o Dropbear SSH local na porta 22\n\
dropbear -E -R -p 22 &\n\
sleep 1\n\
\n\
# 2. Inicia o SOCKS5 em background na porta 1080\n\
microsocks -i 0.0.0.0 -p 1080 > /dev/null 2>&1 &\n\
sleep 1\n\
\n\
# 3. Abre o túnel Pinggy em background registrando o log\n\
ssh -T -p 443 -R0:localhost:22 -o StrictHostKeyChecking=no -o ServerAliveInterval=30 -o ServerAliveCountMax=3 tcp+'"${PINGGY_KEY}"'+force@free.pinggy.io > /var/www/html/pinggy.log 2>&1 &\n\
\n\
# 4. Extração do comando SSH conectando direto como ROOT\n\
(\n\
  echo "Aguardando conexao..." > /var/www/html/ssh_command.txt\n\
  for i in {1..20}; do\n\
    URL_LINE=$(grep -m 1 "tcp://" /var/www/html/pinggy.log)\n\
    if [ -n "$URL_LINE" ]; then\n\
      HOST=$(echo "$URL_LINE" | awk -F"tcp://" "{print \$2}" | cut -d: -f1)\n\
      PORT_NUM=$(echo "$URL_LINE" | awk -F"tcp://" "{print \$2}" | cut -d: -f2 | awk "{print \$1}")\n\
      if [ -n "$HOST" ] && [ -n "$PORT_NUM" ]; then\n\
        echo "ssh -t -p ${PORT_NUM} root@${HOST}" > /var/www/html/ssh_command.txt\n\
        break\n\
      fi\n\
    fi\n\
    sleep 2\n\
  done\n\
) &\n\
\n\
# 5. Servidor PHP interno na porta 8080\n\
php -S 0.0.0.0:8080 -t /var/www/html > /dev/null 2>&1 &\n\
\n\
# 6. Executa o Script Sandbox (se o render_sandbox.sh existir no repositório)\n\
if [ -f /var/www/html/render_sandbox.sh ]; then\n\
  chmod +x /var/www/html/render_sandbox.sh\n\
fi\n\
\n\
# 7. Executa o Bot em background\n\
node index.js &\n\
\n\
# 8. Servidor HTTP principal na PORT 10000\n\
exec php -S 0.0.0.0:${PORT:-10000} -t /var/www/html\n\
' > /index.sh && chmod +x /index.sh

CMD ["/index.sh"]
