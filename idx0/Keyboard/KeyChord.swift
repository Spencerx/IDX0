import AppKit
import SwiftUI

enum ShortcutModifier: String, Codable, CaseIterable, Hashable, Sendable {
    case command
    case option
    case shift
    case control

    var symbol: String {
        switch self {
        case .command:
            return "⌘"
        case .option:
            return "⌥"
        case .shift:
            return "⇧"
        case .control:
            return "⌃"
        }
    }

    var eventFlag: NSEvent.ModifierFlags {
        switch self {
        case .command:
            return .command
        case .option:
            return .option
        case .shift:
            return .shift
        case .control:
            return .control
        }
    }

    var swiftUIModifier: EventModifiers {
        switch self {
        case .command:
            return .command
        case .option:
            return .option
        case .shift:
            return .shift
        case .control:
            return .control
        }
    }
}

enum ShortcutKey: String, Codable, CaseIterable, Hashable, Sendable {
    case a
    case b
    case c
    case d
    case e
    case f
    case g
    case h
    case i
    case j
    case k
    case l
    case m
    case n
    case o
    case p
    case q
    case r
    case s
    case t
    case u
    case v
    case w
    case x
    case y
    case z
    case digit1
    case digit2
    case digit3
    case digit4
    case digit5
    case digit6
    case digit7
    case digit8
    case digit9
    case comma
    case minus
    case equal
    case openBracket
    case closeBracket
    case backslash
    case tab
    case returnKey
    case leftArrow
    case rightArrow
    case upArrow
    case downArrow
    case pageUp
    case pageDown

    var displayText: String {
        switch self {
        case .a: return "A"
        case .b: return "B"
        case .c: return "C"
        case .d: return "D"
        case .e: return "E"
        case .f: return "F"
        case .g: return "G"
        case .h: return "H"
        case .i: return "I"
        case .j: return "J"
        case .k: return "K"
        case .l: return "L"
        case .m: return "M"
        case .n: return "N"
        case .o: return "O"
        case .p: return "P"
        case .q: return "Q"
        case .r: return "R"
        case .s: return "S"
        case .t: return "T"
        case .u: return "U"
        case .v: return "V"
        case .w: return "W"
        case .x: return "X"
        case .y: return "Y"
        case .z: return "Z"
        case .digit1: return "1"
        case .digit2: return "2"
        case .digit3: return "3"
        case .digit4: return "4"
        case .digit5: return "5"
        case .digit6: return "6"
        case .digit7: return "7"
        case .digit8: return "8"
        case .digit9: return "9"
        case .comma: return ","
        case .minus: return "-"
        case .equal: return "="
        case .openBracket: return "["
        case .closeBracket: return "]"
        case .backslash: return "\\"
        case .tab: return "Tab"
        case .returnKey: return "↵"
        case .leftArrow: return "←"
        case .rightArrow: return "→"
        case .upArrow: return "↑"
        case .downArrow: return "↓"
        case .pageUp: return "PgUp"
        case .pageDown: return "PgDn"
        }
    }

    var keyEquivalent: KeyEquivalent {
        switch self {
        case .a: return "a"
        case .b: return "b"
        case .c: return "c"
        case .d: return "d"
        case .e: return "e"
        case .f: return "f"
        case .g: return "g"
        case .h: return "h"
        case .i: return "i"
        case .j: return "j"
        case .k: return "k"
        case .l: return "l"
        case .m: return "m"
        case .n: return "n"
        case .o: return "o"
        case .p: return "p"
        case .q: return "q"
        case .r: return "r"
        case .s: return "s"
        case .t: return "t"
        case .u: return "u"
        case .v: return "v"
        case .w: return "w"
        case .x: return "x"
        case .y: return "y"
        case .z: return "z"
        case .digit1: return "1"
        case .digit2: return "2"
        case .digit3: return "3"
        case .digit4: return "4"
        case .digit5: return "5"
        case .digit6: return "6"
        case .digit7: return "7"
        case .digit8: return "8"
        case .digit9: return "9"
        case .comma: return ","
        case .minus: return "-"
        case .equal: return "="
        case .openBracket: return "["
        case .closeBracket: return "]"
        case .backslash: return "\\"
        case .tab: return .tab
        case .returnKey: return .return
        case .leftArrow: return .leftArrow
        case .rightArrow: return .rightArrow
        case .upArrow: return .upArrow
        case .downArrow: return .downArrow
        case .pageUp:
            return .pageUp
        case .pageDown:
            return .pageDown
        }
    }

    var allowsImplicitShiftMatch: Bool {
        switch self {
        case .equal:
            return true
        default:
            return false
        }
    }

    static func from(event: NSEvent) -> ShortcutKey? {
        switch Int(event.keyCode) {
        case 36:
            return .returnKey
        case 48:
            return .tab
        case 116:
            return .pageUp
        case 121:
            return .pageDown
        case 123:
            return .leftArrow
        case 124:
            return .rightArrow
        case 125:
            return .downArrow
        case 126:
            return .upArrow
        default:
            break
        }

        let characters = (event.charactersIgnoringModifiers ?? "").lowercased()
        switch characters {
        case "a": return .a
        case "b": return .b
        case "c": return .c
        case "d": return .d
        case "e": return .e
        case "f": return .f
        case "g": return .g
        case "h": return .h
        case "i": return .i
        case "j": return .j
        case "k": return .k
        case "l": return .l
        case "m": return .m
        case "n": return .n
        case "o": return .o
        case "p": return .p
        case "q": return .q
        case "r": return .r
        case "s": return .s
        case "t": return .t
        case "u": return .u
        case "v": return .v
        case "w": return .w
        case "x": return .x
        case "y": return .y
        case "z": return .z
        case "1": return .digit1
        case "2": return .digit2
        case "3": return .digit3
        case "4": return .digit4
        case "5": return .digit5
        case "6": return .digit6
        case "7": return .digit7
        case "8": return .digit8
        case "9": return .digit9
        case ",": return .comma
        case "-": return .minus
        case "=": return .equal
        case "[": return .openBracket
        case "]": return .closeBracket
        case "\\": return .backslash
        default:
            return nil
        }
    }
}

struct KeyChord: Codable, Equatable, Hashable, Sendable {
    var key: ShortcutKey
    var modifiers: Set<ShortcutModifier>

    init(key: ShortcutKey, modifiers: Set<ShortcutModifier> = []) {
        self.key = key
        self.modifiers = modifiers
    }

    private enum CodingKeys: String, CodingKey {
        case key
        case modifiers
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = try container.decode(ShortcutKey.self, forKey: .key)
        modifiers = Set(try container.decodeIfPresent([ShortcutModifier].self, forKey: .modifiers) ?? [])
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(key, forKey: .key)
        let encodedModifiers = modifiers.sorted { $0.rawValue < $1.rawValue }
        try container.encode(encodedModifiers, forKey: .modifiers)
    }

    var displayString: String {
        let order: [ShortcutModifier] = [.control, .option, .shift, .command]
        let modifierText = order
            .filter { modifiers.contains($0) }
            .map(\.symbol)
            .joined()
        return modifierText + key.displayText
    }

    var swiftUIModifiers: EventModifiers {
        modifiers.reduce(EventModifiers()) { partial, modifier in
            partial.union(modifier.swiftUIModifier)
        }
    }

    func matches(event: NSEvent) -> Bool {
        guard let eventKey = ShortcutKey.from(event: event), eventKey == key else {
            return false
        }

        var eventModifiers = KeyChord.modifierSet(from: event.modifierFlags)
        if key.allowsImplicitShiftMatch && !modifiers.contains(.shift) {
            eventModifiers.remove(.shift)
        }
        return eventModifiers == modifiers
    }

    static func from(event: NSEvent) -> KeyChord? {
        guard let key = ShortcutKey.from(event: event) else {
            return nil
        }
        let modifiers = modifierSet(from: event.modifierFlags)
        return KeyChord(key: key, modifiers: modifiers)
    }

    private static func modifierSet(from flags: NSEvent.ModifierFlags) -> Set<ShortcutModifier> {
        let filtered = flags.intersection([.command, .option, .shift, .control])
        var set: Set<ShortcutModifier> = []
        if filtered.contains(.command) {
            set.insert(.command)
        }
        if filtered.contains(.option) {
            set.insert(.option)
        }
        if filtered.contains(.shift) {
            set.insert(.shift)
        }
        if filtered.contains(.control) {
            set.insert(.control)
        }
        return set
    }
}

enum KeybindingMode: String, Codable, CaseIterable {
    case both
    case macOSFirst
    case niriFirst
    case custom

    var displayName: String {
        switch self {
        case .both:
            return "Both"
        case .macOSFirst:
            return "macOS-first"
        case .niriFirst:
            return "Niri-first"
        case .custom:
            return "Custom"
        }
    }
}

enum ModKeySetting: String, Codable, CaseIterable {
    case commandOption
    case command
    case option
    case control
    case commandControl
    case optionControl

    var displayName: String {
        switch self {
        case .commandOption:
            return "Command+Option"
        case .command:
            return "Command"
        case .option:
            return "Option"
        case .control:
            return "Control"
        case .commandControl:
            return "Command+Control"
        case .optionControl:
            return "Option+Control"
        }
    }

    var modifiers: Set<ShortcutModifier> {
        switch self {
        case .commandOption:
            return [.command, .option]
        case .command:
            return [.command]
        case .option:
            return [.option]
        case .control:
            return [.control]
        case .commandControl:
            return [.command, .control]
        case .optionControl:
            return [.option, .control]
        }
    }
}

extension View {
    @ViewBuilder
    func keyboardShortcut(_ chord: KeyChord?) -> some View {
        if let chord {
            self.keyboardShortcut(chord.key.keyEquivalent, modifiers: chord.swiftUIModifiers)
        } else {
            self
        }
    }
}
