require "./proc/common"
require "./proc/file_ops"

module Dragonstone
    module CLIRun
        extend self

        def run_command(args : Array(String), stdout : IO, stderr : IO) : Int32
            typed    = false
            filename = nil

            args.each do |arg|
                if arg == "--typed"
                    typed = true
                elsif arg.starts_with?("--")
                    stderr.puts "Unknown option: #{arg}"
                    return 1
                elsif filename.nil?
                    filename = arg
                else
                    stderr.puts "Too many arguments for run command"
                    return 1
                end
            end

            unless filename
                return ProcCommon.show_usage(stdout)
            end

            return ProcFileOps.handle_missing_file(filename, stderr) unless File.exists?(filename)
            ProcFileOps.warn_if_unknown_extension(filename, stderr)

            run_file(filename, stdout, stderr, typed: typed)
        end

        def run_file(filename : String, stdout : IO, stderr : IO, typed : Bool = false) : Int32
            begin
                result = Dragonstone.run_file(filename, log_to_stdout: false, typed: typed)
                stdout.puts result.output
                return 0
            rescue e : Dragonstone::Error
                stderr.puts "ERROR: #{e.message}"
                return 1
            rescue e
                stderr.puts "UNEXPECTED ERROR: #{e.message}"
                return 1
            end
        end
    end
end
