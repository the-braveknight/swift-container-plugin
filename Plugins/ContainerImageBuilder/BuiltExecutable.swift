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

/// Resolves the selected product before passing it (and its sibling resources) to containertool.
enum BuiltExecutable {
    enum DiscoveryError: Error, CustomStringConvertible {
        case missing(String, [URL])
        case ambiguous(String, [URL])

        var description: String {
            switch self {
            case let .missing(name, paths):
                return "Build succeeded, but executable product '\(name)' was not found. Checked: "
                    + paths.map { $0.path }.joined(separator: ", ")
            case let .ambiguous(name, paths):
                return "Multiple build artifacts match executable product '\(name)': "
                    + paths.map { $0.path }.joined(separator: ", ")
                    + ". Clean the build directory and rebuild with the desired configuration and SDK."
            }
        }
    }

    static func find(productName: String, reportedURLs: [URL], packageDirectory: URL) throws -> URL {
        let reported = reportedURLs.filter { $0.lastPathComponent == productName }
        let existing = reported.filter(isRegularFile)
        if let executable = try unique(existing, productName: productName) { return executable }

        // Swift Build may report a legacy path even though the binary is under out/Products.
        // Derive the scratch directory from reported paths where possible, preserving --scratch-path.
        var searchDirectories: [URL] = []
        for url in reported {
            let configurationDirectory = url.deletingLastPathComponent()
            let configuration = configurationDirectory.lastPathComponent
            if configuration == "debug" || configuration == "release" {
                let tripleDirectory = configurationDirectory.deletingLastPathComponent()
                let products = tripleDirectory.deletingLastPathComponent().appendingPathComponent("out/Products")
                let triple = tripleDirectory.lastPathComponent
                if triple.hasSuffix("-unknown-linux-musl"), let architecture = triple.split(separator: "-").first {
                    // Do not accidentally package another architecture or a stale Debug build.
                    let variant = configuration == "release" ? "Release" : "Debug"
                    searchDirectories.append(products.appendingPathComponent("\(variant)-staticlinux-\(architecture)"))
                } else {
                    searchDirectories.append(products)
                }
            } else {
                var directory = configurationDirectory
                while directory.path != "/" {
                    if directory.lastPathComponent == "Products",
                        directory.deletingLastPathComponent().lastPathComponent == "out"
                    {
                        searchDirectories.append(directory)
                        break
                    }
                    directory.deleteLastPathComponent()
                }
            }
        }
        if searchDirectories.isEmpty {
            searchDirectories.append(packageDirectory.appendingPathComponent(".build/out/Products"))
        }
        searchDirectories = Array(Set(searchDirectories)).sorted { $0.path < $1.path }

        var matches: [URL] = []
        for directory in searchDirectories {
            guard
                let enumerator = FileManager.default.enumerator(
                    at: directory,
                    includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                )
            else { continue }
            for case let file as URL in enumerator {
                if file.lastPathComponent == productName && isRegularFile(file) {
                    matches.append(file)
                }
            }
        }
        if let executable = try unique(matches, productName: productName) { return executable }
        throw DiscoveryError.missing(productName, reported + searchDirectories)
    }

    private static func isRegularFile(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
    }

    private static func unique(_ urls: [URL], productName: String) throws -> URL? {
        let candidates = Array(Set(urls.map { $0.resolvingSymlinksInPath() })).sorted { $0.path < $1.path }
        guard candidates.count <= 1 else { throw DiscoveryError.ambiguous(productName, candidates) }
        // Preserve the reported path so sibling resource lookup retains its existing behavior.
        return urls.first
    }
}
