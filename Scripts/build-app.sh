#!/bin/bash
# Builds Velarium.app. macOS only grants Screen Recording and Accessibility to a
# signed bundle with a stable identifier, so a bare SwiftPM binary is not enough.
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
APP="build/Velarium.app"

echo "==> Compilando ($CONFIG)"
swift build -c "$CONFIG"

BIN=".build/$CONFIG/Velarium"
RES=".build/$CONFIG/Velarium_Velarium.bundle"

echo "==> Armando el bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Velarium"
# Los recursos van sueltos en Contents/Resources, que es donde los busca una
# app de macOS; el bundle de SwiftPM sólo sirve cuando se corre con swift run.
cp -R "$RES/Web" "$APP/Contents/Resources/Web"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>                 <string>Velarium</string>
    <key>CFBundleDisplayName</key>          <string>Velarium</string>
    <key>CFBundleIdentifier</key>           <string>app.velarium.mac</string>
    <key>CFBundleExecutable</key>           <string>Velarium</string>
    <key>CFBundlePackageType</key>          <string>APPL</string>
    <key>CFBundleShortVersionString</key>   <string>0.1.0</string>
    <key>CFBundleVersion</key>              <string>1</string>
    <key>LSMinimumSystemVersion</key>       <string>14.0</string>
    <key>LSApplicationCategoryType</key>    <string>public.app-category.productivity</string>
    <key>NSHighResolutionCapable</key>      <true/>
    <key>NSLocalNetworkUsageDescription</key>
    <string>Velarium abre un servidor en tu red local para que tu celular pueda ver y controlar la presentación.</string>
</dict>
</plist>
PLIST

# Drop the icon in if it has been generated yet (see docs/icono.md).
if [ -f "Resources/Velarium.icns" ]; then
  cp Resources/Velarium.icns "$APP/Contents/Resources/"
  /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string Velarium" "$APP/Contents/Info.plist"
  echo "==> Ícono incluido"
fi

# macOS ata los permisos de pantalla y accesibilidad a la firma del binario. Una
# firma ad-hoc cambia de hash en cada compilación, así que el permiso concedido
# deja de valer y la app vuelve a pedirlo aunque el interruptor siga en Ajustes.
# Con un certificado de desarrollo la firma es estable y el permiso sobrevive.
DEV_ID=$(security find-identity -v -p codesigning 2>/dev/null \
  | grep "Apple Development" | head -1 | awk '{print $2}')

if [ -n "$DEV_ID" ]; then
  echo "==> Firmando con el certificado de desarrollo"
  codesign --force --deep --options runtime --sign "$DEV_ID" "$APP"
else
  echo "==> Firmando ad-hoc (sin certificado de desarrollo)"
  echo "    Ojo: vas a tener que volver a dar los permisos en cada compilación."
  codesign --force --deep --sign - "$APP"
fi

echo
echo "Listo: $APP"
echo "Abrilo con:  open $APP"
