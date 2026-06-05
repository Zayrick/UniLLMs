//
//  ChatRuntimeTests.swift
//  UniLLMsTests
//

import Foundation
import XCTest
@testable import UniLLMs

@MainActor
final class ChatRuntimeTests: LLMsProviderStoreTestCase {
    func testPrivateConversationDoesNotPersistSuccessfulTurn() async throws {
        let adapter = CapturingRuntimeProvider()
        let (runtime, historyStore) = makeRuntime(
            adapter: adapter,
            systemPromptStore: InMemorySystemPromptStore(prompts: [])
        )

        runtime.resetConversation(privacyMode: true)
        XCTAssertTrue(runtime.isPrivacyModeEnabled)

        let stream = try runtime.startTurn(prompt: "Keep this private")
        for try await _ in stream {}
        await runtime.waitForPendingHistoryPersistence()

        XCTAssertEqual(adapter.requests.count, 1)
        let sessions = try await historyStore.fetchSessions()
        XCTAssertTrue(sessions.isEmpty)
    }

    func testHistoryPersistenceFailureReportsError() async throws {
        let adapter = CapturingRuntimeProvider()
        let failingHistoryStore = FailingRuntimeHistoryStore(error: RuntimeHistoryPersistenceError.sample)
        var failureDescriptions: [String] = []
        let (runtime, _) = makeRuntime(
            adapter: adapter,
            systemPromptStore: InMemorySystemPromptStore(prompts: []),
            historyStore: failingHistoryStore
        )
        runtime.setHistoryPersistenceFailureHandler { error in
            failureDescriptions.append(error.localizedDescription)
        }

        let stream = try runtime.startTurn(prompt: "Save this")
        for try await _ in stream {}
        await runtime.waitForPendingHistoryPersistence()

        XCTAssertEqual(
            failureDescriptions,
            [
                RuntimeHistoryPersistenceError.sample.localizedDescription,
                RuntimeHistoryPersistenceError.sample.localizedDescription
            ]
        )
    }

    func testStartingPrivateConversationLeavesExistingHistoryIntact() async throws {
        let adapter = CapturingRuntimeProvider()
        let (runtime, historyStore) = makeRuntime(
            adapter: adapter,
            systemPromptStore: InMemorySystemPromptStore(prompts: [])
        )

        let normalTurn = try runtime.startTurn(prompt: "Save this")
        for try await _ in normalTurn {}
        await runtime.waitForPendingHistoryPersistence()

        let savedSessions = try await historyStore.fetchSessions()
        let savedSession = try XCTUnwrap(savedSessions.first)

        runtime.resetConversation(privacyMode: true)
        let privateTurn = try runtime.startTurn(prompt: "Do not save this")
        for try await _ in privateTurn {}
        await runtime.waitForPendingHistoryPersistence()

        let sessions = try await historyStore.fetchSessions()
        XCTAssertEqual(sessions, [savedSession])
        let events = try await historyStore.fetchEvents(sessionID: savedSession.id)
        XCTAssertEqual(ChatTimelineEvent.messages(from: events).map(\.content), ["Save this", "Done."])
    }

    func testSelectingSystemPromptWithoutMessagesDoesNotCreateHistorySession() async throws {
        let prompt = makePrompt(title: "Translator", content: "Always answer in Chinese.")
        let promptStore = InMemorySystemPromptStore(prompts: [prompt])
        let (runtime, historyStore) = makeRuntime(
            adapter: EmptyRuntimeProvider(),
            systemPromptStore: promptStore
        )

        runtime.selectSystemPrompt(id: prompt.id)
        await runtime.waitForPendingHistoryPersistence()

        XCTAssertEqual(runtime.selectedSystemPromptID, prompt.id)
        let sessions = try await historyStore.fetchSessions()
        XCTAssertTrue(sessions.isEmpty)
    }

    func testFailedFirstTurnWithSystemPromptClearsOptimisticHistoryEvent() async throws {
        let prompt = makePrompt(title: "Translator", content: "Always answer in Chinese.")
        let promptStore = InMemorySystemPromptStore(prompts: [prompt])
        let (runtime, historyStore) = makeRuntime(
            adapter: FailingRuntimeProvider(),
            systemPromptStore: promptStore
        )

        runtime.selectSystemPrompt(id: prompt.id)
        let stream = try runtime.startTurn(prompt: "Hello")
        do {
            for try await _ in stream {}
            XCTFail("Expected the provider failure to propagate.")
        } catch {
            XCTAssertEqual(error.localizedDescription, "Provider failed before streaming.")
        }
        await runtime.waitForPendingHistoryPersistence()

        let sessions = try await historyStore.fetchSessions()
        XCTAssertTrue(sessions.isEmpty)
    }

    func testFailedFirstTurnAllowsNextTurnAndRemovesFailedUserMessage() async throws {
        let adapter = SequencedRuntimeProvider(steps: [
            .failBeforeStreaming,
            .succeed(content: "Recovered.")
        ])
        let (runtime, historyStore) = makeRuntime(
            adapter: adapter,
            systemPromptStore: InMemorySystemPromptStore(prompts: [])
        )

        let failedStream = try runtime.startTurn(prompt: "First")
        do {
            for try await _ in failedStream {}
            XCTFail("Expected first provider stream to fail.")
        } catch {
            XCTAssertEqual(error.localizedDescription, "Provider failed before streaming.")
        }

        let recoveredStream = try runtime.startTurn(prompt: "Second")
        var recoveredContent = ""
        for try await delta in recoveredStream {
            recoveredContent += delta.content
        }
        await runtime.waitForPendingHistoryPersistence()

        XCTAssertEqual(recoveredContent, "Recovered.")
        XCTAssertEqual(adapter.requests.map { $0.messages.last?.content }, ["First", "Second"])
        let events = try await historyStore.fetchEvents(sessionID: runtime.currentSessionID)
        let messages = ChatTimelineEvent.messages(from: events)
        XCTAssertEqual(messages.map(\.content), ["Second", "Recovered."])
    }

    func testFailedTurnAfterPersistableProgressKeepsPartialResponseAndAllowsNextTurn() async throws {
        let adapter = SequencedRuntimeProvider(steps: [
            .yieldThenFail(content: "Partial."),
            .succeed(content: "Recovered.")
        ])
        let (runtime, historyStore) = makeRuntime(
            adapter: adapter,
            systemPromptStore: InMemorySystemPromptStore(prompts: [])
        )

        let failedStream = try runtime.startTurn(prompt: "First")
        var partialContent = ""
        do {
            for try await delta in failedStream {
                partialContent += delta.content
            }
            XCTFail("Expected first provider stream to fail after partial progress.")
        } catch {
            XCTAssertEqual(error.localizedDescription, "Provider failed before streaming.")
        }

        let recoveredStream = try runtime.startTurn(prompt: "Second")
        var recoveredContent = ""
        for try await delta in recoveredStream {
            recoveredContent += delta.content
        }
        await runtime.waitForPendingHistoryPersistence()

        XCTAssertEqual(partialContent, "Partial.")
        XCTAssertEqual(recoveredContent, "Recovered.")
        let events = try await historyStore.fetchEvents(sessionID: runtime.currentSessionID)
        let messages = ChatTimelineEvent.messages(from: events)
        XCTAssertEqual(messages.map(\.content), [
            "First",
            "Partial.",
            "Second",
            "Recovered."
        ])
    }

    func testSuccessfulFirstTurnWithSystemPromptSendsPromptAndPersistsSelection() async throws {
        let prompt = makePrompt(title: "Translator", content: "Always answer in Chinese.")
        let promptStore = InMemorySystemPromptStore(prompts: [prompt])
        let adapter = CapturingRuntimeProvider()
        let (runtime, historyStore) = makeRuntime(
            adapter: adapter,
            systemPromptStore: promptStore
        )

        runtime.selectSystemPrompt(id: prompt.id)
        let stream = try runtime.startTurn(prompt: "Hello")
        var content = ""
        for try await delta in stream {
            content += delta.content
        }
        await runtime.waitForPendingHistoryPersistence()

        XCTAssertEqual(content, "Done.")
        let requests = adapter.requests
        XCTAssertEqual(requests.count, 1)
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.context.systemPrompt, prompt)
        XCTAssertEqual(request.messages.map(\.role), [.user])
        let userMessage = try XCTUnwrap(request.messages.first)
        XCTAssertEqual(userMessage.content, "Hello")

        let sessions = try await historyStore.fetchSessions()
        let session = try XCTUnwrap(sessions.first)
        XCTAssertEqual(session.selectedSystemPromptID, prompt.id)
    }

    func testSuccessfulTurnUsesInjectedClockForSessionAndTimelineTimestamps() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let adapter = CapturingRuntimeProvider()
        let (runtime, historyStore) = makeRuntime(
            adapter: adapter,
            systemPromptStore: InMemorySystemPromptStore(prompts: []),
            clock: FixedClock(now: now)
        )

        let stream = try runtime.startTurn(prompt: "Clocked")
        for try await _ in stream {}
        await runtime.waitForPendingHistoryPersistence()

        let sessions = try await historyStore.fetchSessions()
        let session = try XCTUnwrap(sessions.first)
        let events = try await historyStore.fetchEvents(sessionID: runtime.currentSessionID)
        XCTAssertEqual(session.createdAt, now)
        XCTAssertEqual(session.updatedAt, now)
        XCTAssertEqual(events.map(\.timestamp), [now, now])
    }

    func testSelectingSystemPromptDuringActiveTurnUpdatesNextTurnSelectionOnly() async throws {
        let firstPrompt = makePrompt(title: "First", content: "Use the first prompt.")
        let secondPrompt = makePrompt(title: "Second", content: "Use the second prompt.")
        let promptStore = InMemorySystemPromptStore(prompts: [firstPrompt, secondPrompt])
        let adapter = SuspendedRuntimeProvider()
        let (runtime, historyStore) = makeRuntime(
            adapter: adapter,
            systemPromptStore: promptStore
        )

        runtime.selectSystemPrompt(id: firstPrompt.id)
        let stream = try runtime.startTurn(prompt: "Hello")
        await adapter.waitForRequestCount(1)

        runtime.selectSystemPrompt(id: secondPrompt.id)
        XCTAssertEqual(runtime.selectedSystemPromptID, secondPrompt.id)

        adapter.finish()
        for try await _ in stream {}
        await runtime.waitForPendingHistoryPersistence()

        let request = try XCTUnwrap(adapter.requests.first)
        XCTAssertEqual(request.context.systemPrompt, firstPrompt)
        let sessions = try await historyStore.fetchSessions()
        let session = try XCTUnwrap(sessions.first)
        XCTAssertEqual(session.selectedSystemPromptID, secondPrompt.id)
    }

    func testEditingPriorUserMessageResendsFromThatPointOnly() async throws {
        let adapter = CapturingRuntimeProvider()
        let (runtime, historyStore) = makeRuntime(
            adapter: adapter,
            systemPromptStore: InMemorySystemPromptStore(prompts: [])
        )
        let secondMessageID = UUID()

        let firstTurn = try runtime.startTurn(prompt: "First")
        for try await _ in firstTurn {}
        let secondTurn = try runtime.startTurn(
            prompt: "Second",
            userMessageID: secondMessageID
        )
        for try await _ in secondTurn {}
        let thirdTurn = try runtime.startTurn(prompt: "Third")
        for try await _ in thirdTurn {}

        let replacementTurn = try runtime.startTurn(
            prompt: "Edited second",
            userMessageID: secondMessageID,
            replacingUserMessageID: secondMessageID
        )
        for try await _ in replacementTurn {}
        await runtime.waitForPendingHistoryPersistence()

        let replacementRequest = try XCTUnwrap(adapter.requests.last)
        XCTAssertEqual(replacementRequest.messages.map(\.role), [.user, .assistant, .user])
        XCTAssertEqual(replacementRequest.messages.map(\.content), ["First", "Done.", "Edited second"])

        let events = try await historyStore.fetchEvents(sessionID: runtime.currentSessionID)
        let messages = ChatTimelineEvent.messages(from: events)
        XCTAssertEqual(messages.map(\.role), [.user, .assistant, .user, .assistant])
        XCTAssertEqual(messages.map(\.content), ["First", "Done.", "Edited second", "Done."])
        XCTAssertEqual(messages[2].id, secondMessageID)

        let revisions = try XCTUnwrap(ChatTimelineEvent.messageRevisions(from: events)[secondMessageID])
        XCTAssertEqual(revisions.count, 1)
        XCTAssertEqual(revisions.first?.events.count, 4)
        guard let archivedFirstEvent = revisions.first?.events.first,
              case let .userMessage(archivedText) = archivedFirstEvent.kind else {
            XCTFail("Expected the archived branch to start with the replaced user message.")
            return
        }
        XCTAssertEqual(archivedText, "Second")
    }

    func testEditingMissingUserMessageThrowsBeforeProviderRequest() throws {
        let adapter = CapturingRuntimeProvider()
        let (runtime, _) = makeRuntime(
            adapter: adapter,
            systemPromptStore: InMemorySystemPromptStore(prompts: [])
        )

        XCTAssertThrowsError(
            try runtime.startTurn(
                prompt: "Edited missing",
                replacingUserMessageID: UUID()
            )
        ) { error in
            XCTAssertEqual(error as? ChatRuntimeError, .userMessageNotFound)
        }
        XCTAssertTrue(adapter.requests.isEmpty)
    }

    func testResendingOriginalUserMessageArchivesCurrentBranch() async throws {
        let adapter = CapturingRuntimeProvider()
        let (runtime, historyStore) = makeRuntime(
            adapter: adapter,
            systemPromptStore: InMemorySystemPromptStore(prompts: [])
        )
        let messageID = UUID()

        let firstTurn = try runtime.startTurn(
            prompt: "Repeat this",
            userMessageID: messageID
        )
        for try await _ in firstTurn {}
        let resendTurn = try runtime.startTurn(
            prompt: "Repeat this",
            userMessageID: messageID,
            replacingUserMessageID: messageID
        )
        for try await _ in resendTurn {}
        await runtime.waitForPendingHistoryPersistence()

        XCTAssertEqual(adapter.requests.count, 2)
        let resendRequest = try XCTUnwrap(adapter.requests.last)
        XCTAssertEqual(resendRequest.messages.map(\.content), ["Repeat this"])

        let events = try await historyStore.fetchEvents(sessionID: runtime.currentSessionID)
        let messages = ChatTimelineEvent.messages(from: events)
        XCTAssertEqual(messages.map(\.content), ["Repeat this", "Done."])
        XCTAssertEqual(messages.first?.id, messageID)

        let revisions = try XCTUnwrap(ChatTimelineEvent.messageRevisions(from: events)[messageID])
        XCTAssertEqual(revisions.count, 1)
        XCTAssertEqual(revisions.first?.firstUserMessageText, "Repeat this")
    }

    func testSwitchingToMessageRevisionArchivesCurrentBranch() async throws {
        let adapter = CapturingRuntimeProvider()
        let (runtime, historyStore) = makeRuntime(
            adapter: adapter,
            systemPromptStore: InMemorySystemPromptStore(prompts: [])
        )
        let secondMessageID = UUID()

        let firstTurn = try runtime.startTurn(prompt: "First")
        for try await _ in firstTurn {}
        let secondTurn = try runtime.startTurn(
            prompt: "Second",
            userMessageID: secondMessageID
        )
        for try await _ in secondTurn {}
        let thirdTurn = try runtime.startTurn(prompt: "Third")
        for try await _ in thirdTurn {}
        let replacementTurn = try runtime.startTurn(
            prompt: "Edited second",
            userMessageID: secondMessageID,
            replacingUserMessageID: secondMessageID
        )
        for try await _ in replacementTurn {}

        let archivedOriginal = try XCTUnwrap(runtime.messageRevisions(for: secondMessageID).first)
        let restoredEvents = try runtime.switchToMessageRevision(
            anchorUserMessageID: secondMessageID,
            revisionID: archivedOriginal.id
        )
        await runtime.waitForPendingHistoryPersistence()

        let restoredMessages = ChatTimelineEvent.messages(from: restoredEvents)
        XCTAssertEqual(
            restoredMessages.map(\.content),
            ["First", "Done.", "Second", "Done.", "Third", "Done."]
        )

        let events = try await historyStore.fetchEvents(sessionID: runtime.currentSessionID)
        let revisions = try XCTUnwrap(ChatTimelineEvent.messageRevisions(from: events)[secondMessageID])
        XCTAssertEqual(revisions.count, 1)
        guard let archivedCurrentFirstEvent = revisions.first?.events.first,
              case let .userMessage(archivedText) = archivedCurrentFirstEvent.kind else {
            XCTFail("Expected switching branches to archive the replaced current branch.")
            return
        }
        XCTAssertEqual(archivedText, "Edited second")
    }

    func testMessageRevisionsStayInArchivedOrder() async throws {
        let adapter = CapturingRuntimeProvider()
        let (runtime, _) = makeRuntime(
            adapter: adapter,
            systemPromptStore: InMemorySystemPromptStore(prompts: [])
        )
        let messageID = UUID()

        let originalTurn = try runtime.startTurn(
            prompt: "Original",
            userMessageID: messageID
        )
        for try await _ in originalTurn {}
        let firstEditTurn = try runtime.startTurn(
            prompt: "First edit",
            userMessageID: messageID,
            replacingUserMessageID: messageID
        )
        for try await _ in firstEditTurn {}
        let secondEditTurn = try runtime.startTurn(
            prompt: "Second edit",
            userMessageID: messageID,
            replacingUserMessageID: messageID
        )
        for try await _ in secondEditTurn {}

        let revisions = runtime.messageRevisions(for: messageID)
        XCTAssertEqual(revisions.count, 2)
        XCTAssertEqual(revisions.compactMap(\.firstUserMessageText), ["Original", "First edit"])
    }

    private func makeRuntime(
        adapter: any LLMsProviderAdapter,
        systemPromptStore: any SystemPromptStore,
        historyStore: (any ChatHistoryStore)? = nil,
        clock: any AppClock = SystemAppClock()
    ) -> (ChatRuntime, UserDefaultsChatStore) {
        let provider = LLMsProviderRecord(
            kind: adapter.kind,
            name: adapter.displayName,
            configuration: adapter.defaultConfiguration,
            models: [LLMsProviderModel(id: "test-model")],
            createdAt: Date(timeIntervalSince1970: 1)
        )
        store.saveProvider(provider)
        store.saveSelectedModelSelection(
            ChatModelSelection(
                providerID: provider.id,
                providerName: provider.displayName,
                modelID: "test-model"
            )
        )

        let providerManager = LLMsProviderManager(
            registry: LLMsProviderRegistry(adapters: [adapter]),
            store: store
        )
        let toolCatalog = ToolCatalog(registry: ToolRegistry(tools: []), isEnabled: { true })
        let contextBuilder = ChatContextBuilder(
            memoryManager: MemoryManager(retriever: EmptyRuntimeMemoryRetriever()),
            toolCatalog: toolCatalog,
            systemPromptSettingsStore: UserDefaultsSystemPromptSettingsStore(
                defaults: defaults,
                storageKey: "systemPromptSettings"
            )
        )
        let turnRunner = ChatTurnRunner(
            providerManager: providerManager,
            toolManager: ToolManager(catalog: toolCatalog)
        )
        let defaultHistoryStore = UserDefaultsChatStore(
            defaults: defaults,
            storageKey: "chatHistory",
            attachmentStore: ChatAttachmentStore.shared
        )
        let runtime = ChatRuntime(
            providerStore: store,
            providerManager: providerManager,
            systemPromptManager: SystemPromptManager(store: systemPromptStore),
            contextBuilder: contextBuilder,
            turnRunner: turnRunner,
            historyStore: historyStore ?? defaultHistoryStore,
            clock: clock
        )
        return (runtime, defaultHistoryStore)
    }

    private func makePrompt(title: String, content: String) -> SystemPromptRecord {
        SystemPromptRecord(
            title: title,
            content: content,
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 1)
        )
    }
}

private struct FixedClock: AppClock {
    var now: Date
}

private final class InMemorySystemPromptStore: SystemPromptStore {
    private var prompts: [SystemPromptRecord]

    init(prompts: [SystemPromptRecord]) {
        self.prompts = prompts
    }

    func loadPrompts() -> [SystemPromptRecord] {
        prompts
    }

    func savePromptRecord(_ prompt: SystemPromptRecord) {
        if let index = prompts.firstIndex(where: { $0.id == prompt.id }) {
            prompts[index] = prompt
        } else {
            prompts.append(prompt)
        }
    }

    func deletePromptRecord(id: UUID) {
        prompts.removeAll { $0.id == id }
    }
}

private final class FailingRuntimeHistoryStore: ChatHistoryStore {
    private let error: Error

    init(error: Error) {
        self.error = error
    }

    func fetchSessions() async throws -> [ChatSession] {
        []
    }

    func saveSession(_ session: ChatSession) async throws {}

    func deleteSession(id: UUID) async throws {
        throw error
    }

    func fetchEvents(sessionID: UUID) async throws -> [ChatTimelineEvent] {
        []
    }

    func saveEvent(_ event: ChatTimelineEvent, sessionID: UUID) async throws {
        throw error
    }

    func saveEvents(_ events: [ChatTimelineEvent], sessionID: UUID) async throws {
        throw error
    }
}

private enum RuntimeHistoryPersistenceError: LocalizedError {
    case sample

    var errorDescription: String? {
        "History persistence failed."
    }
}

private struct EmptyRuntimeMemoryRetriever: MemoryRetriever {
    func retrieveRelevantMemories(for context: ChatContext) async throws -> [MemoryRecord] {
        []
    }
}

private struct EmptyRuntimeProvider: LLMsProviderAdapter {
    let kind = LLMsProviderKind(rawValue: "emptyRuntimeProvider")
    let displayName = "Empty Runtime Provider"
    let capabilities: Set<LLMsProviderCapability> = [.streamingChat]
    let defaultConfiguration = LLMsProviderConfiguration()
    let configurationFields: [LLMsProviderConfigurationField] = []
    let modelSource: LLMsProviderModelSource = .manual

    func streamChat(
        request: ChatRequest,
        configuration: LLMsProviderConfiguration
    ) -> AsyncThrowingStream<ChatResponseDelta, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }
}

private struct FailingRuntimeProvider: LLMsProviderAdapter {
    let kind = LLMsProviderKind(rawValue: "failingRuntimeProvider")
    let displayName = "Failing Runtime Provider"
    let capabilities: Set<LLMsProviderCapability> = [.streamingChat]
    let defaultConfiguration = LLMsProviderConfiguration()
    let configurationFields: [LLMsProviderConfigurationField] = []
    let modelSource: LLMsProviderModelSource = .manual

    func streamChat(
        request: ChatRequest,
        configuration: LLMsProviderConfiguration
    ) -> AsyncThrowingStream<ChatResponseDelta, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: RuntimeProviderError.failedBeforeStreaming)
        }
    }
}

private final class SequencedRuntimeProvider: LLMsProviderAdapter {
    enum Step {
        case failBeforeStreaming
        case yieldThenFail(content: String)
        case succeed(content: String)
    }

    let kind = LLMsProviderKind(rawValue: "sequencedRuntimeProvider")
    let displayName = "Sequenced Runtime Provider"
    let capabilities: Set<LLMsProviderCapability> = [.streamingChat]
    let defaultConfiguration = LLMsProviderConfiguration()
    let configurationFields: [LLMsProviderConfigurationField] = []
    let modelSource: LLMsProviderModelSource = .manual

    private let lock = NSLock()
    private var remainingSteps: [Step]
    private var capturedRequests: [ChatRequest] = []

    init(steps: [Step]) {
        remainingSteps = steps
    }

    var requests: [ChatRequest] {
        lock.lock()
        defer {
            lock.unlock()
        }

        return capturedRequests
    }

    func streamChat(
        request: ChatRequest,
        configuration: LLMsProviderConfiguration
    ) -> AsyncThrowingStream<ChatResponseDelta, Error> {
        let step: Step
        lock.lock()
        capturedRequests.append(request)
        step = remainingSteps.isEmpty
            ? .succeed(content: "Done.")
            : remainingSteps.removeFirst()
        lock.unlock()

        return AsyncThrowingStream { continuation in
            switch step {
            case .failBeforeStreaming:
                continuation.finish(throwing: RuntimeProviderError.failedBeforeStreaming)
            case let .yieldThenFail(content):
                continuation.yield(ChatResponseDelta(content: content))
                continuation.finish(throwing: RuntimeProviderError.failedBeforeStreaming)
            case let .succeed(content):
                continuation.yield(ChatResponseDelta(content: content))
                continuation.finish()
            }
        }
    }
}

private final class CapturingRuntimeProvider: LLMsProviderAdapter {
    let kind = LLMsProviderKind(rawValue: "capturingRuntimeProvider")
    let displayName = "Capturing Runtime Provider"
    let capabilities: Set<LLMsProviderCapability> = [.streamingChat]
    let defaultConfiguration = LLMsProviderConfiguration()
    let configurationFields: [LLMsProviderConfigurationField] = []
    let modelSource: LLMsProviderModelSource = .manual

    private let lock = NSLock()
    private var capturedRequests: [ChatRequest] = []

    var requests: [ChatRequest] {
        lock.lock()
        defer {
            lock.unlock()
        }

        return capturedRequests
    }

    func streamChat(
        request: ChatRequest,
        configuration: LLMsProviderConfiguration
    ) -> AsyncThrowingStream<ChatResponseDelta, Error> {
        lock.lock()
        capturedRequests.append(request)
        lock.unlock()

        return AsyncThrowingStream { continuation in
            continuation.yield(ChatResponseDelta(content: "Done."))
            continuation.finish()
        }
    }
}

private final class SuspendedRuntimeProvider: LLMsProviderAdapter {
    let kind = LLMsProviderKind(rawValue: "suspendedRuntimeProvider")
    let displayName = "Suspended Runtime Provider"
    let capabilities: Set<LLMsProviderCapability> = [.streamingChat]
    let defaultConfiguration = LLMsProviderConfiguration()
    let configurationFields: [LLMsProviderConfigurationField] = []
    let modelSource: LLMsProviderModelSource = .manual

    private let lock = NSLock()
    private var capturedRequests: [ChatRequest] = []
    private var continuation: AsyncThrowingStream<ChatResponseDelta, Error>.Continuation?

    var requests: [ChatRequest] {
        lock.lock()
        defer {
            lock.unlock()
        }

        return capturedRequests
    }

    func waitForRequestCount(_ count: Int) async {
        for _ in 0..<1_000 {
            if requests.count >= count {
                return
            }
            await Task.yield()
        }
    }

    func finish() {
        lock.lock()
        let continuation = continuation
        lock.unlock()

        continuation?.finish()
    }

    func streamChat(
        request: ChatRequest,
        configuration: LLMsProviderConfiguration
    ) -> AsyncThrowingStream<ChatResponseDelta, Error> {
        lock.lock()
        capturedRequests.append(request)
        lock.unlock()

        return AsyncThrowingStream { continuation in
            self.lock.lock()
            self.continuation = continuation
            self.lock.unlock()
        }
    }
}

private enum RuntimeProviderError: LocalizedError {
    case failedBeforeStreaming

    var errorDescription: String? {
        switch self {
        case .failedBeforeStreaming:
            return "Provider failed before streaming."
        }
    }
}

private extension ChatMessageRevision {
    var firstUserMessageText: String? {
        for event in events {
            switch event.kind {
            case let .userMessage(text),
                 let .userMessageWithAttachments(text, _):
                return text
            case .assistantReasoning,
                 .assistantContent,
                 .assistantToolCalls,
                 .toolEvent:
                continue
            }
        }

        return nil
    }
}
