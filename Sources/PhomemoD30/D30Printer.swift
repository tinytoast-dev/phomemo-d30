import CoreBluetooth
import Foundation

public enum D30Error: LocalizedError {
    case invalidLabel
    case invalidTimeout
    case busy
    case bluetoothUnavailable(String)
    case printServiceMissing
    case writeCharacteristicMissing
    case writeLengthTooShort
    case disconnected
    case timedOut(acknowledgedWrites: Int)

    public var errorDescription: String? {
        switch self {
        case .invalidLabel: return "Use 1–120 dots across the roll and 1–65,535 dots along it, with one grayscale byte per dot."
        case .busy: return "Another print job is already running."
        case .invalidTimeout: return "The timeout must be between 1 and 3,600 seconds."
        case .bluetoothUnavailable(let state): return "Bluetooth is \(state)."
        case .printServiceMissing: return "The printer does not expose service FF00."
        case .writeCharacteristicMissing: return "The printer does not expose writable characteristic FF02."
        case .writeLengthTooShort: return "The Bluetooth write limit is too small for the D30 header."
        case .disconnected: return "The printer disconnected before acknowledging all writes."
        case .timedOut(let writes): return "The print timed out after \(writes) acknowledged Bluetooth writes."
        }
    }
}

@MainActor
public enum D30Printer {
    private static var isPrinting = false

    /// Send one label and return once the peripheral acknowledges the Bluetooth writes.
    /// With no identifier, connects to the first peripheral advertising the name D30.
    /// Pass a CoreBluetooth peripheral UUID to select a specific printer.
    public static func print(_ label: Label, identifier: UUID? = nil, timeout: TimeInterval = 30) async throws {
        guard (1...3600).contains(timeout) else { throw D30Error.invalidTimeout }
        guard !isPrinting else { throw D30Error.busy }
        isPrinting = true
        defer { isPrinting = false }

        let job = PrintJob(label: label, identifier: identifier)
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await job.run(timeout: timeout)
        } onCancel: {
            Task { @MainActor in job.finish(.failure(CancellationError())) }
        }
    }
}

@MainActor
private final class PrintJob: NSObject, @preconcurrency CBCentralManagerDelegate, @preconcurrency CBPeripheralDelegate {
    private let label: Label
    private let identifier: UUID?
    private let serviceID = CBUUID(string: "FF00")
    private let writeID = CBUUID(string: "FF02")
    private var central: CBCentralManager?
    private var printer: CBPeripheral?
    private var completion: CheckedContinuation<Void, Error>?
    private var timer: Task<Void, Never>?
    private var packets: [Data] = []
    private var acknowledgedWrites = 0

    init(label: Label, identifier: UUID?) {
        self.label = label
        self.identifier = identifier
    }

    func run(timeout: TimeInterval) async throws {
        try await withCheckedThrowingContinuation { continuation in
            completion = continuation
            // Both delegate protocols deliver callbacks on this manager’s main queue.
            central = CBCentralManager(delegate: self, queue: .main)
            timer = Task { [weak self] in
                do {
                    try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                } catch {
                    return
                }
                guard let self else { return }
                self.finish(.failure(D30Error.timedOut(acknowledgedWrites: self.acknowledgedWrites)))
            }
        }
    }

    func finish(_ result: Result<Void, Error>) {
        guard let completion else { return }
        self.completion = nil
        timer?.cancel()
        central?.stopScan()
        if let printer {
            printer.delegate = nil
            central?.cancelPeripheralConnection(printer)
        }
        central?.delegate = nil
        completion.resume(with: result)
    }

    func centralManagerDidUpdateState(_ manager: CBCentralManager) {
        switch manager.state {
        case .poweredOn:
            if printer == nil { manager.scanForPeripherals(withServices: nil) }
        case .unknown, .resetting: break
        case .poweredOff: finish(.failure(D30Error.bluetoothUnavailable("powered off")))
        case .unauthorized: finish(.failure(D30Error.bluetoothUnavailable("unauthorized")))
        case .unsupported: finish(.failure(D30Error.bluetoothUnavailable("unsupported")))
        @unknown default: finish(.failure(D30Error.bluetoothUnavailable("unavailable")))
        }
    }

    func centralManager(
        _ manager: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi: NSNumber
    ) {
        let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name
        guard printer == nil, identifier.map({ $0 == peripheral.identifier }) ?? (name == "D30") else { return }
        manager.stopScan()
        printer = peripheral
        peripheral.delegate = self
        manager.connect(peripheral)
    }

    func centralManager(_ manager: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([serviceID])
    }

    func centralManager(_ manager: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        finish(.failure(error ?? D30Error.disconnected))
    }

    func centralManager(_ manager: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        finish(.failure(error ?? D30Error.disconnected))
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let service = peripheral.services?.first(where: { $0.uuid == serviceID }), error == nil else {
            finish(.failure(error ?? D30Error.printServiceMissing))
            return
        }
        peripheral.discoverCharacteristics([writeID], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let output = service.characteristics?.first(where: { $0.uuid == writeID && $0.properties.contains(.write) }),
              error == nil else {
            finish(.failure(error ?? D30Error.writeCharacteristicMissing))
            return
        }
        let maximumLength = min(128, peripheral.maximumWriteValueLength(for: .withResponse))
        guard maximumLength >= 10 else {
            finish(.failure(D30Error.writeLengthTooShort))
            return
        }
        packets = label.packets(maximumLength: maximumLength)
        peripheral.writeValue(packets[0], for: output, type: .withResponse)
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard completion != nil else { return }
        if let error {
            finish(.failure(error))
            return
        }
        acknowledgedWrites += 1
        if acknowledgedWrites == packets.count {
            finish(.success(()))
        } else {
            peripheral.writeValue(packets[acknowledgedWrites], for: characteristic, type: .withResponse)
        }
    }
}
