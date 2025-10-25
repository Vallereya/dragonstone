# ---------------------------------
# -------------- AST --------------
# ---------------------------------
require "../resolver/*"

module Dragonstone
    module AST
        alias NodeArray = Array(Node)
        alias RescueArray = Array(RescueClause)
        alias StringParts = Array(Tuple(Symbol, String))
        alias LiteralValue = Nil | Bool | Int64 | Float64 | String | Char

        abstract class Node
            getter location : Location?

            def initialize(@location : Location? = nil)
            end

            abstract def accept(visitor)

            def to_source : String
                raise NotImplementedError.new("#{self.class} must implement #to_source")
            end

            # I avoided dynamic String -> Symbol conversion to keep compatibility
            # across Crystal versions for some reason I have 3 versions. Names are 
            # kept as String for now.
        end

        class Program < Node
            getter statements : NodeArray

            def initialize(statements : NodeArray, location : Location? = nil)
                super(location: location)
                @statements = statements
            end

            def accept(visitor)
                visitor.visit_program(self)
            end
        end

        class ModuleDefinition < Node
            getter name : String
            getter body : NodeArray

            def initialize(name : String, body : NodeArray, location : Location? = nil)
                super(location: location)
                @name = name
                @body = body
            end

            def accept(visitor)
                visitor.visit_module_definition(self)
            end
        end

        class ClassDefinition < Node
            getter name : String
            getter body : NodeArray
            getter superclass : String?

            def initialize(name : String, body : NodeArray, superclass : String? = nil, location : Location? = nil)
                super(location: location)
                @name = name
                @body = body
                @superclass = superclass
            end

            def accept(visitor)
                visitor.visit_class_definition(self)
            end
        end

        class MethodCall < Node
            getter receiver : Node?
            getter name : String
            getter arguments : NodeArray

            def initialize(name : String, arguments : NodeArray, receiver : Node? = nil, location : Location? = nil)
                super(location: location)
                @receiver = receiver
                @name = name
                @arguments = arguments
            end

            def accept(visitor)
                visitor.visit_method_call(self)
            end

            def to_source : String
                base = if receiver
                    "#{receiver.not_nil!.to_source}.#{name}"

                else
                    name
                    
                end

                return base if arguments.empty?

                args = arguments.map(&.to_source).join(", ")
                "#{base}(#{args})"
            end
        end

        class DebugPrint < Node
            getter expression : Node

            def initialize(expression : Node, location : Location? = nil)
                super(location: location)
                @expression = expression
            end

            def accept(visitor)
                visitor.visit_debug_print(self)
            end

            def to_source : String
                expression.to_source
            end
        end

        class Assignment < Node
            getter name : String
            getter value : Node
            getter operator : Symbol?

            def initialize(name : String, value : Node, operator : Symbol? = nil, location : Location? = nil)
                super(location: location)
                @name = name
                @value = value
                @operator = operator
            end

            def accept(visitor)
                visitor.visit_assignment(self)
            end

            def to_source : String
                if operator
                    "#{name} #{operator} = #{value.to_source}"
                else
                    "#{name} = #{value.to_source}"
                end
            end
        end

        class AttributeAssignment < Node
            getter receiver : Node
            getter name : String
            getter value : Node
            getter operator : Symbol?

            def initialize(receiver : Node, name : String, value : Node, operator : Symbol? = nil, location : Location? = nil)
                super(location: location)
                @receiver = receiver
                @name = name
                @value = value
                @operator = operator
            end

            def accept(visitor)
                visitor.visit_attribute_assignment(self)
            end
        end

        class IndexAssignment < Node
            getter object : Node
            getter index : Node
            getter value : Node
            getter operator : Symbol?
            getter nil_safe : Bool

            def initialize(object : Node, index : Node, value : Node, operator : Symbol? = nil, nil_safe : Bool = false, location : Location? = nil)
                super(location: location)
                @object = object
                @index = index
                @value = value
                @operator = operator
                @nil_safe = nil_safe
            end

            def accept(visitor)
                visitor.visit_index_assignment(self)
            end
        end

        class ConstantDeclaration < Node
            getter name : String
            getter value : Node

            def initialize(name : String, value : Node, location : Location? = nil)
                super(location: location)
                @name = name
                @value = value
            end

            def accept(visitor)
                visitor.visit_constant_declaration(self)
            end
        end

        class Variable < Node
            getter name : String

            def initialize(name : String, location : Location? = nil)
                super(location: location)
                @name = name
            end

            def accept(visitor)
                visitor.visit_variable(self)
            end

            def to_source : String
                name
            end
        end

        class Literal < Node
            getter value : LiteralValue?

            def initialize(value : LiteralValue?, location : Location? = nil)
                super(location: location)
                @value = value
            end

            def accept(visitor)
                visitor.visit_literal(self)
            end

            def to_source : String
                value.inspect
            end
        end

        class ArrayLiteral < Node
            getter elements : NodeArray

            def initialize(elements : NodeArray, location : Location? = nil)
                super(location: location)
                @elements = elements
            end

            def accept(visitor)
                visitor.visit_array_literal(self)
            end

            def to_source : String
                "[#{elements.map(&.to_source).join(", ")}]"
            end
        end

        class IndexAccess < Node
            getter object : Node
            getter index : Node
            getter nil_safe : Bool

            def initialize(object : Node, index : Node, nil_safe : Bool = false, location : Location? = nil)
                super(location: location)
                @object = object
                @index = index
                @nil_safe = nil_safe
            end

            def accept(visitor)
                visitor.visit_index_access(self)
            end

            def to_source : String
                suffix = nil_safe ? "?" : ""
                "#{object.to_source}[#{index.to_source}]#{suffix}"
            end
        end

        class InterpolatedString < Node
            getter parts : StringParts

            def initialize(parts : StringParts, location : Location? = nil)
                super(location: location)
                @parts = parts
            end

            def accept(visitor)
                visitor.visit_interpolated_string(self)
            end

            def to_source : String
                result = String.build do |io|
                    io << '"'
                    parts.each do |part|
                        type, content = part

                        if type == :string
                            io << content

                        else
                            io << "\#{#{content}}"

                        end
                    end

                    io << '"'
                end
                result
            end

            def normalized_parts : StringParts
                parts.map do |type, content|
                    type == :string ? {type, content} : {:expression, content}
                end
            end
        end

        class BinaryOp < Node
            getter left : Node
            getter operator : Symbol
            getter right : Node

            def initialize(left : Node, operator : Symbol, right : Node, location : Location? = nil)
                super(location: location)
                @left = left
                @operator = operator
                @right = right
            end

            def accept(visitor)
                visitor.visit_binary_op(self)
            end

            def to_source : String
                "#{left.to_source} #{operator} #{right.to_source}"
            end
        end

        class UnaryOp < Node
            getter operator : Symbol
            getter operand : Node

            def initialize(operator : Symbol, operand : Node, location : Location? = nil)
                super(location: location)
                @operator = operator
                @operand = operand
            end

            def accept(visitor)
                visitor.visit_unary_op(self)
            end

            def to_source : String
                "#{operator}#{operand.to_source}"
            end
        end

        class ConditionalExpression < Node
            getter condition : Node
            getter then_branch : Node
            getter else_branch : Node

            def initialize(condition : Node, then_branch : Node, else_branch : Node, location : Location? = nil)
                super(location: location)
                @condition = condition
                @then_branch = then_branch
                @else_branch = else_branch
            end

            def accept(visitor)
                visitor.visit_conditional_expression(self)
            end

            def to_source : String
                "#{condition.to_source} ? #{then_branch.to_source} : #{else_branch.to_source}"
            end
        end

        class IfStatement < Node
            getter condition : Node
            getter then_block : NodeArray
            getter elsif_blocks : Array(ElsifClause)
            getter else_block : NodeArray?

            def initialize(condition : Node, then_block : NodeArray, elsif_blocks : Array(ElsifClause) = [] of ElsifClause, else_block : NodeArray? = nil, location : Location? = nil)
                super(location: location)
                @condition = condition
                @then_block = then_block
                @elsif_blocks = elsif_blocks
                @else_block = else_block
            end

            def accept(visitor)
                visitor.visit_if_statement(self)
            end
        end

        class ElsifClause < Node
            getter condition : Node
            getter block : NodeArray

            def initialize(condition : Node, block : NodeArray, location : Location? = nil)
                super(location: location)
                @condition = condition
                @block = block
            end

            def accept(visitor)
                if visitor.responds_to?(:visit_elsif_clause)
                    visitor.visit_elsif_clause(self)

                else
                    nil

                end
            end
        end

        class UnlessStatement < Node
            getter condition : Node
            getter body : NodeArray
            getter else_block : NodeArray?

            def initialize(condition : Node, body : NodeArray, else_block : NodeArray? = nil, location : Location? = nil)
                super(location: location)
                @condition = condition
                @body = body
                @else_block = else_block
            end

            def accept(visitor)
                visitor.visit_unless_statement(self)
            end
        end

        class CaseStatement < Node
            getter expression : Node?
            getter when_clauses : Array(WhenClause)
            getter else_block : NodeArray?

            def initialize(expression : Node?, when_clauses : Array(WhenClause), else_block : NodeArray? = nil, location : Location? = nil)
                super(location: location)
                @expression = expression
                @when_clauses = when_clauses
                @else_block = else_block
            end

            def accept(visitor)
                visitor.visit_case_statement(self)
            end
        end

        class WhenClause < Node
            getter conditions : NodeArray
            getter block : NodeArray

            def initialize(conditions : NodeArray, block : NodeArray, location : Location? = nil)
                super(location: location)
                @conditions = conditions
                @block = block
            end

            def accept(visitor)
                if visitor.responds_to?(:visit_when_clause)
                    visitor.visit_when_clause(self)

                else
                    nil

                end
            end
        end

        class WhileStatement < Node
            getter condition : Node
            getter block : NodeArray

            def initialize(condition : Node, block : NodeArray, location : Location? = nil)
                super(location: location)
                @condition = condition
                @block = block
            end

            def accept(visitor)
                visitor.visit_while_statement(self)
            end
        end

        class BreakStatement < Node
            getter condition : Node?
            getter condition_type : Symbol?

            def initialize(condition : Node? = nil, condition_type : Symbol? = nil, location : Location? = nil)
                super(location: location)
                @condition = condition
                @condition_type = condition_type
            end

            def accept(visitor)
                visitor.visit_break_statement(self)
            end
        end

        class NextStatement < Node
            getter condition : Node?
            getter condition_type : Symbol?

            def initialize(condition : Node? = nil, condition_type : Symbol? = nil, location : Location? = nil)
                super(location: location)
                @condition = condition
                @condition_type = condition_type
            end

            def accept(visitor)
                visitor.visit_next_statement(self)
            end
        end

        class RescueClause < Node
            getter exceptions : Array(String)
            getter exception_variable : String?
            getter body : NodeArray

            def initialize(exceptions : Array(String), exception_variable : String?, body : NodeArray, location : Location? = nil)
                super(location: location)
                @exceptions = exceptions
                @exception_variable = exception_variable
                @body = body
            end

            def accept(visitor)
                if visitor.responds_to?(:visit_rescue_clause)
                    visitor.visit_rescue_clause(self)

                else
                    nil

                end
            end
        end

        class FunctionDef < Node
            getter name : String
            getter parameters : Array(String)
            getter body : NodeArray
            getter rescue_clauses : RescueArray

            def initialize(name : String, parameters : Array(String), body : NodeArray, rescue_clauses : RescueArray = [] of RescueClause, location : Location? = nil)
                super(location: location)
                @name = name
                @parameters = parameters
                @body = body
                @rescue_clauses = rescue_clauses
            end

            def accept(visitor)
                visitor.visit_function_def(self)
            end
        end

        class FunctionLiteral < Node
            getter parameters : Array(String)
            getter body : NodeArray
            getter rescue_clauses : RescueArray

            def initialize(parameters : Array(String), body : NodeArray, rescue_clauses : RescueArray = [] of RescueClause, location : Location? = nil)
                super(location: location)
                @parameters = parameters
                @body = body
                @rescue_clauses = rescue_clauses
            end

            def accept(visitor)
                visitor.visit_function_literal(self)
            end
        end

        class ReturnStatement < Node
            getter value : Node?

            def initialize(value : Node?, location : Location? = nil)
                super(location: location)
                @value = value
            end

            def accept(visitor)
                visitor.visit_return_statement(self)
            end

            def to_source : String
                if value
                    "return #{value.not_nil!.to_source}"

                else
                    "return"

                end
            end
        end
    end
end
