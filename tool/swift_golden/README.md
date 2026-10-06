# Swift golden fixture

`test/fixtures/swift_golden.json` was produced by compiling the **original Swift** implementations
of `SolunarCalculator`, `MoonPhase` and `SpeciesCatalog` (from the retired SwiftUI app) unchanged,
and dumping their outputs over a grid of dates and locations. The Dart ports are tested against it
(`test/domain/swift_parity_test.dart`), so the port is verified numerically, not just by reading.

To regenerate (needs the old project's sources and Xcode's `swiftc`):

```sh
OLD=/path/to/simpleFishLogzOLD/simpleFishLog
swiftc -O -o golden "$OLD/Services/Solunar/SolunarCalculator.swift" "$OLD/Models/MoonPhase.swift" \
  "$OLD/Models/SpeciesCatalog.swift" tool/swift_golden/main.swift
./golden > test/fixtures/swift_golden.json
```
