module Dragonstone
    module AST
        class InterpolatedString < Node
            getter parts : StringParts

            def initialize(parts : StringParts, location : Location? = nil)
                super(location: location)
                @parts = parts
            end

            def accept(visitor)
                visitor.visit_interpolated_string(self)
            end

            # def to_source : String
            #     result = String.build do |io|
            #         io << '"'
            #         parts.each do |part|
            #             type, content = part

            #             if type == :string
            #                 io << content
            #             else
            #                 io << "\#{#{content}}"
            #             end
            #         end
            #         io << '"'
            #     end
            #     result
            # end

            def to_source(io : IO)
                io << '"'
                parts.each do |part|
                    type, content = part

                    if type == :string
                        io << content
                    else
                        io << "\#{" << content << "}"
                    end
                end
                io << '"'
            end

            def normalized_parts : StringParts
                parts.map do |type, content|
                    type == :string ? {type, content} : {:expression, content}
                end
            end
        end
    end
end
