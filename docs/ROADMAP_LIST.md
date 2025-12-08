```diff
- Verify parser & bytecode coverage for all operators, on all backends and on llvm compiler.
- Implement optional Garbage Collection (c-like or crystal-like).
- Implement optional Borrow Checker/Ownership (rust-like).
- Implement support for concurrency.

- Extend annotations via `@[...]`, to be able to use other meaningful things.
- Add dev more commands/flags.
- Setup more micro-benchmarks.
- Setup more spec/unit testing.

- Setup a proper build/release pipeline.
- Set CI + cross-platform builds (Linux/macOS/Windows).
- Maximize portability/native cross-platform.
- VM unwind stack w/ exception objects, make a method cache w/ fallback path.

- Alpha Update ->       Documentation, Examples, Tutorials, and ChangeLog.
- Start work for the `forge` package manager.
- For diagnostics (file:line:col, caret spans, suggestion hints) needs redone some are empty or not giving enough info for the errors.
- For exceptions (ParserError, RuntimeError, TypeError, etc) needs redone for the same reasons as diagnostics.

- Fix FFI and make sure to do some boilerplate code avoidance.
- Expand the bindings of the 3-Way Interop, so Dragonstone can call more.
- Start C lib with something basic.
- Start Crystal lib with something basic.
- Start Ruby lib with something basic.

- Expand C lib.
- Expand Crystal lib.
- Expand Ruby lib.
- C, Crystal, and Ruby libs expanded into stdlib, they are made separate then added as an stdlib.
- Expand the stdlib and port any stdlib to dragonstone if there is any not.

- Begin Bootstrapping.
- Remove donors so everything runs on dragonstone.
- No Ruby or Crystal in build, runtime, or tooling (C is fine, especially for FFI).
- Freeze current grammar subset if needed on C side, and finish target build outs for the compiler.
- Fix `--backend` flags.
```

## For Forge (WORK IN PROGRESS):
1. package.forge or forge.toml?
    - dragonstsones manifest for application/program information in the project folder (root/working directory) and can be created by running `forge init`; Example:
        ```toml
        [PACKAGE]
        Name            =   "Application"
        Version         =   "0.0.0"
        Authors         =   "My Name"
        License         =   "My License"
        Description     =   "Application Description"

        [DRAGONSTONE VERSION]
        Require         =   "0.0.0"

        [TARGET]
        Main            =   "./build/application"

        [DEPENDENCIES]
        Dependency      =   github["REPO/NAME", "VERSION"]

        [DEVELOPMENT DEPENDENCIES]
        DevDependency   =   github["REPO/FILENAME.EXT"]
        
        [REGISTRY]
        Key             = "123" # idk yet ?? probably only show up in lock.forge but some sort of verification
        ```
2. lock.forge
    - when running the command `forge install` resolves and installs the specified dependencies.
3. config.forge
    - Allows a user to change keywords. So devs can create their own `use` alias, with `$:` so path of `./some/folder/modules` can become `$:Modules/<something>`. By default it's in english, but someone who may not know english can change something like `echo` to something like `eco` which is a portuguese translation. This should also be able to convert a file using the keywords in this list to something else. Might try this but idk yet.
    - I might also ex
