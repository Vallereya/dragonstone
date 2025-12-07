module Dragonstone
    module AST
        class ElsifClause < Node
            getter condition : Node
            getter block : NodeArray

            def initialize(condition : Node, block : NodeArray, location : Location? = nil)
                super(location: location)
                @condition = condition
                @block = block
            end

            def accept(visitor)
                if visitor.responds_to?(:visit_elsif_clause)
                    visitor.visit_elsif_clause(self)

                else
                    nil

                end
            end

            def to_source : String
                String.build do |io|
                    io << "elsif " << condition.to_source << "\n"
                    block.each do |node|
                        io << "  " << node.to_source << "\n"
                    end
                end
            end
        end
    end
end
