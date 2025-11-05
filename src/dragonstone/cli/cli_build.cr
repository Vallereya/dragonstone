require "./proc/common"
require "./proc/file_ops"

module Dragonstone
    module CLIBuild
        extend self

        def build_command(args : Array(String), stdout : IO, stderr : IO) : Int32
            if args.empty?
                return ProcCommon.show_usage(stdout)
            end

            filename = args[0]
            return ProcFileOps.handle_missing_file(filename, stderr) unless File.exists?(filename)
            ProcFileOps.warn_if_unknown_extension(filename, stderr)

            # TODO: Need to hook to compiler when completed.
            stdout.puts "Build not implemented yet for #{filename}"
            return 0
        end
    end
end
