import 'package:chessroad/ui/board/thinking_board_layout.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../game/board_state.dart';
import '../../game/game.dart';
import '../ruler.dart';
import 'board_widget.dart';
import 'board_painter.dart';
import 'pieces_layout.dart';
import 'words_on_board.dart';

class ThinkingBoardWidget extends BoardWidget {
  //
  const ThinkingBoardWidget(
      double width, Function(BuildContext, int)? onBoardTap,
      {Key? key, required bool opponentHuman})
      : super(width, onBoardTap, opponentHuman: opponentHuman, key: key);

  @override
  Widget buildPiecesLayer(BoardState board, {bool opponentHuman = false}) {
    //
    return ThinkingBoardLayout(
      board,
      PiecesLayout(
        width,
        board.position,
        focusIndex: board.focusIndex,
        blurIndex: board.blurIndex,
        pieceAnimationValue: board.pieceAnimationValue,
        boardInversed: board.boardInversed,
      ),
    );
  }
}
// 这是迷你版的ThinkingBoardWidget，不显示坐标和楚河汉界
class MiniThinkingBoardWidget extends ThinkingBoardWidget {
  const MiniThinkingBoardWidget(
      double width, Function(BuildContext, int)? onBoardTap,
      {Key? key, required bool opponentHuman})
      : super(width, onBoardTap, opponentHuman: opponentHuman, key: key);

  @override
  double get height {
    // 减少高度，因为不需要显示坐标系
    return (width - Ruler.kBoardPadding * 2) / 9 * 10 + (Ruler.kBoardPadding) * 2;
  }

  @override
  Widget build(BuildContext context) {

    print('height: $height');
    final boardContainer = Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(5),
        color: GameColors.boardBackground,
      ),
      child: RepaintBoundary(
        child: Consumer<BoardState>(
          builder: (context, board, child) {
            return Stack(
              children: <Widget>[
                RepaintBoundary(
                  child: CustomPaint(
                    painter: BoardPainter(width),
                    child: Container(
                      // margin: EdgeInsets.symmetric(
                      //   vertical: Ruler.kBoardPadding,
                      //   horizontal: (width - Ruler.kBoardPadding * 2) / 9 / 2 +
                      //       Ruler.kBoardPadding -
                      //       Ruler.kBoardDigitsTextFontSize / 2,
                      // ),
                      // 使用MiniWordsOnBoard，不显示文字
                      child: MiniWordsOnBoard(board.boardInversed),
                    ),
                  ),
                ),
                RepaintBoundary(
                  child: buildPiecesLayer(board, opponentHuman: opponentHuman),
                ),
              ],
            );
          },
        ),
      ),
    );

    if (onBoardTap == null) {
      return boardContainer;
    }

    return GestureDetector(
      child: boardContainer,
      onTapUp: (d) {
        //
        final gridWidth = (width - Ruler.kBoardPadding * 2) * 8 / 9;
        final squareWidth = gridWidth / 8;

        final dx = d.localPosition.dx, dy = d.localPosition.dy;
        // 点击位置计算方式调整，去掉坐标系所占用的空间
        final rank = (dy - Ruler.kBoardPadding) ~/ squareWidth;
        final file = (dx - Ruler.kBoardPadding) ~/ squareWidth;

        if (rank < 0 || rank > 9) return;
        if (file < 0 || file > 8) return;

        if (onBoardTap != null) {
          onBoardTap!(context, rank * 9 + file);
        }
      },
    );
  }
}

