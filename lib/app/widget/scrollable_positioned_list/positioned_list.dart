// Copyright 2019 The Fuchsia Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'element_registry.dart';
import 'item_positions_listener.dart';
import 'item_positions_notifier.dart';

/// A list of widgets similar to [ListView], except scroll control
/// and position reporting is based on index rather than pixel offset.
///
/// [PositionedList] lays out children in the same way as [ListView].
///
/// The list can be displayed with the item at [initialScrollIndex] positioned
/// at a particular [initialAlignment], where [initialAlignment] positions the
/// leading edge of the item with [initialScrollIndex] at [initialAlignment] *
/// height of the viewport from the leading edge of the viewport.
///
/// All other parameters are the same as specified in [ListView].
class PositionedList extends StatefulWidget {
  /// Create a [PositionedList].
  const PositionedList({
    @required this.itemCount,
    @required this.itemBuilder,
    this.controller,
    this.itemPositionNotifier,
    this.positionedIndex = 0,
    this.alignment = 0,
    this.scrollDirection = Axis.vertical,
    this.reverse = false,
    this.physics,
    this.padding,
    this.cacheExtent,
    this.semanticChildCount,
    this.addSemanticIndexes = true,
    this.addRepaintBoundaries = true,
    this.addAutomaticKeepAlives = true,
  })  : assert(itemCount != null),
        assert(itemBuilder != null);

  /// Number of items the [itemBuilder] can produce.
  final int itemCount;

  /// Called to build children for the list with
  /// 0 <= index < itemCount.
  final IndexedWidgetBuilder itemBuilder;

  /// An object that can be used to control the position to which this scroll
  /// view is scrolled.
  final ScrollController controller;

  /// Notifier that reports the items laid out in the list after each frame.
  final ItemPositionsNotifier itemPositionNotifier;

  /// Index of an item to initially align to a position within the viewport
  /// defined by [alignment].
  final int positionedIndex;

  /// Determines where the leading edge of the item at [positionedIndex]
  /// should be placed.
  ///
  /// Is a value between '0' and '1' that is a proportion of the main axis
  /// length of viewport from its leading edge.
  final double alignment;

  /// The axis along which the scroll view scrolls.
  ///
  /// Defaults to [Axis.vertical].
  final Axis scrollDirection;

  /// Whether the view scrolls in the reading direction.
  ///
  /// Defaults to false.
  ///
  /// See [ScrollView.reverse].
  final bool reverse;

  /// How the scroll view should respond to user input.
  ///
  /// For example, determines how the scroll view continues to animate after the
  /// user stops dragging the scroll view.
  ///
  /// See [ScrollView.physics].
  final ScrollPhysics physics;

  /// {@macro flutter.widgets.scrollable.cacheExtent}
  final double cacheExtent;

  /// The number of children that will contribute semantic information.
  ///
  /// See [ScrollView.semanticChildCount] for more information.
  final int semanticChildCount;

  /// Whether to wrap each child in an [IndexedSemantics].
  ///
  /// See [SliverChildBuilderDelegate.addSemanticIndexes].
  final bool addSemanticIndexes;

  /// The amount of space by which to inset the children.
  final EdgeInsets padding;

  /// Whether to wrap each child in a [RepaintBoundary].
  ///
  /// See [SliverChildBuilderDelegate.addRepaintBoundaries].
  final bool addRepaintBoundaries;

  /// Whether to wrap each child in an [AutomaticKeepAlive].
  ///
  /// See [SliverChildBuilderDelegate.addAutomaticKeepAlives].
  final bool addAutomaticKeepAlives;

  @override
  State<StatefulWidget> createState() => _PositionedListState();
}

class _PositionedListState extends State<PositionedList> {
  final Key _centerKey = UniqueKey();

  Iterable<ItemPosition> topPositions = [];
  Iterable<ItemPosition> middlePositions = [];
  Iterable<ItemPosition> bottomPositions = [];
  double topSliverPosition = 0;
  double middleSliverPosition = 0;
  double bottomSliverPosition = 0;

  Function postFrameCallback;
  Function persistentFrameCallback;

  final registeredElements = ValueNotifier<Set<Element>>(null);
  ScrollController scrollController;

  bool updateScheduled = false;

  @override
  void initState() {
    super.initState();
    scrollController = widget.controller ?? ScrollController();

    postFrameCallback=(_){
      WidgetsBinding.instance.addPersistentFrameCallback(persistentFrameCallback);
    };
    persistentFrameCallback=(_){
      if(!mounted||!ModalRoute.of(context).isCurrent){
        return;
      }
      if (registeredElements.value == null) return;
//      print("test");
      if (!updateScheduled) {
        updateScheduled = true;
        final positions = <ItemPosition>[];
        RenderViewport viewport;
        for (Element element in registeredElements.value) {
          final RenderBox box = element.renderObject;
          viewport ??= RenderAbstractViewport.of(box);
          final ValueKey<int> key = element.widget.key;
          if (widget.scrollDirection == Axis.vertical) {
            final double reveal = viewport.getOffsetToReveal(box, 0).offset;
            final double itemOffset = reveal -
                viewport.offset.pixels +
                viewport.anchor * viewport.size.height;
            positions.add(ItemPosition(
                index: key.value,
                itemLeadingEdge: itemOffset.round() /
                    scrollController.position.viewportDimension,
                itemTrailingEdge: (itemOffset + box.size.height).round() /
                    scrollController.position.viewportDimension));
          } else {
            final double itemOffset =
                box.localToGlobal(Offset.zero, ancestor: viewport).dx;
            positions.add(ItemPosition(
                index: key.value,
                itemLeadingEdge: (widget.reverse
                    ? scrollController.position.viewportDimension -
                    (itemOffset + box.size.width)
                    : itemOffset)
                    .round() /
                    scrollController.position.viewportDimension,
                itemTrailingEdge: (widget.reverse
                    ? scrollController.position.viewportDimension -
                    itemOffset
                    : (itemOffset + box.size.width))
                    .round() /
                    scrollController.position.viewportDimension));
          }
        }
        widget.itemPositionNotifier?.itemPositions?.value = positions;
        updateScheduled = false;
      }
    };

    _schedulePositionNotificationUpdate();

  }

  @override
  void dispose() {
    super.dispose();
    persistentFrameCallback=null;
    postFrameCallback=null;
  }

  @override
  void didUpdateWidget(PositionedList oldWidget) {
    super.didUpdateWidget(oldWidget);
  }

  @override
  Widget build(BuildContext context) => RegistryWidget(
        elementNotifier: registeredElements,
        child: PrimaryScrollController(
          controller: scrollController,
          child: CustomScrollView(
            anchor: widget.alignment,
            center: _centerKey,
            controller: scrollController,
            scrollDirection: widget.scrollDirection,
            reverse: widget.reverse,
            physics: widget.physics,
            semanticChildCount: widget.semanticChildCount ?? widget.itemCount,
            slivers: <Widget>[
              SliverPadding(
                padding: EdgeInsets.only(
                    top: widget.padding?.top ?? 0,
                    left: widget.padding?.left ?? 0,
                    right: widget.padding?.right ?? 0),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) =>
                        _buildItem(widget.positionedIndex - (index + 1)),
                    childCount: widget.positionedIndex,
                    addSemanticIndexes: false,
                    addRepaintBoundaries: widget.addRepaintBoundaries,
                    addAutomaticKeepAlives: widget.addAutomaticKeepAlives,
                  ),
                ),
              ),
              SliverPadding(
                key: _centerKey,
                padding: EdgeInsets.only(
                    top: widget.positionedIndex == 0
                        ? widget.padding?.top ?? 0
                        : 0,
                    bottom: widget.positionedIndex == widget.itemCount - 1
                        ? widget.padding?.bottom ?? 0
                        : 0,
                    left: widget.padding?.left ?? 0,
                    right: widget.padding?.right ?? 0),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) =>
                        _buildItem(index + widget.positionedIndex),
                    childCount: 1,
                    addSemanticIndexes: false,
                    addRepaintBoundaries: widget.addRepaintBoundaries,
                    addAutomaticKeepAlives: widget.addAutomaticKeepAlives,
                  ),
                ),
              ),
              SliverPadding(
                padding: EdgeInsets.only(
                    bottom: widget.padding?.bottom ?? 0,
                    left: widget.padding?.left ?? 0,
                    right: widget.padding?.right ?? 0),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) =>
                        _buildItem(index + widget.positionedIndex + 1),
                    childCount: widget.itemCount - widget.positionedIndex - 1,
                    addSemanticIndexes: false,
                    addRepaintBoundaries: widget.addRepaintBoundaries,
                    addAutomaticKeepAlives: widget.addAutomaticKeepAlives,
                  ),
                ),
              ),
            ],
          ),
        ),
      );

  Widget _buildItem(int index) {
    return RegisteredElementWidget(
      key: ValueKey(index),
      child: widget.addSemanticIndexes
          ? IndexedSemantics(
              index: index, child: widget.itemBuilder(context, index))
          : widget.itemBuilder(context, index),
    );
  }

  void _schedulePositionNotificationUpdate() {
      SchedulerBinding.instance.addPostFrameCallback(postFrameCallback);
  }
}
