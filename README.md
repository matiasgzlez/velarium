# Velarium

**Tu Mac, en tu mano.** Espejá la pantalla de tu Mac en el celular y pasá las diapositivas
desde ahí. Escaneás un QR y listo: sin instalar nada en el teléfono, sin cuentas, sin
internet.

- **Espeja tu pantalla** — ves en el celular lo mismo que ve el público, sin darte vuelta.
- **Pasa las diapositivas** — anda con Keynote, PowerPoint, PDF y Slides, porque manda las
  mismas teclas que apretarías vos.
- **Amplía para el fondo** — pellizcás en el celular y el proyector hace zoom.

Todo por la red local: tus diapositivas no salen de tu Mac.

## Uso

```bash
./Scripts/build-app.sh
open build/Velarium.app
```

macOS pide dos permisos la primera vez:

| Permiso | Para qué |
|---|---|
| Grabación de pantalla | Ver tu pantalla para retransmitirla |
| Accesibilidad | Mandar las flechas que pasan las diapositivas |

Después apuntás la cámara al QR y ya estás controlando: la URL y el token viajan adentro
del código, así que escanear *es* emparejar.

### Gestos

| Gesto | Qué hace |
|---|---|
| Deslizar ← / → | Diapositiva anterior / siguiente |
| Tocar mitad izquierda / derecha | Lo mismo, para cuando deslizar no sale |
| Pellizcar | Zoom sobre lo que ve el público |
| Arrastrar con zoom activo | Mover la zona ampliada |
| Tocar el reloj | Reiniciar el cronómetro |

## Si no conecta

Casi siempre es el WiFi institucional: muchas redes tienen **aislamiento de clientes**, así
que el celular y la Mac están en la misma red pero no se ven entre sí. La salida es no
depender de esa red — prendé el hotspot del celular y conectá la Mac ahí. El QR se regenera
solo con la IP nueva.

## Cómo funciona

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

Tres decisiones sostienen todo lo demás:

1. **El celular no instala nada.** La Mac sirve una web app por HTTP local. Un paso, no dos.

2. **Solo se manda lo que cambió.** ScreenCaptureKit marca cada frame como `.complete` o
   `.idle`; con diapositivas quietas no se transmite nada. El pico medido con la pantalla
   cambiando a 20fps es ~13 Mbps.

3. **El zoom se dibuja dos veces.** La Mac pone una ventana sobre el proyector con el frame
   ampliado (`sharingType = .none`, para no capturarse a sí misma) y el celular aplica el
   mismo transform en CSS. El presentador ve lo mismo que el público sin gastar un byte más.

Además, los frames se descartan si el celular todavía está recibiendo el anterior: una
conexión lenta pierde calidad pero nunca acumula retraso. Los puertos son efímeros, así que
nunca chocan con otra cosa que estés corriendo.

## Estado

MVP funcionando. Verificado de punta a punta: captura, transporte, autenticación por token
y rechazo de clientes sin token.

Falta probar en vivo, con proyector y celular de verdad:

- Que el overlay de zoom quede por encima del modo presentación de Keynote a pantalla
  completa. Está en `CGShieldingWindowLevel() + 1`, que debería alcanzar, pero Keynote es
  quisquilloso con eso.
- Latencia real sobre WiFi institucional.

Limitación conocida: sobre HTTP local no hay contexto seguro, así que la API de Wake Lock no
está disponible y la pantalla del celular se puede apagar sola. Por ahora conviene poner el
bloqueo automático en *Nunca* antes de exponer.

## Distribución

```bash
./Scripts/release.sh          # firma, notariza, grapa y arma el .dmg
cp build/Velarium.dmg site/   # queda servido en /Velarium.dmg
vercel deploy site --prod     # requiere: npm i -g vercel
```

La landing es un HTML estático sin build, en [`site/index.html`](site/index.html). Para
verla en local: `python3 -m http.server 4321 --directory site`.

Por qué no la App Store, por qué no Bluetooth y qué certificado hace falta:
[`docs/decisiones.md`](docs/decisiones.md).

## Próximo

- Puntero láser: arrastrar el dedo dibuja un punto sobre la proyección.
- Notas del orador en el celular.
- HTTPS con certificado propio, para recuperar el Wake Lock.

---

El *velarium* era el toldo que los romanos tendían sobre el Coliseo para el público: la
pantalla gigante sobre la audiencia.
