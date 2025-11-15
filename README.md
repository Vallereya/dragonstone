<p align="center">
    <div align="center"> <img src="./docs/0_Index/logos/dragonstone-logo-type.png" width="500"/>                            </div>
</p>
<br>

## What is Dragonstone?
Dragonstone is a general purpose, high-level, object-oriented programming language. In its current form it is an interpreted language (with the compiled portion coming soon), inspired by Ruby and Crystal but designed for programmer happiness, productivity, and choice. 

*<font color="color:#5E06EE;">This language is a work in progress. At this stage, much can still be changed.*</font>

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
4. Run the command `.\bin\dragonstone.bat --rebuild-exe` *(this rebuilds the project with the `--release` flag and the custom icon embedded)*.
5. <font color="color:#5E06EE;">(Optional)</font> Run the command `.\bin\dragonstone.bat` to add `.\bin` to your user PATH environment variable, allowing you to run `dragonstone` from anywhere. Restart your terminal after this step.

**Note**: You can also just use `shards build` on Windows for a standard build without the custom icon added. <br>
**Note**: Also on Windows you can just use the installer listed in releases. <br>

## Usage
#### Run Files via Interpreter. 
```bash
    dragonstone run examples/hello_world.ds

    ./bin/dragonstone.exe run examples/hello_world.ds
```

#### Select Backend (temporary flag).
```bash
    # Force the bytecode/VM backend
    dragonstone run --backend core examples/hello_world.ds

    # Stick to the native interpreter regardless of heuristics
    DRAGONSTONE_BACKEND=native dragonstone run examples/hello_world.ds
```

#### Build and Run Files via Compiler (Coming Soon). 
```bash
    dragonstone build examples/hello_world.ds

    ./bin/dragonstone.exe build examples/hello_world.ds
```

#### Run Test/Spec.
```bash
    crystal spec

    # Backend-aware helper (auto-detects repo root even from src/dragonstone/native or core)
    # Use `bash` ./scripts/backend_ci.sh [...] when on Windows (Git Bash / WSL).
    ./scripts/backend_ci.sh spec --backend core
```

## Benchmark Information
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

## Examples
#### Example of output using `echo`:
```crystal
    echo "Hello World!"
```

#### Example of comments/block comments using `#` and `#[ ]#`:
```nim
    # This is a Single Line Comment.

    #[
        This is a Multi-Line Comment.
    ]#

    message = "Hello!" # Trailing Comment.

    #[ Multi-Line Comment on same line. ]#     numbers = 10    #[ Inside or outside. ]#
```

#### Some Examples:
###### Example of a String.
```crystal
    name = "Ringo"
    echo name
```

###### Example of a `def` Method and String Interpolation.
```crystal
    def greet(name)
        echo "Hello, #{name}!"
    end

    greet("Jules")
```

###### Example of a `Class`.
```crystal
    class Person
        happy = true

        def greet
            if happy
                echo "Hello!"
            end
        end
    end

    person = Person.new
    person.greet
```
###### Also Ascii and Unicode are supported.
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

###### Example of a Module with `con`, an immutable constant, and `::` for scope resolution.
```crystal
    module Grades
        con Score = 100

        class Greeting
            def greet
                "Hello! I got a #{Grades::Score}%!"
            end
        end
    end

    echo Grades::Score
    echo Grades::Greeting.greet
```

###### Example of a Map literal with key -> value pairs.
```crystal
    ages = { "Jules" -> 32, "Ringo" -> 29, "Peet" -> 35 }
    echo ages["Jules"]

    ages["Ringo"] = 30
    echo ages["Ringo"]

    ages.each do |name, age|
        echo "#{name} is #{age}"
    end

    e! ages.keys
    e! ages.values
```

#### Some More Examples but with Optional Types:
###### Example of a String with types.
```crystal
    name: str = "Peet"
    echo name
```

###### Example of some math/integers with types.
```crystal
    a: int = 10
    b: int = 10
    numbers = a + b
    echo numbers
```

###### Two examples of a `Class` with types.
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

###### Two examples of `struct`.
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

```crystal
    struct Point
        property x: int
        property y: int
    end

    point = Point.new(x: 1, y: 2)

    with point
        echo x
        echo y
    end
```

#### Example of using other files with `use`.
###### (from ./examples/test_use.ds)
```crystal
    con magic = 42

    def add(a, b)
        a + b
    end
```

###### (from ./examples/use.ds)
```crystal
    use "test_use.ds"

    echo add(magic, 8)
```

#### Two examples of `para`, the Dragonstone version of a Proc.
###### For any `{}` used within Dragonstone, these can also be split between lines or placed on the same line.

```crystal
greet = ->(name: str) {
    "Hello, #{name}!" 
}

echo greet.call("Alice")
```

```crystal
square: para(int, int) = ->(x: int) { x * x }

echo square.call(6)
```

#### Examples the interop (some done but still a work in progress).

```crystal
    # Call puts from Ruby
    ffi.call_ruby("puts", ["Hello from Ruby!"])

    # Call puts from Crystal
    ffi.call_crystal("puts", ["Hello from Crystal!"])

    # Call printf from C
    ffi.call_c("printf", ["Hello from C!"])
```

See the `examples/` directory for more sample `.ds` files.

## Contact
    Project:
        www.github.com/vallereya

## License
*© 2025 Vallereya* <br>
All rights reserved. <br> <br>
*Code and Contributions have **Apache-2.0 License** agreed upon by all copyright holders. <br> <br>
See **LICENSE** for more information.* <br>
