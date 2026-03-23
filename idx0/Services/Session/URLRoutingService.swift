import AppKit
import Foundation

enum URLRouteTarget {
    case externalBrowser
    case embeddedBrowser
}

protocol URLRoutingServiceProtocol {
    func target(for url: URL) -> URLRouteTarget
    func open(_ url: URL) throws
}

struct URLRoutingService: URLRoutingServiceProtocol {
    var openLinksInDefaultBrowser: Bool

    func target(for url: URL) -> URLRouteTarget {
        guard let scheme = url.scheme?.lowercased() else {
            return .externalBrowser
        }
        if (scheme == "http" || scheme == "https"), !openLinksInDefaultBrowser {
            return .embeddedBrowser
        }
        return .externalBrowser
    }

    func open(_ url: URL) throws {
        NSWorkspace.shared.open(url)
    }
}
