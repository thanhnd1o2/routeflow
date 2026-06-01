import SwiftUI

struct RulesView: View {
    @EnvironmentObject var appState: AppState
    @State private var showingAddRule = false
    @State private var editingRule: RoutingRule?
    @State private var ruleToDelete: RoutingRule?
    @State private var showingDeleteConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(appState.rules.count) rules")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("(drag to reorder, click to edit)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                Spacer()

                Button(action: { showingAddRule = true }) {
                    Label("Add Rule", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(16)

            Divider()

            List {
                ForEach(appState.rules) { rule in
                    RuleRowView(
                        rule: rule,
                        interfaceName: appState.interfaces.first(where: { $0.id == rule.interfaceId })?.name ?? rule.interfaceId,
                        onToggle: {
                            appState.toggleRule(id: rule.id)
                        },
                        onEdit: {
                            editingRule = rule
                        },
                        onDelete: {
                            ruleToDelete = rule
                            showingDeleteConfirmation = true
                        }
                    )
                }
                .onMove(perform: appState.moveRules)
            }
            .listStyle(.inset)
        }
        .navigationTitle("Routing Rules")
        .sheet(isPresented: $showingAddRule) {
            AddRuleView()
        }
        .sheet(item: $editingRule) { rule in
            EditRuleView(rule: rule)
        }
        .alert("Delete Rule", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
                ruleToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let rule = ruleToDelete,
                   let idx = appState.rules.firstIndex(where: { $0.id == rule.id }) {
                    appState.deleteRules(at: IndexSet(integer: idx))
                }
                ruleToDelete = nil
            }
        } message: {
            if let rule = ruleToDelete {
                Text("Are you sure you want to delete the rule for \"\(rule.pattern)\"?")
            }
        }
    }

    private func moveRuleUp(at index: Int) {
        guard index > 0 else { return }
        appState.moveRules(from: IndexSet(integer: index), to: index - 1)
    }

    private func moveRuleDown(at index: Int) {
        guard index < appState.rules.count - 1 else { return }
        appState.moveRules(from: IndexSet(integer: index), to: index + 2)
    }
}

// MARK: - Rule Row

struct RuleRowView: View {
    let rule: RoutingRule
    let interfaceName: String
    var onToggle: () -> Void
    var onEdit: () -> Void
    var onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(rule.matchType.rawValue)
                .font(.caption)
                .fontWeight(.medium)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(matchTypeColor.opacity(0.1)))
                .foregroundStyle(matchTypeColor)

            Text(rule.pattern)
                .font(.body)
                .fontWeight(.medium)

            Spacer()

            Image(systemName: "arrow.right")
                .foregroundStyle(.secondary)

            Text(interfaceName)
                .font(.body)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 6).fill(.blue.opacity(0.1)))
                .foregroundStyle(.blue)

            Button(action: onToggle) {
                Circle()
                    .fill(rule.isEnabled ? Color.green : Color.gray)
                    .frame(width: 10, height: 10)
            }
            .buttonStyle(.plain)
            .help(rule.isEnabled ? "Disable rule" : "Enable rule")

            Button(action: onEdit) {
                Image(systemName: "pencil.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.blue.opacity(0.7))
            }
            .buttonStyle(.plain)
            .help("Edit rule")

            Button(action: onDelete) {
                Image(systemName: "trash.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.red.opacity(0.6))
            }
            .buttonStyle(.plain)
            .help("Delete rule")
        }
        .padding(.vertical, 4)
    }

    private var matchTypeColor: Color {
        switch rule.matchType {
        case .domain: return .purple
        case .domainSuffix: return .orange
        case .domainKeyword: return .teal
        }
    }
}

// MARK: - Add Rule Sheet

struct AddRuleView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var matchType: RoutingRule.MatchType = .domainSuffix
    @State private var pattern: String = ""
    @State private var selectedInterface: String = "wifi"

    var body: some View {
        VStack(spacing: 20) {
            Text("Add Routing Rule")
                .font(.title2)
                .fontWeight(.semibold)

            Form {
                Picker("Match Type", selection: $matchType) {
                    ForEach(RoutingRule.MatchType.allCases, id: \.self) { type in
                        Text(type.displayName).tag(type)
                    }
                }

                TextField("Pattern (e.g. github.com)", text: $pattern)

                Picker("Interface", selection: $selectedInterface) {
                    ForEach(appState.interfaces) { iface in
                        Text(iface.name).tag(iface.id)
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)

                Spacer()

                Button("Add Rule") {
                    let rule = RoutingRule(
                        matchType: matchType,
                        pattern: pattern,
                        interfaceId: selectedInterface
                    )
                    appState.addRule(rule)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(pattern.isEmpty)
            }
            .padding(.horizontal)
        }
        .padding(20)
        .frame(width: 450, height: 320)
    }
}

// MARK: - Edit Rule Sheet

struct EditRuleView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let rule: RoutingRule
    @State private var matchType: RoutingRule.MatchType
    @State private var pattern: String
    @State private var selectedInterface: String
    @State private var isEnabled: Bool

    init(rule: RoutingRule) {
        self.rule = rule
        _matchType = State(initialValue: rule.matchType)
        _pattern = State(initialValue: rule.pattern)
        _selectedInterface = State(initialValue: rule.interfaceId)
        _isEnabled = State(initialValue: rule.isEnabled)
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("Edit Routing Rule")
                .font(.title2)
                .fontWeight(.semibold)

            Form {
                Picker("Match Type", selection: $matchType) {
                    ForEach(RoutingRule.MatchType.allCases, id: \.self) { type in
                        Text(type.displayName).tag(type)
                    }
                }

                TextField("Pattern", text: $pattern)

                Picker("Interface", selection: $selectedInterface) {
                    ForEach(appState.interfaces) { iface in
                        Text(iface.name).tag(iface.id)
                    }
                }

                Toggle("Enabled", isOn: $isEnabled)
            }
            .formStyle(.grouped)

            HStack {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)

                Spacer()

                Button("Save") {
                    let updated = RoutingRule(
                        id: rule.id,
                        matchType: matchType,
                        pattern: pattern,
                        interfaceId: selectedInterface,
                        isEnabled: isEnabled
                    )
                    appState.updateRule(updated)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(pattern.isEmpty)
            }
            .padding(.horizontal)
        }
        .padding(20)
        .frame(width: 450, height: 380)
    }
}
