import Foundation
import CoreBluetooth
import HelioCore

/// Connects to the strap's standard BLE Heart Rate broadcast and reports BPM.
/// Reports connection state so the UI can show live vs. reconnecting.
final class HeartRateMonitor: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private let onSample: @Sendable (HeartRateSample) -> Void
    private let onBattery: @Sendable (Int) -> Void
    private let onConnected: @Sendable (Bool) -> Void
    private let onUnavailable: @Sendable (String) -> Void

    private let hrService = CBUUID(string: "180D")
    private let hrMeasurement = CBUUID(string: "2A37")
    private let batteryService = CBUUID(string: "180F")
    private let batteryLevel = CBUUID(string: "2A19")

    init(onSample: @escaping @Sendable (HeartRateSample) -> Void,
         onBattery: @escaping @Sendable (Int) -> Void,
         onConnected: @escaping @Sendable (Bool) -> Void,
         onUnavailable: @escaping @Sendable (String) -> Void) {
        self.onSample = onSample
        self.onBattery = onBattery
        self.onConnected = onConnected
        self.onUnavailable = onUnavailable
        super.init()
        central = CBCentralManager(delegate: self, queue: nil)
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            central.scanForPeripherals(withServices: [hrService])
        case .unauthorized:
            onUnavailable("Bluetooth permission denied")
        case .poweredOff:
            onUnavailable("Bluetooth is off")
        case .unsupported:
            onUnavailable("Bluetooth unavailable")
        default:
            break
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any],
                        rssi RSSI: NSNumber) {
        self.peripheral = peripheral
        peripheral.delegate = self
        central.stopScan()
        central.connect(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        onConnected(true)
        peripheral.discoverServices([hrService, batteryService])
    }

    func centralManager(_ central: CBCentralManager,
                        didFailToConnect peripheral: CBPeripheral,
                        error: Error?) {
        onConnected(false)
        central.scanForPeripherals(withServices: [hrService])
    }

    func centralManager(_ central: CBCentralManager,
                        didDisconnectPeripheral peripheral: CBPeripheral,
                        error: Error?) {
        onConnected(false)
        central.scanForPeripherals(withServices: [hrService])
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        for service in peripheral.services ?? [] {
            switch service.uuid {
            case hrService:
                peripheral.discoverCharacteristics([hrMeasurement], for: service)
            case batteryService:
                peripheral.discoverCharacteristics([batteryLevel], for: service)
            default:
                break
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        for char in service.characteristics ?? [] {
            switch char.uuid {
            case hrMeasurement:
                peripheral.setNotifyValue(true, for: char)
            case batteryLevel:
                if char.properties.contains(.read) {
                    peripheral.readValue(for: char)
                }
                if char.properties.contains(.notify) {
                    peripheral.setNotifyValue(true, for: char)
                }
            default:
                break
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        guard let data = characteristic.value else { return }
        switch characteristic.uuid {
        case hrMeasurement:
            guard let sample = HeartRatePacket.parse(data) else { return }
            onSample(sample)
        case batteryLevel:
            guard let percent = data.first else { return }
            onBattery(Int(percent))
        default:
            break
        }
    }
}
