#!/bin/bash

# GitHub Pagesデプロイスクリプト（.envを保護）

set -e

echo "📦 Flutter Webをビルド中..."
flutter build web --release

echo "🚀 GitHub Pagesにデプロイ中..."

# worktreeディレクトリが既に存在する場合は削除
if [ -d "gh-pages-deploy" ]; then
  rm -rf gh-pages-deploy
fi

# gh-pagesブランチ用のworktreeを作成
git worktree add gh-pages-deploy gh-pages

# ビルド成果物をworktreeにコピー
cp -r build/web/* gh-pages-deploy/

# .nojekyllファイルを追加
touch gh-pages-deploy/.nojekyll

# コミットしてプッシュ
cd gh-pages-deploy
git add -A
git commit -m "Deploy to GitHub Pages - $(date '+%Y-%m-%d %H:%M:%S')"
git push origin gh-pages

# worktreeをクリーンアップ
cd ..
git worktree remove gh-pages-deploy

echo "✅ デプロイ完了！"
echo "🌐 URL: https://fifteens-dev.github.io/fifteen/"
