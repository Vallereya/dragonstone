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
        class VMException < Exception
            getter value : Bytecode::Value?

            def initialize(@value : Bytecode::Value?)
            end
        end

        class Frame
            property code : CompiledCode
            property ip : Int32
            property stack_base : Int32
            property locals : Array(Bytecode::Value?)?
            property locals_defined : Array(Bool)?
            property block : Bytecode::BlockValue?
            property signature : Bytecode::FunctionSignature?
            property callable_name : String?
            property method_owner : Bytecode::ClassValue?
            property gc_flags : ::Dragonstone::Runtime::GC::Flags

            def initialize(
                @code : CompiledCode,
                @stack_base : Int32,
                use_locals : Bool = false,
                block_value : Bytecode::BlockValue? = nil,
                signature : Bytecode::FunctionSignature? = nil,
                callable_name : String? = nil,
                method_owner : Bytecode::ClassValue? = nil,
                gc_flags : ::Dragonstone::Runtime::GC::Flags = ::Dragonstone::Runtime::GC::Flags.new
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
                @method_owner = method_owner
                @gc_flags = gc_flags
            end
        end

        record Handler, rescue_ip : Int32?, ensure_ip : Int32?, body_ip : Int32?, stack_depth : Int32, frame_depth : Int32
        record LoopContext, condition_ip : Int32, body_ip : Int32, exit_ip : Int32, stack_depth : Int32

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
            when "empty", "empty?"
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

        private def call_map_method(
            map : Bytecode::MapValue,
            method : String,
            args : Array(Bytecode::Value),
            block_value : Bytecode::BlockValue?
        ) : Bytecode::Value
            case method
            when "length", "size"
                raise ArgumentError.new("Map##{method} does not accept a block") if block_value
                raise ArgumentError.new("Map##{method} does not take arguments") unless args.empty?
                map.size
            when "keys"
                raise ArgumentError.new("Map##{method} does not accept a block") if block_value
                raise ArgumentError.new("Map##{method} does not take arguments") unless args.empty?
                map.keys
            when "values"
                raise ArgumentError.new("Map##{method} does not accept a block") if block_value
                raise ArgumentError.new("Map##{method} does not take arguments") unless args.empty?
                map.values
            when "empty", "empty?"
                raise ArgumentError.new("Map##{method} does not accept a block") if block_value
                raise ArgumentError.new("Map##{method} does not take arguments") unless args.empty?
                map.empty?
            when "each"
                block = ensure_block(block_value, "Map##{method}")
                raise ArgumentError.new("Map##{method} does not take arguments") unless args.empty?
                run_enumeration_loop do
                    map.entries.each do |key, value|
                        outcome = execute_block_iteration(block, [key, value])
                        next if outcome[:state] == :next
                    end
                end
                map
            when "select"
                block = ensure_block(block_value, "Map##{method}")
                raise ArgumentError.new("Map##{method} does not take arguments") unless args.empty?
                result = Bytecode::MapValue.new
                run_enumeration_loop do
                    map.entries.each do |key, value|
                        outcome = execute_block_iteration(block, [key, value])
                        next if outcome[:state] == :next
                        result[key] = value if truthy?(outcome[:value])
                    end
                end
                result
            when "inject"
                block = ensure_block(block_value, "Map##{method}")
                unless args.size <= 1
                    raise ArgumentError.new("Map##{method} expects 0 or 1 argument, got #{args.size}")
                end
                memo_initialized = args.size == 1
                memo : Bytecode::Value? = memo_initialized ? args.first : nil
                if map.entries.empty? && !memo_initialized
                    raise ArgumentError.new("Map##{method} called on empty map with no initial value")
                end
                run_enumeration_loop do
                    map.entries.each do |key, value|
                        unless memo_initialized
                            memo = value
                            memo_initialized = true
                            next
                        end
                        outcome = execute_block_iteration(block, [memo.as(Bytecode::Value), key, value])
                        next if outcome[:state] == :next
                        memo = outcome[:value]
                    end
                end
                memo
            when "until"
                block = ensure_block(block_value, "Map##{method}")
                raise ArgumentError.new("Map##{method} does not take arguments") unless args.empty?
                found : Bytecode::Value? = nil
                run_enumeration_loop do
                    map.entries.each do |key, value|
                        outcome = execute_block_iteration(block, [key, value])
                        next if outcome[:state] == :next
                        if truthy?(outcome[:value])
                            pair = [] of Bytecode::Value
                            pair << key
                            pair << value
                            found = pair
                            raise BreakSignal.new
                        end
                    end
                end
                found
            when "delete"
                raise ArgumentError.new("Map##{method} does not accept a block") if block_value
                unless args.size == 1
                    raise ArgumentError.new("Map##{method} expects 1 argument, got #{args.size}")
                end
                map.delete(args.first)
            else
                raise "Unknown method '#{method}' for Map"
            end
        end

        private def call_tuple_method(
            tuple : Bytecode::TupleValue,
            method : String,
            args : Array(Bytecode::Value),
            block_value : Bytecode::BlockValue?
        ) : Bytecode::Value
            case method
            when "length", "size"
                raise ArgumentError.new("Tuple##{method} does not accept a block") if block_value
                raise ArgumentError.new("Tuple##{method} does not take arguments") unless args.empty?
                tuple.elements.size.to_i64
            when "first"
                raise ArgumentError.new("Tuple##{method} does not accept a block") if block_value
                raise ArgumentError.new("Tuple##{method} does not take arguments") unless args.empty?
                tuple.elements.first?
            when "last"
                raise ArgumentError.new("Tuple##{method} does not accept a block") if block_value
                raise ArgumentError.new("Tuple##{method} does not take arguments") unless args.empty?
                tuple.elements.last?
            when "each"
                block = ensure_block(block_value, "Tuple##{method}")
                raise ArgumentError.new("Tuple##{method} does not take arguments") unless args.empty?
                run_enumeration_loop do
                    tuple.elements.each do |element|
                        outcome = execute_block_iteration(block, [element])
                        next if outcome[:state] == :next
                    end
                end
                tuple
            when "map"
                block = ensure_block(block_value, "Tuple##{method}")
                raise ArgumentError.new("Tuple##{method} does not take arguments") unless args.empty?
                result = [] of Bytecode::Value
                run_enumeration_loop do
                    tuple.elements.each do |element|
                        outcome = execute_block_iteration(block, [element])
                        next if outcome[:state] == :next
                        result << (outcome[:value].nil? ? nil : outcome[:value])
                    end
                end
                result
            else
                raise "Unknown method '#{method}' for Tuple"
            end
        end

        private def call_named_tuple_method(
            tuple : Bytecode::NamedTupleValue,
            method : String,
            args : Array(Bytecode::Value),
            block_value : Bytecode::BlockValue?
        ) : Bytecode::Value
            case method
            when "length", "size"
                raise ArgumentError.new("NamedTuple##{method} does not accept a block") if block_value
                raise ArgumentError.new("NamedTuple##{method} does not take arguments") unless args.empty?
                tuple.entries.size.to_i64
            when "keys"
                raise ArgumentError.new("NamedTuple##{method} does not accept a block") if block_value
                raise ArgumentError.new("NamedTuple##{method} does not take arguments") unless args.empty?
                keys = [] of Bytecode::Value
                tuple.entries.each_key { |key| keys << key }
                keys
            when "values"
                raise ArgumentError.new("NamedTuple##{method} does not accept a block") if block_value
                raise ArgumentError.new("NamedTuple##{method} does not take arguments") unless args.empty?
                values = [] of Bytecode::Value
                tuple.entries.each_value { |value| values << value }
                values
            when "each"
                block = ensure_block(block_value, "NamedTuple##{method}")
                raise ArgumentError.new("NamedTuple##{method} does not take arguments") unless args.empty?
                run_enumeration_loop do
                    tuple.entries.each do |key, value|
                        outcome = execute_block_iteration(block, [key, value])
                        next if outcome[:state] == :next
                    end
                end
                tuple
            when "map"
                block = ensure_block(block_value, "NamedTuple##{method}")
                raise ArgumentError.new("NamedTuple##{method} does not take arguments") unless args.empty?
                result = [] of Bytecode::Value
                run_enumeration_loop do
                    tuple.entries.each do |key, value|
                        outcome = execute_block_iteration(block, [key, value])
                        next if outcome[:state] == :next
                        result << (outcome[:value].nil? ? nil : outcome[:value])
                    end
                end
                result
            else
                raise "Unknown method '#{method}' for NamedTuple"
            end
        end

        private def call_container_method(
            container : Bytecode::ModuleValue,
            method : String,
            args : Array(Bytecode::Value),
            block_value : Bytecode::BlockValue?,
            self_value : Bytecode::Value
        ) : Bytecode::Value
            if container.is_a?(Bytecode::ClassValue)
                klass = container.as(Bytecode::ClassValue)
                info = klass.lookup_method_with_owner(method)
                raise "Unknown method '#{method}' for #{container.name}" unless info
                fn = info[:method]
                owner = info[:owner]
                if fn.abstract?
                    raise ::Dragonstone::TypeError.new("Cannot invoke abstract method #{method} on #{container.name}")
                end
                return with_container_context(container) do
                    call_function_value(fn, args, block_value, self_value, method_owner: owner)
                end
            end

            fn = container.lookup_method(method)
            raise "Unknown method '#{method}' for #{container.name}" unless fn
            if fn.abstract?
                raise ::Dragonstone::TypeError.new("Cannot invoke abstract method #{method} on #{container.name}")
            end
            with_container_context(container) do
                call_function_value(fn, args, block_value, self_value)
            end
        end

        private def call_instance_method(
            instance : Bytecode::InstanceValue,
            method : String,
            args : Array(Bytecode::Value),
            block_value : Bytecode::BlockValue?
        ) : Bytecode::Value
            info = instance.klass.lookup_method_with_owner(method)
            raise "Undefined method '#{method}' for instance of #{instance.klass.name}" unless info
            fn = info[:method]
            owner = info[:owner]
            if fn.abstract?
                raise ::Dragonstone::TypeError.new("Cannot invoke abstract method #{method} on #{instance.klass.name}")
            end
            with_container_context(instance.klass) do
                call_function_value(fn, args, block_value, instance, method_owner: owner)
            end
        end

        private def call_enum_method(
            enum_val : Bytecode::EnumValue,
            method : String,
            args : Array(Bytecode::Value),
            block_value : Bytecode::BlockValue?
        ) : Bytecode::Value
            case method
            when "new"
                raise ArgumentError.new("#{enum_val.name}.new does not accept a block") if block_value
                unless args.size == 1
                    raise ArgumentError.new("#{enum_val.name}.new expects 1 argument")
                end
                value = args.first
                int_value = value.is_a?(Int32) ? value.to_i64 : value.as(Int64)
                member = enum_val.member_for_value(int_value)
                raise "No enum member with value #{int_value} for #{enum_val.name}" unless member
                return member.as(Bytecode::Value)
            when "members"
                raise ArgumentError.new("#{enum_val.name}.members does not accept a block") if block_value
                return enum_val.members.map { |member| member.as(Bytecode::Value) }
            when "values"
                raise ArgumentError.new("#{enum_val.name}.values does not accept a block") if block_value
                return enum_val.members.map { |member| member.value.as(Bytecode::Value) }
            when "each"
                block = ensure_block(block_value, "#{enum_val.name}.each")
                raise ArgumentError.new("#{enum_val.name}.each does not take arguments") unless args.empty?
                run_enumeration_loop do
                    enum_val.members.each do |member|
                        outcome = execute_block_iteration(block, [member])
                        next if outcome[:state] == :next
                    end
                end
                return enum_val.as(Bytecode::Value)
            else
                if fn = enum_val.lookup_method(method)
                    return with_container_context(enum_val) do
                        call_function_value(fn, args, block_value, enum_val)
                    end
                else
                    raise "Unknown method '#{method}' for enum #{enum_val.name}"
                end
            end
        end

        private def call_enum_member_method(
            member : Bytecode::EnumMemberValue,
            method : String,
            args : Array(Bytecode::Value),
            block_value : Bytecode::BlockValue?
        ) : Bytecode::Value
            raise ArgumentError.new("Enum member methods do not accept blocks") if block_value
            unless args.empty?
                raise ArgumentError.new("Enum member methods do not take arguments")
            end
            case method
            when "name"
                member.name
            when "enum"
                member.enum
            when "value", member.enum.value_method_name
                member.value
            else
                raise "Unknown method '#{method}' for enum member"
            end
        end

        private def call_range_method(range : Bytecode::RangeValue, method : String, args : Array(Bytecode::Value), block_value : Bytecode::BlockValue?) : Bytecode::Value
            case method
            when "first"
                raise ArgumentError.new("Range##{method} does not accept a block") if block_value
                raise ArgumentError.new("Range##{method} does not take arguments") unless args.empty?
                range.begin
            when "last"
                raise ArgumentError.new("Range##{method} does not accept a block") if block_value
                raise ArgumentError.new("Range##{method} does not take arguments") unless args.empty?
                range.end
            when "includes?"
                raise ArgumentError.new("Range##{method} does not accept a block") if block_value
                raise ArgumentError.new("Range##{method} expects 1 argument") unless args.size == 1
                arg = args.first
                range_includes?(range, arg)
            when "each"
                block = ensure_block(block_value, "Range##{method}")
                raise ArgumentError.new("Range##{method} does not take arguments") unless args.empty?
                run_enumeration_loop do
                    iterate_range(range) { |val| execute_block_iteration(block, [val]) }
                end
                range
            when "to_a"
                raise ArgumentError.new("Range##{method} does not accept a block") if block_value
                raise ArgumentError.new("Range##{method} does not take arguments") unless args.empty?
                arr = [] of Bytecode::Value
                iterate_range(range) do |val|
                    arr << val
                    {state: :yielded, value: val}
                end
                arr
            else
                raise "Unknown method '#{method}' for Range"
            end
        end

        private def range_includes?(range : Bytecode::RangeValue, arg : Bytecode::Value) : Bool
            beg = range.begin
            if beg.is_a?(Int64)
                return false unless arg.is_a?(Int32) || arg.is_a?(Int64)
                value = arg.to_i64
                start = beg
                finish_val = range.end
                finish = finish_val.is_a?(Int64) ? finish_val : start
                finish -= 1 if range.exclusive?
                return value >= start && value <= finish
            elsif beg.is_a?(Char)
                return false unless arg.is_a?(Char)
                start = beg.ord
                finish_val = range.end
                finish = finish_val.is_a?(Char) ? finish_val.ord : start
                finish -= 1 if range.exclusive?
                value = arg.ord
                return value >= start && value <= finish
            else
                false
            end
        end

        private def iterate_range(range : Bytecode::RangeValue)
            beg = range.begin
            if beg.is_a?(Int64)
                start = beg
                finish = range.end
                finish -= 1 if range.exclusive?
                (start..finish).each do |val|
                    outcome = yield val
                    next if outcome[:state] == :next
                end
            elsif beg.is_a?(Char)
                start = beg.ord
                finish_val = range.end
                finish = finish_val.is_a?(Char) ? finish_val.ord : start
                finish -= 1 if range.exclusive?
                start.upto(finish) do |code|
                    outcome = yield code.chr
                    next if outcome[:state] == :next
                end
            end
        end

        private def ensure_arity(signature : Bytecode::FunctionSignature, provided : Int32, name : String, block_value : Bytecode::BlockValue? = nil) : Nil
            expected = signature.parameters.size
            if ENV["DS_DEBUG_ARITY"]?
                STDERR.puts "ARITY #{name} expected=#{expected} provided=#{provided}"
            end
            return if expected == provided
            if block_value && expected == provided + 1
                return
            end
            raise "Function #{name} expects #{expected} arguments, got #{provided}"
        end

        private def yield_to_block(args : Array(Bytecode::Value)) : Bytecode::Value
            frame = current_frame
            block = frame.block
            raise "No block given" unless block
            ensure_arity(block.signature, args.size, "yield")
            depth_before = @frames.size
            push_callable_frame(block.code, block.signature, args, nil, "<block>", nil, current_frame)
            execute_with_frame_cleanup(depth_before)
        end

        private def call_block(block_value : Bytecode::BlockValue, args : Array(Bytecode::Value)) : Bytecode::Value
            ensure_arity(block_value.signature, args.size, "<block>")
            depth_before = @frames.size
            push_callable_frame(block_value.code, block_value.signature, args, nil, "<block>", nil, current_frame)
            execute_with_frame_cleanup(depth_before)
        end

        private def ensure_block(block_value : Bytecode::BlockValue?, feature : String) : Bytecode::BlockValue
            raise ArgumentError.new("#{feature} requires a block") unless block_value
            block_value
        end

        private def execute_block_iteration(block_value : Bytecode::BlockValue, args : Array(Bytecode::Value)) : NamedTuple(state: Symbol, value: Bytecode::Value)
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

        private def enter_gc_context(flags : ::Dragonstone::Runtime::GC::Flags) : Nil
            if flags.disable
                @gc_manager.disable
            end
            if flags.area
                @gc_manager.begin_area
            end
        end

        private def exit_gc_context(flags : ::Dragonstone::Runtime::GC::Flags) : Nil
            if flags.area
                @gc_manager.end_area
            end
            if flags.disable
                @gc_manager.enable
            end
        end

        private def push_loop_context(condition_ip : Int32, body_ip : Int32, exit_ip : Int32) : Nil
            @loop_stack << LoopContext.new(condition_ip, body_ip, exit_ip, @stack.size)
        end

        private def pop_loop_context : LoopContext?
            @loop_stack.pop?
        end

        private def current_loop_context : LoopContext?
            @loop_stack.last?
        end

        private def trim_stack(depth : Int32) : Nil
            return if depth >= @stack.size
            @stack = @stack[0...depth]
        end

        private def ensure_loop!(keyword : String) : LoopContext
            ctx = current_loop_context
            raise RuntimeError.new("#{keyword} used outside of a loop") unless ctx
            ctx
        end

        private def with_container_context(container : Bytecode::ModuleValue?, &block)
            if container
                @container_stack << container
                begin
                    yield
                ensure
                    @container_stack.pop?
                end
            else
                yield
            end
        end

        private def attach_singleton_method(receiver : Bytecode::Value, fn : Bytecode::FunctionValue) : Nil
            key = singleton_key_for(receiver)
            map = @singleton_methods[key]? || begin
                new_map = {} of String => Bytecode::FunctionValue
                @singleton_methods[key] = new_map
                new_map
            end
            map[fn.name] = fn
        end

        private def lookup_singleton_method(receiver : Bytecode::Value, name : String) : Bytecode::FunctionValue?
            if map = @singleton_methods[singleton_key_for(receiver)]?
                return map[name]?
            end
            nil
        end

        private def singleton_key_for(receiver : Bytecode::Value) : UInt64
            receiver.hash.to_u64
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
        @handlers : Array(Handler)
        @current_exception : Bytecode::Value?
        @rethrow_after_ensure : Bool
        @container_stack : Array(Bytecode::ModuleValue)
        @loop_stack : Array(LoopContext)
        @retry_after_ensure : Int32?
        @singleton_methods : Hash(UInt64, Hash(String, Bytecode::FunctionValue))
        @pending_self : Bytecode::Value?
        @argv_value : Array(Bytecode::Value)

        def initialize(
            @bytecode : CompiledCode,
            globals : Hash(String, Bytecode::Value)? = nil,
            argv : Array(String) = [] of String,
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
            @handlers = [] of Handler
            @current_exception = nil
            @rethrow_after_ensure = false
            @container_stack = [] of Bytecode::ModuleValue
            @loop_stack = [] of LoopContext
            @retry_after_ensure = nil
            @singleton_methods = {} of UInt64 => Hash(String, Bytecode::FunctionValue)
            @pending_self = nil
            @argv_value = argv.map { |arg| arg.as(Bytecode::Value) }
            @gc_manager = ::Dragonstone::Runtime::GC::Manager(Bytecode::Value).new(
                ->(value : Bytecode::Value) : Bytecode::Value { ::Dragonstone::Runtime::GC.deep_copy_bytecode(value) }
            )

            # Initialize FFI
            init_ffi_module
            init_gc_module
            sync_globals_slots
        end

        private def init_ffi_module
            @globals["ffi"] ||= FFIModule.new
            if idx = @name_index_cache["ffi"]?
                ensure_global_capacity(idx)
                @global_slots[idx] = @globals["ffi"]
                @global_defined[idx] = true
            end
            @globals["self"] ||= nil
        end

        private def init_gc_module
            @globals["gc"] ||= Bytecode::GCHost.new(@gc_manager)
            if idx = @name_index_cache["gc"]?
                ensure_global_capacity(idx)
                @global_slots[idx] = @globals["gc"]
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

                begin
                    case opcode
                when OPC::HALT
                    return @stack.empty? ? nil : pop
                when OPC::NOP
                    # nil
                when OPC::CONST
                    idx = fetch_byte
                    value = current_code.consts[idx]
                    if ENV["DS_DEBUG_CONST"]?
                        STDERR.puts "CONST[#{idx}] => #{value.inspect}"
                    end
                    push(value)
                when OPC::LOAD
                    name_idx = fetch_byte
                    name = current_code.names[name_idx]
                    push(resolve_variable(name_idx, name))
                when OPC::LOAD_ARGV
                    push(@argv_value)
                when OPC::LOAD_CONST_PATH
                    const_idx = fetch_byte
                    segments = current_code.consts[const_idx].as(Array(Bytecode::Value))
                    push(resolve_constant_path(segments))
                when OPC::STORE
                    name_idx = fetch_byte
                    name = current_code.names[name_idx]
                    if @stack.empty?
                        STDERR.puts "STORE stack empty for #{name} ip=#{current_frame.ip}"
                    end
                    value = peek
                    store_variable(name_idx, name, value)
                when OPC::LOAD_IVAR
                    name_idx = fetch_byte
                    name = current_code.names[name_idx]
                    push(load_instance_variable(name))
                when OPC::STORE_IVAR
                    name_idx = fetch_byte
                    name = current_code.names[name_idx]
                    value = peek
                    store_instance_variable(name, value)
                when OPC::PUSH_HANDLER
                    rescue_ip = fetch_byte
                    ensure_ip = fetch_byte
                    body_ip = fetch_byte
                    push_handler(rescue_ip, ensure_ip, body_ip)
                when OPC::POP_HANDLER
                    pop_handler
                when OPC::LOAD_EXCEPTION
                    push(@current_exception)
                when OPC::RAISE
                    value = pop
                    raise VMException.new(value)
                when OPC::CHECK_RETHROW
                    if @rethrow_after_ensure
                        @rethrow_after_ensure = false
                        raise VMException.new(@current_exception)
                    elsif @retry_after_ensure
                        target = @retry_after_ensure.not_nil!
                        @retry_after_ensure = nil
                        current_frame.ip = target
                    end
                when OPC::RETRY
                    handler = @handlers.last? || raise "retry used outside of rescue"
                    body_ip = handler.body_ip || raise "retry used outside of begin block"
                    @current_exception = nil
                    @rethrow_after_ensure = false
                    @retry_after_ensure = body_ip
                    if handler.ensure_ip
                        current_frame.ip = handler.ensure_ip.not_nil!
                    else
                        current_frame.ip = body_ip
                    end
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
                when OPC::FLOOR_DIV
                    b, a = pop, pop
                    push(floor_div(a, b))
                when OPC::MOD
                    b, a = pop, pop
                    push(mod(a, b))
                when OPC::BIT_AND
                    b, a = pop, pop
                    push(bit_and(a, b))
                when OPC::BIT_OR
                    b, a = pop, pop
                    push(bit_or(a, b))
                when OPC::BIT_XOR
                    b, a = pop, pop
                    push(bit_xor(a, b))
                when OPC::SHL
                    b, a = pop, pop
                    push(shift_left(a, b))
                when OPC::SHR
                    b, a = pop, pop
                    push(shift_right(a, b))
                when OPC::NEG
                    value = pop
                    push(negate_value(value))
                when OPC::POS
                    value = pop
                    push(unary_positive(value))
                when OPC::EQ
                    b, a = pop, pop
                    overload = invoke_operator_overload(a, "==", b)
                    push(overload.nil? ? (a == b) : overload)
                when OPC::NE
                    b, a = pop, pop
                    overload = invoke_operator_overload(a, "!=", b)
                    push(overload.nil? ? (a != b) : overload)
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
                when OPC::CMP
                    b, a = pop, pop
                    push(spaceship_compare(a, b))
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
                when OPC::POW
                    b, a = pop, pop
                    push(pow(a, b))
                when OPC::ECHO
                    argc = fetch_byte
                    args = pop_values(argc)
                    line = args.map { |arg| arg.nil? ? "" : stringify(arg) }.join(" ")
                    emit_output(line)
                    push(nil)
                when OPC::TYPEOF
                    value = pop
                    push(type_of(value))
                when OPC::DEBUG_ECHO
                    source_idx = fetch_byte
                    source = current_code.consts[source_idx].to_s
                    value = pop
                    emit_output("#{source} # -> #{inspect_value(value)}")
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
                when OPC::MAKE_MAP
                    count = fetch_byte
                    values = pop_values(count * 2)
                    map = Bytecode::MapValue.new
                    (0...count).each do |i|
                        key = values[i * 2]
                        value = values[i * 2 + 1]
                        map[key] = value
                    end
                    push(map)
                when OPC::MAKE_RANGE
                    inclusive = fetch_byte == 1
                    b = pop
                    a = pop
                    push(build_range(a, b, inclusive))
                when OPC::ENTER_LOOP
                    condition_ip = fetch_byte
                    body_ip = fetch_byte
                    exit_ip = fetch_byte
                    push_loop_context(condition_ip, body_ip, exit_ip)
                when OPC::EXIT_LOOP
                    pop_loop_context
                when OPC::EXTEND_CONTAINER
                    target = pop
                    extend_current_container_with(target)
                when OPC::MAKE_MODULE
                    name_idx = fetch_byte
                    name = current_code.names[name_idx]
                    push(Bytecode::ModuleValue.new(name))
                when OPC::MAKE_CLASS
                    name_idx = fetch_byte
                    abstract_flag = fetch_byte
                    super_idx = fetch_byte
                    name = current_code.names[name_idx]
                    superclass = nil
                    if super_idx >= 0
                        super_val = current_code.consts[super_idx]
                        if super_val.is_a?(Bytecode::ClassValue)
                            superclass = super_val
                        elsif super_val.is_a?(String)
                            begin
                                resolved = resolve_variable_by_name(super_val)
                                superclass = resolved if resolved.is_a?(Bytecode::ClassValue)
                            rescue
                                superclass = nil
                            end
                        end
                    end
                    push(Bytecode::ClassValue.new(name, superclass, abstract_flag == 1))
                when OPC::MAKE_STRUCT
                    name_idx = fetch_byte
                    name = current_code.names[name_idx]
                    push(Bytecode::StructValue.new(name))
                when OPC::MAKE_ENUM
                    name_idx = fetch_byte
                    value_method_idx = fetch_byte
                    name = current_code.names[name_idx]
                    method_name = current_code.consts[value_method_idx].to_s
                    push(Bytecode::EnumValue.new(name, method_name))
                when OPC::ENTER_CONTAINER
                    container = pop_container_value
                    @container_stack << container
                when OPC::EXIT_CONTAINER
                    @container_stack.pop?
                when OPC::DEFINE_CONST
                    name_idx = fetch_byte
                    name = current_code.names[name_idx]
                    value = pop
                    define_constant_in_current(name, value)
                    push(value)
                when OPC::DEFINE_METHOD
                    name_idx = fetch_byte
                    name = current_code.names[name_idx]
                    fn = pop
                    unless fn.is_a?(Bytecode::FunctionValue)
                        raise "DEFINE_METHOD expects FunctionValue"
                    end
                    define_method_in_current(name, fn)
                when OPC::DEFINE_ENUM_MEMBER
                    name_idx = fetch_byte
                    has_value = fetch_byte
                    name = current_code.names[name_idx]
                    value = has_value == 1 ? pop : nil
                    define_enum_member(name, value)
                when OPC::MAKE_TUPLE
                    count = fetch_byte
                    elements = pop_values(count)
                    push(Bytecode::TupleValue.new(elements))
                when OPC::MAKE_NAMED_TUPLE
                    count = fetch_byte
                    values = pop_values(count * 2)
                    tuple = Bytecode::NamedTupleValue.new
                    (0...count).each do |i|
                        key = values[i * 2]
                        name = key.is_a?(SymbolValue) ? key : SymbolValue.new(key.to_s)
                        tuple.entries[name] = values[i * 2 + 1]
                    end
                    push(tuple)
                when OPC::INDEX
                    index, obj = pop, pop
                    push(index_access(obj, index))
                when OPC::STORE_INDEX
                    value = pop
                    index = pop
                    object = pop
                    push(assign_index_value(object, index, value))
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
                when OPC::INVOKE_SUPER
                    argc = fetch_byte
                    args = pop_values(argc)
                    result = invoke_super_method(args, current_frame.block)
                    push(result)
                when OPC::INVOKE_SUPER_BLOCK
                    argc = fetch_byte
                    block_value = pop_block
                    args = pop_values(argc)
                    result = invoke_super_method(args, block_value)
                    push(result)
                when OPC::CALL
                    argc = fetch_byte
                    name_idx = fetch_byte
                    args = pop_values(argc)
                    if ENV["DS_DEBUG_CALL"]?
                        STDERR.puts "CALL #{current_code.names[name_idx]} argc=#{argc} args=#{args.inspect}"
                    end
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
                    push(Bytecode::FunctionValue.new(name, signature, code, signature.abstract?))
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
                    if ctx = current_loop_context
                        trim_stack(ctx.stack_depth)
                        pop_loop_context
                        current_frame.ip = ctx.exit_ip
                    else
                        raise BreakSignal.new
                    end
                when OPC::NEXT_SIGNAL
                    if ctx = current_loop_context
                        trim_stack(ctx.stack_depth)
                        pop_loop_context
                        current_frame.ip = ctx.condition_ip
                    else
                        raise NextSignal.new
                    end
                when OPC::REDO_SIGNAL
                    if ctx = current_loop_context
                        trim_stack(ctx.stack_depth)
                        current_frame.ip = ctx.body_ip
                    else
                        raise RedoSignal.new
                    end
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
                when OPC::DEFINE_SINGLETON_METHOD
                    fn_val = pop
                    receiver = pop
                    unless fn_val.is_a?(Bytecode::FunctionValue)
                        raise ArgumentError.new("DEFINE_SINGLETON_METHOD expects a function value")
                    end
                    attach_singleton_method(receiver, fn_val)
                    push(fn_val)
                else
                    raise "Unknown opcode: #{opcode}"
                    end
                rescue ex : VMException
                    handle_exception(ex.value)
                    next
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
            @handlers.clear
            @current_exception = nil
            @rethrow_after_ensure = false
            @container_stack.clear
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
            @pending_self = nil
            frame = current_frame
            if locals = frame.locals
                if defined = frame.locals_defined
                    if name_idx < locals.size && defined[name_idx]
                        slot = locals[name_idx]?
                        return slot.nil? ? nil : slot
                    end
                end
            end

            @container_stack.reverse_each do |container|
                if value = container.fetch_constant(name)
                    return value
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

            if self_candidate = current_self_safe
                case self_candidate
                when Bytecode::InstanceValue
                    if val = self_candidate.ivars[name]?
                        return val
                    end
                    if fn = self_candidate.klass.lookup_method(name)
                        @pending_self = self_candidate
                        return fn
                    end
                when Bytecode::ModuleValue
                    if const = self_candidate.fetch_constant(name)
                        return const
                    end
                    if fn = self_candidate.lookup_method(name)
                        @pending_self = self_candidate
                        return fn
                    end
                else
                    return invoke_method(self_candidate, name, [] of Bytecode::Value, nil)
                end
            end
            if frame.callable_name == "<block>" && @frames.size >= 2
                outer = @frames[@frames.size - 2]
                if locals = outer.locals
                    if defined = outer.locals_defined
                        if name_idx < locals.size && defined[name_idx]
                            slot = locals[name_idx]?
                            return slot.nil? ? nil : slot
                        end
                    end
                end
            end
            raise "Undefined variable: #{name}"
        end

        private def current_self_safe : Bytecode::Value?
            current_self
        rescue
            nil
        end

        private def resolve_constant_path(segments : Array(Bytecode::Value)) : Bytecode::Value
            raise "Empty constant path" if segments.empty?
            head = segments.first
            unless head.is_a?(String)
                raise ::Dragonstone::NameError.new("Invalid constant head")
            end
            value = resolve_variable_by_name(head)
            segments[1..-1].each do |segment_value|
                segment = segment_value.to_s
                unless value.is_a?(Bytecode::ModuleValue)
                    raise ::Dragonstone::NameError.new("Constant #{segment} not found in #{describe_value(value)}")
                end
                mod = value.as(Bytecode::ModuleValue)
                nested = mod.fetch_constant(segment)
                unless nested
                    raise ::Dragonstone::NameError.new("Constant #{segment} not found")
                end
                value = nested.nil? ? nil : nested
            end
            value.nil? ? nil : value
        end

        private def resolve_variable_by_name(name : String) : Bytecode::Value
            if idx = @name_index_cache[name]?
                return resolve_variable(idx, name)
            end

            @container_stack.reverse_each do |container|
                if value = container.fetch_constant(name)
                    return value
                end
            end

            if value = @globals[name]?
                return value
            end

            raise ::Dragonstone::NameError.new("Undefined variable or constant: #{name}")
        end

        private def load_instance_variable(name : String) : Bytecode::Value
            ivars = ensure_instance_ivars
            ivars[name]? || nil
        end

        private def store_instance_variable(name : String, value : Bytecode::Value) : Nil
            ivars = ensure_instance_ivars
            ivars[name] = value
        end

        private def ensure_instance_ivars : Hash(String, Bytecode::Value)
            self_value = current_self
            if self_value.is_a?(Bytecode::InstanceValue)
                return self_value.ivars
            end

            raise ::Dragonstone::InterpreterError.new("Instance variables require self to be an object")
        end

        private def wrap_exception_value(value : Bytecode::Value?) : Bytecode::Value
            return value if value.is_a?(Bytecode::RaisedExceptionValue)
            Bytecode::RaisedExceptionValue.new(value)
        end

        private def current_self : Bytecode::Value
            if idx = @name_index_cache["self"]?
                frame = current_frame
                if locals = frame.locals
                    if defined = frame.locals_defined
                        if idx < defined.size && defined[idx]
                            slot = locals[idx]?
                            return slot.nil? ? nil : slot
                        end
                    end
                end
                ensure_global_capacity(idx)
                if @global_defined[idx]
                    slot = @global_slots[idx]?
                    return slot.nil? ? nil : slot
                end
            end

            if value = @globals["self"]?
                return value
            end

            if container = current_container
                return container
            end

            raise ::Dragonstone::InterpreterError.new("Instance variable access requires self")
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

        private def handle_exception(value : Bytecode::Value?)
            @current_exception = wrap_exception_value(value)
            loop do
                handler = @handlers.last?
                break unless handler
                truncate_stack(handler.stack_depth)

                while (@frames.size - 1) > handler.frame_depth
                    frame = @frames.pop
                    truncate_stack(frame.stack_base)
                end

                if handler.rescue_ip
                    current_frame.ip = handler.rescue_ip.not_nil!
                    return
                elsif handler.ensure_ip
                    @rethrow_after_ensure = true
                    current_frame.ip = handler.ensure_ip.not_nil!
                    return
                end
                @handlers.pop?
            end
            raise ::Dragonstone::RuntimeError.new("Unhandled exception: #{stringify(value)}")
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

        private def pop_container_value : Bytecode::ModuleValue
            value = pop
            unless value.is_a?(Bytecode::ModuleValue)
                raise "Container expected"
            end
            value
        end

        private def current_container : Bytecode::ModuleValue?
            @container_stack.last?
        end

        private def define_constant_in_current(name : String, value : Bytecode::Value)
            if container = current_container
                container.define_constant(name, value)
            else
                assign_global(name, value)
            end
        end

        private def define_method_in_current(name : String, fn : Bytecode::FunctionValue)
            container = current_container
            raise "No container for method #{name}" unless container
            container.define_method(name, fn)
        end

        private def extend_current_container_with(target : Bytecode::Value) : Nil
            container = current_container
            raise ::Dragonstone::TypeError.new("'extend' can only be used inside modules or classes") unless container

            extension = case target
            when Bytecode::ModuleValue
                target
            when Bytecode::ClassValue
                target
            else
                raise ::Dragonstone::TypeError.new("Cannot extend #{container.name} with #{type_of(target)}")
            end

            return if extension == container

            extension.methods.each do |name, method|
                container.define_method(name, method)
            end
        end

        private def define_enum_member(name : String, value : Bytecode::Value?)
            container = current_container
            unless container.is_a?(Bytecode::EnumValue)
                raise "Enum member defined outside enum"
            end
            enum_val = container.as(Bytecode::EnumValue)
            member_value = if value.nil?
                enum_val.last_value + 1
            else
                if value.is_a?(Int32)
                    value.to_i64
                elsif value.is_a?(Int64)
                    value
                else
                    raise ::Dragonstone::TypeError.new("Enum values must be integers")
                end
            end
            enum_val.define_member(name, member_value)
        end

        private def push_handler(rescue_ip : Int32, ensure_ip : Int32, body_ip : Int32)
            handler = Handler.new(
                rescue_ip >= 0 ? rescue_ip : nil,
                ensure_ip >= 0 ? ensure_ip : nil,
                body_ip >= 0 ? body_ip : nil,
                @stack.size,
                @frames.size - 1
            )
            @handlers << handler
        end

        private def pop_handler
            @handlers.pop?
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
                if args.empty?
                    truncate_stack(current_frame.stack_base)
                    push(value)
                    return
                end
                raise "Undefined function: #{name}"
            end
            if value.abstract?
                raise ::Dragonstone::TypeError.new("Cannot invoke abstract function #{name}")
            end
            self_value = @pending_self
            @pending_self = nil
            signature = value.signature
            final_args = coerce_call_args(signature, args, block_value, name)
            frame = push_callable_frame(value.code, signature, final_args, block_value, name, self_value)
            frame.block = block_value
        end

        private def call_function_value(
            fn : Bytecode::FunctionValue,
            args : Array(Bytecode::Value),
            block_value : Bytecode::BlockValue?,
            self_value : Bytecode::Value? = nil,
            *,
            method_owner : Bytecode::ClassValue? = nil
        ) : Bytecode::Value
            if fn.abstract?
                raise ::Dragonstone::TypeError.new("Cannot invoke abstract function #{fn.name}")
            end
            final_args = coerce_call_args(fn.signature, args, block_value, fn.name)
            depth_before = @frames.size
            push_callable_frame(fn.code, fn.signature, final_args, block_value, fn.name, self_value, method_owner: method_owner)
            result = execute_with_frame_cleanup(depth_before)
            pop
            result
        end

        private def coerce_call_args(signature : Bytecode::FunctionSignature, args : Array(Bytecode::Value), block_value : Bytecode::BlockValue?, name : String) : Array(Bytecode::Value)
            ensure_arity(signature, args.size, name, block_value)
            expected = signature.parameters.size
            return args if expected == args.size
            if block_value && expected == args.size + 1
                coerced = args.dup
                coerced << block_value
                return coerced
            end
            args
        end

        private def push_frame(
            code : CompiledCode,
            use_locals : Bool,
            block_value : Bytecode::BlockValue? = nil,
            signature : Bytecode::FunctionSignature? = nil,
            callable_name : String? = nil,
            method_owner : Bytecode::ClassValue? = nil,
            gc_flags : ::Dragonstone::Runtime::GC::Flags = ::Dragonstone::Runtime::GC::Flags.new
        ) : Frame
            frame = Frame.new(code, @stack.size, use_locals, block_value, signature, callable_name, method_owner, gc_flags)
            @frames << frame
            frame
        end

        private def push_callable_frame(
            code : CompiledCode,
            signature : Bytecode::FunctionSignature,
            args : Array(Bytecode::Value),
            block_value : Bytecode::BlockValue?,
            callable_name : String? = nil,
            self_value : Bytecode::Value? = nil,
            locals_source : Frame? = nil,
            method_owner : Bytecode::ClassValue? = nil
        ) : Frame
            frame = push_frame(code, true, block_value, signature, callable_name, method_owner, signature.gc_flags)
            enter_gc_context(frame.gc_flags)
            if ENV["DS_DEBUG_STACK_ENTRY"]?
                STDERR.puts "ENTER #{callable_name || "<lambda>"} stack_base=#{frame.stack_base} stack=#{@stack.inspect}"
            end
            if locals_source
                if source_locals = locals_source.locals
                    frame.locals = source_locals
                    frame.locals_defined = locals_source.locals_defined
                end
            end
            if self_value
                if idx = @name_index_cache["self"]?
                    assign_local(frame, idx, self_value)
                end
            end
            signature.parameters.each_with_index do |param, index|
                value = args[index]
                enforce_type(param.type_expression, value, "parameter #{index + 1}")
                assign_local(frame, param.name_index, value)
                if param.ivar_name && self_value.is_a?(Bytecode::InstanceValue)
                    self_value.ivars[param.ivar_name.not_nil!] = value
                end
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
                exit_gc_context(frame.gc_flags)
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
            exit_gc_context(frame.gc_flags)
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
            if ENV["DS_DEBUG_ADD"]?
                STDERR.puts "STACK before ADD: #{@stack.inspect}"
                STDERR.puts "ADD a=#{a.inspect} b=#{b.inspect}"
            end
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
                overload = invoke_operator_overload(a, "+", b)
                return overload unless overload.nil?
                raise "Cannot add #{type_of(a)} and #{type_of(b)}"

            end
        end

        private def mod(a : Bytecode::Value, b : Bytecode::Value) : Bytecode::Value
            case a
            when Int32, Int64
                lhs = a.to_i64
                rhs = case b
                    when Int32, Int64 then b.to_i64
                    else raise "Type error"
                end
                lhs % rhs
            when Float64
                rhs = case b
                    when Int32, Int64, Float64 then b.to_f64
                    else raise "Type error"
                end
                a % rhs
            else
                overload = invoke_operator_overload(a, "%", b)
                return overload unless overload.nil?
                raise "Type error"
            end
        end

        private def floor_div(a : Bytecode::Value, b : Bytecode::Value) : Bytecode::Value
            overload = invoke_operator_overload(a, "//", b)
            return overload unless overload.nil?

            if (a.is_a?(Int32) || a.is_a?(Int64) || a.is_a?(Float64)) && (b == 0 || b == 0.0)
                raise VMException.new("divided by 0")
            end
            numeric_op(a, b) do |x, y|
                if x.is_a?(Float64) || y.is_a?(Float64)
                    (x.to_f64 / y.to_f64).floor
                else
                    x.to_i64 // y.to_i64
                end
            end
        end

        private def bit_and(a : Bytecode::Value, b : Bytecode::Value) : Bytecode::Value
            overload = invoke_operator_overload(a, "&", b)
            return overload unless overload.nil?
            integer_op(a, b) { |x, y| x & y }
        end

        private def bit_or(a : Bytecode::Value, b : Bytecode::Value) : Bytecode::Value
            overload = invoke_operator_overload(a, "|", b)
            return overload unless overload.nil?
            integer_op(a, b) { |x, y| x | y }
        end

        private def bit_xor(a : Bytecode::Value, b : Bytecode::Value) : Bytecode::Value
            overload = invoke_operator_overload(a, "^", b)
            return overload unless overload.nil?
            integer_op(a, b) { |x, y| x ^ y }
        end

        private def shift_left(a : Bytecode::Value, b : Bytecode::Value) : Bytecode::Value
            overload = invoke_operator_overload(a, "<<", b)
            return overload unless overload.nil?
            integer_op(a, b) { |x, y| x << y }
        end

        private def shift_right(a : Bytecode::Value, b : Bytecode::Value) : Bytecode::Value
            overload = invoke_operator_overload(a, ">>", b)
            return overload unless overload.nil?
            integer_op(a, b) { |x, y| x >> y }
        end

        private def integer_op(a : Bytecode::Value, b : Bytecode::Value)
            case a
            when Int32, Int64
                lhs = a.to_i64
                rhs = case b
                    when Int32, Int64 then b.to_i64
                    else raise "Type error"
                end
                yield lhs, rhs
            else
                raise "Type error"
            end
        end

        private def invoke_operator_overload(receiver : Bytecode::Value, method : String, arg : Bytecode::Value) : Bytecode::Value?
            return nil unless receiver.is_a?(Bytecode::InstanceValue) || receiver.is_a?(Bytecode::ClassValue) || receiver.is_a?(Bytecode::ModuleValue)
            invoke_method(receiver, method, [arg] of Bytecode::Value, nil)
        rescue
            nil
        end
        
        private def sub(a, b)
            overload = invoke_operator_overload(a, "-", b)
            return overload unless overload.nil?
            numeric_op(a, b) { |x, y| x - y }
        end
        
        private def mul(a, b)
            overload = invoke_operator_overload(a, "*", b)
            return overload unless overload.nil?
            numeric_op(a, b) { |x, y| x * y }
        end
        
        private def div(a, b)
            overload = invoke_operator_overload(a, "/", b)
            return overload unless overload.nil?
            if (a.is_a?(Int32) || a.is_a?(Int64) || a.is_a?(Float64)) && (b == 0 || b == 0.0)
                raise VMException.new("divided by 0")
            end
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
            overload = invoke_operator_overload(a, "<", b)
            return overload unless overload.nil?
            numeric_compare(a, b) { |x, y| x < y }
        end
        
        private def compare_le(a, b)
            overload = invoke_operator_overload(a, "<=", b)
            return overload unless overload.nil?
            numeric_compare(a, b) { |x, y| x <= y }
        end
        
        private def compare_gt(a, b)
            overload = invoke_operator_overload(a, ">", b)
            return overload unless overload.nil?
            numeric_compare(a, b) { |x, y| x > y }
        end
        
        private def compare_ge(a, b)
            overload = invoke_operator_overload(a, ">=", b)
            return overload unless overload.nil?
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

        private def spaceship_compare(a, b) : Int64
            overload = invoke_operator_overload(a, "<=>", b)
            if overload
                if overload.is_a?(Int64)
                    return overload
                elsif overload.is_a?(Int32)
                    return overload.to_i64
                end
            end

            case a
            when Int32, Int64, Float64
                numeric_spaceship(a, b)
            when String
                string_spaceship(a, b)
            else
                raise ::Dragonstone::TypeError.new("Cannot compare #{type_of(a)} with #{type_of(b)}")
            end
        end

        private def pow(a : Bytecode::Value, b : Bytecode::Value) : Bytecode::Value
            overload = invoke_operator_overload(a, "**", b)
            return overload unless overload.nil?

            case a
            when Int32, Int64
                base = a.to_i64
                exp = case b
                    when Int32, Int64 then b.to_i64
                    when Float64 then b.to_i64
                    else
                        raise "Type error"
                    end

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
            when Float64
                exponent = case b
                    when Int32, Int64 then b.to_f64
                    when Float64 then b
                    else
                        raise "Type error"
                    end
                a ** exponent
            else
                raise "Type error"
            end
        end

        private def numeric_spaceship(a, b) : Int64
            unless b.is_a?(Int32) || b.is_a?(Int64) || b.is_a?(Float64)
                raise ::Dragonstone::TypeError.new("Cannot compare #{type_of(a)} with #{type_of(b)}")
            end
            l = a.is_a?(Float64) ? a : a.to_f64
            r = b.is_a?(Float64) ? b : b.to_f64
            return -1_i64 if l < r
            return 1_i64 if l > r
            0_i64
        end

        private def string_spaceship(a : String, b) : Int64
            unless b.is_a?(String)
                raise ::Dragonstone::TypeError.new("Cannot compare #{type_of(a)} with #{type_of(b)}")
            end
            (a <=> b).to_i64
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

        private def build_range(a : Bytecode::Value, b : Bytecode::Value, inclusive : Bool) : Bytecode::Value
            if a.is_a?(Int32) || a.is_a?(Int64)
                start = a.to_i64
                finish = if b.is_a?(Int32) || b.is_a?(Int64)
                    b.to_i64
                else
                    raise "Unsupported range endpoint"
                end
                inclusive ? Range.new(start, finish) : Range.new(start, finish, exclusive: true)
            elsif a.is_a?(Char)
                if b.is_a?(Char)
                    inclusive ? Range.new(a, b) : Range.new(a, b, exclusive: true)
                else
                    raise "Unsupported range endpoint"
                end
            else
                raise "Unsupported range endpoints"
            end
        end
        
        private def truthy?(value : Bytecode::Value) : Bool
            case value
            when Nil then false
            when Bool then value
            else true
            end
        end
        
        private def stringify(value : Bytecode::Value) : String
            display_value(value)
        end

        private def display_value(value : Bytecode::Value) : String
            case value
            when Nil
                ""
            when Bool, Int32, Int64, Float64
                value.to_s
            when String
                value
            when Char
                value.to_s
            when SymbolValue
                value.name
            when Array
                "[#{value.map { |element| display_value(element) }.join(", ")}]"
            when Bytecode::MapValue
                pairs = [] of String
                value.entries.each do |key, val|
                    pairs << "#{display_value(key)} -> #{display_value(val)}"
                end
                "{#{pairs.join(", ")}}"
            when Bytecode::BagValue
                "[#{value.elements.map { |element| display_value(element) }.join(", ")}]"
            when Bytecode::TupleValue
                "{#{value.elements.map { |element| display_value(element) }.join(", ")}}"
            when Bytecode::NamedTupleValue
                pairs = [] of String
                value.entries.each do |key, val|
                    pairs << "#{key.name}: #{display_value(val)}"
                end
                "{#{pairs.join(", ")}}"
            when Bytecode::ModuleValue
                "#<Module>"
            when Bytecode::RaisedExceptionValue
                value.message
            when Bytecode::ClassValue
                value.name
            when Bytecode::StructValue
                value.name
            when Bytecode::InstanceValue
                "#<#{value.klass.name}>"
            when Bytecode::EnumValue
                value.name
            when Bytecode::EnumMemberValue
                value.name
            when Bytecode::FunctionValue
                "#<Function #{value.name}>"
            when Bytecode::BlockValue
                "#<Block>"
            when FFIModule
                "ffi"
            else
                value.to_s
            end
        end

        private def inspect_value(value : Bytecode::Value) : String
            case value
            when Nil
                "nil"
            when String
                value.inspect
            when Bool, Int32, Int64, Float64
                value.to_s
            when Char
                value.inspect
            when SymbolValue
                value.inspect
            when Array
                "[#{value.map { |element| inspect_value(element) }.join(", ")}]"
            when Bytecode::MapValue
                pairs = [] of String
                value.entries.each do |key, val|
                    pairs << "#{inspect_value(key)} -> #{inspect_value(val)}"
                end
                "{#{pairs.join(", ")}}"
            when Bytecode::BagValue
                "[#{value.elements.map { |element| inspect_value(element) }.join(", ")}]"
            when Bytecode::TupleValue
                "{#{value.elements.map { |element| inspect_value(element) }.join(", ")}}"
            when Bytecode::NamedTupleValue
                pairs = [] of String
                value.entries.each do |key, val|
                    pairs << "#{key.name}: #{inspect_value(val)}"
                end
                "{#{pairs.join(", ")}}"
            when Bytecode::ModuleValue
                "#<Module>"
            when Bytecode::RaisedExceptionValue
                value.message
            when Bytecode::ClassValue
                value.name
            when Bytecode::StructValue
                value.name
            when Bytecode::InstanceValue
                "#<#{value.klass.name}>"
            when Bytecode::EnumValue
                value.name
            when Bytecode::EnumMemberValue
                value.name
            when Bytecode::FunctionValue
                "#<Function #{value.name}>"
            when Bytecode::BlockValue
                "#<Block>"
            when FFIModule
                "ffi"
            else
                value.to_s
            end
        end
        
        private def type_of(value : Bytecode::Value) : String
            case value
            when Nil then "Nil"
            when Bool then "Boolean"
            when Int32, Int64 then "Integer"
            when Float64 then "Float"
            when String then "String"
            when Array then "Array"
            when Bytecode::MapValue then "Map"
            when Bytecode::BagValue then "Bag"
            when Bytecode::TupleValue then "Tuple"
            when Bytecode::NamedTupleValue then "NamedTuple"
            when Bytecode::ModuleValue then "Module"
            when Bytecode::RaisedExceptionValue then "Exception"
            when Bytecode::ClassValue then "Class"
            when Bytecode::StructValue then "Struct"
            when Bytecode::InstanceValue then "Instance"
            when Bytecode::EnumValue then "Enum"
            when Bytecode::EnumMemberValue then "EnumMember"
            when Range(Int64, Int64) then "Range"
            when Range(Char, Char) then "Range"
            when Bytecode::FunctionValue then "Function"
            when Bytecode::BlockValue then "Block"
            when FFIModule then "FFIModule"
            when ::Dragonstone::Runtime::GC::Area(Bytecode::Value) then "Area"
            when Bytecode::GCHost then "GC"
            else "Object"
            end
        end
        
        private def index_access(obj : Bytecode::Value, index : Bytecode::Value) : Bytecode::Value
            case obj

            when Array
                idx = ensure_integer_index(index, "Array")
                obj[idx]? || nil

            when String
                idx = ensure_integer_index(index, "String")
                char = obj[idx]?
                char ? char.to_s : nil
            when Bytecode::TupleValue
                idx = ensure_integer_index(index, "Tuple")
                obj.elements[idx]? || nil
            when Bytecode::NamedTupleValue
                key = named_tuple_key(index)
                obj.entries[key]?
            when Bytecode::MapValue
                obj[index]?
            else
                raise "Cannot index #{type_of(obj)}"
            end
        end

        private def assign_index_value(obj : Bytecode::Value, index : Bytecode::Value, value : Bytecode::Value) : Bytecode::Value
            case obj

            when Array
                idx = ensure_integer_index(index, "Array")
                obj[idx] = value
                value

            when Bytecode::MapValue
                obj[index] = value
                value

            else
                raise ::Dragonstone::TypeError.new("Cannot assign index on #{type_of(obj)}")

            end
        end

        private def ensure_integer_index(index : Bytecode::Value, container : String) : Int32
            case index
            when Int32
                index
            when Int64
                index.to_i
            when Float64
                index.to_i
            else
                raise ::Dragonstone::TypeError.new("#{container} index must be integer")
            end
        end

        private def named_tuple_key(index : Bytecode::Value) : SymbolValue
            case index
            when SymbolValue
                index
            when String
                SymbolValue.new(index)
            else
                raise ::Dragonstone::TypeError.new("NamedTuple index must be Symbol or String")
            end
        end

        private def conversion_method?(name : String) : Bool
            name == "display" || name == "inspect"
        end

        private def ensure_conversion_call_valid(args : Array(Bytecode::Value), block_value : Bytecode::BlockValue?, method : String) : Nil
            raise ArgumentError.new("#{method} does not accept a block") if block_value
            unless args.empty?
                raise ArgumentError.new("#{method} does not take arguments")
            end
        end

        private def conversion_result(receiver : Bytecode::Value, method : String) : String
            case method
            when "display"
                display_value(receiver)
            when "inspect"
                inspect_value(receiver)
            else
                raise "Unsupported conversion method #{method}"
            end
        end
        
        private def invoke_method(receiver : Bytecode::Value, method : String, args : Array(Bytecode::Value), block_value : Bytecode::BlockValue?) : Bytecode::Value
            
            # Checks if its FFI.
            if receiver.is_a?(FFIModule)
                return call_ffi_method(method, args)
            end

            if method == "nil?"
                ensure_conversion_call_valid(args, block_value, method)
                return receiver.nil?
            end

            if conversion_method?(method)
                ensure_conversion_call_valid(args, block_value, method)
                return conversion_result(receiver, method)
            end

            if fn = lookup_singleton_method(receiver, method)
                return call_function_value(fn, args, block_value, receiver)
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
                when "slice"
                    raise ArgumentError.new("String##{method} does not accept a block") if block_value
                    if args.size == 2
                        start = ensure_integer_index(args[0], "String")
                        count = ensure_integer_index(args[1], "String")
                        if start < 0 || count < 0 || start >= receiver.size
                            raise ::Dragonstone::OutOfBounds.new("Slice out of bounds")
                        end
                        receiver[start, count]
                    elsif args.size == 1 && args[0].is_a?(Range(Int64, Int64))
                        range = args[0].as(Range(Int64, Int64))
                        start = range.begin.to_i
                        last = range.end.to_i
                        last -= 1 if range.exclusive?
                        count = last - start + 1
                        receiver[start, count]
                    else
                        raise ArgumentError.new("Invalid arguments for String#slice")
                    end
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
                when "empty", "empty?"
                    raise ArgumentError.new("Array##{method} does not accept a block") if block_value
                    array.empty?
                when "pop"
                    raise ArgumentError.new("Array##{method} does not accept a block") if block_value
                    array.pop?
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
            when Bytecode::MapValue
                call_map_method(receiver, method, args, block_value)
            when Bytecode::BlockValue
                case method
                when "call"
                    raise ArgumentError.new("Block##{method} does not accept a block") if block_value
                    signature = receiver.signature
                    ensure_arity(signature, args.size, "<block>")
                    depth_before = @frames.size
                    push_callable_frame(receiver.code, signature, args, nil, "<block>")
                    execute_with_frame_cleanup(depth_before)
                else
                    raise "Unknown method '#{method}' on Block"
                end
            when Bytecode::FunctionValue
                call_function_method(receiver, method, args, block_value)
            when Bytecode::TupleValue
                call_tuple_method(receiver, method, args, block_value)
            when Bytecode::NamedTupleValue
                call_named_tuple_method(receiver, method, args, block_value)
            when Bytecode::RaisedExceptionValue
                case method
                when "message"
                    raise ArgumentError.new("Exception##{method} does not accept a block") if block_value
                    raise ArgumentError.new("Exception##{method} does not take arguments") unless args.empty?
                    receiver.message
                else
                    raise "Unknown method #{method} on Exception"
                end
            when Bytecode::ClassValue
                if method == "new"
                    raise ArgumentError.new("#{receiver.name}.new does not accept a block") if block_value
                    if receiver.abstract?
                        raise ::Dragonstone::TypeError.new("Cannot instantiate abstract class #{receiver.name}")
                    end
                    missing = receiver.unimplemented_abstract_methods
                    unless missing.empty?
                        raise ::Dragonstone::TypeError.new("#{receiver.name} must implement abstract methods: #{missing.to_a.sort.join(", ")}")
                    end
                    instance = Bytecode::InstanceValue.new(receiver)
                    if init_info = receiver.lookup_method_with_owner("initialize")
                        call_function_value(init_info[:method], args, nil, instance, method_owner: init_info[:owner])
                    end
                    instance
                else
                    call_container_method(receiver, method, args, block_value, receiver)
                end
            when Bytecode::StructValue
                if method == "new"
                    raise ArgumentError.new("#{receiver.name}.new does not accept a block") if block_value
                    missing = receiver.unimplemented_abstract_methods
                    unless missing.empty?
                        raise ::Dragonstone::TypeError.new("#{receiver.name} must implement abstract methods: #{missing.to_a.sort.join(", ")}")
                    end
                    instance = Bytecode::InstanceValue.new(receiver)
                    if init_info = receiver.lookup_method_with_owner("initialize")
                        call_function_value(init_info[:method], args, nil, instance, method_owner: init_info[:owner])
                    end
                    instance
                else
                    call_container_method(receiver, method, args, block_value, receiver)
                end
            when Bytecode::EnumValue
                call_enum_method(receiver, method, args, block_value)
            when Bytecode::EnumMemberValue
                call_enum_member_method(receiver, method, args, block_value)
            when Bytecode::ModuleValue
                call_container_method(receiver, method, args, block_value, receiver)
            when Bytecode::InstanceValue
                call_instance_method(receiver, method, args, block_value)
            when Range(Int64, Int64)
                call_range_method(receiver, method, args, block_value)
            when Range(Char, Char)
                call_range_method(receiver, method, args, block_value)
            when Bytecode::GCHost
                call_gc_method(receiver, method, args, block_value)
            else
                raise "Cannot call method #{method} on #{type_of(receiver)}"
            end
        end

        private def invoke_super_method(args : Array(Bytecode::Value), block_value : Bytecode::BlockValue?) : Bytecode::Value
            frame = current_frame
            owner = frame.method_owner
            method_name = frame.callable_name

            unless owner && method_name && method_name != "<block>"
                raise ::Dragonstone::InterpreterError.new("'super' used outside of a method")
            end

            receiver_self = current_self_safe
            raise ::Dragonstone::InterpreterError.new("'super' requires a receiver") unless receiver_self

            super_class = owner.not_nil!.superclass
            raise ::Dragonstone::NameError.new("No superclass available for #{owner.not_nil!.name}") unless super_class

            info = super_class.not_nil!.lookup_method_with_owner(method_name.not_nil!)
            raise ::Dragonstone::NameError.new("Undefined method '#{method_name}' for superclass of #{owner.not_nil!.name}") unless info

            fn = info.not_nil![:method]
            super_owner = info.not_nil![:owner]
            if fn.abstract?
                raise ::Dragonstone::TypeError.new("Cannot invoke abstract method #{method_name} on #{super_owner.name}")
            end

            call_function_value(fn, args, block_value, receiver_self, method_owner: super_owner)
        end

        private def call_function_method(
            function : Bytecode::FunctionValue,
            method : String,
            args : Array(Bytecode::Value),
            block_value : Bytecode::BlockValue?
        ) : Bytecode::Value
            case method
            when "call"
                raise ArgumentError.new("Function#call does not accept a block") if block_value
                signature = function.signature
                ensure_arity(signature, args.size, function.name)
                depth_before = @frames.size
                push_callable_frame(function.code, signature, args, nil, function.name)
                execute_with_frame_cleanup(depth_before)
            else
                raise "Unknown method '#{method}' for Function"
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

        private def call_gc_method(host : Bytecode::GCHost, method : String, args : Array(Bytecode::Value), block_value : Bytecode::BlockValue?) : Bytecode::Value
            manager = host.manager
            case method
            when "disable"
                raise ArgumentError.new("gc.disable does not take arguments") unless args.empty?
                manager.disable
                nil
            when "enable"
                raise ArgumentError.new("gc.enable does not take arguments") unless args.empty?
                manager.enable
                nil
            when "with_disabled"
                raise ArgumentError.new("gc.with_disabled requires a block") unless block_value
                raise ArgumentError.new("gc.with_disabled does not take arguments") unless args.empty?
                manager.with_disabled do
                    call_block(block_value.not_nil!, [] of Bytecode::Value)
                end
            when "begin"
                raise ArgumentError.new("gc.begin does not accept arguments") unless args.empty?
                manager.begin_area
            when "end"
                raise ArgumentError.new("gc.end accepts at most 1 argument") if args.size > 1
                target = args.first?
                if target && !target.is_a?(::Dragonstone::Runtime::GC::Area(Bytecode::Value))
                    raise ArgumentError.new("gc.end expects an Area or no argument")
                end
                manager.end_area(target.as?(::Dragonstone::Runtime::GC::Area(Bytecode::Value)))
                nil
            when "current_area"
                raise ArgumentError.new("gc.current_area does not take arguments") unless args.empty?
                manager.current_area
            when "copy"
                raise ArgumentError.new("gc.copy expects 1 argument") unless args.size == 1
                value = args.first
                unless value.is_a?(Bytecode::Value)
                    raise ArgumentError.new("gc.copy expects a value")
                end
                manager.copy(value.as(Bytecode::Value))
            else
                raise ArgumentError.new("Unknown gc method: #{method}")
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
