module Dragonstone
    module ProcFileOps
        extend self

        def handle_missing_file(filename : String, stderr : IO) : Int32
            stderr.puts "ERROR: File '#{filename}' not found"
            return 1
        end

        def warn_if_unknown_extension(filename : String, stderr : IO) : Nil
            return if filename.ends_with?(".ds")
            stderr.puts "WARNING: File '#{filename}' doesn't have any dragonstone extension"
        end

        def read_source(filename : String) : String
            File.read(filename)
        end
    end
end
