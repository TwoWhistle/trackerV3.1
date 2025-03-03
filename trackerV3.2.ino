#include <Wire.h>
#include <BLEDevice.h>
#include <BLEUtils.h>
#include <BLEServer.h>
#include <BLE2902.h>

#define SERVICE_UUID "12345678-1234-1234-1234-123456789abc"
#define EEG_CHARACTERISTIC "abcd5678-ab12-cd34-ef56-abcdef123456"

BLECharacteristic eegCharacteristic(
  EEG_CHARACTERISTIC,
  BLECharacteristic::PROPERTY_NOTIFY);

bool deviceConnected = false;
BLEAdvertising *pAdvertising;

class ServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer* pServer) {
    deviceConnected = true;
  }
  void onDisconnect(BLEServer* pServer) {
    deviceConnected = false;
    Serial.println("❌ Disconnected! Restarting advertising...");
    pServer->getAdvertising()->start();
  }
};

void setup() {
  Serial.begin(115200);
  Serial.println("🚀 ESP32 BLE Setup Starting...");

  BLEDevice::deinit(); // Ensures a clean restart of BLE
  delay(100);

  // ✅ Initialize BLE
  BLEDevice::init("ESP32_Health_Monitor");
  BLEServer* pServer = BLEDevice::createServer();
  pServer->setCallbacks(new ServerCallbacks());

  BLEService* pService = pServer->createService(SERVICE_UUID);
  if (pService == nullptr) {
      Serial.println("❌ Failed to create BLE Service!");
  } else {
      Serial.println("✅ BLE Service Created Successfully");
  }

  pService->addCharacteristic(&eegCharacteristic);

  // ✅ Add BLE2902 Descriptor for EEG
  BLE2902* eegDescriptor = new BLE2902();
  eegCharacteristic.addDescriptor(eegDescriptor);
  eegDescriptor->setNotifications(true);

  pService->start();
  Serial.println("✅ BLE Service Started");

  pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(BLEUUID(SERVICE_UUID));
  pAdvertising->setScanResponse(true);
  pAdvertising->setMinPreferred(0x06);  // Helps with iOS compatibility
  pAdvertising->start();
  Serial.println("📡 BLE Advertising Started with Service UUID");
}

void loop() {
    // ✅ EEG Data Collection
    int eegSignal = analogRead(1);
    String eegString = String(eegSignal);
    eegCharacteristic.setValue(eegString.c_str());
    eegCharacteristic.notify();
    Serial.println(" Sent EEG: " + eegString);

    delay(250); //this too low makes it unable to re/connect
}
