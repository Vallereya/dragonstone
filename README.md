<p align="center">
    <div align="center">
        <img src="./docs/0_Index/logos/Dragonstone-Logo-Full.png" width="500"/>
    </div>
</p>
<br>
<p align="center">
    <a>
        <img src="https://forthebadge.com/images/badges/0-percent-optimized.svg" width="150"/>
    </a>
    <br>
    <br>
    <a>
        <img src="./docs/0_Index/logos/dragonstone-badge.png" width="141"/>
    </a>
    <a>
        <img src="https://img.shields.io/badge/crystal-%23000000.svg?style=for-the-badge&logo=crystal&logoColor=white"/>
    </a>
    <a>
        <img src="https://img.shields.io/badge/ruby-%23CC342D.svg?style=for-the-badge&logo=ruby&logoColor=white"/>
    </a>
    <a>
        <img src="https://img.shields.io/badge/c-%2300599C.svg?style=for-the-badge&logo=c&logoColor=white"/>
    </a>
</p>

## What is Dragonstone?
Dragonstone is a work in progress with many core features either not yet implemented or are only partially implemented, its a Ruby-Like/Crystal-Like programming language built using Ruby, Crystal and C. The goal of this language is meant to provide programmers with happiness and choice. The choice of using interpreted for quick scripting, compiled for heavy applications, dynamic by default but with the ability to enable static, interop with C is the goal but might include Ruby and Crystal interop as well, ability to optionally use a garbage collector, or ownership. But, easy enough to pickup for a newcomer.

P.S. Just a heads up, the codebase is an absolute messy state and some things might not make sense or are duplicated. This is v4 of the project after all and after multiple architecture shifts (v1 pure Ruby -> v2 Ruby/C -> v3 Crystal/Ruby/C -> v4 Crystal/C), Ruby’s gone for performance reasons, interop is bare-bones (currently just puts/printf), garbage collection/ownership is not yet implemented. These will be ironed out and the `Great Refactor` will come before v0.1.0 so don't worry. It's my first time making a language sorry, Thank you.

P.S.S. oh and its super slow rn 1 billion iterations take 50-60 mins 🤷🏽‍♀️ working on it.

## Project Setup

1. Clone this repository.
2. Run `shards build` to build the binary which gets placed in `./bin`.
3. Run `dragonstone.bat` inside `./bin` to add it to user env path and handoff to `dragonstone.ps1`.
4. If it doesn't handoff to .ps1 you can run it, or just load up your terminal and cd to ./bin

## Usage

#### Run Files

```bash
    dragonstone run examples/hello_world.ds

    ./bin/dragonstone.exe run examples/hello_world.ds
```

#### Run Tests
```bash
    crystal spec
```

## Examples

#### Example of Print, Comments and Requiring Files.
```crystal
    puts "Hello World!"
```

```
    # This is a Single Line Comment.

    #[
        This is a Multi-Line Comment.
    ]#

    message = "Hello!" # Trailing Comment.

    #[ Multi-Line Comment on same line. ]#     numbers = 10    #[ Inside or outside. ]#
```

```crystal
(from examples/test_use.ds)
    con magic = 42

    def add(a, b)
        a + b
    end

(from examples/use.ds)
    use "test_use.ds"

    puts add(magic, 8)
```

#### Some More Examples!
```crystal
    name = "Ringo"
    puts name
```

```crystal
    def greet(name)
        puts "Hello, #{name}!"
    end

    greet("Jules")
```

```crystal
    class 🔥
    あ = true
  
        def 道
            if あ
                puts "Hello!"
            end
        end
    end

    🔥.道
```

#### Some More Examples with Optional Types!
```crystal
    name: str = "Peet"
    puts name
```

```crystal
    a: int = 10
    b: int = 10
    numbers = a + b
    puts numbers
```

```crystal
    def 😱(name: str) -> str
        puts "Hello, #{name}!"
    end

    😱("V")
```

See the `examples/` directory for more sample `.ds` files.

## Contact

    Project:
        www.github.com/vallereya

## License

*© 2025 Vallereya*
<br>
All rights reserved.
<br>

*Code and Contributions have **Apache-2.0 License** since it's using Crystal for some of the build, agreed upon by all copyright holders aka me. See **LICENSE** for more information.*
