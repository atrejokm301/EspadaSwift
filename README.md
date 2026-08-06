# Espada (SwiftUI)

Estudio bíblico **offline** en español para iPhone y iPad.  
Alternativa nativa y más simple a e-Sword: **un módulo activo por tipo**, toque de palabra → diccionario + léxico Strong + comentario del versículo.

## Principios

1. **Hacer esto → pasa aquello** (toque de palabra sincroniza estudio).
2. **Módulos selectivos** — catálogo completo, solo se abren los elegidos.
3. Cuatro recursos: **Biblia · Comentarios · Diccionarios · Léxicos**.
4. Strong sin memorizar códigos: use una Biblia interlineal (p. ej. iRV 1960+).

## Stack

- SwiftUI · iOS / iPadOS 27+
- [GRDB](https://github.com/groue/GRDB.swift) (SQLite solo lectura)
- Módulos e-Sword: `.bbli` `.cmti` `.dcti` `.lexi`

## Abrir en Xcode

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd ~/EspadaSwift
xcodegen generate
open EspadaSwift.xcodeproj
```

Firma con su Team (por defecto `RV23UF9649` en `project.yml`).

## Importar módulos

1. Pestaña **Módulos** → **Importar módulos e-Sword…**
2. Elija solo los que necesite (no hace falta importar los 148 de golpe).
3. En cada pestaña, use el menú superior para **elegir un solo** módulo activo.

En el **simulador** hay un botón opcional para sembrar módulos de prueba desde  
`~/Downloads/for mac espada`.

## Uso de estudio

1. Abra **Biblia** (puede ser RV1960 normal **o** interlineal).
2. Toque una palabra en español → salta a **Diccionarios**.
3. El mismo toque **resuelve Strong’s** vía la Biblia interlineal instalada (p. ej. iRV 1960+) y actualiza **Léxico** + **Comentario**.
4. El chip de contexto muestra p. ej. `«amó» → G25 ἠγάπησεν (êgapêsen)`.
5. Toque un chip `G25` en modo estudio → salta a **Léxico**.

### Strong’s desde Biblia normal (no hay que abrir el interlineal)

Usted **lee solo RV1960** en la pestaña Biblia. El interlineal (iRV 1960+) se usa **solo en segundo plano** como tabla de mapa — no se abre como texto de lectura.

Al tocar una palabra:

1. Espada lee el **mismo** versículo en el módulo mapa (iRV) en silencio.
2. Empareja la glosa española (`<blu>`) con la palabra tocada.
3. Obtiene `G####` / `H####` + griego/hebreo.
4. Busca ese código en el léxico Strong (los léxicos indexan G/H, no español).

**Requisitos (importar una vez en Módulos):** RV1960 + iRV 1960+ + léxico Strong. No cambie la Biblia de lectura al interlineal.

## Relación con otros proyectos

| Proyecto | Stack | Rol |
|----------|--------|-----|
| `~/Espada3.7` | Tauri + Rust | Mac de referencia |
| `~/EspadaMobile` | Capacitor + sql.js | iOS WebView anterior |
| `~/EspadaSwift` | SwiftUI + GRDB | **Esta app nativa** |

## Licencia de módulos

Los módulos e-Sword son de usted / sus licencias. Esta app es para **uso personal offline**.  
No se descifran módulos DRM (`.bblx` etc. se marcan 🔒).
