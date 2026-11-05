#!/bin/bash
# Pure control-policy tests: no audio/USB or native windows.
set -euo pipefail
cd "$(dirname "$0")/.."
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
cat > "$scratch/check.swift" <<'SWIFT'
import Foundation
@main struct Test {
    static func main() {
        func expect(_ value: @autoclosure () -> Bool) {
            if !value() { FileHandle.standardError.write(Data("Output safety check failed\n".utf8)); exit(1) }
        }
        expect(OutputSafety.evaluate(requested: 0, current: -60, ceiling: -12) == .confirm(-12))
        expect(OutputSafety.evaluate(requested: -64, current: -60, ceiling: -12) == .allow(-64))
        expect(OutputSafety.evaluate(requested: -62, current: -64, ceiling: -12) == .allow(-62))
        expect(OutputSafety.evaluate(requested: -18, current: -20, ceiling: -12) == .allow(-18))
        expect(OutputSafety.evaluate(requested: -16, current: -18, ceiling: -12) == .allow(-16))
        expect(OutputSafety.evaluate(requested: -14, current: -16, ceiling: -12) == .allow(-14))
        expect(OutputSafety.evaluate(requested: 0, current: -14, ceiling: -12) == .allow(-12))
        expect(OutputSafety.evaluate(requested: 0, current: -14, ceiling: -12) == .allow(-12))
        expect(OutputSafety.evaluate(requested: 0, current: -12, ceiling: -12) == .allow(-12))
        expect(OutputSafety.evaluate(requested: -30, current: -12, ceiling: -30) == .allow(-30))
        expect(OutputSafety.evaluate(requested: -15, current: -40, ceiling: 0) == .allow(-15))
        expect(OutputSafety.evaluate(requested: -14, current: -40, ceiling: 0) == .confirm(-14))
        expect(OutputSafety.evaluate(requested: -12, current: -14, ceiling: 0) == .allow(-12))
        expect(OutputSafety.evaluate(requested: 0, current: -1, ceiling: 0) == .confirm(0))
        expect(OutputSafety.evaluate(requested: 0, current: 0, ceiling: 0) == .allow(0))
        expect(OutputSafety.evaluate(requested: -1, current: 0, ceiling: 0) == .allow(-1))
        expect(OutputSafety.evaluate(requested: -12, current: -13, ceiling: -12) == .allow(-12))
        expect(RelativeDial.value(start: -40, verticalTranslation: 0, fine: false, range: -64...0) == -40)
        expect(RelativeDial.value(start: -40, verticalTranslation: -8, fine: false, range: -64...0) == -38)
        expect(RelativeDial.value(start: -40, verticalTranslation: 8, fine: false, range: -64...0) == -42)
        expect(RelativeDial.value(start: -40, verticalTranslation: -16, fine: true, range: -64...0) == -39)
        expect(RelativeDial.value(start: -40, verticalTranslation: -1000, fine: false, range: -64...0) == 0)
        print("Relative dial anchoring, fine control, output ceilings, large-jump holds and always-allowed reductions passed")
    }
}
SWIFT
swiftc -swift-version 6 -warnings-as-errors -parse-as-library -module-cache-path "$PWD/.build/clang-cache" Sources/OpenDuet/OutputSafety.swift "$scratch/check.swift" -o "$scratch/check"
"$scratch/check"
