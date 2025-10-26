module Dragonstone
    module AST
        class MethodCall < Node
            getter receiver : Node?
            getter name : String
            getter arguments : NodeArray

            def initialize(name : String, arguments : NodeArray, receiver : Node? = nil, location : Location? = nil)
                super(location: location)
                @receiver = receiver
                @name = name
                @arguments = arguments
            end

            def accept(visitor)
                visitor.visit_method_call(self)
            end

            def to_source : String
                base = if receiver
                    "#{receiver.not_nil!.to_source}.#{name}"

                else
                    name
                    
                end

                return base if arguments.empty?

                args = arguments.map(&.to_source).join(", ")
                "#{base}(#{args})"
            end
        end
    end
end
