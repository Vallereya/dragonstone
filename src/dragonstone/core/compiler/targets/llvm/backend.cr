# ---------------------------------
# -------- LLVM Backend -----------
# ---------------------------------
require "../../build_options"
require "../shared/helpers"
require "../shared/program_serializer"

module Dragonstone
    module Core
        module Compiler
            module Targets
                module LLVM
                    class Backend
                        EXTENSION = "ll"

                        def build(program : ::Dragonstone::IR::Program, options : BuildOptions) : BuildArtifact
                            serializer = Shared::ProgramSerializer.new(program)
                            source_dump = serializer.source
                            metadata = serializer.to_json
                            summary_lines = serializer.summary_lines

                            artifact_path = Shared.artifact_path(options, EXTENSION)
                            File.write(artifact_path, build_content(source_dump, summary_lines, metadata))
                            BuildArtifact.new(target: Target::LLVM, object_path: artifact_path)
                        end

                        private def build_content(source : String, summary_lines : Array(String), metadata : String) : String
                            String.build do |io|
                                io << "; ---------------------------------\n"
                                io << "; Dragonstone LLVM target artifact\n"
                                io << "; ---------------------------------\n"
                                unless source.empty?
                                    io << "; Source snapshot\n"
                                    source.each_line do |line|
                                        io << ";   " << line.rstrip << "\n"
                                    end
                                    io << ";\n"
                                end

                                unless summary_lines.empty?
                                    io << "; Summary\n"
                                    summary_lines.each do |line|
                                        io << ";  - " << line << "\n"
                                    end
                                    io << ";\n"
                                end

                                summary_literal = summary_metadata(summary_lines)
                                io << "!dragonstone.summary = #{summary_literal}\n"
                                io << "!dragonstone.ir = !{#{metadata_entry(metadata)}}\n\n"
                                io << "define void @dragonstone_stub() {\n"
                                io << "entry:\n"
                                io << "  ret void\n"
                                io << "}\n"
                            end
                        end

                        private def summary_metadata(lines : Array(String)) : String
                            return "!{}" if lines.empty?
                            entries = lines.map { |line| metadata_entry(line) }
                            "!{#{entries.join(", ")}}"
                        end

                        private def metadata_entry(text : String) : String
                            "!#{Shared.metadata_literal(text)}"
                        end
                    end
                end
            end
        end
    end
end
