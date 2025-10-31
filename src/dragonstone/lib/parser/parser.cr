# ---------------------------------
# ------------ Parser -------------
# ---------------------------------
require "../lexer/*"
require "../codegen/ast"
require "../resolver/*"

module Dragonstone
    class Parser
        def self.parse(source : String, source_name : String = "<source>") : AST::Program
            lexer = Lexer.new(source, source_name: source_name)
            tokens = lexer.tokenize
            new(tokens).parse
        end

        TERMINATOR_TOKENS = [
            :EOF, 
            :END, 
            :ELSIF, 
            :ELSE, 
            :WHEN, 
            :RESCUE, 
            :RETURN, 
            :BREAK, 
            :NEXT, 
            :CON, 
            :DEF, 
            :CLASS, 
            :MODULE, 
            :CASE, 
            :SELECT, 
            :IF, 
            :UNLESS, 
            :WHILE, 
            :PUTS, 
            :DEBUG_PRINT
        ]

        ASSIGNMENT_TOKENS = [
            :ASSIGN, 
            :PLUS_ASSIGN, 
            :MINUS_ASSIGN, 
            :MULTIPLY_ASSIGN, 
            :DIVIDE_ASSIGN, 
            :MODULO_ASSIGN, 
            :POWER_ASSIGN, 
            :FLOOR_DIVIDE_ASSIGN,
            :WRAP_PLUS_ASSIGN, 
            :WRAP_MINUS_ASSIGN, 
            :WRAP_MULTIPLY_ASSIGN, 
            :WRAP_POWER_ASSIGN,
            :BIT_AND_ASSIGN, 
            :BIT_OR_ASSIGN, 
            :BIT_XOR_ASSIGN,
            :SHIFT_LEFT_ASSIGN, 
            :SHIFT_RIGHT_ASSIGN,
            :LOGICAL_OR_ASSIGN, 
            :LOGICAL_AND_ASSIGN
        ]

        PRECEDENCE = {
            assignment: 10,
            conditional: 20,
            range: 30,
            logical_or: 40,
            logical_and: 50,
            equality: 60,
            comparison: 70,
            binary_or: 80,
            binary_and: 90,
            shift: 100,
            additive: 110,
            multiplicative: 120,
            exponential: 130
        }

        TOKEN_OPERATOR_MAP = {
            PLUS: :+,
            MINUS: :-,
            WRAP_PLUS: :"&+",
            WRAP_MINUS: :"&-",
            MULTIPLY: :*,
            WRAP_MULTIPLY: :"&*",
            DIVIDE: :/,
            FLOOR_DIVIDE: :"//",
            MODULO: :%,
            POWER: :"**",
            WRAP_POWER: :"&**",
            SHIFT_LEFT: :<<,
            SHIFT_RIGHT: :>>,
            BIT_AND: :&,
            BIT_OR: :|,
            BIT_XOR: :^,
            EQUALS: :==,
            NOT_EQUALS: :!=,
            LESS: :<,
            LESS_EQUAL: :<=,
            GREATER: :>,
            GREATER_EQUAL: :>=,
            SPACESHIP: :<=>,
            MATCH: :=~,
            NOT_MATCH: :!~,
            CASE_EQUALS: :===,
            LOGICAL_AND: :"&&",
            LOGICAL_OR: :"||",
            RANGE_INCLUSIVE: :"..",
            RANGE_EXCLUSIVE: :"...",
            BIT_AND_ASSIGN: :&,
            BIT_OR_ASSIGN: :|,
            BIT_XOR_ASSIGN: :^,
            LOGICAL_AND_ASSIGN: :"&&",
            LOGICAL_OR_ASSIGN: :"||",
            SHIFT_LEFT_ASSIGN: :<<,
            SHIFT_RIGHT_ASSIGN: :>>,
            PLUS_ASSIGN: :+,
            MINUS_ASSIGN: :-,
            MULTIPLY_ASSIGN: :*,
            DIVIDE_ASSIGN: :/,
            FLOOR_DIVIDE_ASSIGN: :"//",
            MODULO_ASSIGN: :%,
            POWER_ASSIGN: :"**",
            WRAP_PLUS_ASSIGN: :"&+",
            WRAP_MINUS_ASSIGN: :"&-",
            WRAP_MULTIPLY_ASSIGN: :"&*",
            WRAP_POWER_ASSIGN: :"&**"
        }

        OPERATOR_PRECEDENCE = {
            :"**" => PRECEDENCE[:exponential],
            :"&**" => PRECEDENCE[:exponential],
            :* => PRECEDENCE[:multiplicative],
            :/ => PRECEDENCE[:multiplicative],
            :"//" => PRECEDENCE[:multiplicative],
            :% => PRECEDENCE[:multiplicative],
            :"&*" => PRECEDENCE[:multiplicative],
            :+ => PRECEDENCE[:additive],
            :"&+" => PRECEDENCE[:additive],
            :- => PRECEDENCE[:additive],
            :"&-" => PRECEDENCE[:additive],
            :<< => PRECEDENCE[:shift],
            :>> => PRECEDENCE[:shift],
            :& => PRECEDENCE[:binary_and],
            :| => PRECEDENCE[:binary_or],
            :^ => PRECEDENCE[:binary_or],
            :== => PRECEDENCE[:equality],
            :!= => PRECEDENCE[:equality],
            :=~ => PRECEDENCE[:equality],
            :!~ => PRECEDENCE[:equality],
            :=== => PRECEDENCE[:equality],
            :< => PRECEDENCE[:comparison],
            :<= => PRECEDENCE[:comparison],
            :> => PRECEDENCE[:comparison],
            :>= => PRECEDENCE[:comparison],
            :<=> => PRECEDENCE[:comparison],
            :"&&" => PRECEDENCE[:logical_and],
            :"||" => PRECEDENCE[:logical_or],
            :".." => PRECEDENCE[:range],
            :"..." => PRECEDENCE[:range]
        }

        RIGHT_ASSOCIATIVE = [
            :"**", 
            :"&**", 
            :"..", 
            :"..."
        ]

        def initialize(tokens : Array(Token))
            @tokens = tokens
            @pos = 0
        end

        def parse : AST::Program
            statements = [] of AST::Node
            use_decls  = [] of AST::UseDecl

            while current_token.type != :EOF
                if current_token.type == :USE
                    use_decls << parse_use_decl
                    next
                end
                statements << parse_statement
            end

            expect(:EOF)
            AST::Program.new(statements, use_decls)
        end

        def parse_expression_entry : AST::Node
            expr = parse_expression
            expect(:EOF)
            expr
        end

        private def parse_statement : AST::Node
            token = current_token
            case token.type
            when :IDENTIFIER
                parse_expression_statement
            when :INSTANCE_VAR
                next_token = peek_token
                if next_token && next_token.type == :COLON
                    parse_instance_variable_declaration
                else
                    parse_expression_statement
                end
            when :PUTS
                parse_keyword_method_call
            when :DEBUG_PRINT
                parse_debug_print
            when :IF
                parse_if_statement
            when :UNLESS
                parse_unless_statement
            when :WHILE
                parse_while_statement
            when :DEF
                parse_function_def
            when :MODULE
                parse_module_definition
            when :CLASS
                parse_class_definition
            when :CON
                parse_constant_declaration
            when :ENUM
                parse_enum_declaration
            when :STRUCT
                parse_struct_declaration
            when :ALIAS
                parse_alias_definition
            when :EXTEND
                parse_extend_statement
            when :GETTER
                parse_accessor_macro(:getter)
            when :SETTER
                parse_accessor_macro(:setter)
            when :PROPERTY
                parse_accessor_macro(:property)
            when :PRIVATE
                parse_visibility_prefixed_statement(:private)
            when :PROTECTED
                parse_visibility_prefixed_statement(:protected)
            when :RETURN
                parse_return_statement
            when :CASE, :SELECT
                parse_case_statement
            when :BREAK
                parse_break_statement
            when :NEXT
                parse_next_statement
            when :END, :ELSIF, :ELSE, :RESCUE, :WHEN
                error("Unexpected #{token.type.to_s.downcase}", token)
            when :USE
                error("'use' is only allowed at the top level", token)
            else
                parse_expression_statement
            end
        end

        private def parse_expression_statement : AST::Node
            expression = parse_expression
            if expression.is_a?(AST::Variable)
                AST::MethodCall.new(expression.name, [] of AST::Node, nil, location: expression.location)
            else
                expression
            end
        end

        private def parse_constant_declaration : AST::Node
            keyword = expect(:CON)
            name_token = expect(:IDENTIFIER)
            type_annotation = nil
            if current_token.type == :COLON
                advance
                type_annotation = parse_type_expression
            end
            expect(:ASSIGN)
            value = parse_expression
            location = name_token.location || keyword.location
            AST::ConstantDeclaration.new(name_token.value.as(String), value, type_annotation, location: location)
        end

        private def parse_extend_statement : AST::Node
            extend_token = expect(:EXTEND)
            targets = [] of AST::Node
            targets << parse_expression
            while current_token.type == :COMMA
                advance
                targets << parse_expression
            end
            AST::ExtendStatement.new(targets, location: extend_token.location)
        end

        private def parse_visibility_prefixed_statement(visibility : Symbol) : AST::Node
            expect(visibility == :private ? :PRIVATE : :PROTECTED)
            case current_token.type
            when :DEF
                parse_function_def(visibility)
            when :GETTER
                parse_accessor_macro(:getter, visibility)
            when :SETTER
                parse_accessor_macro(:setter, visibility)
            when :PROPERTY
                parse_accessor_macro(:property, visibility)
            else
                error("Expected def/getter/setter/property after #{visibility}", current_token)
            end
        end

        private def parse_accessor_macro(kind : Symbol, visibility : Symbol = :public) : AST::AccessorMacro
            token_type = case kind
                when :getter then :GETTER
                when :setter then :SETTER
                when :property then :PROPERTY
                else
                    raise "Unknown accessor macro kind #{kind}"
                end

            keyword = expect(token_type)
            entries = [] of AST::AccessorEntry

            loop do
                name_token = expect(:IDENTIFIER)
                type_annotation = nil
                if current_token.type == :COLON
                    advance
                    type_annotation = parse_type_expression
                end
                entries << AST::AccessorEntry.new(name_token.value.as(String), type_annotation)
                break unless current_token.type == :COMMA
                advance
            end

            AST::AccessorMacro.new(kind, entries, visibility, location: keyword.location)
        end

        private def parse_keyword_method_call : AST::Node
            name_token = current_token
            advance
            arguments = [] of AST::Node

            while !argument_terminator?(current_token)
                break if assignment_ahead?
                arguments << parse_expression
                if current_token.type == :COMMA
                    advance
                else
                    break
                end
            end

            AST::MethodCall.new(name_token.value.as(String), arguments, nil, location: name_token.location)
        end

        private def parse_instance_variable_declaration : AST::Node
            token = expect(:INSTANCE_VAR)
            type_annotation = nil
            if current_token.type == :COLON
                advance
                type_annotation = parse_type_expression
            end
            AST::InstanceVariableDeclaration.new(token.value.as(String), type_annotation, location: token.location)
        end

        private def parse_debug_print : AST::Node
            token = expect(:DEBUG_PRINT)
            expression = parse_expression
            AST::DebugPrint.new(expression, location: token.location)
        end

        private def parse_module_definition : AST::Node
            module_token = expect(:MODULE)
            name_token = expect(:IDENTIFIER)
            body = parse_block([:END])
            expect(:END)
            AST::ModuleDefinition.new(name_token.value.as(String), body, location: module_token.location)
        end

        private def parse_class_definition : AST::Node
            class_token = expect(:CLASS)
            name_token = expect(:IDENTIFIER)
            superclass = nil
            if current_token.type == :LESS
                advance
                superclass = expect(:IDENTIFIER).value.as(String)
            end
            body = parse_block([:END])
            expect(:END)
            AST::ClassDefinition.new(name_token.value.as(String), body, superclass, location: class_token.location)
        end

        private def parse_struct_declaration : AST::Node
            struct_token = expect(:STRUCT)
            name_token = expect(:IDENTIFIER)
            body = parse_block([:END])
            expect(:END)
            AST::StructDefinition.new(name_token.value.as(String), body, location: struct_token.location)
        end

        private def parse_enum_declaration : AST::Node
            enum_token = expect(:ENUM)
            name_token = expect(:IDENTIFIER)

            value_name = nil
            value_type = nil
            if current_token.type == :LPAREN
                advance
                value_name_token = expect(:IDENTIFIER)
                value_name = value_name_token.value.as(String)
                expect(:COLON)
                value_type = parse_type_expression
                expect(:RPAREN)
            end

            members = [] of AST::EnumMember
            while current_token.type != :END && current_token.type != :EOF
                member_token = expect(:IDENTIFIER)
                member_value = nil
                if current_token.type == :ASSIGN
                    advance
                    member_value = parse_expression
                end
                members << AST::EnumMember.new(member_token.value.as(String), member_value, location: member_token.location)
            end

            expect(:END)
            AST::EnumDefinition.new(
                name_token.value.as(String),
                members,
                value_name: value_name,
                value_type: value_type,
                location: enum_token.location
            )
        end

        private def parse_alias_definition : AST::AliasDefinition
            alias_token = expect(:ALIAS)
            name_token = expect(:IDENTIFIER)
            expect(:ASSIGN)
            type_expr = parse_type_expression
            AST::AliasDefinition.new(name_token.value.as(String), type_expr, location: alias_token.location)
        end

        private def parse_function_def(visibility : Symbol = :public) : AST::Node
            def_token = expect(:DEF)
            name_token = expect(:IDENTIFIER)
            parameters = parse_parameter_list
            return_type = parse_optional_return_type
            body = parse_block([:END, :RESCUE])
            rescue_clauses = [] of AST::RescueClause
            while current_token.type == :RESCUE
                rescue_clauses << parse_rescue_clause
            end
            expect(:END)
            AST::FunctionDef.new(name_token.value.as(String), parameters, body, rescue_clauses, return_type, visibility: visibility, location: def_token.location)
        end

        private def parse_parameter_list(required : Bool = false) : Array(AST::TypedParameter)
            parameters = [] of AST::TypedParameter
            unless current_token.type == :LPAREN
                return parameters unless required
                error("Expected '(' to start parameter list", current_token)
            end

            expect(:LPAREN)
            unless current_token.type == :RPAREN
                parameters << parse_typed_parameter
                while current_token.type == :COMMA
                    advance
                    parameters << parse_typed_parameter
                end
            end
            expect(:RPAREN)
            parameters
        end

        private def parse_typed_parameter : AST::TypedParameter
            instance_var = false
            name_token = case current_token.type
                when :IDENTIFIER
                    expect(:IDENTIFIER)
                when :INSTANCE_VAR
                    instance_var = true
                    expect(:INSTANCE_VAR)
                else
                    error("Expected parameter name", current_token)
                end

            param_annotation = nil
            if current_token.type == :COLON
                advance
                param_annotation = parse_type_expression
            end
            name = name_token.value.as(String)
            if instance_var
                AST::TypedParameter.new(name, param_annotation, name)
            else
                AST::TypedParameter.new(name, param_annotation)
            end
        end

        private def parse_optional_return_type : AST::TypeExpression?
            return nil unless current_token.type == :THIN_ARROW
            expect(:THIN_ARROW)
            parse_type_expression
        end

        private def parse_rescue_clause : AST::RescueClause
            rescue_token = expect(:RESCUE)
            exceptions = [] of String

            if current_token.type == :IDENTIFIER
                exceptions << expect(:IDENTIFIER).value.as(String)
                while current_token.type == :COMMA
                    advance
                    exceptions << expect(:IDENTIFIER).value.as(String)
                end
            end

            body = parse_block([:RESCUE, :END])
            AST::RescueClause.new(exceptions, nil, body, location: rescue_token.location)
        end

        private def parse_if_statement : AST::Node
            if_token = expect(:IF)
            condition = parse_expression
            advance if current_token.type == :DO

            then_block = parse_block([:ELSIF, :ELSE, :END])
            elsif_blocks = [] of AST::ElsifClause
            while current_token.type == :ELSIF
                elsif_blocks << parse_elsif_clause
            end

            else_block = nil
            if current_token.type == :ELSE
                advance
                else_block = parse_block([:END])
            end

            expect(:END)
            AST::IfStatement.new(condition, then_block, elsif_blocks, else_block, location: if_token.location)
        end

        private def parse_unless_statement : AST::Node
            unless_token = expect(:UNLESS)
            condition = parse_expression
            advance if current_token.type == :DO
            body = parse_block([:ELSE, :END])
            else_block = nil
            if current_token.type == :ELSE
                advance
                else_block = parse_block([:END])
            end
            expect(:END)
            AST::UnlessStatement.new(condition, body, else_block, location: unless_token.location)
        end

        private def parse_elsif_clause : AST::ElsifClause
            elsif_token = expect(:ELSIF)
            condition = parse_expression
            advance if current_token.type == :DO
            block = parse_block([:ELSIF, :ELSE, :END])
            AST::ElsifClause.new(condition, block, location: elsif_token.location)
        end

        private def parse_case_statement : AST::Node
            case_token = current_token
            advance

            expression = nil
            unless [:WHEN, :DO].includes?(current_token.type)
                expression = parse_expression
            end
            advance if current_token.type == :DO

            when_clauses = [] of AST::WhenClause
            while current_token.type == :WHEN
                when_clauses << parse_when_clause
            end

            if when_clauses.empty?
                error("Expected at least one when clause", current_token)
            end

            else_block = nil
            if current_token.type == :ELSE
                advance
                else_block = parse_block([:END])
            end
            expect(:END)
            kind = case_token.type == :SELECT ? :select : :case
            AST::CaseStatement.new(expression, when_clauses, else_block, kind: kind, location: case_token.location)
        end
        
        private def parse_when_clause : AST::WhenClause
            when_token = expect(:WHEN)
            conditions = [] of AST::Node
            conditions << parse_expression
            while current_token.type == :COMMA
                advance
                conditions << parse_expression
            end
            advance if current_token.type == :DO
            block = parse_block([:WHEN, :ELSE, :END])
            AST::WhenClause.new(conditions, block, location: when_token.location)
        end

        private def parse_while_statement : AST::Node
            while_token = expect(:WHILE)
            condition = parse_expression
            advance if current_token.type == :DO
            block = parse_block([:END])
            expect(:END)
            AST::WhileStatement.new(condition, block, location: while_token.location)
        end

        private def parse_break_statement : AST::Node
            token = expect(:BREAK)
            condition, modifier = parse_modifier_condition
            AST::BreakStatement.new(condition: condition, condition_type: modifier, location: token.location)
        end

        private def parse_next_statement : AST::Node
            token = expect(:NEXT)
            condition, modifier = parse_modifier_condition
            AST::NextStatement.new(condition: condition, condition_type: modifier, location: token.location)
        end

        private def parse_return_statement : AST::Node
            return_token = expect(:RETURN)
            if return_value_terminator?(current_token)
                AST::ReturnStatement.new(nil, location: return_token.location)
            else
                value = parse_expression
                AST::ReturnStatement.new(value, location: return_token.location)
            end
        end

        private def parse_block(terminators : Array(Symbol)) : Array(AST::Node)
            statements = [] of AST::Node
            while !terminators.includes?(current_token.type) && current_token.type != :EOF
                statements << parse_statement
            end
            statements
        end

        private def parse_expression(precedence : Int32 = 0) : AST::Node
            left = parse_prefix

            loop do
                left = parse_postfix(left)
                token = current_token

                if token.type == :COLON && left.is_a?(AST::Variable)
                    advance
                    var_annotation = parse_type_expression
                    left = AST::Variable.new(left.name, var_annotation, location: left.location)
                    next
                end

                if token.type == :QUESTION
                    info_precedence = PRECEDENCE[:conditional]
                    break unless info_precedence > precedence
                    left = parse_conditional(left, token)
                    next
                end

                op_info = infix_operator_info(token)
                break unless op_info
                break unless op_info[:precedence] > precedence

                advance
                if op_info[:type] == :assignment
                    right = parse_expression(op_info[:precedence] - 1)
                    left = build_assignment(left, op_info, right, token)
                else
                    right_precedence = op_info[:associativity] == :right ? op_info[:precedence] - 1 : op_info[:precedence]
                    right = parse_expression(right_precedence)
                    left = AST::BinaryOp.new(left, op_info[:operator].as(Symbol), right, location: token.location)
                end
            end

            left
        end

        private def parse_prefix : AST::Node
            token = current_token
            case token.type
            when :PLUS
                parse_unary(token, :+)
            when :MINUS
                parse_unary(token, :-)
            when :WRAP_PLUS
                parse_unary(token, :"&+")
            when :WRAP_MINUS
                parse_unary(token, :"&-")
            when :NOT
                parse_unary(token, :!)
            when :BIT_NOT
                parse_unary(token, :~)
            else
                parse_primary
            end
        end

        private def parse_unary(token : Token, operator : Symbol) : AST::Node
            advance
            operand = parse_expression(PRECEDENCE[:exponential] - 1)
            AST::UnaryOp.new(operator, operand, location: token.location)
        end

        private def parse_postfix(left : AST::Node) : AST::Node
            loop do
                case current_token.type
                when :LPAREN
                    break unless left.is_a?(AST::Variable)
                    variable = left.as(AST::Variable)
                    arguments = parse_argument_list
                    left = AST::MethodCall.new(variable.name, arguments, nil, location: variable.location)
                when :LBRACKET
                    bracket_token = current_token
                    advance
                    index = parse_expression
                    nil_safe = false
                    if current_token.type == :RBRACKET_QUESTION
                        nil_safe = true
                        advance
                    else
                        expect(:RBRACKET)
                    end
                    left = AST::IndexAccess.new(left, index, nil_safe: nil_safe, location: bracket_token.location)
                when :DOT
                    advance
                    method_token = expect(:IDENTIFIER)
                    name = method_token.value.as(String)
                    arguments = [] of AST::Node
                    if current_token.type == :LPAREN
                        arguments = parse_argument_list
                    end
                    left = AST::MethodCall.new(name, arguments, left, location: method_token.location)
                else
                    break
                end
            end
            left
        end

        private def parse_primary : AST::Node
            token = current_token
            case token.type
            when :STRING
                advance
                AST::Literal.new(token.value.as(String), location: token.location)
            when :INTERPOLATED_STRING
                advance
                AST::InterpolatedString.new(token.value.as(Array(Tuple(Symbol, String))), location: token.location)
            when :INTEGER
                advance
                AST::Literal.new(token.value.as(Int64), location: token.location)
            when :FLOAT
                advance
                AST::Literal.new(token.value.as(Float64), location: token.location)
            when :CHAR
                advance
                AST::Literal.new(token.value.as(Char), location: token.location)
            when :TRUE
                advance
                AST::Literal.new(true, location: token.location)
            when :FALSE
                advance
                AST::Literal.new(false, location: token.location)
            when :NIL
                advance
                AST::Literal.new(nil, location: token.location)
            when :IDENTIFIER
                parse_identifier_expression
            when :INSTANCE_VAR
                ivar_token = expect(:INSTANCE_VAR)
                AST::InstanceVariable.new(ivar_token.value.as(String), location: ivar_token.location)
            when :TYPEOF
                parse_typeof_expression
            when :LBRACKET
                parse_array_literal
            when :LPAREN
                advance
                expr = parse_expression
                expect(:RPAREN)
                expr
            when :FUN
                parse_function_literal
            else
                error("Unexpected token #{token.type}", token)
            end
        end

        private def parse_identifier_expression : AST::Node
            identifier_token = expect(:IDENTIFIER)
            node = AST::Variable.new(identifier_token.value.as(String), location: identifier_token.location)

            while current_token.type == :DOUBLE_COLON
                advance
                segment_token = expect(:IDENTIFIER)
                names = case node
                    when AST::ConstantPath
                        node.names.dup
                    when AST::Variable
                        [node.name]
                    else
                        error("Invalid constant path segment", segment_token)
                    end
                names << segment_token.value.as(String)
                node = AST::ConstantPath.new(names, location: identifier_token.location)
            end

            node
        end

        private def parse_typeof_expression : AST::Node
            token = expect(:TYPEOF)
            expect(:LPAREN)
            expr = parse_expression
            expect(:RPAREN)
            AST::MethodCall.new("typeof", [expr], nil, location: token.location)
        end

        private def parse_array_literal : AST::Node
            start_token = expect(:LBRACKET)
            elements = [] of AST::Node
            unless current_token.type == :RBRACKET
                elements << parse_expression
                while current_token.type == :COMMA
                    advance
                    elements << parse_expression
                end
            end
            expect(:RBRACKET)
            AST::ArrayLiteral.new(elements, location: start_token.location)
        end

        private def parse_function_literal : AST::Node
            fun_token = expect(:FUN)
            parameters = parse_parameter_list(required: true)
            return_type = parse_optional_return_type
            advance if current_token.type == :DO
            body = parse_block([:END, :RESCUE])
            rescue_clauses = [] of AST::RescueClause
            while current_token.type == :RESCUE
                rescue_clauses << parse_rescue_clause
            end
            expect(:END)
            AST::FunctionLiteral.new(parameters, body, rescue_clauses, return_type, location: fun_token.location)
        end

        private def parse_argument_list : Array(AST::Node)
            expect(:LPAREN)
            arguments = [] of AST::Node
            unless current_token.type == :RPAREN
                arguments << parse_expression
                while current_token.type == :COMMA
                    advance
                    arguments << parse_expression
                end
            end
            expect(:RPAREN)
            arguments
        end

        private def parse_conditional(condition : AST::Node, question_token : Token) : AST::Node
            advance
            then_branch = parse_expression
            expect(:COLON)
            else_branch = parse_expression(PRECEDENCE[:conditional] - 1)
            AST::ConditionalExpression.new(condition, then_branch, else_branch, location: question_token.location)
        end

        private def infix_operator_info(token : Token) : NamedTuple(type: Symbol, operator: Symbol?, precedence: Int32, associativity: Symbol)?
            type = token.type
            if ASSIGNMENT_TOKENS.includes?(type)
                operator = type == :ASSIGN ? nil : TOKEN_OPERATOR_MAP[type]?
                {type: :assignment, operator: operator, precedence: PRECEDENCE[:assignment], associativity: :right}
            else
                operator = TOKEN_OPERATOR_MAP[type]?
                return nil unless operator
                precedence = OPERATOR_PRECEDENCE[operator]?
                return nil unless precedence
                {type: :binary, operator: operator, precedence: precedence, associativity: RIGHT_ASSOCIATIVE.includes?(operator) ? :right : :left}
            end
        end

        private def build_assignment(left : AST::Node, info : NamedTuple(type: Symbol, operator: Symbol?, precedence: Int32, associativity: Symbol), value : AST::Node, token : Token) : AST::Node
            operator = info[:operator]
            location = token.location

            case left
            when AST::Variable
                AST::Assignment.new(left.name, value, operator: operator, type_annotation: left.type_annotation, location: location)
            when AST::InstanceVariable
                AST::InstanceVariableAssignment.new(left.name, value, operator: operator, location: location)
            when AST::IndexAccess
                AST::IndexAssignment.new(left.object, left.index, value, operator: operator, nil_safe: left.nil_safe, location: location)
            when AST::MethodCall
                if left.receiver && left.arguments.empty?
                    AST::AttributeAssignment.new(left.receiver.not_nil!, left.name, value, operator: operator, location: location)
                elsif left.receiver.nil? && left.arguments.empty?
                    AST::Assignment.new(left.name, value, operator: operator, location: location)
                else
                    error("Invalid assignment target", token)
                end
            else
                error("Invalid assignment target", token)
            end
        end

        private def parse_modifier_condition : Tuple(AST::Node?, Symbol?)
            modifier = nil
            condition = nil
            case current_token.type
            when :IF
                modifier = :if
                advance
                condition = parse_expression
            when :UNLESS
                modifier = :unless
                advance
                condition = parse_expression
            end
            {condition, modifier}
        end

        private def return_value_terminator?(token : Token) : Bool
            TERMINATOR_TOKENS.includes?(token.type) || ((token.type == :IDENTIFIER || token.type == :INSTANCE_VAR) && assignment_token?(peek_token))
        end

        private def argument_terminator?(token : Token) : Bool
            TERMINATOR_TOKENS.includes?(token.type)
        end

        private def assignment_ahead? : Bool
            (current_token.type == :IDENTIFIER || current_token.type == :INSTANCE_VAR) && assignment_token?(peek_token)
        end

        private def assignment_token?(token : Token?) : Bool
            return false unless token
            ASSIGNMENT_TOKENS.includes?(token.not_nil!.type)
        end

        private def current_token : Token
            @tokens[@pos]? || @tokens.last
        end

        private def peek_token(offset = 1) : Token?
            @tokens[@pos + offset]?
        end

        private def advance
            @pos += 1 if @pos < @tokens.size - 1
        end

        private def expect(type : Symbol) : Token
            token = current_token
            if token.type != type
                hint = build_expectation_hint(type, token)
                error("Expected #{type}, got #{token.type}", token, hint)
            end
            advance
            token
        end

        private def error(message : String, token : Token, hint : String? = nil) : NoReturn
            location = token.location
            raise ParserError.new(message, location: location, hint: hint)
        end

        private def build_expectation_hint(expected_type : Symbol, token : Token) : String?
            case expected_type

            when :END
                "Add 'end' to close the previous block"

            when :RPAREN
                "Add ')' to close the opening '('"

            when :RBRACKET
                "Add ']' to close the opening '['"

            when :RESCUE
                "Did you forget to add a rescue clause or 'end'?"

            else
                token.type == :EOF ? "Check for missing tokens before the end of the file" : nil

            end
        end

        private def parse_use_decl : AST::UseDecl
            use_token = expect(:USE)

            # Two forms:
            # use "./file.ds", "../lib/*", "./**"
            # use { Foo, bar as baz } from "./file.ds"
            items = [] of AST::UseItem

            if current_token.type == :LBRACE
                items << parse_use_from
            else
                specs = parse_path_spec_list
                items << AST::UseItem.new(
                    kind: AST::UseItemKind::Paths,
                    specs: specs
                )
            end

            AST::UseDecl.new(items, location: use_token.location)
        end

        private def parse_use_from : AST::UseItem
            expect(:LBRACE)
            imports = [] of AST::NamedImport

            # { Foo, bar as baz }
            loop do
                name_tok = expect(:IDENTIFIER)
                alias_name = nil
                if current_token.type == :AS
                    advance
                    alias_tok = expect(:IDENTIFIER)
                    alias_name = alias_tok.value.as(String)
                end
                imports << AST::NamedImport.new(name_tok.value.as(String), alias_name)
                break if current_token.type == :RBRACE
                expect(:COMMA)
            end
            expect(:RBRACE)
            expect(:FROM)
            file_tok = expect(:STRING)

            AST::UseItem.new(
                kind: AST::UseItemKind::From,
                from: file_tok.value.as(String),
                imports: imports
            )
        end

        private def parse_path_spec_list : Array(String)
            # one or more STRING tokens, comma-separated
            specs = [] of String
            first = expect(:STRING)
            specs << first.value.as(String)
            while current_token.type == :COMMA
                advance
                tok = expect(:STRING)
                specs << tok.value.as(String)
            end
            specs
        end

        private def parse_type_expression : AST::TypeExpression
            parse_union_type_expression
        end

        private def parse_union_type_expression : AST::TypeExpression
            members = [] of AST::TypeExpression
            members << parse_optional_type_expression
            while current_token.type == :BIT_OR
                advance
                members << parse_optional_type_expression
            end
            return members.first if members.size == 1
            AST::UnionTypeExpression.new(members, location: members.first.location)
        end

        private def parse_optional_type_expression : AST::TypeExpression
            type = parse_primary_type_expression
            while current_token.type == :QUESTION
                token = expect(:QUESTION)
                type = AST::OptionalTypeExpression.new(type, location: token.location)
            end
            type
        end

        private def parse_primary_type_expression : AST::TypeExpression
            token = current_token
            case token.type
            when :IDENTIFIER
                identifier_token = expect(:IDENTIFIER)
                AST::SimpleTypeExpression.new(identifier_token.value.as(String), location: identifier_token.location)
            when :NIL
                nil_token = expect(:NIL)
                AST::SimpleTypeExpression.new("nil", location: nil_token.location)
            when :LPAREN
                expect(:LPAREN)
                type = parse_type_expression
                expect(:RPAREN)
                type
            else
                error("Expected type name", token)
            end
        end
    end
end
