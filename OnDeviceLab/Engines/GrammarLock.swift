import Foundation
import JSONSchema

// ════════════════════════════════════════════════════════════════════════════
//  GRAMMAR LOCK — the open-weight mirror of Apple's @Generable.
//
//  mlx-swift-structured (XGrammar) masks the logits during sampling so only tokens
//  that keep the output valid against a JSON schema can be chosen. Malformed JSON is
//  impossible — the same guarantee Round 2 says both sides can have. The Extract and
//  Tools tabs use these schemas so the open models call as cleanly as AFM's runtime.
// ════════════════════════════════════════════════════════════════════════════

enum GrammarLock {

    /// Charging-receipt schema — the six fields the Extract tab pulls. All required:
    /// the demo receipt carries every field, so a full, valid object is guaranteed.
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

    /// The four tool names the model may choose. `final_answer` ends the loop.
    static let toolNames = ["charging_stations", "vehicle_range", "weather", "final_answer"]

    /// One constrained tool call: `tool` can only be one of the allowed names, so a bad
    /// name or a non-JSON reply is impossible. `near`/`at` are the tool args; `answer`
    /// carries the grounded reply on `final_answer`.
    static let toolCallSchema = JSONSchema.object(
        description: "A single in-car assistant tool call",
        properties: [
            "tool": .enum(values: toolNames.map { .string($0) }),
            "near": .string(),
            "at": .string(),
            "answer": .string(),
        ],
        required: ["tool"]
    )

    /// Schema for the forced terminal answer (used when the model loops or hits the hop cap).
    static let finalAnswerSchema = JSONSchema.object(
        description: "Final grounded answer for the driver",
        properties: ["answer": .string()],
        required: ["answer"]
    )

    static let toolSystem = """
        You are an in-car assistant with these tools: charging_stations(near), \
        vehicle_range(), weather(at). Each turn emit one tool call. Fill near for \
        charging_stations, at for weather. After TOOL RESULT lines, either call another \
        tool or set tool=final_answer with a short grounded answer. Ground every fact in \
        the tool results; never invent values.
        """
}

/// One decoded constrained tool call (matches `GrammarLock.toolCallSchema`).
struct ToolCall: Codable, Sendable {
    let tool: String
    let near: String?
    let at: String?
    let answer: String?
}

/// The forced terminal answer (matches `GrammarLock.finalAnswerSchema`).
struct FinalAnswer: Codable, Sendable {
    let answer: String
}
