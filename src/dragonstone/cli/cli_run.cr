require "./proc/common"
require "./proc/file_ops"

module Dragonstone
    module CLIRun
        extend self

        def run_command(args : Array(String), stdout : IO, stderr : IO) : Int32
            typed        = false
            filename     = nil

            backend_mode : BackendMode? = nil

            idx = 0

            while idx < args.size
                arg = args[idx]

                if arg == "--typed"
                    typed = true

                elsif arg == "--backend"
                    idx += 1

                    if idx >= args.size
                        stderr.puts "Missing value for --backend"
                        return 1
                    end
                    
                    backend_mode = parse_backend_flag(args[idx], stderr)
                    return 1 unless backend_mode

                elsif arg.starts_with?("--backend=")
                    value = arg.split("=", 2)[1]? || ""
                    backend_mode = parse_backend_flag(value, stderr)
                    return 1 unless backend_mode

                elsif arg.starts_with?("--")
                    stderr.puts "Unknown option: #{arg}"
                    return 1

                elsif filename.nil?
                    filename = arg

                else
                    stderr.puts "Too many arguments for run command"
                    return 1
                end

                idx += 1
            end

            unless filename
                return ProcCommon.show_usage(stdout)
            end

            return ProcFileOps.handle_missing_file(filename, stderr) unless File.exists?(filename)
            ProcFileOps.warn_if_unknown_extension(filename, stderr)

            run_file(filename, stdout, stderr, typed: typed, backend: backend_mode)
        end

        def run_file(filename : String, stdout : IO, stderr : IO, typed : Bool = false, backend : BackendMode? = nil) : Int32
            begin
                result = Dragonstone.run_file(filename, log_to_stdout: false, typed: typed, backend: backend)
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

        private def parse_backend_flag(value : String, stderr : IO) : BackendMode?
            BackendMode.parse(value)
        rescue
            stderr.puts "Unknown backend '#{value}'. Expected auto, native, or core."
            nil
        end
    end
end
