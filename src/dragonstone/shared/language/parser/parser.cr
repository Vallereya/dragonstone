# ---------------------------------
# ------------ Parser -------------
# ---------------------------------
require "../lexer/lexer"
require "../ast/ast"
require "../diagnostics/errors"
require "../../runtime/symbol"

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
            :ENSURE,
            :RETURN, 
            :BREAK, 
            :NEXT, 
            :REDO,
            :RETRY,
            :RAISE,
            :CON, 
            :ABSTRACT,
            :DEF, 
            :CLASS, 
            :MODULE, 
            :CASE, 
            :SELECT, 
            :IF, 
            :UNLESS, 
            :WHILE, 
            :PUTS, 
            :ECHO,
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

        METHOD_NAME_KEYWORDS = [
            :SELECT,
            :BEGIN
        ]

        OVERLOADABLE_OPERATORS = [
            :PLUS,
            :MINUS,
            :MULTIPLY,
            :DIVIDE,
            :MODULO,
            :POWER,
            :SHIFT_LEFT,
            :SHIFT_RIGHT,
            :BIT_AND,
            :BIT_OR,
            :BIT_XOR,
            :BIT_NOT,
            :EQUALS,
            :NOT_EQUALS,
            :LESS,
            :LESS_EQUAL,
            :GREATER,
            :GREATER_EQUAL,
            :SPACESHIP,
            :CASE_EQUALS
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
            when :ANNOTATION_START
                parse_annotated_statement
            when :IDENTIFIER
                parse_expression_statement
            when :INSTANCE_VAR
                next_token = peek_token
                if next_token && next_token.type == :COLON
                    parse_instance_variable_declaration
                else
                    parse_expression_statement
                end
            when :ARGV
                parse_expression_statement
            when :ECHO
                parse_keyword_method_call
            when :DEBUG_PRINT
                parse_debug_print
            when :IF
                parse_if_statement
            when :UNLESS
                parse_unless_statement
            when :WHILE
                parse_while_statement
            when :WITH
                parse_with_expression
            when :DEF
                parse_function_def
            when :MODULE
                parse_module_definition
            when :CLASS
                parse_class_definition
            when :ABSTRACT
                parse_abstract_prefixed_statement
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
            when :REDO
                parse_redo_statement
            when :RETRY
                parse_retry_statement
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
                return expression if expression.name == "self"
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
            when :ABSTRACT
                expect(:ABSTRACT)
                case current_token.type
                when :DEF
                    parse_function_def(visibility, is_abstract: true)
                else
                    error("Expected def after #{visibility} abstract", current_token)
                end
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

        private def parse_module_definition(annotations : Array(AST::Annotation) = [] of AST::Annotation) : AST::Node
            module_token = expect(:MODULE)
            name_token = expect(:IDENTIFIER)
            body = parse_block([:END])
            expect(:END)
            AST::ModuleDefinition.new(name_token.value.as(String), body, annotations, location: module_token.location)
        end

        private def parse_abstract_prefixed_statement(annotations : Array(AST::Annotation) = [] of AST::Annotation) : AST::Node
            expect(:ABSTRACT)
            case current_token.type
            when :CLASS
                parse_class_definition(is_abstract: true, annotations: annotations)
            when :DEF
                parse_function_def(:public, is_abstract: true, annotations: annotations)
            else
                error("Expected 'class' or 'def' after 'abstract'", current_token)
            end
        end

        private def parse_class_definition(is_abstract : Bool = false, annotations : Array(AST::Annotation) = [] of AST::Annotation) : AST::Node
            class_token = expect(:CLASS)
            name_token = expect(:IDENTIFIER)
            superclass = nil
            if current_token.type == :LESS
                advance
                superclass = expect(:IDENTIFIER).value.as(String)
            end
            body = parse_block([:END])
            expect(:END)
            AST::ClassDefinition.new(name_token.value.as(String), body, superclass, is_abstract, annotations, location: class_token.location)
        end

        private def parse_struct_declaration(annotations : Array(AST::Annotation) = [] of AST::Annotation) : AST::Node
            struct_token = expect(:STRUCT)
            name_token = expect(:IDENTIFIER)
            body = parse_block([:END])
            expect(:END)
            AST::StructDefinition.new(name_token.value.as(String), body, annotations, location: struct_token.location)
        end

        private def parse_enum_declaration(annotations : Array(AST::Annotation) = [] of AST::Annotation) : AST::Node
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
                annotations: annotations,
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

        private def parse_function_def(visibility : Symbol = :public, is_abstract : Bool = false, annotations : Array(AST::Annotation) = [] of AST::Annotation) : AST::Node
            def_token = expect(:DEF)
            receiver_node = nil
            name_token = nil

            if singleton_method_definition_start?
                receiver_node = parse_singleton_receiver
                expect(:DOT)
                name_token = expect_method_name
            else
                name_token = expect_method_name
            end

            parameters = parse_parameter_list
            seen_default = false
            parameters.each do |param|
                if param.default_value
                    seen_default = true
                elsif seen_default
                    error(
                        "Default parameters must come after all required parameters",
                        name_token
                    )
                end
            end
            return_type = parse_optional_return_type
            body = parse_block([:END, :RESCUE])
            rescue_clauses = [] of AST::RescueClause
            while current_token.type == :RESCUE
                rescue_clauses << parse_rescue_clause
            end
            expect(:END)

            if is_abstract
                unless body.empty? && rescue_clauses.empty?
                    error("Abstract methods cannot have a body", def_token)
                end
            end

            AST::FunctionDef.new(
                name_token.value.as(String),
                parameters,
                body,
                rescue_clauses,
                return_type,
                visibility: visibility,
                receiver: receiver_node,
                is_abstract: is_abstract,
                annotations: annotations,
                location: def_token.location
            )
        end

        private def parse_annotations : Array(AST::Annotation)
            annotations = [] of AST::Annotation
            while current_token.type == :ANNOTATION_START
                annotations << parse_annotation
            end
            annotations
        end

        private def parse_annotation : AST::Annotation
            start_token = expect(:ANNOTATION_START)
            name_parts = [] of String
            name_parts << expect(:IDENTIFIER).value.as(String)
            while current_token.type == :DOT
                advance
                name_parts << expect(:IDENTIFIER).value.as(String)
            end

            args = [] of AST::Node
            if current_token.type == :LPAREN
                args = parse_annotation_arguments
            end

            expect(:RBRACKET)
            AST::Annotation.new(name_parts.join("."), args, start_token.location)
        end

        private def parse_annotation_arguments : Array(AST::Node)
            expect(:LPAREN)
            args = [] of AST::Node
            unless current_token.type == :RPAREN
                args << parse_expression
                while current_token.type == :COMMA
                    advance
                    args << parse_expression
                end
            end
            expect(:RPAREN)
            args
        end

        private def parse_annotated_statement : AST::Node
            annotations = parse_annotations
            case current_token.type
            when :DEF
                parse_function_def(:public, annotations: annotations)
            when :MODULE
                parse_module_definition(annotations)
            when :CLASS
                parse_class_definition(annotations: annotations)
            when :STRUCT
                parse_struct_declaration(annotations)
            when :ENUM
                parse_enum_declaration(annotations)
            when :ABSTRACT
                parse_abstract_prefixed_statement(annotations)
            else
                error("Annotations are only allowed before definitions", current_token)
            end
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

            default_value = nil
            if current_token.type == :ASSIGN
                advance
                default_value = parse_expression
                unless default_value.is_a?(AST::Literal)
                    error(
                        "Default parameter values must be literals for now",
                        name_token,
                        hint: "Use a literal like \"text\", 123, 3.14, true/false, or nil."
                    )
                end
            end
            name = name_token.value.as(String)
            if instance_var
                AST::TypedParameter.new(name, param_annotation, name, default_value)
            else
                AST::TypedParameter.new(name, param_annotation, nil, default_value)
            end
        end

        private def parse_optional_return_type : AST::TypeExpression?
            case current_token.type
            when :THIN_ARROW
                advance
                parse_type_expression
            when :COLON
                # Allow Crystal/Ruby style return type syntax: def foo : Type
                advance
                parse_type_expression
            else
                nil
            end
        end

        private def parse_exception_list(initial_token : Token? = nil) : Array(String)
            names = [] of String
            names << parse_exception_name(initial_token)
            while current_token.type == :COMMA
                advance
                names << parse_exception_name
            end
            names
        end

        private def parse_exception_name(initial_token : Token? = nil) : String
            parts = [] of String
            if initial_token
                parts << initial_token.value.as(String)
            else
                parts << expect(:IDENTIFIER).value.as(String)
            end
            while current_token.type == :DOUBLE_COLON
                advance
                parts << expect(:IDENTIFIER).value.as(String)
            end
            parts.join("::")
        end

        private def identifier_starts_with_uppercase?(identifier : String) : Bool
            first = identifier[0]?
            return false unless first
            first >= 'A' && first <= 'Z'
        end

        private def parse_rescue_clause : AST::RescueClause
            rescue_token = expect(:RESCUE)
            exceptions = [] of String
            exception_variable = nil

            if current_token.type == :IDENTIFIER
                identifier_token = expect(:IDENTIFIER)
                identifier_str = identifier_token.value.as(String)

                if current_token.type == :COLON
                    exception_variable = identifier_str
                    advance
                    exceptions = parse_exception_list
                elsif identifier_starts_with_uppercase?(identifier_str)
                    exceptions = parse_exception_list(identifier_token)
                else
                    exception_variable = identifier_str
                    if current_token.type == :COLON
                        advance
                        exceptions = parse_exception_list
                    end
                end
            elsif current_token.type == :COMMA
                error("Unexpected ',' in rescue clause", current_token)
            end

            body = parse_block([:RESCUE, :ELSE, :ENSURE, :END])
            AST::RescueClause.new(exceptions, exception_variable, body, location: rescue_token.location)
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

        private def parse_redo_statement : AST::Node
            token = expect(:REDO)
            condition, modifier = parse_modifier_condition
            AST::RedoStatement.new(condition: condition, condition_type: modifier, location: token.location)
        end

        private def parse_retry_statement : AST::Node
            token = expect(:RETRY)
            condition, modifier = parse_modifier_condition
            AST::RetryStatement.new(condition: condition, condition_type: modifier, location: token.location)
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
            when :BEGIN
                parse_begin_expression
            when :RAISE
                parse_raise_expression
            when :BIT_NOT
                parse_unary(token, :~)
            when :WITH
                parse_with_expression
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
                    method_token = expect_method_name
                    name = method_token.value.as(String)
                    arguments = [] of AST::Node
                    if current_token.type == :LPAREN
                        arguments = parse_argument_list
                    end
                    left = AST::MethodCall.new(name, arguments, left, location: method_token.location)
                when :DO
                    unless left.is_a?(AST::MethodCall)
                        error("Unexpected 'do' without preceding method call", current_token)
                    end
                    block_literal = parse_do_block_literal
                    left.as(AST::MethodCall).arguments << block_literal
                when :LBRACE
                    unless left.is_a?(AST::MethodCall)
                        break
                    end
                    block_literal = parse_brace_block_literal
                    left.as(AST::MethodCall).arguments << block_literal
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
            when :SYMBOL
                advance
                AST::Literal.new(token.value.as(SymbolValue), location: token.location)
            when :ARGV
                advance
                AST::ArgvExpression.new(location: token.location)
            when :YIELD
                parse_yield_expression
            when :IDENTIFIER
                parse_identifier_expression
            when :INSTANCE_VAR
                ivar_token = expect(:INSTANCE_VAR)
                AST::InstanceVariable.new(ivar_token.value.as(String), location: ivar_token.location)
            when :TYPEOF
                parse_typeof_expression
            when :LBRACKET
                parse_array_literal
            when :LBRACE
                parse_braced_literal
            when :LPAREN
                advance
                expr = parse_expression
                expect(:RPAREN)
                expr
            when :FUN
                parse_function_literal
            when :THIN_ARROW
                parse_para_literal
            when :BAG
                parse_bag_constructor
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

        private def singleton_method_definition_start? : Bool
            token = current_token
            case token.type
            when :IDENTIFIER
                lookahead_for_singleton_receiver(1)
            when :INSTANCE_VAR
                next_token = peek_token
                return false unless next_token && next_token.type == :DOT
                method_name_token?(peek_token(2))
            else
                false
            end
        end

        private def lookahead_for_singleton_receiver(offset : Int32) : Bool
            index = offset
            loop do
                next_token = peek_token(index)
                return false unless next_token
                case next_token.type
                when :DOUBLE_COLON
                    segment = peek_token(index + 1)
                    return false unless segment && segment.type == :IDENTIFIER
                    index += 2
                when :DOT
                    return method_name_token?(peek_token(index + 1))
                else
                    return false
                end
            end
            false
        end

        private def method_name_token?(token : Token?) : Bool
            return false unless token
            token.not_nil!.type == :IDENTIFIER || METHOD_NAME_KEYWORDS.includes?(token.not_nil!.type)
        end

        private def parse_singleton_receiver : AST::Node
            case current_token.type
            when :IDENTIFIER
                parse_identifier_expression
            when :INSTANCE_VAR
                ivar_token = expect(:INSTANCE_VAR)
                AST::InstanceVariable.new(ivar_token.value.as(String), location: ivar_token.location)
            else
                error("Invalid singleton receiver", current_token)
            end
        end

        private def parse_typeof_expression : AST::Node
            token = expect(:TYPEOF)
            expect(:LPAREN)
            expr = parse_expression
            expect(:RPAREN)
            AST::MethodCall.new("typeof", [expr], nil, location: token.location)
        end

        private def parse_begin_expression : AST::Node
            begin_token = expect(:BEGIN)
            body = parse_block([:RESCUE, :ELSE, :ENSURE, :END])
            rescue_clauses = [] of AST::RescueClause
            while current_token.type == :RESCUE
                rescue_clauses << parse_rescue_clause
            end

            else_block = nil
            if current_token.type == :ELSE
                advance
                else_block = parse_block([:ENSURE, :END])
            end

            ensure_block = nil
            if current_token.type == :ENSURE
                advance
                ensure_block = parse_block([:END])
            end

            expect(:END)
            AST::BeginExpression.new(body, rescue_clauses, else_block, ensure_block, location: begin_token.location)
        end

        private def parse_raise_expression : AST::Node
            token = expect(:RAISE)
            if argument_terminator?(current_token)
                AST::RaiseExpression.new(nil, location: token.location)
            else
                value = parse_expression
                AST::RaiseExpression.new(value, location: token.location)
            end
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

        private def parse_braced_literal : AST::Node
            start_token = expect(:LBRACE)

            if current_token.type == :RBRACE
                advance
                return AST::TupleLiteral.new([] of AST::Node, location: start_token.location)
            end

            if named_tuple_entry_start?
                entries = parse_named_tuple_entries
                expect(:RBRACE)
                return AST::NamedTupleLiteral.new(entries, location: start_token.location)
            end

            first_element = parse_expression

            if current_token.type == :THIN_ARROW
                return parse_map_literal(start_token, first_element)
            end

            elements = [] of AST::Node
            elements << first_element
            while current_token.type == :COMMA
                advance
                break if current_token.type == :RBRACE
                elements << parse_expression
            end
            expect(:RBRACE)
            AST::TupleLiteral.new(elements, location: start_token.location)
        end

        private def parse_inline_named_tuple_literal : AST::NamedTupleLiteral
            entries = [] of AST::NamedTupleEntry
            loop do
                name_token = expect(:IDENTIFIER)
                expect(:COLON)
                value_node = parse_expression

                entries << AST::NamedTupleEntry.new(
                    name_token.value.as(String),
                    value_node,
                    nil,
                    name_token.location
                )

                break unless inline_named_argument_continuation?
                advance
            end
            AST::NamedTupleLiteral.new(entries, location: entries.first.location)
        end

        private def inline_named_argument_continuation? : Bool
            return false unless current_token.type == :COMMA
            next_token = peek_token
            return false unless next_token && next_token.type == :IDENTIFIER
            following = peek_token(2)
            !!(following && following.type == :COLON)
        end

        private def parse_named_tuple_entries : Array(AST::NamedTupleEntry)
            entries = [] of AST::NamedTupleEntry
            loop do
                name_token = expect(:IDENTIFIER)
                expect(:COLON)

                type_annotation = nil
                value_node = nil

                if named_tuple_type_annotation_ahead?
                    type_annotation = parse_type_expression
                    expect(:ASSIGN)
                    value_node = parse_expression
                else
                    value_node = parse_expression
                end

                entries << AST::NamedTupleEntry.new(
                    name_token.value.as(String),
                    value_node,
                    type_annotation,
                    name_token.location
                )

                break unless current_token.type == :COMMA
                advance
                break if current_token.type == :RBRACE
            end
            entries
        end

        private def named_tuple_entry_start? : Bool
            return false unless current_token.type == :IDENTIFIER
            next_token = peek_token
            !!(next_token && next_token.type == :COLON)
        end

        private def named_tuple_type_annotation_ahead? : Bool
            offset = 0
            loop do
                token = peek_token(offset)
                return false unless token
                case token.type
                when :ASSIGN
                    return true
                when :COMMA, :RBRACE
                    return false
                end
                offset += 1
            end
        end

        private def parse_map_literal(start_token : Token, first_key : AST::Node? = nil) : AST::Node
            entries = [] of Tuple(AST::Node, AST::Node)

            if first_key
                entries << parse_map_entry(first_key)
                while current_token.type == :COMMA
                    advance
                    break if current_token.type == :RBRACE
                    entries << parse_map_entry
                end
            elsif current_token.type != :RBRACE
                entries << parse_map_entry
                while current_token.type == :COMMA
                    advance
                    break if current_token.type == :RBRACE
                    entries << parse_map_entry
                end
            end

            expect(:RBRACE)
            AST::MapLiteral.new(entries, location: start_token.location)
        end

        private def parse_map_entry(existing_key : AST::Node? = nil) : Tuple(AST::Node, AST::Node)
            key = existing_key || parse_expression
            expect(:THIN_ARROW)
            value = parse_expression
            {key, value}
        end

        private def parse_with_expression : AST::Node
            with_token = expect(:WITH)
            receiver = parse_expression
            advance if current_token.type == :DO
            body = parse_block([:END])
            expect(:END)
            AST::WithExpression.new(receiver, body, location: with_token.location)
        end

        private def parse_yield_expression : AST::Node
            yield_token = expect(:YIELD)
            arguments = [] of AST::Node
            if current_token.type == :LPAREN
                arguments = parse_argument_list
            elsif !argument_terminator?(current_token)
                arguments << parse_expression
                while current_token.type == :COMMA
                    advance
                    arguments << parse_expression
                end
            end
            AST::YieldExpression.new(arguments, location: yield_token.location)
        end

        private def parse_para_literal : AST::Node
            arrow_token = expect(:THIN_ARROW)
            parameters = [] of AST::TypedParameter
            if current_token.type == :LPAREN
                parameters = parse_parameter_list(required: true)
            end
            return_type = parse_optional_return_type
            body = [] of AST::Node
            rescue_clauses = [] of AST::RescueClause
            if current_token.type == :DO
                expect(:DO)
                body = parse_block([:END, :RESCUE])
                while current_token.type == :RESCUE
                    rescue_clauses << parse_rescue_clause
                end
                expect(:END)
            elsif current_token.type == :LBRACE
                expect(:LBRACE)
                body = parse_block([:RBRACE])
                expect(:RBRACE)
            else
                error("Expected 'do' or '{' to start para body", current_token)
            end
            AST::ParaLiteral.new(parameters, body, rescue_clauses, return_type, location: arrow_token.location)
        end

        private def parse_bag_constructor : AST::Node
            bag_token = expect(:BAG)
            expect(:LPAREN)
            element_type = parse_type_expression
            expect(:RPAREN)
            AST::BagConstructor.new(element_type, location: bag_token.location)
        end

        private def parse_do_block_literal : AST::BlockLiteral
            start_token = expect(:DO)
            parameters = parse_optional_block_parameters
            body = parse_block([:END])
            expect(:END)
            AST::BlockLiteral.new(parameters, body, location: start_token.location)
        end

        private def parse_brace_block_literal : AST::BlockLiteral
            start_token = expect(:LBRACE)
            parameters = parse_optional_block_parameters
            body = parse_block([:RBRACE])
            expect(:RBRACE)
            AST::BlockLiteral.new(parameters, body, location: start_token.location)
        end

        private def parse_optional_block_parameters : Array(AST::TypedParameter)
            return [] of AST::TypedParameter unless current_token.type == :BIT_OR
            parse_block_parameters
        end

        private def parse_block_parameters : Array(AST::TypedParameter)
            expect(:BIT_OR)
            parameters = [] of AST::TypedParameter
            unless current_token.type == :BIT_OR
                parameters << parse_block_parameter
                while current_token.type == :COMMA
                    advance
                    parameters << parse_block_parameter
                end
            end
            expect(:BIT_OR)
            parameters
        end

        private def parse_block_parameter : AST::TypedParameter
            name_token = expect(:IDENTIFIER)
            type_annotation = nil
            if current_token.type == :COLON
                advance
                type_annotation = parse_type_expression
            end
            AST::TypedParameter.new(name_token.value.as(String), type_annotation)
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
                loop do
                    if named_tuple_entry_start?
                        arguments << parse_inline_named_tuple_literal
                    else
                        arguments << parse_expression
                    end
                    break unless current_token.type == :COMMA
                    advance
                    break if current_token.type == :RPAREN
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
                if constant_name?(left.name) && operator.nil?
                    AST::ConstantDeclaration.new(left.name, value, left.type_annotation, location: location)
                else
                    AST::Assignment.new(left.name, value, operator: operator, type_annotation: left.type_annotation, location: location)
                end
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

        private def constant_name?(name : String) : Bool
            return false if name.empty?
            first = name[0]
            first >= 'A' && first <= 'Z'
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

        private def expect_method_name : Token
            token = current_token
            # if token.type == :IDENTIFIER || METHOD_NAME_KEYWORDS.includes?(token.type)
            if token.type == :IDENTIFIER || METHOD_NAME_KEYWORDS.includes?(token.type) || OVERLOADABLE_OPERATORS.includes?(token.type)
                advance
                token
            else
                expect(:IDENTIFIER)
            end
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
                name = identifier_token.value.as(String)
                if current_token.type == :LPAREN
                    args = parse_type_argument_list
                    AST::GenericTypeExpression.new(name, args, location: identifier_token.location)
                else
                    AST::SimpleTypeExpression.new(name, location: identifier_token.location)
                end
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

        private def parse_type_argument_list : Array(AST::TypeExpression)
            expect(:LPAREN)
            arguments = [] of AST::TypeExpression
            unless current_token.type == :RPAREN
                arguments << parse_type_expression
                while current_token.type == :COMMA
                    advance
                    arguments << parse_type_expression
                end
            end
            expect(:RPAREN)
            arguments
        end
    end
end
