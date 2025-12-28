# 행동 로직 시스템

> **문서 목적**: StateTree, Signal, Processor를 활용한 몬스터 행동 구현 방법 이해
>
> **대상 독자**: 블루프린트 개발자부터 C++ 개발자까지

---

## 1. 몬스터 행동, 어떻게 만들어야 하나요?

### 전통적인 AI vs Mass AI

**블루프린트 AI (Actor 기반)**:
```
BP_Monster에서:
- Behavior Tree 사용
- AI Controller 연결
- Blackboard로 상태 관리
- BTTask로 행동 정의

결과: 몬스터 100마리 이상이면 성능 문제!
```

**Mass AI**:
```
몬스터 수천 마리를 위한 세 가지 선택지:

1. Processor 직접 구현 (가장 효율적)
   → 간단한 행동에 적합

2. Signal 시스템 (이벤트 기반)
   → 피격, 죽음 등 이벤트 처리

3. StateTree (상태 기반)
   → 복잡한 행동에 적합, High LOD에서만 사용
```

### 세 가지 방법 비교

| 방법 | 복잡도 | 성능 | 용도 |
|------|--------|------|------|
| **Processor** | 간단 | 최고 | 추적, 공격 등 단순 행동 |
| **Signal** | 중간 | 높음 | 이벤트 반응 (피격, 죽음) |
| **StateTree** | 복잡 | 중간 | 복잡한 상태 전환 (High LOD만) |

---

## 2. Processor로 간단한 행동 만들기

### "플레이어 쫓아가기" 만들기

가장 기본적인 몬스터 행동이에요. Processor 하나로 구현할 수 있어요.

**전체 흐름**:
```
┌─────────────────────────────────────────────────────────────────────┐
│                     플레이어 추적 Processor                           │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  1. 플레이어 위치 가져오기                                          │
│        │                                                             │
│        ▼                                                             │
│  2. 각 몬스터에서 플레이어까지 방향 계산                            │
│        │                                                             │
│        ▼                                                             │
│  3. 그 방향으로 속도 설정                                           │
│        │                                                             │
│        ▼                                                             │
│  4. 이동 Processor가 실제 이동 처리                                 │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

**코드로 구현**:
```cpp
UCLASS()
class UMonsterChaseProcessor : public UMassProcessor
{
    GENERATED_BODY()

public:
    UPROPERTY(EditAnywhere)
    float ChaseSpeed = 400.0f;  // 이동 속도 (cm/s)

    // 생성자: 언제 실행할지 설정
    UMonsterChaseProcessor()
    {
        ProcessingPhase = EMassProcessingPhase::PrePhysics;

        // 이동 적용 Processor보다 먼저 실행
        ExecutionOrder.ExecuteBefore.Add(UMassApplyMovementProcessor::StaticClass());
    }

    // 어떤 엔티티를 처리할지 설정
    virtual void ConfigureQueries() override
    {
        EntityQuery.AddRequirement<FTransformFragment>(EMassFragmentAccess::ReadOnly);
        EntityQuery.AddRequirement<FMassVelocityFragment>(EMassFragmentAccess::ReadWrite);
        EntityQuery.AddRequirement<FMonsterTag>(EMassFragmentPresence::All);
        EntityQuery.AddRequirement<FDeadTag>(EMassFragmentPresence::None);  // 죽은 건 제외
    }

    // 매 프레임 실행
    virtual void Execute(FMassEntityManager& EntityManager,
                         FMassExecutionContext& Context) override
    {
        // 1. 플레이어 위치 가져오기
        const FVector PlayerLocation = GetPlayerLocation();

        // 2. 모든 몬스터 처리
        EntityQuery.ForEachEntityChunk(EntityManager, Context,
            [this, PlayerLocation](FMassExecutionContext& Context)
            {
                auto Transforms = Context.GetFragmentView<FTransformFragment>();
                auto Velocities = Context.GetMutableFragmentView<FMassVelocityFragment>();

                for (int32 i = 0; i < Context.GetNumEntities(); ++i)
                {
                    // 3. 플레이어 방향 계산
                    FVector MyLocation = Transforms[i].Transform.GetLocation();
                    FVector Direction = (PlayerLocation - MyLocation).GetSafeNormal();

                    // 4. 속도 설정
                    Velocities[i].Value = Direction * ChaseSpeed;
                }
            });
    }

private:
    FVector GetPlayerLocation() const
    {
        if (APawn* Player = UGameplayStatics::GetPlayerPawn(GetWorld(), 0))
        {
            return Player->GetActorLocation();
        }
        return FVector::ZeroVector;
    }
};
```

### "가까우면 공격하기" 추가

```cpp
UCLASS()
class UMonsterAttackProcessor : public UMassProcessor
{
    GENERATED_BODY()

public:
    UPROPERTY(EditAnywhere)
    float AttackRange = 100.0f;   // 공격 범위 (cm)

    UPROPERTY(EditAnywhere)
    float AttackCooldown = 1.0f;  // 공격 쿨다운 (초)

    UPROPERTY(EditAnywhere)
    float Damage = 10.0f;

    virtual void Execute(FMassEntityManager& EntityManager,
                         FMassExecutionContext& Context) override
    {
        const FVector PlayerLocation = GetPlayerLocation();
        const float AttackRangeSq = FMath::Square(AttackRange);  // 제곱으로 비교 (더 빠름)
        const float DeltaTime = Context.GetDeltaTimeSeconds();

        EntityQuery.ForEachEntityChunk(EntityManager, Context,
            [=](FMassExecutionContext& Context)
            {
                auto Transforms = Context.GetFragmentView<FTransformFragment>();
                auto Combats = Context.GetMutableFragmentView<FMonsterCombatFragment>();
                auto Velocities = Context.GetMutableFragmentView<FMassVelocityFragment>();

                for (int32 i = 0; i < Context.GetNumEntities(); ++i)
                {
                    // 쿨다운 감소
                    Combats[i].CooldownRemaining -= DeltaTime;

                    // 거리 계산
                    float DistSq = FVector::DistSquared(
                        Transforms[i].Transform.GetLocation(),
                        PlayerLocation);

                    if (DistSq <= AttackRangeSq)
                    {
                        // 공격 범위 안! 멈추기
                        Velocities[i].Value = FVector::ZeroVector;

                        // 쿨다운 끝났으면 공격
                        if (Combats[i].CooldownRemaining <= 0.0f)
                        {
                            Combats[i].bIsAttacking = true;
                            Combats[i].CooldownRemaining = AttackCooldown;

                            // 여기서 플레이어에게 데미지!
                            // (Signal이나 직접 호출로 처리)
                        }
                    }
                    else
                    {
                        Combats[i].bIsAttacking = false;
                    }
                }
            });
    }
};
```

---

## 3. Signal 시스템 - 이벤트 통신

### Signal이 뭐예요?

**쉬운 설명**: Mass Entity끼리 "야 이거 알아!"라고 알려주는 시스템이에요.

**블루프린트 비유**: Event Dispatcher 같은 거예요. 누군가 이벤트를 발생시키면, 구독한 쪽에서 반응해요.

```
블루프린트                     Mass AI Signal
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Event Dispatcher      →       Signal 전송
Bind Event            →       Signal 구독 (Processor에서)
Event 호출             →       SignalEntity() 호출
```

### Signal 사용 예시: 몬스터 피격

**Step 1: Signal 이름 정의**
```cpp
// MonsterSignals.h
namespace MonsterSignals
{
    const FName Hit = TEXT("MonsterHit");           // 피격
    const FName Death = TEXT("MonsterDeath");       // 사망
    const FName PlayerDetected = TEXT("Detected");  // 플레이어 감지
}
```

**Step 2: Signal 보내기**
```cpp
void UDamageProcessor::ApplyDamage(FMassEntityHandle Monster, float Damage)
{
    // Signal Subsystem 가져오기
    UMassSignalSubsystem* SignalSubsystem =
        GetWorld()->GetSubsystem<UMassSignalSubsystem>();

    // 피격 Signal 전송!
    SignalSubsystem->SignalEntity(MonsterSignals::Hit, Monster);

    // 체력 확인
    FMonsterHealthFragment* Health =
        EntityManager.GetFragmentDataPtr<FMonsterHealthFragment>(Monster);

    if (Health->CurrentHealth <= 0)
    {
        // 죽음 Signal 전송!
        SignalSubsystem->SignalEntity(MonsterSignals::Death, Monster);
    }
}
```

**Step 3: Signal 받기**
```cpp
UCLASS()
class UMonsterHitReactionProcessor : public UMassSignalProcessorBase
{
    GENERATED_BODY()

public:
    UMonsterHitReactionProcessor()
    {
        // 이 Signal을 받겠다고 등록
        SubscribeToSignal(MonsterSignals::Hit);
    }

    // Signal을 받으면 이 함수가 호출됨
    virtual void SignalEntities(FMassEntityManager& EntityManager,
                                FMassExecutionContext& Context,
                                FMassSignalNameLookup& EntitySignals) override
    {
        // Hit Signal을 받은 엔티티들 가져오기
        TArray<FMassEntityHandle> HitMonsters;
        EntitySignals.GetEntitiesForSignal(MonsterSignals::Hit, HitMonsters);

        for (FMassEntityHandle Monster : HitMonsters)
        {
            // 피격 반응 처리
            FMonsterAnimStateFragment* AnimState =
                EntityManager.GetFragmentDataPtr<FMonsterAnimStateFragment>(Monster);

            if (AnimState)
            {
                AnimState->bIsHit = true;  // AnimBP에서 Hit 애니메이션 재생
            }
        }
    }
};
```

### Signal 사용 시나리오

| Signal | 언제 보내나요? | 어디서 받나요? |
|--------|---------------|---------------|
| `MonsterHit` | 플레이어 공격이 몬스터에 맞을 때 | 피격 반응 Processor |
| `MonsterDeath` | 몬스터 체력이 0이 될 때 | 죽음 처리 Processor |
| `PlayerHit` | 몬스터 공격이 플레이어에 맞을 때 | UI/사운드 Processor |
| `ItemDrop` | 몬스터 사망 시 | 아이템 스폰 Processor |

---

## 4. StateTree 완전 가이드

### StateTree가 뭐예요?

**쉬운 설명**: "시각적으로 AI 상태 기계를 만드는 도구"

Behavior Tree를 써봤다면 비슷해요. 하지만 더 유연하고, Mass AI와 잘 통합돼요.

```
┌─────────────────────────────────────────────────────────────────────┐
│                        StateTree 기본 개념                           │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  State (상태)                                                        │
│  └─ "현재 뭘 하고 있나요?" (예: Idle, Chase, Attack)                │
│                                                                      │
│  Task (작업)                                                         │
│  └─ "그 상태에서 뭘 하나요?" (예: 이동, 공격, 대기)                 │
│                                                                      │
│  Condition (조건)                                                    │
│  └─ "언제 다른 상태로 바꾸나요?" (예: 플레이어가 가까우면)          │
│                                                                      │
│  Transition (전환)                                                   │
│  └─ "어떤 상태로 바꾸나요?" (예: Idle → Chase)                      │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### StateTree는 언제 쓰나요?

**StateTree가 적합한 경우**:
- 복잡한 행동 패턴 (보스 몬스터)
- 여러 상태 전환이 필요할 때
- 블루프린트로 행동을 정의하고 싶을 때
- High LOD Actor에서만 사용

**StateTree가 불필요한 경우**:
- 단순 추적/공격 (Processor로 충분)
- 수천 마리 전부에게 적용 (성능 문제)

### StateTree 만들기 - 단계별

**Step 1: StateTree 에셋 생성**

1. Content Browser에서 **우클릭**
2. **Artificial Intelligence → StateTree**
3. 이름 지정: `ST_Monster_Behavior`

**Step 2: Schema 설정**

StateTree 에디터에서:
1. **Details** 패널
2. **Schema** → `StateTreeAIComponentSchema` 또는 `MassStateTreeSchema`

```
Schema 종류:
- StateTreeAIComponentSchema: Actor 기반 AI용
- MassStateTreeSchema: Mass Entity 전용
```

**Step 3: 상태(State) 추가**

에디터에서:
1. 루트 상태 우클릭 → **Add State**
2. 상태 이름 지정: `Idle`, `Chase`, `Attack`

```
[Root]
├── [Idle]      ← 기본 상태
├── [Chase]     ← 추적 상태
└── [Attack]    ← 공격 상태
```

**Step 4: Task 추가**

각 상태에 Task 추가:
1. 상태 선택
2. **Tasks** 섹션에서 **+** 클릭
3. Task 선택 (내장 또는 커스텀)

```
[Chase]
└── Tasks
    └── [Move To Task]
        ├─ Target: Player Location
        └─ Acceptable Radius: 100
```

**Step 5: Transition 설정**

상태 전환 조건 추가:
1. 상태 선택
2. **Transitions** 섹션에서 **+** 클릭
3. 조건과 목표 상태 설정

```
[Idle] ─── (Distance < 1000) ───→ [Chase]
[Chase] ─── (Distance < 100) ───→ [Attack]
[Attack] ─── (Attack Done) ───→ [Chase]
[Chase] ─── (Distance > 1500) ───→ [Idle]
```

### 블루프린트로 StateTree Task 만들기

**방법 1: Blueprint에서 Task 생성**

1. Content Browser → **Blueprint Class**
2. 부모 클래스: `StateTreeTaskBlueprintBase`
3. 함수 오버라이드:
   - `Enter State`: 상태 진입 시
   - `Tick`: 매 프레임
   - `Exit State`: 상태 종료 시

**Task Blueprint 예시**:
```
Event Enter State
    │
    ▼
[Play Animation Montage: Attack]
    │
    ▼
[Return: Running]

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Event Tick
    │
    ▼
[Is Montage Playing?]
    │
    ├─ Yes → [Return: Running]
    │
    └─ No → [Apply Damage]
             │
             ▼
         [Return: Succeeded]
```

**방법 2: C++로 Task 생성**

```cpp
USTRUCT()
struct FMonsterAttackTask : public FStateTreeTaskCommonBase
{
    GENERATED_BODY()

    UPROPERTY(EditAnywhere)
    float Damage = 10.0f;

    UPROPERTY(EditAnywhere)
    TObjectPtr<UAnimMontage> AttackMontage;

    // 상태 진입 시
    virtual EStateTreeRunStatus EnterState(
        FStateTreeExecutionContext& Context,
        const FStateTreeTransitionResult& Transition) const override
    {
        // 공격 애니메이션 재생
        AActor* Actor = Context.GetOwner();
        if (USkeletalMeshComponent* Mesh = Actor->FindComponentByClass<USkeletalMeshComponent>())
        {
            if (UAnimInstance* Anim = Mesh->GetAnimInstance())
            {
                Anim->Montage_Play(AttackMontage);
            }
        }
        return EStateTreeRunStatus::Running;
    }

    // 매 프레임
    virtual EStateTreeRunStatus Tick(
        FStateTreeExecutionContext& Context,
        const float DeltaTime) const override
    {
        AActor* Actor = Context.GetOwner();
        if (USkeletalMeshComponent* Mesh = Actor->FindComponentByClass<USkeletalMeshComponent>())
        {
            if (UAnimInstance* Anim = Mesh->GetAnimInstance())
            {
                // 몽타주 끝났으면 성공
                if (!Anim->Montage_IsPlaying(AttackMontage))
                {
                    return EStateTreeRunStatus::Succeeded;
                }
            }
        }
        return EStateTreeRunStatus::Running;
    }
};
```

### Mass AI와 StateTree 통합

**MassStateTreeTrait 사용**:

```cpp
// Entity Config에 MassStateTreeTrait 추가
UCLASS()
class UMonsterStateTreeTrait : public UMassStateTreeTrait
{
    GENERATED_BODY()

public:
    UPROPERTY(EditAnywhere)
    UStateTree* MonsterStateTree;  // StateTree 에셋

    virtual void BuildTemplate(FMassEntityTemplateBuildContext& BuildContext,
                               const UWorld& World) const override
    {
        Super::BuildTemplate(BuildContext, World);

        // StateTree Fragment 추가
        FMassStateTreeFragment& StateTreeFragment =
            BuildContext.AddFragment_GetRef<FMassStateTreeFragment>();

        StateTreeFragment.StateTree = MonsterStateTree;
    }
};
```

**High LOD Actor에서 StateTree 사용**:

```cpp
UCLASS()
class ABP_Monster_HighRes : public AActor
{
    GENERATED_BODY()

public:
    ABP_Monster_HighRes()
    {
        // StateTree AI Component
        StateTreeComponent = CreateDefaultSubobject<UStateTreeAIComponent>(TEXT("StateTree"));

        // Mass Agent
        MassAgent = CreateDefaultSubobject<UMassAgentComponent>(TEXT("MassAgent"));
    }

    virtual void BeginPlay() override
    {
        Super::BeginPlay();

        // StateTree 시작
        if (StateTreeComponent && MonsterStateTree)
        {
            StateTreeComponent->SetStateTree(MonsterStateTree);
            StateTreeComponent->StartLogic();
        }
    }

    UPROPERTY(VisibleAnywhere)
    UStateTreeAIComponent* StateTreeComponent;

    UPROPERTY(EditAnywhere)
    UStateTree* MonsterStateTree;
};
```

---

## 5. 몬스터 행동 StateTree 예시

### 간단한 몬스터 AI: Idle → Chase → Attack

```
┌─────────────────────────────────────────────────────────────────────┐
│                    Monster StateTree 구조                            │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  [Root State]                                                        │
│  │                                                                   │
│  ├── [Idle State]                                                    │
│  │   ├── Enter: PlayIdleAnimation                                   │
│  │   ├── Task: WaitTask (계속 대기)                                 │
│  │   └── Transition:                                                 │
│  │       └── IF (PlayerDistance < 1500) → GOTO [Chase]              │
│  │                                                                   │
│  ├── [Chase State]                                                   │
│  │   ├── Enter: PlayRunAnimation                                    │
│  │   ├── Task: MoveToPlayerTask                                     │
│  │   └── Transitions:                                                │
│  │       ├── IF (PlayerDistance < 150) → GOTO [Attack]              │
│  │       └── IF (PlayerDistance > 2000) → GOTO [Idle]               │
│  │                                                                   │
│  └── [Attack State]                                                  │
│      ├── Enter: PlayAttackMontage                                   │
│      ├── Task: WaitForMontageEnd                                    │
│      ├── Task: ApplyDamageToPlayer                                  │
│      └── Transition:                                                 │
│          └── ON (TaskSucceeded) → GOTO [Chase]                      │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### Condition 만들기: 플레이어 거리

**Blueprint Condition**:
```
[Evaluator: Get Player Distance]
    │
    ▼
[Get Player Pawn] → [Get Actor Location]
    │
    ▼
[Get Owner] → [Get Actor Location]
    │
    ▼
[Vector Distance] → [Return: Distance Float]
```

**C++ Condition**:
```cpp
USTRUCT()
struct FPlayerDistanceCondition : public FStateTreeConditionCommonBase
{
    GENERATED_BODY()

    UPROPERTY(EditAnywhere)
    float DistanceThreshold = 1000.0f;

    UPROPERTY(EditAnywhere)
    bool bLessThan = true;  // true: 더 가까우면, false: 더 멀면

    virtual bool TestCondition(FStateTreeExecutionContext& Context) const override
    {
        AActor* Owner = Context.GetOwner();
        APawn* Player = UGameplayStatics::GetPlayerPawn(Owner->GetWorld(), 0);

        if (!Owner || !Player) return false;

        float Distance = FVector::Dist(Owner->GetActorLocation(), Player->GetActorLocation());

        return bLessThan ? (Distance < DistanceThreshold) : (Distance > DistanceThreshold);
    }
};
```

---

## 6. LOD별 행동 전략

### 거리에 따라 다른 행동 복잡도

```
┌─────────────────────────────────────────────────────────────────────┐
│                      LOD별 행동 복잡도                               │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  [High LOD: 0~50m, ~100마리]                                        │
│  └─ StateTree 사용 가능!                                            │
│     ├─ 복잡한 상태 전환                                             │
│     ├─ 애니메이션 몽타주                                            │
│     └─ 개별 AI 판단                                                 │
│                                                                      │
│  [Medium LOD: 50~200m, ~500마리]                                    │
│  └─ Processor 기반 단순 행동                                        │
│     ├─ 추적 (방향 벡터만)                                           │
│     ├─ 거리 기반 공격                                               │
│     └─ 상태는 Fragment로 관리                                       │
│                                                                      │
│  [Low LOD: 200m+, 나머지]                                           │
│  └─ 최소 행동만                                                     │
│     ├─ 플레이어 방향 이동만                                         │
│     └─ 복잡한 로직 없음                                             │
│                                                                      │
│  [Off LOD: 화면 밖]                                                 │
│  └─ 행동 스킵                                                       │
│     └─ 몇 프레임마다 한 번씩만 처리                                 │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### LOD 분기 Processor

```cpp
UCLASS()
class UMonsterBehaviorProcessor : public UMassProcessor
{
    virtual void Execute(FMassEntityManager& EntityManager,
                         FMassExecutionContext& Context) override
    {
        EntityQuery.ForEachEntityChunk(EntityManager, Context,
            [this](FMassExecutionContext& Context)
            {
                auto LODs = Context.GetFragmentView<FMassRepresentationLODFragment>();

                for (int32 i = 0; i < Context.GetNumEntities(); ++i)
                {
                    switch (LODs[i].LOD)
                    {
                        case EMassLOD::High:
                            // StateTree가 처리 (여기서 스킵)
                            break;

                        case EMassLOD::Medium:
                            ProcessMediumLODBehavior(Context, i);
                            break;

                        case EMassLOD::Low:
                            ProcessLowLODBehavior(Context, i);
                            break;

                        case EMassLOD::Off:
                            // 처리 안 함
                            break;
                    }
                }
            });
    }

    void ProcessMediumLODBehavior(FMassExecutionContext& Context, int32 Index)
    {
        // 단순 추적 + 공격 (상태 Fragment 사용)
    }

    void ProcessLowLODBehavior(FMassExecutionContext& Context, int32 Index)
    {
        // 플레이어 방향 이동만
    }
};
```

---

## 7. 뱀파이어 서바이벌 스타일 행동

### 전체 구조

```
┌─────────────────────────────────────────────────────────────────────┐
│              뱀파이어 서바이벌 몬스터 행동 아키텍처                    │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  [모든 LOD 공통 - Processor]                                        │
│  ├─ ChaseProcessor: 플레이어 방향 이동                              │
│  ├─ SeparationProcessor: 몬스터끼리 겹침 방지                       │
│  └─ MovementApplyProcessor: 실제 이동 적용                          │
│                                                                      │
│  [High LOD만 - StateTree 또는 Processor]                            │
│  ├─ AttackProcessor: 근접 공격 (범위 체크)                          │
│  └─ StateTree: 복잡한 패턴 (선택적)                                 │
│                                                                      │
│  [이벤트 - Signal]                                                  │
│  ├─ MonsterHit → 피격 애니메이션                                    │
│  ├─ MonsterDeath → 사망 처리, 아이템 드랍                           │
│  └─ PlayerHit → UI 업데이트, 사운드                                 │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### 군집 분리 (Separation) - 겹침 방지

몬스터들이 서로 겹치지 않게 하는 로직:

```cpp
UCLASS()
class UMonsterSeparationProcessor : public UMassProcessor
{
public:
    UPROPERTY(EditAnywhere)
    float SeparationRadius = 80.0f;  // 다른 몬스터와 최소 거리

    UPROPERTY(EditAnywhere)
    float SeparationForce = 100.0f;  // 밀어내는 힘

    virtual void Execute(...) override
    {
        // 1. 공간 해싱으로 근처 몬스터 빠르게 찾기
        // 2. 가까운 몬스터 방향 반대로 힘 적용

        EntityQuery.ForEachEntityChunk(EntityManager, Context,
            [=](FMassExecutionContext& Context)
            {
                auto Transforms = Context.GetFragmentView<FTransformFragment>();
                auto Velocities = Context.GetMutableFragmentView<FMassVelocityFragment>();

                for (int32 i = 0; i < Context.GetNumEntities(); ++i)
                {
                    FVector MyPos = Transforms[i].Transform.GetLocation();
                    FVector PushForce = FVector::ZeroVector;

                    // 같은 청크 내 다른 몬스터와 분리
                    for (int32 j = 0; j < Context.GetNumEntities(); ++j)
                    {
                        if (i == j) continue;

                        FVector OtherPos = Transforms[j].Transform.GetLocation();
                        FVector Diff = MyPos - OtherPos;
                        float Dist = Diff.Size();

                        if (Dist > 0 && Dist < SeparationRadius)
                        {
                            // 가까울수록 강하게 밀어냄
                            float Strength = 1.0f - (Dist / SeparationRadius);
                            PushForce += Diff.GetSafeNormal() * Strength * SeparationForce;
                        }
                    }

                    // 분리력 적용
                    Velocities[i].Value += PushForce;
                }
            });
    }
};
```

---

## 8. 흔한 문제와 해결책

### 문제 1: "플레이어 위치를 매번 가져오면 느린가요?"

**해결**: 캐싱!

```cpp
// Processor 멤버 변수로 캐싱
FVector CachedPlayerLocation;
int32 CacheFrame = -1;

FVector GetPlayerLocation()
{
    int32 CurrentFrame = GFrameNumber;
    if (CurrentFrame != CacheFrame)
    {
        // 프레임당 한 번만 업데이트
        CacheFrame = CurrentFrame;
        if (APawn* Player = UGameplayStatics::GetPlayerPawn(GetWorld(), 0))
        {
            CachedPlayerLocation = Player->GetActorLocation();
        }
    }
    return CachedPlayerLocation;
}
```

### 문제 2: "Signal이 안 와요"

**체크리스트**:
```
□ Signal 이름이 정확히 일치하는가?
□ SignalSubsystem을 올바르게 가져왔는가?
□ Signal Processor가 SubscribeToSignal을 호출했는가?
□ Entity Handle이 유효한가?
```

### 문제 3: "StateTree가 실행 안 돼요"

**체크리스트**:
```
□ StateTreeAIComponent가 추가되어 있는가?
□ StateTree 에셋이 설정되어 있는가?
□ BeginPlay에서 StartLogic()을 호출했는가?
□ Schema가 올바르게 설정되어 있는가?
```

---

## 9. 다음 단계

행동 로직 시스템을 이해했다면, 다음 문서에서 Ability System 통합을 살펴보겠습니다:

- **다음**: [06_AbilitySystemIntegration.md](06_AbilitySystemIntegration.md) - GAS와 Mass AI 병행 사용 전략

### 이 문서에서 배운 것

1. **Processor 행동**: 간단한 추적/공격을 Processor로 구현
2. **Signal 시스템**: 이벤트 기반 통신 (피격, 사망)
3. **StateTree**: 복잡한 상태 기계 (High LOD용)
4. **StateTree Task**: 블루프린트/C++로 커스텀 행동 정의
5. **LOD별 전략**: 거리에 따라 행동 복잡도 조절
6. **군집 분리**: 몬스터 겹침 방지
