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

            def to_source : String
                String.build do |io|
                    io << object.to_source
                    io << "["
                    io << index.to_source
                    io << "]"
                    io << "?" if nil_safe
                    
                    if op = operator
                        io << " #{op}= "
                    else
                        io << " = "
                    end
                    
                    io << value.to_source
                end
            end
        end
    end
end
