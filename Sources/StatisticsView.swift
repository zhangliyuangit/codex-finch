import SwiftUI

struct StatisticsView: View {
    var snapshot: UsageSnapshot
    @State private var section = 0
    @State private var days = 7
    var body: some View {
        VStack(alignment:.leading,spacing:14) {
            HStack(alignment:.firstTextBaseline) {
                Text("今日总 token").font(.system(size:12)).foregroundStyle(.secondary)
                Spacer()
                Text(snapshot.menuValue(for:.tokens,at:Date())).font(.system(size:25,weight:.semibold,design:.rounded)).monospacedDigit()
            }
            Picker("统计范围",selection:$section) {
                Text("按项目").tag(0);Text("按模型").tag(1);Text("历史").tag(2)
            }.pickerStyle(.segmented).labelsHidden()
            if snapshot.dailyError != nil {
                Text("统计暂不可用，请刷新；诊断可在设置中复制。")
                    .font(.system(size:11)).foregroundStyle(finchWarning)
            } else if let daily = snapshot.daily {
                if section == 2 { history(daily) }
                else {
                    let rows = section == 0 ? daily.projects : daily.models
                    ScrollView {
                        VStack(alignment:.leading,spacing:17) {
                            if rows.isEmpty { Text("今天还没有可归属的用量记录。").foregroundStyle(.secondary) }
                            ForEach(rows) { row in
                                VStack(alignment:.leading,spacing:6) {
                                    HStack {
                                        Text(row.name).lineLimit(1)
                                        Spacer(minLength:8)
                                        Text(UsageFormat.tokens(row.tokens)).monospacedDigit()
                                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    }.font(.system(size:12))
                                    GeometryReader { geo in
                                        Capsule().fill(Color.primary.opacity(0.07)).overlay(alignment:.leading) {
                                            Capsule().fill(finchAccent)
                                                .frame(width:geo.size.width * min(1,Double(row.tokens)/Double(max(1,daily.tokens))))
                                        }
                                    }.frame(height:4)
                                    Text("输入 \(UsageFormat.tokens(row.input)) · 输出 \(UsageFormat.tokens(row.output)) · \(row.requests) 条记录")
                                        .font(.system(size:10)).foregroundStyle(.secondary)
                                    if section == 1 {
                                        Text("输入缓存 \(UsageFormat.percent(Double(row.cached)/Double(max(1,row.input))*100))")
                                            .font(.system(size:10)).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }.padding(.vertical,5)
                    }.frame(height:290)
                    Text(daily.partial ? "≥ 表示统计不完整；项目拆分为已记录总量。" : "项目归属来自本地元数据，含子智能体与已归档会话。")
                        .font(.system(size:10.5)).foregroundStyle(.secondary)
                }
            } else { Text("正在读取本地用量…").font(.system(size:12)).foregroundStyle(.secondary).frame(height:290) }
        }.padding(.horizontal,20).padding(.bottom,16)
    }
    private func history(_ daily: DailyTokenTotal) -> some View {
        let calendar = Calendar.autoupdatingCurrent
        let first = calendar.date(byAdding:.day,value:1-days,to:daily.start) ?? daily.start
        let rows = daily.history.filter { $0.start >= first && $0.start < daily.end }
        let maxTokens = max(1,rows.map(\.tokens).max() ?? 1)
        return VStack(alignment:.leading,spacing:12) {
            Picker("历史天数",selection:$days) { Text("7 天").tag(7);Text("30 天").tag(30) }
                .pickerStyle(.segmented).labelsHidden()
            ScrollView {
                VStack(spacing:12) {
                    ForEach(rows.reversed()) { row in
                        HStack(spacing:10) {
                            Text(row.start,format:.dateTime.month().day()).frame(width:58,alignment:.leading)
                            GeometryReader { geo in
                                Capsule().fill(Color.primary.opacity(0.06)).overlay(alignment:.leading) {
                                    Capsule().fill(finchAccent).frame(width:geo.size.width*Double(row.tokens)/Double(maxTokens))
                                }
                            }.frame(height:6)
                            Text((row.partial ? "≥" : "")+UsageFormat.tokens(row.tokens)).monospacedDigit().frame(width:65,alignment:.trailing)
                        }.font(.system(size:11))
                    }
                }.padding(.vertical,5)
            }.frame(height:238)
            Text("历史是已记录下限（≥）；空缺不代表零消耗。首次读取今日更新过的日志，历史随使用积累。")
                .font(.system(size:10.5)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
        }
    }
}
