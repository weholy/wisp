import Foundation
import UIKit
import AsyncDisplayKit
import Display
import SwiftSignalKit
import TelegramPresentationData
import ItemListUI
import ComponentFlow
import SliderComponent

/// Title, current value and a slider in one block — the layout from the reference screenshot.
///
/// Modelled on ThemeSettingsBrightnessItem, which is the project's working example of an
/// item list row wrapping TGPhotoEditorSliderView.
final class NetegramStarsSliderItem: ListViewItem, ItemListItem {
    let theme: PresentationTheme
    let title: String
    let value: Int
    let maxValue: Int
    let enabled: Bool
    let sectionId: ItemListSectionId
    let updated: (Int) -> Void

    init(theme: PresentationTheme, title: String, value: Int, maxValue: Int, enabled: Bool, sectionId: ItemListSectionId, updated: @escaping (Int) -> Void) {
        self.theme = theme
        self.title = title
        self.value = value
        self.maxValue = maxValue
        self.enabled = enabled
        self.sectionId = sectionId
        self.updated = updated
    }

    func nodeConfiguredForParams(async: @escaping (@escaping () -> Void) -> Void, params: ListViewItemLayoutParams, synchronousLoads: Bool, previousItem: ListViewItem?, nextItem: ListViewItem?, completion: @escaping (ListViewItemNode, @escaping () -> (Signal<Void, NoError>?, (ListViewItemApply) -> Void)) -> Void) {
        async {
            let node = NetegramStarsSliderItemNode()
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
            if let nodeValue = node() as? NetegramStarsSliderItemNode {
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

final class NetegramStarsSliderItemNode: ListViewItemNode {
    private let backgroundNode: ASDisplayNode
    private let topStripeNode: ASDisplayNode
    private let bottomStripeNode: ASDisplayNode
    private let maskNode: ASImageNode

    private let titleNode: TextNode
    private let valueNode: TextNode
    /// SliderComponent is the project's current slider — the legacy TGPhotoEditorSliderView
    /// still looks like the old system control.
    private let sliderHost = ComponentView<Empty>()

    private var item: NetegramStarsSliderItem?
    private var layoutParams: ListViewItemLayoutParams?

    init() {
        self.backgroundNode = ASDisplayNode()
        self.backgroundNode.isLayerBacked = true

        self.topStripeNode = ASDisplayNode()
        self.topStripeNode.isLayerBacked = true

        self.bottomStripeNode = ASDisplayNode()
        self.bottomStripeNode.isLayerBacked = true

        self.maskNode = ASImageNode()

        self.titleNode = TextNode()
        self.titleNode.isUserInteractionEnabled = false

        self.valueNode = TextNode()
        self.valueNode.isUserInteractionEnabled = false

        super.init(layerBacked: false)

        self.addSubnode(self.titleNode)
        self.addSubnode(self.valueNode)
    }

    func asyncLayout() -> (_ item: NetegramStarsSliderItem, _ params: ListViewItemLayoutParams, _ neighbors: ItemListNeighbors) -> (ListViewItemNodeLayout, () -> Void) {
        let makeTitleLayout = TextNode.asyncLayout(self.titleNode)
        let makeValueLayout = TextNode.asyncLayout(self.valueNode)

        return { item, params, neighbors in
            let leftInset: CGFloat = 16.0 + params.leftInset
            let rightInset: CGFloat = 16.0 + params.rightInset

            let (titleLayout, titleApply) = makeTitleLayout(TextNodeLayoutArguments(
                attributedString: NSAttributedString(string: item.title, font: Font.regular(17.0), textColor: item.theme.list.itemPrimaryTextColor),
                maximumNumberOfLines: 1,
                truncationType: .end,
                constrainedSize: CGSize(width: params.width - leftInset - rightInset - 100.0, height: 24.0),
                insets: UIEdgeInsets()
            ))
            let (valueLayout, valueApply) = makeValueLayout(TextNodeLayoutArguments(
                attributedString: NSAttributedString(string: "\(item.value)", font: Font.regular(17.0), textColor: item.theme.list.itemSecondaryTextColor),
                maximumNumberOfLines: 1,
                truncationType: .end,
                constrainedSize: CGSize(width: 140.0, height: 24.0),
                insets: UIEdgeInsets()
            ))

            let contentSize = CGSize(width: params.width, height: 88.0)
            let insets = itemListNeighborsGroupedInsets(neighbors, params)
            let separatorHeight = UIScreenPixel

            let layout = ListViewItemNodeLayout(contentSize: contentSize, insets: insets)
            let layoutSize = layout.size

            return (layout, { [weak self] in
                guard let strongSelf = self else {
                    return
                }
                strongSelf.item = item
                strongSelf.layoutParams = params

                let _ = titleApply()
                let _ = valueApply()

                strongSelf.backgroundNode.backgroundColor = item.theme.list.itemBlocksBackgroundColor
                strongSelf.topStripeNode.backgroundColor = item.theme.list.itemBlocksSeparatorColor
                strongSelf.bottomStripeNode.backgroundColor = item.theme.list.itemBlocksSeparatorColor

                if strongSelf.backgroundNode.supernode == nil {
                    strongSelf.insertSubnode(strongSelf.backgroundNode, at: 0)
                }
                if strongSelf.topStripeNode.supernode == nil {
                    strongSelf.insertSubnode(strongSelf.topStripeNode, at: 1)
                }
                if strongSelf.bottomStripeNode.supernode == nil {
                    strongSelf.insertSubnode(strongSelf.bottomStripeNode, at: 2)
                }
                if strongSelf.maskNode.supernode == nil {
                    strongSelf.insertSubnode(strongSelf.maskNode, at: 3)
                }

                let hasCorners = itemListHasRoundedBlockLayout(params)
                var hasTopCorners = false
                var hasBottomCorners = false
                switch neighbors.top {
                case .sameSection(false):
                    strongSelf.topStripeNode.isHidden = true
                default:
                    hasTopCorners = true
                    strongSelf.topStripeNode.isHidden = hasCorners
                }
                let bottomStripeInset: CGFloat
                let bottomStripeOffset: CGFloat
                switch neighbors.bottom {
                case .sameSection(false):
                    bottomStripeInset = leftInset
                    bottomStripeOffset = -separatorHeight
                    strongSelf.bottomStripeNode.isHidden = false
                default:
                    bottomStripeInset = 0.0
                    bottomStripeOffset = 0.0
                    hasBottomCorners = true
                    strongSelf.bottomStripeNode.isHidden = hasCorners
                }

                strongSelf.maskNode.image = hasCorners ? PresentationResourcesItemList.cornersImage(item.theme, top: hasTopCorners, bottom: hasBottomCorners) : nil

                strongSelf.backgroundNode.frame = CGRect(origin: CGPoint(x: 0.0, y: -min(insets.top, separatorHeight)), size: CGSize(width: params.width, height: contentSize.height + min(insets.top, separatorHeight) + min(insets.bottom, separatorHeight)))
                strongSelf.maskNode.frame = strongSelf.backgroundNode.frame.insetBy(dx: params.leftInset, dy: 0.0)
                strongSelf.topStripeNode.frame = CGRect(origin: CGPoint(x: 0.0, y: -min(insets.top, separatorHeight)), size: CGSize(width: layoutSize.width, height: separatorHeight))
                strongSelf.bottomStripeNode.frame = CGRect(origin: CGPoint(x: bottomStripeInset, y: contentSize.height + bottomStripeOffset), size: CGSize(width: layoutSize.width - bottomStripeInset, height: separatorHeight))

                strongSelf.titleNode.frame = CGRect(origin: CGPoint(x: leftInset, y: 12.0), size: titleLayout.size)
                strongSelf.valueNode.frame = CGRect(origin: CGPoint(x: params.width - rightInset - valueLayout.size.width, y: 12.0), size: valueLayout.size)

                let sliderSize = CGSize(width: params.width - leftInset - rightInset, height: 44.0)
                let maxValue = max(1, item.maxValue)
                let _ = strongSelf.sliderHost.update(
                    transition: .immediate,
                    component: AnyComponent(SliderComponent(
                        content: .continuous(SliderComponent.Continuous(
                            value: CGFloat(item.value) / CGFloat(maxValue),
                            range: 0.0 ... 1.0,
                            valueUpdated: { fraction in
                                // The slider works in a 0...1 range; the caller wants an
                                // absolute star count.
                                item.updated(Int(fraction * CGFloat(maxValue)))
                            }
                        )),
                        // The system control picks up the current OS slider design on its
                        // own; the custom drawing path still looks like older iOS.
                        useNative: true,
                        trackBackgroundColor: item.theme.list.itemSwitchColors.frameColor,
                        trackForegroundColor: item.theme.list.itemAccentColor,
                        isEnabled: item.enabled
                    )),
                    environment: {},
                    containerSize: sliderSize
                )
                if let sliderView = strongSelf.sliderHost.view {
                    if sliderView.superview == nil {
                        strongSelf.view.addSubview(sliderView)
                    }
                    sliderView.frame = CGRect(origin: CGPoint(x: leftInset, y: 38.0), size: sliderSize)
                    sliderView.alpha = item.enabled ? 1.0 : 0.4
                }
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
