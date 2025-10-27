<p align="center">
    <div align="center">
        <img src="./docs/0_Index/logos/Dragonstone-Logo-Full.png" width="500"/>
    </div>
</p>

<h1 style="text-align:center;">         Development Roadmap             </h1>
<h5 style="text-align:center;">          v0.0.1 -> v0.1.0               </h2>


---

<h6 style="text-align:center;">                ✅ ❎                   </h3>

<h3 style="text-align:center;">         Overall Goals:                  </h3>

```
                            * Core Language Setup
                            * Runtime and Stdlib
                            * Tooling
                            * Optional types, garbage collection and ownership.
                            * Bindings to C at least, maybe with Ruby and Crystal too
                            * Good Performance; Compile to machine code/Interpret to bytecode
                            * Self-Hosting and removal donor languages
```

---

###     <h2 style="text-align:center;">         Phase One
#####   <h4 style="text-align:center;">         Basic Setup
#####   <h6 style="text-align:center;">         `v0.0.0 -> v0.0.1`

```
            ✅ Scaffold project as a Crystal program/exe
            ✅ CONTRIBUTING.md (Exists)
            ✅ ARCHITECTURE.md (Exists)
            ✅ Docs Folder (Exists)
            ✅ Basic language setup
```

###     <h2 style="text-align:center;">         Phase Two
#####   <h4 style="text-align:center;">         Simple Parser/AST/Lexer & Error Model
#####   <h6 style="text-align:center;">         `v0.0.1 -> v0.0.2`

```
            ✅ stack VM, single-pass bytecode
            ✅ simple syntax (Ruby-like/Crystal-like) with unambiguous block/indent rules
            ✅ implement Pratt/precedence parser and produce typed AST
            ✅ implement basic diagnostics (file:line:col, caret spans, suggestion hints)
            ✅ basic loops, strings, some math, etc
            ✅ no regressions moving forward, and clear grammar and recovery
```

###     <h2 style="text-align:center;">         Phase Three
#####   <h4 style="text-align:center;">         Bytecode and VM Skeleton
#####   <h6 style="text-align:center;">         `v0.0.2 -> v0.0.3`

```
            - stack-based bytecode (compact op codes "opc", constant pool, interned symbols)
            ✅ basic values: Nil, Bool, Int, Float, String, Symbol, Object*
            ✅ VM in Crystal: frames, call stack, globals/envs, upvalues placeholder
            ✅ additional testing both success and coverage for syntax/runtime failures
            ✅ benchmark test
            ✅ basic datatypes
```

###     <h2 style="text-align:center;">         Phase Four
#####   <h4 style="text-align:center;">         Object Model and OOP
#####   <h6 style="text-align:center;">         `v0.0.3 -> v0.0.4`

```
            - Class, Module, Object, singleton methods, method tables
            - Method cache w/ fallback path.
            - class creation, inheritance, method lookup, operator overrides
            - additional testing both success and coverage for syntax/runtime failures
            - constants, arithmetic, variable binding, simple calls
            - if/elsif/else, unless, while, until, break/next/redo, case (value-match)
            - 
```

###     <h2 style="text-align:center;">         Phase Five
#####   <h4 style="text-align:center;">         Control Flow and Exceptions
#####   <h6 style="text-align:center;">         `v0.0.4 -> v0.0.5`

```
            - implement optional type system
            - implement optional explicit typing
            - requiring files (use for files and import for urls)
            - Exception; RuntimeError, TypeError, etc
            - raise, begin/rescue/else/ensure; VM unwind stack w/ exception objects
```

###     <h2 style="text-align:center;">         Phase Six
#####   <h4 style="text-align:center;">         Closures, Blocks & Iterators
#####   <h6 style="text-align:center;">         `v0.0.5 -> v0.0.6`

```
            - bindings for 3 way interop so Dragonstone can call any C, Ruby or Crystal
            - ffi fixes and boilerplate code avoidance
            - proper upvalues / closed-over locals
            - yield, &block capture, Proc/lambda values
            - each, map, select, inject on core collections via blocks
            - 
```

###     <h2 style="text-align:center;">         Phase Seven
#####   <h4 style="text-align:center;">         Strings and Core Collections
#####   <h6 style="text-align:center;">         `v0.0.6 -> v0.0.7`

```
            - interpolation & escapes
            - Array, Hash with iteration, slicing, to_s/inspect
            - String builder in runtime
            - 
```

###     <h2 style="text-align:center;">         Phase Eight
#####   <h4 style="text-align:center;">         Operators, Precedence, Truthiness
#####   <h6 style="text-align:center;">         `v0.0.7 -> v0.0.8`

```
            - implement full syntax highlighter
            - full exception handling
            -  arithmetic, comparison, logical, indexing, assignment variants (+=, ||=)
            - Truthiness rules (nil/false falsey, rest truthy)
            - Parser & bytecode coverage for all operators
            - set CI + cross-platform builds (Linux/macOS/Windows)
```

###     <h2 style="text-align:center;">         Phase Nine
#####   <h4 style="text-align:center;">         CLI, Packaging and update
#####   <h6 style="text-align:center;">         `v0.0.8 -> v0.0.9`

```
            - implement optional ownership model (rust-like borrow checker)
            - implement separate optional garbage collection
            - VS Code extension for language syntax highlighting/recognition and running files?
            - maximize portability/native cross-platform
            - release and installation pipeline
            - begin dragonstone bootstrapping
            - No Ruby/Crystal/C in build/runtime/tooling and port stdlib to dragonstone
            - freeze current grammar subset if needed on C side
```

###     <h2 style="text-align:center;">         Phase Ten
#####   <h4 style="text-align:center;">         Performance Pass, Self-Hosting (subset) and Donor Removal
#####   <h6 style="text-align:center;">         `v0.0.9 -> v0.1.0`

```
            - the `Great Refactor`
            - Remove donors: everything runs on dragonstone
            - dev commands
            - microbenchmarks
            - docs, samples, changelog, versioned grammar, tutorial
            - docs/ site (quickstart, language tour, FFI roadmap)
            - tag v0.1.0, signed binaries, reproducible build notes
            - 
```

---