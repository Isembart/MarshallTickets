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
- **Replace all** — the Concert's Tickets are discarded (statuses lost) and replaced by the file. In a Transfer, they are replaced by the sender's Tickets with their statuses, and the Concert takes the sender's date.
- **Join** — only codes not yet present are added; existing Tickets keep their status. In a Transfer, Tickets scanned on the other device also become scanned here (the earlier scan time is kept); a Transfer never un-scans a Ticket.

**Transfer** — sending a whole Concert (name, date, Tickets with their statuses) from one device to another, without any network. One-way: the **Sender** shows it, the **Receiver** takes it in. The Receiver matches it to an existing Concert by name (ignoring case and surrounding spaces); with no match a new Concert is created, with a match it ends in an Import (Join or Replace). Renaming a Concert on either device makes them different Concerts as far as Transfer is concerned. A Transfer is accepted whole or not at all. A Transfer can go either way between devices; the main phone can be the Receiver of the venue phone's results.

**Fingerprint** — a short code derived from a Transfer's exact content, shown on both Sender and Receiver so a person can confirm they hold the same data.

Avoid: "check-in", "used", "admitted" — the status is called *scanned*.
