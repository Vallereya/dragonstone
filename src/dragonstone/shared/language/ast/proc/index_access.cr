module Dragonstone
    module AST
        class IndexAccess < Node
            getter object : Node
            getter index : Node
            getter nil_safe : Bool

            def initialize(object : Node, index : Node, nil_safe : Bool = false, location : Location? = nil)
                super(location: location)
                @object = object
                @index = index
                @nil_safe = nil_safe
            end

            def accept(visitor)
                visitor.visit_index_access(self)
            end

            def to_source : String
                suffix = nil_safe ? "?" : ""
                "#{object.to_source}[#{index.to_source}]#{suffix}"
            end
        end
    end
end
