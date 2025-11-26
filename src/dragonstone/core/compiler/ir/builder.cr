# ---------------------------------
# ---------- IR Builder ----------
# ---------------------------------
require "../../../shared/language/ast/ast"
require "../../../shared/language/sema/type_checker"
require "../../../shared/ir/lowering"

module Dragonstone
    module Core
        module Compiler
            module IR
                class Builder
                    def build(ast : AST::Program, analysis : Language::Sema::AnalysisResult? = nil, typed : Bool = false) : ::Dragonstone::IR::Program
                        resolved_analysis = analysis || analyze(ast, typed)
                        ::Dragonstone::IR::Lowering.lower(ast, resolved_analysis)
                    end

                    private def analyze(ast : AST::Program, typed : Bool) : Language::Sema::AnalysisResult
                        type_checker = Language::Sema::TypeChecker.new
                        type_checker.analyze(ast, typed)
                    end
                end
            end
        end
    end
end
