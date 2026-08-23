module Dragonstone
    module AST
        class ClassDefinition < Node
            getter name : String
            getter body : NodeArray
            getter superclass : String?
            getter annotations : Array(Annotation)
            getter visibility : Symbol
            @abstract : Bool

            def initialize(
                name : String,
                body : NodeArray,
                superclass : String? = nil,
                is_abstract : Bool = false,
                annotations : Array(Annotation) = [] of Annotation,
                visibility : Symbol = :public,
                location : Location? = nil
            )
                super(location: location)
                @name = name
                @body = body
                @superclass = superclass
                @abstract = is_abstract
                @annotations = annotations
                @visibility = visibility
            end

            def accept(visitor)
                visitor.visit_class_definition(self)
            end

            def abstract? : Bool
                @abstract
            end

            def abstract : Bool
                abstract?
            end

            def to_source(io : IO)
                io << visibility << " " unless visibility == :public
                io << "abstract " if abstract?
                io << "class " << name
                io << " < " << superclass if superclass
                io << "\n"
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
