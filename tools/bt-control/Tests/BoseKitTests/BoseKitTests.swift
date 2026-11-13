// Pruebas con mensajes literales de la captura (docs/protocol.md).
import XCTest
@testable import BoseKit

final class BoseKitTests: XCTestCase {
    private func bytes(_ hex: String) -> [UInt8] {
        hex.split(separator: " ").map { UInt8($0, radix: 16)! }
    }

    func testCommandsMatchCapture() {
        XCTAssertEqual(BoseCommand.getCurrentMode.bytes, bytes("1f 03 01 00"))
        XCTAssertEqual(BoseCommand.listModes.bytes, bytes("1f 06 05 00"))
        XCTAssertEqual(BoseCommand.setMode(index: 0x02).bytes, bytes("1f 03 05 02 02 01"))
        XCTAssertEqual(BoseCommand.dumpBlock02.bytes, bytes("02 01 05 00"))
    }

    func testParserSplitsConcatenatedAndPartialMessages() {
        var p = MessageParser()
        // Trama 3100 de la captura (varios mensajes juntos), cortada en dos trozos.
        let all = bytes("05 01 01 00 04 04 01 00 12 0b 01 00 1f 03 03 01 02")
        XCTAssertEqual(p.feed(Array(all[0..<10])).count, 2)
        let rest = p.feed(Array(all[10...]))
        XCTAssertEqual(rest.count, 2)
        XCTAssertEqual(rest.last, BoseMessage(0x1f, 0x03, 0x03, [0x02]))
        XCTAssertEqual(p.pendingBytes, 0)
    }

    func testDecodeCurrentMode() {
        XCTAssertEqual(BoseDecode.currentMode(BoseMessage(0x1f, 0x03, 0x03, [0x03])), 0x03)
        XCTAssertNil(BoseDecode.currentMode(BoseMessage(0x1f, 0x03, 0x06, [0x03])))
    }

    func testDecodeModeChangeAck() {
        // Observado con bt-control: solo llega `1f 03 06 01 <idx>`.
        XCTAssertEqual(BoseDecode.modeChangeAck(BoseMessage(0x1f, 0x03, 0x06, [0x01])), 0x01)
        // Observado en la captura: también `1f 03 03 01 <idx>`.
        XCTAssertEqual(BoseDecode.modeChangeAck(BoseMessage(0x1f, 0x03, 0x03, [0x02])), 0x02)
        XCTAssertNil(BoseDecode.modeChangeAck(BoseMessage(0x1f, 0x06, 0x06, [])))
    }

    func testDecodeModeSlot() {
        // Trama 5315: ranura 01 "Aware".
        var payload = bytes("01 00 02 00 00 01") + Array("Aware".utf8)
        payload += [UInt8](repeating: 0, count: 0x30 - payload.count)
        XCTAssertEqual(BoseDecode.modeSlot(BoseMessage(0x1f, 0x06, 0x03, payload)),
                       ModeSlot(index: 1, name: "Aware"))
        // Ranura vacía "None": se descarta.
        var none = bytes("07 00 00 01 00 00") + Array("None".utf8)
        none += [UInt8](repeating: 0, count: 0x30 - none.count)
        XCTAssertNil(BoseDecode.modeSlot(BoseMessage(0x1f, 0x06, 0x03, none)))
    }

    func testEqualizer() {
        // Tramas 6433 / 6436 de la captura.
        XCTAssertEqual(BoseCommand.setEQ(band: 0, value: 2).bytes, bytes("01 07 02 02 02 00"))
        XCTAssertEqual(BoseCommand.dumpBlock01.bytes, bytes("01 01 05 00"))
        let m = BoseMessage(0x01, 0x07, 0x03, bytes("f6 0a 02 00 f6 0a 02 01 f6 0a 02 02"))
        XCTAssertEqual(BoseDecode.equalizer(m), [
            EQBand(index: 0, value: 2, min: -10, max: 10),
            EQBand(index: 1, value: 2, min: -10, max: 10),
            EQBand(index: 2, value: 2, min: -10, max: 10),
        ])
        // Hipótesis: negativos en complemento a dos (no observado).
        XCTAssertEqual(BoseCommand.setEQ(band: 2, value: -1).bytes, bytes("01 07 02 02 ff 02"))
    }

    func testDecodeBattery() {
        // Trama 2698.
        let m = BoseMessage(0x02, 0x02, 0x03, bytes("64 ff ff 01 64 ff ff 02 64 ff ff 04 5a ff ff 03"))
        XCTAssertEqual(BoseDecode.battery(m), [
            BatteryEntry(componentID: 1, percent: 100), BatteryEntry(componentID: 2, percent: 100),
            BatteryEntry(componentID: 4, percent: 100), BatteryEntry(componentID: 3, percent: 90),
        ])
    }
}
