# todo-cli

Comando `todo` per tenere d'occhio i file `todo.md` di tutti i progetti da un unico
punto: contatori, task pendenti, aggiunta e spunta dei task, apertura nell'editor e
promemoria all'avvio del terminale.

È uno script **bash eseguibile** (`todo.sh`), non una funzione da caricare con `source`:
gira sempre in bash, qualunque sia la shell interattiva (zsh, oh-my-zsh, p10k...).

## Requisiti

- bash 4+ (Debian/WSL ha la 5.x), e i comandi standard: `grep`, `sed`, `awk`, `tr`,
  `realpath` (GNU coreutils), `mktemp`.
- Un editor per `todo open` / `todo here` (default `vim -n`, vedi `TODO_EDITOR`).

## Installazione

Il codice resta in questa cartella; l'installazione crea solo un wrapper.

```bash
cd /mnt/c/Users/RickyMandich/PROJECT/todo-cli
bash install.sh              # crea ~/.local/bin/todo
```

`install.sh` stampa anche i passi da fare una tantum:

1. togliere dal `~/.zshrc` / `~/.bashrc` la vecchia riga `source ~/bash/todo_new.sh` e le
   chiamate a `run_todo_if_needed` (nelle shell già aperte: `unset -f todo`);
2. (opzionale) mettere `todo auto` nel `~/.zshrc` **prima** del blocco
   *Enable Powerlevel10k instant prompt*, perché stampa e chiede input;
3. assicurarsi che `~/.local/bin` sia nel `PATH`.

Poiché il wrapper punta a `todo.sh` in questa cartella, ogni modifica al codice è
subito attiva, senza ricopiare nulla.

## Uso

```text
todo                       contatori per progetto (solo quelli con task pendenti)
todo -a                    contatori per tutti i progetti
todo pending [progetto]    task pendenti numerati P.T (P = progetto, T = task)
todo show                  contenuto completo di tutti i file
todo new <testo>           aggiunge un task al progetto della cartella corrente
todo new -p <prog> <testo> aggiunge un task a un progetto (indice o nome)
todo done <P.T>            segna come fatto il task T del progetto P
todo open [indice|nome]    apre il todo nell'editor (senza argomenti: scelta da lista)
todo here                  apre il todo del progetto in cui ti trovi
todo add <path>            aggiunge un file alla lista (lo crea se non esiste)
todo rm <indice|path>      toglie un file dalla lista (non lo cancella)
todo check                 controlla la lista: file mancanti, duplicati
todo auto                  prompt all'avvio del terminale (max 1 volta all'ora)
todo help
```

Alias: `c`/`count` = stats, `p` = pending, `s`/`summary` = show, `n` = new, `d` = done,
`o` = open, `a` = add, `r`/`remove` = rm, `h` = help.

Esempio di sessione:

```text
$ todo pending
[2] phandalverse
  2.1  fix tree icone
  2.2  documentare .env-overrides

$ todo done 2.1
Fatto: fix tree icone  (phandalverse)

$ cd ~/progetti/swudb && todo new controllare il cronjob
Aggiunto a swudb: controllare il cronjob
```

I progetti si indicano con l'**indice** mostrato da `todo` / `todo pending` oppure con
una parte del **nome** (la cartella che contiene il `todo.md`, case-insensitive). Se due
cartelle hanno lo stesso nome vengono mostrate come `genitore/cartella`.

## Formato dei file todo

Markdown con checkbox. Sono riconosciuti i bullet `-`, `*`, `+`, anche indentati:

```markdown
# fatti
- [X] task completato

# da fare
- [ ] task da fare
```

- Conta come **fatto** `[X]` o `[x]`, come **da fare** `[ ]` (uno spazio).
- `todo new` aggiunge in fondo alla sezione `# da fare` (anche `# todo` / `# to do`);
  se la sezione manca, aggiunge in coda al file.
- `todo done` cambia `[ ]` in `[X]` **sulla stessa riga**, senza spostarla.
- I file con fine riga CRLF sono letti e modificati senza alterare i fine riga.

## File di stato e configurazione

| Cosa | Default | Variabile |
|---|---|---|
| Lista dei todo (un percorso assoluto per riga) | `~/.list_todo` | `TODO_LIST_FILE` |
| Timestamp dell'ultimo prompt automatico | `~/.last_todo` | `TODO_STAMP_FILE` |
| Secondi tra due prompt automatici | `3600` | `TODO_INTERVAL` |
| Editor | `vim -n` | `TODO_EDITOR` |
| Disattiva i colori | | `NO_COLOR=1` |
| Risponde sempre sì alle conferme (script/test) | | `TODO_ASSUME_YES=1` |
| Forza la modalità interattiva (test) | | `TODO_INTERACTIVE=1` |

Le righe vuote in `~/.list_todo` sono ignorate. L'**indice** di un progetto è la sua
posizione tra le righe non vuote, file mancanti compresi, quindi coincide sempre con quello
usato da `open`, `rm`, `done`.

## Struttura del progetto

```text
todo-cli/
├── todo.sh                     implementazione (unico file di codice)
├── install.sh                  crea il wrapper ~/.local/bin/todo
├── tests/test_todo.sh          test con asserzioni, HOME temporanea
├── .gitattributes              fine riga LF forzato per script e markdown
├── README.md                   questa documentazione
├── todo.md                     todo del progetto stesso
└── implementationPlan-V-*.md   piani di implementazione già eseguiti
```

### Mappa di `todo.sh`

Il file è organizzato a sezioni, dall'alto in basso:

| Sezione | Funzioni principali |
|---|---|
| Configurazione e colori | variabili `TODO_*`, regex `DONE_RE` / `OPEN_RE` / `STRIP_SED` |
| Utilità | `interactive`, `confirm`, `abs_path`, `stamp_now` |
| Lista | `load_list`, `save_list`, `compute_names`, `file_counts`, `need_list` |
| Selezione progetto | `resolve_target` (→ `TARGET_IDX`), `pick_project`, `find_here` (→ `HERE_PATH`) |
| Modifica file | `open_file`, `insert_item` |
| Comandi | `cmd_stats`, `cmd_pending`, `cmd_show`, `cmd_new`, `cmd_done`, `cmd_open`, `cmd_here`, `cmd_add`, `cmd_rm`, `cmd_check`, `cmd_auto`, `cmd_help` |
| Dispatch | `main` (il `case` che collega i comandi e i loro alias) |

Convenzioni usate nel codice:

- Stato condiviso in variabili globali: `TODO_FILES` (percorsi), `NAMES` (nomi mostrati,
  stesso indice), `TARGET_IDX` (risultato di `resolve_target`, 0-based), `DONE_N`/`OPEN_N`
  (risultato di `file_counts`). Gli indici interni sono 0-based, quelli mostrati 1-based.
- I messaggi d'errore vanno su stderr (`err`, `warn`), i risultati su stdout (`ok`).
- Exit code: `0` ok, `1` errore operativo, `2` uso errato degli argomenti.
- Nessun `set -e`/`set -u`: ogni comando gestisce i propri errori.
- Il testo dei task passa ad `awk` tramite `ENVIRON`, mai in `-v`, per non interpretare
  i backslash.

### Aggiungere un comando

1. Scrivere `cmd_nome()` in `todo.sh`, usando `need_list` / `resolve_target` per scegliere il
   progetto e `err`/`warn`/`ok` per i messaggi.
2. Registrarlo (con gli alias) nel `case` di `main` e nel testo di `cmd_help`.
3. Aggiungere i test in `tests/test_todo.sh`, ed eseguirli.
4. Aggiornare questo README e `todo.md`.

## Test

```bash
bash tests/test_todo.sh
```

I test creano una HOME e una lista temporanee: non toccano `~/.list_todo` né i tuoi
`todo.md`. Coprono conteggi, indici, ricerca per nome, `pending`/`done`/`new`, `here`,
`add`/`rm`, `check`, `auto`, i file CRLF e le regressioni della vecchia versione (ciclo
infinito su opzioni sconosciute, conteggio `00`, indici sfalsati da righe vuote).
Terminano con exit code diverso da 0 se un controllo fallisce.

## Risoluzione dei problemi

| Sintomo | Causa e rimedio |
|---|---|
| `todo` esegue ancora la vecchia versione | in quella shell esiste ancora la funzione `todo`: `unset -f todo` o nuovo terminale; togliere il `source` dal `.zshrc`/`.bashrc` |
| `command not found: todo` | `~/.local/bin` non è nel `PATH` |
| p10k avvisa di output durante l'inizializzazione | spostare `todo auto` sopra il blocco *instant prompt* nel `~/.zshrc` |
| `bad interpreter` / errori di sintassi strani | fine riga CRLF in `todo.sh`: rilanciare `bash install.sh` (li converte), il `.gitattributes` evita che tornino con Git |
| `Permission denied` su `/mnt/c/...` | il wrapper usa `bash todo.sh`, non serve il bit eseguibile: reinstallare con `bash install.sh` |

## Limiti noti

- `todo done` e `todo new` modificano i file in place, senza annullamento.
- `todo auto` è pensato per shell interattive: negli script non fa nulla.
- Sono riconosciute solo le checkbox in stile Markdown (`- [ ]`, `- [X]`).
