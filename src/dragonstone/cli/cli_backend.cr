module Dragonstone
    module CLIBackend
        extend self

        alias Capability = NamedTuple(feature: String, native: Symbol, core: Symbol, notes: String)

        STATUS_LABELS = {
            full: "yes",
            partial: "partial",
            planned: "planned",
            none: "no"
        }

        CAPABILITIES = [
            {feature: "Typed programs (#! typed / --typed)", native: :full, core: :full, notes: "Type annotations enforced when requested."},
            {feature: "Enumerator block control flow", native: :full, core: :full, notes: "each/map/select/inject/until honor next/redo/break on both backends."},
            {feature: "FFI via ffi.call_* helpers", native: :full, core: :full, notes: "Call into shared C bindings without switching backends."},
            {feature: "Build target: bytecode (vm)", native: :none, core: :full, notes: "Emit Dragonstone VM bytecode artifacts."},
            {feature: "Build target: LLVM IR", native: :none, core: :full, notes: "Generate LLVM IR runnable via lli."},
            {feature: "Build target: C", native: :none, core: :full, notes: "Produce portable C stubs for external toolchains."},
            {feature: "Build target: Crystal", native: :none, core: :full, notes: "Export Crystal-compatible source."},
            {feature: "Build target: Ruby", native: :none, core: :full, notes: "Export Ruby-compatible source."}
        ]

        def handle_command(args : Array(String), stdout : IO, stderr : IO) : Int32
            subcommand = args.shift?
            case subcommand
            when "info"
                print_info(stdout)
                0
            else
                stderr.puts subcommand ? "Unknown backend subcommand: #{subcommand}" : "Missing backend subcommand"
                print_usage(stderr)
                1
            end
        end

        private def print_info(io : IO)
            io.puts "Backend capabilities"
            io.puts "---------------------"
            header = sprintf("%-45s %-8s %-8s %s", "Feature", "Native", "Core", "Notes")
            io.puts header
            io.puts "-" * header.size
            CAPABILITIES.each do |entry|
                io.puts sprintf(
                    "%-45s %-8s %-8s %s",
                    entry[:feature],
                    status_label(entry[:native]),
                    status_label(entry[:core]),
                    entry[:notes]
                )
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
