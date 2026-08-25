Measure-Command { .\bin\build\dragonstone.exe run bin\scripts\benchmark\1m_nested.ds | Out-Null } | Select-Object TotalSeconds, TotalMilliseconds
