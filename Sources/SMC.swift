import Foundation
import IOKit

/// Доступ к SMC (контроллер управления системой) — ТОЛЬКО ЧТЕНИЕ: обороты вентиляторов.
/// Записи в SMC в программе нет намеренно: вентиляторами управляет система.
final class SMC {
    // Структура обмена с драйвером AppleSMC (раскладка как в C, 80 байт).
    private struct Version { var major: UInt8 = 0, minor: UInt8 = 0, build: UInt8 = 0, reserved: UInt8 = 0; var release: UInt16 = 0 }
    private struct PLimit { var version: UInt16 = 0, length: UInt16 = 0; var cpu: UInt32 = 0, gpu: UInt32 = 0, mem: UInt32 = 0 }
    // Явный хвост из 3 байт: в C эта структура занимает 12 байт, а Swift без него упаковал бы её в 9.
    private struct KeyInfo { var dataSize: UInt32 = 0, dataType: UInt32 = 0; var dataAttributes: UInt8 = 0; var pad: (UInt8, UInt8, UInt8) = (0, 0, 0) }
    private typealias Bytes32 = (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                                 UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                                 UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                                 UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)
    private struct KeyData {
        var key: UInt32 = 0
        var vers = Version()
        var pLimit = PLimit()
        var keyInfo = KeyInfo()
        var result: UInt8 = 0
        var status: UInt8 = 0
        var data8: UInt8 = 0
        var data32: UInt32 = 0
        var bytes: Bytes32 = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                              0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    }

    private static let handleEvent: UInt32 = 2
    private static let cmdRead: UInt8 = 5
    private static let cmdKeyInfo: UInt8 = 9

    private var conn: io_connect_t = 0

    init?() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard IOServiceOpen(service, mach_task_self_, 0, &conn) == KERN_SUCCESS else { return nil }
    }

    deinit { if conn != 0 { IOServiceClose(conn) } }

    static func fourCC(_ s: String) -> UInt32 { s.utf8.reduce(0) { ($0 << 8) | UInt32($1) } }
    static func typeName(_ v: UInt32) -> String {
        String(bytes: [UInt8(v >> 24 & 0xff), UInt8(v >> 16 & 0xff), UInt8(v >> 8 & 0xff), UInt8(v & 0xff)], encoding: .ascii) ?? "?"
    }

    private func call(_ input: inout KeyData) -> KeyData? {
        var output = KeyData()
        var outSize = MemoryLayout<KeyData>.stride
        let r = IOConnectCallStructMethod(conn, Self.handleEvent, &input, MemoryLayout<KeyData>.stride, &output, &outSize)
        guard r == KERN_SUCCESS, output.result == 0 else { return nil }
        return output
    }

    /// Читает ключ: (тип, байты).
    func read(_ key: String) -> (type: String, bytes: [UInt8])? {
        var info = KeyData()
        info.key = Self.fourCC(key)
        info.data8 = Self.cmdKeyInfo
        guard let ki = call(&info) else { return nil }

        var req = KeyData()
        req.key = info.key
        req.keyInfo.dataSize = ki.keyInfo.dataSize
        req.data8 = Self.cmdRead
        guard let out = call(&req) else { return nil }

        let size = Int(ki.keyInfo.dataSize)
        let bytes = withUnsafeBytes(of: out.bytes) { Array($0.prefix(size)) }
        return (Self.typeName(ki.keyInfo.dataType), bytes)
    }

    // MARK: - Числа в форматах SMC

    func number(_ key: String) -> Double? {
        guard let (type, b) = read(key) else { return nil }
        switch type {
        case "flt ": // float32, little-endian (Apple Silicon)
            guard b.count == 4 else { return nil }
            return Double(Float(bitPattern: UInt32(b[0]) | UInt32(b[1]) << 8 | UInt32(b[2]) << 16 | UInt32(b[3]) << 24))
        case "fpe2": // беззнаковое 14.2 (Intel)
            guard b.count == 2 else { return nil }
            return Double(UInt16(b[0]) << 8 | UInt16(b[1])) / 4
        case "ui8 ": return b.first.map(Double.init)
        case "ui16": return b.count == 2 ? Double(UInt16(b[0]) << 8 | UInt16(b[1])) : nil
        case "ui32": return b.count == 4 ? Double(UInt32(b[0]) << 24 | UInt32(b[1]) << 16 | UInt32(b[2]) << 8 | UInt32(b[3])) : nil
        default: return nil
        }
    }
}

/// Состояние одного вентилятора.
struct FanInfo: Identifiable {
    let id: Int
    var rpm: Double
    var min: Double
    var max: Double
    var target: Double?
    var manual: Bool
}

extension SMC {
    func fans() -> [FanInfo] {
        let count = Int(number("FNum") ?? 0)
        return (0..<count).map { i in
            FanInfo(id: i,
                    rpm: number("F\(i)Ac") ?? 0,
                    min: number("F\(i)Mn") ?? 0,
                    max: number("F\(i)Mx") ?? 0,
                    target: number("F\(i)Tg"),
                    manual: (number("F\(i)Md") ?? 0) == 1)
        }
    }
}
