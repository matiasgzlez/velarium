<img src="site/logo.png" width="88" alt="">

# Velarium

**Tu Mac, en tu mano.** Espejá la pantalla de tu Mac en el celular y pasá las diapositivas
desde ahí. Escaneás un QR y listo: sin instalar nada en el teléfono, sin cuentas, sin
internet.

## Qué hace

Estás dando una charla. La presentación corre en tu Mac, conectada al proyector, y cada vez
que hay que pasar una diapositiva tenés que volver a la mesa y darte vuelta a mirar la
pantalla.

Velarium convierte tu celular en esa pantalla y en ese control:

- **Ves lo que ve el público.** El celular muestra en vivo lo que sale por el proyector, así
  que hablás de frente a la gente en vez de leer por encima del hombro.
- **Pasás las diapositivas deslizando el dedo.** Anda con Keynote, PowerPoint, PDF y Slides,
  porque manda las mismas teclas que apretarías vos.
- **Ampliás lo que desde el fondo no se lee.** Pellizcás en el celular y el proyector hace
  zoom para toda el aula.

## Cómo se usa

1. **Abrís Velarium en la Mac.** Detecta el proyector y muestra un QR.
2. **Apuntás la cámara del celular al QR.** Se abre el navegador y ya estás controlando: el
   código lleva la dirección y la clave adentro, así que no hay nada que tipear.
3. **Te alejás de la mesa.**

No hay app que instalar en el teléfono, ni cuenta que crear, ni cable. Lo único que hace
falta es que la Mac y el celular estén en la misma red.

### Gestos

| Gesto | Qué hace |
|---|---|
| Deslizar ← / → | Diapositiva anterior / siguiente |
| Tocar mitad izquierda / derecha | Lo mismo, para cuando deslizar no sale |
| Pellizcar | Zoom sobre lo que ve el público |
| Arrastrar con zoom activo | Mover la zona ampliada |
| Tocar el reloj | Reiniciar el cronómetro |

## Requisitos

- macOS 14 o posterior.
- Cualquier navegador en el celular.
- Los dos en la misma red local. **No hace falta internet**: la Mac le habla al celular
  directo, y tus diapositivas nunca salen de tu Mac.

La primera vez macOS pide dos permisos: **Grabación de pantalla**, para poder retransmitir
lo que ves, y **Accesibilidad**, para poder mandar las flechas que pasan las diapositivas.

## Si no conecta

Casi siempre es el WiFi institucional: muchas redes tienen **aislamiento de clientes**, así
que el celular y la Mac están en la misma red pero no se ven entre sí.

La salida es no depender de esa red — prendé el hotspot del celular y conectá la Mac ahí.
El QR se regenera solo con la dirección nueva. Funciona incluso con los datos móviles
apagados, porque lo único que necesitamos es la red, no internet.

## Instalación

Todavía no hay descarga publicada. Por ahora se compila:

```bash
./Scripts/build-app.sh
open build/Velarium.app
```

## Para desarrollar

- Cómo está armado por dentro, qué falta probar y qué sigue:
  [`docs/arquitectura.md`](docs/arquitectura.md).
- Por qué no la App Store, por qué no Bluetooth y qué certificado hace falta para
  distribuir: [`docs/decisiones.md`](docs/decisiones.md).
- La landing es un HTML estático sin build, en [`site/index.html`](site/index.html). Para
  verla: `python3 -m http.server 4321 --directory site`.

```bash
./Scripts/release.sh          # firma, notariza, grapa y arma el .dmg
cp build/Velarium.dmg site/   # queda servido en /Velarium.dmg
vercel deploy site --prod     # requiere: npm i -g vercel
```
