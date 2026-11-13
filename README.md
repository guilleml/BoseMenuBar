# Bose QC Ultra Earbuds (2.ª gen.) — control desde la barra de menús de macOS

App de barra de menús para macOS que muestra la batería y cambia el modo de cancelación de ruido
y el ecualizador de los **Bose QuietComfort Ultra Earbuds (2.ª generación)**, más dos herramientas
de línea de comandos para descubrir y probar el protocolo.

> Proyecto no oficial, sin relación con Bose Corporation. «Bose» y «QuietComfort» son marcas de
> sus respectivos propietarios. El protocolo se ha documentado observando el tráfico entre la app
> oficial y unos auriculares propios, con fines de interoperabilidad. Úsalo bajo tu responsabilidad.

## Funciones

- **Barra de menús**: icono de auriculares con barrita de batería (el auricular con menos carga).
- **Menú**: batería del auricular izquierdo, el derecho y el estuche; selector de modo
  (Quiet, Aware, Immersion); acceso a la ventana del ecualizador.
- **Ecualizador**: ventana con la curva de 3 bandas (Graves, Medio, Agudos, de −10 a +10).
  Se arrastra con el ratón o se escriben los valores.
- **Reconexión automática**: reintenta tras perder la conexión (2, 5, 10 y 30 s, máx. 10 s por
  intento) y después espera al aviso del sistema de que los auriculares se han reconectado.
- Sin icono en el Dock y sin ventana principal.

## Requisitos

- macOS 13 o superior.
- Xcode 16 o superior (probado con Xcode 26.5 y Swift 6.3).
- Los auriculares emparejados con el Mac.

## Estructura

```
app/                      App de barra de menús (proyecto de Xcode, SwiftUI + MenuBarExtra)
tools/bt-control/         Paquete Swift:
  Sources/BoseKit/          biblioteca con el protocolo y la conexión RFCOMM (la usa la app)
  Sources/bt-control/       cliente de línea de comandos
  Tests/BoseKitTests/       pruebas con mensajes reales de la captura
tools/bt-discover/        Lista servicios SDP (RFCOMM) y GATT (BLE) de un dispositivo
tools/capture-analysis/   Script para extraer los mensajes de una captura btsnoop (requiere tshark)
docs/protocol.md          Protocolo documentado, con lo observado separado de las hipótesis
docs/discovery/           Resumen de los servicios Bluetooth del dispositivo
```

## Compilar y ejecutar

### App

Abre `app/BoseMenuBar.xcodeproj` en Xcode y ejecuta (⌘R), o desde la terminal:

```sh
cd app
xcodebuild -project BoseMenuBar.xcodeproj -scheme BoseMenuBar -configuration Release -derivedDataPath build build
open build/Build/Products/Release/BoseMenuBar.app
```

La primera vez macOS pedirá permiso para usar Bluetooth. La app se firma de forma local
(«Sign to Run Locally»); para distribuirla habría que firmarla con un Developer ID.

### Línea de comandos

```sh
cd tools/bt-control
swift build
swift test                       # pruebas de BoseKit
.build/debug/bt-control battery  # batería
.build/debug/bt-control mode     # modo actual
.build/debug/bt-control modes    # modos guardados en los auriculares
.build/debug/bt-control mode aware
.build/debug/bt-control eq       # ecualizador
.build/debug/bt-control eq 0 3   # banda 0 (Graves) a +3
```

Con `-v` se muestra el tráfico en hexadecimal. Los auriculares solo admiten un cliente en el canal
de control: **cierra la app de la barra de menús antes de usar `bt-control`**.

## Cómo funciona

El control va por Bluetooth clásico, **RFCOMM canal 2** (servicio SerialPort). Cada mensaje es
`[bloque] [función] [operación] [longitud] [datos…]`. Los detalles, con cada afirmación marcada como
observada, hipótesis o pendiente de confirmar, están en [`docs/protocol.md`](docs/protocol.md).

Las capturas de tráfico usadas para documentarlo **no se incluyen**: contienen datos personales.
Si quieres generar las tuyas, activa el registro HCI de Bluetooth en las opciones de desarrollador
de Android, usa la app oficial, extrae `btsnoop_hci.log` del bugreport y guárdalo en
`docs/captures/` (está en `.gitignore`).

## Limitaciones conocidas

- Probado solo con un par de auriculares, firmware 8.4.8.
- Batería: el componente 04 no está identificado; el izquierdo/derecho se dedujo de una sola prueba.
- Bandas del EQ: la banda 0 (Graves) está confirmada; Medio y Agudos se asignaron por orden.
- Los cambios hechos desde el Mac no se reflejan en la app del móvil hasta que esta vuelve a leer
  el estado.
- En macOS 26, `IOBluetoothDevice.isConnected()` no es fiable desde un proceso de terminal; las
  herramientas intentan abrir el canal directamente.

## Licencia

Copyright (C) 2026 guilleml

Este programa es software libre: puedes redistribuirlo y/o modificarlo bajo los términos de la
**GNU General Public License versión 3** publicada por la Free Software Foundation. Si lo usas o
creas una obra derivada, debes conservar este aviso de autoría y publicar el código fuente de tu
versión bajo la misma licencia.

Se distribuye SIN NINGUNA GARANTÍA. Consulta el texto completo en [`LICENSE`](LICENSE).
