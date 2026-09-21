import SwiftUI

/// 主窗口：三栏（分类 / 条目列表 / 详情）。
struct MainView: View {
    @EnvironmentObject private var app: AppState
    @ObservedObject var store: EntryStore

    @State private var selectedID: Entry.ID?
    @State private var showingEditor = false

    private static let sidebarFilters: [SidebarFilter] =
        [.all, .favorites, .localOnly] + EntryType.allCases.map { .type($0) }

    var body: some View {
        NavigationSplitView {
            List(Self.sidebarFilters, id: \.self, selection: filterBinding) { f in
                Label(f.label, systemImage: f.icon)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180)
        } content: {
            entryList
                .navigationSplitViewColumnWidth(min: 220, ideal: 260)
        } detail: {
            if let entry = store.entries.first(where: { $0.id == selectedID }) {
                EntryDetailView(store: store, entry: entry)
                    .id(entry.id)   // 切换条目时重建视图（重新解密）
            } else {
                ContentUnavailableView(
                    "选择一个条目", systemImage: "key",
                    description: Text("或按 ⌘N 新建"))
            }
        }
        .searchable(text: $store.searchText, placement: .sidebar, prompt: "搜索标题、网址、标签")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingEditor = true } label: {
                    Label("新建条目", systemImage: "plus")
                }
                .keyboardShortcut("n", modifiers: .command)
            }
            ToolbarItem {
                Button { app.lock() } label: {
                    Label("锁定", systemImage: "lock")
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])
            }
        }
        .sheet(isPresented: $showingEditor) {
            EntryEditorView(store: store, editing: nil) { newEntry in
                selectedID = newEntry?.id
            }
        }
    }

    private var filterBinding: Binding<SidebarFilter?> {
        Binding(
            get: { store.filter },
            set: { store.filter = $0 ?? .all })
    }

    private var entryList: some View {
        List(store.entries, selection: $selectedID) { entry in
            HStack(spacing: 10) {
                Image(systemName: entry.type.icon)
                    .foregroundStyle(.tint)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(entry.title).lineLimit(1)
                        if entry.favorite {
                            Image(systemName: "star.fill")
                                .font(.caption2).foregroundStyle(.yellow)
                        }
                        if entry.localOnly {
                            Image(systemName: "lock.laptopcomputer")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    if let host = entry.urlHost {
                        Text(host).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
            .tag(entry.id)
            .contextMenu {
                Button(entry.favorite ? "取消收藏" : "收藏") {
                    try? store.toggleFavorite(entry)
                }
                Divider()
                Button("删除", role: .destructive) {
                    try? store.softDelete(entry)
                    if selectedID == entry.id { selectedID = nil }
                }
            }
        }
        .overlay {
            if store.entries.isEmpty {
                ContentUnavailableView(
                    store.searchText.isEmpty ? "还没有条目" : "无匹配结果",
                    systemImage: "tray")
            }
        }
    }
}
