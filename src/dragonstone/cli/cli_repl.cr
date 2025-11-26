require "./proc/common"

module Dragonstone
    module CLIRepl
        extend self

        PROMPT = "dragonstone> "
        EXIT_COMMANDS = {"exit", "quit"}

        def start_repl(args : Array(String), stdout : IO, stderr : IO, stdin : IO = STDIN) : Int32
            typed = false
            log_to_stdout = false

            args.each do |arg|
                case arg

                when "--typed"
                    typed = true

                when "--log"
                    log_to_stdout = true

                when "--help", "--h"
                    ProcCommon.print_usage(stdout)
                    return 0

                else
                    stderr.puts "Unknown REPL option: #{arg}"
                    return 1

                end
            end

            stdout.puts "Dragonstone REPL v#{Dragonstone::VERSION}"
            stdout.puts "Type 'exit' or press Ctrl + D to quit"
            stdout.puts

            loop do
                stdout.print PROMPT
                stdout.flush

                line = stdin.gets

                if line.nil?
                    stdout.puts
                    break
                end

                input = line.chomp
                trimmed = input.strip

                break if EXIT_COMMANDS.includes?(trimmed)
                next if trimmed.empty?

                begin
                    result = Dragonstone.run(input, log_to_stdout: log_to_stdout, typed: typed)
                    output = result.output
                    stdout.puts(output) unless output.empty?

                rescue e : Dragonstone::Error
                    stderr.puts "ERROR: #{e.message}"

                rescue e
                    stderr.puts "UNEXPECTED ERROR: #{e.message}"

                end
            end

            stdout.puts "Dragonstone REPL Closed."
            return 0
        end
    end
end
