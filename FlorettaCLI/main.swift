import Foundation
import FlorettaCore

let result = FlorettaCommandLine.run(CommandLine.arguments)
if result.servesMCP {
    do {
        try FlorettaMCP.serve(input: .standardInput, output: .standardOutput)
    } catch {
        let text = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        try? FileHandle.standardError.write(contentsOf: Data((text + "\n").utf8))
        exit(1)
    }
    exit(0)
}
if !result.stdout.isEmpty {
    try? FileHandle.standardOutput.write(contentsOf: Data(result.stdout.utf8))
}
if !result.stderr.isEmpty {
    try? FileHandle.standardError.write(contentsOf: Data(result.stderr.utf8))
}
exit(result.exitCode)
