module Dragonstone
    module AST
        struct Annotation
            getter name : String
            getter arguments : Array(Node)
            getter location : Location?

            def initialize(@name : String, @arguments : Array(Node) = [] of Node, @location : Location? = nil)
            end
        end
    end
end
