import Foundation

// ════════════════════════════════════════════════════════════════════════════
//  TOOL CALLING — three canned, deterministic car tools
//
//  Both engines call the same `CarToolbox`. AFM gets real Tool-protocol
//  structs (the runtime does the call loop); the open-weight path runs a
//  grammar-locked JSON loop (`GrammarLock` + MLXEngine.structured), so both
//  sides carry the same "no malformed call" guarantee.
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
    ///
    /// ── MILESTONE 4a · TOOL IT (open-weight path) ────────────────────────────
    /// The grammar lock guarantees a *valid* call — but nobody runs it for you.
    /// The open-weight loop is yours, and THIS is its routing table (vs Apple's
    /// Tool structs, where the runtime dispatches — that's 4b). Route the wire
    /// names "charging_stations", "vehicle_range" and "weather" to the toolbox
    /// functions above (`near`/`at` arrive in `arguments`; default to "Stuttgart").
    ///
    /// Until you do, every tool call on the Tools tab dead-ends as "unknown
    /// tool — not in the toolbox". Stuck? Build the "OnDeviceLab (Solution)"
    /// scheme (reference in Solutions/Solutions.swift).
    /// ─────────────────────────────────────────────────────────────────────────
    #if !SOLUTION
    static func dispatch(name: String, arguments: [String: Any]) -> String? {
        // TODO 4a — switch on `name`, call the matching CarToolbox function,
        //   return its text. Keep nil for anything you don't recognize.
        _ = arguments
        return nil
    }
    #endif
}

// MARK: - Trace timeline

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

    /// ── MILESTONE 4b · TOOL IT (Apple FM path) ──────────────────────────────
    /// The mirror of 4a: no hand-rolled protocol. A tool is a typed struct — the
    /// `@Generable Arguments` (above) let the runtime fill them and run the call
    /// loop for you; you just implement the body. `ChargingStationsTool` and
    /// `VehicleRangeTool` (also in this file) are done for reference. Do the same
    /// for weather: read the toolbox, fire `onEvent` for the trace, return the
    /// result. Runs on macOS 26; you write it on any Xcode 26. Stuck? Build the
    /// "OnDeviceLab (Solution)" scheme (reference lives in Solutions/Solutions.swift).
    /// ─────────────────────────────────────────────────────────────────────────
    #if !SOLUTION
    func call(arguments: Arguments) async throws -> String {
        // TODO 4b — return `CarToolbox.weather(at: arguments.at)`, and call
        //   `onEvent("weather(at: \"\(arguments.at)\")", result)` first so the hop
        //   shows up in the trace (see ChargingStationsTool / VehicleRangeTool).
        onEvent("weather(at: \"\(arguments.at)\")", "TODO 4b — not implemented")
        return "TODO 4b — WeatherTool.call not implemented"
    }
    #endif
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
            // Same sampling and per-answer token cap as the grammar-locked MLX loop.
            return try await session.respond(
                to: prompt,
                options: GenerationOptions(temperature: 0.3, maximumResponseTokens: 200)).content
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
