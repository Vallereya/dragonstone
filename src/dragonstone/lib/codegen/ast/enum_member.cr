module Dragonstone
    module AST
        class EnumMember < Node
            getter name : String
            getter value : Node?

            def initialize(name : String, value : Node? = nil, location : Location? = nil)
                super(location: location)
                @name = name
                @value = value
            end

            def accept(visitor)
                visitor.visit_enum_member(self)
            end
        end
    end
end
