import AnkiRustLib
import Foundation

protocol WatchHTTPTask: Sendable {
    func resume()
    func cancel()
}

extension URLSessionDataTask: WatchHTTPTask {}

struct WatchHTTPRequest: Sendable {
    let id: UInt64
    let url: URL
    let syncHeader: String
    let body: Data
    let timeoutSeconds: UInt32
}

struct WatchHTTPResult: Sendable {
    let statusCode: UInt16
    let originalSize: Int64
    let location: Data?
    let body: Data
    let nativeError: Data?
}

private enum WatchHTTPTraceRecorder {
    private static let lock = NSLock()

    static func started(_ request: WatchHTTPRequest) {
        append([
            "event": "start",
            "request_id": request.id,
            "scheme": request.url.scheme ?? "",
            "host": request.url.host ?? "",
            "path": request.url.path,
            "request_bytes": request.body.count,
            "timeout_seconds": request.timeoutSeconds,
        ])
    }

    static func finished(
        requestID: UInt64,
        data: Data?,
        response: URLResponse?,
        error: (any Error)?
    ) {
        var fields: [String: Any] = [
            "event": "finish",
            "request_id": requestID,
            "response_bytes": data?.count ?? 0,
        ]
        if let responseURL = response?.url {
            fields["scheme"] = responseURL.scheme ?? ""
            fields["host"] = responseURL.host ?? ""
            fields["path"] = responseURL.path
        }
        if let response = response as? HTTPURLResponse {
            fields["status"] = response.statusCode
            fields["original_size"] = response.value(forHTTPHeaderField: "Anki-Original-Size") ?? ""
            if let location = response.value(forHTTPHeaderField: "Location"),
               let url = URL(string: location) {
                fields["redirect_host"] = url.host ?? ""
                fields["redirect_path"] = url.path
            }
        }
        if let error {
            let native = error as NSError
            fields["error_domain"] = native.domain
            fields["error_code"] = native.code
            fields["error_description"] = native.localizedDescription
        }
        append(fields)
    }

    private static func append(_ fields: [String: Any]) {
        #if os(watchOS)
        lock.withLock {
            do {
                var record = fields
                record["timestamp"] = Date().timeIntervalSince1970
                var line = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
                line.append(0x0A)
                let directory = FileManager.default.urls(
                    for: .applicationSupportDirectory,
                    in: .userDomainMask
                )[0]
                try FileManager.default.createDirectory(
                    at: directory,
                    withIntermediateDirectories: true
                )
                let file = directory.appendingPathComponent("WatchSyncDiagnostics.jsonl")
                if !FileManager.default.fileExists(atPath: file.path) {
                    try line.write(to: file, options: .atomic)
                    return
                }
                let handle = try FileHandle(forWritingTo: file)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: line)
            } catch {
                // Diagnostics must never affect sync.
            }
        }
        #endif
    }
}

final class WatchURLSessionTransport: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    typealias TaskFactory = @Sendable (
        URLRequest,
        @escaping @Sendable (Data?, URLResponse?, (any Error)?) -> Void
    ) -> any WatchHTTPTask
    typealias Completion = @Sendable (UInt64, WatchHTTPResult) -> Void

    private let lock = NSLock()
    private var tasks: [UInt64: any WatchHTTPTask] = [:]
    private var taskFactory: TaskFactory!
    private var retainedSession: URLSession?
    private let completion: Completion

    init(configuration: URLSessionConfiguration = .ephemeral, completion: @escaping Completion) {
        self.completion = completion
        super.init()
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        retainedSession = session
        taskFactory = { request, handler in
            session.dataTask(with: request, completionHandler: handler)
        }
    }

    init(taskFactory: @escaping TaskFactory, completion: @escaping Completion) {
        self.taskFactory = taskFactory
        self.completion = completion
        super.init()
    }

    func start(_ request: WatchHTTPRequest) {
        WatchHTTPTraceRecorder.started(request)
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = "POST"
        urlRequest.httpBody = request.body
        urlRequest.timeoutInterval = TimeInterval(request.timeoutSeconds)
        urlRequest.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(request.syncHeader, forHTTPHeaderField: "Anki-Sync")
        let task = taskFactory(urlRequest) { [weak self] data, response, error in
            self?.finish(requestID: request.id, data: data, response: response, error: error)
        }
        lock.withLock { tasks[request.id] = task }
        task.resume()
    }

    func cancel(requestID: UInt64) {
        let task = lock.withLock { tasks.removeValue(forKey: requestID) }
        task?.cancel()
    }

    func finish(
        requestID: UInt64,
        data: Data?,
        response: URLResponse?,
        error: (any Error)?
    ) {
        guard lock.withLock({ tasks.removeValue(forKey: requestID) != nil }) else { return }
        WatchHTTPTraceRecorder.finished(
            requestID: requestID,
            data: data,
            response: response,
            error: error
        )
        completion(requestID, Self.map(data: data, response: response, error: error))
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(response.statusCode == 308 ? nil : request)
    }

    private static func map(
        data: Data?,
        response: URLResponse?,
        error: (any Error)?
    ) -> WatchHTTPResult {
        if let error {
            let native = error as NSError
            let detail = "\(native.domain)(\(native.code)): \(native.localizedDescription)"
            return WatchHTTPResult(
                statusCode: 0,
                originalSize: -1,
                location: nil,
                body: Data(),
                nativeError: Data(detail.utf8)
            )
        }
        guard let response = response as? HTTPURLResponse else {
            return WatchHTTPResult(
                statusCode: 0,
                originalSize: -1,
                location: nil,
                body: Data(),
                nativeError: Data("URLSession returned no HTTP response".utf8)
            )
        }
        return WatchHTTPResult(
            statusCode: UInt16(response.statusCode),
            originalSize: response.value(forHTTPHeaderField: "Anki-Original-Size")
                .flatMap { Int64($0) } ?? -1,
            location: response.value(forHTTPHeaderField: "Location").map { Data($0.utf8) },
            body: data ?? Data(),
            nativeError: nil
        )
    }
}

#if os(watchOS)
private let watchURLSessionTransport = WatchURLSessionTransport(completion: completeRustRequest)

@_cdecl("anki_swift_http_request")
func ankiSwiftHTTPRequest(
    requestID: UInt64,
    urlData: UnsafePointer<UInt8>?,
    urlLength: Int,
    headerData: UnsafePointer<UInt8>?,
    headerLength: Int,
    bodyData: UnsafePointer<UInt8>?,
    bodyLength: Int,
    timeoutSeconds: UInt32
) {
    guard let urlBytes = copiedData(urlData, count: urlLength),
          let urlString = String(data: urlBytes, encoding: .utf8),
          let url = URL(string: urlString),
          let headerBytes = copiedData(headerData, count: headerLength),
          let syncHeader = String(data: headerBytes, encoding: .utf8),
          let body = copiedData(bodyData, count: bodyLength) else {
        completeRustRequest(
            requestID,
            WatchHTTPResult(
                statusCode: 0,
                originalSize: -1,
                location: nil,
                body: Data(),
                nativeError: Data("Invalid Rust HTTP request".utf8)
            )
        )
        return
    }
    watchURLSessionTransport.start(
        WatchHTTPRequest(
            id: requestID,
            url: url,
            syncHeader: syncHeader,
            body: body,
            timeoutSeconds: timeoutSeconds
        )
    )
}

@_cdecl("anki_swift_http_cancel")
func ankiSwiftHTTPCancel(requestID: UInt64) {
    watchURLSessionTransport.cancel(requestID: requestID)
}

private func copiedData(_ pointer: UnsafePointer<UInt8>?, count: Int) -> Data? {
    guard count >= 0 else { return nil }
    if count == 0 { return Data() }
    guard let pointer else { return nil }
    return Data(bytes: pointer, count: count)
}

private func completeRustRequest(_ requestID: UInt64, _ result: WatchHTTPResult) {
    let location = result.location ?? Data()
    let nativeError = result.nativeError ?? Data()
    location.withUnsafeBytes { locationBuffer in
        result.body.withUnsafeBytes { bodyBuffer in
            nativeError.withUnsafeBytes { errorBuffer in
                let locationPointer: UnsafePointer<UInt8>? = result.location == nil
                    ? nil
                    : locationBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self)
                let errorPointer: UnsafePointer<UInt8>? = result.nativeError == nil
                    ? nil
                    : errorBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self)
                _ = anki_http_complete(
                    requestID,
                    result.statusCode,
                    result.originalSize,
                    locationPointer,
                    location.count,
                    bodyBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self),
                    result.body.count,
                    errorPointer,
                    nativeError.count
                )
            }
        }
    }
}
#endif
