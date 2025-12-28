# 렌더링 및 LOD 시스템

> **문서 목적**: Mass AI의 시각적 표현 시스템과 LOD 최적화 이해
>
> **대상 독자**: 블루프린트 개발자부터 C++ 개발자까지

---

## 1. 왜 렌더링 최적화가 중요한가요?

### 문제 상황

몬스터 1000마리를 화면에 표시하려면 어떻게 해야 할까요?

**Actor 방식의 문제점**:
```
1000개의 Actor × 각각 드로우 콜 = 1000번의 드로우 콜 발생!

결과:
- GPU가 "아 힘들어..." 하면서 프레임 드랍
- 특히 모바일에서는 재앙 수준
```

**Mass AI의 해결책**:
```
같은 메시를 쓰는 몬스터들을 "묶어서" 한 번에 그리기!

결과:
- 1000개 몬스터 → 드로우 콜 1~10번으로 감소
- GPU "어? 할만한데?" → 프레임 유지
```

### 핵심 개념: 드로우 콜(Draw Call)이 뭔가요?

**비유**: GPU에게 "이거 그려줘"라고 요청하는 횟수예요.

```
드로우 콜이 많으면:
CPU: "GPU야 이거 그려"
GPU: "응"
CPU: "이것도 그려"
GPU: "응"
CPU: "이것도..."
GPU: "야 너무 많아! 기다려!"  ← 병목 발생!

드로우 콜이 적으면:
CPU: "GPU야 이거랑 이거랑 이거 한꺼번에 그려"
GPU: "오케이 쉬움!"  ← 효율적!
```

---

## 2. Mass AI의 3단계 표현 시스템

### 거리에 따라 다르게 그려요

Mass AI는 카메라와의 **거리에 따라** 다른 방식으로 몬스터를 표시해요.

```
┌──────────────────────────────────────────────────────────────────────┐
│                          카메라에서 보는 거리                          │
├──────────────────────────────────────────────────────────────────────┤
│                                                                       │
│  가까움 (0~50m)         중간 (50~200m)        멀리 (200m+)           │
│  ┌─────────────┐       ┌─────────────┐       ┌─────────────┐         │
│  │             │       │             │       │   ● ● ●     │         │
│  │   [복잡한   │       │  [간단한    │       │  ● ● ● ●   │         │
│  │   스켈레탈  │       │   Actor]    │       │   [ISM]     │         │
│  │   Actor]    │       │             │       │   ● ● ●     │         │
│  │             │       │             │       │             │         │
│  └─────────────┘       └─────────────┘       └─────────────┘         │
│                                                                       │
│  • 풀 애니메이션       • 간소화 애니        • 애니 없음              │
│  • GAS 활성화          • 기본 로직만        • 최소 로직              │
│  • ~100개까지          • ~500개까지         • 나머지 전부            │
│                                                                       │
│  비용: 높음             비용: 중간            비용: 매우 낮음         │
└──────────────────────────────────────────────────────────────────────┘
```

### 세 가지 표현 타입

| 타입 | 설명 | 비용 | 용도 |
|------|------|------|------|
| **HighResSpawnedActor** | 완전한 Actor (스켈레탈 메시, 풀 애니메이션) | 높음 | 가까운 몬스터 |
| **LowResSpawnedActor** | 간소화된 Actor (단순 메시, 기본 애니) | 중간 | 중간 거리 |
| **StaticMeshInstance (ISM)** | 인스턴스드 스태틱 메시 (애니 없음) | 매우 낮음 | 먼 거리 |

---

## 3. ISM (Instanced Static Mesh) - 핵심 최적화

### ISM이 뭐예요?

**쉬운 설명**: "같은 모양의 물체를 한 번에 그리는 기술"

**비유**: 도장 찍기

```
일반 Actor 렌더링:
🎨 "첫 번째 몬스터 그리기" (드로우 콜 1)
🎨 "두 번째 몬스터 그리기" (드로우 콜 2)
🎨 "세 번째 몬스터 그리기" (드로우 콜 3)
...
🎨 "천 번째 몬스터 그리기" (드로우 콜 1000)

ISM 렌더링:
🔖 "이 모양을 이 위치들에 다 찍어줘: [위치1, 위치2, ... 위치1000]"
   (드로우 콜 1번!)
```

### ISM의 성능 이점

| 항목 | 개별 Actor | ISM | 차이 |
|------|-----------|-----|------|
| **드로우 콜** | 1000번 | 1~10번 | **100배 감소** |
| **CPU 오버헤드** | Actor마다 Tick | Transform만 업데이트 | **10배 감소** |
| **메모리** | Actor당 ~2KB | 인스턴스당 ~64B | **30배 감소** |

### ISM의 한계

하지만 ISM에는 제약이 있어요:

```
ISM으로 할 수 있는 것:
✅ 위치/회전/스케일 변경
✅ 머티리얼 파라미터 변경 (Custom Data)
✅ 간단한 색상 변형

ISM으로 할 수 없는 것:
❌ 스켈레탈 애니메이션
❌ 복잡한 물리 상호작용
❌ 개별 Actor 로직

그래서 "가까운 몬스터 = Actor", "먼 몬스터 = ISM" 전략을 쓰는 거예요!
```

---

## 4. LOD (Level of Detail) 시스템

### LOD가 뭐예요?

**쉬운 설명**: "거리에 따라 디테일 수준을 조절하는 시스템"

```
가까울 때: 고해상도, 풀 기능 (High)
중간 거리: 중간 해상도, 일부 기능 (Medium)
멀 때: 저해상도, 최소 기능 (Low)
화면 밖: 안 그림 (Off)
```

### Mass AI의 LOD 레벨

```cpp
// 4단계 LOD
EMassLOD::High    → 가장 가까움 (0~50m)
EMassLOD::Medium  → 중간 거리 (50~200m)
EMassLOD::Low     → 먼 거리 (200m+)
EMassLOD::Off     → 화면 밖 또는 매우 멀리
```

### LOD별 설정 예시

```
┌─────────────────────────────────────────────────────────────────────┐
│                    1000마리 규모 권장 LOD 설정                        │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  LOD Level    거리          최대 개수     표현 방식                  │
│  ─────────────────────────────────────────────────────────────────  │
│  High         0~50m         100개        HighRes Actor              │
│                                          (스켈레탈 + 풀 애니)       │
│                                                                      │
│  Medium       50~200m       500개        LowRes Actor               │
│                                          (간단 메시 + 기본 애니)    │
│                                                                      │
│  Low          200m+         5000개       ISM                        │
│                                          (스태틱 메시, 애니 없음)   │
│                                                                      │
│  Off          화면 밖       무제한       안 그림                     │
│                                          (로직만 최소 처리)         │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 5. 에디터에서 설정하기

### MassVisualizationTrait 설정

**Step 1: EntityConfigAsset에서 MassVisualizationTrait 추가**

```
[MassVisualizationTrait]
├─ High Res Template Actor
│   └─ BP_Monster_HighRes  ← 스켈레탈 메시 + 풀 애니메이션
│
├─ Low Res Template Actor
│   └─ BP_Monster_LowRes   ← 간소화된 메시 + 기본 애니메이션
│
└─ Static Mesh Instance Desc
    ├─ Mesh: SM_Monster_Billboard  ← 매우 단순한 메시
    ├─ Cast Shadow: false          ← 그림자 꺼서 성능 절약
    └─ Custom Data: [색상 변형값]
```

**Step 2: LOD 파라미터 설정**

```
[LOD Parameters]
├─ Base LOD Distance
│   ├─ [0] High: 0cm        ← 0m부터
│   ├─ [1] Medium: 5000cm   ← 50m부터
│   ├─ [2] Low: 20000cm     ← 200m부터
│   └─ [3] Off: 50000cm     ← 500m부터
│
├─ LOD Max Count
│   ├─ [0] High: 100        ← High LOD 최대 100개
│   ├─ [1] Medium: 500      ← Medium LOD 최대 500개
│   ├─ [2] Low: 5000        ← Low LOD 최대 5000개
│   └─ [3] Off: 무제한
│
└─ Buffer Hysteresis: 15%   ← LOD 전환 떨림 방지
```

### High/Low Res Actor 설정

**High Res Actor (가까운 몬스터용)**:
```
BP_Monster_HighRes
├─ SkeletalMeshComponent
│   └─ 고해상도 스켈레탈 메시
├─ AnimInstance
│   └─ 풀 애니메이션 블루프린트
├─ CapsuleComponent
│   └─ 콜리전
└─ MassAgentComponent
    └─ Mass Entity와 Actor 연결
```

**Low Res Actor (중간 거리용)**:
```
BP_Monster_LowRes
├─ SkeletalMeshComponent 또는 StaticMeshComponent
│   └─ 간소화된 메시
├─ AnimInstance (선택적)
│   └─ 기본 애니메이션만
└─ MassAgentComponent
    └─ Mass Entity와 Actor 연결
```

---

## 6. LOD 전환 시 일어나는 일

### 몬스터가 가까워질 때

```
시나리오: 멀리 있던 몬스터가 플레이어에게 다가옴

[1] 500m 거리 (Off)
    상태: 화면에 안 그려짐
    로직: 최소 처리만

        ↓ 플레이어에게 접근 ↓

[2] 200m 거리 (Low → ISM)
    상태: ISM으로 렌더링 시작
    변화: StaticMeshInstance 활성화

        ↓ 더 가까이 접근 ↓

[3] 50m 거리 (Medium → LowRes Actor)
    상태: Low Res Actor 스폰
    변화: ISM → Actor로 전환
          간단한 애니메이션 시작

        ↓ 아주 가까이 접근 ↓

[4] 10m 거리 (High → HighRes Actor)
    상태: High Res Actor로 교체
    변화: Low Actor → High Actor
          풀 애니메이션 활성화
          GAS 컴포넌트 활성화
```

### 히스테리시스 (Hysteresis) - 떨림 방지

LOD 경계에서 앞뒤로 왔다갔다하면 계속 전환이 일어나요. 이걸 방지하는 게 히스테리시스예요.

```
문제 상황 (히스테리시스 없을 때):
몬스터가 49m ↔ 51m를 왔다갔다 하면...
  → High ↔ Medium 계속 전환
  → Actor 스폰/디스폰 반복
  → 성능 저하!

해결책 (히스테리시스 15%):
  전환 기준: 50m
  실제 전환:
    High → Medium: 50m + 15% = 57.5m에서
    Medium → High: 50m - 15% = 42.5m에서

  결과: 42.5m~57.5m 사이에서는 전환 안 함!
```

---

## 7. 실전 최적화 팁

### 7.1 ISM 최적화

**메시 단순화**
```
원본 몬스터 메시: 10,000 삼각형
ISM용 메시: 100~500 삼각형만!

왜? 멀리 있으면 어차피 디테일 안 보여요.
```

**그림자 비활성화**
```cpp
// ISM 설정에서
MeshDesc.bCastShadow = false;

// 수천 개의 그림자 계산 → 0개!
// 성능 대폭 향상
```

**머티리얼 공유**
```
❌ 나쁜 예: 몬스터 100종류 × 각각 다른 머티리얼 = 100번 드로우 콜

✅ 좋은 예: 1개 머티리얼 + Custom Data로 색상 변형 = 1번 드로우 콜
```

### 7.2 Actor 풀링 최적화

Actor를 매번 생성/삭제하면 성능이 떨어져요. **풀링**을 써서 미리 만들어두고 재사용하세요.

```cpp
// 게임 시작 시 풀 준비
void AMyGameMode::BeginPlay()
{
    UMassRepresentationSubsystem* RepSubsystem =
        GetWorld()->GetSubsystem<UMassRepresentationSubsystem>();

    // High Res Actor 100개 미리 생성
    int16 HighResIndex = RepSubsystem->FindOrAddTemplateActor(BP_Monster_HighRes);
    RepSubsystem->SetActorPoolSize(HighResIndex, 120);  // 여유분 20개 추가

    // Low Res Actor 500개 미리 생성
    int16 LowResIndex = RepSubsystem->FindOrAddTemplateActor(BP_Monster_LowRes);
    RepSubsystem->SetActorPoolSize(LowResIndex, 600);   // 여유분 100개 추가
}
```

### 7.3 LOD 개수 제한

**왜 개수 제한이 필요한가요?**

갑자기 플레이어 앞에 1000마리가 나타나면 High LOD가 1000개가 될 수 있어요. 개수 제한으로 이걸 방지해요.

```cpp
// 권장 설정
LODParams.LODMaxCount[EMassLOD::High] = 100;    // High는 100개까지만
LODParams.LODMaxCount[EMassLOD::Medium] = 500;  // Medium은 500개까지만
LODParams.LODMaxCount[EMassLOD::Low] = 5000;    // Low는 5000개까지
```

**개수 초과 시 어떻게 되나요?**

가장 가까운 것들이 우선순위를 받아요:
```
상황: High LOD 150개 필요, 제한 100개

결과:
- 가장 가까운 100개 → High LOD (Actor)
- 나머지 50개 → Medium LOD로 강등 (덜 자세하게)
```

---

## 8. 디버깅 방법

### 콘솔 명령어

```
// 에디터에서 ~ 키로 콘솔 열고:

// ISM 통계 보기
stat SceneRendering

// Mass Entity 표현 디버그
Mass.Debug.Representation 1

// LOD 상태 시각화
Mass.Debug.LOD 1
```

### LOD 색상으로 확인하기

```cpp
// 디버그 모드에서 LOD별 색상 표시
#if WITH_EDITOR
void DrawLODDebug()
{
    // High LOD: 초록색 구
    // Medium LOD: 노란색 구
    // Low LOD: 빨간색 구
    // Off: 검정색 구 (또는 표시 안 함)
}
#endif
```

### 성능 확인 체크리스트

```
□ 드로우 콜 확인: stat SceneRendering
  - DrawPrimitive Calls < 3000 권장

□ High LOD 개수 확인
  - 100개 이하 유지

□ ISM 인스턴스 확인
  - 같은 메시가 묶여서 렌더링되는지

□ Actor 풀 상태 확인
  - 스폰/디스폰이 반복되는지
```

---

## 9. 1000~5000 마리 규모 권장 설정

### 전체 아키텍처

```
┌─────────────────────────────────────────────────────────────────────┐
│                     5000 마리 몬스터 렌더링 전략                      │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│   [플레이어]                                                         │
│       ●                                                              │
│       │                                                              │
│   ────┼────────────────────────────────────────────────────────     │
│       │                                                              │
│   0m  │  High LOD (최대 100개)                                      │
│       │  • HighRes Actor                                            │
│       │  • 스켈레탈 메시 + 풀 애니                                  │
│       │  • GAS 활성화                                               │
│       │                                                              │
│  50m  ├────────────────────────────────────────                     │
│       │  Medium LOD (최대 500개)                                    │
│       │  • LowRes Actor                                             │
│       │  • 간소화 메시 + 기본 애니                                  │
│       │                                                              │
│ 200m  ├────────────────────────────────────────                     │
│       │  Low LOD (최대 5000개)                                      │
│       │  • ISM (Instanced Static Mesh)                              │
│       │  • 스태틱 메시, 애니 없음                                   │
│       │  • 1~10번 드로우 콜로 처리!                                 │
│       │                                                              │
│ 500m+ │  Off (무제한)                                               │
│       │  • 렌더링 안 함                                             │
│       │  • 최소 로직만 처리                                         │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### 최종 권장 설정값

```cpp
// LOD 거리 (cm 단위)
BaseLODDistance[High] = 0;
BaseLODDistance[Medium] = 5000;     // 50m
BaseLODDistance[Low] = 20000;       // 200m
BaseLODDistance[Off] = 50000;       // 500m

// LOD별 최대 개수
LODMaxCount[High] = 100;
LODMaxCount[Medium] = 500;
LODMaxCount[Low] = 5000;
LODMaxCount[Off] = INT_MAX;

// 히스테리시스
BufferHysteresisOnDistancePercentage = 15.0f;

// 화면 밖 업데이트 주기
NotVisibleUpdateRate = 4;  // 4프레임마다 (15fps 정도)
```

---

## 10. 흔한 실수와 해결책

### 실수 1: ISM 메시가 너무 복잡함

```
❌ 문제: ISM 메시가 10,000 삼각형
   결과: ISM인데도 느림

✅ 해결: ISM용 별도 저폴리 메시 준비 (100~500 삼각형)
```

### 실수 2: High LOD 개수 제한 안 함

```
❌ 문제: LODMaxCount[High]를 설정 안 함
   결과: 플레이어 주변에 몬스터 많으면 1000개 Actor 스폰!

✅ 해결: LODMaxCount[High] = 100으로 제한
```

### 실수 3: Actor 풀 크기가 작음

```
❌ 문제: 풀 크기 50인데 High LOD 100개 필요
   결과: 나머지 50개 런타임 스폰 → 스터터링

✅ 해결: 풀 크기 = LODMaxCount + 여유분(20%)
```

### 실수 4: 히스테리시스 안 씀

```
❌ 문제: BufferHysteresis = 0
   결과: LOD 경계에서 Actor 계속 스폰/디스폰

✅ 해결: BufferHysteresis = 10~20%
```

---

## 11. 다음 단계

렌더링과 LOD 시스템을 이해했다면, 다음 문서에서 애니메이션 통합을 살펴보겠습니다:

- **다음**: [04_AnimationIntegration.md](04_AnimationIntegration.md) - 스켈레탈 애니메이션 통합 및 거리별 애니메이션 전략

### 이 문서에서 배운 것

1. **3단계 표현 시스템**: HighRes Actor → LowRes Actor → ISM
2. **ISM의 장점**: 드로우 콜 100배 감소
3. **LOD 시스템**: 거리에 따른 자동 최적화
4. **히스테리시스**: LOD 전환 떨림 방지
5. **Actor 풀링**: 스폰/디스폰 오버헤드 제거
6. **개수 제한**: 폭발적 스폰 방지
