# ---------------------------------
# ---------- Error ----------------
# ---------- Handling -------------
# ---------------------------------
module Dragonstone
    record Location, 
    file : String?, 
    line : Int32?, 
    column : Int32?, 
    length : Int32?, 
    source_line : String? do

        def width : Int32
            length.nil? || length.not_nil! <= 0 ? 1 : length.not_nil!
        end

        def label : String
            file_part = file || "<source>"
            line_part = line || 0
            column_part = column || 0
            "#{file_part}:#{line_part}:#{column_part}"
        end
    end

    class Error < Exception
        getter location : Location?
        getter hint : String?
        getter original_message : String

        def initialize(@original_message : String, @location : Location? = nil, @hint : String? = nil)
            super(build_message(@original_message))
        end

        private def build_message(message : String) : String
            return message unless location

            parts = [] of String
            parts << "#{location.not_nil!.label}: #{diagnostic_label}: #{message}"

        if loc_source_line = location.not_nil!.source_line
            parts << loc_source_line
            loc = location.not_nil!
            caret = " " * ([loc.column || 0, 1].max - 1) + "^" * loc.width
            parts << caret
        end

            parts << "hint: #{hint}" if hint
            parts.join("\n")
        end

        private def diagnostic_label : String
            self.class.name.split("::").last
        end
    end

    # Raised general errors with syntax.
    class SyntaxError < Error
    end

    # Raised for lexing and tokenization errors via syntax.
    class LexerError < SyntaxError
    end

    # Raised for parsing errors via Syntax.
    class ParserError < SyntaxError
    end

    # Raised for general runtime errors.
    class RuntimeError < Error
    end

    # Raised for interpreter errors via runtime.
    class InterpreterError < RuntimeError
    end

    # Raised when referencing an undefined identifier.
    class NameError < InterpreterError
    end

    # Raised when a type constraint is violated.
    class TypeError < InterpreterError
    end
    
    # Raised when attempting to redefine immutable bindings.
    class ConstantError < InterpreterError
    end
end