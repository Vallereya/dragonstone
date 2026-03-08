# ---------------------------------
# --------- C Backend -------------
# ---------------------------------
require "set"
require "../../build_options"
require "../shared/helpers"
require "../shared/program_serializer"
require "../../../../shared/language/lexer/lexer"
require "../../../../shared/language/parser/parser"
require "../../../../shared/runtime/symbol"

module Dragonstone
  module Core
    module Compiler
      module Targets
        module C
          class Backend
            EXTENSION = "c"

            def build(program : ::Dragonstone::IR::Program, options : BuildOptions) : BuildArtifact
              artifact_path = Shared.artifact_path(options, EXTENSION)
              File.write(artifact_path, build_content(program))
              BuildArtifact.new(target: Target::C, object_path: artifact_path)
            end

            private def build_content(program : ::Dragonstone::IR::Program) : String
              generator = CGenerator.new(program)
              String.build { |io| generator.generate(io) }
            end
          end

          class CGenerator
            alias StringEntry = NamedTuple(name: String, escaped: String, length: Int32)

            private class FunctionContext
              getter io : IO
              getter declared_locals : Set(String)
              getter loop_stack : Array(NamedTuple(exit_label: String, next_label: String, redo_label: String))
              getter retry_stack : Array(String)
              getter ensure_stack : Array(Array(AST::Node))
              getter with_stack : Array(String)
              property block_param : String?
              property callable_name : String?
              property parameter_names : Array(String)

              @temp_counter = 0
              @label_counter = 0

              def initialize(@io : IO)
                @declared_locals = Set(String).new
                @loop_stack = [] of NamedTuple(exit_label: String, next_label: String, redo_label: String)
                @retry_stack = [] of String
                @ensure_stack = [] of Array(AST::Node)
                @with_stack = [] of String
                @block_param = nil
                @callable_name = nil
                @parameter_names = [] of String
              end

              def fresh(prefix = "_t") : String
                n = @temp_counter
                @temp_counter += 1
                "#{prefix}#{n}"
              end

              def fresh_label(prefix = "_lbl") : String
                n = @label_counter
                @label_counter += 1
                "#{prefix}#{n}"
              end

              def declare_local(name : String) : Bool
                return false if @declared_locals.includes?(name)
                @declared_locals << name
                true
              end

              def has_local?(name : String) : Bool
                @declared_locals.includes?(name)
              end
            end

            @string_counter = 0
            @string_literals : Hash(String, StringEntry)
            @string_order : Array(String)

            @function_names : Hash(AST::FunctionDef, String)
            @function_receivers : Hash(AST::FunctionDef, Bool)
            @function_namespaces : Hash(AST::FunctionDef, Array(String))
            @function_defs : Hash(String, AST::FunctionDef)
            @function_overloads : Hash(String, Array(String))
            @function_requires_block : Hash(String, Bool)
            @emitted_functions : Set(String)

            @globals : Set(String)
            @known_constants : Set(String)
            @class_scope_bindings : Hash(String, Set(String))
            @namespace_stack : Array(String)
            @class_name_occurrences : Hash(String, Int32)

            @struct_layouts : Hash(String, Array(AST::TypeExpression?))
            @struct_field_indices : Hash(String, Hash(String, Int32))
            @struct_alias_map : Hash(String, String)
            @struct_name_occurrences : Hash(String, Int32)
            @struct_unique_names : Hash(AST::StructDefinition, String)
            @struct_stack : Array(String)

            @pending_blocks : Array(String)
            @block_counter = 0

            def initialize(@program : ::Dragonstone::IR::Program)
              @string_literals = {} of String => StringEntry
              @string_order = [] of String

              @function_names = {} of AST::FunctionDef => String
              @function_receivers = {} of AST::FunctionDef => Bool
              @function_namespaces = {} of AST::FunctionDef => Array(String)
              @function_defs = {} of String => AST::FunctionDef
              @function_overloads = Hash(String, Array(String)).new { |h, k| h[k] = [] of String }
              @function_requires_block = {} of String => Bool
              @emitted_functions = Set(String).new

              @globals = Set(String).new
              @known_constants = Set(String).new
              @class_scope_bindings = Hash(String, Set(String)).new { |h, k| h[k] = Set(String).new }
              @namespace_stack = [] of String
              @class_name_occurrences = Hash(String, Int32).new(0)

              @struct_layouts = {} of String => Array(AST::TypeExpression?)
              @struct_field_indices = {} of String => Hash(String, Int32)
              @struct_alias_map = {} of String => String
              @struct_name_occurrences = Hash(String, Int32).new(0)
              @struct_unique_names = {} of AST::StructDefinition => String
              @struct_stack = [] of String

              @pending_blocks = [] of String

              index_struct_types
            end

            def generate(io : IO)
              collect_strings
              collect_globals
              collect_bindings
              collect_functions

              @namespace_stack.clear
              @class_name_occurrences.clear

              functions_io = String::Builder.new
              entrypoint_io = String::Builder.new
              emit_functions(functions_io)
              emit_entrypoint(entrypoint_io)

              emit_prelude(io)
              emit_extern_decls(io)
              emit_string_constants(io)
              emit_globals(io)
              emit_forward_decls(io)
              @pending_blocks.each { |blk| io << blk }
              io << functions_io.to_s
              io << entrypoint_io.to_s
            end

            private def emit_prelude(io : IO)
              io << "/* --------------------------------- */\n"
              io << "/* Dragonstone C Target Artifact     */\n"
              io << "/* --------------------------------- */\n"
              io << "#define _CRT_SECURE_NO_WARNINGS\n"
              io << "#include <stdint.h>\n"
              io << "#include <stdbool.h>\n"
              io << "#include <stdio.h>\n"
              io << "#include <stdlib.h>\n"
              io << "#include <string.h>\n"
              io << "#include <setjmp.h>\n"
              io << "#include <math.h>\n"
              io << "\n"
              io << "typedef struct { jmp_buf env; void *prev; } DSExceptionFrame;\n"
              io << "\n"
            end

            private def emit_extern_decls(io : IO)
              io << "/* --- runtime externs --- */\n"
              [
                "extern void  *dragonstone_runtime_box_i32(int32_t v);",
                "extern void  *dragonstone_runtime_box_i64(int64_t v);",
                "extern void  *dragonstone_runtime_box_bool(int32_t v);",
                "extern void  *dragonstone_runtime_box_float(double v);",
                "extern void  *dragonstone_runtime_box_string(void *v);",
                "extern int32_t dragonstone_runtime_unbox_i32(void *v);",
                "extern int64_t dragonstone_runtime_unbox_i64(void *v);",
                "extern int32_t dragonstone_runtime_unbox_bool(void *v);",
                "extern double  dragonstone_runtime_unbox_float(void *v);",
                "extern void  *dragonstone_runtime_box_struct(void *data, int64_t size);",
                "extern void  *dragonstone_runtime_unbox_struct(void *v);",
                "extern void  *dragonstone_runtime_array_literal(int64_t len, void **elems);",
                "extern void  *dragonstone_runtime_array_push(void *arr, void *val);",
                "extern void  *dragonstone_runtime_map_literal(int64_t len, void **keys, void **vals);",
                "extern void  *dragonstone_runtime_tuple_literal(int64_t len, void **elems);",
                "extern void  *dragonstone_runtime_named_tuple_literal(int64_t len, void **keys, void **vals);",
                "extern void  *dragonstone_runtime_block_literal(void *(*func)(void *, int64_t, void **), void *env);",
                "extern void  *dragonstone_runtime_block_invoke(void *block, int64_t argc, void **argv);",
                "extern void **dragonstone_runtime_block_env_allocate(int64_t count);",
                "extern void  *dragonstone_runtime_method_invoke(void *recv, void *name, int64_t argc, void **argv, void *block);",
                "extern void  *dragonstone_runtime_super_invoke(void *recv, void *klass_name, void *meth_name, int64_t argc, void **argv, void *block);",
                "extern void  *dragonstone_runtime_constant_lookup(int64_t count, void **segments);",
                "extern void  *dragonstone_runtime_define_constant(void *name, void *val);",
                "extern void  *dragonstone_runtime_constant_define(void *name, void *val);",
                "extern void  *dragonstone_runtime_define_class(void *name);",
                "extern void   dragonstone_runtime_set_superclass(void *klass, void *super_klass);",
                "extern void  *dragonstone_runtime_define_module(void *name);",
                "extern void   dragonstone_runtime_define_method(void *klass, void *name, void *func, int32_t expects_block);",
                "extern void   dragonstone_runtime_define_singleton_method(void *recv, void *name, void *func);",
                "extern void   dragonstone_runtime_define_enum_member(void *klass, void *name, int64_t val);",
                "extern void   dragonstone_runtime_extend_container(void *target, void *mod);",
                "extern void  *dragonstone_runtime_ivar_get(void *obj, void *name);",
                "extern void  *dragonstone_runtime_ivar_set(void *obj, void *name, void *val);",
                "extern void  *dragonstone_runtime_index_get(void *obj, void *idx);",
                "extern void  *dragonstone_runtime_index_set(void *obj, void *idx, void *val);",
                "extern void  *dragonstone_runtime_value_display(void *v);",
                "extern void  *dragonstone_runtime_value_inspect(void *v);",
                "extern void  *dragonstone_runtime_to_string(void *v);",
                "extern void  *dragonstone_runtime_interpolated_string(int64_t count, void **parts);",
                "extern void  *dragonstone_runtime_typeof(void *v);",
                "extern void  *dragonstone_runtime_add(void *l, void *r);",
                "extern void  *dragonstone_runtime_sub(void *l, void *r);",
                "extern void  *dragonstone_runtime_mul(void *l, void *r);",
                "extern void  *dragonstone_runtime_div(void *l, void *r);",
                "extern void  *dragonstone_runtime_mod(void *l, void *r);",
                "extern void  *dragonstone_runtime_negate(void *v);",
                "extern void  *dragonstone_runtime_shl(void *l, void *r);",
                "extern void  *dragonstone_runtime_shr(void *l, void *r);",
                "extern void  *dragonstone_runtime_bit_and(void *l, void *r);",
                "extern void  *dragonstone_runtime_bit_or(void *l, void *r);",
                "extern void  *dragonstone_runtime_bit_xor(void *l, void *r);",
                "extern void  *dragonstone_runtime_pow(void *l, void *r);",
                "extern void  *dragonstone_runtime_floor_div(void *l, void *r);",
                "extern void  *dragonstone_runtime_cmp(void *l, void *r);",
                "extern void  *dragonstone_runtime_gt(void *l, void *r);",
                "extern void  *dragonstone_runtime_lt(void *l, void *r);",
                "extern void  *dragonstone_runtime_gte(void *l, void *r);",
                "extern void  *dragonstone_runtime_lte(void *l, void *r);",
                "extern void  *dragonstone_runtime_eq(void *l, void *r);",
                "extern void  *dragonstone_runtime_ne(void *l, void *r);",
                "extern _Bool  dragonstone_runtime_is_truthy(void *v);",
                "extern _Bool  dragonstone_runtime_case_compare(void *l, void *r);",
                "extern void  *dragonstone_runtime_range_literal(void *from, void *to, _Bool exclusive);",
                "extern void  *dragonstone_runtime_bag_constructor(void *elem_type);",
                "extern void  *dragonstone_runtime_root_self(void);",
                "extern void   dragonstone_runtime_set_argv(int64_t argc, char **argv);",
                "extern void  *dragonstone_runtime_argv(void);",
                "extern void  *dragonstone_runtime_argc(void);",
                "extern void  *dragonstone_runtime_stdout(void);",
                "extern void  *dragonstone_runtime_stderr(void);",
                "extern void  *dragonstone_runtime_stdin(void);",
                "extern void  *dragonstone_runtime_argf(void);",
                "extern void   dragonstone_io_quit(int64_t status);",
                "extern void   dragonstone_io_abort(void *message);",
                "extern void   dragonstone_runtime_push_exception_frame(void *frame);",
                "extern void   dragonstone_runtime_pop_exception_frame(void);",
                "extern void  *dragonstone_runtime_get_exception(void);",
                "extern void   dragonstone_runtime_raise(void *message);",
                "extern void   dragonstone_runtime_rescue_placeholder(void);",
                "extern void   dragonstone_runtime_yield_missing_block(void);",
                "extern void   dragonstone_runtime_debug_accum(void *label, void *val);",
                "extern void   dragonstone_runtime_debug_flush(void);",
              ].each { |line| io << line << "\n" }
              io << "\n"
            end

            private def emit_string_constants(io : IO)
              return if @string_order.empty?
              io << "/* --- string constants --- */\n"
              @string_order.each do |literal|
                entry = @string_literals[literal]
                io << "static const char #{entry[:name]}[] = #{c_string_literal(literal)};\n"
              end
              io << "\n"
            end

            private def emit_globals(io : IO)
              return if @globals.empty?
              io << "/* --- globals --- */\n"
              @globals.each do |name|
                io << "static void *#{mangle_global_name(name)} = NULL;\n"
              end
              io << "\n"
            end

            private def emit_forward_decls(io : IO)
              return if @function_defs.empty?
              io << "/* --- forward declarations --- */\n"
              @function_defs.each do |c_name, func|
                params = build_param_list(func, c_name)
                io << "static void *#{c_name}(#{params});\n"
              end
              io << "\n"
            end

            private def emit_functions(io : IO)
              @function_defs.values.each do |func|
                c_name = @function_names[func]
                next if @emitted_functions.includes?(c_name)
                emit_function(io, func)
                io << "\n"
              end
            end

            private def emit_function(io : IO, func : AST::FunctionDef)
              c_name = @function_names[func]
              return if @emitted_functions.includes?(c_name)
              @emitted_functions << c_name

              @namespace_stack = @function_namespaces[func].dup

              body_io = String::Builder.new
              ctx = FunctionContext.new(body_io)
              ctx.callable_name = func.name
              ctx.parameter_names = func.typed_parameters.map(&.name)

              requires_block = @function_requires_block[c_name]? || false

              if @function_receivers[func]?
                ctx.declare_local("self")
                body_io << "    void *self = _self;\n"
                if func.name == "initialize"
                  func.typed_parameters.each_with_index do |param, i|
                    pname = safe_c_name(param.name)
                    ctx.declare_local(pname)
                    body_io << "    void *#{pname} = _arg#{i};\n"
                    ivar_name = param.name.starts_with?("@") ? param.name : "@#{param.name}"
                    name_ref = string_ref(ivar_name)
                    body_io << "    dragonstone_runtime_ivar_set(self, (void*)#{name_ref}, #{pname});\n"
                  end
                else
                  func.typed_parameters.each_with_index do |param, i|
                    pname = safe_c_name(param.name)
                    ctx.declare_local(pname)
                    body_io << "    void *#{pname} = _arg#{i};\n"
                  end
                end
              else
                func.typed_parameters.each_with_index do |param, i|
                  pname = safe_c_name(param.name)
                  ctx.declare_local(pname)
                  body_io << "    void *#{pname} = _arg#{i};\n"
                end
              end

              if requires_block
                ctx.block_param = "_block_arg"
                ctx.declare_local("__block")
                body_io << "    void *__block = _block_arg;\n"
              end

              pre_declare_locals(ctx, func.body)

              terminated = generate_block_with_implicit_return(ctx, func.body)
              unless terminated
                body_io << "    return NULL;\n"
              end

              params = build_param_list(func, c_name)
              io << "static void *#{c_name}(#{params}) {\n"
              io << body_io.to_s
              io << "}\n"
            end

            private def emit_entrypoint(io : IO)
              body_io = String::Builder.new
              ctx = FunctionContext.new(body_io)

              @namespace_stack.clear

              top_level = @program.ast.statements.reject do |stmt|
                stmt.is_a?(AST::FunctionDef) && stmt.as(AST::FunctionDef).receiver.nil?
              end

              body_io << "    dragonstone_runtime_set_argv((int64_t)argc, argv);\n"

              pre_declare_locals(ctx, top_level)
              generate_block(ctx, top_level)

              body_io << "    dragonstone_runtime_debug_flush();\n"
              body_io << "    return 0;\n"

              io << "int main(int argc, char **argv) {\n"
              io << body_io.to_s
              io << "}\n"
            end

            private def generate_block(ctx : FunctionContext, stmts : Array(AST::Node)) : Bool
              terminated = false
              stmts.each do |stmt|
                terminated = generate_statement(ctx, stmt)
                break if terminated
              end
              terminated
            end

            private def generate_block_with_implicit_return(ctx : FunctionContext, stmts : Array(AST::Node)) : Bool
              terminated = false
              stmts.each_with_index do |stmt, idx|
                is_last = idx == stmts.size - 1
                if is_last && !terminated && expression_statement?(stmt)
                  ref = emit_expr(ctx, stmt)
                  emit_ensure_chain(ctx)
                  ctx.io << "    return #{ref};\n"
                  return true
                end
                terminated = generate_statement(ctx, stmt)
                break if terminated
              end
              terminated
            end

            private def expression_statement?(stmt : AST::Node) : Bool
              case stmt
              when AST::Literal, AST::Variable, AST::BinaryOp, AST::UnaryOp,
                   AST::MethodCall, AST::SuperCall,
                   AST::ArrayLiteral, AST::BagConstructor, AST::MapLiteral,
                   AST::TupleLiteral, AST::NamedTupleLiteral, AST::ConstantPath,
                   AST::InterpolatedString, AST::BeginExpression,
                   AST::InstanceVariable, AST::InstanceVariableAssignment,
                   AST::IfStatement, AST::UnlessStatement, AST::CaseStatement,
                   AST::ConditionalExpression,
                   AST::Assignment, AST::AttributeAssignment, AST::IndexAssignment,
                   AST::YieldExpression, AST::DebugEcho,
                   AST::ArgvExpression, AST::ArgcExpression, AST::ArgfExpression,
                   AST::StdoutExpression, AST::StderrExpression, AST::StdinExpression
                true
              else
                false
              end
            end

            private def generate_statement(ctx : FunctionContext, stmt : AST::Node) : Bool
              case stmt
              when AST::FunctionDef
                emit_function_inline(stmt)
                if recv = stmt.receiver
                  c_name = @function_names[stmt]?
                  if c_name
                    recv_ref = emit_expr(ctx, recv)
                    meth_name_ref = string_ref(stmt.name)
                    ctx.io << "    dragonstone_runtime_define_singleton_method(#{recv_ref}, (void*)#{meth_name_ref}, (void*)#{c_name});\n"
                  end
                end
                false
              when AST::ClassDefinition
                emit_class_definition(ctx, stmt)
                false
              when AST::ModuleDefinition
                emit_module_definition(ctx, stmt)
                false
              when AST::StructDefinition
                emit_struct_definition(ctx, stmt)
                false
              when AST::EnumDefinition
                emit_enum_definition(ctx, stmt)
                false
              when AST::Assignment
                emit_assignment_stmt(ctx, stmt)
                false
              when AST::ConstantDeclaration
                emit_constant_declaration(ctx, stmt)
                false
              when AST::InstanceVariableDeclaration
                false
              when AST::InstanceVariableAssignment
                emit_ivar_assignment(ctx, stmt)
                false
              when AST::AttributeAssignment
                emit_attr_assignment(ctx, stmt)
                false
              when AST::IndexAssignment
                emit_index_assignment(ctx, stmt)
                false
              when AST::ReturnStatement
                emit_return(ctx, stmt)
                true
              when AST::BreakStatement
                emit_break(ctx, stmt)
                true
              when AST::NextStatement
                emit_next(ctx, stmt)
                true
              when AST::RedoStatement
                emit_redo(ctx)
                false
              when AST::RetryStatement
                emit_retry(ctx)
                false
              when AST::QuitStatement
                emit_quit(ctx, stmt)
                true
              when AST::AbortStatement
                emit_abort(ctx, stmt)
                true
              when AST::RaiseExpression
                emit_raise(ctx, stmt)
                true
              when AST::IfStatement
                emit_if(ctx, stmt)
                false
              when AST::UnlessStatement
                emit_unless(ctx, stmt)
                false
              when AST::WhileStatement
                emit_while(ctx, stmt)
                false
              when AST::CaseStatement
                emit_case(ctx, stmt)
                false
              when AST::BeginExpression
                emit_begin(ctx, stmt)
                false
              when AST::DebugEcho
                emit_debug_echo(ctx, stmt)
                false
              when AST::AliasDefinition
                false
              when AST::AccessorMacro
                false
              when AST::UseDecl
                false
              when AST::WithExpression
                emit_expr(ctx, stmt)
                false
              else
                emit_expr(ctx, stmt)
                false
              end
            end

            private def emit_expr(ctx : FunctionContext, node : AST::Node) : String
              case node
              when AST::Literal
                emit_literal(ctx, node)
              when AST::Variable
                emit_variable_ref(ctx, node)
              when AST::ConstantPath
                emit_constant_path(ctx, node)
              when AST::Assignment
                emit_assignment_expr(ctx, node)
              when AST::ConstantDeclaration
                emit_constant_declaration(ctx, node)
                "NULL"
              when AST::BinaryOp
                emit_binary_op(ctx, node)
              when AST::UnaryOp
                emit_unary_op(ctx, node)
              when AST::MethodCall
                emit_method_call(ctx, node)
              when AST::SuperCall
                emit_super_call(ctx, node)
              when AST::IfStatement
                emit_if_expr(ctx, node)
              when AST::UnlessStatement
                emit_unless_expr(ctx, node)
              when AST::CaseStatement
                emit_case_expr(ctx, node)
              when AST::ConditionalExpression
                emit_conditional_expr(ctx, node)
              when AST::WhileStatement
                emit_while(ctx, node)
                "NULL"
              when AST::BeginExpression
                emit_begin(ctx, node)
                "NULL"
              when AST::RaiseExpression
                emit_raise(ctx, node)
                "NULL"
              when AST::ReturnStatement
                emit_return(ctx, node)
                "NULL"
              when AST::BreakStatement
                emit_break(ctx, node)
                "NULL"
              when AST::NextStatement
                emit_next(ctx, node)
                "NULL"
              when AST::YieldExpression
                emit_yield(ctx, node)
              when AST::InterpolatedString
                emit_interpolated_string(ctx, node)
              when AST::ArrayLiteral
                emit_array_literal(ctx, node)
              when AST::MapLiteral
                emit_map_literal(ctx, node)
              when AST::TupleLiteral
                emit_tuple_literal(ctx, node)
              when AST::NamedTupleLiteral
                emit_named_tuple_literal(ctx, node)
              when AST::IndexAccess
                emit_index_access(ctx, node)
              when AST::IndexAssignment
                emit_index_assignment_expr(ctx, node)
              when AST::AttributeAssignment
                emit_attr_assignment_expr(ctx, node)
              when AST::InstanceVariable
                emit_ivar_get(ctx, node)
              when AST::InstanceVariableAssignment
                emit_ivar_assign_expr(ctx, node)
              when AST::InstanceVariableDeclaration
                "NULL"
              when AST::BagConstructor
                emit_bag_constructor(ctx, node)
              when AST::BlockLiteral
                emit_block_literal(ctx, node)
              when AST::ParaLiteral
                emit_para_literal(ctx, node)
              when AST::FunctionLiteral
                emit_function_literal(ctx, node)
              when AST::WithExpression
                emit_with_expr(ctx, node)
              when AST::DebugEcho
                emit_debug_echo(ctx, node)
                "NULL"
              when AST::ArgvExpression
                "dragonstone_runtime_argv()"
              when AST::ArgcExpression
                "dragonstone_runtime_argc()"
              when AST::ArgfExpression
                "dragonstone_runtime_argf()"
              when AST::StdoutExpression
                "dragonstone_runtime_stdout()"
              when AST::StderrExpression
                "dragonstone_runtime_stderr()"
              when AST::StdinExpression
                "dragonstone_runtime_stdin()"
              when AST::ClassVariable
                emit_class_var(ctx, node)
              when AST::ModuleVariable
                emit_module_var(ctx, node)
              when AST::FunctionDef
                emit_function_inline(node)
                func_ref = @function_names[node]?
                func_ref ? "(void*)#{func_ref}" : "NULL"
              else
                "NULL"
              end
            end

            private def emit_literal(ctx : FunctionContext, node : AST::Literal) : String
              val = node.value
              case val
              when nil
                "NULL"
              when Bool
                t = ctx.fresh
                ctx.io << "    void *#{t} = dragonstone_runtime_box_bool(#{val ? 1 : 0});\n"
                t
              when Int32, Int64
                t = ctx.fresh
                ctx.io << "    void *#{t} = dragonstone_runtime_box_i64((int64_t)#{val}LL);\n"
                t
              when Float64
                t = ctx.fresh
                ctx.io << "    void *#{t} = dragonstone_runtime_box_float(#{val});\n"
                t
              when String
                "(void*)#{string_ref(val)}"
              when Char
                t = ctx.fresh
                ctx.io << "    void *#{t} = dragonstone_runtime_box_i64((int64_t)#{val.ord}LL);\n"
                t
              when SymbolValue
                "(void*)#{string_ref(val.name)}"
              else
                "NULL"
              end
            end

            private def emit_variable_ref(ctx : FunctionContext, node : AST::Variable) : String
              name = node.name
              if name == "ffi"
                return "(void*)#{string_ref("ffi")}"
              end
              if name == "self"
                return ctx.has_local?("self") ? "self" : "dragonstone_runtime_root_self()"
              end

              full_name = qualify_name(name)
              if @globals.includes?(full_name)
                return mangle_global_name(full_name)
              end

              unless ctx.with_stack.empty?
                recv = ctx.with_stack.last
                t = ctx.fresh
                name_ref = string_ref(name)
                ctx.io << "    void *#{t} = dragonstone_runtime_method_invoke(#{recv}, (void*)#{name_ref}, 0, NULL, NULL);\n"
                return t
              end

              cname = safe_c_name(name)
              return cname if ctx.has_local?(cname)

              if const_path = resolve_constant_path(name)
                return emit_constant_path_by_name(ctx, const_path)
              end

              if owner_ns = resolve_class_scope_binding_owner(name)
                owner_ref = emit_constant_path_by_name(ctx, owner_ns.split("::"))
                t = ctx.fresh
                name_ref = string_ref(name)
                ctx.io << "    void *#{t} = dragonstone_runtime_ivar_get(#{owner_ref}, (void*)#{name_ref});\n"
                return t
              end

              recv = ctx.has_local?("self") ? "self" : "dragonstone_runtime_root_self()"
              name_ref = string_ref(name)
              if ctx.has_local?("self")
                t_ivar = ctx.fresh
                t = ctx.fresh
                ctx.io << "    void *#{t_ivar} = dragonstone_runtime_ivar_get(#{recv}, (void*)#{name_ref});\n"
                ctx.io << "    void *#{t} = #{t_ivar} ? #{t_ivar} : dragonstone_runtime_method_invoke(#{recv}, (void*)#{name_ref}, 0, NULL, NULL);\n"
                t
              else
                t = ctx.fresh
                ctx.io << "    void *#{t} = dragonstone_runtime_method_invoke(#{recv}, (void*)#{name_ref}, 0, NULL, NULL);\n"
                t
              end
            end

            private def emit_constant_path(ctx : FunctionContext, node : AST::ConstantPath) : String
              emit_constant_path_by_name(ctx, node.names)
            end

            private def emit_constant_path_by_name(ctx : FunctionContext, names : Array(String)) : String
              t_segs = ctx.fresh("_csegs")
              t = ctx.fresh
              seg_inits = names.map { |n| "(void*)#{string_ref(n)}" }.join(", ")
              ctx.io << "    void *#{t_segs}[] = {#{seg_inits}};\n"
              ctx.io << "    void *#{t} = dragonstone_runtime_constant_lookup(#{names.size}, #{t_segs});\n"
              t
            end

            private def emit_assignment_stmt(ctx : FunctionContext, node : AST::Assignment)
              emit_assignment_expr(ctx, node)
            end

            private def emit_assignment_expr(ctx : FunctionContext, node : AST::Assignment) : String
              rhs = emit_expr(ctx, node.value)
              var_name = safe_c_name(node.name)

              if op = node.operator
                current = safe_c_name(node.name)
                rhs = emit_runtime_binop(ctx, op.to_s, current, rhs)
              end

              full_name = qualify_name(node.name)
              if @globals.includes?(full_name)
                global = mangle_global_name(full_name)
                ctx.io << "    #{global} = #{rhs};\n"
                return global
              end

              if ctx.declare_local(var_name)
                ctx.io << "    void *#{var_name} = #{rhs};\n"
              else
                ctx.io << "    #{var_name} = #{rhs};\n"
              end
              var_name
            end

            private def emit_constant_declaration(ctx : FunctionContext, node : AST::ConstantDeclaration)
              val = emit_expr(ctx, node.value)
              name_ref = string_ref(qualify_name(node.name))
              ctx.io << "    dragonstone_runtime_define_constant((void*)#{name_ref}, #{val});\n"
            end

            private def emit_binary_op(ctx : FunctionContext, node : AST::BinaryOp) : String
              left = emit_expr(ctx, node.left)
              right = emit_expr(ctx, node.right)
              emit_runtime_binop(ctx, node.operator.to_s, left, right)
            end

            private def emit_runtime_binop(ctx : FunctionContext, op : String, left : String, right : String) : String
              fn = case op
                   when "+"   then "dragonstone_runtime_add"
                   when "&+"  then "dragonstone_runtime_add"
                   when "-"   then "dragonstone_runtime_sub"
                   when "&-"  then "dragonstone_runtime_sub"
                   when "*"   then "dragonstone_runtime_mul"
                   when "/"   then "dragonstone_runtime_div"
                   when "%"   then "dragonstone_runtime_mod"
                   when "**"  then "dragonstone_runtime_pow"
                   when "//"  then "dragonstone_runtime_floor_div"
                   when "<<"  then "dragonstone_runtime_shl"
                   when ">>"  then "dragonstone_runtime_shr"
                   when "&"   then "dragonstone_runtime_bit_and"
                   when "|"   then "dragonstone_runtime_bit_or"
                   when "^"   then "dragonstone_runtime_bit_xor"
                   when ">"   then "dragonstone_runtime_gt"
                   when "<"   then "dragonstone_runtime_lt"
                   when ">="  then "dragonstone_runtime_gte"
                   when "<="  then "dragonstone_runtime_lte"
                   when "=="  then "dragonstone_runtime_eq"
                   when "!="  then "dragonstone_runtime_ne"
                   when "<=>" then "dragonstone_runtime_cmp"
                   when ".."
                     t = ctx.fresh
                     ctx.io << "    void *#{t} = dragonstone_runtime_range_literal(#{left}, #{right}, (_Bool)0);\n"
                     return t
                   when "..."
                     t = ctx.fresh
                     ctx.io << "    void *#{t} = dragonstone_runtime_range_literal(#{left}, #{right}, (_Bool)1);\n"
                     return t
                   when "&&", "and"
                     t = ctx.fresh
                     ctx.io << "    void *#{t} = dragonstone_runtime_is_truthy(#{left}) ? #{right} : #{left};\n"
                     return t
                   when "||", "or"
                     t = ctx.fresh
                     ctx.io << "    void *#{t} = dragonstone_runtime_is_truthy(#{left}) ? #{left} : #{right};\n"
                     return t
                   else
                     "dragonstone_runtime_method_invoke"
                   end

              if fn == "dragonstone_runtime_method_invoke"
                op_ref = string_ref(op)
                t2 = ctx.fresh
                ctx.io << "    void *#{t2};\n"
                ctx.io << "    { void *_rarg[] = {#{right}}; #{t2} = dragonstone_runtime_method_invoke(#{left}, (void*)#{op_ref}, 1, _rarg, NULL); }\n"
                return t2
              end

              t = ctx.fresh
              ctx.io << "    void *#{t} = #{fn}(#{left}, #{right});\n"
              t
            end

            private def emit_unary_op(ctx : FunctionContext, node : AST::UnaryOp) : String
              operand = emit_expr(ctx, node.operand)
              t = ctx.fresh
              case node.operator.to_s
              when "-"
                ctx.io << "    void *#{t} = dragonstone_runtime_negate(#{operand});\n"
              when "!", "not"
                ctx.io << "    void *#{t} = dragonstone_runtime_box_bool(!dragonstone_runtime_is_truthy(#{operand}));\n"
              when "~"
                name_ref = string_ref("~")
                ctx.io << "    void *#{t};\n"
                ctx.io << "    { void *_ra[] = {}; #{t} = dragonstone_runtime_method_invoke(#{operand}, (void*)#{name_ref}, 0, NULL, NULL); }\n"
              else
                ctx.io << "    void *#{t} = #{operand};\n"
              end
              t
            end

            private def emit_method_call(ctx : FunctionContext, node : AST::MethodCall) : String
              name = node.name
              receiver = node.receiver
              block = node.arguments.last?.try { |a| (a.is_a?(AST::BlockLiteral) || a.is_a?(AST::ParaLiteral)) ? a : nil }
              block_stripped_args = block ? node.arguments[0..-2] : node.arguments
              args = node.arguments

              if receiver.nil? || (receiver.is_a?(AST::Variable) && receiver.as(AST::Variable).name == "self")
                case name
                when "echo", "puts"
                  val = block_stripped_args.empty? ? "NULL" : emit_expr(ctx, block_stripped_args[0])
                  t = ctx.fresh
                  ctx.io << "    void *#{t} = dragonstone_runtime_value_display(#{val});\n"
                  ctx.io << "    puts((char *)#{t});\n"
                  return "NULL"
                when "eecho", "print"
                  val = block_stripped_args.empty? ? "NULL" : emit_expr(ctx, block_stripped_args[0])
                  t = ctx.fresh
                  ctx.io << "    void *#{t} = dragonstone_runtime_value_display(#{val});\n"
                  ctx.io << "    fputs((char *)#{t}, stdout);\n"
                  return "NULL"
                when "typeof"
                  val = block_stripped_args.empty? ? "NULL" : emit_expr(ctx, block_stripped_args[0])
                  t = ctx.fresh
                  ctx.io << "    void *#{t} = dragonstone_runtime_typeof(#{val});\n"
                  return t
                end
              end

              if recv = receiver
                case name
                when "echo", "puts", "write", "print", "<<", "flush"
                  recv_ref = emit_expr(ctx, recv)
                  val = block_stripped_args.empty? ? "NULL" : emit_expr(ctx, block_stripped_args[0])
                  return emit_stream_write(ctx, recv_ref, val, name)
                end
              end

              if receiver.nil?
                if block
                  if c_name = resolve_direct_call(name, block_stripped_args.size, true)
                    return emit_direct_call(ctx, c_name, nil, block_stripped_args, block)
                  end
                  if c_name = resolve_direct_call(name, args.size, false)
                    return emit_direct_call(ctx, c_name, nil, args, nil)
                  end
                else
                  if c_name = resolve_direct_call(name, args.size, false)
                    return emit_direct_call(ctx, c_name, nil, args, nil)
                  end
                end
              end

              recv_ref = if r = receiver
                           emit_expr(ctx, r)
                         else
                           "dragonstone_runtime_root_self()"
                         end

              emit_dynamic_call(ctx, recv_ref, name, block_stripped_args, block)
            end

            private def emit_stream_write(ctx : FunctionContext, recv_ref : String, val : String, name : String) : String
              t = ctx.fresh
              name_ref = string_ref(name)
              ctx.io << "    void *#{t};\n"
              ctx.io << "    { void *_sa[] = {#{val}}; #{t} = dragonstone_runtime_method_invoke(#{recv_ref}, (void*)#{name_ref}, 1, _sa, NULL); }\n"
              t
            end

            private def emit_direct_call(ctx : FunctionContext, c_name : String, recv_ref : String?, args : Array(AST::Node), block : AST::Node?) : String
              func = @function_defs[c_name]?
              has_receiver = func ? (@function_receivers[func]? || false) : false
              requires_block = @function_requires_block[c_name]? || false

              arg_refs = args.map { |a| emit_expr(ctx, a) }
              block_ref = block ? emit_block_node(ctx, block) : (requires_block ? "NULL" : nil)

              parts = [] of String
              parts << (recv_ref || "dragonstone_runtime_root_self()") if has_receiver
              parts.concat(arg_refs)
              parts << block_ref if block_ref && requires_block

              t = ctx.fresh
              ctx.io << "    void *#{t} = #{c_name}(#{parts.join(", ")});\n"
              t
            end

            private def emit_dynamic_call(ctx : FunctionContext, recv_ref : String, name : String, args : Array(AST::Node), block : AST::Node?) : String
              arg_refs = args.map { |a| emit_expr(ctx, a) }
              block_ref = block ? emit_block_node(ctx, block) : "NULL"
              name_ref = string_ref(name)
              t = ctx.fresh

              if arg_refs.empty?
                ctx.io << "    void *#{t} = dragonstone_runtime_method_invoke(#{recv_ref}, (void*)#{name_ref}, 0, NULL, #{block_ref});\n"
              else
                arr = ctx.fresh("_margs")
                ctx.io << "    void *#{arr}[] = {#{arg_refs.join(", ")}};\n"
                ctx.io << "    void *#{t} = dragonstone_runtime_method_invoke(#{recv_ref}, (void*)#{name_ref}, #{arg_refs.size}, #{arr}, #{block_ref});\n"
              end
              t
            end

            private def emit_super_call(ctx : FunctionContext, node : AST::SuperCall) : String
              block_node = node.arguments.last?.try { |a| (a.is_a?(AST::BlockLiteral) || a.is_a?(AST::ParaLiteral)) ? a : nil }
              real_args = block_node ? node.arguments[0..-2] : node.arguments
              arg_refs = real_args.map { |a| emit_expr(ctx, a) }
              block_ref = block_node ? emit_block_node(ctx, block_node) : "NULL"

              owner_ref = if @namespace_stack.empty?
                            emit_constant_path_by_name(ctx, ["Object"])
                          else
                            emit_constant_path_by_name(ctx, @namespace_stack)
                          end
              meth_ref = string_ref(ctx.callable_name || "initialize")

              t = ctx.fresh
              if arg_refs.empty?
                ctx.io << "    void *#{t} = dragonstone_runtime_super_invoke(self, #{owner_ref}, (void*)#{meth_ref}, 0, NULL, #{block_ref});\n"
              else
                arr = ctx.fresh("_sargs")
                ctx.io << "    void *#{arr}[] = {#{arg_refs.join(", ")}};\n"
                ctx.io << "    void *#{t} = dragonstone_runtime_super_invoke(self, #{owner_ref}, (void*)#{meth_ref}, #{arg_refs.size}, #{arr}, #{block_ref});\n"
              end
              t
            end

            private def emit_yield(ctx : FunctionContext, node : AST::YieldExpression) : String
              block_ref = ctx.block_param || "NULL"
              arg_refs = node.arguments.map { |a| emit_expr(ctx, a) }
              t = ctx.fresh

              if arg_refs.empty?
                ctx.io << "    void *#{t} = #{block_ref} ? dragonstone_runtime_block_invoke(#{block_ref}, 0, NULL) : NULL;\n"
              else
                arr = ctx.fresh("_yargs")
                ctx.io << "    void *#{arr}[] = {#{arg_refs.join(", ")}};\n"
                ctx.io << "    void *#{t} = #{block_ref} ? dragonstone_runtime_block_invoke(#{block_ref}, #{arg_refs.size}, #{arr}) : NULL;\n"
              end
              t
            end

            private def emit_block_node(ctx : FunctionContext, block : AST::Node) : String
              case block
              when AST::BlockLiteral    then emit_block_literal(ctx, block)
              when AST::ParaLiteral     then emit_para_literal(ctx, block)
              when AST::FunctionLiteral then emit_function_literal(ctx, block)
              when AST::Variable
                safe_c_name(block.name)
              else
                "NULL"
              end
            end

            private def emit_block_literal(ctx : FunctionContext, node : AST::BlockLiteral) : String
              lift_closure(ctx, node.typed_parameters.map(&.name), node.body)
            end

            private def emit_para_literal(ctx : FunctionContext, node : AST::ParaLiteral) : String
              lift_closure(ctx, node.parameters, node.body)
            end

            private def emit_function_literal(ctx : FunctionContext, node : AST::FunctionLiteral) : String
              lift_closure(ctx, node.typed_parameters.map(&.name), node.body)
            end

            private def lift_closure(ctx : FunctionContext, params : Array(String), body : Array(AST::Node)) : String
              captures = scan_captures(ctx, body).reject { |cap| params.includes?(cap) }

              block_id = @block_counter
              @block_counter += 1
              func_name = "_ds_block_#{block_id}"
              env_var = "_ds_env"
              argc_var = "_ds_argc"
              argv_var = "_ds_argv"

              blk_io = String::Builder.new
              blk_io << "static void *#{func_name}(void *#{env_var}_raw, int64_t #{argc_var}, void **#{argv_var}) {\n"
              blk_io << "    void **#{env_var} = (void**)#{env_var}_raw;\n"

              inner_ctx = FunctionContext.new(blk_io)
              inner_ctx.block_param = nil

              captures.each_with_index do |cap, i|
                cname = safe_c_name(cap)
                inner_ctx.declare_local(cname)
                blk_io << "    void *#{cname} = #{env_var} ? #{env_var}[#{i}] : NULL;\n"
              end

              params.each_with_index do |pname, i|
                cname = safe_c_name(pname)
                inner_ctx.declare_local(cname)
                blk_io << "    void *#{cname} = #{argc_var} > #{i} ? #{argv_var}[#{i}] : NULL;\n"
              end

              pre_declare_locals(inner_ctx, body)
              terminated = generate_block_with_implicit_return(inner_ctx, body)
              blk_io << "    return NULL;\n" unless terminated

              blk_io << "}\n"
              @pending_blocks << blk_io.to_s

              t = ctx.fresh("_blk")
              if captures.empty?
                ctx.io << "    void *#{t} = dragonstone_runtime_block_literal(#{func_name}, NULL);\n"
              else
                env = ctx.fresh("_env")
                ctx.io << "    void **#{env} = dragonstone_runtime_block_env_allocate(#{captures.size});\n"
                captures.each_with_index do |cap, i|
                  ctx.io << "    #{env}[#{i}] = #{safe_c_name(cap)};\n"
                end
                ctx.io << "    void *#{t} = dragonstone_runtime_block_literal(#{func_name}, (void*)#{env});\n"
              end
              t
            end

            private def scan_captures(ctx : FunctionContext, body : Array(AST::Node)) : Array(String)
              used = Set(String).new
              local_bindings = Set(String).new
              scan_capture_nodes(body, local_bindings, used)
              used.select { |n| ctx.has_local?(safe_c_name(n)) }.to_a
            end

            private def scan_capture_nodes(stmts : Array(AST::Node), bound : Set(String), used : Set(String))
              stmts.each { |s| scan_capture_node(s, bound, used) }
            end

            private def scan_capture_node(node : AST::Node, bound : Set(String), used : Set(String))
              case node
              when AST::Variable
                used << node.name unless bound.includes?(node.name) || constant_symbol?(node.name)
              when AST::Assignment
                scan_capture_node(node.value, bound, used)
                bound << node.name
              when AST::InstanceVariableAssignment
                scan_capture_node(node.value, bound, used)
              when AST::FunctionDef, AST::ClassDefinition, AST::ModuleDefinition,
                   AST::StructDefinition, AST::BlockLiteral, AST::ParaLiteral, AST::FunctionLiteral
              when AST::MethodCall
                node.receiver.try { |r| scan_capture_node(r, bound, used) }
                node.arguments.each { |a| scan_capture_node(a, bound, used) }
              when AST::BinaryOp
                scan_capture_node(node.left, bound, used)
                scan_capture_node(node.right, bound, used)
              when AST::UnaryOp
                scan_capture_node(node.operand, bound, used)
              when AST::ConditionalExpression
                scan_capture_node(node.condition, bound, used)
                scan_capture_node(node.then_branch, bound, used)
                scan_capture_node(node.else_branch, bound, used)
              when AST::ReturnStatement
                node.value.try { |v| scan_capture_node(v, bound, used) }
              when AST::IfStatement
                scan_capture_node(node.condition, bound, used)
                scan_capture_nodes(node.then_block, bound, used)
                node.elsif_blocks.each { |c| scan_capture_node(c.condition, bound, used); scan_capture_nodes(c.block, bound, used) }
                node.else_block.try { |b| scan_capture_nodes(b, bound, used) }
              when AST::WhileStatement
                scan_capture_node(node.condition, bound, used)
                scan_capture_nodes(node.block, bound, used)
              when AST::UnlessStatement
                scan_capture_node(node.condition, bound, used)
                scan_capture_nodes(node.body, bound, used)
                node.else_block.try { |b| scan_capture_nodes(b, bound, used) }
              when AST::CaseStatement
                node.expression.try { |e| scan_capture_node(e, bound, used) }
                node.when_clauses.each do |clause|
                  clause.conditions.each { |cond| scan_capture_node(cond, bound, used) }
                  scan_capture_nodes(clause.block, bound, used)
                end
                node.else_block.try { |b| scan_capture_nodes(b, bound, used) }
              when AST::BeginExpression
                scan_capture_nodes(node.body, bound, used)
                node.rescue_clauses.each do |clause|
                  clause.exception_variable.try { |v| bound << v }
                  scan_capture_nodes(clause.body, bound, used)
                end
                node.else_block.try { |b| scan_capture_nodes(b, bound, used) }
                node.ensure_block.try { |b| scan_capture_nodes(b, bound, used) }
              when AST::ArrayLiteral
                node.elements.each { |e| scan_capture_node(e, bound, used) }
              when AST::MapLiteral
                node.entries.each { |(k, v)| scan_capture_node(k, bound, used); scan_capture_node(v, bound, used) }
              when AST::TupleLiteral
                node.elements.each { |e| scan_capture_node(e, bound, used) }
              when AST::NamedTupleLiteral
                node.entries.each { |entry| scan_capture_node(entry.value, bound, used) }
              when AST::InterpolatedString
                node.normalized_parts.each do |type, content|
                  next unless type == :expression
                  expr_node = content.is_a?(AST::Node) ? content.as(AST::Node) : parse_interpolation(content.to_s)
                  scan_capture_node(expr_node, bound, used)
                end
              else
                # Continue.
              end
            end

            private def emit_if(ctx : FunctionContext, node : AST::IfStatement)
              done_lbl = ctx.fresh_label("_ifDone")

              cond = emit_expr(ctx, node.condition)
              ctx.io << "    if (dragonstone_runtime_is_truthy(#{cond})) {\n"
              generate_block(ctx, node.then_block)
              ctx.io << "    goto #{done_lbl};\n"
              ctx.io << "    }\n"

              node.elsif_blocks.each do |clause|
                elsif_cond = emit_expr(ctx, clause.condition)
                ctx.io << "    if (dragonstone_runtime_is_truthy(#{elsif_cond})) {\n"
                generate_block(ctx, clause.block)
                ctx.io << "    goto #{done_lbl};\n"
                ctx.io << "    }\n"
              end

              if eb = node.else_block
                generate_block(ctx, eb)
              end

              ctx.io << "    #{done_lbl}:;\n"
            end

            private def emit_if_expr(ctx : FunctionContext, node : AST::IfStatement) : String
              result = ctx.fresh("_ifr")
              done_lbl = ctx.fresh_label("_ifExprDone")
              ctx.io << "    void *#{result} = NULL;\n"

              cond = emit_expr(ctx, node.condition)
              ctx.io << "    if (dragonstone_runtime_is_truthy(#{cond})) {\n"
              if !node.then_block.empty?
                last = emit_block_result(ctx, node.then_block)
                ctx.io << "    #{result} = #{last};\n"
              end
              ctx.io << "    goto #{done_lbl};\n"
              ctx.io << "    }\n"

              node.elsif_blocks.each do |clause|
                elsif_cond = emit_expr(ctx, clause.condition)
                ctx.io << "    if (dragonstone_runtime_is_truthy(#{elsif_cond})) {\n"
                unless clause.block.empty?
                  last = emit_block_result(ctx, clause.block)
                  ctx.io << "    #{result} = #{last};\n"
                end
                ctx.io << "    goto #{done_lbl};\n"
                ctx.io << "    }\n"
              end

              if eb = node.else_block
                unless eb.empty?
                  last = emit_block_result(ctx, eb)
                  ctx.io << "    #{result} = #{last};\n"
                end
              end
              ctx.io << "    #{done_lbl}:;\n"
              result
            end

            private def emit_unless(ctx : FunctionContext, node : AST::UnlessStatement)
              cond = emit_expr(ctx, node.condition)
              ctx.io << "    if (!dragonstone_runtime_is_truthy(#{cond})) {\n"
              generate_block(ctx, node.body)
              if eb = node.else_block
                ctx.io << "    } else {\n"
                generate_block(ctx, eb)
              end
              ctx.io << "    }\n"
            end

            private def emit_unless_expr(ctx : FunctionContext, node : AST::UnlessStatement) : String
              result = ctx.fresh("_unlessR")
              ctx.io << "    void *#{result} = NULL;\n"
              cond = emit_expr(ctx, node.condition)
              ctx.io << "    if (!dragonstone_runtime_is_truthy(#{cond})) {\n"
              unless node.body.empty?
                last = emit_block_result(ctx, node.body)
                ctx.io << "    #{result} = #{last};\n"
              end
              if eb = node.else_block
                ctx.io << "    } else {\n"
                unless eb.empty?
                  last = emit_block_result(ctx, eb)
                  ctx.io << "    #{result} = #{last};\n"
                end
              end
              ctx.io << "    }\n"
              result
            end

            private def emit_conditional_expr(ctx : FunctionContext, node : AST::ConditionalExpression) : String
              result = ctx.fresh("_condR")
              ctx.io << "    void *#{result} = NULL;\n"
              cond = emit_expr(ctx, node.condition)
              ctx.io << "    if (dragonstone_runtime_is_truthy(#{cond})) {\n"
              then_ref = emit_expr(ctx, node.then_branch)
              ctx.io << "    #{result} = #{then_ref};\n"
              ctx.io << "    } else {\n"
              else_ref = emit_expr(ctx, node.else_branch)
              ctx.io << "    #{result} = #{else_ref};\n"
              ctx.io << "    }\n"
              result
            end

            private def emit_while(ctx : FunctionContext, node : AST::WhileStatement)
              exit_lbl = ctx.fresh_label("_wExit")
              next_lbl = ctx.fresh_label("_wNext")
              redo_lbl = ctx.fresh_label("_wRedo")
              ctx.loop_stack << {exit_label: exit_lbl, next_label: next_lbl, redo_label: redo_lbl}

              cond = emit_expr(ctx, node.condition)
              ctx.io << "    while (dragonstone_runtime_is_truthy(#{cond})) {\n"
              ctx.io << "    #{redo_lbl}:;\n"
              generate_block(ctx, node.block)
              ctx.io << "    #{next_lbl}:;\n"
              cond2 = emit_expr(ctx, node.condition)
              ctx.io << "    if (!dragonstone_runtime_is_truthy(#{cond2})) break;\n"
              ctx.io << "    }\n"
              ctx.io << "    #{exit_lbl}:;\n"

              ctx.loop_stack.pop
            end

            private def emit_case(ctx : FunctionContext, node : AST::CaseStatement)
              emit_case_impl(ctx, node, nil)
            end

            private def emit_case_expr(ctx : FunctionContext, node : AST::CaseStatement) : String
              result = ctx.fresh("_caseR")
              ctx.io << "    void *#{result} = NULL;\n"
              emit_case_impl(ctx, node, result)
              result
            end

            private def emit_case_impl(ctx : FunctionContext, node : AST::CaseStatement, result_var : String?)
              subj_ref = node.expression ? emit_expr(ctx, node.expression.not_nil!) : nil
              done_lbl = ctx.fresh_label("_caseDone")

              node.when_clauses.each do |clause|
                cond_parts = clause.conditions.map do |cond|
                  t = ctx.fresh
                  if subj = subj_ref
                    if cond.is_a?(AST::TypeExpression)
                      ctx.io << "    void *#{t} = dragonstone_runtime_typeof(#{subj});\n"
                      type_name = cond.to_source
                      ctx.io << "    void *#{t} = dragonstone_runtime_eq(#{subj}, (void*)#{string_ref(type_name)});\n"
                    else
                      cond_ref = emit_expr(ctx, cond)
                      ctx.io << "    void *#{t} = dragonstone_runtime_box_bool(dragonstone_runtime_case_compare(#{subj}, #{cond_ref}));\n"
                    end
                  else
                    cond_ref = emit_expr(ctx, cond)
                    ctx.io << "    void *#{t} = #{cond_ref};\n"
                  end
                  t
                end

                combined = cond_parts.reduce { |acc, c|
                  tt = ctx.fresh
                  ctx.io << "    void *#{tt} = dragonstone_runtime_box_bool(dragonstone_runtime_is_truthy(#{acc}) || dragonstone_runtime_is_truthy(#{c}));\n"
                  tt
                }

                ctx.io << "    if (dragonstone_runtime_is_truthy(#{combined})) {\n"
                if rv = result_var
                  unless clause.block.empty?
                    last = emit_block_result(ctx, clause.block)
                    ctx.io << "    #{rv} = #{last};\n"
                  end
                else
                  generate_block(ctx, clause.block)
                end
                ctx.io << "    goto #{done_lbl};\n"
                ctx.io << "    }\n"
              end

              if eb = node.else_block
                if rv = result_var
                  unless eb.empty?
                    last = emit_block_result(ctx, eb)
                    ctx.io << "    #{rv} = #{last};\n"
                  end
                else
                  generate_block(ctx, eb)
                end
              end
              ctx.io << "    #{done_lbl}:;\n"
            end

            private def emit_begin(ctx : FunctionContext, node : AST::BeginExpression)
              has_rescue = !node.rescue_clauses.empty?
              ensure_block = node.ensure_block
              has_ensure = ensure_block && !ensure_block.empty?

              frame = ctx.fresh("_ehf")
              exc = ctx.fresh("_exc")
              retry_lbl = ctx.fresh_label("_retry")

              ctx.retry_stack << retry_lbl
              ctx.io << "    { DSExceptionFrame #{frame};\n"
              ctx.io << "    #{retry_lbl}:;\n"
              ctx.io << "    dragonstone_runtime_push_exception_frame((void*)&#{frame});\n"

              if has_rescue
                ctx.io << "    if (setjmp(#{frame}.env) == 0) {\n"
                if has_ensure
                  ctx.ensure_stack << ensure_block.not_nil!
                end
                generate_block(ctx, node.body)
                if has_ensure
                  ctx.ensure_stack.pop? rescue nil
                end
                if else_block = node.else_block
                  generate_block(ctx, else_block)
                end
                ctx.io << "    dragonstone_runtime_pop_exception_frame();\n"
                ctx.io << "    } else {\n"
                ctx.io << "    dragonstone_runtime_pop_exception_frame();\n"
                ctx.io << "    void *#{exc} = dragonstone_runtime_get_exception();\n"

                node.rescue_clauses.each do |clause|
                  typed_rescue = !clause.exceptions.empty?
                  if typed_rescue
                    checks = clause.exceptions.map { |t| "strcmp((char*)_exc_type, #{string_ref(t)}) == 0" }.join(" || ")
                    ctx.io << "    {\n"
                    ctx.io << "    void *_exc_type = dragonstone_runtime_typeof(#{exc});\n"
                    ctx.io << "    if (#{checks}) {\n"
                  end
                  if var = clause.exception_variable
                    vname = safe_c_name(var)
                    if ctx.declare_local(vname)
                      ctx.io << "    void *#{vname} = #{exc};\n"
                    else
                      ctx.io << "    #{vname} = #{exc};\n"
                    end
                  end
                  generate_block(ctx, clause.body)
                  if typed_rescue
                    ctx.io << "    }\n"
                    ctx.io << "    }\n"
                  end
                end
                ctx.io << "    }\n"
              else
                generate_block(ctx, node.body)
                ctx.io << "    dragonstone_runtime_pop_exception_frame();\n"
              end

              if has_ensure && (eb = ensure_block)
                generate_block(ctx, eb)
              end

              ctx.io << "    }\n"
              ctx.retry_stack.pop?
            end

            private def emit_class_definition(ctx : FunctionContext, node : AST::ClassDefinition)
              full_name = qualify_name(node.name)
              name_ref = string_ref(full_name)
              class_var = mangle_global_name(full_name)

              ctx.io << "    #{class_var} = dragonstone_runtime_define_class((void*)#{name_ref});\n"

              if super_name = node.superclass
                super_ref = emit_constant_path_by_name(ctx, super_name.split("::"))
                ctx.io << "    dragonstone_runtime_set_superclass(#{class_var}, #{super_ref});\n"
              end

              with_namespace(node.name) do
                node.body.each { |stmt| emit_class_body_stmt(ctx, stmt, class_var) }
              end
            end

            private def emit_module_definition(ctx : FunctionContext, node : AST::ModuleDefinition)
              full_name = qualify_name(node.name)
              name_ref = string_ref(full_name)
              mod_var = mangle_global_name(full_name)

              ctx.io << "    #{mod_var} = dragonstone_runtime_define_module((void*)#{name_ref});\n"

              with_namespace(node.name) do
                node.body.each { |stmt| emit_class_body_stmt(ctx, stmt, mod_var) }
              end
            end

            private def emit_class_body_stmt(ctx : FunctionContext, stmt : AST::Node, container_var : String)
              case stmt
              when AST::FunctionDef
                emit_function_inline(stmt)
                c_name = @function_names[stmt]?
                return unless c_name
                requires_block = @function_requires_block[c_name]? || false
                meth_name_ref = string_ref(stmt.name)
                ctx.io << "    dragonstone_runtime_define_method(#{container_var}, (void*)#{meth_name_ref}, (void*)#{c_name}, #{requires_block ? 1 : 0});\n"
              when AST::ConstantDeclaration
                val = emit_expr(ctx, stmt.value)
                name_ref = string_ref(qualify_name(stmt.name))
                ctx.io << "    dragonstone_runtime_define_constant((void*)#{name_ref}, #{val});\n"
              when AST::ClassDefinition
                emit_class_definition(ctx, stmt)
              when AST::ModuleDefinition
                emit_module_definition(ctx, stmt)
              when AST::EnumDefinition
                emit_enum_definition(ctx, stmt)
              when AST::StructDefinition
                emit_struct_definition(ctx, stmt)
              when AST::AccessorMacro
                emit_accessor_macro(ctx, stmt, container_var)
              when AST::ExtendStatement
                stmt.targets.each do |target|
                  mod_ref = emit_expr(ctx, target)
                  ctx.io << "    dragonstone_runtime_extend_container(#{container_var}, #{mod_ref});\n"
                end
              when AST::Assignment
                val = emit_expr(ctx, stmt.value)
                if stmt.name.starts_with?("@@") || stmt.name.starts_with?("@@@")
                  gname = mangle_global_name(qualify_name(stmt.name))
                  ctx.io << "    #{gname} = #{val};\n"
                elsif constant_symbol?(stmt.name)
                  name_ref = string_ref(qualify_name(stmt.name))
                  ctx.io << "    dragonstone_runtime_define_constant((void*)#{name_ref}, #{val});\n"
                else
                  ctx.io << "    { void *_kval = #{val}; dragonstone_runtime_ivar_set(#{container_var}, (void*)#{string_ref(stmt.name)}, _kval); }\n"
                end
              when AST::AliasDefinition, AST::InstanceVariableDeclaration
                # No codegen needed.
              else
                generate_statement(ctx, stmt)
              end
            end

            private def emit_accessor_macro(ctx : FunctionContext, node : AST::AccessorMacro, container_var : String)
              node.entries.each do |entry|
                field_name = entry.name
                field_ref = string_ref(field_name)
                ivar_name = "@#{field_name}"
                ivar_ref = string_ref(ivar_name)

                if node.kind == :property || node.kind == :getter
                  # getter method: def field_name; @field_name; end
                  getter_id = @block_counter
                  @block_counter += 1
                  getter_c = "_ds_getter_#{getter_id}"
                  blk_io = String::Builder.new
                  blk_io << "static void *#{getter_c}(void *_self) {\n"
                  blk_io << "    return dragonstone_runtime_ivar_get(_self, (void*)#{ivar_ref});\n"
                  blk_io << "}\n"
                  @pending_blocks << blk_io.to_s
                  ctx.io << "    dragonstone_runtime_define_method(#{container_var}, (void*)#{field_ref}, (void*)#{getter_c}, 0);\n"
                end

                if node.kind == :property || node.kind == :setter
                  # setter method: def field_name=(val); @field_name = val; end
                  setter_id = @block_counter
                  @block_counter += 1
                  setter_c = "_ds_setter_#{setter_id}"
                  setter_field_ref = string_ref("#{field_name}=")
                  blk_io = String::Builder.new
                  blk_io << "static void *#{setter_c}(void *_self, void *_val) {\n"
                  blk_io << "    dragonstone_runtime_ivar_set(_self, (void*)#{ivar_ref}, _val);\n"
                  blk_io << "    return _val;\n"
                  blk_io << "}\n"
                  @pending_blocks << blk_io.to_s
                  ctx.io << "    dragonstone_runtime_define_method(#{container_var}, (void*)#{setter_field_ref}, (void*)#{setter_c}, 0);\n"
                end
              end
            end

            private def emit_struct_definition(ctx : FunctionContext, node : AST::StructDefinition)
              full_name = qualify_name(node.name)
              name_ref = string_ref(full_name)
              struct_var = mangle_global_name(full_name)

              ctx.io << "    #{struct_var} = dragonstone_runtime_define_class((void*)#{name_ref});\n"

              with_namespace(node.name) do
                node.body.each { |stmt| emit_class_body_stmt(ctx, stmt, struct_var) }
              end
            end

            private def emit_enum_definition(ctx : FunctionContext, node : AST::EnumDefinition)
              full_name = qualify_name(node.name)
              name_ref = string_ref(full_name)
              enum_var = mangle_global_name(full_name)

              ctx.io << "    #{enum_var} = dragonstone_runtime_define_class((void*)#{name_ref});\n"
              current_value = -1_i64
              node.members.each do |member|
                if explicit = member.value
                  current_value = static_int_value(explicit) || current_value + 1_i64
                else
                  current_value += 1_i64
                end
                mem_ref = string_ref(member.name)
                ctx.io << "    dragonstone_runtime_define_enum_member(#{enum_var}, (void*)#{mem_ref}, #{current_value}LL);\n"
              end
            end

            private def emit_ivar_assignment(ctx : FunctionContext, node : AST::InstanceVariableAssignment)
              val = emit_expr(ctx, node.value)
              self_ref = ctx.has_local?("self") ? "self" : "dragonstone_runtime_root_self()"
              name_ref = string_ref(normalize_ivar_name(node.name))
              ctx.io << "    dragonstone_runtime_ivar_set(#{self_ref}, (void*)#{name_ref}, #{val});\n"
            end

            private def emit_ivar_assign_expr(ctx : FunctionContext, node : AST::InstanceVariableAssignment) : String
              emit_ivar_assignment(ctx, node)
              val_ref = emit_ivar_get_by_name(ctx, node.name)
              val_ref
            end

            private def emit_ivar_get(ctx : FunctionContext, node : AST::InstanceVariable) : String
              emit_ivar_get_by_name(ctx, node.name)
            end

            private def emit_ivar_get_by_name(ctx : FunctionContext, ivar_name : String) : String
              self_ref = ctx.has_local?("self") ? "self" : "dragonstone_runtime_root_self()"
              name_ref = string_ref(normalize_ivar_name(ivar_name))
              t = ctx.fresh
              ctx.io << "    void *#{t} = dragonstone_runtime_ivar_get(#{self_ref}, (void*)#{name_ref});\n"
              t
            end

            private def emit_class_var(ctx : FunctionContext, node : AST::ClassVariable) : String
              emit_ivar_get_by_name(ctx, node.name)
            end

            private def emit_module_var(ctx : FunctionContext, node : AST::ModuleVariable) : String
              emit_ivar_get_by_name(ctx, node.name)
            end

            private def emit_attr_assignment(ctx : FunctionContext, node : AST::AttributeAssignment)
              emit_attr_assignment_expr(ctx, node)
            end

            private def emit_attr_assignment_expr(ctx : FunctionContext, node : AST::AttributeAssignment) : String
              recv = emit_expr(ctx, node.receiver)
              val = emit_expr(ctx, node.value)
              setter_ref = string_ref("#{node.name}=")
              t = ctx.fresh
              ctx.io << "    void *#{t};\n"
              ctx.io << "    { void *_sa[] = {#{val}}; #{t} = dragonstone_runtime_method_invoke(#{recv}, (void*)#{setter_ref}, 1, _sa, NULL); }\n"
              t
            end

            private def emit_index_access(ctx : FunctionContext, node : AST::IndexAccess) : String
              obj = emit_expr(ctx, node.object)
              idx = emit_expr(ctx, node.index)
              t = ctx.fresh
              ctx.io << "    void *#{t} = dragonstone_runtime_index_get(#{obj}, #{idx});\n"
              t
            end

            private def emit_index_assignment(ctx : FunctionContext, node : AST::IndexAssignment)
              obj = emit_expr(ctx, node.object)
              idx = emit_expr(ctx, node.index)
              val = emit_expr(ctx, node.value)
              ctx.io << "    dragonstone_runtime_index_set(#{obj}, #{idx}, #{val});\n"
            end

            private def emit_index_assignment_expr(ctx : FunctionContext, node : AST::IndexAssignment) : String
              emit_index_assignment(ctx, node)
              "NULL"
            end

            private def emit_array_literal(ctx : FunctionContext, node : AST::ArrayLiteral) : String
              elem_refs = node.elements.map { |e| emit_expr(ctx, e) }
              t = ctx.fresh
              if elem_refs.empty?
                ctx.io << "    void *#{t} = dragonstone_runtime_array_literal(0, NULL);\n"
              else
                arr = ctx.fresh("_aelems")
                ctx.io << "    void *#{arr}[] = {#{elem_refs.join(", ")}};\n"
                ctx.io << "    void *#{t} = dragonstone_runtime_array_literal(#{elem_refs.size}, #{arr});\n"
              end
              t
            end

            private def emit_map_literal(ctx : FunctionContext, node : AST::MapLiteral) : String
              key_refs = node.entries.map { |(k, _)| emit_expr(ctx, k) }
              val_refs = node.entries.map { |(_, v)| emit_expr(ctx, v) }
              t = ctx.fresh
              if key_refs.empty?
                ctx.io << "    void *#{t} = dragonstone_runtime_map_literal(0, NULL, NULL);\n"
              else
                karr = ctx.fresh("_mkeys")
                varr = ctx.fresh("_mvals")
                ctx.io << "    void *#{karr}[] = {#{key_refs.join(", ")}};\n"
                ctx.io << "    void *#{varr}[] = {#{val_refs.join(", ")}};\n"
                ctx.io << "    void *#{t} = dragonstone_runtime_map_literal(#{key_refs.size}, #{karr}, #{varr});\n"
              end
              t
            end

            private def emit_tuple_literal(ctx : FunctionContext, node : AST::TupleLiteral) : String
              elem_refs = node.elements.map { |e| emit_expr(ctx, e) }
              t = ctx.fresh
              if elem_refs.empty?
                ctx.io << "    void *#{t} = dragonstone_runtime_tuple_literal(0, NULL);\n"
              else
                arr = ctx.fresh("_telems")
                ctx.io << "    void *#{arr}[] = {#{elem_refs.join(", ")}};\n"
                ctx.io << "    void *#{t} = dragonstone_runtime_tuple_literal(#{elem_refs.size}, #{arr});\n"
              end
              t
            end

            private def emit_named_tuple_literal(ctx : FunctionContext, node : AST::NamedTupleLiteral) : String
              key_refs = node.entries.map { |e| "(void*)#{string_ref(e.name)}" }
              val_refs = node.entries.map { |e| emit_expr(ctx, e.value) }
              t = ctx.fresh
              if key_refs.empty?
                ctx.io << "    void *#{t} = dragonstone_runtime_named_tuple_literal(0, NULL, NULL);\n"
              else
                karr = ctx.fresh("_ntkeys")
                varr = ctx.fresh("_ntvals")
                ctx.io << "    void *#{karr}[] = {#{key_refs.join(", ")}};\n"
                ctx.io << "    void *#{varr}[] = {#{val_refs.join(", ")}};\n"
                ctx.io << "    void *#{t} = dragonstone_runtime_named_tuple_literal(#{key_refs.size}, #{karr}, #{varr});\n"
              end
              t
            end

            private def emit_bag_constructor(ctx : FunctionContext, node : AST::BagConstructor) : String
              type_ref = string_ref(node.element_type.to_source)
              t = ctx.fresh
              ctx.io << "    void *#{t} = dragonstone_runtime_bag_constructor((void*)#{type_ref});\n"
              t
            end

            private def emit_interpolated_string(ctx : FunctionContext, node : AST::InterpolatedString) : String
              parts = [] of String
              node.normalized_parts.each do |type, content|
                if type == :string
                  parts << "(void*)#{string_ref(content.as(String))}"
                else
                  expr_node = content.is_a?(AST::Node) ? content.as(AST::Node) : parse_interpolation(content.to_s)
                  ref = emit_expr(ctx, expr_node)
                  str_ref = ctx.fresh
                  ctx.io << "    void *#{str_ref} = dragonstone_runtime_to_string(#{ref});\n"
                  parts << str_ref
                end
              end

              t = ctx.fresh
              if parts.empty?
                ctx.io << "    void *#{t} = (void*)#{string_ref("")};\n"
              elsif parts.size == 1
                ctx.io << "    void *#{t} = #{parts[0]};\n"
              else
                parr = ctx.fresh("_iparts")
                ctx.io << "    void *#{parr}[] = {#{parts.join(", ")}};\n"
                ctx.io << "    void *#{t} = dragonstone_runtime_interpolated_string(#{parts.size}, #{parr});\n"
              end
              t
            end

            private def emit_debug_echo(ctx : FunctionContext, node : AST::DebugEcho)
              val = emit_expr(ctx, node.expression)
              label_ref = string_ref(node.expression.to_source)
              ctx.io << "    dragonstone_runtime_debug_accum((void*)#{label_ref}, #{val});\n"
              ctx.io << "    dragonstone_runtime_debug_flush();\n"
            end

            private def emit_array_literal_inline(ctx : FunctionContext, refs : Array(String)) : String
              t = ctx.fresh
              arr = ctx.fresh("_inlarr")
              ctx.io << "    void *#{arr}[] = {#{refs.join(", ")}};\n"
              ctx.io << "    void *#{t} = dragonstone_runtime_array_literal(#{refs.size}, #{arr});\n"
              t
            end

            private def emit_with_expr(ctx : FunctionContext, node : AST::WithExpression) : String
              recv = emit_expr(ctx, node.receiver)
              ctx.with_stack << recv
              node.body.each { |stmt| generate_statement(ctx, stmt) }
              ctx.with_stack.pop
              recv
            end

            private def emit_return(ctx : FunctionContext, node : AST::ReturnStatement)
              if v = node.value
                ref = emit_expr(ctx, v)
                emit_ensure_chain(ctx)
                ctx.io << "    return #{ref};\n"
              else
                emit_ensure_chain(ctx)
                ctx.io << "    return NULL;\n"
              end
            end

            private def emit_break(ctx : FunctionContext, node : AST::BreakStatement)
              if loop_info = ctx.loop_stack.last?
                ctx.io << "    goto #{loop_info[:exit_label]};\n"
              else
                ctx.io << "    break;\n"
              end
            end

            private def emit_next(ctx : FunctionContext, node : AST::NextStatement)
              if loop_info = ctx.loop_stack.last?
                ctx.io << "    goto #{loop_info[:next_label]};\n"
              else
                ctx.io << "    continue;\n"
              end
            end

            private def emit_redo(ctx : FunctionContext)
              if loop_info = ctx.loop_stack.last?
                ctx.io << "    goto #{loop_info[:redo_label]};\n"
              end
            end

            private def emit_retry(ctx : FunctionContext)
              if lbl = ctx.retry_stack.last?
                ctx.io << "    goto #{lbl};\n"
              end
            end

            private def emit_quit(ctx : FunctionContext, node : AST::QuitStatement)
              status = node.status ? emit_expr(ctx, node.status.not_nil!) : "NULL"
              if node.status
                ctx.io << "    dragonstone_io_quit(dragonstone_runtime_unbox_i64(#{status}));\n"
              else
                ctx.io << "    dragonstone_io_quit(0);\n"
              end
            end

            private def emit_abort(ctx : FunctionContext, node : AST::AbortStatement)
              msg = node.message ? emit_expr(ctx, node.message.not_nil!) : "(void*)#{string_ref("Aborted")}"
              ctx.io << "    dragonstone_io_abort(#{msg});\n"
            end

            private def emit_raise(ctx : FunctionContext, node : AST::RaiseExpression)
              if expr = node.expression
                ref = emit_expr(ctx, expr)
                ctx.io << "    dragonstone_runtime_raise(#{ref});\n"
              else
                ctx.io << "    dragonstone_runtime_raise(dragonstone_runtime_get_exception());\n"
              end
            end

            private def emit_ensure_chain(ctx : FunctionContext)
              return if ctx.ensure_stack.empty?
              pending = ctx.ensure_stack.dup
              ctx.ensure_stack.clear
              pending.reverse_each { |blk| generate_block(ctx, blk) }
            end

            private def emit_function_inline(func : AST::FunctionDef)
              c_name = @function_names[func]? || begin
                register_function(func)
                @function_names[func]
              end
              return if @emitted_functions.includes?(c_name)
              blk_io = String::Builder.new
              emit_function(blk_io, func)
              blk_io << "\n"
              @pending_blocks << blk_io.to_s
            end

            private def emit_block_result(ctx : FunctionContext, stmts : Array(AST::Node)) : String
              return "NULL" if stmts.empty?
              stmts[0...-1].each { |s| generate_statement(ctx, s) }
              last = stmts.last
              expression_statement?(last) ? emit_expr(ctx, last) : begin
                generate_statement(ctx, last)
                "NULL"
              end
            end

            private def pre_declare_locals(ctx : FunctionContext, stmts : Array(AST::Node))
              vars = Set(String).new
              stmts.each { |s| scan_locals(s, vars) }
              vars.each do |v|
                cname = safe_c_name(v)
                next if ctx.has_local?(cname)
                ctx.declare_local(cname)
                ctx.io << "    void *#{cname} = NULL;\n"
              end
            end

            private def scan_locals(node : AST::Node, vars : Set(String))
              case node
              when AST::Assignment
                n = node.name
                unless constant_symbol?(n) || @globals.includes?(qualify_name(n)) ||
                       n.starts_with?("@@") || n.starts_with?("@@@")
                  vars << n
                end
                scan_locals(node.value, vars)
              when AST::FunctionDef, AST::ClassDefinition, AST::ModuleDefinition,
                   AST::StructDefinition, AST::EnumDefinition
              when AST::IfStatement
                scan_locals(node.condition, vars)
                node.then_block.each { |s| scan_locals(s, vars) }
                node.elsif_blocks.each { |c| scan_locals(c.condition, vars); c.block.each { |s| scan_locals(s, vars) } }
                node.else_block.try { |b| b.each { |s| scan_locals(s, vars) } }
              when AST::WhileStatement
                scan_locals(node.condition, vars)
                node.block.each { |s| scan_locals(s, vars) }
              when AST::CaseStatement
                node.expression.try { |e| scan_locals(e, vars) }
                node.when_clauses.each { |c| c.block.each { |s| scan_locals(s, vars) } }
                node.else_block.try { |b| b.each { |s| scan_locals(s, vars) } }
              when AST::BeginExpression
                node.body.each { |s| scan_locals(s, vars) }
                node.rescue_clauses.each { |c|
                  c.exception_variable.try { |v| vars << v }
                  c.body.each { |s| scan_locals(s, vars) }
                }
              when AST::BinaryOp
                scan_locals(node.left, vars)
                scan_locals(node.right, vars)
              when AST::UnaryOp
                scan_locals(node.operand, vars)
              when AST::ConditionalExpression
                scan_locals(node.condition, vars)
                scan_locals(node.then_branch, vars)
                scan_locals(node.else_branch, vars)
              when AST::MethodCall
                node.receiver.try { |r| scan_locals(r, vars) }
                node.arguments.each { |a| scan_locals(a, vars) }
              when AST::ReturnStatement
                node.value.try { |v| scan_locals(v, vars) }
              when AST::ArrayLiteral
                node.elements.each { |e| scan_locals(e, vars) }
              when AST::MapLiteral
                node.entries.each { |(k, v)| scan_locals(k, vars); scan_locals(v, vars) }
              else
                # Skip.
              end
            end

            private def collect_strings
              @namespace_stack.clear
              @program.ast.statements.each { |s| collect_strings_from(s) }
              @namespace_stack.clear
            end

            private def collect_strings_from(node : AST::Node)
              case node
              when AST::Literal
                case val = node.value
                when String      then intern_string(val)
                when Char        then intern_string(val.to_s)
                when SymbolValue then intern_string(val.name)
                end
              when AST::InterpolatedString
                node.normalized_parts.each do |type, content|
                  intern_string(content.as(String)) if type == :string
                  collect_strings_from(parse_interpolation(content.to_s)) if type == :expression
                end
              when AST::MethodCall
                intern_string(node.name)
                node.receiver.try { |r| collect_strings_from(r) }
                node.arguments.each { |a| collect_strings_from(a) }
              when AST::FunctionDef
                intern_string(node.name)
                node.body.each { |s| collect_strings_from(s) }
              when AST::BlockLiteral
                node.body.each { |s| collect_strings_from(s) }
              when AST::ParaLiteral
                node.body.each { |s| collect_strings_from(s) }
              when AST::FunctionLiteral
                node.body.each { |s| collect_strings_from(s) }
              when AST::ClassDefinition, AST::ModuleDefinition, AST::StructDefinition
                intern_string(qualify_name(node.name))
                with_namespace(node.name) { node.body.each { |s| collect_strings_from(s) } }
              when AST::EnumDefinition
                intern_string(qualify_name(node.name))
                node.members.each { |m| intern_string(m.name) }
              when AST::ConstantDeclaration
                intern_string(qualify_name(node.name))
                collect_strings_from(node.value)
              when AST::ConstantPath
                node.names.each { |n| intern_string(n) }
              when AST::Assignment
                collect_strings_from(node.value)
              when AST::BinaryOp
                collect_strings_from(node.left)
                collect_strings_from(node.right)
              when AST::UnaryOp
                collect_strings_from(node.operand)
              when AST::ConditionalExpression
                collect_strings_from(node.condition)
                collect_strings_from(node.then_branch)
                collect_strings_from(node.else_branch)
              when AST::IfStatement
                collect_strings_from(node.condition)
                node.then_block.each { |s| collect_strings_from(s) }
                node.elsif_blocks.each { |c| collect_strings_from(c.condition); c.block.each { |s| collect_strings_from(s) } }
                node.else_block.try { |b| b.each { |s| collect_strings_from(s) } }
              when AST::UnlessStatement
                collect_strings_from(node.condition)
                node.body.each { |s| collect_strings_from(s) }
                node.else_block.try { |b| b.each { |s| collect_strings_from(s) } }
              when AST::CaseStatement
                node.expression.try { |e| collect_strings_from(e) }
                node.when_clauses.each do |clause|
                  clause.conditions.each { |cond| collect_strings_from(cond) }
                  clause.block.each { |s| collect_strings_from(s) }
                end
                node.else_block.try { |b| b.each { |s| collect_strings_from(s) } }
              when AST::WhileStatement
                collect_strings_from(node.condition)
                node.block.each { |s| collect_strings_from(s) }
              when AST::ArrayLiteral
                node.elements.each { |e| collect_strings_from(e) }
              when AST::MapLiteral
                node.entries.each { |(k, v)| collect_strings_from(k); collect_strings_from(v) }
              when AST::TupleLiteral
                node.elements.each { |e| collect_strings_from(e) }
              when AST::NamedTupleLiteral
                node.entries.each do |entry|
                  intern_string(entry.name)
                  collect_strings_from(entry.value)
                end
              when AST::BagConstructor
                intern_string(node.element_type.to_source)
              when AST::IndexAccess
                collect_strings_from(node.object)
                collect_strings_from(node.index)
              when AST::IndexAssignment
                collect_strings_from(node.object)
                collect_strings_from(node.index)
                collect_strings_from(node.value)
              when AST::ReturnStatement
                node.value.try { |v| collect_strings_from(v) }
              when AST::YieldExpression
                node.arguments.each { |a| collect_strings_from(a) }
              when AST::BeginExpression
                node.body.each { |s| collect_strings_from(s) }
                node.rescue_clauses.each { |c| c.body.each { |s| collect_strings_from(s) } }
                node.else_block.try { |b| b.each { |s| collect_strings_from(s) } }
                node.ensure_block.try { |b| b.each { |s| collect_strings_from(s) } }
              when AST::InstanceVariable, AST::InstanceVariableAssignment
                raw_name = node.is_a?(AST::InstanceVariable) ? node.name : node.as(AST::InstanceVariableAssignment).name
                intern_string(normalize_ivar_name(raw_name))
                if node.is_a?(AST::InstanceVariableAssignment)
                  collect_strings_from(node.as(AST::InstanceVariableAssignment).value)
                end
              when AST::AttributeAssignment
                intern_string(node.name)
                intern_string("#{node.name}=")
                collect_strings_from(node.receiver)
                collect_strings_from(node.value)
              when AST::DebugEcho
                intern_string(node.expression.to_source)
                collect_strings_from(node.expression)
              else
                # Skip.
              end
            end

            private def collect_globals
              @namespace_stack.clear
              @program.ast.statements.each { |s| collect_globals_from(s) }
              @namespace_stack.clear
            end

            private def collect_bindings
              @namespace_stack.clear
              @class_name_occurrences.clear
              @program.ast.statements.each { |s| collect_bindings_from(s) }
              @namespace_stack.clear
            end

            private def collect_bindings_from(node : AST::Node)
              case node
              when AST::ClassDefinition, AST::ModuleDefinition
                @known_constants << qualify_name(node.name)
                with_namespace(node.name) { node.body.each { |s| collect_bindings_from(s) } }
              when AST::StructDefinition
                @known_constants << qualify_name(node.name)
                with_namespace(node.name) { node.body.each { |s| collect_bindings_from(s) } }
              when AST::EnumDefinition
                @known_constants << qualify_name(node.name)
              when AST::ConstantDeclaration
                @known_constants << qualify_name(node.name)
                collect_bindings_from(node.value)
              when AST::Assignment
                if !@namespace_stack.empty? && !node.name.starts_with?("@@") && !node.name.starts_with?("@@@")
                  if constant_symbol?(node.name)
                    @known_constants << qualify_name(node.name)
                  else
                    @class_scope_bindings[@namespace_stack.join("::")] << node.name
                  end
                end
                collect_bindings_from(node.value)
              when AST::FunctionDef
                node.body.each { |s| collect_bindings_from(s) }
              when AST::IfStatement
                collect_bindings_from(node.condition)
                node.then_block.each { |s| collect_bindings_from(s) }
                node.elsif_blocks.each { |c| collect_bindings_from(c.condition); c.block.each { |s| collect_bindings_from(s) } }
                node.else_block.try { |b| b.each { |s| collect_bindings_from(s) } }
              when AST::UnlessStatement
                collect_bindings_from(node.condition)
                node.body.each { |s| collect_bindings_from(s) }
                node.else_block.try { |b| b.each { |s| collect_bindings_from(s) } }
              when AST::CaseStatement
                node.expression.try { |e| collect_bindings_from(e) }
                node.when_clauses.each do |c|
                  c.conditions.each { |cond| collect_bindings_from(cond) }
                  c.block.each { |s| collect_bindings_from(s) }
                end
                node.else_block.try { |b| b.each { |s| collect_bindings_from(s) } }
              when AST::WhileStatement
                collect_bindings_from(node.condition)
                node.block.each { |s| collect_bindings_from(s) }
              when AST::BeginExpression
                node.body.each { |s| collect_bindings_from(s) }
                node.rescue_clauses.each { |c| c.body.each { |s| collect_bindings_from(s) } }
                node.else_block.try { |b| b.each { |s| collect_bindings_from(s) } }
                node.ensure_block.try { |b| b.each { |s| collect_bindings_from(s) } }
              when AST::MethodCall
                node.receiver.try { |r| collect_bindings_from(r) }
                node.arguments.each { |a| collect_bindings_from(a) }
              when AST::BinaryOp
                collect_bindings_from(node.left)
                collect_bindings_from(node.right)
              when AST::UnaryOp
                collect_bindings_from(node.operand)
              when AST::ConditionalExpression
                collect_bindings_from(node.condition)
                collect_bindings_from(node.then_branch)
                collect_bindings_from(node.else_branch)
              when AST::ArrayLiteral
                node.elements.each { |e| collect_bindings_from(e) }
              when AST::MapLiteral
                node.entries.each { |(k, v)| collect_bindings_from(k); collect_bindings_from(v) }
              when AST::TupleLiteral
                node.elements.each { |e| collect_bindings_from(e) }
              when AST::NamedTupleLiteral
                node.entries.each { |entry| collect_bindings_from(entry.value) }
              when AST::InterpolatedString
                node.normalized_parts.each do |type, content|
                  next unless type == :expression
                  collect_bindings_from(content.is_a?(AST::Node) ? content.as(AST::Node) : parse_interpolation(content.to_s))
                end
              else
                # Skip.
              end
            end

            private def collect_globals_from(node : AST::Node)
              case node
              when AST::ClassDefinition, AST::ModuleDefinition
                @globals << qualify_name(node.name)
                with_namespace(node.name) { node.body.each { |s| collect_globals_from(s) } }
              when AST::StructDefinition
                @globals << qualify_name(node.name)
                with_namespace(node.name) { node.body.each { |s| collect_globals_from(s) } }
              when AST::EnumDefinition
                @globals << qualify_name(node.name)
              when AST::FunctionDef
                node.body.each { |s| collect_globals_from(s) }
              when AST::Assignment
                if node.name.starts_with?("__ds_cvar_") || node.name.starts_with?("__ds_mvar_") ||
                   node.name.starts_with?("@@")
                  @globals << qualify_name(node.name)
                end
                collect_globals_from(node.value)
              else
                # Skip.
              end
            end

            private def collect_functions
              @namespace_stack.clear
              @class_name_occurrences.clear
              @program.ast.statements.each { |s| collect_functions_from(s) }
              @namespace_stack.clear
            end

            private def collect_functions_from(node : AST::Node)
              case node
              when AST::StructDefinition
                struct_name = @struct_unique_names[node]? || node.name
                with_namespace(struct_name) { node.body.each { |s| collect_functions_from(s) } }
              when AST::ClassDefinition, AST::ModuleDefinition
                with_namespace(node.name) { node.body.each { |s| collect_functions_from(s) } }
              when AST::FunctionDef
                register_function(node)
              end
            end

            private def register_function(func : AST::FunctionDef)
              base_name = if @namespace_stack.empty?
                            func.name == "main" ? "_ds_user_main" : func.name
                          else
                            "#{@namespace_stack.join("_")}_#{func.name}"
                          end

              @function_namespaces[func] = @namespace_stack.dup

              has_receiver = !func.receiver.nil? || !@namespace_stack.empty?
              @function_receivers[func] = has_receiver

              requires_block = function_body_contains_yield?(func.body)

              c_name = safe_c_func_name(base_name)
              existing_count = @function_overloads[c_name].size
              unique_c_name = existing_count == 0 ? c_name : "#{c_name}_v#{existing_count}"

              @function_names[func] = unique_c_name
              @function_requires_block[unique_c_name] = requires_block
              @function_overloads[c_name] << unique_c_name
              @function_defs[unique_c_name] = func
            end

            private def index_struct_types
              @namespace_stack.clear
              @program.ast.statements.each { |s| register_struct_types(s) }
              @namespace_stack.clear
            end

            private def register_struct_types(node : AST::Node)
              case node
              when AST::StructDefinition
                base_full_name = qualify_name(node.name)
                count = (@struct_name_occurrences[base_full_name] += 1)
                unique_ns = count > 1 ? "#{node.name}_#{count}" : node.name
                full_name = qualify_name(unique_ns)
                @struct_unique_names[node] = unique_ns
                @struct_alias_map[node.name] = full_name
                @struct_alias_map[base_full_name] = full_name
                @struct_layouts[full_name] ||= [] of AST::TypeExpression?
                @struct_field_indices[full_name] ||= {} of String => Int32
                @struct_stack << full_name
                with_namespace(unique_ns) { node.body.each { |s| register_struct_types(s) } }
                @struct_stack.pop
              when AST::ModuleDefinition, AST::ClassDefinition
                with_namespace(node.name) { node.body.each { |s| register_struct_types(s) } }
              when AST::AccessorMacro
                if current = @struct_stack.last?
                  if node.kind == :property || node.kind == :getter
                    fields = (@struct_layouts[current] ||= [] of AST::TypeExpression?)
                    indices = (@struct_field_indices[current] ||= {} of String => Int32)
                    node.entries.each do |entry|
                      indices[entry.name] = fields.size
                      fields << entry.type_annotation
                    end
                  end
                end
              else
                # Skip.
              end
            end

            private def function_body_contains_yield?(stmts : Array(AST::Node)) : Bool
              stmts.any? { |s| node_contains_yield?(s) }
            end

            private def node_contains_yield?(node : AST::Node) : Bool
              case node
              when AST::YieldExpression                                                        then true
              when AST::FunctionDef, AST::FunctionLiteral, AST::BlockLiteral, AST::ParaLiteral then false
              when AST::MethodCall
                (node.receiver ? node_contains_yield?(node.receiver.not_nil!) : false) ||
                  node.arguments.any? { |a| node_contains_yield?(a) }
              when AST::Assignment      then node_contains_yield?(node.value)
              when AST::BinaryOp        then node_contains_yield?(node.left) || node_contains_yield?(node.right)
              when AST::ReturnStatement then node.value ? node_contains_yield?(node.value.not_nil!) : false
              when AST::IfStatement
                node_contains_yield?(node.condition) ||
                  node.then_block.any? { |s| node_contains_yield?(s) } ||
                  node.elsif_blocks.any? { |c| node_contains_yield?(c.condition) || c.block.any? { |s| node_contains_yield?(s) } } ||
                  (node.else_block ? node.else_block.not_nil!.any? { |s| node_contains_yield?(s) } : false)
              when AST::WhileStatement
                node_contains_yield?(node.condition) || node.block.any? { |s| node_contains_yield?(s) }
              when AST::BeginExpression
                node.body.any? { |s| node_contains_yield?(s) }
              else false
              end
            end

            private def build_param_list(func : AST::FunctionDef, c_name : String) : String
              parts = [] of String
              if @function_receivers[func]?
                parts << "void *_self"
              end
              func.typed_parameters.each_with_index do |_, i|
                parts << "void *_arg#{i}"
              end
              if @function_requires_block[c_name]? || false
                parts << "void *_block_arg"
              end
              parts.empty? ? "void" : parts.join(", ")
            end

            private def resolve_direct_call(name : String, argc : Int32, has_block : Bool) : String?
              candidates = [] of String

              if @namespace_stack.empty?
                base = safe_c_func_name(name == "main" ? "_ds_user_main" : name)
                if overloads = @function_overloads[base]?
                  candidates.concat(overloads)
                end
              else
                ns_base = safe_c_func_name("#{@namespace_stack.join("_")}_#{name}")
                if overloads = @function_overloads[ns_base]?
                  candidates.concat(overloads)
                end
                plain_base = safe_c_func_name(name)
                if overloads = @function_overloads[plain_base]?
                  candidates.concat(overloads)
                end
              end

              return nil if candidates.empty?

              exact = candidates.find do |c_name|
                if func = @function_defs[c_name]?
                  expects_block = @function_requires_block[c_name]? || false
                  func.typed_parameters.size == argc && expects_block == has_block
                else
                  false
                end
              end
              return exact if exact

              # If the block-flag differed, allow arity-only exact matches.
              candidates.find do |c_name|
                if func = @function_defs[c_name]?
                  func.typed_parameters.size == argc
                else
                  false
                end
              end
            end

            private def resolve_constant_path(name : String) : Array(String)?
              ns = @namespace_stack.dup
              while ns.size >= 0
                names = ns + [name]
                full = names.join("::")
                return names if @known_constants.includes?(full)
                break if ns.empty?
                ns.pop
              end
              @known_constants.includes?(name) ? [name] : nil
            end

            private def resolve_class_scope_binding_owner(name : String) : String?
              ns = @namespace_stack.dup
              while ns.size > 0
                owner = ns.join("::")
                if @class_scope_bindings[owner]?.try(&.includes?(name))
                  return owner
                end
                ns.pop
              end
              nil
            end

            private def static_int_value(node : AST::Node) : Int64?
              case node
              when AST::Literal
                case val = node.value
                when Int32 then val.to_i64
                when Int64 then val
                else
                  nil
                end
              when AST::UnaryOp
                if node.operator == "-" || node.operator == :"-"
                  if inner = static_int_value(node.operand)
                    -inner
                  else
                    nil
                  end
                else
                  nil
                end
              else
                nil
              end
            end

            private def intern_string(s : String) : String
              return @string_literals[s][:name] if @string_literals.has_key?(s)
              name = "_ds_str#{@string_counter}"
              @string_counter += 1
              escaped = c_escape(s)
              @string_literals[s] = {name: name, escaped: escaped, length: s.bytesize}
              @string_order << s
              name
            end

            private def string_ref(s : String) : String
              intern_string(s)
            end

            private def c_escape(s : String) : String
              String.build do |io|
                s.each_byte do |b|
                  case b
                  when 0x22       then io << "\\\""
                  when 0x5C       then io << "\\\\"
                  when 0x0A       then io << "\\n"
                  when 0x0D       then io << "\\r"
                  when 0x09       then io << "\\t"
                  when 0x00       then io << "\\0"
                  when 0x20..0x7E then io << b.chr
                  else
                    io << sprintf("\\%03o", b)
                  end
                end
              end
            end

            private def c_string_literal(s : String) : String
              "\"#{c_escape(s)}\""
            end

            private def mangle_global_name(name : String) : String
              "_ds_g_#{name.gsub("::", "_").gsub(/[^a-zA-Z0-9_]/) { |m| "_#{m[0].ord}_" }}"
            end

            private def safe_c_name(name : String) : String
              cleaned = name.gsub(/[^a-zA-Z0-9_]/) { |m|
                case m
                when "@" then ""
                when "?" then "_p"
                when "!" then "_b"
                else          "_#{m[0].ord}_"
                end
              }
              reserved = %w[int float double char long short unsigned signed void
                if else while for do switch case break continue return
                struct union enum typedef extern static auto register
                const volatile inline restrict goto default sizeof
                true false NULL]
              cleaned = "_ds_#{cleaned}" if reserved.includes?(cleaned) || cleaned.empty?
              cleaned
            end

            private def safe_c_func_name(name : String) : String
              "_ds_#{name.gsub("::", "_").gsub(/[^a-zA-Z0-9_]/) { |m| "_#{m[0].ord}_" }}"
            end

            private def qualify_name(name : String) : String
              @namespace_stack.empty? ? name : (@namespace_stack + [name]).join("::")
            end

            private def with_namespace(name : String)
              @namespace_stack << name
              yield
            ensure
              @namespace_stack.pop
            end

            private def constant_symbol?(name : String) : Bool
              !name.empty? && name[0].uppercase?
            end

            private def normalize_ivar_name(name : String) : String
              name.starts_with?("@") ? name : "@#{name}"
            end

            private def parse_interpolation(source : String) : AST::Node
              lexer = Lexer.new(source)
              tokens = lexer.tokenize
              parser = Parser.new(tokens)
              parser.parse_expression_entry
            end
          end
        end
      end
    end
  end
end
