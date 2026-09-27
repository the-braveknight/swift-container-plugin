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
struct BuiltExecutableTests {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var checks = 0

        func file(_ path: String) throws -> URL {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data("fixture".utf8).write(to: url)
            return url
        }
        func resolve(_ package: String, _ reported: [URL] = [], name: String = "server") throws -> URL {
            try BuiltExecutable.find(
                productName: name,
                reportedURLs: reported,
                packageDirectory: root.appendingPathComponent(package)
            )
        }
        func equal(_ actual: URL, _ expected: URL) {
            precondition(actual.resolvingSymlinksInPath() == expected.resolvingSymlinksInPath())
            checks += 1
        }
        func missing(_ package: String, _ reported: [URL] = []) throws {
            do {
                _ = try resolve(package, reported)
                preconditionFailure("Expected a missing executable error")
            } catch BuiltExecutable.DiscoveryError.missing(let name, let paths) {
                precondition(name == "server" && !paths.isEmpty)
                checks += 1
            }
        }

        let legacy = try file("legacy/.build/aarch64-unknown-linux-musl/release/server")
        _ = try file("legacy/.build/out/Products/Release-staticlinux-aarch64/server")
        equal(try resolve("legacy", [legacy]), legacy)

        let nested = try file("nested/.build/out/Products/Release-staticlinux-aarch64/arch/server")
        let old = root.appendingPathComponent("nested/.build/aarch64-unknown-linux-musl/release/server")
        _ = try file("nested/.build/out/Products/Release-staticlinux-x86_64/server")
        _ = try file("nested/.build/out/Products/Debug-staticlinux-aarch64/server")
        equal(try resolve("nested", [old]), nested)
        equal(try resolve("nested", [nested]), nested)

        let empty = try file("empty/.build/out/Products/Release-staticlinux-aarch64/deep/server")
        equal(try resolve("empty"), empty)
        let unrelated = try file("empty/.build/debug/another-product")
        equal(try resolve("empty", [unrelated]), empty)

        let custom = try file("custom-scratch/out/Products/Release-staticlinux-aarch64/server")
        equal(
            try resolve(
                "custom-package",
                [root.appendingPathComponent("custom-scratch/aarch64-unknown-linux-musl/release/server")]
            ),
            custom
        )

        let renamed = try file("renamed/.build/out/Products/Release-staticlinux-x86_64/published-name")
        equal(try resolve("renamed", name: "published-name"), renamed)
        try missing("absent")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("directory/.build/out/Products/Release-staticlinux-aarch64/server"),
            withIntermediateDirectories: true
        )
        try missing("directory")
        _ = try file("wrong/.build/out/Products/Release-staticlinux-x86_64/server")
        try missing("wrong", [root.appendingPathComponent("wrong/.build/aarch64-unknown-linux-musl/release/server")])

        _ = try file("ambiguous/.build/out/Products/Release-staticlinux-aarch64/server")
        _ = try file("ambiguous/.build/out/Products/Release-staticlinux-x86_64/server")
        do {
            _ = try resolve("ambiguous")
            preconditionFailure("Expected an ambiguous executable error")
        } catch BuiltExecutable.DiscoveryError.ambiguous(let name, let paths) {
            precondition(name == "server" && paths.count == 2 && paths[0].path < paths[1].path)
            checks += 1
        }
        print("Passed \(checks) executable discovery checks")
    }
}
