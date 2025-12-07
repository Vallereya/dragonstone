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

            def to_source : String
                header = "def #{name}"
                unless typed_parameters.empty?
                    params = typed_parameters.map do |param|
                        if type = param.type
                            "#{param.name} : #{type.to_source}"
                        else
                            param.name
                        end
                    end.join(", ")
                    header += "(#{params})"
                end
                if type = return_type
                    header += " : #{type.to_source}"
                end
                if abstract?
                    "#{header}; end"
                else
                    body_source = body.map(&.to_source).join("; ")
                    "#{header}\n  #{body_source}\nend"
                end
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
