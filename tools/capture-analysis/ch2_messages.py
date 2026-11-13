#!/usr/bin/env python3
"""Extrae y trocea los mensajes del canal RFCOMM 2 (DLCI 0x04) de una captura btsnoop.

Uso:  python3 -I tools/capture-analysis/ch2_messages.py docs/captures/btsnoop_hci.log [filtro_hex]

  filtro_hex: prefijo opcional de cabecera, p. ej. "1f03" o "0107".

Necesita tshark (Wireshark). Trocea cada trama con la hipótesis observada de
cabecera de 4 bytes [b0 b1 b2 longitud] + carga, reensamblando por sentido.
"""
import subprocess, sys, datetime

def main():
    cap = sys.argv[1]
    prefix = bytes.fromhex(sys.argv[2]) if len(sys.argv) > 2 else b""
    out = subprocess.run(
        ["tshark", "-r", cap, "-Y", "btrfcomm.dlci==0x04 && btrfcomm.len>0",
         "-T", "fields", "-E", "separator=;",
         "-e", "frame.number", "-e", "frame.time_epoch", "-e", "hci_h4.direction", "-e", "btspp.data"],
        capture_output=True, text=True, check=True).stdout
    buf = {"0x00": b"", "0x01": b""}
    leftovers = 0
    for line in out.splitlines():
        fn, t, d, h = line.split(";")
        data = buf[d] + bytes.fromhex(h)
        i = 0
        while i + 4 <= len(data) and i + 4 + data[i + 3] <= len(data):
            m = data[i:i + 4 + data[i + 3]]
            i += len(m)
            if m.startswith(prefix):
                ts = datetime.datetime.fromtimestamp(float(t)).strftime("%H:%M:%S.%f")[:-3]
                arrow = "→" if d == "0x00" else "←"
                print(f"{fn:>6} {ts} {arrow} {m[:4].hex(' ')} | {m[4:].hex(' ')}")
        buf[d] = data[i:]
        leftovers += bool(buf[d])
    print(f"# tramas con bytes sin cuadrar: {leftovers}", file=sys.stderr)

if __name__ == "__main__":
    main()
