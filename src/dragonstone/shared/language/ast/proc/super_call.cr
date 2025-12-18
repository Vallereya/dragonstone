module Dragonstone
    module AST
        class SuperCall < Node
            getter arguments : NodeArray
            getter? explicit_arguments : Bool

            def initialize(arguments : NodeArray = [] of Node, explicit_arguments : Bool = false, location : Location? = nil)
                super(location: location)
                @arguments = arguments
                @explicit_arguments = explicit_arguments
            end

            def accept(visitor)
                visitor.visit_super_call(self)
            end

            def to_source(io : IO)
                io << "super"

                block_arg = nil
                regular_args = @arguments

                if !@arguments.empty? && @arguments.last.is_a?(BlockLiteral)
                    block_arg = @arguments.last
                    regular_args = @arguments[0...-1]
                end

                if explicit_arguments?
                    io << "("
                    regular_args.each_with_index do |arg, index|
                        io << ", " if index > 0
                        arg.to_source(io)
                    end
                    io << ")"
                elsif !regular_args.empty?
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

