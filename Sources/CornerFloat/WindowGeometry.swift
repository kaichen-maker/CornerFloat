import AppKit

enum HorizontalScreenEdge: String, Equatable {
    case left
    case right
}

enum WindowGeometry {
    static let defaultMargin: CGFloat = 18

    static func bottomRightOrigin(
        windowSize: CGSize,
        visibleFrame: CGRect,
        margin: CGFloat = defaultMargin,
        cascadeIndex: Int = 0
    ) -> CGPoint {
        let offset = CGFloat(max(0, cascadeIndex)) * 22
        let proposedX = visibleFrame.maxX - windowSize.width - margin - offset
        let proposedY = visibleFrame.minY + margin + offset

        let maxX = max(visibleFrame.minX, visibleFrame.maxX - windowSize.width)
        let maxY = max(visibleFrame.minY, visibleFrame.maxY - windowSize.height)

        return CGPoint(
            x: min(max(proposedX, visibleFrame.minX), maxX),
            y: min(max(proposedY, visibleFrame.minY), maxY)
        )
    }

    static func nearestHorizontalEdge(
        to windowFrame: CGRect,
        in visibleFrame: CGRect
    ) -> HorizontalScreenEdge {
        let leftDistance = abs(windowFrame.minX - visibleFrame.minX)
        let rightDistance = abs(visibleFrame.maxX - windowFrame.maxX)
        return leftDistance < rightDistance ? .left : .right
    }

    static func isNearHorizontalEdge(
        _ edge: HorizontalScreenEdge,
        windowFrame: CGRect,
        visibleFrame: CGRect,
        threshold: CGFloat
    ) -> Bool {
        let distance: CGFloat
        switch edge {
        case .left:
            distance = abs(windowFrame.minX - visibleFrame.minX)
        case .right:
            distance = abs(visibleFrame.maxX - windowFrame.maxX)
        }
        return distance <= max(0, threshold)
    }

    static func dockedFrame(
        _ windowFrame: CGRect,
        to edge: HorizontalScreenEdge,
        in visibleFrame: CGRect,
        inset: CGFloat = 0
    ) -> CGRect {
        let safeInset = max(0, inset)
        var result = clampedFrame(windowFrame, inside: visibleFrame, margin: 0)
        switch edge {
        case .left:
            result.origin.x = visibleFrame.minX + safeInset
        case .right:
            result.origin.x = visibleFrame.maxX - result.width - safeInset
        }
        return result
    }

    static func collapsedFrame(
        expandedFrame: CGRect,
        at edge: HorizontalScreenEdge,
        in visibleFrame: CGRect,
        revealWidth: CGFloat
    ) -> CGRect {
        var result = expandedFrame
        let visibleStrip = min(max(revealWidth, 2), max(expandedFrame.width, 2))
        switch edge {
        case .left:
            result.origin.x = visibleFrame.minX - expandedFrame.width + visibleStrip
        case .right:
            result.origin.x = visibleFrame.maxX - visibleStrip
        }
        result.origin.y = min(
            max(result.origin.y, visibleFrame.minY),
            max(visibleFrame.minY, visibleFrame.maxY - result.height)
        )
        return result
    }

    static func clampedFrame(
        _ windowFrame: CGRect,
        inside visibleFrame: CGRect,
        margin: CGFloat = 12
    ) -> CGRect {
        let safeMargin = max(0, margin)
        var result = windowFrame
        let availableWidth = max(1, visibleFrame.width - safeMargin * 2)
        let availableHeight = max(1, visibleFrame.height - safeMargin * 2)
        result.size.width = min(result.width, availableWidth)
        result.size.height = min(result.height, availableHeight)
        result.origin.x = min(
            max(result.origin.x, visibleFrame.minX + safeMargin),
            visibleFrame.maxX - result.width - safeMargin
        )
        result.origin.y = min(
            max(result.origin.y, visibleFrame.minY + safeMargin),
            visibleFrame.maxY - result.height - safeMargin
        )
        return result
    }

    static func bestVisibleFrame(
        for windowFrame: CGRect,
        candidates: [CGRect],
        fallback: CGRect? = nil
    ) -> CGRect? {
        guard !candidates.isEmpty else { return fallback }

        let intersecting = candidates.max { first, second in
            intersectionArea(windowFrame, first) < intersectionArea(windowFrame, second)
        }
        if let intersecting, intersectionArea(windowFrame, intersecting) > 0 {
            return intersecting
        }

        let center = CGPoint(x: windowFrame.midX, y: windowFrame.midY)
        return candidates.min { first, second in
            squaredDistance(from: center, to: first) < squaredDistance(from: center, to: second)
        } ?? fallback
    }

    private static func intersectionArea(_ first: CGRect, _ second: CGRect) -> CGFloat {
        let intersection = first.intersection(second)
        guard !intersection.isNull else { return 0 }
        return intersection.width * intersection.height
    }

    private static func squaredDistance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let closestX = min(max(point.x, rect.minX), rect.maxX)
        let closestY = min(max(point.y, rect.minY), rect.maxY)
        let dx = point.x - closestX
        let dy = point.y - closestY
        return dx * dx + dy * dy
    }
}
