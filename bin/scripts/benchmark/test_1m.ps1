1..5 | ForEach-Object {
    (Measure-Command { .\bin\build\dragonstone.exe run bin\scripts\benchmark\1m.ds | Out-Null }).TotalMilliseconds
} | Measure-Object -Average -Maximum -Minimum | Format-List
