# ---------------------------------
# -------- LLVM Backend -----------
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
        module LLVM
          class Backend
            EXTENSION = "ll"

            def build(program : ::Dragonstone::IR::Program, options : BuildOptions) : BuildArtifact
              source_dump = ""
              summary_lines = [] of String
              begin
                serializer = Shared::ProgramSerializer.new(program)
                source_dump = serializer.source
                summary_lines = serializer.summary_lines
              rescue
                # Continue.
              end
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

                {% if flag?(:windows) %}
                  io << "target triple = \"x86_64-pc-windows-msvc\"\n"
                {% elsif flag?(:linux) %}
                  io << "target triple = \"x86_64-pc-linux-gnu\"\n"
                {% elsif flag?(:darwin) %}
                  io << "target triple = \"x86_64-apple-darwin\"\n"
                {% end %}

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

                # Generate actual LLVM IR.
                generator.generate(io)
              end
            end
          end

          class IRGenerator
            alias ValueRef = NamedTuple(type: String, ref: String, constant: Bool)
            alias FunctionSignature = NamedTuple(return_type: String, param_types: Array(String), param_typed: Array(Bool))
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
              super_invoke: String,
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
              interpolated_string: String,
              raise: String,
              range_literal: String,
              box_struct: String,
              unbox_struct: String,
              array_push: String,
              generic_add: String,
              generic_sub: String,
              generic_mul: String,
              generic_div: String,
              generic_mod: String,
              generic_negate: String,
              generic_shl: String,
              generic_shr: String,
              generic_pow: String,
              generic_floor_div: String,
              generic_cmp: String,
              to_string: String,
              type_of: String,
              bag_constructor: String,
              ivar_get: String,
              ivar_set: String,
              argv_get: String,
              argv_set: String,
              stdout_get: String,
              stderr_get: String,
              stdin_get: String,
              argc_get: String,
              argf_get: String,
              root_self: String,
              singleton_define: String,
              define_class: String,
              set_superclass: String,
              define_module: String,
              define_method: String,
              define_enum_member: String,
              push_handler: String,
              pop_handler: String,
              get_exception: String,
              extend_container: String,
              gt: String,
              lt: String,
              gte: String,
              lte: String,
              eq: String,
              ne: String,
              is_truthy: String,
              debug_accum: String,
              debug_flush: String,
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
              @function_defs = {} of String => AST::FunctionDef

              @emitted_functions = Set(String).new

              @function_namespaces = {} of AST::FunctionDef => Array(String)

              @runtime_literals_preregistered = false

              @class_name_occurrences = Hash(String, Int32).new(0)

              @runtime_types_emitted = false

              @struct_layouts = {} of String => Array(AST::TypeExpression?)
              @struct_field_indices = {} of String => Hash(String, Int32)
              @struct_alias_map = {} of String => String
              @struct_name_occurrences = Hash(String, Int32).new(0)
              @struct_unique_names = {} of AST::StructDefinition => String
              @struct_stack = [] of String

              @emitted_struct_types = Set(String).new

              @struct_llvm_lookup = {} of String => String

              @namespace_stack = [] of String

              @globals = Set(String).new

              @function_overloads = Hash(String, Array(String)).new { |h, k| h[k] = [] of String }

              @pending_blocks = [] of String
              @pending_strings = [] of String

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
                super_invoke: "dragonstone_runtime_super_invoke",
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
                interpolated_string: "dragonstone_runtime_interpolated_string",
                raise: "dragonstone_runtime_raise",
                range_literal: "dragonstone_runtime_range_literal",
                box_struct: "dragonstone_runtime_box_struct",
                unbox_struct: "dragonstone_runtime_unbox_struct",
                array_push: "dragonstone_runtime_array_push",
                generic_add: "dragonstone_runtime_add",
                generic_sub: "dragonstone_runtime_sub",
                generic_mul: "dragonstone_runtime_mul",
                generic_div: "dragonstone_runtime_div",
                generic_mod: "dragonstone_runtime_mod",
                generic_negate: "dragonstone_runtime_negate",
                generic_shl: "dragonstone_runtime_shl",
                generic_shr: "dragonstone_runtime_shr",
                generic_pow: "dragonstone_runtime_pow",
                generic_floor_div: "dragonstone_runtime_floor_div",
                generic_cmp: "dragonstone_runtime_cmp",
                to_string: "dragonstone_runtime_to_string",
                bag_constructor: "dragonstone_runtime_bag_constructor",
                type_of: "dragonstone_runtime_typeof",
                ivar_get: "dragonstone_runtime_ivar_get",
                ivar_set: "dragonstone_runtime_ivar_set",
                argv_get: "dragonstone_runtime_argv",
                argv_set: "dragonstone_runtime_set_argv",
                stdout_get: "dragonstone_runtime_stdout",
                stderr_get: "dragonstone_runtime_stderr",
                stdin_get: "dragonstone_runtime_stdin",
                argc_get: "dragonstone_runtime_argc",
                argf_get: "dragonstone_runtime_argf",
                root_self: "dragonstone_runtime_root_self",
                singleton_define: "dragonstone_runtime_define_singleton_method",
                define_class: "dragonstone_runtime_define_class",
                set_superclass: "dragonstone_runtime_set_superclass",
                define_module: "dragonstone_runtime_define_module",
                define_method: "dragonstone_runtime_define_method",
                define_enum_member: "dragonstone_runtime_define_enum_member",
                push_handler: "dragonstone_runtime_push_exception_frame",
                pop_handler: "dragonstone_runtime_pop_exception_frame",
                get_exception: "dragonstone_runtime_get_exception",
                extend_container: "dragonstone_runtime_extend_container",
                gt: "dragonstone_runtime_gt",
                lt: "dragonstone_runtime_lt",
                gte: "dragonstone_runtime_gte",
                lte: "dragonstone_runtime_lte",
                eq: "dragonstone_runtime_eq",
                ne: "dragonstone_runtime_ne",
                is_truthy: "dragonstone_runtime_is_truthy",
                debug_accum: "dragonstone_runtime_debug_accum",
                debug_flush: "dragonstone_runtime_debug_flush",
              )
            end

            def generate(io : IO)
              collect_strings
              collect_globals
              collect_functions

              @namespace_stack.clear

              # register_missing_functions(@program.ast.statements)

              @namespace_stack.clear
              @class_name_occurrences.clear

              prepare_runtime_literals
              emit_string_constants(io)
              emit_globals(io)

              emit_runtime_types(io)
              declare_runtime(io)
              emit_functions(io)
              emit_entrypoint(io)

              @pending_blocks.each do |block_code|
                io << block_code
              end

              emit_pending_strings(io)
            end

            private class FunctionContext
              getter io : IO
              getter return_type : String
              getter locals : Hash(String, NamedTuple(ptr: String, type: String, heap: Bool))
              getter ensure_stack : Array(Array(AST::Node))
              getter postamble : String::Builder
              getter with_stack : Array(ValueRef)
              getter loop_stack : Array(NamedTuple(exit: String, next: String, redo: String))
              getter retry_stack : Array(String)
              getter alloca_buffer : String::Builder

              property block_slot : NamedTuple(ptr: String, type: String)?
              property callable_name : String?
              property parameter_names : Array(String)

              def initialize(@io : IO, @return_type : String)
                @next_reg = 0
                @next_label = 0
                @locals = {} of String => NamedTuple(ptr: String, type: String, heap: Bool)
                @ensure_stack = [] of Array(AST::Node)
                @postamble = String::Builder.new
                @with_stack = [] of ValueRef
                @loop_stack = [] of NamedTuple(exit: String, next: String, redo: String)
                @retry_stack = [] of String
                @alloca_buffer = String::Builder.new
                @block_slot = nil
                @callable_name = nil
                @parameter_names = [] of String
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

            private def collect_globals
              @namespace_stack.clear
              @program.ast.statements.each do |stmt|
                collect_globals_from(stmt)
              end
              @namespace_stack.clear
            end

            private def shared_container_variable_name?(name : String) : Bool
              name.starts_with?("__ds_cvar_") || name.starts_with?("__ds_mvar_")
            end

            private def collect_globals_from(node : AST::Node)
              case node
              when AST::ModuleDefinition, AST::ClassDefinition
                full_name = qualify_name(node.name)
                @globals << full_name

                with_namespace(node.name) do
                  node.body.each do |stmt|
                    if stmt.is_a?(AST::Assignment)
                      full_name = qualify_name(stmt.name)
                      @globals << full_name
                    end
                    collect_globals_from(stmt)
                  end
                end
              when AST::StructDefinition
                with_namespace(node.name) do
                  node.body.each { |stmt| collect_globals_from(stmt) }
                end
              when AST::EnumDefinition
                full_name = qualify_name(node.name)
                @globals << full_name
              when AST::FunctionDef
                node.body.each { |stmt| collect_globals_from(stmt) }
              when AST::FunctionLiteral
                node.body.each { |stmt| collect_globals_from(stmt) }
              when AST::ParaLiteral
                node.body.each { |stmt| collect_globals_from(stmt) }
              when AST::BlockLiteral
                node.body.each { |stmt| collect_globals_from(stmt) }
              when AST::WithExpression
                collect_globals_from(node.receiver)
                node.body.each { |stmt| collect_globals_from(stmt) }
              when AST::IfStatement
                collect_globals_from(node.condition)
                node.then_block.each { |stmt| collect_globals_from(stmt) }
                node.elsif_blocks.each do |clause|
                  collect_globals_from(clause.condition)
                  clause.block.each { |stmt| collect_globals_from(stmt) }
                end
                node.else_block.try(&.each { |stmt| collect_globals_from(stmt) })
              when AST::UnlessStatement
                collect_globals_from(node.condition)
                node.body.each { |stmt| collect_globals_from(stmt) }
                node.else_block.try(&.each { |stmt| collect_globals_from(stmt) })
              when AST::WhileStatement
                collect_globals_from(node.condition)
                node.block.each { |stmt| collect_globals_from(stmt) }
              when AST::CaseStatement
                node.expression.try { |expr| collect_globals_from(expr) }
                node.when_clauses.each do |clause|
                  clause.conditions.each { |c| collect_globals_from(c) }
                  clause.block.each { |stmt| collect_globals_from(stmt) }
                end
                node.else_block.try(&.each { |stmt| collect_globals_from(stmt) })
              when AST::BeginExpression
                node.body.each { |stmt| collect_globals_from(stmt) }
                node.rescue_clauses.each do |clause|
                  clause.body.each { |stmt| collect_globals_from(stmt) }
                end
                node.else_block.try(&.each { |stmt| collect_globals_from(stmt) })
                node.ensure_block.try(&.each { |stmt| collect_globals_from(stmt) })
              when AST::ReturnStatement
                node.value.try { |expr| collect_globals_from(expr) }
              when AST::DebugEcho
                collect_globals_from(node.expression)
              when AST::Assignment
                if shared_container_variable_name?(node.name)
                  @globals << qualify_name(node.name)
                end
                collect_globals_from(node.value)
              when AST::Variable
                if shared_container_variable_name?(node.name)
                  @globals << qualify_name(node.name)
                end
              when AST::MethodCall
                node.receiver.try { |recv| collect_globals_from(recv) }
                node.arguments.each { |arg| collect_globals_from(arg) }
              when AST::SuperCall
                node.arguments.each { |arg| collect_globals_from(arg) }
              when AST::BinaryOp
                collect_globals_from(node.left)
                collect_globals_from(node.right)
              when AST::UnaryOp
                collect_globals_from(node.operand)
              when AST::ArrayLiteral
                node.elements.each { |e| collect_globals_from(e) }
              when AST::TupleLiteral
                node.elements.each { |e| collect_globals_from(e) }
              when AST::NamedTupleLiteral
                node.entries.each { |e| collect_globals_from(e.value) }
              when AST::MapLiteral
                node.entries.each do |(k, v)|
                  collect_globals_from(k)
                  collect_globals_from(v)
                end
              when AST::IndexAccess
                collect_globals_from(node.object)
                collect_globals_from(node.index)
              when AST::IndexAssignment
                collect_globals_from(node.object)
                collect_globals_from(node.index)
                collect_globals_from(node.value)
              when AST::AttributeAssignment
                collect_globals_from(node.receiver)
                collect_globals_from(node.value)
              else
                # Recurse if container.
              end
            end

            private def mangle_global_name(name : String) : String
              "ds_global_#{name.gsub("::", "_").gsub(/[^a-zA-Z0-9_]/) { |m| "_#{m[0].ord}_" }}"
            end

            private def emit_globals(io : IO)
              @globals.each do |name|
                global_symbol = mangle_global_name(name)
                io << "@\"#{global_symbol}\" = private global i8* null\n"
              end
              io << "\n" unless @globals.empty?
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
                base_full_name = qualify_name(node.name)
                count = (@struct_name_occurrences[base_full_name] += 1)
                unique_ns = count > 1 ? "#{node.name}_#{count}" : node.name
                full_name = qualify_name(unique_ns)

                @struct_unique_names[node] = unique_ns
                struct_fields_for(full_name)
                struct_field_map_for(full_name)
                @struct_alias_map[node.name] = full_name
                @struct_alias_map[base_full_name] = full_name

                @struct_stack << full_name
                with_namespace(unique_ns) do
                  node.body.each { |stmt| register_struct_types(stmt) }
                end
                @struct_stack.pop
              when AST::ModuleDefinition, AST::ClassDefinition
                with_namespace(node.name) do
                  node.body.each { |stmt| register_struct_types(stmt) }
                end
              when AST::AccessorMacro
                if current = @struct_stack.last?
                  if node.kind == :property || node.kind == :getter
                    fields = struct_fields_for(current)
                    indices = struct_field_map_for(current)
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

            private def collect_strings_from_node(node : AST::Node)
              case node
              when AST::Literal
                if value = node.value
                  case value
                  when String
                    intern_string(value)
                  when ::Char, ::Symbol
                    intern_string(value.to_s)
                  when SymbolValue
                    intern_string(value.name)
                  end
                end
              when AST::TupleLiteral
                node.elements.each { |elem| collect_strings_from_node(elem) }
              when AST::NamedTupleLiteral
                node.entries.each do |entry|
                  intern_string(entry.name)
                  collect_strings_from_node(entry.value)
                end
              when AST::DebugEcho
                intern_string("%s")
                intern_string("#{node.expression.to_source} # -> ")
                collect_strings_from_node(node.expression)
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
                intern_string(node.name)
                collect_strings_from_node(node.receiver.not_nil!) if node.receiver
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
              when AST::BagConstructor
                intern_string(node.element_type.to_source)
              when AST::InstanceVariable
                intern_string(node.name)
              when AST::InstanceVariableAssignment
                intern_string(node.name)
                collect_strings_from_node(node.value)
              when AST::InstanceVariableDeclaration
                intern_string(node.name)
              when AST::AttributeAssignment
                intern_string(node.name)
                collect_strings_from_node(node.receiver)
                collect_strings_from_node(node.value)
              when AST::BlockLiteral
                node.body.each { |stmt| collect_strings_from_node(stmt) }
              when AST::ParaLiteral
                node.body.each { |stmt| collect_strings_from_node(stmt) }
              when AST::BeginExpression
                node.body.each { |stmt| collect_strings_from_node(stmt) }
                node.rescue_clauses.each { |clause| collect_strings_from_node(clause) }
                if block = node.else_block
                  block.each { |stmt| collect_strings_from_node(stmt) }
                end
                if block = node.ensure_block
                  block.each { |stmt| collect_strings_from_node(stmt) }
                end
              when AST::RescueClause
                node.body.each { |stmt| collect_strings_from_node(stmt) }
              when AST::ConstantPath
                node.names.each { |segment| intern_string(segment) }
              when AST::ConstantDeclaration
                intern_string(qualify_name(node.name))
                collect_strings_from_node(node.value)
              when AST::EnumDefinition
                intern_string(qualify_name(node.name))
                node.members.each do |member|
                  intern_string(member.name)
                  if val = member.value
                    collect_strings_from_node(val)
                  end
                end
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
              when AST::RaiseExpression
                node.expression.try { |expr| collect_strings_from_node(expr) }
              when AST::InterpolatedString
                node.normalized_parts.each do |type, content|
                  if type == :string
                    intern_string(content.as(String))
                  elsif type == :expression
                    collect_strings_from_node(interpolation_expression(content))
                  end
                end
              when AST::AliasDefinition
                # Skip.
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
              when AST::FunctionDef, AST::FunctionLiteral, AST::BlockLiteral, AST::ParaLiteral
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
              @class_name_occurrences.clear

              @program.ast.statements.each do |stmt|
                collect_functions_from(stmt)
              end

              @namespace_stack.clear
            end

            private def collect_functions_from(node : AST::Node)
              case node
              when AST::StructDefinition
                struct_name = @struct_unique_names[node]? || node.name
                with_namespace(struct_name) do
                  node.body.each { |stmt| collect_functions_from(stmt) }
                end
              when AST::ClassDefinition, AST::ModuleDefinition
                full_name = qualify_name(node.name)

                @class_name_occurrences[full_name] += 1

                count = @class_name_occurrences[full_name]

                unique_ns = count > 1 ? "#{node.name}_#{count}" : node.name

                with_namespace(unique_ns) do
                  node.body.each { |stmt| collect_functions_from(stmt) }
                end
              when AST::FunctionDef
                register_function(node)
              end
            end

            private def register_function(func : AST::FunctionDef)
              base_name = if @namespace_stack.empty?
                            func.name == "main" ? "__dragonstone_user_main" : func.name
                          else
                            type_name = @namespace_stack.join("::")
                            struct_method_symbol(type_name, func.name)
                          end

              @function_namespaces[func] = @namespace_stack.dup

              receiver_type = nil
              if func.receiver
                receiver_type = "i8*"
                @function_receivers[func] = receiver_type
              elsif !@namespace_stack.empty?
                current_scope = @namespace_stack.join("::")
                if canonical_struct_name(current_scope)
                  receiver_type = llvm_struct_name(current_scope)
                  @function_receivers[func] = receiver_type
                else
                  receiver_type = "i8*"
                  @function_receivers[func] = receiver_type
                end
              end

              requires_block = function_body_contains_yield?(func.body)

              param_types = func.typed_parameters.map { |param| llvm_param_type(param.type) }
              param_typed = func.typed_parameters.map { |param| !param.type.nil? }

              if receiver_type
                param_types.unshift(receiver_type)
                param_typed.unshift(true)
              end

              if requires_block
                param_types << "i8*"
                param_typed << true
              end

              mangled_name = mangle_function_name(base_name, param_types)

              @function_names[func] = mangled_name
              @function_requires_block[mangled_name] = requires_block
              unless @function_overloads[base_name].includes?(mangled_name)
                @function_overloads[base_name] << mangled_name
              end

              signature = FunctionSignature.new(
                return_type: llvm_type_of(func.return_type),
                param_types: param_types,
                param_typed: param_typed
              )

              @function_signatures[mangled_name] = signature
              @function_defs[mangled_name] = func
            end

            # private def register_missing_functions(nodes : Array(AST::Node))
            #     nodes.each do |node|
            #         case node
            #         when AST::FunctionDef
            #             register_function(node)
            #         when AST::ModuleDefinition, AST::ClassDefinition, AST::StructDefinition
            #             with_namespace(node.name) do
            #                 register_missing_functions(node.body)
            #             end
            #         end
            #     end
            # end

            private def prepare_runtime_literals
              return if @runtime_literals_preregistered
              intern_string("%lld\n")
              intern_string("%g\n")
              intern_string("true")
              intern_string("false")
              intern_string("nil")
              intern_string("Division by zero")
              @runtime_literals_preregistered = true
            end

            private def emit_string_constants(io : IO)
              @string_order.each do |literal|
                entry = @string_literals[literal]
                size = entry[:length] + 1
                io << "@\"#{entry[:name]}\" = private unnamed_addr constant [#{size} x i8] c\"#{entry[:escaped]}\\00\"\n"
              end
              io << "\n" unless @string_order.empty?
            end

            private def emit_pending_strings(io : IO)
              @pending_strings.each do |literal|
                entry = @string_literals[literal]
                size = entry[:length] + 1
                io << "@\"#{entry[:name]}\" = private unnamed_addr constant [#{size} x i8] c\"#{entry[:escaped]}\\00\"\n"
              end
              io << "\n" unless @pending_strings.empty?
            end

            private def emit_function_inline(func : AST::FunctionDef)
              name_key = @function_names[func]? || begin
                register_function(func)
                @function_names[func]
              end
              return if @emitted_functions.includes?(name_key)

              builder = String::Builder.new
              emit_function(builder, func)
              builder << "\n"
              @pending_blocks << builder.to_s
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
              io << "declare i8* @#{@runtime[:box_bool]}(i32)\n"
              io << "declare i8* @#{@runtime[:box_string]}(i8*)\n"
              io << "declare i8* @#{@runtime[:box_float]}(double)\n"
              io << "declare i32 @#{@runtime[:unbox_i32]}(i8*)\n"
              io << "declare i64 @#{@runtime[:unbox_i64]}(i8*)\n"
              io << "declare i32 @#{@runtime[:unbox_bool]}(i8*)\n"
              io << "declare double @#{@runtime[:unbox_float]}(i8*)\n"
              io << "declare void @#{@runtime[:argv_set]}(i64, i8**)\n"
              io << "declare i8* @#{@runtime[:argv_get]}()\n"
              io << "declare i8* @#{@runtime[:stdout_get]}()\n"
              io << "declare i8* @#{@runtime[:stderr_get]}()\n"
              io << "declare i8* @#{@runtime[:stdin_get]}()\n"
              io << "declare i8* @#{@runtime[:argc_get]}()\n"
              io << "declare i8* @#{@runtime[:argf_get]}()\n"
              io << "declare i8* @#{@runtime[:array_literal]}(i64, i8**)\n"
              io << "declare i8* @#{@runtime[:map_literal]}(i64, i8**, i8**)\n"
              io << "declare i8* @#{@runtime[:tuple_literal]}(i64, i8**)\n"
              io << "declare i8* @#{@runtime[:named_tuple_literal]}(i64, i8**, i8**)\n"
              io << "declare i8* @#{@runtime[:block_literal]}(i8* (i8*, i64, i8**)*, i8*)\n"
              io << "declare i8* @#{@runtime[:block_invoke]}(i8*, i64, i8**)\n"
              io << "declare i8* @#{@runtime[:method_invoke]}(i8*, i8*, i64, i8**, i8*)\n"
              io << "declare i8* @#{@runtime[:super_invoke]}(i8*, i8*, i8*, i64, i8**, i8*)\n"
              io << "declare i8** @#{@runtime[:block_env_alloc]}(i64)\n"
              io << "declare i8* @#{@runtime[:constant_lookup]}(i64, i8**)\n"
              io << "declare void @#{@runtime[:rescue_placeholder]}()\n\n"
              io << "declare i8* @#{@runtime[:constant_define]}(i8*, i8*)\n"
              io << "declare i8* @#{@runtime[:index_get]}(i8*, i8*)\n"
              io << "declare i8* @#{@runtime[:index_set]}(i8*, i8*, i8*)\n"
              io << "declare i1 @#{@runtime[:case_compare]}(i8*, i8*)\n"
              io << "declare void @#{@runtime[:yield_missing_block]}()\n"
              io << "declare i8* @#{@runtime[:display_value]}(i8*)\n"
              io << "declare i8* @#{@runtime[:to_string]}(i8*)\n"
              io << "declare void @#{@runtime[:debug_accum]}(i8*, i8*)\n"
              io << "declare void @#{@runtime[:debug_flush]}()\n"
              io << "declare i8* @#{@runtime[:type_of]}(i8*)\n"
              io << "declare i8* @#{@runtime[:ivar_get]}(i8*, i8*)\n"
              io << "declare i8* @#{@runtime[:ivar_set]}(i8*, i8*, i8*)\n"
              io << "declare i8* @#{@runtime[:root_self]}()\n"
              io << "declare void @#{@runtime[:singleton_define]}(i8*, i8*, i8*)\n"
              io << "declare i8* @#{@runtime[:interpolated_string]}(i64, i8**)\n"
              io << "declare void @#{@runtime[:raise]}(i8*)\n"
              io << "declare i8* @#{@runtime[:range_literal]}(i8*, i8*, i1)\n"
              io << "declare i8* @malloc(i64)\n\n"
              io << "declare i8* @#{@runtime[:box_struct]}(i8*, i64)\n"
              io << "declare i8* @#{@runtime[:unbox_struct]}(i8*)\n"
              io << "declare i8* @#{@runtime[:array_push]}(i8*, i8*)\n"
              io << "declare i8* @#{@runtime[:generic_add]}(i8*, i8*)\n"
              io << "declare i8* @#{@runtime[:generic_sub]}(i8*, i8*)\n"
              io << "declare i8* @#{@runtime[:generic_mul]}(i8*, i8*)\n"
              io << "declare i8* @#{@runtime[:generic_div]}(i8*, i8*)\n"
              io << "declare i8* @#{@runtime[:generic_mod]}(i8*, i8*)\n"
              io << "declare i8* @#{@runtime[:generic_negate]}(i8*)\n"
              io << "declare i8* @#{@runtime[:generic_shl]}(i8*, i8*)\n"
              io << "declare i8* @#{@runtime[:generic_shr]}(i8*, i8*)\n"
              io << "declare i8* @#{@runtime[:generic_pow]}(i8*, i8*)\n"
              io << "declare i8* @#{@runtime[:generic_floor_div]}(i8*, i8*)\n"
              io << "declare i8* @#{@runtime[:generic_cmp]}(i8*, i8*)\n"
              io << "declare i8* @#{@runtime[:bag_constructor]}(i8*)\n"
              io << "declare i8* @#{@runtime[:define_class]}(i8*)\n"
              io << "declare void @#{@runtime[:set_superclass]}(i8*, i8*)\n"
              io << "declare i8* @#{@runtime[:define_module]}(i8*)\n"
              io << "declare void @#{@runtime[:define_method]}(i8*, i8*, i8*, i32)\n"
              io << "declare void @#{@runtime[:define_enum_member]}(i8*, i8*, i64)\n"
              io << "declare void @#{@runtime[:push_handler]}(i8*)\n"
              io << "declare void @#{@runtime[:pop_handler]}()\n"
              io << "declare i8* @#{@runtime[:get_exception]}()\n"
              io << "declare void @#{@runtime[:extend_container]}(i8*, i8*)\n"
              io << "declare i8* @#{@runtime[:gt]}(i8*, i8*)\n"
              io << "declare i8* @#{@runtime[:lt]}(i8*, i8*)\n"
              io << "declare i8* @#{@runtime[:gte]}(i8*, i8*)\n"
              io << "declare i8* @#{@runtime[:lte]}(i8*, i8*)\n"
              io << "declare i8* @#{@runtime[:eq]}(i8*, i8*)\n"
              io << "declare i8* @#{@runtime[:ne]}(i8*, i8*)\n"
              io << "declare i1 @#{@runtime[:is_truthy]}(i8*)\n"
              {% if flag?(:windows) %}
                io << "declare i32 @_setjmp(i8*, i8*) returns_twice\n"
              {% else %}
                io << "declare i32 @setjmp(i8*) returns_twice\n"
              {% end %}
            end

            private def emit_functions(io : IO)
              @function_defs.values.each do |func|
                emit_function(io, func) unless @emitted_functions.includes?(@function_names[func])
                io << "\n" unless @emitted_functions.includes?(@function_names[func])
              end
            end

            private def emit_function(io : IO, func : AST::FunctionDef)
              name_key = @function_names[func]
              return if @emitted_functions.includes?(name_key)
              return_type = llvm_type_of(func.return_type)

              body_io = String::Builder.new
              ctx = FunctionContext.new(body_io, return_type)
              ctx.callable_name = func.name
              ctx.parameter_names = func.typed_parameters.map(&.name)

              @namespace_stack = @function_namespaces[func].dup
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

              param_specs.each do |spec|
                slot = "%#{ctx.fresh("param")}"
                ctx.alloca_buffer << "  #{slot} = alloca #{spec[:type]}\n"

                incoming_val = value_ref(spec[:type], spec[:source])

                if spec[:name] == "self" && spec[:type] != "i8*"
                  ctx.io << "  store #{spec[:type]} #{spec[:source]}, #{spec[:type]}* #{slot}\n"
                else
                  converted = ensure_value_type(ctx, incoming_val, spec[:type])
                  ctx.io << "  store #{spec[:type]} #{converted[:ref]}, #{spec[:type]}* #{slot}\n"
                end

                ctx.locals[spec[:name]] = {ptr: slot, type: spec[:type], heap: false}

                if spec[:name] == "__block"
                  ctx.block_slot = {ptr: slot, type: spec[:type]}
                end

                is_ivar = spec[:name].starts_with?("@")
                target_ivar_name = is_ivar ? spec[:name] : "@#{spec[:name]}"

                if (is_ivar || func.name == "initialize") && ctx.locals.has_key?("self")
                  receiver = ctx.locals["self"]
                  if receiver[:type] == "i8*"
                    self_ref = load_local(ctx, "self")
                    val_ref = load_local(ctx, spec[:name])
                    boxed_val = box_value(ctx, val_ref)

                    name_ptr = materialize_string_pointer(ctx, target_ivar_name)

                    runtime_call(ctx, "i8*", @runtime[:ivar_set], [
                      {type: "i8*", ref: self_ref[:ref]},
                      {type: "i8*", ref: name_ptr},
                      {type: "i8*", ref: boxed_val[:ref]},
                    ])
                  end
                end
              end

              terminated = generate_block_with_implicit_return(ctx, func.body)

              emit_default_return(ctx) unless terminated
              emit_postamble(ctx)

              io << "define #{return_type} @\"#{llvm_name}\"(#{params.join(", ")}) {\n"
              io << "entry:\n"
              io << ctx.alloca_buffer.to_s
              io << body_io.to_s
              io << "}\n"

              @emitted_functions << name_key
            end

            private def emit_entrypoint(io : IO)
              body_io = String::Builder.new
              ctx = FunctionContext.new(body_io, "i32")

              @namespace_stack.clear

              top_level = @program.ast.statements.reject { |stmt|
                stmt.is_a?(AST::FunctionDef) && stmt.receiver.nil?
              }

              argc_reg = ctx.fresh("argc64")
              ctx.io << "  %#{argc_reg} = zext i32 %argc to i64\n"
              ctx.io << "  call void @#{@runtime[:argv_set]}(i64 %#{argc_reg}, i8** %argv)\n"

              terminated = generate_block(ctx, top_level)

              unless terminated
                ctx.io << "  call void @#{@runtime[:debug_flush]}()\n"
                ctx.io << "  ret i32 0\n"
              end

              emit_postamble(ctx)

              io << "define i32 @main(i32 %argc, i8** %argv) {\n"
              io << "entry:\n"
              io << ctx.alloca_buffer.to_s
              io << body_io.to_s
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

            private def expression_statement?(stmt : AST::Node) : Bool
              case stmt
	              when AST::Literal,
	                   AST::Variable,
	                   AST::ArgvExpression,
	                   AST::ArgcExpression,
	                   AST::ArgfExpression,
	                   AST::StdoutExpression,
	                   AST::StderrExpression,
	                   AST::StdinExpression,
	                   AST::BinaryOp,
	                   AST::UnaryOp,
	                   AST::MethodCall,
	                   AST::SuperCall,
	                   AST::ArrayLiteral,
                   AST::BagConstructor,
                   AST::MapLiteral,
                   AST::TupleLiteral,
                   AST::NamedTupleLiteral,
                   AST::ConstantPath,
                   AST::InterpolatedString,
                   AST::BeginExpression,
                   AST::InstanceVariable,
                   AST::InstanceVariableAssignment,
                   AST::IfStatement,
                   AST::UnlessStatement,
                   AST::CaseStatement,
                   AST::Assignment,
                   AST::AttributeAssignment,
                   AST::IndexAssignment,
                   AST::YieldExpression,
                   AST::DebugEcho
                true
              else
                false
              end
            end

            private def generate_block_with_implicit_return(ctx : FunctionContext, statements : Array(AST::Node)) : Bool
              terminated = false
              statements.each_with_index do |stmt, idx|
                is_last = idx == statements.size - 1

                if is_last && !terminated && ctx.return_type != "void" && expression_statement?(stmt)
                  value = generate_expression(ctx, stmt)
                  value = ensure_value_type(ctx, value, ctx.return_type)
                  emit_ensure_chain(ctx)
                  ctx.io << "  ret #{value[:type]} #{value[:ref]}\n"
                  return true
                end

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
              when AST::SuperCall
                generate_expression(ctx, stmt)
                false
              when AST::DebugEcho
                generate_debug_echo(ctx, stmt)
                false
                # value = generate_expression(ctx, stmt.expression)
                # prefix_str = "#{stmt.expression.to_source} # => "
                # format_ptr = materialize_string_pointer(ctx, "%s")
                # prefix_ptr = materialize_string_pointer(ctx, prefix_str)
                # ctx.io << "  call i32 (i8*, ...) @printf(i8* #{format_ptr}, i8* #{prefix_ptr})\n"
                # emit_echo(ctx, value, inspect: true)
                # false
              when AST::Assignment
                generate_local_assignment(ctx, stmt)
                false
                # value = generate_expression(ctx, stmt.value.as(AST::Node))
                # if type_expr = stmt.type_annotation
                #     target_type = llvm_type_of(type_expr)
                #     value = ensure_value_type(ctx, value, target_type)
                # end
                # if operator = stmt.operator
                #     current = generate_variable_reference(ctx, stmt.name)
                #     value = emit_binary_op(ctx, operator, current, value)
                # end
                # full_name = qualify_name(stmt.name)
                # if @globals.includes?(full_name)
                #     boxed = box_value(ctx, value)
                #     global_name = mangle_global_name(full_name)
                #     ctx.io << "  store i8* #{boxed[:ref]}, i8** @\"#{global_name}\"\n"
                # else
                #     store_local(ctx, stmt.name, value)
                # end
                # false
              when AST::ReturnStatement
                generate_return_statement(ctx, stmt)
                # if value_node = stmt.value
                #     value = generate_expression(ctx, value_node)
                #     value = ensure_value_type(ctx, value, ctx.return_type)
                #     emit_ensure_chain(ctx)
                #     ctx.io << "  ret #{value[:type]} #{value[:ref]}\n"
                # else
                #     emit_ensure_chain(ctx)
                #     emit_default_return(ctx)
                # end
                # true
              when AST::BinaryOp
                generate_expression(ctx, stmt)
                false
              when AST::InstanceVariableDeclaration
                false
              when AST::InstanceVariableAssignment
                generate_instance_variable_assignment(ctx, stmt)
                false
              when AST::AttributeAssignment
                generate_attribute_assignment(ctx, stmt)
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
                emit_function_inline(stmt)
                if stmt.receiver
                  receiver_node = stmt.receiver.not_nil!
                  receiver_val = if receiver_node.is_a?(AST::Variable) && receiver_node.name == "self" && !@namespace_stack.empty?
                                   class_name = @namespace_stack.join("::")
                                   original_name = class_name.sub(/_\d+$/, "")
                                   if @globals.includes?(original_name)
                                     global_name = mangle_global_name(original_name)
                                     cls_reg = ctx.fresh("cls")
                                     ctx.io << "  %#{cls_reg} = load i8*, i8** @\"#{global_name}\"\n"
                                     value_ref("i8*", "%#{cls_reg}")
                                   else
                                     raise "Cannot define singleton method #{stmt.name} on self without a class binding"
                                   end
                                 else
                                   ensure_pointer(ctx, generate_expression(ctx, receiver_node))
                                 end
                  method_name_ptr = materialize_string_pointer(ctx, stmt.name)
                  llvm_name = @function_names[stmt]
                  wrapper, wrapper_sig = generate_method_wrapper(llvm_name)
                  func_ptr = ctx.fresh("func")
                  ctx.io << "  %#{func_ptr} = bitcast #{wrapper_sig} @\"#{wrapper}\" to i8*\n"
                  ctx.io << "  call void @#{@runtime[:singleton_define]}(i8* #{receiver_val[:ref]}, i8* #{method_name_ptr}, i8* %#{func_ptr})\n"
                elsif !@namespace_stack.empty?
                  class_name = @namespace_stack.join("::")
                  original_name = class_name.sub(/_\d+$/, "")

                  if @globals.includes?(original_name)
                    global_name = mangle_global_name(original_name)
                    cls_reg = ctx.fresh("cls")
                    ctx.io << "  %#{cls_reg} = load i8*, i8** @\"#{global_name}\"\n"
                    method_name_ptr = materialize_string_pointer(ctx, stmt.name)
                    llvm_name = @function_names[stmt]
                    requires_block = @function_requires_block[llvm_name]? || false
                    wrapper, wrapper_sig = generate_method_wrapper(llvm_name)
                    func_ptr = ctx.fresh("func")
                    ctx.io << "  %#{func_ptr} = bitcast #{wrapper_sig} @\"#{wrapper}\" to i8*\n"
                    ctx.io << "  call void @#{@runtime[:define_method]}(i8* %#{cls_reg}, i8* #{method_name_ptr}, i8* %#{func_ptr}, i32 #{requires_block ? 1 : 0})\n"
                  end
                end
                false
              when AST::ArrayLiteral
                generate_array_literal(ctx, stmt)
                false
              when AST::BagConstructor
                generate_bag_constructor(ctx, stmt)
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
              when AST::EnumDefinition
                generate_enum_definition(ctx, stmt)
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
              when AST::ExtendStatement
                generate_extend_statement(ctx, stmt)
                false
              when AST::CaseStatement
                generate_case_expression(ctx, stmt)
                false
              when AST::YieldExpression
                generate_yield_expression(ctx, stmt)
                false
              when AST::WithExpression
                generate_with_expression(ctx, stmt)
              when AST::RaiseExpression
                generate_raise_expression(ctx, stmt)
                true
              when AST::BreakStatement
                generate_break_statement(ctx, stmt)
              when AST::NextStatement
                generate_next_statement(ctx, stmt)
              when AST::RedoStatement
                generate_redo_statement(ctx, stmt)
              when AST::RetryStatement
                generate_retry_statement(ctx, stmt)
              when AST::AliasDefinition
                if stmt.type_expression.is_a?(AST::SimpleTypeExpression)
                  segments = stmt.type_expression.as(AST::SimpleTypeExpression).name.split("::")
                  resolved = emit_constant_lookup(ctx, segments)
                  cond = ctx.fresh("alias_present")
                  define_label = ctx.fresh_label("alias_define")
                  merge_label = ctx.fresh_label("alias_merge")

                  ctx.io << "  %#{cond} = icmp ne i8* #{resolved[:ref]}, null\n"
                  ctx.io << "  br i1 %#{cond}, label %#{define_label}, label %#{merge_label}\n"
                  ctx.io << "#{define_label}:\n"
                  name_ptr = materialize_string_pointer(ctx, qualify_name(stmt.name))
                  runtime_call(ctx, "i8*", @runtime[:constant_define], [
                    {type: "i8*", ref: name_ptr},
                    {type: "i8*", ref: resolved[:ref]},
                  ])
                  ctx.io << "  br label %#{merge_label}\n"
                  ctx.io << "#{merge_label}:\n"
                end
                false
              when AST::AccessorMacro
                generate_accessor_macro(ctx, stmt)
                false
              else
                false
              end
            end

            private def generate_accessor_macro(ctx : FunctionContext, node : AST::AccessorMacro)
              return if @namespace_stack.empty?
              class_name = @namespace_stack.join("::")

              [:getter, :property].each do |k|
                if node.kind == k
                  node.entries.each { |entry| generate_synthetic_getter(ctx, class_name, entry.name, entry.type_annotation) }
                end
              end

              [:setter, :property].each do |k|
                if node.kind == k
                  node.entries.each { |entry| generate_synthetic_setter(ctx, class_name, entry.name, entry.type_annotation) }
                end
              end
            end

            private def generate_synthetic_getter(ctx : FunctionContext, class_name : String, name : String, type_expr : AST::TypeExpression?)
              method_name = name
              ivar_name = "@#{name}"
              mangled = mangle_global_name("#{class_name}_#{method_name}")

              return_type = type_expr ? llvm_type_of(type_expr) : "i8*"

              @function_signatures[mangled] = {return_type: "i8*", param_types: ["i8*"], param_typed: [true]}

              body = String::Builder.new
              fctx = FunctionContext.new(body, "i8*")

              self_slot = "%#{fctx.fresh("self_arg")}"
              fctx.alloca_buffer << "  #{self_slot} = alloca i8*\n"
              body << "  store i8* %self, i8** #{self_slot}\n"

              self_val = fctx.fresh("load_self")
              body << "  %#{self_val} = load i8*, i8** #{self_slot}\n"

              name_ptr = materialize_string_pointer(fctx, ivar_name)
              call_reg = fctx.fresh("ivar")
              body << "  %#{call_reg} = call i8* @#{@runtime[:ivar_get]}(i8* %#{self_val}, i8* #{name_ptr})\n"
              body << "  ret i8* %#{call_reg}\n"

              func_code = String.build do |io|
                io << "define i8* @\"#{mangled}\"(i8* %self) {\n"
                io << "entry:\n"
                io << fctx.alloca_buffer.to_s
                io << body.to_s
                io << "}\n\n"
              end
              @pending_blocks << func_code

              emit_define_method_call(ctx, class_name, method_name, mangled, "i8* (i8*)")
            end

            private def generate_synthetic_setter(ctx : FunctionContext, class_name : String, name : String, type_expr : AST::TypeExpression?)
              method_name = "#{name}="
              ivar_name = "@#{name}"
              mangled = mangle_global_name("#{class_name}_#{method_name}")

              @function_signatures[mangled] = {return_type: "i8*", param_types: ["i8*", "i8*"], param_typed: [true, true]}

              body = String::Builder.new
              fctx = FunctionContext.new(body, "i8*")

              self_slot = "%#{fctx.fresh("self_arg")}"
              val_slot = "%#{fctx.fresh("val_arg")}"
              fctx.alloca_buffer << "  #{self_slot} = alloca i8*\n"
              fctx.alloca_buffer << "  #{val_slot} = alloca i8*\n"
              body << "  store i8* %self, i8** #{self_slot}\n"
              body << "  store i8* %value, i8** #{val_slot}\n"

              self_val = fctx.fresh("load_self")
              body << "  %#{self_val} = load i8*, i8** #{self_slot}\n"
              val_val = fctx.fresh("load_val")
              body << "  %#{val_val} = load i8*, i8** #{val_slot}\n"

              name_ptr = materialize_string_pointer(fctx, ivar_name)
              call_reg = fctx.fresh("ivar")
              body << "  %#{call_reg} = call i8* @#{@runtime[:ivar_set]}(i8* %#{self_val}, i8* #{name_ptr}, i8* %#{val_val})\n"
              body << "  ret i8* %#{call_reg}\n"

              func_code = String.build do |io|
                io << "define i8* @\"#{mangled}\"(i8* %self, i8* %value) {\n"
                io << "entry:\n"
                io << fctx.alloca_buffer.to_s
                io << body.to_s
                io << "}\n\n"
              end
              @pending_blocks << func_code

              emit_define_method_call(ctx, class_name, method_name, mangled, "i8* (i8*, i8*)")
            end

            private def generate_method_wrapper(llvm_name : String) : Tuple(String, String)
              wrapper_name = "#{llvm_name}_wrapper"

              signature = @function_signatures[llvm_name]
              param_types = signature[:param_types]

              func_def = @function_defs[llvm_name]?
              has_receiver = func_def ? @function_receivers.has_key?(func_def) : true

              explicit_indices = [] of Int32
              param_types.each_with_index do |_, i|
                if has_receiver && i == 0
                  # Skip.
                else
                  explicit_indices << i
                end
              end

              wrapper_params = ["i8* %self"]
              explicit_indices.each_with_index do |_, i|
                wrapper_params << "i8* %arg#{i}"
              end

              wrapper_sig_str = "i8* (#{wrapper_params.map { "i8*" }.join(", ")})*"

              if @emitted_functions.includes?(wrapper_name)
                return {wrapper_name, wrapper_sig_str}
              end

              body = String::Builder.new
              ctx = FunctionContext.new(body, "i8*")

              call_args = [] of String

              param_types.each_with_index do |expected_type, i|
                if has_receiver && i == 0
                  val_ref = value_ref("i8*", "%self")
                  converted = ensure_value_type(ctx, val_ref, expected_type)
                  call_args << "#{converted[:type]} #{converted[:ref]}"
                else
                  wrapper_arg_idx = has_receiver ? i - 1 : i
                  val_ref = value_ref("i8*", "%arg#{wrapper_arg_idx}")
                  converted = ensure_value_type(ctx, val_ref, expected_type)
                  call_args << "#{converted[:type]} #{converted[:ref]}"
                end
              end

              ret_type = signature[:return_type]
              if ret_type == "void"
                body << "  call void @\"#{llvm_name}\"(#{call_args.join(", ")})\n"
                body << "  ret i8* null\n"
              else
                res = ctx.fresh("res")
                body << "  %#{res} = call #{ret_type} @\"#{llvm_name}\"(#{call_args.join(", ")})\n"
                res_ref = value_ref(ret_type, "%#{res}")
                boxed = box_value(ctx, res_ref)
                body << "  ret i8* #{boxed[:ref]}\n"
              end

              io = String::Builder.new
              io << "define i8* @\"#{wrapper_name}\"(#{wrapper_params.join(", ")}) {\n"
              io << "entry:\n"
              io << ctx.alloca_buffer.to_s
              io << body.to_s
              io << "}\n\n"

              @pending_blocks << io.to_s
              @emitted_functions << wrapper_name
              {wrapper_name, wrapper_sig_str}
            end

            private def emit_define_method_call(ctx : FunctionContext, class_name : String, method_name : String, llvm_func : String, cast_type : String)
              original_name = class_name.sub(/_\d+$/, "")

              if @globals.includes?(original_name)
                global_name = mangle_global_name(original_name)
                cls_reg = ctx.fresh("cls")
                ctx.io << "  %#{cls_reg} = load i8*, i8** @\"#{global_name}\"\n"
                wrapper, wrapper_sig = generate_method_wrapper(llvm_func)
                name_ptr = materialize_string_pointer(ctx, method_name)
                func_ptr = ctx.fresh("func")
                requires_block = @function_requires_block[llvm_func]? || false
                ctx.io << "  %#{func_ptr} = bitcast #{wrapper_sig} @\"#{wrapper}\" to i8*\n"
                ctx.io << "  call void @#{@runtime[:define_method]}(i8* %#{cls_reg}, i8* #{name_ptr}, i8* %#{func_ptr}, i32 #{requires_block ? 1 : 0})\n"
              end
            end

            private def generate_return_statement(ctx : FunctionContext, stmt : AST::ReturnStatement) : Bool
              if value_node = stmt.value
                value = generate_expression(ctx, value_node)

                if ctx.return_type == "i8*" && value[:type] != "i8*"
                  value = box_value(ctx, value)
                elsif ctx.return_type == "i8*" && value[:ref] == "null"
                  # Nil.
                end

                value = ensure_value_type(ctx, value, ctx.return_type)
                emit_ensure_chain(ctx)
                ctx.io << "  call void @#{@runtime[:debug_flush]}()\n"
                ctx.io << "  ret #{value[:type]} #{value[:ref]}\n"
              else
                emit_ensure_chain(ctx)
                ctx.io << "  call void @#{@runtime[:debug_flush]}()\n"
                emit_default_return(ctx)
              end
              true
            end

            private def generate_expression(ctx : FunctionContext, node : AST::Node) : ValueRef
              case node
              when AST::Literal
                generate_literal(ctx, node)
              when AST::Variable
                generate_variable_reference(ctx, node.name)
              when AST::ArgvExpression
                runtime_call(ctx, "i8*", @runtime[:argv_get], [] of CallArg)
              when AST::ArgcExpression
                runtime_call(ctx, "i8*", @runtime[:argc_get], [] of CallArg)
              when AST::ArgfExpression
                runtime_call(ctx, "i8*", @runtime[:argf_get], [] of CallArg)
              when AST::StdoutExpression
                runtime_call(ctx, "i8*", @runtime[:stdout_get], [] of CallArg)
              when AST::StderrExpression
                runtime_call(ctx, "i8*", @runtime[:stderr_get], [] of CallArg)
              when AST::StdinExpression
                runtime_call(ctx, "i8*", @runtime[:stdin_get], [] of CallArg)
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
                if node.receiver.nil? && node.arguments.empty? && ctx.locals.has_key?(node.name)
                  generate_variable_reference(ctx, node.name)
                else
                  generate_method_call(ctx, node) || raise "Method #{node.name} does not return a value"
                end
              when AST::SuperCall
                generate_super_call(ctx, node)
              when AST::UnaryOp
                generate_unary_expression(ctx, node)
              when AST::ArrayLiteral
                generate_array_literal(ctx, node)
              when AST::BagConstructor
                generate_bag_constructor(ctx, node)
              when AST::MapLiteral
                generate_map_literal(ctx, node)
              when AST::BlockLiteral
                generate_block_literal(ctx, node)
              when AST::ParaLiteral
                generate_para_literal(ctx, node)
              when AST::FunctionLiteral
                generate_function_literal(ctx, node)
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
              when AST::InstanceVariable
                generate_instance_variable(ctx, node)
              when AST::InstanceVariableAssignment
                generate_instance_variable_assignment(ctx, node)
              when AST::AttributeAssignment
                generate_attribute_assignment(ctx, node)
              when AST::CaseStatement
                generate_case_expression(ctx, node)
              when AST::YieldExpression
                generate_yield_expression(ctx, node)
              when AST::RaiseExpression
                generate_raise_expression(ctx, node)
              when AST::IfStatement
                generate_if_expression(ctx, node)
              when AST::UnlessStatement
                generate_unless_expression(ctx, node)
              when AST::ConditionalExpression
                generate_conditional_expression(ctx, node)
              when AST::Assignment
                generate_local_assignment(ctx, node)
              when AST::DebugEcho
                generate_debug_echo(ctx, node)
              else
                raise "Unsupported expression #{node.class}"
              end
            end

            private def generate_conditional_expression(ctx : FunctionContext, node : AST::ConditionalExpression) : ValueRef
              cond_value = ensure_boolean(ctx, generate_expression(ctx, node.condition))
              then_label = ctx.fresh_label("cond_then")
              else_label = ctx.fresh_label("cond_else")
              merge_label = ctx.fresh_label("cond_merge")

              ctx.io << "  br i1 #{cond_value[:ref]}, label %#{then_label}, label %#{else_label}\n"

              ctx.io << "#{then_label}:\n"
              then_val = generate_expression(ctx, node.then_branch)
              then_val = ensure_pointer(ctx, then_val)
              then_pred = ctx.fresh_label("cond_pred")
              ctx.io << "  br label %#{then_pred}\n"
              ctx.io << "#{then_pred}:\n"
              ctx.io << "  br label %#{merge_label}\n"

              ctx.io << "#{else_label}:\n"
              else_val = generate_expression(ctx, node.else_branch)
              else_val = ensure_pointer(ctx, else_val)
              else_pred = ctx.fresh_label("cond_pred")
              ctx.io << "  br label %#{else_pred}\n"
              ctx.io << "#{else_pred}:\n"
              ctx.io << "  br label %#{merge_label}\n"

              ctx.io << "#{merge_label}:\n"
              phi = ctx.fresh("condphi")
              ctx.io << "  %#{phi} = phi i8* [ #{then_val[:ref]}, %#{then_pred} ], [ #{else_val[:ref]}, %#{else_pred} ]\n"
              value_ref("i8*", "%#{phi}")
            end

            private def generate_debug_echo(ctx : FunctionContext, node : AST::DebugEcho) : ValueRef
              value = generate_expression(ctx, node.expression)

              if node.inline
                source_ptr = materialize_string_pointer(ctx, node.expression.to_source)
                boxed = box_value(ctx, value)
                ctx.io << "  call void @#{@runtime[:debug_accum]}(i8* #{source_ptr}, i8* #{boxed[:ref]})\n"
                return value
              end

              ctx.io << "  call void @#{@runtime[:debug_flush]}()\n"
              prefix_str = "#{node.expression.to_source} # -> "
              format_ptr = materialize_string_pointer(ctx, "%s")
              prefix_ptr = materialize_string_pointer(ctx, prefix_str)
              ctx.io << "  call i32 (i8*, ...) @printf(i8* #{format_ptr}, i8* #{prefix_ptr})\n"
              emit_echo(ctx, value, inspect: true)
              value
            end

            private def generate_local_assignment(ctx : FunctionContext, stmt : AST::Assignment) : ValueRef
              value = generate_expression(ctx, stmt.value.as(AST::Node))
              if type_expr = stmt.type_annotation
                target_type = llvm_type_of(type_expr)
                value = ensure_value_type(ctx, value, target_type)
              end
              if operator = stmt.operator
                current = generate_variable_reference(ctx, stmt.name)
                value = emit_binary_op(ctx, operator, current, value)
              end

              full_name = qualify_name(stmt.name)
              if @globals.includes?(full_name)
                boxed = box_value(ctx, value)
                global_name = mangle_global_name(full_name)
                ctx.io << "  store i8* #{boxed[:ref]}, i8** @\"#{global_name}\"\n"
              else
                store_local(ctx, stmt.name, value)
              end
              value
            end

            private def generate_unary_expression(ctx : FunctionContext, node : AST::UnaryOp) : ValueRef
              operand = generate_expression(ctx, node.operand)

              case node.operator
              when :-
                if operand[:type] == "i8*"
                  return runtime_call(ctx, "i8*", @runtime[:generic_negate], [{type: "i8*", ref: operand[:ref]}])
                end

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
              rhs_pred = ctx.fresh_label("logic_rpred")
              ctx.io << "  br label %#{rhs_pred}\n"
              ctx.io << "#{rhs_pred}:\n"
              ctx.io << "  br label %#{merge_label}\n"

              ctx.io << "#{short_label}:\n"
              ctx.io << "  br label %#{merge_label}\n"

              ctx.io << "#{merge_label}:\n"
              result = ctx.fresh("logic")
              ctx.io << "  %#{result} = phi i1 [ #{rhs[:ref]}, %#{rhs_pred} ], [ 0, %#{short_label} ]\n"
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
              rhs_pred = ctx.fresh_label("logic_rpred")
              ctx.io << "  br label %#{rhs_pred}\n"
              ctx.io << "#{rhs_pred}:\n"
              ctx.io << "  br label %#{merge_label}\n"

              ctx.io << "#{short_label}:\n"
              ctx.io << "  br label %#{merge_label}\n"

              ctx.io << "#{merge_label}:\n"
              result = ctx.fresh("logic")
              ctx.io << "  %#{result} = phi i1 [ 1, %#{short_label} ], [ #{rhs[:ref]}, %#{rhs_pred} ]\n"
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

            private def generate_if_expression(ctx : FunctionContext, stmt : AST::IfStatement) : ValueRef
              normalized = normalize_if_statement(stmt)

              cond_value = ensure_boolean(ctx, generate_expression(ctx, normalized.condition))

              then_label = ctx.fresh_label("if_then")
              else_label = ctx.fresh_label("if_else")
              merge_label = ctx.fresh_label("if_merge")

              ctx.io << "  br i1 #{cond_value[:ref]}, label %#{then_label}, label %#{else_label}\n"

              phi_entries = [] of NamedTuple(value: ValueRef, label: String)

              ctx.io << "#{then_label}:\n"
              then_val, then_term = evaluate_block_value(ctx, normalized.then_block)
              unless then_term
                v = then_val ? ensure_pointer(ctx, then_val) : value_ref("i8*", "null", constant: true)
                pred_label = ctx.fresh_label("if_pred")
                ctx.io << "  br label %#{pred_label}\n"
                ctx.io << "#{pred_label}:\n"
                ctx.io << "  br label %#{merge_label}\n"
                phi_entries << {value: v, label: pred_label}
              end

              ctx.io << "#{else_label}:\n"
              if else_block = normalized.else_block
                else_val, else_term = evaluate_block_value(ctx, else_block)
                unless else_term
                  v = else_val ? ensure_pointer(ctx, else_val) : value_ref("i8*", "null", constant: true)
                  pred_label = ctx.fresh_label("if_pred")
                  ctx.io << "  br label %#{pred_label}\n"
                  ctx.io << "#{pred_label}:\n"
                  ctx.io << "  br label %#{merge_label}\n"
                  phi_entries << {value: v, label: pred_label}
                end
              else
                pred_label = ctx.fresh_label("if_pred")
                ctx.io << "  br label %#{pred_label}\n"
                ctx.io << "#{pred_label}:\n"
                ctx.io << "  br label %#{merge_label}\n"
                phi_entries << {value: value_ref("i8*", "null", constant: true), label: pred_label}
              end

              ctx.io << "#{merge_label}:\n"
              if phi_entries.empty?
                value_ref("i8*", "null", constant: true)
              else
                phi = ctx.fresh("ifphi")
                entries = phi_entries.map { |e| "[ #{e[:value][:ref]}, %#{e[:label]} ]" }.join(", ")
                ctx.io << "  %#{phi} = phi i8* #{entries}\n"
                value_ref("i8*", "%#{phi}")
              end
            end

            private def generate_unless_expression(ctx : FunctionContext, stmt : AST::UnlessStatement) : ValueRef
              cond_value = ensure_boolean(ctx, generate_expression(ctx, stmt.condition))
              then_label = ctx.fresh_label("unless_then")
              else_label = ctx.fresh_label("unless_else")
              merge_label = ctx.fresh_label("unless_merge")

              ctx.io << "  br i1 #{cond_value[:ref]}, label %#{else_label}, label %#{then_label}\n"

              phi_entries = [] of NamedTuple(value: ValueRef, label: String)

              ctx.io << "#{then_label}:\n"
              then_val, then_term = evaluate_block_value(ctx, stmt.body)
              unless then_term
                v = then_val ? ensure_pointer(ctx, then_val) : value_ref("i8*", "null", constant: true)
                pred_label = ctx.fresh_label("ul_pred")
                ctx.io << "  br label %#{pred_label}\n"
                ctx.io << "#{pred_label}:\n"
                ctx.io << "  br label %#{merge_label}\n"
                phi_entries << {value: v, label: pred_label}
              end

              ctx.io << "#{else_label}:\n"
              if else_block = stmt.else_block
                else_val, else_term = evaluate_block_value(ctx, else_block)
                unless else_term
                  v = else_val ? ensure_pointer(ctx, else_val) : value_ref("i8*", "null", constant: true)
                  pred_label = ctx.fresh_label("ul_pred")
                  ctx.io << "  br label %#{pred_label}\n"
                  ctx.io << "#{pred_label}:\n"
                  ctx.io << "  br label %#{merge_label}\n"
                  phi_entries << {value: v, label: pred_label}
                end
              else
                pred_label = ctx.fresh_label("ul_pred")
                ctx.io << "  br label %#{pred_label}\n"
                ctx.io << "#{pred_label}:\n"
                ctx.io << "  br label %#{merge_label}\n"
                phi_entries << {value: value_ref("i8*", "null", constant: true), label: pred_label}
              end

              ctx.io << "#{merge_label}:\n"
              if phi_entries.empty?
                value_ref("i8*", "null", constant: true)
              else
                phi = ctx.fresh("ulphi")
                entries = phi_entries.map { |e| "[ #{e[:value][:ref]}, %#{e[:label]} ]" }.join(", ")
                ctx.io << "  %#{phi} = phi i8* #{entries}\n"
                value_ref("i8*", "%#{phi}")
              end
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

              ctx.loop_stack << {exit: exit_label, next: cond_label, redo: body_label}

              body_returns = generate_block(ctx, stmt.block)

              ctx.loop_stack.pop
              ctx.io << "  br label %#{cond_label}\n" unless body_returns
              ctx.io << "#{exit_label}:\n"

              false
            end

            private def generate_break_statement(ctx : FunctionContext, node : AST::BreakStatement) : Bool
              loop_info = ctx.loop_stack.last? || raise "break used outside of loop"

              if cond = node.condition
                cond_val = ensure_boolean(ctx, generate_expression(ctx, cond))
                cont_label = ctx.fresh_label("break_cont")
                ctx.io << "  br i1 #{cond_val[:ref]}, label %#{loop_info[:exit]}, label %#{cont_label}\n"
                ctx.io << "#{cont_label}:\n"
                false
              else
                ctx.io << "  br label %#{loop_info[:exit]}\n"
                true
              end
            end

            private def generate_next_statement(ctx : FunctionContext, node : AST::NextStatement) : Bool
              loop_info = ctx.loop_stack.last? || raise "next used outside of loop"

              if cond = node.condition
                cond_val = ensure_boolean(ctx, generate_expression(ctx, cond))
                cont_label = ctx.fresh_label("next_cont")
                ctx.io << "  br i1 #{cond_val[:ref]}, label %#{loop_info[:next]}, label %#{cont_label}\n"
                ctx.io << "#{cont_label}:\n"
                false
              else
                ctx.io << "  br label %#{loop_info[:next]}\n"
                true
              end
            end

            private def generate_redo_statement(ctx : FunctionContext, node : AST::RedoStatement) : Bool
              loop_info = ctx.loop_stack.last? || raise "redo used outside of loop"

              if cond = node.condition
                cond_val = ensure_boolean(ctx, generate_expression(ctx, cond))
                cont_label = ctx.fresh_label("redo_cont")
                ctx.io << "  br i1 #{cond_val[:ref]}, label %#{loop_info[:redo]}, label %#{cont_label}\n"
                ctx.io << "#{cont_label}:\n"
                false
              else
                ctx.io << "  br label %#{loop_info[:redo]}\n"
                true
              end
            end

            private def generate_retry_statement(ctx : FunctionContext, node : AST::RetryStatement) : Bool
              retry_label = ctx.retry_stack.last? || raise "retry used outside of begin block"

              if cond = node.condition
                cond_val = ensure_boolean(ctx, generate_expression(ctx, cond))
                cont_label = ctx.fresh_label("retry_cont")
                ctx.io << "  br i1 #{cond_val[:ref]}, label %#{retry_label}, label %#{cont_label}\n"
                ctx.io << "#{cont_label}:\n"
                false
              else
                ctx.io << "  br label %#{retry_label}\n"
                true
              end
            end

            private def generate_array_literal(ctx : FunctionContext, node : AST::ArrayLiteral) : ValueRef
              generate_array_literal_from_elements(ctx, node.elements)
            end

            private def generate_array_literal_from_elements(ctx : FunctionContext, elements : Array(AST::Node)) : ValueRef
              boxed = elements.map { |elem| box_value(ctx, generate_expression(ctx, elem)) }
              buffer = allocate_pointer_buffer(ctx, boxed) || "null"
              len_literal = elements.size
              reg = ctx.fresh("array")
              ctx.io << "  %#{reg} = call i8* @#{@runtime[:array_literal]}(i64 #{len_literal}, i8** #{buffer})\n"
              value_ref("i8*", "%#{reg}")
            end

            private def generate_bag_constructor(ctx : FunctionContext, node : AST::BagConstructor) : ValueRef
              type_name = node.element_type.to_source
              ptr = materialize_string_pointer(ctx, type_name)
              runtime_call(ctx, "i8*", @runtime[:bag_constructor], [
                {type: "i8*", ref: ptr},
              ])
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
              generate_block_literal_impl(ctx, node.typed_parameters, node.body)
            end

            private def generate_para_literal(ctx : FunctionContext, node : AST::ParaLiteral) : ValueRef
              generate_block_literal_impl(ctx, node.typed_parameters, node.body)
            end

            private def generate_function_literal(ctx : FunctionContext, node : AST::FunctionLiteral) : ValueRef
              body = node.body
              unless node.rescue_clauses.empty?
                body = [AST::BeginExpression.new(node.body, node.rescue_clauses, location: node.location)] of AST::Node
              end
              generate_block_literal_impl(ctx, node.typed_parameters, body, capture: false)
            end

            private def generate_attribute_assignment(ctx : FunctionContext, node : AST::AttributeAssignment) : ValueRef
              method_name = "#{node.name}="
              value = generate_expression(ctx, node.value)
              receiver = generate_expression(ctx, node.receiver)

              if struct_name = struct_name_for_value(receiver)
                emit_struct_method_dispatch(ctx, struct_name, receiver, method_name, [value])
              else
                emit_receiver_call(ctx, method_name, receiver, [value])
              end
            end

            private def generate_block_literal_impl(ctx : FunctionContext, params : Array(AST::TypedParameter), body : Array(AST::Node), capture : Bool = true) : ValueRef
              fn_name = unique_block_symbol
              fn_type = "i8*"
              captures = capture ? collect_block_captures(ctx, params, body) : [] of BlockCaptureInfo
              env_pointer = captures.empty? ? value_ref("i8*", "null", constant: true) : build_block_environment(ctx, captures)

              param_specs = params.map_with_index do |param, index|
                local_type = llvm_param_type(param.type)
                {type: local_type, name: param.name, index: index}
              end

              block_body_io = String::Builder.new
              block_ctx = FunctionContext.new(block_body_io, fn_type)

              param_specs.each do |spec|
                arg_ptr = "%#{block_ctx.fresh("argptr")}"
                block_body_io << "  #{arg_ptr} = getelementptr i8*, i8** %argv, i64 #{spec[:index]}\n"
                loaded = "%#{block_ctx.fresh("argload")}"
                block_body_io << "  #{loaded} = load i8*, i8** #{arg_ptr}\n"
                value = convert_block_argument(block_ctx, value_ref("i8*", loaded), spec[:type])

                slot = "%#{block_ctx.fresh("param")}"
                block_ctx.alloca_buffer << "  #{slot} = alloca #{spec[:type]}\n"
                block_body_io << "  store #{spec[:type]} #{value[:ref]}, #{spec[:type]}* #{slot}\n"

                block_ctx.locals[spec[:name]] = {ptr: slot, type: spec[:type], heap: false}
              end

              attach_block_captures(block_ctx, captures)

              value, terminated = evaluate_block_value(block_ctx, body)
              unless terminated
                boxed = value ? box_value(block_ctx, value) : value_ref("i8*", "null", constant: true)
                block_body_io << "  ret i8* #{boxed[:ref]}\n"
              end

              final_block_io = String::Builder.new
              final_block_io << "define #{fn_type} @#{fn_name}(i8* %closure, i64 %argc, i8** %argv) {\nentry:\n"
              final_block_io << block_ctx.alloca_buffer.to_s
              final_block_io << block_body_io.to_s
              final_block_io << "}\n\n"

              @pending_blocks << final_block_io.to_s

              reg = ctx.fresh("block")
              ctx.io << "  %#{reg} = call i8* @#{@runtime[:block_literal]}(#{fn_type} (i8*, i64, i8**)* @#{fn_name}, i8* #{env_pointer[:ref]})\n"
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
                {type: "i64", ref: captures.size.to_s},
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
                bool_i32 = runtime_call(ctx, "i32", @runtime[:unbox_bool], [{type: "i8*", ref: value[:ref]}])
                reg = ctx.fresh("bool_i1")
                ctx.io << "  %#{reg} = icmp ne i32 #{bool_i32[:ref]}, 0\n"
                value_ref("i1", "%#{reg}")
              when "double"
                runtime_call(ctx, "double", @runtime[:unbox_float], [{type: "i8*", ref: value[:ref]}])
              else
                value
              end
            end

            private def unbox_bool_i1(ctx : FunctionContext, value : ValueRef) : ValueRef
              bool_i32 = runtime_call(ctx, "i32", @runtime[:unbox_bool], [{type: "i8*", ref: value[:ref]}])
              reg = ctx.fresh("bool_i1")
              ctx.io << "  %#{reg} = icmp ne i32 #{bool_i32[:ref]}, 0\n"
              value_ref("i1", "%#{reg}")
            end

            private def collect_block_captures(ctx : FunctionContext, params : Array(AST::TypedParameter), body : Array(AST::Node)) : Array(BlockCaptureInfo)
              return [] of BlockCaptureInfo if ctx.locals.empty?
              locals = ctx.locals
              local_bindings = Set(String).new
              params.each { |param| local_bindings << param.name }
              ordered = [] of String
              seen = Set(String).new
              scan_capture_statements(body, locals, local_bindings, ordered, seen)

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
                # Skip.
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
              when AST::BlockLiteral, AST::ParaLiteral, AST::FunctionDef, AST::FunctionLiteral,
                   AST::ClassDefinition, AST::StructDefinition, AST::ModuleDefinition, AST::EnumDefinition
              else
                # Unhandled node types.
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

              rescue_label = ctx.fresh_label("rescue")
              body_label = ctx.fresh_label("begin_body")
              # ensure_label = ctx.fresh_label("ensure")
              merge_label = ctx.fresh_label("begin_merge")
              frame_storage = ctx.fresh("eh_frame")
              phi_entries = [] of NamedTuple(value: ValueRef, label: String)
              ctx.io << "  %#{frame_storage} = alloca [4096 x i8], align 16\n"
              frame_ptr = ctx.fresh("eh_ptr")
              ctx.io << "  %#{frame_ptr} = bitcast [4096 x i8]* %#{frame_storage} to i8*\n"
              ctx.io << "  call void @#{@runtime[:push_handler]}(i8* %#{frame_ptr})\n"
              jmp_res = ctx.fresh("setjmp_res")
              {% if flag?(:windows) %}
                ctx.io << "  %#{jmp_res} = call i32 @_setjmp(i8* %#{frame_ptr}, i8* null)\n"
              {% else %}
                ctx.io << "  %#{jmp_res} = call i32 @setjmp(i8* %#{frame_ptr})\n"
              {% end %}
              is_raise = ctx.fresh("is_raise")
              ctx.io << "  %#{is_raise} = icmp ne i32 %#{jmp_res}, 0\n"
              ctx.io << "  br i1 %#{is_raise}, label %#{rescue_label}, label %#{body_label}\n"
              ctx.io << "#{body_label}:\n"
              begin_label = ctx.fresh_label("begin_start")
              ctx.retry_stack << begin_label
              ctx.io << "  br label %#{begin_label}\n"
              ctx.io << "#{begin_label}:\n"

              if ensure_nodes
                ctx.ensure_stack << ensure_nodes
              end

              body_value, body_terminated = evaluate_block_value(ctx, node.body)

              if ensure_nodes
                if last = ctx.ensure_stack.last?
                  ctx.ensure_stack.pop if last.same?(ensure_nodes)
                end
              end

              if !body_terminated && (else_block = node.else_block)
                else_value, else_terminated = evaluate_block_value(ctx, else_block)
                final_val = else_value || body_value

                unless else_terminated
                  v = final_val ? ensure_pointer(ctx, final_val) : value_ref("i8*", "null", constant: true)

                  ctx.io << "  call void @#{@runtime[:pop_handler]}()\n"
                  if ensure_nodes
                    generate_block(ctx, ensure_nodes)
                  end

                  pred_label = ctx.fresh_label("begin_pred")
                  ctx.io << "  br label %#{pred_label}\n"
                  ctx.io << "#{pred_label}:\n"
                  ctx.io << "  br label %#{merge_label}\n"
                  phi_entries << {value: v, label: pred_label}
                end
              elsif !body_terminated
                v = body_value ? ensure_pointer(ctx, body_value) : value_ref("i8*", "null", constant: true)
                ctx.io << "  call void @#{@runtime[:pop_handler]}()\n"

                if ensure_nodes
                  generate_block(ctx, ensure_nodes)
                end

                pred_label = ctx.fresh_label("begin_pred")
                ctx.io << "  br label %#{pred_label}\n"
                ctx.io << "#{pred_label}:\n"
                ctx.io << "  br label %#{merge_label}\n"
                phi_entries << {value: v, label: pred_label}
              end

              ctx.io << "#{rescue_label}:\n"
              ex_val_reg = ctx.fresh("ex_val")
              ctx.io << "  %#{ex_val_reg} = call i8* @#{@runtime[:get_exception]}()\n"
              rescue_handled = false
              # rescue_merge = ctx.fresh_label("rescue_done")

              node.rescue_clauses.each do |clause|
                if var_name = clause.exception_variable
                  store_local(ctx, var_name, value_ref("i8*", "%#{ex_val_reg}"))
                end

                clause_val, clause_term = evaluate_block_value(ctx, clause.body)

                if ensure_nodes
                  generate_block(ctx, ensure_nodes) unless clause_term
                end

                unless clause_term
                  v = clause_val ? ensure_pointer(ctx, clause_val) : value_ref("i8*", "null", constant: true)

                  pred_label = ctx.fresh_label("rescue_pred")
                  ctx.io << "  br label %#{pred_label}\n"
                  ctx.io << "#{pred_label}:\n"
                  ctx.io << "  br label %#{merge_label}\n"
                  phi_entries << {value: v, label: pred_label}
                end
                rescue_handled = true
              end

              if !rescue_handled
                if ensure_nodes
                  generate_block(ctx, ensure_nodes)
                end

                pred_label = ctx.fresh_label("rescue_pred")
                ctx.io << "  br label %#{pred_label}\n"
                ctx.io << "#{pred_label}:\n"
                ctx.io << "  br label %#{merge_label}\n"
                phi_entries << {value: value_ref("i8*", "null", constant: true), label: pred_label}
              end

              ctx.retry_stack.pop

              ctx.io << "#{merge_label}:\n"
              if phi_entries.empty?
                value_ref("i8*", "null", constant: true)
              else
                phi = ctx.fresh("beginphi")
                entries = phi_entries.map { |e| "[ #{e[:value][:ref]}, %#{e[:label]} ]" }.join(", ")
                ctx.io << "  %#{phi} = phi i8* #{entries}\n"
                value_ref("i8*", "%#{phi}")
              end
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
	                   AST::ArgvExpression,
	                   AST::ArgcExpression,
	                   AST::ArgfExpression,
	                   AST::StdoutExpression,
	                   AST::StderrExpression,
	                   AST::StdinExpression,
	                   AST::BinaryOp,
	                   AST::MethodCall,
	                   AST::UnaryOp,
	                   AST::ArrayLiteral,
                   AST::BagConstructor,
                   AST::MapLiteral,
                   AST::BlockLiteral,
                   AST::ParaLiteral,
                   AST::InstanceVariable,
                   AST::InstanceVariableAssignment,
                   AST::BeginExpression,
                   AST::ConstantPath,
                   AST::TupleLiteral,
                   AST::NamedTupleLiteral,
                   AST::InterpolatedString,
                   AST::IfStatement,
                   AST::UnlessStatement,
                   AST::ConditionalExpression,
                   AST::CaseStatement,
                   AST::Assignment,
                   AST::AttributeAssignment,
                   AST::IndexAssignment,
                   AST::YieldExpression,
                   AST::DebugEcho
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
                {type: "i8**", ref: buffer},
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
                {type: "i8**", ref: buffer},
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
                {type: "i8**", ref: values_buffer},
              ])
            end

            private def generate_interpolated_string(ctx : FunctionContext, node : AST::InterpolatedString) : ValueRef
              parts = node.normalized_parts
              return value_ref("i8*", materialize_string_pointer(ctx, ""), constant: true) if parts.empty?
              segments = [] of ValueRef
              parts.each do |type, content|
                if type == :string
                  segments << value_ref("i8*", materialize_string_pointer(ctx, content.as(String)), constant: true)
                else
                  expression_value = generate_expression(ctx, interpolation_expression(content))
                  segments << ensure_string_pointer(ctx, expression_value)
                end
              end

              return segments.first if segments.size == 1

              buffer = allocate_pointer_buffer(ctx, segments) || raise "Interpolated string segments missing buffer"
              runtime_call(ctx, "i8*", @runtime[:interpolated_string], [
                {type: "i64", ref: segments.size.to_s},
                {type: "i8**", ref: buffer},
              ])
            end

            private def generate_constant_declaration(ctx : FunctionContext, node : AST::ConstantDeclaration)
              value = generate_expression(ctx, node.value)
              boxed = box_value(ctx, value)
              name_ptr = materialize_string_pointer(ctx, qualify_name(node.name))
              runtime_call(ctx, "i8*", @runtime[:constant_define], [
                {type: "i8*", ref: name_ptr},
                {type: "i8*", ref: boxed[:ref]},
              ])
            end

            private def generate_struct_definition(ctx : FunctionContext, node : AST::StructDefinition) : Bool
              struct_name = @struct_unique_names[node]? || node.name
              emit_namespace_placeholder(ctx, struct_name)
              with_namespace(struct_name) do
                generate_block(ctx, node.body)
              end
              false
            end

            private def generate_enum_definition(ctx : FunctionContext, node : AST::EnumDefinition) : Bool
              full_name = qualify_name(node.name)
              name_ptr = materialize_string_pointer(ctx, full_name)

              reg = ctx.fresh("enum")
              ctx.io << "  %#{reg} = call i8* @#{@runtime[:define_class]}(i8* #{name_ptr})\n"

              if @globals.includes?(full_name)
                global_name = mangle_global_name(full_name)
                ctx.io << "  store i8* %#{reg}, i8** @\"#{global_name}\"\n"
              end

              counter_ptr = ctx.fresh("enum_ctr")
              ctx.io << "  %#{counter_ptr} = alloca i64\n"
              ctx.io << "  store i64 0, i64* %#{counter_ptr}\n"

              node.members.each do |member|
                member_name = materialize_string_pointer(ctx, member.name)

                val_reg = if val_node = member.value
                            v = generate_expression(ctx, val_node)
                            coerce_integer(ctx, v, 64)
                          else
                            loaded = ctx.fresh("enum_load")
                            ctx.io << "  %#{loaded} = load i64, i64* %#{counter_ptr}\n"
                            value_ref("i64", "%#{loaded}")
                          end

                ctx.io << "  call void @#{@runtime[:define_enum_member]}(i8* %#{reg}, i8* #{member_name}, i64 #{val_reg[:ref]})\n"
                next_val = ctx.fresh("enum_next")
                ctx.io << "  %#{next_val} = add i64 #{val_reg[:ref]}, 1\n"
                ctx.io << "  store i64 %#{next_val}, i64* %#{counter_ptr}\n"
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
                  {type: "i8*", ref: index[:ref]},
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
                  {type: "i8*", ref: index[:ref]},
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
                {type: "i8*", ref: value[:ref]},
              ])
            end

            private def generate_instance_variable(ctx : FunctionContext, node : AST::InstanceVariable) : ValueRef
              self_ref = if ctx.locals.has_key?("self")
                           load_local(ctx, "self")
                         else
                           runtime_call(ctx, "i8*", @runtime[:root_self], [] of CallArg)
                         end
              ivar_name = node.name.starts_with?("@") ? node.name : "@#{node.name}"
              name_ptr = materialize_string_pointer(ctx, ivar_name)
              runtime_call(ctx, "i8*", @runtime[:ivar_get], [
                {type: "i8*", ref: self_ref[:ref]},
                {type: "i8*", ref: name_ptr},
              ])
            end

            private def generate_instance_variable_assignment(ctx : FunctionContext, node : AST::InstanceVariableAssignment) : ValueRef
              value = box_value(ctx, generate_expression(ctx, node.value))
              self_ref = if ctx.locals.has_key?("self")
                           load_local(ctx, "self")
                         else
                           runtime_call(ctx, "i8*", @runtime[:root_self], [] of CallArg)
                         end
              ivar_name = node.name.starts_with?("@") ? node.name : "@#{node.name}"
              name_ptr = materialize_string_pointer(ctx, ivar_name)

              runtime_call(ctx, "i8*", @runtime[:ivar_set], [
                {type: "i8*", ref: self_ref[:ref]},
                {type: "i8*", ref: name_ptr},
                {type: "i8*", ref: value[:ref]},
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

                  pred_label = ctx.fresh_label("case_pred")
                  ctx.io << "  br label %#{pred_label}\n"
                  ctx.io << "#{pred_label}:\n"
                  ctx.io << "  br label %#{exit_label}\n"

                  phi_entries << {value: resolved, label: pred_label}
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

                  pred_label = ctx.fresh_label("case_pred")
                  ctx.io << "  br label %#{pred_label}\n"
                  ctx.io << "#{pred_label}:\n"
                  ctx.io << "  br label %#{exit_label}\n"

                  phi_entries << {value: resolved, label: pred_label}
                end
              else
                pred_label = ctx.fresh_label("case_pred")
                ctx.io << "  br label %#{pred_label}\n"
                ctx.io << "#{pred_label}:\n"
                ctx.io << "  br label %#{exit_label}\n"
                phi_entries << {value: value_ref("i8*", "null", constant: true), label: pred_label}
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
                                      {type: "i8*", ref: comparison[:ref]},
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

            private def generate_with_expression(ctx : FunctionContext, node : AST::WithExpression) : Bool
              receiver_val = generate_expression(ctx, node.receiver)
              ctx.with_stack << receiver_val
              generate_block(ctx, node.body)
              ctx.with_stack.pop
              false
            end

            private def resolve_implicit_receiver(ctx : FunctionContext, name : String) : ValueRef?
              ctx.with_stack.reverse_each do |receiver|
                if struct_name = struct_name_for_value(receiver)
                  method_symbol = struct_method_symbol(struct_name, name)

                  if @function_overloads.has_key?(method_symbol) || @function_signatures.has_key?(method_symbol)
                    return receiver
                  end

                  if @struct_field_indices[struct_name]?.try(&.has_key?(name))
                    return receiver
                  end
                end
              end

              if ctx.locals.has_key?("self")
                return load_local(ctx, "self")
              end

              nil
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

            private def generate_raise_expression(ctx : FunctionContext, node : AST::RaiseExpression) : ValueRef
              if exp = node.expression
                message = ensure_string_pointer(ctx, generate_expression(ctx, exp))
                ctx.io << "  call void @#{@runtime[:raise]}(i8* #{message[:ref]})\n"
              else
                ctx.io << "  call void @#{@runtime[:raise]}(i8* null)\n"
              end
              ctx.io << "  unreachable\n"
              value_ref("i8*", "null", constant: true)
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
              when ::Char
                ptr = materialize_string_pointer(ctx, value.to_s)
                value_ref("i8*", ptr)
              when ::Symbol
                ptr = materialize_string_pointer(ctx, value.to_s)
                value_ref("i8*", ptr)
              when SymbolValue
                ptr = materialize_string_pointer(ctx, value.name)
                value_ref("i8*", ptr)
              when Nil
                value_ref("i8*", "null", constant: true)
              else
                raise "Unsupported literal #{value.inspect}"
              end
            end

            private def materialize_string_pointer(ctx : FunctionContext, literal : String) : String
              entry = @string_literals[literal]?

              unless entry
                entry = intern_string(literal)
                @pending_strings << literal
              end

              size = entry[:length] + 1
              reg = ctx.fresh("str")
              ctx.io << "  %#{reg} = getelementptr [#{size} x i8], [#{size} x i8]* @\"#{entry[:name]}\", i32 0, i32 0\n"
              "%#{reg}"
            end

            private def box_value(ctx : FunctionContext, value : ValueRef) : ValueRef
              type = value[:type]

              if type == "%DSValue*" || type == "%DSObject*"
                if type == "i8*"
                  return value
                else
                  cast = ctx.fresh("anycast")
                  ctx.io << "  %#{cast} = bitcast #{type} #{value[:ref]} to i8*\n"
                  return value_ref("i8*", "%#{cast}")
                end
              end

              if type.starts_with?("%")
                temp_ptr = ctx.fresh("box_temp")
                ctx.alloca_buffer << "  %#{temp_ptr} = alloca #{type}\n"
                ctx.io << "  store #{type} #{value[:ref]}, #{type}* %#{temp_ptr}\n"

                raw_ptr = ctx.fresh("box_raw")

                ctx.io << "  %#{raw_ptr} = bitcast #{type}* %#{temp_ptr} to i8*\n"

                size_ptr = ctx.fresh("size_ptr")
                ctx.io << "  %#{size_ptr} = getelementptr #{type}, #{type}* null, i32 1\n"
                size_int = ctx.fresh("size")
                ctx.io << "  %#{size_int} = ptrtoint #{type}* %#{size_ptr} to i64\n"

                reg = ctx.fresh("boxed_struct")
                ctx.io << "  %#{reg} = call i8* @#{@runtime[:box_struct]}(i8* %#{raw_ptr}, i64 %#{size_int})\n"
                return value_ref("i8*", "%#{reg}")
              end

              case value[:type]
              when "i32"
                runtime_call(ctx, "i8*", @runtime[:box_i32], [{type: "i32", ref: value[:ref]}])
              when "i64"
                runtime_call(ctx, "i8*", @runtime[:box_i64], [{type: "i64", ref: value[:ref]}])
              when "double"
                runtime_call(ctx, "i8*", @runtime[:box_float], [{type: "double", ref: value[:ref]}])
              when "i1"
                promoted = ctx.fresh("bool_i32")
                ctx.io << "  %#{promoted} = zext i1 #{value[:ref]} to i32\n"
                runtime_call(ctx, "i8*", @runtime[:box_bool], [{type: "i32", ref: "%#{promoted}"}])
              when "i8*"
                value
              else
                raise "Cannot box value of type #{value[:type]}"
              end
            end

            private def ensure_pointer(ctx : FunctionContext, value : ValueRef) : ValueRef
              case value[:type]
              when "i8*"
                value
              when "%DSValue*", "%DSObject*"
                cast = ctx.fresh("bitcast")
                ctx.io << "  %#{cast} = bitcast #{value[:type]} #{value[:ref]} to i8*\n"
                value_ref("i8*", "%#{cast}")
              else
                box_value(ctx, value)
              end
            end

            private def allocate_pointer_buffer(ctx : FunctionContext, values : Array(ValueRef)) : String?
              return nil if values.empty?

              size = values.size
              buffer = ctx.fresh("buf")
              ctx.alloca_buffer << "  %#{buffer} = alloca [#{size} x i8*], align 16\n"

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
                ctx.alloca_buffer << "  #{ptr} = alloca #{value[:type]}\n"
                slot = {ptr: ptr, type: value[:type], heap: false}
                ctx.locals[name] = slot
              end

              if slot[:type] != value[:type]
                # Allow dynamic locals that were first assigned a boxed value (`i8*`) to later
                # accept primitive values by boxing them on assignment.
                if slot[:type] == "i8*"
                  boxed = box_value(ctx, value)
                  ctx.io << "  store i8* #{boxed[:ref]}, i8** #{slot[:ptr]}\n"
                  return
                end

                # Allow primitive locals to accept boxed values by unboxing them.
                # This is necessary when a local starts as an integer/float and later participates in
                # an operation that routes through the boxed runtime helpers (e.g. array element math).
                if value[:type] == "i8*"
                  case slot[:type]
                  when "i32"
                    unboxed = runtime_call(ctx, "i32", @runtime[:unbox_i32], [{type: "i8*", ref: value[:ref]}])
                    ctx.io << "  store i32 #{unboxed[:ref]}, i32* #{slot[:ptr]}\n"
                    return
                  when "i64"
                    unboxed = runtime_call(ctx, "i64", @runtime[:unbox_i64], [{type: "i8*", ref: value[:ref]}])
                    ctx.io << "  store i64 #{unboxed[:ref]}, i64* #{slot[:ptr]}\n"
                    return
                  when "double"
                    unboxed = runtime_call(ctx, "double", @runtime[:unbox_float], [{type: "i8*", ref: value[:ref]}])
                    ctx.io << "  store double #{unboxed[:ref]}, double* #{slot[:ptr]}\n"
                    return
                  when "i1"
                    raw = runtime_call(ctx, "i32", @runtime[:unbox_bool], [{type: "i8*", ref: value[:ref]}])
                    reg = ctx.fresh("bool_i1")
                    ctx.io << "  %#{reg} = icmp ne i32 #{raw[:ref]}, 0\n"
                    ctx.io << "  store i1 %#{reg}, i1* #{slot[:ptr]}\n"
                    return
                  end
                end

                raise "Type mismatch assigning to #{name}: expected #{slot[:type]}, got #{value[:type]}"
              end

              ctx.io << "  store #{value[:type]} #{value[:ref]}, #{value[:type]}* #{slot[:ptr]}\n"
            end

            private def load_local(ctx : FunctionContext, name : String) : ValueRef
              if name == "ffi"
                return value_ref("i8*", materialize_string_pointer(ctx, "ffi"), constant: true)
              end

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
              if operator == :".." || operator == :"..."
                return emit_range_op(ctx, operator, lhs, rhs)
              end

              if operator == :"**" || operator == :"&**"
                lhs_boxed = box_value(ctx, lhs)
                rhs_boxed = box_value(ctx, rhs)
                return runtime_call(ctx, "i8*", @runtime[:generic_pow], [
                  {type: "i8*", ref: lhs_boxed[:ref]},
                  {type: "i8*", ref: rhs_boxed[:ref]},
                ])
              end

              if operator == :+ && (lhs[:type] == "i8*" || rhs[:type] == "i8*")
                lhs_boxed = box_value(ctx, lhs)
                rhs_boxed = box_value(ctx, rhs)
                return runtime_call(ctx, "i8*", @runtime[:generic_add], [
                  {type: "i8*", ref: lhs_boxed[:ref]},
                  {type: "i8*", ref: rhs_boxed[:ref]},
                ])
              end

              if struct_name = struct_name_for_value(lhs)
                method_name = operator.to_s
                return emit_struct_method_dispatch(ctx, struct_name, lhs, method_name, [rhs])
              end

              if float_type?(lhs[:type]) || float_type?(rhs[:type])
                return emit_float_op(ctx, operator, lhs, rhs)
              end

              if operator == :<<
                if lhs[:type] == "i8*" || rhs[:type] == "i8*"
                  lhs_boxed = box_value(ctx, lhs)
                  rhs_boxed = box_value(ctx, rhs)
                  return runtime_call(ctx, "i8*", @runtime[:generic_shl], [
                    {type: "i8*", ref: lhs_boxed[:ref]},
                    {type: "i8*", ref: rhs_boxed[:ref]},
                  ])
                end

                target_bits = integer_operation_width(lhs, rhs)
                lhs_val = coerce_integer(ctx, lhs, target_bits)
                rhs_val = coerce_integer(ctx, rhs, target_bits)

                reg = ctx.fresh("shl")
                type = "i#{target_bits}"
                ctx.io << "  %#{reg} = shl #{type} #{lhs_val[:ref]}, #{rhs_val[:ref]}\n"
                return value_ref(type, "%#{reg}")
              end

              if operator == :>>
                if lhs[:type] == "i8*" || rhs[:type] == "i8*"
                  lhs_boxed = box_value(ctx, lhs)
                  rhs_boxed = box_value(ctx, rhs)
                  return runtime_call(ctx, "i8*", @runtime[:generic_shr], [
                    {type: "i8*", ref: lhs_boxed[:ref]},
                    {type: "i8*", ref: rhs_boxed[:ref]},
                  ])
                end

                target_bits = integer_operation_width(lhs, rhs)
                lhs_val = coerce_integer(ctx, lhs, target_bits)
                rhs_val = coerce_integer(ctx, rhs, target_bits)

                reg = ctx.fresh("shr")
                type = "i#{target_bits}"
                ctx.io << "  %#{reg} = ashr #{type} #{lhs_val[:ref]}, #{rhs_val[:ref]}\n"
                return value_ref(type, "%#{reg}")
              end

              case operator
              when :+, :-, :*, :/, :"&+", :"//", :"&-", :"<=>", :&, :|, :^, :>>, :%
                if lhs[:type] == "i8*" || rhs[:type] == "i8*"
                  runtime_func = case operator
                                 when :+, :"&+" then @runtime[:generic_add]
                                 when :-, :"&-" then @runtime[:generic_sub]
                                 when :*, :"&*" then @runtime[:generic_mul]
                                 when :/        then @runtime[:generic_div]
                                 when :%        then @runtime[:generic_mod]
                                 else                nil
                                 end

                  if runtime_func
                    lhs_boxed = box_value(ctx, lhs)
                    rhs_boxed = box_value(ctx, rhs)
                    return runtime_call(ctx, "i8*", runtime_func, [
                      {type: "i8*", ref: lhs_boxed[:ref]},
                      {type: "i8*", ref: rhs_boxed[:ref]},
                    ])
                  end
                end

                if operator == :"//" && (lhs[:type] == "i8*" || rhs[:type] == "i8*")
                  lhs_boxed = box_value(ctx, lhs)
                  rhs_boxed = box_value(ctx, rhs)
                  return runtime_call(ctx, "i8*", @runtime[:generic_floor_div], [
                    {type: "i8*", ref: lhs_boxed[:ref]},
                    {type: "i8*", ref: rhs_boxed[:ref]},
                  ])
                end

                if operator == :"<=>" && (lhs[:type] == "i8*" || rhs[:type] == "i8*")
                  lhs_boxed = box_value(ctx, lhs)
                  rhs_boxed = box_value(ctx, rhs)
                  return runtime_call(ctx, "i8*", @runtime[:generic_cmp], [
                    {type: "i8*", ref: lhs_boxed[:ref]},
                    {type: "i8*", ref: rhs_boxed[:ref]},
                  ])
                end

                target_bits = integer_operation_width(lhs, rhs)
                lhs = coerce_integer(ctx, lhs, target_bits)
                rhs = coerce_integer(ctx, rhs, target_bits)
                instruction = case operator
                              when :+, :"&+" then "add"
                              when :-        then "sub"
                              when :*        then "mul"
                              when :/        then "sdiv"
                              when :"//"     then "sdiv"
                              when :"&-"     then "sub"
                              when :"<=>"    then nil
                              when :&        then "and"
                              when :|        then "or"
                              when :^        then "xor"
                              when :>>       then "ashr"
                              when :%        then "srem"
                              else
                                raise "Unsupported arithmetic operator #{operator}"
                              end

                type = "i#{target_bits}"

                if operator == :/ || operator == :"//" || operator == :%
                  is_zero = ctx.fresh("is_zero")
                  ctx.io << "  %#{is_zero} = icmp eq #{type} #{rhs[:ref]}, 0\n"
                  zero_label = ctx.fresh_label("div_zero")
                  cont_label = ctx.fresh_label("div_cont")
                  ctx.io << "  br i1 %#{is_zero}, label %#{zero_label}, label %#{cont_label}\n"

                  ctx.io << "#{zero_label}:\n"
                  msg_ptr = materialize_string_pointer(ctx, "Division by zero")
                  ctx.io << "  call void @#{@runtime[:raise]}(i8* #{msg_ptr})\n"
                  ctx.io << "  unreachable\n"

                  ctx.io << "#{cont_label}:\n"
                end

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
                if lhs[:type] == "i8*" || rhs[:type] == "i8*"
                  runtime_func = case operator
                                 when :"==" then @runtime[:eq]
                                 when :"!=" then @runtime[:ne]
                                 when :"<"  then @runtime[:lt]
                                 when :"<=" then @runtime[:lte]
                                 when :">"  then @runtime[:gt]
                                 when :">=" then @runtime[:gte]
                                 else            raise "Unknown comparison operator"
                                 end

                  lhs_boxed = box_value(ctx, lhs)
                  rhs_boxed = box_value(ctx, rhs)
                  result = runtime_call(ctx, "i8*", runtime_func, [
                    {type: "i8*", ref: lhs_boxed[:ref]},
                    {type: "i8*", ref: rhs_boxed[:ref]},
                  ])

                  unbox_bool_i1(ctx, result)
                elsif float_operation?(lhs, rhs)
                  emit_float_comparison(ctx, operator, lhs, rhs)
                elsif (operator == :"==" || operator == :"!=") && (pointer_type?(lhs[:type]) || pointer_type?(rhs[:type]))
                  emit_pointer_comparison(ctx, operator, lhs, rhs)
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
                ctx.io << "  call void @#{@runtime[:debug_flush]}()\n"
                arg_val = generate_expression(ctx, args.first)
                emit_echo(ctx, arg_val, inspect: false)
                return value_ref("i8*", "null", constant: true)
              elsif call.name == "eecho"
                raise "eecho expects exactly one argument" unless args.size == 1
                raise "eecho does not accept a block" if block_node
                ctx.io << "  call void @#{@runtime[:debug_flush]}()\n"
                arg_val = generate_expression(ctx, args.first)
                emit_eecho(ctx, arg_val, inspect: false)
                return value_ref("i8*", "null", constant: true)
              elsif call.name == "typeof"
                raise "typeof expects exactly one argument" unless args.size == 1
                raise "typeof does not accept a block" if block_node
                arg_val = box_value(ctx, generate_expression(ctx, args.first))
                return runtime_call(ctx, "i8*", @runtime[:type_of], [{type: "i8*", ref: arg_val[:ref]}])
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
                return emit_receiver_call(ctx, call.name, receiver_value, arg_values, block_value)
              else
                if !@namespace_stack.empty?
                  class_name = @namespace_stack.join("::")
                  base_name = "#{llvm_struct_symbol(class_name)}_#{call.name}"

                  if overloads = @function_overloads[base_name]?
                    if self_slot = ctx.locals["self"]?
                      self_val = load_local(ctx, "self")
                    else
                      self_val = value_ref("i8*", "null", constant: true)
                    end

                    final_args = [self_val] + arg_values
                    args_with_block = final_args.dup
                    block_arg = block_value || value_ref("i8*", "null", constant: true)

                    signature = nil
                    target_name = nil
                    best_score = -1

                    overloads.each do |cand|
                      next unless sig = @function_signatures[cand]?
                      expected_params = sig[:param_types]
                      typed_params = sig[:param_typed]

                      candidate_args = args_with_block.dup
                      if expected_params.size == candidate_args.size + 1 && expected_params.last == "i8*"
                        candidate_args << block_arg
                      elsif expected_params.size != candidate_args.size
                        next
                      end

                      score = 0
                      candidate_args.each_with_index do |val, idx|
                        exp_type = expected_params[idx]
                        if val[:constant] && val[:ref] == "null"
                          if exp_type == "%DSValue*" || exp_type == "%DSObject*"
                            score += 2
                          elsif exp_type == "i8*"
                            score += 1
                          end
                        elsif val[:type] == exp_type
                          if exp_type == "i8*" && idx < typed_params.size && !typed_params[idx]
                            score += 1
                          else
                            score += 3
                          end
                        elsif val[:type] == "i8*" && (exp_type == "%DSValue*" || exp_type == "%DSObject*")
                          score += 2
                        end
                      end

                      if score > best_score
                        best_score = score
                        signature = sig
                        target_name = cand
                        args_with_block = candidate_args
                      end
                    end

                    if signature && target_name
                      casted_args = args_with_block.map_with_index do |val, i|
                        ensure_value_type(ctx, val, signature[:param_types][i])
                      end

                      arg_source = casted_args.map { |v| "#{v[:type]} #{v[:ref]}" }.join(", ")
                      return_type = signature[:return_type]

                      if return_type == "void"
                        ctx.io << "  call void @\"#{target_name}\"(#{arg_source})\n"
                        return value_ref("i8*", "null", constant: true)
                      else
                        reg = ctx.fresh("call")
                        ctx.io << "  %#{reg} = call #{return_type} @\"#{target_name}\"(#{arg_source})\n"
                        return value_ref(return_type, "%#{reg}")
                      end
                    end
                  end
                end

                call_args = arg_values.dup

                if implicit_receiver = resolve_implicit_receiver(ctx, call.name)
                  if struct_name = struct_name_for_value(implicit_receiver)
                    return emit_struct_method_dispatch(ctx, struct_name, implicit_receiver, call.name, arg_values)
                  end
                end

                emit_function_call(ctx, call, call_args, block_value)
              end
            end

            private def generate_super_call(ctx : FunctionContext, node : AST::SuperCall) : ValueRef
              method_name = ctx.callable_name
              raise "'super' used outside of a method" unless method_name && method_name != "<block>"

              raise "'super' requires a class context" if @namespace_stack.empty?
              owner_name = @namespace_stack.join("::").sub(/_\d+$/, "")
              owner_val = if @globals.includes?(owner_name)
                            global_name = mangle_global_name(owner_name)
                            owner_reg = ctx.fresh("super_owner")
                            ctx.io << "  %#{owner_reg} = load i8*, i8** @\"#{global_name}\"\n"
                            value_ref("i8*", "%#{owner_reg}")
                          else
                            emit_constant_lookup(ctx, [owner_name])
                          end

              receiver_val = if ctx.locals.has_key?("self")
                               load_local(ctx, "self")
                             else
                               raise "'super' requires a receiver"
                             end

              arg_info = extract_call_arguments(node.arguments)
              args = arg_info[:args]
              block_node = arg_info[:block]

              arg_values = [] of ValueRef
              if node.explicit_arguments?
                arg_values = args.map { |arg| generate_expression(ctx, arg) }
              else
                arg_values = ctx.parameter_names.map { |name| load_local(ctx, name) }
              end

              boxed_args = arg_values.map { |arg| box_value(ctx, arg) }
              buffer = allocate_pointer_buffer(ctx, boxed_args) || "null"

              block_val = if block_node
                            generate_block_literal(ctx, block_node)
                          elsif ctx.locals.has_key?("__block")
                            load_local(ctx, "__block")
                          else
                            value_ref("i8*", "null", constant: true)
                          end

              receiver_ptr = ensure_pointer(ctx, receiver_val)
              owner_ptr = ensure_pointer(ctx, owner_val)
              name_ptr = materialize_string_pointer(ctx, method_name.not_nil!)

              runtime_call(ctx, "i8*", @runtime[:super_invoke], [
                {type: "i8*", ref: receiver_ptr[:ref]},
                {type: "i8*", ref: owner_ptr[:ref]},
                {type: "i8*", ref: name_ptr},
                {type: "i64", ref: arg_values.size.to_s},
                {type: "i8**", ref: buffer},
                {type: "i8*", ref: block_val[:ref]},
              ])
            end

            private def emit_function_call(ctx : FunctionContext, call : AST::MethodCall, args : Array(ValueRef), block_value : ValueRef? = nil) : ValueRef?
              base_name = call.name == "main" ? "__dragonstone_user_main" : call.name
              args_with_block = args.dup
              block_arg = block_value || value_ref("i8*", "null", constant: true)

              overloads = @function_overloads[base_name]?
              signature = nil
              target_name = nil

              if overloads
                best_score = -1
                best_args = nil
                overloads.each do |cand|
                  next unless sig = @function_signatures[cand]?
                  expected_params = sig[:param_types]
                  typed_params = sig[:param_typed]

                  candidate_args = args_with_block.dup
                  if expected_params.size == candidate_args.size + 1 && expected_params.last == "i8*"
                    candidate_args << block_arg
                  elsif expected_params.size != candidate_args.size
                    next
                  end

                  score = 0
                  candidate_args.each_with_index do |val, idx|
                    exp_type = expected_params[idx]
                    if val[:constant] && val[:ref] == "null"
                      if exp_type == "%DSValue*" || exp_type == "%DSObject*"
                        score += 2
                      elsif exp_type == "i8*"
                        score += 1
                      end
                    elsif val[:type] == exp_type
                      if exp_type == "i8*" && idx < typed_params.size && !typed_params[idx]
                        score += 1
                      else
                        score += 3
                      end
                    elsif val[:type] == "i8*" && (exp_type == "%DSValue*" || exp_type == "%DSObject*")
                      score += 2
                    end
                  end

                  if score > best_score
                    best_score = score
                    signature = sig
                    target_name = cand
                    args_with_block = candidate_args
                  end
                end

                if !signature && !overloads.empty?
                  target_name = overloads.first
                  signature = @function_signatures[target_name]?
                end
              end

              unless signature
                target_name = base_name
                signature = @function_signatures[target_name]?
              end

              target_name ||= base_name

              if !signature && target_name != "__dragonstone_user_main"
                param_suffix = args.map { |a| a[:type].gsub("*", "P").gsub("%", "") }.join("_")
                target_name = "#{target_name}_#{param_suffix}" unless param_suffix.empty?
              end

              signature ||= ensure_function_signature(target_name)

              expected = signature[:param_types].size
              if expected == args_with_block.size + 1 && signature[:param_types].last == "i8*"
                args_with_block << block_arg
              end

              provided = args_with_block.size
              unless expected == provided
                raise "Function #{call.name} expects #{expected} arguments but got #{provided}"
              end

              coerced_args = args_with_block.map_with_index do |value, index|
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

            private def emit_receiver_call(ctx : FunctionContext, method_name : String, receiver : ValueRef, args : Array(ValueRef), block_value : ValueRef? = nil) : ValueRef
              packed_args = args.dup

              # Some runtime-provided methods (Array/Map/Range iterators, etc.) expect the
              # block to be passed via the dedicated `block_val` argument, not as part of
              # the argv buffer.
              use_runtime_block_arg = block_value && runtime_method_uses_block_arg?(method_name)

              unless use_runtime_block_arg
                packed_args << block_value if block_value
              end

              boxed = packed_args.map { |arg| box_value(ctx, arg) }
              buffer = allocate_pointer_buffer(ctx, boxed) || "null"
              name_ptr = materialize_string_pointer(ctx, method_name)

              block_arg = use_runtime_block_arg ? block_value.not_nil![:ref] : "null"
              receiver_ptr = ensure_pointer(ctx, receiver)
              argc = use_runtime_block_arg ? args.size : packed_args.size

              runtime_call(ctx, "i8*", @runtime[:method_invoke], [
                {type: "i8*", ref: receiver_ptr[:ref]},
                {type: "i8*", ref: name_ptr},
                {type: "i64", ref: argc.to_s},
                {type: "i8**", ref: buffer},
                {type: "i8*", ref: block_arg},
              ])
            end

            private def runtime_method_uses_block_arg?(method_name : String) : Bool
              case method_name
              when "each", "map", "select", "inject", "until"
                true
              else
                false
              end
            end

            private def emit_echo(ctx : FunctionContext, value : ValueRef, inspect : Bool = false)
              case value[:type]
              when "i8*"
                func = inspect ? @runtime[:display_value] : @runtime[:to_string]
                display = runtime_call(ctx, "i8*", func, [{type: "i8*", ref: value[:ref]}])
                ctx.io << "  call i32 @puts(i8* #{display[:ref]})\n"
              when "i32", "i64"
                emit_echo_integer(ctx, value)
              when "double"
                format_ptr = materialize_string_pointer(ctx, "%g\n")
                ctx.io << "  call i32 (i8*, ...) @printf(i8* #{format_ptr}, double #{value[:ref]})\n"
              when "float"
                format_ptr = materialize_string_pointer(ctx, "%g\n")
                reg = ctx.fresh("fpext")
                ctx.io << "  %#{reg} = fpext float #{value[:ref]} to double\n"
                ctx.io << "  call i32 (i8*, ...) @printf(i8* #{format_ptr}, double %#{reg})\n"
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

            private def emit_eecho(ctx : FunctionContext, value : ValueRef, inspect : Bool = false)
              case value[:type]
              when "i8*"
                func = inspect ? @runtime[:display_value] : @runtime[:to_string]
                display = runtime_call(ctx, "i8*", func, [{type: "i8*", ref: value[:ref]}])
                format_ptr = materialize_string_pointer(ctx, "%s")
                ctx.io << "  call i32 (i8*, ...) @printf(i8* #{format_ptr}, i8* #{display[:ref]})\n"
              when "i32", "i64"
                coerced = value[:type] == "i64" ? value : extend_to_i64(ctx, value)
                format_ptr = materialize_string_pointer(ctx, "%lld")
                ctx.io << "  call i32 (i8*, ...) @printf(i8* #{format_ptr}, i64 #{coerced[:ref]})\n"
              when "double"
                format_ptr = materialize_string_pointer(ctx, "%g")
                ctx.io << "  call i32 (i8*, ...) @printf(i8* #{format_ptr}, double #{value[:ref]})\n"
              when "float"
                format_ptr = materialize_string_pointer(ctx, "%g")
                reg = ctx.fresh("fpext")
                ctx.io << "  %#{reg} = fpext float #{value[:ref]} to double\n"
                ctx.io << "  call i32 (i8*, ...) @printf(i8* #{format_ptr}, double %#{reg})\n"
              when "i1"
                true_ptr = materialize_string_pointer(ctx, "true")
                false_ptr = materialize_string_pointer(ctx, "false")
                reg = ctx.fresh("boolstr")
                ctx.io << "  %#{reg} = select i1 #{value[:ref]}, i8* #{true_ptr}, i8* #{false_ptr}\n"
                format_ptr = materialize_string_pointer(ctx, "%s")
                ctx.io << "  call i32 (i8*, ...) @printf(i8* #{format_ptr}, i8* %#{reg})\n"
              else
                raise "eecho currently supports strings, integers, booleans, or doubles"
              end
            end

            private def emit_echo_integer(ctx : FunctionContext, value : ValueRef)
              coerced = value[:type] == "i64" ? value : extend_to_i64(ctx, value)
              format_ptr = materialize_string_pointer(ctx, "%lld\n")
              ctx.io << "  call i32 (i8*, ...) @printf(i8* #{format_ptr}, i64 #{coerced[:ref]})\n"
            end

            private def ensure_value_type(ctx : FunctionContext, value : ValueRef, expected : String) : ValueRef
              return value if value[:type] == expected

              if expected == "i8*"
                return box_value(ctx, value)
              end

              if expected == "%DSValue*" || expected == "%DSObject*"
                case value[:type]
                when expected
                  return value
                when "i8*"
                  cast = ctx.fresh("bitcast")
                  ctx.io << "  %#{cast} = bitcast i8* #{value[:ref]} to #{expected}\n"
                  return value_ref(expected, "%#{cast}")
                else
                  boxed = box_value(ctx, value)
                  cast = ctx.fresh("bitcast")
                  ctx.io << "  %#{cast} = bitcast i8* #{boxed[:ref]} to #{expected}\n"
                  return value_ref(expected, "%#{cast}")
                end
              end

              if expected.starts_with?("%") && value[:type] == "i8*"
                data_ptr = runtime_call(ctx, "i8*", @runtime[:unbox_struct], [{type: "i8*", ref: value[:ref]}])
                typed_ptr = ctx.fresh("struct_ptr")
                ctx.io << "  %#{typed_ptr} = bitcast i8* #{data_ptr[:ref]} to #{expected}*\n"
                reg = ctx.fresh("unboxed")
                ctx.io << "  %#{reg} = load #{expected}, #{expected}* %#{typed_ptr}\n"
                return value_ref(expected, "%#{reg}")
              end

              case expected
              when "i32"
                coerce_integer(ctx, value, 32)
              when "i64"
                coerce_integer(ctx, value, 64)
              when "i1"
                coerce_boolean_exact(ctx, value)
              when "float"
                ensure_float(ctx, value)
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

            private def emit_range_op(ctx : FunctionContext, operator : Symbol, lhs : ValueRef, rhs : ValueRef) : ValueRef
              # from_val = coerce_integer(ctx, lhs, 64)
              # to_val = coerce_integer(ctx, rhs, 64)
              lhs_ptr = ensure_pointer(ctx, lhs)
              rhs_ptr = ensure_pointer(ctx, rhs)

              exclusive = operator == :"..."
              reg = ctx.fresh("range")
              flag = exclusive ? "1" : "0"

              ctx.io << "  %#{reg} = call i8* @#{@runtime[:range_literal]}(i8* #{lhs_ptr[:ref]}, i8* #{rhs_ptr[:ref]}, i1 #{flag})\n"
              value_ref("i8*", "%#{reg}")
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
                if target_bits <= 32
                  unboxed = runtime_call(ctx, "i32", @runtime[:unbox_i32], [{type: "i8*", ref: value[:ref]}])
                  adjust_integer_width(ctx, unboxed, target_bits)
                else
                  unboxed = runtime_call(ctx, "i64", @runtime[:unbox_i64], [{type: "i8*", ref: value[:ref]}])
                  adjust_integer_width(ctx, unboxed, target_bits)
                end
              elsif value[:type].starts_with?("%") && value[:type].ends_with?("*")
                cast = ctx.fresh("anycast")
                ctx.io << "  %#{cast} = bitcast #{value[:type]} #{value[:ref]} to i8*\n"
                unboxed = runtime_call(ctx, "i64", @runtime[:unbox_i64], [{type: "i8*", ref: "%#{cast}"}])
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

            private def pointer_type?(type : String) : Bool
              type.ends_with?("*")
            end

            private def emit_pointer_comparison(ctx : FunctionContext, operator : Symbol, lhs : ValueRef, rhs : ValueRef) : ValueRef
              unless operator == :"==" || operator == :"!="
                raise "Operator #{operator} not implemented for reference types"
              end

              lhs_ptr = ensure_pointer(ctx, lhs)
              rhs_ptr = ensure_pointer(ctx, rhs)

              cmp = runtime_call(ctx, "i1", @runtime[:case_compare], [
                {type: "i8*", ref: lhs_ptr[:ref]},
                {type: "i8*", ref: rhs_ptr[:ref]},
              ])

              if operator == :"!="
                emit_boolean_not(ctx, cmp)
              else
                cmp
              end
            end

            private def ensure_boolean(ctx : FunctionContext, value : ValueRef) : ValueRef
              return value if value[:type] == "i1"

              if integer_type?(value[:type])
                reg = ctx.fresh("tobool")
                ctx.io << "  %#{reg} = icmp ne #{value[:type]} #{value[:ref]}, 0\n"
                value_ref("i1", "%#{reg}")
              elsif value[:type].ends_with?("*")
                # reg = ctx.fresh("ptrbool")
                # ctx.io << "  %#{reg} = icmp ne #{value[:type]} #{value[:ref]}, null\n"
                # value_ref("i1", "%#{reg}")
                runtime_call(ctx, "i1", @runtime[:is_truthy], [{type: "i8*", ref: value[:ref]}])
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
                elsif value[:type].starts_with?("%") && value[:type].ends_with?("*")
                  cast = ctx.fresh("anycast")
                  ctx.io << "  %#{cast} = bitcast #{value[:type]} #{value[:ref]} to i8*\n"
                  runtime_call(ctx, "double", @runtime[:unbox_float], [{type: "i8*", ref: "%#{cast}"}])
                else
                  raise "Cannot treat #{value[:type]} as floating-point"
                end
              end
            end

            private def ensure_float(ctx : FunctionContext, value : ValueRef) : ValueRef
              case value[:type]
              when "float"
                value
              when "double"
                reg = ctx.fresh("fptrunc")
                ctx.io << "  %#{reg} = fptrunc double #{value[:ref]} to float\n"
                value_ref("float", "%#{reg}")
              when "i8*"
                double_value = runtime_call(ctx, "double", @runtime[:unbox_float], [{type: "i8*", ref: value[:ref]}])
                reg = ctx.fresh("fptrunc")
                ctx.io << "  %#{reg} = fptrunc double #{double_value[:ref]} to float\n"
                value_ref("float", "%#{reg}")
              else
                if integer_type?(value[:type])
                  reg = ctx.fresh("sitofp")
                  ctx.io << "  %#{reg} = sitofp #{value[:type]} #{value[:ref]} to float\n"
                  value_ref("float", "%#{reg}")
                elsif value[:type].starts_with?("%") && value[:type].ends_with?("*")
                  cast = ctx.fresh("anycast")
                  ctx.io << "  %#{cast} = bitcast #{value[:type]} #{value[:ref]} to i8*\n"
                  double_value = runtime_call(ctx, "double", @runtime[:unbox_float], [{type: "i8*", ref: "%#{cast}"}])
                  reg = ctx.fresh("fptrunc")
                  ctx.io << "  %#{reg} = fptrunc double #{double_value[:ref]} to float\n"
                  value_ref("float", "%#{reg}")
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
                            when :*        then "fmul"
                            when :/, :"//" then "fdiv"
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
                unbox_bool_i1(ctx, value)
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
              return "i8*" unless type_expr
              case type_expr
              when AST::SimpleTypeExpression
                name = type_expr.name
                case name
                when "Int32", "int", "int32"     then "i32"
                when "Int64", "int64"            then "i64"
                when "Bool", "bool"              then "i1"
                when "Float32", "float32"        then "float"
                when "Float64", "Float", "float", "float64" then "double"
                when "String", "str"             then "i8*"
                when "Char", "char"              then "i8*"
                when "para", "Para"              then "i8*" # Treat para types as block handles
                # when "Void", "void"                 then "void"
                else
                  if struct_type?(name)
                    llvm_struct_name(name)
                  else
                    pointer_type_for("%DSObject")
                  end
                end
              when AST::GenericTypeExpression
                base = type_expr.name
                case base
                when "para", "Para"
                  "i8*"
                else
                  pointer_type_for("%DSObject")
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
                "i8*"
              end
            end

            private def llvm_param_type(type_expr : AST::TypeExpression?) : String
              return "i8*" unless type_expr
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
              str.gsub("\\", "\\5C").gsub("\"", "\\22").gsub("\n", "\\0A").gsub("\t", "\\09")
            end

            private def ensure_function_signature(name : String) : FunctionSignature
              if signature = @function_signatures[name]?
                return signature
              end

              candidate = @function_signatures.find { |k, v| k.starts_with?("#{name}_") }
              if candidate
                return candidate[1]
              end

              if info = @analysis.symbol_table.lookup(name)
                if info.kind == Language::Sema::SymbolKind::Function
                  raise "Function #{name} is declared but no definition was provided for LLVM emission"
                end
              end

              raise "Unknown function #{name}"
            end

            private def value_ref(type : String, ref : String, constant : Bool = false) : ValueRef
              {type: type, ref: ref, constant: constant}
            end

            private def pointer_type_for(type : String) : String
              "#{type}*"
            end

            private def mangle_function_name(base : String, param_types : Array(String)) : String
              return base if base == "__dragonstone_user_main"
              suffix = param_types.map { |t| t.gsub("%", "").gsub("*", "P") }.join("_")
              suffix.empty? ? base : "#{base}_#{suffix}"
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
                {type: "i8**", ref: buffer},
              ])
            end

            private def generate_variable_reference(ctx : FunctionContext, name : String) : ValueRef
              full_name = qualify_name(name)

              if @globals.includes?(full_name)
                reg = ctx.fresh("load_global")
                global_name = mangle_global_name(full_name)
                ctx.io << "  %#{reg} = load i8*, i8** @\"#{global_name}\"\n"
                return value_ref("i8*", "%#{reg}")
              end

              if constant_symbol?(name)
                return emit_constant_lookup(ctx, [full_name])
              end

              if ctx.locals.has_key?(name)
                return load_local(ctx, name)
              end

              # Ruby-style bare identifiers inside a class/module can mean a 0-arg method call.
              # Example: `next_char` in the TOML lexer (no parentheses).
              if !@namespace_stack.empty?
                class_name = @namespace_stack.join("::")
                base_name = "#{llvm_struct_symbol(class_name)}_#{name}"

                if overloads = @function_overloads[base_name]?
                  self_val = if ctx.locals.has_key?("self")
                               load_local(ctx, "self")
                             else
                               value_ref("i8*", "null", constant: true)
                             end

                  best_score = -1
                  signature = nil
                  target_name = nil
                  args_with_block = nil

                  overloads.each do |cand|
                    next unless sig = @function_signatures[cand]?
                    expected_params = sig[:param_types]

                    candidate_args = [self_val] of ValueRef
                    if expected_params.size == candidate_args.size + 1 && expected_params.last == "i8*"
                      candidate_args << value_ref("i8*", "null", constant: true)
                    elsif expected_params.size != candidate_args.size
                      next
                    end

                    score = 0
                    candidate_args.each_with_index do |val, idx|
                      exp_type = expected_params[idx]
                      if val[:constant] && val[:ref] == "null"
                        score += (exp_type == "i8*" ? 1 : 0)
                      elsif val[:type] == exp_type
                        score += 3
                      elsif val[:type] == "i8*" && (exp_type == "%DSValue*" || exp_type == "%DSObject*")
                        score += 2
                      end
                    end

                    if score > best_score
                      best_score = score
                      signature = sig
                      target_name = cand
                      args_with_block = candidate_args
                    end
                  end

                  if signature && target_name && args_with_block
                    casted_args = args_with_block.map_with_index do |val, i|
                      ensure_value_type(ctx, val, signature[:param_types][i])
                    end

                    arg_source = casted_args.map { |v| "#{v[:type]} #{v[:ref]}" }.join(", ")
                    return_type = signature[:return_type]

                    if return_type == "void"
                      ctx.io << "  call void @\"#{target_name}\"(#{arg_source})\n"
                      return value_ref("i8*", "null", constant: true)
                    else
                      reg = ctx.fresh("call")
                      ctx.io << "  %#{reg} = call #{return_type} @\"#{target_name}\"(#{arg_source})\n"
                      return value_ref(return_type, "%#{reg}")
                    end
                  end
                end
              end

              if name == "self"
                return runtime_call(ctx, "i8*", @runtime[:root_self], [] of CallArg)
              elsif name == "ffi"
                return value_ref("i8*", materialize_string_pointer(ctx, "ffi"), constant: true)
              elsif receiver = resolve_implicit_receiver(ctx, name)
                if struct_name = struct_name_for_value(receiver)
                  return emit_struct_method_dispatch(ctx, struct_name, receiver, name, [] of ValueRef)
                else
                  return emit_receiver_call(ctx, name, receiver, [] of ValueRef)
                end
              else
                raise "Undefined local #{name}"
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
              full_name = qualify_name(node.name)

              @class_name_occurrences[full_name] += 1
              count = @class_name_occurrences[full_name]
              unique_ns = count > 1 ? "#{node.name}_#{count}" : node.name

              name_ptr = materialize_string_pointer(ctx, full_name)

              reg = ctx.fresh("class")
              ctx.io << "  %#{reg} = call i8* @#{@runtime[:define_class]}(i8* #{name_ptr})\n"

              if @globals.includes?(full_name)
                global_name = mangle_global_name(full_name)
                ctx.io << "  store i8* %#{reg}, i8** @\"#{global_name}\"\n"
              end

              if superclass_name = node.superclass
                super_full_name = if superclass_name.includes?("::")
                                    superclass_name
                                  else
                                    qualify_name(superclass_name)
                                  end

                superclass_val = if @globals.includes?(super_full_name)
                                   global_name = mangle_global_name(super_full_name)
                                   load_reg = ctx.fresh("superclass")
                                   ctx.io << "  %#{load_reg} = load i8*, i8** @\"#{global_name}\"\n"
                                   value_ref("i8*", "%#{load_reg}")
                                 else
                                   emit_constant_lookup(ctx, [super_full_name])
                                 end

                superclass_ptr = ensure_pointer(ctx, superclass_val)
                ctx.io << "  call void @#{@runtime[:set_superclass]}(i8* %#{reg}, i8* #{superclass_ptr[:ref]})\n"
              end

              with_namespace(unique_ns) do
                generate_block(ctx, node.body)
              end
              false
            end

            private def generate_module_definition(ctx : FunctionContext, node : AST::ModuleDefinition) : Bool
              full_name = qualify_name(node.name)

              @class_name_occurrences[full_name] += 1
              count = @class_name_occurrences[full_name]
              unique_ns = count > 1 ? "#{node.name}_#{count}" : node.name

              name_ptr = materialize_string_pointer(ctx, full_name)

              reg = ctx.fresh("module")
              ctx.io << "  %#{reg} = call i8* @#{@runtime[:define_module]}(i8* #{name_ptr})\n"

              if @globals.includes?(full_name)
                global_name = mangle_global_name(full_name)
                ctx.io << "  store i8* %#{reg}, i8** @\"#{global_name}\"\n"
              end

              with_namespace(unique_ns) do
                generate_block(ctx, node.body)
              end
              false
            end

            private def generate_extend_statement(ctx : FunctionContext, node : AST::ExtendStatement) : Nil
              return if @namespace_stack.empty?
              container_name = @namespace_stack.join("::")
              return unless @globals.includes?(container_name)

              global_name = mangle_global_name(container_name)
              container_reg = ctx.fresh("extend_container")
              ctx.io << "  %#{container_reg} = load i8*, i8** @\"#{global_name}\"\n"

              node.targets.each do |target|
                target_val = ensure_pointer(ctx, generate_expression(ctx, target))
                ctx.io << "  call void @#{@runtime[:extend_container]}(i8* %#{container_reg}, i8* #{target_val[:ref]})\n"
              end
            end

            private def emit_namespace_placeholder(ctx : FunctionContext, name : String)
              full_name = qualify_name(name)
              name_ptr = materialize_string_pointer(ctx, full_name)
              runtime_call(ctx, "i8*", @runtime[:constant_define], [
                {type: "i8*", ref: name_ptr},
                {type: "i8*", ref: "null"},
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

              struct_type = llvm_struct_name(struct_name)
              current_ref = "zeroinitializer"
              fields.each_with_index do |target_type_expr, index|
                if index < args.size
                  arg = args[index]
                  target_type = target_type_expr ? llvm_type_of(target_type_expr) : "i8*"
                  coerced = ensure_value_type(ctx, arg, target_type)
                  reg = ctx.fresh("structinit")
                  base = current_ref == "zeroinitializer" ? "zeroinitializer" : current_ref
                  ctx.io << "  %#{reg} = insertvalue #{struct_type} #{base}, #{coerced[:type]} #{coerced[:ref]}, #{index}\n"
                  current_ref = "%#{reg}"
                else
                  target_type = target_type_expr ? llvm_type_of(target_type_expr) : "i8*"
                  zero = zero_value(target_type)
                  reg = ctx.fresh("structinit")
                  base = current_ref == "zeroinitializer" ? "zeroinitializer" : current_ref
                  ctx.io << "  %#{reg} = insertvalue #{struct_type} #{base}, #{target_type} #{zero}, #{index}\n"
                  current_ref = "%#{reg}"
                end
              end

              if args.size > fields.size
                raise "Struct #{struct_name} expects #{fields.size} arguments but got #{args.size}"
              end
              args.each_with_index do |arg, index|
                target_type_expr = fields[index]
                target_type = target_type_expr ? llvm_type_of(target_type_expr) : "i8*"
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
              boxed = box_value(ctx, value)
              runtime_call(ctx, "i8*", @runtime[:to_string], [{type: "i8*", ref: boxed[:ref]}])
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
              field_type = field_type_expr ? llvm_type_of(field_type_expr) : "i8*"
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
              call_args = [receiver] + args
              mangled_symbol = mangle_function_name(function_symbol, call_args.map { |arg| arg[:type] })
              signature = ensure_function_signature(mangled_symbol)
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
                ctx.io << "  call void @\"#{mangled_symbol}\"(#{arg_source})\n"
                value_ref("i8*", "null", constant: true)
              else
                reg = ctx.fresh("structcall")
                ctx.io << "  %#{reg} = call #{return_type} @\"#{mangled_symbol}\"(#{arg_source})\n"
                value_ref(return_type, "%#{reg}")
              end
            end

            def pre_scan_definitions(nodes : Array(AST::Node))
              nodes.each { |node| scan_node(node) }
            end

            private def scan_node(node : AST::Node)
              case node
              when AST::ClassDefinition
                full_name = qualify_name(node.name)
                @globals << full_name
                with_namespace(node.name) do
                  node.body.each { |stmt| scan_node(stmt) }
                end
              when AST::ModuleDefinition
                full_name = qualify_name(node.name)
                @globals << full_name
                with_namespace(node.name) do
                  node.body.each { |stmt| scan_node(stmt) }
                end
              when AST::StructDefinition
                full_name = qualify_name(node.name)
                with_namespace(node.name) do
                  node.body.each { |stmt| scan_node(stmt) }
                end
              when AST::FunctionDef
                receiver_type = nil
                if node.receiver
                  receiver_node = node.receiver.as(AST::Node)
                  if receiver_node.is_a?(AST::Variable) && receiver_node.name == "self"
                    if !@namespace_stack.empty?
                      receiver_type = @namespace_stack.join("::")
                      @function_receivers[node] = receiver_type
                    end
                  end
                end

                current_ns = @namespace_stack.empty? ? "" : @namespace_stack.join("::")
                method_name = node.name

                global_name = if receiver_type
                                "#{receiver_type}_#{method_name}"
                              elsif !current_ns.empty?
                                "#{current_ns}::#{method_name}"
                              else
                                method_name
                              end

                mangled_name = mangle_global_name(global_name)
                @function_names[node] = mangled_name
                @function_namespaces[node] = @namespace_stack.dup

                params = node.typed_parameters.map { |p| llvm_param_type(p.type) }
                if receiver_type || !current_ns.empty?
                  params.unshift("i8*")
                end

                return_type = llvm_type_of(node.return_type)
                @function_signatures[mangled_name] = {
                  return_type: return_type,
                  param_types: params,
                  param_typed: params.map { true },
                }
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
