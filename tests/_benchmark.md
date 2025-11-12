## Benchmark Data

Made this file to remove comments from benchmark files.

The `_benchmark` files are the dragonstone benchmark testing files.

Minimal whitespace to save precious time.

Abbreviations used to save more precious time:
s = sum/total
i = iterations
o = outer nest
i = inner nest

## Files:
    _benchmark_1m.ds            = 1 Million Single Loops

    _benchmark_1b.ds            = 1 Billion Single Loops

    _benchmark_1m_nested.ds     = 1 Million Nested Loops

    _benchmark_1b_nested.ds     = 1 Billion Nested Loops

These runs I'm going to start making after any new implementations, updates or changes; Then place the results below.

## Runs:

```diff
+    Tested on 2025-10-25:
        Iterations Tested of 1,000,000 (1 Million)
        5 Passes with an Average of 3.43ms.

        If we were going to 1,000,000,000 (1 Billion),
        this would take about ~57 Minutes.

+    Tested on 2025-10-25:
        Iterations Tested of 1,000,000 (1 Million)
        5 Passes with an Average of 3.43ms.

        If we were going to 1,000,000,000 (1 Billion),
        this would take about ~57 Minutes.

+    Tested on 2025-11-03:
        Iterations Tested of 1,000,000 (1 Million)
        5 Passes with an Average of 2.27ms.

        If we were going to 1,000,000,000 (1 Billion),
        this would take about ~37 Minutes.

+    Tested on 2025-11-04:
        Iterations Tested of 1,000,000 (1 Million)
        5 Passes with an Average of 242-246ms.

        Iterations Tested of 1,000,000,000 (1 Billion)
        this would take about ~4 Minutes.

+    Tested on 2025-11-05:
        Nested Iterations Tested of 1,000,000 (1 Million)
        Time: 282.6ms
        Overhead: 15.4% slower than Single Loop.

        Nested Iterations Tested of 1,000,000,000 (1 Billion)
        Time: 225.81 seconds (3.76 minutes)
        Overhead: 0.9% slower than Single Loop.

        Summary:
        <2% overhead at scale
```
