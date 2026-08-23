module Dragonstone
    module ProcBootstrap
        extend self

        def bootstrap_command?(argv : Array(String)) : Bool
            argv.size == 1 && {"--sh"}.includes?(argv[0])
        end

        def return_bootstrap(io : IO) : Int32
            io.puts "The Dragonstone Self-Hosted CLI is not yet implemented with the `--sh` flag."
            io.puts "Use `dragonstone run ./bin/main.ds` to run the bootstrap version of Dragonstone for now."
            return 0
        end
    end
end
