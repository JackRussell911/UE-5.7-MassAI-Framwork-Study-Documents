# 애니메이션 통합 전략

> **문서 목적**: Mass AI에서 기존 애니메이션 리소스를 활용하는 방법 이해
>
> **대상 독자**: 블루프린트 개발자부터 C++ 개발자까지

---

## 1. Mass AI와 애니메이션 - 핵심 질문

### "기존에 만든 애니메이션 블루프린트를 그대로 쓸 수 있나요?"

**짧은 답변**: 네, 하지만 **가까운 몬스터에만**요.

**왜 그런가요?**

Mass AI의 핵심은 **데이터만 다루는 것**이에요. Fragment에는 숫자, 위치, 상태 같은 데이터만 저장되고, 스켈레탈 메시나 애니메이션 같은 **복잡한 컴포넌트는 없어요**.

```
Mass Entity가 가진 것:
✅ FTransformFragment (위치, 회전)
✅ FMassVelocityFragment (속도)
✅ FMonsterHealthFragment (체력)
✅ 기타 데이터 Fragment들

Mass Entity가 없는 것:
❌ USkeletalMeshComponent
❌ UAnimInstance (애니메이션 블루프린트)
❌ Physics Body
```

### 그래서 어떻게 해결하나요?

**거리에 따라 다르게 처리해요:**

```
┌─────────────────────────────────────────────────────────────────────┐
│                      거리별 애니메이션 전략                           │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  가까움 (0~50m)                                                     │
│  └─ Actor 스폰 → AnimBP 사용 가능!                                 │
│     기존 애니메이션 블루프린트 그대로 활용                          │
│                                                                      │
│  중간 (50~200m)                                                     │
│  └─ 간소화 Actor → 단순 AnimBP                                     │
│     복잡한 블렌드 없이 기본 애니메이션만                            │
│                                                                      │
│  멀리 (200m+)                                                       │
│  └─ ISM (Static Mesh) → 애니메이션 없음                            │
│     셰이더로 흔들림 효과만 (선택적)                                 │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 2. 데이터 흐름 이해하기 - Translator 시스템

### "Mass Entity의 속도 데이터가 어떻게 AnimBP까지 전달되나요?"

이게 핵심이에요! **Translator**라는 시스템이 중간에서 데이터를 전달해줘요.

### 전체 흐름

```
┌─────────────────────────────────────────────────────────────────────┐
│                    Mass Entity → AnimBP 데이터 흐름                   │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  1. Mass Processor가 Fragment 데이터 업데이트                       │
│     ┌─────────────────────────────────────────┐                     │
│     │ FMassVelocityFragment.Value = (100,0,0) │                     │
│     │ FTransformFragment.Location = (...)     │                     │
│     └─────────────────────────────────────────┘                     │
│                           │                                          │
│                           ▼                                          │
│  2. Translator가 Fragment → Actor로 복사                            │
│     ┌─────────────────────────────────────────┐                     │
│     │ CopyToActor():                          │                     │
│     │   Actor->SetActorLocation(Location)     │                     │
│     │   MovementComponent->Velocity = (100,0,0)│                    │
│     └─────────────────────────────────────────┘                     │
│                           │                                          │
│                           ▼                                          │
│  3. AnimInstance가 Actor 데이터 읽기                                │
│     ┌─────────────────────────────────────────┐                     │
│     │ NativeUpdateAnimation():                │                     │
│     │   Speed = GetOwner()->GetVelocity()     │                     │
│     │   // Speed = 100                        │                     │
│     └─────────────────────────────────────────┘                     │
│                           │                                          │
│                           ▼                                          │
│  4. AnimBP가 Speed로 애니메이션 선택                                │
│     ┌─────────────────────────────────────────┐                     │
│     │ if Speed < 10: Idle                     │                     │
│     │ elif Speed < 200: Walk                  │                     │
│     │ else: Run                               │                     │
│     └─────────────────────────────────────────┘                     │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### Translator가 뭔가요?

**쉬운 설명**: Mass Entity와 Actor 사이의 **통역사**예요.

Mass Entity는 Fragment(데이터)만 갖고 있고, Actor는 Component(기능)를 갖고 있어요. 둘은 언어가 달라서 Translator가 번역해줘야 해요.

```
Mass Entity                 Translator               Actor
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
FMassVelocityFragment   →   CopyToActor()    →   GetVelocity()
FTransformFragment      →   CopyToActor()    →   GetActorTransform()
FHealthFragment         →   CopyToActor()    →   HealthComponent
```

---

## 3. High LOD Actor 설정하기 - 단계별 가이드

### Step 1: Monster Actor Blueprint 생성

에디터에서 Actor Blueprint를 만들어요.

**블루프린트 구조**:
```
BP_Monster_HighRes
├─ SceneComponent (Root)
├─ SkeletalMeshComponent (Mesh)
│   └─ SkeletalMesh: SK_Monster
│   └─ AnimClass: ABP_Monster  ← 기존 AnimBP!
├─ CapsuleComponent (Collision)
└─ MassAgentComponent (Mass 연결)  ← 중요!
```

### Step 2: MassAgentComponent 추가

**MassAgentComponent**는 Mass Entity와 Actor를 연결하는 다리예요.

```cpp
// C++에서 추가
UCLASS()
class ABP_Monster_HighRes : public AActor
{
    GENERATED_BODY()

public:
    ABP_Monster_HighRes()
    {
        // 스켈레탈 메시
        SkeletalMesh = CreateDefaultSubobject<USkeletalMeshComponent>(TEXT("Mesh"));
        RootComponent = SkeletalMesh;

        // MassAgentComponent - 이게 중요!
        MassAgent = CreateDefaultSubobject<UMassAgentComponent>(TEXT("MassAgent"));
    }

    UPROPERTY(VisibleAnywhere)
    USkeletalMeshComponent* SkeletalMesh;

    UPROPERTY(VisibleAnywhere)
    UMassAgentComponent* MassAgent;
};
```

**블루프린트에서**:
1. Actor Blueprint 열기
2. **Add Component** → "Mass Agent" 검색
3. **MassAgentComponent** 추가

### Step 3: AnimBP에서 속도 읽기

기존 AnimBP를 거의 그대로 사용할 수 있어요. 단, 속도를 읽는 방식을 확인해야 해요.

**AnimBP Event Graph**:
```
[Event Blueprint Update Animation]
        │
        ▼
[Try Get Pawn Owner] ─→ [Get Velocity] ─→ [Vector Length]
                                                │
                                                ▼
                                         [Set Speed]
```

**C++에서**:
```cpp
void UMonsterAnimInstance::NativeUpdateAnimation(float DeltaSeconds)
{
    Super::NativeUpdateAnimation(DeltaSeconds);

    AActor* Owner = TryGetPawnOwner();
    if (!Owner) return;

    // Actor의 속도 가져오기 (Translator가 이미 동기화함)
    Speed = Owner->GetVelocity().Size();

    // 이동 방향
    FVector Velocity = Owner->GetVelocity();
    if (!Velocity.IsNearlyZero())
    {
        MoveDirection = Velocity.GetSafeNormal();
    }
}
```

### Step 4: Visualization Trait에서 Actor 설정

**MassEntityConfigAsset에서**:
```
[MassVisualizationTrait]
├─ High Res Template Actor: BP_Monster_HighRes  ← 여기!
├─ Low Res Template Actor: BP_Monster_LowRes
└─ Static Mesh Instance Desc: SM_Monster_Low
```

---

## 4. 속도 기반 Walk/Run 전환 구현

### AnimBP에서 블렌드 스페이스 사용하기

**방법 1: 블렌드 스페이스 1D (Speed만 사용)**

```
블렌드 스페이스 설정:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Axis: Speed
Range: 0 ~ 600

Speed = 0     → Idle 애니메이션
Speed = 150   → Walk 애니메이션
Speed = 400   → Run 애니메이션
Speed = 600   → Sprint 애니메이션
```

**AnimBP State Machine**:
```
[Locomotion State]
    │
    └─ [Blend Space 1D: BS_Locomotion]
           │
           └─ Input: Speed (from AnimInstance variable)
```

**블루프린트 구현**:
```
[Event Blueprint Update Animation]
    │
    ▼
[Try Get Pawn Owner]
    │
    ▼
[Get Velocity] → [Vector Length] → [Set Speed Variable]
```

### 방법 2: 블렌드 스페이스 2D (Speed + Direction)

```
블렌드 스페이스 설정:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Horizontal Axis: Direction (-180 ~ 180)
Vertical Axis: Speed (0 ~ 600)

조합:
(Direction=0, Speed=0)     → Idle
(Direction=0, Speed=300)   → Forward Walk
(Direction=90, Speed=300)  → Right Strafe
(Direction=-90, Speed=300) → Left Strafe
(Direction=180, Speed=300) → Backward Walk
```

**방향 계산**:
```cpp
void UMonsterAnimInstance::NativeUpdateAnimation(float DeltaSeconds)
{
    AActor* Owner = TryGetPawnOwner();
    if (!Owner) return;

    FVector Velocity = Owner->GetVelocity();
    Speed = Velocity.Size();

    if (Speed > 10.0f)
    {
        // 로컬 방향 계산
        FRotator ActorRotation = Owner->GetActorRotation();
        FVector LocalVelocity = ActorRotation.UnrotateVector(Velocity);

        // -180 ~ 180도로 변환
        Direction = FMath::Atan2(LocalVelocity.Y, LocalVelocity.X);
        Direction = FMath::RadiansToDegrees(Direction);
    }
}
```

---

## 5. 기존 AnimBP 재활용 전략

### "이미 만들어둔 몬스터 AnimBP가 있는데, 그대로 쓸 수 있나요?"

**대부분 그대로 쓸 수 있어요!** 다만 몇 가지 확인이 필요해요.

### 체크리스트

```
□ AnimBP가 Pawn Owner의 Velocity를 사용하나요?
  → Mass AI에서 잘 작동함!

□ AnimBP가 CharacterMovementComponent를 직접 참조하나요?
  → 수정 필요 (Actor의 Velocity 사용으로 변경)

□ AnimBP가 AI Controller를 참조하나요?
  → 수정 필요 (Mass AI에서는 Controller 없음)

□ Root Motion을 사용하나요?
  → 주의 필요 (아래 섹션 참조)
```

### 수정이 필요한 경우

**Before (CharacterMovementComponent 직접 참조)**:
```
[Get Owning Component] → [Get Character Movement] → [Get Velocity]
```

**After (Actor Velocity 사용)**:
```
[Try Get Pawn Owner] → [Get Velocity]
```

### Root Motion 처리

Root Motion을 사용하면 애니메이션이 Actor를 이동시켜요. 이 경우 Actor의 위치를 다시 Mass Entity에 반영해야 해요.

```cpp
// Actor → Mass 방향 동기화 필요
USTRUCT()
struct FRootMotionTranslator : public FMassTranslator
{
    virtual void CopyFromActor(FMassEntityManager& EntityManager,
                               FMassEntityHandle Entity,
                               const AActor* Actor) const override
    {
        // Actor 위치를 Fragment에 복사
        FTransformFragment* Transform =
            EntityManager.GetFragmentDataPtr<FTransformFragment>(Entity);

        Transform->Transform = Actor->GetActorTransform();
    }
};
```

---

## 6. Low LOD Actor 설정 (중간 거리)

### 간소화 전략

중간 거리의 몬스터는 **간소화된 Actor**를 사용해요.

```
High Res Actor              Low Res Actor
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
50개 본                 →   20개 본 (주요 본만)
10,000 삼각형          →   2,000 삼각형
복잡한 AnimBP          →   단순 State Machine
블렌드 스페이스        →   직접 애니 전환
IK 활성화             →   IK 비활성화
물리 시뮬레이션        →   물리 없음
```

### Low Res AnimBP 만들기

**단순 State Machine**:
```
┌─────────────────────────────────────────────────────────────────────┐
│                        Low Res State Machine                         │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│   ┌──────────┐    Speed > 10    ┌──────────┐                        │
│   │   Idle   │ ───────────────→ │   Walk   │                        │
│   │          │ ←─────────────── │          │                        │
│   └──────────┘    Speed < 10    └──────────┘                        │
│                                                                      │
│   조건만 단순하게! 블렌드 스페이스 없음                              │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### Low Res 스켈레톤 만들기

1. 원본 스켈레톤에서 **LOD 스켈레톤** 생성
2. 불필요한 본 제거 (손가락, 얼굴 본 등)
3. 주요 본만 유지 (Spine, Pelvis, Legs, Arms, Head)

```
제거할 본들:
- 손가락 본 (finger_*)
- 얼굴 본 (face_*)
- 보조 본 (twist_*, helper_*)
- 천 시뮬레이션 본 (cloth_*)

유지할 본들:
- Root, Pelvis, Spine 체인
- 양팔 (Shoulder → Elbow → Hand)
- 양다리 (Thigh → Knee → Foot)
- Neck, Head
```

---

## 7. ISM (원거리) - 셰이더 기반 움직임

### 애니메이션 없는 Static Mesh에 생동감 주기

ISM은 Static Mesh라서 애니메이션이 안 돼요. 하지만 **셰이더**로 간단한 움직임을 줄 수 있어요!

### 머티리얼에서 흔들림 효과

**월드 포지션 오프셋 (WPO)**:
```
Material Blueprint에서:

[Time] × [Speed Parameter]
        │
        ▼
[Sin] × [Amplitude Parameter]
        │
        ▼
[Append (0, 0, Result)]  ← Z축으로만 흔들림
        │
        ▼
[World Position Offset]
```

**파라미터 설정**:
```
Speed: 2.0 (흔들림 속도)
Amplitude: 10.0 (흔들림 크기, cm)
```

### 걷기 시뮬레이션 (고급)

```
// 다리가 번갈아 움직이는 것처럼 보이게

[VertexPosition.X] × 0.01
        │
        ▼
[Time] + [위 결과]  ← 버텍스마다 다른 타이밍
        │
        ▼
[Sin] × [Leg Swing Amount]
        │
        ▼
// UV나 Vertex Color로 다리 부분만 마스킹
[Mask] × [위 결과]
        │
        ▼
[World Position Offset]
```

### CustomData로 개체별 변형

ISM은 **PerInstanceCustomData**로 개체마다 다른 값을 셰이더에 전달할 수 있어요.

```cpp
// 스폰 시 CustomData 설정
FStaticMeshInstanceVisualizationMeshDesc MeshDesc;
MeshDesc.Mesh = MonsterMesh;

// 색상 변형 (Hue Shift)
MeshDesc.CustomDataFloats.Add(FMath::RandRange(0.0f, 1.0f));

// 애니메이션 오프셋 (타이밍 차이)
MeshDesc.CustomDataFloats.Add(FMath::RandRange(0.0f, 2.0f * PI));

// 크기 변형
MeshDesc.CustomDataFloats.Add(FMath::RandRange(0.9f, 1.1f));
```

**머티리얼에서 읽기**:
```
[PerInstanceCustomData Index 0] → Color Hue
[PerInstanceCustomData Index 1] → Animation Offset
[PerInstanceCustomData Index 2] → Scale
```

---

## 8. 애니메이션 최적화 기법

### 8.1 Update Rate Optimization (URO)

화면 밖이나 멀리 있는 Actor의 애니메이션 업데이트 횟수를 줄여요.

**AnimInstance에서 설정**:
```cpp
void UMonsterAnimInstance::NativeInitializeAnimation()
{
    Super::NativeInitializeAnimation();

    USkeletalMeshComponent* Mesh = GetSkelMeshComponent();

    // URO 활성화
    Mesh->SetEnableUpdateRateOptimizations(true);

    // 화면에 안 보이면 포즈만 업데이트 (애니메이션 계산 스킵)
    Mesh->VisibilityBasedAnimTickOption =
        EVisibilityBasedAnimTickOption::OnlyTickPoseWhenRendered;
}
```

**에디터에서**:
1. Skeletal Mesh Component 선택
2. **Enable Update Rate Optimizations** 체크
3. **Visibility Based Anim Tick Option** 설정

### 8.2 거리 기반 업데이트 주기

가까운 몬스터만 매 프레임 업데이트하고, 먼 몬스터는 띄엄띄엄 업데이트해요.

```cpp
void UpdateAnimationTickInterval(AActor* Actor, float DistanceToPlayer)
{
    USkeletalMeshComponent* Mesh = Actor->FindComponentByClass<USkeletalMeshComponent>();
    if (!Mesh) return;

    float TickInterval;

    if (DistanceToPlayer < 1000.0f)       // 10m 이내
        TickInterval = 0.0f;              // 매 프레임 (60fps)
    else if (DistanceToPlayer < 3000.0f)  // 30m 이내
        TickInterval = 0.033f;            // 30fps
    else if (DistanceToPlayer < 5000.0f)  // 50m 이내
        TickInterval = 0.066f;            // 15fps
    else
        TickInterval = 0.1f;              // 10fps

    Mesh->SetComponentTickInterval(TickInterval);
}
```

### 8.3 애니메이션 LOD

스켈레탈 메시 자체에 LOD를 설정해서 먼 거리에서 본 수를 줄여요.

**에디터에서**:
1. Skeletal Mesh Asset 열기
2. **Asset Details > LOD Settings**
3. LOD 레벨 추가
4. **Reduction Settings**에서 본 수 감소

```
LOD 0: 50개 본 (100% 품질)
LOD 1: 30개 본 (60% 품질)
LOD 2: 15개 본 (30% 품질)
```

---

## 9. 실전 예시: 뱀파이어 서바이벌 몬스터

### 전체 설정

```
┌─────────────────────────────────────────────────────────────────────┐
│                 뱀파이어 서바이벌 몬스터 애니메이션 설정              │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  [High LOD: 0~50m, 최대 100마리]                                    │
│  └─ BP_Monster_HighRes                                              │
│      ├─ SkeletalMesh: SK_Zombie (50 bones)                         │
│      ├─ AnimBP: ABP_Zombie                                          │
│      │   ├─ Blend Space: Walk/Run                                   │
│      │   ├─ Montage: Attack, Hit, Death                            │
│      │   └─ URO: Enabled                                            │
│      └─ MassAgentComponent                                          │
│                                                                      │
│  [Medium LOD: 50~200m, 최대 500마리]                                │
│  └─ BP_Monster_LowRes                                               │
│      ├─ SkeletalMesh: SK_Zombie_LOD (20 bones)                     │
│      ├─ AnimBP: ABP_Zombie_Simple                                   │
│      │   └─ Simple State: Idle ↔ Walk                              │
│      └─ MassAgentComponent                                          │
│                                                                      │
│  [Low LOD: 200m+, 나머지 전부]                                      │
│  └─ ISM: SM_Zombie_Billboard (500 triangles)                       │
│      ├─ Material: M_Zombie_ISM                                      │
│      │   └─ WPO: 흔들림 효과                                        │
│      └─ CustomData: Color, AnimOffset                               │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### 몬스터 종류별 설정

| 몬스터 | High LOD 본 | Low LOD 본 | ISM 삼각형 |
|--------|------------|-----------|-----------|
| 좀비 | 50 | 20 | 500 |
| 박쥐 | 30 | 15 | 200 |
| 슬라임 | 10 | 5 | 100 |
| 보스 | 80 | 40 | 1000 |

---

## 10. 흔한 문제와 해결책

### 문제 1: "Actor가 스폰되는데 애니메이션이 안 재생돼요"

**원인**: AnimBP가 설정 안 됨

**해결**:
```
BP_Monster_HighRes > SkeletalMeshComponent > Anim Class
→ ABP_Monster 설정
```

### 문제 2: "속도가 0으로 나와서 Idle만 재생돼요"

**원인**: Translator가 속도를 동기화하기 전에 AnimBP가 읽음

**해결**: AnimBP에서 Actor의 Velocity 직접 사용
```
[Try Get Pawn Owner] → [Get Velocity] → [Vector Length] → [Speed]
```

### 문제 3: "LOD 전환 시 애니메이션이 끊겨요"

**원인**: High ↔ Low Actor 전환 시 포즈가 다름

**해결**: 전환 시 현재 포즈 유지하는 로직 추가 또는 빠른 블렌드
```cpp
// Actor 전환 시 현재 포즈 복사
NewMesh->SetAnimationMode(EAnimationMode::AnimationCustomMode);
NewMesh->SetComponentTickEnabled(false);
// 1프레임 후 AnimBP로 복귀
```

### 문제 4: "ISM이 너무 정적으로 보여요"

**해결**: 머티리얼에 WPO 흔들림 추가 + CustomData로 개체별 오프셋

---

## 11. 다음 단계

애니메이션 통합을 이해했다면, 다음 문서에서 행동 로직 시스템을 살펴보겠습니다:

- **다음**: [05_BehaviorLogic.md](05_BehaviorLogic.md) - StateTree, Signal, Smart Objects를 활용한 몬스터 행동 구현

### 이 문서에서 배운 것

1. **거리별 전략**: 가까움(AnimBP) → 중간(단순 AnimBP) → 멀리(ISM)
2. **Translator**: Mass Entity ↔ Actor 데이터 동기화
3. **MassAgentComponent**: Actor를 Mass Entity에 연결
4. **기존 AnimBP 재활용**: 대부분 그대로 사용 가능
5. **속도 기반 애니메이션**: Blend Space 활용
6. **최적화**: URO, Animation LOD, Update Rate
7. **ISM 애니메이션**: 셰이더 WPO로 흔들림 효과
