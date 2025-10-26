# ---------------------------------
# ---------- Interpreter ----------
# ---------------------------------
require "../resolver/errors"
require "../lexer/*"
require "../parser/*"
require "../codegen/*"
require "../typing/*"

module Dragonstone
    alias RangeValue = Range(Int64, Int64) | Range(Float64, Float64) | Range(Char, Char)
    alias RuntimeValue = Nil | Bool | Int32 | Int64 | Float64 | String | Char | Array(RuntimeValue) | DragonModule | DragonClass | DragonInstance | Function | RangeValue | FFIModule
    alias ScopeValue = RuntimeValue | ConstantBinding
    alias Scope = Hash(String, ScopeValue)
    alias TypeScope = Hash(String, Typing::Descriptor)

    class ReturnValue < Exception
        getter value : RuntimeValue?

        def initialize(@value : RuntimeValue?)
            super()
        end
    end

    class BreakSignal < Exception; end
    
    class NextSignal < Exception; end

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
        @parameter_names : Array(String)

        def initialize(@name : String, typed_parameters : Array(AST::TypedParameter), @body : Array(AST::Node), @closure : Scope, @type_closure : TypeScope, @rescue_clauses : Array(AST::RescueClause) = [] of AST::RescueClause, @return_type : AST::TypeExpression? = nil)
            @typed_parameters = typed_parameters
            @parameter_names = typed_parameters.map(&.name)
        end

        def parameters : Array(String)
            @parameter_names
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

        def initialize(name : String, @superclass : DragonClass? = nil)
            super(name)
        end

        def lookup_method(name : String) : MethodDefinition?
            super || @superclass.try &.lookup_method(name)
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
            @container_definition_depth = 0
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
            if node.receiver
                receiver_value = node.receiver.not_nil!.accept(self)
                call_receiver_method(receiver_value, node)
            else
                call_function_name(node)
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
                current_value = call_receiver_method(receiver, current_call)
                evaluate_compound_assignment(current_value, operator, node.value, node)

            else
                node.value.accept(self)

            end

            literal = literal_node_for(value, node)
            setter_args = [] of AST::Node
            setter_args << literal
            setter_call = AST::MethodCall.new(setter_name, setter_args, nil, location: node.location)
            call_receiver_method(receiver, setter_call)
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

        def visit_variable(node : AST::Variable) : RuntimeValue?
            get_variable(node.name, location: node.location)
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

        def visit_index_access(node : AST::IndexAccess) : RuntimeValue?
            object = node.object.accept(self)
            return nil if node.nil_safe && object.nil?

            index = node.index.accept(self)
            fetch_index_value(object, index, node)
        end

        def visit_interpolated_string(node : AST::InterpolatedString) : RuntimeValue?
            result = String.build do |io|
                node.parts.each do |part|
                    type, content = part
                    if type == :string
                        io << content
                    else
                        value = evaluate_interpolation(content)
                        io << (value.nil? ? "" : value.to_s)
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
            target = node.expression.try &.accept(self)
            node.when_clauses.each do |clause|
                clause.conditions.each do |condition|
                    value = condition.accept(self)
                    match = if node.expression
                            value == target
                        else
                            truthy?(value)
                        end
                    return execute_block(clause.block) if match
                end
            end
            execute_block(node.else_block || [] of AST::Node)
        end

        def visit_while_statement(node : AST::WhileStatement) : RuntimeValue?
            result = nil
            @loop_depth += 1
            while truthy?(node.condition.accept(self))
                begin
                    result = execute_block(node.block)
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
            if current_container
                method = MethodDefinition.new(node.name, node.typed_parameters, node.body, closure, type_closure, node.rescue_clauses, node.return_type)
                current_container.not_nil!.define_method(node.name, method)
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

        def visit_return_statement(node : AST::ReturnStatement) : RuntimeValue?
            value = node.value ? node.value.not_nil!.accept(self) : nil
            raise ReturnValue.new(value)
        end

        def visit_module_definition(node : AST::ModuleDefinition) : RuntimeValue?
            existing = lookup_constant_value(node.name)
            mod = if existing

                unless existing.is_a?(DragonModule)
                    runtime_error(ConstantError, "Constant #{node.name} already defined", node)
                    
                end
                existing.as(DragonModule)
            else
                new_module = DragonModule.new(node.name)
                set_constant(node.name, new_module, location: node.location)
                new_module

            end

            with_container(mod) do
                @container_definition_depth += 1
                push_scope(Scope.new, new_type_scope)

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
            existing = lookup_constant_value(node.name)
            klass = if existing
                unless existing.is_a?(DragonClass)
                    runtime_error(ConstantError, "Constant #{node.name} already defined", node)
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
                set_constant(node.name, new_class, location: node.location)
                new_class
            end

            with_container(klass) do
                @container_definition_depth += 1
                push_scope(Scope.new, new_type_scope)
                begin
                    execute_block(node.body)
                ensure
                    pop_scope
                    @container_definition_depth -= 1
                end
            end
            klass
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

            when Array(RuntimeValue)
                idx = index_to_int(index, node)
                object[idx]? || nil
            when String
                idx = index_to_int(index, node)
                object[idx]? || nil
            else
                runtime_error(TypeError, "Cannot index #{object.class}", node)
            end
        end

        private def assign_index_value(object, index, value, node : AST::Node)
            case object

            when Array(RuntimeValue)
                idx = index_to_int(index, node)
                object[idx] = value
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

            elsif left.is_a?(Float64) && right.is_a?(Float64)
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

        private def call_function_name(node : AST::MethodCall)
            case node.name

            when "puts"
                values = node.arguments.map { |arg| arg.accept(self) }
                append_output(values.map { |v| v.nil? ? "" : v.to_s }.join(" "))
                nil

            when "typeof"
                if node.arguments.size != 1
                    runtime_error(TypeError, "typeof expects exactly 1 argument, got #{node.arguments.size}", node)

                end
                value = node.arguments[0].accept(self)
                get_type_name(value)

            else
                func = get_variable(node.name, location: node.location)

                unless func.is_a?(Function)
                    runtime_error(NameError, "Unknown method or variable: #{node.name}", node)

                end
                call_function(func.as(Function), node.arguments, node.location)

            end
        end

        private def call_receiver_method(receiver, node : AST::MethodCall)
            case receiver

            when Array(RuntimeValue)
                args = evaluate_arguments(node.arguments)
                call_array_method(receiver, node.name, args, node)

            when String
                args = evaluate_arguments(node.arguments)
                call_string_method(receiver, node.name, args, node)

            when FFIModule
                args = evaluate_arguments(node.arguments)
                call_ffi_dispatch(node.name, args, node)

            when DragonClass
                if node.name == "new"
                    args = evaluate_arguments(node.arguments)
                    instantiate_class(receiver, args, node)

                else
                    method = receiver.lookup_method(node.name)
                    runtime_error(NameError, "Unknown method '#{node.name}' for class #{receiver.name}", node) unless method
                    args = evaluate_arguments(node.arguments)
                    with_container(receiver) do
                        call_bound_method(receiver, method.not_nil!, args, node.location)
                    end
                end

            when DragonModule
                method = receiver.lookup_method(node.name)
                runtime_error(NameError, "Unknown method '#{node.name}' for module #{receiver.name}", node) unless method
                args = evaluate_arguments(node.arguments)
                with_container(receiver) do
                    call_bound_method(receiver, method.not_nil!, args, node.location)
                end

            when DragonInstance
                method = receiver.klass.lookup_method(node.name)
                runtime_error(NameError, "Undefined method '#{node.name}' for instance of #{receiver.klass.name}", node) unless method
                args = evaluate_arguments(node.arguments)
                with_container(receiver.klass) do
                    call_bound_method(receiver.klass, method.not_nil!, args, node.location, self_object: receiver)
                end

            when Function
                if node.name == "call"
                    call_function(receiver, node.arguments, node.location)

                else
                    runtime_error(InterpreterError, "Unknown method '#{node.name}' for Function", node)

                end
            else
                runtime_error(TypeError, "Cannot call method '#{node.name}' on #{receiver.class}", node)

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
                value.map { |element| from_ffi_value(element) }

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
                value.map { |element| from_ffi_value(element) }

            else
                nil

            end
        end


        private def call_array_method(array : Array(RuntimeValue), name : String, args : Array(RuntimeValue), node : AST::MethodCall)
            case name

            when "length", "size"
                array.size.to_i64

            when "push"
                args.each { |arg| array << arg }
                array
                
            when "pop"
                array.pop?

            when "first"
                array.first?

            when "last"
                array.last?

            when "empty"
                array.empty?

            else
                runtime_error(InterpreterError, "Unknown method '#{name}' for Array", node)

            end
        end

        private def call_string_method(string : String, name : String, args : Array(RuntimeValue), node : AST::MethodCall)
            case name

            when "length", "size"
                string.size.to_i64

            when "upcase"
                string.upcase

            when "downcase"
                string.downcase

            when "reverse"
                string.reverse

            when "empty"
                string.empty?

            else
                runtime_error(InterpreterError, "Unknown method '#{name}' for String", node)
                
            end
        end

        private def instantiate_class(klass : DragonClass, args : Array(RuntimeValue), node : AST::MethodCall)
            instance = DragonInstance.new(klass)
            initializer = klass.lookup_method("initialize")
            
            if initializer
                with_container(klass) do
                    call_bound_method(instance, initializer.not_nil!, args, node.location, self_object: instance)
                end
            elsif !args.empty?
                runtime_error(TypeError, "#{klass.name}#initialize expects 0 arguments, got #{args.size}", node)
            end
            instance
        end

        private def call_function(func : Function, arg_nodes : Array(AST::Node), call_location : Location? = nil)
            args = arg_nodes.map { |arg| arg.accept(self) }
            if args.size != func.parameters.size
                runtime_error(TypeError, "Function #{func.name || "anonymous"} expects #{func.parameters.size} arguments, got #{args.size}", call_location)
            end

            push_scope(func.closure.dup, func.type_closure.dup)
            scope_index = @scopes.size - 1
            func.typed_parameters.each_with_index do |param, index|
                value = args[index]
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

        private def call_bound_method(receiver, method_def : MethodDefinition, args : Array(RuntimeValue), call_location : Location? = nil, *, self_object : RuntimeValue? = nil)
            if args.size != method_def.parameters.size
                runtime_error(TypeError, "Method #{method_def.name} expects #{method_def.parameters.size} arguments, got #{args.size}", call_location)
            end

            push_scope(method_def.closure.dup, method_def.type_closure.dup)
            current_scope["self"] = self_object || receiver
            scope_index = @scopes.size - 1
            method_def.typed_parameters.each_with_index do |param, index|
                value = args[index]
                descriptor = typing_enabled? && param.type ? descriptor_for(param.type.not_nil!) : nil
                ensure_type!(descriptor, value, call_location) if descriptor
                current_scope[param.name] = value
                assign_type_to_scope(scope_index, param.name, descriptor)
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

        private def execute_block_with_rescue(statements : Array(AST::Node), rescue_clauses : Array(AST::RescueClause))
            result = nil
            begin
                statements.each { |stmt| result = stmt.accept(self) }
                result

            rescue e : ReturnValue
                raise e

            rescue e : BreakSignal
                raise e

            rescue e : NextSignal
                raise e

            rescue e : InterpreterError
                clause = match_rescue_clause(e, rescue_clauses)

                if clause
                    clause_result = nil
                    clause.body.each { |stmt| clause_result = stmt.accept(self) }
                    clause_result

                else
                    raise e

                end
            end
        end

        private def match_rescue_clause(error : InterpreterError, rescue_clauses : Array(AST::RescueClause))
            return nil if rescue_clauses.empty?
            rescue_clauses.find do |clause|
                clause.exceptions.empty? || clause.exceptions.any? { |name| error.class.name.split("::").last == name }
            end
        end

        private def truthy?(value) : Bool
            !(value.nil? || value == false)
        end

        private def get_variable(name : String, location : Location? = nil)
            binding_info = find_binding_with_scope(name)
            return unwrap_binding(binding_info[:value]) if binding_info

            container_value = lookup_container_constant(name)
            return container_value unless container_value.nil?

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
            binding = find_binding(name)
            unwrap_binding(binding) if binding
        end

        private def lookup_container_constant(name : String)
            @container_stack.reverse_each do |container|
                return container.fetch_constant(name) if container.constant?(name)
            end
            nil
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
            end

            runtime_error(TypeError, "Expected #{descriptor.to_s}, got #{describe_runtime_value(value)}", node_or_location)
        end

        private def typing_context : Typing::Context
            @typing_context ||= Typing::Context.new(
                ->(name : String) { lookup_constant_value(name) },
                ->(constant : RuntimeValue, value : RuntimeValue) { constant_type_match?(constant, value) }
            )
        end

        private def constant_type_match?(constant : RuntimeValue, value : RuntimeValue)
            case constant
            when DragonClass
                value.is_a?(DragonInstance) && value.klass == constant
            when DragonModule
                value.is_a?(DragonModule) && value == constant
            when Function
                value.is_a?(Function) && value == constant
            else
                value == constant
            end
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
            else
                value.class.name
            end
        end

        private def new_type_scope : TypeScope
            {} of String => Typing::Descriptor
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

            when Array(RuntimeValue)
                "Array"

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

            when Range(Int64, Int64), Range(Float64, Float64), Range(Char, Char)
                "Range"

            else
                value.class.name

            end
        end

        private def format_value(value) : String
            case value

            when String
                value.inspect

            when Array(RuntimeValue)
                "[#{value.map { |v| format_value(v) }.join(", ")}]"

            when Nil
                "nil"

            when Bool
                value.to_s

            when FFIModule
                "ffi"

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
