1..5 | ForEach-Object {
    (Measure-Command { .\bin\dragonstone.exe run tests\benchmark.ds | Out-Null }).TotalMilliseconds
} | Measure-Object -Average -Maximum -Minimum | Format-List