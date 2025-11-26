# ---------------------------------
# ----- Target Shared Helpers -----
# ---------------------------------
require "../../build_options"
require "../../../../shared/ir/program"
require "../../../../shared/language/ast/ast"

module Dragonstone
    module Core
        module Compiler
            module Targets
                module Shared
                    extend self

                    DEFAULT_BUILD_ROOT = File.join("build", "core")

                    def build_output_dir(options : BuildOptions) : String
                        base = options.output_dir
                        dir = if base
                            File.expand_path(base, Dir.current)
                        else
                            File.join(Dir.current, DEFAULT_BUILD_ROOT, options.target.to_s.downcase)
                        end
                        Dir.mkdir_p(dir)
                        dir
                    end

                    def artifact_path(options : BuildOptions, extension : String) : String
                        dir = build_output_dir(options)
                        basename = "dragonstone_#{options.target.to_s.downcase}"
                        File.join(dir, "#{basename}.#{extension}")
                    end

                    def normalized_source(program : ::Dragonstone::IR::Program) : String
                        pieces = [] of String
                        uses = program.ast.use_decls.map(&.to_source)
                        pieces << uses.join("\n") unless uses.empty?

                        statements = program.ast.statements.map(&.to_source)
                        unless statements.empty?
                            pieces << statements.join("\n\n")
                        end

                        text = pieces.join("\n\n")
                        text.rstrip
                    end

                    def node_summary(node : AST::Node) : String
                        type_name = node.class.name.split("::").last
                        snippet = truncate_line(node.to_source)
                        "#{type_name}: #{snippet}"
                    end

                    def c_string_literal(text : String) : String
                        text.inspect
                    end

                    def metadata_literal(text : String) : String
                        escaped = text.gsub("\\", "\\\\").gsub("\"", "\\\"").gsub("\n", "\\0A")
                        "\"#{escaped}\""
                    end

                    private def truncate_line(source : String) : String
                        first_line = source.split('\n', 2).first? || ""
                        trimmed = first_line.strip
                        return trimmed if trimmed.size <= 80
                        "#{trimmed[0, 77]}..."
                    end
                end
            end
        end
    end
end
