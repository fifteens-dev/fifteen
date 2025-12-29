// モバイルWebブラウザ用のオーディオヘルパー
window.audioHelper = {
  currentAudio: null,
  isLoading: false,
  currentUrl: null,

  // 音声を再生
  playAudio: function(url) {
    console.log('🎵 Playing audio:', url);

    // 同じURLが既に読み込み中または再生中の場合はスキップ
    if (this.currentUrl === url && (this.isLoading || (this.currentAudio && !this.currentAudio.paused))) {
      console.log('⏭ Already loading or playing this URL, skipping');
      return Promise.resolve();
    }

    // 読み込み中フラグを設定
    this.isLoading = true;
    this.currentUrl = url;

    // 既存のオーディオを適切に停止
    if (this.currentAudio) {
      try {
        this.currentAudio.pause();
        this.currentAudio.src = ''; // リソースを解放
        this.currentAudio.load(); // 状態をリセット
      } catch (e) {
        console.warn('⚠️ Error stopping previous audio:', e);
      }
      this.currentAudio = null;
    }

    // 新しいオーディオ要素を作成
    this.currentAudio = new Audio();
    this.currentAudio.crossOrigin = "anonymous";
    this.currentAudio.loop = true;
    this.currentAudio.preload = "auto";

    // イベントリスナーを設定
    const audio = this.currentAudio;

    return new Promise((resolve, reject) => {
      // 読み込み完了時
      audio.addEventListener('canplaythrough', function onCanPlay() {
        console.log('✅ Audio loaded and ready to play');
        audio.removeEventListener('canplaythrough', onCanPlay);
      }, { once: true });

      // エラー時
      audio.addEventListener('error', function onError(e) {
        console.error('❌ Audio load error:', e);
        window.audioHelper.isLoading = false;
        reject(new Error('音声の読み込みに失敗しました'));
      }, { once: true });

      // URLを設定（これで読み込み開始）
      audio.src = url;
      audio.load();

      // 少し待ってから再生を試みる
      setTimeout(() => {
        const playPromise = audio.play();

        if (playPromise !== undefined) {
          playPromise
            .then(() => {
              console.log('✅ Audio playing successfully');
              window.audioHelper.isLoading = false;
              resolve();
            })
            .catch(error => {
              console.error('❌ Audio play failed:', error);
              window.audioHelper.isLoading = false;

              // "aborted"エラーは無視（ユーザーが連続クリックした場合）
              if (error.name !== 'AbortError') {
                alert('音楽の再生に失敗しました: ' + error.message);
              }
              reject(error);
            });
        } else {
          window.audioHelper.isLoading = false;
          resolve();
        }
      }, 100); // 100ms待機してメタデータの読み込みを確実に
    });
  },
  
  // 一時停止
  pauseAudio: function() {
    if (this.currentAudio) {
      this.currentAudio.pause();
      console.log('⏸ Audio paused');
    }
  },
  
  // 停止
  stopAudio: function() {
    if (this.currentAudio) {
      try {
        this.currentAudio.pause();
        this.currentAudio.currentTime = 0;
        this.currentAudio.src = '';
        this.currentAudio.load();
      } catch (e) {
        console.warn('⚠️ Error stopping audio:', e);
      }
      this.currentAudio = null;
      this.currentUrl = null;
      this.isLoading = false;
      console.log('⏹ Audio stopped');
    }
  },
  
  // 再開
  resumeAudio: function() {
    if (this.currentAudio) {
      this.currentAudio.play()
        .then(() => console.log('▶️ Audio resumed'))
        .catch(error => console.error('❌ Resume failed:', error));
    }
  }
};

console.log('🎵 Audio helper loaded');
