<p align="center">
    <div align="center">
        <img src="./0_Index/logos/dragonstone-logo-type.png" width="500"/>
    </div>
</p>

<h1 align="center">                     Development Roadmap             </h1>
<h5 align="center">                          Prototype                  </h5>
<h5 align="center">                      v0.0.1 -> v0.1.0               </h5>
<h5 align="center">                          ☑️ ❌ ⭕                  </h5>

<h3> Overall Goals:                                                     </h3>

- Core Language Setup (**allow for both interpreted and compiled**).
- Standard Library Setup (**stdlib**).
- Package Manager Setup (**Forge aka .forge**).
- Optional Types (Dynamic and Static).
- Optional Typing (Implicit and Explicit).
- Optional Garbage Collection (**Opt in or out of manual memory management**).
- Optional Borrow Checker/Ownership (**Opt in or out of manual ownership model**).
- Self-Hosted.
- Tooling.
- Crystal and Ruby inspired syntax but with a modern refresh.
- 3-Way Bindings to C, Crystal and Ruby.
- Native provider for `eden`.
- S-Tier Performance: 
    - Compile to Machine Code executed by the DC (**Dragonstone Compiler**)
    - Interpret to Bytecode executed by the DVM (**Dragonstone Virtual Machine**)

---

###     <h2 align="center">         Phase One
#####   <h6 align="center">         `v0.0.0 -> v0.0.1`

```diff
+ The `Great Refactor`: (Part One)              Prototype Refactor.
+ Make these config files exist: .editorconfig, .gitattributes, and .gitignore
+ Make these misc files exist: LICENSE, README.md, shard.yml (for Crystal), and package.forge (for Dragonstone)
+ Make these files exist: ARCHITECTURE.md, CONTRIBUTING.md, and ROADMAP.md
+ Make these folders exist: bin, docs, examples, spec, tests, scripts, and src
```

###     <h2 align="center">         Phase Two
#####   <h6 align="center">         `v0.0.1 -> v0.0.2`

```diff
+ No regressions moving forward from day 1, clear grammar and recovery. **USE THE FUCKING GIT THIS TIME**
+ Scaffold the dragonstone project.
+ Setup as a Crystal .exe and basic language setup.
+ Make sure any Dragonstone builds are removed, from v1-v4.
+ Refactor for Pratt/Precedence Parser and produce Typed AST.
```

###     <h2 align="center">         Phase Three
#####   <h6 align="center">         `v0.0.2 -> v0.0.3`

```diff
+ Create new/port previous AST, Parser, Lexer, Compiler, Interpreter and VM.
+ VM in Crystal: frames, call stack, globals/envs, up-values placeholders
+ Refactor for stack-based VM and single-pass bytecode.
+ Simple syntax (Ruby and Crystal inspired) with unambiguous block/indent rules.
+ Port from previous versions and expand the Bytecode and VM (op codes "opc", constant pool, interned symbols).
```

###     <h2 align="center">         Phase Four
#####   <h6 align="center">         `v0.0.3 -> v0.0.4`

```diff
+ Port previous Error Handling.
+ Port the basic diagnostics from Dragonstone v4 (file:line:col, caret spans, suggestion hints)
+ Basic Values: Nil, Bool, Int, Float, Character, and String
+ Verify/Add Module, Class, Def, End, con (constant), fun (function), struct, enums.
+ Implement alias, variable instance, and getters and setters.
```

###     <h2 align="center">         Phase Five
#####   <h6 align="center">         `v0.0.4 -> v0.0.5`

```diff
+ add .github folder for sponsors.
+ Expand examples.
+ Implement basic build pipeline.
+ Implement benchmark tests.
+ Implement additional testing for both success and coverage for syntax/runtime failures.
```

###     <h2 align="center">         Phase Six
#####   <h6 align="center">         `v0.0.5 -> v0.0.6`

```diff
+ Basic loops, strings, some math, etc.
+ Arithmetic, variable binding, and simple calls.
+ if/elsif/else, unless, break/else, while, case (value-match), and select.
+ Expand arithmetic, comparison, logical, indexing, assignment variants (+=, ||=).
+ Class creation, inheritance, method lookup, operator overrides.
```

###     <h2 align="center">         Phase Seven
#####   <h6 align="center">         `v0.0.6 -> v0.0.7`

```diff
+ Implement the optional type system for dynamic and static.
+ Implement optional explicit typing. 
+ Implement a way to import/require files (use) and allow the use of urls.
+ String interpolation and Unicode Support.
+ typeof, swap puts -> echo, p! -> e!, refactor cli and ast (make them modular).
```

###     <h2 align="center">         Phase Eight
#####   <h6 align="center">         `v0.0.7 -> v0.0.8`

```diff
+ Escapes: raise, begin/rescue/redo/retry/do/next/ensure, yield, &block capture.
+ Add support for Array, map (hash), and bag(like set but not .set that's different) on core collections.
+ Add support for .slice and .display/.inspect (my version of to_s/inspect).
+ Truthiness rules (nil/false, rest truthy, falsey).
+ Escapes are implemented but needs extended to each, map and bag.
```

###     <h2 align="center">         Phase Nine
#####   <h6 align="center">         `v0.0.8 -> v0.0.9`

```diff
+ Proper up-values/closed-over locals.
+ Advanced Values: Para (proc), Lambda values, Sym/Symbol (Symbol), and Object*
+ Add support for singleton methods.
+ COLLECTIONS: Add support for select, until, inject, and each in collections.
+ Start Standard Library with a String Length, I/O, and a String Builder for the runtime.
```

###     <h2 align="center">         Phase Ten
#####   <h6 align="center">         `v0.0.9 -> v0.1.0`

```diff
+ The `Great Refactor`: (Part Two)              Pre-Alpha Refactor.
```

---

<h1 align="center">                   Transition to Pre-Alpha           </h1>
<h5 align="center">                          Pre-Alpha                  </h5>
<h5 align="center">                      v0.1.0 -> v0.1.1               </h5>

###     <h2 align="center">         Phase One
#####   <h6 align="center">         `v0.1.0 -> v0.1.1`

```diff
+ REPL needs to be wired to the CLI.
+ Update folder structure so its properly splitup for bootstrapping and separate compiler.
+ Modularize files to better support separate interpreter and compiler.
+ Flesh out the compiler for later targets.
+ Targets should be setup for artifacts for DVM (Bytecode), LLVM (IR), C, Crystal, and Ruby.
```

###     <h2 align="center">         Phase Two
#####   <h6 align="center">         `v0.1.1 -> v0.1.2`

```diff
+ Pre-Alpha Update ->   Documentation, Examples, Tutorials, and ChangeLog.
+ Tagged version & signed binaries.
+ Setup installer/uninstaller.
+ Reproducible build notes.
+ Flesh out what the versioned grammar is.
```

###     <h2 align="center">         Phase Three
#####   <h6 align="center">         `v0.1.2 -> v0.1.3`

```diff
+ Reformat the stdlib.
+ Add a simple networking and toml stdlibs, and adjust the path/file utilities.
+ Implement abstract classes and abstract def.

- Implement support for concurrency.
- Implement optional Garbage Collection (c-like or crystal-like).
- Support for annotations via `@[...]`.
```

###     <h2 align="center">         Phase Four
#####   <h6 align="center">         `v0.1.3 -> v0.1.4`

```diff
- Setup a proper build/release pipeline.
- Set CI + cross-platform builds (Linux/macOS/Windows).
- Maximize portability/native cross-platform.
- VM unwind stack w/ exception objects, make a method cache w/ fallback path.
- Implement optional Borrow Checker/Ownership (rust-like).
```

###     <h2 align="center">         Phase Five
#####   <h6 align="center">         `v0.1.4 -> v0.1.5`

```diff
- The `Great Refactor`: (Part Three)            Alpha Refactor.
```

---

<h1 align="center">                    Transition to Alpha              </h1>
<h5 align="center">                            Alpha                    </h5>
<h5 align="center">                      v0.1.X -> v0.2.0               </h5>

###     <h2 align="center">         Phase One
#####   <h6 align="center">         `v0.1.5 -> v0.1.6`

```diff
- Alpha Update ->       Documentation, Examples, Tutorials, and ChangeLog.
- Start work for the `forge` package manager.
- Add dev more commands/flags and setup micro-benchmarks, verify parser & bytecode coverage for all operators.
- For diagnostics (file:line:col, caret spans, suggestion hints) needs redone some are empty or not giving enough info for the errors.
- For exceptions (ParserError, RuntimeError, TypeError, etc) needs redone for the same reasons as diagnostics.
```

###     <h2 align="center">         Phase Two
#####   <h6 align="center">         `v0.1.6 -> v0.1.7`

```diff
- Fix FFI and make sure to do some boilerplate code avoidance.
- Expand the bindings of the 3-Way Interop, so Dragonstone can call more.
- Start C lib with something basic.
- Start Crystal lib with something basic.
- Start Ruby lib with something basic.
```

###     <h2 align="center">         Phase Three
#####   <h6 align="center">         `v0.1.7 -> v0.1.8`

```diff
- Expand C lib.
- Expand Crystal lib.
- Expand Ruby lib.
- C, Crystal, and Ruby libs expanded into stdlib, they are made separate then added as an stdlib.
- Expand the stdlib and port any stdlib to dragonstone if there is any not.
```

###     <h2 align="center">         Phase Four
#####   <h6 align="center">         `v0.1.8 -> v0.1.9`

```diff
- Begin Bootstrapping.
- Remove donors so everything runs on dragonstone.
- No Ruby or Crystal in build, runtime, or tooling (C is fine, especially for FFI).
- Freeze current grammar subset if needed on C side, and finish target build outs for the compiler.
- Fix `--backend` flags.
```

###     <h2 align="center">         Phase Five
#####   <h6 align="center">         `v0.1.9 -> v0.2.0`

```diff
- The `Great Refactor`: (Part Four)             Beta Refactor.
```

<h1 align="center">                     Transition to Beta              </h1>
<h5 align="center">                            Beta                     </h5>
<h5 align="center">                      v0.2.0 -> v1.X.X               </h5>

###     <h2 align="center">         Phase One
#####   <h6 align="center">         `v0.2.0 -> v0.3.0`

```diff
- Beta Update ->        Documentation, Examples, Tutorials, and ChangeLog.
- Start building a VSCode extension for language syntax support and running files.
- Start building the main website (quickstart, language tour, FFI roadmap, reference to the docs, etc.).
- Start building the website documentation subdomain.
- Start building the website forge subdomain.
```

###     <h2 align="center">         Phase Two
#####   <h6 align="center">         `v0.3.0 -> v0.4.0`

```diff
- Expand the `forge` package manager.
- 
- 
- 
- 
```

###     <h2 align="center">         Phase Three
#####   <h6 align="center">         `v0.4.0 -> v0.5.0`

```diff
- 
- 
- 
- 
- 
```

###     <h2 align="center">         Phase Four
#####   <h6 align="center">         `v0.5.0 -> v0.6.0`

```diff
- 
- 
- 
- 
- 
```

###     <h2 align="center">         Phase Five
#####   <h6 align="center">         `v0.6.0 -> v0.7.0`

```diff
- 
- 
- 
- 
- 
```

###     <h2 align="center">         Phase Six
#####   <h6 align="center">         `v0.7.0 -> v0.8.0`

```diff
- Start work on embedded functionality.
- 
- 
- 
- 
```

###     <h2 align="center">         Phase Seven
#####   <h6 align="center">         `v0.8.0 -> v0.9.0`

```diff
- VSCode extension completed.
- dragonstone-lang.org completed.
- docs.dragonstone-lang.org completed.
- forge.dragonstone-lang.org completed.
- The `forge` package manager has the ability for development by others.
```

###     <h2 align="center">         Phase Eight
#####   <h6 align="center">         `v0.9.0 -> v1.0.0`

```diff
- The `Great Refactor`: (Part Five & Final)     Release Refactor.
```
<h1 align="center">                    The Future of Dragonstone        </h1>
<h1 align="center">                     & Transition to Release         </h1>
<h5 align="center">                          Release                    </h5>
<h5 align="center">                      v1.0.0 -> v1.X.X               </h5>

###     <h2 align="center">         Phase One
#####   <h6 align="center">         `v1.0.0+`

```diff
- Release Update ->     Documentation, Examples, Tutorials, and ChangeLog.
- Implement native provider for `eden`.
- 
- 
- 
```
