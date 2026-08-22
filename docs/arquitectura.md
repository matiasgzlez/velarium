# Arquitectura

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

1. **El celular no instala nada.** La Mac sirve una web app por HTTP local y el QR lleva
   adentro la URL y el token, así que escanear *es* emparejar. Un paso, no dos.

2. **Solo se manda lo que cambió.** ScreenCaptureKit marca cada frame como `.complete` o
   `.idle`; con diapositivas quietas no se transmite nada y el ancho de banda solo sube en
   la transición. El pico medido con la pantalla cambiando a 20fps es ~13 Mbps.

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

Limitación conocida: sobre HTTP local no hay contexto seguro, así que la API de Wake Lock
no está disponible y la pantalla del celular se puede apagar sola. Por ahora conviene poner
el bloqueo automático en *Nunca* antes de exponer.

## Próximo

- Puntero láser: arrastrar el dedo dibuja un punto sobre la proyección.
- Notas del orador en el celular.
- HTTPS con certificado propio, para recuperar el Wake Lock.
