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
Dragonstone is a general purpose, high-level, object-oriented programming language. In its current form it is an interpreted language, inspired by Ruby and Crystal but designed for programmer happiness, productivity, and choice. 

*This language is a work in progress.*

**P.S.** Just a heads up, it was built with windows and is stable so you can download/clone and get up and running easy; However, I have not tested the build process on Linux or MacOS yet. 

<!-- And, this language is a work in progress. There are a ton of things already done but some of the more interesting core features are either are not yet implemented or are only partially implemented. However, these will be ironed out and the `Great Refactor` will come before v0.1.0 so don't worry. It's my first time making a language sorry, Thank you. -->

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

```crystal
    ages = { "Jules" -> 32, "Ringo" -> 29, "Peet" -> 35 }
    puts ages["Jules"]
```

```crystal
    module MyModule
        con Test = 100

        class MyClass
            def greet
                "Hello from MyClass"
            end
        end
    end

    puts MyModule::Test
    puts MyModule::MyClass.greet
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

```crystal
    class Person
        property name: str

        def initialize(name: str)
            self.name = name
        end

        def greet
            puts "Hello, my name is #{self.name}"
        end
    end

    person = Person.new("Jules")
    person.greet
```

```crystal
    struct Point
        property x: int
        property y: int

        def initialize(@x: int, @y: int)
        end
    end

    point = Point.new(10, 20)
    puts "x: #{point.x}, y: #{point.y}"
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
