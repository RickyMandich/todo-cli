#!/usr/bin/env bash
# Installa il comando `todo`: crea un piccolo wrapper in ~/.local/bin che esegue
# todo.sh di questo repository. Non serve il bit eseguibile (utile su /mnt/c) e il
# codice resta dove si trova: ogni modifica a todo.sh è subito attiva.
#
# Uso: bash install.sh [cartella-bin]     (default: ~/.local/bin)

set -e

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="${1:-$HOME/.local/bin}"
SCRIPT="$REPO_DIR/todo.sh"

if [ ! -f "$SCRIPT" ]; then
    echo "todo.sh non trovato in $REPO_DIR" >&2
    exit 1
fi

# Fine riga CRLF (tipici dei file creati da Windows) rompono bash: li normalizzo.
if grep -q $'\r' "$SCRIPT"; then
    echo "todo.sh contiene fine riga CRLF: li converto in LF"
    sed -i 's/\r$//' "$SCRIPT"
fi

mkdir -p "$BIN_DIR"
cat > "$BIN_DIR/todo" <<EOF
#!/usr/bin/env bash
exec bash "$SCRIPT" "\$@"
EOF
chmod +x "$BIN_DIR/todo"
echo "Installato: $BIN_DIR/todo -> $SCRIPT"

case ":$PATH:" in
    *":$BIN_DIR:"*) ;;
    *) echo
       echo "ATTENZIONE: $BIN_DIR non è nel PATH. Aggiungi al tuo ~/.zshrc:"
       echo "  export PATH=\"$BIN_DIR:\$PATH\"" ;;
esac

cat <<'EOF'

Prossimi passi (una tantum):

1. Rimuovi dal ~/.zshrc / ~/.bashrc la vecchia riga `source ~/bash/todo_new.sh`
   e le chiamate a `run_todo_if_needed`: ora `todo` è un programma, non una funzione.
   Nelle shell già aperte, esegui `unset -f todo` (o apri un nuovo terminale).

2. Per il prompt automatico all'avvio del terminale, aggiungi in ~/.zshrc la riga
       todo auto
   PRIMA del blocco "Enable Powerlevel10k instant prompt" in cima al file:
   `todo auto` stampa e chiede input, e dopo quel blocco p10k lo segnalerebbe
   come output durante l'inizializzazione.

3. Prova:  todo        todo pending        todo help
EOF
