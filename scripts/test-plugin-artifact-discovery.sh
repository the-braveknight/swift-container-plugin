#!/usr/bin/env bash
##===----------------------------------------------------------------------===##
##
## This source file is part of the SwiftContainerPlugin open source project
##
## Copyright (c) 2025 Apple Inc. and the SwiftContainerPlugin project authors
## Licensed under Apache License v2.0
##
## See LICENSE.txt for license information
## See CONTRIBUTORS.txt for the list of SwiftContainerPlugin project authors
##
## SPDX-License-Identifier: Apache-2.0
##
##===----------------------------------------------------------------------===##

# Compile the plugin's resolver directly: plugin targets cannot be imported by test targets.
set -euo pipefail

REPO_ROOT=$(git rev-parse --show-toplevel)
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc -swift-version 6 -warnings-as-errors \
    "$REPO_ROOT/Plugins/ContainerImageBuilder/BuiltExecutable.swift" \
    "$REPO_ROOT/Tests/PluginTests/BuiltExecutableTests.swift" \
    -o "$TEST_DIR/artifact-discovery-tests"
"$TEST_DIR/artifact-discovery-tests"

# A failed helper launch must finish the pipe reader and fail the command.
swiftc -swift-version 6 -warnings-as-errors \
    "$REPO_ROOT/Plugins/ContainerImageBuilder/runner.swift" \
    "$REPO_ROOT/Plugins/ContainerImageBuilder/Pipe+lines.swift" \
    "$REPO_ROOT/Tests/PluginTests/RunnerTests.swift" \
    -o "$TEST_DIR/runner-tests"
"$TEST_DIR/runner-tests"
