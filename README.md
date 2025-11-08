<p align="center">
    <div align="center"> <img src="./docs/0_Index/logos/Dragonstone-Logo-Full.png" width="500"/>                            </div>
</p>
<br>
<p align="center">
    <a> <img src="./docs/0_Index/logos/dragonstone-badge.png" width="141"/>                                                 </a>
    <a> <img src="https://img.shields.io/badge/crystal-%23000000.svg?style=for-the-badge&logo=crystal&logoColor=white"/>    </a>
    <a> <img src="https://img.shields.io/badge/ruby-%23CC342D.svg?style=for-the-badge&logo=ruby&logoColor=white"/>          </a>
    <a> <img src="https://img.shields.io/badge/c-%2300599C.svg?style=for-the-badge&logo=c&logoColor=white"/>                </a>
</p>
<br>

## What is Dragonstone?
Dragonstone is a general purpose, high-level, object-oriented programming language. In its current form it is an interpreted language (with the compiled portion coming soon), inspired by Ruby and Crystal but designed for programmer happiness, productivity, and choice. 

*<font color="color:#5E06EE;">This language is a work in progress. At this stage, much can still be changed.*</font>

**P.S.** Just a heads up, it was built with windows and is stable so you can download/clone and get up and running easy; However, I have not tested the build process on Linux or MacOS yet.

## Benchmark
- When using `--release` flag.
- <2% overhead at scale.
- Near identical for loops vs single.

You can run these yourself from the `./scripts` directory. *(This was made using Windows/Powershell)*

### 1 Billion Single Loop Iteration Benchmark (Interpreter)
```bash
    ~4.47 million iterations/second
    ~0.224 microseconds per iteration

    Iterations:     223,712 ms
    Actual Time:    223.71 seconds (3.73 minutes)
```

### 1 Billion Nested Loop Iteration Benchmark (Interpreter)
```bash
    ~4.43 million iterations/second
    ~0.226 microseconds per iteration

    Iterations:     225,810 ms
    Actual Time:    225.81 seconds (3.76 minutes)
```

## Project Setup
### Requirements
1. The [Crystal Programming Language](https://crystal-lang.org/install/) needs to be installed. (1.17.1 or higher are the only versions verified)

### Building from Source using Bash (All Platforms)
1. Clone this repository.
2. Change directory to this project.
3. Run the command `shards build` to build *(this gets placed in `./bin`)*.

### Building from Source using Terminal or Powershell (Windows Only)
1. Clone this repository.
2. Change directory to this project.
3. Run the command `shards build` to build *(this gets placed in `./bin`)*.
4. Run the command `.\bin\dragonstone.bat --rebuild-exe` *(this builds the project with the custom icon embedded)*.
5. <font color="color:#5E06EE;">(Optional)</font> Run the command `.\bin\dragonstone.bat` to add `.\bin` to your user PATH environment variable, allowing you to run `dragonstone` from anywhere. Restart your terminal after this step.

**Note**: You can also just use `shards build` on Windows for a standard build without the custom icon added. <br>
**Note**: Also on Windows you can just use the installer listed in releases. <br>

## Usage
#### Run Files via Interpreter. 
```bash
    dragonstone run examples/hello_world.ds

    ./bin/dragonstone.exe run examples/hello_world.ds
```

#### Build and Run Files via Compiler (Coming Soon). 
```bash
    dragonstone build examples/hello_world.ds

    ./bin/dragonstone.exe build examples/hello_world.ds
```

#### Run Test/Spec.
```bash
    crystal spec
```

## Examples
#### Example of print/puts; Dragonstone uses `echo`:
```crystal
    echo "Hello World!"
```

#### Example of comments/block comments; Dragonstone uses `#` and `#[ ]#`:
```nim
    # This is a Single Line Comment.

    #[
        This is a Multi-Line Comment.
    ]#

    message = "Hello!" # Trailing Comment.

    #[ Multi-Line Comment on same line. ]#     numbers = 10    #[ Inside or outside. ]#
```

#### Example of requiring/importing other files.
###### (from examples/test_use.ds)
```crystal
    con magic = 42

    def add(a, b)
        a + b
    end
```

###### (from examples/use.ds)
```crystal
    use "test_use.ds"

    echo add(magic, 8)
```

#### Some More Examples!
```crystal
    name = "Ringo"
    echo name
```

```crystal
    def greet(name)
        echo "Hello, #{name}!"
    end

    greet("Jules")
```

```crystal
    class 🔥
    あ = true
  
        def 道
            if あ
                echo "Hello!"
            end
        end
    end

    🔥.道
```

```crystal
    ages = { "Jules" -> 32, "Ringo" -> 29, "Peet" -> 35 }
    echo ages["Jules"]
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

    echo MyModule::Test
    echo MyModule::MyClass.greet
```

#### Some More Examples with Optional Types!
```crystal
    name: str = "Peet"
    echo name
```

```crystal
    a: int = 10
    b: int = 10
    numbers = a + b
    echo numbers
```

```crystal
    def 😱(name: str) -> str
        echo "Hello, #{name}!"
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
            echo "Hello, my name is #{self.name}"
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
    echo "x: #{point.x}, y: #{point.y}"
```

See the `examples/` directory for more sample `.ds` files.

## Contact
    Project:
        www.github.com/vallereya

## License
*© 2025 Vallereya* <br>
All rights reserved. <br>

*Code and Contributions have **Apache-2.0 License** agreed upon by all copyright holders. <br>
See **LICENSE** for more information.* <br>