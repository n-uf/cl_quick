// Models: the models each profile's account can use, as Claude Code lists them. The chat's `claude` is asked when it
// starts (`initialize`, which sends nothing to a model); the list is kept per profile and account, in memory and in
// models.json, so Settings can show it without starting `claude`. From it the chat takes the newest of each family
// (QuickChatModels in Engine.swift) and the thinking steps that model takes. Before any list is known: the aliases, and
// thinking Low to High.

import Foundation

final class ModelCatalog {
    static let shared = ModelCatalog()
    /// Posted (main thread) when a list changed.
    static let changed = Notification.Name("cl_quick.models.changed")

    /// "<profile id>|<account uuid>" → the list.
    private(set) var lists: [String: [QuickChatModelEntry]]

    init() { lists = Files.read([String: [QuickChatModelEntry]].self, Files.models) ?? [:] }

    static func key(_ profile: String, _ account: String?) -> String { profile + "|" + (account ?? "") }

    /// The list Claude Code gave last for the profile's account; nil before one was given.
    func list(profile: String, account: String?) -> [QuickChatModelEntry]? { lists[Self.key(profile, account)] }

    /// A list Claude Code gave: kept, and written when it changed. Main thread.
    func set(_ list: [QuickChatModelEntry], profile: String, account: String?) {
        let k = Self.key(profile, account)
        guard lists[k] != list else { return }
        lists[k] = list
        Files.write(lists, Files.models)
        NotificationCenter.default.post(name: Self.changed, object: nil)
    }

    /// The four families as a picker offers them for a list: the ones the account has, each by its newest name; with no
    /// list known, all four by family.
    static func choices(_ list: [QuickChatModelEntry]?) -> [(choice: QuickChatModelChoice, title: String)] {
        guard let list else { return QuickChatModelChoice.allCases.map { ($0, $0.title) } }
        let have = QuickChatModels.newest(list)
        return QuickChatModelChoice.allCases.compactMap { c in have[c].map { (c, $0.displayName) } }
    }

    /// The thinking steps for a family on a list (Off, then what its model takes), and the step a saved one becomes.
    static func thinking(_ saved: QuickChatThinking, family: QuickChatModelChoice, list: [QuickChatModelEntry]?) -> (steps: [QuickChatThinking], now: QuickChatThinking) {
        let entry = QuickChatModels.resolve(family, in: list).entry
        let steps = QuickChatModels.steps(entry, listKnown: list != nil)
        return (steps.compactMap(QuickChatThinking.init(rawValue:)),
                QuickChatThinking(rawValue: QuickChatModels.clamp(saved.rawValue, to: steps)) ?? .off)
    }
}

extension QuickChatModel {
    /// The list for the profile and account the chat is on, if Claude Code gave one.
    var modelList: [QuickChatModelEntry]? {
        target.flatMap { ModelCatalog.shared.list(profile: $0.profileID, account: $0.accountUUID) }
    }
    /// The model the chat answers with: the chosen family's newest on the account (or the nearest family it has).
    var resolvedModel: (family: QuickChatModelChoice, value: String, entry: QuickChatModelEntry?) {
        QuickChatModels.resolve(choice, in: modelList)
    }
    /// The families the chat's model control steps through.
    var modelChoices: [(choice: QuickChatModelChoice, title: String)] { ModelCatalog.choices(modelList) }
    /// The thinking steps that model takes, and the chosen step clamped to them.
    var thinkingSteps: [QuickChatThinking] { ModelCatalog.thinking(thinking, family: resolvedModel.family, list: modelList).steps }
    var effectiveThinking: QuickChatThinking { ModelCatalog.thinking(thinking, family: resolvedModel.family, list: modelList).now }
}
