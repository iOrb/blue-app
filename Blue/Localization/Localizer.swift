import Foundation
import Observation

@MainActor
@Observable
final class Localizer {
    var language: AppLanguage {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: "blue.language") }
    }
    init(language: AppLanguage? = nil) {
        self.language =
            language ?? AppLanguage(rawValue: UserDefaults.standard.string(forKey: "blue.language") ?? "en") ?? .english
    }
    var locale: Locale { language.locale }
    func callAsFunction(_ key: String) -> String {
        let path = Bundle.main.path(forResource: language.rawValue, ofType: "lproj")
        let bundle = path.flatMap(Bundle.init(path:)) ?? Bundle.main
        return bundle.localizedString(forKey: key, value: key, table: "Localizable")
    }
    func text(_ value: LocalText) -> String {
        if let key = value.key { return self(key) }
        return language == .spanish ? value.spanish : value.english
    }
    func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: self(key), locale: locale, arguments: arguments)
    }
    func number(_ value: Double) -> String { value.formatted(.number.locale(locale).precision(.fractionLength(0...1))) }
    func date(_ date: Date) -> String { date.formatted(.dateTime.day().month(.wide).locale(locale)) }
    func time(_ date: Date) -> String { date.formatted(.dateTime.hour().minute().locale(locale)) }
    func value(_ value: FieldValue?, field: FieldDefinition) -> String {
        guard let value else { return self("value.empty") }
        switch value {
        case .text(let text): return text
        case .number(let value): return number(value)
        case .date(let date): return self.date(date)
        case .flag(let flag): return self(flag ? "yes" : "no")
        case .tags(let values): return values.joined(separator: ", ")
        case .option(let id): return field.options.first { $0.id == id }.map { text($0.label) } ?? id
        }
    }
    func error(_ error: Error) -> String { self((error as? BlueError ?? .saveFailed).key) }
}
