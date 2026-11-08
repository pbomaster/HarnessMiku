# 개인 Mac에서 답변 완료 푸시 받기

DeepSeek 로그인을 이용한 채팅에는 이 서버가 필요하지 않습니다. 원격 푸시를 켠 경우에만 iPhone이 이 서버에 답변 생성을 맡깁니다. 대화와 요청 인증에 필요한 DeepSeek 세션 또는 API 키가 전송되므로 **본인만 관리하는 서버**를 사용하세요. Fish 키와 Apple 로그인 정보는 전달하지 않습니다.

1. 개발자 계정의 Certificates, Identifiers & Profiles에서 앱의 실제 Bundle ID에 **Push Notifications**를 활성화합니다. Xcode의 Signing & Capabilities에서 동일한 팀과 명시적인 Bundle ID를 사용해 개발 프로필을 갱신하세요. 프로젝트는 개발용 `aps-environment` entitlement를 포함합니다. APNs를 쓸 수 없는 서명 팀은 타깃의 **Code Signing Entitlements** 값을 비운 뒤 직접 채팅과 로컬 알림을 쓸 수 있습니다.
2. 개발자 계정에서 **Apple Push Notification service (APNs)**용 인증 키를 생성합니다. 개발 환경과 해당 앱의 topic이 허용된 키여야 합니다. .p8은 개인 Mac에만 보관하세요. 아래 명령은 Mac 터미널에서 실행합니다. 예시의 팀, 키 ID, 파일 경로, Bundle ID를 본인 값으로 바꾸세요. Node.js 22 이상이 필요하며 npm 패키지 설치는 필요하지 않습니다.

```bash
cd "/프로젝트/폴더/Relay"
export APNS_TEAM="본인의 Team ID"
export APNS_KID="본인의 APNs Key ID"
export APNS_TOPIC="Xcode에 지정한 Bundle ID"
export APNS_P8="$HOME/Keys/AuthKey_본인키.p8"
export APNS_ENV="development"
export MIKU_PAIR_KEY="$(openssl rand -hex 32)"
printf %s "$MIKU_PAIR_KEY" | pbcopy
node server.mjs
```

3. 서버는 Mac의 `127.0.0.1:8787`에만 바인딩합니다. 그 포트로 전달하는 **아이폰에서 신뢰하는 HTTPS 주소**를 준비하세요. 예를 들어 두 기기에서 같은 개인 Tailscale 네트워크에 접속한 상태로 Mac에서 `tailscale serve --bg http://127.0.0.1:8787`를 실행하고 표시된 HTTPS 주소를 사용할 수 있습니다. 인증서 경고를 무시하거나 HTTP 포트를 그대로 노출하지 마세요. 기기에서 개인 LAN 호스트에 접속할 때는 iOS 설정의 로컬 네트워크 접근을 허용해야 할 수 있습니다. Mac은 요청 처리 중 깨어 있고 네트워크에 연결되어 있어야 합니다.
4. 아이폰에서 **설정 → 답변이 오면 알림**을 켜고 허용합니다. **개인 중계로 원격 푸시 받기**를 켜고 HTTPS 주소와 2단계에서 복사한 중계 연결 키를 입력해 저장하세요. 같은 연결 키를 계속 쓸 때에는 Mac에 안전하게 보관하고 재실행할 때 동일한 값을 설정하세요. APNs용 .p8을 앱 프로젝트나 아이폰에 넣지 마세요.
5. 새 메시지를 보내고 홈 화면으로 이동합니다. 중계는 실제 응답 생성이 성공한 다음 결과를 저장하고 APNs로 알림을 보냅니다. iOS 알림을 누르면 앱이 열리고 해당 작업이 현재 대화에 남아 있으면 답변을 가져옵니다. 앱을 연 상태에서는 같은 답변에 배너를 띄우지 않습니다.

## 보관과 실패 처리
- 요청 자격 증명과 질문 본문은 중계 프로세스 메모리에서만 사용합니다. 답변은 Mac 사용자 전용 폴더 `~/Library/Application Support/Harness Miku/ReplyRelay`에 파일 모드 0600으로 보관합니다. 조회 기한은 24시간이며 만료 파일은 조회할 때와 서버의 주기적 정리 시 삭제합니다.
- 같은 작업 ID를 재전송할 때 이미 처리 중이거나 응답이 남아 있으면 기존 작업을 사용합니다. 중계 재시작 시 완료된 결과는 복구되지만 실행 중이던 작업은 다시 보내야 할 수 있습니다. 중계가 실패했다고 앱이 다른 인증 방식으로 몰래 재요청하지 않습니다.
- APNs 전송이 실패해도 답변은 조회할 수 있습니다. 알림이 오지 않으면 iOS 알림 설정, 집중 모드, Mac의 APNs 환경과 Team·Key·Topic, HTTPS 연결, 앱의 Push Notifications 프로필을 확인하세요. App Store 등록은 필요하지 않습니다.
