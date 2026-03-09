# Self-Hosting/Bootstrapping Directory
## Overview
This is a working directory for Self-Hosting/Bootstrapping, currently ignored files, but will be unignored when complete.

> WARNING: The self-hosted/bootstrapped dragonstone is a work in progress, it does not work as intended right now and some files are just the `stage0` crystal implementation copy/paste so I can view them in one spot. Also these files are not a good representation of "good" dragonstone code as they were implemented in steps based on what was available at the time during the bootstrap phase.

## New Project Structure
```md
[root]/                                 -> dragonstone bootstrap build
    ├── examples/                       -> example .ds files; modified for bootstrap
    ├── spec/                           -> spec testing files (dragonstone spec module)
    ├── bin/                            -> **BUILD**
    │   ├── build/                      -> dragonstone bootstrap builds
    │   ├── dev/                        -> dragonstone bootstrap dev builds
    │   ├── payloads/                   -> dragonstone bootstrap installer specific payloads
    │   ├── resources/                  -> dragonstone bootstrap resources files needed for builds
    │   └── main.ds                     -> main entry
    ├── src/                            -> **SOURCE**
    │   ├── dragonstone/                
    │   │   ├── api/                    -> api providers
    │   │   │   ├── eden/               -> eden provider
    │   │   │   └── api.ds              -> api controller
    │   │   ├── cli/                    -> command line interface
    │   │   │   ├── etc/                
    │   │   │   ├── proc/               
    │   │   │   └── cli.ds              
    │   │   ├── core/                   -> compiler, VM, and targets
    │   │   ├── native/                 -> interpreter runtime
    │   │   ├── shared/                 -> shared front-end and runtime commons
    │   │   ├── stdlib/                 -> standard library
    │   │   └── syslib/                 -> system library
    │   ├── VERSION                     -> generated version file
    │   ├── mode.ds                     -> backend flag/env helpers
    │   ├── version.ds                  -> version control
    │   └── dragonstone.ds              -> main orchestrator
    ├── forge.toml
    └── README.md                   -> *you are here* (Bootstrap README)
```
