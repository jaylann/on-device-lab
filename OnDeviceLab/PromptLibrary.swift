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

    /// Arena preset: dashboard-glance arithmetic — the kind of question a driver actually asks the car.
    static let carRange = "How far can I drive with 61% battery if my car averages 18.4 kWh/100km and has an 82 kWh pack? Give a short answer for a driver glancing at the dashboard."

    /// Arena preset: the extraction shape again, but automotive — a messy charging receipt.
    static let chargingInvoice = """
    LADEBELEG / CHARGING RECEIPT  --  IONITY GmbH
    Standort: IONITY Stuttgart-Zuffenhausen, Porschestr. 1, 70435 Stuttgart
    Ladevorgang gestartet 2026-07-14T18:42:07+02:00
    Energie geladen: 43,7 kWh   Ladedauer: 31,2 min   Tarif: 0,79 EUR/kWh
    Gesamtbetrag: 34,52 EUR inkl. 19% MwSt.
    Session-ID: IONITY-DE-2207-884131   Vielen Dank fuer Ihre Ladung. Gute Fahrt!

    Read the receipt above and return ONLY a JSON object with keys: provider, location, \
    kwh, duration_min, total_eur, session_id. If a field is missing use null. Never invent \
    a value that is not present in the text.
    """

    /// Context-window race: a synthetic trip-log of `repeats` timestamped entries
    /// (~35 tokens each — same idea as `longContext`, but sized on demand), ending
    /// with a needle question the model can only answer by reading the whole log.
    static func contextBlock(repeats: Int) -> String {
        let locations = ["A8 near Ulm", "A81 near Sindelfingen", "B27 near Zuffenhausen", "A5 near Karlsruhe"]
        var lines: [String] = []
        lines.reserveCapacity(repeats)
        for i in 0..<repeats {
            let stamp = String(format: "13:%02d:%02d", (i * 2) % 60, (i * 17) % 60)
            let speed = 96 + (i * 7) % 45
            let soc = max(90 - i, 9)
            let kwh = 16.0 + Double((i * 3) % 60) / 10.0
            let location = locations[i % locations.count]
            lines.append(
                "[\(stamp)] trip log: speed \(speed) km/h, battery SoC \(soc)%, " +
                "consumption \(String(format: "%.1f", kwh)) kWh/100km, position \(location).")
        }
        return lines.joined(separator: "\n")
            + "\n\nWhat was the lowest state of charge mentioned, and where?"
    }
}
