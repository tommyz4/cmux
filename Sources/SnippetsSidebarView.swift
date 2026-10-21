import AppKit
import CmuxFoundation
import CmuxTextActions
import SwiftUI

/// Right-sidebar Snippets tool: a search field over every `type: "text"`
/// action and a flat, ranked list. Selecting a row pastes the snippet into
/// the focused terminal through the project-trust gate.
struct SnippetsSidebarView: View {
    @ObservedObject var tabManager: TabManager
    @EnvironmentObject private var cmuxConfigStore: CmuxConfigStore
    @StateObject private var store = SnippetsSidebarStore()
    @Environment(\.cmuxGlobalFontMagnificationPercent) private var globalFontPercent

    private var searchFieldHeight: CGFloat {
        _ = globalFontPercent
        return SidebarSearchField.visibleHeight
    }

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            content
        }
        .background(
            SnippetsSidebarFocusBridge(
                onMove: { store.moveSelection(by: $0) },
                onActivate: activateSelection,
                onEscape: returnFocusToTerminal
            )
            .frame(width: 1, height: 1)
        )
        .onAppear { store.attach(configStore: cmuxConfigStore) }
        .onDisappear { store.detach() }
    }

    private var searchBar: some View {
        HStack(spacing: RightSidebarChromeMetrics.headerControlSpacing) {
            SidebarSearchFieldView(
                text: $store.query,
                placeholder: String(localized: "snippetsSidebar.searchPlaceholder", defaultValue: "Search snippets…"),
                accessibilityIdentifier: SnippetsSidebarFocusBridge.searchFieldIdentifier,
                onSubmit: activateSelection,
                onCommandSubmit: activateSelection
            )
            .frame(height: searchFieldHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .titlebarInteractiveControl()
            addButton
        }
        .frame(height: searchFieldHeight)
        .padding(.leading, SidebarSearchField.leadingPadding)
        .padding(.trailing, RightSidebarChromeMetrics.headerTrailingPadding)
        .padding(.top, SidebarSearchField.topPadding)
        .padding(.bottom, RightSidebarChromeMetrics.barVerticalPadding)
    }

    /// Opens Settings > Snippets, where snippets are added and edited. Same
    /// 20-point header control as the Vault bar's view menu.
    private var addButton: some View {
        Button {
            AppDelegate.presentPreferencesWindow(navigationTarget: .snippets)
        } label: {
            HeaderChromeIconStyle.symbol("plus")
        }
        .buttonStyle(RightSidebarHeaderIconButtonStyle(iconGeometryKeyPrefix: "rightSidebarSnippetsAddIcon"))
        .frame(
            width: RightSidebarChromeMetrics.headerControlSize,
            height: RightSidebarChromeMetrics.headerControlSize
        )
        .help(String(localized: "snippetsSidebar.add.tooltip", defaultValue: "Add or edit snippets in Settings"))
        .accessibilityLabel(Text(String(localized: "snippetsSidebar.add.label", defaultValue: "Add Snippet")))
        .accessibilityIdentifier("SnippetsSidebarAddButton")
        .titlebarInteractiveControl()
    }

    @ViewBuilder
    private var content: some View {
        if store.entries.isEmpty {
            emptyState(
                title: String(localized: "snippetsSidebar.empty.title", defaultValue: "No snippets configured"),
                detail: String(localized: "snippetsSidebar.empty.hint", defaultValue: "Use + to add one in Settings.")
            )
        } else if store.results.isEmpty {
            emptyState(title: String(localized: "snippetsSidebar.noMatches", defaultValue: "No matches"), detail: nil)
        } else {
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(store.results, id: \.actionID) { entry in
                            SnippetsSidebarRow(
                                entry: entry,
                                isSelected: entry.actionID == store.selectedActionID,
                                onActivate: {
                                    store.select(actionID: entry.actionID)
                                    deliver(entry)
                                }
                            )
                            .id(entry.actionID)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .onChange(of: store.selectedActionID) { _, id in
                    if let id { proxy.scrollTo(id) }
                }
            }
        }
    }

    private func emptyState(title: String, detail: String?) -> some View {
        VStack(spacing: 6) {
            Text(title)
                .cmuxFont(size: 12, weight: .medium)
                .foregroundColor(.secondary)
            if let detail {
                Text(detail)
                    .cmuxFont(size: 11)
                    .foregroundColor(.secondary.opacity(0.8))
                    .multilineTextAlignment(.center)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func activateSelection() {
        guard let entry = store.selectedEntry else {
            NSSound.beep()
            return
        }
        deliver(entry)
    }

    /// Same gate and delivery as the palette: the workspace's focused
    /// terminal input target stays valid while the sidebar holds key focus.
    /// A refused or failed paste keeps the sidebar (the executor beeps on a
    /// failed paste); a delivered paste hands focus back to the terminal.
    private func deliver(_ entry: CmuxSnippetMenuEntry) {
        guard let action = cmuxConfigStore.resolvedAction(id: entry.actionID),
              let payload = action.action.textPayload,
              tabManager.selectedWorkspace?.focusedTerminalInputTarget() != nil else {
            NSSound.beep()
            return
        }
        _ = CmuxConfigExecutor.executeTextAction(
            payload,
            confirm: action.confirm ?? false,
            actionID: action.id,
            configSourcePath: action.actionSourcePath,
            globalConfigPath: cmuxConfigStore.globalConfigPath,
            displayTitle: action.title,
            icon: action.icon,
            iconSourcePath: action.iconSourcePath,
            tabManager: tabManager,
            presentingWindow: NSApp.keyWindow,
            onExecuted: returnFocusToTerminal
        )
    }

    private func returnFocusToTerminal() {
        guard let window = NSApp.keyWindow,
              let coordinator = AppDelegate.shared?.keyboardFocusCoordinator(for: window) else { return }
        _ = coordinator.restoreFocusedPanelFocusFromRightSidebarIfNeeded()
    }
}
