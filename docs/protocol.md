# Protocolo de control — Bose QC Ultra Earbuds (2.ª gen.)

> **Estado: borrador para revisión.** Todo lo de este documento sale de la captura
> `docs/captures/btsnoop_hci.log` (móvil Android → auriculares, 13-11-2026, 16:31:39–16:38:26).
> La captura no se publica: contiene datos personales del teléfono y de los auriculares. Los nombres
> de los modos personalizados del usuario se han sustituido por «Personalizado A/B/C»
> y de `docs/discovery/`. Cada afirmación lleva una etiqueta:
>
> - **[observado]**: aparece literalmente en la captura.
> - **[hipótesis]**: interpretación mía, coherente con lo observado, pero sin prueba directa.
> - **[pendiente de confirmar]**: no hay datos suficientes; requiere otra captura o prueba.
>
> Reproducible con: `python3 -I tools/capture-analysis/ch2_messages.py docs/captures/btsnoop_hci.log [prefijo_hex]`

## 1. Transporte

- **[observado con bt-control]** En macOS 26, `IOBluetoothDevice.isConnected()` devuelve `false` desde
  un proceso de terminal aunque el sistema tenga la conexión; abrir el canal RFCOMM sí funciona.
- **[observado]** El control va por **Bluetooth clásico, RFCOMM canal 2** (DLCI 0x04), sobre la
  conexión ACL con los auriculares. En SDP ese canal es el registro "SPPS De", clase
  `SerialPort` (0x1101). Volumen: 4 109 tramas (1 279 enviadas, 2 830 recibidas).
- **[observado]** BLE (ATT) tiene solo 54 paquetes, que son lecturas/descubrimiento. No hay
  escrituras de control por BLE. **No se usará BLE.**
- **[observado]** RFCOMM canal 22 (`DF21FE2C-…`) tiene 8 tramas al conectar (16:31:43) con otro
  formato. **[hipótesis]** es un servicio del sistema Android (no de la app de Bose). Se ignora.
- **[observado]** RFCOMM canal 10 es manos libres (HFP). Se ignora.

## 2. Formato de mensaje

```
+------+------+------+------+-------------------+
|  b0  |  b1  |  op  | len  | carga (len bytes) |
+------+------+------+------+-------------------+
```

- **[observado]** Con esta regla se trocean las 4 109 tramas en 4 380 mensajes sin que sobre
  ningún byte. A veces van varios mensajes concatenados en una trama.
- **[hipótesis]** `b0` = bloque funcional, `b1` = función dentro del bloque, `op` = operación.
- Valores de `op` vistos y su comportamiento:

| op | Sentido | Observado | Hipótesis |
|----|---------|-----------|-----------|
| 01 | → | casi siempre `len=0`; la respuesta trae el mismo `b0 b1` con op 03 | GET |
| 02 | → | lleva carga; respuesta op 03 con el estado nuevo | SET |
| 05 | → | respuestas op 03 (y a veces 06 y/o 07) | SET con confirmación / "iniciar"; con `b1=01` y `len=0` vuelca todo el bloque |
| 03 | ← | datos/estado | respuesta o notificación de estado |
| 04 | ← | p. ej. `01 26 04 01 04` | error **[pendiente de confirmar]** |
| 06, 07 | ← | `len=0` en general | acuses de recibo **[pendiente de confirmar]** |

## 3. Modo de cancelación de ruido

### 3.1 Lista de modos (`1f 06`)

- **[observado]** `→ 1f 06 05 00` provoca 11 respuestas `← 1f 06 03 30 …` (48 bytes), una por
  ranura, terminadas en `← 1f 06 06 00`.
- **[observado]** El índice de ranura es el primer byte de la carga y el nombre en ASCII,
  rellenado con ceros, empieza en el byte 7 de la carga:

| Índice | Nombre (en la captura) |
|--------|------------------------|
| 00 | Quiet |
| 01 | Aware |
| 02 | Immersion |
| 03 | Cinema |
| 04 | Personalizado A |
| 05 | Personalizado B |
| 06 | None → «Personalizado C» (creado durante la captura, 16:33:39) |
| 07–0a | None |

- **[observado]** `→ 1f 06 01 01 <idx>` devuelve solo el registro de esa ranura.
- **[observado]** `→ 1f 06 02 28 <idx> …` (40 bytes) crea o modifica una ranura (nombre incluido).
  **No se usará**: modifica la configuración guardada en los auriculares.
- **[pendiente de confirmar]** Significado del resto de bytes del registro de 48 bytes.
- **[hipótesis]** Los índices 00–02 son fijos (Quiet/Aware/Immersion) y el resto,
  modos personalizados. Para la app conviene **leer la lista** en vez de fijar índices.

### 3.2 Leer el modo actual (`1f 03`)

- **[observado]** `→ 1f 03 01 00`  ⇒  `← 1f 03 03 01 <idx>`

### 3.3 Cambiar de modo (`1f 03`)

- **[observado]** `→ 1f 03 05 02 <idx> 01`  ⇒  `← 1f 03 03 01 <idx>`, `← 1f 03 06 01 <idx>`
  (más una notificación `← 1f 0a 03 05 …`, ver 3.4).
- Cambios observados en orden:

| Hora | Envío | Modo |
|------|-------|------|
| 16:33:15 | `1f 03 05 02 04 01` | Personalizado A |
| 16:33:21 | `1f 03 05 02 00 01` | Quiet |
| 16:33:24 | `1f 03 05 02 02 01` | Immersion |
| 16:33:27 | `1f 03 05 02 05 01` | Personalizado B |
| 16:33:29 | `1f 03 05 02 03 01` | Cinema |
| 16:33:30 | `1f 03 05 02 03 01` | Cinema (repetido) |
| 16:33:46 | `1f 03 05 02 00 01` | Quiet |

- **[observado con bt-control, 13-11-2026 17:14]** Aware: `1f 03 05 02 01 01` funciona.
  Secuencia probada Aware → Immersion → Quiet; cada cambio verificado después con `1f 03 01 00`.
- **[observado con bt-control]** Desde el Mac la única confirmación que llega es
  `← 1f 03 06 01 <idx>`; no llega `1f 03 03`. **[hipótesis]** `1f 03 03` es una notificación que
  solo se envía a otros clientes o tras algún registro que hace la app. El cliente acepta cualquiera de las dos.
- **[pendiente de confirmar]** Significado del último byte (`01` en todos los casos).

### 3.4 Notificación `1f 0a`

- **[observado]** Acompaña a cada cambio de modo: `← 1f 0a 03 05 <5 bytes>`. Ejemplos:
  Quiet → `00 00 00 00 01`, Immersion → `00 00 02 00 01`, Cinema → `00 00 01 00 01`,
  Personalizado A y B → `05 00 00 00 01`.
- **[pendiente de confirmar]** Significado. No es necesario para cambiar de modo.

## 4. Batería

- **[observado]** No hay ninguna petición explícita de batería en la captura. El dato aparece
  dentro del volcado del bloque 02, provocado por `→ 02 01 05 00` (16:32:34):

```
← 02 02 03 10 | 64 ff ff 01 | 64 ff ff 02 | 64 ff ff 04 | 5a ff ff 03
```

- **[hipótesis]** Son 4 entradas de 4 bytes `[nivel %] ff ff [id componente]`:
  0x64 = 100 % (ids 01, 02, 04) y 0x5a = 90 % (id 03).
- **[observado]** Lo corrobora el canal 22 al conectar: `03 03 00 03 64 64 5a` (100, 100, 90).
- **[pendiente de confirmar]**
  - **[observado por el usuario, 13-11-2026 17:18]** La app del usuario indicaba auriculares al
    100 % y estuche al 90 %; el único valor al 90 % es el id 03. **[hipótesis]** id 03 = estuche.
  - **[observado con la app, 13-11-2026 18:04]** Con el auricular derecho fuera y el izquierdo dentro
    del estuche, el mensaje pasa a tener 3 entradas (`64 ff ff 01 | 64 ff ff 04 | 5a ff ff 03`): desaparece
    el id 02. **[hipótesis]** 02 = izquierdo, 01 = derecho. Para confirmarlo: al revés (izquierdo fuera,
    derecho dentro) debería desaparecer el 01.
  - Qué es el id 04 (100 %) y qué significan `ff ff`.
  - Si `→ 02 02 01 00` (GET directo, por analogía con op 01) funciona. No está observado.
  - Si los auriculares notifican cambios de batería sin pedirlo. En los 6 min de captura no
    hubo ninguna notificación `02 02` adicional.

## 5. Ecualizador (`01 07`)

- **[observado]** Lectura: no hay GET directo en la captura. El estado llega dentro del volcado del
  bloque 01 que provoca `→ 01 01 05 00` (la app lo envía al arrancar). Es el que usan bt-control y la app.
- **[observado]** Estado inicial (16:32:34): `← 01 07 03 0c | f6 0a 04 00 | f6 0a 02 01 | f6 0a 02 02`
- **[observado]** `→ 01 07 02 02 <valor> <banda>`  ⇒  `← 01 07 03 0c` con las 3 bandas:

| Hora | Envío | Estado devuelto (valor por banda 00/01/02) |
|------|-------|--------------------------------------------|
| 16:33:58 | `02 00` | 2 / 2 / 2 |
| 16:34:00 | `03 00` | 3 / 2 / 2 |
| 16:34:06 | `04 02` | 3 / 2 / 4 |
| 16:34:06 | `03 02` | 3 / 2 / 3 |
| 16:34:11 | `02 02` | 3 / 2 / 2 |

- **[hipótesis, reforzada]** Cada banda va en 4 bytes `[mín] [máx] [valor] [banda]` con mín = 0xf6 (−10) y
  máx = 0x0a (+10). El valor negativo se codifica con signo (ver abajo).
- **[observado, 13-11-2026 18:06]** El usuario ve en la app de Bose Graves +3, Medio +2, Agudos +2 y
  bt-control lee banda 0 = 3, 1 = 2, 2 = 2 → **banda 0 = Graves**. **[hipótesis]** 1 = Medio y 2 = Agudos
  (orden de la app de Bose, de izquierda a derecha; los dos valían +2 y no se distinguen).
- **[observado con bt-control, 13-11-2026 18:11]** Valores negativos: entero con signo de 8 bits.
  `→ 01 07 02 02 ff 02` ⇒ `← … f6 0a ff 02` (Agudos = −1); se mantuvo y se restauró a +2. Eso confirma
  también mín. `f6` = −10 y máx. `0a` = +10 como enteros con signo.
- **[pendiente de confirmar]** Si existen presets.
- El EQ queda fuera del alcance de las fases 3–4. Se documenta como referencia.

## 6. Otros mensajes vistos (sin uso previsto)

- **[observado]** `00 xx`: información del dispositivo (versión de firmware, nombre, número de
  serie, MAC) al arrancar la app. `01 02 03` contiene el nombre del dispositivo.
- **[observado]** `0d 07` / `0d 08`: ~350 mensajes cada uno, periódicos hasta el final de la
  captura y con contenido de alta entropía.
  **[hipótesis]** Es un túnel cifrado (¿autenticación o nube?) de la app.
- **[observado]** `04 04`, `04 05`, `05 01`, `05 03`, `05 04`, `05 06`: sondeo periódico. `04 05` contiene el nombre del
  teléfono. **[hipótesis]** Información de dispositivos conectados o multipunto.

## 7. Dudas abiertas (antes de la fase 3)

1. ~~Inicialización / autenticación~~ **[observado con bt-control]** No hace falta: tras abrir
   RFCOMM 2, los auriculares responden a `1f 03 01`, `1f 06 05`, `02 01 05` y `1f 03 05` sin la
   secuencia inicial de la app y sin el túnel `0d`.
2. ~~Comando para Aware~~ Confirmado (sección 3.3).
3. Petición directa de batería (sección 4). Además, `02 01 05` devolvió a las 17:0x los mismos
   valores que la captura (100/100/100/90): **[pendiente de confirmar]** que el dato se actualice.
   **[observado en Android, 17-11-2026]** El estuche pasó a `0x50` (80 %): el dato sí se actualiza (sección 8).
4. Sugerencia para una segunda captura corta: Quiet → Aware → Immersion → Aware → Quiet,
   ~10 s entre pasos, apuntando la hora; abrir la pantalla de batería con el estuche abierto y
   luego cerrado.

## 8. Observaciones en Android

Con la app Android ([boseAndroidMgr](https://github.com/guilleml/boseAndroidMgr)) en un
Pixel 11 Pro con Android 17, 17-11-2026, 13:05–13:16. Se ha omitido el nombre de los
modos personalizados.

### 8.1 Transporte

- **[observado en Android]** `BluetoothDevice.createRfcommSocketToServiceRecord(UUID 0x1101)`
  abre el canal de control: los auriculares responden a los comandos de las secciones 3–5. La API
  pública no informa del número de canal RFCOMM elegido por SDP. **[hipótesis]** es el 2.
- **[observado en Android]** Tampoco hace falta la secuencia inicial ni el túnel `0d` (como en §7.1).
- **[observado en Android]** El canal se abre y funciona con el proceso de la app oficial en
  ejecución. **[pendiente de confirmar]** si la app oficial tenía su canal abierto en ese momento.
- **[observado en Android]** Una vez, los auriculares cerraron el canal (fin de flujo) ~0,5 s después
  de responder a las lecturas iniciales, justo después de que se abriera la app oficial. No se repitió en las
  conexiones siguientes. **[pendiente de confirmar]** la causa.

### 8.2 Modos

- **[observado en Android]** `→ 1f 06 05 00` ⇒ `← 1f 06 07 00`, 11 × `← 1f 06 03 30 …`, `← 1f 06 06 00`.
  El registro de la ranura 01 «Aware» coincide byte a byte con el de la captura.
- Nota sobre §3.1: el nombre empieza en el byte 7 de la carga contando desde 1, es decir, en el
  índice 6 contando desde 0 (lo que usan BoseKit y la app Android).
- **[observado en Android]** `→ 1f 03 01 00` ⇒ `← 1f 03 03 01 <idx>`.
- **[observado en Android]** Quiet → Aware → Immersion → Quiet con `1f 03 05 02 <idx> 01`: la única
  confirmación es `← 1f 03 06 01 <idx>`, en 0,2–0,7 s. No llegaron `1f 03 03` ni `1f 0a` (igual que con bt-control, §3.3).

### 8.3 Batería

- **[observado en Android]** `02 02 03 10 | 64 ff ff 01 | 64 ff ff 02 | 64 ff ff 04 | 50 ff ff 03`:
  auriculares al 100 % y estuche (id 03) al 80 %. El dato se actualiza respecto a la captura (90 %).

### 8.4 Ecualizador

- **[observado en Android]** Estado leído: `f6 0a 07 00 | f6 0a 00 01 | f6 0a 07 02` (+7 / 0 / +7).
- **[observado en Android]** Banda 1 (Medio): 0 → +1 → −1 → 0 con `01 07 02 02 <valor> 01`. Cada
  respuesta `01 07 03 0c` trae las 3 bandas y solo cambia la banda 1; −1 se recibe como `ff`.

### 8.5 Estuche y apagado

- **[observado en Android, 17-11-2026]** Con el canal de control abierto, los auriculares tardaron en
  desconectarse ~2 min 40 s tras cerrar la tapa del estuche (cierre ~14:01:00, el sistema pierde el
  enlace a las 14:03:39) y ~3 min en una prueba anterior (~13:49 → 13:52:19). Sin el canal abierto
  (app en segundo plano), el enlace cayó a los pocos segundos (conexión 14:04:23, desconexión 14:04:34).
  **[hipótesis]** un canal RFCOMM abierto retrasa el apagado en el estuche. Pocas muestras.
- **[observado en Android]** Al apagarse, se cierran a la vez el audio (A2DP/HFP) y el canal RFCOMM
  (la lectura del socket devuelve fin de flujo).
- **[observado en Android]** Con la tapa cerrada y el canal aún abierto, `02 02 03` seguía trayendo los
  ids 01 y 02 (14:02:49). Matiza la hipótesis de §4 (id ausente = auricular en el estuche): quizá solo
  aplica con la tapa abierta. **[pendiente de confirmar]**
- **[observado en Android]** Con los auriculares apagados en el estuche cerrado, abrir RFCOMM falla a los
  ~5 s y no los vuelve a conectar (5 intentos seguidos, 13:58:35–13:59:47).

### 8.6 Otros mensajes del volcado (sin uso previsto)

- **[observado en Android]** `01 00 03 05` y `02 00 03 05` contienen el texto ASCII `1.1.0`.
  **[hipótesis]** versión de firmware.
- **[observado en Android]** `02 14 03 04` cambia entre lecturas: `00 00 85 7d` (13:05:41),
  `00 00 85 90` (13:06:00), `00 00 87 0c` (13:12:20). **[pendiente de confirmar]** significado.
- **[observado en Android]** `02 05 03 01` valía `01` (13:05–13:06) y `00` (13:12–13:13).
  **[pendiente de confirmar]** significado.
