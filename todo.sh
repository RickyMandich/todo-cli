#!/usr/bin/env bash
# todo - gestore di più file todo.md sparsi nei progetti.
#
# Va ESEGUITO come programma (non caricato con `source`): così gira sempre in bash,
# qualunque sia la shell interattiva (zsh, oh-my-zsh, p10k...). Vedi README.md.

TODO_VERSION="2.0.0"

TODO_LIST_FILE="${TODO_LIST_FILE:-$HOME/.list_todo}"
TODO_STAMP_FILE="${TODO_STAMP_FILE:-$HOME/.last_todo}"
TODO_INTERVAL="${TODO_INTERVAL:-3600}"
TODO_EDITOR="${TODO_EDITOR:-vim -n}"

# Checkbox riconosciute: "- [X]", "* [x]", "+ [ ]" (anche indentate)
DONE_RE='^[[:space:]]*[-*+][[:space:]]+\[[xX]\]'
OPEN_RE='^[[:space:]]*[-*+][[:space:]]+\[ \]'
STRIP_SED='s/^[[:space:]]*[-*+][[:space:]]+\[[ xX]\][[:space:]]*//'

# ---------------------------------------------------------------- colori ----
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[1;33m'
    BLUE=$'\033[0;34m'; CYAN=$'\033[0;36m'; DIM=$'\033[2m'; NC=$'\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; BLUE=''; CYAN=''; DIM=''; NC=''
fi

err()  { printf '%s%s%s\n' "$RED" "$*" "$NC" >&2; }
warn() { printf '%s%s%s\n' "$YELLOW" "$*" "$NC" >&2; }
ok()   { printf '%s%s%s\n' "$GREEN" "$*" "$NC"; }

# ------------------------------------------------------------- utilità ------
# Terminale interattivo (TODO_INTERACTIVE=1 forza il comportamento, per i test).
interactive() {
    [ "${TODO_INTERACTIVE:-}" = 1 ] || { [ -t 0 ] && [ -t 1 ]; }
}

# Chiede conferma (s/N). TODO_ASSUME_YES=1 risponde sempre sì.
confirm() {
    [ "${TODO_ASSUME_YES:-}" = 1 ] && return 0
    interactive || return 1
    local ans
    read -r -p "$1 [s/N] " ans
    case "${ans,,}" in s|si|sì|y|yes) return 0 ;; *) return 1 ;; esac
}

# Percorso assoluto normalizzato, anche se il file o la cartella non esistono.
abs_path() {
    realpath -m -- "$1" 2>/dev/null || printf '%s\n' "$1"
}

stamp_now() { date +%s > "$TODO_STAMP_FILE"; }

# ------------------------------------------------------------- lista --------
TODO_FILES=()
NAMES=()

# Nome progetto = cartella che contiene il file; se due nomi coincidono si usa
# "cartella-padre/cartella".
compute_names() {
    NAMES=()
    local f d base i
    declare -A seen=()
    for f in "${TODO_FILES[@]}"; do
        d="$(dirname "$f")"
        if [ "$d" = "$HOME" ]; then base="~"; else base="$(basename "$d")"; fi
        NAMES+=("$base")
        seen["$base"]=$(( ${seen["$base"]:-0} + 1 ))
    done
    for i in "${!TODO_FILES[@]}"; do
        if [ "${seen["${NAMES[$i]}"]}" -gt 1 ]; then
            d="$(dirname "${TODO_FILES[$i]}")"
            NAMES[$i]="$(basename "$(dirname "$d")")/$(basename "$d")"
        fi
    done
}

# Legge la lista ignorando le righe vuote: l'indice mostrato (1-based) è sempre
# la posizione in questo array, anche per i file mancanti.
load_list() {
    TODO_FILES=()
    if [ -f "$TODO_LIST_FILE" ]; then
        local line
        while IFS= read -r line || [ -n "$line" ]; do
            line="${line%$'\r'}"
            line="${line#"${line%%[![:space:]]*}"}"
            line="${line%"${line##*[![:space:]]}"}"
            [ -z "$line" ] && continue
            TODO_FILES+=("$line")
        done < "$TODO_LIST_FILE"
    fi
    compute_names
}

save_list() {
    local tmp="$TODO_LIST_FILE.tmp.$$"
    : > "$tmp"
    if [ ${#TODO_FILES[@]} -gt 0 ]; then
        printf '%s\n' "${TODO_FILES[@]}" > "$tmp"
    fi
    mv -f "$tmp" "$TODO_LIST_FILE"
}

# Imposta DONE_N e OPEN_N; ritorna 1 se il file non esiste.
file_counts() {
    DONE_N=0; OPEN_N=0
    [ -f "$1" ] || return 1
    DONE_N=$(tr -d '\r' < "$1" | grep -cE "$DONE_RE" || true)
    OPEN_N=$(tr -d '\r' < "$1" | grep -cE "$OPEN_RE" || true)
    DONE_N=${DONE_N:-0}; OPEN_N=${OPEN_N:-0}
    return 0
}

need_list() {
    load_list
    if [ ${#TODO_FILES[@]} -eq 0 ]; then
        warn "Nessun file nella lista ($TODO_LIST_FILE). Usa: todo add <path>"
        return 1
    fi
}

# Stampa una riga di riepilogo per l'elemento $1 (indice 0-based).
print_entry() {
    local i="$1" f="${TODO_FILES[$1]}"
    if file_counts "$f"; then
        printf '%s[%d]%s %s%-22s%s %sDone: %d%s | %sTodo: %d%s\n' \
            "$BLUE" $((i + 1)) "$NC" "$YELLOW" "${NAMES[$i]}" "$NC" \
            "$GREEN" "$DONE_N" "$NC" "$RED" "$OPEN_N" "$NC"
    else
        printf '%s[%d]%s %s%-22s%s %s[!] file non trovato%s\n' \
            "$BLUE" $((i + 1)) "$NC" "$YELLOW" "${NAMES[$i]}" "$NC" "$RED" "$NC"
    fi
}

print_list_numbered() {
    local i
    for i in "${!TODO_FILES[@]}"; do print_entry "$i"; done
}

# Risolve un indice o un nome (anche parziale) in TARGET_IDX (0-based).
resolve_target() {
    local arg="$1" i n lower exact=() matches=() choice
    need_list || return 1

    if [[ "$arg" =~ ^[0-9]+$ ]]; then
        if [ "$arg" -ge 1 ] && [ "$arg" -le ${#TODO_FILES[@]} ]; then
            TARGET_IDX=$((arg - 1)); return 0
        fi
        err "Indice non valido: $arg (valori ammessi: 1-${#TODO_FILES[@]})"
        return 1
    fi

    lower="${arg,,}"
    for i in "${!TODO_FILES[@]}"; do
        n="${NAMES[$i]}"
        [ "${n,,}" = "$lower" ] && exact+=("$i")
        if [[ "${n,,}" == *"$lower"* || "${TODO_FILES[$i],,}" == *"$lower"* ]]; then
            matches+=("$i")
        fi
    done

    if [ ${#exact[@]} -eq 1 ]; then TARGET_IDX="${exact[0]}"; return 0; fi
    case ${#matches[@]} in
        0) err "Nessun progetto corrisponde a: $arg"; return 1 ;;
        1) TARGET_IDX="${matches[0]}"; return 0 ;;
    esac

    if ! interactive; then
        err "Più progetti corrispondono a '$arg': usa l'indice."
        for i in "${matches[@]}"; do print_entry "$i" >&2; done
        return 1
    fi
    warn "Più progetti corrispondono a '$arg':"
    for i in "${matches[@]}"; do print_entry "$i"; done
    read -r -p "Numero: " choice
    for i in "${matches[@]}"; do
        if [ "$choice" = "$((i + 1))" ]; then TARGET_IDX="$i"; return 0; fi
    done
    err "Scelta non valida"
    return 1
}

# Chiede all'utente di scegliere un progetto dalla lista: imposta TARGET_IDX.
pick_project() {
    local choice
    print_list_numbered
    read -r -p "Numero progetto (q per uscire): " choice
    case "$choice" in q|Q|"") return 1 ;; esac
    resolve_target "$choice"
}

# Trova il todo del progetto corrente: imposta HERE_PATH (e HERE_IDX se in lista).
find_here() {
    HERE_PATH=""; HERE_IDX=-1
    load_list
    local i d best=-1 bestlen=0 n cwd="$PWD"
    for i in "${!TODO_FILES[@]}"; do
        d="$(dirname "${TODO_FILES[$i]}")"
        if [ "$cwd" = "$d" ] || [[ "$cwd" == "$d"/* ]]; then
            if [ ${#d} -gt "$bestlen" ]; then best=$i; bestlen=${#d}; fi
        fi
    done
    if [ "$best" -ge 0 ]; then
        HERE_IDX=$best; HERE_PATH="${TODO_FILES[$best]}"; return 0
    fi
    d="$cwd"
    while true; do
        for n in todo.md TODO.md; do
            if [ -f "$d/$n" ]; then HERE_PATH="$d/$n"; return 0; fi
        done
        [ "$d" = "/" ] && break
        d="$(dirname "$d")"
    done
    return 1
}

open_file() {
    local file="$1" ed
    if [ ! -f "$file" ]; then err "File non trovato: $file"; return 1; fi
    stamp_now
    read -ra ed <<< "$TODO_EDITOR"
    "${ed[@]}" "$file"
}

# Inserisce "- [ ] testo" in fondo alla sezione "# da fare" (o in coda al file).
insert_item() {
    local file="$1" text="$2" tmp
    if [ ! -f "$file" ]; then err "File non trovato: $file"; return 1; fi
    tmp="$(mktemp)" || return 1
    TODO_ITEM="- [ ] $text" awk '
        { lines[NR] = $0 }
        END {
            item = ENVIRON["TODO_ITEM"]
            if (NR > 0 && lines[1] ~ /\r$/) item = item "\r"
            insec = 0; found = 0; last = 0
            for (i = 1; i <= NR; i++) {
                l = lines[i]; sub(/\r$/, "", l)
                if (l ~ /^#+/) {
                    if (insec) break
                    h = tolower(l); sub(/^#+[ \t]*/, "", h); sub(/[ \t]+$/, "", h)
                    if (h == "da fare" || h == "todo" || h == "to do") { insec = 1; found = 1; last = i }
                    continue
                }
                if (insec && l !~ /^[ \t]*$/) last = i
            }
            for (i = 1; i <= NR; i++) {
                print lines[i]
                if (found && i == last) print item
            }
            if (!found) print item
        }' "$file" > "$tmp"
    cat "$tmp" > "$file"
    rm -f "$tmp"
}

# ------------------------------------------------------------- comandi ------
cmd_stats() {
    local show_all=0
    while [ $# -gt 0 ]; do
        case "$1" in
            -a|--all) show_all=1 ;;
            *) err "Opzione sconosciuta: $1"; echo "Uso: todo stats [-a|--all]" >&2; return 2 ;;
        esac
        shift
    done
    need_list || return 1

    local i f total_done=0 total_todo=0 hidden=0
    for i in "${!TODO_FILES[@]}"; do
        f="${TODO_FILES[$i]}"
        if ! file_counts "$f"; then print_entry "$i"; continue; fi
        total_done=$((total_done + DONE_N))
        total_todo=$((total_todo + OPEN_N))
        if [ "$show_all" -eq 0 ] && [ "$OPEN_N" -eq 0 ]; then
            hidden=$((hidden + 1)); continue
        fi
        print_entry "$i"
        printf '    %s%s%s\n' "$DIM" "$f" "$NC"
    done
    [ "$hidden" -gt 0 ] && printf '%s(%d progetti senza pendenti nascosti, usa -a per vederli)%s\n' "$DIM" "$hidden" "$NC"
    printf '%s=== Totale ===%s\n' "$CYAN" "$NC"
    printf '%sDone: %d%s | %sTodo: %d%s\n' "$GREEN" "$total_done" "$NC" "$RED" "$total_todo" "$NC"
}

cmd_pending() {
    local only=-1 i f lines line t total=0
    need_list || return 1
    if [ -n "${1:-}" ]; then resolve_target "$1" || return 1; only=$TARGET_IDX; fi

    for i in "${!TODO_FILES[@]}"; do
        if [ "$only" -ge 0 ] && [ "$i" -ne "$only" ]; then continue; fi
        f="${TODO_FILES[$i]}"
        if [ ! -f "$f" ]; then print_entry "$i"; continue; fi
        lines=$(tr -d '\r' < "$f" | grep -E "$OPEN_RE" | sed -E "$STRIP_SED")
        [ -z "$lines" ] && continue
        printf '%s[%d]%s %s%s%s\n' "$BLUE" $((i + 1)) "$NC" "$YELLOW" "${NAMES[$i]}" "$NC"
        t=0
        while IFS= read -r line; do
            t=$((t + 1)); total=$((total + 1))
            printf '  %s%d.%d%s  %s\n' "$CYAN" $((i + 1)) "$t" "$NC" "$line"
        done <<< "$lines"
        echo
    done
    [ "$total" -eq 0 ] && echo "Nessun task pendente."
    return 0
}

cmd_show() {
    local f
    need_list || return 1
    for f in "${TODO_FILES[@]}"; do
        if [ -f "$f" ]; then
            printf '%s# %s%s\n' "$YELLOW" "$f" "$NC"
            tr -d '\r' < "$f"
            echo
        else
            printf '%s[!] File non trovato: %s%s\n\n' "$RED" "$f" "$NC"
        fi
    done
}

cmd_new() {
    local proj="" words=() file text
    while [ $# -gt 0 ]; do
        case "$1" in
            -p|--project)
                shift; proj="${1:-}"
                if [ -z "$proj" ]; then err "-p richiede un progetto (indice o nome)"; return 2; fi ;;
            *) words+=("$1") ;;
        esac
        shift
    done
    text="${words[*]}"
    if [ -z "$text" ]; then err "Uso: todo new [-p progetto] <testo>"; return 2; fi

    if [ -n "$proj" ]; then
        resolve_target "$proj" || return 1
        file="${TODO_FILES[$TARGET_IDX]}"
    elif find_here; then
        file="$HERE_PATH"
    elif interactive && need_list && pick_project; then
        file="${TODO_FILES[$TARGET_IDX]}"
    else
        err "Progetto non determinabile: usa -p <indice|nome> o lancia il comando dentro un progetto."
        return 1
    fi

    insert_item "$file" "$text" || return 1
    ok "Aggiunto a $(basename "$(dirname "$file")"): $text"
}

cmd_done() {
    local ref="${1:-}" p t f ln text
    if ! [[ "$ref" =~ ^([0-9]+)\.([0-9]+)$ ]]; then
        err "Uso: todo done <progetto>.<task>   (i numeri si vedono con: todo pending)"
        return 2
    fi
    p="${BASH_REMATCH[1]}"; t="${BASH_REMATCH[2]}"
    if [ "$t" -lt 1 ]; then err "Numero task non valido: $t"; return 1; fi
    resolve_target "$p" || return 1
    f="${TODO_FILES[$TARGET_IDX]}"
    if [ ! -f "$f" ]; then err "File non trovato: $f"; return 1; fi

    ln=$(tr -d '\r' < "$f" | grep -nE "$OPEN_RE" | sed -n "${t}p" | cut -d: -f1)
    if [ -z "$ln" ]; then err "Il task $ref non esiste"; return 1; fi
    text=$(sed -n "${ln}p" "$f" | tr -d '\r' | sed -E "$STRIP_SED")
    sed -i "${ln}s/\[ \]/[X]/" "$f"
    ok "Fatto: $text  (${NAMES[$TARGET_IDX]})"
}

cmd_open() {
    local arg="${1:-}" choice
    need_list || return 1
    if [ -z "$arg" ]; then
        if ! interactive; then
            err "todo open: serve un indice o un nome (terminale non interattivo)"
            return 1
        fi
        pick_project || return 0
    else
        resolve_target "$arg" || return 1
    fi
    open_file "${TODO_FILES[$TARGET_IDX]}"
}

cmd_here() {
    if ! find_here; then
        err "Nessun todo.md trovato da qui in su. Crealo e registralo con: todo add ./todo.md"
        return 1
    fi
    open_file "$HERE_PATH"
}

cmd_add() {
    local p="${1:-}" f
    if [ -z "$p" ]; then err "Uso: todo add <path>"; return 2; fi
    p="$(abs_path "$p")"

    if [ ! -f "$p" ]; then
        warn "Il file non esiste: $p"
        if confirm "Crearlo?"; then
            mkdir -p "$(dirname "$p")" || return 1
            printf '# fatti\n\n# da fare\n\n' > "$p"
            ok "Creato: $p"
        else
            return 1
        fi
    fi

    load_list
    for f in "${TODO_FILES[@]}"; do
        if [ "$f" = "$p" ]; then warn "Già in lista: $p"; return 0; fi
    done
    TODO_FILES+=("$p")
    save_list
    ok "Aggiunto alla lista: $p"
}

cmd_rm() {
    local arg="${1:-}" idx=-1 i p removed
    if [ -z "$arg" ]; then err "Uso: todo rm <indice|path>"; return 2; fi
    load_list
    if [[ "$arg" =~ ^[0-9]+$ ]]; then
        if [ "$arg" -ge 1 ] && [ "$arg" -le ${#TODO_FILES[@]} ]; then idx=$((arg - 1)); fi
    else
        p="$(abs_path "$arg")"
        for i in "${!TODO_FILES[@]}"; do
            if [ "${TODO_FILES[$i]}" = "$p" ]; then idx=$i; fi
        done
    fi
    if [ "$idx" -lt 0 ]; then err "Non trovato nella lista: $arg"; return 1; fi
    removed="${TODO_FILES[$idx]}"
    unset "TODO_FILES[$idx]"
    TODO_FILES=("${TODO_FILES[@]}")
    save_list
    ok "Rimosso dalla lista: $removed"
}

cmd_check() {
    local i f problems=0 dups
    need_list || return 1
    for i in "${!TODO_FILES[@]}"; do
        f="${TODO_FILES[$i]}"
        if ! file_counts "$f"; then
            err "[$((i + 1))] file non trovato: $f"; problems=$((problems + 1))
        elif [ $((DONE_N + OPEN_N)) -eq 0 ]; then
            warn "[$((i + 1))] nessuna checkbox riconosciuta in: $f"
        fi
    done
    dups=$(printf '%s\n' "${TODO_FILES[@]}" | sort | uniq -d)
    if [ -n "$dups" ]; then
        while IFS= read -r f; do err "duplicato in lista: $f"; problems=$((problems + 1)); done <<< "$dups"
    fi
    if [ "$problems" -eq 0 ]; then ok "Lista ok (${#TODO_FILES[@]} file)"; return 0; fi
    return 1
}

# Prompt automatico all'apertura del terminale: al massimo una volta ogni
# TODO_INTERVAL secondi, solo in terminali interattivi, solo se c'è qualcosa da fare.
cmd_auto() {
    interactive || return 0
    [ -f "$TODO_LIST_FILE" ] || return 0

    local now last choice i has=0
    now=$(date +%s)
    if [ -f "$TODO_STAMP_FILE" ]; then
        last=$(cat "$TODO_STAMP_FILE" 2>/dev/null)
        [[ "$last" =~ ^[0-9]+$ ]] || last=0
        if (( now - last < TODO_INTERVAL )); then return 0; fi
    fi

    load_list
    for i in "${!TODO_FILES[@]}"; do
        if file_counts "${TODO_FILES[$i]}" && [ "$OPEN_N" -gt 0 ]; then has=1; fi
    done

    if [ "$has" -eq 1 ]; then
        cmd_stats
        echo
        read -r -p "Progetto da aprire (numero o nome, Invio per saltare): " choice
        if [ -n "$choice" ] && resolve_target "$choice"; then
            open_file "${TODO_FILES[$TARGET_IDX]}"
        fi
    fi
    stamp_now
}

cmd_help() {
    cat <<'EOF'
todo - gestore di più file todo.md

Uso: todo [comando] [argomenti]

Comandi:
  (nessuno), stats, c [-a]    contatori per progetto (solo con pendenti, -a = tutti)
  pending, p [progetto]       task pendenti numerati P.T
  show, s                     contenuto completo di tutti i file
  new, n [-p prog] <testo>    aggiunge "- [ ] testo" sotto "# da fare"
                              (senza -p usa il progetto della cartella corrente)
  done, d <P.T>               segna come fatto il task T del progetto P
  open, o [indice|nome]       apre il todo nell'editor (senza argomenti: scelta da lista)
  here                        apre il todo del progetto in cui ti trovi
  add, a <path>               aggiunge un file alla lista (lo crea se manca)
  rm, r <indice|path>         rimuove un file dalla lista (non lo cancella)
  check                       controlla la lista: file mancanti, duplicati
  auto                        prompt all'avvio del terminale (max 1 volta/ora)
  help, h                     questo aiuto

Variabili d'ambiente:
  TODO_LIST_FILE   lista dei file          (default ~/.list_todo)
  TODO_STAMP_FILE  ultimo prompt automatico (default ~/.last_todo)
  TODO_INTERVAL    secondi tra i prompt    (default 3600)
  TODO_EDITOR      editor                  (default "vim -n")
  NO_COLOR         disattiva i colori

Esempi:
  todo                         # cosa c'è da fare, per progetto
  todo pending phandalverse    # i task pendenti di un progetto
  todo done 2.1                # spunta il primo task pendente del progetto 2
  todo new comprare il latte   # aggiunge al progetto della cartella corrente
  todo new -p swudb fix cron   # aggiunge al progetto "swudb"
  todo open 3                  # apre il terzo todo
EOF
}

main() {
    local cmd="${1:-}"
    [ $# -gt 0 ] && shift
    case "$cmd" in
        "")                       cmd_stats "$@" ;;
        -a|--all)                 cmd_stats -a "$@" ;;
        stats|count|c)            cmd_stats "$@" ;;
        pending|p)                cmd_pending "$@" ;;
        show|summary|s)           cmd_show "$@" ;;
        new|n)                    cmd_new "$@" ;;
        done|d)                   cmd_done "$@" ;;
        open|o)                   cmd_open "$@" ;;
        here)                     cmd_here "$@" ;;
        add|a)                    cmd_add "$@" ;;
        remove|rm|r)              cmd_rm "$@" ;;
        check)                    cmd_check "$@" ;;
        auto)                     cmd_auto "$@" ;;
        help|h|-h|--help)         cmd_help ;;
        version|-v|--version)     echo "todo $TODO_VERSION" ;;
        *)
            err "Comando sconosciuto: $cmd"
            echo "Usa 'todo help' per l'elenco dei comandi." >&2
            return 1 ;;
    esac
}

main "$@"
