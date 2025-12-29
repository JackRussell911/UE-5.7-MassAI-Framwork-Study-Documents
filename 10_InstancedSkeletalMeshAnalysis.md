# Instanced Skeletal Mesh + Mass AI 통합 분석

> **문서 목적**: UE 5.7의 Instanced Skeletal Mesh Component와 Mass AI 병행 활용 가능성 검토
>
> **난이도**: ★★★★☆ (중급-고급)
>
> **작성일**: 2025-12-29

---

## 들어가며

### 이 문서를 읽어야 하는 분

```
당신이 이런 고민을 하고 있다면:

"Mass AI로 1000마리 몬스터를 만들었는데,
 멀리 있는 애들도 애니메이션이 있으면 좋겠어요.
 Static Mesh ISM은 애니메이션이 안 되잖아요..."

"UE 5.7에 Instanced Skeletal Mesh가 새로 나왔다던데,
 Mass AI랑 같이 쓸 수 있나요?"

→ 이 문서가 그 질문에 답해드릴게요!
```

### 결론 먼저 말하면

```
┌─────────────────────────────────────────────────────────────┐
│                        핵심 결론                             │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│   UInstancedSkinnedMeshComponent  +  Mass AI                 │
│                                                              │
│           ⚠️ 실험적 기능              ❌ 통합 없음           │
│                                                              │
│   ──────────────────────────────────────────────────────    │
│                                                              │
│   🟡 기술적으로 커스텀 통합 가능                              │
│   🔴 하지만 현시점에서 권장하지 않음                          │
│   ✅ 기존 LOD 하이브리드 (Actor + Static ISM)로 충분!        │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

왜 그런지, 어떤 대안이 있는지 상세히 알아볼게요!

---

## 1. UInstancedSkinnedMeshComponent란?

### 1.1 개념 설명

**한 줄 요약**: "같은 스켈레탈 메시를 수천 개 그리는데, 각각 다른 애니메이션을 재생할 수 있어요!"

기존에는 스켈레탈 메시(캐릭터, 몬스터 등)를 여러 개 그리려면 각각 Actor로 만들어야 했어요.
Actor 하나당 SkeletalMeshComponent 하나, 그러다 보니 1000개 그리면 1000개의 Actor가 필요했죠.

```
기존 방식 (SkeletalMeshComponent):
┌─────────────────────────────────────────────────────────────┐
│                                                              │
│   Monster1 (Actor)     Monster2 (Actor)     Monster3 (Actor) │
│   ├─ SKMeshComp        ├─ SKMeshComp        ├─ SKMeshComp    │
│   └─ AnimBP            └─ AnimBP            └─ AnimBP        │
│                                                              │
│   CPU: 각각 Tick      GPU: 각각 Draw Call                    │
│   = 1000마리면 너무 무거움!                                   │
│                                                              │
└─────────────────────────────────────────────────────────────┘

새로운 방식 (InstancedSkinnedMeshComponent):
┌─────────────────────────────────────────────────────────────┐
│                                                              │
│   InstancedSkinnedMeshComponent (하나)                       │
│   ├─ Instance 0: Transform + AnimIndex 0 (Idle)             │
│   ├─ Instance 1: Transform + AnimIndex 1 (Walk)             │
│   ├─ Instance 2: Transform + AnimIndex 0 (Idle)             │
│   └─ ... (수천 개)                                          │
│                                                              │
│   CPU: 한 번 업데이트    GPU: 배치 렌더링                    │
│   = 훨씬 효율적!                                             │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 1.2 주요 특징

| 특징 | 설명 |
|------|------|
| **다중 인스턴스** | 동일 메시를 수천 개 렌더링 |
| **개별 애니메이션** | 인스턴스마다 다른 애니메이션 인덱스 |
| **AnimBank 시스템** | 애니메이션을 사전 컴파일하여 사용 |
| **GPU 인스턴스** | GPU에서만 존재하는 인스턴스 지원 |
| **커스텀 데이터** | 인스턴스별 float 값 (머티리얼 파라미터용) |
| **컬링 거리** | Start/End 거리 설정 가능 |

### 1.3 AnimBank가 뭔가요?

AnimBank는 **미리 구워놓은 애니메이션 데이터**예요.

```
일반 AnimBP:
├── 런타임에 본(Bone) 트랜스폼 계산
├── 블렌딩, IK, 모든 것 실시간 처리
└── CPU 비용 높음

AnimBank:
├── 에디터에서 미리 애니메이션 시퀀스들을 "컴파일"
├── 본 트랜스폼이 이미 계산되어 있음
├── 런타임에는 인덱스만 지정하면 됨
└── CPU 비용 낮음 (대신 동적 블렌딩 제한)
```

**AnimBank 워크플로우:**
1. 사용할 애니메이션 시퀀스들 선택 (Idle, Walk, Run, Attack...)
2. AnimBank 에셋 생성 및 컴파일
3. InstancedSkinnedMeshComponent에 AnimBank 연결
4. 런타임에 인스턴스별로 AnimationIndex 설정

### 1.4 현재 상태: ⚠️ 실험적

**파일 위치:**
```
Engine/Source/Runtime/Engine/Classes/Components/InstancedSkinnedMeshComponent.h
```

**코드에서 발견된 경고:**
```cpp
UE_EXPERIMENTAL(5.6, "This class is currently extremely experimental
                      and should not be used at this time.")
```

**의미:**
- UE 5.6에서 처음 도입
- UE 5.7에서도 여전히 "extremely experimental" (매우 실험적)
- Epic에서 공식적으로 **프로덕션 사용을 권장하지 않음**
- API가 변경될 수 있음
- 버그가 있을 수 있음

### 1.5 주요 API

```cpp
// 인스턴스 추가
FPrimitiveInstanceId AddInstance(
    const FTransform& InstanceTransform,
    int32 AnimationIndex,          // AnimBank 내 애니메이션 인덱스
    bool bWorldSpace = false
);

// 배치로 여러 인스턴스 추가
TArray<FPrimitiveInstanceId> AddInstances(
    const TArray<FTransform>& Transforms,
    const TArray<int32>& AnimationIndices,
    bool bShouldReturnIds,
    bool bWorldSpace = false
);

// 인스턴스 제거
bool RemoveInstance(FPrimitiveInstanceId InstanceId);
void ClearInstances();

// 데이터 조회/수정
bool GetInstanceTransform(FPrimitiveInstanceId, FTransform& OutTransform);
bool GetInstanceAnimationIndex(FPrimitiveInstanceId, int32& OutIndex);
bool SetCustomDataValue(FPrimitiveInstanceId, int32 Index, float Value);

// 컬링 설정
void SetCullDistances(int32 StartCullDistance, int32 EndCullDistance);
```

### 1.6 제한사항

```
⚠️ 알아둬야 할 제한사항:

1. AnimBank 사전 컴파일 필요
   └─ 런타임에 새 애니메이션 추가 불가
   └─ 애니메이션 변경 시 AnimBank 재빌드 필요

2. 인스턴스별 본 제어 불가
   └─ IK, 래그돌, 물리 시뮬레이션 등 불가
   └─ AnimBank 인덱스만 지정 가능

3. 동적 블렌딩 제한
   └─ A → B 애니메이션 전환 시 블렌딩이 제한적
   └─ AnimBP의 스테이트 머신처럼 유연하지 않음

4. GPU-Only 인스턴스 제한
   └─ 에디터 선택/히트 테스트 불가
   └─ 디버깅이 어려울 수 있음

5. 레이 트레이싱 제한
   └─ 동적 레이 트레이싱 인스턴스 미지원
```

---

## 2. Mass AI 표현 시스템 현황

### 2.1 현재 지원하는 표현 타입

Mass AI는 엔티티를 화면에 어떻게 보여줄지 4가지 방식으로 관리해요:

```cpp
enum class EMassRepresentationType : uint8
{
    HighResSpawnedActor,      // 풀 Actor (스켈레탈 애니메이션 OK)
    LowResSpawnedActor,       // 간소화 Actor
    StaticMeshInstance,       // ISM (Static Mesh만!)
    None,                     // 안 보임
};
```

**LOD별 표현 매핑:**
```
┌────────────────────────────────────────────────────────────┐
│  LOD Level    │    Representation       │   애니메이션     │
├────────────────────────────────────────────────────────────┤
│  EMassLOD::High    │ HighResSpawnedActor │ ✅ 풀 AnimBP   │
│  EMassLOD::Medium  │ LowResSpawnedActor  │ ✅ 간소화 Anim │
│  EMassLOD::Low     │ StaticMeshInstance  │ ❌ 없음!       │
│  EMassLOD::Off     │ None                │ ❌ 없음        │
└────────────────────────────────────────────────────────────┘
```

### 2.2 왜 스켈레탈 인스턴싱이 없나요?

**단순한 이유:** Mass AI가 만들어질 때 `UInstancedSkinnedMeshComponent`가 없었어요!

Mass AI의 ISM 시스템은 `UInstancedStaticMeshComponent`를 기반으로 설계되었어요.
스켈레탈 메시 인스턴싱은 고려 대상이 아니었죠.

```cpp
// Mass AI의 ISM 구성 구조체
struct FMassStaticMeshInstanceVisualizationMeshDesc
{
    UStaticMesh* Mesh;  // Static Mesh만!
    TArray<UMaterialInterface*> MaterialOverrides;

    // 확장 포인트가 있긴 해요:
    TSubclassOf<UInstancedStaticMeshComponent> ISMComponentClass;
    //           ↑ 이게 핵심! 하지만 InstancedStaticMeshComponent 상속만 받음
};
```

### 2.3 핵심 발견: 공식 통합 없음

UE 5.7 소스 코드를 전수 조사한 결과:

```
❌ EMassRepresentationType에 SkeletalMeshInstance 없음
❌ MassRepresentation 플러그인에 스켈레탈 관련 코드 없음
❌ InstancedSkinnedMeshComponent와 Mass를 연결하는 코드 없음
❌ Epic의 공식 통합 계획 문서 없음
```

**결론:** 두 시스템은 **완전히 분리**되어 있어요.

---

## 3. 통합 가능성 분석

### 3.1 커스텀 통합이 가능한 이유

Mass AI 표현 시스템에는 확장 포인트가 있어요:

```cpp
struct FMassStaticMeshInstanceVisualizationMeshDesc
{
    // ...

    // 🔑 확장 포인트 1: 커스텀 컴포넌트 클래스
    TSubclassOf<UInstancedStaticMeshComponent> ISMComponentClass;

    // 🔑 확장 포인트 2: 외부 ID 추적
    bool bRequiresExternalInstanceIDTracking;
};
```

이론적으로 `UInstancedStaticMeshComponent`를 상속받는 래퍼를 만들어서
내부적으로 `UInstancedSkinnedMeshComponent`를 사용하게 할 수 있어요.

### 3.2 옵션 A: ISMComponentClass 래퍼 (최소 수정)

**접근법:**
1. `UMassSkeletalMeshWrapper` 클래스 생성
2. `UInstancedStaticMeshComponent` 상속
3. 내부에서 `UInstancedSkinnedMeshComponent` 위임

```cpp
// 개념적 코드 (실제 구현은 더 복잡)
UCLASS()
class UMassSkeletalMeshWrapper : public UInstancedStaticMeshComponent
{
    GENERATED_BODY()

private:
    UPROPERTY()
    UInstancedSkinnedMeshComponent* InternalSkinnedMesh;

public:
    // Mass AI가 호출하는 API를 오버라이드
    virtual int32 AddInstance(const FTransform& Transform) override
    {
        // 내부적으로 스켈레탈 인스턴스 추가
        return InternalSkinnedMesh->AddInstance(Transform, DefaultAnimIndex);
    }

    virtual bool UpdateInstanceTransform(int32 Index, const FTransform& Transform) override
    {
        // 스켈레탈 인스턴스 업데이트
        return InternalSkinnedMesh->UpdateInstanceTransform(...);
    }
};
```

**장점:**
- Mass AI 코어 수정 불필요
- 기존 Trait 시스템 활용 가능

**단점:**
- API 불일치 해결 복잡
- 애니메이션 인덱스 전달 방법 필요
- 유지보수 부담

### 3.3 옵션 B: 새로운 RepresentationType 추가 (확장 수정)

**접근법:**
1. `EMassRepresentationType::SkeletalMeshInstance` 추가
2. 전용 Fragment, Processor, Trait 구현
3. Mass AI 플러그인 포크 또는 확장

```cpp
// 새로운 표현 타입
enum class EMassRepresentationType : uint8
{
    HighResSpawnedActor,
    LowResSpawnedActor,
    StaticMeshInstance,
    SkeletalMeshInstance,   // 새로 추가!
    None,
};

// 새로운 Fragment
USTRUCT()
struct FMassSkeletalRepresentationFragment : public FMassFragment
{
    GENERATED_BODY()

    int32 SkeletalMeshDescHandle;
    int32 CurrentAnimationIndex;
    FPrimitiveInstanceId InstanceId;
};

// 새로운 Processor
UCLASS()
class UMassUpdateSkeletalISMProcessor : public UMassProcessor
{
    // 스켈레탈 인스턴스 Transform + AnimIndex 업데이트
};
```

**장점:**
- 깔끔한 아키텍처
- 애니메이션 인덱스 자연스럽게 관리

**단점:**
- Mass AI 플러그인 수정/포크 필요
- 엔진 업데이트 시 머지 충돌 위험
- 개발/유지보수 비용 높음

### 3.4 옵션별 비교

```
┌─────────────────────────────────────────────────────────────┐
│                    옵션 A vs 옵션 B                          │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│             옵션 A (래퍼)         옵션 B (확장)              │
│             ────────────         ────────────              │
│ 수정 범위:   프로젝트 내           Mass 플러그인            │
│ 복잡도:     🟡 중간               🔴 높음                   │
│ 유지보수:   🟡 API 불일치          🔴 머지 충돌              │
│ 깔끔함:     🟡 해킹스러움          ✅ 아키텍처적             │
│ 리스크:     🟡 중간               🔴 높음                   │
│                                                              │
│ 권장:       실험/프로토타입       장기 프로젝트              │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## 4. 권장 전략

### 4.1 현시점 권장: 기존 LOD 하이브리드 유지

**왜 커스텀 통합을 권장하지 않나요?**

```
1. UInstancedSkinnedMeshComponent가 실험적
   └─ Epic도 "프로덕션에 쓰지 마세요"라고 해요
   └─ UE 5.8에서 API가 바뀔 수 있어요

2. AnimBank 제한이 뱀서 스타일에 맞지 않을 수 있어요
   └─ 동적 행동에는 실시간 블렌딩이 필요
   └─ AnimBank는 사전 정의된 시퀀스만 재생

3. 개발 비용 대비 효과가 낮아요
   └─ 커스텀 통합에 수주~수개월 소요 가능
   └─ 기존 LOD 시스템으로도 1000-5000마리 처리 가능

4. 공식 지원이 오면 그게 더 나아요
   └─ Epic이 5.8+에서 통합해줄 수도 있어요
   └─ 커스텀 코드 버리고 공식 코드로 마이그레이션?
```

### 4.2 기존 LOD 하이브리드가 충분한 이유

```
1000-5000마리 뱀서 스타일 권장 설정:

┌─────────────────────────────────────────────────────────────┐
│                        플레이어 기준 거리                    │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│   ┌─────────────┐   ┌─────────────┐   ┌─────────────────┐   │
│   │  High LOD   │   │ Medium LOD  │   │    Low LOD      │   │
│   │   (0-50m)   │   │  (50-200m)  │   │    (200m+)      │   │
│   ├─────────────┤   ├─────────────┤   ├─────────────────┤   │
│   │   ~100개    │   │   ~500개    │   │   나머지 전부   │   │
│   │             │   │             │   │                 │   │
│   │  • Actor    │   │  • LowActor │   │  • Static ISM   │   │
│   │  • 풀 AnimBP│   │  • 간소 Anim│   │  • 애니메이션 X │   │
│   │  • GAS OK   │   │  • 제한 로직│   │  • 최소 로직    │   │
│   └─────────────┘   └─────────────┘   └─────────────────┘   │
│                                                              │
│   플레이어 눈에 보이는 건 대부분 High/Medium                 │
│   Low LOD는 배경처럼 느껴짐 → 애니메이션 없어도 OK!          │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

**핵심 인사이트:**
> "플레이어가 실제로 인식하는 건 가까운 몬스터들이에요.
> 200m 이상 떨어진 몬스터가 애니메이션이 있든 없든,
> 그걸 눈치채는 플레이어는 거의 없어요!"

### 4.3 성능 비교

```
기존 LOD 하이브리드 (권장):
├── High Actor 100개: ~2ms CPU
├── Low Actor 500개: ~1ms CPU
├── Static ISM 4400개: ~0.3ms CPU
└── 총합: ~3.3ms → 60fps 충분!

커스텀 스켈레탈 ISM 통합 (권장X):
├── 개발 시간: 수주~수개월
├── 실험적 기능 리스크
├── 성능 개선: ~0.5ms? (측정 불가)
└── 결론: 비용 대비 효과 낮음
```

---

## 5. 미래 전망

### 5.1 모니터링 항목

UE 5.8+ 릴리스 노트에서 확인할 것:

```
□ UInstancedSkinnedMeshComponent 정식 출시 여부
  └─ "experimental" 태그 제거?

□ Epic의 Mass AI + 스켈레탈 인스턴싱 공식 통합
  └─ EMassRepresentationType에 새 타입 추가?

□ AnimBank 런타임 블렌딩 지원
  └─ 동적 전환 가능해지면 활용도 증가

□ City Sample / Fortnite에서의 활용 사례
  └─ Epic 내부 프로젝트에서 먼저 검증될 가능성
```

### 5.2 잠재적 활용 시나리오 (실험적)

만약 정말 스켈레탈 ISM을 시도해보고 싶다면:

**시나리오: 초원거리 스켈레탈 LOD**

```
원거리 (200m+)에서:
├── 기존: Static Mesh ISM (애니메이션 없음)
└── 새로운: Instanced Skeletal Mesh (단순 Walk 루프)
```

**구현 아이디어:**
1. Mass Entity와 별도로 `UInstancedSkinnedMeshComponent` 직접 관리
2. Mass Entity Transform을 주기적으로 복사 (10Hz?)
3. AnimBank에는 Idle, Walk 2개 애니메이션만 포함
4. LOD 전환 시 Mass ISM ↔ Skeletal ISM 전환

**주의사항:**
- 두 시스템 간 Transform 동기화 오버헤드
- AnimBank 빌드/관리 복잡성
- 실험적 기능 사용 리스크
- LOD 경계에서 시각적 팝핑 가능성

---

## 6. 결론 및 체크리스트

### 6.1 핵심 메시지

```
┌─────────────────────────────────────────────────────────────┐
│                                                              │
│   "Instanced Skeletal Mesh + Mass AI 통합은                 │
│    기술적으로 가능하지만, 현시점에서 권장하지 않습니다."      │
│                                                              │
│   ✅ 기존 Mass AI LOD 시스템으로 1000-5000마리 충분히 처리   │
│   ✅ Actor (근거리) + Static ISM (원거리)가 더 안정적        │
│   ⏳ UE 5.8+ 정식 지원을 기다리는 것이 현명                  │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 6.2 의사결정 가이드

```
"스켈레탈 인스턴싱이 필요한가요?"

질문 1: 원거리 몬스터에 애니메이션이 꼭 필요한가요?
├─ YES → 질문 2로
└─ NO → ✅ 기존 LOD 하이브리드 사용

질문 2: 프로덕션 프로젝트인가요?
├─ YES → ⚠️ 실험적 기능 리스크 감수 가능?
│        ├─ YES → 질문 3으로
│        └─ NO → ✅ 기존 LOD 하이브리드 사용
└─ NO (프로토타입) → 🟡 시도해볼 만함

질문 3: 커스텀 통합 개발 리소스가 있나요?
├─ YES (수주~수개월) → 🟡 옵션 A (래퍼) 시도
└─ NO → ✅ 기존 LOD 하이브리드 사용
```

### 6.3 체크리스트

**현재 프로젝트에 적용할 것:**
```
✅ Mass AI LOD 하이브리드 설정
   ├─ High LOD: 0-50m, 최대 100개, 풀 Actor + AnimBP
   ├─ Medium LOD: 50-200m, 최대 500개, Low Actor
   └─ Low LOD: 200m+, Static ISM

✅ 원거리 Static ISM 최적화
   ├─ 저폴리 메시 사용 (<500 tris)
   ├─ 그림자 끄기
   └─ 단순 머티리얼

⏳ 모니터링
   ├─ UE 5.8 릴리스 노트 체크
   └─ Instanced Skeletal Mesh 정식 출시 여부
```

---

## 참고 문서

- [03_RenderingAndLOD.md](03_RenderingAndLOD.md) - LOD 시스템 상세
- [04_AnimationIntegration.md](04_AnimationIntegration.md) - 애니메이션 통합
- [07_OptimizationGuide.md](07_OptimizationGuide.md) - 최적화 전략

---

## 참조 소스 경로

```
InstancedSkinnedMeshComponent:
Engine/Source/Runtime/Engine/Classes/Components/InstancedSkinnedMeshComponent.h
Engine/Source/Runtime/Engine/Private/Components/InstancedSkinnedMeshComponent.cpp

AnimBank:
Engine/Source/Runtime/Engine/Classes/Animation/AnimBank.h

Mass Representation:
Engine/Plugins/Runtime/MassGameplay/Source/MassRepresentation/Public/MassRepresentationTypes.h
Engine/Plugins/Runtime/MassGameplay/Source/MassRepresentation/Private/MassRepresentationProcessor.cpp
```

---

## 버전 히스토리

| 버전 | 날짜 | 변경 내용 |
|------|------|----------|
| v1.0 | 2025-12-29 | 초기 문서 작성 |
