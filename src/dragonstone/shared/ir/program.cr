require "../language/ast/ast"
require "../language/sema/type_checker"

module Dragonstone
    module IR
        # Minimal intermediate representation produced after semantic analysis.
        class Program
            getter ast : AST::Program
            getter analysis : Language::Sema::AnalysisResult

            def initialize(@ast : AST::Program, @analysis : Language::Sema::AnalysisResult)
            end

            def typed? : Bool
                @analysis.typed
            end

            def symbol_table : Language::Sema::SymbolTable
                @analysis.symbol_table
            end

            def warnings : Array(String)
                @analysis.warnings
            end
        end
    end
end
