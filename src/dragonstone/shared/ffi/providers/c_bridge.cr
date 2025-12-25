module Dragonstone
    module FFI
        module Providers
            module CBridge
                extend Dragonstone::FFI::Utils

                lib DragonstoneLibC
                    fun getchar : Int32
                end

                def self.call(function_name : String, arguments : Array(Dragonstone::FFI::InteropValue)) : Dragonstone::FFI::InteropValue
                    case function_name
                    when "printf"
                        format_value = expect_string(arguments, 0, function_name)
                        ::LibC.printf(format_value)
                    when "getchar"
                        DragonstoneLibC.getchar
                    when "write"
                        fd = expect_int(arguments, 0, function_name)
                        content = expect_string(arguments, 1, function_name)
                        count = if arguments.size >= 3
                            expect_int(arguments, 2, function_name)
                        else
                            content.bytesize
                        end
                        buf = content.to_unsafe

                        {% if flag?(:windows) %}
                            ::LibC._write(fd, buf, count.to_u32).to_i64
                        {% else %}
                            capped = Math.min(count, content.bytesize)
                            {% if flag?(:bits32) %}
                                ::LibC.write(fd.to_i, buf.as(Void*), capped.to_u32).to_i64
                            {% else %}
                                ::LibC.write(fd.to_i, buf.as(Void*), capped.to_u64).to_i64
                            {% end %}
                        {% end %}
                    when "chr"
                        code = expect_int(arguments, 0, function_name)
                        code.chr
                    when "fsync"
                        fd = expect_int(arguments, 0, function_name)
                        {% if flag?(:windows) %}
                            ::LibC._commit(fd)
                        {% else %}
                            ::LibC.fsync(fd)
                        {% end %}
                    else
                        raise "Unknown C function: #{function_name}"
                    end
                end
            end
        end
    end
end
