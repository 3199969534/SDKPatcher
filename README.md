# SDK Patcher（iOS）

在 iPhone 上选择 .ipa，把主程序的 SDK 版本改成 27.1.0（可改），再导出，交给你自己的签名工具签名安装。

## 没有 Mac 怎么编译
1. 新建一个 GitHub 仓库，把本文件夹全部内容上传（注意 .github 目录）。
2. 打开仓库 Actions → Build unsigned IPA → Run workflow。
3. 完成后在 Artifacts 下载 SDKPatcher-unsigned-ipa，解压得到 SDKPatcher.ipa。
4. 用你自己的证书/Sideloadly 签名安装。

## 使用
打开 App → 选 IPA → 导出 → 用签名工具重新签名。
说明：修改会使原签名失效，导出的 IPA 必须重新签名。

## 关于 iPhone Duo / iOS 27.1 SDK
- 只有用 iOS 27.1 SDK（Xcode 27.1+）编译的 App，在 iPhone Duo 展开时才会铺满到屏幕边缘；工作流会检查 SDK，没有 27.1 会直接报错。
- 界面只用系统标准控件（NavigationStack / Form），安全区和竖排导航按钮由系统自动适配，没有写死尺寸。
- 编译后可看 Actions 日志里 vtool 的输出，确认 sdk 为 27.1。
