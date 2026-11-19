#!/bin/bash
set -euo pipefail
BLUE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$BLUE_ROOT"
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
BLUE_LOG="${BLUE_ROOT}/artifacts/iPhone-update-$(date +%Y%m%d-%H%M%S).log"
mkdir -p artifacts

blue_pause() {
    if [[ "${BLUE_UPDATE_NONINTERACTIVE:-0}" != 1 && -t 0 ]]; then
        read -r -p 'Pulsa Intro para cerrar… ' BLUE_REPLY
    fi
}
blue_failed() {
    printf '\nNo se ha podido actualizar Blue. Desbloquea el iPhone y comprueba que está conectado a Xcode por Wi-Fi.\nRegistro: %s\n' "$BLUE_LOG"
    tail -n 18 "$BLUE_LOG" 2>/dev/null || true
    blue_pause
}
trap blue_failed ERR

BLUE_TEAM="${BLUE_TEAM_ID:-$(sed -nE 's/^[[:space:]]*DEVELOPMENT_TEAM = ([A-Z0-9]{10});/\1/p' Blue.xcodeproj/project.pbxproj | head -1)}"
if [[ -z "$BLUE_TEAM" && -f .blue-personal-team ]]; then BLUE_TEAM=$(cat .blue-personal-team); fi
if [[ ! "$BLUE_TEAM" =~ ^[A-Z0-9]{10}$ ]]; then
    printf 'Selecciona tu equipo de desarrollo en Xcode → Blue → Signing & Capabilities y vuelve a ejecutar este archivo.\n'
    blue_pause
    exit 1
fi
BLUE_TARGET="${BLUE_IPHONE:-}"
if [[ -z "$BLUE_TARGET" && -f .blue-iphone-target ]]; then BLUE_TARGET=$(cat .blue-iphone-target); fi
if [[ -z "$BLUE_TARGET" ]]; then
    printf 'Configura BLUE_IPHONE con el nombre o identificador del iPhone emparejado en Xcode.\n'
    blue_pause
    exit 1
fi
printf 'Actualizando Blue. Mantén el iPhone desbloqueado y en la misma Wi-Fi que el Mac.\n'
printf 'Conectando con el iPhone…\n'
xcrun devicectl device info lockState --device "$BLUE_TARGET" --timeout 15 > "$BLUE_LOG" 2>&1
printf '1/3 Compilando y firmando con tu equipo de desarrollo…\n'
xcodebuild -project Blue.xcodeproj -scheme Blue -configuration Debug \
    -destination 'generic/platform=iOS' -derivedDataPath artifacts/iphone-update \
    -allowProvisioningUpdates ENABLE_DEBUG_DYLIB=NO DEVELOPMENT_TEAM="$BLUE_TEAM" build >> "$BLUE_LOG" 2>&1
BLUE_APP="${BLUE_ROOT}/artifacts/iphone-update/Build/Products/Debug-iphoneos/Blue.app"
codesign --verify --strict --deep "$BLUE_APP" >> "$BLUE_LOG" 2>&1
printf '2/3 Instalando en el iPhone…\n'
xcrun devicectl device install app --device "$BLUE_TARGET" --timeout 60 "$BLUE_APP" >> "$BLUE_LOG" 2>&1
printf '3/3 Abriendo Blue…\n'
xcrun devicectl device process launch --device "$BLUE_TARGET" --timeout 25 --terminate-existing app.iorb.blue.ios >> "$BLUE_LOG" 2>&1
printf '%s\n' "$BLUE_TEAM" > .blue-personal-team
printf '\nBlue está actualizada. Tus datos se conservan.\n'
blue_pause
