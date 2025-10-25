<p align="center">
    <div align="center">
        <img src="./docs/0_Index/logos/Dragonstone-Logo-Full.png" width="500"/>
    </div>
</p>

# <p align=center> Architecture Overview </p>

#### This document serves as a critical, living template designed to provide a quick, rapid and comprehensive understanding of the codebase's architecture. This document will update as the project evolves.

## 1. Project Structure

```md
[root]/
    ├── .git/                           
    ├── docs/                           -> documentation                (coming soon)
    ├── scripts/                        -> auto scripts                 (coming soon)
    ├── examples/                       -> example .ds files
    ├── spec/                           -> testing files
    ├── bin/
    │   ├── dragonstone                 -> main entry
    │   ├── dragonstone.ps1             -> .ps1 script for env
    │   └── dragonstone.bat             -> add to path and handoff to .ps1
    ├── src/
    │   ├── dragonstone/                -> main source
    │   ├── version.cr                  -> version control
    │   └── dragonstone.cr              -> orchestrator
    ├── shard.yml                       
    ├── LICENSE
    ├── ARCHITECTURE.md                 -> *you are here*
    ├── CONTRIBUTING.md
    ├── README.md
    ├── .editorconfig
    ├── .gitattributes
    └── .gitignore
```