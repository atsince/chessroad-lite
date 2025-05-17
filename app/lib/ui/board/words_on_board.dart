import 'package:flutter/material.dart';

import '../../game/game.dart';
import '../ruler.dart';

class WordsOnBoard extends StatelessWidget {
  //
  final bool boardInversed;
  final bool miniMode;

  const WordsOnBoard(this.boardInversed, {Key? key, this.miniMode = false}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // 如果是mini模式，返回空白Widget
    if (miniMode) {
      return const SizedBox();
    }

    final topSideColumns = boardInversed ? '一二三四五六七八九' : '１２３４５６７８９';
    final bottomSideColumns = boardInversed ? '９８７６５４３２１' : '九八七六五四三二一';

    final topSideChildren = <Widget>[], bottomSideChildren = <Widget>[];

    const digitsStyle = TextStyle(fontSize: Ruler.kBoardDigitsTextFontSize);
    const riverTipsStyle = TextStyle(fontSize: 28);

    for (var i = 0; i < 9; i++) {
      //
      topSideChildren.add(Text(topSideColumns[i], style: digitsStyle));
      bottomSideChildren.add(Text(bottomSideColumns[i], style: digitsStyle));

      if (i < 8) {
        topSideChildren.add(const Expanded(child: SizedBox()));
        bottomSideChildren.add(const Expanded(child: SizedBox()));
      }
    }

    final riverTips = Row(
      children: const <Widget>[
        Expanded(child: SizedBox()),
        Text('楚河', style: riverTipsStyle),
        Expanded(flex: 2, child: SizedBox()),
        Text('汉界', style: riverTipsStyle),
        Expanded(child: SizedBox()),
      ],
    );

    return DefaultTextStyle(
      style: GameFonts.art(color: GameColors.boardTips),
      child: Column(
        children: <Widget>[
          Row(children: topSideChildren),
          const Expanded(child: SizedBox()),
          riverTips,
          const Expanded(child: SizedBox()),
          Row(children: bottomSideChildren),
        ],
      ),
    );
  }
}

// 没有文字和标注的迷你棋盘Widget
class MiniWordsOnBoard extends WordsOnBoard {
  const MiniWordsOnBoard(bool boardInversed, {Key? key})
      : super(boardInversed, key: key, miniMode: true);
}
