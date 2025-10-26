module Dragonstone
    module AST
        class CaseStatement < Node
            getter expression : Node?
            getter when_clauses : Array(WhenClause)
            getter else_block : NodeArray?

            def initialize(expression : Node?, when_clauses : Array(WhenClause), else_block : NodeArray? = nil, location : Location? = nil)
                super(location: location)
                @expression = expression
                @when_clauses = when_clauses
                @else_block = else_block
            end

            def accept(visitor)
                visitor.visit_case_statement(self)
            end
        end
    end
end
