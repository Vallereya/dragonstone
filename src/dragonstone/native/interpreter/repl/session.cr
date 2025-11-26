module Dragonstone
    class Interpreter
        private def append_output(text : String)
            @output += text
            @output += "\n"
            puts text if @log_to_stdout
        end

        def import_variable(name : String, value : RuntimeValue)
            @global_scope[name] = value
        end

        def import_constant(name : String, value : RuntimeValue)
            @global_scope[name] = ConstantBinding.new(value)
        end

        def export_scope_snapshot : Scope
            snapshot = {} of String => ScopeValue
            @global_scope.each do |name, value|
                snapshot[name] = value.is_a?(ConstantBinding) ? ConstantBinding.new(value.value) : value
            end
            snapshot
        end
    end
end
