#!/bin/sh

set -eu

symbol_graph_directory="$PWD/.build/docc-symbol-graphs"
module_graph_directory="$PWD/.build/docc-SwiftDunk-symbol-graph"
archive_path="$PWD/.build/SwiftDunk.doccarchive"

mkdir -p "$symbol_graph_directory" "$module_graph_directory"

swift build \
    --target SwiftDunkTestSupport \
    -Xswiftc -emit-symbol-graph \
    -Xswiftc -emit-symbol-graph-dir \
    -Xswiftc "$symbol_graph_directory"

swift Scripts/MergeSymbolDocumentation.swift \
    "$symbol_graph_directory/SwiftDunk.symbols.json" \
    "$module_graph_directory/SwiftDunk.symbols.json" \
    "$symbol_graph_directory/SwiftDunkCore.symbols.json" \
    "$symbol_graph_directory/SwiftDunkAnisette.symbols.json" \
    "$symbol_graph_directory/SwiftDunkAuth.symbols.json" \
    "$symbol_graph_directory/SwiftDunkPortal.symbols.json" \
    "$symbol_graph_directory/SwiftDunkCertificates.symbols.json" \
    "$symbol_graph_directory/SwiftDunkTestSupport.symbols.json"

xcrun docc convert Sources/SwiftDunk/Documentation.docc \
    --additional-symbol-graph-dir "$module_graph_directory" \
    --output-path "$archive_path" \
    --fallback-display-name SwiftDunk \
    --fallback-bundle-identifier dev.swiftdunk.documentation \
    --fallback-bundle-version 0.0.0 \
    --experimental-documentation-coverage \
    --coverage-summary-level brief \
    --warnings-as-errors
