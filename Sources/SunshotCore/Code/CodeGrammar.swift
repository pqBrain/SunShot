/// Lexical rules for one language, as data. `SyntaxHighlighter` interprets it; HTML/XML has its own scanner.
struct CodeGrammar: Sendable {
    var keywords: Set<String> = []
    var types: Set<String> = []
    /// Built-in functions / commands, coloured like function calls.
    var builtins: Set<String> = []
    var lineComments: [String] = []
    var blockComment: (open: String, close: String)?
    /// Quotes that end at the end of the line.
    var quotes: Set<UInt16> = [ASCII.doubleQuote, ASCII.singleQuote]
    /// Quotes whose strings may span lines (template literals, raw strings).
    var multilineQuotes: Set<UInt16> = []
    /// `"""` (and `'''` for Python) strings.
    var tripleQuotes = false
    var caseInsensitive = false
    /// Identifiers starting with an uppercase letter are types (Swift, Rust, Python classes…).
    var capitalizedAreTypes = false
    /// Extra identifier characters (`$` in JavaScript, `-` in CSS).
    var identifierExtras: Set<UInt16> = []
    /// `$name` / `${…}` variables (Shell).
    var variablePrefix: UInt16?
    /// `@name` attributes / decorators.
    var attributePrefix: UInt16?
    /// `#name` compiler directives coloured as keywords (Swift `#if`).
    var directivePrefix: UInt16?
    /// A string or identifier followed by `:` is a property (JSON keys, CSS properties).
    var colonProperties = false
    /// `name!` is a macro call (Rust).
    var bangMacros = false
    /// `'a` lifetimes rather than character literals when not closed right away (Rust).
    var lifetimes = false
    /// CSS: selectors outside braces, properties inside, `#hex` colours.
    var css = false
}

enum ASCII {
    static let newline: UInt16 = 10
    static let space: UInt16 = 32
    static let tab: UInt16 = 9
    static let carriageReturn: UInt16 = 13
    static let doubleQuote: UInt16 = 34
    static let singleQuote: UInt16 = 39
    static let backtick: UInt16 = 96
    static let backslash: UInt16 = 92
    static let dollar: UInt16 = 36
    static let at: UInt16 = 64
    static let hash: UInt16 = 35
    static let dot: UInt16 = 46
    static let colon: UInt16 = 58
    static let openParen: UInt16 = 40
    static let openBrace: UInt16 = 123
    static let closeBrace: UInt16 = 125
    static let underscore: UInt16 = 95
    static let minus: UInt16 = 45
    static let bang: UInt16 = 33
    static let less: UInt16 = 60
    static let greater: UInt16 = 62
    static let slash: UInt16 = 47
    static let equals: UInt16 = 61
    static let question: UInt16 = 63
    static let ampersand: UInt16 = 38
    static let semicolon: UInt16 = 59
    static let openBracket: UInt16 = 91

    static func isDigit(_ unit: UInt16) -> Bool { unit >= 48 && unit <= 57 }
    static func isLetter(_ unit: UInt16) -> Bool { (unit | 0x20) >= 97 && (unit | 0x20) <= 122 }
    static func isUpper(_ unit: UInt16) -> Bool { unit >= 65 && unit <= 90 }
    static func isSpace(_ unit: UInt16) -> Bool {
        unit == space || unit == tab || unit == newline || unit == carriageReturn
    }
    /// Operator characters drawn in the punctuation colour.
    static let operators: Set<UInt16> = Set("=+-*/%<>!&|^~?:".utf16)
}

extension CodeGrammar {
    static func grammar(for language: CodeLanguage) -> CodeGrammar? {
        switch language {
        case .swift: swift
        case .javascript: javascript
        case .typescript: typescript
        case .python: python
        case .json: json
        case .css: css
        case .shell: shell
        case .go: go
        case .rust: rust
        case .sql: sql
        case .markup, .plainText: nil
        }
    }

    private static func words(_ list: String) -> Set<String> {
        Set(list.split(separator: " ").map(String.init))
    }

    static let swift = CodeGrammar(
        keywords: words(
            "associatedtype class deinit enum extension fileprivate func import init inout internal let open operator "
                + "private protocol public rethrows static struct subscript typealias var break case continue default "
                + "defer do else fallthrough for guard if in repeat return switch where while as catch false is nil "
                + "super self Self throw throws true try async await actor some any mutating nonmutating override "
                + "final lazy weak unowned convenience required get set willSet didSet consume borrowing consuming"),
        types: words("Int Double Float String Bool Character Array Dictionary Set Optional Void Never Error Any"),
        builtins: words("print debugPrint min max abs zip stride"),
        lineComments: ["//"], blockComment: ("/*", "*/"), quotes: [ASCII.doubleQuote], tripleQuotes: true,
        capitalizedAreTypes: true, attributePrefix: ASCII.at, directivePrefix: ASCII.hash)

    static let javascript = CodeGrammar(
        keywords: words(
            "break case catch class const continue debugger default delete do else export extends finally for "
                + "function if import in instanceof let new return super switch this throw try typeof var void while "
                + "with yield async await of static get set from as true false null undefined NaN Infinity"),
        types: words("Array Object String Number Boolean Promise Map Set Date RegExp Error Symbol JSON Math"),
        builtins: words("console require setTimeout setInterval parseInt parseFloat fetch"),
        lineComments: ["//"], blockComment: ("/*", "*/"), multilineQuotes: [ASCII.backtick],
        identifierExtras: [ASCII.dollar], attributePrefix: ASCII.at)

    static let typescript: CodeGrammar = {
        var grammar = javascript
        grammar.keywords.formUnion(
            words(
                "interface type enum implements namespace declare abstract readonly private protected public "
                    + "keyof infer is satisfies asserts module"))
        grammar.types.formUnion(words("string number boolean any unknown never void object bigint symbol Record"))
        grammar.capitalizedAreTypes = true
        return grammar
    }()

    static let python = CodeGrammar(
        keywords: words(
            "and as assert async await break class continue def del elif else except finally for from global if "
                + "import in is lambda nonlocal not or pass raise return try while with yield match case True False "
                + "None self"),
        types: words("int float str bool list dict set tuple bytes object type"),
        builtins: words("print len range open enumerate zip map filter sorted isinstance super input"),
        lineComments: ["#"], tripleQuotes: true, capitalizedAreTypes: true, attributePrefix: ASCII.at)

    static let json = CodeGrammar(
        keywords: words("true false null"), quotes: [ASCII.doubleQuote], colonProperties: true)

    static let css = CodeGrammar(
        keywords: words("important inherit initial unset none auto"), blockComment: ("/*", "*/"),
        identifierExtras: [ASCII.minus], attributePrefix: ASCII.at, colonProperties: true, css: true)

    static let shell = CodeGrammar(
        keywords: words(
            "if then else elif fi for while until do done case esac in function return local export readonly "
                + "declare select time break continue"),
        builtins: words(
            "echo cd ls cat grep sed awk printf read source exit set unset test mkdir rm cp mv chmod sudo git "
                + "curl make brew npm swift xcodebuild"),
        lineComments: ["#"], identifierExtras: [ASCII.minus], variablePrefix: ASCII.dollar)

    static let go = CodeGrammar(
        keywords: words(
            "break case chan const continue default defer else fallthrough for func go goto if import interface "
                + "map package range return select struct switch type var true false nil iota"),
        types: words(
            "bool byte complex64 complex128 error float32 float64 int int8 int16 int32 int64 rune string uint "
                + "uint8 uint16 uint32 uint64 uintptr any"),
        builtins: words("append cap close copy delete len make new panic print println recover"),
        lineComments: ["//"], blockComment: ("/*", "*/"), multilineQuotes: [ASCII.backtick])

    static let rust = CodeGrammar(
        keywords: words(
            "as async await break const continue crate dyn else enum extern false fn for if impl in let loop match "
                + "mod move mut pub ref return self Self static struct super trait true type unsafe use where while"),
        types: words(
            "i8 i16 i32 i64 i128 isize u8 u16 u32 u64 u128 usize f32 f64 bool char str String Vec Option Result Box"),
        lineComments: ["//"], blockComment: ("/*", "*/"), quotes: [ASCII.doubleQuote, ASCII.singleQuote],
        capitalizedAreTypes: true, directivePrefix: ASCII.hash, bangMacros: true, lifetimes: true)

    static let sql = CodeGrammar(
        keywords: words(
            "select from where and or not insert into values update set delete create table drop alter add index "
                + "view join inner left right outer full on as group by order having limit offset distinct union "
                + "all case when then else end is null like in between exists primary key foreign references "
                + "default unique asc desc with returning true false begin commit rollback"),
        types: words(
            "int integer bigint smallint decimal numeric real float double varchar char text boolean date time "
                + "timestamp uuid json jsonb serial blob"),
        builtins: words("count sum avg min max coalesce now lower upper length cast"),
        lineComments: ["--"], blockComment: ("/*", "*/"), caseInsensitive: true)
}
