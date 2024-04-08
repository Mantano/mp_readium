import 'dart:convert';
import 'dart:io';

import 'package:dartx/dartx.dart';
import 'package:dfunc/dfunc.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:iridium_reader_widget/views/viewers/book_screen.dart';
import 'package:iridium_reader_widget/views/viewers/model/fonts.dart';
import 'package:mno_commons/utils/functions.dart';
import 'package:mno_navigator/epub.dart';
import 'package:mno_navigator/publication.dart';
import 'package:mno_server/mno_server.dart';
import 'package:mno_shared/mediatype.dart';
import 'package:mno_shared/publication.dart';
import 'package:mno_streamer/parser.dart';

class EpubScreen extends BookScreen {
  final String? location;
  final int? settings;
  final bool isTextInteractionEnabled;
  final Map<String, dynamic>? theme;
  ReaderThemeConfig? themeObject;
  final int? startPage;

  EpubScreen(
      {super.key,
      required super.asset,
      super.onDocumentLoaded,
      super.onPageSwiped,
      this.themeObject,
      super.readerAnnotationRepository,
      super.paginationCallback,
      this.location,
      this.settings,
      this.startPage,
      this.theme,
      this.isTextInteractionEnabled = true}) {
    themeObject = themeObject ?? ReaderThemeConfig.defaultTheme;
  }

  factory EpubScreen.fromPath(
      {Key? key,
      required String filePath,
      ReaderAnnotationRepository? readerAnnotationRepository,
      PaginationCallback? paginationCallback,
      String? location,
      String? settings,
      String? theme,
      int? startPage,
      Function(double totalNumberOfPages)? onDocumentLoaded,
      Function(
              String href, int percentage, int spineItemIndex, int currentPage)?
          onPageSwiped,
      ReaderThemeConfig? themeObject,
      bool isTextInteractionEnabled = true}) {
    Map<String, dynamic>? decodedTheme;
    try {
      decodedTheme = json.decode(theme!);
    } catch (e) {
      debugPrint('failure to decode theme: $e');
    }
    return EpubScreen(
      key: key,
      themeObject: themeObject,
      startPage: startPage,
      onDocumentLoaded: onDocumentLoaded,
      onPageSwiped: onPageSwiped,
      asset: FileAsset(File(filePath)),
      readerAnnotationRepository: readerAnnotationRepository,
      paginationCallback: paginationCallback,
      location: location,
      settings: int.tryParse(settings ?? '100'),
      theme: decodedTheme,
      isTextInteractionEnabled: isTextInteractionEnabled,
    );
  }

  factory EpubScreen.fromFile(
      {Key? key,
      required File file,
      ReaderAnnotationRepository? readerAnnotationRepository,
      PaginationCallback? paginationCallback,
      ReaderThemeConfig? themeObject,
      int? startPage,
      Function(double totalNumberOfPages)? onDocumentLoaded,
      Function(
              String href, int percentage, int spineItemIndex, int currentPage)?
          onPageSwiped,
      String? location,
      String? settings,
      String? theme,
      bool isTextInteractionEnabled = true}) {
    Map<String, dynamic>? decodedTheme;
    try {
      decodedTheme = json.decode(theme!);
    } catch (e) {
      debugPrint('failure to decode theme: $e');
    }
    return EpubScreen(
      key: key,
      onPageSwiped: onPageSwiped,
      startPage: startPage,
      onDocumentLoaded: onDocumentLoaded,
      themeObject: themeObject,
      asset: FileAsset(file),
      readerAnnotationRepository: readerAnnotationRepository,
      paginationCallback: paginationCallback,
      location: location,
      settings: int.tryParse(settings ?? '100'),
      theme: decodedTheme,
      isTextInteractionEnabled: isTextInteractionEnabled,
    );
  }

  factory EpubScreen.fromUri(
      {Key? key,
      required String rootHref,
      ReaderAnnotationRepository? readerAnnotationRepository,
      ReaderThemeConfig? themeObject,
      PaginationCallback? paginationCallback,
      Function(double totalNumberOfPages)? onDocumentLoaded,
      Function(
              String href, int percentage, int spineItemIndex, int currentPage)?
          onPageSwiped,
      MediaType? mimeType,
      String? location,
      String? settings,
      int? startPage,
      String? theme,
      bool isTextInteractionEnabled = true}) {
    Map<String, dynamic>? decodedTheme; //Theme
    try {
      decodedTheme = json.decode(theme!);
    } catch (e) {
      debugPrint('failure to decode theme: $e');
    }
    return EpubScreen(
      key: key,
      onDocumentLoaded: onDocumentLoaded,
      onPageSwiped: onPageSwiped,
      startPage: startPage,
      themeObject: themeObject,
      asset: HttpAsset(rootHref, knownMediaType: mimeType),
      readerAnnotationRepository: readerAnnotationRepository,
      paginationCallback: paginationCallback,
      location: location,
      settings: int.tryParse(settings ?? '100'),
      theme: decodedTheme,
      isTextInteractionEnabled: isTextInteractionEnabled,
    );
  }

  @override
  State<StatefulWidget> createState() => EpubScreenState();
}

class EpubScreenState extends BookScreenState<EpubScreen, EpubController> {
  late ViewerSettingsBloc _viewerSettingsBloc;
  late ReaderThemeBloc _readerThemeBloc;

  @override
  void initState() {
    super.initState();
    _viewerSettingsBloc = ViewerSettingsBloc(EpubReaderState(
        "", widget.settings ?? 100, widget.isTextInteractionEnabled));
    debugPrint(widget.theme.toString());
    _readerThemeBloc = ReaderThemeBloc(widget.theme != null
        ? ReaderThemeConfig.fromJson(widget.theme!)
        : widget.themeObject);
  }

  @override
  void onPopInvoked(didPop) async {
    try {
      readerContext.paginationInfo?.let((paginationInfo) =>
          readerAnnotationRepository.savePosition(paginationInfo));
      Navigator.pop(context, {
        'locator': readerContext.paginationInfo?.locator.json,
        'settings': _viewerSettingsBloc.viewerSettings.fontSize.toString(),
        'theme': json.encode(_readerThemeBloc.currentTheme.toJson()),
      });
    } catch (e) {
      // perhaps a snackbar notification can be added to indicate that there was a problem saving last location and settings
      debugPrint('error returning location and settings');
    }
  }

  //NOTE: The startup location when the epub is opened for the first time.
  @override
  Future<String?> get openLocation async {
    if (widget.location != null) {
      return widget.location;
    }
    return readerAnnotationRepository
        .getPosition()
        .then((position) => position?.location);
  }

  SelectionListenerFactory get selectionListenerFactory =>
      SimpleSelectionListenerFactory(this);

  @override
  EpubController createPublicationController(
          Function onServerClosed,
          Function? onPageJump,
          Future<String?> locationFuture,
          PublicationAsset fileAsset,
          Future<Streamer> streamerFuture,
          ReaderAnnotationRepository readerAnnotationRepository,
          Function0<List<RequestHandler>> handlersProvider) =>
      EpubController(
        onServerClosed,
        onPageJump,
        locationFuture,
        onDocumentLoaded,
        widget.onPageSwiped,
        fileAsset,
        streamerFuture,
        readerAnnotationRepository,
        handlersProvider,
        selectionListenerFactory,
      );

  void onDocumentLoaded(double totalNumberOfPages) {
    if (widget.onDocumentLoaded != null) {
      widget.onDocumentLoaded!(totalNumberOfPages);
    }
    if (widget.startPage != null && widget.startPage! < totalNumberOfPages) {
      Future.delayed(const Duration(seconds: 1), () {
        readerContext.execute(GoToPageCommand(widget.startPage!));
      });
    }
  }

  @override
  Widget createPublicationNavigator({
    required WidgetBuilder waitingScreenBuilder,
    required WidgetErrorBuilder displayErrorBuilder,
    required Consumer<ReaderContext> onReaderContextCreated,
    required WrapperWidgetBuilder wrapper,
    required EpubController publicationController,
  }) =>
      EpubNavigator(
          waitingScreenBuilder: waitingScreenBuilder,
          displayErrorBuilder: displayErrorBuilder,
          onReaderContextCreated: onReaderContextCreated,
          wrapper: wrapper,
          epubController: publicationController);

  @override
  Widget build(BuildContext context) => MultiBlocProvider(
        providers: [
          BlocProvider(create: (context) => _viewerSettingsBloc),
          BlocProvider(create: (context) => _readerThemeBloc),
        ],
        child: super.build(context),
      );

  @override
  Widget buildBackground() => BlocBuilder(
        bloc: _readerThemeBloc,
        builder: (BuildContext context, ReaderThemeState state) => Container(
          color: state.readerTheme.backgroundColor,
        ),
      );

  @override
  Function0<List<RequestHandler>> get handlersProvider => () => [
        AssetsRequestHandler(
          'packages/mno_navigator/assets',
          assetProvider: _AssetProvider(),
        ),
        FetcherRequestHandler(
            readerContext.publication!, () => readerContext.viewportWidth,
            googleFonts: Fonts.googleFonts)
      ];
}

class _AssetProvider implements AssetProvider {
  @override
  Future<ByteData> load(String path) => rootBundle.load(path);
}
