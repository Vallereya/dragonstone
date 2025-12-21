module Dragonstone
  module Language
    module Transforms
      module DefaultArguments
        extend self

        record FunctionDefaults,
          parameters : Array(AST::TypedParameter),
          required_count : Int32

        def apply(program : AST::Program) : AST::Program
          defaults = collect_defaults(program.statements)
          rewritten = program.statements.map { |stmt| rewrite_node(stmt, defaults) }
          AST::Program.new(rewritten, program.use_decls, location: program.location)
        end

        private def collect_defaults(nodes : Array(AST::Node)) : Hash(String, FunctionDefaults)
          index = {} of String => FunctionDefaults
          nodes.each { |node| collect_node_defaults(node, index) }
          index
        end

        private def collect_node_defaults(node : AST::Node, index : Hash(String, FunctionDefaults)) : Nil
          case node
          when AST::FunctionDef
            if node.receiver.nil?
              index[node.name] = FunctionDefaults.new(node.typed_parameters, required_count(node.typed_parameters))
            end
          when AST::ClassDefinition, AST::StructDefinition, AST::ModuleDefinition
            node.body.each { |stmt| collect_node_defaults(stmt, index) }
          else
            # no-op
          end
        end

        private def required_count(parameters : Array(AST::TypedParameter)) : Int32
          idx = parameters.index { |param| !!param.default_value }
          idx ? idx : parameters.size
        end

        private def rewrite_node(node : AST::Node, defaults : Hash(String, FunctionDefaults)) : AST::Node
          case node
          when AST::Assignment
            AST::Assignment.new(node.name, rewrite_node(node.value, defaults), node.operator, node.type_annotation, location: node.location)
          when AST::ConstantDeclaration
            AST::ConstantDeclaration.new(node.name, rewrite_node(node.value, defaults), node.type_annotation, location: node.location)
          when AST::BinaryOp
            AST::BinaryOp.new(rewrite_node(node.left, defaults), node.operator, rewrite_node(node.right, defaults), location: node.location)
          when AST::UnaryOp
            AST::UnaryOp.new(node.operator, rewrite_node(node.operand, defaults), location: node.location)
          when AST::ArrayLiteral
            AST::ArrayLiteral.new(
              node.elements.map { |e| rewrite_node(e, defaults) },
              node.element_type,
              location: node.location
            )
          when AST::TupleLiteral
            AST::TupleLiteral.new(node.elements.map { |e| rewrite_node(e, defaults) }, location: node.location)
          when AST::NamedTupleLiteral
            entries = node.entries.map do |entry|
              AST::NamedTupleEntry.new(entry.name, rewrite_node(entry.value, defaults).as(AST::Node), entry.type_annotation, entry.location)
            end
            AST::NamedTupleLiteral.new(entries, location: node.location)
          when AST::MapLiteral
            entries = [] of Tuple(AST::Node, AST::Node)
            node.entries.each do |(k, v)|
              entries << {rewrite_node(k, defaults).as(AST::Node), rewrite_node(v, defaults).as(AST::Node)}
            end
            AST::MapLiteral.new(entries, node.key_type, node.value_type, location: node.location)
          when AST::IndexAccess
            AST::IndexAccess.new(rewrite_node(node.object, defaults), rewrite_node(node.index, defaults), nil_safe: node.nil_safe, location: node.location)
          when AST::IndexAssignment
            AST::IndexAssignment.new(
              rewrite_node(node.object, defaults),
              rewrite_node(node.index, defaults),
              rewrite_node(node.value, defaults),
              operator: node.operator,
              nil_safe: node.nil_safe,
              location: node.location
            )
          when AST::AttributeAssignment
            AST::AttributeAssignment.new(
              rewrite_node(node.receiver, defaults),
              node.name,
              rewrite_node(node.value, defaults),
              operator: node.operator,
              location: node.location
            )
          when AST::MethodCall
            rewrite_method_call(node, defaults)
          when AST::IfStatement
            then_block = node.then_block.map { |n| rewrite_node(n, defaults) }
            elsif_blocks = node.elsif_blocks.map do |clause|
              AST::ElsifClause.new(
                rewrite_node(clause.condition, defaults),
                clause.block.map { |n| rewrite_node(n, defaults) },
                location: clause.location
              )
            end
            else_block = node.else_block.try { |block| block.map { |n| rewrite_node(n, defaults) } }
            AST::IfStatement.new(rewrite_node(node.condition, defaults), then_block, elsif_blocks, else_block, location: node.location)
          when AST::UnlessStatement
            body = node.body.map { |n| rewrite_node(n, defaults) }
            else_block = node.else_block.try { |block| block.map { |n| rewrite_node(n, defaults) } }
            AST::UnlessStatement.new(rewrite_node(node.condition, defaults), body, else_block, location: node.location)
          when AST::WhileStatement
            AST::WhileStatement.new(rewrite_node(node.condition, defaults), node.block.map { |n| rewrite_node(n, defaults) }, location: node.location)
          when AST::CaseStatement
            expr = node.expression.try { |e| rewrite_node(e, defaults) }
            whens = node.when_clauses.map do |clause|
              AST::WhenClause.new(
                clause.conditions.map { |c| rewrite_node(c, defaults) },
                clause.block.map { |n| rewrite_node(n, defaults) },
                location: clause.location
              )
            end
            else_block = node.else_block.try { |block| block.map { |n| rewrite_node(n, defaults) } }
            AST::CaseStatement.new(expr, whens, else_block, location: node.location)
          when AST::ReturnStatement
            AST::ReturnStatement.new(node.value.try { |v| rewrite_node(v, defaults) }, location: node.location)
          when AST::YieldExpression
            AST::YieldExpression.new(node.arguments.map { |arg| rewrite_node(arg, defaults) }, location: node.location)
          when AST::BeginExpression
            body = node.body.map { |n| rewrite_node(n, defaults) }
            rescue_clauses = node.rescue_clauses.map do |clause|
              AST::RescueClause.new(
                clause.exceptions,
                clause.exception_variable,
                clause.body.map { |n| rewrite_node(n, defaults) },
                location: clause.location
              )
            end
            ensure_block = node.ensure_block.try { |block| block.map { |n| rewrite_node(n, defaults) } }
            else_block = node.else_block.try { |block| block.map { |n| rewrite_node(n, defaults) } }
            AST::BeginExpression.new(body, rescue_clauses, else_block: else_block, ensure_block: ensure_block, location: node.location)
          when AST::RaiseExpression
            AST::RaiseExpression.new(node.expression.try { |v| rewrite_node(v, defaults) }, location: node.location)
          when AST::DebugEcho
            AST::DebugEcho.new(rewrite_node(node.expression, defaults), node.inline, location: node.location)
          when AST::FunctionDef
            body = node.body.map { |n| rewrite_node(n, defaults) }
            rescues = node.rescue_clauses.map do |clause|
              AST::RescueClause.new(
                clause.exceptions,
                clause.exception_variable,
                clause.body.map { |n| rewrite_node(n, defaults) },
                location: clause.location
              )
            end
            receiver = node.receiver.try { |r| rewrite_node(r, defaults) }
            AST::FunctionDef.new(
              node.name,
              node.typed_parameters,
              body,
              rescues,
              node.return_type,
              visibility: node.visibility,
              receiver: receiver,
              is_abstract: node.abstract?,
              annotations: node.annotations,
              location: node.location
            )
          when AST::FunctionLiteral
            body = node.body.map { |n| rewrite_node(n, defaults) }
            rescues = node.rescue_clauses.map do |clause|
              AST::RescueClause.new(
                clause.exceptions,
                clause.exception_variable,
                clause.body.map { |n| rewrite_node(n, defaults) },
                location: clause.location
              )
            end
            AST::FunctionLiteral.new(node.typed_parameters, body, rescues, node.return_type, location: node.location)
          when AST::ParaLiteral
            body = node.body.map { |n| rewrite_node(n, defaults) }
            rescues = node.rescue_clauses.map do |clause|
              AST::RescueClause.new(
                clause.exceptions,
                clause.exception_variable,
                clause.body.map { |n| rewrite_node(n, defaults) },
                location: clause.location
              )
            end
            AST::ParaLiteral.new(node.typed_parameters, body, rescues, node.return_type, location: node.location)
          when AST::BlockLiteral
            AST::BlockLiteral.new(node.typed_parameters, node.body.map { |n| rewrite_node(n, defaults) }, location: node.location)
          when AST::WithExpression
            AST::WithExpression.new(rewrite_node(node.receiver, defaults), node.body.map { |n| rewrite_node(n, defaults) }, location: node.location)
          when AST::ClassDefinition
            AST::ClassDefinition.new(
              node.name,
              node.body.map { |n| rewrite_node(n, defaults) },
              node.superclass,
              is_abstract: node.abstract?,
              annotations: node.annotations,
              location: node.location
            )
          when AST::StructDefinition
            AST::StructDefinition.new(node.name, node.body.map { |n| rewrite_node(n, defaults) }, annotations: node.annotations, location: node.location)
          when AST::ModuleDefinition
            AST::ModuleDefinition.new(node.name, node.body.map { |n| rewrite_node(n, defaults) }, annotations: node.annotations, location: node.location)
          when AST::EnumDefinition
            members = node.members.map do |m|
              AST::EnumMember.new(m.name, m.value.try { |v| rewrite_node(v, defaults) }, location: m.location)
            end
            AST::EnumDefinition.new(node.name, members, value_name: node.value_name, value_type: node.value_type, annotations: node.annotations, location: node.location)
          when AST::ExtendStatement
            AST::ExtendStatement.new(node.targets.map { |t| rewrite_node(t, defaults) }, location: node.location)
          else
            node
          end
        end

        private def rewrite_method_call(node : AST::MethodCall, defaults : Hash(String, FunctionDefaults)) : AST::Node
          receiver = node.receiver.try { |r| rewrite_node(r, defaults) }
          rewritten_args = node.arguments.map { |arg| rewrite_node(arg, defaults) }

          # Only expand defaults for bare function calls (no receiver).
          return AST::MethodCall.new(node.name, rewritten_args, receiver, location: node.location) unless receiver.nil?

          info = defaults[node.name]?
          return AST::MethodCall.new(node.name, rewritten_args, receiver, location: node.location) unless info

          block_arg = (!rewritten_args.empty? && rewritten_args.last.is_a?(AST::BlockLiteral)) ? rewritten_args.last.as(AST::BlockLiteral) : nil
          call_args = block_arg ? rewritten_args[0...-1] : rewritten_args

          provided = call_args.size
          total = info.parameters.size
          required = info.required_count

          return AST::MethodCall.new(node.name, rewritten_args, receiver, location: node.location) if provided >= total

          if provided < required
            return AST::MethodCall.new(node.name, rewritten_args, receiver, location: node.location)
          end

          expanded = call_args.dup
          (provided...total).each do |idx|
            default_node = info.parameters[idx].default_value
            break unless default_node
            expanded << default_node
          end

          final_args = block_arg ? (expanded + [block_arg]) : expanded
          AST::MethodCall.new(node.name, final_args, receiver, location: node.location)
        end
      end
    end
  end
end
