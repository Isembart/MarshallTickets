# MarshallTickets — domain glossary

**Concert** — one event night. Owns a set of Tickets. Has a name and an optional date.

**Ticket** — one admissible entry for one Concert, identified by its Ticket Code. Status is either *not scanned* or *scanned* (with the time it was scanned).

**Ticket Code** — the exact string from the import file, which is also what the ticket's QR code or barcode encodes. Unique within a Concert; the same code may appear in different Concerts. Avoid: "ID", "number".

**Scan** — one attempt to validate a Ticket Code against the selected Concert, by camera or manual entry. Produces a **Scan Result**:
- *Valid* — the Ticket existed and was not scanned; it is now scanned.
- *Already scanned* — the Ticket was scanned before (shows when).
- *Invalid* — no such Ticket in this Concert (may note which other Concert it belongs to).

**Un-scan** — reverting a Ticket to *not scanned* (correcting a mistaken Scan).

**Import** — loading Ticket Codes from a file into a Concert, in one of two modes:
- **Replace all** — the Concert's Tickets are discarded (statuses lost) and replaced by the file.
- **Join** — only codes not yet present are added; existing Tickets keep their status.

Avoid: "check-in", "used", "admitted" — the status is called *scanned*.
