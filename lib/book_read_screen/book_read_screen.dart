import 'dart:async';

import 'package:cronicalia_flutter/custom_widgets/backdrop_widget.dart';
import 'package:cronicalia_flutter/models/book_stop_info.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:cronicalia_flutter/custom_widgets/rounded_button_widget.dart';
import 'package:cronicalia_flutter/flux/book_read_store.dart';
import 'package:cronicalia_flutter/main.dart';
import 'package:cronicalia_flutter/models/book.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter_flux/flutter_flux.dart';
import 'package:cronicalia_flutter/utils/constants.dart';
import 'package:flutter_full_pdf_viewer/flutter_full_pdf_viewer.dart' as pdfViewer;
import 'package:flutter_html/flutter_html.dart' as epubViewer;

// Displays PDF books
class BookPdfReadScreen extends StatefulWidget {
  BookPdfReadScreen(this._book);

  final BookPdf _book;

  @override
  _BookPdfReadScreenState createState() => _BookPdfReadScreenState();
}

class _BookPdfReadScreenState extends State<BookPdfReadScreen> with StoreWatcherMixin {
  PdfReadStore _pdfReadStore;

  @override
  void initState() {
    super.initState();

    _pdfReadStore = listenToStore(pdfReadStoreToken);

    Completer bookReadyCompleter = Completer();
    // TODO check if completer is necessary
    downloadPdfFileAction([widget._book, bookReadyCompleter]);
  }

  @override
  void dispose() {
    disposePdfBookAction();
    SystemChrome.setEnabledSystemUIOverlays(SystemUiOverlay.values);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _pdfReadStore.showingFilePath == null
        ? Scaffold(
            body: Padding(
              padding: const EdgeInsets.only(
                top: 24.0,
                left: 8.0,
                bottom: 8.0,
                right: 8.0,
              ),
              child: Center(
                child: SingleChildScrollView(
                  child: Container(
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Text(
                        "No book detected",
                      ),
                    ),
                  ),
                ),
              ),
            ),
          )
        : pdfViewer.PDFViewerScaffold(
            appBar: AppBar(
              title: Text(widget._book.isSingleLaunch ? widget._book.title : widget._book.chapterTitles[0]),
            ),
            path: _pdfReadStore.showingFilePath,
          );
  }
}

// Displays Epub books
class BookEpubReadScreen extends StatefulWidget {
  BookEpubReadScreen(this._book);

  final BookEpub _book;

  @override
  _BookEpubReadScreenState createState() => _BookEpubReadScreenState();
}

class _BookEpubReadScreenState extends State<BookEpubReadScreen>
    with StoreWatcherMixin<BookEpubReadScreen>, SingleTickerProviderStateMixin {
  Future<SharedPreferences> _prefs = SharedPreferences.getInstance();
  EpubReadStore _bookReadStore;
  double _textSize;
  BookStopInfo _bookStopInfo;
  bool _isFullScreen = false;

  AnimationController _backdropAnimationController;

  Completer _bookReadyCompleter;

  @override
  void initState() {
    super.initState();

    _bookReadStore = listenToStore(epubReadStoreToken);
    _bookStopInfo = BookStopInfo(widget._book.uID, _bookReadStore.currentChapterIndex, 0.0);

    _backdropAnimationController = new AnimationController(
      vsync: this,
      duration: new Duration(milliseconds: 500),
    );

    _bookReadyCompleter = Completer();
    downloadEpubFileAction([widget._book, _bookReadyCompleter]);

    _bookReadyCompleter.future.then((_) {
      _retrieveSharedPreferences();
    });

    _scrollController.addListener(_scrollListener);
  }

  void _scrollListener() {
    if (_scrollController.offset >= _scrollController.position.maxScrollExtent &&
        !_scrollController.position.outOfRange) {
      print("PAGE REACHED BOTTOM");
      loadNextSubChapterAction();
    }
    if (_scrollController.offset <= _scrollController.position.minScrollExtent &&
        !_scrollController.position.outOfRange) {
      print("PAGE REACHED TOP");
      loadPreviousSubChapterAction();
    }
  }

  @override
  void dispose() {
    _saveBookPosition();
    disposeEpubBookAction();
    _backdropAnimationController.dispose();
    super.dispose();
  }

  void _saveBookPosition() {
    _prefs.then((SharedPreferences prefs) {
      if (_bookStopInfo != null) {
        prefs.setString(BookStopInfo.generateSharedPreferencesKey(widget._book.uID), _bookStopInfo.toJson());
      }
    });
  }

  bool _isBookContentOnDisplay = false;
  ScrollController _scrollController = ScrollController();

  Future<void> _retrieveSharedPreferences() async {
    _textSize = await _prefs.then((SharedPreferences prefs) {
      if (prefs.getKeys().contains(BookStopInfo.generateSharedPreferencesKey(widget._book.uID))) {
        showReturnToLastPositionDialog(prefs);
      }
      return (prefs.getDouble(Constants.SHARED_PREFERENCES_TEXT_SIZE_KEY) ?? 14.0);
    });

    setState(() {});
  }

  void showReturnToLastPositionDialog(SharedPreferences prefs) {
    showDialog(
        context: context,
        builder: (BuildContext buildContext) {
          return SimpleDialog(
            title: Text("Go to last location?"),
            children: <Widget>[
              SimpleDialogOption(
                child: Text("STAY"),
                onPressed: () {
                  Navigator.of(context).pop();
                },
              ),
              SimpleDialogOption(
                child: Text("GO"),
                onPressed: () {
                  Navigator.of(context).pop();
                  _bookStopInfo = BookStopInfo.fromJson(
                    prefs.getString(
                      BookStopInfo.generateSharedPreferencesKey(widget._book.uID),
                    ),
                  );
                  epubNavigateToChapterAction(_bookStopInfo.lastChapterIndex);
                  _isBookContentOnDisplay = true;
                  SchedulerBinding.instance.addPostFrameCallback((_) {
                    _scrollController.animateTo(
                      _bookStopInfo.scrollPosition,
                      duration: const Duration(seconds: 1),
                      curve: Curves.easeInOut,
                    );
                  });
                },
              )
            ],
          );
        });
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () {
        _bookStopInfo.scrollPosition = _scrollController.offset;
        _bookStopInfo.lastChapterIndex = _bookReadStore.currentChapterIndex;
        return Future<bool>.value(true);
      },
      child: _bookReadyCompleter.isCompleted
          ? Scaffold(
              appBar: _isFullScreen
                  ? null
                  : AppBar(
                      title: Text(
                        widget._book.title,
                      ),
                    ),
              body: BackdropWidget(
                controller: _backdropAnimationController,
                backChild: Scrollbar(
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    child: Container(
                      child: AnimatedCrossFade(
                        crossFadeState: _isBookContentOnDisplay ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                        duration: Duration(seconds: 1),
                        firstChild: _buildNavigationMapWidget(),
                        secondChild: _buildBookContentWidget(),
                      ),
                    ),
                  ),
                ),
                frontChild: _buildBackdropPanel(),
              ),
            )
          : Hero(tag: Constants.HERO_TAG_BOOK_COVER, child: Image.network(widget._book.remoteCoverUri)),
    );
  }

  Widget _buildNavigationMapWidget() {
    return Center(
      child: ListView.builder(
          physics: PageScrollPhysics(),
          shrinkWrap: true,
          itemCount: widget._book.chapterTitles.length,
          itemBuilder: (BuildContext context, int index) {
            return Padding(
              padding: const EdgeInsets.only(top: 8.0, right: 64.0, left: 64.0),
              child: RoundedButton(
                color: AppThemeColors.primaryColorLight,
                onPressed: () {
                  epubNavigateToChapterAction(index);
                  _isBookContentOnDisplay = true;
                },
                child: Text(
                  widget._book.chapterTitles[index].toUpperCase(),
                ),
              ),
            );
          }),
    );
  }

  bool _isBackdropPanelVisible() {
    final AnimationStatus status = _backdropAnimationController.status;
    return status == AnimationStatus.completed || status == AnimationStatus.forward;
  }

  Widget _buildBookContentWidget() {
    return Container(
        child: InkWell(
      splashColor: AppThemeColors.primaryColorLight,
      highlightColor: AppThemeColors.primaryColorLight,
      onTap: () {
        _isBackdropPanelVisible() ? _backdropAnimationController.reverse() : _backdropAnimationController.forward();
      },
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: MediaQuery.of(context).size.height),
          child: epubViewer.Html(
            data: _bookReadStore.loadedData.join(" "),
            backgroundColor: Colors.transparent,
            defaultTextStyle: TextStyle(color: Colors.white, fontSize: _textSize),
          ),
        ),
      ),
    ));
  }

  Widget _buildBackdropPanel() {
    return Container(
      decoration: BoxDecoration(color: AppThemeColors.cardColor, borderRadius: BorderRadius.circular(8.0)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildNavigationButtons(),
          _buildDivider(),
          _buildTextSizeWidget(),
          _buildDivider(),
          _buildFullScreenButton(),
          Divider(
            height: 4.0,
          )
        ],
      ),
    );
  }

  Widget _buildDivider() {
    return Padding(
      padding: const EdgeInsets.only(left: 8.0, right: 8.0),
      child: Divider(
        height: 2.0,
        color: AppThemeColors.primaryColor,
      ),
    );
  }

  Widget _buildNavigationButtons() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            FlatButton.icon(
              onPressed: _bookReadStore.currentChapterIndex > 0
                  ? () {
                      epubBackwardChapterAction(widget._book);
                      _scrollController.animateTo(0.0, duration: Duration(seconds: 2), curve: Curves.decelerate);
                    }
                  : null,
              icon: Icon(Icons.arrow_left),
              label: Text("BACK"),
            ),
            FlatButton.icon(
              onPressed: () {
                setState(() {
                  _isBookContentOnDisplay = false;
                  if (_isBackdropPanelVisible()) _backdropAnimationController.reverse();
                });
              },
              icon: Icon(
                Icons.navigation,
                size: 12.0,
              ),
              label: Text("CONTENTS"),
            ),
            FlatButton.icon(
              onPressed: _bookReadStore.currentChapterIndex < (widget._book.chapterTitles.length - 1)
                  ? () {
                      epubForwardChapterAction(widget._book);
                      _scrollController.animateTo(0.0, duration: Duration(seconds: 2), curve: Curves.decelerate);
                    }
                  : null,
              icon: Icon(Icons.arrow_right),
              label: Text("FORWARD"),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTextSizeWidget() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: <Widget>[
        Expanded(
          flex: 8,
          child: Padding(
            padding: const EdgeInsets.only(left: 16.0),
            child: Text(
              "Text Size    ${_textSize.toInt()}",
              style: TextStyle(fontSize: 16.0),
            ),
          ),
        ),
        Expanded(
          flex: 2,
          child: IconButton(
              icon: Icon(Icons.keyboard_arrow_up),
              onPressed: () {
                if (_textSize < MAX_TEXT_SIZE) {
                  setState(() {
                    _textSize++;
                    _prefs.then((SharedPreferences sharedPreferences) {
                      sharedPreferences.setDouble(Constants.SHARED_PREFERENCES_TEXT_SIZE_KEY, _textSize);
                    });
                  });
                }
              }),
        ),
        Expanded(
          flex: 2,
          child: Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: IconButton(
                icon: Icon(Icons.keyboard_arrow_down),
                onPressed: () {
                  if (_textSize > MIN_TEXT_SIZE) {
                    setState(() {
                      _textSize--;
                      _prefs.then((SharedPreferences sharedPreferences) {
                        sharedPreferences.setDouble(Constants.SHARED_PREFERENCES_TEXT_SIZE_KEY, _textSize);
                      });
                    });
                  }
                }),
          ),
        )
      ],
    );
  }

  Widget _buildFullScreenButton() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 16.0, right: 16.0),
          child: Text(
            "Fullscreen",
            style: TextStyle(fontSize: 16.0),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(right: 8.0),
          child: Switch(
              value: _isFullScreen,
              onChanged: (bool isFullScreen) {
                _isFullScreen = isFullScreen;
                if (isFullScreen) {
                  setState(() {
                    SystemChrome.setEnabledSystemUIOverlays([]);
                  });
                } else {
                  setState(() {
                    SystemChrome.setEnabledSystemUIOverlays(SystemUiOverlay.values);
                  });
                }
              }),
        )
      ],
    );
  }

  Widget _buildSubSectionsButtons() {}
}

const double MAX_TEXT_SIZE = 24.0;
const double MIN_TEXT_SIZE = 12.0;
