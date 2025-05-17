package cn.mdevs.apps.chessroad;

import androidx.annotation.NonNull;

import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.embedding.engine.FlutterEngineCache;
import io.flutter.embedding.engine.dart.DartExecutor;

public class MainActivity extends FlutterActivity {

    @Override
    public void configureFlutterEngine(@NonNull FlutterEngine flutterEngine) {
        super.configureFlutterEngine(flutterEngine);

        // // 创建并缓存单独的引擎用于悬浮窗
        // FlutterEngine overlayEngine = new FlutterEngine(this);

        // // 注册简易悬浮窗入口点，使用createDefault()
        // // 入口点将由AndroidManifest.xml中的meta-data指定
        // overlayEngine.getDartExecutor().executeDartEntrypoint(
        //     DartExecutor.DartEntrypoint.createDefault()
        // );

        // // 缓存引擎供悬浮窗服务使用
        // FlutterEngineCache.getInstance().put("overlay_engine", overlayEngine);
    }
}
