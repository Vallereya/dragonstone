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

            def to_source(io : IO)
                io << "begin\n"
                body.each do |stmt|
                    stmt.to_source(io)
                    io << "\n"
                end
                rescue_clauses.each do |clause|
                    clause.to_source(io)
                    io << "\n"
                end
                if e = else_block
                    io << "else\n"
                    e.each do |stmt|
                        stmt.to_source(io)
                        io << "\n"
                    end
                end
                if ens = ensure_block
                    io << "ensure\n"
                    ens.each do |stmt|
                        stmt.to_source(io)
                        io << "\n"
                    end
                end
                io << "end"
            end
        end
    end
end
