module Dragonstone
    module AST
        class ModuleDefinition < Node
            getter name : String
            getter body : NodeArray
            getter annotations : Array(Annotation)
            getter visibility : Symbol

            def initialize(
                name : String,
                body : NodeArray,
                annotations : Array(Annotation) = [] of Annotation,
                visibility : Symbol = :public,
                location : Location? = nil
            )
                super(location: location)
                @name = name
                @body = body
                @annotations = annotations
                @visibility = visibility
            end

            def accept(visitor)
                visitor.visit_module_definition(self)
            end

            def to_source(io : IO)
                io << visibility << " " unless visibility == :public
                io << "module " << name << "\n"
                body.each do |stmt|
                    io << "  "
                    stmt.to_source(io)
                    io << "\n"
                end
                io << "end"
            end
        end
    end
end
