module Dragonstone
    module AST
        class IfStatement < Node
            getter condition : Node
            getter then_block : NodeArray
            getter elsif_blocks : Array(ElsifClause)
            getter else_block : NodeArray?

            def initialize(condition : Node, then_block : NodeArray, elsif_blocks : Array(ElsifClause) = [] of ElsifClause, else_block : NodeArray? = nil, location : Location? = nil)
                super(location: location)
                @condition = condition
                @then_block = then_block
                @elsif_blocks = elsif_blocks
                @else_block = else_block
            end

            def accept(visitor)
                visitor.visit_if_statement(self)
            end

            def to_source : String
                String.build do |io|
                    io << "if " << condition.to_source << "\n"
                    emit_block_source(io, then_block)
                    elsif_blocks.each do |clause|
                        io << "elsif " << clause.condition.to_source << "\n"
                        emit_block_source(io, clause.block)
                    end
                    if else_block
                        io << "else\n"
                        emit_block_source(io, else_block.not_nil!)
                    end
                    io << "end"
                end
            end

            private def emit_block_source(io : IO, nodes : Array(Node))
                nodes.each do |node|
                    io << "  " << node.to_source << "\n"
                end
            end
        end
    end
end
