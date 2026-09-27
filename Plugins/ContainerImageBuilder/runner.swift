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

/// Error code returned if the process fails or terminates because of an uncaught signal.
public enum ExitCode: Error, CustomStringConvertible {
    case rawValue(Int32)

    /// Human-readable termination status for plugin diagnostics.
    public var description: String {
        switch self {
        case .rawValue(let status): return "Helper process failed with status \(status)"
        }
    }
}

/// Runs `command` with the given arguments and environment variables, capturing standard output and standard error.
/// - Parameters:
///   - command: The URL for the executable.
///   - arguments: An array of arguments to supply to the executable.
///   - environment: A dictionary of environment variables to supply to the executable.
///   - currentDirectory: The directory in which to run the executable.
///   - outputPipe: A Pipe to which to send anything the executable writes to standard output.
///   - errorPipe: A Pipe to which to send anything the executable writes to standard error.
/// - Throws: The launch error, or `ExitCode` if the process exits unsuccessfully.
public func run(
    command: URL,
    arguments: [String],
    environment: [String: String]? = nil,
    currentDirectory: URL? = nil,
    outputPipe: Pipe? = nil,
    errorPipe: Pipe? = nil
) async throws {
    // A failed launch never lets Process close the parent's pipe ends. Close them on
    // every exit path so readers receive EOF instead of waiting forever.
    defer {
        outputPipe?.fileHandleForWriting.closeFile()
        errorPipe?.fileHandleForWriting.closeFile()
    }
    let task = Process()

    task.executableURL = command
    task.arguments = arguments
    task.environment = environment
    if let currentDirectory { task.currentDirectoryURL = currentDirectory }
    if let outputPipe { task.standardOutput = outputPipe }
    if let errorPipe { task.standardError = errorPipe }

    return try await withCheckedThrowingContinuation { continuation in
        task.terminationHandler = { process in
            switch process.terminationReason {
            case .uncaughtSignal:
                let error = ExitCode.rawValue(process.terminationStatus)
                continuation.resume(throwing: error)
            case .exit:
                if process.terminationStatus == 0 {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: ExitCode.rawValue(process.terminationStatus))
                }
            @unknown default:
                // This point should be unreachable.
                continuation.resume(returning: ())
            }
        }

        do { try task.run() } catch { continuation.resume(throwing: error) }
    }
}
