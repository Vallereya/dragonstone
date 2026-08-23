require "./proc/common"

module Dragonstone
    module CLIRepl
        extend self

        PROMPT = "dragonstone> "
        EXIT_COMMANDS = {"exit", "quit"}

        def start_repl(args : Array(String), stdout : IO, stderr : IO, stdin : IO = STDIN) : Int32
            typed = false

            args.each do |arg|
                case arg

                when "--typed"
                    typed = true
                when "--help", "--h"
                    ProcCommon.print_usage(stdout)
                    return 0
                else
                    stderr.puts "Unknown REPL option: #{arg}"
                    return 1
                end
            end

            stdout.puts "Dragonstone REPL v#{Dragonstone::VERSION}"
            stdout.puts "Type 'exit' or press Ctrl + C to quit"
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

                # The REPL writes each result itself (and skips a blank
                # line when the entry produced nothing), so it captures
                # rather than streaming.
                begin
                    result = Dragonstone.run(input, typed: typed)
                    output = result.output
                    stdout.print(output) unless output.empty?
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
