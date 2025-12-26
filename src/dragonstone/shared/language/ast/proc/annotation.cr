module Dragonstone
    module AST
        struct Annotation
            getter name : String
            getter arguments : Array(Node)
            getter location : Location?

            def initialize(@name : String, @arguments : Array(Node) = [] of Node, @location : Location? = nil)
            end

            enum MemoryOperator
                And  # &&
                Or   # ||
            end

            struct MemoryAnnotation
                property garbage : GarbageMode?
                property ownership : OwnershipMode?
                property operator : MemoryOperator?
                property area_name : String?
                
                def gc_enabled? : Bool
                    case garbage
                    when .enable?, .area? then true
                    else false
                    end
                end
                
                def ownership_enabled? : Bool
                    ownership == OwnershipMode::Enable
                end
                
                def fully_manual? : Bool
                    garbage == GarbageMode::Disable && ownership == OwnershipMode::Disable
                end
                
                def combined_mode? : Bool
                    !garbage.nil? && !ownership.nil?
                end

                enum GarbageMode
                    Enable
                    Disable
                    Area
                end

                enum OwnershipMode
                    Enable
                    Disable
                end
            end
        end
    end
end
