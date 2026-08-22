# Decisiones

Las alternativas que se descartaron y por qué. El README cuenta cómo funciona; esto
cuenta por qué no funciona de otra manera.

## Por qué no Bluetooth

Velarium ya anda sin internet: el QR apunta a una IP de tu red local y el celular se
conecta directo. Lo único que hace falta es que los dos estén en la *misma* red, no que
esa red tenga salida a internet. Si no hay red, la prendés vos con el hotspot del celular
y los datos apagados — sigue creando una red local, que es todo lo que necesitamos.

Bluetooth no reemplaza eso, por dos razones independientes:

- **Ancho de banda.** BLE da del orden de decenas de KB/s y un solo frame pesa 60–90 KB.
  El espejado es directamente imposible.
- **Safari.** iOS no soporta Web Bluetooth, así que una página web nunca podría usarlo,
  ni aunque el ancho de banda alcanzara.

Si algún día se quiere sacar el router del medio, el camino es **WiFi peer-to-peer (AWDL)**
vía `NWParameters.includePeerToPeer`, lo mismo que usa AirDrop. Da ancho de banda de sobra,
pero requiere una app iOS nativa — y eso cuesta lo único que hace especial a Velarium, que
es no instalar nada en el teléfono.

## Por qué no la Mac App Store

Las apps en sandbox no pueden obtener el permiso de Accesibilidad, y sin Accesibilidad no
hay forma de pasar las diapositivas. Es el mismo motivo por el que Rectangle, Karabiner y
BetterTouchTool se distribuyen fuera de la tienda.

El camino que queda es **Developer ID + notarización**, con un `.dmg` descargable desde la
landing.

## Por qué la web no se hostea

La sirve la Mac. Subirla a un hosting rompería justamente el funcionamiento sin internet,
que es la premisa del producto. Vercel entra solo para la landing de `velarium.app`, que
es una página estática distinta y que sí vive en internet.

## Certificados

`Scripts/release.sh` verifica que exista un certificado **Developer ID Application** antes
de empezar. Un certificado **Apple Development** no sirve para distribuir: alcanza para
correr la app en la Mac propia, pero a cualquier otra persona macOS le muestra el cartel de
"no se puede abrir porque proviene de un desarrollador no identificado". El Developer ID se
crea en developer.apple.com y necesita membresía paga del Apple Developer Program.
