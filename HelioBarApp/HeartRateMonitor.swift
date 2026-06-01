import CoreBluetooth
import HelioCore

/// Connects to the strap's standard BLE Heart Rate broadcast and reports BPM.
/// Reports connection state so the UI can show live vs. reconnecting.
final class HeartRateMonitor: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private let onBPM: @Sendable (Int) -> Void
    private let onConnected: @Sendable (Bool) -> Void
    private let onUnavailable: @Sendable (String) -> Void

    private let hrService = CBUUID(string: "180D")
    private let hrMeasurement = CBUUID(string: "2A37")

    init(onBPM: @escaping @Sendable (Int) -> Void,
         onConnected: @escaping @Sendable (Bool) -> Void,
         onUnavailable: @escaping @Sendable (String) -> Void) {
        self.onBPM = onBPM
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
        peripheral.discoverServices([hrService])
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
        for service in peripheral.services ?? [] where service.uuid == hrService {
            peripheral.discoverCharacteristics([hrMeasurement], for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        for char in service.characteristics ?? [] where char.uuid == hrMeasurement {
            peripheral.setNotifyValue(true, for: char)
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        guard let data = characteristic.value,
              let bpm = HeartRatePacket.parse(data) else { return }
        onBPM(bpm)
    }
}
