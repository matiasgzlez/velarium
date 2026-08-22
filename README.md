# Velarium

Controlá y espejá la presentación de tu Mac desde el celular. Escaneás un QR y ya está —
sin instalar nada en el teléfono, sin cuentas, sin configuración.

El *velarium* era el toldo que los romanos tendían sobre el Coliseo para el público:
la pantalla gigante sobre la audiencia.

## Qué hace

- **Espeja** la pantalla de la Mac (o el proyector conectado) al navegador del celular.
- **Pasa diapositivas** deslizando el dedo, en cualquier app: Keynote, PowerPoint, PDF, Google Slides.
- **Hace zoom sobre la proyección**: pellizcás en el celu y el público ve la ampliación.
- Todo por la red local. Sin internet, sin servidor externo, sin que tus diapositivas salgan de tu Mac.

## Uso

```bash
./Scripts/build-app.sh
open build/Velarium.app
```

La primera vez macOS pide dos permisos:

| Permiso | Para qué |
|---|---|
| Grabación de pantalla | Ver tu pantalla para retransmitirla |
| Accesibilidad | Mandar las flechas que pasan las diapositivas |

Después: apuntás la cámara del celular al QR, se abre el navegador y ya controlás.

### Gestos

| Gesto | Qué hace |
|---|---|
| Deslizar ← / → | Diapositiva anterior / siguiente |
| Tocar mitad izquierda / derecha | Lo mismo, para cuando deslizar no sale |
| Pellizcar | Zoom sobre lo que ve el público |
| Arrastrar con zoom activo | Mover la zona ampliada |
| Tocar el reloj | Reiniciar el cronómetro |

## Si no conecta

Casi siempre es el WiFi de la facultad: muchas redes institucionales tienen **aislamiento
de clientes**, así que tu celu y tu Mac están en la misma red pero no se ven entre sí.

La solución es no depender de esa red: prendé el **hotspot del celular** y conectá la Mac ahí.
El QR se regenera solo con la IP nueva.

## Cómo está armado

```
Mac                                         Celular
┌─────────────────────────────┐            ┌──────────────┐
│ ScreenCaptureKit            │            │              │
│   └─ solo frames que        │  JPEG ───► │  <img>       │
│      cambiaron (.complete)  │   (WS)     │              │
│                             │            │              │
│ CGEvent  ◄──── comandos ────┼── JSON ────┤  gestos      │
│   └─ flechas ← →            │   (WS)     │              │
│                             │            │              │
│ ZoomOverlay                 │            │              │
│   └─ ventana sobre el       │            │  mismo       │
│      proyector, excluida    │            │  transform   │
│      de la captura          │            │  local       │
└─────────────────────────────┘            └──────────────┘
```

Tres decisiones que sostienen todo lo demás:

1. **El celular no instala nada.** La Mac sirve una web app por HTTP local; el QR lleva
   la URL y el token de acceso adentro, así que escanear *es* emparejar. Un paso, no dos.

2. **Solo se manda lo que cambió.** ScreenCaptureKit marca cada frame como `.complete` o
   `.idle`. Con diapositivas quietas no se transmite nada; el ancho de banda solo sube en
   la transición. El pico medido con la pantalla cambiando a 20fps es ~13 Mbps.

3. **El zoom se dibuja dos veces.** La Mac pone una ventana por encima del proyector con
   el frame ampliado (`sharingType = .none`, para no capturarse a sí misma) y el celular
   aplica exactamente el mismo transform en CSS. El presentador ve lo mismo que el público
   sin gastar un byte extra.

Además: los frames se descartan si el celular todavía está recibiendo el anterior, así una
conexión lenta pierde calidad pero nunca acumula retraso; y los puertos son efímeros, así
que nunca chocan con otra cosa que estés corriendo.

## Estado

MVP funcionando. Verificado de punta a punta: captura, transporte, autenticación por token,
y el rechazo de clientes sin token.

Lo que falta probar en vivo (necesita proyector y celular de verdad):

- Que el overlay de zoom aparezca por encima del modo presentación a pantalla completa de
  Keynote. Está en `CGShieldingWindowLevel() + 1`, que debería alcanzar, pero Keynote es
  quisquilloso con eso.
- Latencia real sobre WiFi de la facultad.

Limitación conocida: sobre HTTP local no hay contexto seguro, así que la API de Wake Lock no
está disponible y la pantalla del celular se puede apagar sola. Por ahora conviene poner el
bloqueo automático en *Nunca* antes de exponer.

## Sin internet

Velarium ya funciona sin internet: nada sale de tu Mac, el QR apunta a una IP de tu red
local y el celular se conecta directo. Lo único que hace falta es que ambos estén en la
*misma* red — no que esa red tenga salida a internet.

Si no hay red, la prendés vos: **hotspot del celular con los datos apagados**. Sigue creando
una red local, que es todo lo que necesitamos.

Bluetooth no es una alternativa viable, por dos razones independientes: BLE da del orden de
decenas de KB/s y un solo frame pesa 60–90 KB, así que el espejado es imposible; y Safari en
iOS no soporta Web Bluetooth, así que una página web nunca podría usarlo.

Si algún día se quiere eliminar el router del todo, el camino es **WiFi peer-to-peer (AWDL)**,
lo mismo que usa AirDrop, vía `NWParameters.includePeerToPeer`. Da ancho de banda de sobra,
pero requiere una app iOS nativa — y eso cuesta la magia de no instalar nada.

## Distribución

La web **no se hostea en ningún lado**: la sirve tu Mac. Subirla a un hosting rompería
justamente el funcionamiento sin internet.

La Mac App Store no es una opción: las apps en sandbox no pueden obtener el permiso de
Accesibilidad, y sin eso no podemos pasar las diapositivas. Es el mismo motivo por el que
Rectangle, Karabiner y BetterTouchTool se distribuyen fuera de la tienda.

El camino correcto con licencia de desarrollador es **Developer ID + notarización**, y un
`.dmg` descargable desde una landing propia. Ahí sí entra Vercel: para la página de
`velarium.app`, no para la app.

```bash
./Scripts/release.sh          # firma, notariza, grapa y arma el .dmg
cp build/Velarium.dmg site/   # queda servido en /Velarium.dmg
vercel deploy site --prod     # requiere: npm i -g vercel
```

`release.sh` verifica que exista un certificado **Developer ID Application** antes de
empezar. El que tenés ahora es **Apple Development**, que sirve para correr la app en tu
Mac pero no para distribuirla: hay que crear el otro en developer.apple.com.

La landing vive en [`site/index.html`](site/index.html); para verla, `open site/index.html`.

## Próximo

- Puntero láser: arrastrar el dedo dibuja un punto sobre la proyección.
- Notas del orador en el celular.
- HTTPS con certificado propio, para recuperar el Wake Lock.
