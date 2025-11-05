# ---------------------------------
# ----------- Compiler ------------
# ---------------------------------
require "../runtime/opc"
require "../runtime/ffi_module"
require "../lexer/*"
require "../parser/*"
require "../codegen/ast"
require "../runtime/symbol"

module Dragonstone
    module Bytecode
        alias Value = Nil | Bool | Int32 | Int64 | Float64 | String | Char | SymbolValue | Array(Value) | CompiledCode | NamedTuple(name: String, params: Array(Value), code: CompiledCode) | FFIModule
    end

    record CompiledCode,
        code : Array(Int32),
        consts : Array(Bytecode::Value),
        names : Array(String),
        locals_count : Int32

    class Compiler
        include OPC

        class NamePool
            @indexes : Hash(String, Int32)
            @names : Array(String)

            def initialize
                @indexes = {} of String => Int32
                @names = [] of String
            end

            def index_for(name : String) : Int32
                @indexes.fetch(name) do
                    idx = @names.size
                    @indexes[name] = idx
                    @names << name
                    idx
                end
            end

            def to_a : Array(String)
                @names.dup
            end
        end

        def self.compile(ast : AST::Program) : CompiledCode
            new.compile(ast)
        end

        @name_pool : NamePool
        @code : Array(Int32)
        @consts : Array(Bytecode::Value)
        @stack_depth : Int32
        @max_stack : Int32

        def initialize(name_pool : NamePool? = nil)
            @name_pool = name_pool || NamePool.new
            @code = [] of Int32
            @consts = [] of Bytecode::Value
            @stack_depth = 0
            @max_stack = 0
        end

        def compile(ast : AST::Program) : CompiledCode
            compile_program(ast)
            emit(OPC::HALT)
            ensure_stack_clean!
            build_bytecode
        end

        private def build_bytecode : CompiledCode
            CompiledCode.new(
                code: @code.dup,
                consts: @consts.dup,
                names: @name_pool.to_a,
                locals_count: @max_stack
            )
        end

        private def compile_program(node : AST::Program)
            compile_statements(node.statements)
        end

        def compile_statements(statements : Array(AST::Node))
            statements.each { |stmt| compile_statement(stmt) }
        end

        private def compile_statement(node : AST::Node)
            case node

            when AST::AliasDefinition
                # Type aliases do not emit runtime code.
                return

            when AST::ReturnStatement
                compile_return(node)
                
            when AST::FunctionDef
                compile_function_def(node)
                emit(OPC::POP)

            when AST::IfStatement
                compile_if(node)
                emit(OPC::POP)

            when AST::WhileStatement
                compile_while(node)
                emit(OPC::POP)

            when AST::DebugPrint
                compile_debug_print(node)
                emit(OPC::POP)
                
            when AST::Assignment
                compile_assignment(node)
                emit(OPC::POP)

            else
                compile_expression(node)
                emit(OPC::POP)

            end
        end

        private def compile_expression(node : AST::Node)
            case node

            when AST::Literal
                emit_const(node.value)

            when AST::Variable
                emit_load_name(node.name)

            when AST::Assignment
                compile_assignment(node)

            when AST::BinaryOp
                compile_binary(node)

            when AST::MethodCall
                compile_method_call(node)

            when AST::DebugPrint
                compile_debug_print(node)

            when AST::IfStatement
                compile_if(node)

            when AST::WhileStatement
                compile_while(node)

            when AST::InterpolatedString
                compile_interpolated_string(node)

            when AST::ArrayLiteral
                compile_array_literal(node)

            when AST::IndexAccess
                compile_index_access(node)

            when AST::UnaryOp
                compile_unary(node)

            when AST::FunctionDef
                compile_function_def(node)

            when AST::ReturnStatement
                compile_return(node)

            else
                raise ArgumentError.new("Unhandled AST node #{node.class}")
            end
        end

        private def compile_assignment(node : AST::Assignment)
            compile_expression(node.value)
            emit_store_name(node.name)
        end

        BINARY_OPCODE = {
            :+   => OPC::ADD,
            :"&+" => OPC::ADD,
            :-   => OPC::SUB,
            :"&-" => OPC::SUB,
            :*   => OPC::MUL,
            :"&*" => OPC::MUL,
            :/   => OPC::DIV,
            :==  => OPC::EQ,
            :!=  => OPC::NE,
            :<   => OPC::LT,
            :<=  => OPC::LE,
            :>   => OPC::GT,
            :>=  => OPC::GE,
        }

        private def compile_binary(node : AST::BinaryOp)
            compile_expression(node.left)
            compile_expression(node.right)
            opcode = BINARY_OPCODE[node.operator]?
            raise ArgumentError.new("Unknown operator #{node.operator}") unless opcode
            emit(opcode)
        end

        UNARY_OPCODE = {
            :+  => OPC::POS,
            :"&+" => OPC::POS,
            :-  => OPC::NEG,
            :"&-" => OPC::NEG,
            :!  => OPC::NOT,
            :~  => OPC::BIT_NOT,
        }

        private def compile_unary(node : AST::UnaryOp)
            compile_expression(node.operand)
            opcode = UNARY_OPCODE[node.operator]?
            raise ArgumentError.new("Unhandled unary operator #{node.operator}") unless opcode
            emit(opcode)
        end

        private def compile_method_call(node : AST::MethodCall)
            if receiver = node.receiver

                # Load the ffi module onto the stack.
                if receiver.is_a?(AST::Variable) && receiver.name == "ffi"
                    compile_expression(receiver)
                    node.arguments.each { |arg| compile_expression(arg) }
                    emit(OPC::INVOKE, name_index(node.name), node.arguments.size)
                    return
                end

                compile_expression(receiver)
                node.arguments.each { |arg| compile_expression(arg) }
                emit(OPC::INVOKE, name_index(node.name), node.arguments.size)
                return
            end

            case node.name
            when "echo", "puts"
                node.arguments.each { |arg| compile_expression(arg) }
                emit(OPC::ECHO, node.arguments.size)

            when "typeof"
                node.arguments.each { |arg| compile_expression(arg) }
                emit(OPC::TYPEOF)

            else
                node.arguments.each { |arg| compile_expression(arg) }
                emit(OPC::CALL, node.arguments.size, name_index(node.name))

            end
        end

        private def compile_debug_print(node : AST::DebugPrint)
            source_idx = const_index(node.to_source)
            compile_expression(node.expression)
            emit(OPC::DEBUG_PRINT, source_idx)
        end

        private def compile_if(node : AST::IfStatement)
            compile_expression(node.condition)
            jump_false = emit(OPC::JMPF, 0)

            compile_block(node.then_block)
            emit_nil
            after_then = emit(OPC::JMP, 0)
            patch_jump(jump_false, current_ip)

            end_jumps = [after_then]

            node.elsif_blocks.each do |clause|
                compile_expression(clause.condition)
                clause_false = emit(OPC::JMPF, 0)
                compile_block(clause.block)
                emit_nil
                end_jumps << emit(OPC::JMP, 0)
                patch_jump(clause_false, current_ip)
            end

            if else_block = node.else_block
                compile_block(else_block)
                emit_nil

            else
                emit_nil

            end

            end_jumps.each { |pos| patch_jump(pos, current_ip) }
        end

        private def compile_while(node : AST::WhileStatement)
            loop_start = current_ip
            compile_expression(node.condition)
            exit_jump = emit(OPC::JMPF, 0)
            compile_block(node.block)
            emit(OPC::JMP, loop_start)
            patch_jump(exit_jump, current_ip)
            emit_nil
        end

        private def compile_block(statements : Array(AST::Node))
            compile_statements(statements)
        end

        def compile_function_body(statements : Array(AST::Node)) : CompiledCode
            compile_statements(statements)
            finalize_function_chunk
        end

        private def finalize_function_chunk : CompiledCode
            emit_nil
            emit(OPC::RET)
            ensure_stack_clean!
            build_bytecode
        end

        private def compile_interpolated_string(node : AST::InterpolatedString)
            parts = node.normalized_parts
            return emit_const("") if parts.empty?

            count = 0
            parts.each do |type, content|
                if type == :string
                    emit_const(content)
                    
                else
                    expression_node = interpolation_expression(content)
                    compile_expression(expression_node)
                    emit(OPC::TO_S)

                end
                count += 1
            end

            (count - 1).times { emit(OPC::CONCAT) } if count > 1
        end

        private def interpolation_expression(content)
            return content if content.is_a?(AST::Node)

            lexer = Lexer.new(content.to_s)
            tokens = lexer.tokenize
            parser = Parser.new(tokens)
            parser.parse_expression_entry
        end

        private def compile_array_literal(node : AST::ArrayLiteral)
            if node.elements.empty?
                emit_const([] of Bytecode::Value)

            else
                node.elements.each { |element| compile_expression(element) }
                emit(OPC::MAKE_ARRAY, node.elements.size)

            end
        end

        private def compile_index_access(node : AST::IndexAccess)
            compile_expression(node.object)
            compile_expression(node.index)
            emit(OPC::INDEX)
        end

        private def compile_return(node : AST::ReturnStatement)
            if value = node.value
                compile_expression(value)

            else
                emit_nil

            end
            emit(OPC::RET)
            @stack_depth = 0
        end

        private def compile_function_def(node : AST::FunctionDef)
            fn_compiler = self.class.new(@name_pool)
            fn_chunk = fn_compiler.compile_function_body(node.body)
            fn_const_idx = const_index(fn_chunk)
            params_const = [] of Bytecode::Value
            node.parameters.each do |param_name|
                params_const << name_index(param_name)
            end
            params_idx = const_index(params_const)
            name_idx = name_index(node.name)

            emit(OPC::MAKE_FUNCTION, name_idx, params_idx, fn_const_idx)
            emit(OPC::STORE, name_idx)
        end

        private def emit_load_name(sym : String)
            emit(OPC::LOAD, name_index(sym))
        end

        private def emit_store_name(sym : String)
            emit(OPC::STORE, name_index(sym))
        end

        private def emit_const(value : Bytecode::Value)
            emit(OPC::CONST, const_index(value))
        end

        private def emit_nil
            emit_const(nil)
        end

        private def name_index(sym : String) : Int32
            @name_pool.index_for(sym)
        end

        private def const_index(value : Bytecode::Value) : Int32
            existing = @consts.index(value)
            return existing if existing

            @consts << value
            @consts.size - 1
        end

        private def emit(opcode : Int32) : Int32
            position = @code.size
            @code << opcode

            adjust_stack(opcode, [] of Int32)
            position
        end

        private def emit(opcode : Int32, *operands : Int32) : Int32
            position = @code.size
            @code << opcode

            @code.concat(operands)

            ops = [] of Int32
            operands.each { |o| ops << o }

            adjust_stack(opcode, ops)
            position
        end

        private def patch_jump(position : Int32, target : Int32)
            @code[position + 1] = target
        end

        private def current_ip : Int32
            @code.size
        end

        private def adjust_stack(opcode : Int32, operands : Array(Int32))
            case opcode

            when OPC::CONST, OPC::LOAD
                stack_push

            when OPC::STORE
                stack_pop
                stack_push

            when OPC::POP
                stack_pop
                
            when OPC::ADD, OPC::SUB, OPC::MUL, OPC::DIV, OPC::EQ, OPC::NE, OPC::LT, OPC::LE, OPC::GT, OPC::GE, OPC::CONCAT
                stack_pop(2)
                stack_push

            when OPC::ECHO
                argc = operands[0]? || 0
                stack_pop(argc)
                stack_push

            when OPC::TYPEOF
                stack_pop
                stack_push

            when OPC::DEBUG_PRINT
                stack_pop
                stack_push

            when OPC::MAKE_ARRAY
                count = operands[0]? || 0
                stack_pop(count)
                stack_push

            when OPC::INDEX
                stack_pop(2)
                stack_push

            when OPC::NEG, OPC::POS, OPC::NOT, OPC::BIT_NOT
                stack_pop
                stack_push

            when OPC::CALL
                argc = operands[0]? || 0
                stack_pop(argc)
                stack_push

            when OPC::INVOKE
                argc = operands[1]? || 0
                stack_pop(argc + 1)
                stack_push

            when OPC::TO_S
                stack_pop
                stack_push

            when OPC::MAKE_FUNCTION
                stack_push

            when OPC::JMPF
                stack_pop

            when OPC::RET
                @stack_depth = 0

            when OPC::HALT, OPC::JMP, OPC::NOP
                # No interop yet.
            end
        end

        private def stack_push(count : Int32 = 1)
            @stack_depth += count
            @max_stack = @stack_depth if @stack_depth > @max_stack
        end

        private def stack_pop(count : Int32 = 1)
            @stack_depth -= count
            raise "Bytecode stack underflow" if @stack_depth < 0
        end

        private def ensure_stack_clean!
            raise "Bytecode stack imbalance" unless @stack_depth == 0
        end
    end
end

