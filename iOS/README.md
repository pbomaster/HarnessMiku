# Harness Miku · iPhone Duo 개인용
Mac판의 ‘지금 바로 윤회’ 미쿠를 iPhone에서 만나기 위한 SwiftUI 프로젝트입니다. iOS 27.2 SDK로 빌드하며 최소 배포 대상은 iOS 27.0입니다. 빌드 단계에서 기기 및 시뮬레이터 SDK 버전을 확인합니다.

## 빌드 23 소스에서 시작하기

이 폴더에는 iOS 앱과 로컬 MLX 패키지의 소스가 들어 있습니다. 저장소 루트에서 `cd iOS` 후 `bash Tools/install-prism-runtime.sh`로 고정 버전의 프레임워크를 준비하세요. 개인적으로 보유한 8B 모델을 `ModelAssets/Miku-August-8B-Memory-Q4_K_M.gguf` 경로에 두고, 아래의 Prepare.command로 본인이 보유한 캐릭터 리소스를 Mac에서 준비하세요. 서명 시 자신의 개발 팀과 앱 식별자를 사용하세요.

## Mac에서 아이폰에 설치
1. iOS 27.2 SDK가 포함된 Xcode를 설치하고 한 번 실행해 iOS 플랫폼과 개발 도구 설치를 완료하세요. Xcode의 Settings → Locations → Command Line Tools에서 해당 Xcode를 선택하세요. 터미널에서 `xcrun --sdk iphoneos --show-sdk-version` 결과가 27.2여야 합니다.
2. 프로젝트 ZIP을 압축 해제하세요. 제작자 원본 `New1007-RetrynowMiku.zip`은 압축을 그대로 유지하세요. Finder에서 `Prepare.command`를 실행하고 모델 ZIP을 선택하세요. Finder 실행이 차단되면 내용을 확인한 뒤, 터미널에서 프로젝트 폴더로 이동해 `bash Prepare.command`를 실행할 수 있습니다.
3. 준비가 끝나면 Xcode 프로젝트가 열립니다. 프로젝트의 **HarnessMiku 타깃 → Signing & Capabilities**에서 Automatically manage signing을 선택하고 본인의 Team을 지정하세요. Bundle Identifier를 본인이 등록할 수 있는 고유한 역도메인 값으로 바꾸세요. 이후 같은 식별자로 설치해야 기존 대화와 키체인을 이어 쓸 수 있습니다.
4. 케이블로 아이폰을 연결하고 신뢰를 승인하세요. iPhone의 설정 → 개인정보 보호 및 보안 → 개발자 모드를 켜고 재시동 안내를 따르세요. Xcode의 실행 대상으로 실제 iPhone Duo를 고른 뒤 **Run (⌘R)** 을 누르세요. App Store Connect 제출이나 IPA 업로드는 필요하지 않습니다.

## 아이폰에서 로컬 모델로 대화하기
1. **설정 → 로컬 AI → 기기 내 모델**에서 사용할 모델을 고릅니다. 처음에는 **Miku August 8B**가 선택됩니다.
2. **Miku August 8B**는 **8B 모델 받기**로 Apple 모델 팩을 받습니다. 이미 설치한 GGUF도 그대로 사용합니다. 앱은 원본 Q4_K·Q6_K 가중치를 MLX에서 계산하고 GGUF 어휘로 토큰을 읽습니다. 지시문·대화·답변을 합친 문맥은 3,072토큰입니다.
3. **Bonsai 2 9B MLX** 또는 **Bonsai 2 27B**를 선택한 뒤 모델 받기를 누르세요. 파일 앱의 MLX 모델 폴더도 가져올 수 있습니다. 9B 설치 파일은 약 3.48GB, 27B는 약 7.69GB입니다. 27B 다운로드는 공식 모델에서 텍스트 대화에 쓰이는 가중치만 받습니다. 이전 GGUF는 보관되며 MLX용 파일은 따로 설치합니다.
   Bonsai는 비추론 모드에서 실행합니다. **자동 최대**는 현재 메모리 여유와 모델 한도에 맞춰 대화를 담습니다. **64K 고정**은 입력과 출력을 합해 65,536토큰을 허용합니다. 두 모드 모두 시스템 지시문과 답변 공간을 먼저 확보하고 최근 대화부터 완전한 턴 단위로 포함합니다. 실제 답변 시간은 이번에 읽는 입력 길이에 따라 달라집니다.

4. **오프라인 대화 준비됨**이 표시되면 설정을 닫고 채팅 또는 음성 대화를 시작합니다. 모델별 대화 지침은 앱의 `Stage/august-persona.txt`와 `Stage/bonsai-persona.txt`에 있습니다.

모델을 정리하려면 **설정 → 로컬 AI → 기기 내 모델**에서 모델을 고른 뒤 **모델 삭제** 또는 **모델 다시 받기**를 누르세요. 다시 받기는 기존 설치 파일을 지운 뒤 재설치합니다. 27B 삭제는 이전 GGUF 파일도 포함합니다. 8B의 Apple 다운로드 캐시는 iOS가 관리하며, 캐시가 있으면 다시 설치할 때 원본 검증 후 복원합니다.

전체화면에 들어가면 음성 인식을 시작하고, 사이드바의 마이크 아이콘으로 켜고 끌 수 있습니다. 화면을 접거나 펼치는 동안 선택한 마이크 상태를 이어 갑니다. 앱이 백그라운드로 이동하거나 오디오가 중단되면 음성 대화를 멈춥니다. 대화 자막과 실제 오류를 표시합니다.

## 첫 대화
- **DeepSeek 연결 → DeepSeek 로그인**을 누릅니다. 시스템 브라우저 창에서 공식 DeepSeek 페이지의 로그인을 승인하세요. 앱이 PKCE 코드와 상태값을 확인하고 기기 키체인에 계정 세션을 저장합니다. 설정을 닫고 대화를 보내면 계정의 모델 목록에서 Flash 계열을 우선 사용합니다. 기존 API 키 사용자는 **API 키** 방식도 선택할 수 있습니다. 계정의 서비스 접근 권한과 쿼터가 적용됩니다.
- **설정 → 답변이 오면 알림**을 켜고 iOS 알림 권한을 허용하세요. 채팅을 열어 둔 상태에서는 배너를 생략합니다. 개인 중계가 꺼져 있으면 앱이 백그라운드 실행 시간을 받은 동안 수신한 답변에 로컬 알림을 보냅니다. iOS가 앱을 정지시킨 뒤에도 완료 알림을 받으려면 아래의 개인 중계를 구성하세요.

- 낭독에는 로컬 모델에서도 인터넷 연결과 Fish Audio API 키가 필요합니다. 키를 저장하면 미쿠 답변의 **듣기**로 재생할 수 있습니다. 기본 참조 음성은 기존 Mac 개인판의 `f77a554c56df4c9caf578cb43e6bac43`입니다. 본인에게 사용 권한이 있는 다른 음성으로 교체할 수 있습니다. 모델 접근 권한과 요금은 Fish 계정에 따릅니다. **답변 자동 낭독**은 기본으로 꺼져 있습니다.
- **마이크 → 말하기 → 완료** 순서로 한국어를 받아씁니다. 초안을 고친 뒤 보내세요. 55초에 자동으로 녹음을 마칩니다. 인식 서비스나 권한을 사용할 수 없어도 텍스트 채팅은 가능합니다.
- 이전 답변도 다시 들을 수 있습니다. 재생 중에는 **중지**를 누르세요. Fish 합성이 실패해도 답변은 채팅에 남습니다.

## 미쿠 터치
캐릭터 패널을 누른 채 움직이면 시선이 손끝을 따라갑니다. 손을 놓으면 잠시 뒤 정면으로 돌아옵니다. 미쿠의 머리·팔·리본·몸통을 가볍게 탭하면 Mac판의 해당 부위 대사와 표정이 나옵니다. 여백은 시선 이동에만 사용됩니다. 자동 낭독이 켜져 있고 답변 생성·녹음·재생 중이 아닐 때에는 터치 대사도 Fish Audio로 읽습니다. 터치 대사는 채팅 기록에 저장하지 않습니다. iOS의 동작 줄이기에서는 시선을 유지하면서 고개 움직임을 줄입니다.

## 화면과 데이터
좁은 공간에서는 캐릭터 아래에 대화를 배치합니다. 충분히 넓으면 캐릭터와 대화를 좌우로 나눕니다. 레이아웃은 사용 가능 폭, 시스템 크기 클래스, 글자 크기로 결정합니다. 키보드가 공간을 차지하면 세로 캐릭터 영역이 줄어듭니다. 표준 NavigationStack, 시스템 툴바, Safe Area, Dynamic Type, 입력 버튼 접근성 레이블을 사용합니다.

대화는 앱의 Application Support에 파일 보호를 적용해 저장하며 가장 최근 24개 메시지를 요청에 포함합니다. 새 대화 메뉴로 기록을 지울 수 있습니다. 두 API 키는 이 기기에서 잠금 해제 중에만 접근 가능한 키체인 항목으로 저장합니다. 키는 캐릭터 웹 뷰에 전달되지 않습니다. 오디오 입력은 기기 내 인식을 우선하며 지원되지 않는 경우 Apple 음성 인식을 사용합니다. 오디오·대화가 외부로 전송되는 시점은 설정 화면에 안내합니다.

iOS판은 앱 안의 캐릭터와 대화에 집중합니다. 데스크톱 오버레이, 셸 실행, 외부 앱 제어, Mac 로그인 항목, 로컬 llama.cpp 서버 실행 기능은 포함하지 않았습니다. 낭독 중에는 한글을 모음으로 분해해 ㅏ·ㅔ·ㅣ·ㅗ·ㅜ 입 모양을 연결합니다. Fish Audio는 단어별 시간 정보와 재생 위치를 사용합니다. 단어 내부의 모음 시점은 추정하며, Fish 시간 정보가 빠지면 전체 음성 길이를 기준으로 추정합니다.

## 모델과 런타임
준비 도구는 Mac판과 같은 고정 커밋의 한국어 하네스 배포 ZIP을 내려받아 SHA-256을 확인하고 렌더러 3개와 고지만 가져옵니다. 공식 모델 ZIP의 알려진 파일 61개를 검증합니다. 기기용 사본의 텍스처 17장을 최대 1024px로 축소해 GPU 메모리 사용량을 줄입니다. 생성물은 `HarnessMiku/Stage/Private/`에만 둡니다. 모델이나 렌더러가 빠지면 빌드 단계에서 준비 방법을 안내합니다. 프로젝트 ZIP에는 모델과 Cubism Core가 들어 있지 않습니다. 준비 후 생성한 앱과 모델 사본은 개인 기기에서만 사용하세요.

일러스트 Ruby_呜哔うび, Live2D 慈善小霓. 렌더링에 Live2D Cubism Core, PixiJS, pixi-live2d-display를 사용합니다. 고정 커밋의 LICENSE와 NOTICE.md가 준비 과정에서 앱 리소스에 포함됩니다. Mac판 페르소나와 원작 크레딧은 동봉한 고지를 참고하세요.

[공식 모델 제공처](https://ko-fi.com/s/7bb9ac0243) · [한국어 하네스 소스](https://github.com/noire113-dev/deepseek-harness-kr/tree/96544431322d3f2cde1ec42db156c8b8eee5e6fd) · [Live2D 사용 조건](https://www.live2d.com/eula/live2d-proprietary-software-license-agreement_en.html)

## Mac에서 확인
준비 작업 후 `bash Verify-Simulator.command`로 iOS 27.2 시뮬레이터용 컴파일을 확인할 수 있습니다. Xcode에서 iPhone Duo 시뮬레이터를 선택해 실행하고 다음을 확인하세요.

- 초안에 몇 글자를 쓴 뒤 접기·펼치기와 회전을 반복해 대화, 초안, 캐릭터가 유지되는지 확인합니다.
- 큰 글자, 가로 화면, 키보드를 연 상태에서 보내기·마이크와 설정 툴바에 접근할 수 있는지 확인합니다.
- 실제 아이폰에서는 받아쓰기 승인·거절, Fish 재생·중지, 다른 앱으로 전환하기를 확인합니다. 맥에서 아이폰으로 API 키가 자동 전송되지 않으므로 첫 설정은 기기에서 직접 합니다.

[Apple iPhone Duo 디자인 지침](https://developer.apple.com/design/human-interface-guidelines/designing-for-iphone-duo) · [Apple Duo 개발 준비](https://developer.apple.com/iphone-duo/prepare/) · [Xcode 27.2 릴리스 노트](https://developer.apple.com/documentation/xcode-release-notes/xcode-27_2-release-notes)


## 원격 푸시를 쓰는 경우
`Relay/README.md`에 서명, APNs 키, 개인 Mac 중계, HTTPS 연결 순서가 있습니다. 중계에 접수된 요청은 아이폰이 정지되어도 중계가 처리합니다. 앱을 다시 열면 저장된 작업 ID로 답변을 가져옵니다. 결과를 받기 전에 새 대화를 시작하면 이전 대화의 결과는 새 대화에 붙지 않습니다. 이미 접수된 작업은 중계에서 끝까지 실행될 수 있습니다. 완료 알림에는 대화 본문이 포함되지 않습니다.

[DeepSeek Harness 계정 인증](https://github.com/deepseek-ai/deepseek-harness/tree/master/packages/credentials/deepseek-account-platform) · [Apple 원격 알림](https://developer.apple.com/documentation/usernotifications/setting-up-a-remote-notification-server)
