import 'package:chessroad/cchess/cc_base.dart';
import 'package:chessroad/config/local_data.dart';
import 'package:chessroad/engine/pikafish_engine.dart';
import 'package:chessroad/game/board_state.dart';
import 'package:chessroad/ui/thinking_board_painter.dart';
import 'package:flutter/material.dart';

import 'pieces_layout.dart';

class ThinkingBoardLayout extends StatefulWidget {
  //
  final BoardState boardState;

  final PiecesLayout layoutParams;

  const ThinkingBoardLayout(this.boardState, this.layoutParams, {Key? key}) : super(key: key);

  @override
  State createState() => _PiecesLayoutState();
}

class _PiecesLayoutState extends State<ThinkingBoardLayout> {
  //
  @override
  Widget build(BuildContext context) {
    //
    final moves = <Move>[];

    // 处理bestmove和ponder
    if (widget.boardState.bestmove != null) {
      // 如果有最佳着法，添加
      if (widget.boardState.bestmove!.bestmove != null) {
        try {
          moves.add(Move.fromEngineMove(widget.boardState.bestmove!.bestmove!));

          // 如果有后续走法(ponder)，也添加
          if (widget.boardState.bestmove!.ponder != null) {
            moves.add(Move.fromEngineMove(widget.boardState.bestmove!.ponder!));
          }
        } catch (e) {
          print('解析bestmove和ponder时出错: $e');
        }
      }
    }
    // 处理engineInfo中的pvs
    else if (widget.boardState.engineInfo != null) {
      //
      var pvs = widget.boardState.engineInfo!.pvs;

      // 最多显示前两个走法（红黑双方）
      if (pvs.length > 2) {
        pvs = pvs.sublist(0, 2);
      }

      try {
        moves.addAll(pvs.map((move) => Move.fromEngineMove(move)));
      } catch (e) {
        print('解析引擎PV信息时出错: $e');
      }
    }

    // 打印调试信息
    if (moves.isNotEmpty) {
      print('准备显示的箭头数量: ${moves.length}');
      for (int i = 0; i < moves.length; i++) {
        print('箭头${i+1}: ${moves[i].asEngineMove()}');
      }
    }

    final layout = widget.layoutParams.buildPiecesLayout(context);

    return Stack(children: [
      layout,
      CustomPaint(
        painter: ThinkingBoardPainter(moves, widget.layoutParams),
      )
    ]);
  }
}
