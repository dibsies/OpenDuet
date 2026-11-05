/// Replaces unsent intermediate values while retaining order between controls.
struct ControlUpdateQueue {
    private var order: [String] = []
    private var pending: [String: [[String]]] = [:]
    var isEmpty: Bool { order.isEmpty }
    mutating func put(_ key: String, commands: [[String]]) {
        if pending[key] == nil { order.append(key) }
        pending[key] = commands
    }
    mutating func take() -> [[String]]? {
        guard !order.isEmpty else { return nil }
        return pending.removeValue(forKey: order.removeFirst())
    }
    mutating func clear() { order.removeAll(); pending.removeAll() }
}
