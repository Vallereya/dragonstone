module Dragonstone
    module CLIBackend
        extend self

        alias Capability = NamedTuple(feature: String, native: Symbol, core: Symbol, notes: String)

        STATUS_LABELS = {full: "yes", partial: "partial", planned: "planned", none: "no"}

        CAPABILITIES = [
            {feature: "Typed Programs (#! typed / --typed)",   native: :full,   core: :full,   notes: "Type annotations are enforced when requested."},
            {feature: "Block Control Flow",                    native: :full,   core: :full,   notes: "Control flows such as each/map/select/inject/until honor next/redo/break on both backends."},
            {feature: "FFI via ffi.call_* Helpers",            native: :full,   core: :full,   notes: "Call into shared C bindings without switching backends."},
            {feature: "Build Target: Bytecode (VM)",           native: :none,   core: :full,   notes: "Emit Dragonstone VM Bytecode artifacts."},
            {feature: "Build Target: LLVM IR",                 native: :none,   core: :full,   notes: "Generate LLVM IR runnable via lli."},
            {feature: "Build Target: C",                       native: :none,   core: :full,   notes: "Produce portable C stubs for external toolchains."},
            {feature: "Build Target: Crystal",                 native: :none,   core: :full,   notes: "Export Crystal-compatible source."},
            {feature: "Build Target: Ruby",                    native: :none,   core: :full,   notes: "Export Ruby-compatible source."}
        ]

        def capability_command?(argv : Array(String)) : Bool
            argv.size == 1 && {"capability", "--capability", "--c"}.includes?(argv[0])
        end

        def capability_command(stdout)
            print_info(stdout)
            return 0
        end

        def handle_command(args : Array(String), stdout : IO, stderr : IO) : Int32
            subcommand = args.shift?
            case subcommand

            when "info"
                print_info(stdout)
                return 0

            else
                stderr.puts subcommand ? "Unknown backend subcommand: #{subcommand}" : "Missing backend subcommand"
                print_usage(stderr)
                return 1

            end
        end

        private def print_info(io : IO)
            io.puts "                           Backend Supported Capabilities                           "
            io.puts "------------------------------------------------------------------------------------"
            header = sprintf("%-45s %-8s %-8s %s", "Feature", "Native", "Core", "Notes")
            io.puts header
            io.puts "-" * header.size

            CAPABILITIES.each do |entry|
                io.puts sprintf("%-45s %-8s %-8s %s", entry[:feature], status_label(entry[:native]), status_label(entry[:core]), entry[:notes])
            end
        end

        private def print_usage(io : IO)
            io.puts "Usage: dragonstone backend info"
        end

        private def status_label(status : Symbol) : String
            STATUS_LABELS[status]? || status.to_s
        end
    end
end
