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
        
        @bytecode : CompiledCode
        @ip : Int32
        @stack : Array(Bytecode::Value)
        @globals : Hash(String, Bytecode::Value)

        def initialize(@bytecode : CompiledCode)
            @ip = 0
            @stack = [] of Bytecode::Value
            @globals = {} of String => Bytecode::Value

            # Initialize FFI
            init_ffi_module
        end

        private def init_ffi_module
            @globals["ffi"] = FFIModule.new
        end
    
        def run : Bytecode::Value
            loop do
                opcode = fetch_byte
                
                case opcode
                when OPC::HALT
                    return pop
                when OPC::NOP
                    # nil
                when OPC::CONST
                    idx = fetch_byte
                    push(@bytecode.consts[idx])
                when OPC::LOAD
                    name_idx = fetch_byte
                    name = @bytecode.names[name_idx]
                    value = @globals[name]?
                    raise "Undefined variable: #{name}" unless value
                    push(value)
                when OPC::STORE
                    name_idx = fetch_byte
                    name = @bytecode.names[name_idx]
                    value = peek
                    @globals[name] = value
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
                    @ip = target
                when OPC::JMPF
                    target = fetch_byte
                    condition = pop
                    @ip = target unless truthy?(condition)
                when OPC::PUTS
                    argc = fetch_byte
                    args = pop_values(argc)
                    args.each { |arg| puts stringify(arg) }
                    push(nil)
                when OPC::TYPEOF
                    value = pop
                    push(type_of(value))
                when OPC::DEBUG_PRINT
                    source_idx = fetch_byte
                    source = @bytecode.consts[source_idx]
                    value = pop
                    puts "DEBUG: #{source} => #{stringify(value)}"
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
                    result = invoke_method(receiver, @bytecode.names[name_idx], args)
                    push(result)
                when OPC::CALL
                    argc = fetch_byte
                    name_idx = fetch_byte
                    args = pop_values(argc)
                    result = call_function(@bytecode.names[name_idx], args)
                    push(result)
                when OPC::MAKE_FUNCTION
                    name_idx = fetch_byte
                    params_idx = fetch_byte
                    code_idx = fetch_byte
                    name = @bytecode.names[name_idx]
                    params = @bytecode.consts[params_idx].as(Array(Bytecode::Value))
                    code = @bytecode.consts[code_idx].as(CompiledCode)
                    func_value = {name: name, params: params, code: code}
                    push(func_value)
                when OPC::RET
                    return pop
                else
                    raise "Unknown opcode: #{opcode}"
                end
            end
        end
    
        private def fetch_byte : Int32
            byte = @bytecode.code[@ip]
            @ip += 1
            byte
        end
        
        private def push(value : Bytecode::Value)
            @stack << value
        end
        
        private def pop : Bytecode::Value
            @stack.pop? || raise "Stack underflow"
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

        private def call_function(name : String, args : Array(Bytecode::Value)) : Bytecode::Value
            func = @globals[name]?

            raise "Undefined function: #{name}" unless func
            nil
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
            vm = VM.new(bytecode)
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
