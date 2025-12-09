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

            def to_source(io : IO)
                if recv = @receiver
                    recv.to_source(io)
                    io << "." << @name
                else
                    io << @name
                end

                block_arg = nil
                regular_args = @arguments

                if !@arguments.empty? && @arguments.last.is_a?(BlockLiteral)
                    block_arg = @arguments.last
                    regular_args = @arguments[0...-1]
                end

                unless regular_args.empty?
                    io << "("
                    regular_args.each_with_index do |arg, index|
                        io << ", " if index > 0
                        arg.to_source(io)
                    end
                    io << ")"
                end

                if block = block_arg
                    io << " "
                    block.to_source(io)
                end
            end
        end
    end
end
