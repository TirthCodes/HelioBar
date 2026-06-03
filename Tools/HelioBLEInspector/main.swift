import CoreBluetooth
import Foundation

final class BLEInspector: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private let heartRateService = CBUUID(string: "180D")

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: nil)
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            print("Bluetooth powered on")
            print("Scanning for peripherals advertising Heart Rate service 180D...")
            central.scanForPeripherals(withServices: [heartRateService], options: [
                CBCentralManagerScanOptionAllowDuplicatesKey: false,
            ])
        case .poweredOff:
            print("Bluetooth is off")
            exit(2)
        case .unauthorized:
            print("Bluetooth permission denied")
            exit(2)
        case .unsupported:
            print("Bluetooth unsupported")
            exit(2)
        default:
            print("Bluetooth state: \(central.state.rawValue)")
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        print("Found peripheral: \(peripheral.name ?? "(unnamed)") RSSI \(RSSI)")
        printAdvertisement(advertisementData)
        self.peripheral = peripheral
        peripheral.delegate = self
        central.stopScan()
        central.connect(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("Connected: \(peripheral.name ?? "(unnamed)")")
        print("Discovering all services...")
        peripheral.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        print("Failed to connect: \(error?.localizedDescription ?? "unknown error")")
        exit(1)
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        print("Disconnected: \(error?.localizedDescription ?? "no error")")
        exit(0)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            print("Service discovery failed: \(error.localizedDescription)")
            exit(1)
        }

        for service in peripheral.services ?? [] {
            print("Service \(service.uuid.uuidString)")
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error {
            print("Characteristic discovery failed for \(service.uuid.uuidString): \(error.localizedDescription)")
            return
        }

        for characteristic in service.characteristics ?? [] {
            print("  Characteristic \(characteristic.uuid.uuidString) properties: \(properties(characteristic.properties))")
            peripheral.discoverDescriptors(for: characteristic)

            if characteristic.properties.contains(.read) {
                peripheral.readValue(for: characteristic)
            }

            if characteristic.properties.contains(.notify) || characteristic.properties.contains(.indicate) {
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverDescriptorsFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil else { return }
        for descriptor in characteristic.descriptors ?? [] {
            print("    Descriptor \(descriptor.uuid.uuidString)")
            peripheral.readValue(for: descriptor)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor descriptor: CBDescriptor, error: Error?) {
        guard error == nil else { return }
        print("    Descriptor \(descriptor.uuid.uuidString) value: \(String(describing: descriptor.value))")
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            print("    \(characteristic.uuid.uuidString) update failed: \(error.localizedDescription)")
            return
        }

        let bytes = characteristic.value.map(hex) ?? "(nil)"
        print("    \(timestamp()) \(characteristic.uuid.uuidString) value: \(bytes)")
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            print("    Notify \(characteristic.uuid.uuidString) failed: \(error.localizedDescription)")
        } else {
            print("    Notify \(characteristic.uuid.uuidString): \(characteristic.isNotifying ? "on" : "off")")
        }
    }

    private func printAdvertisement(_ advertisementData: [String: Any]) {
        for (key, value) in advertisementData.sorted(by: { $0.key < $1.key }) {
            if let data = value as? Data {
                print("  adv \(key): \(hex(data))")
            } else {
                print("  adv \(key): \(value)")
            }
        }
    }

    private func properties(_ properties: CBCharacteristicProperties) -> String {
        var names: [String] = []
        if properties.contains(.broadcast) { names.append("broadcast") }
        if properties.contains(.read) { names.append("read") }
        if properties.contains(.writeWithoutResponse) { names.append("writeWithoutResponse") }
        if properties.contains(.write) { names.append("write") }
        if properties.contains(.notify) { names.append("notify") }
        if properties.contains(.indicate) { names.append("indicate") }
        if properties.contains(.authenticatedSignedWrites) { names.append("authenticatedSignedWrites") }
        if properties.contains(.extendedProperties) { names.append("extendedProperties") }
        if properties.contains(.notifyEncryptionRequired) { names.append("notifyEncryptionRequired") }
        if properties.contains(.indicateEncryptionRequired) { names.append("indicateEncryptionRequired") }
        return names.isEmpty ? "none" : names.joined(separator: ",")
    }

    private func hex(_ data: Data) -> String {
        data.map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    private func timestamp() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}

print("Helio BLE Inspector")
print("Wear the strap and keep this running while walking to look for step-like characteristic changes.")

let inspector = BLEInspector()
withExtendedLifetime(inspector) {
    RunLoop.main.run()
}
