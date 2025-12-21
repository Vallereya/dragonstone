# ---------------------------------
# ----- Bytecode Codegen ----------
# ---------------------------------
require "../../vm/opc"
require "../../vm/bytecode"
require "../../../shared/language/lexer/lexer"
require "../../../shared/language/parser/parser"
require "../../../shared/language/ast/ast"
require "../../../shared/runtime/symbol"
require "../../../shared/runtime/gc/gc"

module Dragonstone
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
        @container_depth : Int32
        @parameter_name_stack : Array(Array(String))

        def initialize(name_pool : NamePool? = nil)
            @name_pool = name_pool || NamePool.new
            @code = [] of Int32
            @consts = [] of Bytecode::Value
            @stack_depth = 0
            @max_stack = 0
            @container_depth = 0
            @parameter_name_stack = [] of Array(String)
        end

        def compile(ast : AST::Program) : CompiledCode
            name_index("self")
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

        def compile_statements(statements : Array(AST::Node), preserve_last : Bool = false)
            statements.each_with_index do |stmt, index|
                consume_result = !(preserve_last && index == statements.size - 1)
                compile_statement(stmt, consume_result: consume_result)
            end
        end

        private def compile_statement(node : AST::Node, *, consume_result : Bool = true)
            case node

            when AST::AliasDefinition
                compile_alias_definition(node)
                return

            when AST::BreakStatement
                compile_flow_modifier(node.condition, node.condition_type) do
                    emit(OPC::BREAK_SIGNAL)
                end

            when AST::NextStatement
                compile_flow_modifier(node.condition, node.condition_type) do
                    emit(OPC::NEXT_SIGNAL)
                end

            when AST::RedoStatement
                compile_flow_modifier(node.condition, node.condition_type) do
                    emit(OPC::REDO_SIGNAL)
                end

            when AST::RetryStatement
                compile_flow_modifier(node.condition, node.condition_type) do
                    emit(OPC::RETRY)
                end

            when AST::ModuleDefinition
                compile_module_definition(node)
                emit(OPC::POP) if consume_result

            when AST::ClassDefinition
                compile_class_definition(node)
                emit(OPC::POP) if consume_result

            when AST::StructDefinition
                compile_struct_definition(node)
                emit(OPC::POP) if consume_result

            when AST::EnumDefinition
                compile_enum_definition(node)
                emit(OPC::POP) if consume_result
            when AST::ExtendStatement
                compile_extend(node)
                emit(OPC::POP) if consume_result
            when AST::AccessorMacro
                compile_accessor_macro(node)

            when AST::UnlessStatement
                compile_unless(node)
                emit(OPC::POP) if consume_result

            when AST::InstanceVariableDeclaration
                compile_instance_variable_declaration(node)
                emit(OPC::POP) if consume_result

            when AST::ReturnStatement
                compile_return(node)
                
            when AST::FunctionDef
                compile_function_def(node)
                emit(OPC::POP) if consume_result && @container_depth == 0

            when AST::IfStatement
                compile_if(node)
                emit(OPC::POP) if consume_result

            when AST::WhileStatement
                compile_while(node)
                emit(OPC::POP) if consume_result

            when AST::DebugEcho
                compile_debug_echo(node)
                emit(OPC::POP) if consume_result
            when AST::CaseStatement
                compile_case_statement(node)
                emit(OPC::POP) if consume_result
            when AST::RaiseExpression
                compile_raise(node)
                # raise does not return; no POP

            when AST::ConstantDeclaration
                compile_constant_declaration(node)
                emit(OPC::POP) if consume_result

            when AST::Assignment
                compile_assignment(node)
                emit(OPC::POP) if consume_result
            when AST::InstanceVariableAssignment
                compile_instance_variable_assignment(node)
                emit(OPC::POP) if consume_result
            when AST::IndexAssignment
                compile_index_assignment(node)
                emit(OPC::POP) if consume_result
            when AST::AttributeAssignment
                compile_attribute_assignment(node)
                emit(OPC::POP) if consume_result

            else
                compile_expression(node)
                emit(OPC::POP) if consume_result

            end
        end

        private def compile_expression(node : AST::Node)
            case node

            when AST::Literal
                emit_const(node.value)

            when AST::Variable
                emit_load_name(node.name)

            when AST::ArgvExpression
                emit(OPC::LOAD_ARGV)

            when AST::Assignment
                compile_assignment(node)
            when AST::InstanceVariable
                compile_instance_variable(node)

            when AST::BinaryOp
                compile_binary(node)

            when AST::MethodCall
                compile_method_call(node)

            when AST::DebugEcho
                compile_debug_echo(node)

            when AST::IfStatement
                compile_if(node)
            when AST::UnlessStatement
                compile_unless(node)
            when AST::ConditionalExpression
                compile_conditional_expression(node)
            when AST::SuperCall
                compile_super_call(node)

            when AST::WhileStatement
                compile_while(node)

            when AST::InterpolatedString
                compile_interpolated_string(node)

            when AST::ArrayLiteral
                compile_array_literal(node)
            when AST::TupleLiteral
                compile_tuple_literal(node)
            when AST::NamedTupleLiteral
                compile_named_tuple_literal(node)
            when AST::MapLiteral
                compile_map_literal(node)
            when AST::WithExpression
                compile_with_expression(node)

            when AST::IndexAccess
                compile_index_access(node)
            when AST::IndexAssignment
                compile_index_assignment(node)

            when AST::UnaryOp
                compile_unary(node)

            when AST::FunctionDef
                compile_function_def(node)

            when AST::ReturnStatement
                compile_return(node)

            when AST::FunctionLiteral
                compile_function_literal(node)
            when AST::ParaLiteral
                compile_para_literal(node)

            when AST::BlockLiteral
                compile_block_literal(node)

            when AST::BagConstructor
                compile_bag_constructor(node)
            when AST::InstanceVariableDeclaration
                compile_instance_variable_declaration(node)

            when AST::YieldExpression
                compile_yield(node)
            when AST::ConstantPath
                compile_constant_path(node)
            when AST::CaseStatement
                compile_case_statement(node)
            when AST::RaiseExpression
                compile_raise(node)
            when AST::BeginExpression
                compile_begin_expression(node)

            else
                raise ArgumentError.new("Unhandled AST node #{node.class}")
            end
        end

        private def compile_conditional_expression(node : AST::ConditionalExpression)
            compile_expression(node.condition)
            jump_false = emit(OPC::JMPF, 0)

            compile_expression(node.then_branch)
            after_then = emit(OPC::JMP, 0)

            patch_jump(jump_false, current_ip)
            compile_expression(node.else_branch)

            patch_jump(after_then, current_ip)
        end

        private def compile_super_call(node : AST::SuperCall)
            arg_info = extract_call_arguments(node.arguments)
            args = arg_info[:args]
            block_node = arg_info[:block]

            if !node.explicit_arguments?
                args = [] of AST::Node
                if params = @parameter_name_stack.last?
                    params.each { |name| args << AST::Variable.new(name) }
                end
            end

            args.each { |arg| compile_expression(arg) }

            if block_node
                compile_block_literal(block_node)
                emit(OPC::INVOKE_SUPER_BLOCK, args.size)
            else
                emit(OPC::INVOKE_SUPER, args.size)
            end
        end

        private def compile_assignment(node : AST::Assignment)
            if operator = node.operator
                emit_load_name(node.name)
                compile_expression(node.value)
                opcode = BINARY_OPCODE[operator]?
                raise ArgumentError.new("Unsupported compound operator #{operator}") unless opcode
                emit(opcode)
            else
                compile_expression(node.value)
            end
            emit_type_check(node.type_annotation)
            emit_store_name(node.name)
        end

        private def compile_instance_variable(node : AST::InstanceVariable)
            emit(OPC::LOAD_IVAR, name_index(node.name))
        end

        private def compile_instance_variable_declaration(node : AST::InstanceVariableDeclaration)
            emit_nil
        end

        private def compile_instance_variable_assignment(node : AST::InstanceVariableAssignment)
            if node.operator
                raise ArgumentError.new("Compound instance variable assignment is not supported by the core backend yet")
            end
            compile_expression(node.value)
            emit(OPC::STORE_IVAR, name_index(node.name))
        end

        BINARY_OPCODE = {
            :+   => OPC::ADD,
            :"&+" => OPC::ADD,
            :-   => OPC::SUB,
            :"&-" => OPC::SUB,
            :*   => OPC::MUL,
            :"&*" => OPC::MUL,
            :/   => OPC::DIV,
            :"//" => OPC::FLOOR_DIV,
            :%   => OPC::MOD,
            :"**" => OPC::POW,
            :"&**" => OPC::POW,
            :&   => OPC::BIT_AND,
            :|   => OPC::BIT_OR,
            :^   => OPC::BIT_XOR,
            :<<  => OPC::SHL,
            :>>  => OPC::SHR,
            :==  => OPC::EQ,
            :!=  => OPC::NE,
            :<   => OPC::LT,
            :<=  => OPC::LE,
            :>   => OPC::GT,
            :>=  => OPC::GE,
            :<=> => OPC::CMP,
        }

        private def compile_binary(node : AST::BinaryOp)
            case node.operator
            when :"&&"
                compile_logical_and(node)
            when :"||"
                compile_logical_or(node)
            when :"..", :"..."
                compile_range(node)
            else
                compile_standard_binary(node)
            end
        end

        private def compile_range(node : AST::BinaryOp)
            compile_expression(node.left)
            compile_expression(node.right)
            emit(OPC::MAKE_RANGE, node.operator == :".." ? 1 : 0)
        end

        private def compile_standard_binary(node : AST::BinaryOp)
            compile_expression(node.left)
            compile_expression(node.right)
            opcode = BINARY_OPCODE[node.operator]?
            raise ArgumentError.new("Unknown operator #{node.operator}") unless opcode
            emit(opcode)
        end

        private def compile_logical_and(node : AST::BinaryOp)
            compile_expression(node.left)
            emit(OPC::DUP)
            skip_rhs = emit(OPC::JMPF, 0)
            emit(OPC::POP)
            compile_expression(node.right)
            patch_jump(skip_rhs, current_ip)
        end

        private def compile_logical_or(node : AST::BinaryOp)
            compile_expression(node.left)
            emit(OPC::DUP)
            eval_rhs = emit(OPC::JMPF, 0)
            skip_rhs = emit(OPC::JMP, 0)
            patch_jump(eval_rhs, current_ip)
            emit(OPC::POP)
            compile_expression(node.right)
            patch_jump(skip_rhs, current_ip)
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
            arg_info = extract_call_arguments(node.arguments)
            args = arg_info[:args]
            block_node = arg_info[:block]

            if receiver = node.receiver

                # Load the ffi module onto the stack.
                if receiver.is_a?(AST::Variable) && receiver.name == "ffi"
                    compile_expression(receiver)
                    args.each { |arg| compile_expression(arg) }
                    emit(OPC::INVOKE, name_index(node.name), args.size)
                    return
                end

                compile_expression(receiver)
                args.each { |arg| compile_expression(arg) }
                if block_node
                    compile_block_literal(block_node)
                    emit(OPC::INVOKE_BLOCK, name_index(node.name), args.size)
                else
                    emit(OPC::INVOKE, name_index(node.name), args.size)
                end
                return
            end

            case node.name
            when "echo", "puts"
                raise ArgumentError.new("#{node.name} does not accept a block") if block_node
                args.each { |arg| compile_expression(arg) }
                emit(OPC::ECHO, args.size)

            when "eecho"
                raise ArgumentError.new("eecho does not accept a block") if block_node
                args.each { |arg| compile_expression(arg) }
                emit(OPC::EECHO, args.size)

            when "typeof"
                raise ArgumentError.new("typeof does not accept a block") if block_node
                args.each { |arg| compile_expression(arg) }
                emit(OPC::TYPEOF)

            else
                args.each { |arg| compile_expression(arg) }
                if block_node
                    compile_block_literal(block_node)
                    emit(OPC::CALL_BLOCK, args.size, name_index(node.name))
                else
                    emit(OPC::CALL, args.size, name_index(node.name))
                end

            end
        end

        private def extract_call_arguments(arguments : Array(AST::Node)) : NamedTuple(args: Array(AST::Node), block: AST::BlockLiteral?)
            args = [] of AST::Node
            block_node = nil

            arguments.each do |argument|
                if argument.is_a?(AST::BlockLiteral)
                    block_node = argument.as(AST::BlockLiteral)
                else
                    args << argument
                end
            end

            {args: args, block: block_node}
        end

        private def compile_debug_echo(node : AST::DebugEcho)
            source_idx = const_index(node.to_source)
            compile_expression(node.expression)
            emit(node.inline ? OPC::DEBUG_EECHO : OPC::DEBUG_ECHO, source_idx)
        end

        private def compile_unless(node : AST::UnlessStatement)
            compile_expression(node.condition)
            jump_to_body = emit(OPC::JMPF, 0)

            if node.else_block
                compile_block(node.else_block.not_nil!)
                emit_nil
            else
                emit_nil
            end

            after_else = emit(OPC::JMP, 0)
            patch_jump(jump_to_body, current_ip)

            compile_block(node.body)
            emit_nil

            patch_jump(after_else, current_ip)
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
            enter_pos = emit(OPC::ENTER_LOOP, loop_start, 0, 0)
            body_start = current_ip
            compile_block(node.block)
            emit(OPC::EXIT_LOOP)
            emit(OPC::JMP, loop_start)
            exit_ip = current_ip
            patch_jump(exit_jump, exit_ip)
            # Patch loop metadata operands: condition_ip already set, fill body and exit.
            @code[enter_pos + 2] = body_start
            @code[enter_pos + 3] = exit_ip
            emit_nil
        end

        private def compile_block(statements : Array(AST::Node), preserve_last : Bool = false)
            compile_statements(statements, preserve_last)
        end

        private def enter_container(&block)
            @container_depth += 1
            name_index("self")
            yield
        ensure
            @container_depth -= 1
        end

        private def compile_begin_expression(node : AST::BeginExpression)
            if node.rescue_clauses.empty? && node.ensure_block.nil?
                compile_block(node.body)
                return
            end

            rescue_label = 0
            ensure_label = 0

            handler_pos = emit(OPC::PUSH_HANDLER, 0, 0, 0)
            body_start = current_ip

            compile_block(node.body, preserve_last: true)
            after_body = emit(OPC::JMP, 0)

            rescue_label = node.rescue_clauses.empty? ? -1 : current_ip
            rescue_jumps = [] of Int32
            node.rescue_clauses.each do |clause|
                if var = clause.exception_variable
                    emit(OPC::LOAD_EXCEPTION)
                    emit(OPC::STORE, name_index(var))
                end
                compile_block(clause.body, preserve_last: true)
                rescue_jumps << emit(OPC::JMP, 0)
            end

            ensure_label = current_ip
            if node.ensure_block
                compile_block(node.ensure_block.not_nil!)
            end
            emit(OPC::CHECK_RETHROW)
            emit(OPC::POP_HANDLER)

            @code[handler_pos + 1] = rescue_label
            @code[handler_pos + 2] = ensure_label
            @code[handler_pos + 3] = body_start
            patch_jump(after_body, ensure_label)
            rescue_jumps.each { |pos| patch_jump(pos, ensure_label) }
        end

        private def compile_raise(node : AST::RaiseExpression)
            if node.expression
                compile_expression(node.expression.not_nil!)
            else
                emit_nil
            end
            emit(OPC::RAISE)
            @stack_depth = 0
        end

        def compile_function_body(statements : Array(AST::Node), preserve_last : Bool = false, parameter_names : Array(String) = [] of String) : CompiledCode
            @parameter_name_stack << parameter_names
            begin
                compile_statements(statements, preserve_last)
                use_default_nil = !preserve_last || @stack_depth == 0
                finalize_function_chunk(use_default_nil)
            ensure
                @parameter_name_stack.pop
            end
        end

        private def finalize_function_chunk(use_default_nil : Bool = true) : CompiledCode
            emit_nil if use_default_nil
            emit(OPC::RET)
            @stack_depth = 0
            ensure_stack_clean!
            build_bytecode
        end

        private def compile_flow_modifier(condition : AST::Node?, condition_type : Symbol?, &block)
            unless condition
                yield
                return
            end

            compile_expression(condition)
            emit(OPC::NOT) if condition_type == :unless
            skip_jump = emit(OPC::JMPF, 0)
            yield
            patch_jump(skip_jump, current_ip)
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
            node.elements.each { |element| compile_expression(element) }
            emit(OPC::MAKE_ARRAY, node.elements.size)
        end

        private def compile_tuple_literal(node : AST::TupleLiteral)
            if node.elements.empty?
                emit_const(Bytecode::TupleValue.new([] of Bytecode::Value))
                return
            end

            node.elements.each { |element| compile_expression(element) }
            emit(OPC::MAKE_TUPLE, node.elements.size)
        end

        private def compile_named_tuple_literal(node : AST::NamedTupleLiteral)
            if node.entries.empty?
                emit_const(Bytecode::NamedTupleValue.new)
                return
            end

            node.entries.each do |entry|
                symbol_idx = const_index(SymbolValue.new(entry.name))
                emit(OPC::CONST, symbol_idx)
                compile_expression(entry.value)
            end
            emit(OPC::MAKE_NAMED_TUPLE, node.entries.size)
        end

        private def compile_map_literal(node : AST::MapLiteral)
            node.entries.each do |(key_node, value_node)|
                compile_expression(key_node)
                compile_expression(value_node)
            end
            emit(OPC::MAKE_MAP, node.entries.size)
        end

        private def compile_index_access(node : AST::IndexAccess)
            compile_expression(node.object)
            compile_expression(node.index)
            emit(OPC::INDEX)
        end

        private def compile_index_assignment(node : AST::IndexAssignment)
            if node.operator
                raise ArgumentError.new("Compound index assignment is not supported by the core backend yet")
            end
            if node.nil_safe
                raise ArgumentError.new("Nil-safe index assignment is not supported by the core backend yet")
            end

            compile_expression(node.object)
            compile_expression(node.index)
            compile_expression(node.value)
            emit(OPC::STORE_INDEX)
        end

        private def compile_attribute_assignment(node : AST::AttributeAssignment)
            setter_idx = name_index("#{node.name}=")
            getter_idx = name_index(node.name)

            if operator = node.operator
                compile_expression(node.receiver)
                emit(OPC::DUP)
                emit(OPC::INVOKE, getter_idx, 0)
                compile_expression(node.value)
                opcode = BINARY_OPCODE[operator]?
                raise ArgumentError.new("Unsupported compound operator #{operator}") unless opcode
                emit(opcode)
            else
                compile_expression(node.receiver)
                compile_expression(node.value)
            end

            emit(OPC::INVOKE, setter_idx, 1)
        end

        private def compile_with_expression(node : AST::WithExpression)
            self_idx = name_index("self")
            tmp_idx = name_index("__with_prev_self")
            result_tmp_idx = name_index("__with_result")

            emit(OPC::LOAD, self_idx) rescue nil
            emit(OPC::STORE, tmp_idx)

            compile_expression(node.receiver)
            emit(OPC::STORE, self_idx)

            compile_block(node.body, preserve_last: true)
            emit(OPC::STORE, result_tmp_idx)

            emit(OPC::LOAD, tmp_idx)
            emit(OPC::STORE, self_idx)
            emit(OPC::POP)

            emit(OPC::LOAD, result_tmp_idx)
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
            if node.abstract && @container_depth == 0
                raise "'abstract def' is only allowed inside classes or modules"
            end

            if node.receiver
                compile_singleton_function_def(node)
                return
            end

            fn_compiler = self.class.new(@name_pool)
            fn_chunk = fn_compiler.compile_function_body(node.body, preserve_last: true, parameter_names: node.typed_parameters.map(&.name))
            fn_const_idx = const_index(fn_chunk)
            gc_flags = ::Dragonstone::Runtime::GC.flags_from_annotations(node.annotations)
            signature_idx = const_index(build_signature(node.typed_parameters, node.return_type, node.abstract, gc_flags))
            name_idx = name_index(node.name)

            emit(OPC::MAKE_FUNCTION, name_idx, signature_idx, fn_const_idx)
            if @container_depth > 0
                emit(OPC::DEFINE_METHOD, name_idx)
            else
                emit(OPC::STORE, name_idx)
            end
        end

        private def compile_singleton_function_def(node : AST::FunctionDef)
            compile_expression(node.receiver.not_nil!)

            name_index("self")
            fn_compiler = self.class.new(@name_pool)
            fn_chunk = fn_compiler.compile_function_body(node.body, preserve_last: true, parameter_names: node.typed_parameters.map(&.name))
            fn_const_idx = const_index(fn_chunk)
            gc_flags = ::Dragonstone::Runtime::GC.flags_from_annotations(node.annotations)
            signature_idx = const_index(build_signature(node.typed_parameters, node.return_type, node.abstract, gc_flags))
            name_idx = name_index(node.name)

            emit(OPC::MAKE_FUNCTION, name_idx, signature_idx, fn_const_idx)
            emit(OPC::DEFINE_SINGLETON_METHOD)
        end

        private def compile_function_literal(node : AST::FunctionLiteral)
            fn_compiler = self.class.new(@name_pool)
            chunk = fn_compiler.compile_function_body(node.body, preserve_last: true, parameter_names: node.typed_parameters.map(&.name))
            chunk_idx = const_index(chunk)
            signature_idx = const_index(build_signature(node.typed_parameters, node.return_type))
            name_idx = name_index("<lambda>")
            emit(OPC::MAKE_FUNCTION, name_idx, signature_idx, chunk_idx)
        end

        private def compile_para_literal(node : AST::ParaLiteral)
            fn_compiler = self.class.new(@name_pool)
            chunk = fn_compiler.compile_function_body(node.body, preserve_last: true, parameter_names: node.typed_parameters.map(&.name))
            chunk_idx = const_index(chunk)
            signature_idx = const_index(build_signature(node.typed_parameters, node.return_type))
            name_idx = name_index("<lambda>")
            emit(OPC::MAKE_FUNCTION, name_idx, signature_idx, chunk_idx)
        end

        private def compile_block_literal(node : AST::BlockLiteral)
            block_compiler = self.class.new(@name_pool)
            chunk = block_compiler.compile_function_body(node.body, preserve_last: true, parameter_names: node.typed_parameters.map(&.name))
            chunk_idx = const_index(chunk)
            signature_idx = const_index(build_signature(node.typed_parameters, nil))
            emit(OPC::MAKE_BLOCK, signature_idx, chunk_idx)
        end

        private def compile_bag_constructor(node : ::Dragonstone::AST::BagConstructor)
            emit_const(::Dragonstone::Bytecode::BagConstructorValue.new(node.element_type))
        end

        private def compile_constant_declaration(node : AST::ConstantDeclaration)
            compile_expression(node.value)
            emit_type_check(node.type_annotation)
            if @container_depth > 0
                emit(OPC::DEFINE_CONST, name_index(node.name))
            else
                emit(OPC::STORE, name_index(node.name))
            end
        end

        private def compile_module_definition(node : AST::ModuleDefinition)
            name_idx = name_index(node.name)
            emit(OPC::MAKE_MODULE, name_idx)
            if @container_depth > 0
                emit(OPC::DEFINE_CONST, name_idx)
            else
                emit(OPC::STORE, name_idx)
            end
            emit(OPC::LOAD, name_idx)
            emit(OPC::ENTER_CONTAINER)
            enter_container do
                compile_block(node.body)
            end
            emit(OPC::EXIT_CONTAINER)
            emit(OPC::POP)
            emit_nil
        end

        private def compile_class_definition(node : AST::ClassDefinition)
            name_idx = name_index(node.name)
            super_idx = node.superclass ? const_index(node.superclass.not_nil!) : -1
            emit(OPC::MAKE_CLASS, name_idx, node.abstract ? 1 : 0, super_idx)
            if @container_depth > 0
                emit(OPC::DEFINE_CONST, name_idx)
            else
                emit(OPC::STORE, name_idx)
            end
            emit(OPC::LOAD, name_idx)
            emit(OPC::ENTER_CONTAINER)
            enter_container do
                compile_block(node.body)
            end
            emit(OPC::EXIT_CONTAINER)
            emit(OPC::POP)
            emit_nil
        end

        private def compile_struct_definition(node : AST::StructDefinition)
            name_idx = name_index(node.name)
            emit(OPC::MAKE_STRUCT, name_idx)
            if @container_depth > 0
                emit(OPC::DEFINE_CONST, name_idx)
            else
                emit(OPC::STORE, name_idx)
            end
            emit(OPC::LOAD, name_idx)
            emit(OPC::ENTER_CONTAINER)
            enter_container do
                compile_block(node.body)
            end
            emit(OPC::EXIT_CONTAINER)
            emit(OPC::POP)
            emit_nil
        end

        private def compile_enum_definition(node : AST::EnumDefinition)
            name_idx = name_index(node.name)
            value_method = node.value_name || node.value_type ? (node.value_name || "value") : "value"
            value_method_idx = const_index(value_method)
            emit(OPC::MAKE_ENUM, name_idx, value_method_idx)
            if @container_depth > 0
                emit(OPC::DEFINE_CONST, name_idx)
            else
                emit(OPC::STORE, name_idx)
            end
            emit(OPC::LOAD, name_idx)
            emit(OPC::ENTER_CONTAINER)
            enter_container do
                node.members.each do |member|
                    if member.value
                        compile_expression(member.value.not_nil!)
                        emit(OPC::DEFINE_ENUM_MEMBER, name_index(member.name), 1)
                    else
                        emit(OPC::DEFINE_ENUM_MEMBER, name_index(member.name), 0)
                    end
                end
            end
            emit(OPC::EXIT_CONTAINER)
            emit(OPC::POP)
            emit_nil
        end

        private def compile_extend(node : AST::ExtendStatement)
            node.targets.each do |target|
                compile_expression(target)
                emit(OPC::EXTEND_CONTAINER)
            end
            emit_nil
        end

        private def compile_accessor_macro(node : AST::AccessorMacro)
            node.entries.each do |entry|
                case node.kind
                when :getter
                    emit_accessor_getter(entry, node.visibility)
                when :setter
                    emit_accessor_setter(entry, node.visibility)
                when :property
                    emit_accessor_getter(entry, node.visibility)
                    emit_accessor_setter(entry, node.visibility)
                else
                    raise ArgumentError.new("Unknown accessor macro kind #{node.kind}")
                end
            end
        end

        private def emit_accessor_getter(entry : AST::AccessorEntry, visibility : Symbol)
            body = [] of AST::Node
            body << AST::InstanceVariable.new(entry.name)
            fn = AST::FunctionDef.new(entry.name, [] of AST::TypedParameter, body, [] of AST::RescueClause, entry.type_annotation, visibility: visibility)
            compile_function_def(fn)
        end

        private def emit_accessor_setter(entry : AST::AccessorEntry, visibility : Symbol)
            param = AST::TypedParameter.new("value", entry.type_annotation)
            assignment = AST::InstanceVariableAssignment.new(entry.name, AST::Variable.new("value"))
            body = [] of AST::Node
            body << assignment
            fn = AST::FunctionDef.new("#{entry.name}=", [param], body, [] of AST::RescueClause, entry.type_annotation, visibility: visibility)
            compile_function_def(fn)
        end

        private def compile_alias_definition(node : AST::AliasDefinition)
            type_idx = const_index(node.type_expression)
            emit(OPC::DEFINE_TYPE_ALIAS, name_index(node.name), type_idx)
        end

        private def compile_yield(node : AST::YieldExpression)
            node.arguments.each { |arg| compile_expression(arg) }
            emit(OPC::YIELD, node.arguments.size)
        end

        private def compile_constant_path(node : AST::ConstantPath)
            raw_segments = [node.head] + node.tail
            segments = [] of Bytecode::Value
            raw_segments.each { |seg| segments << seg }
            const_idx = const_index(segments)
            emit(OPC::LOAD_CONST_PATH, const_idx)
        end

        private def compile_case_statement(node : AST::CaseStatement)
            has_expression = !!node.expression
            if has_expression
                compile_expression(node.expression.not_nil!)
            end

            end_jumps = [] of Int32

            node.when_clauses.each do |clause|
                body_entry_jumps = [] of Int32

                clause.conditions.each do |condition|
                    if has_expression
                        emit(OPC::DUP)
                        compile_expression(condition)
                        emit(OPC::EQ)
                    else
                        compile_expression(condition)
                    end
                    
                    skip_jump = emit(OPC::JMPF, 0)
                    body_entry_jumps << emit(OPC::JMP, 0)
                    patch_jump(skip_jump, current_ip)
                end

                next_clause_jump = emit(OPC::JMP, 0)

                body_start = current_ip
                body_entry_jumps.each { |pos| patch_jump(pos, body_start) }

                emit(OPC::POP) if has_expression
                compile_block(clause.block)
                emit_nil
                end_jumps << emit(OPC::JMP, 0)

                patch_jump(next_clause_jump, current_ip)
            end

            emit(OPC::POP) if has_expression
            if node.else_block
                compile_block(node.else_block.not_nil!)
            end

            emit_nil
            end_jumps.each { |pos| patch_jump(pos, current_ip) }
        end

        private def build_signature(parameters : Array(AST::TypedParameter), return_type : AST::TypeExpression?, is_abstract : Bool = false, gc_flags : ::Dragonstone::Runtime::GC::Flags = ::Dragonstone::Runtime::GC::Flags.new) : Bytecode::FunctionSignature
            specs = parameters.map do |param|
                Bytecode::ParameterSpec.new(name_index(param.name), param.type, param.instance_var_name)
            end
            Bytecode::FunctionSignature.new(specs, return_type, is_abstract, gc_flags)
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

        private def emit_type_check(type_expr : AST::TypeExpression?)
            return unless type_expr
            type_idx = const_index(type_expr)
            emit(OPC::CHECK_TYPE, type_idx)
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

            when OPC::CONST, OPC::LOAD, OPC::LOAD_ARGV
                stack_push

            when OPC::STORE
                stack_pop
                stack_push

            when OPC::POP
                stack_pop
            when OPC::DUP
                stack_push
                
            when OPC::ADD, OPC::SUB, OPC::MUL, OPC::DIV, OPC::EQ, OPC::NE, OPC::LT, OPC::LE, OPC::GT, OPC::GE, OPC::CONCAT, OPC::CMP
                stack_pop(2)
                stack_push
            when OPC::FLOOR_DIV, OPC::MOD, OPC::BIT_AND, OPC::BIT_OR, OPC::BIT_XOR, OPC::SHL, OPC::SHR
                stack_pop(2)
                stack_push

            when OPC::ECHO
                argc = operands[0]? || 0
                stack_pop(argc)
                stack_push

            when OPC::TYPEOF
                stack_pop
                stack_push

            when OPC::DEBUG_ECHO
                stack_pop
                stack_push

            when OPC::MAKE_ARRAY
                count = operands[0]? || 0
                stack_pop(count)
                stack_push

            when OPC::MAKE_TUPLE
                count = operands[0]? || 0
                stack_pop(count)
                stack_push

            when OPC::MAKE_NAMED_TUPLE
                count = operands[0]? || 0
                stack_pop(count * 2)
                stack_push

            when OPC::MAKE_MAP
                count = operands[0]? || 0
                stack_pop(count * 2)
                stack_push

            when OPC::MAKE_RANGE
                stack_pop(2)
                stack_push

            when OPC::MAKE_MODULE, OPC::MAKE_CLASS, OPC::MAKE_STRUCT, OPC::MAKE_ENUM
                stack_push

            when OPC::ENTER_CONTAINER
                stack_pop

            when OPC::EXIT_CONTAINER
                # no stack change

            when OPC::DEFINE_CONST
                stack_pop
                stack_push

            when OPC::DEFINE_METHOD
                stack_pop

            when OPC::DEFINE_ENUM_MEMBER
                has_value = operands[1]? || 0
                stack_pop(has_value)

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

            when OPC::CALL_BLOCK
                argc = operands[0]? || 0
                stack_pop(argc + 1)
                stack_push

            when OPC::INVOKE
                argc = operands[1]? || 0
                stack_pop(argc + 1)
                stack_push

            when OPC::INVOKE_BLOCK
                argc = operands[1]? || 0
                stack_pop(argc + 2) # receiver + args + block
                stack_push

            when OPC::TO_S
                stack_pop
                stack_push

            when OPC::MAKE_FUNCTION
                stack_push

            when OPC::MAKE_BLOCK
                stack_push

            when OPC::STORE_INDEX
                stack_pop(3)
                stack_push

            when OPC::LOAD_CONST_PATH
                stack_push

            when OPC::LOAD_IVAR
                stack_push

            when OPC::STORE_IVAR
                stack_pop
                stack_push

            when OPC::PUSH_HANDLER
                # handler stack only
            when OPC::POP_HANDLER
                # handler stack only
            when OPC::LOAD_EXCEPTION
                stack_push
            when OPC::RAISE
                stack_pop
            when OPC::CHECK_RETHROW
                # no stack change

            when OPC::YIELD
                argc = operands[0]? || 0
                stack_pop(argc)
                stack_push

            when OPC::JMPF
                stack_pop

            when OPC::RET
                @stack_depth = 0

            when OPC::CHECK_TYPE
                stack_pop
                stack_push

            when OPC::HALT
                @stack_depth = 0

            when OPC::JMP, OPC::NOP, OPC::BREAK_SIGNAL, OPC::NEXT_SIGNAL, OPC::REDO_SIGNAL, OPC::DEFINE_TYPE_ALIAS, OPC::RETRY
                # No interop yet.
            when OPC::ENTER_LOOP, OPC::EXIT_LOOP
                # metadata only
            when OPC::EXTEND_CONTAINER
                stack_pop
            when OPC::DEFINE_SINGLETON_METHOD
                stack_pop(2)
                stack_push
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
