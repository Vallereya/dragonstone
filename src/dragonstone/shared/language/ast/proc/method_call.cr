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

                block_arg = arguments.last.is_a?(BlockLiteral) ? arguments.last.as(BlockLiteral) : nil
                regular_args = block_arg ? arguments[0...-1] : arguments

                source = if regular_args.empty?
                    base
                else
                    args = regular_args.map(&.to_source).join(", ")
                    "#{base}(#{args})"
                end

                block_arg ? "#{source} #{block_arg.to_source}" : source
            end
        end
    end
end
