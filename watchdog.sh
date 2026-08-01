#!/usr/bin/env bash
# NOVA Watchdog — vigila el servidor y avisa por Telegram cuando cae o vuelve
set -uo pipefail

URL="${WATCHDOG_URL:-https://compartida.wahandri.com/}"
STATE_FILE="status.txt"
MAX_STRIKES=2
UP="UP"
DOWN="DOWN"

now_utc() { date -u '+%d/%m/%Y %H:%M UTC'; }

send_telegram() {
  local text="$1"
  local resp
  resp=$(curl -sS --max-time 20 -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    -d "chat_id=${TELEGRAM_CHAT_ID}" \
    --data-urlencode "text=${text}" \
    -d "parse_mode=HTML" 2>&1)
  if echo "$resp" | grep -q '"ok":true'; then
    echo "Telegram: mensaje enviado OK"
  else
    echo "Telegram: ERROR - ${resp:0:300}"
    exit 1
  fi
}

check_server() {
  local code
  code=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 15 "$URL" 2>/dev/null)
  [ "$code" = "200" ]
}

git pull --quiet --ff-only >/dev/null 2>&1 || true

prev=$(cat "$STATE_FILE" 2>/dev/null || echo "$UP")
prev_base="${prev%%:*}"
prev_strikes="${prev##*:}"
[ "$prev_strikes" = "$prev" ] && prev_strikes=0

if check_server; then
  if [ "$prev_base" = "$DOWN" ]; then
    send_telegram "<b>✅🎉 ¡El servidor ha vuelto!</b>
🟢 En línea de nuevo desde las <b>$(now_utc)</b>
🔗 ${URL}"
  else
    echo "Estado: UP (sin cambios, sin aviso)"
  fi
  echo "$UP" > "$STATE_FILE"
else
  if [ "$prev_base" = "$DOWN" ]; then
    strikes=$((prev_strikes + 1))
  else
    strikes=1
  fi
  if [ "$strikes" -ge "$MAX_STRIKES" ]; then
    if [ "$prev" != "$DOWN" ]; then
      send_telegram "<b>⚠️🔥 ¡El SERVIDOR se ha caído!</b>
💥 <b>${URL}</b> sin respuesta
🕐 Detectado a las <b>$(now_utc)</b>
🛑 ${MAX_STRIKES} comprobaciones fallidas consecutivas"
    else
      echo "Ya notificado de la caída (sin reaviso)"
    fi
    echo "$DOWN" > "$STATE_FILE"
  else
    echo "Fallos consecutivos: ${strikes} (aviso a partir de ${MAX_STRIKES})"
    echo "${DOWN}:${strikes}" > "$STATE_FILE"
  fi
fi

if ! git diff --quiet "$STATE_FILE" 2>/dev/null; then
  git add "$STATE_FILE"
  git -c user.name="github-actions[bot]" -c user.email="41898282+github-actions[bot]@users.noreply.github.com" \
    commit -m "watchdog: estado $(cat "$STATE_FILE")" --quiet
  git push --quiet && echo "Estado persistido: $(cat "$STATE_FILE")"
else
  echo "Estado sin cambios (no se commitea)"
fi
