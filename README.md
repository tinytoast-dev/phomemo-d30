# PhomemoD30

A dependency-free Swift library for printing custom labels over Bluetooth LE.
The print protocol was tested on a Phomemo D30 with hardware revision D30C.
The package uses Swift 6 and targets macOS 12+ and iOS 15+. The command-line
tool runs on macOS.

## Print from a Mac

Power on the printer and load a roll. The command connects directly over
Bluetooth and defaults to 40 × 12 mm stock. Match the dimensions to your roll.
If macOS prompts for Bluetooth access, allow it for the terminal or app you
are running the command from.

```sh
git clone https://github.com/tinytoast-dev/phomemo-d30.git
cd phomemo-d30
swift run d30 text "COFFEE"
swift run d30 --length 30 --width 12 image ./logo.png
```

Use `--preview ./label.png` before the `text` or `image` subcommand to save
the rendered design without connecting to the printer. Use `--device UUID` to
select a specific printer by its CoreBluetooth peripheral identifier.

## Use from Swift

Add the dependency to your package and add the `PhomemoD30` product to the
target that imports it.

```swift
.package(url: "https://github.com/tinytoast-dev/phomemo-d30.git", from: "0.1.0")
```

```swift
import Foundation
import PhomemoD30

func printLabel(grayscalePixels: Data) async throws {
    let label = try Label(length: 320, width: 96, grayscale: grayscalePixels)
    try await D30Printer.print(label)
}
```

Supply one grayscale byte per pixel, row-major from the top left. `length`
runs along the roll and `width` across it. At about 8 dots per millimeter,
40 × 12 mm is 320 × 96 dots. Values below 128 print black. The library rotates
and packs the raster for the printer.

For an iOS app, set `NSBluetoothAlwaysUsageDescription` in its Info.plist.
Sandboxed macOS apps also need the Bluetooth entitlement. The first device
advertising as `D30` is selected by default. Await each job before sending
another. The async print call returns when
the printer acknowledges the Bluetooth writes. Paper feed and print quality
need to be checked on the device.

## Bluetooth protocol

The tested D30C advertised service `AF30` and HID. CoreBluetooth exposed
service `FF00` after connecting.

| Characteristic | Capabilities |
| --- | --- |
| `FF01` | Read |
| `FF02` | Write with or without response |
| `FF03` | Notify |

The print job writes to `FF02` with a response for each packet. It sends
ESC `@`, GS `v 0` with the little-endian raster dimensions, the packed
bitmap in chunks of up to 128 bytes, then ESC `d 0`.

Prior protocol work includes [odensc's Web Bluetooth demo](https://github.com/odensc/phomemo-d30-web-bluetooth),
[Shoot2Skoot's label editor](https://github.com/Shoot2Skoot/phomemo-d30),
and [polskafan's D30 capture notes](https://github.com/polskafan/phomemo_d30).

Run the raster and packet tests with `swift test`.

## License

[MIT](LICENSE)
