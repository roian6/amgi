@testable import AnkiBackend
import Foundation
import Synchronization
import Testing

private final class FakeTask: WatchHTTPTask, @unchecked Sendable {
    private let state = Mutex((resumed: 0, cancelled: 0))

    func resume() {
        state.withLock { $0.resumed += 1 }
    }

    func cancel() {
        state.withLock { $0.cancelled += 1 }
    }

    var counts: (resumed: Int, cancelled: Int) {
        state.withLock { $0 }
    }
}

private struct CapturedTask: Sendable {
    let request: URLRequest
    let handler: @Sendable (Data?, URLResponse?, (any Error)?) -> Void
}

@Suite("Watch URLSession transport")
struct WatchURLSessionTransportTests {
    @Test("constructs the request and maps one response")
    func requestAndResponseContract() throws {
        // Given
        let task = FakeTask()
        let captured = Mutex<CapturedTask?>(nil)
        let completions = Mutex<[(UInt64, WatchHTTPResult)]>([])
        let transport = WatchURLSessionTransport(
            taskFactory: { request, handler in
                captured.withLock { $0 = CapturedTask(request: request, handler: handler) }
                return task
            },
            completion: { requestID, result in
                completions.withLock { $0.append((requestID, result)) }
            }
        )
        let url = try #require(URL(string: "https://sync.example.invalid/sync/meta"))
        let requestBody = Data([1, 2, 3, 4])

        // When
        transport.start(
            WatchHTTPRequest(
                id: 42,
                url: url,
                syncHeader: "test-sync-header",
                body: requestBody,
                timeoutSeconds: 17
            )
        )
        let sent = try #require(captured.withLock { $0 })
        let response = try #require(HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Anki-Original-Size": "2", "Location": "https://sync2.example.invalid/"]
        ))
        sent.handler(Data([8, 9]), response, nil)
        transport.finish(requestID: 42, data: Data(), response: response, error: nil)

        // Then
        #expect(task.counts.resumed == 1)
        #expect(sent.request.httpMethod == "POST")
        #expect(sent.request.httpBody == requestBody)
        #expect(sent.request.timeoutInterval == 17)
        #expect(sent.request.value(forHTTPHeaderField: "Content-Type") == "application/octet-stream")
        #expect(sent.request.value(forHTTPHeaderField: "Anki-Sync") == "test-sync-header")
        let delivered = completions.withLock { $0 }
        #expect(delivered.count == 1)
        #expect(delivered.first?.0 == 42)
        #expect(delivered.first?.1.statusCode == 200)
        #expect(delivered.first?.1.originalSize == 2)
        #expect(delivered.first?.1.location == Data("https://sync2.example.invalid/".utf8))
        #expect(delivered.first?.1.body == Data([8, 9]))
    }

    @Test("cancels once and ignores late completion")
    func cancellationContract() throws {
        // Given
        let task = FakeTask()
        let captured = Mutex<CapturedTask?>(nil)
        let completionCount = Mutex(0)
        let transport = WatchURLSessionTransport(
            taskFactory: { request, handler in
                captured.withLock { $0 = CapturedTask(request: request, handler: handler) }
                return task
            },
            completion: { _, _ in completionCount.withLock { $0 += 1 } }
        )
        let url = try #require(URL(string: "https://sync.example.invalid/sync/meta"))
        transport.start(
            WatchHTTPRequest(
                id: 7,
                url: url,
                syncHeader: "test-sync-header",
                body: Data(),
                timeoutSeconds: 5
            )
        )
        let pending = try #require(captured.withLock { $0 })

        // When
        transport.cancel(requestID: 7)
        transport.cancel(requestID: 7)
        pending.handler(nil, nil, CancellationError())

        // Then
        #expect(task.counts.cancelled == 1)
        #expect(completionCount.withLock { $0 } == 0)
    }

    @Test("preserves native URL error domain and code")
    func nativeErrorDetails() throws {
        let task = FakeTask()
        let captured = Mutex<CapturedTask?>(nil)
        let completion = Mutex<WatchHTTPResult?>(nil)
        let transport = WatchURLSessionTransport(
            taskFactory: { request, handler in
                captured.withLock { $0 = CapturedTask(request: request, handler: handler) }
                return task
            },
            completion: { _, result in completion.withLock { $0 = result } }
        )
        let url = try #require(URL(string: "https://sync.example.invalid/sync/meta"))
        transport.start(
            WatchHTTPRequest(
                id: 9,
                url: url,
                syncHeader: "redacted",
                body: Data(),
                timeoutSeconds: 5
            )
        )

        let pending = try #require(captured.withLock { $0 })
        pending.handler(nil, nil, URLError(.notConnectedToInternet))

        let result = try #require(completion.withLock { $0 })
        let message = try #require(result.nativeError.flatMap { String(data: $0, encoding: .utf8) })
        #expect(message.contains(NSURLErrorDomain))
        #expect(message.contains(String(URLError.notConnectedToInternet.rawValue)))
    }
}
