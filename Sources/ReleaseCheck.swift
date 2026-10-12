import Foundation
import Combine

enum ReleaseVersion {
    static func components(_ value: String) -> [Int]? {
        let text = value.hasPrefix("v") ? String(value.dropFirst()) : value
        let pieces = text.split(separator:".",omittingEmptySubsequences:false)
        guard pieces.count == 3 else { return nil }
        let numbers = pieces.compactMap { Int($0) }
        guard numbers.count == 3 && numbers.allSatisfy({ $0 >= 0 }) else { return nil }
        return numbers
    }
    static func newer(_ candidate: String, than current: String) -> Bool {
        guard let a=components(candidate),let b=components(current) else { return false }
        for (left,right) in zip(a,b) { if left != right { return left > right } }
        return false
    }
}

final class ReleaseCheck: ObservableObject {
    @Published private(set) var checking = false
    @Published private(set) var message = "手动检查 GitHub 发布；平时不发网络请求。"
    @Published private(set) var releaseURL: URL?
    func check() {
        guard !checking else { return }
        checking=true;releaseURL=nil;message="正在检查…"
        var request = URLRequest(url:URL(string:"https://api.github.com/repos/zhangliyuangit/codex-finch/releases?per_page=10")!)
        request.timeoutInterval=15
        request.setValue("application/vnd.github+json",forHTTPHeaderField:"Accept")
        let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.6.0"
        URLSession.shared.dataTask(with:request) { [weak self] data,response,error in
            var message = "检查失败，请稍后重试。"
            var url: URL?
            if error == nil,let http=response as? HTTPURLResponse,http.statusCode==200,let data,
               let releases=try? JSONDecoder().decode([PublicRelease].self,from:data) {
                let newest=releases.filter { !$0.draft && ReleaseVersion.components($0.tag_name) != nil }
                    .sorted { ReleaseVersion.newer($0.tag_name,than:$1.tag_name) }.first
                if let newest,ReleaseVersion.newer(newest.tag_name,than:current),
                   let destination=URL(string:newest.html_url),destination.scheme=="https",destination.host=="github.com",
                   destination.path.hasPrefix("/zhangliyuangit/codex-finch/releases/tag/") {
                    message="发现 \(newest.tag_name)\(newest.prerelease ? "（预览版）" : "")，可前往发布页。";url=destination
                } else { message="暂未发现新版。" }
            }
            DispatchQueue.main.async { self?.checking=false;self?.message=message;self?.releaseURL=url }
        }.resume()
    }
    private struct PublicRelease: Decodable {
        var tag_name: String
        var html_url: String
        var prerelease: Bool
        var draft: Bool
    }
}
