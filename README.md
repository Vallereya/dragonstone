<p align="center">
    <div align="center"> <img src="./docs/0_Index/logos/dragonstone-logo-type.png" width="500"/>                            </div>
</p>
<br>

## What is Dragonstone?
Dragonstone is a general purpose, high-level, object-oriented programming language. It is both an interpreted and compiled language, inspired by Ruby and Crystal but designed for programmer happiness, productivity, and choice. 

*<font color="color:#5E06EE;">This language is a work in progress. At this stage, much can still be changed.*</font>

## Project Setup
### Requirements
1. The [Crystal Programming Language](https://crystal-lang.org/install/) needs to be installed. (1.17.1 or higher are the only versions verified)

### Building from Source using Bash (All Platforms)
1. Clone this repository.
2. Change directory to this project.
3. Run `shards build` to build *(this gets placed in `./bin`)*.

### Building from Source using Terminal or Powershell (Windows Only)
1. Clone this repository.
2. Change directory to this project.
3. Run `shards build` to build *(this gets placed in `./bin`)*.
4. Run `.\bin\dragonstone.bat --rebuild-exe` *(this rebuilds the project with the `--release` flag and adds the dragonstone icon)*.
5. <font color="color:#5E06EE;">(Optional)</font> Run `.\bin\dragonstone.bat` to add `.\bin` to your users PATH environmental variable, allowing you to run `dragonstone` from anywhere. Restart your terminal after this step.

**Note**: You can also just use `shards build` on Windows for a standard build but this will not use the `--release` flag unless specified otherwise, this will make dragonstone compile/interpret usage significantly slower. <br>

**Note**: Also on Windows you can just use the installer listed in releases. <br>

## Usage
#### Run Files via Interpreter. 
```bash
    dragonstone run examples/hello_world.ds

    ./bin/dragonstone.exe run examples/hello_world.ds
```

#### Select Backend (for now this is a temporary flag).
```bash
    # Select between native (interpreter) or core (compiler) backends.
    dragonstone run --backend native examples/hello_world.ds
    dragonstone run --backend core examples/hello_world.ds

    # By default, dragonstone will use native (interpreter),
    # However, you can change it anytime.
    DRAGONSTONE_BACKEND=core dragonstone run examples/hello_world.ds

    # Or export the flag once for the CLI:
    export DRAGONSTONE_BACKEND=core
```

#### Build and Run Files via the Compiler with a target.
```bash
    # Supported Target Flags: bytecode, llvm, c, crystal, and ruby
    dragonstone build --target bytecode examples/hello_world.ds

    # Build and immediately execute the produced artifacts.
    dragonstone build-run --target bytecode examples/hello_world.ds
```

#### Run Test/Spec (still building out unit tests).
```bash
    crystal spec

    # helper script that runs spec for just a specific backend.
    ./scripts/backend_ci.sh spec --backend native
    ./scripts/backend_ci.sh spec --backend core
```

## Benchmark Information
- When using `--release` flag.
- <2% overhead at scale.
- Near identical for loops vs single.

You can run these yourself from the `./scripts` directory.

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

### Comparison Context
For 1 billion iterations of this benchmark:
```bash
    Ruby v2.X.X         = ~15-30 minutes    (varies by version)
    Python v3.X.X       = ~5-15 minutes     (varies by version)
 -> Dragonstone         = ~3.7 minutes
    Lua                 = ~1-2 minutes
    JavaScript          = ~10-30 seconds    (using V8)
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
###### This calling convention will change when I expand the FFI.

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
