// TrueCarryHub — ESP32-S3 firmware
// Hardware: M5Stack AtomS3 Lite + M5Stack RFID 2 Unit (WS1850S)
//
// How it works:
//   1. Reads the NDEF URI written on each club's NFC sticker (truecarry://nfc/{uuid})
//   2. Advertises as a BLE peripheral named "TrueCarry Hub"
//   3. Notifies the connected iPhone via a custom characteristic whenever a tag is detected
//
// Required Arduino libraries (install via Library Manager):
//   - MFRC522_I2C  by arozcan   (search "MFRC522 I2C")
//   - NimBLE-Arduino by h2zero  (search "NimBLE-Arduino")
//
// Board setup (Arduino IDE):
//   Tools > Board > ESP32 Arduino > "M5Stack-AtomS3" or "ESP32S3 Dev Module"
//   Tools > USB CDC On Boot > Enabled   (for Serial.print over USB-C)

#include <Wire.h>
#include <MFRC522_I2C.h>
#include <NimBLEDevice.h>

// ---------------------------------------------------------------------------
// Hardware pins — AtomS3 Lite Grove PORT.A
// ---------------------------------------------------------------------------
#define SDA_PIN 2
#define SCL_PIN 1

// WS1850S default I2C address (fixed on the RFID 2 Unit)
#define RFID_I2C_ADDR 0x28

// No dedicated RST pin via Grove cable — use software reset (255 = disabled)
#define RFID_RST_PIN  255

// ---------------------------------------------------------------------------
// BLE identifiers — must match RFIDHubManager.swift exactly
// ---------------------------------------------------------------------------
#define SERVICE_UUID  "12E40001-89AB-CDEF-0123-456789ABCDEF"
#define TAG_CHAR_UUID "12E40002-89AB-CDEF-0123-456789ABCDEF"

// ---------------------------------------------------------------------------
// Globals
// ---------------------------------------------------------------------------
MFRC522_I2C mfrc522(RFID_I2C_ADDR, RFID_RST_PIN);

NimBLEServer*         pServer          = nullptr;
NimBLECharacteristic* pTagChar         = nullptr;
bool                  deviceConnected  = false;

// Debounce: ignore the same physical card within this window
static byte          lastUID[7]        = {};
static uint8_t       lastUIDLen        = 0;
static unsigned long lastTagTimeMs     = 0;
static const unsigned long COOLDOWN_MS = 2000;

// ---------------------------------------------------------------------------
// BLE server callbacks
// ---------------------------------------------------------------------------
class HubServerCallbacks : public NimBLEServerCallbacks {
    void onConnect(NimBLEServer* svr, NimBLEConnInfo& connInfo) override {
        deviceConnected = true;
        Serial.println("[BLE] iPhone connected.");
    }
    void onDisconnect(NimBLEServer* svr, NimBLEConnInfo& connInfo, int reason) override {
        deviceConnected = false;
        Serial.println("[BLE] iPhone disconnected — restarting advertising.");
        NimBLEDevice::startAdvertising();
    }
};

// ---------------------------------------------------------------------------
// setup()
// ---------------------------------------------------------------------------
void setup() {
    Serial.begin(115200);
    delay(200);

    // I2C for RFID reader
    Wire.begin(SDA_PIN, SCL_PIN);
    delay(100);

    mfrc522.PCD_Init();
    delay(50);
    mfrc522.PCD_SetAntennaGain(mfrc522.RxGain_max);  // max sensitivity
    mfrc522.PCD_DumpVersionToSerial();

    // Confirm the reader responded with a non-zero version
    byte ver = mfrc522.PCD_ReadRegister(mfrc522.VersionReg);
    Serial.printf("[RFID] VersionReg raw: 0x%02X  AntennaGain: 0x%02X\n",
                  ver, mfrc522.PCD_GetAntennaGain());
    if (ver == 0x00 || ver == 0xFF) {
        Serial.println("[RFID] WARNING: reader not responding — check Grove cable seating");
    }

    // BLE peripheral
    NimBLEDevice::init("TrueCarry Hub");
    NimBLEDevice::setMTU(128);

    pServer = NimBLEDevice::createServer();
    pServer->setCallbacks(new HubServerCallbacks());

    NimBLEService* pSvc = pServer->createService(SERVICE_UUID);

    pTagChar = pSvc->createCharacteristic(
        TAG_CHAR_UUID,
        NIMBLE_PROPERTY::NOTIFY
    );

    pSvc->start();

    NimBLEAdvertising* pAdv = NimBLEDevice::getAdvertising();
    pAdv->addServiceUUID(SERVICE_UUID);
    pAdv->start();

    Serial.println("[Hub] Ready. Waiting for BLE connection and NFC tags...");
}

// ---------------------------------------------------------------------------
// loop()
// ---------------------------------------------------------------------------
void loop() {
    // Heartbeat — prints every 3s so we can confirm the loop is running
    static unsigned long lastHeartbeat = 0;
    if (millis() - lastHeartbeat > 3000) {
        lastHeartbeat = millis();
        Serial.printf("[Loop] Polling — BLE connected: %d\n", deviceConnected);
    }

    // Attempt to detect a new card in the field
    if (!mfrc522.PICC_IsNewCardPresent() || !mfrc522.PICC_ReadCardSerial()) {
        return;
    }

    unsigned long now = millis();

    // Debounce — same card detected again within cooldown window?
    bool sameCard = (mfrc522.uid.size == lastUIDLen) &&
                    (memcmp(mfrc522.uid.uidByte, lastUID, lastUIDLen) == 0);
    if (sameCard && (now - lastTagTimeMs) < COOLDOWN_MS) {
        mfrc522.PICC_HaltA();
        return;
    }

    // Record this card as the last-seen card
    memcpy(lastUID, mfrc522.uid.uidByte, mfrc522.uid.size);
    lastUIDLen    = mfrc522.uid.size;
    lastTagTimeMs = now;

    // Read NDEF BEFORE any Serial output — minimises time between
    // card selection and the first read command (WS1850S is timing-sensitive)
    String uri = readNDEFURI();

    mfrc522.PICC_HaltA();
    mfrc522.PCD_StopCrypto1();

    // Print UID after we're done with the RF transaction
    Serial.printf("[NFC] Card UID: ");
    for (byte i = 0; i < lastUIDLen; i++) {
        Serial.printf("%02X ", lastUID[i]);
    }
    Serial.println();

    if (uri.length() == 0) {
        Serial.println("[NFC] No NDEF URI found on tag — is it programmed?");
        return;
    }

    Serial.printf("[NFC] URI: %s\n", uri.c_str());

    // Only send tags that belong to TrueCarry clubs
    if (!uri.startsWith("truecarry://nfc/")) {
        Serial.println("[NFC] Not a TrueCarry club tag — ignored.");
        return;
    }

    if (deviceConnected) {
        pTagChar->setValue(uri.c_str());
        pTagChar->notify();
        Serial.println("[BLE] Notified iPhone.");
    } else {
        Serial.println("[BLE] No iPhone connected — tag ignored.");
    }
}

// ---------------------------------------------------------------------------
// readNDEFURI()
//
// Reads pages 4–19 of an NTAG213/215/216 tag (64 bytes of user memory),
// parses the NFC Forum Type 2 TLV structure, and returns the URI string
// from the first NDEF Well-Known URI record found.
// Returns "" on any failure or if no URI record is present.
// ---------------------------------------------------------------------------
// ISO 14443-A CRC-A calculated in software.
// The WS1850S hardware CRC coprocessor doesn't work with the MFRC522_I2C
// library — PCD_CalculateCRC always returns STATUS_ERROR on this chip.
static void crcA(const byte* data, byte len, byte* out2) {
    uint32_t crc = 0x6363;
    for (byte i = 0; i < len; i++) {
        byte b = data[i] ^ (byte)(crc & 0xFF);
        b ^= (b << 4);
        crc = (crc >> 8) ^ ((uint32_t)b << 8) ^ ((uint32_t)b << 3) ^ ((uint32_t)b >> 4);
    }
    out2[0] = (byte)(crc & 0xFF);
    out2[1] = (byte)((crc >> 8) & 0xFF);
}

// Send a raw READ command (0x30) with software CRC and separate TX/RX buffers.
static byte readPages(byte startPage, byte* out16) {
    byte tx[4] = {0x30, startPage, 0, 0};
    crcA(tx, 2, &tx[2]);   // software CRC — bypasses broken HW coprocessor

    for (int attempt = 0; attempt < 3; attempt++) {
        byte rx[18];
        byte rxLen = sizeof(rx);
        // checkCRC=false: skip response CRC verification (also uses HW coprocessor)
        mfrc522.PCD_TransceiveData(tx, 4, rx, &rxLen, nullptr, 0, false);
        // WS1850S always sets an error bit in ErrorReg even on clean reads because
        // its CRC hardware is broken, so the library returns STATUS_ERROR (1) even
        // when 18 valid bytes arrive. Accept the data if we received enough bytes.
        if (rxLen >= 16) {
            memcpy(out16, rx, 16);
            return 0;
        }
        delay(8);
    }
    return 0xFF;
}

String readNDEFURI() {
    byte data[64];
    memset(data, 0, sizeof(data));

    for (int block = 0; block < 4; block++) {
        if (readPages(4 + block * 4, data + block * 16) != 0) {
            return "";
        }
    }

    // Walk the TLV (Type-Length-Value) stream
    int pos = 0;
    while (pos < (int)sizeof(data) - 2) {
        byte tlvType = data[pos++];

        if (tlvType == 0x00) continue;          // Null TLV — skip single byte
        if (tlvType == 0xFE) return "";          // Terminator TLV — no NDEF found

        // Read length (only single-byte lengths needed; truecarry URIs fit in 1 byte)
        if (pos >= (int)sizeof(data)) return "";
        byte tlvLen = data[pos++];

        if (tlvType != 0x03) {                   // Not an NDEF TLV — skip payload
            pos += tlvLen;
            continue;
        }

        // NDEF Message TLV — parse the first record
        // NDEF record layout (Short Record, SR bit set):
        //   [0] flags byte   (TNF | MB | ME | SR ...)
        //   [1] type length
        //   [2] payload length
        //   [3..3+typeLen-1] type  (should be 'U' = 0x55 for URI)
        //   [3+typeLen] URI identifier code
        //   [4+typeLen..] URI payload (without abbreviation byte)
        if (pos + 3 >= (int)sizeof(data)) return "";

        // byte flags   = data[pos];    // not needed
        byte typeLen    = data[pos + 1];
        byte payloadLen = data[pos + 2];
        pos += 3;

        if (typeLen < 1 || pos + (int)typeLen - 1 >= (int)sizeof(data)) return "";
        byte recType = data[pos];   // 'U' = 0x55 for URI record type
        pos += typeLen;

        if (recType != 0x55) {
            pos += payloadLen;
            continue;
        }

        // URI record: first payload byte is the identifier code (RFC 3986 prefix)
        if (pos >= (int)sizeof(data)) return "";
        byte uriCode = data[pos++];
        String prefix = uriCodeToPrefix(uriCode);

        int uriBodyLen = (int)payloadLen - 1;    // subtract identifier byte
        if (uriBodyLen <= 0) return "";

        String uri = prefix;
        for (int i = 0; i < uriBodyLen && pos < (int)sizeof(data); i++) {
            uri += (char)data[pos++];
        }
        return uri;
    }
    return "";
}

// Map NFC Forum URI identifier codes to their string prefixes.
// Code 0x00 means no abbreviation — the full URI is in the payload.
// truecarry:// uses a custom scheme, so the sticker will use 0x00.
String uriCodeToPrefix(byte code) {
    switch (code) {
        case 0x00: return "";
        case 0x01: return "http://www.";
        case 0x02: return "https://www.";
        case 0x03: return "http://";
        case 0x04: return "https://";
        case 0x05: return "tel:";
        case 0x06: return "mailto:";
        default:   return "";
    }
}
