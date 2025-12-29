// モバイルWebブラウザ用のオーディオヘルパー
window.audioHelper = {
  currentAudio: null,
  
  // 音声を再生
  playAudio: function(url) {
    console.log('🎵 Playing audio:', url);
    
    // 既存のオーディオを停止
    if (this.currentAudio) {
      this.currentAudio.pause();
      this.currentAudio = null;
    }
    
    // 新しいオーディオ要素を作成
    this.currentAudio = new Audio(url);
    this.currentAudio.crossOrigin = "anonymous";
    this.currentAudio.loop = true;
    
    // 再生を試みる
    const playPromise = this.currentAudio.play();
    
    if (playPromise !== undefined) {
      playPromise
        .then(() => {
          console.log('✅ Audio playing successfully');
        })
        .catch(error => {
          console.error('❌ Audio play failed:', error);
          alert('音楽の再生に失敗しました: ' + error.message);
        });
    }
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
      this.currentAudio.pause();
      this.currentAudio.currentTime = 0;
      this.currentAudio = null;
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
