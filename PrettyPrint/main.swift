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
    /// - Paramter: `blankSpace` is the number of spaces per blank.
    case begin(offset: Int, breakType: Break)

    /// The end delimiter of a block.
    case end

    /// The end of the file.
    ///
    /// This token initiates cleanup.
    case eof

    /// A required line break.
    static var linebreak: Token {
        return .break(blankSpace: 1, offset: Int.max)
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

    public mutating func scanToken(_ token: Token) {
        switch token {
        case .eof:
            if !scanStack.isEmpty {
                checkStack(0)
            }
        case .begin:
            if scanStack.isEmpty {
                (leftTotal, rightTotal) = (1, 1)
                tokens.removeAll() // this isn't in scan psuedo code
                sizes.removeAll() // this isn't in scan psuedo code
            } else {
                scanStack.append(tokens.endIndex)
                tokens.append(token)
                sizes.append(-rightTotal)
            }
        case .end:
            if scanStack.isEmpty {
                printToken(token, length: 0)
            } else {
                scanStack.append(tokens.endIndex)
                tokens.append(token)
                sizes.append(-1) // -1 or 0?
            }
        case let .break(blankSpace, _):
            if scanStack.isEmpty {
                (leftTotal, rightTotal) = (1, 1)
            } else {
                checkStack(0)
                scanStack.append(tokens.endIndex)
                tokens.append(token)
                sizes.append(-rightTotal)
                rightTotal += blankSpace
            }
        case let .string(s):
            if scanStack.isEmpty {
                printToken(token, length: s.count)
            } else {
                tokens.append(token)
                sizes.append(s.count)
                rightTotal += s.count

                // The elements in `tokens` can't fit in the space remaining on
                // this line. Force a break at the earliest opportunity (the
                // bottom of `scanStack`) by setting its associated length to
                // `Int.max`. Then start print tokens until the elements in
                // `tokens` can fit on a line again.
                while rightTotal - leftTotal > space {
                    sizes[scanStack.removeFirst()] = Int.max
                    advanceLeft(token: tokens.first!, length: sizes.first!)
                }
            }
        }
    }

//    private mutating func checkStream() {
//        if rightTotal - leftTotal > space {
//            if let bottom = scanStack.first, bottom == 0 {
//                sizes[scanStack.removeFirst()] = Int.max
//            }
//            advanceLeft(token: tokens.first!, length: sizes.first!)
//            if !tokens.isEmpty {
//                checkStream()
//            }
//        }
//    }

    /// Forces output from the left of the stream.
    private mutating func advanceLeft(token x: Token, length l: Int) {
        if l >= 0 {
            printToken(x, length: l)
            switch x {
            case let .break(blankSpace, _): leftTotal += blankSpace
            case .string: leftTotal += l
            default: break
            }
            if !tokens.isEmpty {
                advanceLeft(token: tokens.removeFirst(), length: sizes.removeFirst())
            }
        }
    }

    private mutating func checkStack(_ k: Int) {
        if let x = scanStack.last {
            switch tokens[x] {
            case .begin:
                if k > 0 {
                    scanStack.removeLast()
                    sizes[x] += rightTotal
                    checkStack(k - 1)
                }
            case .end:
                scanStack.removeLast()
                sizes[x] + 1; // ???
                checkStack(k + 1)
            default:
                scanStack.removeLast()
                sizes[x] += rightTotal
                if k > 0 { checkStack(k) }
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
            // C1 = printStack.removeLast() // ???
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
            assert(l <= space, "Line too long")
            space -= l
            printString(string)
        default:
            fatalError("unreachable")
        }
    }
}

//struct PrettyPrinter {
//    enum Token {
//        case string(String)
//        case blank
//        case openBlock
//        case closeBlock
//    }
//
//    var maxLineLength: Int
//
//    init(maxLineLength: Int = 80) {
//        self.maxLineLength = maxLineLength
//    }
//
//    mutating func printTokens(_ tokens: [Token]) -> String {
//        return scanTokens(tokens)
//    }
//
//    private mutating func scanTokens(_ tokens: [Token]) -> String {
//        var result = ""
//
//        // A parallel array of `tokens` that stores each token's "associated
//        // length".
//        //
//        // Each token case stores a different "associated length":
//        // - `.string` is the length of the string.
//        // - `.openBlock` is the length of the block it begins.
//        // - `.closeBlock` is 0.
//        // - `.blank` is 1 + the length of the next block.
//        //
//        // To compute the length for `.openBlock` and `.blank` requires
//        // looking ahead.
//        var tokenLengths = Array(repeatElement(0, count: tokens.count))
//
//        // A stack of indices to `.openBlock` or `.blank` tokens with
//        // running "associated length" computations.
//        var stack: [Int] = []
//
//        // The length required to print the block of `tokens[left...right]`.
//        var rootBlockLength = 0
//
//        var left = 0
//        for right in 0..<tokens.endIndex {
//            let token = tokens[right]
//            switch token {
//            case .openBlock:
//                if stack.isEmpty {
//                    rootBlockLength = 1
//                }
//
//                tokenLengths[right] = -rootBlockLength
//                stack.append(right)
//
//            case .closeBlock:
//                tokenLengths[right] = 0
//
//                // `i` is either:
//                // - the index of the `.openBlock` starting the block.
//                // - the index of the previous `.blank` (in which case `i - 1`
//                //   is the index of the `.openBlock` starting the block).
//                var i = stack.removeLast()
//                tokenLengths[i] += rootBlockLength // so the blank gets length from the blank to the next closeBlock
//                if case .blank = tokens[i] {
//                    i = stack.removeLast()
//                    tokenLengths[i] += rootBlockLength
//                }
//
//                if stack.isEmpty {
//                    while left <= right {
//                        printToken(
//                            tokens[left],
//                            ofLength: tokenLengths[left],
//                            to: &result
//                        )
//                        left += 1
//                    }
//                }
//
//            case .blank:
//                // so the blank gets the length to the next blank
//                if let i = stack.last, case .blank = tokens[i] {
//                    tokenLengths[stack.removeLast()] += rootBlockLength
//                }
//
//                tokenLengths[right] = -rootBlockLength
//                stack.append(tokens.endIndex - 1)
//                rootBlockLength += 1
//
//            case let .string(string):
//                if stack.isEmpty {
//                    printToken(token, ofLength: string.count, to: &result)
//                } else {
//                    let length = string.count
//                    tokenLengths[right] = length
//                    rootBlockLength += length
//                }
//            }
//        }
//    }
//
//    var indentLength = 4
//    private var spaceStack: [Int] = []
//
//    // Each token case has a different "associated length":
//    // - `.string` is the length of the string.
//    // - `.openBlock` is the length of the block it begins.
//    // - `.closeBlock` is 0.
//    // - `.blank` is 1 + the length of the next block.
//    //
//    // `.string`s can't be broken, so print regardless of length
//    // `.blank` checks if the next block can fit on the present line
//    private mutating func printToken(
//        _ token: Token, ofLength length: Int, to target: inout String, availableLineLength: inout Int,
//    ) {
//        switch token {
//        case let .string(string):
//            target += string
//            availableLineLength -= length
//        case .openBlock:
//            spaceStack.append(availableLineLength)
//        case .closeBlock:
//            spaceStack.removeLast()
//        case .blank:
//            // if the next block can't fit on the line, start a new line and
//            // indent.
//            if length > availableLineLength {
//                availableLineLength = spaceStack.last! - indentLength
//                target += "\n"
//                target.append(contentsOf: repeatElement(
//                    " ", count: maxLineLength - availableLineLength))
//            } else {
//                target += " "
//                availableLineLength -= 1
//            }
//        }
//    }
//}

extension Character {
    // Cache character construction
    static let space = Character(" ")
    static let tab = Character("\t")
    static let vtab = Character("\u{000B}")
    static let ffeed = Character("\u{000C}")
    static let null = Character("\0")
    static let lf = Character("\n")
    static let cr = Character("\r")
    static let crlf = Character("\r\n")

    var isBlank: Bool {
        switch self {
        case Character.space, Character.tab, Character.vtab, Character.ffeed, Character.null, Character.lf, Character.cr, Character.crlf:
            return true
        default:
            return false
        }
    }

    // Cache character construction
    static let lbrace = Character("{")
    static let rbrace = Character("}")
    static let lsquare = Character("[")
    static let rsquare = Character("]")
    static let lparen = Character("(")
    static let rparen = Character(")")

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

