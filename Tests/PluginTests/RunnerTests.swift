//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftContainerPlugin open source project
//
// Copyright (c) 2024 Apple Inc. and the SwiftContainerPlugin project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftContainerPlugin project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import Foundation

@main
struct RunnerTests {
    static func invoke(_ command: URL, arguments: [String] = []) async throws -> String {
        let pipe = Pipe()
        return try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                var output = ""
                for try await chunk in pipe.lines { output += chunk }
                return output
            }
            group.addTask {
                try await run(command: command, arguments: arguments, errorPipe: pipe)
                return ""
            }
            var output = ""
            for try await result in group { output += result }
            return output
        }
    }

    static func main() async throws {
        let shell = URL(fileURLWithPath: "/bin/sh")
        let output = try await invoke(shell, arguments: ["-c", "printf 'first\\nlast' >&2"])
        precondition(output == "first\nlast")
        do {
            _ = try await invoke(shell, arguments: ["-c", "exit 7"])
            preconditionFailure("Expected a nonzero exit error")
        } catch ExitCode.rawValue(let status) { precondition(status == 7) }
        do {
            _ = try await invoke(shell, arguments: ["-c", "kill -TERM $$"])
            preconditionFailure("Expected a signal error")
        } catch ExitCode.rawValue(let status) { precondition(status == 15) }
        do {
            _ = try await invoke(FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
            preconditionFailure("Expected a launch error")
        } catch {
            precondition(!(error is ExitCode), "The original launch error must propagate")
        }
        print("Passed 4 helper process checks")
    }
}
