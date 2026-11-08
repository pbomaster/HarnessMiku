# Harness Miku · iPhone Duo 개인용
Mac판의 ‘지금 바로 윤회’ 미쿠를 iPhone에서 만나기 위한 SwiftUI 프로젝트입니다. iOS 27.2 SDK로 빌드하며 최소 배포 대상은 iOS 27.0입니다. 빌드 단계에서 기기 및 시뮬레이터 SDK 버전을 확인합니다.

## 첫 실행과 캐릭터 가져오기

아이폰의 파일 앱에 제작자의 원본 `New1007-RetrynowMiku.zip`을 저장하세요. 처음 실행하면 Cubism Core 이용 조건과 Live2D 공식 약관 링크가 표시됩니다. 동의하면 캐릭터 설정이 열립니다. 이전 버전에서 가져온 캐릭터가 있으면 동의 후 바로 대화 화면이 열립니다. 파일 선택 창에서 원본 ZIP을 고른 뒤 가져오기가 끝날 때까지 기다리세요. 캐릭터는 앱의 전용 저장 공간에 보관됩니다.

[공식 캐릭터 ZIP 제공처](https://ko-fi.com/s/7bb9ac0243)

## 배포용 IPA 빌드

iOS 27.2 SDK를 선택한 Mac에서 저장소 루트의 `bash packaging/build-ios.sh "$PWD/HarnessMiku-iOS.ipa"`를 실행하세요. 기기용 IPA에는 개인 서명 정보가 들어가지 않습니다.

## 아이폰 기기 내 하츠네 미쿠 음성

설정의 **미쿠의 목소리 → 기기 내 미쿠**에서 `HatsuneMiku-RVC-iPhone.zip`을 선택한 뒤 저장하세요. 캐릭터를 그리는 Live2D ZIP과 목소리 ZIP은 별개입니다. 아이폰에 설치된 한국어 시스템 음성과 RVC 모델로 낭독하며 Fish API 키는 필요하지 않습니다. DeepSeek 채팅은 기존 연결 방식을 사용합니다. 기존 Fish Audio 사용자 설정은 유지됩니다.

음성 팩을 준비하려면 Python 3, Node.js, npm이 있는 컴퓨터에서 `python3 iOS/Tools/prepare-rvc-pack.py HatsuneMiku-RVC-iPhone.zip`을 실행하세요. 출력 ZIP을 아이폰 파일 앱에 보관하세요. 이후 낭독은 아이폰에서 수행합니다. 아카이브에는 aple / 3939_dancer의 `miku_default_rvc` 가중치를 변환한 40 kHz ONNX 모델과 ContentVec 특징 추출기가 들어갑니다. 선택적 검색 인덱스는 사용하지 않습니다.

[음성 모델 및 제작자](https://huggingface.co/aple/HatsuneMikuRVC) · [ContentVec 배포처](https://huggingface.co/wok000/weights_gpl)

## 음성 대화

전체화면에 들어가면 음성 인식을 시작하고, 사이드바의 마이크 아이콘으로 켜고 끌 수 있습니다. 화면을 접거나 펼치는 동안 선택한 마이크 상태를 이어 갑니다. 앱이 백그라운드로 이동하거나 오디오가 중단되면 음성 대화를 멈춥니다. 대화 자막과 실제 오류를 표시합니다.

## 첫 대화
- **DeepSeek 연결 → DeepSeek 로그인**을 누릅니다. 시스템 브라우저 창에서 공식 DeepSeek 페이지의 로그인을 승인하세요. 앱이 PKCE 코드와 상태값을 확인하고 기기 키체인에 계정 세션을 저장합니다. 설정을 닫고 대화를 보내면 계정의 모델 목록에서 Flash 계열을 우선 사용합니다. 기존 API 키 사용자는 **API 키** 방식도 선택할 수 있습니다. 계정의 서비스 접근 권한과 쿼터가 적용됩니다.
- **설정 → 답변이 오면 알림**을 켜고 iOS 알림 권한을 허용하세요. 채팅을 열어 둔 상태에서는 배너를 생략합니다. 개인 중계가 꺼져 있으면 앱이 백그라운드 실행 시간을 받은 동안 수신한 답변에 로컬 알림을 보냅니다. iOS가 앱을 정지시킨 뒤에도 완료 알림을 받으려면 아래의 개인 중계를 구성하세요.

- 낭독에는 인터넷 연결과 Fish Audio API 키가 필요합니다. 키를 저장하면 미쿠 답변의 **듣기**로 재생할 수 있습니다. 본인이 사용할 참조 음성 ID를 설정하세요. 모델 접근 권한과 요금은 Fish 계정에 따릅니다. **답변 자동 낭독**은 기본으로 꺼져 있습니다.
- **마이크 → 말하기 → 완료** 순서로 한국어를 받아씁니다. 초안을 고친 뒤 보내세요. 55초에 자동으로 녹음을 마칩니다. 인식 서비스나 권한을 사용할 수 없어도 텍스트 채팅은 가능합니다.
- 이전 답변도 다시 들을 수 있습니다. 재생 중에는 **중지**를 누르세요. Fish 합성이 실패해도 답변은 채팅에 남습니다.

## 미쿠 터치
캐릭터 패널을 누른 채 움직이면 시선이 손끝을 따라갑니다. 손을 놓으면 잠시 뒤 정면으로 돌아옵니다. 미쿠의 머리·팔·리본·몸통을 가볍게 탭하면 Mac판의 해당 부위 대사와 표정이 나옵니다. 여백은 시선 이동에만 사용됩니다. 자동 낭독이 켜져 있고 답변 생성·녹음·재생 중이 아닐 때에는 터치 대사도 Fish Audio로 읽습니다. 전체 화면 음성 대화에서는 미쿠를 탭하면 터치 대사를 낭독합니다. 마이크가 켜져 있으면 재생 동안 받아쓰기를 멈추고 대사가 끝나면 다시 듣습니다. 터치 대사는 채팅 기록에 저장하지 않습니다. iOS의 동작 줄이기에서는 시선을 유지하면서 고개 움직임을 줄입니다.

## 화면과 데이터
좁은 공간에서는 캐릭터 아래에 대화를 배치합니다. 충분히 넓으면 캐릭터와 대화를 좌우로 나눕니다. 레이아웃은 사용 가능 폭, 시스템 크기 클래스, 글자 크기로 결정합니다. 키보드가 공간을 차지하면 세로 캐릭터 영역이 줄어듭니다. 표준 NavigationStack, 시스템 툴바, Safe Area, Dynamic Type, 입력 버튼 접근성 레이블을 사용합니다.

대화는 앱의 Application Support에 파일 보호를 적용해 저장하며 가장 최근 24개 메시지를 요청에 포함합니다. 새 대화 메뉴로 기록을 지울 수 있습니다. 이전 버전에서 기기 전용으로 생성한 대화는 화면에 남으며 DeepSeek 요청에서 제외됩니다. 두 API 키는 이 기기에서 잠금 해제 중에만 접근 가능한 키체인 항목으로 저장합니다. 키는 캐릭터 웹 뷰에 전달되지 않습니다. 오디오 입력은 기기 내 인식을 우선하며 지원되지 않는 경우 Apple 음성 인식을 사용합니다. 오디오·대화가 외부로 전송되는 시점은 설정 화면에 안내합니다.

iOS판은 앱 안의 캐릭터와 대화에 집중합니다. 낭독 중에는 한글을 모음으로 분해해 ㅏ·ㅔ·ㅣ·ㅗ·ㅜ 입 모양을 연결합니다. Fish Audio는 단어별 시간 정보와 재생 위치를 사용합니다. 단어 내부의 모음 시점은 추정하며, Fish 시간 정보가 빠지면 전체 음성 길이를 기준으로 추정합니다.

## 캐릭터와 렌더러

빌드 준비 도구는 고정 버전의 한국어 하네스 배포 ZIP 해시를 확인하고 Live2D 렌더러와 고지를 준비합니다. 해시가 등록된 캐릭터 원본 파일은 사용자가 직접 가져옵니다. 캐릭터 WebView는 정점 데이터를 프레임당 한 번에 전송하고 UV 및 인덱스 버퍼를 재사용합니다.

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
