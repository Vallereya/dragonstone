<p align="center">
    <div align="center">
        <img src="../docs/0_Index/logos/dragonstone-logo-type.png" width="500"/>
    </div>
</p>

<h1 align="center">                     Development Roadmap             </h1>
<h5 align="center">                          Pre-Alpha                  </h5>
<h5 align="center">                      v0.0.1 -> v0.1.0               </h5>
<h5 align="center">                          ☑️ ❌ ⭕                  </h5>

<h3> Overall Goals:                                                     </h3>

- Core Language Setup (**allow for both interpreted and compiled**)
- Standard Library Setup (**stdlib**)
- Package Manager Setup (**forge**)
    - .forge extension/inside is just .toml format
- Tooling
- Optional Types (Dynamic and Static)
- Optional Typing (Implicit and Explicit)
- Optional Garbage Collection (**Opt in or out of manual memory management**)
- Optional version of Borrow Checker/Ownership (*cool? or nah?*)
- S-Tier Performance: 
    - Compile to Machine Code (*coming soon..working on thought process for this*)
    - Interpret to Bytecode executed by the DVM (**Dragonstone Virtual Machine**)
- Complete removal of donor languages and bootstrap dragonstone to be Self-Hosted
    - ☑️ Dragonstone v1 had Python, was removed and rebuilt.
    - ☑️ Dragonstone v2 had Ruby, ran into issues with performance and rebuilt.
    - ☑️ Dragonstone v3 also had Ruby and Crystal, ran into issues with performance again and rebuilt.
    - ❌ Dragonstone v4 had Ruby, Crystal and C, wasn't ready to switch, got annoyed with Ruby so removed it and rebuilt again.
    - Dragonstone v5 (This Version & Last Rewrite) has Crystal and C.
- Crystal and Ruby inspired but with a modern refresh (*for now just temporarily use their keywords then swap but then keep legacy compatibility?*)
- Bindings to C at minimum, expose a blank ffi to C++? (*maybe?*), and MAYBE with Crystal and Ruby too.

---

###     <h2 align="center">         Phase One
#####   <h6 align="center">         `v0.0.0 -> v0.0.1`

```diff
+ Make these config files exist: .editorconfig, .gitattributes, and .gitignore
+ Make these misc files exist: LICENSE, README.md, shard.yml (for Crystal), and package.forge (for Dragonstone)
+ Make these files exist: ARCHITECTURE.md, CONTRIBUTING.md, and ROADMAP.md
+ Make these folders exist: bin, docs, examples, spec, tests, scripts, and src
+ Scaffold the dragonstone project.
+ Setup as a Crystal .exe and basic language setup.
+ No regressions moving forward from day 1, clear grammar and recovery. **USE THE FUCKING GIT THIS TIME**
```

###     <h2 align="center">         Phase Two
#####   <h6 align="center">         `v0.0.1 -> v0.0.2`

```diff
+ Make sure any Dragonstone builds are removed, from v1-v4.
+ Create new/port previous AST, Parser, Lexer, Compiler, Interpreter and VM.
+ Port previous Error Handling.
+ Port the basic diagnostics from Dragonstone v4 (file:line:col, caret spans, suggestion hints)
+ Refactor for stack-based VM and single-pass bytecode.
+ Refactor for Pratt/Precedence Parser and produce Typed AST.
+ Simple syntax (Ruby and Crystal inspired) with unambiguous block/indent rules.
```

###     <h2 align="center">         Phase Three
#####   <h6 align="center">         `v0.0.2 -> v0.0.3`

```diff
+ Port from previous versions and expand the Bytecode and VM (op codes "opc", constant pool, interned symbols).
+ Basic Values: Nil, Bool, Int, Float, Character, and String
+ VM in Crystal: frames, call stack, globals/envs, up-values placeholders
+ Implement additional testing for both success and coverage for syntax/runtime failures.
+ Implement benchmark tests.
+ Expand examples.
+ Implement basic build pipeline.
```

###     <h2 align="center">         Phase Four
#####   <h6 align="center">         `v0.0.3 -> v0.0.4`

```diff
+ Implement the optional type system for dynamic and static.
+ Implement alias.
+ Implement variable instance.
+ Implement getters and setters.
+ Implement a way to import/require files (use).
+ Verify/Add Module, Class, Def, End.
+ Verify/Add con (constant), fun (function), struct, enums.
```

###     <h2 align="center">         Phase Five
#####   <h6 align="center">         `v0.0.4 -> v0.0.5`

```diff
+ add .github folder for sponsors.
+ Arithmetic, variable binding, and simple calls.
+ Basic loops, strings, some math, etc.
+ Basic datatypes.
+ if/elsif/else.
+ unless, break/else.
+ while, case (value-match), select.
```

###     <h2 align="center">         Phase Six
#####   <h6 align="center">         `v0.0.5 -> v0.0.6`

```diff
+ Expand arithmetic, comparison, logical, indexing, assignment variants (+=, ||=).
+ String interpolation and Unicode Support.
+ Class creation, inheritance, method lookup, operator overrides.
+ Proper up-values/closed-over locals.
+ typeof, swap puts -> echo, p! -> e!, refactor cli and ast (make them modular).
+ Start Standard Library with something basic (String Length).
+ REPL needs to be wired to the CLI.
```

###     <h2 align="center">         Phase Seven
#####   <h6 align="center">         `v0.0.6 -> v0.0.7`

```diff
+ Implement optional explicit typing. 
+ Escapes: raise, begin/rescue/redo/retry/do/next/ensure, yield, &block capture.
+ Add support for Array, map (hash), and bag(like set but not .set that's different) on core collections via blocks.
+ Add support for .slice and .display/.inspect (my version of to_s/inspect).
+ Truthiness rules (nil/false, rest truthy, falsey).
+ Escapes are implemented but needs extended to each, map and bag. 
+ Advanced Values: Para (proc), Lambda values, Sym/Symbol (Symbol), and Object* 
```

###     <h2 align="center">         Phase Eight
#####   <h6 align="center">         `v0.0.7 -> v0.0.8`

```diff
+ COLLECTIONS: Add support for select, until, inject, and each.
+ Add support for singleton methods.
+ Update folder structure so its properly splitup for bootstrapping and separate compiler.
+ Allow the use (import/require) to support for urls.
+ Make a string builder in stdlib for the runtime.
- 
- 
```

###     <h2 align="center">         Phase Nine
#####   <h6 align="center">         `v0.0.8 -> v0.0.9`

```diff
- For diagnostics (file:line:col, caret spans, suggestion hints) needs redone some are empty or not giving enough info for the errors. Full/Expand diagnostics handling.
- For exceptions (ParserError, RuntimeError, TypeError, etc) needs redone for the same reasons as diagnostics. Full/Expand exception handling.

- Set CI + cross-platform builds (Linux/macOS/Windows).
- Maximize portability/native cross-platform.

- Extend for named for Bag/NamedBag, Array/NamedArray, Map/NamedMap, Range/NamedRange, and Tuple/NamedTuple?

- Add support for concurrency.
- VM unwind stack w/ exception objects.
- Make a method cache w/ fallback path.
- Implement optional Garbage Collection (c-like or crystal-like) 
- Implement optional Borrow Checker/Ownership (rust-like).
- Fix FFI and make sure to do some boilerplate code avoidance, and freeze current grammar subset if needed on C side.
- Expand the bindings of the 3-Way Interop, so Dragonstone can call more from any C, Ruby or Crystal code.
- No Ruby/Crystal/C in build, runtime, or tooling and port stdlib to dragonstone if there is any not.
```

###     <h2 align="center">         Phase Ten
#####   <h6 align="center">         `v0.0.9 -> v0.1.0`

```diff
- The `Great Refactor`.
- (Started) Begin Bootstrapping, remove donors so everything runs on dragonstone.
- Add dev commands/flags.
- (Started) Setup micro-benchmarks, verify parser & bytecode coverage for all operators.
- (Started) Flesh out the docs, samples, examples, tutorials, changelogs, and some versioned grammar.
- (Started) Start building the website (quickstart, language tour, FFI roadmap, reference to the docs, etc.)
- (Started) Start building a VSCode extension for language syntax support and running files.
- Tagged v0.1.0, signed binaries, reproducible build notes, installer/uninstaller, and setup a proper build/release pipeline.
```

---

<h1 align="center">                     The Future of Dragonstone       </h1>
<h5 align="center">                              Alpha                  </h5>
<h5 align="center">                         v0.1.0 -> v1.0.0            </h5>

###     <h2 align="center">         Future Phases
#####   <h6 align="center">         `v0.1.0 -> v0.2.0`

```diff
- Expand the stdlib.
```
