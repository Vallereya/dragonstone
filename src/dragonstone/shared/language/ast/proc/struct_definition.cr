module Dragonstone
    module AST
        class StructDefinition < Node
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
                visitor.visit_struct_definition(self)
            end

            def to_source : String
                String.build do |io|
                    io << "struct " << name << "\n"
                    body.each do |stmt|
                        io << "  " << stmt.to_source << "\n"
                    end
                    io << "end"
                end
            end
        end
    end
end
