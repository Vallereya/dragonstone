# ---------------------------------
# -------- Frontend Pipeline ------
# ---------------------------------
require "../../../shared/language/lexer/lexer"
require "../../../shared/language/parser/parser"
require "../ir/builder"

module Dragonstone
    module Core
        module Compiler
            module Frontend
                class Pipeline
                    def initialize(@ir_builder : IR::Builder = IR::Builder.new)
                    end

                    def parse(source : String) : AST::Program
                        tokens = Lexer.new(source).tokenize
                        parser = Parser.new(tokens)
                        parser.parse
                    end

                    def build_ir(source : String, typed : Bool = false) : ::Dragonstone::IR::Program
                        ast = parse(source)
                        @ir_builder.build(ast, typed: typed)
                    end

                    def build_ir(ast : AST::Program, typed : Bool = false) : ::Dragonstone::IR::Program
                        @ir_builder.build(ast, typed: typed)
                    end
                end
            end
        end
    end
end
