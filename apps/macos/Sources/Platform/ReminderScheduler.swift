import Foundation

@MainActor
final class ReminderScheduler {
    private var task: Task<Void, Never>?
    func cancel() { task?.cancel(); task = nil }
    func schedule(at date: Date?, generation: UInt64, fire: @escaping @MainActor (UInt64) -> Void) {
        cancel(); guard let date else { return }
        let seconds = max(0.1, date.timeIntervalSinceNow)
        task = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: UInt64(min(seconds, 8 * 24 * 3600) * 1_000_000_000)) }
            catch { return }
            guard !Task.isCancelled, self != nil else { return }; fire(generation)
        }
    }
}
