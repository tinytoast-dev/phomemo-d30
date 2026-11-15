import Foundation

/// One horizontal label, in dots at approximately 8 dots per millimeter.
public struct Label: Sendable {
    public let length: Int
    public let width: Int
    private let raster: Data

    /// Provide one grayscale byte per dot, row-major from the top left.
    /// Each row spans `length` dots along the roll. Values below 128 print black.
    public init(length: Int, width: Int, grayscale: Data) throws {
        guard (1...Int(UInt16.max)).contains(length), (1...120).contains(width),
              grayscale.count == length * width else {
            throw D30Error.invalidLabel
        }
        self.length = length
        self.width = width

        // Rotate clockwise and pack one printhead row at a time, leftmost bit first.
        let rowBytes = (width + 7) / 8
        var packed = Data(repeating: 0, count: length * rowBytes)
        grayscale.withUnsafeBytes { (pixels: UnsafeRawBufferPointer) in
            for row in 0..<length {
                for column in 0..<width {
                    let source = (width - 1 - column) * length + row
                    if pixels[source] < 128 {
                        packed[row * rowBytes + column / 8] |= UInt8(0x80 >> (column % 8))
                    }
                }
            }
        }
        raster = packed
    }

    /// The bytes written to the printer, before splitting into Bluetooth writes.
    public var commandData: Data {
        let rowBytes = (width + 7) / 8
        var job = Data([
            0x1B, 0x40,                   // ESC @: initialize
            0x1D, 0x76, 0x30, 0x00,       // GS v 0: normal-size raster
            UInt8(rowBytes), 0,
            UInt8(truncatingIfNeeded: length), UInt8(length >> 8),
        ])
        job.append(raster)
        job.append(contentsOf: [0x1B, 0x64, 0x00]) // ESC d 0: finish
        return job
    }

    func packets(maximumLength: Int) -> [Data] {
        let job = commandData
        let footer = job.count - 3
        return [job.subdata(in: 0..<10)] + stride(from: 10, to: footer, by: maximumLength).map {
            job.subdata(in: $0..<min($0 + maximumLength, footer))
        } + [job.subdata(in: footer..<job.count)]
    }
}
