module Dragonstone
    module AST
        class ClassDefinition < Node
            getter name : String
            getter body : NodeArray
            getter superclass : String?
            getter abstract : Bool

            def initialize(name : String, body : NodeArray, superclass : String? = nil, is_abstract : Bool = false, location : Location? = nil)
                super(location: location)
                @name = name
                @body = body
                @superclass = superclass
                @abstract = is_abstract
            end

            def accept(visitor)
                visitor.visit_class_definition(self)
            end
        end
    end
end
