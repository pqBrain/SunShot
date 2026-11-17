/// HTML / XML: comments, CDATA, tags, attributes, attribute values, entities. Text between tags stays plain.
struct MarkupScanner {
    var cursor: UnitCursor

    init(units: [UInt16]) { cursor = UnitCursor(units: units) }

    mutating func scan() -> [CodeToken] {
        var index = 0
        while index < cursor.count {
            index = step(at: index)
        }
        return cursor.tokens
    }

    private func isNameUnit(_ unit: UInt16) -> Bool {
        ASCII.isLetter(unit) || ASCII.isDigit(unit) || unit >= 0x80
            || unit == ASCII.minus || unit == ASCII.colon || unit == ASCII.underscore || unit == ASCII.dot
    }

    private func nameEnd(from index: Int) -> Int {
        var position = index
        while let unit = cursor.unit(position), isNameUnit(unit) { position += 1 }
        return position
    }

    private mutating func step(at index: Int) -> Int {
        if cursor.matches("<!--", at: index) {
            let end = cursor.end(of: "-->", from: index + 4)
            cursor.emit(.comment, index, end)
            return end
        }
        if cursor.matches("<![CDATA[", at: index) {
            let end = cursor.end(of: "]]>", from: index + 9)
            cursor.emit(.string, index, end)
            return end
        }
        let unit = cursor.units[index]
        if unit == ASCII.less, let next = cursor.unit(index + 1),
            isNameUnit(next) || next == ASCII.slash || next == ASCII.bang || next == ASCII.question
        {
            return tag(at: index)
        }
        if unit == ASCII.ampersand {
            var position = index + 1
            while let next = cursor.unit(position), position - index <= 10, isNameUnit(next) || next == ASCII.hash {
                position += 1
            }
            if cursor.unit(position) == ASCII.semicolon {
                cursor.emit(.keyword, index, position + 1)
                return position + 1
            }
        }
        return index + 1
    }

    /// `<name attr="value" …>`; an unclosed tag runs to the end of the text.
    private mutating func tag(at index: Int) -> Int {
        var position = index + 1
        while let unit = cursor.unit(position), unit == ASCII.slash || unit == ASCII.bang || unit == ASCII.question {
            position += 1
        }
        cursor.emit(.punctuation, index, position)
        let nameEnd = nameEnd(from: position)
        cursor.emit(.tag, position, nameEnd)
        position = nameEnd
        while let unit = cursor.unit(position) {
            if unit == ASCII.greater {
                cursor.emit(.punctuation, position, position + 1)
                return position + 1
            }
            if unit == ASCII.slash || unit == ASCII.question || unit == ASCII.equals {
                cursor.emit(.punctuation, position, position + 1)
                position += 1
            } else if unit == ASCII.doubleQuote || unit == ASCII.singleQuote {
                let end = cursor.stringEnd(from: position, quote: unit, multiline: true)
                cursor.emit(.string, position, end)
                position = end
            } else if isNameUnit(unit) {
                let end = self.nameEnd(from: position)
                cursor.emit(.attribute, position, end)
                position = end
            } else {
                position += 1
            }
        }
        return position
    }
}
