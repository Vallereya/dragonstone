require "../ir/program"
require "../../backend_mode"
require "../../core/vm/bytecode"
require "../../native/runtime/values"

module Dragonstone
    module Runtime
        class ConstantBytecodeBinding
            getter value : Bytecode::Value

            def initialize(@value : Bytecode::Value)
            end
        end

        alias ExportValue = ScopeValue | Bytecode::Value | ConstantBytecodeBinding

        # Buffers output produced by a backend attempt that may later be discarded.
        #
        # The engine tries backends in sequence and restarts the program from the
        # beginning for each attempt. If one backend fails after producing output, that
        # output must not be written to the final destination; otherwise it would be
        # duplicated when a later backend succeeds.
        #
        # This sink stores each attempt's output until the engine knows that attempt
        # should be committed. Failed or abandoned attempts are never flushed, so their
        # partial output is discarded.
        #
        # `quit` requires special handling because it exits the process immediately.
        # If output were stored only in `IO::Memory`, the process would exit before the
        # buffer could be committed, losing everything printed so far.
        #
        # Both `quit` and `abort` flush this sink before exiting. Flushing writes the
        # buffered output to the real destination, preserving the program's output for
        # an intentional exit while still discarding output from unsuccessful backend
        # attempts.
        class DeferredIO < IO
            getter target : IO

            def initialize(@target : IO)
                @buffer = IO::Memory.new
            end

            def read(slice : Bytes)
                raise IO::Error.new("DeferredIO is write-only")
            end

            def write(slice : Bytes) : Nil
                @buffer.write(slice)
            end

            def flush : Nil
                text = @buffer.to_s
                return if text.empty?
                @buffer.clear
                @target.print(text)
                @target.flush
            end
        end

        # The destination for program output.
        #
        # Backends write output to this stream as they execute instead of collecting it
        # in a single string. This allows output to stream normally, remain correctly
        # ordered with `stderr`, and survive `quit`, which exits the process
        # immediately.
        #
        # Pass an `IO::Memory` instance when output should be captured instead of
        # written directly.
        #
        # The engine changes this destination for each backend attempt. Any candidate
        # that is not the final attempt writes to a capture buffer, so output produced
        # before a failed attempt is discarded rather than duplicated when a later
        # backend succeeds.
        abstract class Backend
            getter stdout : IO

            def initialize(@stdout : IO)
            end

            def stdout=(io : IO)
                @stdout = io
            end

            abstract def import_variable(name : String, value : ExportValue) : Nil
            abstract def import_constant(name : String, value : ExportValue) : Nil
            abstract def export_namespace : Hash(String, ExportValue)
            abstract def execute(program : IR::Program) : Nil
            abstract def backend_mode : BackendMode
        end

        class Unit
            getter path : String
            getter backend : Backend
            getter exports : Hash(String, ExportValue)

            def initialize(@path : String, @backend : Backend)
                @exports = {} of String => ExportValue
            end

            def bind(name : String, value : ExportValue)
                @backend.import_variable(name, value)
            end

            def bind_namespace(namespace : Hash(String, ExportValue))
                namespace.each do |name, scope_value|
                    bind_scope_value(name, scope_value)
                end
            end

            def exported_lookup(name : String) : ExportValue?
                if value = @exports[name]?
                    case value
                    when ConstantBinding
                        value.value
                    when ConstantBytecodeBinding
                        value.value
                    else
                        value
                    end
                end
            end

            def default_namespace : Hash(String, ExportValue)
                @exports
            end

            def capture_exports!
                @exports = @backend.export_namespace
            end

            def execute(program : IR::Program) : Nil
                @backend.execute(program)
            end

            private def bind_scope_value(name : String, value : ExportValue)
                case value
                when ConstantBinding
                    @backend.import_constant(name, value.value)
                when ConstantBytecodeBinding
                    @backend.import_constant(name, value.value)
                else
                    @backend.import_variable(name, value)
                end
            end
        end
    end
end
