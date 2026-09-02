#!/usr/bin/env bash
#
# Startup & Lexer Benchmark
#

set -uo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/../lib/paths.sh"
cd "$DS_ROOT"
ds_require_binary

# Seconds allowed for one stage1 cold start. Measured ~2.0s 
# after lexer fix; 5s leaves room for slower CI hardware 
# while still catching a return to previous 16.5s.
startup_budget=5

# How much slower a unicode file may lex than its ASCII 
# variant before we call it a regression. They are within 
# noise of each other; previously made it 164x.
utf8_ratio_budget=3

report_only=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --report) report_only=true; shift ;;
        --startup-budget) startup_budget="$2"; shift 2 ;;
        --utf8-ratio-budget) utf8_ratio_budget="$2"; shift 2 ;;
        -h|--help) sed -n '2,22p' "${BASH_SOURCE[0]}"; exit 0 ;;
        *) echo "Unknown argument: $1" >&2; exit 2 ;;
    esac
done

work="$DS_ROOT/.cache/benchmark"
mkdir -p "$work"

# Fixture: 
# N lines of code. The utf8 variant is identical except for
# one leading comment holding a unicode, which is enough to 
# make the whole string non-ascii_only?
make_fixture() {
    local path="$1" lines="$2" nonascii="$3"
    {
        [[ "$nonascii" == "yes" ]] && printf '# note \xe2\x80\x94 em-dash and arrow \xe2\x86\x92\n'
        local i=0

        while [[ $i -lt $lines ]]; do
            printf 'let value_%d = %d + %d # comment %d\n' "$i" "$i" "$((i * 2))" "$i"
            i=$((i + 1))
        done
    } > "$path"
}

# Milliseconds for one command run.
time_ms() {
    local start end
    start=$(date +%s%N)
    "$@" > /dev/null 2>&1
    end=$(date +%s%N)
    echo $(( (end - start) / 1000000 ))
}

# Best of N, for scheduler noise.
best_of() {
    local runs="$1"; shift
    local best="" t i=0

    while [[ $i -lt $runs ]]; do
        t=$(time_ms "$@")
        if [[ -z "$best" || $t -lt $best ]]; then best=$t; fi
        i=$((i + 1))
    done
    echo "$best"
}

status=0

echo "------------------------------------------------------------"
echo "Dragonstone Startup & Lexer Benchmark"
echo "------------------------------------------------------------"

# Part One:
# Stage1 Cold Start
entry="$work/noop.ds"
printf 'echo "ready"\n' > "$entry"

# The same backend that the bootstrap spec uses, this 
# exists for the iteration loop, so it has to measure 
# what the loop actually does. The budget was set for 
# the interpreter, for the VM it differs as there is 
# more room to work with, the number to watch for is
# if there are any regressions against the previous.
startup_ms=$(best_of 3 "$DS_EXE" run $DS_STAGE1_FLAGS "$DS_MAIN" run "$entry")
startup_s=$(awk "BEGIN { printf \"%.2f\", $startup_ms / 1000 }")
budget_ms=$((startup_budget * 1000))

printf '\nStage1 Cold Start: %sms (%ss)  budget %ss\n' "$startup_ms" "$startup_s" "$startup_budget"
if [[ $startup_ms -gt $budget_ms ]]; then
    echo "  REGRESSION: Stage1 Cold Start exceeds ${startup_budget}s budget."
    echo "  This is the number that governs the whole iteration loop."
    echo "  The bootstrap specs pay it once per file, twice per stage."
    status=1
else
    echo "  OK"
fi

# Part Two:
# Non-ASCII Lexer Parity
echo ""
echo "Stage0 Lexer, ASCII vs Unicode:"
printf '  %-8s %-12s %-12s %s\n' "lines" "ascii" "utf8" "ratio"

for n in 1000 4000; do
    make_fixture "$work/ascii_$n.ds" "$n" no
    make_fixture "$work/utf8_$n.ds"  "$n" yes

    a=$(best_of 3 "$DS_EXE" lex "$work/ascii_$n.ds")
    u=$(best_of 3 "$DS_EXE" lex "$work/utf8_$n.ds")

    [[ $a -lt 1 ]] && a=1
    ratio=$(awk "BEGIN { printf \"%.2f\", $u / $a }")
    printf '  %-8s %-12s %-12s %sx\n' "$n" "${a}ms" "${u}ms" "$ratio"

    over=$(awk "BEGIN { print ($u / $a > $utf8_ratio_budget) ? 1 : 0 }")
    if [[ "$over" == "1" ]]; then
        echo "  REGRESSION: Non-ASCII lexing is ${ratio}x slower than ASCII (budget ${utf8_ratio_budget}x)."
        echo "  The O(n^2) String#[] path is back; see Lexer#initialize."
        status=1
    fi
done

echo ""
echo "------------------------------------------------------------"
if [[ "$report_only" == "true" ]]; then
    echo "Report-Only: not failing on regressions"
    exit 0
fi

if [[ $status -eq 0 ]]; then
    echo "PASS within budget"
else
    echo "FAIL outside budget: see regressions above"
fi
exit "$status"
