# Bose QC Ultra Earbuds (2nd Gen) — macOS menu bar control

A macOS menu bar app that shows the battery level and switches the noise cancelling mode and the
equalizer of the **Bose QuietComfort Ultra Earbuds (2nd generation)**, plus two command-line tools
to discover and test the protocol.

> Unofficial project, not affiliated with Bose Corporation. "Bose" and "QuietComfort" are trademarks
> of their respective owners. The protocol was documented by observing the traffic between the
> official app and a pair of earbuds owned by the author, for interoperability purposes. Use at your
> own risk.

## Features

- **Menu bar**: earbuds icon with a battery gauge (shows the earbud with the lowest charge).
- **Menu**: left earbud, right earbud and case battery; mode selector (Quiet, Aware, Immersion);
  access to the equalizer window.
- **Equalizer**: a window with the 3-band curve (bass, mid, treble, from −10 to +10). Drag the
  points with the mouse or type the values.
- **Automatic reconnection**: retries after the connection is lost (after 2, 5, 10 and 30 s, at most
  10 s per attempt), then waits for the system to report that the earbuds have reconnected.
- No Dock icon and no main window.

The app's user interface is currently in Spanish.

## Requirements

- macOS 13 or later.
- Xcode 16 or later (tested with Xcode 26.5 and Swift 6.3).
- The earbuds paired with the Mac.

## Project layout

```
app/                      Menu bar app (Xcode project, SwiftUI + MenuBarExtra)
tools/bt-control/         Swift package:
  Sources/BoseKit/          library with the protocol and the RFCOMM connection (used by the app)
  Sources/bt-control/       command-line client
  Tests/BoseKitTests/       tests built from real messages in the capture
tools/bt-discover/        Lists the SDP (RFCOMM) and GATT (BLE) services of a device
tools/capture-analysis/   Script that extracts the messages from a btsnoop capture (requires tshark)
docs/protocol.md          Protocol documentation, separating observations from hypotheses (Spanish)
docs/discovery/           Summary of the device's Bluetooth services (Spanish)
```

## Build and run

### App

Open `app/BoseMenuBar.xcodeproj` in Xcode and run it (⌘R), or from the terminal:

```sh
cd app
xcodebuild -project BoseMenuBar.xcodeproj -scheme BoseMenuBar -configuration Release -derivedDataPath build build
open build/Build/Products/Release/BoseMenuBar.app
```

On first launch macOS asks for Bluetooth permission. The app is signed to run locally ("Sign to Run
Locally"); distributing it would require signing it with a Developer ID.

### Command line

```sh
cd tools/bt-control
swift build
swift test                       # BoseKit tests
.build/debug/bt-control battery  # battery
.build/debug/bt-control mode     # current mode
.build/debug/bt-control modes    # modes stored in the earbuds
.build/debug/bt-control mode aware
.build/debug/bt-control eq       # equalizer
.build/debug/bt-control eq 0 3   # band 0 (bass) to +3
```

Use `-v` to print the traffic in hexadecimal. The earbuds accept a single client on the control
channel: **quit the menu bar app before using `bt-control`**.

## How it works

Control goes over Bluetooth Classic, **RFCOMM channel 2** (SerialPort service). Each message is
`[block] [function] [operation] [length] [data…]`. The details, with every statement marked as
observed, hypothesis or pending confirmation, are in [`docs/protocol.md`](docs/protocol.md).

The traffic captures used to document it are **not included**, because they contain personal data.
To generate your own, enable the Bluetooth HCI snoop log in Android's developer options, use the
official app, extract `btsnoop_hci.log` from the bug report and save it to `docs/captures/` (which is
listed in `.gitignore`).

## Known limitations

- Tested with a single pair of earbuds, firmware 8.4.8.
- Battery: component 04 is unidentified; left/right was inferred from a single test.
- Equalizer bands: band 0 (bass) is confirmed; mid and treble were assigned by order.
- Changes made from the Mac are not reflected in the phone app until it reads the state again.
- On macOS 26, `IOBluetoothDevice.isConnected()` is unreliable from a terminal process; the tools
  try to open the channel directly instead.

## License

Copyright (C) 2026 guilleml

This program is free software: you can redistribute it and/or modify it under the terms of the
**GNU General Public License version 3** as published by the Free Software Foundation. If you
distribute this program or a work based on it, you must keep this copyright notice and release your
version's source code under the same license.

This program is distributed WITHOUT ANY WARRANTY. See the full text in [`LICENSE`](LICENSE).
