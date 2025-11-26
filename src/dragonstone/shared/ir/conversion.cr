require "./program"

module Dragonstone
    module IR
        module Conversion
            extend self

            record VMInput,
                ast : AST::Program

            def for_vm(program : Program) : VMInput
                VMInput.new(program.ast)
            end
        end
    end
end
