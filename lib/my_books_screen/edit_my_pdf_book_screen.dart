import 'dart:async';
import 'dart:math';

import 'package:cronicalia_flutter/custom_widgets/book_pdf_file_widget.dart';
import 'package:cronicalia_flutter/custom_widgets/book_stats_widget.dart';
import 'package:cronicalia_flutter/custom_widgets/rounded_button_widget.dart';
import 'package:cronicalia_flutter/flux/user_store.dart';
import 'package:cronicalia_flutter/main.dart';
import 'package:cronicalia_flutter/models/book.dart';
import 'package:cronicalia_flutter/my_books_screen/my_book_image_picker.dart';
import 'package:cronicalia_flutter/utils/constants.dart';
import 'package:cronicalia_flutter/utils/custom_flushbar_helper.dart';
import 'package:flushbar/flushbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_document_picker/flutter_document_picker.dart';
import 'package:flutter_flux/flutter_flux.dart';

enum ImageType { COVER }
enum ImageOrigin { CAMERA, GALLERY }

class EditMyPdfBookScreen extends StatefulWidget {
  final String bookUID;

  EditMyPdfBookScreen(this.bookUID);

  @override
  State createState() {
    return new EditMyBookPdfScreenState();
  }
}

class EditMyBookPdfScreenState extends State<EditMyPdfBookScreen>
    with TickerProviderStateMixin, StoreWatcherMixin<EditMyPdfBookScreen>
    implements BookFileWidgetCallback {
  UserStore _userStore;
  bool _isEditModeOn = false;
  BookPdf _immutableBook;

  AnimationController _wiggleController;
  Animation<double> _wiggleAnimation;
  TextEditingController _textController;
  ScrollController _scrollController;

  @override
  void initState() {
    _textController = new TextEditingController();
    _scrollController = new ScrollController();
    _uploadProgressController = AnimationController(vsync: this, value: 0.0);
    _userStore = listenToStore(userStoreToken);

    _immutableBook = _userStore.user.booksPdf[widget.bookUID];

    _initializeFilesWidgets();

    _wiggleController = new AnimationController(vsync: this, duration: Duration(milliseconds: 250));
    _wiggleAnimation = new Tween(begin: -pi / 60, end: pi / 60).animate(_wiggleController)
      ..addListener(() {
        setState(() {});
      });

    _wiggleController.addStatusListener((animationStatus) {
      switch (animationStatus) {
        case AnimationStatus.completed:
          {
            if (_isEditModeOn) {
              _wiggleController.reverse();
            } else {
              _wiggleController.reset();
            }
            break;
          }
        case AnimationStatus.dismissed:
          {
            if (_isEditModeOn) {
              _wiggleController.forward();
            } else {
              _wiggleController.reset();
            }
            break;
          }
        default:
          break;
      }
    });
    super.initState();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _textController.dispose();
    _wiggleController.dispose();

    _filesWidgets?.forEach((BookPdfFileWidget fileWidget) {
      fileWidget.cleanUp();
    });

    super.dispose();
  }

  void _initializeFilesWidgets() {
    if (_immutableBook.isSingleLaunch) {
      _replaceFileWidget(filePath: _immutableBook.remoteFullBookUri, fileTitle: _immutableBook.title);
    } else {
      _addFileWidgets(
          filePaths: _immutableBook.chapterUris.map((chapterUri) {
            return chapterUri.toString();
          }).toList(),
          fileTitles: _immutableBook.chapterTitles.map((chapterTitle) {
            return chapterTitle.toString();
          }).toList());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Edit ${_immutableBook.title}")),
      persistentFooterButtons: _immutableBook.isCurrentlyComplete ? null : _buildPersistentButtons(context),
      body: Center(
        child: SingleChildScrollView(
          controller: _scrollController,
          padding: new EdgeInsets.only(top: 84.0),
          child: new Column(
            children: <Widget>[
              new Stack(
                children: [
                  _buildBookInfoCard(),
                  _buildCoverPicture(),
                ],
              ),
              _buildPeriodicityDropdownButton(),
              _buildFilesListWidget(),
              _buildNextReleaseChapterWidget(),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildPersistentButtons(BuildContext context) {
    Widget resolveFilePickButton() {
      if (_immutableBook.isCurrentlyComplete) {
        return Container(width: 0.0, height: 0.0);
      } else if (_immutableBook.isSingleLaunch) {
        return FlatButton(
          textColor: TextColorDarkBackground.secondary,
          child: Text("UPDATE FILE"),
          onPressed: () {
            _getPdfPaths().then((paths) {
              if (paths != null && paths.isNotEmpty) {
                setState(
                  () {
                    _replaceFileWidget(filePath: paths[0]);
                  },
                );
                _scrollController.animateTo(MediaQuery.of(context).size.height,
                    duration: Duration(seconds: 2), curve: Curves.decelerate);
              }
            });
          },
        );
      } else {
        return FlatButton(
          textColor: TextColorDarkBackground.secondary,
          child: Text("ADD FILE"),
          onPressed: () {
            _getPdfPaths().then((paths) {
              if (paths != null && paths.isNotEmpty) {
                setState(
                  () {
                    _addFileWidgets(filePaths: paths);
                  },
                );
                _scrollController.animateTo(MediaQuery.of(context).size.height,
                    duration: Duration(seconds: 2), curve: Curves.decelerate);
              }
            });
          },
        );
      }
    }

    return <Widget>[
      resolveFilePickButton(),
      FlatButton(
        child: Text("SAVE FILES"),
        onPressed: _immutableBook.areFilesTheSame(_filesWidgets)
            ? null
            : () {
                final BookPdf fileChangesBook = _userStore.user.booksPdf[widget.bookUID].copy();

                if (_validateInformation()) {
                  if (fileChangesBook.isSingleLaunch) {
                    updateSingleFileBookFile(fileChangesBook);
                  } else {
                    updateMultiFileBookFiles(fileChangesBook);
                  }
                  _showProgressFlushbar();
                  print("Updatin book files");
                }
              },
      ),
    ];
  }

  bool _validateInformation() {
    return (_validateMinimumFileSize() && _validateNewChapterTitles());
  }

  bool _validateMinimumFileSize() {
    if (_filesWidgets.length < 1) {
      FlushbarHelper.createError(message: "You need at least one file").show(context);
      return false;
    }

    return true;
  }

  bool _validateNewChapterTitles() {
    if (_immutableBook.isSingleLaunch) return true;

    Set<String> fileNamesSet = Set<String>();
    _filesWidgets.forEach((BookPdfFileWidget fileWidget) {
      fileNamesSet.add(fileWidget.formattedFilePath);
    });

    //check if there are equal files
    if (_filesWidgets.length != fileNamesSet.length) {
      FlushbarHelper.createError(message: "Equal files detected. Remove one of the copies").show(context);
      return false;
    }

    //check if there is a missing title
    for (var counter = 0; counter < _filesWidgets.length; counter++) {
      String title = _filesWidgets[counter].fileTitle;
      if (title == null || title.isEmpty) {
        FlushbarHelper.createError(message: "Your chapter title number ${counter + 1} is missing").show(context);
        return false;
      }
    }

    return true;
  }

  void updateSingleFileBookFile(BookPdf book) {
    String filePath = _filesWidgets[0].filePath;
    if (book.localFullBookUri != filePath) {
      book.localFullBookUri = _filesWidgets[0].filePath;
      updateBookFilesAction(book);
    }
  }

  void updateMultiFileBookFiles(BookPdf book) {
    book.chapterUris.clear();
    book.chapterTitles.clear();
    book.chaptersLaunchDates.clear();

    _filesWidgets.forEach((BookPdfFileWidget fileWidget) {
      //fileWidget.filePath & fileTitle are never null
      book.chapterUris.add(fileWidget.filePath);
      book.chapterTitles.add(fileWidget.fileTitle);
      fileWidget.date == null
          ? book.chaptersLaunchDates.add(DateTime.now().millisecondsSinceEpoch)
          : book.chaptersLaunchDates.add(fileWidget.date);
    });

    updateBookFilesAction(book);
  }

  //do not dispose. Flushbar already randles it
  AnimationController _uploadProgressController;

  void _showProgressFlushbar() {
    UserStore userStore = listenToStore(userStoreToken);

    Flushbar progressFlushbar = FlushbarHelper.createLoading(
      message: "Wait while we update your book files",
      indicatorBackgroundColor: Colors.blue[300],
      indicatorController: _uploadProgressController,
      duration: null,
    )
      ..onStatusChanged = (FlushbarStatus status) {
        switch (status) {
          case FlushbarStatus.DISMISSED:
            {
              Navigator.of(context).pop();
              break;
            }
          default:
            {}
        }
      }
      ..show(context);

    if (userStore.getProgressStream() != null) {
      userStore.getProgressStream().controller.stream.listen((progress) {
        _uploadProgressController.animateTo(progress, duration: Duration(milliseconds: 300));
      }, onDone: () {
        progressFlushbar.dismiss();
      }, onError: (error) {
        FlushbarHelper.createError(title: "Update failed", message: "One or more files failed. Try again");
      }, cancelOnError: true);
    }
  }

  Future<List<String>> _getPdfPaths() async {
    FlutterDocumentPickerParams params = FlutterDocumentPickerParams(
        allowedFileExtensions: ["pdf"],
        // allowedMimeType only works on Android. Check for IOS latter
        allowedMimeType: Constants.CONTENT_TYPE_PDF);

    List<String> documentPaths = [await FlutterDocumentPicker.openDocument(params: params)];

    return documentPaths;
  }

  Widget _buildBookInfoCard() {
    return Card(
      child: new FractionallySizedBox(
        widthFactor: 0.90,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            _buildEditButton(
                buttonTitle: "CHANGE COVER",
                onClick: () {
                  _showImageOriginDialog(ImageType.COVER);
                },
                padding: EdgeInsets.only(top: 8.0, left: 8.0, right: 16.0)),
            _buildEditButton(
              buttonTitle: "CHANGE TEXTS",
              onClick: () {
                _isEditModeOn = !_isEditModeOn;
                if (_isEditModeOn) {
                  _wiggleController.forward();
                }
              },
            ),
            new Padding(
              padding: const EdgeInsets.only(top: 16.0, left: 16.0, right: 16.0),
              child: new GestureDetector(
                onTap: () {
                  if (_isEditModeOn) {
                    _showTitleTextInputDialog();
                    _isEditModeOn = false;
                  }
                },
                child: new Transform.rotate(
                  angle: (_isEditModeOn == true) ? _wiggleAnimation.value : 0.0,
                  child: new Text(
                    _immutableBook.title,
                    style: TextStyle(fontSize: 24.0),
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
              ),
            ),
            new Padding(
              padding: const EdgeInsets.only(top: 8.0, left: 16.0, right: 16.0, bottom: 8.0),
              child: new GestureDetector(
                onTap: () {
                  if (_isEditModeOn) {
                    _showSynopsisTextInputDialog();
                    _isEditModeOn = false;
                  }
                },
                child: new Transform.rotate(
                  angle: (_isEditModeOn == true) ? _wiggleAnimation.value : 0.0,
                  child: new Text(
                    _immutableBook.synopsis,
                    style: TextStyle(color: TextColorDarkBackground.secondary),
                    textAlign: TextAlign.justify,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 8,
                  ),
                ),
              ),
            ),
            _buildBookStatsWidget(context),
            _buildCompletionStatusButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildEditButton(
      {@required String buttonTitle,
      @required Function onClick,
      EdgeInsets padding = const EdgeInsets.only(left: 8.0, right: 16.0)}) {
    return new Align(
      alignment: Alignment.centerRight,
      child: new Padding(
        padding: padding,
        child: ButtonTheme(
          minWidth: 130.0,
          child: RoundedButton(
            child: Text(
              buttonTitle,
              style: TextStyle(fontSize: 12.0, color: TextColorBrightBackground.secondary),
            ),
            onPressed: onClick,
            highlightColor: Colors.grey[200],
            color: Colors.grey[350],
          ),
        ),
      ),
    );
  }

  Widget _buildCompletionStatusButton() {
    return AnimatedSize(
      vsync: this,
      curve: Curves.bounceOut,
      alignment: Alignment.centerLeft,
      duration: Duration(milliseconds: 500),
      child: Padding(
        padding: const EdgeInsets.only(top: 8.0, bottom: 16.0),
        child: new RaisedButton.icon(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16.0),
          ),
          elevation: 0.0,
          highlightColor: Colors.grey[200],
          color: Colors.grey[350],
          icon: _immutableBook.isCurrentlyComplete
              ? Icon(
                  Icons.done,
                  color: TextColorBrightBackground.primary,
                )
              : Icon(
                  Icons.build,
                  color: TextColorBrightBackground.primary,
                ),
          label: _immutableBook.isCurrentlyComplete
              ? Text(
                  "Book marked as complete",
                  style: TextStyle(color: TextColorBrightBackground.primary),
                )
              : Text(
                  "Book under development",
                  style: TextStyle(color: TextColorBrightBackground.primary),
                ),
          onPressed: () {
            updateBookCompletionStatusAction([_immutableBook.uID, !_immutableBook.isCurrentlyComplete, context]);
          },
        ),
      ),
    );
  }

  Widget _buildCoverPicture() {
    return FractionalTranslation(
      translation: Offset(0.15, -0.42),
      child: Container(
        constraints: BoxConstraints.tight(Size(Constants.BOOK_COVER_DEFAULT_WIDTH, Constants.BOOK_COVER_DEFAULT_HEIGHT)),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6.0),
          child: Image(
            image: MyBookImagePicker.getCoverImageProvider(_immutableBook.localCoverUri, _immutableBook.remoteCoverUri),
            fit: BoxFit.fill,
          ),
        ),
        decoration: BoxDecoration(
          boxShadow: [BoxShadow(color: Colors.black26, offset: Offset(2.0, 2.0), blurRadius: 6.0, spreadRadius: 1.0)],
          borderRadius: BorderRadius.circular(6.0),
          shape: BoxShape.rectangle,
        ),
      ),
    );
  }

  Widget _buildPeriodicityDropdownButton() {
    return AnimatedCrossFade(
      duration: Duration(milliseconds: 800),
      crossFadeState: (_immutableBook.isSingleLaunch || _immutableBook.isCurrentlyComplete)
          ? CrossFadeState.showFirst
          : CrossFadeState.showSecond,
      firstChild: Container(
        height: 0.0,
        width: 0.0,
      ),
      secondChild: Material(
        color: Colors.transparent,
        child: AnimatedOpacity(
          duration: Duration(microseconds: 800),
          opacity: _immutableBook.isCurrentlyComplete ? 0.0 : 1.0,
          curve: Curves.easeIn,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  "Change chapter launch periodicity",
                  style: TextStyle(color: TextColorDarkBackground.secondary),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 8.0, top: 8.0),
                  child: DropdownButton<ChapterPeriodicity>(
                    style: TextStyle(color: TextColorDarkBackground.secondary),
                    value: _immutableBook.periodicity == ChapterPeriodicity.NONE ? null : _immutableBook.periodicity,
                    items: ChapterPeriodicity.values
                        .map((ChapterPeriodicity periodicity) {
                          if (periodicity != ChapterPeriodicity.NONE) return _buildPeriodicityDropdownItem(periodicity);
                        })
                        .toList()
                        .sublist(1),
                    hint: Text("Change chapter launch periodicity"),
                    onChanged: (newPeriodicity) {
                      updateBookChapterPeriodicityAction([_immutableBook.uID, newPeriodicity, context]);
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  DropdownMenuItem<ChapterPeriodicity> _buildPeriodicityDropdownItem(ChapterPeriodicity chapterPeriodicity) {
    String periodicityTitle = Book.convertPeriodicityToString(chapterPeriodicity);

    return DropdownMenuItem<ChapterPeriodicity>(
      child: SizedBox(
        child: Text(periodicityTitle),
        width: MediaQuery.of(context).size.width - 64.0,
      ),
      value: chapterPeriodicity,
    );
  }

  final List<BookPdfFileWidget> _filesWidgets = List<BookPdfFileWidget>();

  Widget _buildFilesListWidget() {
    return _immutableBook.isCurrentlyComplete || _filesWidgets.length < 1
        ? Container(
            height: 0.0,
            width: 0.0,
          )
        : SizedBox(
            height: _filesWidgets.length <= 1 ? (_filesWidgets.length + 0.5) * FILE_WIDGET_HEIGHT : (3 * FILE_WIDGET_HEIGHT),
            child: _immutableBook.isSingleLaunch
                ? Column(mainAxisSize: MainAxisSize.min, children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 16.0, right: 16.0, left: 16.0),
                      child: Text(
                        "Book File",
                        style: TextStyle(color: TextColorDarkBackground.primary, fontSize: 24.0),
                      ),
                    ),
                    _filesWidgets[0],
                  ])
                : Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: ReorderableListView(                   
                      children: _filesWidgets,
                      onReorder: (int oldIndex, int newIndex) {
                        setState(() {
                          Widget toBeMovedFileWidget = _filesWidgets.removeAt(oldIndex);

                          if (oldIndex < newIndex) {
                            newIndex -= 1;
                          }
                          _filesWidgets.insert(newIndex, toBeMovedFileWidget);
                        });
                      },
                      header: Padding(
                        padding: const EdgeInsets.only(left: 16.0, right: 16.0),
                        child: Text(
                          "Book Files",
                          style: TextStyle(color: TextColorDarkBackground.primary, fontSize: 24.0),
                        ),
                      ),
                    ),
                ),
          );
  }

  //Use when _book.isSingleLaunch == false
  void _addFileWidgets({List<String> filePaths, List<String> fileTitles}) {
    filePaths?.asMap()?.forEach((int index, String filePath) {
      String fileTitle;
      if (fileTitles != null && index < fileTitles.length) {
        fileTitle = fileTitles[index];
      }

      //if file is not present, chapterPosition is -1
      int chapterPosition = _immutableBook.chapterUris.indexWhere((chapterUri) {
        return chapterUri == filePath;
      });

      int date = chapterPosition != -1 ? _immutableBook.chaptersLaunchDates[chapterPosition] : null;
      int position = _filesWidgets.length;

      _filesWidgets.add(
        BookPdfFileWidget(
            key: Key(filePath),
            isReorderable: true,
            allowUserInput: true,
            isSingleLaunch: _immutableBook.isSingleLaunch,
            filePath: filePath,
            date: date,
            fileTitle: fileTitle,
            position: position,
            bookFileWidgetCallback: this,
            widgetHeight: FILE_WIDGET_HEIGHT),
      );
    });
  }

  Color getChapterReleaseStatusColor() {
    int timeRemaining = _immutableBook.getDaysRemainingForNewChapterPublication();

    // No color is shown
    if (timeRemaining == null) return null;

    if (timeRemaining <= 0) {
      return Colors.yellow[900];
    } else if (timeRemaining <= 3) {
      return Colors.yellowAccent;
    } else {
      return Colors.green;
    }
  }

  //Use when _book.isSingleLaunch == true
  void _replaceFileWidget({String filePath, String fileTitle}) {
    assert(filePath != null, "filePath must not be null");

    if (_filesWidgets.isNotEmpty) _filesWidgets.clear();

    _filesWidgets.add(
      BookPdfFileWidget(
        key: Key(filePath),
        isReorderable: false,
        allowUserInput: false,
        isSingleLaunch: _immutableBook.isSingleLaunch,
        filePath: filePath,
        fileTitle: fileTitle,
        position: 0,
        widgetHeight: FILE_WIDGET_HEIGHT,
      ),
    );
  }

  Future<Null> _showImageOriginDialog(ImageType imageType) async {
    switch (await showDialog<ImageOrigin>(
        context: context,
        builder: (BuildContext context) {
          return new SimpleDialog(
            title: const Text('Select image from?'),
            children: <Widget>[
              new SimpleDialogOption(
                onPressed: () {
                  Navigator.pop(context, ImageOrigin.CAMERA);
                },
                child: const Text('CAMERA'),
              ),
              new SimpleDialogOption(
                onPressed: () {
                  Navigator.pop(context, ImageOrigin.GALLERY);
                },
                child: const Text('GALLERY'),
              ),
            ],
          );
        })) {
      case ImageOrigin.CAMERA:
        imageCache.clear();
        MyBookImagePicker.pickImageFromCamera(imageType, _userStore.user, widget.bookUID, context);
        break;
      case ImageOrigin.GALLERY:
        imageCache.clear();
        MyBookImagePicker.pickImageFromGallery(imageType, _userStore.user, widget.bookUID, context);
        break;
    }
  }

  Widget _buildNextReleaseChapterWidget() {
        // this is a sign that a new chapter has been picked
    if(_immutableBook.chaptersLaunchDates.length < _filesWidgets.length){
      return Container(
        height: 0.0,
        width: 0.0,
      );
    }

    int daysUntilNextChapterRelease = _immutableBook.getDaysRemainingForNewChapterPublication();

    if (daysUntilNextChapterRelease == null)
      return Container(
        height: 0.0,
        width: 0.0,
      );

    Color backgroundColor;
    String statusText;

    if (daysUntilNextChapterRelease < 0) {
      backgroundColor = Colors.yellow[900];
      statusText = "CHAPTER RELEASE IS ${daysUntilNextChapterRelease.abs()} DAY(S) LATE";
    } else if(daysUntilNextChapterRelease == 0){
      backgroundColor = Colors.yellow[600];
      statusText = "CHAPTER RELEASE IS TODAY. ADD FILE";
    }
    else if (daysUntilNextChapterRelease <= 3) {
      backgroundColor = Colors.yellow[600];
      statusText = "RELEASE DATE IS ALMOST HERE. $daysUntilNextChapterRelease DAYS(S) LEFT";
    } else {
      backgroundColor = Colors.green;
      statusText = "NEXT RELEASE IN $daysUntilNextChapterRelease DAYS(S)";
    }

    return Padding(
      padding: const EdgeInsets.only(left: 8.0, right: 8.0, top: 16.0, bottom: 8.0),
      child: RaisedButton(
        onPressed: (){
          _getPdfPaths().then((paths) {
              if (paths != null && paths.isNotEmpty) {
                setState(
                  () {
                    _addFileWidgets(filePaths: paths);
                  },
                );
                _scrollController.animateTo(MediaQuery.of(context).size.height,
                    duration: Duration(seconds: 2), curve: Curves.decelerate);
              }
            });
        },
        color: backgroundColor,
        child: ConstrainedBox(
          constraints: BoxConstraints.tightFor(width: MediaQuery.of(context).size.width),
          child: Text(
            statusText,
            style: TextStyle(color: TextColorBrightBackground.primary),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }

  Widget _buildBookStatsWidget(BuildContext context) {
    return new Padding(
        padding: const EdgeInsets.only(top: 8.0, left: 16.0, right: 16.0, bottom: 8.0),
        child: new BookStatsWidget(
          readingsNumber: _immutableBook.readingsNumber,
          rating: _immutableBook.rating,
          income: _immutableBook.income,
        ));
  }

  Future<Null> _showTitleTextInputDialog() async {
    _textController.text = _immutableBook.title;

    const Text title = Text(
      "Edit book title",
      style: const TextStyle(fontSize: 20.0),
    );
    TextFormField textFormField = TextFormField(
      controller: _textController,
      maxLength: 40,
      maxLengthEnforced: true,
      keyboardType: TextInputType.text,
      decoration: InputDecoration(labelText: "Book title", helperText: "3 characters minimum"),
      onFieldSubmitted: (value) {
        if (value.length >= 3) {
          Navigator.pop(context, value);
        }
      },
    );

    String userInput = (await showDialog<String>(
        context: context,
        builder: (BuildContext context) {
          return new Dialog(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                new Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: title,
                ),
                new Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: textFormField,
                ),
                new Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: new Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: <Widget>[
                      new FlatButton(
                        onPressed: () {
                          Navigator.pop(context);
                        },
                        child: Text("CANCEL"),
                        textColor: AppThemeColors.accentColor,
                      ),
                      new FlatButton(
                        onPressed: () {
                          if (_textController.text.length >= 3) {
                            Navigator.pop(context, _textController.text);
                          }
                        },
                        child: Text("SUBMIT"),
                        textColor: AppThemeColors.accentColor,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }));

    if (userInput != null && userInput.length >= 3) {
      updateBookTitleAction([_immutableBook.uID, userInput, context]);
    }
  }

  Future<Null> _showSynopsisTextInputDialog() async {
    _textController.text = _immutableBook.synopsis;

    const Text title = Text(
      "Edit book synopsis",
      style: const TextStyle(fontSize: 20.0),
    );
    TextFormField textFormField = TextFormField(
      controller: _textController,
      maxLines: 8,
      maxLength: 3000,
      maxLengthEnforced: true,
      keyboardType: TextInputType.text,
      decoration: InputDecoration(labelText: "Book synopsis"),
      onFieldSubmitted: (value) {
        if (value.length <= 3000) {
          Navigator.pop(context, value);
        }
      },
    );

    String userInput = (await showDialog<String>(
        context: context,
        builder: (BuildContext context) {
          return new SingleChildScrollView(
            child: new Dialog(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  new Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: title,
                  ),
                  new Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: textFormField,
                  ),
                  new Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: new Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: <Widget>[
                        new FlatButton(
                          onPressed: () {
                            Navigator.pop(context);
                          },
                          child: Text("CANCEL"),
                          textColor: AppThemeColors.accentColor,
                        ),
                        new FlatButton(
                          onPressed: () {
                            if (_textController.text.length <= 3000) {
                              Navigator.pop(context, _textController.text);
                            }
                          },
                          child: Text("SUBMIT"),
                          textColor: AppThemeColors.accentColor,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }));

    if (userInput != null) {
      updateBookSynopsisAction([_immutableBook.uID, userInput, context]);
    }
  }

  @override
  void onRemoveFileClick({int position}) {
    setState(() {
      _filesWidgets.removeAt(position);
      _updateFileWidgetsPositions();
    });
  }

  void _updateFileWidgetsPositions() {
    _filesWidgets.asMap().forEach((int position, BookPdfFileWidget fileWidget) {
      fileWidget.position = position;
    });
  }
}

const double FILE_WIDGET_HEIGHT = 118.0;
