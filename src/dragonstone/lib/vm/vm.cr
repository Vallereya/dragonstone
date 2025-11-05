# ---------------------------------
# ----------- Virtual -------------
# ----------- Machine -------------
# ---------------------------------
require "../lexer/*"
require "../parser/*"
require "../compiler/*"
require "../runtime/opc"
require "../codegen/ffi"
require "../resolver/*"

module Dragonstone
    class VM
        include OPC

        class Frame
            property code : CompiledCode
            property ip : Int32
            property stack_base : Int32
            property locals : Array(Bytecode::Value?)?
            property locals_defined : Array(Bool)?

            def initialize(@code : CompiledCode, @stack_base : Int32, use_locals : Bool = false)
                @ip = 0
                if use_locals
                    size = @code.names.size
                    @locals = Array(Bytecode::Value?).new(size) { nil }
                    @locals_defined = Array(Bool).new(size) { false }
                else
                    @locals = nil
                    @locals_defined = nil
                end
            end
        end

        @bytecode : CompiledCode
        @stack : Array(Bytecode::Value)
        @globals : Hash(String, Bytecode::Value)
        @stdout_io : IO
        @log_to_stdout : Bool
        @frames : Array(Frame)
        @global_slots : Array(Bytecode::Value?)
        @global_defined : Array(Bool)
        @name_index_cache : Hash(String, Int32)
        @globals_dirty : Bool

        def initialize(@bytecode : CompiledCode, globals : Hash(String, Bytecode::Value)? = nil, *, stdout_io : IO = IO::Memory.new, log_to_stdout : Bool = false)
            @stack = [] of Bytecode::Value
            @globals = globals ? globals.dup : {} of String => Bytecode::Value
            @stdout_io = stdout_io
            @log_to_stdout = log_to_stdout
            @frames = [] of Frame
            @global_slots = Array(Bytecode::Value?).new(@bytecode.names.size) { nil }
            @global_defined = Array(Bool).new(@bytecode.names.size) { false }
            @name_index_cache = {} of String => Int32
            @bytecode.names.each_with_index do |name, idx|
                @name_index_cache[name] = idx
            end
            @globals_dirty = false

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
                    value = peek
                    store_variable(name_idx, name, value)
                when OPC::POP
                    pop
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
                    result = invoke_method(receiver, current_code.names[name_idx], args)
                    push(result)
                when OPC::CALL
                    argc = fetch_byte
                    name_idx = fetch_byte
                    args = pop_values(argc)
                    prepare_function_call(name_idx, args)
                when OPC::MAKE_FUNCTION
                    name_idx = fetch_byte
                    params_idx = fetch_byte
                    code_idx = fetch_byte
                    name = current_code.names[name_idx]
                    params = current_code.consts[params_idx].as(Array(Bytecode::Value))
                    code = current_code.consts[code_idx].as(CompiledCode)
                    func_value = {name: name, params: params, code: code}
                    push(func_value)
                when OPC::RET
                    handle_return
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
            if frame.locals
                assign_local(frame, name_idx, value)
            else
                if idx = @name_index_cache[name]?
                    ensure_global_capacity(idx)
                    @global_slots[idx] = value
                    @global_defined[idx] = true
                    @globals_dirty = true
                else
                    @globals[name] = value
                end
            end
        end

        private def prepare_function_call(name_idx : Int32, args : Array(Bytecode::Value)) : Nil
            name = current_code.names[name_idx]
            value = resolve_variable(name_idx, name)
            unless value.is_a?(NamedTuple(name: String, params: Array(Bytecode::Value), code: CompiledCode))
                raise "Undefined function: #{name}"
            end

            params = value[:params].as(Array(Bytecode::Value))
            unless params.size == args.size
                raise "Function #{name} expects #{params.size} arguments, got #{args.size}"
            end

            frame = push_frame(value[:code], true)
            params.each_with_index do |param_value, index|
                param_index = case param_value
                    when Int32
                        param_value
                    when String
                        idx = frame.code.names.index(param_value)
                        raise "Parameter #{param_value} missing from function frame" unless idx
                        idx
                    else
                        raise "Unsupported parameter metadata #{param_value.inspect}"
                    end
                assign_local(frame, param_index, args[index])
            end
        end

        private def push_frame(code : CompiledCode, use_locals : Bool) : Frame
            frame = Frame.new(code, @stack.size, use_locals)
            @frames << frame
            frame
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

        private def handle_return : Nil
            result = pop
            frame = @frames.pop?
            raise "Return from empty frame stack" unless frame
            if @frames.empty?
                raise "Return from top-level frame not supported"
            end
            truncate_stack(frame.stack_base)
            push(result)
        end
        
        private def push(value : Bytecode::Value)
            @stack << value
        end
        
        private def pop : Bytecode::Value
            raise "Stack underflow" if @stack.empty?
            @stack.pop
        end
        
        private def peek : Bytecode::Value
            @stack.last? || raise "Stack empty"
        end

        private def pop_values(count : Int32) : Array(Bytecode::Value)
            values = [] of Bytecode::Value
            count.times { values << pop }
            values.reverse!
            values
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
        
        private def invoke_method(receiver : Bytecode::Value, method : String, args : Array(Bytecode::Value)) : Bytecode::Value
            
            # Checks if its FFI.
            if receiver.is_a?(FFIModule)
                return call_ffi_method(method, args)
            end

            case receiver

            when String
                case method
                when "upcase" then receiver.upcase
                when "downcase" then receiver.downcase
                when "length", "size" then receiver.size.to_i64
                else raise "Unknown method #{method} on String"
                end
            when Array
                case method
                when "length", "size" then receiver.size.to_i64
                when "push"
                    receiver.as(Array(Bytecode::Value)) << args[0]
                    receiver
                else raise "Unknown method #{method} on Array"
                end
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
            tokens = Lexer.new(src).tokenize
            ast = Parser.new(tokens).parse
            bytecode = Compiler.compile(ast)
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
