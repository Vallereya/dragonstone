module Dragonstone
    module AST
        class Variable < Node
            getter name : String

            def initialize(name : String, location : Location? = nil)
                super(location: location)
                @name = name
            end

            def accept(visitor)
                visitor.visit_variable(self)
            end

            def to_source : String
                name
            end
        end
    end
end
