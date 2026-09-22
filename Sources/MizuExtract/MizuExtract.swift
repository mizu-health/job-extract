import Foundation

@main
struct MizuExtract {
    static func main() async {
        var args = Array(CommandLine.arguments.dropFirst())
        let command = args.first ?? "help"
        if !args.isEmpty { args.removeFirst() }

        switch command {
        case "probe":
            await Probe.run()
        case "enrich":
            await Enrich.run()
        case "salary":
            await Salary.run()
        case "salaryprobe":
            await SalaryProbe.run()
        case "extract":
            await Extract.run()
        case "help", "--help", "-h":
            printUsage()
        default:
            FileHandle.standardError.write(Data("unknown command: \(command)\n".utf8))
            printUsage()
            exit(64)
        }
    }

    static func printUsage() {
        print("""
        mizu-extract - structured field extraction for job listings

        USAGE:
          mizu-extract probe      Report on-device model availability and run a round-trip
          mizu-extract extract    Read raw listings as JSON on stdin, write extracted JSON to stdout

        The extract command is a pure function: no network, no database.
        """)
    }
}
