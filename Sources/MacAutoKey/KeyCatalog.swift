import Foundation

struct KeyStroke: Equatable, Sendable {
    var code: UInt16
    var shift: Bool
}

enum KeyCatalog {
    struct Key: Identifiable, Sendable {
        var name: String
        var code: UInt16
        var id: UInt16 { code }
    }
    // macOS virtual key codes, explicitly US ANSI positions. No layout assumptions
    // are hidden: Unicode mode is available for non-US text input.
    static let letters: [(String, UInt16)] = [
        ("A",0),("B",11),("C",8),("D",2),("E",14),("F",3),("G",5),
        ("H",4),("I",34),("J",38),("K",40),("L",37),("M",46),("N",45),
        ("O",31),("P",35),("Q",12),("R",15),("S",1),("T",17),("U",32),
        ("V",9),("W",13),("X",7),("Y",16),("Z",6)
    ]
    static let digits: [(String, UInt16)] = [
        ("0",29),("1",18),("2",19),("3",20),("4",21),("5",23),
        ("6",22),("7",26),("8",28),("9",25)
    ]
    static let special: [(String, UInt16)] = [
        ("Enter",36),("Tab",48),("Space",49),("Backspace",51),("Escape",53),
        ("Arrow Up",126),("Arrow Down",125),("Arrow Left",123),("Arrow Right",124),
        ("Forward Delete",117),("Home",115),("End",119),("Page Up",116),("Page Down",121)
    ]
    static let functions: [(String, UInt16)] = zip(
        (1...20).map { "F\($0)" },
        [122,120,99,118,96,97,98,100,101,109,103,111,105,107,113,106,64,79,80,90].map(UInt16.init)
    ).map { ($0, $1) }
    static let punctuation: [(String, UInt16)] = [
        ("-",27),("=",24),("[",33),("]",30),("\\",42),(";",41),("'",39),
        (",",43),(".",47),("/",44),("`",50)
    ]
    static let keys: [Key] = (special + letters + digits + punctuation + functions).map { Key(name: $0.0, code: $0.1) }
    static func name(for code: UInt16) -> String { keys.first { $0.code == code }?.name ?? "Unknown key" }
    static func stroke(for character: Character) -> KeyStroke? {
        let string = String(character)
        if character == "\n" || character == "\r" { return .init(code: 36, shift: false) }
        if character == "\t" { return .init(code: 48, shift: false) }
        if character == " " { return .init(code: 49, shift: false) }
        if let pair = (letters + digits + punctuation).first(where: { $0.0.lowercased() == string.lowercased() }) {
            return .init(code: pair.1, shift: string != string.lowercased())
        }
        let shifted = Array(")!@#$%^&*(")
        if let i = shifted.firstIndex(of: character) { return .init(code: digits[i].1, shift: true) }
        let symbols: [Character: UInt16] = ["_":27,"+":24,"{":33,"}":30,"|":42,":":41,"\"":39,"<":43,">":47,"?":44,"~":50]
        return symbols[character].map { .init(code: $0, shift: true) }
    }
}
