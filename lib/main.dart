import 'package:cronicalia_flutter/login_screen/login_screen.dart';
import 'package:cronicalia_flutter/utils/constants.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:cronicalia_flutter/bookmarks_screen/bookmarks_screen.dart';
import 'package:cronicalia_flutter/my_books_screen/my_books_screen.dart';
import 'package:cronicalia_flutter/profile_screen/profile_screen.dart';
import 'package:cronicalia_flutter/search_screen/search_screen.dart';
import 'package:cronicalia_flutter/suggestions_screen/suggestions_screen.dart';

//Firebase
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

class TextColorDarkBackground {
  static final Color primary = Colors.white;
  static final Color secondary = Colors.grey[500];
  static final Color tertiary = Colors.grey[700];
}

class TextColorBrightBackground {
  static final Color primary = Colors.grey[900];
  static final Color secondary = Colors.grey[700];
  static final Color tertiary = Colors.grey[500];
}

class AppThemeColors {
  static final Color primaryColorDark = Colors.black;
  static final Color primaryColor = Colors.grey[900];
  static final Color primaryColorLight = Colors.grey[800];
  static final Color accentColor = Colors.amberAccent;
  static final Color errorColor = Colors.orange[700];
  static final Color backgroundColor = Colors.grey[850];
  static final Color canvasColor = Colors.grey[850];
  static final Color cardColor = Colors.grey[800];
}

void main() {
  runApp(new Cronicalia());
}

class Cronicalia extends StatelessWidget {
  FirebaseStorage firebaseStorage;
  Firestore firestore;
  FirebaseAuth firebaseAuth;

  Cronicalia() {
    _initializeFirebase();
  }



  @override
  Widget build(BuildContext context) {
    return new MaterialApp(
      routes: <String, WidgetBuilder>{
        Constants.ROUTE_LOGIN_SCREEN: (BuildContext context) => new LoginScreen(firebaseAuth),
        Constants.ROUTE_SUGGESTIONS_SCREEN: (BuildContext context) => new SuggestionsScreen(),
        Constants.ROUTE_SEARCH_SCREEN: (BuildContext context) => new SearchScreen(),
        Constants.ROUTE_BOOKMARKS_SCREEN: (BuildContext context) => new BookmarksScreen(),
        Constants.ROUTE_MY_BOOKS_SCREEN: (BuildContext context) => new MyBooksScreen(),
        Constants.ROUTE_PROFILE_SCREEN: (BuildContext context) => new ProfileScreen()
      },
      theme: new ThemeData(
          brightness: Brightness.dark,
          primaryColor: AppThemeColors.primaryColor,
          primaryColorDark: AppThemeColors.primaryColorDark,
          primaryColorLight: AppThemeColors.primaryColorLight,
          accentColor: AppThemeColors.accentColor,
          errorColor: AppThemeColors.errorColor,
          backgroundColor: AppThemeColors.backgroundColor,
          canvasColor: AppThemeColors.canvasColor,
          cardColor: AppThemeColors.cardColor,
          toggleableActiveColor: AppThemeColors.accentColor),
      title: 'Cronicalia',
      home: SuggestionsScreen(),
    );
  }
}