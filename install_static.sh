#!/usr/bin/env bash
set -e

# ====== ПРЕДГЕНЕРИРОВАННЫЙ СЕКРЕТ ======
# Домен: storage.googleapis.com
SECRET_B64="7jZ6GJruGPoxwZAFTv1KjpVzdG9yYWdlLmdvb2dsZWFwaXMuY29t"
SECRET_HEX="eee1337aafb8e588895089b5f5c182eeb04676f6f676c652e636f6d"
FAKE_HOST="storage.googleapis.com"

# ====== АВТО-ОПРЕДЕЛЕНИЕ IP ======
SERVER_IP=$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}' | head -n1)
if [[ -z "$SERVER_IP" ]]; then
  echo "Не удалось определить IP автоматически. Введи IPv4 сервера:"
  read -r SERVER_IP
fi
echo "Обнаружен IP сервера: ${SERVER_IP}"

# ====== ИНТЕРАКТИВНЫЙ ВЫБОР ПОРТА ======
read -p "Введи внешний порт для MTG [3128]: " PUBLIC_PORT
PUBLIC_PORT=${PUBLIC_PORT:-3128}

CFG_DIR="/etc/mtg"
CFG_FILE="${CFG_DIR}/config.toml"

echo "======================================================="
echo "Настраиваем MTG v2 на порту ${PUBLIC_PORT}..."
echo "======================================================="

mkdir -p "${CFG_DIR}"
chmod 700 "${CFG_DIR}"
echo "${SECRET_HEX}" > "${CFG_DIR}/secret"
chmod 600 "${CFG_DIR}/secret"

cat > "${CFG_FILE}" <<EOF
debug = true

secret = "${SECRET_B64}"

bind-to = "0.0.0.0:3128"
public-ip = "${SERVER_IP}:${PUBLIC_PORT}"

[faketls]
domain = "${FAKE_HOST}"
EOF

chmod 600 "${CFG_FILE}"

if command -v ufw >/dev/null 2>&1; then
  ufw allow ${PUBLIC_PORT}/tcp || true
fi

docker rm -f mtg 2>/dev/null || true

docker run -d --name mtg --restart unless-stopped \
  -p ${SERVER_IP}:${PUBLIC_PORT}:3128 \
  -v "${CFG_FILE}":/config.toml:ro \
  ghcr.io/9seconds/mtg:stable \
  run /config.toml

cat >/usr/local/bin/mtg-link <<EOF
#!/usr/bin/env bash
echo "======================================================="
echo "   MTProto Proxy (MTG v2) - Active Config"
echo "======================================================="
echo "SERVER_IP: ${SERVER_IP}"
echo "PORT:      ${PUBLIC_PORT}"
echo "FAKE_HOST: ${FAKE_HOST}"
echo ""
echo "Ссылка для Telegram:"
echo "https://t.me/proxy?server=${SERVER_IP}&port=${PUBLIC_PORT}&secret=${SECRET_B64}"
echo ""
echo "Внутренняя ссылка (tg://):"
echo "tg://proxy?server=${SERVER_IP}&port=${PUBLIC_PORT}&secret=${SECRET_B64}"
echo "======================================================="
EOF

chmod +x /usr/local/bin/mtg-link

echo "Прокси запущен."
mtg-link
