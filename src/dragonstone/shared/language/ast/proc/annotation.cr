module Dragonstone
    module AST
        struct Annotation
            getter name : String
            getter arguments : Array(Node)
            getter location : Location?
            getter memory : MemoryAnnotation?

            def initialize(
                @name : String,
                @arguments : Array(Node) = [] of Node,
                @location : Location? = nil,
                @memory : MemoryAnnotation? = nil
            )
            end

            def to_source : String
                String.build { |io| to_source(io) }
            end

            def to_source(io : IO)
                io << "@[" << name
                unless arguments.empty?
                    io << "("
                    arguments.each_with_index do |argument, index|
                        io << ", " if index > 0
                        argument.to_source(io)
                    end
                    io << ")"
                end
                io << "]"
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
                property escape_return : Bool = false
                
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
