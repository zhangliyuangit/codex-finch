import SwiftUI
import AppKit

private let accent = Color(red: 0.26, green: 0.77, blue: 0.57)

struct UsagePanel: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var login = LoginItemController()
    var openSession: (String) -> Bool
    var quit: () -> Void
    @State var settings = false
    @State var statistics = false
    @StateObject private var releases = ReleaseCheck()
    @State private var copiedDiagnostics = false
    @State private var openError = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header.padding(.horizontal, 22).padding(.top, 22).padding(.bottom, 18)
            if settings { settingsContent }
            else if statistics { StatisticsView(snapshot: store.snapshot) }
            else { mainContent }
            footer
        }
        .frame(width: 380)
        .background(.ultraThinMaterial)
        .alert("未能打开 Codex", isPresented: $openError) {
            Button("知道了", role: .cancel) { }
        } message: { Text("请确认本机已安装 Codex，且已注册 codex:// 链接。") }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: FinchBrand.appImage).resizable().scaledToFit()
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(settings ? "偏好设置" : statistics ? "用量统计" : "Codex Finch")
                    .font(.system(size: 17, weight: .semibold))
                HStack(spacing: 4) {
                    Circle().fill(store.paused ? Color.secondary : accent).frame(width: 4, height: 4)
                    Text(store.paused ? "采集已暂停" : "本地同步 · \(store.snapshot.activeCount(at: Date())) 处理中\(store.snapshot.waitingCount > 0 ? " · \(store.snapshot.waitingCount) 待确认" : "")")
                        .font(.system(size: 10.5)).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if !settings {
                Button { store.refresh() } label: {
                    Image(systemName: "arrow.clockwise").font(.system(size: 13))
                        .frame(width: 27, height: 27)
                }.buttonStyle(.plain).foregroundStyle(.secondary)
                    .help("读取最新的本地记录；不会向模型发出请求")
                    .accessibilityLabel("刷新")
            }
            if !settings {
                Button { statistics.toggle() } label: {
                    Image(systemName: statistics ? "arrow.left" : "chart.bar.xaxis")
                        .font(.system(size: 14)).frame(width: 27, height: 27)
                }.buttonStyle(.plain).foregroundStyle(.secondary)
                    .accessibilityLabel(statistics ? "返回会话" : "用量统计")
            }
            Button { settings.toggle() } label: {
                Image(systemName: settings ? "xmark" : "gearshape")
                    .font(.system(size: 14)).frame(width: 27, height: 27)
            }.buttonStyle(.plain).foregroundStyle(.secondary)
                .help(settings ? "返回用量" : "设置")
                .accessibilityLabel(settings ? "返回用量" : "设置")
        }
    }

    private var mainContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            quotaBlock.padding(.horizontal, 22)
            if store.snapshot.dailyError != nil {
                Text("今日统计暂不可用 · 请刷新或查看诊断")
                    .font(.system(size:10.5)).foregroundStyle(.orange).padding(.horizontal,22).padding(.top,8)
            }
            HStack {
                Text("今日总 token").font(.system(size:11)).foregroundStyle(.secondary)
                Spacer()
                Text(store.snapshot.menuValue(for:.tokens,at:Date())).font(.system(size:14,weight:.semibold,design:.rounded)).monospacedDigit()
            }.padding(.horizontal,22).padding(.top,12)
                .help("按系统时区统计本机已记录今日用量，包含缓存输入、子智能体及已归档会话；独立响应按 ID 去重。≥ 表示统计不完整。")
            if let session = store.snapshot.sessions.first {
                latestSession(session).padding(.horizontal, 22).padding(.top, 20)
            }
            HStack {
                Text("会话 · 按项目").font(.system(size: 12, weight: .semibold))
                Spacer()
                Text("累计 token").font(.system(size: 10.5)).foregroundStyle(.secondary)
            }.padding(.horizontal, 22).padding(.top, 23).padding(.bottom, 8)
            if store.snapshot.sessions.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "bubble.left.and.bubble.right").font(.system(size: 24)).foregroundStyle(.secondary)
                    Text(store.snapshot.error ?? "还没有本地会话记录")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                    Text("在 Codex 中开始会话后，这里会自动更新。")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity).padding(.vertical, 32)
            } else {
                ProjectSessionList(sessions: store.snapshot.sessions) { id in
                    if !openSession(id) { openError = true }
                }
            }
            if store.snapshot.error != nil && !store.snapshot.sessions.isEmpty {
                Text("同步暂不可用 · 保留上次记录")
                    .font(.system(size: 10.5)).foregroundStyle(.orange)
                    .padding(.horizontal, 22).padding(.bottom, 10)
            }
        }
    }

    @ViewBuilder private var quotaBlock: some View {
        if let quota = store.snapshot.quota, let window = quota.displayWindow {
            let expired = window.resetsAt.map { $0 <= Date() } ?? false
            let stale = Date().timeIntervalSince(quota.timestamp) > 900 || expired
            HStack(alignment: .firstTextBaseline) {
                Text("账号\(window.title) · 剩余").font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
                Text(UsageFormat.reset(window.resetsAt)).font(.system(size: 10.5)).foregroundStyle(.secondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(expired ? "—" : UsageFormat.percent(window.remaining))
                    .font(.system(size: 38, weight: .medium, design: .rounded))
                    .monospacedDigit().foregroundStyle(window.remaining <= 15 ? Color.orange : Color.primary)
                Text(expired ? "等待新快照" : "可用")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                if let other = otherWindow(quota, window) {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(other.title).font(.system(size: 10)).foregroundStyle(.secondary)
                        Text(UsageFormat.percent(other.remaining)).font(.system(size: 14, weight: .medium)).monospacedDigit()
                    }
                }
            }.padding(.top, 7).padding(.bottom, 10)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.09))
                    if !expired {
                        Capsule().fill(window.remaining <= 15 ? Color.orange : accent)
                            .frame(width: geo.size.width * window.remaining / 100)
                    }
                }
            }.frame(height: 5)
            HStack(spacing: 4) {
                if stale { Image(systemName: "clock").font(.system(size: 9)) }
                Text("额度快照 \(UsageFormat.time(quota.timestamp))\(stale ? " · 等待 Codex 更新" : "")")
                    .font(.system(size: 10.5))
            }.foregroundStyle(stale ? Color.orange : Color.secondary).padding(.top, 9)
                .help("账号额度来自最近一次本地用量记录。此工具不会主动请求服务器；多个会话共用账号额度。")
        } else {
            Text("账号额度").font(.system(size: 12)).foregroundStyle(.secondary)
            Text("—").font(.system(size: 38, weight: .medium)).padding(.top, 7)
            Text("等待 Codex 记录额度快照")
                .font(.system(size: 11)).foregroundStyle(.secondary).padding(.top, 5)
        }
    }

    private func otherWindow(_ quota: QuotaSnapshot, _ primary: QuotaWindow) -> QuotaWindow? {
        let other = quota.primary == primary ? quota.secondary : quota.primary
        guard let other, other.resetsAt.map({ $0 > Date() }) ?? true else { return nil }
        return other
    }

    private func latestSession(_ session: SessionRecord) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Text("最近活跃").foregroundStyle(.secondary)
                Text(session.title).lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 4)
                ActivityBadge(activity: session.activity)
            }.font(.system(size: 10.5))
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(UsageFormat.tokens(session.tokens)).font(.system(size: 20, weight: .semibold, design: .rounded)).monospacedDigit()
                    Text("会话累计 token").font(.system(size: 10.5)).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Rectangle().fill(Color.primary.opacity(0.08)).frame(width: 1, height: 35).padding(.trailing, 20)
                VStack(alignment: .leading, spacing: 5) {
                    Text(session.usage.map { UsageFormat.percent($0.cacheRatio * 100) } ?? "—")
                        .font(.system(size: 20, weight: .semibold, design: .rounded)).monospacedDigit()
                    Text("输入缓存命中").font(.system(size: 10.5)).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            if let usage = session.usage {
                HStack(spacing: 4) {
                    Text("输入 \(UsageFormat.tokens(usage.input))")
                    Text("·").padding(.horizontal, 3)
                    Text("输出 \(UsageFormat.tokens(usage.output))")
                }.font(.system(size: 10.5)).foregroundStyle(.secondary)
            }
        }.padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.06), lineWidth: 0.5))
            .help("这是完整会话的累计记录，可能包含历史上下文；缓存 token 已含在输入中，推理 token 已含在输出中。token 不能直接换算为订阅账单。")
    }

    private var loginBinding: Binding<Bool> {
        Binding(get: { login.state.isEnabled }, set: { login.setEnabled($0) })
    }
    private var settingsContent: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                preferenceToggle("登录后自动启动", selection: loginBinding)
                Text(login.message).font(.system(size: 10.5)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if login.state == .approvalRequired {
                    Button("打开登录项设置") { login.openSystemSettings() }.buttonStyle(.borderless)
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("菜单栏显示").font(.system(size: 12, weight: .semibold))
                Picker("常驻指标", selection: $store.metric) {
                    ForEach(MenuMetric.allCases) { item in Text(item.label).tag(item) }
                }.pickerStyle(.segmented).labelsHidden()
                Text(store.metric == .tokens ? "按系统时区从 0 点统计本机今日总量，含缓存、子智能体和已归档会话；≥ 表示统计不完整。" : store.metric == .quota ? "显示账号每周剩余额度；没有周窗口时使用主额度窗口。" : store.metric == .activity ? "显示当前监测范围内正在处理的会话数；待确认另行标记。" : "保持菜单栏简洁，用量仍可在弹窗查看。")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 10) {
                preferenceToggle("系统通知", selection: $store.notifications.enabled, emphasized: true)
                Text(store.notificationMessage).font(.system(size: 10.5)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 10) {
                    preferenceToggle("任务结束", selection: $store.notifications.completed)
                    preferenceToggle("需要确认", selection: $store.notifications.attention)
                    HStack(spacing: 6) {
                        Text("额度偏低")
                        Picker("提醒阈值", selection: $store.notifications.lowQuotaThreshold) {
                            ForEach([10,20,30], id: \.self) { value in Text("≤ \(value)%").tag(value) }
                        }.labelsHidden().frame(width: 80).disabled(!store.notifications.lowQuota)
                        Spacer()
                        Toggle("额度偏低", isOn: $store.notifications.lowQuota).labelsHidden().toggleStyle(.switch)
                    }
                    preferenceToggle("提示音", selection: $store.notifications.sound)
                }.toggleStyle(.switch).font(.system(size: 11))
                    .disabled(!store.notifications.enabled)
                HStack {
                    Text("同一事件只提醒一次，启动不补推旧记录。")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                    Spacer(minLength: 5)
                    Button("系统通知设置") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") { NSWorkspace.shared.open(url) }
                    }.buttonStyle(.borderless).font(.system(size: 10.5))
                    Button("测试通知") { store.onTestNotification?() }
                        .buttonStyle(.borderless).font(.system(size: 10.5))
                        .disabled(!store.notifications.enabled)
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                preferenceToggle("暂停采集", selection: $store.paused)
                Text("暂停后停止监听；恢复时读取最新记录。")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("监测最近会话").font(.system(size:12))
                    Spacer()
                    Picker("监测数量",selection:$store.sessionLimit) {
                        ForEach([24,50,100],id: \.self) { Text("\($0) 条").tag($0) }
                    }.labelsHidden().frame(width:100)
                }
                Text("增加范围会监听更多日志；今日总量不受此设置影响。")
                    .font(.system(size:10.5)).foregroundStyle(.secondary)
            }
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                Label("轻量本地采集", systemImage: "leaf").font(.system(size: 12, weight: .semibold))
                Text("列表保留最近 \(store.sessionLimit) 个会话；今日总量覆盖全部今日日志。首次回填后缓存读取位置，只读新增内容。没有定时轮询或网络请求。")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("账号额度是日志快照。官方会话额度和费用暂未接入；不把账号额度变化当成某个会话的消耗。")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment:.leading,spacing:8) {
                HStack {
                    Button(releases.checking ? "正在检查…" : "检查更新") { releases.check() }
                        .disabled(releases.checking).buttonStyle(.borderless)
                    Spacer()
                    Button(copiedDiagnostics ? "已复制诊断" : "复制诊断") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(store.snapshot.sanitizedDiagnostics,forType:.string)
                        copiedDiagnostics=true
                    }.buttonStyle(.borderless)
                }.font(.system(size:11))
                Text(releases.message).font(.system(size:10.5)).foregroundStyle(.secondary)
                    .fixedSize(horizontal:false,vertical:true)
                if let url = releases.releaseURL {
                    Button("打开发布页") { NSWorkspace.shared.open(url) }.buttonStyle(.borderless)
                }
                Text("诊断仅含状态和计数，不包含会话标题、路径或内容。")
                    .font(.system(size:10)).foregroundStyle(.secondary)
            }
            HStack {
                Text("Codex Finch 0.6 · 本地记录").font(.system(size: 10.5)).foregroundStyle(.secondary)
                Spacer()
                Button("退出", action: quit).buttonStyle(.borderless).font(.system(size: 11))
            }.padding(.top, 10)
        }.padding(.horizontal, 22).padding(.top, 8).padding(.bottom, 18)
        }.scrollIndicators(.visible).frame(height: 560)
    }

    private func preferenceToggle(_ title: String, selection: Binding<Bool>, emphasized: Bool = false) -> some View {
        HStack {
            Text(title).font(.system(size: 12, weight: emphasized ? .semibold : .regular))
            Spacer()
            Toggle(title, isOn: selection).labelsHidden().toggleStyle(.switch)
        }
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.5)
            HStack(spacing: 5) {
                Image(systemName: settings ? "lock" : "arrow.up.forward.app").font(.system(size: 10))
                Text(settings ? "数据留在本机" : statistics ? "本机已记录用量 · 非云端账单" : "点击会话，在 Codex 中打开")
                    .font(.system(size: 10.5))
                Spacer()
                if !settings {
                    Text("⌘Q 退出").font(.system(size: 10)).opacity(0.75)
                }
            }.foregroundStyle(.secondary).padding(.horizontal, 22).padding(.vertical, 13)
        }
    }
}

private struct ProjectSessionList: View {
    let sessions: [SessionRecord]
    var openSession: (String) -> Void
    @State private var expandedProjects = Set<String>()
    @State private var allSessionsProjects = Set<String>()
    @State private var initialized = false
    @State private var search = ""
    @State private var filter: SessionFilter = .all
    private var filtered: [SessionRecord] { sessions.filter { filter.matches($0,search:search,now:Date()) } }
    private var groups: [SessionGroup] { SessionGroup.make(from: filtered) }

    var body: some View {
        VStack(spacing: 0) {
            TextField("搜索会话或项目",text:$search).textFieldStyle(.roundedBorder)
                .font(.system(size:11)).padding(.horizontal,22).padding(.bottom,8)
            Picker("会话筛选",selection:$filter) {
                ForEach(SessionFilter.allCases) { Text($0.label).tag($0) }
            }.pickerStyle(.segmented).labelsHidden().padding(.horizontal,22).padding(.bottom,8)
            if groups.isEmpty {
                Text("没有匹配的会话").font(.system(size:11)).foregroundStyle(.secondary).padding(16)
            }
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(groups) { group in
                        let expanded = expandedProjects.contains(group.id)
                        Button {
                            if expanded { expandedProjects.remove(group.id) }
                            else { expandedProjects.insert(group.id) }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: group.isUnassigned ? "tray" : "folder")
                                    .font(.system(size: 12)).foregroundStyle(.secondary)
                                    .frame(width: 16)
                                Text(group.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                                Text("\(group.sessions.count)")
                                    .font(.system(size: 10)).foregroundStyle(.secondary).monospacedDigit()
                                let active = group.sessions.filter { $0.activity?.effectivePhase(at: Date()) == .running }.count
                                let waiting = group.sessions.filter { $0.activity?.phase == .waiting }.count
                                if active > 0 {
                                    Text("\(active) 活跃").font(.system(size: 10)).foregroundStyle(accent)
                                }
                                if waiting > 0 {
                                    Text("\(waiting) 待确认").font(.system(size: 10)).foregroundStyle(.orange)
                                }
                                Spacer(minLength: 8)
                                Image(systemName: expanded ? "chevron.down" : "chevron.right")
                                    .font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                            }.padding(.horizontal, 22).frame(height: 32)
                                .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                            .help("\(group.name) · 最近 \(group.sessions.count) 个会话")
                            .accessibilityLabel("\(expanded ? "折叠" : "展开")项目 \(group.name)，\(group.sessions.count) 个最近会话")
                        if expanded {
                            let showingAll = allSessionsProjects.contains(group.id)
                            let visible = Array(group.sessions.prefix(showingAll ? group.sessions.count : 2))
                            ForEach(Array(visible.enumerated()), id: \.element.id) { index, session in
                                SessionRow(session: session, active: session.id == sessions.first?.id) { openSession(session.id) }
                                    .padding(.leading, 14)
                                if index < visible.count - 1 {
                                    Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 0.5)
                                        .padding(.leading, 62).padding(.trailing, 22)
                                }
                            }
                            if group.sessions.count > 2 {
                                Button {
                                    if showingAll { allSessionsProjects.remove(group.id) }
                                    else { allSessionsProjects.insert(group.id) }
                                } label: {
                                    Text(showingAll ? "收起更多会话" : "显示另外 \(group.sessions.count - 2) 个会话")
                                        .font(.system(size: 10.5)).foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.leading, 62).frame(height: 24)
                                        .contentShape(Rectangle())
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                }
            }.scrollIndicators(.hidden).frame(height: min(222, listHeight))
            Text("\(groups.filter { !$0.isUnassigned }.count) 个项目 · \(filtered.count) / \(sessions.count) 个最近会话")
                .font(.system(size: 10.5)).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity).padding(.vertical, 9)
        }.onAppear {
            if !initialized {
                if let first = groups.first { expandedProjects.insert(first.id) }
                initialized = true
            }
        }
    }

    private var listHeight: CGFloat {
        groups.reduce(CGFloat(0)) { height, group in
            guard expandedProjects.contains(group.id) else { return height + 34 }
            let rows = allSessionsProjects.contains(group.id) ? group.sessions.count : min(2, group.sessions.count)
            return height + 34 + CGFloat(rows) * 56 + (group.sessions.count > 2 ? 24 : 0)
        }
    }
}

private struct SessionRow: View {
    let session: SessionRecord
    let active: Bool
    var action: () -> Void
    @State private var hovering = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: "bubble.left")
                    .font(.system(size: 12)).foregroundStyle(active ? accent : Color.secondary)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.title).font(.system(size: 12, weight: .medium))
                        .lineLimit(1).truncationMode(.tail)
                    HStack(spacing: 4) {
                        ActivityBadge(activity: session.activity)
                        Text("· \(session.model.isEmpty ? "Codex" : session.model)")
                            .foregroundStyle(.secondary).lineLimit(1)
                    }.font(.system(size: 10))
                }
                Spacer(minLength: 6)
                Text(UsageFormat.tokens(session.tokens))
                    .font(.system(size: 12, weight: .medium, design: .rounded)).monospacedDigit()
                    .fixedSize()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(hovering ? accent : Color.secondary.opacity(0.6))
            }.padding(.horizontal, 22).frame(height: 55.5)
                .contentShape(Rectangle())
                .background(hovering ? Color.primary.opacity(0.045) : Color.clear)
        }.buttonStyle(.plain).onHover { hovering = $0 }
            .help("\(session.title)\n更新于 \(UsageFormat.time(session.updatedAt)) · 在 Codex 中打开")
            .accessibilityLabel("打开会话 \(session.title)，累计 \(session.tokens) token")
    }
}

private struct ActivityBadge: View {
    let activity: SessionActivity?
    private var phase: ActivityPhase { activity?.effectivePhase(at: Date()) ?? .unknown }
    private var color: Color {
        switch phase {
        case .running: return accent
        case .waiting: return .orange
        case .failed: return .red
        default: return .secondary
        }
    }
    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 4, height: 4)
            Text(activity?.label(at: Date()) ?? "状态未知")
                .font(.system(size: 10)).foregroundStyle(color).lineLimit(1)
        }.fixedSize()
            .help("依据本地任务生命周期事件；处理中超过 10 分钟无进展会标为状态待更新。待确认仅覆盖日志明确记录的阻塞请求。")
    }
}

// The scene uses the same native view as the running popover.
// The background and menu strip only provide visual context for the exported preview.
struct PreviewScene: View {
    @ObservedObject var store: UsageStore
    var showSettings = false
    var showStatistics = false
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "apple.logo").font(.system(size: 15))
                Text("Finder").font(.system(size: 12, weight: .semibold))
                Spacer()
                HStack(spacing: 5) {
                    Image(nsImage: FinchBrand.menuImage).resizable().frame(width: 16, height: 16)
                    Text(store.snapshot.menuValue(for:store.metric,at:Date()))
                        .font(.system(size: 12, weight: .medium)).monospacedDigit()
                }.padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color.primary.opacity(0.09), in: RoundedRectangle(cornerRadius: 5))
                Image(systemName: "wifi").font(.system(size: 12))
                Text(UsageFormat.time(Date())).font(.system(size: 12))
            }.padding(.horizontal, 20).frame(height: 32).background(.ultraThinMaterial)
            HStack {
                Spacer()
                VStack(spacing: 0) {
                    Image(systemName: "triangle.fill").font(.system(size: 12)).rotationEffect(.degrees(0))
                        .foregroundStyle(Color(nsColor: .windowBackgroundColor)).offset(x: 121, y: 3)
                    UsagePanel(store: store, openSession: { _ in true }, quit: {}, settings: showSettings, statistics: showStatistics)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.primary.opacity(0.12), lineWidth: 0.5))
                        .shadow(color: .black.opacity(0.2), radius: 22, y: 9)
                }.padding(.trailing, 16)
            }.padding(.top, 2)
            Spacer(minLength: 20)
        }.frame(width: 460, height: showSettings ? 780 : 860)
            .background(Color(nsColor: .underPageBackgroundColor))
    }
}
