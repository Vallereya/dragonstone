<p align="center">
    <div align="center">
        <img src="./docs/0_Index/logos/Dragonstone-Logo-Full.png" width="500"/>
    </div>
</p>
<br>
<p align="center">
    <a>
        <img src="https://forthebadge.com/images/badges/0-percent-optimized.svg"/>
    </a>
    <br>
    <a>
        <img src="https://forthebadge.com/images/badges/contains-technical-debt.svg"/>
    </a>
    <br>
    <a>
        <img src="https://img.shields.io/badge/ruby-%23CC342D.svg?style=for-the-badge&logo=ruby&logoColor=white"/>
    </a>
    <a>
        <img src="https://img.shields.io/badge/crystal-%23000000.svg?style=for-the-badge&logo=crystal&logoColor=white"/>
    </a>
    <a>
        <img src="https://img.shields.io/badge/c-%2300599C.svg?style=for-the-badge&logo=c&logoColor=white"/>
    </a>
</p>

## What is Dragonstone?
Well it's a suppose to be an interpreted ruby-like programming language built with ruby (yeeted all of it due to performance), crystal (mostly) and c (some) but I don't know what I'm doing and it's my first time making a language. Sorry if some files don't make sense this is my v4 of this after all, thank you.

## Examples

See the `examples/` directory for sample `.ds` files.

## Project Setup

1. Clone this repository.
2. Run `shards build` to build the binary which gets placed in `./bin`.
3. Run `dragonstone.bat` inside `./bin` to add it to env path and handoff to `dragonstone.ps1`.

## Usage

### Run Files

```bash
    dragonstone run examples/hello_world.ds

    ./bin/dragonstone.exe run examples/hello_world.ds
```

### Run Tests
```bash
    crystal spec
```

## Contact

    Project:
        www.github.com/vallereya

## License

*© 2025 Vallereya*
<br>
All rights reserved.
<br>

*Code and Contributions have **Apache-2.0 License** since it's using Crystal for some of the build, agreed upon by all copyright holders aka me. See **LICENSE** for more information.*