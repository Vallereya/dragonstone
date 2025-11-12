module Dragonstone
    module AST
        class ConstantPath < Node
            getter names : Array(String)

            def initialize(names : Array(String), location : Location? = nil)
                super(location: location)
                @names = names
            end

            def accept(visitor)
                visitor.visit_constant_path(self)
            end

            def head : String
                names.first
            end

            def tail : Array(String)
                names[1..] || [] of String
            end
        end
    end
end
