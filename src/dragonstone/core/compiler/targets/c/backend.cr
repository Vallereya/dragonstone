# ---------------------------------
# ---------- C Backend ------------
# ---------------------------------
require "../../build_options"
require "../shared/helpers"
require "../shared/program_serializer"

module Dragonstone
    module Core
        module Compiler
            module Targets
                module C
                    class Backend
                        EXTENSION = "c"

                        def build(program : ::Dragonstone::IR::Program, options : BuildOptions) : BuildArtifact
                            serializer = Shared::ProgramSerializer.new(program)
                            source_dump = serializer.source
                            summary_lines = serializer.summary_lines
                            metadata = serializer.to_json

                            artifact_path = Shared.artifact_path(options, EXTENSION)
                            File.write(artifact_path, build_content(source_dump, summary_lines, metadata))
                            BuildArtifact.new(target: Target::C, object_path: artifact_path)
                        end

                        private def build_content(source : String, summary_lines : Array(String), metadata : String) : String
                            String.build do |io|
                                io << "/* --------------------------------- */\n"
                                io << "/* Dragonstone C target artifact     */\n"
                                io << "/* --------------------------------- */\n"
                                io << "#include <stdio.h>\n"
                                io << "\n"
                                io << "static const char *DRAGONSTONE_SOURCE = #{Shared.c_string_literal(source)};\n"
                                io << "static const char *DRAGONSTONE_IR = #{Shared.c_string_literal(metadata)};\n"
                                io << "\n"
                                io << "static const char *DRAGONSTONE_SUMMARY[] = {\n"
                                summary_lines.each do |line|
                                    io << "    #{Shared.c_string_literal(line)},\n"
                                end
                                io << "    NULL\n"
                                io << "};\n\n"
                                io << "static void dragonstone_emit_summary(void) {\n"
                                io << "    const char **entry = DRAGONSTONE_SUMMARY;\n"
                                io << "    while (*entry) {\n"
                                io << "        printf(\" - %s\\n\", *entry);\n"
                                io << "        entry++;\n"
                                io << "    }\n"
                                io << "}\n\n"
                                io << "int main(void) {\n"
                                io << "    puts(\"=== Dragonstone program (C target stub) ===\");\n"
                                io << "    puts(DRAGONSTONE_SOURCE);\n"
                                io << "    puts(\"=== IR metadata ===\");\n"
                                io << "    puts(DRAGONSTONE_IR);\n"
                                io << "    puts(\"=== Summary ===\");\n"
                                io << "    dragonstone_emit_summary();\n"
                                io << "    return 0;\n"
                                io << "}\n"
                            end
                        end
                    end
                end
            end
        end
    end
end
