// Copyright © 2018 Kyle Macomber. All rights reserved.

import Foundation

enum Token {
    enum Break {
        case consistent, inconsistent
    }

    /// A contiguous sequence of non-delimiter characters that can't be broken.
    case string(String)

    /// An optional line break.
    ///
    /// If the printer outputs a `break` it indents `offset` spaces relative to
    /// the indentation of the enclosing block; otherwise it outputs
    /// `blankSpace` blanks.
    ///
    /// - Paramter: `blankSpace` is the number of spaces per blank.
    /// - Parameter: `offset` is the indent for overflow lines.
    case `break`(blankSpace: Int, offset: Int)

    /// The opening delimiter of a block.
    ///
    /// - Parameter: `offset` is the indent for this group.
    /// - Paramter: `breakType` TODO: consistent, inconsistent
    case begin(offset: Int, breakType: Break)

    /// The end delimiter of a block.
    case end

    /// The end of the file.
    ///
    /// This token initiates cleanup.
    case eof

    /// A required line break.
    static var linebreak: Token {
        return .break(blankSpace: Int.max, offset: 0)
    }

    var string: String? {
        if case .string(let x) = self { return x }
        return nil
    }
    var `break`: (blankSpace: Int, offset: Int)? {
        if case .break(let x) = self { return x }
        return nil
    }
    var begin: (offset: Int, breakType: Break)? {
        if case .begin(let x) = self { return x }
        return nil
    }
}

enum PrintBreak {
    case fits, consistent, inconsistent
}

struct PrettyPrinter {
    var margin: Int
    var space: Int
    var tokens: RingBuffer<Token>

    // A parallel array of `tokens` that stores each token's "associated
    // length".
    //
    // Each token case stores a different "associated length":
    // - `.string` is the length of the string.
    // - `.begin` is the length of the block it begins.
    // - `.end` is 0.
    // - `.blank` is 1 + the length of the next block.
    //
    // To compute the length for `.openBlock` and `.blank` requires
    // looking ahead.
    var sizes: RingBuffer<Int>
    var leftTotal: Int = 0
    var rightTotal: Int = 0
    var scanStack: RingBuffer<Int>
    var printStack: [(offset: Int, `break`: PrintBreak)]

    public init(lineWidth: Int) {
        margin = lineWidth
        space = lineWidth

        let n = 3 * lineWidth
        tokens = RingBuffer(repeating: .eof, count: n)
        sizes = RingBuffer(repeating: 0, count: n)
        scanStack = RingBuffer(repeating: 0, count: n)
        printStack = []
    }

    public mutating func scanToken(_ t: Token) {
        switch t {
        case .eof:
            if !scanStack.isEmpty {
                checkStack()
                advanceLeft()
            }
            indent(0)
        case .begin:
            if scanStack.isEmpty {
                (leftTotal, rightTotal) = (1, 1)
                tokens.removeAll() // this isn't in scan psuedo code
                sizes.removeAll() // this isn't in scan psuedo code
            } else {
                scanStack.append(tokens.endIndex)
                tokens.append(t)
                sizes.append(-rightTotal)
            }
        case .end:
            if scanStack.isEmpty {
                printToken(t, length: 0)
            } else {
                scanStack.append(tokens.endIndex)
                tokens.append(t)
                sizes.append(-1)
            }
        case let .break(blankSpace, _):
            if scanStack.isEmpty {
                (leftTotal, rightTotal) = (1, 1)
                tokens.removeAll() // this isn't in scan psuedo code
                sizes.removeAll() // this isn't in scan psuedo code
            } else {
                checkStack()
                scanStack.append(tokens.endIndex)
                tokens.append(t)
                sizes.append(-rightTotal)
                rightTotal += blankSpace
            }
        case let .string(s):
            if scanStack.isEmpty {
                printToken(t, length: s.count)
            } else {
                tokens.append(t)
                sizes.append(s.count)
                rightTotal += s.count
                checkStream()
            }
        }
    }

    // If the elements in `tokens` can't fit in the space remaining on the
    // current line, force a break at the earliest opportunity (the bottom of
    // `scanStack`) by setting its associated length to `Int.max`. Then print
    // tokens until the elements in
    // `tokens` can fit on a line again.
    private mutating func checkStream() {
        while rightTotal - leftTotal > space {
            if let bottom = scanStack.first, bottom == 0 {
                sizes[scanStack.removeFirst()] = Int.max
            }
            advanceLeft()
            if tokens.isEmpty { break }
        }
    }

    /// Print all finalized tokens at the left of the buffer.
    private mutating func advanceLeft() {
        assert(!sizes.isEmpty) // sanity check
        
        while let l = sizes.first, l >= 0 {
            let x = tokens.removeFirst()
            sizes.removeFirst()
            
            printToken(x, length: l)

            leftTotal += x.break?.blankSpace ?? x.string.map { _ in l } ?? 0
        }
    }

    /// Finalizes sizes of tokens in zero or more consecutive matched
    /// `.begin`/`.end` groups, preceded by at most one `.break`, at the end of
    /// a sequence of the buffered, un-finalized, non-string tokens.
    ///
    /// If no matching `.begin` can be found for an `.end` in the
    /// buffer (e.g. the `.begin` has already been flushed), all
    /// un-finalized buffered tokens will be finalized.
    private mutating func checkStack() {
        var k = 0 // nesting level
        
        while let i = scanStack.popLast() {
            switch tokens[i] {
            case .begin:
                if k == 0 { scanStack.append(i); return }
                sizes[i] += rightTotal
                k -= 1
            case .end:
                sizes[i] += 1
                k += 1
            default:
                assert(tokens[i].break != nil) // sanity check
                sizes[i] += rightTotal
                if k == 0 { return }
            }
        }
    }

    /// Prints a newline and indents `amount` spaces.
    private func printNewLine(_ amount: Int) {

    }

    /// Prints `amount` spaces.
    private func indent(_ amount: Int) {

    }

    private func printString(_ string: String) {

    }

    private mutating func printToken(_ x: Token, length l: Int) {
        switch x {
        case let .begin(offset, breakType):
            if l > space {
                printStack.append((space - offset, breakType == .consistent ? PrintBreak.consistent : .inconsistent))
            } else {
                printStack.append((0, .fits))
            }
        case .end:
            printStack.removeLast()
        case let .break(blankSpace, offset):
            switch printStack.last!.break {
            case .fits:
                space -= blankSpace
                indent(blankSpace)
            case .consistent:
                space = printStack.last!.offset - offset
                printNewLine(margin - space)
            case .inconsistent:
                if l > space {
                    space = printStack.last!.offset - offset
                    printNewLine(margin - space)
                } else {
                    space -= blankSpace
                    indent(blankSpace)
                }
            }
        case let .string(string):
            // TODO: do we need to handle a string longer than lineWidth here?
            assert(l <= space, "Line too long")
            space -= l
            printString(string)
        default:
            fatalError("unreachable")
        }
    }
}

extension Character {
    // Cache character construction
    static let space = " " as Character
    static let tab = "\t" as Character
    static let vtab = "\u{000B}" as Character
    static let ffeed = "\u{000C}" as Character
    static let null = "\0" as Character
    static let lf = "\n" as Character
    static let cr = "\r" as Character
    static let crlf = "\r\n" as Character

    var isBlank: Bool {
        switch self {
        case Character.space, Character.tab, Character.vtab, Character.ffeed, Character.null, Character.lf, Character.cr, Character.crlf:
            return true
        default:
            return false
        }
    }

    // Cache character construction
    static let lbrace = "{" as Character
    static let rbrace = "}" as Character
    static let lsquare = "[" as Character
    static let rsquare = "]" as Character
    static let lparen = "(" as Character
    static let rparen = ")" as Character

    var isOpenBlock: Bool {
        switch self {
        case Character.lbrace, Character.lsquare, Character.lparen:
            return true
        default:
            return false
        }
    }

    var isCloseBlock: Bool {
        switch self {
        case Character.rbrace, Character.rsquare, Character.rparen:
            return true
        default:
            return false
        }
    }

}

/*
var lines: [String] = []
let args = CommandLine.arguments
let path = CommandLine.arguments[1]
let fileContents = try String(contentsOfFile: path)

var string = ""
var tokens: [Token] = []
for c in fileContents {
    string.append(c)
    if c.isBlank {
        // TODO: we don't want to actually include newlines in the string
        tokens.append(.string(string))
        tokens.append(.blank)
    } else if c.isOpenBlock {
        tokens.append(.string(string))
        tokens.append(.openBlock)
    } else if c.isCloseBlock {
        tokens.append(.string(string))
        tokens.append(.closeBlock)
    }
}



// scan()





for arg in args[1...] {
    let paths = arg.absolutePathsBelow.filter { $0.pathExtension == "swift" || $0.pathExtension == "gyb" }
    for path in paths {
        let contents = try String(contentsOfFile: path)
        for line in contents.split(separator: "\n") {
            lines.append(String(line))
        }
    }
}

print("Hello, World!")

*/

