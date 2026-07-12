import Network
import Foundation

class HookListener {
    var onEvent: ((CompanionState, String, String, String) -> Void)?
    private var listener: NWListener?

    func start() {
        do {
            listener = try NWListener(using: .tcp, on: 47291)
            listener?.newConnectionHandler = { [weak self] conn in self?.handle(conn) }
            listener?.start(queue: .global(qos: .background))
        } catch {
            print("HookListener failed to start: \(error)")
        }
    }

    private func handle(_ conn: NWConnection) {
        conn.start(queue: .global(qos: .background))
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, _ in
            defer { conn.cancel() }
            guard let self,
                  let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let stateStr = json["state"] as? String,
                  let state = CompanionState(rawValue: stateStr) else { return }
            let msg = json["message"] as? String ?? ""
            let sessionId = json["session_id"] as? String ?? ""
            let cwd = json["cwd"] as? String ?? ""
            // First hook event means Claude Code was restarted — clear the setup banner
            DispatchQueue.main.async {
                UserDefaults.standard.set(false, forKey: "hooksJustInstalled")
            }
            self.onEvent?(state, msg, sessionId, cwd)
        }
    }
}
