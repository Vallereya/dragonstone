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
- Bindings to C, Crystal, Ruby, Python, and JavaScript.
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
+ REPL needs to be wired to the CLI.
+ Update folder structure so its properly splitup for bootstrapping and separate compiler.
+ Modularize files to better support separate interpreter and compiler.
+ Flesh out the compiler for later targets.
```

---

<h1 align="center">                   Transition to Pre-Alpha           </h1>
<h5 align="center">                          Pre-Alpha                  </h5>
<h5 align="center">                      v0.1.0 -> v0.1.1               </h5>

###     <h2 align="center">         Phase One
#####   <h6 align="center">         `v0.1.0 -> v0.1.1`

```diff
+ Pre-Alpha Update ->   Documentation, Examples, Tutorials, and ChangeLog.
+ Tagged version & binaries.
+ Setup installer/uninstaller.
+ Reproducible build notes.
+ Targets should be setup for artifacts for DVM (Bytecode), LLVM (IR), C, Crystal, and Ruby.
```

###     <h2 align="center">         Phase Two
#####   <h6 align="center">         `v0.1.1 -> v0.1.2`

```diff
+ Implemented support for abstract classes and abstract def.
+ Extend the LLVM backend be able to compile all current examples, excluding stdlibs.
+ Support for annotations via `@[...]`, this will allow us to use it later but doesn't need anything added yet.
+ Reformat the stdlib and adjust the path/file utilities so we can just use File/Path.
+ Flesh out what the versioned grammar is.
```

###     <h2 align="center">         Phase Three
#####   <h6 align="center">         `v0.1.2 -> v0.1.3`

```diff
+ Updated functions to allow default values directly, and updated `e!` and typeof to correctly use `->`.
+ Added support for command line arguments using `argv`.
+ Change FFI to use a new calling convention/syntax, maintains direct calls. 
+ Added support for `super` classes. 
+ Added a simple networking stdlib and simple toml stdlib.
```

###     <h2 align="center">         Phase Four
#####   <h6 align="center">         `v0.1.3 -> v0.1.4`

```diff
+ Added .strip
+ Added new echo options (eecho and ee!) for inline omission.
+ Added flush, getchar, and write to C's FFI. 
+ Extended `as` to allow `[] as T` and `{} as K -> V`.
+ Fixed Operator overloading issues, implemented ones now work correctly on all run options/llvm.
```

###     <h2 align="center">         Phase Five
#####   <h6 align="center">         `v0.1.4 -> v0.1.5`

```diff
+ The `Great Refactor`: (Part Three)            Alpha Refactor.
+ Removed an I/O stdlib, move directly to language.
+ Fixed build pipeline, so all `shards build`'s go to the same place. 
+ Added Levenshtein, Colorize, and Unicode stdlibs.
+ Updated mod, def, fun, cls, and abs to support optional module, define, function, class, and abstract depending on preference. 
```

---

<h1 align="center">                    Transition to Alpha              </h1>
<h5 align="center">                            Alpha                    </h5>
<h5 align="center">                      v0.1.X -> v0.2.0               </h5>

###     <h2 align="center">         Phase One
#####   <h6 align="center">         `v0.1.5 -> v0.1.6`

```diff
- Alpha Update ->       Documentation, Examples, Tutorials, and ChangeLog.
+ Expanded `fun` so it works as intended. 
+ Fixed `con` keyword, re-added optional explicit-ness with the keywords `let`, `var`, and `fix`. 
+ Re-Implemented `@@` for class instance variables, and `@@@` for module instance variables. 
+ Updated the optional Garbage Collection; Is now using hybrid-like system, with boehm fallback via vendor.
```

###     <h2 align="center">         Phase Two
#####   <h6 align="center">         `v0.1.6 -> v0.1.7`

```diff
- 
- 
- 
- 
- 
```

###     <h2 align="center">         Phase Three
#####   <h6 align="center">         `v0.1.7 -> v0.1.8`

```diff
- 
- 
- 
- 
- 
```

###     <h2 align="center">         Phase Four
#####   <h6 align="center">         `v0.1.8 -> v0.1.9`

```diff
- 
- 
- 
- 
- 
```

###     <h2 align="center">         Phase Five
#####   <h6 align="center">         `v0.1.9 -> v0.2.0`

```diff
- The `Great Refactor`: (Part Four)             Beta Refactor.
- Begin Bootstrapping.
- Freeze current grammar subset if needed on C side.
- 
- 
```

<h1 align="center">                     Transition to Beta              </h1>
<h5 align="center">                            Beta                     </h5>
<h5 align="center">                      v0.2.0 -> v1.X.X               </h5>

###     <h2 align="center">         Phase One
#####   <h6 align="center">         `v0.2.0 -> v0.3.0`

```diff
- Beta Update ->        Documentation, Examples, Tutorials, and ChangeLog.
- 
- 
- 
- 
```

###     <h2 align="center">         Phase Two
#####   <h6 align="center">         `v0.3.0 -> v0.4.0`

```diff
- 
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
- Finish Bootstrapping.
- Remove donors so everything runs on dragonstone.
- No Ruby or Crystal in build, runtime, or tooling (C is fine, especially for FFI/ABI).
- 
- 
```

###     <h2 align="center">         Phase Five
#####   <h6 align="center">         `v0.6.0 -> v0.7.0`

```diff
- Start building a VSCode extension for language syntax support and running files.
- Start building the main website (quickstart, language tour, FFI roadmap, reference to the docs, etc.).
- Start building the website documentation subdomain.
- Start building the website forge subdomain.
- Start work for the `forge` package manager.
```

###     <h2 align="center">         Phase Six
#####   <h6 align="center">         `v0.7.0 -> v0.8.0`

```diff
- Start work on embedded functionality.
- Setup a proper build/release pipeline.
- Set CI + cross-platform builds (Linux/macOS/Windows).
- Maximize portability/native cross-platform.
- Add signed binaries.
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
- 
- 
- 
- 
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
