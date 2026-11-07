# fatti
- [X] analizzare il vecchio todo_new.sh e individuare i difetti
- [X] riscrivere come script bash eseguibile (indipendente da zsh/bash e dal .bashrc)
- [X] correggere: ciclo infinito in stats, conteggio "00", indici sfalsati, open senza numeri, ask_bool mancante, percorsi relativi
- [X] nuovi comandi: pending, new, done, here, check
- [X] test con asserzioni (83 controlli, HOME temporanea)
- [X] install.sh, README.md unico, .gitattributes (fine riga LF)
- [X] installare con install.sh e verificare `todo auto` in zsh sulla lista reale (13 progetti)
- [X] migrare ~/.zshrc e ~/.bashrc: tolti source e funzione run_todo_if_needed, `todo auto` dopo il fastfetch e prima del blocco p10k instant prompt

# da fare
- [X] provare `todo pending`, `todo done`, `todo new` sui progetti reali
- [X] rimuovere dalla home i vecchi file (bash/todo_new.sh, test_todo*.sh, TODO_COMMAND_USAGE.md, INSTALL_TODO_COMMAND.md, TODO_IMPLEMENTATION_SUMMARY.md)
- [ ] git init del progetto e primo commit
- [ ] idee: todo undo, archiviazione dei fatti, completamento con Tab per zsh/bash
