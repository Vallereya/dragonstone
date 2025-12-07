module Dragonstone
    module AST
        class ModuleDefinition < Node
            getter name : String
            getter body : NodeArray
            getter annotations : Array(Annotation)

            def initialize(name : String, body : NodeArray, annotations : Array(Annotation) = [] of Annotation, location : Location? = nil)
                super(location: location)
                @name = name
                @body = body
                @annotations = annotations
            end

            def accept(visitor)
                visitor.visit_module_definition(self)
            end

            def to_source : String
                body_source = body.map(&.to_source).join("; ")
                if body_source.empty?
                    "module #{name}\nend"
                else
                    "module #{name}\n  #{body_source}\nend"
                end
            end
        end
    end
end
