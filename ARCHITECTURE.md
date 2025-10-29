<p align="center">
    <div align="center">
        <img src="./docs/0_Index/logos/Dragonstone-Logo-Full.png" width="500"/>
    </div>
</p>

# <p align=center> Architecture Overview </p>

#### This document serves as a critical, living template designed to provide a quick, rapid and comprehensive understanding of the codebase's architecture. This document will update as the project evolves.

## 1. Misc. Information

```css

    Dragonstone Colors Scheme:
        --DS-Primary:             oklch(0.4793 0.2774 285.03);     /* #5E06EE */

        --DS-Base-100:            oklch(0.5085 0.2825 287.47);     /* #6B15F9 */
        --DS-Base-200:            oklch(0.4793 0.2774 285.03);     /* #5E06EE */
        --DS-Base-300:            oklch(0.442 0.2547 285.27);      /* #5406D5 */
        --DS-Base-400:            oklch(0.3732 0.2141 285.73);     /* #4204A9 */
        --DS-Base-500:            oklch(0.3438 0.1956 286.38);     /* #3B0496 */

        --Light-Accent:           oklch(0.8373 0 0);               /* #C9C9C9 */
        --Light-Secondary:        oklch(0.8767 0 0);               /* #D6D6D6 */
        --Light-Primary:          oklch(0.9157 0 0);               /* #E3E3E3 */
        --Light-Base:             oklch(0.9581 0 0);               /* #F1F1F1 */

        --Dark-Base:              oklch(0.1638 0 0);               /* #0E0E0E */
        --Dark-Primary:           oklch(0.2267 0 0);               /* #1D1D1D */
        --Dark-Secondary:         oklch(0.2801 0 0);               /* #292929 */
        --Dark-Accent:            oklch(0.3311 0 0);               /* #363636 */

        --Text-Light-Primary:     var(--Dark-Secondary);
        --Text-Light-Secondary:   oklch(0.5192 0 0);               /* #696969 */

        --Text-Dark-Primary:      var(--Light-Secondary);
        --Text-Dark-Secondary:    oklch(0.6746 0 0);               /* #969696 */

        --DS-Text-Accent:         oklch(0.6746 0 0);               /* #5E06EE */

        --State-Positive          oklch(0.5842 0.1418 146.12);     /* #379144 */
        --State-Negative          oklch(0.9062 0.1927 105.48);     /* #BC002D */
        --State-Focus             oklch(0.5625 0.2405 270.2);      /* #455CFF */
        --State-Signal            oklch(0.5028 0.2021 20.72);      /* #F3E600 */

```

## 2. Project Structure

```md
[root]/
    ├── .git/                           
    ├── docs/                           -> documentation
    ├── scripts/                        -> auto scripts
    ├── examples/                       -> example .ds files
    ├── tests/                          -> unimportant test .ds files
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