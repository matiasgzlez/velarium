#!/bin/bash
# Firma, notariza y empaqueta Velarium en un .dmg descargable.
#
# Requisitos, una sola vez:
#   1. Certificado "Developer ID Application" en el llavero.
#      Se crea en developer.apple.com > Certificates > "+" > Developer ID Application.
#      Necesita membresía paga del Apple Developer Program; el certificado
#      "Apple Development" que ya tenés NO sirve para distribuir.
#   2. Credenciales de notarización guardadas:
#      xcrun notarytool store-credentials velarium \
#        --apple-id TU_APPLE_ID --team-id TU_TEAM_ID --password APP_SPECIFIC_PASSWORD
set -euo pipefail

cd "$(dirname "$0")/.."

PROFILE="${NOTARY_PROFILE:-velarium}"
APP="build/Velarium.app"
DMG="build/Velarium.dmg"
STAGING="build/dmg"

IDENTITY=$(security find-identity -v -p codesigning \
  | grep "Developer ID Application" | head -1 | sed 's/.*"\(.*\)"/\1/')

if [ -z "$IDENTITY" ]; then
  cat <<'MSG'
No encontré un certificado "Developer ID Application".

Tenés "Apple Development", que sirve para correr la app en tu Mac pero no para
distribuirla: sin Developer ID, macOS le muestra a cualquier otra persona el cartel
de "no se puede abrir porque proviene de un desarrollador no identificado".

Creá uno en developer.apple.com > Certificates, IDs & Profiles > Certificates > "+"
> Developer ID Application. Descargalo, doble clic para instalarlo, y corré esto de nuevo.
MSG
  exit 1
fi

echo "==> Firmando con: $IDENTITY"
./Scripts/build-app.sh release

# El hardened runtime es obligatorio para notarizar.
codesign --force --deep --options runtime --timestamp \
  --sign "$IDENTITY" "$APP"
codesign --verify --strict --verbose=2 "$APP"

echo "==> Armando el .dmg"
rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "Velarium" -srcfolder "$STAGING" -ov -format UDZO "$DMG"
codesign --force --sign "$IDENTITY" --timestamp "$DMG"

echo "==> Notarizando (esto tarda unos minutos)"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait

echo "==> Grapando el ticket"
# Grapar deja el ticket dentro del .dmg, así se abre sin internet.
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"

echo
echo "Listo: $DMG"
echo "Subilo a la landing y ese es el link de instalación."
