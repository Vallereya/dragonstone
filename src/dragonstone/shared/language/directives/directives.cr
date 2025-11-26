# ---------------------------------
# --------- Directives ------------
# ---------------------------------
module Dragonstone
    module Language
        module Directives
            extend self

            TYPED_DIRECTIVE_PATTERN = /\A#![ \t]*typed[^\r\n]*(\r?\n)?/i

            def process_typed_directive(source : String) : Tuple(String, Bool)
                if match = TYPED_DIRECTIVE_PATTERN.match(source)
                    newline = match[1]? || ""
                    directive_length = match[0].size
                    body_length = directive_length - newline.size
                    replacement = " " * body_length + newline
                    remainder = directive_length < source.size ? source[directive_length..-1] : ""
                    {replacement + remainder, true}
                else
                    {source, false}
                end
            end
        end
    end
end
