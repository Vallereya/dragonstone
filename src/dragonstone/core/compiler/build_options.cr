# ---------------------------------
# ------- Build Options -----------
# ---------------------------------
require "../vm/bytecode"

module Dragonstone
    module Core
        module Compiler
            enum Target
                Bytecode
                LLVM
                C
                Crystal
                Ruby
            end

            struct BuildOptions
                getter target : Target
                getter optimize : Bool
                getter emit_debug : Bool
                getter output_dir : String?

                def initialize(
                    @target : Target = Target::Bytecode,
                    @optimize : Bool = false,
                    @emit_debug : Bool = false,
                    @output_dir : String? = nil
                )
                end
            end

            record BuildArtifact,
                target : Target,
                bytecode : CompiledCode? = nil,
                object_path : String? = nil
        end
    end
end
