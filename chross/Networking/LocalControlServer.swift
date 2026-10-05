import AppKit
import Foundation
import Network
import SwiftData

/// A minimal HTTP server bound to the loopback interface only, so the Chross Chrome
/// extension can show live session progress and add sites without any native-messaging
/// host to install — the extension just does `fetch("http://127.0.0.1:<port>/...")`.
@MainActor
final class LocalControlServer {
    static let port: UInt16 = 52847

    private var listener: NWListener?
    private weak var tracker: ActivityTracker?
    private weak var coordinator: SessionCoordinator?
    private var modelContext: ModelContext?

    func start(tracker: ActivityTracker, coordinator: SessionCoordinator, modelContext: ModelContext) {
        guard listener == nil else { return }
        self.tracker = tracker
        self.coordinator = coordinator
        self.modelContext = modelContext

        guard let port = NWEndpoint.Port(rawValue: Self.port) else { return }
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: port)
        parameters.allowLocalEndpointReuse = true

        guard let listener = try? NWListener(using: parameters) else { return }
        listener.newConnectionHandler = { [weak self] connection in
            Task { @MainActor [weak self] in
                self?.accept(connection)
            }
        }
        listener.start(queue: .main)
        self.listener = listener
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: .main)
        receive(on: connection, buffer: Data())
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                var buffer = buffer
                if let data, !data.isEmpty { buffer.append(data) }

                if let request = HTTPRequestParser.parse(buffer) {
                    self.handle(request, on: connection)
                    return
                }
                if isComplete || error != nil {
                    connection.cancel()
                    return
                }
                self.receive(on: connection, buffer: buffer)
            }
        }
    }

    private func handle(_ request: HTTPRequest, on connection: NWConnection) {
        if request.method == "OPTIONS" {
            respondOptions(connection)
            return
        }

        guard let tracker, let coordinator, let modelContext else {
            respond(connection, status: 503, json: ["error": "not ready"])
            return
        }

        switch (request.method, request.path) {
        case ("GET", "/status"):
            respond(connection, status: 200, json: statusPayload(tracker: tracker, coordinator: coordinator, modelContext: modelContext))

        case ("POST", "/session/start"):
            if !tracker.isRunning {
                var projectName = "Session Chrome"
                var presetName: String?
                if let body = try? JSONSerialization.jsonObject(with: request.body) as? [String: Any] {
                    if let name = body["projectName"] as? String, !name.trimmingCharacters(in: .whitespaces).isEmpty {
                        projectName = name.trimmingCharacters(in: .whitespaces)
                    }
                    if let pName = body["presetName"] as? String, !pName.isEmpty {
                        presetName = pName
                    }
                }

                if let presetName,
                   let presets = try? modelContext.fetch(FetchDescriptor<Preset>()),
                   let matching = presets.first(where: { $0.name == presetName }) {
                    coordinator.startSession(fromPreset: matching, tracker: tracker, modelContext: modelContext)
                } else {
                    coordinator.startQuickSession(tracker: tracker, projectName: projectName, modelContext: modelContext)
                }
            }
            respond(connection, status: 200, json: statusPayload(tracker: tracker, coordinator: coordinator, modelContext: modelContext))

        case ("POST", "/session/pause"):
            if tracker.isRunning && !tracker.isPaused {
                tracker.pauseManually()
            }
            respond(connection, status: 200, json: statusPayload(tracker: tracker, coordinator: coordinator, modelContext: modelContext))

        case ("POST", "/session/resume"):
            if tracker.isRunning && tracker.isPaused {
                tracker.resumeManually()
            }
            respond(connection, status: 200, json: statusPayload(tracker: tracker, coordinator: coordinator, modelContext: modelContext))

        case ("POST", "/session/toggle-pause"):
            if tracker.isRunning {
                if tracker.isPaused {
                    tracker.resumeManually()
                } else {
                    tracker.pauseManually()
                }
            }
            respond(connection, status: 200, json: statusPayload(tracker: tracker, coordinator: coordinator, modelContext: modelContext))

        case ("POST", "/session/stop"):
            coordinator.stopAndFinalizeWithoutBilling(tracker: tracker, modelContext: modelContext)
            respond(connection, status: 200, json: statusPayload(tracker: tracker, coordinator: coordinator, modelContext: modelContext))

        case ("POST", "/session/sites"):
            if let body = try? JSONSerialization.jsonObject(with: request.body) as? [String: Any],
               let urlString = body["url"] as? String,
               let domain = DomainNormalizer.normalize(urlString) {
                coordinator.addDeclaredItem(TrackedItem(kind: .website, key: domain, displayName: domain), tracker: tracker)
            }
            respond(connection, status: 200, json: statusPayload(tracker: tracker, coordinator: coordinator, modelContext: modelContext))

        case ("POST", "/session/sites/remove"), ("DELETE", "/session/sites"):
            if let body = try? JSONSerialization.jsonObject(with: request.body) as? [String: Any] {
                let targetDomain: String? = {
                    if let key = body["key"] as? String { return DomainNormalizer.normalize(key) }
                    if let url = body["url"] as? String { return DomainNormalizer.normalize(url) }
                    return nil
                }()
                if let targetDomain {
                    coordinator.removeDeclaredItem(TrackedItem(kind: .website, key: targetDomain, displayName: targetDomain), tracker: tracker)
                }
            }
            respond(connection, status: 200, json: statusPayload(tracker: tracker, coordinator: coordinator, modelContext: modelContext))

        case ("POST", "/activate-app"):
            NSApp.activate(ignoringOtherApps: true)
            respond(connection, status: 200, json: ["status": "activated"])

        default:
            respond(connection, status: 404, json: ["error": "not found"])
        }
    }

    private func statusPayload(tracker: ActivityTracker, coordinator: SessionCoordinator, modelContext: ModelContext) -> [String: Any] {
        let allSessions = (try? modelContext.fetch(FetchDescriptor<WorkSession>())) ?? []
        let todayPersisted = allSessions
            .filter { Calendar.current.isDateInToday($0.startDate) }
            .reduce(0) { $0 + $1.activeSeconds }
        let todaySeconds = todayPersisted + (tracker.isRunning ? tracker.elapsed : 0)
        let goalHours = UserDefaults.standard.double(forKey: AppPreferences.dailyGoalHoursKey)
        let presets = (try? modelContext.fetch(FetchDescriptor<Preset>()))?.map(\.name) ?? []

        return [
            "isRunning": tracker.isRunning,
            "isPaused": tracker.isPaused,
            "isOutOfScope": tracker.isOutOfScope,
            "isManuallyPaused": tracker.isManuallyPaused,
            "projectName": coordinator.runningProjectName ?? "",
            "elapsedSeconds": tracker.elapsed,
            "idleSeconds": tracker.liveIdleSeconds,
            "outOfScopeSeconds": tracker.liveOutOfScopeSeconds,
            "currentAppName": tracker.currentAppName ?? "",
            "currentDetail": tracker.currentDetail ?? "",
            "sites": tracker.declaredWebsites.map { ["key": $0.key, "displayName": $0.displayName] },
            "presets": presets,
            "todaySeconds": todaySeconds,
            "dailyGoalHours": goalHours == 0 ? AppPreferences.defaultDailyGoalHours : goalHours,
        ]
    }

    private func respondOptions(_ connection: NWConnection) {
        var head = "HTTP/1.1 204 No Content\r\n"
        head += "Access-Control-Allow-Origin: *\r\n"
        head += "Access-Control-Allow-Methods: GET, POST, DELETE, OPTIONS\r\n"
        head += "Access-Control-Allow-Headers: Content-Type, Accept\r\n"
        head += "Access-Control-Max-Age: 86400\r\n"
        head += "Content-Length: 0\r\n"
        head += "Connection: close\r\n\r\n"
        let response = Data(head.utf8)
        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func respond(_ connection: NWConnection, status: Int, json: [String: Any]) {
        let body = (try? JSONSerialization.data(withJSONObject: json)) ?? Data("{}".utf8)
        let statusText = switch status {
        case 200: "OK"
        case 404: "Not Found"
        default: "Service Unavailable"
        }
        var head = "HTTP/1.1 \(status) \(statusText)\r\n"
        head += "Content-Type: application/json\r\n"
        head += "Content-Length: \(body.count)\r\n"
        head += "Access-Control-Allow-Origin: *\r\n"
        head += "Access-Control-Allow-Methods: GET, POST, DELETE, OPTIONS\r\n"
        head += "Access-Control-Allow-Headers: Content-Type, Accept\r\n"
        head += "Connection: close\r\n\r\n"

        var response = Data(head.utf8)
        response.append(body)
        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}

struct HTTPRequest: Equatable {
    let method: String
    let path: String
    let body: Data
}

/// Parses just enough HTTP/1.1 to serve `LocalControlServer`'s routes —
/// not a general-purpose parser, since the only client is the Chross extension itself.
enum HTTPRequestParser {
    static func parse(_ data: Data) -> HTTPRequest? {
        guard let headerEnd = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        guard let headerString = String(data: data[data.startIndex..<headerEnd.lowerBound], encoding: .utf8) else { return nil }
        let lines = headerString.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let parts = requestLine.components(separatedBy: " ")
        guard parts.count >= 2 else { return nil }

        var contentLength = 0
        for line in lines.dropFirst() where line.lowercased().hasPrefix("content-length:") {
            let value = line.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)
            contentLength = Int(value) ?? 0
        }

        let bodyData = data[headerEnd.upperBound...]
        guard bodyData.count >= contentLength else { return nil }
        return HTTPRequest(method: parts[0], path: parts[1], body: Data(bodyData.prefix(contentLength)))
    }
}
