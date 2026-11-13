# Descubrimiento de servicios (fase 1)

Resumen de lo que exponen los Bose QuietComfort Ultra Earbuds (2.ª gen.) con firmware 8.4.8,
obtenido con `system_profiler SPBluetoothDataType` y `tools/bt-discover`.

Las salidas completas no se publican porque contienen las direcciones MAC de todos los
dispositivos emparejados. Para generarlas en tu equipo:

```sh
system_profiler SPBluetoothDataType > docs/discovery/system_profiler.txt
cd tools/bt-discover && swift run bt-discover --scan 8 > ../../docs/discovery/bt-discover.txt
```

## Identificación (registro PnP de SDP)

| Campo | Valor |
|---|---|
| Vendor ID | 0x009E |
| Product ID | 0x4062 |
| Clase de dispositivo | 0x240404 (audio, auriculares) |

## Bluetooth clásico (SDP)

| Canal / PSM | Servicio | UUID |
|---|---|---|
| RFCOMM 2 | "SPPS De" (SerialPort) | `0x1101` — **canal de control** (ver `docs/protocol.md`) |
| RFCOMM 10 | Hands-Free unit | `0x111E` |
| RFCOMM 14 | — | `00000000-DECA-FADE-DECA-DEAFDECACAFF` |
| RFCOMM 22 | — | `DF21FE2C-2515-4FDB-8886-F12C4D67927C` |
| RFCOMM 24 | "SRfcomm" | `9B26D8C0-A8ED-440B-95B0-C4714A518BCC` |
| L2CAP 0x0017 | AVRCP (CT/TG) | `0x110E`, `0x110C`, `0x110F` |
| L2CAP 0x0019 | A2DP (AudioSink) | `0x110B` |
| L2CAP 0xFEFF / 0xFEFD / 0xFEFB | — | `0000EB04/EB06/EB07-D102-11E1-9B23-00025B00A5A5` |
| L2CAP 0xFCFF / 0xFCFD / 0xFCFB | — | `88B0EE3C-…`, `346D5C4B-…`, `77265D41-…` |

## BLE (GATT)

Anuncia el servicio `FEBE`. Servicios primarios:

| Servicio | Características (propiedades) |
|---|---|
| `FEBE` | 4 propietarias (`read/write/writeWithoutResponse/notify` y `read`) |
| `180A` Device Information | fabricante, modelo, serie, versiones |
| `FE2C` | `FE2C1233…1239-8366-4814-8EB0-01DE32100BEA` |
| `0000EB10-D102-11E1-9B23-00025B00A5A5` | `EB11`…`EB14` |
| `FD92` | `0000EB20/EB21/EB22-D102-11E1-9B23-00025B00A5A5` |

En la captura de la app oficial, BLE no se usa para el control: todo va por RFCOMM 2.
