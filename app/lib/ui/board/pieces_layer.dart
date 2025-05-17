import 'package:flutter/material.dart';
import 'pieces_layout.dart';

class PiecesLayer extends StatefulWidget {
  //
  final PiecesLayout layoutParams;

  const PiecesLayer(this.layoutParams, {Key? key}) : super(key: key);

  @override
  State createState() => _PiecesLayerState();
}

class _PiecesLayerState extends State<PiecesLayer> with SingleTickerProviderStateMixin {
  //
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: widget.layoutParams.buildPiecesLayout(context),
    );
  }
}
