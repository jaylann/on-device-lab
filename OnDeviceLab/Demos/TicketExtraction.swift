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

/// Outcome of one extraction run: parsed fields, or the exact broken output.
struct ValidationResult {
    let fields: InvoiceFields?
    let missing: [String]
    let raw: String
    let errorDescription: String?

    var passed: Bool { fields != nil && missing.isEmpty && errorDescription == nil }
}

/// The validation half of the open-weight pipeline: strip reasoning noise,
/// decode, check that every field actually arrived.
enum TicketValidator {

    /// Remove `<think>…</think>` blocks and markdown fences, then cut down to
    /// the outermost JSON object.
    static func strip(_ text: String) -> String {
        var s = text.replacingOccurrences(
            of: "<think>[\\s\\S]*?</think>", with: "", options: .regularExpression)
        s = s.replacingOccurrences(
            of: "```[a-zA-Z]*", with: "", options: .regularExpression)
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if let start = s.firstIndex(of: "{"), let end = s.lastIndex(of: "}"), start < end {
            s = String(s[start...end])
        }
        return s
    }

    static func missingFields(in fields: InvoiceFields) -> [String] {
        fields.fieldPairs.filter { $0.value == nil }.map { $0.name }
    }

    /// Full pipeline for raw model text: strip → decode → presence check.
    ///
    /// ── MILESTONE 3a · EXTRACT IT (open-weight path) ─────────────────────────
    /// This is the whole open-weight philosophy: the model returns *text*, and
    /// YOU turn it into typed data and check it. `strip()` (above) already peels
    /// off `<think>` blocks / fences and isolates the outermost `{…}`. Your job:
    /// decode that into `InvoiceFields` and report which fields are missing.
    ///
    /// Until you do, the Extract tab shows "validation failed" for every
    /// open-weight run — that's the point. Stuck? Build the "OnDeviceLab
    /// (Solution)" scheme (reference lives in Solutions/Solutions.swift).
    /// ─────────────────────────────────────────────────────────────────────────
    #if !SOLUTION
    static func validate(rawOutput: String) -> ValidationResult {
        let cleaned = strip(rawOutput)
        guard let data = cleaned.data(using: .utf8), !cleaned.isEmpty else {
            return ValidationResult(fields: nil, missing: [], raw: rawOutput,
                                    errorDescription: "No JSON object found in the output")
        }
        // TODO 3a — decode `data` into `InvoiceFields` and return a ValidationResult:
        //   • on success: pass the decoded fields + `missingFields(in:)`, errorDescription nil
        //   • on a decode throw: fields nil, put `error.localizedDescription` in errorDescription
        _ = data
        return ValidationResult(fields: nil, missing: [], raw: rawOutput,
                                errorDescription: "TODO 3a — parse the model's JSON")
    }
    #endif

    /// For fields that arrived already-typed (the AFM path).
    static func validate(fields: InvoiceFields, raw: String) -> ValidationResult {
        ValidationResult(fields: fields, missing: missingFields(in: fields),
                         raw: raw, errorDescription: nil)
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

#if canImport(FoundationModels)
extension EngineError {
    /// Same mapping as `AFMEngine` (whose version is private to that file).
    @available(iOS 26.0, macOS 26.0, *)
    init(generationError error: LanguageModelSession.GenerationError) {
        switch error {
        case .exceededContextWindowSize: self = .contextOverflow
        case .guardrailViolation: self = .guardrail
        case .rateLimited: self = .rateLimited
        default: self = .other(error.localizedDescription)
        }
    }
}
#endif
