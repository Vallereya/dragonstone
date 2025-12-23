# ---------------------------------
# -------- Unicode XID Data -------
# ---------------------------------

module Dragonstone
    # Minimal Unicode identifier support for the stage0 (Crystal) implementation.
    #
    # This parses `DerivedCoreProperties.txt` (checked into the repo) at program
    # startup and exposes `xid_start?` / `xid_continue?` for lexer identifier
    # rules. Emoji identifiers are intentionally omitted for now.
    module UnicodeXID
        extend self

        private RELATIVE_DERIVED_CORE_PROPERTIES = "src/dragonstone/stdlib/modules/shared/unicode/proc/UCD/DerivedCoreProperties.txt"

        @@xid_start_ranges : Array(Tuple(Int32, Int32))?
        @@xid_continue_ranges : Array(Tuple(Int32, Int32))?
        @@warned_missing = false

        def xid_start?(codepoint : Int32) : Bool
            ensure_loaded
            range_in?(@@xid_start_ranges.not_nil!, codepoint)
        end

        def xid_continue?(codepoint : Int32) : Bool
            ensure_loaded
            range_in?(@@xid_continue_ranges.not_nil!, codepoint)
        end

        private def range_in?(ranges : Array(Tuple(Int32, Int32)), codepoint : Int32) : Bool
            left = 0
            right = ranges.size - 1

            while left <= right
                mid = (left + right) // 2
                low, high = ranges[mid]

                if codepoint < low
                    right = mid - 1
                elsif codepoint > high
                    left = mid + 1
                else
                    return true
                end
            end

            false
        end

        private def ensure_loaded : Nil
            return if @@xid_start_ranges && @@xid_continue_ranges
            start_ranges, continue_ranges = load_xid_ranges
            @@xid_start_ranges = start_ranges
            @@xid_continue_ranges = continue_ranges
        end

        private def load_xid_ranges : Tuple(Array(Tuple(Int32, Int32)), Array(Tuple(Int32, Int32)))
            start_ranges = [] of Tuple(Int32, Int32)
            continue_ranges = [] of Tuple(Int32, Int32)

            path = derived_core_properties_path

            begin
                File.each_line(path) do |raw|
                    line = raw.split('#', 2)[0].strip
                    next if line.empty?

                    pieces = line.split(';', 2)
                    next unless pieces.size == 2

                    code_field = pieces[0].strip
                    prop = pieces[1].strip

                    ranges = case prop
                    when "XID_Start"
                        start_ranges
                    when "XID_Continue"
                        continue_ranges
                    else
                        next
                    end

                    if (dots = code_field.index(".."))
                        low = code_field[0, dots].to_i(16)
                        high = code_field[dots + 2, code_field.size - (dots + 2)].to_i(16)
                        ranges << {low, high}
                    else
                        cp = code_field.to_i(16)
                        ranges << {cp, cp}
                    end
                end
            rescue ex : File::NotFoundError
                unless @@warned_missing
                    @@warned_missing = true
                    STDERR.puts "WARNING: Missing #{RELATIVE_DERIVED_CORE_PROPERTIES}; Unicode identifier rules will be ASCII-only."
                end
            end

            start_ranges.sort_by!(&.[0])
            continue_ranges.sort_by!(&.[0])
            {merge_ranges(start_ranges), merge_ranges(continue_ranges)}
        end

        private def merge_ranges(ranges : Array(Tuple(Int32, Int32))) : Array(Tuple(Int32, Int32))
            return ranges if ranges.empty?

            merged = [] of Tuple(Int32, Int32)
            current_low, current_high = ranges[0]

            i = 1
            while i < ranges.size
                low, high = ranges[i]
                if low <= current_high + 1
                    current_high = high if high > current_high
                else
                    merged << {current_low, current_high}
                    current_low = low
                    current_high = high
                end
                i += 1
            end

            merged << {current_low, current_high}
            merged
        end

        private def derived_core_properties_path : String
            candidates = [] of String

            if explicit = ENV["DRAGONSTONE_UCD_DERIVED_CORE_PROPERTIES"]?
                candidates << explicit
            end

            if root = ENV["DRAGONSTONE_ROOT"]?
                candidates << File.join(root, RELATIVE_DERIVED_CORE_PROPERTIES)
            end

            candidates << File.join(Dir.current, RELATIVE_DERIVED_CORE_PROPERTIES)

            if exe = Process.executable_path
                exe_dir = File.dirname(exe)
                candidates << File.join(exe_dir, RELATIVE_DERIVED_CORE_PROPERTIES)
                candidates << File.expand_path(File.join(exe_dir, "..", RELATIVE_DERIVED_CORE_PROPERTIES))
            end

            candidates.each do |path|
                return path if File.exists?(path)
            end

            # Fall back to relative path (will be handled by `load_xid_ranges`).
            RELATIVE_DERIVED_CORE_PROPERTIES
        end
    end
end
