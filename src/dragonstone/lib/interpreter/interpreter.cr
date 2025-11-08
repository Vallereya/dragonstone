# ---------------------------------
# ---------- Interpreter ----------
# ---------------------------------
require "../resolver/errors"
require "../lexer/*"
require "../parser/*"
require "../codegen/*"
require "../typing/*"
require "../runtime/ffi_module"
require "../runtime/symbol"

module Dragonstone
    class RaisedException
        getter error : InterpreterError

        def initialize(@error : InterpreterError)
        end

        def message : String
            @error.original_message
        end

        def to_s : String
            class_name = error.class.name.split("::").last
            "#{class_name}: #{message}"
        end
    end

    alias RangeValue = Range(Int64, Int64) | Range(Char, Char)
    alias RuntimeValue = Nil | Bool | Int32 | Int64 | Float64 | String | Char | SymbolValue | Array(RuntimeValue) | Hash(RuntimeValue, RuntimeValue) | TupleValue | NamedTupleValue | DragonModule | DragonClass | DragonInstance | Function | RangeValue | FFIModule | DragonEnumMember | RaisedException | BagConstructor | BagValue
    alias MapValue = Hash(RuntimeValue, RuntimeValue)
    alias ScopeValue = RuntimeValue | ConstantBinding
    alias Scope = Hash(String, ScopeValue)
    alias TypeScope = Hash(String, Typing::Descriptor)

    class TupleValue
        getter elements : Array(RuntimeValue)

        def initialize(elements : Array(RuntimeValue))
            @elements = elements
        end
    end

    class NamedTupleValue
        getter entries : Hash(SymbolValue, RuntimeValue)

        def initialize(entries : Hash(SymbolValue, RuntimeValue))
            @entries = entries
        end
    end

    class BagConstructor
        getter element_descriptor : Typing::Descriptor
        getter element_type : AST::TypeExpression

        def initialize(@element_descriptor : Typing::Descriptor, @element_type : AST::TypeExpression)
        end

        def to_s : String
            "bag(#{element_descriptor.to_s})"
        end
    end

    class BagValue
        getter element_descriptor : Typing::Descriptor?
        getter elements : Array(RuntimeValue)

        def initialize(@element_descriptor : Typing::Descriptor?)
            @elements = [] of RuntimeValue
        end

        def size : Int64
            @elements.size.to_i64
        end

        def includes?(value : RuntimeValue) : Bool
            @elements.any? { |existing| existing == value }
        end

        def add(value : RuntimeValue)
            unless includes?(value)
                @elements << value
            end
            self
        end
    end

        class ReturnValue < Exception
        getter value : RuntimeValue?

        def initialize(@value : RuntimeValue?)
            super()
        end
    end

    class BreakSignal < Exception; end
    
    class NextSignal < Exception; end

    class RedoSignal < Exception; end

    class RetrySignal < Exception; end

    class ConstantBinding
        getter value : RuntimeValue

        def initialize(@value : RuntimeValue)
        end
    end

    class Function
        getter name : String?
        getter typed_parameters : Array(AST::TypedParameter)
        getter body : Array(AST::Node)
        getter closure : Scope
        getter type_closure : TypeScope
        getter rescue_clauses : Array(AST::RescueClause)
        getter return_type : AST::TypeExpression?
        @parameter_names : Array(String)

        def initialize(@name : String?, typed_parameters : Array(AST::TypedParameter), @body : Array(AST::Node), @closure : Scope, @type_closure : TypeScope, @rescue_clauses : Array(AST::RescueClause) = [] of AST::RescueClause, @return_type : AST::TypeExpression? = nil)
            @typed_parameters = typed_parameters
            @parameter_names = typed_parameters.map(&.name)
        end

        def parameters : Array(String)
            @parameter_names
        end

    end

    class MethodDefinition
        getter name : String
        getter typed_parameters : Array(AST::TypedParameter)
        getter body : Array(AST::Node)
        getter closure : Scope
        getter type_closure : TypeScope
        getter rescue_clauses : Array(AST::RescueClause)
        getter return_type : AST::TypeExpression?
        getter visibility : Symbol
        getter owner : DragonModule
        @parameter_names : Array(String)

        def initialize(@name : String, typed_parameters : Array(AST::TypedParameter), @body : Array(AST::Node), @closure : Scope, @type_closure : TypeScope, @owner : DragonModule, @rescue_clauses : Array(AST::RescueClause) = [] of AST::RescueClause, @return_type : AST::TypeExpression? = nil, visibility : Symbol = :public)
            @typed_parameters = typed_parameters
            @parameter_names = typed_parameters.map(&.name)
            @visibility = visibility
        end

        def parameters : Array(String)
            @parameter_names
        end

        def dup_with_owner(new_owner : DragonModule) : MethodDefinition
            MethodDefinition.new(
                @name,
                @typed_parameters.dup,
                @body.dup,
                @closure.dup,
                @type_closure.dup,
                new_owner,
                @rescue_clauses.dup,
                @return_type,
                visibility: @visibility
            )
        end
    end

    class DragonModule
        getter name : String

        def initialize(@name : String)
            @methods = {} of String => MethodDefinition
            @constants = {} of String => RuntimeValue
        end

        def define_method(name : String, method : MethodDefinition)
            @methods[name] = method
        end

        def lookup_method(name : String) : MethodDefinition?
            @methods[name]?
        end

        def each_method
            @methods.each do |name, method|
                yield name, method
            end
        end

        def constant?(name : String) : Bool
            @constants.has_key?(name)
        end

        def define_constant(name : String, value : RuntimeValue)
            @constants[name] = value
        end

        def fetch_constant(name : String) : RuntimeValue
            @constants[name]
        end
    end

    class DragonClass < DragonModule
        getter superclass : DragonClass?
        getter ivar_type_annotations : Hash(String, AST::TypeExpression?)

        def initialize(name : String, @superclass : DragonClass? = nil)
            super(name)
            if @superclass
                parent = @superclass.not_nil!
                @ivar_type_annotations = parent.ivar_type_annotations.dup
                @ivar_type_descriptors = parent.ivar_type_descriptors.dup
            else
                @ivar_type_annotations = {} of String => AST::TypeExpression?
                @ivar_type_descriptors = {} of String => Typing::Descriptor?
            end
        end

        def lookup_method(name : String) : MethodDefinition?
            super || @superclass.try &.lookup_method(name)
        end

        def register_ivar_type(name : String, type : AST::TypeExpression?)
            if type
                @ivar_type_annotations[name] = type
            else
                @ivar_type_annotations[name] = nil unless @ivar_type_annotations.has_key?(name)
            end
            @ivar_type_descriptors.delete(name)
        end

        def ivar_type_annotation(name : String) : AST::TypeExpression?
            @ivar_type_annotations[name]?
        end

        def ivar_type_descriptor(name : String) : Typing::Descriptor?
            @ivar_type_descriptors[name]?
        end

        def cache_ivar_descriptor(name : String, descriptor : Typing::Descriptor)
            @ivar_type_descriptors[name] = descriptor
        end

        getter ivar_type_descriptors : Hash(String, Typing::Descriptor?)
    end

    class DragonStruct < DragonClass
        def initialize(name : String)
            super(name)
        end
    end

    class DragonEnum < DragonModule
        getter value_method_name : String
        getter value_type_annotation : AST::TypeExpression?

        def initialize(name : String, value_method_name : String = "value", value_type_annotation : AST::TypeExpression? = nil)
            super(name)
            @value_method_name = value_method_name.empty? ? "value" : value_method_name
            @value_type_annotation = value_type_annotation
            @members = [] of DragonEnumMember
            @members_by_name = {} of String => DragonEnumMember
            @members_by_value = {} of Int64 => DragonEnumMember
        end

        def member(name : String) : DragonEnumMember?
            @members_by_name[name]?
        end

        def member_for_value(value : Int64) : DragonEnumMember?
            @members_by_value[value]?
        end

        def define_member(name : String, value : Int64) : DragonEnumMember
            member = DragonEnumMember.new(self, name, value)
            @members << member
            @members_by_name[name] = member
            @members_by_value[value] = member
            define_constant(name, member)
            member
        end

        def members : Array(DragonEnumMember)
            @members.dup
        end
    end

    class DragonEnumMember
        getter enum : DragonEnum
        getter name : String
        getter value : Int64

        def initialize(@enum : DragonEnum, @name : String, @value : Int64)
        end

        def to_s : String
            @name
        end
    end

    class DragonInstance
        getter klass : DragonClass
        getter ivars : Hash(String, RuntimeValue)

        def initialize(@klass : DragonClass)
            @ivars = {} of String => RuntimeValue
        end
    end

    class Interpreter
        getter output : String
        @type_scopes : Array(TypeScope)
        @typing_context : Typing::Context?
        @descriptor_cache : Typing::DescriptorCache

        def initialize(log_to_stdout : Bool = false, typing_enabled : Bool = false)
            @global_scope = Scope.new
            @scopes = [@global_scope]
            @type_scopes = [new_type_scope]
            @typing_enabled = typing_enabled
            @descriptor_cache = Typing::DescriptorCache.new
            @typing_context = nil
            @output = String.new
            @log_to_stdout = log_to_stdout
            @container_stack = [] of DragonModule
            @loop_depth = 0
            @rescue_depth = 0
            @exception_stack = [] of InterpreterError
            @container_definition_depth = 0
            @type_aliases = {} of String => AST::TypeExpression
            @alias_descriptor_cache = {} of String => Typing::Descriptor
            @block_stack = [] of Function?
            set_variable("ffi", FFIModule.new)
        end

        def typing_enabled? : Bool
            @typing_enabled
        end

        def interpret(ast : AST::Program) : String
            ast.accept(self)
            @output
        end

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

        def visit_debug_print(node : AST::DebugPrint) : RuntimeValue?
            source = node.to_source
            value = node.expression.accept(self)
            output_text = "#{source} # => #{format_value(value)}"
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
                if method_defined_for_implicit_self?(self_value, node.name)
                    method_call = AST::MethodCall.new(node.name, [] of AST::Node, nil, location: node.location)
                    return call_receiver_method(self_value, method_call, [] of AST::Node, nil, implicit_self: true)
                end
            end

            runtime_error(NameError, "Undefined variable or constant: #{node.name}", node)
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
                key = key_node.accept(self)
                value = value_node.accept(self)
                map[key.as(RuntimeValue)] = value.as(RuntimeValue)
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
            Function.new(nil, node.typed_parameters, node.body, current_scope.dup, current_type_scope.dup)
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
            if node.typed_parameters.any?(&.assigns_instance_variable?) && !container.is_a?(DragonClass)
                runtime_error(InterpreterError, "Instance variable parameters are only allowed inside classes", node)
            end

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
                    visibility: node.visibility
                )
                container.define_method(node.name, method)
                nil
            else
                func = Function.new(node.name, node.typed_parameters, node.body, closure, type_closure, node.rescue_clauses, node.return_type)
                set_variable(node.name, func, location: node.location)
                nil
            end
        end

        def visit_function_literal(node : AST::FunctionLiteral) : RuntimeValue?
            Function.new(nil, node.typed_parameters, node.body, current_scope.dup, current_type_scope.dup, node.rescue_clauses, node.return_type)
        end

        def visit_para_literal(node : AST::ParaLiteral) : RuntimeValue?
            Function.new(nil, node.typed_parameters, node.body, current_scope.dup, current_type_scope.dup, node.rescue_clauses, node.return_type)
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
                new_class = DragonClass.new(node.name, superclass)
                if container
                    define_container_constant(container, node.name, new_class, node)
                else
                    set_constant(node.name, new_class, location: node.location)
                end
                new_class
            end

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

        private def evaluate_compound_assignment(current, operator : Symbol, value_node : AST::Node, node : AST::Node)
            case operator

            when :"||"
                return current if truthy?(current)
                value_node.accept(self)

            when :"&&"
                return current unless truthy?(current)
                value_node.accept(self)

            else
                rhs = value_node.accept(self)
                apply_binary_operator(current, operator, rhs, node)
                
            end
        end

        private def fetch_index_value(object, index, node : AST::Node)
            case object

            when TupleValue
                idx = index_to_int(index, node)
                object.elements[idx]? || nil

            when NamedTupleValue
                key = coerce_named_tuple_key(index, node)
                object.entries[key]?

            when Array(RuntimeValue)
                idx = index_to_int(index, node)
                object[idx]? || nil

            when MapValue
                key = index.as(RuntimeValue)
                object[key]?

            when String
                idx = index_to_int(index, node)
                object[idx]? || nil
            else
                runtime_error(TypeError, "Cannot index #{object.class}", node)
            end
        end

        private def assign_index_value(object, index, value, node : AST::Node)
            case object

            when TupleValue
                runtime_error(TypeError, "Cannot assign index on Tuple", node)

            when NamedTupleValue
                runtime_error(TypeError, "Cannot assign index on NamedTuple", node)

            when Array(RuntimeValue)
                idx = index_to_int(index, node)
                object[idx] = value

            when MapValue
                key = index.as(RuntimeValue)
                object[key] = value.as(RuntimeValue)
            else
                runtime_error(TypeError, "Cannot assign index on #{object.class}", node)
            end
        end

        private def index_to_int(index, node : AST::Node) : Int32
            case index

            when Int64
                index.to_i32

            when Int32
                index

            when Float64
                index.to_i32

            else
                runtime_error(TypeError, "Index must be a number", node)

            end
        end

        private def coerce_named_tuple_key(index, node : AST::Node) : SymbolValue
            case index
            when SymbolValue
                index
            when String
                SymbolValue.new(index)
            else
                runtime_error(TypeError, "NamedTuple index must be a Symbol or String", node)
            end
        end

        private def to_int64(value, node : AST::Node) : Int64
            case value
            when Int64
                value
            when Int32
                value.to_i64
            when Float64
                value.to_i64
            else
                runtime_error(TypeError, "Enum values must be numeric", node)
            end
        end

        private def apply_binary_operator(left, operator : Symbol, right, node : AST::Node)
            case operator

            when :+, :"&+"
                add_values(left, right, node)

            when :-, :"&-"
                subtract_values(left, right, node)

            when :*, :"&*"
                multiply_values(left, right, node)

            when :/
                divide_values(left, right, node)

            when :"//"
                perform_floor_division(left, right, node)

            when :%
                modulo_values(left, right, node)

            when :"**", :"&**"
                power_values(left, right, node)

            when :&, :|, :^, :<<, :>>
                bitwise_values(left, operator, right, node)

            when :===
                triple_equals(left, right, node)

            when :==
                left == right

            when :!=
                left != right

            when :<, :<=, :>, :>=, :<=>
                compare_values(left, operator, right, node)

            when :=~, :!~
                match_values(left, operator, right, node)

            when :"..", :"..."
                create_range(left, right, operator == :"...", node)

            else
                runtime_error(InterpreterError, "Unknown operator: #{operator}", node)

            end
        end

        private def add_values(left, right, node : AST::Node)
            case left

            when Int64, Float64
                lnum, rnum = numeric_pair(left, right, node)
                numeric_add(lnum, rnum)

            when String
                left + (right.nil? ? "" : right.to_s)

            when Array(RuntimeValue)
                unless right.is_a?(Array(RuntimeValue))
                    runtime_error(TypeError, "Cannot add #{right.class} to Array", node)

                end

                (left + right.as(Array(RuntimeValue))).map { |v| v }

            else
                runtime_error(TypeError, "Unsupported operands for +", node)

            end
        end

        private def subtract_values(left, right, node : AST::Node)
            lnum, rnum = numeric_pair(left, right, node)
            numeric_subtract(lnum, rnum)
        end

        private def multiply_values(left, right, node : AST::Node)
            lnum, rnum = numeric_pair(left, right, node)
            numeric_multiply(lnum, rnum)
        end

        private def divide_values(left, right, node : AST::Node)
            lnum, rnum = numeric_pair(left, right, node)

            if rnum == 0 || rnum == 0.0
                runtime_error(InterpreterError, "divided by 0", node)
            end

            numeric_divide(lnum, rnum)
        end

        private def modulo_values(left, right, node : AST::Node)
            lnum, rnum = numeric_pair(left, right, node)

            if rnum == 0 || rnum == 0.0
                runtime_error(InterpreterError, "divided by 0", node)
            end

            if lnum.is_a?(Float64) || rnum.is_a?(Float64)
                lnum.to_f64 % rnum.to_f64
            else
                lnum.to_i64 % rnum.to_i64
            end
        end

        private def power_values(left, right, node : AST::Node)
            lnum, rnum = numeric_pair(left, right, node)
            lnum.to_f64 ** rnum.to_f64
        end

        private def bitwise_values(left, operator : Symbol, right, node : AST::Node)
            lint = to_int(left, node)
            rint = to_int(right, node)

            case operator

            when :&
                lint & rint

            when :|
                lint | rint

            when :^
                lint ^ rint

            when :<<
                lint << rint

            when :>>
                lint >> rint

            else
                runtime_error(InterpreterError, "Unknown bitwise operator #{operator}", node)

            end
        end

        private def compare_values(left, operator : Symbol, right, node : AST::Node)
            case left
                
            when Int64, Float64
                lnum, rnum = numeric_pair(left, right, node)
                compare_numbers(lnum, rnum, operator)

            when String
                unless right.is_a?(String)
                    runtime_error(TypeError, "Cannot compare #{left.class} with #{right.class}", node)

                end
                compare_strings(left, right.as(String), operator)

            else
                runtime_error(TypeError, "Unsupported comparison between #{left.class} and #{right.class}", node)

            end
        end

        private def match_values(left, operator : Symbol, right, node : AST::Node)
            unless right.is_a?(String)
                runtime_error(TypeError, "Right operand for =~ must be a String", node)

            end

            pattern = right.as(String)
            string = left.to_s
            matched = string.includes?(pattern)
            operator == :=~ ? matched : !matched
        end

        private def create_range(left, right, exclusive : Bool, node : AST::Node)
            if left.is_a?(Int64) && right.is_a?(Int64)
                Range.new(left, right, exclusive)

            elsif left.is_a?(Char) && right.is_a?(Char)
                Range.new(left, right, exclusive)

            else
                runtime_error(TypeError, "Unsupported range bounds #{left.class} and #{right.class}", node)

            end
        end

        private def numeric_pair(left, right, node : AST::Node) : Tuple(Float64 | Int64, Float64 | Int64)
            {coerce_number(left, node), coerce_number(right, node)}
        end

        private def numeric_add(left : Float64 | Int64, right : Float64 | Int64)
            if left.is_a?(Float64) || right.is_a?(Float64)
                left.to_f64 + right.to_f64

            else
                left.to_i64 + right.to_i64

            end
        end

        private def numeric_subtract(left : Float64 | Int64, right : Float64 | Int64)
            if left.is_a?(Float64) || right.is_a?(Float64)
                left.to_f64 - right.to_f64
            else
                left.to_i64 - right.to_i64
            end
        end

        private def numeric_multiply(left : Float64 | Int64, right : Float64 | Int64)
            if left.is_a?(Float64) || right.is_a?(Float64)
                left.to_f64 * right.to_f64
            else
                left.to_i64 * right.to_i64
            end
        end

        private def numeric_divide(left : Float64 | Int64, right : Float64 | Int64)
            if left.is_a?(Float64) || right.is_a?(Float64)
                left.to_f64 / right.to_f64
            else
                left.to_i64 / right.to_i64
            end
        end

        private def coerce_number(value, node : AST::Node) : Float64 | Int64
            case value

            when Int64
                value

            when Int32
                value.to_i64

            when Float64
                value

            when Float32
                value.to_f64

            else
                runtime_error(TypeError, "Expected numeric value, got #{value.class}", node)

            end
        end

        private def to_int(value, node : AST::Node) : Int64
            case value

            when Int64
                value

            when Int32
                value.to_i64

            else
                runtime_error(TypeError, "Expected integer value", node)

            end
        end

        private def compare_numbers(left : Float64 | Int64, right : Float64 | Int64, operator : Symbol)
            l = left.is_a?(Float64) ? left : left.to_f64
            r = right.is_a?(Float64) ? right : right.to_f64

            case operator

            when :<
                l < r

            when :<=
                l <= r

            when :>
                l > r

            when :>=
                l >= r

            when :<=>
                (l < r ? -1_i64 : (l > r ? 1_i64 : 0_i64))

            else
                raise "Unsupported comparison"

            end
        end

        private def compare_strings(left : String, right : String, operator : Symbol)
            case operator

            when :<
                left < right

            when :<=
                left <= right

            when :>
                left > right

            when :>=
                left >= right

            when :<=>
                left <=> right

            else
                runtime_error(InterpreterError, "Unsupported string comparison #{operator}", nil)

            end
        end

        private def apply_unary_operator(operator : Symbol, operand, node : AST::Node)
            case operator

            when :+, :"&+"
                coerce_number(operand, node)

            when :-, :"&-"
                value = coerce_number(operand, node)
                value.is_a?(Float64) ? -value : -value.to_i64

            when :!
                !truthy?(operand)

            when :~
                ~to_int(operand, node)

            else
                runtime_error(InterpreterError, "Unknown unary operator: #{operator}", node)

            end
        end

        private def perform_floor_division(left, right, node : AST::Node)
            lnum, rnum = numeric_pair(left, right, node)

            if rnum == 0 || rnum == 0.0
                runtime_error(InterpreterError, "divided by 0", node)

            end

            if lnum.is_a?(Float64) || rnum.is_a?(Float64)
                (lnum.to_f64 / rnum.to_f64).floor

            else
                lnum.to_i64 // rnum.to_i64

            end
        end

        private def call_function_name(node : AST::MethodCall, arg_nodes : Array(AST::Node), block_value : Function?)
            case node.name

            when "echo", "puts"
                if block_value
                    runtime_error(InterpreterError, "echo does not accept a block", node)
                end
                values = arg_nodes.map { |arg| arg.accept(self) }
                append_output(values.map { |v| display_value(v) }.join(" "))
                nil

            when "typeof"
                if block_value
                    runtime_error(InterpreterError, "typeof does not accept a block", node)
                end
                if arg_nodes.size != 1
                    runtime_error(TypeError, "typeof expects exactly 1 argument, got #{arg_nodes.size}", node)

                end
                value = arg_nodes[0].accept(self)
                get_type_name(value)

            else
                binding = find_binding(node.name)
                if binding
                    value = unwrap_binding(binding)
                    if value.is_a?(Function)
                        call_function(value.as(Function), arg_nodes, block_value, node.location)
                    elsif arg_nodes.empty? && block_value.nil?
                        value
                    else
                        runtime_error(NameError, "Unknown method or variable: #{node.name}", node)
                    end
                else
                    if self_value = current_scope["self"]?
                        call_receiver_method(self_value, node, arg_nodes, block_value, implicit_self: true)
                    else
                        runtime_error(NameError, "Unknown method or variable: #{node.name}", node)
                    end
                end

            end
        end

        private def call_receiver_method(receiver, node : AST::MethodCall, arg_nodes : Array(AST::Node), block_value : Function?, implicit_self : Bool = false)
            args = evaluate_arguments(arg_nodes)
            conversion_call = conversion_method?(node.name)

            if node.name == "nil?"
                if block_value
                    runtime_error(InterpreterError, "nil? does not accept a block", node)
                end
                unless args.empty?
                    runtime_error(InterpreterError, "nil? does not take arguments", node)
                end
                return receiver.nil?
            end

            if conversion_call && !supports_custom_methods?(receiver)
                ensure_conversion_call_valid(args, block_value, node)
                return conversion_result_for(receiver, node.name)
            end

            case receiver

            when TupleValue
                call_tuple_method(receiver, node.name, args, block_value, node)

            when NamedTupleValue
                call_named_tuple_method(receiver, node.name, args, block_value, node)

            when Array(RuntimeValue)
                call_array_method(receiver, node.name, args, block_value, node)

            when MapValue
                call_map_method(receiver, node.name, args, block_value, node)

            when BagConstructor
                call_bag_constructor_method(receiver, node.name, args, block_value, node)

            when BagValue
                call_bag_method(receiver, node.name, args, block_value, node)

            when String
                call_string_method(receiver, node.name, args, block_value, node)

            when RangeValue
                call_range_method(receiver, node.name, args, block_value, node)

            when RaisedException
                call_exception_method(receiver, node.name, args, block_value, node)

            when FFIModule
                if block_value
                    runtime_error(InterpreterError, "ffi methods do not accept blocks", node)
                end
                call_ffi_dispatch(node.name, args, node)

            when DragonEnum
                case node.name
                when "new"
                    if block_value
                        runtime_error(InterpreterError, "#{receiver.name}.new does not accept a block", node)
                    end
                    unless args.size == 1
                        runtime_error(InterpreterError, "#{receiver.name}.new expects 1 argument, got #{args.size}", node)
                    end
                    value = to_int64(args.first, node)
                    member = receiver.member_for_value(value)
                    runtime_error(NameError, "No enum member with value #{value} for #{receiver.name}", node) unless member
                    member

                when "each", "members"
                    unless args.empty?
                        runtime_error(InterpreterError, "#{receiver.name}.#{node.name} does not take arguments", node)
                    end
                    if block_value
                        block = block_value.not_nil!
                        run_enumeration_loop do
                            receiver.members.each do |member|
                                outcome = execute_loop_iteration(block, [member.as(RuntimeValue)], node)
                                next if outcome[:state] == :next
                            end
                        end
                        receiver
                    else
                        receiver.members.map { |member| member.as(RuntimeValue) }
                    end

                when "values"
                    if block_value
                        runtime_error(InterpreterError, "#{receiver.name}.values does not accept a block", node)
                    end
                    unless args.empty?
                        runtime_error(InterpreterError, "#{receiver.name}.values does not take arguments", node)
                    end
                    receiver.members.map { |member| member.value.as(RuntimeValue) }

                else
                    method = receiver.lookup_method(node.name)
                    unless method
                        if conversion_call
                            ensure_conversion_call_valid(args, block_value, node)
                            return conversion_result_for(receiver, node.name)
                        end
                        runtime_error(NameError, "Unknown method '#{node.name}' for enum #{receiver.name}", node)
                    end
                    method = method.not_nil!
                    ensure_method_visible!(receiver, method, node, implicit_self)
                    with_container(receiver) do
                        call_bound_method(receiver, method, args, block_value, node.location)
                    end
                end

            when DragonClass
                if node.name == "new"
                    if block_value
                        runtime_error(InterpreterError, "#{receiver.name}.new does not accept a block", node)
                    end
                    instantiate_class(receiver, args, node)

                else
                    method = receiver.lookup_method(node.name)
                    unless method
                        if conversion_call
                            ensure_conversion_call_valid(args, block_value, node)
                            return conversion_result_for(receiver, node.name)
                        end
                        runtime_error(NameError, "Unknown method '#{node.name}' for class #{receiver.name}", node)
                    end
                    method = method.not_nil!
                    ensure_method_visible!(receiver, method, node, implicit_self)
                    with_container(receiver) do
                        call_bound_method(receiver, method, args, block_value, node.location)
                    end
                end

            when DragonModule
                method = receiver.lookup_method(node.name)
                unless method
                    if conversion_call
                        ensure_conversion_call_valid(args, block_value, node)
                        return conversion_result_for(receiver, node.name)
                    end
                    runtime_error(NameError, "Unknown method '#{node.name}' for module #{receiver.name}", node)
                end
                method = method.not_nil!
                ensure_method_visible!(receiver, method, node, implicit_self)
                with_container(receiver) do
                    call_bound_method(receiver, method, args, block_value, node.location)
                end

            when DragonInstance
                method = receiver.klass.lookup_method(node.name)
                unless method
                    if conversion_call
                        ensure_conversion_call_valid(args, block_value, node)
                        return conversion_result_for(receiver, node.name)
                    end
                    runtime_error(NameError, "Undefined method '#{node.name}' for instance of #{receiver.klass.name}", node)
                end
                method = method.not_nil!
                ensure_method_visible!(receiver, method, node, implicit_self)
                with_container(receiver.klass) do
                    call_bound_method(receiver.klass, method, args, block_value, node.location, self_object: receiver)
                end

            when DragonEnumMember
                if block_value
                    runtime_error(InterpreterError, "Enum member methods do not accept blocks", node)
                end
                unless args.empty?
                    runtime_error(InterpreterError, "Enum member methods do not take arguments", node)
                end

                if node.name == "name"
                    receiver.name
                elsif node.name == "enum"
                    receiver.enum
                elsif node.name == "value" || node.name == receiver.enum.value_method_name
                    receiver.value
                else
                    runtime_error(NameError, "Unknown method '#{node.name}' for enum member #{receiver}", node)
                end

            when Function
                if node.name == "call"
                    if block_value
                        runtime_error(InterpreterError, "Function#call does not accept a block", node)
                    end
                    invoke_block(receiver, args, node.location)
                else
                    runtime_error(InterpreterError, "Unknown method '#{node.name}' for Function", node)
                end
            else
                runtime_error(TypeError, "Cannot call method '#{node.name}' on #{receiver.class}", node)

            end
        end

        private def conversion_method?(name : String) : Bool
            name == "display" || name == "inspect"
        end

        private def supports_custom_methods?(receiver) : Bool
            receiver.is_a?(DragonModule) || receiver.is_a?(DragonInstance)
        end

        private def ensure_conversion_call_valid(args : Array(RuntimeValue), block_value : Function?, node : AST::MethodCall)
            reject_block(block_value, node.name, node)
            unless args.empty?
                runtime_error(InterpreterError, "#{node.name} does not take arguments", node)
            end
        end

        private def conversion_result_for(value, method_name : String) : String
            case method_name
            when "display"
                display_value(value)
            when "inspect"
                format_value(value)
            else
                runtime_error(InterpreterError, "Unsupported conversion '#{method_name}'", nil)
            end
        end

        private def call_ffi_dispatch(method : String, args : Array(RuntimeValue), node : AST::MethodCall) : RuntimeValue
            case method

            when "call_ruby"
                ffi_call_ruby(args, node)

            when "call_crystal"
                ffi_call_crystal(args, node)

            when "call_c"
                ffi_call_c(args, node)

            else
                runtime_error(NameError, "Unknown FFI method: #{method}", node)

            end
        end

        private def ffi_call_ruby(args : Array(RuntimeValue), node : AST::MethodCall) : RuntimeValue
            unless args.size >= 2
                runtime_error(InterpreterError, "ffi.call_ruby requires at least 2 arguments: method_name, [args]", node)
            end

            method_name = args[0]
            method_args = args[1]

            unless method_name.is_a?(String)
                runtime_error(TypeError, "First argument to ffi.call_ruby must be a string", node)
            end

            unless method_args.is_a?(Array(RuntimeValue))
                runtime_error(TypeError, "Second argument to ffi.call_ruby must be an array", node)
            end

            ruby_args = method_args.as(Array(RuntimeValue)).map { |arg| Dragonstone::FFI.normalize(arg) }
            result = Dragonstone::FFI.call_ruby(method_name, ruby_args)
            from_ffi_value(result)
        end

        private def ffi_call_crystal(args : Array(RuntimeValue), node : AST::MethodCall) : RuntimeValue
            unless args.size >= 2
                runtime_error(InterpreterError, "ffi.call_crystal requires at least 2 arguments: func_name, [args]", node)
            end

            func_name = args[0]
            func_args = args[1]

            unless func_name.is_a?(String)
                runtime_error(TypeError, "First argument to ffi.call_crystal must be a string", node)
            end

            unless func_args.is_a?(Array(RuntimeValue))
                runtime_error(TypeError, "Second argument to ffi.call_crystal must be an array", node)
            end

            crystal_args = func_args.as(Array(RuntimeValue)).map { |arg| Dragonstone::FFI.normalize(arg) }
            result = Dragonstone::FFI.call_crystal(func_name, crystal_args)
            from_ffi_value(result)
        end

        private def ffi_call_c(args : Array(RuntimeValue), node : AST::MethodCall) : RuntimeValue
            unless args.size >= 2
                runtime_error(InterpreterError, "ffi.call_c requires at least 2 arguments: func_name, [args]", node)
            end

            func_name = args[0]
            func_args = args[1]

            unless func_name.is_a?(String)
                runtime_error(TypeError, "First argument to ffi.call_c must be a string", node)
            end

            unless func_args.is_a?(Array(RuntimeValue))
                runtime_error(TypeError, "Second argument to ffi.call_c must be an array", node)
            end

            c_args = func_args.as(Array(RuntimeValue)).map { |arg| Dragonstone::FFI.normalize(arg) }
            result = Dragonstone::FFI.call_c(func_name, c_args)
            from_ffi_value(result)
        end

        private def from_ffi_value(value : Dragonstone::FFI::InteropValue) : RuntimeValue
            case value

            when Nil, Bool, Int32, Int64, Float64, String, Char
                value

            when Array
                converted = [] of RuntimeValue
                value.each { |element| converted << from_ffi_value(element) }
                converted

            else
                nil

            end
        end

        private def ffi_call_crystal(args : Array(RuntimeValue), node : AST::MethodCall) : RuntimeValue
            unless args.size >= 2
                runtime_error(InterpreterError, "ffi.call_crystal requires at least 2 arguments: func_name, [args]", node)
            end

            func_name = args[0]
            func_args = args[1]

            unless func_name.is_a?(String)
                runtime_error(TypeError, "First argument to ffi.call_crystal must be a string", node)
            end

            unless func_args.is_a?(Array(RuntimeValue))
                runtime_error(TypeError, "Second argument to ffi.call_crystal must be an array", node)
            end

            crystal_args = func_args.as(Array(RuntimeValue)).map { |arg| Dragonstone::FFI.normalize(arg) }
            result = Dragonstone::FFI.call_crystal(func_name, crystal_args)
            from_ffi_value(result)
        end

        private def ffi_call_c(args : Array(RuntimeValue), node : AST::MethodCall) : RuntimeValue
            unless args.size >= 2
                runtime_error(InterpreterError, "ffi.call_c requires at least 2 arguments: func_name, [args]", node)
            end

            func_name = args[0]
            func_args = args[1]

            unless func_name.is_a?(String)
                runtime_error(TypeError, "First argument to ffi.call_c must be a string", node)
            end

            unless func_args.is_a?(Array(RuntimeValue))
                runtime_error(TypeError, "Second argument to ffi.call_c must be an array", node)
            end

            c_args = func_args.as(Array(RuntimeValue)).map { |arg| Dragonstone::FFI.normalize(arg) }
            result = Dragonstone::FFI.call_c(func_name, c_args)
            from_ffi_value(result)
        end

        private def from_ffi_value(value : Dragonstone::FFI::InteropValue) : RuntimeValue
            case value

            when Nil, Bool, Int32, Int64, Float64, String, Char
                value

            when Array
                converted = [] of RuntimeValue
                value.each { |element| converted << from_ffi_value(element) }
                converted

            else
                nil

            end
        end


        private def call_tuple_method(tuple : TupleValue, name : String, args : Array(RuntimeValue), block_value : Function?, node : AST::MethodCall)
            case name

            when "length", "size"
                reject_block(block_value, "Tuple##{name}", node)
                unless args.empty?
                    runtime_error(InterpreterError, "Tuple##{name} does not take arguments", node)
                end
                tuple.elements.size.to_i64

            when "first"
                reject_block(block_value, "Tuple##{name}", node)
                unless args.empty?
                    runtime_error(InterpreterError, "Tuple##{name} does not take arguments", node)
                end
                tuple.elements.first?

            when "last"
                reject_block(block_value, "Tuple##{name}", node)
                unless args.empty?
                    runtime_error(InterpreterError, "Tuple##{name} does not take arguments", node)
                end
                tuple.elements.last?

            when "each"
                unless block_value
                    runtime_error(InterpreterError, "Tuple##{name} requires a block", node)
                end
                unless args.empty?
                    runtime_error(InterpreterError, "Tuple##{name} does not take arguments", node)
                end
                block = block_value.not_nil!
                run_enumeration_loop do
                    tuple.elements.each do |element|
                        outcome = execute_loop_iteration(block, [element.as(RuntimeValue)], node)
                        next if outcome[:state] == :next
                    end
                end
                tuple

            when "to_a"
                reject_block(block_value, "Tuple##{name}", node)
                unless args.empty?
                    runtime_error(InterpreterError, "Tuple##{name} does not take arguments", node)
                end
                tuple.elements.map { |value| value }

            else
                runtime_error(InterpreterError, "Unknown method '#{name}' for Tuple", node)

            end
        end

        private def method_defined_for_implicit_self?(receiver, name : String) : Bool
            case receiver
            when DragonInstance
                !!receiver.klass.lookup_method(name)
            when DragonClass
                !!receiver.lookup_method(name)
            when DragonModule
                !!receiver.lookup_method(name)
            when DragonEnum
                !!receiver.lookup_method(name)
            when DragonEnumMember
                name == "name" || name == "enum" || name == "value" || name == receiver.enum.value_method_name
            when Function
                name == "call"
            else
                false
            end
        end

        private def call_named_tuple_method(tuple : NamedTupleValue, name : String, args : Array(RuntimeValue), block_value : Function?, node : AST::MethodCall)
            case name

            when "length", "size"
                reject_block(block_value, "NamedTuple##{name}", node)
                unless args.empty?
                    runtime_error(InterpreterError, "NamedTuple##{name} does not take arguments", node)
                end
                tuple.entries.size.to_i64

            when "keys"
                reject_block(block_value, "NamedTuple##{name}", node)
                unless args.empty?
                    runtime_error(InterpreterError, "NamedTuple##{name} does not take arguments", node)
                end
                tuple.entries.keys.map(&.as(RuntimeValue))

            when "values"
                reject_block(block_value, "NamedTuple##{name}", node)
                unless args.empty?
                    runtime_error(InterpreterError, "NamedTuple##{name} does not take arguments", node)
                end
                tuple.entries.values.map { |value| value.as(RuntimeValue) }

            when "each"
                unless block_value
                    runtime_error(InterpreterError, "NamedTuple##{name} requires a block", node)
                end
                unless args.empty?
                    runtime_error(InterpreterError, "NamedTuple##{name} does not take arguments", node)
                end
                block = block_value.not_nil!
                run_enumeration_loop do
                    tuple.entries.each do |key, value|
                        outcome = execute_loop_iteration(block, [key.as(RuntimeValue), value.as(RuntimeValue)], node)
                        next if outcome[:state] == :next
                    end
                end
                tuple

            when "map"
                unless block_value
                    runtime_error(InterpreterError, "NamedTuple##{name} requires a block", node)
                end
                unless args.empty?
                    runtime_error(InterpreterError, "NamedTuple##{name} does not take arguments", node)
                end
                block = block_value.not_nil!
                result = [] of RuntimeValue
                run_enumeration_loop do
                    tuple.entries.each do |key, value|
                        outcome = execute_loop_iteration(block, [key.as(RuntimeValue), value.as(RuntimeValue)], node)
                        next if outcome[:state] == :next
                        result << normalize_runtime_value(outcome[:value], node)
                    end
                end
                result

            else
                runtime_error(InterpreterError, "Unknown method '#{name}' for NamedTuple", node)

            end
        end

        private def call_array_method(array : Array(RuntimeValue), name : String, args : Array(RuntimeValue), block_value : Function?, node : AST::MethodCall)
            case name

            when "length", "size"
                reject_block(block_value, "Array##{name}", node)
                array.size.to_i64

            when "push"
                reject_block(block_value, "Array##{name}", node)
                args.each { |arg| array << arg }
                array
                
            when "pop"
                reject_block(block_value, "Array##{name}", node)
                array.pop?

            when "first"
                reject_block(block_value, "Array##{name}", node)
                array.first?

            when "last"
                reject_block(block_value, "Array##{name}", node)
                array.last?

            when "empty"
                reject_block(block_value, "Array##{name}", node)
                array.empty?

            when "each"
                unless block_value
                    runtime_error(InterpreterError, "Array##{name} requires a block", node)
                end
                unless args.empty?
                    runtime_error(InterpreterError, "Array##{name} does not take arguments", node)
                end
                block = block_value.not_nil!
                run_enumeration_loop do
                    array.each do |element|
                        outcome = execute_loop_iteration(block, [element.as(RuntimeValue)], node)
                        next if outcome[:state] == :next
                    end
                end
                array

            when "map"
                unless block_value
                    runtime_error(InterpreterError, "Array##{name} requires a block", node)
                end
                unless args.empty?
                    runtime_error(InterpreterError, "Array##{name} does not take arguments", node)
                end
                block = block_value.not_nil!
                result = [] of RuntimeValue
                run_enumeration_loop do
                    array.each do |element|
                        outcome = execute_loop_iteration(block, [element.as(RuntimeValue)], node)
                        next if outcome[:state] == :next
                        result << normalize_runtime_value(outcome[:value], node)
                    end
                end
                result

            else
                runtime_error(InterpreterError, "Unknown method '#{name}' for Array", node)

            end
        end

        private def call_map_method(map : MapValue, name : String, args : Array(RuntimeValue), block_value : Function?, node : AST::MethodCall)
            case name

            when "length", "size"
                reject_block(block_value, "Map##{name}", node)
                map.size.to_i64

            when "keys"
                reject_block(block_value, "Map##{name}", node)
                map.keys.map { |key| key.as(RuntimeValue) }

            when "values"
                reject_block(block_value, "Map##{name}", node)
                map.values.map { |value| value.as(RuntimeValue) }

            when "empty"
                reject_block(block_value, "Map##{name}", node)
                map.empty?

            when "each"
                unless block_value
                    runtime_error(InterpreterError, "Map##{name} requires a block", node)
                end
                unless args.empty?
                    runtime_error(InterpreterError, "Map##{name} does not take arguments", node)
                end
                block = block_value.not_nil!
                run_enumeration_loop do
                    map.each do |key, value|
                        outcome = execute_loop_iteration(block, [key.as(RuntimeValue), value.as(RuntimeValue)], node)
                        next if outcome[:state] == :next
                    end
                end
                map

            when "each_key"
                unless block_value
                    runtime_error(InterpreterError, "Map##{name} requires a block", node)
                end
                unless args.empty?
                    runtime_error(InterpreterError, "Map##{name} does not take arguments", node)
                end
                block = block_value.not_nil!
                run_enumeration_loop do
                    map.each_key do |key|
                        outcome = execute_loop_iteration(block, [key.as(RuntimeValue)], node)
                        next if outcome[:state] == :next
                    end
                end
                map

            when "each_value"
                unless block_value
                    runtime_error(InterpreterError, "Map##{name} requires a block", node)
                end
                unless args.empty?
                    runtime_error(InterpreterError, "Map##{name} does not take arguments", node)
                end
                block = block_value.not_nil!
                run_enumeration_loop do
                    map.each_value do |value|
                        outcome = execute_loop_iteration(block, [value.as(RuntimeValue)], node)
                        next if outcome[:state] == :next
                    end
                end
                map

        when "map"
            unless block_value
                runtime_error(InterpreterError, "Map##{name} requires a block", node)
            end
            unless args.empty?
                runtime_error(InterpreterError, "Map##{name} does not take arguments", node)
            end
            block = block_value.not_nil!
            result = [] of RuntimeValue
            run_enumeration_loop do
                map.each do |key, value|
                    outcome = execute_loop_iteration(block, [key.as(RuntimeValue), value.as(RuntimeValue)], node)
                    next if outcome[:state] == :next
                    result << normalize_runtime_value(outcome[:value], node)
                end
            end
            result

        when "map_keys"
            unless block_value
                runtime_error(InterpreterError, "Map##{name} requires a block", node)
            end
            unless args.empty?
                runtime_error(InterpreterError, "Map##{name} does not take arguments", node)
            end
            block = block_value.not_nil!
            result = [] of RuntimeValue
            run_enumeration_loop do
                map.each_key do |key|
                    outcome = execute_loop_iteration(block, [key.as(RuntimeValue)], node)
                    next if outcome[:state] == :next
                    result << normalize_runtime_value(outcome[:value], node)
                end
            end
            result

        when "map_values"
            unless block_value
                runtime_error(InterpreterError, "Map##{name} requires a block", node)
            end
            unless args.empty?
                runtime_error(InterpreterError, "Map##{name} does not take arguments", node)
            end
            block = block_value.not_nil!
            result = [] of RuntimeValue
            run_enumeration_loop do
                map.each_value do |value|
                    outcome = execute_loop_iteration(block, [value.as(RuntimeValue)], node)
                    next if outcome[:state] == :next
                    result << normalize_runtime_value(outcome[:value], node)
                end
            end
            result

        when "has_key?", "includes_key?", "key?"
            reject_block(block_value, "Map##{name}", node)
            unless args.size == 1
                runtime_error(InterpreterError, "Map##{name} expects 1 argument, got #{args.size}", node)
            end
                map.has_key?(args.first)

            when "has_value?", "value?"
                reject_block(block_value, "Map##{name}", node)
                unless args.size == 1
                    runtime_error(InterpreterError, "Map##{name} expects 1 argument, got #{args.size}", node)
                end
                map.has_value?(args.first)

            when "delete"
                reject_block(block_value, "Map##{name}", node)
                unless args.size == 1
                    runtime_error(InterpreterError, "Map##{name} expects 1 argument, got #{args.size}", node)
                end
                map.delete(args.first)

            else
                runtime_error(InterpreterError, "Unknown method '#{name}' for Map", node)

            end
        end

        private def call_bag_constructor_method(constructor : BagConstructor, name : String, args : Array(RuntimeValue), block_value : Function?, node : AST::MethodCall)
            case name

            when "new"
                reject_block(block_value, "bag(#{constructor.element_descriptor.to_s})##{name}", node)
                unless args.empty?
                    runtime_error(InterpreterError, "bag(#{constructor.element_descriptor.to_s})::new does not take arguments", node)
                end
                BagValue.new(constructor.element_descriptor)

            else
                runtime_error(InterpreterError, "Unknown method '#{name}' for Bag constructor", node)

            end
        end

        private def call_bag_method(bag : BagValue, name : String, args : Array(RuntimeValue), block_value : Function?, node : AST::MethodCall)
            case name

            when "length", "size"
                reject_block(block_value, "Bag##{name}", node)
                unless args.empty?
                    runtime_error(InterpreterError, "Bag##{name} does not take arguments", node)
                end
                bag.size

            when "empty"
                reject_block(block_value, "Bag##{name}", node)
                unless args.empty?
                    runtime_error(InterpreterError, "Bag##{name} does not take arguments", node)
                end
                bag.elements.empty?

            when "add"
                reject_block(block_value, "Bag##{name}", node)
                unless args.size == 1
                    runtime_error(InterpreterError, "Bag##{name} expects 1 argument, got #{args.size}", node)
                end
                value = args.first
                ensure_descriptor_match!(bag.element_descriptor, value, node)
                bag.add(value)

            when "includes?", "member?", "contains?"
                reject_block(block_value, "Bag##{name}", node)
                unless args.size == 1
                    runtime_error(InterpreterError, "Bag##{name} expects 1 argument, got #{args.size}", node)
                end
                value = args.first
                ensure_descriptor_match!(bag.element_descriptor, value, node)
                bag.includes?(value)

            when "each"
                unless block_value
                    runtime_error(InterpreterError, "Bag##{name} requires a block", node)
                end
                unless args.empty?
                    runtime_error(InterpreterError, "Bag##{name} does not take arguments", node)
                end
                block = block_value.not_nil!
                run_enumeration_loop do
                    bag.elements.each do |value|
                        outcome = execute_loop_iteration(block, [value], node)
                        next if outcome[:state] == :next
                    end
                end
                bag

            when "map"
                unless block_value
                    runtime_error(InterpreterError, "Bag##{name} requires a block", node)
                end
                unless args.empty?
                    runtime_error(InterpreterError, "Bag##{name} does not take arguments", node)
                end
                block = block_value.not_nil!
                result = [] of RuntimeValue
                run_enumeration_loop do
                    bag.elements.each do |value|
                        outcome = execute_loop_iteration(block, [value], node)
                        next if outcome[:state] == :next
                        result << normalize_runtime_value(outcome[:value], node)
                    end
                end
                result

            when "to_a"
                reject_block(block_value, "Bag##{name}", node)
                unless args.empty?
                    runtime_error(InterpreterError, "Bag##{name} does not take arguments", node)
                end
                bag.elements.dup

            else
                runtime_error(InterpreterError, "Unknown method '#{name}' for Bag", node)

            end
        end

        private def call_string_method(string : String, name : String, args : Array(RuntimeValue), block_value : Function?, node : AST::MethodCall)
            case name

            when "length", "size"
                reject_block(block_value, "String##{name}", node)
                string.size.to_i64

            when "upcase"
                reject_block(block_value, "String##{name}", node)
                string.upcase

            when "downcase"
                reject_block(block_value, "String##{name}", node)
                string.downcase

            when "reverse"
                reject_block(block_value, "String##{name}", node)
                string.reverse

            when "empty"
                reject_block(block_value, "String##{name}", node)
                string.empty?

            when "slice"
                reject_block(block_value, "String##{name}", node)
                case args.size
                when 2
                    slice_string_with_start_and_length(string, args[0], args[1], node)
                when 1
                    slice_string_with_range(string, args.first, node)
                else
                    runtime_error(InterpreterError, "String#slice expects either 2 arguments (start, length) or 1 range argument, got #{args.size}", node)
                end

            else
                runtime_error(InterpreterError, "Unknown method '#{name}' for String", node)
                
            end
        end

        private def slice_string_with_start_and_length(string : String, start_value, length_value, node : AST::MethodCall) : String
            start = slice_numeric_argument(start_value, "slice start index", node)
            length = slice_numeric_argument(length_value, "slice length", node)
            slice_chars_with_bounds(string.chars, start, length, node)
        end

        private def slice_string_with_range(string : String, range_value, node : AST::MethodCall) : String
            range = case range_value
                when Range(Int64, Int64)
                    range_value
                else
                    runtime_error(TypeError, "String#slice expects a range of integers", node)
                end

            start = slice_numeric_argument(range.begin, "slice range start", node)
            finish = slice_numeric_argument(range.end, "slice range end", node)
            length = if range.excludes_end?
                finish - start
            else
                finish - start + 1
            end

            length = 0_i64 if length < 0
            slice_chars_with_bounds(string.chars, start, length, node)
        end

        private def slice_chars_with_bounds(chars : Array(Char), start : Int64, length : Int64, node : AST::Node) : String
            if length < 0
                runtime_error(OutOfBounds, "String#slice length must be >= 0, got #{length}", node)
            end

            if start < 0
                runtime_error(OutOfBounds, "String#slice start index #{start} is negative", node)
            end

            char_count = chars.size.to_i64

            if start > char_count
                runtime_error(OutOfBounds, "String#slice start index #{start} is out of bounds for #{char_count} characters", node)
            elsif start == char_count
                if length == 0
                    return ""
                else
                    runtime_error(OutOfBounds, "String#slice start index #{start} is out of bounds for #{char_count} characters", node)
                end
            end

            return "" if length == 0

            if start + length > char_count
                runtime_error(OutOfBounds, "String#slice length #{length} exceeds string boundary (#{char_count} characters)", node)
            end

            start_i = start.to_i32
            length_i = length.to_i32
            chars[start_i, length_i].not_nil!.join
        end

        private def slice_numeric_argument(value, description : String, node : AST::Node) : Int64
            number = case value
                when Int64
                    value
                when Int32
                    value.to_i64
                when Float64
                    value.to_i64
                else
                    runtime_error(TypeError, "String##{description} must be numeric", node)
                end
            number
        end

        private def call_range_method(range : RangeValue, name : String, args : Array(RuntimeValue), block_value : Function?, node : AST::MethodCall)
            case name

            when "each"
                unless block_value
                    runtime_error(InterpreterError, "Range##{name} requires a block", node)
                end
                unless args.empty?
                    runtime_error(InterpreterError, "Range##{name} does not take arguments", node)
                end
                block = block_value.not_nil!
                run_enumeration_loop do
                    range.each do |element|
                        runtime_element = coerce_range_element(element).as(RuntimeValue)
                        outcome = execute_loop_iteration(block, [runtime_element], node)
                        next if outcome[:state] == :next
                    end
                end
                range

            when "includes?", "include?"
                reject_block(block_value, "Range##{name}", node)
                unless args.size == 1
                    runtime_error(InterpreterError, "Range##{name} expects 1 argument, got #{args.size}", node)
                end
                value = args.first
                case range
                when Range(Int64, Int64)
                    range.includes?(to_int64(value, node))
                when Range(Char, Char)
                    char = if value.is_a?(Char)
                        value
                    elsif value.is_a?(String) && value.size == 1
                        value[0]
                    else
                        runtime_error(TypeError, "Expected character value for Range", node)
                    end
                    range.includes?(char)
                else
                    runtime_error(InterpreterError, "Unsupported range type #{range.class}", node)
                end

            when "begin", "first"
                reject_block(block_value, "Range##{name}", node)
                unless args.empty?
                    runtime_error(InterpreterError, "Range##{name} does not take arguments", node)
                end
                coerce_range_element(range.begin)

            when "end", "last"
                reject_block(block_value, "Range##{name}", node)
                unless args.empty?
                    runtime_error(InterpreterError, "Range##{name} does not take arguments", node)
                end
                coerce_range_element(range.end)

            when "size"
                reject_block(block_value, "Range##{name}", node)
                unless args.empty?
                    runtime_error(InterpreterError, "Range##{name} does not take arguments", node)
                end
                size = range.size
                size.nil? ? nil : (size.is_a?(Int32) ? size.to_i64 : size)

            when "to_a"
                reject_block(block_value, "Range##{name}", node)
                unless args.empty?
                    runtime_error(InterpreterError, "Range##{name} does not take arguments", node)
                end
                result = [] of RuntimeValue
                range.each do |element|
                    result << coerce_range_element(element)
                end
                result

            else
                runtime_error(InterpreterError, "Unknown method '#{name}' for Range", node)

            end
        end

        private def call_exception_method(exception : RaisedException, name : String, args : Array(RuntimeValue), block_value : Function?, node : AST::MethodCall)
            reject_block(block_value, "Exception##{name}", node)
            unless args.empty?
                runtime_error(InterpreterError, "Exception##{name} does not take arguments", node)
            end

            case name
            when "message"
                exception.message
            when "class", "type"
                exception.error.class.name.split("::").last
            else
                runtime_error(InterpreterError, "Unknown method '#{name}' for Exception", node)

            end
        end

        private def instantiate_class(klass : DragonClass, args : Array(RuntimeValue), node : AST::MethodCall)
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
                push_scope(func.closure.dup, func.type_closure.dup)
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
                end

                if typing_enabled? && func.return_type
                    descriptor = descriptor_for(func.return_type.not_nil!)
                    ensure_type!(descriptor, result, call_location)
                end
                result
            end
        end

        private def call_bound_method(receiver, method_def : MethodDefinition, args : Array(RuntimeValue), block_value : Function?, call_location : Location? = nil, *, self_object : RuntimeValue? = nil)
            final_args = args.dup
            expected_params = method_def.parameters.size

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
                current_scope["self"] = self_object || receiver
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

        private def invoke_block(block : Function, args : Array(RuntimeValue), call_location : Location? = nil)
            if args.size != block.parameters.size
                runtime_error(TypeError, "Block expects #{block.parameters.size} arguments, got #{args.size}", call_location)
            end

            with_block(nil) do
                push_scope(block.closure.dup, block.type_closure.dup)
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
                end
                result
            end
        end

        private def execute_loop_iteration(block : Function, args : Array(RuntimeValue), node : AST::MethodCall) : NamedTuple(state: Symbol, value: RuntimeValue?)
            begin
                value = invoke_block(block, args, node.location)
                {state: :yielded, value: value}
            rescue e : NextSignal
                {state: :next, value: nil}
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
            when Nil, Bool, Int32, Int64, Float64, String, Char, SymbolValue, Range(Int64, Int64), Range(Char, Char), DragonModule, DragonClass, DragonInstance, DragonEnumMember, Function, FFIModule, RaisedException, TupleValue, NamedTupleValue, BagConstructor, BagValue
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

        private def get_variable(name : String, location : Location? = nil)
            binding_info = find_binding_with_scope(name)
            return unwrap_binding(binding_info[:value]) if binding_info

            constant_info = lookup_container_constant(name)
            return constant_info[:value] if constant_info[:found]

            runtime_error(NameError, "Undefined variable or constant: #{name}", location)
        end

        private def set_variable(name : String, value, location : Location? = nil, type_descriptor : Typing::Descriptor? = nil)
            binding_info = find_binding_with_scope(name)

            target_scope = current_scope
            scope_index = @scopes.size - 1

            if binding_info
                stored_value = binding_info[:value]

                if stored_value.is_a?(ConstantBinding)
                    runtime_error(ConstantError, "Cannot reassign constant #{name}", location)
                elsif binding_info[:scope] == current_scope
                    target_scope = binding_info[:scope]
                    scope_index = binding_info[:index]
                end
            end

            descriptor = nil
            if typing_enabled?
                descriptor = type_descriptor || type_descriptor_for_scope(scope_index, name)
                ensure_type!(descriptor, value, location) if descriptor
            end

            target_scope[name] = value

            assign_type_to_scope(scope_index, name, type_descriptor || descriptor) if typing_enabled?
            value
        end

        private def set_constant(name : String, value, location : Location? = nil)
            binding_info = find_binding_with_scope(name)
            if binding_info
                runtime_error(ConstantError, "Constant #{name} already defined", location)
            end
            current_scope[name] = ConstantBinding.new(value)
            value
        end

        private def define_container_constant(container : DragonModule, name : String, value, node : AST::Node)
            if container.constant?(name)
                runtime_error(ConstantError, "Constant #{name} already defined in #{container.name}", node)
            end
            container.define_constant(name, value)
            value
        end

        private def lookup_constant_value(name : String)
            constant_info = lookup_container_constant(name)
            return constant_info[:value] if constant_info[:found]

            binding = find_binding(name)
            unwrap_binding(binding) if binding
        end

        private def lookup_container_constant(name : String) : NamedTuple(found: Bool, value: RuntimeValue?)
            @container_stack.reverse_each do |container|
                if name == "self"
                    return {found: true, value: container}
                end
                if container.constant?(name)
                    return {found: true, value: container.fetch_constant(name)}
                end
            end
            {found: false, value: nil}
        end

        private def find_binding_with_scope(name : String)
            (@scopes.size - 1).downto(0) do |index|
                scope = @scopes[index]
                return {index: index, scope: scope, value: scope[name]?} if scope.has_key?(name)
            end
            nil
        end

        private def find_binding(name : String)
            info = find_binding_with_scope(name)
            info ? info[:value] : nil
        end

        private def unwrap_binding(binding)
            if binding.is_a?(ConstantBinding)
                binding.value
            else
                binding
            end
        end

        private def current_scope
            @scopes.last
        end

        private def current_type_scope
            @type_scopes.last
        end

        private def current_container
            @container_stack.last?
        end

        private def push_scope(scope : Scope, type_scope : TypeScope? = nil)
            @scopes << scope
            @type_scopes << (type_scope || new_type_scope)
        end

        private def pop_scope
            @scopes.pop
            @type_scopes.pop
        end

        private def with_container(container : DragonModule)
            @container_stack << container
            yield
        ensure
            @container_stack.pop
        end

        private def with_block(block : Function?, &block_proc)
            @block_stack << block
            begin
                yield
            ensure
                @block_stack.pop
            end
        end

        private def current_block : Function?
            @block_stack.last?
        end

        private def descriptor_for(expr : AST::TypeExpression) : Typing::Descriptor
            @descriptor_cache.fetch(expr)
        end

        private def ensure_type!(descriptor : Typing::Descriptor?, value, node_or_location = nil)
            return unless typing_enabled?
            return unless descriptor

            context = typing_context
            begin
                return if descriptor.satisfied_by?(value, context)
            rescue e : Typing::UnknownTypeError
                runtime_error(NameError, "Unknown type '#{e.type_name}'", node_or_location)
            rescue e : Typing::RecursiveAliasError
                runtime_error(TypeError, "Recursive alias '#{e.alias_name}' detected during type checking", node_or_location)
            end

            runtime_error(TypeError, "Expected #{descriptor.to_s}, got #{describe_runtime_value(value)}", node_or_location)
        end

        private def ensure_descriptor_match!(descriptor : Typing::Descriptor?, value, node_or_location = nil)
            return unless descriptor

            context = typing_context
            begin
                return if descriptor.satisfied_by?(value, context)
            rescue e : Typing::UnknownTypeError
                runtime_error(NameError, "Unknown type '#{e.type_name}'", node_or_location)
            rescue e : Typing::RecursiveAliasError
                runtime_error(TypeError, "Recursive alias '#{e.alias_name}' detected during type checking", node_or_location)
            end

            runtime_error(TypeError, "Expected #{descriptor.to_s}, got #{describe_runtime_value(value)}", node_or_location)
        end

        private def typing_context : Typing::Context
            @typing_context ||= Typing::Context.new(
                ->(name : String) { lookup_constant_value(name) },
                ->(constant : RuntimeValue, value : RuntimeValue) { constant_type_match?(constant, value) },
                ->(name : String) { descriptor_for_alias(name) }
            )
        end

        private def constant_type_match?(constant : RuntimeValue, value : RuntimeValue)
            case constant
            when DragonClass
                if value.is_a?(DragonInstance)
                    within_hierarchy?(value.as(DragonInstance).klass, constant)
                elsif value.is_a?(DragonClass)
                    within_hierarchy?(value.as(DragonClass), constant)
                else
                    false
                end
            when DragonModule
                value.is_a?(DragonModule) && value == constant
            when Function
                value.is_a?(Function) && value == constant
            else
                value == constant
            end
        end

        private def current_self_instance(node : AST::Node) : DragonInstance
            self_value = current_scope["self"]?
            unless self_value && self_value.is_a?(DragonInstance)
                runtime_error(InterpreterError, "Instance variables can only be accessed inside instance methods", node)
            end
            self_value.as(DragonInstance)
        end

        private def set_instance_variable(instance : DragonInstance, name : String, value, node_or_location)
            if typing_enabled?
                if descriptor = resolve_instance_variable_descriptor(instance.klass, name)
                    ensure_type!(descriptor, value, node_or_location)
                end
            end
            instance.ivars[name] = value
        end

        private def resolve_instance_variable_descriptor(klass : DragonClass, name : String) : Typing::Descriptor?
            if descriptor = klass.ivar_type_descriptor(name)
                descriptor
            else
                if type_expr = klass.ivar_type_annotation(name)
                    descriptor = descriptor_for(type_expr)
                    klass.cache_ivar_descriptor(name, descriptor)
                    descriptor
                else
                    nil
                end
            end
        end

        private def define_accessor_methods(klass : DragonClass, macro_node : AST::AccessorMacro, entry : AST::AccessorEntry)
            location = macro_node.location
            case macro_node.kind
            when :getter
                define_getter_method(klass, entry, macro_node.visibility, location)
            when :setter
                define_setter_method(klass, entry, macro_node.visibility, location)
            when :property
                define_getter_method(klass, entry, macro_node.visibility, location)
                define_setter_method(klass, entry, macro_node.visibility, location)
            else
                runtime_error(InterpreterError, "Unknown accessor macro '#{macro_node.kind}'", macro_node)
            end
        end

        private def define_getter_method(klass : DragonClass, entry : AST::AccessorEntry, visibility : Symbol, location : Location?)
            body = [] of AST::Node
            body << AST::InstanceVariable.new(entry.name, location: location)
            method = build_method_definition(klass, entry.name, [] of AST::TypedParameter, body, entry.type_annotation, visibility)
            klass.define_method(entry.name, method)
        end

        private def define_setter_method(klass : DragonClass, entry : AST::AccessorEntry, visibility : Symbol, location : Location?)
            param = AST::TypedParameter.new("value", entry.type_annotation)
            value_var = AST::Variable.new("value", nil, location: location)
            assignment = AST::InstanceVariableAssignment.new(entry.name, value_var, location: location)
            body = [] of AST::Node
            body << assignment
            method = build_method_definition(klass, "#{entry.name}=", [param], body, entry.type_annotation, visibility)
            klass.define_method("#{entry.name}=", method)
        end

        private def build_method_definition(klass : DragonClass, name : String, typed_parameters : Array(AST::TypedParameter), body : Array(AST::Node), return_type : AST::TypeExpression?, visibility : Symbol) : MethodDefinition
            MethodDefinition.new(
                name,
                typed_parameters,
                body,
                current_scope.dup,
                current_type_scope.dup,
                klass,
                [] of AST::RescueClause,
                return_type,
                visibility: visibility
            )
        end

        private def ensure_method_visible!(receiver, method : MethodDefinition, node : AST::MethodCall, implicit_self : Bool)
            case method.visibility
            when :public
                return
            when :private
                runtime_error(InterpreterError, "Cannot call private method '#{method.name}' with an explicit receiver", node) unless implicit_self
            when :protected
                owner = method.owner
                unless owner.is_a?(DragonClass)
                    runtime_error(InterpreterError, "Cannot call protected method '#{method.name}' with an explicit receiver", node) unless implicit_self
                    return
                end

                owner_class = owner.as(DragonClass)
                caller_self = current_scope["self"]?
                unless caller_self && caller_self.is_a?(DragonInstance)
                    runtime_error(InterpreterError, "Protected method '#{method.name}' can only be called from within #{owner_class.name} or its subclasses", node)
                end

                caller_class = caller_self.as(DragonInstance).klass
                unless within_hierarchy?(caller_class, owner_class)
                    runtime_error(InterpreterError, "Protected method '#{method.name}' can only be called from within #{owner_class.name} or its subclasses", node)
                end

                if receiver.is_a?(DragonInstance)
                    receiver_class = receiver.as(DragonInstance).klass
                    unless within_hierarchy?(receiver_class, owner_class)
                        runtime_error(InterpreterError, "Protected method '#{method.name}' can only be called on instances of #{owner_class.name} or its subclasses", node)
                    end
                else
                    runtime_error(InterpreterError, "Cannot call protected method '#{method.name}' with an explicit receiver", node) unless implicit_self
                end
            else
                runtime_error(InterpreterError, "Unknown method visibility '#{method.visibility}'", node)
            end
        end

        private def within_hierarchy?(klass : DragonClass, ancestor : DragonClass) : Bool
            current = klass
            while current
                return true if current == ancestor
                current = current.superclass
            end
            false
        end

        private def describe_runtime_value(value)
            case value
            when DragonInstance
                "#{value.klass.name} instance"
            when DragonClass
                "#{value.name} class"
            when DragonModule
                "#{value.name} module"
            when Nil
                "nil"
            when TupleValue
                "Tuple"
            when NamedTupleValue
                "NamedTuple"
            when SymbolValue
                "Symbol"
            when BagConstructor
                value.to_s
            when BagValue
                "Bag"
            else
                value.class.name
            end
        end

        private def new_type_scope : TypeScope
            {} of String => Typing::Descriptor
        end

        private def register_type_alias(name : String, expr : AST::TypeExpression, node : AST::AliasDefinition)
            if @type_aliases.has_key?(name)
                runtime_error(NameError, "Type alias #{name} already defined", node)
            end
            @type_aliases[name] = expr
            @alias_descriptor_cache.delete(name)
        end

        private def find_type_alias(name : String) : AST::TypeExpression?
            @type_aliases[name]?
        end

        private def descriptor_for_alias(name : String) : Typing::Descriptor?
            expr = find_type_alias(name)
            return nil unless expr
            cached = @alias_descriptor_cache[name]?
            return cached if cached
            descriptor = descriptor_for(expr)
            @alias_descriptor_cache[name] = descriptor
            descriptor
        end

        private def assign_type_to_scope(index : Int32, name : String, descriptor : Typing::Descriptor?)
            scope = @type_scopes[index]
            if descriptor
                scope[name] = descriptor
            else
                scope.delete(name)
            end
        end

        private def type_descriptor_for_scope(index : Int32, name : String) : Typing::Descriptor?
            scope = @type_scopes[index]?
            scope ? scope[name]? : nil
        end

        private def runtime_error(klass, message : String, node_or_location = nil)
            location = case node_or_location
                when AST::Node
                    node_or_location.location
                when Location
                    node_or_location
                when Nil
                    nil
                else
                    node_or_location.as(Location?)
                end
            raise klass.new(message, location: location)
        end

        private def evaluate_interpolation(content : String)
            lexer = Lexer.new(content)
            tokens = lexer.tokenize
            parser = Parser.new(tokens)
            expression = parser.parse_expression_entry
            expression.accept(self)
        rescue e : LexerError
            runtime_error(InterpreterError, "Error evaluating interpolation #{content.inspect}: #{e.message}")
        rescue e : ParserError
            runtime_error(InterpreterError, "Error evaluating interpolation #{content.inspect}: #{e.message}")
        end

        private def get_type_name(value) : String
            case value

            when String
                "String"

            when Int64
                "Integer"

            when Int32
                "Integer"

            when Float64
                "Float"

            when Bool
                "Boolean"

            when Nil
                "Nil"

            when SymbolValue
                "Symbol"

            when Array(RuntimeValue)
                "Array"

            when Hash(RuntimeValue, RuntimeValue)
                "Map"

            when TupleValue
                "Tuple"

            when NamedTupleValue
                "NamedTuple"

            when FFIModule
                "FFIModule"

            when DragonClass
                "Class"

            when DragonInstance
                value.klass.name

            when DragonModule
                "Module"

            when Function
                "Function"

            when Range(Int64, Int64), Range(Char, Char)
                "Range"

            else
                value.class.name

            end
        end

        private def display_value(value) : String
            case value

            when Nil
                ""

            when String
                value

            when SymbolValue
                value.name

            when Array(RuntimeValue)
                "[#{value.map { |v| display_value(v) }.join(", ")}]"

            when MapValue
                pairs = value.map { |k, v| "#{display_value(k)} -> #{display_value(v)}" }.join(", ")
                "{#{pairs}}"

            when TupleValue
                "{#{value.elements.map { |element| display_value(element) }.join(", ")}}"

            when NamedTupleValue
                pairs = value.entries.map { |key, val| "#{key.name}: #{display_value(val)}" }.join(", ")
                "{#{pairs}}"

            when Bool
                value.to_s

            when Int64
                value.to_s

            when Int32
                value.to_i64.to_s

            when Float64
                value.to_s

            when Char
                value.to_s

            when FFIModule
                "ffi"

            when DragonInstance
                "#<#{value.klass.name}:0x#{value.object_id.to_s(16)}>"

            when DragonClass
                value.name

            when DragonModule
                value.name

            when DragonEnumMember
                value.name

            when BagValue
                "[#{value.elements.map { |element| display_value(element) }.join(", ")}]"

            when BagConstructor
                value.to_s

            when Function
                name = value.name || "<anonymous>"
                "#<Function #{name}>"

            when RaisedException
                value.to_s

            when Range(Int64, Int64), Range(Char, Char)
                value.to_s

            else
                value.to_s

            end
        end

        private def format_value(value) : String
            case value

            when String
                value.inspect

            when Array(RuntimeValue)
                "[#{value.map { |v| format_value(v) }.join(", ")}]"

            when Hash(RuntimeValue, RuntimeValue)
                pairs = value.map { |k, v| "#{format_value(k)} -> #{format_value(v)}" }.join(", ")
                "{#{pairs}}"

            when TupleValue
                "{#{value.elements.map { |element| format_value(element) }.join(", ")}}"

            when NamedTupleValue
                pairs = value.entries.map { |key, val| "#{key.name}: #{format_value(val)}" }.join(", ")
                "{#{pairs}}"

            when Nil
                "nil"

            when Bool
                value.to_s

            when FFIModule
                "ffi"

            when SymbolValue
                value.inspect

            when DragonInstance
                "#<#{value.klass.name}:0x#{value.object_id.to_s(16)}>"

            when DragonClass
                value.name

            when DragonModule
                value.name

            else
                value.to_s

            end
        end

        private def literal_node_for(value, node : AST::Node) : AST::Literal
            case value

            when Nil
                AST::Literal.new(nil, location: node.location)

            when Bool
                AST::Literal.new(value, location: node.location)

            when Int64
                AST::Literal.new(value, location: node.location)

            when Float64
                AST::Literal.new(value, location: node.location)

            when String
                AST::Literal.new(value, location: node.location)

            when Char
                AST::Literal.new(value, location: node.location)

            else
                runtime_error(InterpreterError, "Cannot use value of type #{value.class} in attribute assignment", node)
            
            end
        end

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
