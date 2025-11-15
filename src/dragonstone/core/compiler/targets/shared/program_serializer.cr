# ---------------------------------
# ---- Program Serializer ---------
# ---------------------------------
require "json"
require "./helpers"

module Dragonstone
    module Core
        module Compiler
            module Targets
                module Shared
                    class ProgramSerializer
                        getter program : ::Dragonstone::IR::Program

                        def initialize(@program : ::Dragonstone::IR::Program)
                        end

                        def source : String
                            Shared.normalized_source(@program)
                        end

                        def summary_lines : Array(String)
                            @program.ast.statements.map { |node| Shared.node_summary(node) }
                        end

                        def to_json : String
                            JSON.build do |json|
                                json.object do
                                    json.field "typed", @program.typed?
                                    json.field "warnings" do
                                        json.array do
                                            @program.warnings.each { |warning| json.string warning }
                                        end
                                    end
                                    json.field "uses" do
                                        json.array do
                                            @program.ast.use_decls.each { |use_decl| json.string use_decl.to_source }
                                        end
                                    end
                                    json.field "summary" do
                                        json.array do
                                            summary_lines.each { |line| json.string line }
                                        end
                                    end
                                    json.field "functions" do
                                        json.array do
                                            functions.each do |func|
                                                json.object do
                                                    json.field "name", func.name
                                                    json.field "visibility", func.visibility.to_s
                                                    json.field "parameters" do
                                                        json.array do
                                                            func.typed_parameters.each do |param|
                                                                json.object do
                                                                    json.field "name", param.name
                                                                    if type = param.type
                                                                        json.field "type", type.to_source
                                                                    end
                                                                    if instance = param.instance_var_name
                                                                        json.field "instance", instance
                                                                    end
                                                                end
                                                            end
                                                        end
                                                    end
                                                    if return_type = func.return_type
                                                        json.field "return_type", return_type.to_source
                                                    end
                                                end
                                            end
                                        end
                                    end
                                end
                            end
                        end

                        private def functions : Array(AST::FunctionDef)
                            funcs = [] of AST::FunctionDef
                            @program.ast.statements.each do |stmt|
                                if func = stmt.as?(AST::FunctionDef)
                                    funcs << func
                                end
                            end
                            funcs
                        end
                    end
                end
            end
        end
    end
end
