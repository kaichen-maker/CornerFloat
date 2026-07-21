# CornerFloat GitHub 首次发布指南

这份清单用于把当前本地仓库作为一个干净、可信的开源项目发布到
`kaichen-maker/CornerFloat`。第一次公开时只发布源码；不要把 `dist/`、
原始录屏、未公证的 ZIP/DMG 或签名密钥加入仓库。

## 1. Preflight before the first push

进入项目目录：

```bash
cd "/Users/calvinkai/Documents/Daily works/CornerFloat"
```

先确认公开身份。GitHub 会永久显示已有提交中的作者姓名和邮箱：

```bash
git config user.name
git config user.email
git log --format='%h  %an <%ae>' --all
```

如果 `Kaichen Guo <kaichen@withkai.ai>` 是你愿意公开的求职身份，可继续；
如果不是，请在第一次推送前停下来处理，不要等仓库公开后再改写历史。

运行发布前检查：

```bash
make doctor
make test
make strict
make acceptance
git diff --check
git status --short
```

最后一条在已提交本轮优化后应该没有输出。额外确认大文件和本地录屏确实
被忽略：

```bash
git check-ignore -v .demo-video-stage docs/media
git count-objects -vH
```

不要删除 `.gitignore` 中的录屏、`dist/`、环境变量、证书和 Xcode 发行产物
规则。GitHub 对单个 Git 对象强制执行 100MB 上限；即使较小的视频可以被
提交，也会让每一次克隆都承担永久成本。

## 2. Create and push the public repository

这台 Mac 已安装 GitHub CLI。先检查登录：

```bash
gh auth status
```

如果显示 token 无效或未登录，重新进行浏览器授权：

```bash
gh auth login -h github.com -w
gh auth status
```

然后从现有本地仓库直接创建公开仓库、添加 `origin` 并推送 `main`：

```bash
gh repo create kaichen-maker/CornerFloat \
  --public \
  --source=. \
  --remote=origin \
  --push \
  --description "Native floating web workspaces for macOS — AppKit + WebKit, no Electron."
```

如果你更愿意用网页创建仓库，请创建一个完全空的 `CornerFloat` 仓库，
不要勾选 README、`.gitignore` 或 License；然后运行：

```bash
git remote add origin https://github.com/kaichen-maker/CornerFloat.git
git push -u origin main
```

这是 GitHub 对已有本地仓库的官方导入方式：
[Adding locally hosted code to GitHub](https://docs.github.com/en/migrations/importing-source-code/using-the-command-line-to-import-source-code/adding-locally-hosted-code-to-github)。

推送后立即验证：

```bash
git remote -v
git ls-remote --heads origin main
gh repo view kaichen-maker/CornerFloat --web
```

## 3. Configure the repository page

在仓库首页右侧 **About → Edit** 中设置：

- Description: `Native floating web workspaces for macOS — AppKit + WebKit, no Electron.`
- Website: 暂时留空；公开视频上线后可填演示或项目主页。
- Topics: `macos`, `swift`, `appkit`, `webkit`, `menu-bar`, `productivity`,
  `floating-window`, `native-macos`, `open-source`。

Topics 会帮助项目被搜索和发现；GitHub 的配置说明见
[Classifying your repository with topics](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/classifying-your-repository-with-topics)。

在 **Settings → General → Social preview** 上传：

```text
docs/images/cornerfloat-social-preview.png
```

这个文件已准备为 1280×640、低于 1MB，并保留实体应用界面。GitHub 对社交
预览的官方建议见
[Customizing your repository's social media preview](https://docs.github.com/en/enterprise-cloud@latest/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/customizing-your-repositorys-social-media-preview)。

同时确认：

- **Issues** 已启用；仓库已带有 bug 和 feature issue 模板。
- **Discussions** 可先不启用，等出现真实社区讨论再打开。
- MIT License 被 GitHub 正确识别。
- README 顶部的 `Contributor CI` badge 在第一次 Actions 完成后变绿。

## 4. Publish the real demo

90 秒真实录屏属于发布素材，不属于源代码。推荐把隐私安全的最终 MP4
上传到 YouTube（公开或 Unlisted）或 Vimeo，然后让 README 封面链接到它。
不要把 MP4/MOV 提交进 Git，也不要使用 Git LFS 来解决一个宣传视频问题。

当前唯一可公开上传的视频文件是：

```text
docs/media/CornerFloat-0.8.0-real-demo-final.mp4
SHA-256: 79fa8f61395fda43f5304a07177d6dc4d3ac654bb3dd5c49ff3fdd705ae360a9
```

它是 1920×1080、89.998 秒的真实屏幕录像，已逐段移除账户资料、历史任务和
系统弹窗。不要上传同目录中没有 `-final` 后缀的旧视频；旧文件只作为本地
制作备份保留。

上传视频时使用：

- Title: `CornerFloat 0.8 — 90-second real macOS demo`
- Description: `A real-time capture of CornerFloat's native AppKit + WebKit floating workspace. No Electron.`
- Thumbnail: `docs/images/cornerfloat-demo-poster.png`

得到公开 URL 后，把 README 的预览图片改成：

```html
<p align="center">
  <a href="https://YOUR_VIDEO_URL">
    <img src="docs/images/cornerfloat-demo-poster.png" width="100%" alt="Watch the 90-second CornerFloat demo">
  </a>
</p>
```

并在图片下增加：

```markdown
[Watch the full 90-second real demo →](https://YOUR_VIDEO_URL)
```

以一个小的独立提交发布这个链接：

```bash
git add README.md README.zh-CN.md
git commit -m "Link the real CornerFloat demo"
git push
```

不要创建“demo-only” GitHub Release。当前正式发布工作流会把任何已有 Release
视为更新历史，并要求其中存在有效 `appcast.xml`；演示 Release 会破坏第一次
签名版本的校验。GitHub Releases 应留给经过 Developer ID 签名、Apple 公证并
包含 Sparkle 更新资产的正式二进制。

## 5. Verify CI before protecting main

打开 **Actions → Contributor CI**，等待两个矩阵任务都通过：

- `macOS 14`
- `macOS 15`

如果失败，先点开具体步骤修复；不要用空提交反复重跑，也不要在红色 CI 上
发布“稳定”标签。两个任务通过后再设置规则，避免把一个拼写错误的 check 名
锁成永远无法满足的要求。

进入 **Settings → Rules → Rulesets → New branch ruleset**：

1. 名称填 `Protect main`，状态设为 Active。
2. Target 选择 default branch。
3. 保持禁止 branch deletion 和 non-fast-forward pushes。
4. 启用 **Require status checks to pass**，添加 `macOS 14` 与 `macOS 15`。
5. 启用 **Require conversation resolution before merging**。
6. 单人维护初期可不要求外部 approval；日常功能仍用分支和 PR 合并。

GitHub Free 的公开仓库支持 protected branches/rulesets；官方说明见
[About protected branches](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches)。

## 6. Seed real contribution paths

不要制造虚假 star、虚假 contributor 或无意义提交。先从
[`docs/GOOD_FIRST_ISSUES.md`](GOOD_FIRST_ISSUES.md) 建立三个边界清楚的 Issues：

1. `Add a Quick Site from the active page`
2. `Add a Duplicate Current Tab command`
3. `Improve empty-state keyboard navigation`

为每个 Issue 保留原文中的 acceptance criteria 和验证命令，并添加合适的
`good first issue`、`enhancement`、`accessibility` 标签。只把仍然有效、尚未被
领取的任务标为 `good first issue`。

随后启用 **Settings → Security → Private vulnerability reporting**，并确认
Dependabot 在仓库 Security 页面正常工作。仓库已经包含 `SECURITY.md`、
Dependabot 配置、PR 模板和权限最小化的 Actions。

## 7. Source launch versus binary release

第一次 GitHub 上线只承诺“从源码构建”。当前本地 ZIP/DMG 使用 ad-hoc 签名，
适合开发和个人测试，不应作为普通用户下载版。

以后准备正式二进制时，按此顺序操作：

1. 获得 Apple Developer Program 的 Developer ID Application certificate。
2. 配置 Apple notarization、Sparkle EdDSA key 和 GitHub `release` environment。
3. 把所需 secrets 放进 GitHub environment，不放进仓库或普通 workflow 日志。
4. 更新版本号、`CHANGELOG.md` 与 `RELEASE_NOTES.md`。
5. 从默认分支手动运行 **Optional: Signed Binary Release** workflow。
6. 让工作流创建 tag、DMG、ZIP、checksums、`appcast.xml` 和正式 Release。

GitHub Releases 用 tag 打包软件和二进制资产；官方说明见
[Managing releases in a repository](https://docs.github.com/en/repositories/releasing-projects-on-github/managing-releases-in-a-repository)。

## 8. What to do after launch

### 上线当天

- 用退出登录/隐私窗口打开仓库，确认匿名用户能看到 README、图片、License
  和 Actions。
- 点击 README 的每个主要链接，检查中英文页面、贡献指南和安全政策。
- 上传 social preview，添加 topics，发布并链接真实演示视频。
- 在个人 GitHub Profile 固定 CornerFloat，使招聘者不需要翻找仓库。

### 第一周

- 建立上述三个真实 Issues，并用一个小分支完成其中一个，再通过 PR 合并。
- 在 PR 中展示问题、方案、截图/测试结果和权衡，而不只是代码差异。
- 把一个真实限制写入 Roadmap 或 Website compatibility，而不是宣称所有网站
  登录、语音或屏幕分享都已完整支持。
- 回应每个真实 Issue，即使答复只是确认复现和下一步。

### 接下来的 2–4 周

- 每周至少形成一个有意义的 Issue、PR、文档改进或 bug fix；质量比提交数重要。
- 在 **Insights → Traffic** 查看最近 14 天的访问、独立访客、clone 和来源，
  记录哪次分享真正带来阅读或使用。
- 等有实质变化再发布 `0.8.1`；不要只为了“活跃”反复改版本号。
- 如果开始出现外部用户，再启用 Discussions、增加兼容性矩阵和公开 changelog。

GitHub 对 Profile pin 和 Traffic 的说明：
[Pinning items to your profile](https://docs.github.com/en/account-and-profile/how-tos/profile-customization/pinning-items-to-your-profile)、
[Viewing traffic to a repository](https://docs.github.com/en/repositories/viewing-activity-and-data-for-your-repository/viewing-traffic-to-a-repository)。

## 9. Present it in a job application

简历项目描述可使用：

> Built a native macOS floating web workspace with AppKit and WebKit; designed
> resizable always-on-top panels, persistent tabs/workspaces, privacy-safe URL
> handling, macOS 14/15 CI, and a signed/notarized Universal 2 release path.

面试演示按 90 秒顺序讲清四件事：

1. 用户问题：浏览器内容在工作切换时消失。
2. 产品体验：网页始终置顶、边缘缩放、标签页、搜索和全局显隐。
3. 工程判断：AppKit + WebKit、无 Electron、核心功能无需高风险隐私权限。
4. 开源可信度：可复现构建、双版本 CI、测试边界、Issue/PR 和正式发布路径。

真正有说服力的不是文件数量，而是仓库能证明：你识别了 Mac 用户问题、做出
原生产品取舍、处理了隐私与发布边界，并且能让陌生贡献者理解和验证项目。

## 10. Common recovery commands

如果远程仓库名输错，在尚未推送重要协作内容时修正 URL：

```bash
git remote set-url origin https://github.com/kaichen-maker/CornerFloat.git
```

如果 `origin` 已存在，不要再次 `git remote add`；先查看：

```bash
git remote -v
```

如果 GitHub CLI 登录过期：

```bash
gh auth login -h github.com -w
```

任何时候都不要用 `git push --force` 去“解决”首次上传问题。先确认远端是否是
空仓库、分支名是否为 `main`、认证账户是否正确，再处理具体错误。
