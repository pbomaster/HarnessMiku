# 제3자 소프트웨어 및 저작물 고지

Harness Miku v28 공개 키트는 설치 시 외부 배포처에서 구성 요소를 받아 사용자의 Mac에 앱을 구성합니다. 아래 저작권 및 사용권은 각 항목에 적용됩니다.

## DeepSeek Harness와 한국어 패치

DeepSeek Harness 0.2.1-rc.5는 데스크톱 앱의 기반입니다. 한국어 패치의 오버레이에는 이 버전의 파일을 수정한 코드가 포함되어 있습니다. 설치기는 DMG와 오버레이를 별도로 받아 적용하고, 한국어 패치의 LICENSE와 NOTICE.md를 앱의 Contents/Resources/HarnessMikuNotices에 복사합니다. [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) · [한국어 패치의 고정 커밋](https://github.com/noire113-dev/deepseek-harness-kr/tree/96544431322d3f2cde1ec42db156c8b8eee5e6fd) · [원본 고지](https://github.com/noire113-dev/deepseek-harness-kr/blob/96544431322d3f2cde1ec42db156c8b8eee5e6fd/NOTICE.md)

### DeepSeek Harness

MIT License

Copyright (c) 2026 DeepSeek

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

### deepseek-harness-kr

MIT License

Copyright (c) 2026 DeepSeek짱 contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

## 캐릭터 렌더러와 모델

- **Live2D Cubism Core** — Copyright (c) Live2D Inc. 한국어 오버레이의 vendor 디렉터리에 포함된 런타임에는 Live2D Proprietary Software License가 적용됩니다. [사용권 원문](https://www.live2d.com/eula/live2d-proprietary-software-license-agreement_en.html)
- **pixi.js와 pixi-live2d-display** — 오버레이의 렌더링 구성 요소입니다. 한국어 패치의 NOTICE.md는 두 프로젝트의 사용권을 MIT로 명시합니다. [pixi.js](https://github.com/pixijs/pixijs) · [pixi-live2d-display](https://github.com/guansss/pixi-live2d-display)
- **오버레이의 DeepSeek짱 모델과 배경** — 업스트림 README는 모델 원작자로 Kamiya_Ryoko를 표기하며, NOTICE.md는 배경을 저장소 작성자의 AI 생성물로 설명합니다. 이 키트의 설치기는 해당 모델과 배경을 설치용 오버레이에서 제거합니다.
- **RetrynowMiku** — 일러스트 Ruby_呜哔うび, Live2D 리깅 慈善小霓. 사용자가 제작자의 공식 페이지에서 직접 받은 원본을 개인 Mac에서 사용합니다. 모델 파일, 수정본 및 모델을 포함한 완성 앱을 재배포하지 마세요. 개인 비상업적 사용 및 수익화 방송 제한 등은 제작자의 조건을 따릅니다. [공식 배포 및 이용 조건](https://ko-fi.com/s/7bb9ac0243)
- **いますぐ輪廻** — 음악 なきそ, MV channel. 캐릭터 연출에 영감을 준 작품입니다. 작품 크레딧은 README의 Acknowledgements에도 수록했습니다. [공식 MV](https://youtu.be/3iUgKH8c7p4)

## 음성 및 로컬 추론

- 받아쓰기를 위해 설치기가 sherpa-onnx v1.12.14와 SenseVoice INT8 모델을 별도 다운로드합니다. 엔진과 모델 가중치의 조건은 각 배포처에서 확인하세요. [엔진](https://github.com/k2-fsa/sherpa-onnx/releases/tag/v1.12.14) · [모델 배포](https://github.com/k2-fsa/sherpa-onnx/releases/tag/asr-models) · [SenseVoice](https://github.com/FunAudioLLM/SenseVoice)
- llama.cpp와 GGUF 가중치는 사용자가 준비합니다. 가중치에는 선택한 모델의 사용권이 적용됩니다. [llama.cpp](https://github.com/ggml-org/llama.cpp)
- Fish Audio는 선택 가능한 외부 음성 합성 서비스입니다. 본인이 사용 권한을 확보한 참조 음성을 지정하세요. [Fish Audio](https://fish.audio/)
