#!/bin/bash
set -e

FILE=$(git diff --name-only HEAD~1 HEAD -- uploads/ | head -n1)
if [ -z "$FILE" ]; then
  FILE=$(git show --name-only --pretty="" HEAD -- uploads/ | head -n1)
fi
BASENAME=$(basename "$FILE")
CHATID=$(echo "$BASENAME" | cut -d'_' -f1)

curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
  -d chat_id="$CHATID" -d text="Компилирую..."

curl -fsSL -o ndk.zip https://dl.google.com/android/repository/android-ndk-r25c-linux.zip
unzip -q ndk.zip -d "$HOME"
NDK_PATH="$HOME/android-ndk-r25c"

mkdir -p project
if ! unzip -q "$FILE" -d project; then
  curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
    -d chat_id="$CHATID" -d text="Не удалось распаковать архив."
  exit 1
fi

if [ ! -f project/jni/Android.mk ]; then
  curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
    -d chat_id="$CHATID" -d text="В архиве не найдена папка jni/Android.mk."
  exit 1
fi

cd project
if ! "$NDK_PATH/ndk-build" -j"$(nproc)" NDK_PROJECT_PATH=. APP_BUILD_SCRIPT=jni/Android.mk APP_ABI="arm64-v8a armeabi-v7a"; then
  cd ..
  curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
    -d chat_id="$CHATID" -d text="Ошибка сборки. Проверь Android.mk и структуру архива."
  exit 1
fi
cd ..

cd project/libs
zip -r ../../libs.zip .
cd ../..

curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
  -d chat_id="$CHATID" -d text="Готово! Библиотеки во вложении."
curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendDocument" \
  -F chat_id="$CHATID" -F document=@libs.zip
