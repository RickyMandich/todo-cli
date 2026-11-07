#!/usr/bin/env bash
# Test di todo.sh: usano una HOME temporanea, non toccano i tuoi file reali.
# Uso: bash tests/test_todo.sh

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TODO="$ROOT/todo.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export HOME="$TMP/home"
export TODO_LIST_FILE="$TMP/list"
export TODO_STAMP_FILE="$TMP/stamp"
export NO_COLOR=1
unset TODO_INTERACTIVE TODO_ASSUME_YES
mkdir -p "$HOME"

PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL: %s\n' "$1"; [ -n "${2:-}" ] && printf '      %s\n' "$2"; }

assert_eq() { # nome atteso effettivo
    if [ "$2" = "$3" ]; then pass; else fail "$1" "atteso '$2', ottenuto '$3'"; fi
}
assert_contains() { # nome testo ago
    if [[ "$2" == *"$3"* ]]; then pass; else fail "$1" "manca '$3' in: $2"; fi
}
assert_not_contains() {
    if [[ "$2" != *"$3"* ]]; then pass; else fail "$1" "non doveva contenere '$3'"; fi
}

# run <args...>: esegue todo.sh, imposta OUT e RC (con timeout contro i loop infiniti)
run() { OUT=$(timeout 10 bash "$TODO" "$@" 2>&1); RC=$?; }
# run_in <stdin> <args...>: come run ma con input e modalità interattiva
run_in() {
    local input="$1"; shift
    OUT=$(printf '%s' "$input" | TODO_INTERACTIVE=1 timeout 10 bash "$TODO" "$@" 2>&1); RC=$?
}

# ------------------------------------------------------------- fixture ------
mkdir -p "$TMP/p/alpha" "$TMP/p/beta" "$TMP/p/gamma" "$TMP/p/x/dup" "$TMP/p/y/dup"

# alpha: bullet misti, 2 fatti, 2 da fare, fine riga CRLF
printf '# fatti\r\n- [X] uno\r\n* [x] due\r\n\r\n# da fare\r\n- [ ] tre\r\n  + [ ] quattro\r\n\r\n# note\r\nfine\r\n' > "$TMP/p/alpha/todo.md"
# beta: solo fatti
printf '# fatti\n- [X] a\n\n# da fare\n' > "$TMP/p/beta/todo.md"
# gamma: nessuna sezione, nessun fatto
printf -- '- [ ] g1\n- [ ] g2\n' > "$TMP/p/gamma/todo.md"
printf -- '- [ ] dx\n' > "$TMP/p/x/dup/todo.md"
printf -- '- [ ] dy\n' > "$TMP/p/y/dup/todo.md"

# lista con riga vuota e un file mancante nel mezzo
cat > "$TODO_LIST_FILE" <<EOF
$TMP/p/alpha/todo.md

$TMP/p/beta/todo.md
$TMP/p/missing/todo.md
$TMP/p/gamma/todo.md
EOF

# ---------------------------------------------------------------- stats -----
run stats
assert_eq "stats: exit 0" 0 "$RC"
assert_contains "stats: alpha 2/2" "$OUT" "alpha"
assert_contains "stats: conteggi alpha" "$OUT" "Done: 2 | Todo: 2"
assert_not_contains "stats: niente '00'" "$OUT" "Done: 00"
assert_contains "stats: gamma 0 fatti" "$OUT" "Done: 0 | Todo: 2"
assert_contains "stats: file mancante segnalato" "$OUT" "file non trovato"
assert_contains "stats: beta nascosto" "$OUT" "1 progetti senza pendenti nascosti"
assert_not_contains "stats: beta non elencato" "$OUT" "beta "
assert_contains "stats: totale comprende anche i nascosti" "$OUT" "Done: 3 | Todo: 4"

run stats -a
assert_contains "stats -a: beta visibile" "$OUT" "beta"
run -a
assert_contains "-a diretto: beta visibile" "$OUT" "beta"

run stats --boh
assert_eq "stats: opzione sconosciuta non va in loop (exit 2)" 2 "$RC"
assert_contains "stats: messaggio opzione sconosciuta" "$OUT" "Opzione sconosciuta"

run
assert_contains "senza argomenti = stats" "$OUT" "=== Totale ==="

# ------------------------------------------- indici stabili (riga vuota) ------
# Indici: 1 alpha, 2 beta, 3 missing, 4 gamma
run stats -a
assert_contains "indice alpha = 1" "$OUT" "[1] alpha"
assert_contains "indice beta = 2" "$OUT" "[2] beta"
assert_contains "indice missing = 3" "$OUT" "[3] missing"
assert_contains "indice gamma = 4" "$OUT" "[4] gamma"

OUT=$(TODO_EDITOR="echo EDIT" bash "$TODO" open 4 2>&1)
assert_eq "open 4 apre gamma (non sfalsato dalla riga vuota)" "EDIT $TMP/p/gamma/todo.md" "$OUT"
OUT=$(TODO_EDITOR="echo EDIT" bash "$TODO" open gam 2>&1)
assert_eq "open per nome parziale" "EDIT $TMP/p/gamma/todo.md" "$OUT"
run open 99
assert_eq "open indice fuori range: exit 1" 1 "$RC"
run open nonesiste
assert_eq "open nome inesistente: exit 1" 1 "$RC"
run open
assert_eq "open senza argomenti non interattivo: exit 1" 1 "$RC"

OUT=$(printf '4\n' | TODO_INTERACTIVE=1 TODO_EDITOR="echo EDIT" bash "$TODO" open 2>&1)
assert_contains "open interattivo: scelta da lista" "$OUT" "EDIT $TMP/p/gamma/todo.md"
OUT=$(printf 'q\n' | TODO_INTERACTIVE=1 TODO_EDITOR="echo EDIT" bash "$TODO" open 2>&1)
assert_not_contains "open interattivo: q esce" "$OUT" "EDIT"

# ---------------------------------------------------------------- pending ----
run pending
assert_contains "pending: numerazione 1.1" "$OUT" "1.1  tre"
assert_contains "pending: bullet '+' e indentazione" "$OUT" "1.2  quattro"
assert_contains "pending: gamma 4.1" "$OUT" "4.1  g1"
assert_not_contains "pending: i fatti non compaiono" "$OUT" "uno"
run pending gamma
assert_contains "pending filtrato" "$OUT" "g2"
assert_not_contains "pending filtrato: niente alpha" "$OUT" "tre"

# ------------------------------------------------------------------ done ----
run done 1.1
assert_eq "done: exit 0" 0 "$RC"
assert_contains "done: messaggio" "$OUT" "Fatto: tre"
assert_contains "done: file aggiornato" "$(tr -d '\r' < "$TMP/p/alpha/todo.md")" "- [X] tre"
assert_eq "done: CRLF preservato su tutte le 10 righe" 10 "$(grep -c $'\r' "$TMP/p/alpha/todo.md")"
run done 1.1
assert_contains "done: ora 1.1 è 'quattro'" "$OUT" "Fatto: quattro"
run done 1.1
assert_eq "done: task inesistente exit 1" 1 "$RC"
run done abc
assert_eq "done: sintassi errata exit 2" 2 "$RC"
run done 1.0
assert_eq "done: task 0 non valido" 1 "$RC"

# ------------------------------------------------------------------- new ----
printf '# fatti\n- [X] a\n\n# da fare\n- [ ] primo\n\n# altro\nnota\n' > "$TMP/p/beta/todo.md"
run new -p beta secondo task
assert_eq "new -p: exit 0" 0 "$RC"
EXPECTED=$'# fatti\n- [X] a\n\n# da fare\n- [ ] primo\n- [ ] secondo task\n\n# altro\nnota'
assert_eq "new: inserito in fondo a '# da fare'" "$EXPECTED" "$(cat "$TMP/p/beta/todo.md")"

run new -p gamma senza sezione
assert_eq "new: file senza sezione, append in coda" "$(printf -- '- [ ] g1\n- [ ] g2\n- [ ] senza sezione')" "$(cat "$TMP/p/gamma/todo.md")"

printf '# da fare\n' > "$TMP/p/x/dup/todo.md"
run new -p 1 voce
assert_contains "new -p con indice" "$(cat "$TMP/p/alpha/todo.md")" "- [ ] voce"

OUT=$(cd "$TMP/p/gamma" && bash "$TODO" new dalla cartella 2>&1)
assert_contains "new: usa il progetto della cartella corrente" "$(cat "$TMP/p/gamma/todo.md")" "- [ ] dalla cartella"

OUT=$(cd "$TMP" && bash "$TODO" new fuori 2>&1); RC=$?
assert_eq "new fuori da un progetto: exit 1" 1 "$RC"
run new
assert_eq "new senza testo: exit 2" 2 "$RC"

# progetto non in lista ma con todo.md nella cartella (risalita)
mkdir -p "$TMP/q/sub/deep"; printf '# da fare\n' > "$TMP/q/todo.md"
OUT=$(cd "$TMP/q/sub/deep" && bash "$TODO" new risalita 2>&1)
assert_contains "new: trova todo.md risalendo le cartelle" "$(cat "$TMP/q/todo.md")" "- [ ] risalita"

# ------------------------------------------------------------------ here ----
OUT=$(cd "$TMP/p/gamma" && TODO_EDITOR="echo EDIT" bash "$TODO" here 2>&1)
assert_eq "here: apre il todo del progetto" "EDIT $TMP/p/gamma/todo.md" "$OUT"
mkdir -p "$TMP/p/gamma/sottocartella"
OUT=$(cd "$TMP/p/gamma/sottocartella" && TODO_EDITOR="echo EDIT" bash "$TODO" here 2>&1)
assert_eq "here: da sottocartella" "EDIT $TMP/p/gamma/todo.md" "$OUT"
OUT=$(cd "$TMP" && bash "$TODO" here 2>&1); RC=$?
assert_eq "here: fuori da un progetto exit 1" 1 "$RC"

# ------------------------------------------------------------------- add ----
run add "$TMP/p/nuovo/todo.md"
assert_eq "add: file inesistente senza conferma -> exit 1" 1 "$RC"
OUT=$(TODO_ASSUME_YES=1 bash "$TODO" add "$TMP/p/nuovo/todo.md" 2>&1)
assert_contains "add: crea il file" "$(cat "$TMP/p/nuovo/todo.md")" "# da fare"
assert_contains "add: aggiunto alla lista" "$(cat "$TODO_LIST_FILE")" "$TMP/p/nuovo/todo.md"
run add "$TMP/p/nuovo/todo.md"
assert_contains "add: duplicato segnalato" "$OUT" "Già in lista"
assert_eq "add: nessun duplicato in lista" 1 "$(grep -cF "$TMP/p/nuovo/todo.md" "$TODO_LIST_FILE")"

# percorso relativo con cartella inesistente: deve diventare assoluto corretto
OUT=$(cd "$TMP" && TODO_ASSUME_YES=1 bash "$TODO" add ./rel/dir/todo.md 2>&1)
assert_contains "add: relativo + cartella nuova" "$(cat "$TODO_LIST_FILE")" "$TMP/rel/dir/todo.md"
assert_eq "add: file relativo creato" yes "$([ -f "$TMP/rel/dir/todo.md" ] && echo yes || echo no)"

# -------------------------------------------------------------------- rm ----
BEFORE=$(wc -l < "$TODO_LIST_FILE")
run rm "$TMP/rel/dir/todo.md"
assert_eq "rm per path" 0 "$RC"
assert_not_contains "rm: rimosso" "$(cat "$TODO_LIST_FILE")" "rel/dir"
run rm 99
assert_eq "rm indice non valido: exit 1" 1 "$RC"
run rm
assert_eq "rm senza argomenti: exit 2" 2 "$RC"
run rm 3
assert_contains "rm per indice rimuove 'missing' (3)" "$OUT" "missing"
run stats -a
assert_not_contains "rm: missing sparito dalla lista" "$OUT" "missing"
assert_contains "rm: file originale intatto" "$(cat "$TMP/p/alpha/todo.md")" "# fatti"

# ----------------------------------------------------------------- check ----
printf '%s\n%s\n%s\n' "$TMP/p/alpha/todo.md" "$TMP/p/alpha/todo.md" "$TMP/p/zzz/todo.md" > "$TODO_LIST_FILE"
run check
assert_eq "check: problemi -> exit 1" 1 "$RC"
assert_contains "check: duplicato" "$OUT" "duplicato"
assert_contains "check: mancante" "$OUT" "non trovato"
printf '%s\n%s\n' "$TMP/p/alpha/todo.md" "$TMP/p/beta/todo.md" > "$TODO_LIST_FILE"
run check
assert_eq "check: lista pulita -> exit 0" 0 "$RC"

# ------------------------------------------------- nomi duplicati ------------
printf '%s\n%s\n' "$TMP/p/x/dup/todo.md" "$TMP/p/y/dup/todo.md" > "$TODO_LIST_FILE"
printf -- '- [ ] dx\n' > "$TMP/p/x/dup/todo.md"
run stats -a
assert_contains "nomi uguali disambiguati (x/dup)" "$OUT" "x/dup"
assert_contains "nomi uguali disambiguati (y/dup)" "$OUT" "y/dup"

# ------------------------------------------------------------------ auto ----
printf '%s\n' "$TMP/p/gamma/todo.md" > "$TODO_LIST_FILE"
rm -f "$TODO_STAMP_FILE"
run auto
assert_eq "auto non interattivo: exit 0" 0 "$RC"
assert_eq "auto non interattivo: nessun output" "" "$OUT"
assert_eq "auto non interattivo: non scrive lo stamp" no "$([ -f "$TODO_STAMP_FILE" ] && echo yes || echo no)"

run_in $'\n' auto
assert_contains "auto interattivo: mostra il riepilogo" "$OUT" "Todo:"
assert_eq "auto: scrive lo stamp" yes "$([ -f "$TODO_STAMP_FILE" ] && echo yes || echo no)"
run_in $'\n' auto
assert_eq "auto: entro l'intervallo non mostra nulla" "" "$OUT"
date +%s -d '2 hours ago' > "$TODO_STAMP_FILE"
OUT=$(printf 'gamma\n' | TODO_INTERACTIVE=1 TODO_EDITOR="echo EDIT" bash "$TODO" auto 2>&1)
assert_contains "auto: apre il progetto scelto" "$OUT" "EDIT $TMP/p/gamma/todo.md"

# senza pendenti: nessun output ma stamp aggiornato
printf -- '- [X] fatto\n' > "$TMP/p/gamma/todo.md"
date +%s -d '2 hours ago' > "$TODO_STAMP_FILE"
run_in $'\n' auto
assert_eq "auto senza pendenti: silenzioso" "" "$OUT"

# ----------------------------------------------------------------- varie ----
run help
assert_contains "help" "$OUT" "Uso: todo"
run --version
assert_contains "version" "$OUT" "todo "
run comandoinesistente
assert_eq "comando sconosciuto: exit 1" 1 "$RC"

: > "$TODO_LIST_FILE"
run stats
assert_eq "lista vuota: exit 1" 1 "$RC"
rm -f "$TODO_LIST_FILE"
run stats
assert_eq "lista assente: exit 1" 1 "$RC"

printf '\nRisultato: %d ok, %d falliti\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
