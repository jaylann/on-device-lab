import Foundation

// ════════════════════════════════════════════════════════════════════════════
//  TOOL CALLING — three canned, deterministic car tools
//
//  Both engines call the same `CarToolbox`. AFM gets real Tool-protocol
//  structs (the runtime does the call loop); the open-weight path does the
//  JSON-protocol dance by hand, which is exactly the point of the demo.
//  All wording stays neutral (charging, range, weather) by design.
// ════════════════════════════════════════════════════════════════════════════

struct Station: Identifiable {
    let id = UUID()
    let name: String
    let operatorName: String
    let kW: Int
    let distanceKm: Double
}

enum CarToolbox {

    static func chargingStations(near query: String) -> [Station] {
        [
            Station(name: "IONITY Stuttgart-Zuffenhausen", operatorName: "IONITY", kW: 350, distanceKm: 1.2),
            Station(name: "EnBW HyperNetz Pragsattel", operatorName: "EnBW", kW: 300, distanceKm: 3.8),
            Station(name: "IONITY Sindelfingen Ost", operatorName: "IONITY", kW: 350, distanceKm: 14.5),
        ]
    }

    static func vehicleRange() -> (socPercent: Int, rangeKm: Int) {
        (socPercent: 20, rangeKm: 61)
    }

    static func weather(at place: String) -> String {
        "Mild in \(place): 18 °C, light clouds, dry roads, gentle breeze."
    }

    // MARK: Text renderings (what both engines receive as tool results)

    static func chargingStationsText(near query: String) -> String {
        chargingStations(near: query)
            .map { String(format: "%@ (%@) — %d kW, %.1f km away", $0.name, $0.operatorName, $0.kW, $0.distanceKm) }
            .joined(separator: "; ")
    }

    static func vehicleRangeText() -> String {
        let r = vehicleRange()
        return "Battery at \(r.socPercent)%, estimated remaining range \(r.rangeKm) km."
    }

    /// Dispatch by wire name. Returns nil for an unknown tool so the caller
    /// can surface the miss in the trace instead of hiding it.
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

// MARK: - The hand-rolled protocol for open-weight models

/// One entry in the trace timeline the Tools tab renders.
struct ToolTraceStep: Identifiable {
    enum Kind {
        case model, toolCall, toolResult, answer, failure
    }
    let id = UUID()
    let kind: Kind
    let title: String
    let detail: String
    let ok: Bool
}

struct ParsedToolCall {
    let name: String
    let arguments: [String: Any]
}

enum MLXToolProtocol {

    /// The whole "function calling" contract for the open-weight path is just
    /// this system prompt. No runtime support — the model either follows it or
    /// the trace shows it didn't.
    static let systemPrompt = """
    You are an in-car assistant. You can call these tools:
    - charging_stations(near: string) — list fast-charging stations near a place
    - vehicle_range() — current battery percent and remaining range in km
    - weather(at: string) — current weather at a place

    To call a tool, reply ONLY with one JSON object like \
    {"tool": "charging_stations", "arguments": {"near": "Stuttgart"}} and nothing else.
    When you have the information you need, reply with a short plain-language \
    answer for the driver (no JSON).
    """

    /// Pull `{"tool": ..., "arguments": {...}}` out of a model reply, if the
    /// reply is a tool call at all. Reuses the extraction stripper so `<think>`
    /// blocks and fences don't confuse the parser.
    static func parseToolCall(_ text: String) -> ParsedToolCall? {
        let cleaned = TicketValidator.strip(text)
        guard let data = cleaned.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let name = object["tool"] as? String
        else { return nil }
        return ParsedToolCall(name: name, arguments: object["arguments"] as? [String: Any] ?? [:])
    }
}

// MARK: - Apple FM tools (runtime-managed call loop)

#if canImport(FoundationModels)
import FoundationModels

@available(iOS 26.0, macOS 26.0, *)
struct ChargingStationsTool: Tool {
    let name = "chargingStations"
    let description = "Finds fast-charging stations near a location, with charging power and distance."
    let onEvent: @Sendable (String, String) -> Void

    @Generable
    struct Arguments {
        @Guide(description: "City or area to search near")
        var near: String
    }

    func call(arguments: Arguments) async throws -> String {
        let result = CarToolbox.chargingStationsText(near: arguments.near)
        onEvent("chargingStations(near: \"\(arguments.near)\")", result)
        return result
    }
}

@available(iOS 26.0, macOS 26.0, *)
struct VehicleRangeTool: Tool {
    let name = "vehicleRange"
    let description = "Reads the vehicle's current battery percentage and estimated remaining range."
    let onEvent: @Sendable (String, String) -> Void

    @Generable
    struct Arguments {}

    func call(arguments: Arguments) async throws -> String {
        let result = CarToolbox.vehicleRangeText()
        onEvent("vehicleRange()", result)
        return result
    }
}

@available(iOS 26.0, macOS 26.0, *)
struct WeatherTool: Tool {
    let name = "weather"
    let description = "Gets the current weather at a location."
    let onEvent: @Sendable (String, String) -> Void

    @Generable
    struct Arguments {
        @Guide(description: "The location to get weather for")
        var at: String
    }

    func call(arguments: Arguments) async throws -> String {
        let result = CarToolbox.weather(at: arguments.at)
        onEvent("weather(at: \"\(arguments.at)\")", result)
        return result
    }
}

@available(iOS 26.0, macOS 26.0, *)
@MainActor
private enum AFMToolSession {
    static func answer(prompt: String, onToolEvent: @escaping @Sendable (String, String) -> Void) async throws -> String {
        let session = LanguageModelSession(
            tools: [
                ChargingStationsTool(onEvent: onToolEvent),
                VehicleRangeTool(onEvent: onToolEvent),
                WeatherTool(onEvent: onToolEvent),
            ],
            instructions: "You are an in-car assistant. Use the tools to ground your answer, "
                + "then answer the driver in at most two short sentences.")
        do {
            return try await session.respond(to: prompt).content
        } catch let error as LanguageModelSession.GenerationError {
            throw EngineError(generationError: error)
        }
    }
}
#endif

/// Availability-safe facade so the Tools tab never touches FoundationModels types.
@MainActor
enum AFMToolFacade {
    static func answer(prompt: String, onToolEvent: @escaping @Sendable (String, String) -> Void) async throws -> String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            return try await AFMToolSession.answer(prompt: prompt, onToolEvent: onToolEvent)
        }
        #endif
        throw EngineError.other("Needs macOS 26 / iOS 26 + Apple Intelligence")
    }
}
