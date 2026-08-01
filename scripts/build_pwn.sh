#!/bin/bash
set -e

FILE=$(git diff --name-only HEAD~1 HEAD -- pwn_uploads/ | head -n1)
if [ -z "$FILE" ]; then
  FILE=$(git show --name-only --pretty="" HEAD -- pwn_uploads/ | head -n1)
fi
BASENAME=$(basename "$FILE")
CHATID=$(echo "$BASENAME" | cut -d'_' -f1)

curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
  -d chat_id="$CHATID" -d text="Компилирую PWN..."

mkdir -p project
if ! powershell -NoProfile -Command "Expand-Archive -Path '$FILE' -DestinationPath 'project' -Force"; then
  curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
    -d chat_id="$CHATID" -d text="Не удалось распаковать архив."
  exit 1
fi

# Ищем папку pawno (с компилятором) и папку gamemodes (со скриптом) на любой глубине
PAWNO_DIR=$(find project -type d -iname "pawno" | head -n1)
if [ -z "$PAWNO_DIR" ]; then
  curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
    -d chat_id="$CHATID" -d text="В архиве не найдена папка pawno с компилятором."
  exit 1
fi

PAWNCC=$(find "$PAWNO_DIR" -maxdepth 1 -iname "pawncc.exe" | head -n1)
if [ -z "$PAWNCC" ]; then
  curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
    -d chat_id="$CHATID" -d text="В папке pawno не найден pawncc.exe."
  exit 1
fi

GAMEMODES_DIR=$(find project -type d -iname "gamemodes" | head -n1)
if [ -z "$GAMEMODES_DIR" ]; then
  curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
    -d chat_id="$CHATID" -d text="В архиве не найдена папка gamemodes."
  exit 1
fi

PWN_FILE=$(find "$GAMEMODES_DIR" -maxdepth 1 -iname "*.pwn" | head -n1)
if [ -z "$PWN_FILE" ]; then
  curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
    -d chat_id="$CHATID" -d text="В папке gamemodes не найден .pwn файл."
  exit 1
fi

INCLUDE_DIR="$PAWNO_DIR/include"

# Запускаем компилятор из архива пользователя (тот же, что и pawno.exe вызывает внутри себя)
"$PAWNCC" "$PWN_FILE" "-i$INCLUDE_DIR"

AMX_FILE="${PWN_FILE%.pwn}.amx"
if [ ! -f "$AMX_FILE" ]; then
  curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
    -d chat_id="$CHATID" -d text="Ошибка компиляции. Проверь .pwn файл и include-файлы в pawno/include."
  exit 1
fi

mkdir -p output
cp "$AMX_FILE" output/

powershell -NoProfile -Command "Compress-Archive -Path 'output/*' -DestinationPath 'amx.zip' -Force"

curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
  -d chat_id="$CHATID" -d text="Готово! .amx во вложении."
curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendDocument" \
  -F chat_id="$CHATID" -F document=@amx.zip
