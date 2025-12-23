require "set"
require "../ast/ast"
require "../lexer/lexer"
require "../parser/parser"
require "../diagnostics/errors"

module Dragonstone
    module Language
        module Transforms
            # Lowers `let` and `fix` declarations into regular assignments by:
            # - Mangling the declared name to simulate block scoping.
            # - Rewriting references to point at the mangled name within the scope.
            # - Rejecting reassignment of a `let`/`fix` binding (binding immutability).
            module LexicalBindings
                extend self

                private class Counter
                    property value : Int32

                    def initialize(@value : Int32 = 0)
                    end
                end

                private record ContainerEntry, kind : Symbol, name : String

                private record Scope,
                    bindings : Hash(String, String),
                    shadowed : Set(String),
                    immutable : Set(String)

                def apply(program : AST::Program) : AST::Program
                    scopes = [] of Scope
                    counter = Counter.new
                    containers = [] of ContainerEntry
                    rewritten = rewrite_node_array(program.statements, scopes, counter, containers)
                    AST::Program.new(rewritten, program.use_decls, location: program.location)
                end

                private def rewrite_node_array(
                    nodes : Array(AST::Node),
                    scopes : Array(Scope),
                    counter : Counter,
                    containers : Array(ContainerEntry),
                    shadowed : Set(String)? = nil
                ) : Array(AST::Node)
                    scopes << Scope.new(::Hash(String, String).new, ::Set(String).new, ::Set(String).new)
                    if shadowed_names = shadowed
                        shadowed_names.each { |name| scopes.last.shadowed.add(name) }
                    end

                    begin
                        nodes.flat_map do |node|
                            rewrite_statement(node, scopes, counter, containers)
                        end
                    ensure
                        scopes.pop
                    end
                end

                private def rewrite_statement(node : AST::Node, scopes : Array(Scope), counter : Counter, containers : Array(ContainerEntry)) : Array(AST::Node)
                    case node
                    when AST::LetDeclaration
                        rewritten_value = rewrite_node(node.value, scopes, counter, containers)
                        mangled = fresh_name("__ds_let", node.name, counter)
                        scopes.last.bindings[node.name] = mangled
                        ([AST::Assignment.new(mangled, rewritten_value, operator: nil, type_annotation: node.type_annotation, location: node.location)] of AST::Node)
                    when AST::FixDeclaration
                        rewritten_value = rewrite_node(node.value, scopes, counter, containers)
                        mangled = fresh_name("__ds_fix", node.name, counter)
                        scopes.last.bindings[node.name] = mangled
                        scopes.last.immutable.add(node.name)
                        ([AST::Assignment.new(mangled, rewritten_value, operator: nil, type_annotation: node.type_annotation, location: node.location)] of AST::Node)
                    else
                        [rewrite_node(node, scopes, counter, containers)]
                    end
                end

                private def rewrite_node(node : AST::Node, scopes : Array(Scope), counter : Counter, containers : Array(ContainerEntry)) : AST::Node
                    case node
                    when AST::Program
                        AST::Program.new(rewrite_node_array(node.statements, scopes, counter, containers), node.use_decls, location: node.location)
                    when AST::Assignment
                        validate_mutation!(node.name, node.location, scopes)
                        name = resolve_binding_name(node.name, scopes)
                        value = rewrite_node(node.value, scopes, counter, containers)
                        AST::Assignment.new(name, value, operator: node.operator, type_annotation: node.type_annotation, location: node.location)
                    when AST::ConstantDeclaration
                        value = rewrite_node(node.value, scopes, counter, containers)
                        AST::ConstantDeclaration.new(node.name, value, node.type_annotation, location: node.location)
                    when AST::BinaryOp
                        left = rewrite_node(node.left, scopes, counter, containers)
                        right = rewrite_node(node.right, scopes, counter, containers)
                        AST::BinaryOp.new(left, node.operator, right, location: node.location)
                    when AST::UnaryOp
                        operand = rewrite_node(node.operand, scopes, counter, containers)
                        AST::UnaryOp.new(node.operator, operand, location: node.location)
                    when AST::ArrayLiteral
                        elems = node.elements.map { |e| rewrite_node(e, scopes, counter, containers) }
                        AST::ArrayLiteral.new(elems, node.element_type, location: node.location)
                    when AST::TupleLiteral
                        elems = node.elements.map { |e| rewrite_node(e, scopes, counter, containers) }
                        AST::TupleLiteral.new(elems, location: node.location)
                    when AST::NamedTupleLiteral
                        entries = node.entries.map do |entry|
                            AST::NamedTupleEntry.new(
                                entry.name,
                                rewrite_node(entry.value, scopes, counter, containers),
                                entry.type_annotation,
                                entry.location
                            )
                        end
                        AST::NamedTupleLiteral.new(entries, location: node.location)
                    when AST::MapLiteral
                        entries = [] of Tuple(AST::Node, AST::Node)
                        node.entries.each do |(k, v)|
                            entries << {
                                rewrite_node(k, scopes, counter, containers).as(AST::Node),
                                rewrite_node(v, scopes, counter, containers).as(AST::Node),
                            }
                        end
                        AST::MapLiteral.new(entries, node.key_type, node.value_type, location: node.location)
                    when AST::IndexAccess
                        object = rewrite_node(node.object, scopes, counter, containers)
                        index = rewrite_node(node.index, scopes, counter, containers)
                        AST::IndexAccess.new(object, index, nil_safe: node.nil_safe, location: node.location)
                    when AST::IndexAssignment
                        object = rewrite_node(node.object, scopes, counter, containers)
                        index = rewrite_node(node.index, scopes, counter, containers)
                        value = rewrite_node(node.value, scopes, counter, containers)
                        AST::IndexAssignment.new(object, index, value, operator: node.operator, nil_safe: node.nil_safe, location: node.location)
                    when AST::AttributeAssignment
                        receiver = rewrite_node(node.receiver, scopes, counter, containers)
                        value = rewrite_node(node.value, scopes, counter, containers)
                        AST::AttributeAssignment.new(receiver, node.name, value, operator: node.operator, location: node.location)
                    when AST::MethodCall
                        receiver = node.receiver ? rewrite_node(node.receiver.not_nil!, scopes, counter, containers) : nil
                        args = node.arguments.map { |a| rewrite_node(a, scopes, counter, containers) }
                        AST::MethodCall.new(node.name, args, receiver, location: node.location)
                    when AST::SuperCall
                        args = node.arguments.map { |a| rewrite_node(a, scopes, counter, containers) }
                        AST::SuperCall.new(args, explicit_arguments: node.explicit_arguments?, location: node.location)
                    when AST::IfStatement
                        condition = rewrite_node(node.condition, scopes, counter, containers)
                        then_block = rewrite_node_array(node.then_block, scopes, counter, containers)
                        elsif_blocks = node.elsif_blocks.map { |clause| rewrite_elsif_clause(clause, scopes, counter, containers) }
                        else_block = node.else_block.try { |block| rewrite_node_array(block, scopes, counter, containers) }
                        AST::IfStatement.new(condition, then_block, elsif_blocks, else_block, location: node.location)
                    when AST::UnlessStatement
                        condition = rewrite_node(node.condition, scopes, counter, containers)
                        body = rewrite_node_array(node.body, scopes, counter, containers)
                        else_block = node.else_block.try { |block| rewrite_node_array(block, scopes, counter, containers) }
                        AST::UnlessStatement.new(condition, body, else_block, location: node.location)
                    when AST::WhileStatement
                        condition = rewrite_node(node.condition, scopes, counter, containers)
                        body = rewrite_node_array(node.block, scopes, counter, containers)
                        AST::WhileStatement.new(condition, body, location: node.location)
                    when AST::BeginExpression
                        body = rewrite_node_array(node.body, scopes, counter, containers)
                        rescues = node.rescue_clauses.map { |clause| rewrite_rescue_clause(clause, scopes, counter, containers) }
                        else_block = node.else_block.try { |block| rewrite_node_array(block, scopes, counter, containers) }
                        ensure_block = node.ensure_block.try { |block| rewrite_node_array(block, scopes, counter, containers) }
                        AST::BeginExpression.new(body, rescues, else_block, ensure_block, location: node.location)
                    when AST::CaseStatement
                        expr = node.expression ? rewrite_node(node.expression.not_nil!, scopes, counter, containers) : nil
                        whens = node.when_clauses.map { |clause| rewrite_when_clause(clause, scopes, counter, containers) }
                        else_block = node.else_block.try { |block| rewrite_node_array(block, scopes, counter, containers) }
                        AST::CaseStatement.new(expr, whens, else_block, location: node.location)
                    when AST::WithExpression
                        receiver = rewrite_node(node.receiver, scopes, counter, containers)
                        body = rewrite_node_array(node.body, scopes, counter, containers)
                        AST::WithExpression.new(receiver, body, location: node.location)
                    when AST::YieldExpression
                        args = node.arguments.map { |a| rewrite_node(a, scopes, counter, containers) }
                        AST::YieldExpression.new(args, location: node.location)
                    when AST::ConditionalExpression
                        cond = rewrite_node(node.condition, scopes, counter, containers)
                        then_branch = rewrite_node(node.then_branch, scopes, counter, containers)
                        else_branch = rewrite_node(node.else_branch, scopes, counter, containers)
                        AST::ConditionalExpression.new(cond, then_branch, else_branch, location: node.location)
                    when AST::RaiseExpression
                        expr = node.expression ? rewrite_node(node.expression.not_nil!, scopes, counter, containers) : nil
                        AST::RaiseExpression.new(expr, location: node.location)
                    when AST::ReturnStatement
                        value = node.value ? rewrite_node(node.value.not_nil!, scopes, counter, containers) : nil
                        AST::ReturnStatement.new(value, location: node.location)
                    when AST::DebugEcho
                        expr = rewrite_node(node.expression, scopes, counter, containers)
                        AST::DebugEcho.new(expr, node.inline, location: node.location)
                    when AST::BreakStatement
                        condition = node.condition ? rewrite_node(node.condition.not_nil!, scopes, counter, containers) : nil
                        AST::BreakStatement.new(condition, node.condition_type, location: node.location)
                    when AST::NextStatement
                        condition = node.condition ? rewrite_node(node.condition.not_nil!, scopes, counter, containers) : nil
                        AST::NextStatement.new(condition, node.condition_type, location: node.location)
                    when AST::RedoStatement
                        condition = node.condition ? rewrite_node(node.condition.not_nil!, scopes, counter, containers) : nil
                        AST::RedoStatement.new(condition, node.condition_type, location: node.location)
                    when AST::RetryStatement
                        condition = node.condition ? rewrite_node(node.condition.not_nil!, scopes, counter, containers) : nil
                        AST::RetryStatement.new(condition, node.condition_type, location: node.location)
                    when AST::ExtendStatement
                        targets = node.targets.map { |t| rewrite_node(t, scopes, counter, containers) }
                        AST::ExtendStatement.new(targets, location: node.location)
                    when AST::FunctionDef
                        receiver = node.receiver ? rewrite_node(node.receiver.not_nil!, scopes, counter, containers) : nil
                        typed_parameters = rewrite_typed_parameters(node.typed_parameters, scopes, counter, containers)
                        rescues = node.rescue_clauses.map { |clause| rewrite_rescue_clause(clause, scopes, counter, containers) }
                        body = rewrite_node_array(node.body, scopes, counter, containers, shadowed: node.parameters.to_set)
                        AST::FunctionDef.new(
                            node.name,
                            typed_parameters,
                            body,
                            rescues,
                            node.return_type,
                            visibility: node.visibility,
                            receiver: receiver,
                            is_abstract: node.abstract?,
                            annotations: rewrite_annotations(node.annotations, scopes, counter, containers),
                            location: node.location
                        )
                    when AST::FunctionLiteral
                        typed_parameters = rewrite_typed_parameters(node.typed_parameters, scopes, counter, containers)
                        rescues = node.rescue_clauses.map { |clause| rewrite_rescue_clause(clause, scopes, counter, containers) }
                        body = rewrite_node_array(node.body, scopes, counter, containers, shadowed: node.parameters.to_set)
                        AST::FunctionLiteral.new(typed_parameters, body, rescues, node.return_type, location: node.location)
                    when AST::ParaLiteral
                        typed_parameters = rewrite_typed_parameters(node.typed_parameters, scopes, counter, containers)
                        rescues = node.rescue_clauses.map { |clause| rewrite_rescue_clause(clause, scopes, counter, containers) }
                        body = rewrite_node_array(node.body, scopes, counter, containers, shadowed: node.parameters.to_set)
                        AST::ParaLiteral.new(typed_parameters, body, rescues, node.return_type, location: node.location)
                    when AST::BlockLiteral
                        typed_parameters = rewrite_typed_parameters(node.typed_parameters, scopes, counter, containers)
                        body = rewrite_node_array(node.body, scopes, counter, containers, shadowed: typed_parameters.map(&.name).to_set)
                        AST::BlockLiteral.new(typed_parameters, body, location: node.location)
                    when AST::ClassDefinition
                        containers << ContainerEntry.new(:class, node.name)
                        body = [] of AST::Node
                        annotations = [] of AST::Annotation
                        begin
                            annotations = rewrite_annotations(node.annotations, scopes, counter, containers)
                            body = rewrite_node_array(node.body, scopes, counter, containers)
                        ensure
                            containers.pop
                        end
                        AST::ClassDefinition.new(
                            node.name,
                            body,
                            node.superclass,
                            is_abstract: node.abstract?,
                            annotations: annotations,
                            location: node.location
                        )
                    when AST::StructDefinition
                        body = rewrite_node_array(node.body, scopes, counter, containers)
                        AST::StructDefinition.new(node.name, body, rewrite_annotations(node.annotations, scopes, counter, containers), location: node.location)
                    when AST::ModuleDefinition
                        containers << ContainerEntry.new(:module, node.name)
                        body = [] of AST::Node
                        annotations = [] of AST::Annotation
                        begin
                            annotations = rewrite_annotations(node.annotations, scopes, counter, containers)
                            body = rewrite_node_array(node.body, scopes, counter, containers)
                        ensure
                            containers.pop
                        end
                        AST::ModuleDefinition.new(node.name, body, annotations, location: node.location)
                    when AST::EnumDefinition
                        members = node.members.map do |member|
                            value = member.value ? rewrite_node(member.value.not_nil!, scopes, counter, containers) : nil
                            AST::EnumMember.new(member.name, value, location: member.location)
                        end
                        AST::EnumDefinition.new(
                            node.name,
                            members,
                            value_name: node.value_name,
                            value_type: node.value_type,
                            annotations: rewrite_annotations(node.annotations, scopes, counter, containers),
                            location: node.location
                        )
                    when AST::InstanceVariableAssignment
                        value = rewrite_node(node.value, scopes, counter, containers)
                        AST::InstanceVariableAssignment.new(node.name, value, operator: node.operator, location: node.location)
                    when AST::ClassVariableAssignment
                        resolved = resolve_container_variable(:class, node.name, containers, node.location)
                        value = rewrite_node(node.value, scopes, counter, containers)
                        AST::Assignment.new(resolved, value, operator: node.operator, location: node.location)
                    when AST::ModuleVariableAssignment
                        resolved = resolve_container_variable(:module, node.name, containers, node.location)
                        value = rewrite_node(node.value, scopes, counter, containers)
                        AST::Assignment.new(resolved, value, operator: node.operator, location: node.location)
                    when AST::InterpolatedString
                        parts = node.parts.map do |type, content|
                            if type == :expression
                                expr = parse_interpolation_expression(content)
                                rewritten = rewrite_node(expr, scopes, counter, containers)
                                {type, rewritten.to_source}
                            else
                                {type, content}
                            end
                        end
                        AST::InterpolatedString.new(parts, location: node.location)
                    when AST::Variable
                        name = resolve_binding_name(node.name, scopes)
                        AST::Variable.new(name, node.type_annotation, location: node.location)
                    when AST::ClassVariable
                        resolved = resolve_container_variable(:class, node.name, containers, node.location)
                        AST::Variable.new(resolved, location: node.location)
                    when AST::ModuleVariable
                        resolved = resolve_container_variable(:module, node.name, containers, node.location)
                        AST::Variable.new(resolved, location: node.location)
                    when AST::ConstantPath
                        AST::ConstantPath.new(node.names, location: node.location)
                    when AST::Literal, AST::ArgvExpression, AST::ArgcExpression, AST::ArgfExpression, AST::StdoutExpression, AST::StderrExpression, AST::StdinExpression, AST::BagConstructor, AST::InstanceVariable, AST::InstanceVariableDeclaration
                        node
                    else
                        node
                    end
                end

                private def rewrite_when_clause(node : AST::WhenClause, scopes : Array(Scope), counter : Counter, containers : Array(ContainerEntry)) : AST::WhenClause
                    conditions = node.conditions.map { |c| rewrite_node(c, scopes, counter, containers) }
                    block = rewrite_node_array(node.block, scopes, counter, containers)
                    AST::WhenClause.new(conditions, block, location: node.location)
                end

                private def rewrite_elsif_clause(node : AST::ElsifClause, scopes : Array(Scope), counter : Counter, containers : Array(ContainerEntry)) : AST::ElsifClause
                    condition = rewrite_node(node.condition, scopes, counter, containers)
                    block = rewrite_node_array(node.block, scopes, counter, containers)
                    AST::ElsifClause.new(condition, block, location: node.location)
                end

                private def rewrite_rescue_clause(node : AST::RescueClause, scopes : Array(Scope), counter : Counter, containers : Array(ContainerEntry)) : AST::RescueClause
                    body = rewrite_node_array(node.body, scopes, counter, containers)
                    AST::RescueClause.new(node.exceptions, node.exception_variable, body, location: node.location)
                end

                private def rewrite_typed_parameters(
                    typed_parameters : Array(AST::TypedParameter),
                    scopes : Array(Scope),
                    counter : Counter,
                    containers : Array(ContainerEntry)
                ) : Array(AST::TypedParameter)
                    typed_parameters.map do |param|
                        default_value = param.default_value
                        rewritten_default = default_value ? rewrite_node(default_value.not_nil!, scopes, counter, containers) : nil
                        AST::TypedParameter.new(param.name, param.type, param.instance_var_name, rewritten_default)
                    end
                end

                private def rewrite_annotations(
                    annotations : Array(AST::Annotation),
                    scopes : Array(Scope),
                    counter : Counter,
                    containers : Array(ContainerEntry)
                ) : Array(AST::Annotation)
                    annotations.map do |ann|
                        args = ann.arguments.map { |arg| rewrite_node(arg, scopes, counter, containers) }
                        AST::Annotation.new(ann.name, args, ann.location)
                    end
                end

                private def resolve_binding_name(name : String, scopes : Array(Scope)) : String
                    return name if name == "self"
                    scopes.reverse_each do |scope|
                        return name if scope.shadowed.includes?(name)
                        if mangled = scope.bindings[name]?
                            return mangled
                        end
                    end
                    name
                end

                private def validate_mutation!(name : String, location : Location?, scopes : Array(Scope)) : Nil
                    return if name == "self"
                    scopes.reverse_each do |scope|
                        return if scope.shadowed.includes?(name)
                        if scope.immutable.includes?(name)
                            raise ::Dragonstone::ConstantError.new("Cannot reassign immutable binding #{name}", location)
                        end
                    end
                end

                private def fresh_name(prefix : String, name : String, counter : Counter) : String
                    counter.value += 1
                    "#{prefix}_#{counter.value}_#{name}"
                end

                private def resolve_container_variable(kind : Symbol, name : String, containers : Array(ContainerEntry), location : Location?) : String
                    idx = containers.rindex { |entry| entry.kind == kind }
                    unless idx
                        label = kind == :class ? "Class variables (@@)" : "Module variables (@@@)"
                        owner = kind == :class ? "classes" : "modules"
                        raise ::Dragonstone::ParserError.new("#{label} are only allowed inside #{owner}", location)
                    end

                    container_path = containers[0..idx].map(&.name).join("__")
                    prefix = kind == :class ? "__ds_cvar_" : "__ds_mvar_"
                    "#{prefix}#{container_path}__#{name}"
                end

                private def parse_interpolation_expression(source : String) : AST::Node
                    lexer = Lexer.new(source)
                    tokens = lexer.tokenize
                    parser = Parser.new(tokens)
                    parser.parse_expression_entry
                end
            end
        end
    end
end
