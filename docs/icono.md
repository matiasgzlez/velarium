# Prompt para el ícono

Referencia de estilo: Metaflow y NetNewsWire. Fondo casi blanco con degradado sutil, una
sola silueta negra maciza y centrada, con brillo dimensional apenas insinuado y grano fino
sobre todo el tile. Sin color, sin texto, sin contorno.

La clave de ese estilo es la **restricción**: una forma, dos tonos, y todo el trabajo puesto
en que la silueta tenga carácter.

**El ícono tiene que decir qué hace la app.** Tus dos referencias no lo hacen — el pájaro no
dice "lector de RSS" y la M no dice nada — pero se lo pueden permitir porque son marcas
conocidas con años encima. Una app nueva no tiene ese crédito: si el ícono no comunica el
propósito, no comunica nada. Por eso las tres opciones de abajo muestran el trabajo, no el
nombre.

---

## Bloque de estilo (va en las tres)

> A macOS/iOS app icon, 1024×1024, rounded-square (squircle) tile, full bleed.
>
> Background: a very light warm off-white, near cream (#F4F1EA), with a soft vertical
> gradient — barely lighter at the top, settling a touch cooler and darker toward the
> bottom. Almost flat, just enough gradient to give the tile depth. A fine, subtle film
> grain across the whole surface.
>
> Subject: one single solid black silhouette, centred, occupying roughly 60% of the tile.
> The black is not perfectly uniform — a soft gradient runs from a slightly lifted charcoal
> (#2a2a2a) along the upper edges into pure black (#000) in the mass, so the shape reads as
> having gentle volume and a soft sheen, like polished stone. A very tight, very soft
> shadow sits directly beneath the shape where it meets the background.
>
> Style: confident, minimal, high contrast. Smooth vector-like curves. No outline, no
> stroke, no text, no letters, no numerals, no UI elements. Monochrome only — no colour
> anywhere except the off-white ground and the black mark.

---

## Opción A — La pantalla y el pulgar  ⭐

Lo que hace la app, en dos formas: la pantalla que proyectás y el dedo que la maneja.

> Subject: a wide projection screen, seen head-on, as a single solid black shape with
> softly rounded corners. Its top edge bows downward in a shallow, even curve, as if the
> surface were a piece of fabric stretched taut between two points — subtle, not a deep
> sag. Rising into the lower half of this screen, cut cleanly out of it as negative space
> so the off-white background shows through, is the silhouette of a thumb mid-swipe:
> entering from the bottom edge, angled, its tip curving toward the right. The thumb is
> simplified to its essential outline — one smooth tapered form, no knuckle detail, no
> nail, no separated joints. The two shapes read as one figure: a screen with a thumb
> moving across it.

## Opción B — El eco

La tesis del producto: la misma imagen en dos lugares a la vez.

> Subject: two screens showing the same thing. A large wide rectangle with softly rounded
> corners, solid black, fills most of the composition — the projected screen. Overlapping
> its lower right corner and extending slightly beyond it sits a smaller upright rounded
> rectangle in the proportions of a phone, also solid black, separated from the large
> shape by a clean gap of off-white background so both silhouettes stay legible where
> they meet. Inside each shape, cut out as negative space, sits the same simplified mark:
> three horizontal bars, one short and two long, identically arranged and scaled to each
> screen. The repetition is the point — the same picture, twice, at two sizes.

## Opción C — El atril

La más literal. Si A y B siguen sin leerse, esta no falla.

> Subject: a presentation screen on a tripod stand, as one solid black silhouette: a wide
> rounded rectangle sitting on a simple splayed tripod base with three straight tapered
> legs. Cut out of the screen as negative space is a bold chevron pointing right, the
> universal mark for "next". Clean, symmetrical, unmistakably a presentation being
> advanced.

---

## Cuál elegir

**A** es la mejor si sale bien: es orgánica, tiene carácter, y se parece a tus referencias.
**B** es la más segura: dos rectángulos aguantan cualquier tamaño y dicen "espejado" sin
ambigüedad, aunque se acerca al ícono genérico de AirPlay. **C** no falla pero tampoco
emociona.

Generá las tres con el bloque de estilo **idéntico**, palabra por palabra. Si lo cambiás
entre una y otra no las podés comparar.

---

## La prueba que importa

Bajá cada resultado a **32×32** y miralo en el Dock, al lado de otros íconos.

- **A** falla si el pulgar se convierte en una mancha sin dirección. Si pasa: engordá el
  pulgar y bajá la curvatura del borde superior, que a ese tamaño no se percibe igual.
- **B** falla si las dos formas se funden en un bloque. Si pasa: agrandá el espacio que
  las separa antes que achicar el teléfono.
- **C** falla si las patas del trípode desaparecen. Si pasa: engrosalas y acortalas.

Ninguna de tus dos referencias tiene detalle fino. Por algo.

---

## Versión para el celular

La web se agrega a la pantalla de inicio, así que necesita su `apple-touch-icon` de 180×180.
Usá **la misma silueta**, pero con el fondo plano (sin degradado ni grano) y la forma un 10%
más gruesa — a ese tamaño el grano se convierte en suciedad y las partes finas desaparecen.

---

## Armar el `.icns`

```bash
mkdir Velarium.iconset
sips -z 16 16     icono-1024.png --out Velarium.iconset/icon_16x16.png
sips -z 32 32     icono-1024.png --out Velarium.iconset/icon_16x16@2x.png
sips -z 32 32     icono-1024.png --out Velarium.iconset/icon_32x32.png
sips -z 64 64     icono-1024.png --out Velarium.iconset/icon_32x32@2x.png
sips -z 128 128   icono-1024.png --out Velarium.iconset/icon_128x128.png
sips -z 256 256   icono-1024.png --out Velarium.iconset/icon_128x128@2x.png
sips -z 256 256   icono-1024.png --out Velarium.iconset/icon_256x256.png
sips -z 512 512   icono-1024.png --out Velarium.iconset/icon_256x256@2x.png
sips -z 512 512   icono-1024.png --out Velarium.iconset/icon_512x512.png
cp                icono-1024.png     Velarium.iconset/icon_512x512@2x.png
iconutil -c icns Velarium.iconset
```

Dejá `Velarium.icns` en `Resources/` del proyecto y el build script lo levanta solo.

---

## v2 — qué corregir de la versión actual

La v1 (`Resources/icono-1024.png`) acertó el estilo y el concepto: es la opción B, el eco.
Lo que falla:

**1. El símbolo dice "fotos", no "presentación".** Adentro de las dos pantallas hay un sol
y una montaña — el ícono universal de galería de imágenes. A simple vista la app parece un
visor de fotos o un AirDrop. Este es el error importante, y es de significado, no de
prolijidad: hay que reemplazarlo por contenido de diapositiva, o sea una barra de título
gruesa y dos líneas de texto debajo.

**2. Demasiado detalle para 32px.** La camarita del laptop, el auricular del teléfono y el
contorno blanco del pulgar desaparecen o se ensucian. A ese tamaño entran unas cuatro
formas, no diez.

**3. El teléfono se funde con la base del laptop.** Al achicarse, los dos objetos se pegan
en una sola mancha. Necesitan un canal de fondo claro entre medio.

### Prompt de la v2

Va con el mismo bloque de estilo de arriba, palabra por palabra, y este subject:

> Subject: two screens showing the same slide. Behind, a laptop reduced to its essentials —
> a wide rounded screen and a simple tapered base, nothing else: no camera dot, no hinge
> detail, no keyboard. In front and below it, a phone: an upright rounded rectangle held at
> a slight tilt, with no earpiece slot and no buttons. A clear channel of background
> separates the phone from the laptop base so the two silhouettes never touch.
>
> Inside each screen, cut out as negative space, sits the same simplified slide: one thick
> horizontal bar across the top, and two thinner bars below it, the second shorter than the
> first. Identical arrangement in both, scaled to each screen. This mark must read as a
> slide of text — never as a landscape, a sun, or a photograph.
>
> A hand holds the phone from below: a single simplified silhouette, only the palm edge and
> one thumb resting on the phone's face, merged into one solid mass with no internal
> outlines and no separated fingers. It occupies the bottom corner and must not compete
> with the screens.
>
> Four shapes total — laptop, phone, slide marks, hand. Nothing else. Both devices sit
> large in the composition, filling it confidently.
