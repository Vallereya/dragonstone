module Dragonstone
    module AST
        class IndexAssignment < Node
            getter object : Node
            getter index : Node
            getter value : Node
            getter operator : Symbol?
            getter nil_safe : Bool

            def initialize(object : Node, index : Node, value : Node, operator : Symbol? = nil, nil_safe : Bool = false, location : Location? = nil)
                super(location: location)
                @object = object
                @index = index
                @value = value
                @operator = operator
                @nil_safe = nil_safe
            end

            def accept(visitor)
                visitor.visit_index_assignment(self)
            end

            def to_source(io : IO)
                @object.to_source(io)
                io << "["
                @index.to_source(io)
                io << "]"
                io << "?" if @nil_safe
                
                io << " "
                io << @operator if @operator
                io << "= "
                
                @value.to_source(io)
            end
        end
    end
end
