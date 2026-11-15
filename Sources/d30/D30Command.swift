#if os(macOS)
import AppKit
import Foundation
import PhomemoD30

@main
struct D30Command {
    static let usage = """
    Usage: d30 [--length MM] [--width MM] [--device UUID] [--preview PNG] text "YOUR TEXT"
           d30 [--length MM] [--width MM] [--device UUID] [--preview PNG] image FILE

    Default stock size: 40 mm long by 12 mm wide.
    --preview saves a PNG without connecting to the printer.
    """

    struct ArgumentError: LocalizedError {
        let errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }

    @MainActor
    static func main() async {
        do {
            try await run(Array(CommandLine.arguments.dropFirst()))
        } catch {
            FileHandle.standardError.write(Data("d30: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }

    @MainActor
    static func run(_ arguments: [String]) async throws {
        if arguments.isEmpty || arguments == ["--help"] {
            print(usage)
            return
        }

        var args = ArraySlice(arguments)
        var length = 320
        var width = 96
        var preview: URL?
        var device: UUID?
        while let option = args.first, option.hasPrefix("--") {
            args.removeFirst()
            guard let value = args.popFirst() else { throw ArgumentError("Missing value for \(option).") }
            switch option {
            case "--length": length = try dots(value, in: 4...200)
            case "--width": width = try dots(value, in: 4...15)
            case "--preview": preview = URL(fileURLWithPath: value)
            case "--device":
                guard let uuid = UUID(uuidString: value) else { throw ArgumentError("Invalid CoreBluetooth device UUID.") }
                device = uuid
            default: throw ArgumentError("Unknown option \(option). See d30 --help.")
            }
        }
        guard args.count == 2, let mode = args.popFirst(), let value = args.popFirst() else {
            throw ArgumentError("Provide text or image and one value. See d30 --help.")
        }

        let bitmap = try render(mode: mode, value: value, length: length, width: width)
        if let preview {
            guard let png = bitmap.representation(using: .png, properties: [:]) else { throw ArgumentError("Could not encode PNG.") }
            try png.write(to: preview, options: .atomic)
            print("Saved preview to \(preview.path)")
            return
        }

        guard let pixels = bitmap.bitmapData else { throw ArgumentError("Could not read rendered pixels.") }
        var gray = Data(capacity: length * width)
        for row in 0..<width {
            for col in 0..<length {
                let offset = row * bitmap.bytesPerRow + col * 4
                let luma = 299 * Int(pixels[offset]) + 587 * Int(pixels[offset + 1]) + 114 * Int(pixels[offset + 2])
                gray.append(UInt8(luma / 1000))
            }
        }
        let label = try Label(length: length, width: width, grayscale: gray)
        try await D30Printer.print(label, identifier: device)
        print("Printer acknowledged the label data.")
    }

    static func dots(_ value: String, in range: ClosedRange<Double>) throws -> Int {
        guard let number = Double(value), range.contains(number) else {
            throw ArgumentError("Size must be between \(range.lowerBound) and \(range.upperBound) mm.")
        }
        return Int((number * 8).rounded())
    }

    @MainActor
    static func render(mode: String, value: String, length: Int, width: Int) throws -> NSBitmapImageRep {
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: length, pixelsHigh: width,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: length * 4, bitsPerPixel: 32
        ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            throw ArgumentError("Could not allocate the label bitmap.")
        }

        let bounds = NSRect(x: 0, y: 0, width: length, height: width)
        let content = bounds.insetBy(dx: 8, dy: 4)
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = context
        NSColor.white.setFill()
        NSBezierPath(rect: bounds).fill()

        switch mode {
        case "text":
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            let lines = value.components(separatedBy: .newlines)
            guard lines.contains(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else {
                throw ArgumentError("Enter some text to print.")
            }
            for fontSize in stride(from: width, through: 8, by: -1) {
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.boldSystemFont(ofSize: Double(fontSize)),
                    .foregroundColor: NSColor.black,
                    .paragraphStyle: paragraph,
                ]
                let text = NSAttributedString(string: value, attributes: attributes)
                let lineWidth = lines.map { ($0 as NSString).size(withAttributes: attributes).width }.max() ?? 0
                let options: NSString.DrawingOptions = [.usesLineFragmentOrigin, .usesFontLeading]
                let size = text.boundingRect(with: content.size, options: options).integral.size
                if ceil(lineWidth) <= content.width && size.height <= content.height {
                    let rect = NSRect(x: content.minX, y: content.midY - size.height / 2, width: content.width, height: size.height)
                    text.draw(with: rect, options: options)
                    return bitmap
                }
            }
            throw ArgumentError("Text does not fit. Use a longer label or fewer characters.")
        case "image":
            guard let image = NSImage(contentsOfFile: value), image.size.width > 0, image.size.height > 0 else {
                throw ArgumentError("Could not open the image.")
            }
            let scale = min(content.width / image.size.width, content.height / image.size.height)
            let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
            let rect = NSRect(x: content.midX - size.width / 2, y: content.midY - size.height / 2, width: size.width, height: size.height)
            context.imageInterpolation = .high
            image.draw(in: rect)
        default:
            throw ArgumentError("Unknown mode \(mode). See d30 --help.")
        }
        return bitmap
    }
}
#else
@main
struct D30Command {
    static func main() {
        print("The d30 command-line tool requires macOS.")
    }
}
#endif
