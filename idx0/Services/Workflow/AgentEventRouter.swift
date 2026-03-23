import Foundation

struct AgentEventRouter {
    func decodeEnvelope(from requestPayload: [String: String]) throws -> AgentEventEnvelope {
        guard let rawEnvelope = requestPayload["envelope"], !rawEnvelope.isEmpty else {
            throw NSError(domain: "idx0.AgentEventRouter", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing envelope payload"])
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(AgentEventEnvelope.self, from: Data(rawEnvelope.utf8))
    }
}
