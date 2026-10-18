#!/usr/bin/env bash
# test.sh — test suite for id-textnorm. No dependencies, no network.
set -uo pipefail
cd "$(dirname "$0")"
BIN="$PWD/bin/id-textnorm"

pass=0; fail=0
ok()    { pass=$((pass+1)); printf 'ok   %s\n' "$1"; }
notok() { fail=$((fail+1)); printf 'FAIL %s\n  expected: %s\n  got:      %s\n' "$1" "$2" "$3"; }

# --- source the script for unit tests (main guard prevents execution) ---
# shellcheck disable=SC1090
source "$BIN"

# unit: normalize one line in both-modes, compare result
t() { # t NAME INPUT EXPECTED
  local name=$1 input=$2 expected=$3
  MODE="both"; JSON_OUT=0
  normalize_line "$input"
  if [ "$L" = "$expected" ]; then ok "$name"; else notok "$name" "$expected" "$L"; fi
}

# unit with explicit mode
tm() { # tm NAME MODE INPUT EXPECTED
  local name=$1; MODE=$2; local input=$3 expected=$4
  JSON_OUT=0
  normalize_line "$input"
  if [ "$L" = "$expected" ]; then ok "$name"; else notok "$name" "$expected" "$L"; fi
}

# --- dates: month names ---
t "date: full month name"            "Rapat 18 Oktober 2026 di Jakarta" "Rapat 2026-10-18 di Jakarta"
t "date: abbrev uppercase"           "deadline 5 AGU 2026 ya"             "deadline 2026-08-05 ya"
t "date: day name preserved"         "Senin, 18 Oktober 2026"            "Senin, 2026-10-18"
t "date: comma after month"          "dibayar 2 Januari, 2026 lunas"     "dibayar 2026-01-02 lunas"
t "date: multiple dates one line"    "dari 1 Jan 2026 sampai 31 Des 2026" "dari 2026-01-01 sampai 2026-12-31"
t "date: sept spelling"              "rilis 9 September 2026"            "rilis 2026-09-09"

# --- dates: numeric DD/MM/YYYY ---
t "date: dd/mm/yyyy"                 "log 18/10/2026 error"              "log 2026-10-18 error"
t "date: dd-mm-yyyy single digits"   "mulai 1-2-2026"                    "mulai 2026-02-01"

# --- dates: validation & passthrough ---
t "date: invalid 30 Feb kept"        "acara 30 Februari 2026 batal"      "acara 30 Februari 2026 batal"
t "date: invalid 32/01 kept"         "x 32/01/2026 y"                    "x 32/01/2026 y"
t "date: invalid month 13 kept"      "x 10/13/2026 y"                    "x 10/13/2026 y"
t "date: leap 29/02/2024 ok"         "29/02/2024 kabisat"                 "2024-02-29 kabisat"
t "date: non-leap 29/02/2026 kept"   "29/02/2026 salah"                  "29/02/2026 salah"
t "date: already ISO untouched"      "pada 2026-10-18"                   "pada 2026-10-18"
t "date: no year untouched"          "tiap 18 Oktober"                   "tiap 18 Oktober"

# --- numbers: thousands & decimals ---
t "num: thousands dots"              "total 1.234.567 rupiah"            "total 1234567 rupiah"
t "num: thousands+decimal comma"     "harga 1.234.567,89 nett"          "harga 1234567.89 nett"
t "num: decimal comma"               "suhu 36,6 derajat"                 "suhu 36.6 derajat"
t "num: negative decimal"            "rugi -3,5 persen"                  "rugi -3.5 persen"
t "num: ip untouched"                "host 192.168.1.1 down"             "host 192.168.1.1 down"
t "num: version untouched"           "rilis v1.2.3"                      "rilis v1.2.3"
t "num: dot decimal untouched"       "pi 3.14"                           "pi 3.14"
t "num: rupiah prefix"               "bayar Rp 1.234.567 tunai"          "bayar Rp 1234567 tunai"
t "num: english commas untouched"    "pop 1,234,567"                     "pop 1,234,567"

# --- numbers: magnitude words ---
t "num: juta"                        "naik 2,5 juta"                     "naik 2500000"
t "num: ribu"                        "100 ribu peserta"                  "100000 peserta"
t "num: miliar"                      "utang 3 miliar"                    "utang 3000000000"
t "num: triliun"                     "APBN 1,2 triliun"                  "APBN 1200000000000"
t "num: magnitude uppercase"         "dana 5 JUTA rupiah"                "dana 5000000 rupiah"
t "num: magnitude fractional"        "bunga 1,25 juta"                   "bunga 1250000"
t "num: miliarder not matched"       "para miliarder hadir"              "para miliarder hadir"

# --- modes ---
tm "mode: dates-only keeps numbers"  "dates"   "1.234,5 pada 18/10/2026" "1.234,5 pada 2026-10-18"
tm "mode: numbers-only keeps dates"  "numbers" "1.234,5 pada 18 Oktober 2026" "1234.5 pada 18 Oktober 2026"

# --- counters in JSON mode ---
MODE="both"; JSON_OUT=0
normalize_line "18 Oktober 2026 seharga 2,5 juta"
if [ "$NDATES" = "1" ] && [ "$NNUMBERS" = "1" ]; then
  ok "counters: 1 date + 1 number"
else
  notok "counters: 1 date + 1 number" "1/1" "$NDATES/$NNUMBERS"
fi

# --- e2e: real process, piped input ---
got=$(printf 'Laporan 18 Oktober 2026: omzet Rp 12.500.000, naik 2,5 juta.\n' | "$BIN")
if [ "$got" = "Laporan 2026-10-18: omzet Rp 12500000, naik 2500000." ]; then
  ok "e2e: pipe through binary"
else
  notok "e2e: pipe through binary" \
    "Laporan 2026-10-18: omzet Rp 12500000, naik 2500000." "$got"
fi

# --- e2e: --json shape ---
got=$(printf 'a 1,5 b\n' | "$BIN" --json)
if [ "$got" = '{"line":1,"input":"a 1,5 b","output":"a 1.5 b","dates":0,"numbers":1}' ]; then
  ok "e2e: --json object"
else
  notok "e2e: --json object" \
    '{"line":1,"input":"a 1,5 b","output":"a 1.5 b","dates":0,"numbers":1}' "$got"
fi

# --- e2e: --json escapes quotes ---
got=$(printf 'kata "18/10/2026" ok\n' | "$BIN" --json)
if [ "$got" = '{"line":1,"input":"kata \"18/10/2026\" ok","output":"kata \"2026-10-18\" ok","dates":1,"numbers":0}' ]; then
  ok "e2e: --json escapes quotes"
else
  notok "e2e: --json escapes quotes" '{...escaped...}' "$got"
fi

# --- e2e: empty input ---
got=$(printf '' | "$BIN"); rc=$?
if [ -z "$got" ] && [ "$rc" = "0" ]; then ok "e2e: empty input -> empty, exit 0";
else notok "e2e: empty input -> empty, exit 0" "empty/0" "$got/$rc"; fi

# --- e2e: missing trailing newline still processed ---
got=$(printf 'tgl 18/10/2026' | "$BIN"); rc=$?
if [ "$got" = "tgl 2026-10-18" ] && [ "$rc" = "0" ]; then ok "e2e: no trailing newline";
else notok "e2e: no trailing newline" "tgl 2026-10-18/0" "$got/$rc"; fi

# --- e2e: file argument ---
tmpf=$(mktemp)
printf 'bayar 3,5 juta tgl 1 Jan 2026\n' > "$tmpf"
got=$("$BIN" "$tmpf"); rc=$?
rm -f "$tmpf"
if [ "$got" = "bayar 3500000 tgl 2026-01-01" ] && [ "$rc" = "0" ]; then ok "e2e: file argument";
else notok "e2e: file argument" "bayar 3500000 tgl 2026-01-01/0" "$got/$rc"; fi

# --- e2e: missing file -> exit 1, message on stderr ---
got=$("$BIN" /tidak/ada/file.txt 2>&1); rc=$?
if [ "$rc" = "1" ] && [ -n "$got" ]; then ok "e2e: missing file exit 1";
else notok "e2e: missing file exit 1" "rc=1 + message" "rc=$rc got=$got"; fi

# --- e2e: bad flag -> exit 2 ---
"$BIN" --bogus >/dev/null 2>&1; rc=$?
if [ "$rc" = "2" ]; then ok "e2e: bad flag exit 2";
else notok "e2e: bad flag exit 2" "2" "$rc"; fi

# --- e2e: --help / --version ---
if "$BIN" --help | grep -q "Usage: id-textnorm"; then ok "e2e: --help"; else notok "e2e: --help" "Usage line" "-"; fi
if [ "$("$BIN" --version)" = "id-textnorm 1.0.0" ]; then ok "e2e: --version"; else notok "e2e: --version" "id-textnorm 1.0.0" "$("$BIN" --version)"; fi

# --- e2e: --json escapes C0 control chars (ESC from colored logs) ---
got=$(printf '\x1b[31m18/10/2026\x1b[0m\n' | "$BIN" --json)
exp=$'{"line":1,"input":"\\u001b[31m18/10/2026\\u001b[0m","output":"\\u001b[31m2026-10-18\\u001b[0m","dates":1,"numbers":0}'
if [ "$got" = "$exp" ]; then
  ok "e2e: --json escapes ESC as \\u001b"
else
  notok "e2e: --json escapes ESC as \\u001b" "$exp" "$got"
fi
if printf '%s' "$got" | python3 -c 'import json,sys; json.loads(sys.stdin.read())' 2>/dev/null; then
  ok "e2e: --json output is valid JSON"
else
  notok "e2e: --json output is valid JSON" "parseable" "$got"
fi

# --- e2e: unreadable file -> exit 1 ---
tmpf=$(mktemp); printf 'x\n' > "$tmpf"; chmod 000 "$tmpf"
"$BIN" "$tmpf" >/dev/null 2>&1; rc=$?
chmod 644 "$tmpf"; rm -f "$tmpf"
if [ "$(id -u)" = "0" ]; then
  ok "e2e: unreadable file exit 1 (skipped as root)"
elif [ "$rc" = "1" ]; then
  ok "e2e: unreadable file exit 1"
else
  notok "e2e: unreadable file exit 1" "1" "$rc"
fi

# --- e2e: streaming — 30k lines in one pass, correct count + tail, sane time ---
big=$(mktemp); out=$(mktemp)
for i in $(seq 1 30000); do printf 'baris %d: tgl 18/10/2026 nominal 1.234,5\n' "$i"; done > "$big"
start=$(date +%s)
"$BIN" < "$big" > "$out"
rc=$?
dur=$(( $(date +%s) - start ))
n=$(wc -l < "$out")
last=$(tail -1 "$out")
rm -f "$big" "$out"
if [ "$rc" = "0" ] && [ "$n" = "30000" ] && [ "$last" = "baris 30000: tgl 2026-10-18 nominal 1234.5" ] && [ "$dur" -lt 120 ]; then
  ok "e2e: streaming 30k lines (${dur}s)"
else
  notok "e2e: streaming 30k lines" "rc=0, 30000 lines, correct tail, <120s" "rc=$rc n=$n dur=${dur}s tail=$last"
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
