// Copyright 2018 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

library webview_flutter;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

part 'src/callbacks.dart';
part 'src/error.dart';

typedef void WebViewCreatedCallback(WebViewController controller);

/// Handler to prevent loading a web page.
typedef U ArgumentHandler<T, U>(T argument);

enum JavaScriptMode {
  /// JavaScript execution is disabled.
  disabled,

  /// JavaScript execution is not restricted.
  unrestricted,
}

/// A web view widget for showing html content.
class WebView extends StatefulWidget {
  /// Creates a new web view.
  ///
  /// The web view can be controlled using a `WebViewController` that is passed to the
  /// `onWebViewCreated` callback once the web view is created.
  ///
  /// The `javaScriptMode` parameter must not be null.
  /// The `clearCookies` parameter must not be null.
  const WebView({
    Key key,
    this.onWebViewCreated,
    this.initialUrl,
    this.javaScriptMode = JavaScriptMode.disabled,
    this.userAgent,
    this.clearCookies = false,
    this.gestureRecognizers,
  })  : assert(javaScriptMode != null),
        assert(clearCookies != null),
        super(key: key);

  /// If not null invoked once the web view is created.
  final WebViewCreatedCallback onWebViewCreated;

  /// Which gestures should be consumed by the web view.
  ///
  /// It is possible for other gesture recognizers to be competing with the web view on pointer
  /// events, e.g if the web view is inside a [ListView] the [ListView] will want to handle
  /// vertical drags. The web view will claim gestures that are recognized by any of the
  /// recognizers on this list.
  ///
  /// When this set is empty or null, the web view will only handle pointer events for gestures that
  /// were not claimed by any other gesture recognizer.
  final Set<Factory<OneSequenceGestureRecognizer>> gestureRecognizers;

  /// The initial URL to load.
  final String initialUrl;

  /// Whether JavaScript execution is enabled.
  final JavaScriptMode javaScriptMode;

  /// The custom UserAgent.
  final String userAgent;

  /// Whether removing all cookies is enabled.
  ///
  /// It is possible without iOS 8.
  final bool clearCookies;

  @override
  State<StatefulWidget> createState() => _WebViewState();
}

class _WebViewState extends State<WebView> {
  final Completer<WebViewController> _controller =
      Completer<WebViewController>();

  _WebSettings _settings;

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return GestureDetector(
        // We prevent text selection by intercepting the long press event.
        // This is a temporary stop gap due to issues with text selection on Android:
        // https://github.com/flutter/flutter/issues/24585 - the text selection
        // dialog is not responding to touch events.
        // https://github.com/flutter/flutter/issues/24584 - the text selection
        // handles are not showing.
        // TODO(amirh): remove this when the issues above are fixed.
        onLongPress: () {},
        child: AndroidView(
          viewType: 'plugins.flutter.io/webview',
          onPlatformViewCreated: _onPlatformViewCreated,
          gestureRecognizers: widget.gestureRecognizers,
          // WebView content is not affected by the Android view's layout direction,
          // we explicitly set it here so that the widget doesn't require an ambient
          // directionality.
          layoutDirection: TextDirection.rtl,
          creationParams: _CreationParams.fromWidget(widget).toMap(),
          creationParamsCodec: const StandardMessageCodec(),
        ),
      );
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      return UiKitView(
        viewType: 'plugins.flutter.io/webview',
        onPlatformViewCreated: _onPlatformViewCreated,
        gestureRecognizers: widget.gestureRecognizers,
        creationParams: _CreationParams.fromWidget(widget).toMap(),
        creationParamsCodec: const StandardMessageCodec(),
      );
    }
    return Text(
        '$defaultTargetPlatform is not yet supported by the webview_flutter plugin');
  }

  @override
  void initState() {
    super.initState();
    _settings = _WebSettings.fromWidget(widget);
  }

  @override
  void didUpdateWidget(WebView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final _WebSettings newSettings = _WebSettings.fromWidget(widget);
    final Map<String, dynamic> settingsUpdate =
        _settings.updatesMap(newSettings);
    _updateSettings(settingsUpdate);
    _settings = newSettings;
  }

  Future<void> _updateSettings(Map<String, dynamic> update) async {
    if (update == null) {
      return;
    }
    final WebViewController controller = await _controller.future;
    controller._updateSettings(update);
  }

  void _onPlatformViewCreated(int id) {
    final WebViewController controller = WebViewController._(id);
    _controller.complete(controller);
    if (widget.onWebViewCreated != null) {
      widget.onWebViewCreated(controller);
    }
  }
}

class _CreationParams {
  _CreationParams({this.initialUrl, this.settings});

  static _CreationParams fromWidget(WebView widget) {
    return _CreationParams(
      initialUrl: widget.initialUrl,
      settings: _WebSettings.fromWidget(widget),
    );
  }

  final String initialUrl;
  final _WebSettings settings;

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'initialUrl': initialUrl,
      'settings': settings.toMap(),
    };
  }
}

class _WebSettings {
  _WebSettings({
    this.javaScriptMode,
    this.clearCookies,
    this.userAgent
  });

  static _WebSettings fromWidget(WebView widget) {
    return _WebSettings(
        javaScriptMode: widget.javaScriptMode,
        userAgent: widget.userAgent,
        clearCookies: widget.clearCookies);
  }

  final JavaScriptMode javaScriptMode;

  final String userAgent;

  final bool clearCookies;

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'jsMode': javaScriptMode.index,
      'userAgent': userAgent,
      'clearCookies': clearCookies,
    };
  }

  Map<String, dynamic> updatesMap(_WebSettings newSettings) {
    if (javaScriptMode == newSettings.javaScriptMode &&
        userAgent == newSettings.userAgent &&
        clearCookies == newSettings.clearCookies) {
      return null;
    }
    return <String, dynamic>{
      'jsMode': newSettings.javaScriptMode.index,
      'userAgent': newSettings.userAgent,
      'clearCookies': newSettings.clearCookies,
    };
  }
}

/// Controls a [WebView].
///
/// A [WebViewController] instance can be obtained by setting the [WebView.onWebViewCreated]
/// callback for a [WebView] widget.
class WebViewController {
  WebViewController._(int id)
      : _channel = MethodChannel('plugins.flutter.io/webview_$id') {
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  final MethodChannel _channel;

  /// Handles to receive ready to load web page events.
  ArgumentHandler<String, bool> shouldOverrideUrlLoading;

  /// Callbacks to receive start loading web page events.
  final ArgumentCallbacks<String> onPageStarted = ArgumentCallbacks<String>();

  /// Callbacks to receive finish loading web page events.
  final ArgumentCallbacks<String> onPageFinished = ArgumentCallbacks<String>();

  /// Callbacks to receive error loading web page events.
  final ArgumentCallbacks<WebViewError> onReceivedError =
      ArgumentCallbacks<WebViewError>();

  /// Loads the specified URL.
  ///
  /// `url` must not be null.
  ///
  /// Throws an ArgumentError if `url` is not a valid URL string.
  Future<void> loadUrl(String url) async {
    assert(url != null);
    _validateUrlString(url);
    return _channel.invokeMethod('loadUrl', url);
  }

  /// Accessor to the current URL that the WebView is displaying.
  ///
  /// If [WebView.initialUrl] was never specified, returns `null`.
  /// Note that this operation is asynchronous, and it is possible that the
  /// current URL changes again by the time this function returns (in other
  /// words, by the time this future completes, the WebView may be displaying a
  /// different URL).
  Future<String> currentUrl() async {
    final String url = await _channel.invokeMethod('currentUrl');
    return url;
  }

  /// Accessor to the UserAgent.
  Future<String> userAgent() async {
    final String userAgent = await _channel.invokeMethod('userAgent');
    return Future<String>.value(userAgent);
  }

  /// Checks whether there's a back history item.
  ///
  /// Note that this operation is asynchronous, and it is possible that the "canGoBack" state has
  /// changed by the time the future completed.
  Future<bool> canGoBack() async {
    final bool canGoBack = await _channel.invokeMethod("canGoBack");
    return canGoBack;
  }

  /// Checks whether there's a forward history item.
  ///
  /// Note that this operation is asynchronous, and it is possible that the "canGoForward" state has
  /// changed by the time the future completed.
  Future<bool> canGoForward() async {
    final bool canGoForward = await _channel.invokeMethod("canGoForward");
    return canGoForward;
  }

  /// Goes back in the history of this WebView.
  ///
  /// If there is no back history item this is a no-op.
  Future<void> goBack() async {
    return _channel.invokeMethod("goBack");
  }

  /// Goes forward in the history of this WebView.
  ///
  /// If there is no forward history item this is a no-op.
  Future<void> goForward() async {
    return _channel.invokeMethod("goForward");
  }

  /// Reloads the current URL.
  Future<void> reload() async {
    return _channel.invokeMethod("reload");
  }

  /// Stops loading of this WebView.
  Future<void> stopLoading() async {
    return _channel.invokeMethod('stopLoading');
  }

  /// Evaluates a JavaScript expression in the context of the current page.
  ///
  /// On Android returns the evaluation result as a JSON formatted string.
  ///
  /// On iOS depending on the value type the return value would be one of:
  ///
  ///  - For primitive JavaScript types: the value string formatted (e.g JavaScript 100 returns '100').
  ///  - For JavaScript arrays of supported types: a string formatted NSArray(e.g '(1,2,3), note that the string for NSArray is formatted and might contain newlines and extra spaces.').
  ///  - Other non-primitive types are not supported on iOS and will complete the Future with an error.
  ///
  /// The Future completes with an error if a JavaScript error occurred, or on iOS, if the type of the
  /// evaluated expression is not supported as described above.
  Future<String> evaluateJavascript(String javascriptString) async {
    
    if (javascriptString == null) {
      throw ArgumentError('The argument javascriptString must not be null. ');
    }
    // TODO(amirh): remove this on when the invokeMethod update makes it to stable Flutter.
    // https://github.com/flutter/flutter/issues/26431
    // ignore: strong_mode_implicit_dynamic_method
    final String result =
        await _channel.invokeMethod('evaluateJavascript', javascriptString);
    return result;
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'shouldOverrideUrlLoading':
        final String url = call.arguments['url'];
        if (url != null) {
          final bool result = shouldOverrideUrlLoading?.call(url) ?? false;
          return Future<bool>.value(result);
        }
        break;
      case 'onPageStarted':
        final String url = call.arguments['url'];
        if (url != null) {
          onPageStarted(url);
        }
        break;
      case 'onPageFinished':
        final String url = call.arguments['url'];
        if (url != null) {
          onPageFinished(url);
        }
        break;
      case 'onReceivedError':
        final String url = call.arguments['url'];
        final int errorCode = call.arguments['errorCode'];
        final String description = call.arguments['description'];
        if (url != null) {
          final WebViewError error = WebViewError(url, errorCode, description);
          onReceivedError(error);
        }
        break;
      default:
        throw MissingPluginException();
    }
  }

  Future<void> _updateSettings(Map<String, dynamic> update) async {
    return _channel.invokeMethod('updateSettings', update);
  }
}

// Throws an ArgumentError if `url` is not a valid URL string.
void _validateUrlString(String url) {
  try {
    final Uri uri = Uri.parse(url);
    if (uri.scheme.isEmpty) {
      throw ArgumentError('Missing scheme in URL string: "$url"');
    }
  } on FormatException catch (e) {
    throw ArgumentError(e);
  }
}
