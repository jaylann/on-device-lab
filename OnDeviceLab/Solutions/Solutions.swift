//  Solutions.swift — reference implementations for the code-along milestones:
//  M2 (measure), M3a/M3b (extraction, open + AFM), M4a/M4b (tools, open + AFM).
//
//  Compiled ONLY by the "OnDeviceLab (Solution)" scheme (the SOLUTION flag). In
//  the default scheme every symbol here is #if'd out, and the participant-facing
//  files carry the matching #if !SOLUTION stubs instead. This file is the answer
//  key — don't peek unless you're truly stuck (or you're presenting).
//
//  Present from the Solution scheme so the Extract / Tools / Arena tabs are live.

#if SOLUTION
import Foundation
import JSONSchema
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - M2 · Measure it (round 1 — latency)

extension BenchmarkRunner {
    func tally(firstTokenTime: inout Date?, tokenCount: inout Int) {
        if firstTokenTime == nil { firstTokenTime = Date() }   // TTFT: stamp the first token
        tokenCount += 1                                        // throughput: count every token
    }
}

// MARK: - M3a · Extract it, open-weight path (round 2 — structured output)

extension GrammarLock {
    /// All six fields required: the demo receipts carry every field, so the
    /// grammar guarantees a full, valid object.
    static let invoiceSchema = JSONSchema.object(
        description: "Fields extracted from an EV charging receipt",
        properties: [
            "provider": .string(),
            "location": .string(),
            "kwh": .number(),
            "duration_min": .number(),
            "total_eur": .number(),
            "session_id": .string(),
        ],
        required: ["provider", "location", "kwh", "duration_min", "total_eur", "session_id"]
    )
}

// MARK: - M4a · Tool it, open-weight path (round 3 — tool calling)

extension CarToolbox {
    static func dispatch(name: String, arguments: [String: Any]) -> String? {
        switch name {
        case "charging_stations", "chargingStations":
            return chargingStationsText(near: arguments["near"] as? String ?? "Stuttgart")
        case "vehicle_range", "vehicleRange":
            return vehicleRangeText()
        case "weather":
            return weather(at: arguments["at"] as? String ?? "Stuttgart")
        default:
            return nil
        }
    }
}

// MARK: - M3b · Extract it, Apple FM path

extension AFMExtractor {
    static func extractInvoice(prompt: String) async throws -> InvoiceFields {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            let session = LanguageModelSession()
            do {
                // Generate directly into the schema — no string parsing anywhere.
                // Same sampling and token cap as the grammar-locked MLX path.
                let response = try await session.respond(
                    to: prompt, generating: GenerableInvoice.self,
                    options: GenerationOptions(temperature: 0.3, maximumResponseTokens: 512))
                return response.content.asInvoiceFields
            } catch let error as LanguageModelSession.GenerationError {
                throw EngineError(generationError: error)
            }
        }
        #endif
        throw EngineError.other("Needs macOS 26 / iOS 26 + Apple Intelligence")
    }
}

// MARK: - M4b · Tool it, Apple FM path

#if canImport(FoundationModels)
@available(iOS 26.0, macOS 26.0, *)
extension WeatherTool {
    func call(arguments: Arguments) async throws -> String {
        let result = CarToolbox.weather(at: arguments.at)
        onEvent("weather(at: \"\(arguments.at)\")", result)
        return result
    }
}
#endif
#endif
