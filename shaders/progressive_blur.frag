#version 460 core
#include <flutter/runtime_effect.glsl>

precision mediump float;

// ウィジェットのピクセルサイズ
uniform vec2 uSize;
// これより上（y が小さい側）でぼかしが効き始める境界（px, 上端からの距離）
uniform float uFadeStart;
// 最上部(y=0)での最大ぼかし半径（px）
uniform float uMaxRadius;
// ぼかし対象のテクスチャ（子ウィジェットのスナップショット）
uniform sampler2D uTexture;

out vec4 fragColor;

void main() {
  vec2 pos = FlutterFragCoord().xy;

  // t: 上端(y=0)で 1.0、uFadeStart で 0.0。境界より下は 0（ぼかし無し）。
  float t = clamp((uFadeStart - pos.y) / max(uFadeStart, 1.0), 0.0, 1.0);
  // イージング（下端をより自然に溶かす）
  t = t * t;
  float radius = t * uMaxRadius;

  if (radius < 0.5) {
    fragColor = texture(uTexture, pos / uSize);
    return;
  }

  // 黄金角スパイラルでディスク状にサンプリング。正方格子だと軸に沿った
  // 網目（ピクセル状の線）が出るため、非整列な分布にして構造的な線を消す。
  // さらにピクセル毎に開始角をジッターして残りのパターンをノイズに散らす。
  const int SAMPLES = 48;
  const float GA = 2.3999632; // 黄金角(rad)
  const float TAU = 6.2831853;
  float sigma = radius * 0.5;

  // 位置ベースの擬似乱数（フレーム間で不変＝ちらつかない）で開始角をずらす。
  float rnd = fract(sin(dot(pos, vec2(12.9898, 78.233))) * 43758.5453);
  float a0 = rnd * TAU;

  vec4 sum = vec4(0.0);
  float total = 0.0;
  for (int i = 0; i < SAMPLES; i++) {
    float fi = float(i) + 0.5;
    // 面積一様になる sqrt 分布で半径方向に配置。
    float r = sqrt(fi / float(SAMPLES)) * radius;
    float a = a0 + fi * GA;
    vec2 off = vec2(cos(a), sin(a)) * r;
    float w = exp(-(r * r) / (2.0 * sigma * sigma));
    sum += texture(uTexture, (pos + off) / uSize) * w;
    total += w;
  }
  fragColor = sum / total;
}
