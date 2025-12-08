module Dragonstone
    module AST
        class WhenClause < Node
            getter conditions : NodeArray
            getter block : NodeArray

            def initialize(conditions : NodeArray, block : NodeArray, location : Location? = nil)
                super(location: location)
                @conditions = conditions
                @block = block
            end

            def accept(visitor)
                if visitor.responds_to?(:visit_when_clause)
                    visitor.visit_when_clause(self)
                else
                    nil
                end
            end

            def to_source(io : IO)
                io << "when "
                @conditions.each_with_index do |cond, index|
                    io << ", " if index > 0
                    cond.to_source(io)
                end
                io << "\n"
                
                @block.each do |node|
                    node.to_source(io)
                    io << "\n"
                end
            end
        end
    end
end