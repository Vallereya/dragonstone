# Changelog v0.1.0

## [0.1.8] (2026-08-26)
[0.1.8]: https://github.com/Vallereya/dragonstone/releases#release-v0.1.8-Alpha

### features
#### language & syntax (stage0 & stage1)

* *(language)* **numeric literals** now support radix prefixes (`0x`, `0b`, `0o`), `_` separators, and exponents ([#27], [@Vallereya])
* *(language)* **statement modifiers** (`if` / `unless`) now apply to all statements, reading right-to-left ([#27], [@Vallereya])
* *(language)* **named arguments** now bind by name positionally and support out-of-order execution or skipped defaults ([#27], [@Vallereya])
* *(language)* **default parameters** now accept constants and expressions, evaluating in the caller's scope ([#27], [@Vallereya])
* *(language)* **non-local returns** **`return`** are implemented for `|...|` blocks, unwinding directly to what wrote it ([#27], [@Vallereya])
* _(language)_ **`bag`** is now a fully implemented keyword with a constructor ([#27], [@Vallereya])
* *(language)* **`.class`** is now reachable from source; `x.class` parses on both backends and answers an instance's class, while `define class` remains rejected ([#27], [@Vallereya])
* *(language)* **nil-safe indexing** (`obj[i]?` and `obj[i]?= v`) now compiles on the core backend, and the index is still not evaluated when the receiver is nil ([#27], [@Vallereya])
* *(runtime)* **`object_id` & `not_nil!`** added as universal methods for all identity-bearing values ([#27], [@Vallereya])

#### stdlib & syslib
* _(stdlib)_ **`array`** expanded with 24 new methods including `map`, `select`, `any?`, `join`, `uniq`, `count`, and `sort` ([#27], [@Vallereya])
* _(stdlib)_ **`map`** expanded with 10 new methods including `map_values`, `has_value?`, `delete`, and `inject` ([#27], [@Vallereya])
* _(stdlib)_ **`bag`** type fully implemented with 10 methods including `add`, `includes?`, and `select` ([#27], [@Vallereya])
* _(syslib)_ **`file`** module added with `exists?`, `file?`, `join`, and `extname` capabilities ([#27], [@Vallereya])
* _(syslib)_ **`path`** module added featuring `stem`, `absolute?`, and anchoring `expand` capabilities ([#27], [@Vallereya])
* _(syslib)_ **`dir`** module added to expose absolute `current` directories, `exists?`, and `glob` pathing ([#27], [@Vallereya])
* _(runtime)_ **`ffi.call("env_get", [key])`** reads an environment variable through the native ABI; answers `nil` when the variable is unset and `""` when it is set to nothing, which are different answers ([#27], [@Vallereya])

#### architecture (stage0 & stage1)
* _(vm)_ **stage1 execution** is now fully supported on the core backend, added performance gains over the interpreter ([#27], [@Vallereya])
* _(vm)_ **module reopening** now correctly merges namespaces and definitions across files instead of overwriting previous declarations ([#27], [@Vallereya])
* _(vm)_ **singletons** (`def self.x`) now correctly bind to object and survive imports ([#27], [@Vallereya])
* _(vm)_ **struct initialization** now automatically handles implicit constructors to named fields on the core backend ([#27], [@Vallereya])
* _(vm)_ **short-circuiting operators** (`||=`, `&&=`) are now fully compiled with proper jumping to prevent right-hand-side execution ([#27], [@Vallereya])
* _(architecture)_ **interpreter singletons** were moved to engine, preserving static methods across imports ([#27], [@Vallereya])
* _(architecture)_ **`run` and `run_file` pipelines** merged to share a single execution path, so AST lowering and accurate resolution for inline source ([#27], [@Vallereya])
* _(tooling)_ **bytecode source mapping** added by padding the `@lines` array so every opcode and operand maps to precise source lines for better error reporting ([#27], [@Vallereya])

### bugfixes
#### parser & lexer
* _(parser)_ **ternary then-branches** no longer swallow the colon separator as a false type annotation ([#27], [@Vallereya])
* _(parser)_ **line boundaries** enforced for postfix operators like `[` to prevent accidental array indexing into previous statements ([#27], [@Vallereya])
* _(parser)_ **`nil`** permitted in a type union using `str? \| nil` style annotations ([#27], [@Vallereya])
* _(parser)_ **`.`** keyword may be a method name after the dot; e.g. `resolver.next`, `x.end` ([#27], [@Vallereya])
* _(parser)_ **`define Receiver.name`** is now correctly supported where previously only `define self.name` worked ([#27], [@Vallereya])
* _(parser)_ **[breaking]** Implicit argument lists now strictly stop at the end of the line ([#27], [@Vallereya])
* _(parser)_ **`elsif` & `elseif`** both accepted; normalizes to `elsif` under stage1 ([#27], [@Vallereya])
* _(parser)_ **`to_source` rendering** fixed across both stages; `+=` had never survived a render (`x + = 1`), bodies were joined with `"; "` which Dragonstone has no separator for, map literals rendered as `{"k": 1}` instead of `{ "k" -> 1 }`, and `rescue` used Crystal's `rescue Foo => e` rather than `rescue e: Foo` ([#27], [@Vallereya])
* _(parser)_ **`DebugEcho`** rendering fixed in stage1 to accurately match stage0 ([#27], [@Vallereya])
* _(lexer)_ **`.abs`** is now callable by name, bypassing the former issue with the `:ABSTRACT` token ([#27], [@Vallereya])
* _(lexer)_ **`:DEF` -> `:DEFINE` & `:FUN` -> `:FUNCTION`** token names updated to match the keywords ([#27], [@Vallereya])
* _(lexer)_ **string interpolations** re-parse fixed, preventing silent failures when using `let` or `fix` inside interpolated expressions ([#27], [@Vallereya])

#### scoping & resolution
* _(interpreter)_ **lexical scope** correctly traverses out through parents, allowing bare name resolutions for siblings ([#27], [@Vallereya])
* _(interpreter)_ **`self`** is correctly resolved inside blocks by traversing the full scope chain ([#27], [@Vallereya])
* _(interpreter)_ **block writes** to an enclosing variable are no longer discarded; the closure is now held by reference, so an accumulator such as `total = total + n` inside `items.each do \|n\|` keeps its value instead of reading back as its initial ([#27], [@Vallereya])
* _(interpreter)_ **`alias`** now binds a value; `alias Color = Colorize::Object` was a no-op, while an alias whose right-hand side is not a resolvable constant path stays type-only ([#27], [@Vallereya])
* _(interpreter)_ **nested definitions** no longer reopen the root namespace; `class Object` inside `module Colorize` now creates `Colorize::Object` rather than reopening the global `Object` ([#27], [@Vallereya])
* _(interpreter)_ **`fun` closures** strictly isolate scope, closing over globals but no longer leaking into the caller's local variables ([#27], [@Vallereya])
* _(interpreter)_ **recursive local variables** fixed to assign to their own method frames rather than clobbering outer frame variables ([#27], [@Vallereya])
* _(vm)_ **block parameters** now save and restore their masked slots during frame execution to prevent variable leakage ([#27], [@Vallereya])
* *(vm)* **core backend fix** for primitives, named arguments, block closures, and default parameters so they have parity ([#27], [@Vallereya])

#### exceptions, control flow & I/O
* _(interpreter)_ **`case` / `when`** now dispatches on the condition's type instead of comparing with `==`, so class and range patterns match rather than silently falling through to `else` ([#27], [@Vallereya])
* _(vm)_ **exception loops** fixed by tracking handler, preventing a `raise` inside a `rescue` body from infinitely re-entering the same handler ([#27], [@Vallereya])
* _(vm)_ **stack underflows** refactored to prevent infinite `ensure` loops and `raise` leaves the stack with enclosing expressions ([#27], [@Vallereya])
* _(vm)_ **opcode** route fixed for `Dragonstone::Error` to allow handling without losing class and location info ([#27], [@Vallereya])
* _(vm)_ **stale exception handlers and loop contexts** are explicitly discarded when a frame unwinds early via return ([#27], [@Vallereya])
* _(runtime)_ **`quit`** no longer discards buffered stdout, now reliably buffered through `Runtime::DeferredIO` ([#27], [@Vallereya])
* _(interpreter & vm)_ **`quit` & `abort`** flush I/O buffers before the ABI `exit()` triggers ([#27], [@Vallereya])
* _(runtime)_ **`quit f()`** now correctly evaluates a call expression ([#27], [@Vallereya])
* _(runtime)_ **Broken pipes** (`… \| head`) now exit quietly rather than throwing an `UNEXPECTED ERROR` ([#27], [@Vallereya])
* _(runtime)_ **`Char` & `Float64`** formatting separated to ensure `inspect` accurately without sharing the `display` formatter ([#27], [@Vallereya])
* _(runtime)_ **`ee!`** inline debug echo now flushes strictly in source order ([#27], [@Vallereya])

[#27]: https://github.com/Vallereya/dragonstone/pull/27

<br>

---

> Contributors:

V. ([@Vallereya])

[@Vallereya]: (https://github.com/Vallereya)
