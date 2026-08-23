module Dragonstone
    module AST
        class ExtendStatement < Node
            getter targets : NodeArray

            def initialize(targets : NodeArray, location : Location? = nil)
                super(location: location)
                @targets = targets
            end

            def accept(visitor)
                visitor.visit_extend_statement(self)
            end

            def to_source(io : IO)
                io << "extend "
                targets.each_with_index do |target, index|
                    io << ", " if index > 0
                    target.to_source(io)
                end
            end
        end
    end
end
