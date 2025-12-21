# ---------------------------------
# ------------- Lexer -------------
# ---------------------------------
require "unicode"
require "string/grapheme"
require "../resolver/encoding"
require "../diagnostics/errors"
require "../../runtime/symbol"

module Dragonstone
    alias TokenValue = Nil | Bool | Int64 | Float64 | String | Char | SymbolValue | Array(Tuple(Symbol, String))

    class Token
        getter type : Symbol
        getter value : TokenValue
        getter line : Int32
        getter column : Int32
        getter length : Int32
        getter line_text : String?
        getter source_name : String

        def initialize(type : Symbol, value : TokenValue, line : Int32, column : Int32, length : Int32, line_text : String?, source_name : String)
            @type = type
            @value = value
            @line = line
            @column = column
            @length = length
            @line_text = line_text
            @source_name = source_name
        end

        def location : Location
            Location.new(
                file: source_name,
                line: line,
                column: column,
                length: length,
                source_line: line_text
            )
        end

        def to_s : String
            "Token(#{type}, #{value.inspect}, line: #{line}, col: #{column})"
        end
    end

    class Lexer
        KEYWORDS = %w[
            echo
            eecho
            puts 
            argv
            if 
            else 
            elsif 
            elseif 
            end 
            while 
            do 
            def 
            define
            fun 
            function
            abstract
            module 
            class 
            return 
            true 
            false 
            nil 
            typeof 
            con 
            unless 
            case 
            when 
            select 
            break 
            next 
            begin
            rescue
            ensure
            raise
            redo
            retry
            use
            from
            as
            private
            protected
            getter
            setter
            bag
            property
            enum
            struct
            alias
            extend
            with
            yield
            super
        ]

        getter source_name : String

        def initialize(source : String, source_name : String = "<source>")
            @source = source
            @source_name = source_name
            @pos = 0
            @line = 1
            @column = 1
            @tokens = [] of Token
            @lines = source.split(/\r?\n/)
            @lines << "" if source.ends_with?("\n")
        end

        def tokenize : Array(Token)
            while (char = current_char)
                if char.ascii_whitespace?
                    skip_whitespace
                elsif char == '#'
                    if peek_char == '['
                        skip_multiline_comment
                    else
                        skip_comment
                    end
                elsif char == '"'
                    scan_string
                elsif char == '\''
                    scan_char
                elsif char == 'e' && peek_char == '!'
                    add_token(:DEBUG_ECHO, "e!", @line, @column, 2)
                    advance(2)
                elsif char == 'e' && peek_char == 'e' && peek_char(2) == '!'
                    add_token(:DEBUG_EECHO, "ee!", @line, @column, 3)
                    advance(3)
                elsif char == 'p' && peek_char == '!'
                    add_token(:DEBUG_ECHO, "p!", @line, @column, 2)
                    advance(2)
                elsif identifier_start?(char)
                    scan_identifier
                elsif char.ascii_number?
                    scan_number
                else
                    case char
                when '@'
                    if peek_char == '['
                        add_token(:ANNOTATION_START, "@[", @line, @column, 2)
                        advance(2)
                    else
                        scan_instance_variable
                    end
                when '='
                    case peek_char
                    when '='
                        if peek_char(2) == '='
                            add_token(:CASE_EQUALS, "===", @line, @column, 3)
                            advance(3)
                        else
                            add_token(:EQUALS, "==", @line, @column, 2)
                            advance(2)
                        end
                    when '~'
                        add_token(:MATCH, "=~", @line, @column, 2)
                        advance(2)
                    when '>'
                        add_token(:FAT_ARROW, "=>", @line, @column, 2)
                        advance(2)
                    else
                        add_token(:ASSIGN, "=", @line, @column, 1)
                        advance
                    end
                when '!'
                    case peek_char
                    when '='
                        add_token(:NOT_EQUALS, "!=", @line, @column, 2)
                        advance(2)
                    when '~'
                        add_token(:NOT_MATCH, "!~", @line, @column, 2)
                        advance(2)
                    else
                        add_token(:NOT, "!", @line, @column, 1)
                        advance
                    end
                when '+'
                    if peek_char == '='
                        add_token(:PLUS_ASSIGN, "+=", @line, @column, 2)
                        advance(2)
                    else
                        add_token(:PLUS, "+", @line, @column, 1)
                        advance
                    end
                when '-'
                    case peek_char
                    when '='
                        add_token(:MINUS_ASSIGN, "-=", @line, @column, 2)
                        advance(2)
                    when '>'
                        add_token(:THIN_ARROW, "->", @line, @column, 2)
                        advance(2)
                    else
                        add_token(:MINUS, "-", @line, @column, 1)
                        advance
                    end
                when '*'
                    if peek_char == '*'
                        if peek_char(2) == '='
                            add_token(:POWER_ASSIGN, "**=", @line, @column, 3)
                            advance(3)
                        else
                            add_token(:POWER, "**", @line, @column, 2)
                            advance(2)
                        end
                    elsif peek_char == '='
                        add_token(:MULTIPLY_ASSIGN, "*=", @line, @column, 2)
                        advance(2)
                    else
                        add_token(:MULTIPLY, "*", @line, @column, 1)
                        advance
                    end
                when '/'
                    if peek_char == '/'
                        if peek_char(2) == '='
                            add_token(:FLOOR_DIVIDE_ASSIGN, "//=", @line, @column, 3)
                            advance(3)
                        else
                            add_token(:FLOOR_DIVIDE, "//", @line, @column, 2)
                            advance(2)
                        end
                    elsif peek_char == '='
                        add_token(:DIVIDE_ASSIGN, "/=", @line, @column, 2)
                        advance(2)
                    else
                        add_token(:DIVIDE, "/", @line, @column, 1)
                        advance
                    end
                when '('
                    add_token(:LPAREN, "(", @line, @column, 1)
                    advance
                when ')'
                    add_token(:RPAREN, ")", @line, @column, 1)
                    advance
                when '{'
                    add_token(:LBRACE, "{", @line, @column, 1)
                    advance
                when '}'
                    add_token(:RBRACE, "}", @line, @column, 1)
                    advance
                when '['
                    add_token(:LBRACKET, "[", @line, @column, 1)
                    advance
                when ']'
                    if peek_char == '?'
                        add_token(:RBRACKET_QUESTION, "]?", @line, @column, 2)
                        advance(2)
                    else
                        add_token(:RBRACKET, "]", @line, @column, 1)
                        advance
                    end
                when ','
                    add_token(:COMMA, ",", @line, @column, 1)
                    advance
                when '<'
                    if peek_char == '<'
                        if peek_char(2) == '='
                            add_token(:SHIFT_LEFT_ASSIGN, "<<=", @line, @column, 3)
                            advance(3)
                        else
                            add_token(:SHIFT_LEFT, "<<", @line, @column, 2)
                            advance(2)
                        end
                    elsif peek_char == '='
                        if peek_char(2) == '>'
                            add_token(:SPACESHIP, "<=>", @line, @column, 3)
                            advance(3)
                        else
                            add_token(:LESS_EQUAL, "<=", @line, @column, 2)
                            advance(2)
                        end
                    else
                        add_token(:LESS, "<", @line, @column, 1)
                        advance
                    end
                when '>'
                    if peek_char == '>'
                        if peek_char(2) == '='
                            add_token(:SHIFT_RIGHT_ASSIGN, ">>=", @line, @column, 3)
                            advance(3)
                        else
                            add_token(:SHIFT_RIGHT, ">>", @line, @column, 2)
                            advance(2)
                        end
                    elsif peek_char == '='
                        add_token(:GREATER_EQUAL, ">=", @line, @column, 2)
                        advance(2)
                    else
                        add_token(:GREATER, ">", @line, @column, 1)
                        advance
                    end
                when '&'
                    case peek_char
                    when '&'
                        if peek_char(2) == '='
                            add_token(:LOGICAL_AND_ASSIGN, "&&=", @line, @column, 3)
                            advance(3)
                        else
                            add_token(:LOGICAL_AND, "&&", @line, @column, 2)
                            advance(2)
                        end
                    when '+'
                        if peek_char(2) == '='
                            add_token(:WRAP_PLUS_ASSIGN, "&+=", @line, @column, 3)
                            advance(3)
                        else
                            add_token(:WRAP_PLUS, "&+", @line, @column, 2)
                            advance(2)
                        end
                    when '-'
                        if peek_char(2) == '='
                            add_token(:WRAP_MINUS_ASSIGN, "&-=", @line, @column, 3)
                            advance(3)
                        else
                            add_token(:WRAP_MINUS, "&-", @line, @column, 2)
                            advance(2)
                        end
                    when '*'
                        if peek_char(2) == '*'
                        if peek_char(3) == '='
                            add_token(:WRAP_POWER_ASSIGN, "&**=", @line, @column, 4)
                            advance(4)
                        else
                            add_token(:WRAP_POWER, "&**", @line, @column, 3)
                            advance(3)
                        end
                        elsif peek_char(2) == '='
                            add_token(:WRAP_MULTIPLY_ASSIGN, "&*=", @line, @column, 3)
                            advance(3)
                        else
                            add_token(:WRAP_MULTIPLY, "&*", @line, @column, 2)
                            advance(2)
                        end
                    when '='
                        add_token(:BIT_AND_ASSIGN, "&=", @line, @column, 2)
                        advance(2)
                    else
                        add_token(:BIT_AND, "&", @line, @column, 1)
                        advance
                    end
                when '|'
                    if peek_char == '|'
                        if peek_char(2) == '='
                            add_token(:LOGICAL_OR_ASSIGN, "||=", @line, @column, 3)
                            advance(3)
                        else
                            add_token(:LOGICAL_OR, "||", @line, @column, 2)
                            advance(2)
                        end
                    elsif peek_char == '='
                        add_token(:BIT_OR_ASSIGN, "|=", @line, @column, 2)
                        advance(2)
                    else
                        add_token(:BIT_OR, "|", @line, @column, 1)
                        advance
                    end
                when '^'
                    if peek_char == '='
                        add_token(:BIT_XOR_ASSIGN, "^=", @line, @column, 2)
                        advance(2)
                    else
                        add_token(:BIT_XOR, "^", @line, @column, 1)
                        advance
                    end
                when '~'
                    add_token(:BIT_NOT, "~", @line, @column, 1)
                    advance
                when '?'
                    add_token(:QUESTION, "?", @line, @column, 1)
                    advance
                when ':'
                    if peek_char == ':'
                        add_token(:DOUBLE_COLON, "::", @line, @column, 2)
                        advance(2)
                    elsif symbol_literal_start?
                        scan_symbol
                    else
                        add_token(:COLON, ":", @line, @column, 1)
                        advance
                    end
                when '.'
                    if peek_char == '.'
                        if peek_char(2) == '.'
                            add_token(:RANGE_EXCLUSIVE, "...", @line, @column, 3)
                            advance(3)
                        else
                            add_token(:RANGE_INCLUSIVE, "..", @line, @column, 2)
                            advance(2)
                        end
                    else
                        add_token(:DOT, ".", @line, @column, 1)
                        advance
                    end
                when '%'
                    if peek_char == '='
                        add_token(:MODULO_ASSIGN, "%=", @line, @column, 2)
                        advance(2)
                    else
                        add_token(:MODULO, "%", @line, @column, 1)
                        advance
                    end
                    else
                        raise error_at_current("Unexpected character '#{char}'")
                    end
                end
            end

            add_token(:EOF, nil, @line, @column, 0)
            @tokens
        end

        private def current_char : Char?
            return nil if @pos >= @source.size
            @source[@pos]
        end

        private def peek_char(offset = 1) : Char?
            index = @pos + offset
            return nil if index >= @source.size
            @source[index]
        end

        private def advance(count = 1)
            count.times do
                char = current_char
                break unless char
                @pos += 1
                if char == '\n'
                    @line += 1
                    @column = 1
                else
                    @column += 1
                end
            end
        end

        private def skip_whitespace
            while (char = current_char) && char.whitespace?
                advance
            end
        end

        private def skip_comment
            while (char = current_char) && char != '\n'
                advance
            end
        end

        private def skip_multiline_comment
            start_line = @line
            start_col = @column
            advance(2)
            nesting = 1

            while nesting > 0 && (char = current_char)
                if char == '#' && peek_char == '['
                    nesting += 1
                    advance(2)
                elsif char == ']' && peek_char == '#'
                    nesting -= 1
                    advance(2)
                else
                    advance
                end
            end

            if nesting > 0
                raise error_at(start_line, start_col, "Unterminated multi-line comment", length: 2)
            end
        end

        private def scan_string
            start_line = @line
            start_col = @column
            advance

            parts = [] of Tuple(Symbol, String)
            current_part = String::Builder.new

            while (char = current_char)
                break if char == '"'

                if char == '\\'
                    advance
                    current_part << read_escape_sequence(:string, start_line, start_col)
                elsif char == '#' && peek_char == '{'
                    unless current_part.empty?
                        parts << {:string, current_part.to_s}
                        current_part = String::Builder.new
                    end

                    advance(2)
                    interpolation = String::Builder.new
                    brace_count = 1

                    while brace_count > 0 && (inner = current_char)
                        if inner == '{'
                            brace_count += 1
                        elsif inner == '}'
                            brace_count -= 1
                            break if brace_count == 0
                        end
                        interpolation << inner
                        advance
                    end

                    if brace_count != 0
                        raise error_at(start_line, start_col, "Unterminated string interpolation")
                    end

                    parts << {:interpolation, interpolation.to_s}
                    advance
                else
                    current_part << char
                    advance
                end
            end

            unless current_char == '"'
                raise error_at(start_line, start_col, "Unterminated string literal")
            end

            unless current_part.empty?
                parts << {:string, current_part.to_s}
            end

            advance

            if parts.any? { |part| part[0] == :interpolation }
                add_token(:INTERPOLATED_STRING, parts, start_line, start_col, compute_length(parts))
            else
                value = parts.empty? ? "" : parts[0][1]
                add_token(:STRING, value, start_line, start_col, value.size)
            end
        end

        private def compute_length(parts : Array(Tuple(Symbol, String))) : Int32
            length = parts.sum { |part| part[1].size }
            (length + 2).to_i
        end

        private def scan_identifier
            start_line = @line
            start_col = @column
            identifier = String::Builder.new

            while (char = current_char) && identifier_part?(char)
                identifier << char
                advance
            end          

            trailing = current_char
            if trailing && trailing_identifier_char?(trailing)
                if trailing == '=' && (peek_char == '=' || peek_char == '>')
                    # Treat as operator token instead of identifier suffix
                else
                    identifier << trailing
                    advance
                end
            end

            identifier_str = identifier.to_s

            if KEYWORDS.includes?(identifier_str)
                keyword = identifier_str.downcase
                type : Symbol = case keyword
                    when "true" then :TRUE
                    when "false" then :FALSE
                    when "nil" then :NIL
                    when "elseif" then :ELSIF
                    when "echo", "puts" then :ECHO
                    when "eecho" then :EECHO
                    when "argv" then :ARGV
                    when "if" then :IF
                    when "else" then :ELSE
                    when "elsif" then :ELSIF
                    when "end" then :END
                    when "while" then :WHILE
                    when "do" then :DO
                    when "def", "define" then :DEF
                    when "fun", "function" then :FUN
                    when "abstract" then :ABSTRACT
                    when "module" then :MODULE
                    when "class" then :CLASS
                    when "return" then :RETURN
                    when "typeof" then :TYPEOF
                    when "con" then :CON
                    when "unless" then :UNLESS
                    when "case" then :CASE
                    when "when" then :WHEN
                    when "select" then :SELECT
                    when "break" then :BREAK
                    when "next" then :NEXT
                    when "begin" then :BEGIN
                    when "rescue" then :RESCUE
                    when "ensure" then :ENSURE
                    when "raise" then :RAISE
                    when "redo" then :REDO
                    when "retry" then :RETRY
                    when "use" then :USE
                    when "from" then :FROM
                    when "as" then :AS
                    when "private" then :PRIVATE
                    when "protected" then :PROTECTED
                    when "getter" then :GETTER
                    when "setter" then :SETTER
                    when "bag" then :BAG
                    when "property" then :PROPERTY
                    when "enum" then :ENUM
                    when "struct" then :STRUCT
                    when "alias" then :ALIAS
                    when "extend" then :EXTEND
                    when "with" then :WITH
                    when "yield" then :YIELD
                    when "super" then :SUPER
                    else
                        :IDENTIFIER
                    end
                value = case keyword
                    when "true" then true
                    when "false" then false
                    when "nil" then nil
                    else
                    identifier_str
                    end
                add_token(type, value, start_line, start_col, identifier_str.size)
            else
                add_token(:IDENTIFIER, identifier_str, start_line, start_col, identifier_str.size)
            end
        end

        private def trailing_identifier_char?(char : Char) : Bool
            char == '?' || char == '!' || char == '='
        end

        private def scan_instance_variable
            start_line = @line
            start_col = @column
            advance # consume '@'

            if current_char == '@'
                raise error_at_current("Class variables (@@) are not supported yet", 2)
            end

            char = current_char
            unless char && identifier_start?(char)
                raise error_at_current("Invalid instance variable name", 1)
            end

            identifier = String::Builder.new
            while (char = current_char) && identifier_part?(char)
                identifier << char
                advance
            end

            name = identifier.to_s
            length = @column - start_col
            add_token(:INSTANCE_VAR, name, start_line, start_col, length)
        end

        private def scan_number
            start_line = @line
            start_col = @column
            number = String::Builder.new

            while (char = current_char) && char.ascii_number?
                number << char
                advance
            end

            if current_char == '.' && peek_char.try(&.ascii_number?)
                number << '.'
                advance
                while (char = current_char) && char.ascii_number?
                    number << char
                    advance
                end
                number_str = number.to_s  # Convert to String first
                add_token(:FLOAT, number_str.to_f64, start_line, start_col, number_str.size)
            else
                number_str = number.to_s  # Convert to String first
                add_token(:INTEGER, number_str.to_i64, start_line, start_col, number_str.size)
            end
        end

        private def scan_char
            start_line = @line
            start_col = @column
            advance

            char = current_char
            raise error_at(start_line, start_col, "Empty character literal") unless char

            value = if char == '\\'
                advance
                read_escape_sequence(:char, start_line, start_col)
            else
                advance
                char
            end

            unless current_char == '\''
                raise error_at(start_line, start_col, "Unterminated character literal")
            end

            advance
            add_token(:CHAR, value, start_line, start_col, 3)
        end

        private def scan_symbol
            start_line = @line
            start_col = @column
            advance

            char = current_char
            unless char && identifier_start?(char)
                raise error_at(start_line, start_col, "Invalid symbol literal", length: 1)
            end

            identifier = String::Builder.new
            identifier << char
            advance

            while (char = current_char) && identifier_part?(char)
                identifier << char
                advance
            end

            name = identifier.to_s
            length = @column - start_col
            add_token(:SYMBOL, SymbolValue.new(name), start_line, start_col, length)
        end

        private def symbol_literal_start? : Bool
            next_char = peek_char
            return false unless next_char && identifier_start?(next_char)

            return true if @pos.zero?
            previous_index = @pos - 1
            previous_char = @source[previous_index]?
            return true unless previous_char && identifier_part?(previous_char)
            false
        end

        private def identifier_start?(char : Char) : Bool
            char.ascii_letter? || char == '_' || unicode_identifier_start?(char)
        end

        private def identifier_part?(char : Char) : Bool
            char.ascii_letter? || char.ascii_number? || char == '_' || unicode_identifier_part?(char)
        end

        private def unicode_identifier_start?(char : Char) : Bool
            return false if char.ascii?
            Unicode.letter?(char) || emoji_identifier_char?(char)
        end

        private def unicode_identifier_part?(char : Char) : Bool
            return false if char.ascii?
            Unicode.letter?(char) || Unicode.number?(char) || char.mark? || emoji_identifier_char?(char)
        end

        private def emoji_identifier_char?(char : Char) : Bool
            String::Grapheme::Property.from(char).extended_pictographic?
        end

        private def read_escape_sequence(_literal : Symbol, start_line : Int32, start_col : Int32) : Char
            escape = current_char || raise error_at(start_line, start_col, "Unterminated escape sequence")

            case escape
            when 'n'
                advance
                '\n'
            when 't'
                advance
                '\t'
            when 'r'
                advance
                '\r'
            when 'b'
                advance
                '\b'
            when 'f'
                advance
                '\f'
            when 'v'
                advance
                '\v'
            when '0'
                advance
                '\0'
            when '\\'
                advance
                '\\'
            when '"'
                advance
                '"'
            when '\''
                advance
                '\''
            when 'u'
                advance
                read_unicode_codepoint(start_line, start_col)
            when 'x'
                advance
                read_fixed_length_hex_escape(2, start_line, start_col)
            else
                advance
                escape
            end
        end

        private def read_unicode_codepoint(start_line : Int32, start_col : Int32) : Char
            codepoint = if current_char == '{'
                advance
                read_variable_length_unicode_escape(start_line, start_col)
            else
                read_fixed_length_hex_value(4, start_line, start_col)
            end

            Encoding::Checks.ensure_scalar!(codepoint, @source_name, start_line, start_col)
            codepoint.chr
        end

        private def read_variable_length_unicode_escape(start_line : Int32, start_col : Int32) : Int32
            digits = String::Builder.new

            while (char = current_char)
                break if char == '}'
                unless hex_digit?(char)
                    raise error_at(start_line, start_col, "Invalid unicode escape sequence")
                end
                digits << char
                advance
            end

            unless current_char == '}'
                raise error_at(start_line, start_col, "Unterminated unicode escape sequence")
            end

            if digits.empty?
                raise error_at(start_line, start_col, "Unicode escape must contain at least one hex digit")
            end

            value = digits.to_s.to_i(16)
            advance # consume closing brace
            value
        end

        private def read_fixed_length_hex_escape(length : Int32, start_line : Int32, start_col : Int32) : Char
            codepoint = read_fixed_length_hex_value(length, start_line, start_col)
            Encoding::Checks.ensure_scalar!(codepoint, @source_name, start_line, start_col)
            codepoint.chr
        end

        private def read_fixed_length_hex_value(length : Int32, start_line : Int32, start_col : Int32) : Int32
            value = 0
            length.times do
                char = current_char || raise error_at(start_line, start_col, "Unterminated escape sequence")
                unless hex_digit?(char)
                    raise error_at(start_line, start_col, "Invalid hex digit `#{char}` in escape sequence")
                end
                value = (value << 4) | hex_digit_value(char)
                advance
            end
            value
        end

        private def hex_digit?(char : Char) : Bool
            (char >= '0' && char <= '9') ||
                (char >= 'a' && char <= 'f') ||
                (char >= 'A' && char <= 'F')
        end

        private def hex_digit_value(char : Char) : Int32
            case char
            when '0'..'9'
                char.ord - '0'.ord
            when 'a'..'f'
                10 + (char.ord - 'a'.ord)
            when 'A'..'F'
                10 + (char.ord - 'A'.ord)
            else
                0
            end
        end

        private def add_token(type : Symbol, value : TokenValue, line : Int32 = @line, column : Int32 = @column, length : Int32 = default_length(value))
            @tokens << Token.new(type, value, line, column, length, line_text_for(line), @source_name)
        end

        private def default_length(value : TokenValue) : Int32
            case value
            when String
                [value.size, 1].max
            when Char
                1
            when Nil
                1
            when Array(Tuple(Symbol, String))
                value.sum { |part| part[1].size }.to_i + 2
            else
                value.to_s.size
            end
        end

        private def line_text_for(line : Int32) : String?
            return nil if line <= 0
            index = line - 1
            @lines[index]? 
        end

        private def error_at_current(message : String, length : Int32 = 1)
            location = Location.new(
                file: @source_name,
                line: @line,
                column: @column,
                length: length,
                source_line: line_text_for(@line)
            )
            LexerError.new(message, location: location)
        end

        private def error_at(line : Int32, column : Int32, message : String, length : Int32 = 1)
            location = Location.new(
                file: @source_name,
                line: line,
                column: column,
                length: length,
                source_line: line_text_for(line)
            )
            LexerError.new(message, location: location)
        end
    end
end
