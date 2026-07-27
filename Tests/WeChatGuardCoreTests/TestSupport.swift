import Foundation

struct TestFailure: Error, CustomStringConvertible {
    let description: String
}

func test(_ name: String, body: () throws -> Void) throws {
    do {
        try body()
        print("PASS: \(name)")
    } catch {
        print("FAIL: \(name): \(error)")
        throw error
    }
}

func expect(
    _ condition: @autoclosure () throws -> Bool,
    _ message: String = "expectation failed"
) throws {
    guard try condition() else {
        throw TestFailure(description: message)
    }
}

func expectThrows<T: Error>(
    _ type: T.Type,
    body: () throws -> Any
) throws {
    do {
        _ = try body()
        throw TestFailure(description: "expected \(type), but no error was thrown")
    } catch is T {
        return
    }
}

func expectThrows<T: Error & Equatable>(
    _ expected: T,
    body: () throws -> Any
) throws {
    do {
        _ = try body()
        throw TestFailure(description: "expected \(expected), but no error was thrown")
    } catch let error as T {
        try expect(error == expected, "expected \(expected), got \(error)")
    }
}
