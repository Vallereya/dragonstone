module Dragonstone
    module ProcCommon
        extend self

        def version_command?(argv : Array(String)) : Bool
            argv.size == 1 && {"version", "--version", "--v"}.includes?(argv[0])
        end

        def help_command?(argv : Array(String)) : Bool
            argv.size == 1 && {"help", "--help", "--h"}.includes?(argv[0])
        end

        def print_version(io : IO) : Int32
            io.puts "Dragonstone #{Dragonstone::VERSION}"
            return 0
        end

        def print_help(io : IO) : Int32
            print_usage(io)
            return 0
        end

        def show_usage(io : IO) : Int32
            print_usage(io)
            return 1
        end

        def print_usage(io : IO) : Nil
            io.puts "-----------------------------------------------------------------------------"
            io.puts "                     DRAGONSTONE COMMAND LINE INTERFACE                      "
            io.puts "-----------------------------------------------------------------------------"
            io.puts "Usage:"
            io.puts "   dragonstone <command> [options]"
            io.puts
            io.puts "Commands:"
            io.puts "   --version or --v                            Show Version"
            io.puts "   --help or --h                               Show Help"
            io.puts "   repl                                        Starts REPL"
            io.puts "   <command> [--typed] <file>                  Force types in a File"
            io.puts
            io.puts "Commands to lex a File:"
            io.puts "   lex <file>                                  Tokenize File"
            io.puts
            io.puts "Commands to parse a File:"
            io.puts "   parse <file>                                Parse File & Show AST"
            io.puts
            io.puts "Commands to run a File:"
            io.puts "   run <file>                                  Run File"
            io.puts "   run [--backend auto|native|core] <file>     Choose backend to use"
            io.puts "                  auto     = default"
            io.puts "                  native   = interpreter"
            io.puts "                  core     = compiler"
            io.puts
            io.puts "Commands for building a File via compiler:"
            io.puts "   build <file>                                Compile File"
            io.puts "-----------------------------------------------------------------------------"
        end
    end
end
