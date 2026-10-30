import SwiftUI
import AppKit

let finchAccent = Color(nsColor: NSColor(name: "FinchAccent") { appearance in
    appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        ? NSColor(srgbRed: 0.26, green: 0.77, blue: 0.57, alpha: 1)
        : NSColor(srgbRed: 0.06, green: 0.43, blue: 0.29, alpha: 1)
})
let finchWarning = Color(nsColor: NSColor(name: "FinchWarning") { appearance in
    appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        ? NSColor(srgbRed: 1, green: 0.65, blue: 0.15, alpha: 1)
        : NSColor(srgbRed: 0.65, green: 0.31, blue: 0.02, alpha: 1)
})

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
            header.padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 16)
            if settings { settingsContent }
            else if statistics { StatisticsView(snapshot: store.snapshot) }
            else { mainContent }
            footer
        }
        .frame(width: 380)
        .background(.ultraThinMaterial)
        .tint(finchAccent)
        .alert("未能打开 Codex", isPresented: $openError) {
            Button("知道了", role: .cancel) { }
        } message: { Text("请确认本机已安装 Codex，且已注册 codex:// 链接。") }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: FinchBrand.appImage).resizable().scaledToFit()
                .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(settings ? "偏好设置" : statistics ? "用量统计" : "Codex Finch")
                    .font(.system(size: 16, weight: .semibold))
                HStack(spacing: 4) {
                    Circle().fill(store.paused ? Color.secondary : finchAccent).frame(width: 4, height: 4)
                    Text(store.paused ? "采集已暂停" : "本地同步 · \(store.snapshot.activeCount(at: Date())) 处理中\(store.snapshot.waitingCount > 0 ? " · \(store.snapshot.waitingCount) 待确认" : "")")
                        .font(.system(size: 10.5)).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if !settings {
                Button { store.refresh() } label: {
                    Image(systemName: "arrow.clockwise").font(.system(size: 13))
                        .frame(width: 28, height: 28)
                }.buttonStyle(PanelIconStyle())
                    .help("读取最新的本地记录；不会向模型发出请求")
                    .accessibilityLabel("刷新")
            }
            if !settings {
                Button { statistics.toggle() } label: {
                    Image(systemName: statistics ? "arrow.left" : "chart.bar.xaxis")
                        .font(.system(size: 14)).frame(width: 28, height: 28)
                }.buttonStyle(PanelIconStyle())
                    .help(statistics ? "返回会话" : "按项目、模型查看用量和历史")
                    .accessibilityLabel(statistics ? "返回会话" : "用量统计")
            }
            if settings {
                Button { settings = false } label: {
                    Image(systemName: "xmark").font(.system(size: 13)).frame(width: 28, height: 28)
                }.buttonStyle(PanelIconStyle()).help("返回用量").accessibilityLabel("返回用量")
            }
        }
    }

    private var mainContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            todaySummary.padding(.horizontal, 20)
            if store.snapshot.dailyError != nil {
                Text("今日统计暂不可用 · 请刷新或查看诊断")
                    .font(.system(size:10.5)).foregroundStyle(finchWarning).padding(.horizontal,20).padding(.top,8)
            }
            quotaBlock.padding(.horizontal, 20).padding(.top, 14)
            HStack {
                Text("项目会话").font(.system(size: 12, weight: .semibold))
                Spacer()
                Text("配置按本地记录").font(.system(size: 11)).foregroundStyle(.secondary)
            }.padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 10)
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
                    .font(.system(size: 10.5)).foregroundStyle(finchWarning)
                    .padding(.horizontal, 22).padding(.bottom, 10)
            }
        }
    }

    private var todaySummary: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("今日总 token").font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
                Text(store.snapshot.menuValue(for: .tokens, at: Date()))
                    .font(.system(size: 30, weight: .semibold, design: .rounded)).monospacedDigit()
            }
            if let daily = store.snapshot.daily, store.snapshot.dailyError == nil {
                let input = daily.projects.reduce(Int64(0)) { $0 + $1.input }
                let output = daily.projects.reduce(Int64(0)) { $0 + $1.output }
                HStack(spacing: 12) {
                    Text("输入 \(UsageFormat.tokens(input))")
                    Text("输出 \(UsageFormat.tokens(output))")
                    Spacer(minLength: 0)
                    Text("\(daily.requests) 条记录").monospacedDigit()
                }.font(.system(size: 10.5)).foregroundStyle(.secondary)
            }
        }.help("按系统时区统计本机已记录今日用量，包含缓存输入、子智能体及已归档会话；独立响应按 ID 去重。≥ 表示统计不完整。")
    }

    @ViewBuilder private var quotaBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let quota = store.snapshot.quota, let window = quota.displayWindow {
                HStack(alignment: .top, spacing: 20) {
                    quotaRow(window, snapshot:quota.timestamp)
                    if let other = quota.primary == window ? quota.secondary : quota.primary {
                        quotaRow(other, snapshot:quota.timestamp)
                    }
                }
                if Date().timeIntervalSince(quota.timestamp) > 900 {
                    Text("额度快照 \(UsageFormat.time(quota.timestamp)) · 等待更新")
                        .font(.system(size: 11)).foregroundStyle(finchWarning)
                }
            } else {
                Text("等待 Codex 记录额度快照")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }.padding(.top, 12)
            .overlay(alignment: .top) { Divider().opacity(0.5) }
            .help("账号共享额度来自本地记录；悬停每个窗口查看快照与重置时间。Finch 不会主动请求服务器。")
    }

    private func quotaRow(_ window: QuotaWindow, snapshot: Date) -> some View {
        let expired = window.resetsAt.map { $0 <= Date() } ?? false
        let color = window.remaining <= 15 ? finchWarning : finchAccent
        let title = window.minutes == 10080 ? "每周剩余" : window.minutes == 300 ? "5 小时剩余" : window.title
        let status = expired ? "等待新快照" : UsageFormat.percent(window.remaining)
        return VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title).font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Text(expired ? "—" : UsageFormat.percent(window.remaining))
                    .font(.system(size: 14, weight: .semibold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(expired || window.remaining <= 15 ? finchWarning : Color.primary)
            }
            GeometryReader { geo in
                Capsule().fill(Color.primary.opacity(0.08)).overlay(alignment: .leading) {
                    if !expired {
                        Capsule().fill(color).frame(width:geo.size.width * max(0,min(100,window.remaining))/100)
                    }
                }
            }.frame(height:3)
        }.frame(maxWidth:.infinity)
            .help("\(window.title)：\(status)；快照 \(UsageFormat.time(snapshot))；\(UsageFormat.reset(window.resetsAt))。")
            .accessibilityElement(children:.ignore)
            .accessibilityLabel("\(window.title)，\(status)，快照 \(UsageFormat.time(snapshot))，\(UsageFormat.reset(window.resetsAt))")
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
                Text("Codex Finch \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "开发版") · 本地记录")
                    .font(.system(size: 10.5)).foregroundStyle(.secondary)
                Spacer()
                Button("退出", action: quit).buttonStyle(.borderless).font(.system(size: 11))
            }.padding(.top, 10)
        }.padding(.horizontal, 20).padding(.top, 4).padding(.bottom, 16)
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
                Image(systemName: settings ? "lock" : statistics ? "internaldrive" : "arrow.up.forward.app")
                    .font(.system(size: 10))
                Text(settings ? "数据留在本机" : statistics ? "本机记录 · 非云端账单" : "点击会话，在 Codex 中打开")
                    .font(.system(size: 10.5))
                Spacer(minLength: 4)
                if !settings {
                    Button { settings = true } label: {
                        Image(systemName: "gearshape").font(.system(size: 13)).frame(width: 28, height: 28)
                    }.buttonStyle(PanelIconStyle()).help("偏好设置").accessibilityLabel("偏好设置")
                }
            }.foregroundStyle(.secondary).padding(.leading, 20).padding(.trailing, 14).padding(.vertical, 7)
        }
    }

}

private struct ProjectSessionList: View {
    let sessions: [SessionRecord]
    var openSession: (String) -> Void
    @State private var expandedProjects = Set<String>()
    @State private var allSessionsProjects = Set<String>()
    @State private var initialized = false
    @State private var filter: SessionFilter = .all
    @State private var order: SessionListOrder?
    private var presented: [SessionRecord] { (order?.groups(from:sessions) ?? SessionGroup.make(from:sessions)).flatMap(\.sessions) }
    private var filtered: [SessionRecord] { presented.filter { filter.matches($0,now:Date()) } }
    private var groups: [SessionGroup] { order?.groups(from:filtered) ?? SessionGroup.make(from:filtered) }

    var body: some View {
        VStack(spacing: 0) {
            Picker("会话筛选",selection:$filter) {
                ForEach(SessionFilter.allCases) { item in
                    let count = presented.filter { item.matches($0, now: Date()) }.count
                    Text("\(item.label) \(count)").tag(item)
                }
            }.pickerStyle(.segmented).controlSize(.small).labelsHidden()
                .padding(.horizontal,20).padding(.bottom,10)
            if groups.isEmpty {
                Text(filter == .running ? "目前没有处理中的会话" : "目前没有待确认的会话")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity).padding(.vertical, 24)
            }
            VStack(alignment:.trailing,spacing:5) {
                Text("最近完成一轮").font(.system(size:11)).foregroundStyle(.secondary)
                SessionNumberColumns(values:["累计 token","首 token","整轮耗时","平均吞吐"], heading:true)
            }.padding(.leading,40).padding(.trailing,20).padding(.bottom,8)
                .overlay(alignment:.bottom) { Divider().padding(.leading,40).padding(.trailing,20) }
            ScrollView {
                LazyVStack(spacing: 4) {
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
                                Spacer(minLength: 8)
                                Image(systemName: expanded ? "chevron.down" : "chevron.right")
                                    .font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                            }.padding(.horizontal, 8).frame(height: 32)
                                .contentShape(Rectangle())
                        }.buttonStyle(ProjectHeaderStyle()).padding(.horizontal, 12)
                            .help("\(group.name) · 最近 \(group.sessions.count) 个会话")
                            .accessibilityLabel("\(expanded ? "折叠" : "展开")项目 \(group.name)，\(group.sessions.count) 个最近会话")
                        if expanded {
                            let showingAll = allSessionsProjects.contains(group.id)
                            let visible = Array(group.sessions.prefix(showingAll ? group.sessions.count : 2))
                            ForEach(Array(visible.enumerated()), id: \.element.id) { index, session in
                                SessionRow(session: session) { openSession(session.id) }
                                if index < visible.count - 1 {
                                    Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 0.5)
                                        .padding(.leading, 44).padding(.trailing, 20)
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
                                        .padding(.leading, 44).frame(height: 26)
                                        .contentShape(Rectangle())
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                }
            }.scrollIndicators(.visible).frame(height: min(366, listHeight))
            let pending = order?.pendingCount(in:sessions) ?? 0
            if pending > 0 {
                Text("\(pending) 个新会话 · 重开面板查看")
                    .font(.system(size:11)).foregroundStyle(.secondary)
                    .padding(.horizontal,20).padding(.top,8)
            }
            Label("配置看记录，性能看上一轮", systemImage:"info.circle")
                .font(.system(size:11)).foregroundStyle(.secondary)
                .padding(.horizontal,20).padding(.vertical,10)
                .help("模型、思考和模式来自本地记录，可能滞后于界面变化。后三列是最近完成一轮；均速含推理、工具与等待，不是纯生成速度。面板打开期间保持顺序，新会话重开后显示。")
        }.onAppear {
            if !initialized {
                order = SessionListOrder(sessions:sessions)
                if let first = groups.first { expandedProjects.insert(first.id) }
                expandedProjects.formUnion(groups.filter { group in
                    group.sessions.contains { $0.activity?.phase == .waiting || $0.activity?.effectivePhase(at:Date()) == .running }
                }.map(\.id))
                initialized = true
            }
        }.onChange(of: filter) { _, selection in
            if selection != .all { expandedProjects.formUnion(groups.map(\.id)) }
        }
    }

    private var listHeight: CGFloat {
        groups.reduce(CGFloat(0)) { height, group in
            guard expandedProjects.contains(group.id) else { return height + 34 }
            let rows = allSessionsProjects.contains(group.id) ? group.sessions.count : min(2, group.sessions.count)
            return height + 34 + CGFloat(rows) * 88 + (group.sessions.count > 2 ? 26 : 0)
        }
    }
}

private struct SessionNumberColumns: View {
    let values: [String]
    var heading = false
    var body: some View {
        HStack(spacing:4) {
            cell(0).frame(width:72,alignment:.leading)
            cell(1).frame(width:66,alignment:.leading)
            cell(2).frame(width:68,alignment:.leading)
            cell(3).frame(maxWidth:.infinity,alignment:.trailing)
        }.font(.system(size:heading ? 11 : 12)).monospacedDigit()
    }
    private func cell(_ index: Int) -> some View {
        Text(values[index]).lineLimit(1).minimumScaleFactor(0.8)
            .foregroundStyle(heading || index == 0 ? Color.secondary : Color.primary)
    }
}

private struct SessionRow: View {
    let session: SessionRecord
    var action: () -> Void
    @State private var hovering = false
    private var config: SessionConfiguration { session.recordedConfiguration }
    private var details: String {
        var lines = [session.title,config.help,"更新于 \(UsageFormat.time(session.updatedAt)) · 在 Codex 中打开"]
        if let usage = session.usage {
            lines.append("会话累计：输入 \(UsageFormat.tokens(usage.input)) · 输出 \(UsageFormat.tokens(usage.output)) · 输入缓存 \(UsageFormat.percent(usage.cacheRatio * 100))；缓存已含在输入中。")
        }
        lines.append(session.performance?.help ?? "暂无完整的完成轮次记录；缺失值不表示零延迟或零速度。")
        return lines.joined(separator:"\n")
    }
    var body: some View {
        Button(action:action) {
            VStack(alignment:.leading,spacing:5) {
                HStack(spacing:8) {
                    Text(session.title).font(.system(size:12,weight:.medium))
                        .lineLimit(1).truncationMode(.tail)
                    Spacer(minLength:6)
                    ActivityBadge(activity:session.activity)
                }
                HStack(spacing:6) {
                    Text(config.model ?? "模型未知").lineLimit(1).truncationMode(.middle)
                    separator
                    Text("思考 \(config.effortLabel)").fixedSize()
                    separator
                    HStack(spacing:3) {
                        if config.isFast { Image(systemName:"bolt").font(.system(size:9)) }
                        Text(config.modeLabel).lineLimit(1).truncationMode(.tail)
                    }.frame(maxWidth:84,alignment:.leading)
                }.font(.system(size:11)).foregroundStyle(.secondary)
                SessionNumberColumns(values:[UsageFormat.tokens(session.tokens),
                    session.performance?.firstTokenLabel ?? "—",session.performance?.durationLabel ?? "—",
                    session.performance?.throughputLabel ?? "—"])
                    .padding(.top,5)
            }.padding(.leading,40).padding(.trailing,20).frame(height:87.5)
                .contentShape(Rectangle())
                .background(hovering ? Color.primary.opacity(0.045) : Color.clear)
        }.buttonStyle(.plain).onHover { hovering = $0 }.help(details)
            .accessibilityLabel("打开会话 \(session.title)，\(session.activity?.label(at:Date()) ?? "状态未知")，\(config.summary)，累计 \(session.tokens) token，首 token \(session.performance?.firstTokenLabel ?? "—")，整轮耗时 \(session.performance?.durationLabel ?? "—")，平均吞吐 \(session.performance?.throughputLabel ?? "—")")
    }
    private var separator: some View { Rectangle().fill(Color.primary.opacity(0.12)).frame(width:1,height:9) }
}

private struct ActivityBadge: View {
    let activity: SessionActivity?
    private var phase: ActivityPhase { activity?.effectivePhase(at: Date()) ?? .unknown }
    private var color: Color {
        switch phase {
        case .running: return finchAccent
        case .waiting: return finchWarning
        case .failed: return .red
        default: return .secondary
        }
    }
    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 4, height: 4)
            Text(activity?.label(at: Date()) ?? "状态未知")
                .font(.system(size: 11)).foregroundStyle(color).lineLimit(1)
        }.fixedSize()
            .help("依据本地任务生命周期事件；处理中超过 10 分钟无进展会标为状态待更新。待确认仅覆盖日志明确记录的阻塞请求。")
    }
}

private struct PanelIconStyle: ButtonStyle {
    @State private var hovering = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(hovering ? Color.primary : Color.secondary)
            .background(Color.primary.opacity(configuration.isPressed ? 0.10 : hovering ? 0.06 : 0), in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle()).onHover { hovering = $0 }
    }
}

private struct ProjectHeaderStyle: ButtonStyle {
    @State private var hovering = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.foregroundStyle(Color.primary)
            .background(Color.primary.opacity(configuration.isPressed ? 0.07 : hovering ? 0.04 : 0), in: RoundedRectangle(cornerRadius: 6))
            .onHover { hovering = $0 }
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
        }.frame(width: 460, height: showSettings ? 780 : showStatistics ? 610 : 800)
            .background(Color(nsColor: .underPageBackgroundColor))
    }
}
