#!/usr/bin/env bash
# 签名 HAP 包
# Usage: ./sign.sh

set -e
cd "$(dirname "$0")"

TOOL="/run/media/xy/新加卷/harmony/DevEco Studio/sdk/default/openharmony/toolchains/lib/hap-sign-tool.jar"
P12="./signing/OpenHarmonyDebug.p12"
CHAIN="./signing/app_chain.cer"
PROFILE="./signing/debug.p7b"
UNSIGNED="./entry/build/default/outputs/default/entry-default-unsigned.hap"
SIGNED="./entry/build/default/outputs/default/entry-default-signed.hap"

if [ ! -f "$UNSIGNED" ]; then
    echo "ERROR: 未找到未签名的 HAP: $UNSIGNED"
    echo "请先运行: node hvigorw.js assembleHap"
    exit 1
fi

echo "签名 HAP..."
java -jar "$TOOL" sign-app \
  -mode localSign \
  -keyAlias "openharmony application release" \
  -keyPwd "123456" \
  -appCertFile "$CHAIN" \
  -profileFile "$PROFILE" \
  -inFile "$UNSIGNED" \
  -signAlg SHA256withECDSA \
  -keystoreFile "$P12" \
  -keystorePwd "123456" \
  -outFile "$SIGNED" \
  -compatibleVersion 23 \
  -signCode 1

echo "已签名: $SIGNED"
ls -lh "$SIGNED"