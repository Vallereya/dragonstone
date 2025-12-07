# ---------------------------------
# -------- LLVM Backend -----------
# ---------------------------------
require "set"
require "../../build_options"
require "../shared/helpers"
require "../shared/program_serializer"
require "../../../../shared/language/lexer/lexer"
require "../../../../shared/language/parser/parser"

module Dragonstone
    module Core
        module Compiler
            module Targets
                module LLVM
                    class Backend
                        EXTENSION = "ll"
                        
                        def build(program : ::Dragonstone::IR::Program, options : BuildOptions) : BuildArtifact
                            serializer = Shared::ProgramSerializer.new(program)
                            source_dump = serializer.source
                            summary_lines = serializer.summary_lines
                            artifact_path = Shared.artifact_path(options, EXTENSION)
                            File.write(artifact_path, build_content(program, source_dump, summary_lines))
                            BuildArtifact.new(target: Target::LLVM, object_path: artifact_path)
                        end
                        
                        
                        private def build_content(program : ::Dragonstone::IR::Program, source : String, summary_lines : Array(String)) : String
                            generator = IRGenerator.new(program)
                            
                            String.build do |io|
                                io << "; ---------------------------------\n"
                                io << "; Dragonstone LLVM Target Artifact \n"
                                io << "; ---------------------------------\n"
                                unless source.empty?
                                    io << "; Source snapshot\n"
                                    source.each_line do |line|
                                        io << ";   " << line.rstrip << "\n"
                                    end
                                    io << ";\n"
                                end
                                unless summary_lines.empty?
                                    io << "; Summary\n"
                                    summary_lines.each do |line|
                                        io << ";  - " << line << "\n"
                                    end
                                    io << ";\n"
                                end
                                
                                # Generate actual LLVM IR
                                generator.generate(io)
                            end
                        end
                    end
                    
                    class IRGenerator
                        alias ValueRef = NamedTuple(type: String, ref: String, constant: Bool, kind: Symbol?)
                        alias FunctionSignature = NamedTuple(return_type: String, param_types: Array(String))
                        alias CallArg = NamedTuple(type: String, ref: String)
                        alias BlockCaptureInfo = NamedTuple(name: String, value_type: String, slot_ptr: String)
                        alias RuntimeContext = NamedTuple(
                            box_i32: String,
                            box_i64: String,
                            box_bool: String,
                            box_string: String,
                            box_float: String,
                            unbox_i32: String,
                            unbox_i64: String,
                            unbox_bool: String,
                            unbox_float: String,
                            array_literal: String,
                            map_literal: String,
                            block_literal: String,
                            block_invoke: String,
                            method_invoke: String,
                            block_env_alloc: String,
                            tuple_literal: String,
                            named_tuple_literal: String,
                            constant_lookup: String,
                            rescue_placeholder: String,
                            constant_define: String,
                            index_get: String,
                            index_set: String,
                            case_compare: String,
                            yield_missing_block: String,
                            display_value: String,
                            interpolated_string: String
                        )
                        
                        @string_counter = 0
                        
                        def initialize(@program : ::Dragonstone::IR::Program)
                            @analysis = @program.analysis
                            @string_literals = {} of String => NamedTuple(name: String, escaped: String, length: Int32)
                            @string_order = [] of String
                            @functions = [] of AST::FunctionDef
                            @function_names = {} of AST::FunctionDef => String
                            @function_receivers = {} of AST::FunctionDef => String
                            @function_signatures = {} of String => FunctionSignature
                            @function_requires_block = {} of String => Bool
                            @runtime_literals_preregistered = false
                            @runtime_types_emitted = false
                            @struct_layouts = {} of String => Array(AST::TypeExpression?)
                            @struct_field_indices = {} of String => Hash(String, Int32)
                            @struct_alias_map = {} of String => String
                            @struct_stack = [] of String
                            @emitted_struct_types = Set(String).new
                            @struct_llvm_lookup = {} of String => String
                            @namespace_stack = [] of String
                            index_struct_types
                            @runtime = RuntimeContext.new(
                                box_i32: "dragonstone_runtime_box_i32",
                                box_i64: "dragonstone_runtime_box_i64",
                                box_bool: "dragonstone_runtime_box_bool",
                                box_string: "dragonstone_runtime_box_string",
                                box_float: "dragonstone_runtime_box_float",
                                unbox_i32: "dragonstone_runtime_unbox_i32",
                                unbox_i64: "dragonstone_runtime_unbox_i64",
                                unbox_bool: "dragonstone_runtime_unbox_bool",
                                unbox_float: "dragonstone_runtime_unbox_float",
                                array_literal: "dragonstone_runtime_array_literal",
                                map_literal: "dragonstone_runtime_map_literal",
                                block_literal: "dragonstone_runtime_block_literal",
                                block_invoke: "dragonstone_runtime_block_invoke",
                                method_invoke: "dragonstone_runtime_method_invoke",
                                block_env_alloc: "dragonstone_runtime_block_env_allocate",
                                tuple_literal: "dragonstone_runtime_tuple_literal",
                                named_tuple_literal: "dragonstone_runtime_named_tuple_literal",
                                constant_lookup: "dragonstone_runtime_constant_lookup",
                                rescue_placeholder: "dragonstone_runtime_rescue_placeholder",
                                constant_define: "dragonstone_runtime_define_constant",
                                index_get: "dragonstone_runtime_index_get",
                                index_set: "dragonstone_runtime_index_set",
                                case_compare: "dragonstone_runtime_case_compare",
                                yield_missing_block: "dragonstone_runtime_yield_missing_block",
                                display_value: "dragonstone_runtime_value_display",
                                interpolated_string: "dragonstone_runtime_interpolated_string"
                            )
                        end
                        
                        def generate(io : IO)
                            collect_strings
                            collect_functions
                            prepare_runtime_literals
                            emit_string_constants(io)
                            emit_runtime_types(io)
                            declare_runtime(io)
                            emit_functions(io)
                            emit_entrypoint(io)
                        end
                        
                        private class FunctionContext
                            getter io : IO
                            getter return_type : String
                            getter locals : Hash(String, NamedTuple(ptr: String, type: String, heap: Bool))
                            getter ensure_stack : Array(Array(AST::Node))
                            getter postamble : String::Builder
                            property block_slot : NamedTuple(ptr: String, type: String)?
                            
                            def initialize(@io : IO, @return_type : String)
                                @next_reg = 0
                                @next_label = 0
                                @locals = {} of String => NamedTuple(ptr: String, type: String, heap: Bool)
                                @ensure_stack = [] of Array(AST::Node)
                                @postamble = String::Builder.new
                                @block_slot = nil
                            end
                            
                            def fresh(prefix = "t") : String
                                name = "#{prefix}#{@next_reg}"
                                @next_reg += 1
                                name
                            end
                            
                            def fresh_label(prefix = "block") : String
                                name = "#{prefix}#{@next_label}"
                                @next_label += 1
                                name
                            end
                            
                            def append_postamble(fragment : String)
                                @postamble << fragment
                            end
                        end
                        
                        private def collect_strings
                            @namespace_stack.clear
                            @program.ast.statements.each do |stmt|
                                collect_strings_from_node(stmt)
                            end
                            @namespace_stack.clear
                        end

                        private def index_struct_types
                            @namespace_stack.clear
                            @program.ast.statements.each do |stmt|
                                register_struct_types(stmt)
                            end
                            @namespace_stack.clear
                        end

                        private def struct_fields_for(name : String) : Array(AST::TypeExpression?)
                            @struct_layouts[name]? || begin
                                fields = [] of AST::TypeExpression?
                                @struct_layouts[name] = fields
                                fields
                            end
                        end

                        private def struct_field_map_for(name : String) : Hash(String, Int32)
                            @struct_field_indices[name]? || begin
                                map = {} of String => Int32
                                @struct_field_indices[name] = map
                                map
                            end
                        end

                        private def register_struct_types(node : AST::Node)
                            case node
                            when AST::StructDefinition
                                full_name = qualify_name(node.name)
                                struct_fields_for(full_name)
                                struct_field_map_for(full_name)
                                @struct_alias_map[node.name] = full_name unless @struct_alias_map.has_key?(node.name)
                                @struct_stack << full_name
                                with_namespace(node.name) do
                                    node.body.each { |stmt| register_struct_types(stmt) }
                                end
                                @struct_stack.pop
                            when AST::ModuleDefinition, AST::ClassDefinition
                                with_namespace(node.name) do
                                    node.body.each { |stmt| register_struct_types(stmt) }
                                end
                            when AST::AccessorMacro
                                if current = @struct_stack.last?
                                    if node.kind == :property
                                        fields = struct_fields_for(current)
                                        indices = struct_field_map_for(current)
                                        node.entries.each do |entry|
                                            indices[entry.name] = fields.size
                                            fields << entry.type_annotation
                                        end
                                    end
                                end
                            else
                                # no-op
                            end
                        end
                        
                        private def collect_strings_from_node(node : AST::Node)
                            case node
                            when AST::Literal
                                if value = node.value
                                    intern_string(value) if value.is_a?(String)
                                end
                            when AST::Variable
                                intern_string(node.name) if constant_symbol?(node.name)
                            when AST::MethodCall
                                intern_string(node.name)
                                node.receiver.try { |recv| collect_strings_from_node(recv) }
                                node.arguments.each { |arg| collect_strings_from_node(arg) }
                            when AST::Assignment
                                collect_strings_from_node(node.value)
                            when AST::BinaryOp
                                collect_strings_from_node(node.left)
                                collect_strings_from_node(node.right)
                            when AST::ReturnStatement
                                node.value.try { |value| collect_strings_from_node(value) }
                            when AST::FunctionDef
                                node.body.each { |stmt| collect_strings_from_node(stmt) }
                            when AST::IfStatement
                                collect_strings_from_node(node.condition)
                                node.then_block.each { |stmt| collect_strings_from_node(stmt) }
                                node.elsif_blocks.each { |clause| collect_strings_from_node(clause) }
                                if block = node.else_block
                                    block.each { |stmt| collect_strings_from_node(stmt) }
                                end
                            when AST::ElsifClause
                                collect_strings_from_node(node.condition)
                                node.block.each { |stmt| collect_strings_from_node(stmt) }
                            when AST::UnlessStatement
                                collect_strings_from_node(node.condition)
                                node.body.each { |stmt| collect_strings_from_node(stmt) }
                                if block = node.else_block
                                    block.each { |stmt| collect_strings_from_node(stmt) }
                                end
                            when AST::WhileStatement
                                collect_strings_from_node(node.condition)
                                node.block.each { |stmt| collect_strings_from_node(stmt) }
                            when AST::UnaryOp
                                collect_strings_from_node(node.operand)
                            when AST::ArrayLiteral
                                node.elements.each { |elem| collect_strings_from_node(elem) }
                            when AST::MapLiteral
                                node.entries.each do |(key, value)|
                                    collect_strings_from_node(key)
                                    collect_strings_from_node(value)
                                end
                            when AST::BlockLiteral
                                node.body.each { |stmt| collect_strings_from_node(stmt) }
                            when AST::BeginExpression
                                node.body.each { |stmt| collect_strings_from_node(stmt) }
                                if block = node.else_block
                                    block.each { |stmt| collect_strings_from_node(stmt) }
                                end
                                if block = node.ensure_block
                                    block.each { |stmt| collect_strings_from_node(stmt) }
                                end
                            when AST::ConstantPath
                                node.names.each { |segment| intern_string(segment) }
                            when AST::ConstantDeclaration
                                intern_string(qualify_name(node.name))
                                collect_strings_from_node(node.value)
                            when AST::ClassDefinition
                                intern_string(qualify_name(node.name))
                                with_namespace(node.name) do
                                    node.body.each { |stmt| collect_strings_from_node(stmt) }
                                end
                            when AST::ModuleDefinition
                                intern_string(qualify_name(node.name))
                                with_namespace(node.name) do
                                    node.body.each { |stmt| collect_strings_from_node(stmt) }
                                end
                            when AST::StructDefinition
                                intern_string(qualify_name(node.name))
                                with_namespace(node.name) do
                                    node.body.each { |stmt| collect_strings_from_node(stmt) }
                                end
                            when AST::EnumDefinition
                                intern_string(qualify_name(node.name))
                                with_namespace(node.name) do
                                    node.members.each do |member|
                                        intern_string(qualify_name(member.name))
                                        if value = member.value
                                            collect_strings_from_node(value)
                                        end
                                    end
                                end
                            when AST::IndexAccess
                                collect_strings_from_node(node.object)
                                collect_strings_from_node(node.index)
                            when AST::IndexAssignment
                                collect_strings_from_node(node.object)
                                collect_strings_from_node(node.index)
                                collect_strings_from_node(node.value)
                            when AST::CaseStatement
                                node.expression.try { |expr| collect_strings_from_node(expr) }
                                node.when_clauses.each do |clause|
                                    clause.conditions.each { |cond| collect_strings_from_node(cond) }
                                    clause.block.each { |stmt| collect_strings_from_node(stmt) }
                                end
                                if else_block = node.else_block
                                    else_block.each { |stmt| collect_strings_from_node(stmt) }
                                end
                            when AST::YieldExpression
                                node.arguments.each { |arg| collect_strings_from_node(arg) }
                            when AST::InterpolatedString
                                node.parts.each do |part|
                                    type, content = part
                                    intern_string(content) if type == :string
                                end
                            end
                        end
                        
                        private def function_body_contains_yield?(statements : Array(AST::Node)) : Bool
                            nodes_contain_yield?(statements)
                        end
                        
                        private def nodes_contain_yield?(statements : Array(AST::Node)) : Bool
                            statements.any? { |stmt| node_contains_yield?(stmt) }
                        end
                        
                        private def node_contains_yield?(node : AST::Node) : Bool
                            case node
                            when AST::YieldExpression
                                true
                            when AST::FunctionDef, AST::FunctionLiteral, AST::BlockLiteral
                                false
                            when AST::MethodCall
                                if receiver = node.receiver
                                    return true if node_contains_yield?(receiver)
                                end
                                nodes_contain_yield?(node.arguments)
                            when AST::Assignment
                                node_contains_yield?(node.value)
                            when AST::BinaryOp
                                node_contains_yield?(node.left) || node_contains_yield?(node.right)
                            when AST::ReturnStatement
                                if value = node.value
                                    node_contains_yield?(value)
                                else
                                    false
                                end
                            when AST::IfStatement
                                node_contains_yield?(node.condition) ||
                                    nodes_contain_yield?(node.then_block) ||
                                    node.elsif_blocks.any? { |clause| node_contains_yield?(clause) } ||
                                    (node.else_block ? nodes_contain_yield?(node.else_block.not_nil!) : false)
                            when AST::ElsifClause
                                node_contains_yield?(node.condition) || nodes_contain_yield?(node.block)
                            when AST::UnlessStatement
                                node_contains_yield?(node.condition) ||
                                    nodes_contain_yield?(node.body) ||
                                    (node.else_block ? nodes_contain_yield?(node.else_block.not_nil!) : false)
                            when AST::WhileStatement
                                node_contains_yield?(node.condition) || nodes_contain_yield?(node.block)
                            when AST::ArrayLiteral
                                nodes_contain_yield?(node.elements)
                            when AST::MapLiteral
                                node.entries.any? { |(key, value)| node_contains_yield?(key) || node_contains_yield?(value) }
                            when AST::BeginExpression
                                nodes_contain_yield?(node.body) ||
                                    (node.else_block ? nodes_contain_yield?(node.else_block.not_nil!) : false) ||
                                    (node.ensure_block ? nodes_contain_yield?(node.ensure_block.not_nil!) : false) ||
                                    node.rescue_clauses.any? { |clause| nodes_contain_yield?(clause.body) }
                            when AST::ConstantDeclaration
                                node_contains_yield?(node.value)
                            when AST::IndexAccess
                                node_contains_yield?(node.object) || node_contains_yield?(node.index)
                            when AST::IndexAssignment
                                node_contains_yield?(node.object) || node_contains_yield?(node.index) || node_contains_yield?(node.value)
                            when AST::CaseStatement
                                (node.expression ? node_contains_yield?(node.expression.not_nil!) : false) ||
                                    node.when_clauses.any? { |clause| node_contains_yield?(clause) } ||
                                    (node.else_block ? nodes_contain_yield?(node.else_block.not_nil!) : false)
                            when AST::WhenClause
                                nodes_contain_yield?(node.conditions) || nodes_contain_yield?(node.block)
                            else
                                false
                            end
                        end

                        private def collect_functions
                            @namespace_stack.clear
                            @program.ast.statements.each do |stmt|
                                collect_functions_from(stmt)
                            end
                            @namespace_stack.clear
                        end

                        private def collect_functions_from(node : AST::Node)
                            case node
                            when AST::StructDefinition
                                with_namespace(node.name) do
                                    node.body.each { |stmt| collect_functions_from(stmt) }
                                end
                            when AST::ClassDefinition, AST::ModuleDefinition
                                with_namespace(node.name) do
                                    node.body.each { |stmt| collect_functions_from(stmt) }
                                end
                            when AST::FunctionDef
                                register_function(node)
                            end
                        end

                        private def register_function(func : AST::FunctionDef)
                            mangled_name = if @namespace_stack.empty?
                                func.name == "main" ? "__dragonstone_user_main" : func.name
                            else
                                type_name = @namespace_stack.join("::")
                                struct_method_symbol(type_name, func.name)
                            end

                            @function_names[func] = mangled_name
                            @functions << func

                            receiver_type = nil
                            if !@namespace_stack.empty?
                                current_scope = @namespace_stack.join("::")
                                if canonical_struct_name(current_scope)
                                    receiver_type = llvm_struct_name(current_scope)
                                    @function_receivers[func] = receiver_type
                                end
                            end

                            requires_block = function_body_contains_yield?(func.body)
                            @function_requires_block[mangled_name] = requires_block

                            param_types = func.typed_parameters.map { |param| llvm_param_type(param.type) }

                            if receiver_type
                                param_types.unshift(receiver_type)
                            end

                            param_types << "i8*" if requires_block
                            
                            signature = FunctionSignature.new(
                                return_type: llvm_type_of(func.return_type),
                                param_types: param_types
                            )
                            
                            @function_signatures[mangled_name] = signature
                        end
                        
                        private def prepare_runtime_literals
                            return if @runtime_literals_preregistered
                            intern_string("%lld\n")
                            intern_string("%g\n")
                            intern_string("true")
                            intern_string("false")
                            intern_string("nil")
                            @runtime_literals_preregistered = true
                        end
                        
                        private def emit_string_constants(io : IO)
                            @string_order.each do |literal|
                                entry = @string_literals[literal]
                                size = entry[:length] + 1
                                io << "@#{entry[:name]} = private unnamed_addr constant [#{size} x i8] c\"#{entry[:escaped]}\\00\"\n"
                            end
                            io << "\n" unless @string_order.empty?
                        end
                        
                        private def emit_runtime_types(io : IO)
                            return if @runtime_types_emitted
                            io << "%DSObject = type { i8* }\n"
                            io << "%DSValue = type { i8, i64 }\n"
                            @struct_layouts.each do |full_name, fields|
                                next if @emitted_struct_types.includes?(full_name)
                                symbol = llvm_struct_symbol(full_name)
                                @struct_llvm_lookup[symbol] = full_name
                                type_name = "%#{symbol}"
                                field_types = fields.map { |field| struct_field_type(field) }
                                if field_types.empty?
                                    io << "#{type_name} = type { }\n"
                                else
                                    io << "#{type_name} = type { #{field_types.join(", ")} }\n"
                                end
                                @emitted_struct_types << full_name
                            end
                            io << "\n"
                            @runtime_types_emitted = true
                        end

                        private def declare_runtime(io : IO)
                            io << "declare i32 @puts(i8*)\n"
                            io << "declare i32 @printf(i8*, ...)\n"
                            io << "declare i8* @#{@runtime[:box_i32]}(i32)\n"
                            io << "declare i8* @#{@runtime[:box_i64]}(i64)\n"
                            io << "declare i8* @#{@runtime[:box_bool]}(i1)\n"
                            io << "declare i8* @#{@runtime[:box_string]}(i8*)\n"
                            io << "declare i8* @#{@runtime[:box_float]}(double)\n"
                            io << "declare i32 @#{@runtime[:unbox_i32]}(i8*)\n"
                            io << "declare i64 @#{@runtime[:unbox_i64]}(i8*)\n"
                            io << "declare i1 @#{@runtime[:unbox_bool]}(i8*)\n"
                            io << "declare double @#{@runtime[:unbox_float]}(i8*)\n"
                            io << "declare i8* @#{@runtime[:array_literal]}(i64, i8**)\n"
                            io << "declare i8* @#{@runtime[:map_literal]}(i64, i8**, i8**)\n"
                            io << "declare i8* @#{@runtime[:tuple_literal]}(i64, i8**)\n"
                            io << "declare i8* @#{@runtime[:named_tuple_literal]}(i64, i8**, i8**)\n"
                            io << "declare i8* @#{@runtime[:block_literal]}(i8*, i8*)\n"
                            io << "declare i8* @#{@runtime[:block_invoke]}(i8*, i64, i8**)\n"
                            io << "declare i8* @#{@runtime[:method_invoke]}(i8*, i8*, i64, i8**)\n"
                            io << "declare i8** @#{@runtime[:block_env_alloc]}(i64)\n"
                            io << "declare i8* @#{@runtime[:constant_lookup]}(i64, i8**)\n"
                            io << "declare void @#{@runtime[:rescue_placeholder]}()\n\n"
                            io << "declare i8* @#{@runtime[:constant_define]}(i8*, i8*)\n"
                            io << "declare i8* @#{@runtime[:index_get]}(i8*, i8*)\n"
                            io << "declare i8* @#{@runtime[:index_set]}(i8*, i8*, i8*)\n"
                            io << "declare i1 @#{@runtime[:case_compare]}(i8*, i8*)\n"
                            io << "declare void @#{@runtime[:yield_missing_block]}()\n"
                            io << "declare i8* @#{@runtime[:display_value]}(i8*)\n"
                            io << "declare i8* @#{@runtime[:interpolated_string]}(i64, i8**)\n"
                            io << "declare i8* @malloc(i64)\n\n"
                        end
                        
                        private def emit_functions(io : IO)
                            @functions.each do |func|
                                emit_function(io, func)
                                io << "\n"
                            end
                        end
                        
                        private def emit_function(io : IO, func : AST::FunctionDef)
                            return_type = llvm_type_of(func.return_type)

                            ctx = FunctionContext.new(io, return_type)
                            @namespace_stack.clear

                            llvm_name = @function_names[func]

                            param_specs = [] of NamedTuple(type: String, source: String, name: String)
                            params = [] of String
                            requires_block = @function_requires_block[llvm_name]? || false

                            if receiver_type = @function_receivers[func]?
                                arg_name = "%self"
                                params << "#{receiver_type} #{arg_name}"
                                param_specs << {type: receiver_type, source: arg_name, name: "self"}
                            end

                            func.typed_parameters.each_with_index do |param, index|
                                type = llvm_param_type(param.type)
                                arg_name = "%arg#{index}"
                                param_specs << {type: type, source: arg_name, name: param.name}
                                params << "#{type} #{arg_name}"
                            end

                            if requires_block
                                block_arg = "%block_arg"
                                param_specs << {type: "i8*", source: block_arg, name: "__block"}
                                params << "i8* #{block_arg}"
                            end
                            
                            io << "define #{return_type} @\"#{llvm_name}\"(#{params.join(", ")}) {\n"
                            io << "entry:\n"
                            
                            param_specs.each do |spec|
                                slot = "%#{ctx.fresh("param")}"
                                io << "  #{slot} = alloca #{spec[:type]}\n"
                                io << "  store #{spec[:type]} #{spec[:source]}, #{spec[:type]}* #{slot}\n"
                                ctx.locals[spec[:name]] = {ptr: slot, type: spec[:type], heap: false}
                                if spec[:name] == "__block"
                                    ctx.block_slot = {ptr: slot, type: spec[:type]}
                                end
                            end
                            
                            terminated = generate_block(ctx, func.body)
                            emit_default_return(ctx) unless terminated
                            emit_postamble(ctx)
                            io << "}\n"
                        end
                        
                        private def emit_entrypoint(io : IO)
                            ctx = FunctionContext.new(io, "i32")
                            @namespace_stack.clear
                            
                            io << "define i32 @main() {\n"
                            io << "entry:\n"
                            
                            top_level = @program.ast.statements.reject { |stmt| stmt.is_a?(AST::FunctionDef) }
                            terminated = generate_block(ctx, top_level)
                            
                            io << "  ret i32 0\n" unless terminated
                            emit_postamble(ctx)
                            io << "}\n"
                        end
                        
                        private def generate_block(ctx : FunctionContext, statements : Array(AST::Node)) : Bool
                            terminated = false
                            statements.each do |stmt|
                                terminated = generate_statement(ctx, stmt)
                                break if terminated
                            end
                            terminated
                        end
                        
                        private def emit_default_return(ctx : FunctionContext)
                            if ctx.return_type == "void"
                                ctx.io << "  ret void\n"
                            else
                                ctx.io << "  ret #{ctx.return_type} #{zero_value(ctx.return_type)}\n"
                            end
                        end
                        
                        private def emit_postamble(ctx : FunctionContext)
                            fragment = ctx.postamble.to_s
                            return if fragment.empty?
                            ctx.io << fragment
                        end
                        
                        private def emit_ensure_chain(ctx : FunctionContext)
                            stack = ctx.ensure_stack
                            return if stack.empty?
                            pending = stack.dup
                            stack.clear
                            pending.reverse_each do |block|
                                generate_block(ctx, block)
                            end
                        end
                        
                        private def generate_statement(ctx : FunctionContext, stmt : AST::Node) : Bool
                            case stmt
                            when AST::MethodCall
                                generate_method_call(ctx, stmt)
                                false
                            when AST::Assignment
                                value = generate_expression(ctx, stmt.value.as(AST::Node))
                                if operator = stmt.operator
                                    current = load_local(ctx, stmt.name)
                                    value = emit_binary_op(ctx, operator, current, value)
                                end
                                store_local(ctx, stmt.name, value)
                                false
                            when AST::ReturnStatement
                                if value_node = stmt.value
                                    value = generate_expression(ctx, value_node)
                                    emit_ensure_chain(ctx)
                                    ctx.io << "  ret #{value[:type]} #{value[:ref]}\n"
                                else
                                    emit_ensure_chain(ctx)
                                    emit_default_return(ctx)
                                end
                                true
                            when AST::BinaryOp
                                generate_expression(ctx, stmt)
                                false
                            when AST::Literal
                                generate_expression(ctx, stmt)
                                false
                            when AST::Variable
                                load_local(ctx, stmt.name)
                                false
                            when AST::IfStatement
                                generate_if_statement(ctx, stmt)
                            when AST::UnlessStatement
                                generate_unless_statement(ctx, stmt)
                            when AST::WhileStatement
                                generate_while_statement(ctx, stmt)
                            when AST::FunctionDef
                                false
                            when AST::ArrayLiteral
                                generate_array_literal(ctx, stmt)
                                false
                            when AST::MapLiteral
                                generate_map_literal(ctx, stmt)
                                false
                            when AST::TupleLiteral
                                generate_tuple_literal(ctx, stmt)
                                false
                            when AST::NamedTupleLiteral
                                generate_named_tuple_literal(ctx, stmt)
                                false
                            when AST::IndexAssignment
                                generate_index_assignment(ctx, stmt)
                                false
                            when AST::BlockLiteral
                                generate_block_literal(ctx, stmt)
                                false
                            when AST::BeginExpression
                                generate_begin_expression(ctx, stmt)
                                false
                            when AST::ConstantPath
                                generate_constant_path(ctx, stmt)
                                false
                            when AST::ConstantDeclaration
                                generate_constant_declaration(ctx, stmt)
                                false
                            when AST::StructDefinition
                                generate_struct_definition(ctx, stmt)
                                false
                            when AST::ClassDefinition
                                generate_class_definition(ctx, stmt)
                                false
                            when AST::ModuleDefinition
                                generate_module_definition(ctx, stmt)
                                false
                            when AST::CaseStatement
                                generate_case_expression(ctx, stmt)
                                false
                            when AST::YieldExpression
                                generate_yield_expression(ctx, stmt)
                                false
                            else
                                false
                            end
                        end
                        
                        private def generate_expression(ctx : FunctionContext, node : AST::Node) : ValueRef
                            case node
                            when AST::Literal
                                generate_literal(ctx, node)
                            when AST::Variable
                                generate_variable_reference(ctx, node.name)
                            when AST::BinaryOp
                                case node.operator
                                when :"&&", :"and"
                                    emit_logical_and(ctx, node)
                                when :"||", :"or"
                                    emit_logical_or(ctx, node)
                                else
                                    lhs = generate_expression(ctx, node.left)
                                    rhs = generate_expression(ctx, node.right)
                                    emit_binary_op(ctx, node.operator, lhs, rhs)
                                end
                            when AST::MethodCall
                                generate_method_call(ctx, node) || raise "Method #{node.name} does not return a value"
                            when AST::UnaryOp
                                generate_unary_expression(ctx, node)
                            when AST::ArrayLiteral
                                generate_array_literal(ctx, node)
                            when AST::MapLiteral
                                generate_map_literal(ctx, node)
                            when AST::BlockLiteral
                                generate_block_literal(ctx, node)
                            when AST::BeginExpression
                                generate_begin_expression(ctx, node)
                            when AST::ConstantPath
                                generate_constant_path(ctx, node)
                            when AST::TupleLiteral
                                generate_tuple_literal(ctx, node)
                            when AST::NamedTupleLiteral
                                generate_named_tuple_literal(ctx, node)
                            when AST::InterpolatedString
                                generate_interpolated_string(ctx, node)
                            when AST::IndexAccess
                                generate_index_access(ctx, node)
                            when AST::IndexAssignment
                                generate_index_assignment(ctx, node)
                            when AST::CaseStatement
                                generate_case_expression(ctx, node)
                            when AST::YieldExpression
                                generate_yield_expression(ctx, node)
                            else
                                raise "Unsupported expression #{node.class}"
                            end
                        end

                        private def generate_unary_expression(ctx : FunctionContext, node : AST::UnaryOp) : ValueRef
                            operand = generate_expression(ctx, node.operand)

                            case node.operator
                            when :-
                                if operand[:type] == "double" || operand[:type] == "float"
                                    reg = ctx.fresh("fneg")
                                    ctx.io << "  %#{reg} = fneg double #{operand[:ref]}\n"
                                    return value_ref("double", "%#{reg}")
                                end

                                bits = bits_for_type(operand[:type])
                                raise "Cannot apply unary minus to boolean values" if bits == 1
                                bits = 64 if bits == 0
                                coerced = coerce_integer(ctx, operand, bits)
                                reg = ctx.fresh("neg")
                                type = "i#{bits}"
                                ctx.io << "  %#{reg} = sub #{type} 0, #{coerced[:ref]}\n"
                                value_ref(type, "%#{reg}")
                            when :!
                                bool_value = ensure_boolean(ctx, operand)
                                emit_boolean_not(ctx, bool_value)
                            else
                                raise "Unsupported unary operator #{node.operator}"
                            end
                        end
                        
                        private def emit_logical_and(ctx : FunctionContext, node : AST::BinaryOp) : ValueRef
                            lhs = ensure_boolean(ctx, generate_expression(ctx, node.left))
                            rhs_label = ctx.fresh_label("logic_rhs")
                            short_label = ctx.fresh_label("logic_short")
                            merge_label = ctx.fresh_label("logic_merge")
                            
                            ctx.io << "  br i1 #{lhs[:ref]}, label %#{rhs_label}, label %#{short_label}\n"
                            
                            ctx.io << "#{rhs_label}:\n"
                            rhs = ensure_boolean(ctx, generate_expression(ctx, node.right))
                            ctx.io << "  br label %#{merge_label}\n"
                            
                            ctx.io << "#{short_label}:\n"
                            ctx.io << "  br label %#{merge_label}\n"
                            
                            ctx.io << "#{merge_label}:\n"
                            result = ctx.fresh("logic")
                            ctx.io << "  %#{result} = phi i1 [ #{rhs[:ref]}, %#{rhs_label} ], [ 0, %#{short_label} ]\n"
                            value_ref("i1", "%#{result}")
                        end
                        
                        private def emit_logical_or(ctx : FunctionContext, node : AST::BinaryOp) : ValueRef
                            lhs = ensure_boolean(ctx, generate_expression(ctx, node.left))
                            rhs_label = ctx.fresh_label("logic_rhs")
                            short_label = ctx.fresh_label("logic_short")
                            merge_label = ctx.fresh_label("logic_merge")
                            
                            ctx.io << "  br i1 #{lhs[:ref]}, label %#{short_label}, label %#{rhs_label}\n"
                            
                            ctx.io << "#{rhs_label}:\n"
                            rhs = ensure_boolean(ctx, generate_expression(ctx, node.right))
                            ctx.io << "  br label %#{merge_label}\n"
                            
                            ctx.io << "#{short_label}:\n"
                            ctx.io << "  br label %#{merge_label}\n"
                            
                            ctx.io << "#{merge_label}:\n"
                            result = ctx.fresh("logic")
                            ctx.io << "  %#{result} = phi i1 [ 1, %#{short_label} ], [ #{rhs[:ref]}, %#{rhs_label} ]\n"
                            value_ref("i1", "%#{result}")
                        end
                        
                        private def generate_if_statement(ctx : FunctionContext, stmt : AST::IfStatement) : Bool
                            normalized = normalize_if_statement(stmt)
                            
                            cond_value = ensure_boolean(ctx, generate_expression(ctx, normalized.condition))
                            then_label = ctx.fresh_label("if_then")
                            else_label = ctx.fresh_label("if_else")
                            merge_label = ctx.fresh_label("if_merge")
                            
                            ctx.io << "  br i1 #{cond_value[:ref]}, label %#{then_label}, label %#{else_label}\n"
                            
                            ctx.io << "#{then_label}:\n"
                            then_returns = generate_block(ctx, normalized.then_block)
                            ctx.io << "  br label %#{merge_label}\n" unless then_returns
                            
                            ctx.io << "#{else_label}:\n"
                            else_returns = if block = normalized.else_block
                                generate_block(ctx, block)
                            else
                                false
                            end
                            ctx.io << "  br label %#{merge_label}\n" unless else_returns
                            
                            unless then_returns && else_returns
                                ctx.io << "#{merge_label}:\n"
                            end
                            
                            then_returns && else_returns
                        end
                        
                        private def normalize_if_statement(stmt : AST::IfStatement) : AST::IfStatement
                            return stmt if stmt.elsif_blocks.empty?
                            
                            else_block = stmt.else_block
                            stmt.elsif_blocks.reverse_each do |clause|
                                nested = AST::IfStatement.new(clause.condition, clause.block, [] of AST::ElsifClause, else_block)
                                else_block = [nested] of AST::Node
                            end
                            
                            AST::IfStatement.new(stmt.condition, stmt.then_block, [] of AST::ElsifClause, else_block)
                        end
                        
                        private def generate_unless_statement(ctx : FunctionContext, stmt : AST::UnlessStatement) : Bool
                            cond_value = ensure_boolean(ctx, generate_expression(ctx, stmt.condition))
                            then_label = ctx.fresh_label("unless_then")
                            else_label = ctx.fresh_label("unless_else")
                            merge_label = ctx.fresh_label("unless_merge")
                            
                            ctx.io << "  br i1 #{cond_value[:ref]}, label %#{else_label}, label %#{then_label}\n"
                            
                            ctx.io << "#{then_label}:\n"
                            then_returns = generate_block(ctx, stmt.body)
                            ctx.io << "  br label %#{merge_label}\n" unless then_returns
                            
                            ctx.io << "#{else_label}:\n"
                            else_returns = if block = stmt.else_block
                                generate_block(ctx, block)
                            else
                                false
                            end
                            ctx.io << "  br label %#{merge_label}\n" unless else_returns
                            
                            unless then_returns && else_returns
                                ctx.io << "#{merge_label}:\n"
                            end
                            
                            then_returns && else_returns
                        end
                        
                        private def generate_while_statement(ctx : FunctionContext, stmt : AST::WhileStatement) : Bool
                            cond_label = ctx.fresh_label("while_cond")
                            body_label = ctx.fresh_label("while_body")
                            exit_label = ctx.fresh_label("while_exit")
                            
                            ctx.io << "  br label %#{cond_label}\n"
                            
                            ctx.io << "#{cond_label}:\n"
                            cond_value = ensure_boolean(ctx, generate_expression(ctx, stmt.condition))
                            ctx.io << "  br i1 #{cond_value[:ref]}, label %#{body_label}, label %#{exit_label}\n"
                            
                            ctx.io << "#{body_label}:\n"
                            body_returns = generate_block(ctx, stmt.block)
                            ctx.io << "  br label %#{cond_label}\n" unless body_returns
                            
                            ctx.io << "#{exit_label}:\n"
                            
                            false
                        end
                        
                        private def generate_array_literal(ctx : FunctionContext, node : AST::ArrayLiteral) : ValueRef
                            boxed = node.elements.map { |elem| box_value(ctx, generate_expression(ctx, elem)) }
                            buffer = allocate_pointer_buffer(ctx, boxed) || "null"
                            len_literal = node.elements.size
                            reg = ctx.fresh("array")
                            ctx.io << "  %#{reg} = call i8* @#{@runtime[:array_literal]}(i64 #{len_literal}, i8** #{buffer})\n"
                            value_ref("i8*", "%#{reg}")
                        end
                        
                        private def generate_map_literal(ctx : FunctionContext, node : AST::MapLiteral) : ValueRef
                            keys = [] of ValueRef
                            values = [] of ValueRef
                            node.entries.each do |(key, value)|
                                keys << box_value(ctx, generate_expression(ctx, key))
                                values << box_value(ctx, generate_expression(ctx, value))
                            end
                            
                            len_literal = node.entries.size
                            keys_buffer = allocate_pointer_buffer(ctx, keys) || "null"
                            values_buffer = allocate_pointer_buffer(ctx, values) || "null"
                            
                            reg = ctx.fresh("map")
                            len_arg = len_literal
                            ctx.io << "  %#{reg} = call i8* @#{@runtime[:map_literal]}(i64 #{len_arg}, i8** #{keys_buffer}, i8** #{values_buffer})\n"
                            value_ref("i8*", "%#{reg}")
                        end
                        
                        private def generate_block_literal(ctx : FunctionContext, node : AST::BlockLiteral) : ValueRef
                            fn_name = unique_block_symbol
                            fn_type = "i8*"
                            captures = collect_block_captures(ctx, node)
                            env_pointer = captures.empty? ? value_ref("i8*", "null", constant: true) : build_block_environment(ctx, captures)
                            
                            param_specs = node.typed_parameters.map_with_index do |param, index|
                                local_type = llvm_param_type(param.type)
                                {type: local_type, name: param.name, index: index}
                            end
                            
                            block_io = String::Builder.new
                            block_io << "define #{fn_type} @#{fn_name}(i8* %closure, i64 %argc, i8** %argv) {\nentry:\n"
                            
                            block_ctx = FunctionContext.new(block_io, fn_type)
                            
                            param_specs.each do |spec|
                                arg_ptr = "%#{block_ctx.fresh("argptr")}"
                                block_io << "  #{arg_ptr} = getelementptr i8*, i8** %argv, i64 #{spec[:index]}\n"
                                loaded = "%#{block_ctx.fresh("argload")}"
                                block_io << "  #{loaded} = load i8*, i8** #{arg_ptr}\n"
                                value = convert_block_argument(block_ctx, value_ref("i8*", loaded), spec[:type])
                                slot = "%#{block_ctx.fresh("param")}"
                                block_io << "  #{slot} = alloca #{spec[:type]}\n"
                                block_io << "  store #{spec[:type]} #{value[:ref]}, #{spec[:type]}* #{slot}\n"
                                block_ctx.locals[spec[:name]] = {ptr: slot, type: spec[:type], heap: false}
                            end
                            
                            attach_block_captures(block_ctx, captures)
                            
                            terminated = generate_block(block_ctx, node.body)
                            block_io << "  ret i8* null\n" unless terminated
                            block_io << "}\n\n"
                            
                            ctx.io << block_io.to_s
                            
                            reg = ctx.fresh("block")
                            ctx.io << "  %#{reg} = call i8* @#{@runtime[:block_literal]}(i8* bitcast (#{fn_type} (i8*, i64, i8**)* @#{fn_name} to i8*), i8* #{env_pointer[:ref]})\n"
                            value_ref("i8*", "%#{reg}")
                        end
                        
                        private def attach_block_captures(ctx : FunctionContext, captures : Array(BlockCaptureInfo))
                            return if captures.empty?
                            
                            env_base = "%#{ctx.fresh("closureenv")}"
                            ctx.io << "  #{env_base} = bitcast i8* %closure to i8**\n"
                            
                            captures.each_with_index do |capture, index|
                                slot_ptr = "%#{ctx.fresh("capfield")}"
                                ctx.io << "  #{slot_ptr} = getelementptr i8*, i8** #{env_base}, i64 #{index}\n"
                                raw_ptr = "%#{ctx.fresh("capload")}"
                                ctx.io << "  #{raw_ptr} = load i8*, i8** #{slot_ptr}\n"
                                typed_ptr = "%#{ctx.fresh("captured")}"
                                pointer_type = pointer_type_for(capture[:value_type])
                                ctx.io << "  #{typed_ptr} = bitcast i8* #{raw_ptr} to #{pointer_type}\n"
                                ctx.locals[capture[:name]] = {ptr: typed_ptr, type: capture[:value_type], heap: true}
                            end
                        end
                        
                        private def build_block_environment(ctx : FunctionContext, captures : Array(BlockCaptureInfo)) : ValueRef
                            env = runtime_call(ctx, "i8**", @runtime[:block_env_alloc], [
                                {type: "i64", ref: captures.size.to_s}
                            ])
                            
                            captures.each_with_index do |capture, index|
                                pointer_type = pointer_type_for(capture[:value_type])
                                cast_reg = ctx.fresh("capstore")
                                ctx.io << "  %#{cast_reg} = bitcast #{pointer_type} #{capture[:slot_ptr]} to i8*\n"
                                slot_reg = ctx.fresh("envslot")
                                ctx.io << "  %#{slot_reg} = getelementptr i8*, i8** #{env[:ref]}, i64 #{index}\n"
                                ctx.io << "  store i8* %#{cast_reg}, i8** %#{slot_reg}\n"
                            end
                            
                            handle = ctx.fresh("envhandle")
                            ctx.io << "  %#{handle} = bitcast i8** #{env[:ref]} to i8*\n"
                            value_ref("i8*", "%#{handle}")
                        end

                        private def convert_block_argument(ctx : FunctionContext, value : ValueRef, target_type : String) : ValueRef
                            case target_type
                            when "i8*"
                                value
                            when "i32"
                                runtime_call(ctx, "i32", @runtime[:unbox_i32], [{type: "i8*", ref: value[:ref]}])
                            when "i64"
                                runtime_call(ctx, "i64", @runtime[:unbox_i64], [{type: "i8*", ref: value[:ref]}])
                            when "i1"
                                runtime_call(ctx, "i1", @runtime[:unbox_bool], [{type: "i8*", ref: value[:ref]}])
                            when "double"
                                runtime_call(ctx, "double", @runtime[:unbox_float], [{type: "i8*", ref: value[:ref]}])
                            else
                                value
                            end
                        end
                        
                        private def collect_block_captures(ctx : FunctionContext, block : AST::BlockLiteral) : Array(BlockCaptureInfo)
                            return [] of BlockCaptureInfo if ctx.locals.empty?
                            
                            locals = ctx.locals
                            local_bindings = Set(String).new
                            block.typed_parameters.each { |param| local_bindings << param.name }
                            ordered = [] of String
                            seen = Set(String).new
                            scan_capture_statements(block.body, locals, local_bindings, ordered, seen)
                            
                            ordered.each { |name| promote_local_to_heap(ctx, name) }
                            
                            ordered.compact_map do |name|
                                if slot = locals[name]?
                                    {name: name, value_type: slot[:type], slot_ptr: slot[:ptr]}
                                end
                            end
                        end
                        
                        private def promote_local_to_heap(ctx : FunctionContext, name : String)
                            slot = ctx.locals[name]?
                            return unless slot
                            return if slot[:heap]
                            
                            size = bytes_for_type(slot[:type])
                            raw = ctx.fresh("capalloc")
                            ctx.io << "  %#{raw} = call i8* @malloc(i64 #{size})\n"
                            cast = ctx.fresh("capptr")
                            ctx.io << "  %#{cast} = bitcast i8* %#{raw} to #{slot[:type]}*\n"
                            temp = ctx.fresh("capval")
                            ctx.io << "  %#{temp} = load #{slot[:type]}, #{slot[:type]}* #{slot[:ptr]}\n"
                            ctx.io << "  store #{slot[:type]} %#{temp}, #{slot[:type]}* %#{cast}\n"
                            ctx.locals[name] = {ptr: "%#{cast}", type: slot[:type], heap: true}
                        end
                        
                        private def bytes_for_type(type : String) : Int32
                            case type
                            when "i1"
                                1
                            when "i32"
                                4
                            when "i64"
                                8
                            when "i8*"
                                8
                            else
                                raise "Cannot determine size for #{type}"
                            end
                        end
                        
                        private def scan_capture_statements(statements : Array(AST::Node), available : Hash(String, NamedTuple(ptr: String, type: String, heap: Bool)), local_bindings : Set(String), ordered : Array(String), seen : Set(String))
                            statements.each do |stmt|
                                scan_capture_node(stmt, available, local_bindings, ordered, seen)
                            end
                        end
                        
                        private def scan_capture_node(node : AST::Node, available : Hash(String, NamedTuple(ptr: String, type: String, heap: Bool)), local_bindings : Set(String), ordered : Array(String), seen : Set(String))
                            case node
                            when AST::Literal, AST::ConstantPath
                                # no-op
                            when AST::Variable
                                record_capture(node.name, available, local_bindings, ordered, seen)
                            when AST::MethodCall
                                if receiver = node.receiver
                                    scan_capture_node(receiver, available, local_bindings, ordered, seen)
                                end
                                node.arguments.each { |arg| scan_capture_node(arg, available, local_bindings, ordered, seen) }
                            when AST::Assignment
                                scan_capture_node(node.value, available, local_bindings, ordered, seen)
                                if available.has_key?(node.name) && !local_bindings.includes?(node.name)
                                    record_capture(node.name, available, local_bindings, ordered, seen)
                                else
                                    local_bindings << node.name
                                end
                            when AST::ReturnStatement
                                node.value.try { |value| scan_capture_node(value, available, local_bindings, ordered, seen) }
                            when AST::BinaryOp
                                scan_capture_node(node.left, available, local_bindings, ordered, seen)
                                scan_capture_node(node.right, available, local_bindings, ordered, seen)
                            when AST::UnaryOp
                                scan_capture_node(node.operand, available, local_bindings, ordered, seen)
                            when AST::ArrayLiteral
                                node.elements.each { |elem| scan_capture_node(elem, available, local_bindings, ordered, seen) }
                            when AST::MapLiteral
                                node.entries.each do |key, value|
                                    scan_capture_node(key, available, local_bindings, ordered, seen)
                                    scan_capture_node(value, available, local_bindings, ordered, seen)
                                end
                            when AST::TupleLiteral
                                node.elements.each { |elem| scan_capture_node(elem, available, local_bindings, ordered, seen) }
                            when AST::NamedTupleLiteral
                                node.entries.each { |entry| scan_capture_node(entry.value, available, local_bindings, ordered, seen) }
                            when AST::IfStatement
                                scan_capture_node(node.condition, available, local_bindings, ordered, seen)
                                scan_capture_statements(node.then_block, available, local_bindings, ordered, seen)
                                node.elsif_blocks.each { |clause| scan_capture_node(clause, available, local_bindings, ordered, seen) }
                                if block = node.else_block
                                    scan_capture_statements(block, available, local_bindings, ordered, seen)
                                end
                            when AST::ElsifClause
                                scan_capture_node(node.condition, available, local_bindings, ordered, seen)
                                scan_capture_statements(node.block, available, local_bindings, ordered, seen)
                            when AST::UnlessStatement
                                scan_capture_node(node.condition, available, local_bindings, ordered, seen)
                                scan_capture_statements(node.body, available, local_bindings, ordered, seen)
                                if block = node.else_block
                                    scan_capture_statements(block, available, local_bindings, ordered, seen)
                                end
                            when AST::WhileStatement
                                scan_capture_node(node.condition, available, local_bindings, ordered, seen)
                                scan_capture_statements(node.block, available, local_bindings, ordered, seen)
                            when AST::BeginExpression
                                scan_capture_statements(node.body, available, local_bindings, ordered, seen)
                                node.rescue_clauses.each { |clause| scan_capture_node(clause, available, local_bindings, ordered, seen) }
                                if else_block = node.else_block
                                    scan_capture_statements(else_block, available, local_bindings, ordered, seen)
                                end
                                if ensure_block = node.ensure_block
                                    scan_capture_statements(ensure_block, available, local_bindings, ordered, seen)
                                end
                            when AST::RescueClause
                                scan_capture_statements(node.body, available, local_bindings, ordered, seen)
                            when AST::ConstantDeclaration
                                scan_capture_node(node.value, available, local_bindings, ordered, seen)
                            when AST::IndexAccess
                                scan_capture_node(node.object, available, local_bindings, ordered, seen)
                                scan_capture_node(node.index, available, local_bindings, ordered, seen)
                            when AST::IndexAssignment
                                scan_capture_node(node.object, available, local_bindings, ordered, seen)
                                scan_capture_node(node.index, available, local_bindings, ordered, seen)
                                scan_capture_node(node.value, available, local_bindings, ordered, seen)
                            when AST::CaseStatement
                                node.expression.try { |expr| scan_capture_node(expr, available, local_bindings, ordered, seen) }
                                node.when_clauses.each { |clause| scan_capture_node(clause, available, local_bindings, ordered, seen) }
                                if else_block = node.else_block
                                    scan_capture_statements(else_block, available, local_bindings, ordered, seen)
                                end
                            when AST::WhenClause
                                node.conditions.each { |cond| scan_capture_node(cond, available, local_bindings, ordered, seen) }
                                scan_capture_statements(node.block, available, local_bindings, ordered, seen)
                            when AST::YieldExpression
                                node.arguments.each { |arg| scan_capture_node(arg, available, local_bindings, ordered, seen) }
                            when AST::InterpolatedString
                                node.normalized_parts.each do |type, content|
                                    next unless type == :expression
                                    scan_capture_node(interpolation_expression(content), available, local_bindings, ordered, seen)
                                end
                            when AST::BlockLiteral, AST::FunctionDef, AST::FunctionLiteral,
                                 AST::ClassDefinition, AST::StructDefinition, AST::ModuleDefinition, AST::EnumDefinition
                                # nested scopes – skip
                            else
                                # nodes not explicitly handled either have no children or do not introduce captures
                            end
                        end
                        
                        private def record_capture(name : String, available : Hash(String, NamedTuple(ptr: String, type: String, heap: Bool)), local_bindings : Set(String), ordered : Array(String), seen : Set(String))
                            return unless available.has_key?(name)
                            return if local_bindings.includes?(name)
                            if seen.add?(name)
                                ordered << name
                            end
                        end
                        
                        private def generate_begin_expression(ctx : FunctionContext, node : AST::BeginExpression) : ValueRef
                            ensure_block = node.ensure_block
                            ensure_nodes = ensure_block
                            if ensure_nodes && ensure_nodes.empty?
                                ensure_nodes = nil
                            end
                            if ensure_nodes
                                ctx.ensure_stack << ensure_nodes
                            end
                            
                            value = nil
                            terminated = false
                            
                            body_value, body_terminated = evaluate_block_value(ctx, node.body)
                            value = body_value if body_value
                            terminated ||= body_terminated
                            
                            if !terminated && (else_block = node.else_block)
                                else_value, else_terminated = evaluate_block_value(ctx, else_block)
                                value = else_value if else_value
                                terminated ||= else_terminated
                            end
                            
                            unless node.rescue_clauses.empty?
                                emit_rescue_placeholder(ctx)
                            end
                            
                            if ensure_nodes
                                if last = ctx.ensure_stack.last?
                                    ctx.ensure_stack.pop if last.same?(ensure_nodes)
                                end
                                generate_block(ctx, ensure_nodes) unless terminated
                            end
                            
                            value || value_ref("i8*", "null", constant: true)
                        end
                        
                        private def evaluate_block_value(ctx : FunctionContext, statements : Array(AST::Node)) : Tuple(ValueRef?, Bool)
                            value = nil
                            terminated = false
                            
                            statements.each do |stmt|
                                if expression_node?(stmt)
                                    value = generate_expression(ctx, stmt)
                                else
                                    terminated = generate_statement(ctx, stmt)
                                end
                                break if terminated
                            end
                            
                            {value, terminated}
                        end
                        
                        private def expression_node?(node : AST::Node) : Bool
                            case node
                            when AST::Literal,
                                 AST::Variable,
                                 AST::BinaryOp,
                                 AST::MethodCall,
                                 AST::UnaryOp,
                                 AST::ArrayLiteral,
                                 AST::MapLiteral,
                                 AST::BlockLiteral,
                                 AST::BeginExpression,
                                 AST::ConstantPath,
                                 AST::TupleLiteral,
                                 AST::NamedTupleLiteral,
                                 AST::InterpolatedString
                                true
                            else
                                false
                            end
                        end
                        
                        private def extract_call_arguments(arguments : Array(AST::Node)) : NamedTuple(args: Array(AST::Node), block: AST::BlockLiteral?)
                            args = [] of AST::Node
                            block_node = nil
                            arguments.each do |argument|
                                if argument.is_a?(AST::BlockLiteral)
                                    block_node = argument
                                else
                                    args << argument
                                end
                            end
                            {args: args, block: block_node}
                        end
                        
                        private def emit_rescue_placeholder(ctx : FunctionContext)
                            label = ctx.fresh_label("rescue_stub")
                            ctx.append_postamble("#{label}:\n")
                            ctx.append_postamble("  call void @#{@runtime[:rescue_placeholder]}()\n")
                            ctx.append_postamble("  unreachable\n\n")
                        end
                        
                        private def invoke_block(ctx : FunctionContext, block_value : ValueRef, args : Array(ValueRef)) : ValueRef
                            unless block_value[:type] == "i8*"
                                raise "Cannot invoke non-block receiver of type #{block_value[:type]}"
                            end
                            boxed_args = args.map { |arg| box_value(ctx, arg) }
                            buffer = allocate_pointer_buffer(ctx, boxed_args) || "null"
                            runtime_call(ctx, "i8*", @runtime[:block_invoke], [
                                {type: "i8*", ref: block_value[:ref]},
                                {type: "i64", ref: args.size.to_s},
                                {type: "i8**", ref: buffer}
                            ])
                        end
                        
                        private def generate_constant_path(ctx : FunctionContext, node : AST::ConstantPath) : ValueRef
                            emit_constant_lookup(ctx, node.names)
                        end
                        
                        private def generate_tuple_literal(ctx : FunctionContext, node : AST::TupleLiteral) : ValueRef
                            values = node.elements.map { |elem| box_value(ctx, generate_expression(ctx, elem)) }
                            buffer = allocate_pointer_buffer(ctx, values) || "null"
                            len_literal = node.elements.size
                            runtime_call(ctx, "i8*", @runtime[:tuple_literal], [
                                {type: "i64", ref: len_literal.to_s},
                                {type: "i8**", ref: buffer}
                            ])
                        end
                        
                        private def generate_named_tuple_literal(ctx : FunctionContext, node : AST::NamedTupleLiteral) : ValueRef
                            keys = [] of ValueRef
                            values = [] of ValueRef
                            node.entries.each do |entry|
                                keys << value_ref("i8*", materialize_string_pointer(ctx, entry.name), constant: true)
                                values << box_value(ctx, generate_expression(ctx, entry.value))
                            end
                            len_literal = node.entries.size
                            keys_buffer = allocate_pointer_buffer(ctx, keys) || "null"
                            values_buffer = allocate_pointer_buffer(ctx, values) || "null"
                            runtime_call(ctx, "i8*", @runtime[:named_tuple_literal], [
                                {type: "i64", ref: len_literal.to_s},
                                {type: "i8**", ref: keys_buffer},
                                {type: "i8**", ref: values_buffer}
                            ])
                        end

                        private def generate_interpolated_string(ctx : FunctionContext, node : AST::InterpolatedString) : ValueRef
                            parts = node.normalized_parts
                            return value_ref("i8*", materialize_string_pointer(ctx, ""), constant: true) if parts.empty?

                            segments = [] of ValueRef
                            parts.each do |type, content|
                                if type == :string
                                    segments << value_ref("i8*", materialize_string_pointer(ctx, content), constant: true)
                                else
                                    expression_value = generate_expression(ctx, interpolation_expression(content))
                                    segments << ensure_string_pointer(ctx, expression_value)
                                end
                            end

                            return segments.first if segments.size == 1

                            buffer = allocate_pointer_buffer(ctx, segments) || raise "Interpolated string segments missing buffer"
                            runtime_call(ctx, "i8*", @runtime[:interpolated_string], [
                                {type: "i64", ref: segments.size.to_s},
                                {type: "i8**", ref: buffer}
                            ])
                        end
                        
                        private def generate_constant_declaration(ctx : FunctionContext, node : AST::ConstantDeclaration)
                            value = generate_expression(ctx, node.value)
                            boxed = box_value(ctx, value)
                            name_ptr = materialize_string_pointer(ctx, qualify_name(node.name))
                            runtime_call(ctx, "i8*", @runtime[:constant_define], [
                                {type: "i8*", ref: name_ptr},
                                {type: "i8*", ref: boxed[:ref]}
                            ])
                        end

                        private def generate_struct_definition(ctx : FunctionContext, node : AST::StructDefinition) : Bool
                            emit_namespace_placeholder(ctx, node.name)
                            with_namespace(node.name) do
                                generate_block(ctx, node.body)
                            end
                            false
                        end
                        
                        private def generate_index_access(ctx : FunctionContext, node : AST::IndexAccess) : ValueRef
                            object = ensure_pointer(ctx, generate_expression(ctx, node.object))
                            index = box_value(ctx, generate_expression(ctx, node.index))
                            if node.nil_safe
                                cmp = ctx.fresh("indexnil")
                                invoke_label = ctx.fresh_label("index_access")
                                nil_label = ctx.fresh_label("index_nil")
                                merge_label = ctx.fresh_label("index_merge")
                                ctx.io << "  %#{cmp} = icmp eq i8* #{object[:ref]}, null\n"
                                ctx.io << "  br i1 %#{cmp}, label %#{nil_label}, label %#{invoke_label}\n"
                                ctx.io << "#{invoke_label}:\n"
                                value = runtime_call(ctx, "i8*", @runtime[:index_get], [
                                    {type: "i8*", ref: object[:ref]},
                                    {type: "i8*", ref: index[:ref]}
                                ])
                                ctx.io << "  br label %#{merge_label}\n"
                                ctx.io << "#{nil_label}:\n"
                                ctx.io << "  br label %#{merge_label}\n"
                                ctx.io << "#{merge_label}:\n"
                                phi = ctx.fresh("indexphi")
                                ctx.io << "  %#{phi} = phi i8* [ #{value[:ref]}, %#{invoke_label} ], [ null, %#{nil_label} ]\n"
                                value_ref("i8*", "%#{phi}")
                            else
                                runtime_call(ctx, "i8*", @runtime[:index_get], [
                                    {type: "i8*", ref: object[:ref]},
                                    {type: "i8*", ref: index[:ref]}
                                ])
                            end
                        end
                        
                        private def generate_index_assignment(ctx : FunctionContext, node : AST::IndexAssignment) : ValueRef
                            if node.operator
                                raise "Compound index assignment is not supported by the LLVM backend yet"
                            end
                            if node.nil_safe
                                raise "Nil-safe index assignment is not supported by the LLVM backend yet"
                            end
                            object = ensure_pointer(ctx, generate_expression(ctx, node.object))
                            index = box_value(ctx, generate_expression(ctx, node.index))
                            value = box_value(ctx, generate_expression(ctx, node.value))
                            runtime_call(ctx, "i8*", @runtime[:index_set], [
                                {type: "i8*", ref: object[:ref]},
                                {type: "i8*", ref: index[:ref]},
                                {type: "i8*", ref: value[:ref]}
                            ])
                        end
                        
                        private def generate_case_expression(ctx : FunctionContext, node : AST::CaseStatement) : ValueRef
                            case_value = node.expression ? ensure_pointer(ctx, generate_expression(ctx, node.expression.not_nil!)) : nil
                            exit_label = ctx.fresh_label("case_exit")
                            phi_entries = [] of NamedTuple(value: ValueRef, label: String)
                            current_label = nil
                            
                            node.when_clauses.each do |clause|
                                match_label = ctx.fresh_label("case_match")
                                next_label = ctx.fresh_label("case_next")
                                condition_value = generate_case_condition(ctx, clause, case_value)
                                ctx.io << "  br i1 #{condition_value[:ref]}, label %#{match_label}, label %#{next_label}\n"
                                ctx.io << "#{match_label}:\n"
                                clause_value, clause_terminated = evaluate_block_value(ctx, clause.block)
                                unless clause_terminated
                                    resolved = clause_value ? ensure_pointer(ctx, clause_value) : value_ref("i8*", "null", constant: true)
                                    phi_entries << {value: resolved, label: match_label}
                                    ctx.io << "  br label %#{exit_label}\n"
                                end
                                ctx.io << "#{next_label}:\n"
                                current_label = next_label
                            end
                            
                            unless current_label
                                current_label = ctx.fresh_label("case_next")
                                ctx.io << "#{current_label}:\n"
                            end
                            
                            if else_block = node.else_block
                                else_value, else_terminated = evaluate_block_value(ctx, else_block)
                                unless else_terminated
                                    resolved = else_value ? ensure_pointer(ctx, else_value) : value_ref("i8*", "null", constant: true)
                                    phi_entries << {value: resolved, label: current_label}
                                    ctx.io << "  br label %#{exit_label}\n"
                                end
                            else
                                phi_entries << {value: value_ref("i8*", "null", constant: true), label: current_label}
                                ctx.io << "  br label %#{exit_label}\n"
                            end
                            
                            ctx.io << "#{exit_label}:\n"
                            if phi_entries.empty?
                                value_ref("i8*", "null", constant: true)
                            else
                                phi = ctx.fresh("casephi")
                                entries = phi_entries.map { |entry| "[ #{entry[:value][:ref]}, %#{entry[:label]} ]" }.join(", ")
                                ctx.io << "  %#{phi} = phi i8* #{entries}\n"
                                value_ref("i8*", "%#{phi}")
                            end
                        end
                        
                        private def generate_case_condition(ctx : FunctionContext, clause : AST::WhenClause, case_value : ValueRef?) : ValueRef
                            return value_ref("i1", "0", constant: true) if clause.conditions.empty?
                            
                            result = nil
                            clause.conditions.each do |condition|
                                condition_value = if case_value
                                    comparison = ensure_pointer(ctx, generate_expression(ctx, condition))
                                    runtime_call(ctx, "i1", @runtime[:case_compare], [
                                        {type: "i8*", ref: case_value[:ref]},
                                        {type: "i8*", ref: comparison[:ref]}
                                    ])
                                else
                                    ensure_boolean(ctx, generate_expression(ctx, condition))
                                end
                                if result
                                    reg = ctx.fresh("casecond")
                                    ctx.io << "  %#{reg} = or i1 #{result[:ref]}, #{condition_value[:ref]}\n"
                                    result = value_ref("i1", "%#{reg}")
                                else
                                    result = condition_value
                                end
                            end
                            
                            result || value_ref("i1", "0", constant: true)
                        end
                        
                        private def generate_yield_expression(ctx : FunctionContext, node : AST::YieldExpression) : ValueRef
                            block_pointer = load_block_pointer(ctx)
                            has_block = ctx.fresh("yieldhas")
                            invoke_label = ctx.fresh_label("yield_invoke")
                            missing_label = ctx.fresh_label("yield_missing")
                            merge_label = ctx.fresh_label("yield_merge")
                            ctx.io << "  %#{has_block} = icmp ne i8* #{block_pointer[:ref]}, null\n"
                            ctx.io << "  br i1 %#{has_block}, label %#{invoke_label}, label %#{missing_label}\n"
                            
                            ctx.io << "#{invoke_label}:\n"
                            args = node.arguments.map { |arg| generate_expression(ctx, arg) }
                            invoked = invoke_block(ctx, block_pointer, args)
                            ctx.io << "  br label %#{merge_label}\n"
                            
                            ctx.io << "#{missing_label}:\n"
                            ctx.io << "  call void @#{@runtime[:yield_missing_block]}()\n"
                            ctx.io << "  br label %#{merge_label}\n"
                            
                            ctx.io << "#{merge_label}:\n"
                            result = ctx.fresh("yield")
                            ctx.io << "  %#{result} = phi i8* [ #{invoked[:ref]}, %#{invoke_label} ], [ null, %#{missing_label} ]\n"
                            value_ref("i8*", "%#{result}")
                        end
                        
                        private def generate_literal(ctx : FunctionContext, literal : AST::Literal) : ValueRef
                            value = literal.value
                            case value
                            when Int32
                                value_ref("i32", value.to_s, constant: true)
                            when Int64
                                value_ref("i64", value.to_s, constant: true)
                            when Float64, Float32
                                value_ref("double", value.to_s, constant: true)
                            when Bool
                                value_ref("i1", value ? "1" : "0", constant: true)
                            when String
                                ptr = materialize_string_pointer(ctx, value)
                                value_ref("i8*", ptr)
                            when Nil
                                value_ref("i8*", "null", constant: true)
                            else
                                raise "Unsupported literal #{value.inspect}"
                            end
                        end
                        
                        private def materialize_string_pointer(ctx : FunctionContext, literal : String) : String
                            entry = intern_string(literal)
                            size = entry[:length] + 1
                            reg = ctx.fresh("str")
                            ctx.io << "  %#{reg} = getelementptr [#{size} x i8], [#{size} x i8]* @#{entry[:name]}, i32 0, i32 0\n"
                            "%#{reg}"
                        end
                        
                        private def box_value(ctx : FunctionContext, value : ValueRef) : ValueRef
                            case value[:type]
                            when "i32"
                                runtime_call(ctx, "i8*", @runtime[:box_i32], [{type: "i32", ref: value[:ref]}])
                            when "i64"
                                runtime_call(ctx, "i8*", @runtime[:box_i64], [{type: "i64", ref: value[:ref]}])
                            when "double"
                                runtime_call(ctx, "i8*", @runtime[:box_float], [{type: "double", ref: value[:ref]}])
                            when "i1"
                                runtime_call(ctx, "i8*", @runtime[:box_bool], [{type: "i1", ref: value[:ref]}])
                            when "i8*"
                                value
                            else
                                raise "Cannot box value of type #{value[:type]}"
                            end
                        end
                        
                        private def ensure_pointer(ctx : FunctionContext, value : ValueRef) : ValueRef
                            value[:type] == "i8*" ? value : box_value(ctx, value)
                        end
                        
                        private def allocate_pointer_buffer(ctx : FunctionContext, values : Array(ValueRef)) : String?
                            return nil if values.empty?
                            
                            size = values.size
                            buffer = ctx.fresh("buf")
                            ctx.io << "  %#{buffer} = alloca [#{size} x i8*]\n"
                            
                            values.each_with_index do |value, index|
                                slot = ctx.fresh("bufslot")
                                ctx.io << "  %#{slot} = getelementptr [#{size} x i8*], [#{size} x i8*]* %#{buffer}, i32 0, i32 #{index}\n"
                                ctx.io << "  store i8* #{value[:ref]}, i8** %#{slot}\n"
                            end
                            
                            base = ctx.fresh("bufbase")
                            ctx.io << "  %#{base} = getelementptr [#{size} x i8*], [#{size} x i8*]* %#{buffer}, i32 0, i32 0\n"
                            "%#{base}"
                        end
                        
                        private def runtime_call(ctx : FunctionContext, return_type : String, name : String, args : Array(CallArg)) : ValueRef
                            arg_source = args.map { |arg| "#{arg[:type]} #{arg[:ref]}" }.join(", ")
                            reg = ctx.fresh(name)
                            ctx.io << "  %#{reg} = call #{return_type} @#{name}(#{arg_source})\n"
                            value_ref(return_type, "%#{reg}")
                        end
                        
                        private def store_local(ctx : FunctionContext, name : String, value : ValueRef)
                            slot = ctx.locals[name]?
                            unless slot
                                ptr = "%#{ctx.fresh("slot")}"
                                ctx.io << "  #{ptr} = alloca #{value[:type]}\n"
                                slot = {ptr: ptr, type: value[:type], heap: false}
                                ctx.locals[name] = slot
                            end
                            
                            if slot[:type] != value[:type]
                                raise "Type mismatch assigning to #{name}"
                            end
                            ctx.io << "  store #{value[:type]} #{value[:ref]}, #{value[:type]}* #{slot[:ptr]}\n"
                        end
                        
                        private def load_local(ctx : FunctionContext, name : String) : ValueRef
                            slot = ctx.locals[name]? || raise "Undefined local #{name}"
                            reg = ctx.fresh("load")
                            ctx.io << "  %#{reg} = load #{slot[:type]}, #{slot[:type]}* #{slot[:ptr]}\n"
                            value_ref(slot[:type], "%#{reg}")
                        end
                        
                        private def load_block_pointer(ctx : FunctionContext) : ValueRef
                            slot = ctx.block_slot || raise "yield used in function without a block parameter"
                            reg = ctx.fresh("blockptr")
                            ctx.io << "  %#{reg} = load #{slot[:type]}, #{slot[:type]}* #{slot[:ptr]}\n"
                            value_ref(slot[:type], "%#{reg}")
                        end

                        private def emit_binary_op(ctx : FunctionContext, operator : Symbol, lhs : ValueRef, rhs : ValueRef) : ValueRef
                            if struct_name = struct_name_for_value(lhs)
                                method_name = operator.to_s
                                return emit_struct_method_dispatch(ctx, struct_name, lhs, method_name, [rhs])
                            end

                            if float_type?(lhs[:type]) || float_type?(rhs[:type])
                                return emit_float_op(ctx, operator, lhs, rhs)
                            end

                            case operator
                            when :+, :-, :*, :/, :"&+", :"//", :"&-", :"<=>"
                                target_bits = integer_operation_width(lhs, rhs)
                                lhs = coerce_integer(ctx, lhs, target_bits)
                                rhs = coerce_integer(ctx, rhs, target_bits)
                                instruction = case operator
                                when :+, :"&+" then "add"
                                when :- then "sub"
                                when :* then "mul"
                                when :/ then "sdiv"
                                when :"//" then "sdiv"
                                when :"&-" then "sub"
                                when :"<=>" then nil
                                else
                                    raise "Unsupported arithmetic operator #{operator}"
                                end
                                
                                type = "i#{target_bits}"
                                if operator == :"<=>"
                                    reg = ctx.fresh("cmp3")
                                    gt = ctx.fresh("cmpgt")
                                    lt = ctx.fresh("cmplt")
                                    ctx.io << "  %#{gt} = icmp sgt #{type} #{lhs[:ref]}, #{rhs[:ref]}\n"
                                    ctx.io << "  %#{lt} = icmp slt #{type} #{lhs[:ref]}, #{rhs[:ref]}\n"
                                    pos = ctx.fresh("cmpres")
                                    ctx.io << "  %#{pos} = select i1 %#{gt}, #{type} 1, #{type} 0\n"
                                    neg = ctx.fresh("cmpneg")
                                    ctx.io << "  %#{neg} = select i1 %#{lt}, #{type} -1, #{type} 0\n"
                                    ctx.io << "  %#{reg} = add #{type} %#{pos}, %#{neg}\n"
                                    value_ref(type, "%#{reg}")
                                else
                                    reg = ctx.fresh
                                    ctx.io << "  %#{reg} = #{instruction} #{type} #{lhs[:ref]}, #{rhs[:ref]}\n"
                                    value_ref(type, "%#{reg}")
                                end
                            when :"==", :"!=", :"<", :"<=", :">", :">="
                                if float_operation?(lhs, rhs)
                                    emit_float_comparison(ctx, operator, lhs, rhs)
                                else
                                    emit_integer_comparison(ctx, operator, lhs, rhs)
                                end
                            else
                                raise "Unsupported operator #{operator}"
                            end
                        end
                        
                        private def emit_integer_comparison(ctx : FunctionContext, operator : Symbol, lhs : ValueRef, rhs : ValueRef) : ValueRef
                            target_bits = integer_operation_width(lhs, rhs)
                            lhs = coerce_integer(ctx, lhs, target_bits)
                            rhs = coerce_integer(ctx, rhs, target_bits)
                            predicate = case operator
                            when :"==" then "eq"
                            when :"!=" then "ne"
                            when :"<"  then "slt"
                            when :"<=" then "sle"
                            when :">"  then "sgt"
                            when :">=" then "sge"
                            else
                                raise "Unsupported comparison #{operator}"
                            end
                            reg = ctx.fresh("cmp")
                            type = "i#{target_bits}"
                            ctx.io << "  %#{reg} = icmp #{predicate} #{type} #{lhs[:ref]}, #{rhs[:ref]}\n"
                            value_ref("i1", "%#{reg}")
                        end
                        
                        private def generate_method_call(ctx : FunctionContext, call : AST::MethodCall) : ValueRef?
                            arg_info = extract_call_arguments(call.arguments)
                            args = arg_info[:args]
                            block_node = arg_info[:block]
                            
                            if call.name == "echo"
                                raise "echo expects exactly one argument" unless args.size == 1
                                raise "echo does not accept a block" if block_node
                                arg_val = generate_expression(ctx, args.first)
                                emit_echo(ctx, arg_val)
                                return nil
                            end
                            
                            block_value = block_node ? generate_block_literal(ctx, block_node) : nil
                            arg_values = args.map { |arg| generate_expression(ctx, arg) }
                            if receiver = call.receiver
                                if struct_name = resolve_struct_reference(receiver)
                                    if call.name == "new"
                                        raise "Struct constructors do not accept blocks" if block_value
                                        return emit_struct_new(ctx, struct_name, arg_values)
                                    end
                                end
                                receiver_value = generate_expression(ctx, receiver)
                                if call.name == "call" && receiver_value[:type] == "i8*"
                                    return invoke_block(ctx, receiver_value, arg_values)
                                end
                                if struct_name = struct_name_for_value(receiver_value)
                                    raise "Struct methods do not support blocks yet" if block_value
                                    return emit_struct_method_dispatch(ctx, struct_name, receiver_value, call.name, arg_values)
                                end
                                return emit_receiver_call(ctx, call.name, receiver_value, arg_values)
                            end
                            
                            requires_block = @function_requires_block[call.name]? || false
                            call_args = arg_values.dup
                            if requires_block
                                block_argument = block_value || value_ref("i8*", "null", constant: true)
                                call_args << block_argument
                            elsif block_value
                                raise "Function #{call.name} does not accept a block"
                            end
                            
                            emit_function_call(ctx, call, call_args)
                        end
                        
                        private def emit_function_call(ctx : FunctionContext, call : AST::MethodCall, args : Array(ValueRef)) : ValueRef?
                            target_name = call.name == "main" ? "__dragonstone_user_main" : call.name
                            signature = ensure_function_signature(target_name)
                            
                            expected = signature[:param_types].size
                            provided = args.size
                            unless expected == provided
                                raise "Function #{call.name} expects #{expected} arguments but got #{provided}"
                            end
                            
                            coerced_args = args.map_with_index do |value, index|
                                ensure_value_type(ctx, value, signature[:param_types][index])
                            end
                            
                            arg_source = coerced_args.map { |value| "#{value[:type]} #{value[:ref]}" }.join(", ")

                            if signature[:return_type] == "void"
                                ctx.io << "  call void @\"#{target_name}\"(#{arg_source})\n"
                                nil
                            else
                                reg = ctx.fresh("call")
                                ctx.io << "  %#{reg} = call #{signature[:return_type]} @\"#{target_name}\"(#{arg_source})\n"
                                value_ref(signature[:return_type], "%#{reg}")
                            end
                        end
                        
                        private def emit_receiver_call(ctx : FunctionContext, method_name : String, receiver : ValueRef, args : Array(ValueRef)) : ValueRef
                            boxed = args.map { |arg| box_value(ctx, arg) }
                            buffer = allocate_pointer_buffer(ctx, boxed) || "null"
                            name_ptr = materialize_string_pointer(ctx, method_name)
                            runtime_call(ctx, "i8*", @runtime[:method_invoke], [
                                {type: "i8*", ref: receiver[:ref]},
                                {type: "i8*", ref: name_ptr},
                                {type: "i64", ref: args.size.to_s},
                                {type: "i8**", ref: buffer}
                            ])
                        end
                        
                        private def emit_echo(ctx : FunctionContext, value : ValueRef)
                            case value[:type]
                            when "i8*"
                                display = runtime_call(ctx, "i8*", @runtime[:display_value], [{type: "i8*", ref: value[:ref]}])
                                ctx.io << "  call i32 @puts(i8* #{display[:ref]})\n"
                            when "i32", "i64"
                                emit_echo_integer(ctx, value)
                            when "double"
                                format_ptr = materialize_string_pointer(ctx, "%g\n")
                                ctx.io << "  call i32 (i8*, ...) @printf(i8* #{format_ptr}, double #{value[:ref]})\n"
                            when "i1"
                                true_ptr = materialize_string_pointer(ctx, "true")
                                false_ptr = materialize_string_pointer(ctx, "false")
                                reg = ctx.fresh("boolstr")
                                ctx.io << "  %#{reg} = select i1 #{value[:ref]}, i8* #{true_ptr}, i8* #{false_ptr}\n"
                                ctx.io << "  call i32 @puts(i8* %#{reg})\n"
                            else
                                raise "echo currently supports strings, integers, booleans, or doubles"
                            end
                        end
                        
                        private def emit_echo_integer(ctx : FunctionContext, value : ValueRef)
                            coerced = value[:type] == "i64" ? value : extend_to_i64(ctx, value)
                            format_ptr = materialize_string_pointer(ctx, "%lld\n")
                            ctx.io << "  call i32 (i8*, ...) @printf(i8* #{format_ptr}, i64 #{coerced[:ref]})\n"
                        end
                        
                        private def ensure_value_type(ctx : FunctionContext, value : ValueRef, expected : String) : ValueRef
                            return value if value[:type] == expected

                            case expected
                            when "i32"
                                coerce_integer(ctx, value, 32)
                            when "i64"
                                coerce_integer(ctx, value, 64)
                            when "i1"
                                coerce_boolean_exact(ctx, value)
                            when "double"
                                ensure_double(ctx, value)
                            else
                                raise "Cannot convert #{value[:type]} to #{expected}"
                            end
                        end
                        
                        private def extend_to_i64(ctx : FunctionContext, value : ValueRef) : ValueRef
                            unless value[:type] == "i32"
                                raise "Expected i32 when extending to i64, got #{value[:type]}"
                            end
                            reg = ctx.fresh("sext")
                            ctx.io << "  %#{reg} = sext i32 #{value[:ref]} to i64\n"
                            value_ref("i64", "%#{reg}")
                        end

                        private def integer_operation_width(lhs : ValueRef, rhs : ValueRef) : Int32
                            left_bits = bits_for_type(lhs[:type])
                            right_bits = bits_for_type(rhs[:type])
                            bits = {left_bits, right_bits}.max
                            bits = 64 if bits == 0
                            bits
                        end

                        private def bits_for_type(type : String) : Int32
                            case type
                            when "i32" then 32
                            when "i64" then 64
                            when "i1"  then 1
                            else
                                0
                            end
                        end

                        private def coerce_integer(ctx : FunctionContext, value : ValueRef, target_bits : Int32) : ValueRef
                            if integer_type?(value[:type])
                                adjust_integer_width(ctx, value, target_bits)
                            elsif float_type?(value[:type])
                                double_value = ensure_double(ctx, value)
                                reg = ctx.fresh("fptosi")
                                ctx.io << "  %#{reg} = fptosi double #{double_value[:ref]} to i#{target_bits}\n"
                                value_ref("i#{target_bits}", "%#{reg}")
                            elsif value[:type] == "i8*"
                                unboxed = runtime_call(ctx, "i64", @runtime[:unbox_i64], [{type: "i8*", ref: value[:ref]}])
                                target_bits == 32 ? truncate_integer(ctx, unboxed, 32) : unboxed
                            else
                                raise "Cannot treat #{value[:type]} as integer"
                            end
                        end

                        private def adjust_integer_width(ctx : FunctionContext, value : ValueRef, target_bits : Int32) : ValueRef
                            current_bits = bits_for_type(value[:type])
                            raise "Unknown integer width for #{value[:type]}" if current_bits == 0
                            return value if current_bits == target_bits

                            if current_bits < target_bits
                                reg = ctx.fresh("sext")
                                ctx.io << "  %#{reg} = sext i#{current_bits} #{value[:ref]} to i#{target_bits}\n"
                                value_ref("i#{target_bits}", "%#{reg}")
                            else
                                truncate_integer(ctx, value, target_bits)
                            end
                        end

                        private def truncate_integer(ctx : FunctionContext, value : ValueRef, target_bits : Int32) : ValueRef
                            current_bits = bits_for_type(value[:type])
                            raise "Cannot truncate non-integer #{value[:type]}" if current_bits == 0
                            return value if current_bits == target_bits
                            reg = ctx.fresh("trunc")
                            ctx.io << "  %#{reg} = trunc i#{current_bits} #{value[:ref]} to i#{target_bits}\n"
                            value_ref("i#{target_bits}", "%#{reg}")
                        end
                        
                        private def ensure_integer_type(type : String)
                            raise "Expected integer type, got #{type}" unless integer_type?(type)
                        end
                        
                        private def integer_type?(type : String) : Bool
                            type.starts_with?("i") && !type.ends_with?("*")
                        end
                        
                        private def ensure_boolean(ctx : FunctionContext, value : ValueRef) : ValueRef
                            return value if value[:type] == "i1"
                            
                            if integer_type?(value[:type])
                                reg = ctx.fresh("tobool")
                                ctx.io << "  %#{reg} = icmp ne #{value[:type]} #{value[:ref]}, 0\n"
                                value_ref("i1", "%#{reg}")
                            elsif value[:type].ends_with?("*")
                                reg = ctx.fresh("ptrbool")
                                ctx.io << "  %#{reg} = icmp ne #{value[:type]} #{value[:ref]}, null\n"
                                value_ref("i1", "%#{reg}")
                            else
                                raise "Cannot treat #{value[:type]} as boolean"
                            end
                        end

                        private def float_operation?(lhs : ValueRef, rhs : ValueRef) : Bool
                            float_type?(lhs[:type]) || float_type?(rhs[:type])
                        end

                        private def float_type?(type : String) : Bool
                            type == "float" || type == "double"
                        end

                        private def ensure_double(ctx : FunctionContext, value : ValueRef) : ValueRef
                            case value[:type]
                            when "double"
                                value
                            when "float"
                                reg = ctx.fresh("fpext")
                                ctx.io << "  %#{reg} = fpext float #{value[:ref]} to double\n"
                                value_ref("double", "%#{reg}")
                            when "i8*"
                                runtime_call(ctx, "double", @runtime[:unbox_float], [{type: "i8*", ref: value[:ref]}])
                            else
                                if integer_type?(value[:type])
                                    reg = ctx.fresh("sitofp")
                                    ctx.io << "  %#{reg} = sitofp #{value[:type]} #{value[:ref]} to double\n"
                                    value_ref("double", "%#{reg}")
                                else
                                    raise "Cannot treat #{value[:type]} as floating-point"
                                end
                            end
                        end

                        private def emit_float_op(ctx : FunctionContext, operator : Symbol, lhs : ValueRef, rhs : ValueRef) : ValueRef
                            lhs = ensure_double(ctx, lhs)
                            rhs = ensure_double(ctx, rhs)
                            instruction = case operator
                            when :+, :"&+" then "fadd"
                            when :-, :"&-" then "fsub"
                            when :* then "fmul"
                            when :/ , :"//" then "fdiv"
                            when :"<=>"
                                return emit_float_spaceship(ctx, lhs, rhs)
                            else
                                raise "Unsupported float operator #{operator}"
                            end
                            reg = ctx.fresh("fmath")
                            ctx.io << "  %#{reg} = #{instruction} double #{lhs[:ref]}, #{rhs[:ref]}\n"
                            value_ref("double", "%#{reg}")
                        end

                        private def emit_float_spaceship(ctx : FunctionContext, lhs : ValueRef, rhs : ValueRef) : ValueRef
                            lhs = ensure_double(ctx, lhs)
                            rhs = ensure_double(ctx, rhs)
                            gt = ctx.fresh("fcmpgt")
                            lt = ctx.fresh("fcmplt")
                            ctx.io << "  %#{gt} = fcmp ogt double #{lhs[:ref]}, #{rhs[:ref]}\n"
                            ctx.io << "  %#{lt} = fcmp olt double #{lhs[:ref]}, #{rhs[:ref]}\n"
                            pos = ctx.fresh("fcmpres")
                            ctx.io << "  %#{pos} = select i1 %#{gt}, i32 1, i32 0\n"
                            neg = ctx.fresh("fcmpneg")
                            ctx.io << "  %#{neg} = select i1 %#{lt}, i32 -1, i32 0\n"
                            reg = ctx.fresh("fcmpadd")
                            ctx.io << "  %#{reg} = add i32 %#{pos}, %#{neg}\n"
                            value_ref("i32", "%#{reg}")
                        end

                        private def emit_float_comparison(ctx : FunctionContext, operator : Symbol, lhs : ValueRef, rhs : ValueRef) : ValueRef
                            lhs = ensure_double(ctx, lhs)
                            rhs = ensure_double(ctx, rhs)
                            predicate = case operator
                            when :"==" then "oeq"
                            when :"!=" then "one"
                            when :"<"  then "olt"
                            when :"<=" then "ole"
                            when :">"  then "ogt"
                            when :">=" then "oge"
                            else
                                raise "Unsupported float comparison #{operator}"
                            end
                            reg = ctx.fresh("fcmp")
                            ctx.io << "  %#{reg} = fcmp #{predicate} double #{lhs[:ref]}, #{rhs[:ref]}\n"
                            value_ref("i1", "%#{reg}")
                        end

                        private def coerce_boolean_exact(ctx : FunctionContext, value : ValueRef) : ValueRef
                            case value[:type]
                            when "i1"
                                value
                            when "i8*"
                                runtime_call(ctx, "i1", @runtime[:unbox_bool], [{type: "i8*", ref: value[:ref]}])
                            else
                                ensure_boolean(ctx, value)
                            end
                        end
                        
                        private def emit_boolean_not(ctx : FunctionContext, value : ValueRef) : ValueRef
                            reg = ctx.fresh("not")
                            ctx.io << "  %#{reg} = xor i1 #{value[:ref]}, 1\n"
                            value_ref("i1", "%#{reg}")
                        end
                        
                        private def llvm_type_of(type_expr : AST::TypeExpression?) : String
                            return "void" unless type_expr
                            
                            case type_expr
                            when AST::SimpleTypeExpression
                                name = type_expr.name
                                case name
                                when "Int32", "int"                 then "i32"
                                when "Int64"                        then "i64"
                                when "Bool", "bool"                 then "i1"
                                when "Float32"                      then "float"
                                when "Float64", "Float", "float"    then "double"
                                when "String", "str"                then "i8*"
                                # when "Void", "void"                 then "void"
                                else
                                    if struct_type?(name)
                                        llvm_struct_name(name)
                                    else
                                        pointer_type_for("%DSObject")
                                    end
                                end
                            else
                                pointer_type_for("%DSValue")
                            end
                        end
                        
                        private def struct_field_type(type_expr : AST::TypeExpression?) : String
                            if type_expr
                                field_type = llvm_type_of(type_expr)
                                field_type == "void" ? pointer_type_for("%DSValue") : field_type
                            else
                                pointer_type_for("%DSValue")
                            end
                        end
                        
                        private def llvm_param_type(type_expr : AST::TypeExpression?) : String
                            return pointer_type_for("%DSValue") unless type_expr
                            llvm_type_of(type_expr)
                        end
                        
                        private def zero_value(type : String) : String
                            case type
                            when "i1", "i32", "i64"
                                "0"
                            when "double", "float"
                                "0.0"
                            when "i8*"
                                "null"
                            else
                                if type.starts_with?("%")
                                    "zeroinitializer"
                                else
                                    "0"
                                end
                            end
                        end
                        
                        private def intern_string(value : String) : NamedTuple(name: String, escaped: String, length: Int32)
                            @string_literals[value]? || begin
                                escaped = escape_string(value)
                                name = ".str#{@string_counter}"
                                @string_counter += 1
                                entry = {name: name, escaped: escaped, length: value.bytesize}
                                @string_literals[value] = entry
                                @string_order << value
                                entry
                            end
                        end
                        
                        private def escape_string(str : String) : String
                            str.gsub("\\", "\\\\").gsub("\"", "\\\"").gsub("\n", "\\0A").gsub("\t", "\\09")
                        end
                        
                        private def ensure_function_signature(name : String) : FunctionSignature
                            if signature = @function_signatures[name]?
                                signature
                            else
                                if info = @analysis.symbol_table.lookup(name)
                                    if info.kind == Language::Sema::SymbolKind::Function
                                        raise "Function #{name} is declared but no definition was provided for LLVM emission"
                                    end
                                end
                                raise "Unknown function #{name}"
                            end
                        end
                        
                        private def value_ref(type : String, ref : String, constant : Bool = false, kind : Symbol? = nil) : ValueRef
                            {type: type, ref: ref, constant: constant, kind: kind}
                        end
                        
                        private def pointer_type_for(type : String) : String
                            "#{type}*"
                        end
                        
                        private def unique_block_symbol : String
                            symbol = "dragonstone_block_#{@string_counter}"
                            @string_counter += 1
                            symbol
                        end
                        
                        private def emit_constant_lookup(ctx : FunctionContext, segments : Array(String)) : ValueRef
                            raise "Empty constant path" if segments.empty?
                            refs = segments.map do |segment|
                                ptr = materialize_string_pointer(ctx, segment)
                                value_ref("i8*", ptr, constant: true)
                            end
                            
                            buffer = allocate_pointer_buffer(ctx, refs) || raise("Constant path segments missing buffer")
                            runtime_call(ctx, "i8*", @runtime[:constant_lookup], [
                                {type: "i64", ref: segments.size.to_s},
                                {type: "i8**", ref: buffer}
                            ])
                        end

                        private def generate_variable_reference(ctx : FunctionContext, name : String) : ValueRef
                            if constant_symbol?(name)
                                emit_constant_lookup(ctx, [name])
                            else
                                load_local(ctx, name)
                            end
                        end

                        private def constant_symbol?(name : String) : Bool
                            if info = @analysis.symbol_table.lookup(name)
                                case info.kind
                                    
                                when Language::Sema::SymbolKind::Constant,
                                     Language::Sema::SymbolKind::Type,
                                     Language::Sema::SymbolKind::Module
                                    true
                                else
                                    false
                                end
                            else
                                false
                            end
                        end

                        private def generate_class_definition(ctx : FunctionContext, node : AST::ClassDefinition) : Bool
                            emit_namespace_placeholder(ctx, node.name)
                            with_namespace(node.name) do
                                generate_block(ctx, node.body)
                            end
                            false
                        end

                        private def generate_module_definition(ctx : FunctionContext, node : AST::ModuleDefinition) : Bool
                            emit_namespace_placeholder(ctx, node.name)
                            with_namespace(node.name) do
                                generate_block(ctx, node.body)
                            end
                            false
                        end

                        private def emit_namespace_placeholder(ctx : FunctionContext, name : String)
                            full_name = qualify_name(name)
                            name_ptr = materialize_string_pointer(ctx, full_name)
                            runtime_call(ctx, "i8*", @runtime[:constant_define], [
                                {type: "i8*", ref: name_ptr},
                                {type: "i8*", ref: "null"}
                            ])
                        end

                        private def canonical_struct_name(name : String) : String?
                            return name if @struct_layouts.has_key?(name)
                            @struct_alias_map[name]?
                        end

                        private def struct_type?(name : String) : Bool
                            !!canonical_struct_name(name)
                        end

                        private def struct_name_for_value(value : ValueRef) : String?
                            type = value[:type]
                            return nil unless type.starts_with?("%")
                            symbol = strip_pointer_suffix(type[1..-1])
                            @struct_llvm_lookup[symbol]?
                        end

                        private def strip_pointer_suffix(symbol : String) : String
                            idx = symbol.index('*')
                            idx ? symbol[0, idx] : symbol
                        end

                        private def llvm_struct_symbol(name : String) : String
                            canonical = canonical_struct_name(name) || name
                            canonical.gsub("::", "_")
                        end

                        private def llvm_struct_name(name : String) : String
                            "%#{llvm_struct_symbol(name)}"
                        end

                        private def struct_method_symbol(struct_name : String, method_name : String) : String
                            "#{llvm_struct_symbol(struct_name)}_#{method_name}"
                        end

                        private def resolve_struct_reference(node : AST::Node) : String?
                            name = case node
                                when AST::ConstantPath
                                    node.names.join("::")
                                when AST::Variable
                                    node.name
                                else
                                    return nil
                                end
                            canonical_struct_name(name)
                        end

                        private def emit_struct_new(ctx : FunctionContext, struct_name : String, args : Array(ValueRef)) : ValueRef
                            fields = @struct_layouts[struct_name]? || raise "Unknown struct #{struct_name}"

                            if args.size != fields.size
                                raise "Struct #{struct_name} expects #{fields.size} arguments but got #{args.size}"
                            end

                            struct_type = llvm_struct_name(struct_name)
                            current_ref = "zeroinitializer"
                            args.each_with_index do |arg, index|
                                target_type_expr = fields[index]
                                target_type = target_type_expr ? llvm_type_of(target_type_expr) : pointer_type_for("%DSValue")
                                coerced = ensure_value_type(ctx, arg, target_type)
                                reg = ctx.fresh("structinit")
                                base = current_ref == "zeroinitializer" ? "zeroinitializer" : current_ref
                                ctx.io << "  %#{reg} = insertvalue #{struct_type} #{base}, #{coerced[:type]} #{coerced[:ref]}, #{index}\n"
                                current_ref = "%#{reg}"
                            end

                            if current_ref == "zeroinitializer"
                                value_ref(struct_type, current_ref, constant: true)
                            else
                                value_ref(struct_type, current_ref)
                            end
                        end

                        private def ensure_string_pointer(ctx : FunctionContext, value : ValueRef) : ValueRef
                            return value if value[:type] == "i8*"
                            boxed = box_value(ctx, value)
                            runtime_call(ctx, "i8*", @runtime[:display_value], [{type: "i8*", ref: boxed[:ref]}])
                        end

                        private def interpolation_expression(content)
                            return content if content.is_a?(AST::Node)
                            parse_interpolation_expression(content.to_s)
                        end

                        private def parse_interpolation_expression(source : String) : AST::Node
                            lexer = Lexer.new(source)
                            tokens = lexer.tokenize
                            parser = Parser.new(tokens)
                            parser.parse_expression_entry
                        end

                        private def emit_struct_field_access(ctx : FunctionContext, struct_name : String, receiver : ValueRef, method_name : String, args : Array(ValueRef)) : ValueRef?
                            indices = @struct_field_indices[struct_name]?
                            return nil unless indices
                            index = indices[method_name]?
                            return nil unless index
                            raise "Struct field #{method_name} expects no arguments" unless args.empty?
                            fields = @struct_layouts[struct_name]? || raise "Unknown struct layout #{struct_name}"
                            field_type_expr = fields[index]?
                            field_type = field_type_expr ? llvm_type_of(field_type_expr) : pointer_type_for("%DSValue")
                            reg = ctx.fresh("field")
                            struct_type = receiver[:type]
                            ctx.io << "  %#{reg} = extractvalue #{struct_type} #{receiver[:ref]}, #{index}\n"
                            value_ref(field_type, "%#{reg}")
                        end

                        private def emit_struct_method_dispatch(ctx : FunctionContext, struct_name : String, receiver : ValueRef, method_name : String, args : Array(ValueRef)) : ValueRef
                            if value = emit_struct_field_access(ctx, struct_name, receiver, method_name, args)
                                return value
                            end
                            
                            function_symbol = struct_method_symbol(struct_name, method_name)
                            signature = ensure_function_signature(function_symbol)
                            call_args = [receiver] + args
                            expected_params = signature[:param_types]

                            if expected_params.size != call_args.size
                                raise "Struct method #{function_symbol} expects #{expected_params.size} arguments but got #{call_args.size}"
                            end

                            coerced_args = call_args.map_with_index do |value, index|
                                expected_type = expected_params[index]
                                value[:type] == expected_type ? value : ensure_value_type(ctx, value, expected_type)
                            end

                            arg_source = coerced_args.map { |value| "#{value[:type]} #{value[:ref]}" }.join(", ")
                            return_type = signature[:return_type]

                            if return_type == "void"
                                ctx.io << "  call void @\"#{function_symbol}\"(#{arg_source})\n"
                                value_ref("i8*", "null", constant: true)
                            else
                                reg = ctx.fresh("structcall")
                                ctx.io << "  %#{reg} = call #{return_type} @\"#{function_symbol}\"(#{arg_source})\n"
                                value_ref(return_type, "%#{reg}")
                            end
                        end

                    private def qualify_name(name : String) : String
                            if @namespace_stack.empty?
                                name
                            else
                                (@namespace_stack + [name]).join("::")
                            end
                        end

                        private def with_namespace(name : String)
                            @namespace_stack << name
                            yield
                        ensure
                            @namespace_stack.pop
                        end

                        private def generate_expression_result(ctx : FunctionContext, node : AST::Node) : ValueRef?
                            begin
                                generate_expression(ctx, node)
                            rescue
                                nil
                            end
                        end
                    end
                end
            end
        end
    end
end
