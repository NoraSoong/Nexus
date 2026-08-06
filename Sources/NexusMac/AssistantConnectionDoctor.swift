import Foundation

func runMCPDoctor(helperPath: String, bindingID: Int64? = nil) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: helperPath)
    process.arguments = ["--doctor"]
    if let bindingID {
        process.arguments?.append(contentsOf: ["--binding-id", String(bindingID)])
    }
    let output = Pipe()
    let error = Pipe()
    process.standardOutput = output
    process.standardError = error
    try process.run()

    let deadline = Date().addingTimeInterval(3)
    while process.isRunning, Date() < deadline {
        Thread.sleep(forTimeInterval: 0.05)
    }
    if process.isRunning {
        process.terminate()
        throw NSError(
            domain: "NexusAssistantConnection",
            code: 124,
            userInfo: [NSLocalizedDescriptionKey: "nexus-mcp --doctor timed out"]
        )
    }

    let outputData = output.fileHandleForReading.readDataToEndOfFile()
    let errorData = error.fileHandleForReading.readDataToEndOfFile()
    let outputText = String(data: outputData, encoding: .utf8) ?? ""
    let errorText = String(data: errorData, encoding: .utf8) ?? ""
    if process.terminationStatus != 0 {
        throw NSError(
            domain: "NexusAssistantConnection",
            code: Int(process.terminationStatus),
            userInfo: [NSLocalizedDescriptionKey: errorText.isEmpty ? outputText : errorText]
        )
    }
    return outputText.trimmingCharacters(in: .whitespacesAndNewlines)
}
