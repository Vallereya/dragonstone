Measure-Command { .\bin\build\dragonstone.exe run bin\scripts\benchmark\1b.ds | Out-Null } | Select-Object TotalSeconds, TotalMinutes
