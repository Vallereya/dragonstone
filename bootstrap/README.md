# Self-Hosting/Bootstrapping Directory
## Overview
This is a working directory for Self-Hosting/Bootstrapping.

> WARNING: The self-hosted/bootstrapped dragonstone is a work in progress, some parts do not work as intended right now and some files are just the `stage0` crystal implementation copy/paste so I can view them in one spot. Also these files are not a good representation of "good" dragonstone code as they were implemented in steps based on what was available at the time during the bootstrap phase.

## New Project Structure
```md
[root]/                                 -> dragonstone bootstrap build
    ├── src/                            -> **SOURCE**
    │   ├── dragonstone/
    │   │   ├── api/                    -> api placeholder  
    │   │   ├── cli/                    -> command line interface      
    │   │   ├── core/                   -> compiler, VM, and targets
    │   │   ├── native/                 -> interpreter runtime
    │   │   ├── hybrid/                 -> shared front-end and runtime commons
    │   │   ├── stdlib/                 -> standard library (hands off to root dir)
    │   │   └── syslib/                 -> system library (hands off to root dir)
    │   ├── VERSION                     -> generated version file
    │   ├── mode.ds                     -> backend flag/env helpers
    │   ├── version.ds                  -> version control
    │   └── dragonstone.ds              -> main orchestrator
    └── README.md                   -> *you are here* (Bootstrap README)
```
