# ---------------------------------
# ----------- Virtual -------------
# ----------- Machine -------------
# ---------------------------------
require "set"
require "../../shared/language/diagnostics/errors"
require "./bytecode"
require "../compiler/compiler"
require "./opc"
require "../../shared/runtime/ffi_module"
require "../../shared/ffi/ffi"
require "../../shared/language/ast/ast"

module Dragonstone
    class VM
        include OPC

        class BreakSignal < Exception; end
        class NextSignal < Exception; end
        class RedoSignal < Exception; end

        class Frame
            property code : CompiledCode
            property ip : Int32
            property stack_base : Int32
            property locals : Array(Bytecode::Value?)?
            property locals_defined : Array(Bool)?
            property block : Bytecode::BlockValue?
            property signature : Bytecode::FunctionSignature?
            property callable_name : String?

            def initialize(
                @code : CompiledCode,
                @stack_base : Int32,
                use_locals : Bool = false,
                block_value : Bytecode::BlockValue? = nil,
                signature : Bytecode::FunctionSignature? = nil,
                callable_name : String? = nil
            )
                @ip = 0
                if use_locals
                    size = @code.names.size
                    @locals = Array(Bytecode::Value?).new(size) { nil }
                    @locals_defined = Array(Bool).new(size) { false }
                else
                    @locals = nil
                    @locals_defined = nil
                end
                @block = block_value
                @signature = signature
                @callable_name = callable_name
            end
        end

        private def truthy?(value : Bytecode::Value) : Bool
            !(value.nil? || value == false)
        end

        private def define_type_alias(name : String, expr : AST::TypeExpression) : Nil
            @type_aliases[name] = expr
        end

        private def enforce_type(type_expr : AST::TypeExpression?, value : Bytecode::Value, context : String) : Nil
            return unless @typing_enabled
            return unless type_expr
            unless type_matches?(value, type_expr, Set(String).new)
                raise ::Dragonstone::TypeError.new("Type error in #{context}: expected #{type_expr.to_source}, got #{describe_value(value)}")
            end
        end

        private def type_matches?(value : Bytecode::Value, expr : AST::TypeExpression, seen_aliases : Set(String)) : Bool
            case expr
            when AST::SimpleTypeExpression
                simple_type_matches?(value, expr.name, seen_aliases)
            when AST::UnionTypeExpression
                expr.members.any? { |member| type_matches?(value, member, seen_aliases) }
            when AST::OptionalTypeExpression
                value.nil? || type_matches?(value, expr.inner, seen_aliases)
            when AST::GenericTypeExpression
                generic_type_matches?(value, expr, seen_aliases)
            else
                false
            end
        end

        private def simple_type_matches?(value : Bytecode::Value, name : String, seen_aliases : Set(String)) : Bool
            case name.downcase
            when "int"
                value.is_a?(Int32) || value.is_a?(Int64)
            when "str", "string"
                value.is_a?(String)
            when "bool"
                value.is_a?(Bool)
            when "float"
                value.is_a?(Float64)
            when "char"
                value.is_a?(Char)
            when "nil"
                value.nil?
            else
                if alias_expr = @type_aliases[name]?
                    return false if seen_aliases.includes?(name)
                    next_seen = seen_aliases.dup
                    next_seen.add(name)
                    type_matches?(value, alias_expr, next_seen)
                else
                    false
                end
            end
        end

        private def generic_type_matches?(value : Bytecode::Value, expr : AST::GenericTypeExpression, seen_aliases : Set(String)) : Bool
            name = expr.name.downcase
            case name
            when "array"
                return false unless value.is_a?(Array)
                element_type = expr.arguments.first?
                return true unless element_type
                value.all? { |element| type_matches?(element, element_type, seen_aliases) }
            when "bag"
                return false unless value.is_a?(Bytecode::BagValue)
                element_type = expr.arguments.first?
                return true unless element_type
                value.elements.all? { |element| type_matches?(element, element_type, seen_aliases) }
            when "para"
                return false unless value.is_a?(Bytecode::FunctionValue)
                param_types = expr.arguments[0...-1]
                return true if param_types.empty?
                value.signature.parameters.size == param_types.size
            else
                false
            end
        end

        private def describe_value(value : Bytecode::Value) : String
            type_of(value)
        end

        private def call_bag_constructor_method(
            constructor : Bytecode::BagConstructorValue,
            method : String,
            args : Array(Bytecode::Value),
            block_value : Bytecode::BlockValue?
        ) : Bytecode::Value
            raise ArgumentError.new("Bag constructor methods do not accept blocks") if block_value

            case method
            when "new"
                unless args.empty?
                    raise ArgumentError.new("bag(...)::new does not take arguments")
                end
                Bytecode::BagValue.new(constructor.element_type)
            else
                raise "Unknown method '#{method}' for bag constructor"
            end
        end

        private def call_bag_method(
            bag : Bytecode::BagValue,
            method : String,
            args : Array(Bytecode::Value),
            block_value : Bytecode::BlockValue?
        ) : Bytecode::Value
            case method
            when "length", "size"
                raise ArgumentError.new("Bag##{method} does not take arguments") unless args.empty?
                raise ArgumentError.new("Bag##{method} does not accept a block") if block_value
                bag.size
            when "empty"
                raise ArgumentError.new("Bag##{method} does not take arguments") unless args.empty?
                raise ArgumentError.new("Bag##{method} does not accept a block") if block_value
                bag.elements.empty?
            when "add"
                raise ArgumentError.new("Bag##{method} expects 1 argument") unless args.size == 1
                raise ArgumentError.new("Bag##{method} does not accept a block") if block_value
                value = args.first
                enforce_type(bag.element_type, value, "Bag##{method}")
                bag.add(value)
            when "includes?", "member?", "contains?"
                raise ArgumentError.new("Bag##{method} expects 1 argument") unless args.size == 1
                raise ArgumentError.new("Bag##{method} does not accept a block") if block_value
                value = args.first
                enforce_type(bag.element_type, value, "Bag##{method}")
                bag.includes?(value)
            when "each"
                block = ensure_block(block_value, "Bag##{method}")
                raise ArgumentError.new("Bag##{method} does not take arguments") unless args.empty?
                run_enumeration_loop do
                    bag.elements.each do |value|
                        outcome = execute_block_iteration(block, [value])
                        next if outcome[:state] == :next
                    end
                end
                bag
            when "map"
                block = ensure_block(block_value, "Bag##{method}")
                raise ArgumentError.new("Bag##{method} does not take arguments") unless args.empty?
                result = [] of Bytecode::Value
                run_enumeration_loop do
                    bag.elements.each do |value|
                        outcome = execute_block_iteration(block, [value])
                        next if outcome[:state] == :next
                        result << (outcome[:value].nil? ? nil : outcome[:value])
                    end
                end
                result
            when "select"
                block = ensure_block(block_value, "Bag##{method}")
                raise ArgumentError.new("Bag##{method} does not take arguments") unless args.empty?
                result = Bytecode::BagValue.new(bag.element_type)
                run_enumeration_loop do
                    bag.elements.each do |value|
                        outcome = execute_block_iteration(block, [value])
                        next if outcome[:state] == :next
                        result.add(value) if truthy?(outcome[:value])
                    end
                end
                result
            when "inject"
                block = ensure_block(block_value, "Bag##{method}")
                unless args.size <= 1
                    raise ArgumentError.new("Bag##{method} expects 0 or 1 argument, got #{args.size}")
                end
                memo_initialized = args.size == 1
                memo : Bytecode::Value? = memo_initialized ? args.first : nil
                if bag.elements.empty? && !memo_initialized
                    raise ArgumentError.new("Bag##{method} called on empty bag with no initial value")
                end
                    run_enumeration_loop do
                        bag.elements.each do |value|
                            unless memo_initialized
                                memo = value
                                memo_initialized = true
                                next
                            end
                            outcome = execute_block_iteration(block, [memo.as(Bytecode::Value), value])
                            next if outcome[:state] == :next
                            memo = outcome[:value]
                        end
                    end
                    memo
            when "until"
                block = ensure_block(block_value, "Bag##{method}")
                raise ArgumentError.new("Bag##{method} does not take arguments") unless args.empty?
                found : Bytecode::Value? = nil
                run_enumeration_loop do
                    bag.elements.each do |value|
                        outcome = execute_block_iteration(block, [value])
                        next if outcome[:state] == :next
                        if truthy?(outcome[:value])
                            found = value
                            raise BreakSignal.new
                        end
                    end
                end
                found
            when "to_a"
                raise ArgumentError.new("Bag##{method} does not accept a block") if block_value
                raise ArgumentError.new("Bag##{method} does not take arguments") unless args.empty?
                bag.elements.dup
            else
                raise "Unknown method '#{method}' for Bag"
            end
        end

        private def ensure_arity(signature : Bytecode::FunctionSignature, provided : Int32, name : String) : Nil
            expected = signature.parameters.size
            return if expected == provided
            raise "Function #{name} expects #{expected} arguments, got #{provided}"
        end

        private def yield_to_block(args : Array(Bytecode::Value)) : Bytecode::Value
            frame = current_frame
            block = frame.block
            raise "No block given" unless block
            ensure_arity(block.signature, args.size, "yield")
            depth_before = @frames.size
            push_callable_frame(block.code, block.signature, args, nil, "<block>")
            execute_with_frame_cleanup(depth_before)
        end

        private def call_block(block_value : Bytecode::BlockValue, args : Array(Bytecode::Value)) : Bytecode::Value
            ensure_arity(block_value.signature, args.size, "<block>")
            depth_before = @frames.size
            push_callable_frame(block_value.code, block_value.signature, args, nil, "<block>")
            execute_with_frame_cleanup(depth_before)
        end

        private def ensure_block(block_value : Bytecode::BlockValue?, feature : String) : Bytecode::BlockValue
            raise ArgumentError.new("#{feature} requires a block") unless block_value
            block_value
        end

        private def execute_block_iteration(block_value : Bytecode::BlockValue, args : Array(Bytecode::Value)) : NamedTuple(state: Symbol, value: Bytecode::Value?)
            loop do
                begin
                    value = call_block(block_value, args)
                    pop
                    return {state: :yielded, value: value}
                rescue NextSignal
                    return {state: :next, value: nil}
                rescue RedoSignal
                    next
                end
            end
        end

        private def run_enumeration_loop(&block)
            with_loop_context do
                begin
                    yield
                rescue BreakSignal
                end
            end
        end

        private def with_loop_context(&block)
            @loop_depth += 1
            yield
        ensure
            @loop_depth -= 1
        end

        private def define_type_alias(name : String, expr : AST::TypeExpression) : Nil
            @type_aliases[name] = expr
        end

        private def enforce_type(type_expr : AST::TypeExpression?, value : Bytecode::Value, context : String) : Nil
            return unless @typing_enabled
            return unless type_expr
            unless type_matches?(value, type_expr, Set(String).new)
                raise ::Dragonstone::TypeError.new("Type error in #{context}: expected #{type_expr.to_source}, got #{describe_value(value)}")
            end
        end

        private def type_matches?(value : Bytecode::Value, expr : AST::TypeExpression, seen_aliases : Set(String)) : Bool
            case expr
            when AST::SimpleTypeExpression
                simple_type_matches?(value, expr.name, seen_aliases)
            when AST::UnionTypeExpression
                expr.members.any? { |member| type_matches?(value, member, seen_aliases) }
            when AST::OptionalTypeExpression
                value.nil? || type_matches?(value, expr.inner, seen_aliases)
            when AST::GenericTypeExpression
                generic_type_matches?(value, expr, seen_aliases)
            else
                false
            end
        end

        private def simple_type_matches?(value : Bytecode::Value, name : String, seen_aliases : Set(String)) : Bool
            case name.downcase
            when "int"
                value.is_a?(Int32) || value.is_a?(Int64)
            when "str", "string"
                value.is_a?(String)
            when "bool"
                value.is_a?(Bool)
            when "float"
                value.is_a?(Float64)
            when "char"
                value.is_a?(Char)
            when "nil"
                value.nil?
            else
                if alias_expr = @type_aliases[name]?
                    return false if seen_aliases.includes?(name)
                    next_seen = seen_aliases.dup
                    next_seen.add(name)
                    type_matches?(value, alias_expr, next_seen)
                else
                    false
                end
            end
        end

        private def generic_type_matches?(value : Bytecode::Value, expr : AST::GenericTypeExpression, seen_aliases : Set(String)) : Bool
            name = expr.name.downcase
            case name
            when "array"
                return false unless value.is_a?(Array)
                element_type = expr.arguments.first?
                return true unless element_type
                value.all? { |element| type_matches?(element, element_type, seen_aliases) }
            when "bag"
                return false unless value.is_a?(Bytecode::BagValue)
                element_type = expr.arguments.first?
                return true unless element_type
                value.elements.all? { |element| type_matches?(element, element_type, seen_aliases) }
            when "para"
                return false unless value.is_a?(Bytecode::FunctionValue)
                param_types = expr.arguments[0...-1]
                return true if param_types.empty?
                value.signature.parameters.size == param_types.size
            else
                false
            end
        end

        private def describe_value(value : Bytecode::Value) : String
            type_of(value)
        end

        @bytecode : CompiledCode
        @stack : Array(Bytecode::Value)
        @globals : Hash(String, Bytecode::Value)
        @stdout_io : IO
        @log_to_stdout : Bool
        @frames : Array(Frame)
        @loop_depth : Int32
        @global_slots : Array(Bytecode::Value?)
        @global_defined : Array(Bool)
        @name_index_cache : Hash(String, Int32)
        @globals_dirty : Bool

        def initialize(
            @bytecode : CompiledCode,
            globals : Hash(String, Bytecode::Value)? = nil,
            *,
            stdout_io : IO = IO::Memory.new,
            log_to_stdout : Bool = false,
            typing_enabled : Bool = false
        )
            @stack = [] of Bytecode::Value
            @globals = globals ? globals.dup : {} of String => Bytecode::Value
            @stdout_io = stdout_io
            @log_to_stdout = log_to_stdout
            @frames = [] of Frame
            @loop_depth = 0
            @global_slots = Array(Bytecode::Value?).new(@bytecode.names.size) { nil }
            @global_defined = Array(Bool).new(@bytecode.names.size) { false }
            @name_index_cache = {} of String => Int32
            @bytecode.names.each_with_index do |name, idx|
                @name_index_cache[name] = idx
            end
            @globals_dirty = false
            @typing_enabled = typing_enabled
            @type_aliases = {} of String => AST::TypeExpression

            # Initialize FFI
            init_ffi_module
            sync_globals_slots
        end

        private def init_ffi_module
            @globals["ffi"] ||= FFIModule.new
            if idx = @name_index_cache["ffi"]?
                ensure_global_capacity(idx)
                @global_slots[idx] = @globals["ffi"]
                @global_defined[idx] = true
            end
        end

        private def ensure_global_capacity(index : Int32)
            if index >= @global_slots.size
                new_size = index + 1
                (@global_slots.size...new_size).each do
                    @global_slots << nil
                    @global_defined << false
                end
            end
        end

        private def rebuild_globals_map : Nil
            fresh = {} of String => Bytecode::Value
            @globals.each do |name, value|
                fresh[name] = value if @name_index_cache[name]?.nil?
            end

            @name_index_cache.each do |name, idx|
                next unless idx < @global_defined.size && @global_defined[idx]
                value = @global_slots[idx]?
                fresh[name] = value.nil? ? nil : value
            end

            @globals = fresh
            @globals_dirty = false
        end

        private def sync_globals_slots
            @globals.each do |name, value|
                if idx = @name_index_cache[name]?
                    ensure_global_capacity(idx)
                    @global_slots[idx] = value
                    @global_defined[idx] = true
                end
            end
            @globals_dirty = false
        end

        def export_globals : Hash(String, Bytecode::Value)
            rebuild_globals_map if @globals_dirty
            @globals.dup
        end

        def run : Bytecode::Value
            reset_for_run
            execute
        end

        private def execute(target_depth : Int32? = nil) : Bytecode::Value
            loop do
                opcode = fetch_byte

                case opcode
                when OPC::HALT
                    return @stack.empty? ? nil : pop
                when OPC::NOP
                    # nil
                when OPC::CONST
                    idx = fetch_byte
                    push(current_code.consts[idx])
                when OPC::LOAD
                    name_idx = fetch_byte
                    name = current_code.names[name_idx]
                    push(resolve_variable(name_idx, name))
                when OPC::STORE
                    name_idx = fetch_byte
                    name = current_code.names[name_idx]
                    if @stack.empty?
                        STDERR.puts "STORE stack empty for #{name} ip=#{current_frame.ip}"
                    end
                    value = peek
                    store_variable(name_idx, name, value)
                when OPC::POP
                    pop
                when OPC::DUP
                    push(peek)
                when OPC::ADD
                    b, a = pop, pop
                    push(add(a, b))
                when OPC::SUB
                    b, a = pop, pop
                    push(sub(a, b))
                when OPC::MUL
                    b, a = pop, pop
                    push(mul(a, b))
                when OPC::DIV
                    b, a = pop, pop
                    push(div(a, b))
                when OPC::NEG
                    value = pop
                    push(negate_value(value))
                when OPC::POS
                    value = pop
                    push(unary_positive(value))
                when OPC::EQ
                    b, a = pop, pop
                    push(a == b)
                when OPC::NE
                    b, a = pop, pop
                    push(a != b)
                when OPC::LT
                    b, a = pop, pop
                    push(compare_lt(a, b))
                when OPC::LE
                    b, a = pop, pop
                    push(compare_le(a, b))
                when OPC::GT
                    b, a = pop, pop
                    push(compare_gt(a, b))
                when OPC::GE
                    b, a = pop, pop
                    push(compare_ge(a, b))
                when OPC::JMP
                    target = fetch_byte
                    current_frame.ip = target
                when OPC::JMPF
                    target = fetch_byte
                    condition = pop
                    current_frame.ip = target unless truthy?(condition)
                when OPC::NOT
                    value = pop
                    push(logical_not(value))
                when OPC::BIT_NOT
                    value = pop
                    push(bitwise_not(value))
                when OPC::ECHO
                    argc = fetch_byte
                    args = pop_values(argc)
                    line = args.map { |arg| arg.nil? ? "" : stringify(arg) }.join(" ")
                    emit_output(line)
                    push(nil)
                when OPC::TYPEOF
                    value = pop
                    push(type_of(value))
                when OPC::DEBUG_PRINT
                    source_idx = fetch_byte
                    source = current_code.consts[source_idx].to_s
                    value = pop
                    emit_output("#{source} # => #{stringify(value)}")
                    push(value)
                when OPC::CONCAT
                    b, a = pop, pop
                    push(stringify(a) + stringify(b))
                when OPC::TO_S
                    value = pop
                    push(stringify(value))
                when OPC::MAKE_ARRAY
                    count = fetch_byte
                    elements = pop_values(count)
                    push(elements)
                when OPC::INDEX
                    index, obj = pop, pop
                    push(index_access(obj, index))
                when OPC::INVOKE
                    name_idx = fetch_byte
                    argc = fetch_byte
                    args = pop_values(argc)
                    receiver = pop
                    result = invoke_method(receiver, current_code.names[name_idx], args, nil)
                    push(result)
                when OPC::INVOKE_BLOCK
                    name_idx = fetch_byte
                    argc = fetch_byte
                    block_value = pop_block
                    args = pop_values(argc)
                    receiver = pop
                    result = invoke_method(receiver, current_code.names[name_idx], args, block_value)
                    push(result)
                when OPC::CALL
                    argc = fetch_byte
                    name_idx = fetch_byte
                    args = pop_values(argc)
                    prepare_function_call(name_idx, args, nil)
                when OPC::CALL_BLOCK
                    argc = fetch_byte
                    name_idx = fetch_byte
                    block_value = pop_block
                    args = pop_values(argc)
                    prepare_function_call(name_idx, args, block_value)
                when OPC::MAKE_FUNCTION
                    name_idx = fetch_byte
                    signature_idx = fetch_byte
                    code_idx = fetch_byte
                    name = current_code.names[name_idx]
                    signature = current_code.consts[signature_idx].as(Bytecode::FunctionSignature)
                    code = current_code.consts[code_idx].as(CompiledCode)
                    push(Bytecode::FunctionValue.new(name, signature, code))
                when OPC::MAKE_BLOCK
                    signature_idx = fetch_byte
                    code_idx = fetch_byte
                    signature = current_code.consts[signature_idx].as(Bytecode::FunctionSignature)
                    code = current_code.consts[code_idx].as(CompiledCode)
                    push(Bytecode::BlockValue.new(signature, code))
                when OPC::YIELD
                    argc = fetch_byte
                    args = pop_values(argc)
                    result = yield_to_block(args)
                    push(result)
                when OPC::BREAK_SIGNAL
                    raise BreakSignal.new
                when OPC::NEXT_SIGNAL
                    raise NextSignal.new
                when OPC::REDO_SIGNAL
                    raise RedoSignal.new
                when OPC::DEFINE_TYPE_ALIAS
                    name_idx = fetch_byte
                    type_idx = fetch_byte
                    type_expr = current_code.consts[type_idx].as(AST::TypeExpression)
                    define_type_alias(current_code.names[name_idx], type_expr)
                when OPC::CHECK_TYPE
                    type_idx = fetch_byte
                    value = pop
                    type_expr = current_code.consts[type_idx].as(AST::TypeExpression)
                    enforce_type(type_expr, value, "assignment")
                    push(value)
                when OPC::RET
                    result = handle_return
                    return result if target_depth && @frames.size == target_depth
                else
                    raise "Unknown opcode: #{opcode}"
                end
            end
        end

        private def fetch_byte : Int32
            frame = current_frame
            byte = frame.code.code[frame.ip]
            frame.ip += 1
            byte
        end

        private def reset_for_run : Nil
            @stack.clear
            @frames.clear
            push_frame(@bytecode, false)
            init_ffi_module
            sync_globals_slots
            @type_aliases.clear
        end

        private def current_frame : Frame
            @frames.last? || raise "VM frame stack is empty"
        end

        private def current_code : CompiledCode
            current_frame.code
        end

        private def truncate_stack(size : Int32) : Nil
            while @stack.size > size
                @stack.pop
            end
        end

        private def resolve_variable(name_idx : Int32, name : String) : Bytecode::Value
            frame = current_frame
            if locals = frame.locals
                if defined = frame.locals_defined
                    if name_idx < locals.size && defined[name_idx]
                        slot = locals[name_idx]?
                        return slot.nil? ? nil : slot
                    end
                end
            end

            if idx = @name_index_cache[name]?
                ensure_global_capacity(idx)
                if @global_defined[idx]
                    slot = @global_slots[idx]?
                    return slot.nil? ? nil : slot
                end
            end

            if value = @globals[name]?
                if idx = @name_index_cache[name]?
                    ensure_global_capacity(idx)
                    @global_slots[idx] = value
                    @global_defined[idx] = true
                end
                return value
            end
            raise "Undefined variable: #{name}"
        end

        private def store_variable(name_idx : Int32, name : String, value : Bytecode::Value) : Nil
            frame = current_frame
            locals = frame.locals
            defined = frame.locals_defined

            if locals && defined && name_idx < defined.size && defined[name_idx]
                assign_local(frame, name_idx, value)
                return
            end

            if should_store_global?(name)
                assign_global(name, value)
            elsif locals
                assign_local(frame, name_idx, value)
            else
                assign_global(name, value)
            end
        end

        private def assign_global(name : String, value : Bytecode::Value) : Nil
            if idx = @name_index_cache[name]?
                ensure_global_capacity(idx)
                @global_slots[idx] = value
                @global_defined[idx] = true
                @globals_dirty = true
            else
                @globals[name] = value
            end
        end

        private def should_store_global?(name : String) : Bool
            if idx = @name_index_cache[name]?
                ensure_global_capacity(idx)
                return true if @global_defined[idx]
            end
            @globals.has_key?(name)
        end

        private def prepare_function_call(name_idx : Int32, args : Array(Bytecode::Value), block_value : Bytecode::BlockValue?) : Nil
            name = current_code.names[name_idx]
            value = resolve_variable(name_idx, name)
            unless value.is_a?(Bytecode::FunctionValue)
                raise "Undefined function: #{name}"
            end

            signature = value.signature
            ensure_arity(signature, args.size, name)
            frame = push_callable_frame(value.code, signature, args, block_value, name)
            frame.block = block_value
        end

        private def push_frame(
            code : CompiledCode,
            use_locals : Bool,
            block_value : Bytecode::BlockValue? = nil,
            signature : Bytecode::FunctionSignature? = nil,
            callable_name : String? = nil
        ) : Frame
            frame = Frame.new(code, @stack.size, use_locals, block_value, signature, callable_name)
            @frames << frame
            frame
        end

        private def push_callable_frame(
            code : CompiledCode,
            signature : Bytecode::FunctionSignature,
            args : Array(Bytecode::Value),
            block_value : Bytecode::BlockValue?,
            callable_name : String? = nil
        ) : Frame
            frame = push_frame(code, true, block_value, signature, callable_name)
            signature.parameters.each_with_index do |param, index|
                value = args[index]
                enforce_type(param.type_expression, value, "parameter #{index + 1}")
                assign_local(frame, param.name_index, value)
            end
            frame
        end

        private def execute_with_frame_cleanup(depth_before : Int32) : Bytecode::Value
            execute(target_depth: depth_before)
        rescue ex
            cleanup_frames_from(depth_before)
            raise ex
        end

        private def cleanup_frames_from(depth_before : Int32) : Nil
            while @frames.size > depth_before
                frame = @frames.pop
                truncate_stack(frame.stack_base)
            end
        end

        private def ensure_local_capacity(frame : Frame, index : Int32) : Nil
            return unless locals = frame.locals
            return unless defined = frame.locals_defined

            if index >= locals.size
                new_size = index + 1
                (locals.size...new_size).each do
                    locals << nil
                    defined << false
                end
            end
        end

        private def assign_local(frame : Frame, index : Int32, value : Bytecode::Value) : Nil
            ensure_local_capacity(frame, index)
            if locals = frame.locals
                locals[index] = value
            end
            if defined = frame.locals_defined
                defined[index] = true
            end
        end

        private def handle_return : Bytecode::Value
            result = pop
            frame = @frames.pop?
            raise "Return from empty frame stack" unless frame
            if @frames.empty?
                raise "Return from top-level frame not supported"
            end
            if signature = frame.signature
                enforce_type(signature.return_type, result, "return from #{frame.callable_name || "<lambda>"}")
            end
            truncate_stack(frame.stack_base)
            push(result)
            result
        end
        
        private def push(value : Bytecode::Value)
            @stack << value
        end
        
        private def pop : Bytecode::Value
            raise "Stack underflow" if @stack.empty?
            @stack.pop
        end
        
        private def peek : Bytecode::Value
            raise "Stack empty" if @stack.empty?
            @stack.last
        end

        private def pop_values(count : Int32) : Array(Bytecode::Value)
            values = [] of Bytecode::Value
            count.times { values << pop }
            values.reverse!
            values
        end

        private def pop_block : Bytecode::BlockValue
            value = pop
            unless value.is_a?(Bytecode::BlockValue)
                raise "Expected block literal, got #{type_of(value)}"
            end
            value
        end

        private def emit_output(text : String) : Nil
            @stdout_io << text
            @stdout_io << "\n"
            puts text if @log_to_stdout
        end

        private def add(a : Bytecode::Value, b : Bytecode::Value) : Bytecode::Value
            case a

            when Int32
                case b

                when Int32 then a + b
                when Int64 then a + b
                when Float64 then a + b

                else raise "Cannot add #{type_of(a)} and #{type_of(b)}"

                end
            when Int64
                case b

                when Int32, Int64, Float64 then a + b

                else raise "Cannot add #{type_of(a)} and #{type_of(b)}"

                end
            when Float64
                case b

                when Int32, Int64, Float64 then a + b

                else raise "Cannot add #{type_of(a)} and #{type_of(b)}"

                end
            when String
                stringify(a) + stringify(b)

            else
                raise "Cannot add #{type_of(a)} and #{type_of(b)}"

            end
        end
        
        private def sub(a, b)
            numeric_op(a, b) { |x, y| x - y }
        end
        
        private def mul(a, b)
            numeric_op(a, b) { |x, y| x * y }
        end
        
        private def div(a, b)
            numeric_op(a, b) { |x, y| x / y }
        end
        
        private def numeric_op(a, b, &block)
            case a

            when Int32, Int64, Float64
                case b

                when Int32, Int64, Float64
                    yield a, b

                else
                    raise "Type error"

                end
            else
                raise "Type error"

            end
        end
        
        private def compare_lt(a, b)
            numeric_compare(a, b) { |x, y| x < y }
        end
        
        private def compare_le(a, b)
            numeric_compare(a, b) { |x, y| x <= y }
        end
        
        private def compare_gt(a, b)
            numeric_compare(a, b) { |x, y| x > y }
        end
        
        private def compare_ge(a, b)
            numeric_compare(a, b) { |x, y| x >= y }
        end
        
        private def numeric_compare(a, b, &block)
            case a

            when Int32, Int64, Float64
                case b

                when Int32, Int64, Float64
                    yield a, b

                else
                    false

                end
            else
                false

            end
        end

        private def coerce_unary_numeric(value : Bytecode::Value, op : String) : Int64 | Float64
            case value
            when Int64
                value
            when Int32
                value.to_i64
            when Float64
                value
            else
                raise "Cannot apply #{op} to #{type_of(value)}"
            end
        end

        private def coerce_unary_integer(value : Bytecode::Value, op : String) : Int64
            case value
            when Int64
                value
            when Int32
                value.to_i64
            else
                raise "Cannot apply #{op} to #{type_of(value)}"
            end
        end

        private def unary_positive(value : Bytecode::Value) : Bytecode::Value
            coerce_unary_numeric(value, "unary +")
        end

        private def negate_value(value : Bytecode::Value) : Bytecode::Value
            numeric = coerce_unary_numeric(value, "unary -")
            numeric.is_a?(Float64) ? -numeric : -numeric.to_i64
        end

        private def logical_not(value : Bytecode::Value) : Bool
            !truthy?(value)
        end

        private def bitwise_not(value : Bytecode::Value) : Bytecode::Value
            integer = coerce_unary_integer(value, "unary ~")
            ~integer
        end
        
        private def truthy?(value : Bytecode::Value) : Bool
            case value
            when Nil then false
            when Bool then value
            else true
            end
        end
        
        private def stringify(value : Bytecode::Value) : String
            case value
            when Nil then "nil"
            when Bool then value.to_s
            when Int32, Int64, Float64 then value.to_s
            when String then value
            when Array then "[#{value.map { |v| stringify(v) }.join(", ")}]"
            when FFIModule then "ffi"
            else value.to_s
            end
        end
        
        private def type_of(value : Bytecode::Value) : String
            case value
            when Nil then "Nil"
            when Bool then "Bool"
            when Int32, Int64 then "Int"
            when Float64 then "Float"
            when String then "String"
            when Array then "Array"
            when Bytecode::FunctionValue then "Function"
            when Bytecode::BlockValue then "Block"
            when FFIModule then "FFIModule"
            else "Object"
            end
        end
        
        private def index_access(obj : Bytecode::Value, index : Bytecode::Value) : Bytecode::Value
            case obj

            when Array
                case index

                when Int32, Int64
                    obj[index.to_i]? || nil
                else
                    raise "Array index must be integer"
                end

            when String
                case index

                when Int32, Int64
                    char = obj[index.to_i]?
                    char ? char.to_s : nil
                else
                    raise "String index must be integer"
                end
            else
                raise "Cannot index #{type_of(obj)}"
            end
        end
        
        private def invoke_method(receiver : Bytecode::Value, method : String, args : Array(Bytecode::Value), block_value : Bytecode::BlockValue?) : Bytecode::Value
            
            # Checks if its FFI.
            if receiver.is_a?(FFIModule)
                return call_ffi_method(method, args)
            end

            case receiver

            when String
                case method
                when "upcase"
                    raise ArgumentError.new("String##{method} does not accept a block") if block_value
                    receiver.upcase
                when "downcase"
                    raise ArgumentError.new("String##{method} does not accept a block") if block_value
                    receiver.downcase
                when "length", "size"
                    raise ArgumentError.new("String##{method} does not accept a block") if block_value
                    receiver.size.to_i64
                else raise "Unknown method #{method} on String"
                end
            when Array
                array = receiver.as(Array(Bytecode::Value))
                case method
                when "length", "size"
                    raise ArgumentError.new("Array##{method} does not accept a block") if block_value
                    array.size.to_i64
                when "first"
                    raise ArgumentError.new("Array##{method} does not accept a block") if block_value
                    array.first?
                when "last"
                    raise ArgumentError.new("Array##{method} does not accept a block") if block_value
                    array.last?
                when "push"
                    raise ArgumentError.new("Array##{method} does not accept a block") if block_value
                    array << args[0]
                    array
                when "each"
                    block = ensure_block(block_value, "Array##{method}")
                    run_enumeration_loop do
                        array.each do |element|
                            outcome = execute_block_iteration(block, [element])
                            next if outcome[:state] == :next
                        end
                    end
                    array
                when "map"
                    block = ensure_block(block_value, "Array##{method}")
                    result = [] of Bytecode::Value
                    run_enumeration_loop do
                        array.each do |element|
                            outcome = execute_block_iteration(block, [element])
                            next if outcome[:state] == :next
                            result << (outcome[:value].nil? ? nil : outcome[:value])
                        end
                    end
                    result
                when "select"
                    block = ensure_block(block_value, "Array##{method}")
                    result = [] of Bytecode::Value
                    run_enumeration_loop do
                        array.each do |element|
                            outcome = execute_block_iteration(block, [element])
                            next if outcome[:state] == :next
                            if truthy?(outcome[:value])
                                result << element
                            end
                        end
                    end
                    result
                when "inject"
                    block = ensure_block(block_value, "Array##{method}")
                    unless args.size <= 1
                        raise ArgumentError.new("Array##{method} expects 0 or 1 argument, got #{args.size}")
                    end
                    memo_initialized = args.size == 1
                    memo : Bytecode::Value? = memo_initialized ? args.first : nil
                    if array.empty? && !memo_initialized
                        raise ArgumentError.new("Array##{method} called on empty array with no initial value")
                    end
                    run_enumeration_loop do
                        array.each do |element|
                            unless memo_initialized
                                memo = element
                                memo_initialized = true
                                next
                            end
                            outcome = execute_block_iteration(block, [memo.as(Bytecode::Value), element])
                            next if outcome[:state] == :next
                            memo = outcome[:value]
                        end
                    end
                    memo
                when "until"
                    block = ensure_block(block_value, "Array##{method}")
                    found : Bytecode::Value? = nil
                    run_enumeration_loop do
                        array.each do |element|
                            outcome = execute_block_iteration(block, [element])
                            next if outcome[:state] == :next
                            if truthy?(outcome[:value])
                                found = element
                                raise BreakSignal.new
                            end
                        end
                    end
                    found
                else raise "Unknown method #{method} on Array"
                end
            when Bytecode::BagConstructorValue
                call_bag_constructor_method(receiver, method, args, block_value)
            when Bytecode::BagValue
                call_bag_method(receiver, method, args, block_value)
            else
                raise "Cannot call method #{method} on #{type_of(receiver)}"
            end
        end

        #
        # FFI
        #
        
        private def from_ffi_value(value : Dragonstone::FFI::InteropValue) : Bytecode::Value
            case value

            when Nil, Bool, Int32, Int64, Float64, String, Char
                value

            when Array
                converted = [] of Bytecode::Value
                value.each { |element| converted << from_ffi_value(element) }
                converted

            else
                nil

            end
        end

        private def call_ffi_method(method : String, args : Array(Bytecode::Value)) : Bytecode::Value
            case method

            when "call_ruby"
                call_ffi_ruby(args)

            when "call_crystal"
                call_ffi_crystal(args)

            when "call_c"
                call_ffi_c(args)

            else
                raise "Unknown FFI method: #{method}"

            end
        end
        
        # FFI: Call Ruby functions.
        private def call_ffi_ruby(args : Array(Bytecode::Value)) : Bytecode::Value

            unless args.size >= 2
                raise "ffi.call_ruby requires at least 2 arguments: method_name, [args]"
            end
            
            method_name = args[0]
            method_args = args[1]
            
            unless method_name.is_a?(String)
                raise "First argument to ffi.call_ruby must be a string"
            end
            
            unless method_args.is_a?(Array)
                raise "Second argument to ffi.call_ruby must be an array"
            end

            ruby_args = method_args.as(Array(Bytecode::Value)).map { |arg| Dragonstone::FFI.normalize(arg) }
            result = Dragonstone::FFI.call_ruby(method_name, ruby_args)

            from_ffi_value(result)
        end
        
        # FFI: Call Crystal functions.
        private def call_ffi_crystal(args : Array(Bytecode::Value)) : Bytecode::Value
            unless args.size >= 2
                raise "ffi.call_crystal requires at least 2 arguments: func_name, [args]"
            end
            
            func_name = args[0]
            func_args = args[1]
            
            unless func_name.is_a?(String)
                raise "First argument to ffi.call_crystal must be a string"
            end
            
            unless func_args.is_a?(Array)
                raise "Second argument to ffi.call_crystal must be an array"
            end

            crystal_args = func_args.as(Array(Bytecode::Value)).map { |arg| Dragonstone::FFI.normalize(arg) }
            result = Dragonstone::FFI.call_crystal(func_name, crystal_args)

            from_ffi_value(result)
        end
        
        # FFI: Call C functions.
        private def call_ffi_c(args : Array(Bytecode::Value)) : Bytecode::Value
            unless args.size >= 2
                raise "ffi.call_c requires at least 2 arguments: func_name, [args]"
            end
            
            func_name = args[0]
            func_args = args[1]
            
            unless func_name.is_a?(String)
                raise "First argument to ffi.call_c must be a string"
            end
            
            unless func_args.is_a?(Array)
                raise "Second argument to ffi.call_c must be an array"
            end

            c_args = func_args.as(Array(Bytecode::Value)).map { |arg| Dragonstone::FFI.normalize(arg) }
            result = Dragonstone::FFI.call_c(func_name, c_args)

            from_ffi_value(result)
        end
    end
  
    # Main entry point for running Dragonstone code.
    module Runtime
        def self.run_source(src : String) : Int32
            # Lex -> Parse -> Compile -> Execute
            pipeline = Core::Compiler::Frontend::Pipeline.new
            program = pipeline.build_ir(src)
            artifact = Core::Compiler.build(program)
            bytecode = artifact.bytecode
            raise "Failed to produce bytecode for VM runtime" unless bytecode
            vm = VM.new(bytecode, log_to_stdout: true)
            vm.run
            0
            
        rescue e : Error
            STDERR.puts e.message
            1

        rescue e : Exception
            STDERR.puts "Runtime error: #{e.message}"
            1
            
        end
    end
end

# Export to C (had to be global).
fun ds_run_source(src : UInt8*) : Int32
    source = String.new(src)
    Dragonstone::Runtime.run_source(source)
end

{% if env("DRAGONSTONE_RUBY_LIB") %}
    fun ds_const_under(outer : LibRuby::VALUE, name : UInt8*) : LibRuby::VALUE
        name_str = String.new(name)
        id = LibRuby.rb_intern(name)
        LibRuby.rb_const_get(outer, id)
    end
{% end %}
