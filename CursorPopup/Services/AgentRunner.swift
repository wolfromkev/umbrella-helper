import Foundation

enum AgentEvent {
    case sessionStarted(String)
    case textDelta(String)
    case textFinal(String)
    case completed
    case failed(String)
}

final class AgentRunner {
    private var process: Process?
    private var stdoutPipe: Pipe?
    private var activeRunID = UUID()
    private let queue = DispatchQueue(label: "com.cursorpopup.agent", qos: .userInitiated)

    func cancel() {
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        if let process, process.isRunning {
            process.terminate()
        }
        process = nil
        stdoutPipe = nil
        activeRunID = UUID()
    }

    private static func wasTerminated(_ status: Int32) -> Bool {
        status == 15 || status == 143
    }

    func send(
        prompt: String,
        workspace: String,
        sessionID: String?,
        imagePaths: [String] = [],
        onEvent: @escaping (AgentEvent) -> Void
    ) {
        cancel()

        guard let agentPath = Self.locateAgentBinary() else {
            onEvent(.failed("Could not find the Cursor `agent` CLI. Install it from Cursor or ensure it is on your PATH."))
            return
        }

        var arguments = [
            "-p",
            "--mode", "ask",
            "--workspace", workspace,
            "--trust",
            "--approve-mcps",
            "--output-format", "stream-json",
            "--stream-partial-output",
        ]

        for imagePath in imagePaths {
            arguments.append(contentsOf: ["--image", imagePath])
        }

        arguments.append(prompt)

        if let sessionID {
            arguments.insert(contentsOf: ["--resume", sessionID], at: 0)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: agentPath)
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: workspace)

        var environment = ProcessInfo.processInfo.environment
        let pathExtras = [
            "\(NSHomeDirectory())/.local/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin"
        ]
        let existingPath = environment["PATH"] ?? ""
        environment["PATH"] = (pathExtras + [existingPath]).joined(separator: ":")
        process.environment = environment

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        var buffer = Data()
        var latestFullText = ""

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }

            buffer.append(chunk)
            while let newlineRange = buffer.firstRange(of: Data([0x0A])) {
                let lineData = buffer.subdata(in: buffer.startIndex..<newlineRange.lowerBound)
                buffer.removeSubrange(buffer.startIndex...newlineRange.lowerBound)

                guard
                    let line = String(data: lineData, encoding: .utf8),
                    !line.isEmpty,
                    let data = line.data(using: .utf8),
                    let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                else {
                    continue
                }

                self?.handleJSON(json, latestFullText: &latestFullText, onEvent: onEvent)
            }
        }

        let runID = UUID()
        activeRunID = runID

        process.terminationHandler = { [weak self] proc in
            pipe.fileHandleForReading.readabilityHandler = nil
            guard let self, self.activeRunID == runID else { return }

            let status = proc.terminationStatus
            if status == 0 {
                onEvent(.completed)
            } else if !Self.wasTerminated(status) {
                onEvent(.failed("Agent exited with status \(status)."))
            }
        }

        do {
            try process.run()
            self.process = process
            self.stdoutPipe = pipe
        } catch {
            onEvent(.failed("Failed to start agent: \(error.localizedDescription)"))
        }
    }

    private func handleJSON(
        _ json: [String: Any],
        latestFullText: inout String,
        onEvent: @escaping (AgentEvent) -> Void
    ) {
        if let type = json["type"] as? String, type == "system",
           let sessionID = json["session_id"] as? String {
            onEvent(.sessionStarted(sessionID))
        }

        if let type = json["type"] as? String, type == "assistant",
           let message = json["message"] as? [String: Any],
           let content = message["content"] as? [[String: Any]] {
            for item in content {
                guard
                    let itemType = item["type"] as? String,
                    itemType == "text",
                    let text = item["text"] as? String
                else { continue }

                if text.count > latestFullText.count, text.hasPrefix(latestFullText) {
                    let delta = String(text.dropFirst(latestFullText.count))
                    latestFullText = text
                    if !delta.isEmpty {
                        onEvent(.textDelta(delta))
                    }
                } else if !text.isEmpty, text != latestFullText {
                    latestFullText = text
                    onEvent(.textDelta(text))
                }
            }
        }

        if let type = json["type"] as? String, type == "result",
           let subtype = json["subtype"] as? String, subtype == "success",
           let result = json["result"] as? String,
           !result.isEmpty {
            latestFullText = result
            onEvent(.textFinal(result))
        }

        if let type = json["type"] as? String, type == "result",
           let subtype = json["subtype"] as? String, subtype == "error",
           let error = json["error"] as? String {
            onEvent(.failed(error))
        }
    }

    private static func locateAgentBinary() -> String? {
        let candidates = [
            "\(NSHomeDirectory())/.local/bin/agent",
            "/opt/homebrew/bin/agent",
            "/usr/local/bin/agent"
        ]

        for candidate in candidates where FileManager.default.isExecutableFile(atPath: candidate) {
            return candidate
        }

        let which = Process()
        which.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        which.arguments = ["agent"]

        let pipe = Pipe()
        which.standardOutput = pipe
        which.standardError = Pipe()

        do {
            try which.run()
            which.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let path = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !path.isEmpty,
               FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        } catch {
            return nil
        }

        return nil
    }
}
