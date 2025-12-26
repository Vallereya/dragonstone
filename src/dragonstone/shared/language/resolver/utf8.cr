# ---------------------------------
# ---------- UTF-8 Checks ---------
# ---------------------------------

module Dragonstone
    module Encoding
        module UTF8
            extend self

            private UNROLL = 64

            # Returns whether *bytes* are valid UTF-8.
            #
            # This is a tight DFA-based validator adapted from Crystal's `Unicode.valid?`,
            # kept here so the resolver/reader can validate input without relying on
            # Crystal's stdlib `Unicode` module.
            def valid?(bytes : Bytes) : Bool
                state = 0_u64
                table = UTF8_ENCODING_DFA.to_unsafe
                s = bytes.to_unsafe
                e = s + bytes.size

                while s + UNROLL <= e
                    {% for i in 0...UNROLL %}
                        state = table[s[{{ i }}]].unsafe_shr(state & 0x3F)
                    {% end %}
                    return false if state & 0x3F == 6
                    s += UNROLL
                end

                while s < e
                    state = table[s.value].unsafe_shr(state & 0x3F)
                    return false if state & 0x3F == 6
                    s += 1
                end

                state & 0x3F == 0
            end

            private UTF8_ENCODING_DFA = begin
                x = Array(UInt64).new(256)

                {% for ch in 0x00..0x7F %} put1(x, dfa_state(0, 1, 1, 1, 1, 1, 1, 1, 1)); {% end %}
                {% for ch in 0x80..0x8F %} put1(x, dfa_state(1, 1, 0, 2, 1, 2, 1, 3, 3)); {% end %}
                {% for ch in 0x90..0x9F %} put1(x, dfa_state(1, 1, 0, 2, 1, 2, 3, 3, 1)); {% end %}
                {% for ch in 0xA0..0xBF %} put1(x, dfa_state(1, 1, 0, 2, 2, 1, 3, 3, 1)); {% end %}
                {% for ch in 0xC0..0xC1 %} put1(x, dfa_state(1, 1, 1, 1, 1, 1, 1, 1, 1)); {% end %}
                {% for ch in 0xC2..0xDF %} put1(x, dfa_state(2, 1, 1, 1, 1, 1, 1, 1, 1)); {% end %}
                {% for ch in 0xE0..0xE0 %} put1(x, dfa_state(4, 1, 1, 1, 1, 1, 1, 1, 1)); {% end %}
                {% for ch in 0xE1..0xEC %} put1(x, dfa_state(3, 1, 1, 1, 1, 1, 1, 1, 1)); {% end %}
                {% for ch in 0xED..0xED %} put1(x, dfa_state(5, 1, 1, 1, 1, 1, 1, 1, 1)); {% end %}
                {% for ch in 0xEE..0xEF %} put1(x, dfa_state(3, 1, 1, 1, 1, 1, 1, 1, 1)); {% end %}
                {% for ch in 0xF0..0xF0 %} put1(x, dfa_state(6, 1, 1, 1, 1, 1, 1, 1, 1)); {% end %}
                {% for ch in 0xF1..0xF3 %} put1(x, dfa_state(7, 1, 1, 1, 1, 1, 1, 1, 1)); {% end %}
                {% for ch in 0xF4..0xF4 %} put1(x, dfa_state(8, 1, 1, 1, 1, 1, 1, 1, 1)); {% end %}
                {% for ch in 0xF5..0xFF %} put1(x, dfa_state(1, 1, 1, 1, 1, 1, 1, 1, 1)); {% end %}

                x
            end

            private def self.put1(array : Array, value) : Nil
                array << value
            end

            private macro dfa_state(*transitions)
                {% x = 0_u64 %}
                {% for tr, i in transitions %}
                    {% x |= (1_u64 << (i * 6)) * tr * 6 %}
                {% end %}
                {{ x }}
            end
        end
    end
end

