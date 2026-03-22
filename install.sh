#!/usr/bin/env bash
set -e

# ====== АВТО-ОПРЕДЕЛЕНИЕ IP СЕРВЕРА ======
# Пытаемся взять внешний IPv4 через STUN-подобный трюк
SERVER_IP=$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}' | head -n1)
if [[ -z "$SERVER_IP" ]]; then
  echo "Не смог определить IP автоматически. Введи IPv4 сервера:"
  read -r SERVER_IP
fi

echo "Обнаружен IP сервера: ${SERVER_IP}"

# ====== ИНТЕРАКТИВНЫЙ ВВОД ПОРТА И ДОМЕНА ======
read -p "Введи внешний порт для MTG [По умолчанию: 8443]: " PUBLIC_PORT
PUBLIC_PORT=${PUBLIC_PORT:-8443}

read -p "Введи домен для FakeTLS [По умолчанию: google.com]: " FAKE_HOST
FAKE_HOST=${FAKE_HOST:-google.com}

CFG_DIR="/etc/mtg"
CFG_FILE="${CFG_DIR}/config.toml"

echo "======================================================="
echo "Генерируем секрет для FAKE_HOST=${FAKE_HOST}..."
echo "======================================================="

SECRET_B64=$(docker run --rm ghcr.io/9seconds/mtg:stable generate-secret "${FAKE_HOST}")
echo "SECRET_B64: ${SECRET_B64}"

SECRET_HEX=$(python3 - <<PY
import base64, binascii
b64 = "${SECRET_B64}"
b = base64.urlsafe_b64decode(b64 + "=" * (-len(b64) % 4))
print(binascii.hexlify(b).decode())
PY
)
echo "SECRET_HEX: ${SECRET_HEX}"

mkdir -p "${CFG_DIR}"
chmod 700 "${CFG_DIR}"

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
echo "mtg-link — показать ссылки"
