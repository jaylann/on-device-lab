import Foundation

// ════════════════════════════════════════════════════════════════════════════
//  STRUCTURED OUTPUT — the two philosophies, side by side
//
//  Open weights: ask nicely for JSON, then validate what came back (that's
//  the NeatPass pipeline). Apple FM: the schema is enforced by the runtime
//  via @Generable — its failure mode is refusal, not malformed JSON.
// ════════════════════════════════════════════════════════════════════════════

/// The six fields every engine must pull out of `PromptLibrary.chargingInvoice`.
struct InvoiceFields: Codable {
    var provider: String?
    var location: String?
    var kwh: Double?
    var duration_min: Double?
    var total_eur: Double?
    var session_id: String?

    enum CodingKeys: String, CodingKey {
        case provider, location, kwh, duration_min, total_eur, session_id
    }

    init(provider: String?, location: String?, kwh: Double?,
         duration_min: Double?, total_eur: Double?, session_id: String?) {
        self.provider = provider
        self.location = location
        self.kwh = kwh
        self.duration_min = duration_min
        self.total_eur = total_eur
        self.session_id = session_id
    }

    /// Lenient decoding: small models love returning "43,7" (a string, comma
    /// decimal) where a number belongs. Accept number-or-string for the numeric
    /// fields; truly malformed JSON still fails — that's the show.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        provider = try c.decodeIfPresent(String.self, forKey: .provider)
        location = try c.decodeIfPresent(String.self, forKey: .location)
        kwh = try Self.flexibleDouble(c, .kwh)
        duration_min = try Self.flexibleDouble(c, .duration_min)
        total_eur = try Self.flexibleDouble(c, .total_eur)
        session_id = try c.decodeIfPresent(String.self, forKey: .session_id)
    }

    private static func flexibleDouble(
        _ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys
    ) throws -> Double? {
        if let d = try? c.decodeIfPresent(Double.self, forKey: key) { return d }
        if let s = try? c.decodeIfPresent(String.self, forKey: key) {
            return Double(s.replacingOccurrences(of: ",", with: "."))
        }
        return nil
    }

    var fieldPairs: [(name: String, value: String?)] {
        [("provider", provider),
         ("location", location),
         ("kwh", kwh.map { String(format: "%.1f", $0) }),
         ("duration_min", duration_min.map { String(format: "%.1f", $0) }),
         ("total_eur", total_eur.map { String(format: "%.2f", $0) }),
         ("session_id", session_id)]
    }
}

/// One field graded against the receipt's ground truth.
struct FieldCheck {
    let name: String
    let got: String?
    let expected: String
    let ok: Bool
}

/// Outcome of one extraction run: per-field verdicts, or the exact broken output.
struct ValidationResult {
    let checks: [FieldCheck]
    let raw: String
    let errorDescription: String?

    var passed: Bool {
        errorDescription == nil && !checks.isEmpty && checks.allSatisfy { $0.ok }
    }
}

/// The validation half of the pipeline. Both engines produce typed fields
/// (grammar lock / @Generable) so the schema always holds — the real question
/// is whether the VALUES match the receipt. Presence isn't correctness.
enum TicketValidator {

    private static let numericFields: Set<String> = ["kwh", "duration_min", "total_eur"]

    /// Grade typed fields against the preset's known-good values.
    static func validate(fields: InvoiceFields, raw: String, expected: InvoiceFields) -> ValidationResult {
        let checks = zip(fields.fieldPairs, expected.fieldPairs).map { got, exp in
            FieldCheck(name: got.name, got: got.value, expected: exp.value ?? "",
                       ok: matches(got.value, exp.value ?? "", numeric: numericFields.contains(got.name)))
        }
        return ValidationResult(checks: checks, raw: raw, errorDescription: nil)
    }

    /// Lenient on formatting, strict on substance: numbers within ±0.05,
    /// strings normalized and matched by containment either way (so
    /// "IONITY GmbH" satisfies "IONITY", "…Kamener Kreuz Nord, 59174 Kamen"
    /// satisfies "Kamener Kreuz") — but a value from the wrong session fails.
    private static func matches(_ got: String?, _ expected: String, numeric: Bool) -> Bool {
        guard let got, !got.isEmpty, !expected.isEmpty else { return false }
        if numeric {
            guard let g = Double(got.replacingOccurrences(of: ",", with: ".")),
                  let e = Double(expected.replacingOccurrences(of: ",", with: "."))
            else { return false }
            return abs(g - e) < 0.05
        }
        let g = normalize(got), e = normalize(expected)
        return g == e || g.contains(e) || e.contains(g)
    }

    private static func normalize(_ s: String) -> String {
        s.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

// MARK: - Apple FM structured generation (schema enforced by the runtime)

#if canImport(FoundationModels)
import FoundationModels

/// The same six fields, but as a @Generable schema: the model literally cannot
/// emit malformed JSON — constrained decoding guarantees the shape.
@available(iOS 26.0, macOS 26.0, *)
@Generable(description: "Fields extracted from an EV charging receipt")
struct GenerableInvoice {
    @Guide(description: "Charging network operator, e.g. IONITY")
    var provider: String?
    @Guide(description: "Human-readable station location from the receipt")
    var location: String?
    @Guide(description: "Energy delivered in kWh")
    var kwh: Double?
    @Guide(description: "Charging duration in minutes")
    var durationMin: Double?
    @Guide(description: "Total amount in euros including VAT")
    var totalEur: Double?
    @Guide(description: "Provider session identifier")
    var sessionId: String?

    var asInvoiceFields: InvoiceFields {
        InvoiceFields(provider: provider, location: location, kwh: kwh,
                      duration_min: durationMin, total_eur: totalEur, session_id: sessionId)
    }
}
#endif

/// Availability-safe facade so the view never touches FoundationModels types.
@MainActor
enum AFMExtractor {
    /// ── MILESTONE 3b · EXTRACT IT (Apple FM path) ───────────────────────────
    /// The Apple philosophy is the mirror image of 3a: instead of parsing text
    /// defensively, you hand the runtime a `@Generable` *type* (`GenerableInvoice`,
    /// defined above) and it constrained-decodes straight into it — malformed
    /// JSON is impossible; the only failure mode is a refusal. Your job is the one
    /// call that does this. Runs only on macOS 26 + Apple Intelligence, but you
    /// write it on any Xcode 26. Stuck? Build the "OnDeviceLab (Solution)" scheme
    /// (reference lives in Solutions/Solutions.swift).
    /// ─────────────────────────────────────────────────────────────────────────
    #if !SOLUTION
    static func extractInvoice(prompt: String) async throws -> InvoiceFields {
        // TODO 3b — with Apple's FoundationModels, create a `LanguageModelSession`,
        //   call `respond(to: prompt, generating: GenerableInvoice.self)`, and return
        //   `.content.asInvoiceFields`. No JSONDecoder — constrained decoding does it.
        //   (Runs on macOS 26 + Apple Intelligence; `GenerableInvoice` is defined above.)
        _ = prompt
        throw EngineError.other("TODO 3b — respond(generating:)")
    }
    #endif
}
