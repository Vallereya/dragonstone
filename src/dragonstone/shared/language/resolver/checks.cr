require "../diagnostics/errors"
require "./utf8"

module Dragonstone
    module Encoding
        module Checks
            extend self

            def ensure_valid_utf8!(bytes : Bytes, path : String)
                return if UTF8.valid?(bytes)
                raise encoding_error(path, "Invalid UTF-8 byte sequence detected while reading #{File.basename(path)}")
            end

            def ensure_scalar!(codepoint : Int32, path : String, line : Int32, column : Int32)
                if codepoint < 0 || codepoint > Char::MAX_CODEPOINT
                    raise encoding_error(path, "Unicode escape is out of range (0x#{codepoint.to_s(16).upcase})", line, column)
                end

                if 0xD800 <= codepoint <= 0xDFFF
                    raise encoding_error(path, "Unicode escape points to a surrogate pair (0x#{codepoint.to_s(16).upcase})", line, column)
                end
            end

            def encoding_error(path : String, message : String, line : Int32 = 1, column : Int32 = 1, hint : String? = nil) : SyntaxError
                location = Location.new(
                    file: path,
                    line: line,
                    column: column,
                    length: 1,
                    source_line: nil
                )
                SyntaxError.new(message, location: location, hint: hint)
            end
        end
    end
end
