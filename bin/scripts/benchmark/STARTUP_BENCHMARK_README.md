## Startup & Lexer Benchmark

The `startup_bench.sh` & `startup_bench.ps1` are different
from the loop benchmarks below; As they "assert" rather 
than report, and are wired into CI.

They govern the self-hosting iteration loop:

1. **Stage1 Cold Start**: How long 
    `dragonstone run bin/main.ds ...` takes to
    reach the first line of code. The bootstrap specs pay 
    it once per file, twice per stage. 
    
    * Budget 5s; currently ~1.5s (was 16.5s).

2. **Non-ASCII Lexer Parity**: The stage0 lexer used to index a 
    Crystal `String` by character, which is O(1) only while 
    the string is `ascii_only?`. One unicode character in 
    one comment made a 4k LOC file take 29,095ms instead of 
    177ms. 
    
    * Budget: Non-ASCII may not be more than 3x its ASCII variant.

### Usage for `.sh`:
```pwsh
    # Assertion; non-zero on regression.
    .\bin\scripts\benchmark\startup_bench.ps1

    # Print only, never fail.
    .\bin\scripts\benchmark\startup_bench.ps1 -Report

    # Override budget
    .\bin\scripts\benchmark\startup_bench.ps1 -StartupBudget 4

    Exit codes: 0 within budget, 1 regression, 2 prerequisites missing.
```

### Usage for `.sh`:
```bash
    # Assertion; non-zero on regression.
    ./bin/scripts/benchmark/startup_bench.sh

    # Print only, never fail.
    ./bin/scripts/benchmark/startup_bench.sh --report

    # Override budget
    ./bin/scripts/benchmark/startup_bench.sh --startup-budget 4

    Exit codes: 0 within budget, 1 regression, 2 prerequisites missing.
```
