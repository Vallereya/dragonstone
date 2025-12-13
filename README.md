<p align="center">
    <div align="center"> <img src="./docs/0_Index/logos/dragonstone-logo-type.png" width="500"/> </div>
</p>
<br>
<p align="center">
    <div align="center">
        <img src="https://img.shields.io/badge/⚠️%20Warning-This%20language%20is%20a%20work%20in%20progress,%20and%20much%20can%20still%20be%20changed!-5E06EE"/>
    </div>
    <br>
    <div align="center">
        <img src="https://img.shields.io/badge/🟢%20Passing-Frontend:%20Interpreter-379144"/>
        <img src="https://img.shields.io/badge/🟢%20Passing-Backend:%20ByteCode-379144"/>
    </div>
    <div align="center">
        <img src="https://img.shields.io/badge/🟡%20Limited-Backend:%20LLVM-E7CD54"/>
    </div>
    <div align="center">
        <img src="https://img.shields.io/badge/🔴%20Failing-Backend:%20Ruby-BC002D"/>
        <img src="https://img.shields.io/badge/🔴%20Failing-Backend:%20Crystal-BC002D"/>
        <img src="https://img.shields.io/badge/🔴%20Failing-Backend:%20C-BC002D"/>
    </div>
</p>
<br>

## <img src="./docs/0_Index/icons/dragonstone.png" width="25"/> What is Dragonstone?
Dragonstone is a general purpose, high-level, object-oriented programming language. It is both an interpreted and compiled language, it's inspired by Ruby and Crystal but designed for programmer happiness, productivity, and choice.

> **WARNING:** Some compile targets are still a work in progress, as of `v0.1.2` the LLVM backend has limited support, there are some minor gaps between it and the interpreter and a few edge cases. However all examples, excluding the stdlibs are working fine. Please report any you find so they can be fixed. In regards to the C, Crystal, and the Ruby backends these still need built out as they only create temporary artifacts for echo/strings, I haven't merged that work yet.
<br>
<br>

## ⚙️ Project Setup
### *Requirements*
1. The [Crystal Programming Language](https://crystal-lang.org/install/) needs to be installed (*1.17.1+*).
2. (optional) [**LLVM/Clang**](https://releases.llvm.org/); While the [Crystal Programming Language](https://crystal-lang.org/install/) also installs [LLVM/Clang](https://releases.llvm.org/), installing a standalone version is recommended if you want to target `dragonstone build --target llvm`.
3. (optional) The [Ruby Programming Language](https://www.ruby-lang.org/en/downloads/) is needed if you want to use `dragonstone build --target ruby` (*3.4.6+*).

### *To Build from Source (All Platforms)*
###### **(MacOS/Linux/Windows)**
1. Clone this repository.
2. `cd` to the project directory.
3. Run `shards build --release`

<br>

> **Tip:** Always use the `--release` flag for production builds as it significantly improves performance, without it a standard build is made and the dragonstone interpreter will run files roughly about 3-5x slower.

### *To Build from Source (Linux)*
###### **(Linux Recommended)**
1. Clone this repository.
2. `cd` to the project directory.
3. Run `./bin/dragonstone.sh --rebuild`
4. (optional) Run `./bin/dragonstone.sh --install` which adds `.\bin` to your user PATH.
    - After running that command please restart your terminal, then you can use `dragonstone` from anywhere.

###### **(Linux Alternative)**
3. Run `shards build --release` for a standard build and without PATH.

<br>

> **Tip for Linux Users:** If you want to rebuild the project, after already doing so, you can use `./bin/dragonstone.sh --clean` which will remove the build files, then you can use `./bin/dragonstone.sh --rebuild` to build it again. For an automated version you can use `./bin/dragonstone.sh --clean-rebuild` which will clean first then rebuild for you.

### *To Build from Source (Windows)*
###### **(Windows Recommended)**
1. Clone this repository.
2. `cd` to the project directory.
3. Run `.\bin\dragonstone.bat --rebuild`
    - This builds with the icons/resources and adds `.\bin` to your user PATH.
    - After running that command please restart your terminal, then you can use `dragonstone` from anywhere.

###### **(Windows Alternative)**
3. Run `shards build --release` for a standard build, without any icons/resources or PATH.

<br>

> **Tip for Windows Users:** If you want to rebuild the project, after already doing so, you can use `.\bin\dragonstone.bat --clean` which will remove the build files, then you can use `.\bin\dragonstone.bat --rebuild` to build it again. For an automated version you can use `.\bin\dragonstone.bat --clean-rebuild` which will clean first then rebuild for you.

> **Tip for Windows Users:** An installer is also available in the [Releases](https://github.com/Vallereya/dragonstone/releases) section.

## 🧪 Usage
#### Run Files via Interpreter. 
```bash
    # On PATH:
    dragonstone run examples/hello_world.ds

    # Not on PATH:
    ./bin/dragonstone.exe run examples/hello_world.ds
```

#### Select a Backend to Use.
###### For now this is a temporary flag so I can verify some of my `--backend` build targets, this may change in the future when the self-host/bootstrap process begins.
```bash
    # Select between native (interpreter) or core (compiler) backends.
    dragonstone run --backend native examples/hello_world.ds
    dragonstone run --backend core examples/hello_world.ds

    # Without specifying it will automatically use the native (interpreter) or 
    # with auto it can choose the correct backend based on what is being ran 
    # within the file.
    dragonstone run examples/hello_world.ds
    dragonstone run --backend auto examples/hello_world.ds

    # However, if you don't want to specify the flag every time you can just 
    # set it change it anytime, this works on the fly.
    DRAGONSTONE_BACKEND=core dragonstone run examples/hello_world.ds

    # Or export the flag once, to set it permanently for the CI:
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
    # To run the full spec/unit testing suite.
    crystal spec

    # Helper script that runs the spec for just a specific backend.
    ./scripts/backend_ci.sh spec --backend native
    ./scripts/backend_ci.sh spec --backend core
```

## ✨ Examples
#### Example of a sting output using `echo`:
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

###### Example of a Module with `con`, an immutable constant, and `::` for scope resolution for modules.
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

###### Two examples of a `Class` with types, one of which showing Unicode support again.
```crystal
    def 😱(name: str) -> str
        echo "Hello, #{name}!"
    end

    😱("V")
```

###### With this example using a bit more complex features.
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

###### With this example showing `with`.
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

#### Example of using/importing other files with `use`.
###### From (./examples/use.ds)
```crystal
    use "./test_use"

    echo add(magic, 8)
```

###### What's being grabbed from (./examples/test_use.ds), and using the `con` keyword again.
```crystal
    con magic = 42

    def add(a, b)
        a + b
    end
```

###### Imports via `use` are built out, so you can import a file, selectively import as well, and the same applies by importing through a url.
```crystal
    # Both by file and selectively using `from` with it.
    use "./test_use"
    use { divide } from "./raise"

    # Any both by file and selectively via a url, I used `cdn.jsdelivr.net`
    # because it was the only thing I could find that would grab the examples from GitHub.
    use "https://cdn.jsdelivr.net/gh/vallereya/dragonstone@main/examples/unicode"
    use { MyModule } from "https://cdn.jsdelivr.net/gh/vallereya/dragonstone@main/examples/resolution"
```
> **WARNING:** I've mostly resolved issues with imports that occurred after the interpreter/compiler split, you might still come across some edge cases, please report any you find so I can fix them.

#### Two examples of `para`, this is the Dragonstone version of what another languages calls a `Proc`.
###### For any `{}` used within Dragonstone, these can also be split between lines or placed on the same line.
```crystal
greet = ->(name: str) {
    "Hello, #{name}!" 
}

echo greet.call("Jalyn")
```

###### Another bit more complex `para`.
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

###### Like I said, the ffi is still a work in progress but I have settled on what it will look like, the only reason it doesn't work yet is because I'm still deciding on whether I want it as something from the stdlib by `use "ffi"` or through extending the actual ffi to support it, doing that would require a rewrite in some places that already use the current ffi.
```crystal
    #! This does not currently work but just to give you an ideal of where its going.
    Invoke C
        with printf

        as {
            "Hello from C!"
        }

    end
```

#### See the `examples/` directory for more sample `.ds` files.

## ⚡ Benchmark Information
- Built with --release.
- Results are for this specific benchmark + machine; expect variance across CPUs/Operating Systems.
- "Nested" means an extra loop layer (measuring loop-overhead vs a single loop), not extra work.
- <2% overhead at scale.
- Near identical for loops vs single.

You can run these yourself from the `./tests/benchmark` directory.

### *1 Billion Nested Loop Iteration Benchmark (Interpreter)*
```
    Iterations:             ~4.47M iterations/s
    Per-iteration cost:     ~223.71 ns
    Actual Time:            223.71 s (~3.73 min)
```

### *1 Billion Nested Loop Iteration Benchmark (LLVM Compiler)*
```
    Iterations:             ~811M iterations/s
    Per-iteration cost:     ~1.23 ns
    LLVM Compiler Time:     1.2326 s
    Results:                ~182× vs Interpreter
```

### *Comparison Context (Rough context, not direct comparable)*
###### For 1 billion iterations of this benchmark (Interpreter):
```
    Ruby v2.X.X         = ~15-30 minutes    (varies by version)
    Python v3.X.X       = ~5-15 minutes     (varies by version)
 -> Dragonstone         = ~3.7 minutes
    Lua                 = ~1-2 minutes
    JavaScript          = ~10-30 seconds    (using V8)
```

###### For 1 billion iterations of this benchmark (Compiler/LLVM):
```
    C                   = ~0.5-1.5 seconds
    Rust                = ~0.5-1.5 seconds
 -> Dragonstone LLVM    = ~1.23 seconds
    GO                  = ~1-2 seconds
    Java                = ~2-5 seconds      (using JIT)
    PyPy                = ~10-20 seconds    (using JIT)
    Node.js             = ~10-30 seconds    (using V8)
```

## 📝 Contact
    Project:
        www.github.com/vallereya

## ⚖️ License
*© 2025 Vallereya*
<br>

*Code and Contributions have **Apache-2.0 License**.
<br>
See **LICENSE** for more information.*
<br>
