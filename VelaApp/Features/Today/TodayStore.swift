import Foundation
import SwiftUI

/// The smallest Today orchestration boundary.  It owns no persistence context,
/// platform store, or global service; those remain inside the injected reader and
/// effect adapters at the composition root.
@MainActor
final class TodayStore: ObservableObject {
    @Published private(set) var state: TodayViewState

    private let reader: any TodayReadingModule
    private let clock: any AppClock
    private let calendar: Calendar
    private let effects: any TodayEffectRouter
    /// A load is shared by all callers for the same health day.  Waiters are
    /// tracked independently so cancellation of one caller only releases its
    /// own continuation; the underlying reader task is cancelled only after
    /// the last waiter leaves (or an explicit date switch invalidates it).
    @MainActor
    private final class InFlightLoad {
        let token: UInt64
        let task: Task<TodayDashboardSnapshot, Error>
        var nextWaiterID: UInt64 = 0
        var waiterCount = 0
        var continuations: [UInt64: CheckedContinuation<TodayDashboardSnapshot, Error>] = [:]
        var cancelledWaiters: Set<UInt64> = []
        var result: Result<TodayDashboardSnapshot, Error>?

        init(token: UInt64, task: Task<TodayDashboardSnapshot, Error>) {
            self.token = token
            self.task = task
        }
    }
    private var inFlight: [Date: InFlightLoad] = [:]
    private var nextLoadToken: UInt64 = 0
    private var requestGeneration: UInt64 = 0
    private var lastStableState: TodayViewState

    init(
        reader: any TodayReadingModule,
        clock: any AppClock,
        calendar: Calendar,
        effects: any TodayEffectRouter = NoOpTodayEffectRouter()
    ) {
        self.reader = reader
        self.clock = clock
        self.calendar = calendar
        let day = calendar.startOfDay(for: clock.now)
        let initial = TodayViewState.initial(day: day)
        self.state = initial
        self.lastStableState = initial
        self.effects = effects
    }

    func send(_ action: TodayStoreAction) async {
        switch action {
        case .appear:
            await appear()
        case .selectDay(let day):
            await selectDay(day)
        case .refresh(let force):
            await loadCurrent(policy: force ? .force : .automatic)
        case .retry:
            await loadCurrent(policy: .automatic)
        case .openCalendar:
            await effects.openCalendar()
        case .openMetric(let metric):
            await effects.openMetric(metric)
        case .openEvidence:
            await effects.openEvidence()
        case .openPlan:
            await effects.openPlan()
        case .openSettings:
            await effects.openSettings()
        case .askCoach(let question):
            await effects.askCoach(question)
        case .startTraining:
            await effects.startTraining()
        case .openTrends:
            await effects.openTrends()
        case .openQuickCoach:
            await effects.openQuickCoach()
        case .requestWeather:
            state.weather = await effects.requestWeather() ?? .unavailable
        case .weatherLocationChanged:
            if let weather = await effects.refreshWeatherFromKnownLocation() {
                state.weather = weather
            }
        case .refreshCoverage:
            state.coverage = await effects.requestCoverage() ?? state.coverage
        case .trackDailyDecisionViewed(let bodyStateHash):
            await effects.trackDailyDecisionViewed(bodyStateHash: bodyStateHash)
        case .trackDailyDecisionAction(let bodyStateHash, let destination):
            await effects.trackDailyDecisionAction(
                bodyStateHash: bodyStateHash,
                destination: destination
            )
        case .setLivedStateAlignment(let alignment):
            await effects.saveLivedStateAlignment(alignment)
            state.livedState.alignment = alignment
        case .saveLivedState(let checkIn):
            await effects.saveLivedState(checkIn)
            state.livedState.checkIn = checkIn
        case .submitFeedback(let values):
            await effects.submitFeedback(values)
            state.feedback = TodayFeedbackProjection(isSubmitted: true, summary: values.note.isEmpty ? nil : values.note)
        }
    }

    private func appear() async {
        let day = state.selectedDay
        do {
            if let cached = try await reader.cached(for: day) {
                apply(
                    TodayViewState.projection(
                        snapshot: cached,
                        selectedDay: day,
                        now: clock.now,
                        calendar: calendar
                    ),
                    generation: requestGeneration
                )
            }
        } catch is CancellationError {
            return
        } catch {
            // A cache miss/failure is non-fatal; live load below is the source
            // of truth and will surface a real reader error if it fails too.
        }
        await loadCurrent(policy: .automatic)
    }

    private func selectDay(_ requestedDay: Date) async {
        let day = calendar.startOfDay(for: requestedDay)
        guard !calendar.isDate(day, inSameDayAs: calendar.startOfDay(for: clock.now)) || day <= clock.now else {
            state.error = .invalidDay
            state.phase = .failed(.invalidDay)
            return
        }
        guard day <= clock.now else {
            state.error = .invalidDay
            state.phase = .failed(.invalidDay)
            return
        }

        requestGeneration &+= 1
        let generation = requestGeneration
        state = TodayViewState.initial(day: day)
        lastStableState = state
        // Old tasks may finish, but their generation can no longer publish into
        // this selected day.  Cancellation is only an optimisation.
        let staleKeys = inFlight.keys.filter { $0 != day }
        for key in staleKeys {
            if let staleLoad = inFlight[key] {
                cancel(load: staleLoad, day: key)
            }
        }
        do {
            if let cached = try await reader.cached(for: day) {
                let projection = TodayViewState.projection(
                    snapshot: cached,
                    selectedDay: day,
                    now: clock.now,
                    calendar: calendar
                )
                apply(projection, generation: generation)
            }
        } catch is CancellationError {
            return
        } catch {
            // Continue to live load.  The live reader error is the actionable
            // failure and will preserve any stable state from this day.
        }
        await load(day: day, policy: .automatic, generation: generation)
    }

    private func loadCurrent(policy: TodayRefreshPolicy) async {
        await load(day: state.selectedDay, policy: policy, generation: requestGeneration)
    }

    private func load(day: Date, policy: TodayRefreshPolicy, generation: UInt64) async {
        guard generation == requestGeneration, day == state.selectedDay else { return }
        let previous = lastStableState
        state.phase = .loading(previous: previous.phase == .ready || previous.phase == .empty)
        state.error = nil

        let load: InFlightLoad
        if let existing = inFlight[day] {
            load = existing
        } else {
            let reader = self.reader
            let task = Task { @MainActor in
                try await reader.load(for: day, policy: policy)
            }
            nextLoadToken &+= 1
            load = InFlightLoad(token: nextLoadToken, task: task)
            inFlight[day] = load
            observeCompletion(of: load)
        }

        let waiterID = reserveWaiter(on: load)
        defer { releaseWaiter(day: day, load: load, waiterID: waiterID) }

        do {
            let snapshot = try await withTaskCancellationHandler(operation: {
                try await withCheckedThrowingContinuation { continuation in
                    register(
                        continuation,
                        day: day,
                        load: load,
                        waiterID: waiterID
                    )
                }
            }, onCancel: {
                // Cancellation is scoped to this caller.  The actor hop keeps
                // continuation removal serialized with completion and date
                // selection, while the shared reader task remains alive for
                // any other waiter.
                Task { @MainActor [weak self] in
                    self?.cancelWaiter(day: day, load: load, waiterID: waiterID)
                }
            })
            try Task.checkCancellation()
            guard generation == requestGeneration, day == state.selectedDay else { return }
            let projected = TodayViewState.projection(
                snapshot: snapshot,
                selectedDay: day,
                now: clock.now,
                calendar: calendar
            )
            apply(projected, generation: generation)
        } catch is CancellationError {
            guard generation == requestGeneration, day == state.selectedDay else { return }
            state = lastStableState
        } catch {
            guard generation == requestGeneration, day == state.selectedDay else { return }
            state.error = .reader(error.localizedDescription)
            state.phase = .failed(state.error!)
        }
    }

    private func apply(_ projected: TodayViewState, generation: UInt64) {
        guard generation == requestGeneration, projected.selectedDay == state.selectedDay else { return }
        state = projected
        lastStableState = projected
    }

    private func reserveWaiter(on load: InFlightLoad) -> UInt64 {
        load.nextWaiterID &+= 1
        load.waiterCount += 1
        return load.nextWaiterID
    }

    private func register(
        _ continuation: CheckedContinuation<TodayDashboardSnapshot, Error>,
        day: Date,
        load: InFlightLoad,
        waiterID: UInt64
    ) {
        if load.cancelledWaiters.remove(waiterID) != nil {
            continuation.resume(throwing: CancellationError())
            return
        }
        if let result = load.result {
            continuation.resume(with: result)
            return
        }
        guard inFlight[day]?.token == load.token else {
            continuation.resume(throwing: CancellationError())
            return
        }
        load.continuations[waiterID] = continuation
        if Task.isCancelled {
            cancelWaiter(day: day, load: load, waiterID: waiterID)
        }
    }

    private func cancelWaiter(day: Date, load: InFlightLoad, waiterID: UInt64) {
        guard load.result == nil else { return }
        load.cancelledWaiters.insert(waiterID)
        if let continuation = load.continuations.removeValue(forKey: waiterID) {
            continuation.resume(throwing: CancellationError())
        }
    }

    private func releaseWaiter(day: Date, load: InFlightLoad, waiterID: UInt64) {
        load.continuations.removeValue(forKey: waiterID)
        load.cancelledWaiters.remove(waiterID)
        guard load.waiterCount > 0 else { return }
        load.waiterCount -= 1
        guard load.waiterCount == 0, load.result == nil else { return }
        cancel(load: load, day: day)
    }

    private func cancel(load: InFlightLoad, day: Date) {
        guard load.result == nil else { return }
        load.task.cancel()
        finish(load: load, result: .failure(CancellationError()))
        guard inFlight[day]?.token == load.token else { return }
        inFlight[day] = nil
    }

    private func observeCompletion(of load: InFlightLoad) {
        Task { @MainActor [weak self, load] in
            let result: Result<TodayDashboardSnapshot, Error>
            do {
                result = .success(try await load.task.value)
            } catch {
                result = .failure(error)
            }
            self?.finish(load: load, result: result)
        }
    }

    private func finish(load: InFlightLoad, result: Result<TodayDashboardSnapshot, Error>) {
        guard load.result == nil else { return }
        load.result = result
        let continuations = load.continuations
        load.continuations.removeAll()
        for continuation in continuations.values {
            continuation.resume(with: result)
        }
        if let day = inFlight.first(where: { $0.value === load })?.key {
            inFlight[day] = nil
        }
    }
}
