import Foundation
import UIKit
import AsyncDisplayKit
import Display
import SwiftSignalKit
import TelegramPresentationData
import ItemListUI
import AppBundle

/// Netegram's own revision, shown in brackets after the app version.
///
/// Kept by hand: the CI build number counts commits and jumps around, so it says nothing
/// about how many changes the client itself has gone through. Bump this with each change.
public let netegramRevision: Int = 57

/// Logo, name and version at the top of the Netegram screen.
final class NetegramHeaderItem: ListViewItem, ItemListItem {
    let theme: PresentationTheme
    /// The revision counts changes to this fork, which is a number only the person making them
    /// has any use for. Everyone else sees the app version alone.
    let showsRevision: Bool
    let sectionId: ItemListSectionId

    init(theme: PresentationTheme, showsRevision: Bool, sectionId: ItemListSectionId) {
        self.theme = theme
        self.showsRevision = showsRevision
        self.sectionId = sectionId
    }

    func nodeConfiguredForParams(async: @escaping (@escaping () -> Void) -> Void, params: ListViewItemLayoutParams, synchronousLoads: Bool, previousItem: ListViewItem?, nextItem: ListViewItem?, completion: @escaping (ListViewItemNode, @escaping () -> (Signal<Void, NoError>?, (ListViewItemApply) -> Void)) -> Void) {
        async {
            let node = NetegramHeaderItemNode()
            let (layout, apply) = node.asyncLayout()(self, params, itemListNeighbors(item: self, topItem: previousItem as? ItemListItem, bottomItem: nextItem as? ItemListItem))

            node.contentSize = layout.contentSize
            node.insets = layout.insets

            Queue.mainQueue().async {
                completion(node, {
                    return (nil, { _ in apply() })
                })
            }
        }
    }

    func updateNode(async: @escaping (@escaping () -> Void) -> Void, node: @escaping () -> ListViewItemNode, params: ListViewItemLayoutParams, previousItem: ListViewItem?, nextItem: ListViewItem?, animation: ListViewItemUpdateAnimation, completion: @escaping (ListViewItemNodeLayout, @escaping (ListViewItemApply) -> Void) -> Void) {
        Queue.mainQueue().async {
            if let nodeValue = node() as? NetegramHeaderItemNode {
                let layout = nodeValue.asyncLayout()
                async {
                    let (nodeLayout, apply) = layout(self, params, itemListNeighbors(item: self, topItem: previousItem as? ItemListItem, bottomItem: nextItem as? ItemListItem))
                    Queue.mainQueue().async {
                        completion(nodeLayout, { _ in
                            apply()
                        })
                    }
                }
            }
        }
    }
}

final class NetegramHeaderItemNode: ListViewItemNode {
    private let logoNode: ASImageNode
    private let titleNode: TextNode
    private let versionNode: TextNode

    init() {
        self.logoNode = ASImageNode()
        self.logoNode.displaysAsynchronously = false
        self.logoNode.displayWithoutProcessing = true
        self.logoNode.contentMode = .scaleAspectFit

        self.titleNode = TextNode()
        self.titleNode.isUserInteractionEnabled = false

        self.versionNode = TextNode()
        self.versionNode.isUserInteractionEnabled = false

        super.init(layerBacked: false)

        self.addSubnode(self.logoNode)
        self.addSubnode(self.titleNode)
        self.addSubnode(self.versionNode)
    }

    func asyncLayout() -> (_ item: NetegramHeaderItem, _ params: ListViewItemLayoutParams, _ neighbors: ItemListNeighbors) -> (ListViewItemNodeLayout, () -> Void) {
        let makeTitleLayout = TextNode.asyncLayout(self.titleNode)
        let makeVersionLayout = TextNode.asyncLayout(self.versionNode)
        let currentLogo = self.logoNode.image

        return { item, params, neighbors in
            let logoSize = CGSize(width: 70.0, height: 70.0)
            let topInset: CGFloat = 24.0
            let logoToTitle: CGFloat = 14.0
            let titleToVersion: CGFloat = 4.0
            let bottomInset: CGFloat = 28.0

            let appVersion = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? ""

            let (titleLayout, titleApply) = makeTitleLayout(TextNodeLayoutArguments(
                attributedString: NSAttributedString(string: "Netegram", font: Font.bold(28.0), textColor: item.theme.list.itemPrimaryTextColor),
                maximumNumberOfLines: 1,
                truncationType: .end,
                constrainedSize: CGSize(width: params.width - 32.0, height: 40.0),
                insets: UIEdgeInsets()
            ))
            let (versionLayout, versionApply) = makeVersionLayout(TextNodeLayoutArguments(
                attributedString: NSAttributedString(string: item.showsRevision ? "\(appVersion) (\(netegramRevision))" : appVersion, font: Font.semibold(17.0), textColor: item.theme.list.itemSecondaryTextColor),
                maximumNumberOfLines: 1,
                truncationType: .end,
                constrainedSize: CGSize(width: params.width - 32.0, height: 24.0),
                insets: UIEdgeInsets()
            ))

            let contentHeight = topInset + logoSize.height + logoToTitle + titleLayout.size.height + titleToVersion + versionLayout.size.height + bottomInset
            let contentSize = CGSize(width: params.width, height: contentHeight)
            // No grouped insets: the header stands on its own above the first block.
            let layout = ListViewItemNodeLayout(contentSize: contentSize, insets: UIEdgeInsets())

            return (layout, { [weak self] in
                guard let strongSelf = self else {
                    return
                }
                let _ = titleApply()
                let _ = versionApply()

                if currentLogo == nil {
                    strongSelf.logoNode.image = UIImage(bundleImageName: "Netegram Icons/HeaderLogo")
                }

                strongSelf.logoNode.frame = CGRect(
                    origin: CGPoint(x: floorToScreenPixels((params.width - logoSize.width) / 2.0), y: topInset),
                    size: logoSize
                )
                strongSelf.titleNode.frame = CGRect(
                    origin: CGPoint(x: floorToScreenPixels((params.width - titleLayout.size.width) / 2.0), y: topInset + logoSize.height + logoToTitle),
                    size: titleLayout.size
                )
                strongSelf.versionNode.frame = CGRect(
                    origin: CGPoint(x: floorToScreenPixels((params.width - versionLayout.size.width) / 2.0), y: topInset + logoSize.height + logoToTitle + titleLayout.size.height + titleToVersion),
                    size: versionLayout.size
                )
            })
        }
    }

    override func animateInsertion(_ currentTimestamp: Double, duration: Double, options: ListViewItemAnimationOptions) {
        self.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.4)
    }

    override func animateRemoved(_ currentTimestamp: Double, duration: Double) {
        self.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.15, removeOnCompletion: false)
    }
}
