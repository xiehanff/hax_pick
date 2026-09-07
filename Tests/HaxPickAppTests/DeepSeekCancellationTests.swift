import Foundation
import XCTest
@testable import HaxPickApp

@MainActor
final class DeepSeekCancellationTests: XCTestCase {
    func testCancellingConsumerTerminatesUnderlyingLineStream() async throws {
        let started = expectation(description: "transport started")
        let terminated = expectation(description: "transport line stream terminated")
        let client = CancellationProbeHTTPClient(
            started: started,
            terminated: terminated,
            response: Self.httpResponse(statusCode: 200)
        )
        let service = DeepSeekService(
            apiKeyProvider: { "test-key" },
            modelProvider: { .flash },
            streamingClient: client
        )

        let consumer = Task {
            do {
                for try await _ in service.stream(
                    messages: [AiMessage(role: .user, content: "Hello")]
                ) {}
            } catch is CancellationError {
                // Expected cancellation path.
            } catch {
                // AsyncThrowingStream implementations may finish rather than throw
                // when their consumer task is cancelled. Either way the transport
                // termination expectation below is the behavior this test protects.
            }
        }

        await fulfillment(of: [started], timeout: 1)
        client.yieldContent("partial")
        await Task.yield()
        consumer.cancel()
        await fulfillment(of: [terminated], timeout: 1)
        _ = await consumer.result

        XCTAssertTrue(client.didTerminate)
    }

    private static func httpResponse(statusCode: Int) -> HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: "https://api.deepseek.com/chat/completions")!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/event-stream"]
        )!
    }
}

private final class CancellationProbeHTTPClient: DeepSeekStreamingHTTPClient {
    private let started: XCTestExpectation
    private let terminated: XCTestExpectation
    private let response: URLResponse
    private var continuation: AsyncThrowingStream<String, Error>.Continuation?
    private let lock = NSLock()
    private var _didTerminate = false

    var didTerminate: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _didTerminate
    }

    init(
        started: XCTestExpectation,
        terminated: XCTestExpectation,
        response: URLResponse
    ) {
        self.started = started
        self.terminated = terminated
        self.response = response
    }

    func lines(for request: URLRequest) async throws -> (AsyncThrowingStream<String, Error>, URLResponse) {
        let stream = AsyncThrowingStream<String, Error> { continuation in
            lock.lock()
            self.continuation = continuation
            lock.unlock()

            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                self.lock.lock()
                let shouldFulfill = !self._didTerminate
                self._didTerminate = true
                self.lock.unlock()
                if shouldFulfill {
                    self.terminated.fulfill()
                }
            }
            started.fulfill()
        }
        return (stream, response)
    }

    func yieldContent(_ value: String) {
        lock.lock()
        let continuation = self.continuation
        lock.unlock()
        continuation?.yield(
            "data: {\"choices\":[{\"delta\":{\"content\":\"\(value)\"}}]}"
        )
    }
}
