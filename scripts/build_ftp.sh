#!/bin/bash
set -e

# !!! ВАЖНО: замени строку ниже на свой домен PythonAnywhere перед загрузкой !!!
BOT_DOMAIN="sandercompile.pythonanywhere.com"

CHATID="$CHAT_ID"
FILE="$ZIP_PATH"

send_message() {
  curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
    -d chat_id="$CHATID" -d text="$1" > /dev/null
}

report_result() {
  curl -s -X POST "https://$BOT_DOMAIN/build_result" \
    -d chat_id="$CHATID" -d status="$1" -d type="ftp" > /dev/null || true
}

cleanup_repo_file() {
  BLOB_SHA=$(git rev-parse "HEAD:$FILE" 2>/dev/null || true)
  if [ -n "$BLOB_SHA" ]; then
    curl -s -X DELETE \
      -H "Authorization: Bearer $GITHUB_TOKEN" \
      -H "Accept: application/vnd.github+json" \
      "https://api.github.com/repos/$GITHUB_REPOSITORY/contents/$FILE" \
      -d "{\"message\":\"cleanup: remove processed ftp upload [skip ci]\",\"sha\":\"$BLOB_SHA\",\"branch\":\"builds\"}" \
      > /dev/null || true
  fi
}
trap cleanup_repo_file EXIT

fail() {
  send_message "$1"
  report_result "failed"
  exit 1
}

START_TS=$(date +%s)

send_message "🔄 Подключаюсь и загружаю файлы по FTP..."

mkdir -p project
if ! unzip -q "$FILE" -d project; then
  fail "Не удалось распаковать архив."
fi

sudo apt-get update -qq > /dev/null
sudo apt-get install -y -qq lftp > /dev/null

if ! lftp -u "$FTP_LOGIN","$FTP_PASSWORD" -p "$FTP_PORT" "$FTP_HOST" \
    -e "set ftp:ssl-allow no; set net:timeout 20; set net:max-retries 2; mirror -R --parallel=3 project /; bye"; then
  fail "❌ Не удалось загрузить файлы на FTP. Проверь host/port/логин/пароль."
fi

END_TS=$(date +%s)
DURATION=$((END_TS - START_TS))
MM=$((DURATION / 60))
SS=$((DURATION % 60))

send_message "✅ Загрузка на FTP завершена!
⏱️ Время: ${MM}м ${SS}с"

report_result "success"
