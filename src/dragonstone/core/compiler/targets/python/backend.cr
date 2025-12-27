# ---------------------------------
# -------- Python Backend ---------
# ---------------------------------
require "../../build_options"
require "../shared/helpers"
require "../../../../shared/ir/program"

module Dragonstone
    module Core
        module Compiler
            module Targets
                module Python
                    class Backend
                        EXTENSION = "py"

                        def build(program : ::Dragonstone::IR::Program, options : BuildOptions) : BuildArtifact
                            warn_not_implemented
                            artifact_path = Shared.artifact_path(options, EXTENSION)
                            File.write(artifact_path, stub_content(program))
                            BuildArtifact.new(target: Target::Python, object_path: artifact_path)
                        end

                        private def warn_not_implemented
                            STDERR.puts("[warning] Python target is not implemented yet.")
                        end

                        private def stub_content(program : ::Dragonstone::IR::Program) : String
                            source = Shared.normalized_source(program)
                            String.build do |io|
                                io << "# Dragonstone Python target stub\n"
                                io << "# WARNING: Not implemented yet\n"
                                io << "# Source:\n"
                                source.each_line do |line|
                                    io << "# " << line << "\n"
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end
