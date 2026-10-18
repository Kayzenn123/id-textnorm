# id-textnorm

> Normalize Indonesian-format dates and numbers in a text stream. Daily Tools #12.

## Why

Indonesian data is messy in a specifically Indonesian way: scraped marketplace
listings write "Rp 1.250.000,50", bank statements say "2,5 juta", news articles
write "18 Oktober 2026" and server logs from local apps stamp "18/10/2026".
Before any of that can be analyzed, sorted, or loaded into a spreadsheet, the
dates and numbers have to be normalized — usually with a throwaway Python
script that loads everything into memory, or with `date`/regex one-liners that
only handle one format each.

`id-textnorm` does it in one streaming pass, with zero dependencies: pipe text
in, get the same text back with dates as ISO `YYYY-MM-DD` and numbers as
machine format. Unlike generic parsers (Python `dateparser`, GNU `date -d`),
it understands the Indonesian locale (month names, `DD/MM/YYYY` convention,
`.` thousands / `,` decimal, `ribu/juta/miliar/triliun`), validates real
calendar dates in pure bash (no GNU `date`, so it also runs on macOS, Termux
and Git Bash), and never holds more than one line in memory.

## Install

```bash
git clone https://github.com/Kayzenn123/id-textnorm.git
cd id-textnorm
# no dependencies — pure bash
```

Requires: Bash 4+ (check with `bash --version`).

Optional: put it on your PATH:

```bash
export PATH="$PWD/bin:$PATH"
```

## Usage

```bash
bin/id-textnorm [OPTIONS] [FILE...]
```

Reads UTF-8 text line by line from stdin (or the given files) and writes the
normalized text to stdout. Use `-` as a file name to read stdin explicitly.

| Flag | Function | Default |
| --- | --- | --- |
| `--dates-only` | only normalize dates | off |
| `--numbers-only` | only normalize numbers | off |
| `--json` | emit one JSON object per input line (`{"line":N,"input":"...","output":"...","dates":D,"numbers":M}`) instead of plain text | off |
| `-h`, `--help` | show help | — |
| `-V`, `--version` | show version | — |

Exit codes: `0` success, `1` runtime error (e.g. file not found), `2` bad usage.

```bash
bin/id-textnorm < laporan.txt
cat data.csv | bin/id-textnorm --numbers-only
bin/id-textnorm --json access.log | jq -r '.output'
```

## Example output

Command:

```bash
bin/id-textnorm < laporan.txt
```

Input (`laporan.txt`):

```text
LAPORAN PENJUALAN TOKO MAJU JAYA
Periode: 1 Oktober 2026 s.d. 18 Oktober 2026

- Omzet kotor: Rp 125.750.000 (naik 12,5% dari September 2026)
- Omzet bersih: Rp 98.400.500
- Piutang: Rp 7.250.000, jatuh tempo 25/10/2026
- Utang supplier: Rp 3,5 juta, dibayar 2 Oktober 2026
- Target tahun: 1,2 miliar (tercapai 78,25%)
- Kas kecil: Rp 500 ribu

Catatan: audit internal dijadwalkan Senin, 2 November 2026.
```

Output (real, copied from an actual run):

```text
LAPORAN PENJUALAN TOKO MAJU JAYA
Periode: 2026-10-01 s.d. 2026-10-18

- Omzet kotor: Rp 125750000 (naik 12.5% dari September 2026)
- Omzet bersih: Rp 98400500
- Piutang: Rp 7250000, jatuh tempo 2026-10-25
- Utang supplier: Rp 3500000, dibayar 2026-10-02
- Target tahun: 1200000000 (tercapai 78.25%)
- Kas kecil: Rp 500000

Catatan: audit internal dijadwalkan Senin, 2026-11-02.
```

Command:

```bash
bin/id-textnorm --json data.csv | head -2
```

Output (real, copied from an actual run):

```text
{"line":1,"input":"nama,tanggal_lahir,saldo,catatan","output":"nama,tanggal_lahir,saldo,catatan","dates":0,"numbers":0}
{"line":2,"input":"Budi Santoso,17 Agustus 1995,\"1.250.000,50\",nasabah prioritas","output":"Budi Santoso,1995-08-17,\"1250000.50\",nasabah prioritas","dates":1,"numbers":1}
```

## How it works

Each input line goes through up to five regex passes, in order:

1. **Month-name dates** — `18 Oktober 2026` (full/abbreviated Indonesian month
   names, any case, optional weekday and comma) → validated against a pure-bash
   calendar (leap-year aware) → `2026-10-18`. Invalid dates such as
   `30 Februari 2026` are left untouched.
2. **Numeric dates** — `18/10/2026`, `18-10-2026` (Indonesian `DD/MM/YYYY`
   convention) → `2026-10-18`. Already-ISO `2026-10-18` never matches.
3. **Magnitude words** — `2,5 juta` → `2500000` (`ribu`/`juta`/`miliar`/`triliun`,
   computed with pure-bash integer arithmetic, 64-bit overflow guarded).
4. **Thousands separators** — `1.234.567,89` → `1234567.89`. The pattern
   requires strict 3-digit groups, so `192.168.1.1`, `v1.2.3` and `3.14` are
   never touched.
5. **Decimal commas** — `3,5` → `3.5`.

Cheap glob pre-checks skip the regex engine for lines that cannot match, and
only one line is ever held in memory, so multi-gigabyte files stream through.
Matches directly wrapped in ANSI color codes (e.g. `\x1b[31m18/10/2026\x1b[0m`)
are still normalized; the color codes are preserved.

Structure:

```text
bin/id-textnorm   # the tool (executable bash, ~360 lines)
test.sh           # test suite, no dependencies
```

## Limitations

- Assumes the Indonesian `DD/MM/YYYY` convention: `10/18/2026` is treated as
  an invalid date and left as-is.
- Two-digit years (`18 Okt 26`) and month+year without a day
  (`September 2026`) are not converted.
- A comma is always the decimal separator (Indonesian convention), so
  English-style `1,234,567` is left untouched.
- A thousands number at the very end of a sentence (`total 1.234.`) is left
  as-is: the trailing dot is excluded from the match boundary to protect
  IPv4 addresses.
- Absurd magnitude values that would overflow 64-bit arithmetic are kept
  verbatim instead of converted.
- `--json` escapes C0 control characters as `\u00XX`; other unusual bytes
  pass through unchanged.
- Throughput is modest (pure bash): ~9.000 lines/s on plain text, ~1.000
  lines/s when every line contains matches (measured on a 4-CPU Linux VM).
  Memory use stays flat regardless of input size.

## Development

```bash
bash test.sh   # 48 tests, no dependencies
```

## License

MIT

---
Ringkasan (Bahasa Indonesia): `id-textnorm` menormalisasi tanggal dan angka
format Indonesia di dalam aliran teks — `18 Oktober 2026` menjadi `2026-10-18`,
`1.234.567,89` menjadi `1234567.89`, `2,5 juta` menjadi `2500000`. Murni bash
tanpa dependensi, membaca stdin atau file baris-per-baris (ramah file besar),
dengan flag `--dates-only`, `--numbers-only`, dan `--json`. Tanggal tidak valid
(`30 Februari 2026`) dan format yang ambigu (IP address, versi `v1.2.3`)
dibiarkan apa adanya. Batasan utama: memakai konvensi `DD/MM/YYYY`, koma selalu
dianggap pemisah desimal, dan throughput sekitar 1.000–9.000 baris/detik.
