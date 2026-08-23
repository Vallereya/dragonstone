module Dragonstone
    module AST
        class FunctionDef < Node
            getter name : String
            getter typed_parameters : Array(TypedParameter)
            getter return_type : TypeExpression?
            getter body : NodeArray
            getter rescue_clauses : RescueArray
            getter visibility : Symbol
            getter receiver : Node?
            getter annotations : Array(Annotation)
            @abstract : Bool

            def initialize(name : String, typed_parameters : Array(TypedParameter), body : NodeArray, rescue_clauses : RescueArray = [] of RescueClause, return_type : TypeExpression? = nil, visibility : Symbol = :public, receiver : Node? = nil, is_abstract : Bool = false, annotations : Array(Annotation) = [] of Annotation, location : Location? = nil)
                super(location: location)
                @name = name
                @typed_parameters = typed_parameters
                @body = body
                @rescue_clauses = rescue_clauses
                @return_type = return_type
                @visibility = visibility
                @receiver = receiver
                @abstract = is_abstract
                @annotations = annotations
            end

            def parameters : Array(String)
                @typed_parameters.map(&.name)
            end

            def accept(visitor)
                visitor.visit_function_def(self)
            end

            def to_source(io : IO)
                io << "abstract " if abstract?
                io << "def " << name
                unless typed_parameters.empty?
                    io << "("
                    typed_parameters.each_with_index do |param, index|
                        io << ", " if index > 0
                        param.to_source(io)
                    end
                    io << ")"
                end
                
                if type = return_type
                    io << " : "
                    type.to_source(io)
                end


                io << "\n"
                body.each do |stmt|
                    io << "  "
                    stmt.to_source(io)
                    io << "\n"
                end
                io << "end"
            end

            def abstract? : Bool
                @abstract
            end

            def abstract : Bool
                @abstract
            end
        end
    end
end
