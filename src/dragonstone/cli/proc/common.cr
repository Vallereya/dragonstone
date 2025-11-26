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
            io.puts "------------------------------------------------------------------------------------"
            io.puts "                         DRAGONSTONE COMMAND LINE INTERFACE                         "
            io.puts "------------------------------------------------------------------------------------"
            io.puts "Usage:"
            io.puts "   dragonstone <command> [options]"
            io.puts
            io.puts "Commands:"
            io.puts "   version, --version, --v                     Show Version"
            io.puts "   help, --help, --h                           Show Help"
            io.puts "   capability, --capability, --c               Show Backend Capabilities"
            io.puts "   repl                                        Starts REPL"
            io.puts "   lex <file>                                  Tokenize a File"
            io.puts "   parse <file>                                Parse a File & Show AST"
            io.puts "   run <file>                                  Run a File"
            io.puts "   build [options] <file>                      Build a File"
            io.puts "   build-run [options] <file>                  Build and Run a File"
            io.puts
            io.puts "Options:"
            io.puts "   <command> [--typed] <file>                  Force types in a File"
            io.puts "   <command> [--backend <backend>] <file>      Choose a backend to use"
            io.puts "                         auto                      = default backend (native)"
            io.puts "                         native                    = interpreter backend"
            io.puts "                         core                      = compiler backend"
            io.puts "   <command> [--target <target>] <file>        Choose a target to build for"
            io.puts "                        bytecode                   = default target"
            io.puts "                        llvm                       = llvm target"
            io.puts "                        c                          = c target"
            io.puts "                        crystal                    = crystal target"
            io.puts "                        ruby                       = ruby target"
            io.puts "   <command> [--output <dir>] <file>           Choose a target location to build to"
            io.puts
            io.puts "------------------------------------------------------------------------------------"
        end
    end
end
