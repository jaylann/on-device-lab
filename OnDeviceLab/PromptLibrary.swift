import Foundation

/// Prompts used by the chat box and the benchmark. The extraction prompt is on-theme:
/// it's the exact shape of work NeatPass does — pull structured fields out of a messy ticket.
enum PromptLibrary {

    static let chatDefault = "In two sentences: why does an app run a language model on the phone instead of in the cloud?"

    /// The benchmark prompt. Long enough that prompt-eval (the TTFT cost) is realistic.
    static let extraction = """
    You extract structured data from event tickets. Read the raw text and return ONLY a JSON object \
    with keys: type, title, venue, city, date, seat. If a field is missing use null. Never invent a \
    value that is not present in the text.

    RAW TICKET TEXT:
    Die Fantastischen Vier - Live 2026  ||  Olympiahalle Muenchen, Spiridon-Louis-Ring 21
    Einlass 19:00  Beginn 20:00   12.09.2026   Block C  Reihe 14  Platz 7
    Order #DE-99213  ticket-id 8841200391  price 89,90 EUR incl. VAT
    Bitte halten Sie diesen QR-Code am Einlass bereit. Kein Wiederverkauf.

    Return the JSON now:
    """

    /// M3 stress: a long prompt to watch the context window fill.
    static let longContext = String(repeating:
        "The vehicle log records that at the given timestamp the cabin temperature, battery state of charge, " +
        "and estimated range were sampled and written to the on-device store. ", count: 40)
        + "\n\nSummarize the repeated log line above in one sentence."
}
