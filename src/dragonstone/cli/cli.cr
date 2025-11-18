# ---------------------------------
# ------------- MAIN --------------
# ------------- CLI ---------------
# ---------------------------------
# ---------- DISPATCHER -----------
# ---------------------------------
require "../../dragonstone"

require "./proc/common"
require "./proc/file_ops"
require "./proc/inspect"

require "./cli_run"
require "./cli_build"
require "./cli_repl"
require "./cli_backend"

module Dragonstone
    module CLI
        extend self 

        def run (
            argv = ARGV, 
            stdout : IO = STDOUT,
            stderr : IO = STDERR
        ) : Int32

            return ProcCommon.print_version(stdout)     if ProcCommon.version_command?(argv)
            return ProcCommon.print_help(stdout)        if ProcCommon.help_command?(argv)
            return ProcCommon.show_usage(stdout)        if argv.empty?

            command = argv[0]
            args    = argv[1..-1]

            case command

            when "lex"
                return ProcInspect.handle_lex_command(args, stdout, stderr)

            when "parse"
                return ProcInspect.handle_parse_command(args, stdout, stderr)

            when "run"
                return CLIRun.run_command(args, stdout, stderr)

            when "build", "compile"
                return CLIBuild.build_command(args, stdout, stderr)

            when "build-run", "buildrun"
                return CLIBuild.build_and_run_command(args, stdout, stderr)

            when "repl"
                return CLIRepl.start_repl(args, stdout, stderr)

            when "backend"
                return CLIBackend.handle_command(args, stdout, stderr)

            else
                stderr.puts "Unknown command: #{command}"
                ProcCommon.print_usage(stdout)
                return 1
            end
        end
    end
end
