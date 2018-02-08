// Copyright © 2018 Kyle Macomber. All rights reserved.

public struct RingBuffer<Element> {
    private var storage: [Element]
    private var left: Int
    private var right: Int

    public init(repeating repeatedValue: Element, count: Int) {
        storage = Array(repeatElement(repeatedValue, count: count))
        left = 0
        right = 0
    }
}

extension RingBuffer : MutableCollection, RandomAccessCollection {
    public typealias Index = Int

    public var startIndex: Index {
        return 0
    }

    public var endIndex: Index {
        return left <= right
            ? right - left
            : right + storage.count - left 
    }

    public func index(after i: Index) -> Index {
        return i + 1
    }

    public func index(before i: Index) -> Index {
        return i - 1
    }

    public subscript(position: Index) -> Element {
        get {
            precondition((startIndex..<endIndex).contains(position))
            let i = left + position % storage.count
            return storage[i]
        }
        set {
            precondition((startIndex..<endIndex).contains(position))
            let i = left + position % storage.count
            storage[i] = newValue
        }
    }
}

extension RingBuffer {
    @discardableResult
    public mutating func removeFirst() -> Element {
        precondition(left != right, "Can't remove. RingBuffer is empty.")
        let x = storage[left]
        left = left + 1 % storage.count
        return x
    }

    @discardableResult
    public mutating func removeLast() -> Element {
        precondition(left != right, "Can't remove. RingBuffer is empty.")
        let x = storage[right]
        right = right - 1 % storage.count
        return x
    }

    public mutating func popLast(
        where test: (Element)->Bool = { _ in true }) -> Element?
    {
        return last.map(test) == true ? removeLast() : nil
    }
    
    public mutating func popFirst(
        where test: (Element)->Bool = { _ in true }
    ) -> Element? {
        return first.map(test) == true ? removeFirst() : nil
    }
    
    public mutating func append(_ newElement: Element) {
        right = right + 1 % storage.count
        precondition(left != right, "Can't append. RingBuffer is full.")
        storage[right] = newElement
    }

    public mutating func insertFirst(_ newElement: Element) {
        left = left + 1 % storage.count
        precondition(left != right, "Can't insertFirst. RingBuffer is full.")
        storage[right] = newElement
    }

    public mutating func removeAll() {
        (left, right) = (0, 0)
    }
}
