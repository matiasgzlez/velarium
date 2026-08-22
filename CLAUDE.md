# CLAUDE.md

Notas para trabajar en Velarium. Lo que está acá vale para todo el repo.

## Qué es

App de macOS que espeja la pantalla de la Mac al navegador del celular y recibe de vuelta
gestos convertidos en pulsaciones de teclado, para pasar diapositivas sin volver a la mesa.
El celular no instala nada: la Mac le sirve una web app por la red local y el QR lleva
adentro la dirección y el token.

## Reglas de trabajo

- **Los commits no llevan coautoría.** Nada de `Co-Authored-By: Claude`, ni de "Generated
  with Claude Code" en los cuerpos de PR. Los commits van firmados sólo por Matías.
- Mensajes de commit **en español**, como el resto del proyecto. Título en una línea, y
  cuerpo que explique *por qué*, no *qué* — el diff ya dice qué.
- Antes de pushear a un repo público, revisar que no se filtren credenciales. El token de
  la app se genera en runtime con `UUID()`, y `Scripts/release.sh` usa placeholders.

## Voz

Español rioplatense, con voseo: *escaneás*, *pasás*, *conectá*, *prendé*. Nunca *escanea
tú* ni *usted*.

Frases cortas. Se dice qué hace algo, no qué tan bueno es. Nada de "potente", "increíble",
"revolucionario". Si una oración se puede borrar sin perder información, se borra: la
landing pasó de tener párrafos de tres líneas por tarjeta a una sola línea, y quedó mejor.

Los números concretos valen (`~13 Mbps`, `macOS 14+`); los adjetivos vagos no.

## Estilo visual

La landing (`site/index.html`) es la referencia. La app (`Sources/Velarium/Style.swift`)
copia sus valores para que abrir Velarium se parezca a la página de la que se bajó. Si
cambia uno, cambia el otro.

### Paleta

Un solo tema claro, sin variante oscura, con todo pintado explícitamente.

| Rol | Valor | Uso |
|---|---|---|
| `--bg` | `#fafafa` | fondo de la página y de la ventana |
| `--surface` | `#ffffff` | tarjetas |
| `--border` | `#ececec` | borde de 1px de las tarjetas |
| `--text` | `#1a1a1a` | texto y rótulos |
| `--text-soft` | `#3a3a3a` | párrafos |
| `--solid` | `#2e2e2e` | botones |

Es monocroma. El único color es el naranja de "falta un permiso" en la app, porque ahí hay
algo que hacer. **No hay grises claros para texto**: se probaron y se sacaron, todo rótulo
va en `--text`.

### Tipografía

- **Títulos y cuerpo**: Manrope, peso 800 para títulos, 500 para cuerpo, `letter-spacing`
  negativo (`-0.035em`) en los títulos.
- **Rótulos chicos** (etiquetas, pies, valores de tabla, números de paso): Nunito 800/900 —
  redonda y gruesa. Antes eran mono gris fino y no gustaron.
- En la app, el equivalente de sistema: San Francisco, y `.rounded` donde la web usa Nunito.

### Formas

- Tarjetas: radio 20px, borde de 1px, sombra apenas perceptible.
- Botones: píldora negra (`border-radius: 999px`), texto blanco.
- Iconos: trazo de 1.7px, `currentColor`, sin relleno.

### Qué no hacer

- No agregar tema oscuro a la landing.
- No dejar tarjetas con un título de dos líneas al lado de otras de una: desalinea la fila.
- No usar rótulos sueltos y chiquitos como encabezado de sección; va un `h2`.

## Comandos

```bash
./Scripts/build-app.sh              # compila y arma build/Velarium.app
open build/Velarium.app             # ojo: si ya hay una instancia, la reactiva
killall Velarium                    # matala antes de probar un binario nuevo

python3 -m http.server 4321 --directory site   # la landing, que no tiene build
```

## Trampas conocidas

- **El zoom no amplía la captura.** Se probó y se descartó: agrandar un bitmap
  siempre pierde nitidez, y encima el overlay que lo dibujaba se capturaba a sí
  mismo y quedaba fuera del duplicado por AirPlay. Ahora se le manda ⌘+ a la app
  de adelante, que redibuja nítida. El costo: no funciona en Keynote ni
  PowerPoint en modo presentación, que ignoran ese atajo.
- **Los keycodes son posiciones, no caracteres.** `0x18` es la tecla que da `=` en
  un teclado US y otra cosa en uno español; con Spanish-ISO el atajo llegaba como
  ⌘ más una tecla cualquiera y no pasaba nada. `InputController.keyPosition(of:)`
  resuelve la posición contra el layout activo. Ojo al agregar atajos nuevos.
- **`Bundle.module` no sirve acá.** En un target ejecutable busca los recursos al lado del
  binario, no en `Contents/Resources`, y aborta el proceso si no los encuentra en vez de
  devolver nil. Se usa `AppDelegate.locateWebRoot()`.
- **Los permisos se atan a la firma.** Una firma ad-hoc cambia de hash en cada compilación,
  así que macOS revoca el permiso concedido aunque el interruptor siga activado en Ajustes.
  `build-app.sh` firma con el certificado *Apple Development* si existe, que da una firma
  estable. Si los permisos quedan raros: `tccutil reset ScreenCapture app.velarium.mac`.
- **Rutas absolutas en la landing.** `href="/algo"` se rompe al abrir el HTML con `file://`,
  porque apunta a la raíz del disco. Van relativas.
- **`.build` guarda rutas absolutas.** Si se mueve o renombra la carpeta del proyecto, hay
  que borrarlo o la compilación falla con `missing required module 'SwiftShims'`.

## Dónde está cada cosa

| | |
|---|---|
| `Sources/Velarium/` | la app: captura, servidores, gestos, overlay de zoom |
| `Sources/Velarium/Web/` | la web app que se sirve al celular |
| `Sources/Velarium/Style.swift` | la paleta y las formas, espejo de la landing |
| `site/index.html` | la landing, un solo archivo sin build |
| `docs/arquitectura.md` | cómo está armado y qué falta probar |
| `docs/decisiones.md` | por qué no App Store, por qué no Bluetooth |
