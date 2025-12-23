module Dragonstone
    class Interpreter
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
                if left == right
                    true
                else
                    overload = invoke_operator_overload(left, :"==", right, node)
                    overload.nil? ? false : overload
                end

            when :!=
                if left != right
                    true
                else
                    overload = invoke_operator_overload(left, :"!=", right, node)
                    overload.nil? ? false : overload
                end

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

        private def operator_overload_name(operator : Symbol) : String
            case operator
            when :"&+" then "+"
            when :"&-" then "-"
            when :"&*" then "*"
            when :"&**" then "**"
            else
                operator.to_s
            end
        end

        private def invoke_operator_overload(left, operator : Symbol, right, node : AST::Node) : RuntimeValue?
            return nil unless supports_custom_methods?(left)

            method_name = operator_overload_name(operator)
            args = [right.as(RuntimeValue)] of RuntimeValue

            case left
            when DragonInstance
                method = left.klass.lookup_method(method_name)
                return nil unless method
                with_container(left.klass) do
                    return call_bound_method(left.klass, method.not_nil!, args, nil, node.location, self_object: left)
                end
            when DragonClass
                method = left.lookup_method(method_name)
                return nil unless method
                with_container(left) do
                    return call_bound_method(left, method.not_nil!, args, nil, node.location)
                end
            when DragonModule
                method = left.lookup_method(method_name)
                return nil unless method
                with_container(left) do
                    return call_bound_method(left, method.not_nil!, args, nil, node.location)
                end
            else
                nil
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
                overload = invoke_operator_overload(left, :+, right, node)
                return overload unless overload.nil?
                runtime_error(TypeError, "Unsupported operands for +", node)

            end
        end

        private def subtract_values(left, right, node : AST::Node)
            overload = invoke_operator_overload(left, :-, right, node)
            return overload unless overload.nil?

            lnum, rnum = numeric_pair(left, right, node)
            numeric_subtract(lnum, rnum)
        end

        private def multiply_values(left, right, node : AST::Node)
            overload = invoke_operator_overload(left, :*, right, node)
            return overload unless overload.nil?

            lnum, rnum = numeric_pair(left, right, node)
            numeric_multiply(lnum, rnum)
        end

        private def divide_values(left, right, node : AST::Node)
            overload = invoke_operator_overload(left, :/, right, node)
            return overload unless overload.nil?

            lnum, rnum = numeric_pair(left, right, node)

            if rnum == 0 || rnum == 0.0
                runtime_error(InterpreterError, "divided by 0", node)
            end

            numeric_divide(lnum, rnum)
        end

        private def modulo_values(left, right, node : AST::Node)
            overload = invoke_operator_overload(left, :%, right, node)
            return overload unless overload.nil?

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
            overload = invoke_operator_overload(left, :"**", right, node)
            return overload unless overload.nil?

            lnum, rnum = numeric_pair(left, right, node)
            if lnum.is_a?(Float64) || rnum.is_a?(Float64)
                lnum.to_f64 ** rnum.to_f64
            else
                base = lnum.to_i64
                exp = rnum.to_i64
                return base.to_f64 ** exp.to_f64 if exp < 0

                result = 1_i64
                factor = base
                power = exp
                while power > 0
                    result *= factor if (power & 1) == 1
                    power >>= 1
                    break if power == 0
                    factor *= factor
                end
                result
            end
        end

        private def bitwise_values(left, operator : Symbol, right, node : AST::Node)
            overload = invoke_operator_overload(left, operator, right, node)
            return overload unless overload.nil?

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
            overload = invoke_operator_overload(left, operator, right, node)
            return overload unless overload.nil?

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
            overload = invoke_operator_overload(left, :"//", right, node)
            return overload unless overload.nil?

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

            when "eecho"
                if block_value
                    runtime_error(InterpreterError, "eecho does not accept a block", node)
                end
                values = arg_nodes.map { |arg| arg.accept(self) }
                append_output_inline(values.map { |v| display_value(v) }.join(" "))
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
            receiver = receiver.value if receiver.is_a?(ConstantBinding)
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

            if singleton_info = lookup_singleton_method(receiver, node.name)
                method = singleton_info[:method]
                owner = singleton_info[:owner]
                ensure_method_visible!(receiver, method, node, implicit_self)
                with_singleton_container(owner) do
                    return call_bound_method(owner, method, args, block_value, node.location, self_object: receiver)
                end
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

            when Runtime::GC::Host
                if block_value && node.name != "with_disabled"
                    runtime_error(InterpreterError, "gc.#{node.name} does not accept a block", node)
                end
                call_gc_dispatch(receiver, node.name, args, block_value, node)

            when BuiltinStream
                if block_value
                    runtime_error(InterpreterError, "#{node.name} does not accept a block", node)
                end

                case node.name
                when "echoln"
                    append_output(args.map { |v| display_value(v) }.join(" "))
                    nil
                when "eecholn"
                    append_output_inline(args.map { |v| display_value(v) }.join(" "))
                    nil
                when "debug"
                    if args.size != 1
                        runtime_error(InterpreterError, "debug expects 1 argument, got #{args.size}", node)
                    end
                    append_output(display_value(args[0]))
                    args[0]
                when "debug_inline"
                    if args.size != 1
                        runtime_error(InterpreterError, "debug_inline expects 1 argument, got #{args.size}", node)
                    end
                    append_output_inline(display_value(args[0]))
                    args[0]
                when "flush"
                    if args.size != 0
                        runtime_error(InterpreterError, "flush expects 0 arguments, got #{args.size}", node)
                    end
                    nil
                else
                    runtime_error(NameError, "Unknown method '#{node.name}' for builtin stream", node)
                end

            when BuiltinStdin
                if block_value
                    runtime_error(InterpreterError, "#{node.name} does not accept a block", node)
                end
                case node.name
                when "read"
                    if args.size != 0
                        runtime_error(InterpreterError, "read expects 0 arguments, got #{args.size}", node)
                    end
                    line = STDIN.gets
                    (line || "").chomp
                else
                    runtime_error(NameError, "Unknown method '#{node.name}' for stdin", node)
                end

            when BuiltinArgf
                if block_value
                    runtime_error(InterpreterError, "#{node.name} does not accept a block", node)
                end
                case node.name
                when "read"
                    if args.size != 0
                        runtime_error(InterpreterError, "read expects 0 arguments, got #{args.size}", node)
                    end
                    if argv.empty?
                        STDIN.gets_to_end
                    else
                        String.build do |io|
                            argv.each do |path|
                                begin
                                    io << File.read(path)
                                rescue e
                                    runtime_error(InterpreterError, "Failed to read '#{path}': #{e.message}", node)
                                end
                            end
                        end
                    end
                else
                    runtime_error(NameError, "Unknown method '#{node.name}' for argf", node)
                end

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
            return true if receiver.is_a?(DragonModule) || receiver.is_a?(DragonInstance)
            if identity = singleton_identity(receiver)
                @singleton_classes.has_key?(identity)
            else
                false
            end
        end

        private def lookup_singleton_method(receiver, name : String) : NamedTuple(method: MethodDefinition, owner: SingletonClass)?
            if identity = singleton_identity(receiver)
                if owner = @singleton_classes[identity]?
                    if method = owner.lookup_method(name)
                        return {method: method, owner: owner}
                    end
                end
            end
            nil
        end

        private def singleton_identity(value) : UInt64?
            case value
            when Nil
                nil
            when Bool
                nil
            when Int32
                nil
            when Int64
                nil
            when Float64
                nil
            when Char
                nil
            when SymbolValue
                nil
            when Range(Int64, Int64)
                nil
            when Range(Char, Char)
                nil
            when FFIModule
                nil
            else
                value.object_id
            end
        end

        private def singleton_class_for_value(value, node : AST::Node) : SingletonClass
            unless identity = singleton_identity(value)
                runtime_error(TypeError, "Cannot define singleton methods on #{describe_runtime_value(value)}", node)
            end
            parent_candidate = singleton_parent_for(value)
            owner = @singleton_classes.fetch(identity) do
                singleton = SingletonClass.new(identity, singleton_class_name(value, identity), parent_candidate)
                @singleton_classes[identity] = singleton
                singleton
            end
            if owner.parent.nil? && parent_candidate
                owner.parent = parent_candidate
            end
            owner
        end

        private def singleton_class_name(value, identity : UInt64) : String
            descriptor = describe_runtime_value(value)
            "#<Singleton:0x#{identity.to_s(16)} #{descriptor}>"
        end

        private def singleton_parent_for(value)
            case value
            when DragonInstance
                value.klass
            when DragonModule
                value
            else
                nil
            end
        end

        private def with_singleton_container(owner : SingletonClass)
            with_container(owner) do
                if parent = owner.parent
                    with_container(parent) { yield }
                else
                    yield
                end
            end
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

        private def call_gc_dispatch(host : Runtime::GC::Host, method : String, args : Array(RuntimeValue), block_value : Function?, node : AST::MethodCall) : RuntimeValue
            manager = host.manager
            case method
            when "disable"
                runtime_error(InterpreterError, "gc.disable does not take arguments", node) unless args.empty?
                manager.disable
                nil
            when "enable"
                runtime_error(InterpreterError, "gc.enable does not take arguments", node) unless args.empty?
                manager.enable
                nil
            when "with_disabled"
                runtime_error(InterpreterError, "gc.with_disabled requires a block", node) unless block_value
                runtime_error(InterpreterError, "gc.with_disabled does not take arguments", node) unless args.empty?
                manager.with_disabled do
                    call_function(block_value.not_nil!, [] of AST::Node, nil, node.location)
                end
            when "begin"
                runtime_error(InterpreterError, "gc.begin does not accept arguments", node) unless args.empty?
                manager.begin_area
            when "end"
                runtime_error(InterpreterError, "gc.end accepts at most 1 argument", node) if args.size > 1
                target = args.first?
                if target && !target.is_a?(Runtime::GC::Area(RuntimeValue))
                    runtime_error(TypeError, "gc.end expects an Area or no argument", node)
                end
                manager.end_area(target.as?(Runtime::GC::Area(RuntimeValue)))
                nil
            when "current_area"
                runtime_error(InterpreterError, "gc.current_area does not take arguments", node) unless args.empty?
                manager.current_area
            when "copy"
                runtime_error(InterpreterError, "gc.copy expects 1 argument", node) unless args.size == 1
                value = args.first
                unless value.is_a?(RuntimeValue)
                    runtime_error(TypeError, "gc.copy expects a value", node)
                end
                manager.copy(value.as(RuntimeValue))
            else
                runtime_error(NameError, "Unknown gc method: #{method}", node)
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
                keys = [] of RuntimeValue
                tuple.entries.each_key { |key| keys << key.as(RuntimeValue) }
                keys

            when "values"
                reject_block(block_value, "NamedTuple##{name}", node)
                unless args.empty?
                    runtime_error(InterpreterError, "NamedTuple##{name} does not take arguments", node)
                end
                result = [] of RuntimeValue
                tuple.entries.each_value { |value| result << value.as(RuntimeValue) }
                result

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

            when "empty", "empty?"
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

            when "select"
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
                        if truthy?(outcome[:value])
                            result << element.as(RuntimeValue)
                        end
                    end
                end
                result

            when "inject"
                unless block_value
                    runtime_error(InterpreterError, "Array##{name} requires a block", node)
                end
                unless args.size <= 1
                    runtime_error(InterpreterError, "Array##{name} expects 0 or 1 argument, got #{args.size}", node)
                end
                memo_initialized = args.size == 1
                memo : RuntimeValue? = memo_initialized ? args.first : nil
                if array.empty? && !memo_initialized
                    runtime_error(InterpreterError, "Array##{name} called on empty array with no initial value", node)
                end
                block = block_value.not_nil!
                run_enumeration_loop do
                    array.each do |element|
                        unless memo_initialized
                            memo = element.as(RuntimeValue)
                            memo_initialized = true
                            next
                        end
                        outcome = execute_loop_iteration(block, [memo.as(RuntimeValue), element.as(RuntimeValue)], node)
                        next if outcome[:state] == :next
                        memo = normalize_runtime_value(outcome[:value], node)
                    end
                end
                memo.as(RuntimeValue)

            when "until"
                unless block_value
                    runtime_error(InterpreterError, "Array##{name} requires a block", node)
                end
                unless args.empty?
                    runtime_error(InterpreterError, "Array##{name} does not take arguments", node)
                end
                block = block_value.not_nil!
                found : RuntimeValue = nil
                match_found = false
                run_enumeration_loop do
                    array.each do |element|
                        break if match_found
                        outcome = execute_loop_iteration(block, [element.as(RuntimeValue)], node)
                        next if outcome[:state] == :next
                        if truthy?(outcome[:value])
                            found = element.as(RuntimeValue)
                            match_found = true
                            break
                        end
                    end
                end
                found

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

            when "empty", "empty?"
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

        when "select"
            unless block_value
                runtime_error(InterpreterError, "Map##{name} requires a block", node)
            end
            unless args.empty?
                runtime_error(InterpreterError, "Map##{name} does not take arguments", node)
            end
            block = block_value.not_nil!
            result = MapValue.new
            run_enumeration_loop do
                map.each do |key, value|
                    outcome = execute_loop_iteration(block, [key.as(RuntimeValue), value.as(RuntimeValue)], node)
                    next if outcome[:state] == :next
                    if truthy?(outcome[:value])
                        result[key] = value
                    end
                end
            end
            result

        when "inject"
            unless block_value
                runtime_error(InterpreterError, "Map##{name} requires a block", node)
            end
            unless args.size <= 1
                runtime_error(InterpreterError, "Map##{name} expects 0 or 1 argument, got #{args.size}", node)
            end
            memo_initialized = args.size == 1
            memo : RuntimeValue? = memo_initialized ? args.first : nil
            if map.empty? && !memo_initialized
                runtime_error(InterpreterError, "Map##{name} called on empty map with no initial value", node)
            end
            block = block_value.not_nil!
            run_enumeration_loop do
                map.each do |key, value|
                    unless memo_initialized
                        memo = value.as(RuntimeValue)
                        memo_initialized = true
                        next
                    end
                    outcome = execute_loop_iteration(block, [memo.as(RuntimeValue), key.as(RuntimeValue), value.as(RuntimeValue)], node)
                    next if outcome[:state] == :next
                    memo = normalize_runtime_value(outcome[:value], node)
                end
            end
            memo.as(RuntimeValue)

        when "until"
            unless block_value
                runtime_error(InterpreterError, "Map##{name} requires a block", node)
            end
            unless args.empty?
                runtime_error(InterpreterError, "Map##{name} does not take arguments", node)
            end
            block = block_value.not_nil!
            found : RuntimeValue = nil
            match_found = false
            run_enumeration_loop do
                map.each do |key, value|
                    break if match_found
                    outcome = execute_loop_iteration(block, [key.as(RuntimeValue), value.as(RuntimeValue)], node)
                    next if outcome[:state] == :next
                    if truthy?(outcome[:value])
                        found = TupleValue.new([key.as(RuntimeValue), value.as(RuntimeValue)])
                        match_found = true
                        break
                    end
                end
            end
            found

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

            when "empty", "empty?"
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

            when "select"
                unless block_value
                    runtime_error(InterpreterError, "Bag##{name} requires a block", node)
                end
                unless args.empty?
                    runtime_error(InterpreterError, "Bag##{name} does not take arguments", node)
                end
                block = block_value.not_nil!
                result = BagValue.new(bag.element_descriptor)
                run_enumeration_loop do
                    bag.elements.each do |value|
                        outcome = execute_loop_iteration(block, [value], node)
                        next if outcome[:state] == :next
                        if truthy?(outcome[:value])
                            result.add(value)
                        end
                    end
                end
                result

            when "inject"
                unless block_value
                    runtime_error(InterpreterError, "Bag##{name} requires a block", node)
                end
                unless args.size <= 1
                    runtime_error(InterpreterError, "Bag##{name} expects 0 or 1 argument, got #{args.size}", node)
                end
                memo_initialized = args.size == 1
                memo : RuntimeValue? = memo_initialized ? args.first : nil
                if bag.elements.empty? && !memo_initialized
                    runtime_error(InterpreterError, "Bag##{name} called on empty bag with no initial value", node)
                end
                block = block_value.not_nil!
                run_enumeration_loop do
                    bag.elements.each do |value|
                        unless memo_initialized
                            memo = value
                            memo_initialized = true
                            next
                        end
                        outcome = execute_loop_iteration(block, [memo.as(RuntimeValue), value], node)
                        next if outcome[:state] == :next
                        memo = normalize_runtime_value(outcome[:value], node)
                    end
                end
                memo.as(RuntimeValue)

            when "until"
                unless block_value
                    runtime_error(InterpreterError, "Bag##{name} requires a block", node)
                end
                unless args.empty?
                    runtime_error(InterpreterError, "Bag##{name} does not take arguments", node)
                end
                block = block_value.not_nil!
                found : RuntimeValue = nil
                match_found = false
                run_enumeration_loop do
                    bag.elements.each do |value|
                        break if match_found
                        outcome = execute_loop_iteration(block, [value], node)
                        next if outcome[:state] == :next
                        if truthy?(outcome[:value])
                            found = value
                            match_found = true
                            break
                        end
                    end
                end
                found

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

            when "strip"
                reject_block(block_value, "String##{name}", node)
                string.strip

            when "reverse"
                reject_block(block_value, "String##{name}", node)
                string.reverse

            when "empty", "empty?"
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
    end
end
