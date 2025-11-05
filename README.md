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

*<span style="color: #5E06EE;">This language is a work in progress. At this stage, must can still be changed.*

<!-- 
The biggest goal is to be able to have a language that can be both compiled and interpreted, easy to read like Ruby/Crystal and interop with C, Ruby and Crystal. Ruby, and by extension Crystal, is a beautiful language and Crystal, bringing that inspiration, was made to improve upon Ruby but integration was not its goal. And that's okay. For Dragonstone what I want is to bring that original inspiration from ruby, the performance and C interop from Crystal, and with Dragonstone expand the interop to both Crystal and Ruby but with a new modern facelift, cross-platform capabilities, and most importantly aim to bring choice, the choice of using or not using things like dynamic vs static, compiled vs interpreted, implicit vs explicit, garbage collected vs none, hell even an ownership model.
-->

**P.S.** Just a heads up, it was built with windows and is stable so you can download/clone and get up and running easy; However, I have not tested the build process on Linux or MacOS yet.

## 1 Billion Iteration Benchmark (Interpreter)
```
    ~4.47 million iterations per second
    ~0.224 microseconds per iteration

    1B iterations:  223,712ms
    Actual Time:    223.71 seconds (3.73 minutes)
```

## Project Setup

### Building from Source using Bash (All Platforms)
1. Clone this repository.
2. Change directory to this project.
3. Run the command `shards build` to build *(this gets placed in `./bin`)*.

### Building from Source using Terminal or Powershell (Windows Only)
1. Clone this repository.
2. Change directory to this project.
3. Run the command `shards build` to build *(this gets placed in `./bin`)*.
4. Run the command `.\bin\dragonstone.bat --rebuild-exe` *(this builds the project with the custom icon embedded)*.
5. <span style="color: #5E06EE;">(Optional)</span> Run the command `.\bin\dragonstone.bat` to add `.\bin` to your user PATH environment variable, allowing you to run `dragonstone` from anywhere. Restart your terminal after this step.

**Note**: You can also just use `shards build` on Windows for a standard build without the custom icon added.

## Usage

#### Run Files via Interpreter. 

```bash
    dragonstone run examples/hello_world.ds

    ./bin/dragonstone.exe run examples/hello_world.ds
```

#### Build and Run Files via Compiler. 

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
```bash
    echo "Hello World!"
```

#### Example of comments/block comments; Dragonstone uses `#` and `#[ ]#`:
```dragonstone
    # This is a Single Line Comment.

    #[
        This is a Multi-Line Comment.
    ]#

    message = "Hello!" # Trailing Comment.

    #[ Multi-Line Comment on same line. ]#     numbers = 10    #[ Inside or outside. ]#
```

#### Example of requiring/importing other files.
```dragonstone
(from examples/test_use.ds)
    con magic = 42

    def add(a, b)
        a + b
    end
```

```dragonstone
(from examples/use.ds)
    use "test_use.ds"

    echo add(magic, 8)
```

#### Some More Examples!
```dragonstone
    name = "Ringo"
    echo name
```

```dragonstone
    def greet(name)
        echo "Hello, #{name}!"
    end

    greet("Jules")
```

```dragonstone
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

```dragonstone
    ages = { "Jules" -> 32, "Ringo" -> 29, "Peet" -> 35 }
    echo ages["Jules"]
```

```dragonstone
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
```dragonstone
    name: str = "Peet"
    echo name
```

```dragonstone
    a: int = 10
    b: int = 10
    numbers = a + b
    echo numbers
```

```dragonstone
    def 😱(name: str) -> str
        echo "Hello, #{name}!"
    end

    😱("V")
```

```dragonstone
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

```dragonstone
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

*© 2025 Vallereya*
<br>
All rights reserved.
<br>

*Code and Contributions have **Apache-2.0 License** since it's using Crystal for some of the build, agreed upon by all copyright holders aka me. See **LICENSE** for more information.*
