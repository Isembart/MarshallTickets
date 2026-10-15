# MarshallTickets

Offline ticket scanner for concerts (Flutter, Android + iOS, Polish UI). Glossary: [CONTEXT.md](CONTEXT.md).

- Concerts: create / edit / delete, list with scanned/total counts.
- Import `.txt` (one code per line) or `.csv` (first column, `,` or `;`, optional header) into a concert. If the concert already has tickets: **Zastąp wszystko** (Replace all) or **Połącz** (Join: only new codes added, statuses kept).
- Scanner: QR, EAN-13/8, UPC-A, Code128, Code39, plus manual entry. Result: valid (marks scanned) / already scanned (with time) / invalid (with the other concert's name if the code belongs elsewhere).
- Tap a ticket in the list to mark it scanned or not scanned (with confirmation).

Matching is exact on the trimmed code string.

## Run

```
flutter test
flutter run
```

## Future (not in MVP)

- Syncing scan statuses between phones (`tickets.scanned_at` timestamps are stored for this).
- Exporting scan results.
