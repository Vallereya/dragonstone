module Dragonstone
    module AST
        class CaseStatement < Node
            getter expression : Node?
            getter when_clauses : Array(WhenClause)
            getter else_block : NodeArray?
            getter kind : Symbol

            def initialize(expression : Node?, when_clauses : Array(WhenClause), else_block : NodeArray? = nil, *, kind : Symbol = :case, location : Location? = nil)
                super(location: location)
                @expression = expression
                @when_clauses = when_clauses
                @else_block = else_block
                @kind = kind
            end

            def accept(visitor)
                visitor.visit_case_statement(self)
            end

            def select? : Bool
                @kind == :select
            end
        end
    end
end
