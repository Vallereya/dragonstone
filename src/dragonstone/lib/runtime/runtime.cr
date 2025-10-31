require "../interpreter/interpreter"
require "../resolver/loader"

module Dragonstone
    module Runtime
        class Unit
            getter path : String
            getter interpreter : Interpreter
            getter exports : Scope

            def initialize(@path : String, @interpreter : Interpreter)
                @exports = {} of String => ScopeValue
            end

            def bind(name : String, value : RuntimeValue)
                @interpreter.import_variable(name, value)
            end

            def bind_namespace(namespace : Scope)
                namespace.each do |name, scope_value|
                    bind_scope_value(name, scope_value)
end
end

            def exported_lookup(name : String) : RuntimeValue?
                scope_value = @exports[name]?
                scope_value ? unwrap_scope_value(scope_value) : nil
            end

            def default_namespace : Scope
                @exports
            end

            def capture_exports!
                @exports = @interpreter.export_scope_snapshot
            end

            private def bind_scope_value(name : String, value : ScopeValue)
                if value.is_a?(ConstantBinding)
                    @interpreter.import_constant(name, value.value)
                else
                    @interpreter.import_variable(name, value.as(RuntimeValue))
                end
            end

            private def unwrap_scope_value(value : ScopeValue) : RuntimeValue
                value.is_a?(ConstantBinding) ? value.value : value.as(RuntimeValue)
            end
        end

        class Engine
            getter unit_cache : Hash(String, Unit)

            def initialize(@resolver : ModuleResolver, @log_to_stdout : Bool = false, @typing_enabled : Bool = false)
                @unit_cache = {} of String => Unit
            end

            def compile_or_eval(ast : AST::Program, path : String, typed : Bool? = nil) : Unit
                node = @resolver.graph[path]
                node_typed = node && node.typed
                typing_flag = if !typed.nil?
                    typed
                elsif node_typed
                    true
                else
                    @typing_enabled
                end
                unit = Unit.new(path, Interpreter.new(log_to_stdout: @log_to_stdout, typing_enabled: typing_flag))
                importer = Importer.new(@resolver, self)
                ast.use_decls.each do |use_decl|
                    importer.apply_imports(unit, use_decl, path)
                end
                unit.interpreter.interpret(ast)
                unit.capture_exports!
                unit
            end
        end
    end
end
