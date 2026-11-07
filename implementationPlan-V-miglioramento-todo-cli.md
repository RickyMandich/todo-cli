# Implementation plan: miglioramento todo-cli

## Contesto

Lo strumento `todo` nasce come funzione bash (`~/bash/todo_new.sh`) caricata con `source`.
Gestisce più file `todo.md` di progetti diversi, elencati in `~/.list_todo`; `~/.last_todo`
contiene il timestamp dell'ultimo prompt automatico.

La shell interattiva dell'utente è **zsh (oh-my-zsh + p10k)**, quindi il codice sourced
(che usa sintassi solo bash: `read -p`, `${!array[@]}`, array 0-indexed) non è affidabile.

## Problemi da risolvere

1. `show_stats`: ciclo infinito con argomenti diversi da `-a`, `echo "parso"` di debug.
2. Conteggio "00": `grep -c ... || echo 0` stampa due zeri se non ci sono match.
3. Indici sfalsati tra `stats` e `open` / `rm` (righe vuote, file mancanti).
4. `todo open` senza argomenti mostra il riepilogo senza numeri.
5. `ask_bool` non è definita nello script (dipende dal `.bashrc`).
6. Percorsi relativi in `add` / `rm` con cartelle inesistenti.
7. Documentazione incoerente (3 file `.md` sovrapposti), test senza asserzioni.
8. Solo i bullet `-` sono contati.

## Scelte di progetto

- **Script eseguibile, non funzione sourced**: `#!/usr/bin/env bash`, quindi gira in bash
  qualunque sia la shell dell'utente. Nessuna dipendenza dal `.bashrc` o `.zshrc`.
- **Wrapper di installazione**: `install.sh` crea `~/.local/bin/todo` con
  `exec bash <repo>/todo.sh "$@"`. Evita problemi con il bit eseguibile su `/mnt/c` e
  permette di tenere il codice in `C:\Users\RickyMandich\PROJECT\todo-cli` senza ricopiare.
- **Compatibilità dello stato**: stessi `~/.list_todo` e `~/.last_todo`, formato invariato.
- **Configurabile via variabili d'ambiente** (`TODO_LIST_FILE`, `TODO_STAMP_FILE`,
  `TODO_INTERVAL`, `TODO_EDITOR`), così i test usano una HOME temporanea.
- **Fine riga LF garantito** da `.gitattributes`, dato che il codice vive sul filesystem Windows.
- **Indici stabili**: la lista viene letta in un array ignorando le righe vuote (niente
  commenti: `rm` riscrive il file e li perderebbe); l'indice mostrato è sempre la posizione
  in questo array, anche per i file mancanti.
- **p10k instant prompt**: `todo auto` va chiamato nel `.zshrc` *prima* del blocco
  instant prompt, perché stampa e chiede input.

## Comandi finali

| Comando | Alias | Descrizione |
|---|---|---|
| `todo` | `stats`, `c` | contatori per progetto (solo con pendenti, `-a` per tutti) |
| `todo pending` | `p` | task pendenti per progetto, numerati `P.T` |
| `todo show` | `s`, `summary` | contenuto completo dei file |
| `todo new [-p prog] <testo>` | `n` | aggiunge `- [ ] testo` sotto `# da fare` (o in coda); senza `-p` usa il progetto della cartella corrente |
| `todo done P.T` | `d` | segna il task T del progetto P come `[X]` |
| `todo open [n\|nome]` | `o` | apre in vim (`TODO_EDITOR`), senza argomenti sceglie dalla lista |
| `todo here` | | apre il todo del progetto corrente (risale da cwd) |
| `todo add / rm` | `a`, `r` | gestione lista, percorsi sempre normalizzati |
| `todo check` | | segnala file mancanti, duplicati, righe anomale |
| `todo auto` | | prompt orario, solo se terminale interattivo |
| `todo help` | `h` | aiuto |

## Passi

1. [x] Analizzare il codice esistente e individuare i difetti.
2. [x] Scrivere questo piano nella root del progetto.
3. [x] Implementare `todo.sh` e `install.sh` nella sandbox Linux.
4. [x] Scrivere `tests/test_todo.sh` con asserzioni (HOME temporanea) ed eseguirli:
       83 controlli, tutti ok.
5. [x] Scrivere i file nel progetto: `todo.sh`, `install.sh`, `tests/`, `README.md`,
       `todo.md`, `.gitattributes`.
6. [x] Verificare i file scritti (dimensioni identiche a quelle collaudate, fine riga LF).
7. [x] Rinominare il piano in `implementationPlan-V-miglioramento-todo-cli.md`.

## Fuori scopo

- Non vengono toccati i file originali in `~` (`bash/todo_new.sh`, vecchie guide `.md`):
  vanno rimossi a mano dopo la migrazione.
- Nessuna modifica a `.zshrc` / `.bashrc`: le istruzioni sono nel README.
