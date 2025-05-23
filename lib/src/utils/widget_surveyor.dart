// Licensed to the Apache Software Foundation (ASF) under one or more
// contributor license agreements. See the NOTICE file distributed with
// this work for additional information regarding copyright ownership.
// The ASF licenses this file to you under the Apache License,
// Version 2.0 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Allows callers to measure the size of arbitrary widgets when laid out with
/// specific constraints.
///
/// The widget surveyor creates synthetic widget trees to hold the widgets it
/// measures. This is crucial because widgets relying on inherited widgets
/// (e.g., [Directionality]) assume they exist in their ancestry. These
/// assumptions may hold true when the widget is rendered by the application but
/// prove false when the widget is rendered via the widget surveyor.
///
/// Due to this, callers should ensure that:
///
///  1. Passed-in widgets do not rely on inherited widgets, or
///  2. All necessary inherited widget dependencies exist in the widget tree
///  provided to the widget surveyor's measure methods.
class WidgetSurveyor {
  const WidgetSurveyor();

  /// Builds a widget using the specified builder function, inserts the widget
  /// into a synthetic widget tree, lays out the resulting render tree, and
  /// returns the size of the laid-out render tree.
  ///
  /// The build context passed to the [builder] function represents the root of
  /// the synthetic tree.
  ///
  /// The [constraints] argument specifies the constraints passed to the render
  /// tree during layout. If unspecified, the widget will be laid out
  /// unconstrained.
  Size measureBuilder(
    WidgetBuilder builder, {
    BoxConstraints constraints = const BoxConstraints(),
  }) {
    return measureWidget(Builder(builder: builder), constraints: constraints);
  }

  /// Inserts the specified widget into a synthetic widget tree, lays out the
  /// resulting render tree, and returns the size of the laid-out render tree.
  ///
  /// The [constraints] argument specifies the constraints passed to the render
  /// tree during layout. If unspecified, the widget will be laid out
  /// unconstrained.
  Size measureWidget(
    Widget widget, {
    BoxConstraints constraints = const BoxConstraints(),
  }) {
    final SurveyorView rendered = _render(widget, constraints);
    assert(rendered.hasSize);
    return rendered.size;
  }

  double measureDistanceToBaseline(
    Widget widget, {
    TextBaseline baseline = TextBaseline.alphabetic,
    BoxConstraints constraints = const BoxConstraints(),
  }) {
    final SurveyorView rendered =
        _render(widget, constraints, baselineToCalculate: baseline);
    return rendered.childBaseline ?? rendered.size.height;
  }

  double? measureDistanceToActualBaseline(
    Widget widget, {
    TextBaseline baseline = TextBaseline.alphabetic,
    BoxConstraints constraints = const BoxConstraints(),
  }) {
    final SurveyorView rendered =
        _render(widget, constraints, baselineToCalculate: baseline);
    return rendered.childBaseline;
  }

  SurveyorView _render(
    Widget widget,
    BoxConstraints constraints, {
    TextBaseline? baselineToCalculate,
  }) {
    bool debugIsPerformingCleanup = false;
    final PipelineOwner pipelineOwner = PipelineOwner(
      onNeedVisualUpdate: () {
        assert(() {
          if (!debugIsPerformingCleanup) {
            throw FlutterError.fromParts(<DiagnosticsNode>[
              ErrorSummary('Visual update was requested during survey.'),
              ErrorDescription(
                  'WidgetSurveyor does not support a render object '
                  'calling markNeedsLayout(), markNeedsPaint(), or '
                  'markNeedsSemanticUpdate() while the widget is being surveyed.'),
            ]);
          }
          return true;
        }());
      },
    );
    final SurveyorView rootView = pipelineOwner.rootNode = SurveyorView();
    final BuildOwner buildOwner = BuildOwner(focusManager: FocusManager());
    assert(buildOwner.globalKeyCount == 0);
    final RenderObjectToWidgetElement element =
        RenderObjectToWidgetAdapter<RenderBox>(
      container: rootView,
      debugShortDescription: '[root]',
      child: widget,
    ).attachToRenderTree(buildOwner);
    try {
      rootView.baselineToCalculate = baselineToCalculate;
      rootView.childConstraints = constraints;
      rootView.scheduleInitialLayout();
      pipelineOwner.flushLayout();
      assert(rootView.child != null);
      return rootView;
    } finally {
      // Unmounts all child elements to ensure proper cleanup.
      debugIsPerformingCleanup = true;
      try {
        element.update(
          RenderObjectToWidgetAdapter<RenderBox>(container: rootView),
        );
        buildOwner.finalizeTree();
      } finally {
        debugIsPerformingCleanup = false;
      }
      assert(
        buildOwner.globalKeyCount == 1,
      ); // RenderObjectToWidgetAdapter uses a global key.
    }
  }
}

class SurveyorView extends RenderBox
    with RenderObjectWithChildMixin<RenderBox> {
  BoxConstraints? childConstraints;
  TextBaseline? baselineToCalculate;
  double? childBaseline;

  @override
  void performLayout() {
    assert(child != null);
    assert(childConstraints != null);
    child!.layout(childConstraints!, parentUsesSize: true);
    if (baselineToCalculate != null) {
      childBaseline = child!.getDistanceToBaseline(baselineToCalculate!);
    }
    size = child!.size;
  }

  @override
  void debugAssertDoesMeetConstraints() => true;
}
