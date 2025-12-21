module Dragonstone
    class Interpreter
        def visit_program(node : AST::Program) : RuntimeValue?
            execute_block(node.statements)
        end

        def visit_method_call(node : AST::MethodCall) : RuntimeValue?
            args_info = extract_call_arguments(node)
            block_node = args_info[:block]
            block_value = if block_node
                block_node.accept(self).as(Function)
            else
                nil
            end

            if node.receiver
                receiver_value = node.receiver.not_nil!.accept(self)
                call_receiver_method(receiver_value, node, args_info[:arg_nodes], block_value)
            else
                call_function_name(node, args_info[:arg_nodes], block_value)
            end
        end

        def visit_begin_expression(node : AST::BeginExpression) : RuntimeValue?
            loop do
                begin
                    result = execute_block(node.body)
                    if node.else_block
                        result = execute_block(node.else_block.not_nil!)
                    end
                    return result
                rescue e : InterpreterError
                    handling = handle_rescue_clauses(node.rescue_clauses, e, node)
                    case handling[:action]
                    when :retry
                        next
                    when :handled
                        return handling[:result]
                    else
                        raise e
                    end
                ensure
                    execute_block(node.ensure_block.not_nil!) if node.ensure_block
                end
            end
        end

        def visit_raise_expression(node : AST::RaiseExpression) : RuntimeValue?
            value = node.expression ? node.expression.not_nil!.accept(self) : nil

            if value.nil?
                if @exception_stack.empty?
                    runtime_error(InterpreterError, "No active exception to re-raise", node)
                end
                raise @exception_stack.last
            elsif value.is_a?(RaisedException)
                raise value.error
            elsif value.is_a?(InterpreterError)
                raise value
            elsif value.is_a?(String)
                runtime_error(InterpreterError, value, node)
            else
                runtime_error(InterpreterError, value.to_s, node)
            end
        end

        def visit_debug_echo(node : AST::DebugEcho) : RuntimeValue?
            source = node.to_source
            value = node.expression.accept(self)
            output_text = "#{source} # -> #{format_value(value)}"
            append_output(output_text)
            nil
        end

        def visit_assignment(node : AST::Assignment) : RuntimeValue?
            descriptor = typing_enabled? && node.type_annotation ? descriptor_for(node.type_annotation.not_nil!) : nil
            value = if operator = node.operator
                current = get_variable(node.name, location: node.location)
                evaluate_compound_assignment(current, operator, node.value, node)
            else
                node.value.accept(self)
            end
            set_variable(node.name, value, location: node.location, type_descriptor: descriptor)
            value
        end

        def visit_attribute_assignment(node : AST::AttributeAssignment) : RuntimeValue?
            receiver = node.receiver.accept(self)
            setter_name = "#{node.name}="

            value = if operator = node.operator
                current_call = AST::MethodCall.new(node.name, [] of AST::Node, node.receiver, location: node.location)
                current_value = call_receiver_method(receiver, current_call, [] of AST::Node, nil)
                evaluate_compound_assignment(current_value, operator, node.value, node)

            else
                node.value.accept(self)

            end

            value = normalize_runtime_value(value, node)
            literal = literal_node_for(value, node)
            setter_args = [] of AST::Node
            setter_args << literal
            setter_call = AST::MethodCall.new(setter_name, setter_args, nil, location: node.location)
            call_receiver_method(receiver, setter_call, setter_args, nil)
            value
        end

        def visit_index_assignment(node : AST::IndexAssignment) : RuntimeValue?
            object = node.object.accept(self)
            return nil if node.nil_safe && object.nil?

            index = node.index.accept(self)
            value = if operator = node.operator
                current_value = fetch_index_value(object, index, node)
                evaluate_compound_assignment(current_value, operator, node.value, node)

            else
                node.value.accept(self)

            end

            assign_index_value(object, index, value, node)
            value
        end

        def visit_constant_declaration(node : AST::ConstantDeclaration) : RuntimeValue?
            descriptor = typing_enabled? && node.type_annotation ? descriptor_for(node.type_annotation.not_nil!) : nil
            value = node.value.accept(self)
            ensure_type!(descriptor, value, node) if descriptor
            if current_container && @container_definition_depth.positive?
                define_container_constant(current_container.not_nil!, node.name, value, node)

            else
                set_constant(node.name, value, location: node.location)

            end
            value
        end

        def visit_alias_definition(node : AST::AliasDefinition) : RuntimeValue?
            register_type_alias(node.name, node.type_expression, node)
            nil
        end

        def visit_variable(node : AST::Variable) : RuntimeValue?
            if binding_info = find_binding_with_scope(node.name)
                return unwrap_binding(binding_info[:value])
            end

            constant_info = lookup_container_constant(node.name)
            return constant_info[:value] if constant_info[:found]

            if self_value = current_scope["self"]?
                method_call = AST::MethodCall.new(node.name, [] of AST::Node, nil, location: node.location)
                return call_receiver_method(self_value, method_call, [] of AST::Node, nil, implicit_self: true)
            end

            runtime_error(NameError, "Undefined variable or constant: #{node.name}", node)
        end

        def visit_argv_expression(_node : AST::ArgvExpression) : RuntimeValue?
            argv_value
        end

        def visit_constant_path(node : AST::ConstantPath) : RuntimeValue?
            base = lookup_constant_value(node.head)
            unless base
                runtime_error(NameError, "Undefined constant #{node.head}", node)
            end

            value = base
            node.tail.each do |segment|
                unless value.is_a?(DragonModule)
                    runtime_error(NameError, "Constant #{segment} not found in #{describe_runtime_value(value)}", node)
                end

                container = value.as(DragonModule)
                unless container.constant?(segment)
                    runtime_error(NameError, "Constant #{segment} not found in #{container.name}", node)
                end

                value = container.fetch_constant(segment)
            end
            value
        end

        def visit_instance_variable(node : AST::InstanceVariable) : RuntimeValue?
            instance = current_self_instance(node)
            instance.ivars[node.name]? || nil
        end

        def visit_instance_variable_assignment(node : AST::InstanceVariableAssignment) : RuntimeValue?
            instance = current_self_instance(node)

            value = if operator = node.operator
                current_value = instance.ivars[node.name]? || nil
                evaluate_compound_assignment(current_value, operator, node.value, node)
            else
                node.value.accept(self)
            end

            set_instance_variable(instance, node.name, value, node)
            value
        end

        def visit_instance_variable_declaration(node : AST::InstanceVariableDeclaration) : RuntimeValue?
            container = current_container
            unless container.is_a?(DragonClass)
                runtime_error(InterpreterError, "Instance variable declarations are only allowed inside classes", node)
            end
            container.as(DragonClass).register_ivar_type(node.name, node.type_annotation)
            nil
        end

        def visit_accessor_macro(node : AST::AccessorMacro) : RuntimeValue?
            container = current_container
            unless container.is_a?(DragonClass)
                runtime_error(InterpreterError, "#{node.kind} is only allowed inside classes", node)
            end

            klass = container.as(DragonClass)
            node.entries.each do |entry|
                klass.register_ivar_type(entry.name, entry.type_annotation)
                define_accessor_methods(klass, node, entry)
            end
            nil
        end

        def visit_literal(node : AST::Literal) : RuntimeValue?
            case value = node.value

            when Int32
                value.to_i64

            else
                value

            end
        end

        def visit_array_literal(node : AST::ArrayLiteral) : RuntimeValue?
            node.elements.map { |element| element.accept(self).as(RuntimeValue) }
        end

        def visit_tuple_literal(node : AST::TupleLiteral) : RuntimeValue?
            elements = node.elements.map { |element| element.accept(self).as(RuntimeValue) }
            TupleValue.new(elements)
        end

        def visit_named_tuple_literal(node : AST::NamedTupleLiteral) : RuntimeValue?
            entries = {} of SymbolValue => RuntimeValue
            node.entries.each do |entry|
                value = entry.value.accept(self).as(RuntimeValue)
                if type_annotation = entry.type_annotation
                    descriptor = typing_enabled? ? descriptor_for(type_annotation) : nil
                    ensure_type!(descriptor, value, entry.value) if descriptor
                end
                entries[SymbolValue.new(entry.name)] = value
            end
            NamedTupleValue.new(entries)
        end

        def visit_map_literal(node : AST::MapLiteral) : RuntimeValue?
            map = MapValue.new
            node.entries.each do |key_node, value_node|
                key = key_node.accept(self).as(RuntimeValue)
                value = value_node.accept(self).as(RuntimeValue)
                map[key] = value
            end
            map
        end

        def visit_index_access(node : AST::IndexAccess) : RuntimeValue?
            object = node.object.accept(self)
            return nil if node.nil_safe && object.nil?

            index = node.index.accept(self)
            fetch_index_value(object, index, node)
        end

        def visit_block_literal(node : AST::BlockLiteral) : RuntimeValue?
            Function.new(nil, node.typed_parameters, node.body, current_scope, current_type_scope)
        end

        def visit_interpolated_string(node : AST::InterpolatedString) : RuntimeValue?
            result = String.build do |io|
                node.parts.each do |part|
                    type, content = part
                    if type == :string
                        io << content
                    else
                        value = evaluate_interpolation(content)
                        io << display_value(value)
                    end
                end
            end
            result
        end

        def visit_binary_op(node : AST::BinaryOp) : RuntimeValue?
            operator = node.operator
            if operator == :"&&"
                left = node.left.accept(self)
                return left unless truthy?(left)
                return node.right.accept(self)
            elsif operator == :"||"
                left = node.left.accept(self)
                return left if truthy?(left)
                return node.right.accept(self)
            end

            left = node.left.accept(self)
            right = node.right.accept(self)
            apply_binary_operator(left, operator, right, node)
        end

        def visit_unary_op(node : AST::UnaryOp) : RuntimeValue?
            operand = node.operand.accept(self)
            apply_unary_operator(node.operator, operand, node)
        end

        def visit_conditional_expression(node : AST::ConditionalExpression) : RuntimeValue?
            if truthy?(node.condition.accept(self))
                node.then_branch.accept(self)

            else
                node.else_branch.accept(self)

            end
        end

        def visit_if_statement(node : AST::IfStatement) : RuntimeValue?
            if truthy?(node.condition.accept(self))
                execute_block(node.then_block)
            else
                node.elsif_blocks.each do |elsif_clause|
                    if truthy?(elsif_clause.condition.accept(self))
                        return execute_block(elsif_clause.block)
                    end
                end
                execute_block(node.else_block || [] of AST::Node)
            end
        end

        def visit_unless_statement(node : AST::UnlessStatement) : RuntimeValue?
            if truthy?(node.condition.accept(self))
                execute_block(node.else_block || [] of AST::Node)
            else
                execute_block(node.body)
            end
        end

        def visit_case_statement(node : AST::CaseStatement) : RuntimeValue?
            return execute_select_statement(node) if node.select?

            target = node.expression.try &.accept(self)
            node.when_clauses.each do |clause|
                clause.conditions.each do |condition|
                    value = condition.accept(self)
                    match = if node.expression
                            case_match?(value, target, node)
                        else
                            truthy?(value)
                        end
                    return execute_block(clause.block) if match
                end
            end
            execute_block(node.else_block || [] of AST::Node)
        end

        private def execute_select_statement(node : AST::CaseStatement) : RuntimeValue?
            node.when_clauses.each do |clause|
                clause.conditions.each do |condition|
                    result = condition.accept(self)
                    if truthy?(result)
                        return execute_block(clause.block)
                    end
                end
            end
            execute_block(node.else_block || [] of AST::Node)
        end

        private def case_match?(condition_value, target, node : AST::Node) : Bool
            if target.nil?
                return condition_value.nil?
            end

            case condition_value
            when RangeValue
                range_contains?(condition_value, target, node)
            when DragonClass
                if target.is_a?(DragonInstance)
                    within_hierarchy?(target.as(DragonInstance).klass, condition_value)
                else
                    false
                end
            when DragonEnum
                target.is_a?(DragonEnumMember) && target.as(DragonEnumMember).enum == condition_value
            when DragonEnumMember
                target == condition_value
            when DragonModule
                target == condition_value
            else
                condition_value == target
            end
        end

        private def range_contains?(range : RangeValue, value, node : AST::Node) : Bool
            case range
            when Range(Int64, Int64)
                if value.is_a?(Int64)
                    range.includes?(value)
                elsif value.is_a?(Int32)
                    range.includes?(value.to_i64)
                else
                    false
                end
            when Range(Char, Char)
                value.is_a?(Char) && range.includes?(value)
            else
                runtime_error(TypeError, "Unsupported range type #{range.class}", node)
            end
        end

        private def triple_equals(left, right, node : AST::Node) : Bool
            case left
            when RangeValue
                range_contains?(left, right, node)
            when DragonClass
                if right.is_a?(DragonInstance)
                    within_hierarchy?(right.as(DragonInstance).klass, left)
                else
                    false
                end
            when DragonEnum
                right.is_a?(DragonEnumMember) && right.as(DragonEnumMember).enum == left
            when DragonModule
                left == right
            else
                left == right
            end
        end

        private def resolve_extend_target(container : DragonModule, expr : AST::Node)
            if expr.is_a?(AST::Variable) && expr.name == "self"
                container
            else
                expr.accept(self)
            end
        end

        private def extend_container_with(container : DragonModule, value, node : AST::Node)
            extension = case value
            when DragonModule
                value
            when DragonClass
                value
            else
                runtime_error(TypeError, "Cannot extend #{container.name} with #{describe_runtime_value(value)}", node)
            end

            return if extension == container

            extension.each_method do |name, method|
                container.define_method(name, method.dup_with_owner(container))
            end
        end

        def visit_while_statement(node : AST::WhileStatement) : RuntimeValue?
            result = nil
            @loop_depth += 1
            while truthy?(node.condition.accept(self))
                begin
                    loop do
                        begin
                            result = execute_block(node.block)
                            break
                        rescue e : RedoSignal
                            next
                        end
                    end
                rescue e : NextSignal
                    next
                rescue e : BreakSignal
                    break
                end
            end
            result
        ensure
            @loop_depth -= 1
        end

        def visit_function_def(node : AST::FunctionDef) : RuntimeValue?
            closure = current_scope.dup
            type_closure = current_type_scope.dup

            container = current_container
            if node.abstract && !container
                runtime_error(InterpreterError, "'abstract def' is only allowed inside classes or modules", node)
            end
            if node.typed_parameters.any?(&.assigns_instance_variable?) && (!container.is_a?(DragonClass) || node.receiver)
                runtime_error(InterpreterError, "Instance variable parameters are only allowed inside classes", node)
            end

            if receiver_node = node.receiver
                if node.abstract
                    runtime_error(InterpreterError, "Singleton methods cannot be abstract", node)
                end
                target = receiver_node.accept(self)
                define_singleton_method(target, node, closure, type_closure)
                return nil
            end

            gc_flags = Runtime::GC.flags_from_annotations(node.annotations)

            if container
                if container.is_a?(DragonClass)
                    klass = container.as(DragonClass)
                    node.typed_parameters.each do |param|
                        next unless param.assigns_instance_variable?
                        klass.register_ivar_type(param.instance_var_name.not_nil!, param.type)
                    end
                end

                method = MethodDefinition.new(
                    node.name,
                    node.typed_parameters,
                    node.body,
                    closure,
                    type_closure,
                    container,
                    node.rescue_clauses,
                    node.return_type,
                    visibility: node.visibility,
                    is_abstract: node.abstract,
                    gc_flags: gc_flags
                )
                container.define_method(node.name, method)
                nil
            else
                func = Function.new(node.name, node.typed_parameters, node.body, closure, type_closure, node.rescue_clauses, node.return_type, gc_flags: gc_flags)
                set_variable(node.name, func, location: node.location)
                nil
            end
        end

        def visit_function_literal(node : AST::FunctionLiteral) : RuntimeValue?
            Function.new(nil, node.typed_parameters, node.body, current_scope, current_type_scope, node.rescue_clauses, node.return_type)
        end

        private def define_singleton_method(target, node : AST::FunctionDef, closure : Scope, type_closure : TypeScope)
            owner = singleton_class_for_value(target, node)
            method = MethodDefinition.new(
                node.name,
                node.typed_parameters,
                node.body,
                closure,
                type_closure,
                owner,
                node.rescue_clauses,
                node.return_type,
                visibility: node.visibility,
                is_abstract: node.abstract
            )
            owner.define_method(node.name, method)
        end

        def visit_para_literal(node : AST::ParaLiteral) : RuntimeValue?
            Function.new(nil, node.typed_parameters, node.body, current_scope, current_type_scope, node.rescue_clauses, node.return_type)
        end

        def visit_with_expression(node : AST::WithExpression) : RuntimeValue?
            receiver = node.receiver.accept(self)
            scope = current_scope
            type_scope = current_type_scope
            had_self = scope.has_key?("self")
            previous_self = scope["self"]?
            had_type_self = type_scope.has_key?("self")
            previous_type_descriptor : Typing::Descriptor? = had_type_self ? type_scope["self"]? : nil
            scope["self"] = receiver.as(RuntimeValue)
            assign_type_to_scope(@scopes.size - 1, "self", nil)
            result = execute_block(node.body)
            if had_self
                scope["self"] = previous_self
                assign_type_to_scope(@scopes.size - 1, "self", previous_type_descriptor)
            else
                scope.delete("self")
                assign_type_to_scope(@scopes.size - 1, "self", nil)
            end
            result
        end

        def visit_yield_expression(node : AST::YieldExpression) : RuntimeValue?
            block = current_block
            runtime_error(InterpreterError, "No block given", node) unless block
            args = node.arguments.map { |argument| argument.accept(self).as(RuntimeValue) }
            invoke_block(block.not_nil!, args, node.location)
        end

        def visit_super_call(node : AST::SuperCall) : RuntimeValue?
            frame = @method_call_stack.last?
            runtime_error(InterpreterError, "'super' used outside of a method", node) unless frame

            owner = frame.not_nil!.owner
            unless owner.is_a?(DragonClass)
                runtime_error(InterpreterError, "'super' is only supported inside classes", node)
            end

            args = [] of RuntimeValue
            block_value : Function? = nil

            arg_nodes = [] of AST::Node
            block_node = nil
            node.arguments.each do |argument|
                if argument.is_a?(AST::BlockLiteral)
                    block_node = argument.as(AST::BlockLiteral)
                else
                    arg_nodes << argument
                end
            end

            if block_node
                block_value = block_node.not_nil!.accept(self).as(Function)
            else
                block_value = frame.not_nil!.block
            end

            if node.explicit_arguments?
                args = evaluate_arguments(arg_nodes)
            else
                args = frame.not_nil!.args.dup
            end

            receiver_self = frame.not_nil!.receiver
            receiver_class = receiver_self.is_a?(DragonInstance) ? receiver_self.as(DragonInstance).klass : receiver_self.as?(DragonClass)
            runtime_error(InterpreterError, "'super' requires a class receiver", node) unless receiver_class

            super_class = owner.as(DragonClass).superclass
            runtime_error(NameError, "No superclass available for #{owner.as(DragonClass).name}", node) unless super_class

            method_name = frame.not_nil!.method.name
            super_method = super_class.not_nil!.lookup_method(method_name)
            runtime_error(NameError, "Undefined method '#{method_name}' for superclass of #{owner.as(DragonClass).name}", node) unless super_method

            super_owner = super_method.not_nil!.owner
            unless super_owner.is_a?(DragonClass)
                runtime_error(InterpreterError, "Superclass method '#{method_name}' must belong to a class", node)
            end

            with_container(super_owner) do
                call_bound_method(super_owner, super_method.not_nil!, args, block_value, node.location, self_object: receiver_self)
            end
        end

        def visit_bag_constructor(node : AST::BagConstructor) : RuntimeValue?
            descriptor = descriptor_for(node.element_type)
            BagConstructor.new(descriptor, node.element_type)
        end

        def visit_return_statement(node : AST::ReturnStatement) : RuntimeValue?
            value = node.value ? node.value.not_nil!.accept(self) : nil
            raise ReturnValue.new(value)
        end

        def visit_module_definition(node : AST::ModuleDefinition) : RuntimeValue?
            container = @container_definition_depth.positive? ? current_container : nil

            existing = if container
                if container.constant?(node.name)
                    container.fetch_constant(node.name)
                else
                    nil
                end
            else
                lookup_constant_value(node.name)
            end

            mod = if existing
                unless existing.is_a?(DragonModule)
                    message = if container
                        "Constant #{node.name} already defined in #{container.name}"
                    else
                        "Constant #{node.name} already defined"
                    end
                    runtime_error(ConstantError, message, node)
                end
                existing.as(DragonModule)
            else
                new_module = DragonModule.new(node.name)
                if container
                    define_container_constant(container, node.name, new_module, node)
                else
                    set_constant(node.name, new_module, location: node.location)
                end
                new_module
            end

            with_container(mod) do
                @container_definition_depth += 1
                push_scope(Scope.new, new_type_scope)
                current_scope["self"] = mod

                begin
                    execute_block(node.body)
                ensure
                    pop_scope
                    @container_definition_depth -= 1
                end
            end
            mod
        end

        def visit_class_definition(node : AST::ClassDefinition) : RuntimeValue?
            container = @container_definition_depth.positive? ? current_container : nil

            existing = if container
                if container.constant?(node.name)
                    container.fetch_constant(node.name)
                else
                    nil
                end
            else
                lookup_constant_value(node.name)
            end

            klass = if existing
                unless existing.is_a?(DragonClass)
                    message = if container
                        "Constant #{node.name} already defined in #{container.name}"
                    else
                        "Constant #{node.name} already defined"
                    end
                    runtime_error(ConstantError, message, node)
                end
                existing.as(DragonClass)
            else
                superclass = nil
                if node.superclass
                    superclass_value = lookup_constant_value(node.superclass.not_nil!)
                    unless superclass_value.is_a?(DragonClass)
                        runtime_error(TypeError, "Superclass #{node.superclass} must be a class", node)
                    end
                    superclass = superclass_value.as(DragonClass)
                end
                new_class = DragonClass.new(node.name, superclass, node.abstract)
                if container
                    define_container_constant(container, node.name, new_class, node)
                else
                    set_constant(node.name, new_class, location: node.location)
                end
                new_class
            end

            klass.mark_abstract! if node.abstract && !klass.abstract?

            with_container(klass) do
                @container_definition_depth += 1
                push_scope(Scope.new, new_type_scope)
                current_scope["self"] = klass
                begin
                    execute_block(node.body)
                ensure
                    pop_scope
                    @container_definition_depth -= 1
                end
            end

            unless klass.abstract?
                missing = klass.unimplemented_abstract_methods
                unless missing.empty?
                    runtime_error(TypeError, "#{klass.name} must implement abstract methods: #{missing.to_a.sort.join(", ")}", node)
                end
            end
            klass
        end

        def visit_struct_definition(node : AST::StructDefinition) : RuntimeValue?
            container = @container_definition_depth.positive? ? current_container : nil

            existing = if container
                if container.constant?(node.name)
                    container.fetch_constant(node.name)
                else
                    nil
                end
            else
                lookup_constant_value(node.name)
            end

            struct_type = if existing
                unless existing.is_a?(DragonStruct)
                    message = if container
                        "Constant #{node.name} already defined in #{container.name}"
                    else
                        "Constant #{node.name} already defined"
                    end
                    runtime_error(ConstantError, message, node)
                end
                existing.as(DragonStruct)
            else
                new_struct = DragonStruct.new(node.name)
                if container
                    define_container_constant(container, node.name, new_struct, node)
                else
                    set_constant(node.name, new_struct, location: node.location)
                end
                new_struct
            end

            with_container(struct_type) do
                @container_definition_depth += 1
                push_scope(Scope.new, new_type_scope)
                current_scope["self"] = struct_type
                begin
                    execute_block(node.body)
                ensure
                    pop_scope
                    @container_definition_depth -= 1
                end
            end

            struct_type
        end

        def visit_enum_definition(node : AST::EnumDefinition) : RuntimeValue?
            container = @container_definition_depth.positive? ? current_container : nil

            if container
                if container.constant?(node.name)
                    runtime_error(ConstantError, "Constant #{node.name} already defined in #{container.name}", node)
                end
            elsif lookup_constant_value(node.name)
                runtime_error(ConstantError, "Constant #{node.name} already defined", node)
            end

            accessor_name = node.value_name
            accessor_name = accessor_name && !accessor_name.empty? ? accessor_name : nil
            accessor_name ||= "value"

            enum_type = DragonEnum.new(node.name, accessor_name, node.value_type)
            if container
                define_container_constant(container, node.name, enum_type, node)
            else
                set_constant(node.name, enum_type, location: node.location)
            end

            last_value = -1_i64
            node.members.each do |member_node|
                value = if member_node.value
                    runtime_value = member_node.value.not_nil!.accept(self)
                    to_int64(runtime_value, member_node)
                else
                    last_value + 1
                end

                last_value = value

                if enum_type.member(member_node.name)
                    runtime_error(ConstantError, "Enum member #{member_node.name} already defined for #{enum_type.name}", member_node)
                end

                if enum_type.member_for_value(value)
                    runtime_error(ConstantError, "Enum value #{value} already used in #{enum_type.name}", member_node)
                end

                enum_type.define_member(member_node.name, value)
            end

            enum_type
        end

        def visit_enum_member(node : AST::EnumMember) : RuntimeValue?
            runtime_error(InterpreterError, "Enum members cannot be evaluated directly", node)
        end

        def visit_extend_statement(node : AST::ExtendStatement) : RuntimeValue?
            container = current_container
            unless container
                runtime_error(InterpreterError, "'extend' can only be used inside modules or classes", node)
            end

            node.targets.each do |target_expr|
                target = resolve_extend_target(container.not_nil!, target_expr)
                extend_container_with(container.not_nil!, target, node)
            end

            nil
        end

        def visit_break_statement(node : AST::BreakStatement) : RuntimeValue?
            if @loop_depth.zero?
                runtime_error(InterpreterError, "'break' used outside of a loop", node)
            end
            return nil unless flow_modifier_allows?(node)
            raise BreakSignal.new
        end

        def visit_next_statement(node : AST::NextStatement) : RuntimeValue?
            if @loop_depth.zero?
                runtime_error(InterpreterError, "'next' used outside of a loop", node)
            end
            return nil unless flow_modifier_allows?(node)
            raise NextSignal.new
        end

        def visit_redo_statement(node : AST::RedoStatement) : RuntimeValue?
            if @loop_depth.zero?
                runtime_error(InterpreterError, "'redo' used outside of a loop", node)
            end
            return nil unless flow_modifier_allows?(node)
            raise RedoSignal.new
        end

        def visit_retry_statement(node : AST::RetryStatement) : RuntimeValue?
            if @rescue_depth.zero?
                runtime_error(InterpreterError, "'retry' used outside of a rescue clause", node)
            end
            return nil unless flow_modifier_allows?(node)
            raise RetrySignal.new
        end

        private def extract_call_arguments(node : AST::MethodCall) : NamedTuple(arg_nodes: Array(AST::Node), block: AST::BlockLiteral?)
            arg_nodes = [] of AST::Node
            block_node = nil
            node.arguments.each do |argument|
                if argument.is_a?(AST::BlockLiteral)
                    block_node = argument.as(AST::BlockLiteral)
                else
                    arg_nodes << argument
                end
            end
            {arg_nodes: arg_nodes, block: block_node}
        end

        private def evaluate_arguments(nodes : Array(AST::Node)) : Array(RuntimeValue)
            nodes.map { |node| node.accept(self).as(RuntimeValue) }
        end

        private def flow_modifier_allows?(node)
            condition = node.try(&.condition)
            return true unless condition
            value = condition.not_nil!.accept(self)
            truthy = truthy?(value)
            node.try(&.condition_type) == :unless ? !truthy : truthy
        end

        private def execute_block(statements : Array(AST::Node))
            result = nil
            statements.each { |stmt| result = stmt.accept(self) }
            result
        end

        private def handle_rescue_clauses(rescue_clauses : Array(AST::RescueClause), error : InterpreterError, _node : AST::Node?) : NamedTuple(action: Symbol, result: RuntimeValue?)
            return {action: :unhandled, result: nil} if rescue_clauses.empty?
            clause = match_rescue_clause(error, rescue_clauses)
            return {action: :unhandled, result: nil} unless clause

            @exception_stack << error
            begin
                clause_execution = run_rescue_clause(clause, error)
            ensure
                @exception_stack.pop
            end

            clause_execution[:retry] ? {action: :retry, result: nil} : {action: :handled, result: clause_execution[:result]}
        end

        private def run_rescue_clause(clause : AST::RescueClause, error : InterpreterError) : NamedTuple(result: RuntimeValue?, retry: Bool)
            push_scope(Scope.new, new_type_scope)
            @rescue_depth += 1
            if var = clause.exception_variable
                current_scope[var] = RaisedException.new(error)
            end

            result = nil
            begin
                clause.body.each { |stmt| result = stmt.accept(self) }
                {result: result, retry: false}
            rescue e : RetrySignal
                {result: nil, retry: true}
            rescue e : ReturnValue
                raise e
            rescue e : BreakSignal
                raise e
            rescue e : NextSignal
                raise e
            rescue e : RedoSignal
                raise e
            ensure
                @rescue_depth -= 1
                pop_scope
            end
        end

        private def execute_block_with_rescue(statements : Array(AST::Node), rescue_clauses : Array(AST::RescueClause))
            loop do
                begin
                    result = nil
                    statements.each { |stmt| result = stmt.accept(self) }
                    return result

                rescue e : ReturnValue
                    raise e

                rescue e : BreakSignal
                    raise e

                rescue e : NextSignal
                    raise e

                rescue e : RedoSignal
                    raise e

                rescue e : InterpreterError
                    handling = handle_rescue_clauses(rescue_clauses, e, nil)
                    case handling[:action]
                    when :retry
                        next
                    when :handled
                        return handling[:result]
                    else
                        raise e
                    end
                end
            end
        end

        private def match_rescue_clause(error : InterpreterError, rescue_clauses : Array(AST::RescueClause))
            return nil if rescue_clauses.empty?
            full_name = error.class.name
            simple_name = full_name.split("::").last
            rescue_clauses.find do |clause|
                clause.exceptions.empty? || clause.exceptions.any? { |name| name == simple_name || name == full_name }
            end
        end

        private def truthy?(value) : Bool
            !(value.nil? || value == false)
        end

    end
end
