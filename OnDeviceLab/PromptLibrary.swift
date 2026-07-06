import Foundation

/// Prompts used by the chat box and the benchmark. The extraction prompt is on-theme:
/// it's the exact shape of work NeatPass does — pull structured fields out of a messy ticket.
enum PromptLibrary {

    static let chatDefault = "In two sentences: why does an app run a language model on the phone instead of in the cloud?"

    /// Everything is English on purpose: AFM throws `unsupportedLanguageOrLocale`
    /// when a prompt's detected language isn't in the device's Apple Intelligence
    /// language set, and a demo must not depend on the demo Mac's settings.
    /// The extraction prompt is on-theme: the exact shape of work NeatPass does.
    static let extraction = """
    You extract structured data from event tickets. Read the raw text and return ONLY a JSON object \
    with keys: type, title, venue, city, date, seat. If a field is missing use null. Never invent a \
    value that is not present in the text.

    RAW TICKET TEXT:
    Die Fantastischen Vier - Live 2026  ||  Olympiahalle Munich, Spiridon-Louis-Ring 21
    Doors 19:00  Show 20:00   12.09.2026   Block C  Row 14  Seat 7
    Order #DE-99213  ticket-id 8841200391  price 89.90 EUR incl. VAT
    Please have this QR code ready at the entrance. No resale.

    Return the JSON now:
    """

    /// Mirrors `bench/bench.py` DEFAULT_PROMPT verbatim so in-app benchmark
    /// numbers are comparable to the harness behind the deck's Round-1 chart.
    static let benchmark = """
    You are an in-car voice assistant. A passenger asks how regenerative braking \
    works and how it affects the car's range in city versus highway driving. Answer in clear, friendly \
    prose of at least 500 words. Cover the physics of turning motion back into charge, what the driver \
    feels through the pedal, when it helps most, when it barely helps, and its limits in cold weather \
    and at high speed.
    """

    /// M3 stress: a long prompt to watch the context window fill.
    static let longContext = String(repeating:
        "The vehicle log records that at the given timestamp the cabin temperature, battery state of charge, " +
        "and estimated range were sampled and written to the on-device store. ", count: 40)
        + "\n\nSummarize the repeated log line above in one sentence."

    /// Arena preset: dashboard-glance arithmetic — the kind of question a driver actually asks the car.
    static let carRange = "How far can I drive with 61% battery if my car averages 18.4 kWh/100km and has an 82 kWh pack? Give a short answer for a driver glancing at the dashboard."

    /// The instruction shared by every charging-receipt preset.
    private static let invoiceInstruction = """

    Read the receipt above and return ONLY a JSON object with keys: provider, location, \
    kwh, duration_min, total_eur, session_id. If a field is missing use null. Never invent \
    a value that is not present in the text.
    """

    /// Extract preset: the extraction shape again, but automotive — a clean charging receipt.
    static let chargingInvoice = """
    CHARGING RECEIPT  --  IONITY GmbH
    Location: IONITY Stuttgart-Zuffenhausen, Porschestr. 1, 70435 Stuttgart
    Session started 2026-07-14T18:42:07+02:00
    Energy delivered: 43.7 kWh   Charging time: 31.2 min   Tariff: 0.79 EUR/kWh
    Total: 34.52 EUR incl. 19% VAT
    Session ID: IONITY-DE-2207-884131   Thank you for charging. Safe travels!
    """ + invoiceInstruction

    /// Extract preset: different provider and values — proves the schema, not the memorized receipt.
    static let chargingInvoiceAlt = """
    CHARGING RECEIPT  --  EnBW mobility+ AG
    Location: EnBW HyperNetz Pragsattel, Loewentorstr. 64, 70376 Stuttgart
    Session started 2026-07-02T08:17:44+02:00
    Energy delivered: 27.9 kWh   Charging time: 18.6 min   Tariff: 0.61 EUR/kWh
    Total: 17.02 EUR incl. 19% VAT
    Session ID: ENBW-DE-0702-113058   Thank you for charging.
    """ + invoiceInstruction

    /// Extract preset: the stress test — ~2k tokens of OCR-grade mess. The six
    /// real fields are scattered through marketing filler, terms boilerplate and
    /// four traps: a "recent sessions" history of lookalike values, a NOT-billed
    /// unplug estimate right before the real block, OCR digit/letter swaps in the
    /// billed numbers (6l.5kWh, 8O.OO hold), and a duration in min+s (44min48s
    /// = 44.8) with the session id broken across a line. Long enough to bury the
    /// needle, still inside AFM's 4,096-token window so it tests extraction, not
    /// context overflow. Wrong values or dropped fields on stage ARE the demo.
    static let chargingInvoiceScan = """
    fastned deutschland gmbh & co. kg -- CHARGlNG RECElPT -- page 1/3
    customer copy *** retain for your records *** doc-scan quality: LOW

    Thank you for choosing Fastned! Did you know you can save up to 30% with
    Fastned Gold Membership? Ask in the app. Rate your charging experience
    today and win one of 50 charging credits worth 25.00 EUR each. Terms apply.

    >>> loc: Fastned Kamener Kreuz Nord, A1/A2, 59174 Kamen <<<
    station no. DE*FSN*E110119 | CCS-2 | max 300 kW | bays: 8 (2 accessible)
    operator hotline +49 30 770 193 39 (24/7) | support@fastned.de

    - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
    YOUR RECENT SESSIONS (for reference only, already billed):
    2026-06-02  Fastned Limburg Ost      sess. FASTNED-DE-0602-001981   38.2 kWh   27.1 min   31.55 EUR
    2026-06-07  Fastned Hilden Sued      sess. FASTNED-DE-0607-004410   52.0 kWh   39.4 min   44.20 EUR
    2026-06-13  Fastned Brohltal West    sess. FASTNED-DE-0613-007733   19.8 kWh   14.9 min   16.83 EUR
    - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

    ALLGEMEINE HINWEISE / GENERAL NOTES (excerpt, machine-translated):
    The displayed charging power depends on vehicle, battery temperature and
    state of charge. Billing is per kWh delivered at the connector. Parking
    fees may apply after 45 minutes of idle time (blocking fee 0.35 EUR/min,
    not charged on this receipt). Prices include statutory VAT. Receipts are
    also available in the Fastned app under Account > History > Receipts.
    For reimbursement questions contact your fleet manager. Fastned assumes
    no liability for vehicle-side charging interruptions. Complaints must be
    submitted within 8 weeks of the charging date. This document was produced
    automatically and is valid without signature.

    SESSION SUMMARY AS SHOWN AT UNPLUG (estimate only, NOT billed):
    energy ~61.2 kWh | time ~44 min | est. cost 54.47 EUR
    figures above are a connector-side preview; see final receipt below.

    ******************* CURRENT SESSION *******************
    started 2026-06-19T21:03:12+02:00 | connector CCS right | auth: app
    energy de1ivered 6l.5kWh | charging time 44min48s
    tariff 0.89 EUR/kWh (Standard, no membership discount applied)
    sess. id FASTNED-DE-1119-
    002764
    card authorization hold 8O.OO EUR (released after billing)
    tOTAL 58 . 41 EUR incl.19%VAT (net 49.08 EUR, VAT 9.33 EUR)
    payment: visa ****4412, authorized 21:48:07, code 00 (approved)
    *** thank you & safe travels ***
    ********************************************************

    Fastned Deutschland GmbH & Co. KG, Reichsstr. 15, 14052 Berlin
    USt-IdNr. DE815341741 | Amtsgericht Charlottenburg HRA 55923 B
    Managing directors: M. Langezaal, V. van Dijk. Regulated under EichVO.
    Calibration law (Eichrecht) transparency record: SAFE-XDA-119-P44 —
    verify at transparenz.software with public key 8842-AA31-0D77-91FC.

    Download the Fastned app for live availability, plug & charge setup and
    kWh price overviews. Follow us @fastnedcharging. Unsubscribe from paper
    receipts in the app: Account > Preferences > Go paperless. Fastned is
    carbon neutral: all electricity is sourced 100% from sun and wind. This
    page intentionally contains no further billing information. -- page 3/3
    """ + invoiceInstruction

    /// Context-window race: a synthetic trip-log of `repeats` timestamped entries
    /// (~`tokensPerRepeat` tokens each — same idea as `longContext`, but sized on
    /// demand), ending with a needle question the model can only answer by
    /// reading the whole log.
    static let tokensPerRepeat = 35

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
        // The English framing up front is not decoration: AFM language-detects
        // the prompt, and a wall of numeric telemetry classifies as no supported
        // language ("unsupported language or locale"). Anchoring the prompt in
        // natural prose fixes that — identically for every engine, so it's fair.
        return "The following is a trip log recorded by the vehicle during one drive. "
            + "Read the whole log carefully and then answer the question that follows it.\n\n"
            + lines.joined(separator: "\n")
            + "\n\nQuestion: What was the lowest battery state of charge mentioned anywhere "
            + "in the log above, and at which position did it occur? Answer in one sentence."
    }
}
