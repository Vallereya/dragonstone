module Dragonstone
    class Interpreter
        private record MethodCallFrame,
            owner : DragonModule,
            method : MethodDefinition,
            receiver : RuntimeValue,
            args : Array(RuntimeValue),
            block : Function?

        private def instantiate_class(klass : DragonClass, args : Array(RuntimeValue), node : AST::MethodCall)
            if klass.abstract?
                runtime_error(TypeError, "Cannot instantiate abstract class #{klass.name}", node)
            end

            missing = klass.unimplemented_abstract_methods
            unless missing.empty?
                runtime_error(TypeError, "#{klass.name} must implement abstract methods: #{missing.to_a.sort.join(", ")}", node)
            end

            instance = DragonInstance.new(klass)
            initializer = klass.lookup_method("initialize")
            
            if initializer
                with_container(klass) do
                    call_bound_method(instance, initializer.not_nil!, args, nil, node.location, self_object: instance)
                end
            elsif klass.is_a?(DragonStruct)
                initialize_struct_instance(instance, args, node)
            elsif !args.empty?
                runtime_error(TypeError, "#{klass.name}#initialize expects 0 arguments, got #{args.size}", node)
            end
            instance
        end

        private def initialize_struct_instance(instance : DragonInstance, args : Array(RuntimeValue), node : AST::MethodCall)
            klass = instance.klass
            field_names = klass.ivar_type_annotations.keys

            if field_names.empty?
                unless args.empty?
                    runtime_error(TypeError, "#{klass.name}.new expects 0 arguments, got #{args.size}", node)
                end
                return
            end

            if args.empty?
                runtime_error(TypeError, "#{klass.name}.new expects named arguments for #{field_names.join(", ")}", node)
            end

            unless args.size == 1 && args.first.is_a?(NamedTupleValue)
                runtime_error(TypeError, "#{klass.name}.new expects named arguments", node)
            end

            tuple = args.first.as(NamedTupleValue)
            tuple.entries.each do |symbol, value|
                name = symbol.name
                unless klass.ivar_type_annotations.has_key?(name)
                    runtime_error(NameError, "Unknown attribute '#{name}' for #{klass.name}", node)
                end
                set_instance_variable(instance, name, value, node)
            end

            missing = field_names.reject { |name| instance.ivars.has_key?(name) }
            unless missing.empty?
                runtime_error(TypeError, "#{klass.name}.new missing required attributes: #{missing.join(", ")}", node)
            end
        end

        private def call_function(func : Function, arg_nodes : Array(AST::Node), block_value : Function?, call_location : Location? = nil)
            with_gc_context(func.gc_flags) do
                evaluated_args = arg_nodes.map { |arg| arg.accept(self) }
                final_args = evaluated_args.dup
                expected_params = func.parameters.size

                if block_value
                    if final_args.size == expected_params
                        # Block passed implicitly for yield support.
                    elsif final_args.size + 1 == expected_params
                        final_args << block_value.as(RuntimeValue)
                    else
                        runtime_error(TypeError, "Function #{func.name || "anonymous"} expects #{expected_params} arguments, got #{evaluated_args.size}", call_location)
                    end
                elsif final_args.size != expected_params
                    runtime_error(TypeError, "Function #{func.name || "anonymous"} expects #{expected_params} arguments, got #{evaluated_args.size}", call_location)
                end

                with_block(block_value) do
                    push_scope(func.closure, func.type_closure)
                    push_scope(Scope.new, new_type_scope)
                    scope_index = @scopes.size - 1
                    func.typed_parameters.each_with_index do |param, index|
                        value = final_args[index]
                        descriptor = typing_enabled? && param.type ? descriptor_for(param.type.not_nil!) : nil
                        ensure_type!(descriptor, value, call_location) if descriptor
                        current_scope[param.name] = value
                        assign_type_to_scope(scope_index, param.name, descriptor)
                    end

                    result = nil
                    begin
                        result = execute_block_with_rescue(func.body, func.rescue_clauses)
                    rescue e : ReturnValue
                        result = e.value
                    ensure
                        pop_scope
                        pop_scope
                    end

                    if typing_enabled? && func.return_type
                        descriptor = descriptor_for(func.return_type.not_nil!)
                        ensure_type!(descriptor, result, call_location)
                    end
                    result
                end
            end
        end

        private def call_bound_method(receiver, method_def : MethodDefinition, args : Array(RuntimeValue), block_value : Function?, call_location : Location? = nil, *, self_object : RuntimeValue? = nil)
            with_gc_context(method_def.gc_flags) do
                final_args = args.dup
                expected_params = method_def.parameters.size

                if method_def.abstract?
                    runtime_error(TypeError, "Cannot invoke abstract method #{method_def.name}", call_location)
                end

                receiver_self = (self_object || receiver).as(RuntimeValue)
                @method_call_stack << MethodCallFrame.new(method_def.owner, method_def, receiver_self, args.dup, block_value)

                if block_value
                    if final_args.size == expected_params
                        # yield-only block
                    elsif final_args.size + 1 == expected_params
                        final_args << block_value.as(RuntimeValue)
                    else
                        runtime_error(TypeError, "Method #{method_def.name} expects #{expected_params} arguments, got #{args.size}", call_location)
                    end
                elsif final_args.size != expected_params
                    runtime_error(TypeError, "Method #{method_def.name} expects #{expected_params} arguments, got #{args.size}", call_location)
                end

                with_block(block_value) do
                    push_scope(method_def.closure.dup, method_def.type_closure.dup)
                    current_scope["self"] = receiver_self
                    scope_index = @scopes.size - 1
                    method_def.typed_parameters.each_with_index do |param, index|
                        value = final_args[index]
                        descriptor = typing_enabled? && param.type ? descriptor_for(param.type.not_nil!) : nil
                        ensure_type!(descriptor, value, call_location) if descriptor
                        current_scope[param.name] = value
                        assign_type_to_scope(scope_index, param.name, descriptor)
                        if param.assigns_instance_variable?
                            instance = self_object
                            unless instance && instance.is_a?(DragonInstance)
                                runtime_error(InterpreterError, "Instance variable parameters require an instance context", call_location)
                            end
                            set_instance_variable(instance.as(DragonInstance), param.instance_var_name.not_nil!, value, call_location)
                        end
                    end

                    result = nil
                    begin
                        result = execute_block_with_rescue(method_def.body, method_def.rescue_clauses)
                    rescue e : ReturnValue
                        result = e.value
                    ensure
                        pop_scope
                    end

                    if typing_enabled? && method_def.return_type
                        descriptor = descriptor_for(method_def.return_type.not_nil!)
                        ensure_type!(descriptor, result, call_location)
                    end
                    result
                end
            end
        ensure
            @method_call_stack.pop?
        end

        private def invoke_block(block : Function, args : Array(RuntimeValue), call_location : Location? = nil)
            if args.size != block.parameters.size
                runtime_error(TypeError, "Block expects #{block.parameters.size} arguments, got #{args.size}", call_location)
            end

            with_block(nil) do
                push_scope(block.closure, block.type_closure)
                push_scope(Scope.new, new_type_scope)
                scope_index = @scopes.size - 1
                block.typed_parameters.each_with_index do |param, index|
                    value = args[index]
                    descriptor = typing_enabled? && param.type ? descriptor_for(param.type.not_nil!) : nil
                    ensure_type!(descriptor, value, call_location) if descriptor
                    current_scope[param.name] = value
                    assign_type_to_scope(scope_index, param.name, descriptor)
                end

                result = nil
                begin
                    loop do
                        begin
                            result = execute_block(block.body)
                            break
                        rescue e : RedoSignal
                            next
                        end
                    end
                rescue e : ReturnValue
                    result = e.value
                ensure
                    pop_scope
                    pop_scope
                end
                result
            end
        end

        private def with_gc_context(flags : Runtime::GC::Flags, &block)
            if flags.effective_gc_disabled? && flags.effective_gc_area?
                result = nil
                @gc_manager.with_disabled do
                    @gc_manager.with_area(flags.effective_area_name) do
                        result = yield
                        result = @gc_manager.copy(result) if flags.escape_return
                    end
                end
                result
            elsif flags.effective_gc_disabled?
                yield
            elsif flags.effective_gc_area?
                result = nil
                @gc_manager.with_area(flags.effective_area_name) do
                    result = yield
                    result = @gc_manager.copy(result) if flags.escape_return
                end
                result
            else
                yield
            end
        end

        private def execute_loop_iteration(block : Function, args : Array(RuntimeValue), node : AST::MethodCall) : NamedTuple(state: Symbol, value: RuntimeValue?)
            loop do
                begin
                    value = invoke_block(block, args, node.location)
                    return {state: :yielded, value: value}
                rescue e : NextSignal
                    return {state: :next, value: nil}
                rescue e : RedoSignal
                    next
                end
            end
        end

        private def run_enumeration_loop(&block)
            with_loop_context do
                begin
                    yield
                rescue e : BreakSignal
                end
            end
        end

        private def with_loop_context(&block)
            @loop_depth += 1
            yield
        ensure
            @loop_depth -= 1
        end

        private def reject_block(block_value : Function?, feature : String, node : AST::MethodCall)
            return unless block_value
            runtime_error(InterpreterError, "#{feature} does not accept a block", node)
        end

        private def coerce_range_element(element)
            case element
            when Int32
                element.to_i64
            else
                element
            end
        end

        private def normalize_runtime_value(value, node : AST::Node) : RuntimeValue
            case value
            when Nil, Bool, Int32, Int64, Float32, Float64, String, Char, SymbolValue, Range(Int64, Int64), Range(Char, Char), DragonModule, DragonClass, DragonInstance, DragonEnumMember, Function, FFIModule, RaisedException, TupleValue, NamedTupleValue, BagConstructor, BagValue
                value
            when Array(RuntimeValue)
                value
            when Array
                result = [] of RuntimeValue
                value.each do |element|
                    result << normalize_runtime_value(element, node)
                end
                result
            when MapValue
                value
            when Hash
                map = MapValue.new
                value.each do |key, val|
                    normalized_key = normalize_runtime_value(key, node)
                    normalized_value = normalize_runtime_value(val, node)
                    map[normalized_key] = normalized_value
                end
                map
            else
                runtime_error(InterpreterError, "Unsupported runtime value #{value.class}", node)
            end
        end

    end
end
