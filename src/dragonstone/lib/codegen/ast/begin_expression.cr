module Dragonstone
    module AST
        class BeginExpression < Node
            getter body : NodeArray
            getter rescue_clauses : RescueArray
            getter else_block : NodeArray?
            getter ensure_block : NodeArray?

            def initialize(body : NodeArray, rescue_clauses : RescueArray, else_block : NodeArray? = nil, ensure_block : NodeArray? = nil, location : Location? = nil)
                super(location: location)
                @body = body
                @rescue_clauses = rescue_clauses
                @else_block = else_block
                @ensure_block = ensure_block
            end

            def accept(visitor)
                visitor.visit_begin_expression(self)
            end
        end
    end
end
