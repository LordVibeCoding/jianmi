import SwiftUI

/// 主窗口：三栏（分类 / 条目列表 / 详情）。
@MainActor
struct MainView: View {
    @EnvironmentObject private var app: AppState
    @ObservedObject var store: EntryStore
    @ObservedObject private var categories = CategoryStore.shared

    @State private var selectedID: Entry.ID?
    @State private var showingEditor = false
    @State private var categorySheet: CategorySheetTarget?

    /// sheet(item:) 目标：避免 isPresented + 独立状态的时序问题
    struct CategorySheetTarget: Identifiable {
        let id: String
        let category: Category?    // nil = 新建
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } content: {
            entryList
                .navigationSplitViewColumnWidth(min: 240, ideal: 280)
        } detail: {
            if let entry = store.entries.first(where: { $0.id == selectedID }) {
                EntryDetailView(store: store, entry: entry) {
                    selectedID = nil
                }
                .id("\(entry.id)-\(entry.version)")
            } else {
                emptyDetail
            }
        }
        .searchable(text: $store.searchText, placement: .sidebar, prompt: "搜索")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingEditor = true } label: {
                    Label("新建条目", systemImage: "plus")
                }
                .keyboardShortcut("n", modifiers: .command)
                .help("新建条目 (⌘N)")
            }
            ToolbarItem {
                Button { app.lock() } label: {
                    Label("锁定", systemImage: "lock")
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])
                .help("立即锁定 (⇧⌘L)")
            }
        }
        .sheet(isPresented: $showingEditor) {
            EntryEditorView(store: store, editing: nil) { newEntry in
                if let newEntry { selectedID = newEntry.id }
            }
        }
    }

    // ── 侧栏 ─────────────────────────────────────────────
    private var sidebar: some View {
        List(selection: filterBinding) {
            Section("资料库") {
                sidebarRow(.all, label: "全部条目", icon: "tray.full")
                sidebarRow(.favorites, label: "收藏", icon: "star")
                sidebarRow(.localOnly, label: "仅本机", icon: "lock.laptopcomputer")
            }
            Section {
                ForEach(categories.all) { category in
                    sidebarRow(.category(category.id),
                               label: category.name, icon: category.icon)
                        .contextMenu {
                            Button("编辑分类…") {
                                categorySheet = .init(id: category.id, category: category)
                            }
                            if category.isBuiltin, categories.isOverridden(category.id) {
                                Button("恢复默认") {
                                    categories.resetBuiltin(id: category.id)
                                }
                            }
                            if !category.isBuiltin {
                                Divider()
                                Button("删除分类", role: .destructive) {
                                    categories.remove(id: category.id)
                                    if store.filter == .category(category.id) {
                                        store.filter = .all
                                    }
                                }
                            }
                        }
                }
            } header: {
                HStack {
                    Text("分类")
                    Spacer()
                    Button {
                        categorySheet = .init(id: "new", category: nil)
                    } label: {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.borderless)
                    .help("新建分类")
                }
            }
        }
        .navigationSplitViewColumnWidth(min: 170, ideal: 190)
        .safeAreaInset(edge: .bottom) {
            if let sync = app.sync, SyncSettings.isConfigured {
                VStack(spacing: 0) {
                    Divider()
                    HStack {
                        SyncStatusLabel(sync: sync)
                        Spacer()
                        Button {
                            Task { await sync.syncNow() }
                        } label: {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
                        .help("立即同步")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .background(.bar)
            }
        }
        .sheet(item: $categorySheet) { target in
            CategoryEditorView(editing: target.category)
        }
    }

    private func sidebarRow(_ filter: SidebarFilter, label: String, icon: String) -> some View {
        Label {
            Text(label)
        } icon: {
            Image(systemName: icon)
        }
        .badge(store.counts[filter] ?? 0)
        .tag(filter)
    }

    private var filterBinding: Binding<SidebarFilter?> {
        Binding(
            get: { store.filter },
            set: { store.filter = $0 ?? .all })
    }

    // ── 条目列表 ─────────────────────────────────────────
    private var entryList: some View {
        List(store.entries, selection: $selectedID) { entry in
            EntryRow(entry: entry)
                .tag(entry.id)
                .contextMenu {
                    Button(entry.favorite ? "取消收藏" : "收藏") {
                        try? store.toggleFavorite(entry)
                    }
                    Button("钉在屏幕上") {
                        PinnedPanelManager.shared.pin(entry: entry, store: store)
                    }
                    Divider()
                    Button("删除", role: .destructive) {
                        try? store.softDelete(entry)
                        if selectedID == entry.id { selectedID = nil }
                    }
                }
        }
        .listStyle(.inset)
        .overlay {
            if store.entries.isEmpty {
                ContentUnavailableView {
                    Label(store.searchText.isEmpty ? "还没有条目" : "无匹配结果",
                          systemImage: store.searchText.isEmpty ? "tray" : "magnifyingglass")
                } description: {
                    if store.searchText.isEmpty {
                        Text("按 ⌘N 新建，或在任何地方按 ⌥⌘N 快速捕获")
                    }
                }
            }
        }
    }

    private var emptyDetail: some View {
        ContentUnavailableView {
            Label("选择一个条目", systemImage: "key.fill")
        } description: {
            VStack(spacing: 6) {
                Text("全局快捷键随时可用：")
                HStack(spacing: 12) {
                    HStack(spacing: 4) { KeyCap(text: "⌥⌘N"); Text("快速捕获") }
                    HStack(spacing: 4) { KeyCap(text: "⌥⌘P"); Text("快速搜索") }
                }
                .font(.caption)
            }
        }
    }
}

/// 列表行。
@MainActor
struct EntryRow: View {
    let entry: Entry

    var body: some View {
        HStack(spacing: 10) {
            TypeBadge(typeID: entry.type, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(entry.title)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    if entry.favorite {
                        Image(systemName: "star.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.yellow)
                    }
                    if entry.localOnly {
                        Image(systemName: "lock.laptopcomputer")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                }
                Text(entry.urlHost ?? CategoryStore.shared.category(for: entry.type).name)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 3)
    }
}
