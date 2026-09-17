# Recorta ✂️

Recorta es una aplicación gratuita y de código abierto para macOS. Abre una carpeta y permite recortar fotografías en una secuencia continua: encuadrar, presionar Enter y continuar.

La versión 0.1 beta requiere macOS 14 o posterior y un Mac con Apple Silicon.

Sitio oficial: [recorta-delta.vercel.app](https://recorta-delta.vercel.app/)

## Descargar

Descarga [Recorta 0.1 Beta para Apple Silicon](https://github.com/seba2020/recorta/releases/download/v0.1.0-beta/Recorta-0.1.0-beta-macOS-Apple-Silicon.zip). Después de intentar abrirla por primera vez, autorízala en **Ajustes del Sistema → Privacidad y seguridad → Abrir igualmente**.

SHA-256:

```text
8a8885c2f72e11e37490bf8a980eb57fee55ccaadd552ebe0074c5c674da618a
```

## Compilar

Ejecuta `./build-app.sh` en este directorio (requiere las herramientas de desarrollo de Apple). Abre `dist/Recorta.app`; puedes arrastrarla a Aplicaciones. El paquete también se puede abrir en Xcode mediante `Package.swift`.

## Uso

- Barra lateral: miniaturas de la carpeta con selección directa. La foto activa se resalta y el listado la sigue al avanzar; las miniaturas se actualizan al recortar o deshacer.
- ⌘O: elegir carpeta. Lee JPEG, PNG, HEIC y TIFF de esa carpeta, sin subcarpetas.
- Arrastrar: dibujar un recorte. Arrastrar dentro de una selección: moverla. Arrastrar una esquina: ajustar.
- ⌥ + arrastrar: dibujar una selección nueva dentro de la actual.
- Enter: guardar y continuar. Si está seleccionada toda la foto, avanza sin volver a codificarla.
- Mantén las flechas para reducir continuamente el recorte: ↓ baja el borde superior; ↑ sube el inferior; ← acerca el derecho; → acerca el izquierdo. No depende de la repetición del teclado de macOS. Recorre el 25 % de la dimensión original por segundo; con Mayúsculas, el 60 %. Al soltar se detiene. Esc recupera el encuadre completo.
- ⌥ + flechas: ampliar nuevamente el borde correspondiente.
- B: mostrar temporalmente la original cuando existe un respaldo de esa fotografía.
- Espacio: saltar la foto. El botón de retroceso y la barra lateral permiten volver. Esc: restablecer selección.
- ⌘Z: deshacer el último recorte de esta sesión y volver a esa foto.
- Proporciones: Libre, 1:1, 4:3, 3:2 y 9:16.
- Opciones: recordar el último encuadre y elegir la velocidad del teclado.
- Miniaturas: marca las fotografías procesadas y permite mostrar solamente las pendientes.

Cada cambio guarda los bytes anteriores en `.recorta-backups` dentro de la carpeta elegida. El botón «Ver respaldos» abre esa carpeta. Los respaldos persisten al cerrar la app; el historial de ⌘Z dura hasta que se abre otra carpeta o se cierra la app. Se recuerda la última foto visitada por carpeta y se ofrece continuar desde la pantalla inicial.

El guardado usa reemplazo atómico y comprueba cambios externos antes de escribir. Los originales no se modifican si falla la codificación o el respaldo. No se editan enlaces simbólicos ni archivos con varias imágenes/páginas. Las fotos se normalizan según su orientación EXIF antes del recorte. Se conserva el formato y se copian los metadatos convencionales, actualizando orientación y dimensiones. JPEG y HEIC se vuelven a comprimir; esta primera versión no promete conservar datos auxiliares HDR, profundidad, Live Photos ni atributos extendidos del archivo.

## Verificación

`./check.sh` (no requiere Xcode completo)

Las pruebas usan archivos sintéticos temporales: recorte y dimensiones, orientación, coordenadas de la zona superior, respaldo exacto, deshacer y protección ante cambios externos.

## Limitaciones conocidas

La beta no está firmada con Developer ID ni notarizada. El script genera una aplicación para la arquitectura del Mac que la compila; la descarga publicada inicialmente es para Apple Silicon. No incluye rotación ni zoom. JPEG y HEIC se vuelven a comprimir al guardar.

## Privacidad y licencia

Recorta procesa todo localmente y no contiene cuentas, anuncios ni analítica. Consulta [PRIVACY.md](PRIVACY.md). El proyecto se distribuye bajo la licencia MIT incluida en [LICENSE](LICENSE).
