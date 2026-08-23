require "./proc/common"
require "./proc/file_ops"

module Dragonstone
    module CLIRun
        extend self

        def run_command(args : Array(String), stdout : IO, stderr : IO) : Int32
            typed        = false
            filename     = nil
            script_argv  = [] of String

            backend_mode : BackendMode? = nil

            idx = 0

            while idx < args.size
                arg = args[idx]

                if filename
                    script_argv << arg
                    idx += 1
                    next
                end

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
                else
                    filename = arg
                end

                idx += 1
            end

            unless filename
                return ProcCommon.show_usage(stdout)
            end

            return ProcFileOps.handle_missing_file(filename, stderr) unless File.exists?(filename)
            ProcFileOps.warn_if_unknown_extension(filename, stderr)
            run_file(filename, stdout, stderr, typed: typed, backend: backend_mode, argv: script_argv)
        end

        def run_file(filename : String, stdout : IO, stderr : IO, typed : Bool = false, backend : BackendMode? = nil, argv : Array(String) = [] of String) : Int32
            
            # Stream straight to the caller's stdout. Nothing is buffered,
            # so output appears as it is produced and is not lost when the
            # program calls `quit` (which exits the process immediately).
            begin
                Dragonstone.run_file(filename, argv, output: stdout, typed: typed, backend: backend)
                return 0

            # Output streams, a consumer that stops reading 
            # (`dragonstone run something.ds | head`) shows
            # here instead of at the end.
            rescue e : IO::Error
                raise e unless broken_pipe?(e)
                return 0
                
            rescue e : Dragonstone::Error
                stderr.puts "ERROR: #{e.message}"
                return 1
            
            # An unexpected error is a host-level bug, not a Dragonstone
            # one, so the Crystal backtrace is the only thing that locates
            # it. Off by default.
            rescue e
                stderr.puts "UNEXPECTED ERROR: #{e.message}"
                stderr.puts e.backtrace?.try(&.join("\n")) if ENV["DS_TRACE"]?
                return 1
            end
        end

        private def broken_pipe?(error : IO::Error) : Bool
            {% if flag?(:windows) %}
                error.os_error == WinError::ERROR_BROKEN_PIPE || error.os_error == WinError::ERROR_NO_DATA
            {% else %}
                error.os_error == Errno::EPIPE
            {% end %}
        end

        private def parse_backend_flag(value : String, stderr : IO) : BackendMode?
            BackendMode.parse(value)
        rescue
            stderr.puts "Unknown backend '#{value}'. Expected auto, native, or core."
            nil
        end
    end
end
