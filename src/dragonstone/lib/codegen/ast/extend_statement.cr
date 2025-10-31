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
        end
    end
end
