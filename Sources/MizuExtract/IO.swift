import Foundation

enum IO {
    static func fail(_ message: String, code: Int32 = 1) -> Never {
        FileHandle.standardError.write(Data("mizu-extract: \(message)\n".utf8))
        exit(code)
    }
}
