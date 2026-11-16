#!/bin/bash
set -e

echo "Iniciando compilação do IPA..."

PROJECT=$(find . -name "*.xcodeproj" -print -quit)

if [ -z "$PROJECT" ]; then
    echo "ERRO: Nenhum projeto Xcode encontrado."
    exit 1
fi

SCHEME=$(xcodebuild -list -project "$PROJECT" | grep -E '^[[:space:]]+[A-Za-z0-9_-]+$' | head -1 | xargs)

echo "Projeto: $PROJECT"
echo "Scheme: $SCHEME"

xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -sdk iphoneos \
  -archivePath build/App.xcarchive \
  CODE_SIGNING_ALLOWED=NO \
  archive

mkdir -p build/Payload

APP=$(find build/App.xcarchive/Products/Applications -maxdepth 1 -name "*.app" -print -quit)

cp -R "$APP" build/Payload/

cd build
zip -r Hyper-Regedit-Key-Enabled-unsigned.ipa Payload
