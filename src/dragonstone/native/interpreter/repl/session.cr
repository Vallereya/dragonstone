module Dragonstone
    class Interpreter
        private def debug_inline_pending? : Bool
            @debug_inline_sources.size > 0
        end

        private def flush_debug_inline
            return unless debug_inline_pending?

            source = @debug_inline_sources.join(" + ")
            value = @debug_inline_values.join(" + ")
            @debug_inline_sources.clear
            @debug_inline_values.clear

            @output += "#{source} # -> #{value}"
            @output += "\n"
            puts "#{source} # -> #{value}" if @log_to_stdout
        end

        private def append_output(text : String)
            flush_debug_inline
            @output += text
            @output += "\n"
            puts text if @log_to_stdout
        end

        private def append_output_inline(text : String)
            flush_debug_inline
            @output += text
            print text if @log_to_stdout
        end

        private def append_debug_inline(source : String, value : String)
            @debug_inline_sources << source
            @debug_inline_values << value
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
