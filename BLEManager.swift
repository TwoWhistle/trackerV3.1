//
//  BLEManager.swift
//  trackerV3
//
//  Created by Ryan Yue on 2/4/25.
//


import CoreBluetooth
import SwiftUI

class BLEManager: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    @Published var receivedEEG: String = "0"
    @Published var eegBands: [String: Float] = ["Delta": 0, "Theta": 0, "Alpha": 0, "Beta": 0, "Gamma": 0]
    @Published var debugLogs: [String] = []


    private var centralManager: CBCentralManager!
    private var connectedPeripheral: CBPeripheral?
    private var eegCharacteristic: CBCharacteristic?

    let serviceUUID = CBUUID(string: "12345678-1234-1234-1234-123456789abc")
    let eegCharUUID = CBUUID(string: "abcd5678-ab12-cd34-ef56-abcdef123456")

    private var eegDataBuffer: [Float] = []  // Stores raw EEG data for FFT
    private var eegDataLog: [(Date, Float)] = [] // Stores raw EEG data with timestamps

    override init() {
        super.init()
        print("🔵 BLEManager Initialized - Starting Central Manager")
        log("🔵 BLEManager Initialized - Starting Central Manager")
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            print("✅ Bluetooth is ON - Scanning for ALL peripherals...")
            log("✅ Bluetooth is ON - Scanning for ALL peripherals...")
            central.scanForPeripherals(withServices: [serviceUUID], options: nil) // Scan for ALL devices
        } else {
            print("❌ Bluetooth is OFF or Not Available")
            log("❌ Bluetooth is OFF or Not Available")
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let peripheralName = peripheral.name ?? "Unknown Device"
        print("🔍 Discovered Peripheral: \(peripheralName) | RSSI: \(RSSI)")
        log("🔍 Discovered Peripheral: \(peripheralName) | RSSI: \(RSSI)")

        if peripheralName.lowercased().contains("esp32") {
            print("✅ Matched ESP32 Device: \(peripheralName)")
            log("✅ Matched ESP32 Device: \(peripheralName)")
            connectedPeripheral = peripheral
            connectedPeripheral?.delegate = self
            centralManager.stopScan()
            print("🚀 Stopping Scan & Connecting to \(peripheralName)")
            log("🚀 Stopping Scan & Connecting to \(peripheralName)")
            centralManager.connect(peripheral, options: nil)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("✅ Connected to ESP32 - Waiting before discovering services...")
        log("✅ Connected to ESP32 - Waiting before discovering services...")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {  // Wait 2 seconds before discovering services
            print("🔍 Discovering Services Now...")
            self.log("🔍 Discovering Services Now...")
            peripheral.discoverServices([self.serviceUUID])
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            print("❌ Error discovering services: \(error.localizedDescription)")
            log("❌ Error discovering services: \(error.localizedDescription)")
            return
        }

        guard let services = peripheral.services else {
            print("❌ No Services Found")
            log("❌ No Services Found")
            return
        }

        print("🔍 Discovered \(services.count) services:")
        log("🔍 Discovered \(services.count) services:")

        for service in services {
            print("🛠 Found Service: \(service.uuid)")

            if service.uuid == serviceUUID {
                print("✅ Matched Service UUID! Discovering Characteristics...")
                log("✅ Matched Service UUID! Discovering Characteristics...")
                peripheral.discoverCharacteristics([eegCharUUID], for: service)
            }
        }
    }


    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error = error {
            print("❌ Error discovering characteristics: \(error.localizedDescription)")
            log("❌ Error discovering characteristics: \(error.localizedDescription)")
            return
        }

        guard let characteristics = service.characteristics else {
            print("❌ No Characteristics Found")
            log("❌ No Characteristics Found")
            return
        }

        print("🔍 Discovered \(characteristics.count) characteristics for service \(service.uuid):")
        log("🔍 Discovered \(characteristics.count) characteristics for service \(service.uuid):")

        for characteristic in characteristics {
            print("📡 Found Characteristic: \(characteristic.uuid)")
            log("📡 Found Characteristic: \(characteristic.uuid)")

            if characteristic.uuid == eegCharUUID {
                print("✅ Matched EEG Characteristic! Enabling notifications...")
                log("✅ Matched EEG Characteristic! Enabling notifications...")
                eegCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            print("❌ Error enabling notifications for \(characteristic.uuid): \(error.localizedDescription)")
            log("❌ Error enabling notifications for \(characteristic.uuid): \(error.localizedDescription)")
            return
        }

        if characteristic.isNotifying {
            print("✅ Notifications successfully enabled for \(characteristic.uuid)!")
            log("✅ Notifications successfully enabled for \(characteristic.uuid)!")
        } else {
            print("❌ Notifications were disabled unexpectedly.")
            log("❌ Notifications were disabled unexpectedly.")
        }
    }



    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            print("❌ Error receiving data: \(error.localizedDescription)")
            log("❌ Error receiving data: \(error.localizedDescription)")
            return
        }

        if let data = characteristic.value {
            let stringValue = String(data: data, encoding: .utf8) ?? "N/A"
            print("📡 Received EEG Data: \(stringValue)")
            log("📡 Received EEG Data: \(stringValue)")

            if let eegValue = Float(stringValue) {
                DispatchQueue.main.async {
                    self.receivedEEG = stringValue
                }
                processEEGData(eegValue)
                saveEEGData(eegValue)
            }
        } else {
            print("❌ No Data Received")
            log("❌ No Data Received")
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        let peripheralName = peripheral.name ?? "Unknown Device"
        log("❌ BLE Disconnected from \(peripheralName)")

        DispatchQueue.main.async {
            self.receivedEEG = "Disconnected"
        }

        // Attempt to reconnect
        if let connectedPeripheral = self.connectedPeripheral {
            log("🔄 Attempting to reconnect to \(peripheralName)...")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {  // Avoid instant reconnection loops
                central.connect(connectedPeripheral, options: nil)
            }
        } else {
            log("🔍 Lost reference to device. Rescanning...")
            central.scanForPeripherals(withServices: [serviceUUID], options: nil)
        }
    }



    private func processEEGData(_ eegValue: Float) {
        eegDataBuffer.append(eegValue)
        print("📊 EEG Data Buffer Size: \(eegDataBuffer.count)/256")  // ✅ Debug log
        log("📊 EEG Data Buffer Size: \(eegDataBuffer.count)/256")  // ✅ Debug log
        if eegDataBuffer.count >= 256 {
            let newBands = FFTProcessor.performFFT(eegDataBuffer)
            DispatchQueue.main.async {
                self.eegBands = newBands
                print("eegBands updated")
            }
            eegDataBuffer.removeAll()
        }
    }

    private func saveEEGData(_ eegValue: Float) {
        let timestamp = Date()
        self.eegDataLog.append((timestamp, eegValue))
        let entry = "\(timestamp),\(eegValue)\n"
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("EEGDataLog.txt")
        
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            handle.seekToEndOfFile()
            if let data = entry.data(using: .utf8) {
                handle.write(data)
            }
            handle.closeFile()
        } else {
            try? entry.write(to: fileURL, atomically: true, encoding: .utf8)
        }
    }
    
    /// Exports EEG data log
            func exportEEGData() {
                let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("EEGDataLog.txt")
                let activityVC = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
                UIApplication.shared.windows.first?.rootViewController?.present(activityVC, animated: true)
            }
    private func log(_ message: String) {
        DispatchQueue.main.async {
            self.debugLogs.append(message)
            if self.debugLogs.count > 100 { // Keep the log limited to the last 100 entries
                self.debugLogs.removeFirst()
            }
        }
    }
}
