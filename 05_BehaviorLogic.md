# 행동 로직 시스템

> **문서 목적**: StateTree, Signal, Smart Objects를 활용한 몬스터 행동 구현 방법 이해

---

## 1. 행동 로직 아키텍처 개요

Mass AI에서 행동 로직을 구현하는 방법은 여러 가지입니다:

```
┌─────────────────────────────────────────────────────────────────┐
│                     행동 로직 계층                               │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌─────────────────┐                                            │
│  │   StateTree     │  ← 복잡한 상태 기반 행동 (High LOD)        │
│  │   (선택적)      │                                            │
│  └────────┬────────┘                                            │
│           │                                                      │
│  ┌────────▼────────┐                                            │
│  │   Signal        │  ← 이벤트 기반 통신 (모든 LOD)             │
│  │   System        │                                            │
│  └────────┬────────┘                                            │
│           │                                                      │
│  ┌────────▼────────┐                                            │
│  │   Processor     │  ← 기본 행동 로직 (모든 LOD)               │
│  │   (직접 구현)   │                                            │
│  └─────────────────┘                                            │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## 2. Processor 기반 단순 행동

### 플레이어 추적 Processor

가장 기본적인 행동: 플레이어를 향해 이동

```cpp
UCLASS()
class UMonsterChasePlayerProcessor : public UMassProcessor
{
    GENERATED_BODY()

public:
    UMonsterChasePlayerProcessor()
    {
        ProcessingPhase = EMassProcessingPhase::PrePhysics;
        // 이동 적용 전에 실행
        ExecutionOrder.ExecuteBefore.Add(UMassApplyMovementProcessor::StaticClass());
    }

    virtual void ConfigureQueries() override
    {
        EntityQuery.AddRequirement<FTransformFragment>(EMassFragmentAccess::ReadOnly);
        EntityQuery.AddRequirement<FMassDesiredMovementFragment>(EMassFragmentAccess::ReadWrite);
        EntityQuery.AddRequirement<FMonsterTag>(EMassFragmentPresence::All);

        // 죽은 몬스터 제외
        EntityQuery.AddRequirement<FDeadTag>(EMassFragmentPresence::None);
    }

    virtual void Execute(FMassEntityManager& EntityManager,
                         FMassExecutionContext& Context) override
    {
        // 플레이어 위치 캐싱
        FVector PlayerLocation = GetPlayerLocation();

        EntityQuery.ForEachEntityChunk(EntityManager, Context,
            [PlayerLocation](FMassExecutionContext& Context)
            {
                auto Transforms = Context.GetFragmentView<FTransformFragment>();
                auto Movements = Context.GetMutableFragmentView<FMassDesiredMovementFragment>();

                const int32 NumEntities = Context.GetNumEntities();
                for (int32 i = 0; i < NumEntities; ++i)
                {
                    // 플레이어 방향 계산
                    FVector MyLocation = Transforms[i].Transform.GetLocation();
                    FVector Direction = (PlayerLocation - MyLocation).GetSafeNormal();

                    // 원하는 속도 설정 (이동 Processor가 적용)
                    Movements[i].DesiredVelocity = Direction * 400.0f;  // 400 cm/s
                    Movements[i].DesiredFacing = Direction.Rotation();
                }
            });
    }

private:
    FVector GetPlayerLocation() const
    {
        // 플레이어 위치 가져오기 (캐싱 권장)
        if (APlayerController* PC = GetWorld()->GetFirstPlayerController())
        {
            if (APawn* Pawn = PC->GetPawn())
            {
                return Pawn->GetActorLocation();
            }
        }
        return FVector::ZeroVector;
    }
};
```

### 범위 기반 공격 Processor

```cpp
UCLASS()
class UMonsterAttackProcessor : public UMassProcessor
{
    GENERATED_BODY()

public:
    UPROPERTY(EditAnywhere)
    float AttackRange = 100.0f;

    UPROPERTY(EditAnywhere)
    float AttackCooldown = 1.0f;

    virtual void ConfigureQueries() override
    {
        EntityQuery.AddRequirement<FTransformFragment>(EMassFragmentAccess::ReadOnly);
        EntityQuery.AddRequirement<FMonsterCombatFragment>(EMassFragmentAccess::ReadWrite);
        EntityQuery.AddRequirement<FMonsterTag>(EMassFragmentPresence::All);
        EntityQuery.AddRequirement<FDeadTag>(EMassFragmentPresence::None);
    }

    virtual void Execute(FMassEntityManager& EntityManager,
                         FMassExecutionContext& Context) override
    {
        FVector PlayerLocation = GetPlayerLocation();
        float AttackRangeSq = FMath::Square(AttackRange);
        float DeltaTime = Context.GetDeltaTimeSeconds();

        EntityQuery.ForEachEntityChunk(EntityManager, Context,
            [=](FMassExecutionContext& Context)
            {
                auto Transforms = Context.GetFragmentView<FTransformFragment>();
                auto Combats = Context.GetMutableFragmentView<FMonsterCombatFragment>();

                for (int32 i = 0; i < Context.GetNumEntities(); ++i)
                {
                    // 쿨다운 감소
                    Combats[i].AttackCooldownRemaining -= DeltaTime;

                    // 거리 체크
                    float DistSq = FVector::DistSquared(
                        Transforms[i].Transform.GetLocation(),
                        PlayerLocation);

                    if (DistSq <= AttackRangeSq &&
                        Combats[i].AttackCooldownRemaining <= 0.0f)
                    {
                        // 공격 실행
                        Combats[i].bIsAttacking = true;
                        Combats[i].AttackCooldownRemaining = AttackCooldown;

                        // 데미지 적용 (Signal로 전달 가능)
                        // ...
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

### 전투 Fragment

```cpp
USTRUCT()
struct FMonsterCombatFragment : public FMassFragment
{
    GENERATED_BODY()

    UPROPERTY()
    float AttackDamage = 10.0f;

    UPROPERTY()
    float AttackCooldownRemaining = 0.0f;

    UPROPERTY()
    bool bIsAttacking = false;

    UPROPERTY()
    FMassEntityHandle CurrentTarget;
};
```

---

## 3. Signal 시스템

Signal은 Mass 엔티티 간의 **이벤트 통신** 메커니즘입니다.

### 소스 위치
```
C:\Program Files\Epic Games\UE_5.7.1\UE_5.7\Engine\Plugins\Runtime\MassGameplay\Source\MassSignals\Public\
```

### Signal Subsystem

```cpp
// MassSignalSubsystem.h
UCLASS()
class UMassSignalSubsystem : public UWorldSubsystem
{
    GENERATED_BODY()

public:
    // 단일 엔티티에 신호 전송
    void SignalEntity(FName SignalName, FMassEntityHandle Entity);

    // 여러 엔티티에 신호 전송
    void SignalEntities(FName SignalName, TArrayView<FMassEntityHandle> Entities);

    // 지연 신호 전송
    void DelaySignalEntity(FName SignalName, FMassEntityHandle Entity, float Delay);

    // Command Buffer를 통한 지연 신호
    void SignalEntityDeferred(FName SignalName, FMassEntityHandle Entity,
                              FMassCommandBuffer& CommandBuffer);
};
```

### Signal Processor 기본 클래스

```cpp
// Signal에 반응하는 Processor
UCLASS()
class UMassSignalProcessorBase : public UMassProcessor
{
    GENERATED_BODY()

public:
    // 수신할 신호 등록
    void SubscribeToSignal(FName SignalName);

    // 신호 수신 시 호출 (오버라이드)
    virtual void SignalEntities(FMassEntityManager& EntityManager,
                                FMassExecutionContext& Context,
                                FMassSignalNameLookup& EntitySignals) PURE_VIRTUAL;
};
```

### Signal 사용 예시

**1. 신호 정의**
```cpp
// MonsterSignals.h
namespace MonsterSignals
{
    const FName PlayerDetected = TEXT("PlayerDetected");
    const FName PlayerLost = TEXT("PlayerLost");
    const FName TakeDamage = TEXT("TakeDamage");
    const FName Death = TEXT("Death");
    const FName AttackHit = TEXT("AttackHit");
}
```

**2. 신호 전송**
```cpp
// 플레이어 감지 시 신호 전송
void UDetectionProcessor::Execute(...)
{
    UMassSignalSubsystem* SignalSubsystem =
        GetWorld()->GetSubsystem<UMassSignalSubsystem>();

    EntityQuery.ForEachEntityChunk(...,
        [SignalSubsystem](FMassExecutionContext& Context)
        {
            for (int32 i = 0; i < Context.GetNumEntities(); ++i)
            {
                if (DetectedPlayer(i))
                {
                    // 신호 전송
                    SignalSubsystem->SignalEntity(
                        MonsterSignals::PlayerDetected,
                        Context.GetEntity(i));
                }
            }
        });
}
```

**3. 신호 수신**
```cpp
UCLASS()
class UMonsterAlertProcessor : public UMassSignalProcessorBase
{
    GENERATED_BODY()

public:
    UMonsterAlertProcessor()
    {
        // 수신할 신호 등록
        SubscribeToSignal(MonsterSignals::PlayerDetected);
        SubscribeToSignal(MonsterSignals::TakeDamage);
    }

    virtual void SignalEntities(FMassEntityManager& EntityManager,
                                FMassExecutionContext& Context,
                                FMassSignalNameLookup& EntitySignals) override
    {
        // PlayerDetected 신호를 받은 엔티티 처리
        TArray<FMassEntityHandle> DetectedEntities;
        EntitySignals.GetEntitiesForSignal(MonsterSignals::PlayerDetected,
                                            DetectedEntities);

        for (FMassEntityHandle Entity : DetectedEntities)
        {
            // 경계 상태로 전환
            if (FMonsterStateFragment* State =
                EntityManager.GetFragmentDataPtr<FMonsterStateFragment>(Entity))
            {
                State->CurrentState = EMonsterState::Alert;
            }
        }
    }
};
```

---

## 4. StateTree 통합

StateTree는 **복잡한 상태 기반 행동**을 위한 비주얼 스크립팅 시스템입니다.

### 소스 위치
```
C:\Program Files\Epic Games\UE_5.7.1\UE_5.7\Engine\Plugins\Runtime\GameplayStateTree\Source\GameplayStateTreeModule\Public\
```

### StateTree AI Component

```cpp
// High LOD Actor에서 StateTree 사용
UCLASS()
class ABP_Monster_HighRes : public AActor
{
    GENERATED_BODY()

public:
    ABP_Monster_HighRes()
    {
        // StateTree AI 컴포넌트 추가
        StateTreeComponent = CreateDefaultSubobject<UStateTreeAIComponent>(TEXT("StateTree"));

        // Mass Agent 컴포넌트
        MassAgent = CreateDefaultSubobject<UMassAgentComponent>(TEXT("MassAgent"));
    }

    UPROPERTY(VisibleAnywhere)
    UStateTreeAIComponent* StateTreeComponent;

    UPROPERTY(VisibleAnywhere)
    UMassAgentComponent* MassAgent;
};
```

### StateTree 에셋 생성

에디터에서:
1. Content Browser → 우클릭 → AI → StateTree
2. StateTree 에디터에서 상태 및 전환 정의

### StateTree 기본 구조

```
┌─────────────────────────────────────────────────────────────────┐
│                        StateTree Asset                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Root State                                                      │
│  ├── Idle State                                                  │
│  │   ├── Enter: PlayIdleAnimation                                │
│  │   ├── Tick: CheckPlayerDistance                               │
│  │   └── Transition: PlayerNear → Chase                          │
│  │                                                               │
│  ├── Chase State                                                 │
│  │   ├── Enter: PlayRunAnimation                                 │
│  │   ├── Task: MoveToTarget (FStateTreeMoveToTask)              │
│  │   ├── Transition: InRange → Attack                            │
│  │   └── Transition: PlayerFar → Idle                            │
│  │                                                               │
│  └── Attack State                                                │
│      ├── Enter: PlayAttackAnimation                              │
│      ├── Task: DealDamage                                        │
│      └── Transition: AttackDone → Chase                          │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### StateTree Task 예시

```cpp
// 이동 Task (내장)
// GameplayStateTree/Tasks/StateTreeMoveToTask.h
USTRUCT()
struct FStateTreeMoveToTask : public FStateTreeAIActionTaskBase
{
    GENERATED_BODY()

    // 목표 위치
    UPROPERTY(EditAnywhere, Category = "Parameter")
    FVector TargetLocation;

    // 허용 반경
    UPROPERTY(EditAnywhere, Category = "Parameter")
    float AcceptableRadius = 50.0f;

    // 부분 경로 허용
    UPROPERTY(EditAnywhere, Category = "Parameter")
    bool bAllowPartialPath = true;
};
```

### 커스텀 StateTree Task

```cpp
// 공격 Task
USTRUCT()
struct FMonsterAttackTask : public FStateTreeAIActionTaskBase
{
    GENERATED_BODY()

    UPROPERTY(EditAnywhere, Category = "Parameter")
    float Damage = 10.0f;

    UPROPERTY(EditAnywhere, Category = "Parameter")
    UAnimMontage* AttackMontage;

    virtual EStateTreeRunStatus EnterState(
        FStateTreeExecutionContext& Context,
        const FStateTreeTransitionResult& Transition) const override
    {
        // 공격 애니메이션 재생
        if (AActor* Actor = GetActor(Context))
        {
            if (USkeletalMeshComponent* Mesh =
                Actor->FindComponentByClass<USkeletalMeshComponent>())
            {
                if (UAnimInstance* AnimInst = Mesh->GetAnimInstance())
                {
                    AnimInst->Montage_Play(AttackMontage);
                }
            }
        }
        return EStateTreeRunStatus::Running;
    }

    virtual EStateTreeRunStatus Tick(
        FStateTreeExecutionContext& Context,
        const float DeltaTime) const override
    {
        // 몽타주 완료 체크
        if (AActor* Actor = GetActor(Context))
        {
            if (USkeletalMeshComponent* Mesh =
                Actor->FindComponentByClass<USkeletalMeshComponent>())
            {
                if (UAnimInstance* AnimInst = Mesh->GetAnimInstance())
                {
                    if (!AnimInst->Montage_IsPlaying(AttackMontage))
                    {
                        return EStateTreeRunStatus::Succeeded;
                    }
                }
            }
        }
        return EStateTreeRunStatus::Running;
    }
};
```

---

## 5. Smart Objects

Smart Objects는 **환경과의 상호작용**을 정의합니다.

### 소스 위치
```
C:\Program Files\Epic Games\UE_5.7.1\UE_5.7\Engine\Plugins\Runtime\MassGameplay\Source\MassSmartObjects\Public\
```

### Smart Object Fragment

```cpp
// MassSmartObjectFragments.h
USTRUCT()
struct FMassSmartObjectUserFragment : public FMassFragment
{
    GENERATED_BODY()

    // 현재 상호작용 핸들
    FSmartObjectClaimHandle ClaimHandle;

    // 상호작용 상태
    EMassSmartObjectInteractionStatus Status = EMassSmartObjectInteractionStatus::None;

    // 쿨다운
    float InteractionCooldown = 0.0f;
};
```

### Smart Object 사용

```cpp
// 몬스터가 Smart Object와 상호작용
// 예: 특정 지점에서 대기, 순찰 포인트 등

// 1. Smart Object User Trait 추가
UCLASS()
class UMonsterSmartObjectTrait : public UMassSmartObjectUserTrait
{
    // 필요한 행동 정의 설정
};

// 2. Smart Object Actor 배치 (레벨에)
// - Patrol Point, Cover Position 등

// 3. Processor에서 Smart Object 탐색 및 사용
void UMonsterSmartObjectProcessor::Execute(...)
{
    // UMassSmartObjectCandidatesFinderProcessor가
    // 자동으로 근처 Smart Object 탐색
}
```

---

## 6. 뱀파이어 서바이벌 스타일 행동 구현

### 단순 추적 + 근접 공격 패턴

```cpp
// 간단한 뱀서 스타일 몬스터 Processor
UCLASS()
class USimpleSurvivorMonsterProcessor : public UMassProcessor
{
    GENERATED_BODY()

public:
    UPROPERTY(EditAnywhere)
    float ChaseSpeed = 300.0f;

    UPROPERTY(EditAnywhere)
    float AttackRange = 80.0f;

    UPROPERTY(EditAnywhere)
    float AttackDamage = 5.0f;

    UPROPERTY(EditAnywhere)
    float AttackCooldown = 1.5f;

    virtual void ConfigureQueries() override
    {
        EntityQuery.AddRequirement<FTransformFragment>(EMassFragmentAccess::ReadOnly);
        EntityQuery.AddRequirement<FMassDesiredMovementFragment>(EMassFragmentAccess::ReadWrite);
        EntityQuery.AddRequirement<FMonsterCombatFragment>(EMassFragmentAccess::ReadWrite);
        EntityQuery.AddRequirement<FMonsterTag>(EMassFragmentPresence::All);
        EntityQuery.AddRequirement<FDeadTag>(EMassFragmentPresence::None);
    }

    virtual void Execute(FMassEntityManager& EntityManager,
                         FMassExecutionContext& Context) override
    {
        const FVector PlayerLocation = GetCachedPlayerLocation();
        const float AttackRangeSq = FMath::Square(AttackRange);
        const float DeltaTime = Context.GetDeltaTimeSeconds();

        EntityQuery.ForEachEntityChunk(EntityManager, Context,
            [=](FMassExecutionContext& Context)
            {
                auto Transforms = Context.GetFragmentView<FTransformFragment>();
                auto Movements = Context.GetMutableFragmentView<FMassDesiredMovementFragment>();
                auto Combats = Context.GetMutableFragmentView<FMonsterCombatFragment>();

                for (int32 i = 0; i < Context.GetNumEntities(); ++i)
                {
                    const FVector MyLocation = Transforms[i].Transform.GetLocation();
                    const FVector ToPlayer = PlayerLocation - MyLocation;
                    const float DistSq = ToPlayer.SizeSquared();

                    // 쿨다운 감소
                    Combats[i].AttackCooldownRemaining =
                        FMath::Max(0.0f, Combats[i].AttackCooldownRemaining - DeltaTime);

                    if (DistSq <= AttackRangeSq)
                    {
                        // 공격 범위 내: 멈추고 공격
                        Movements[i].DesiredVelocity = FVector::ZeroVector;

                        if (Combats[i].AttackCooldownRemaining <= 0.0f)
                        {
                            Combats[i].bIsAttacking = true;
                            Combats[i].AttackCooldownRemaining = AttackCooldown;
                            // 데미지는 별도 시스템에서 처리
                        }
                    }
                    else
                    {
                        // 추적
                        const FVector Direction = ToPlayer.GetSafeNormal();
                        Movements[i].DesiredVelocity = Direction * ChaseSpeed;
                        Movements[i].DesiredFacing = Direction.Rotation();
                        Combats[i].bIsAttacking = false;
                    }
                }
            });
    }
};
```

### 군집 회피 (Separation)

```cpp
UCLASS()
class UMonsterSeparationProcessor : public UMassProcessor
{
    GENERATED_BODY()

public:
    UPROPERTY(EditAnywhere)
    float SeparationRadius = 100.0f;

    UPROPERTY(EditAnywhere)
    float SeparationStrength = 200.0f;

    virtual void Execute(FMassEntityManager& EntityManager,
                         FMassExecutionContext& Context) override
    {
        // 간단한 공간 해싱 또는 그리드 기반 이웃 탐색
        // (실제로는 더 효율적인 알고리즘 필요)

        TArray<FVector> AllPositions;
        // 모든 몬스터 위치 수집...

        EntityQuery.ForEachEntityChunk(EntityManager, Context,
            [=, &AllPositions](FMassExecutionContext& Context)
            {
                auto Transforms = Context.GetFragmentView<FTransformFragment>();
                auto Forces = Context.GetMutableFragmentView<FMassForceFragment>();

                for (int32 i = 0; i < Context.GetNumEntities(); ++i)
                {
                    FVector SeparationForce = FVector::ZeroVector;
                    FVector MyPos = Transforms[i].Transform.GetLocation();

                    // 근처 몬스터와의 분리력 계산
                    for (const FVector& OtherPos : AllPositions)
                    {
                        FVector Diff = MyPos - OtherPos;
                        float Dist = Diff.Size();
                        if (Dist > 0.0f && Dist < SeparationRadius)
                        {
                            // 거리에 반비례하는 밀어내기 힘
                            SeparationForce += Diff.GetSafeNormal() *
                                (1.0f - Dist / SeparationRadius) * SeparationStrength;
                        }
                    }

                    Forces[i].Value += SeparationForce;
                }
            });
    }
};
```

---

## 7. LOD별 행동 복잡도

### 행동 복잡도 전략

| LOD | 행동 복잡도 | 구현 방법 |
|-----|------------|-----------|
| High | 풀 행동 | StateTree + AnimBP |
| Medium | 단순 행동 | Processor 기반 |
| Low | 최소 행동 | 추적만 |
| Off | 로직 없음 | 틱 스킵 |

### LOD 기반 Processor 분기

```cpp
UCLASS()
class UMonsterBehaviorProcessor : public UMassProcessor
{
    virtual void Execute(FMassEntityManager& EntityManager,
                         FMassExecutionContext& Context) override
    {
        EntityQuery.ForEachEntityChunk(EntityManager, Context,
            [](FMassExecutionContext& Context)
            {
                auto LODs = Context.GetFragmentView<FMassRepresentationLODFragment>();
                auto Movements = Context.GetMutableFragmentView<FMassDesiredMovementFragment>();

                for (int32 i = 0; i < Context.GetNumEntities(); ++i)
                {
                    switch (LODs[i].LOD)
                    {
                        case EMassLOD::High:
                            // High LOD: StateTree가 처리 (이 Processor에서 스킵)
                            break;

                        case EMassLOD::Medium:
                            // Medium LOD: 단순 추적 + 공격
                            ProcessMediumLOD(i, Movements[i]);
                            break;

                        case EMassLOD::Low:
                            // Low LOD: 추적만
                            ProcessLowLOD(i, Movements[i]);
                            break;

                        case EMassLOD::Off:
                            // Off: 아무것도 안 함
                            break;
                    }
                }
            });
    }
};
```

---

## 8. 핵심 포인트 정리

### 뱀파이어 서바이벌 스타일 권장 구조

1. **플레이어 추적**: 단순 방향 벡터 계산 (Processor)
2. **공격**: 거리 체크 + 쿨다운 (Processor)
3. **피격**: Signal로 데미지 이벤트 전파
4. **죽음**: Signal + Tag 추가 + 지연 삭제
5. **군집**: 분리력 계산 (선택적)

### Signal 활용

- `MonsterHit`: 몬스터 피격 시
- `MonsterDeath`: 몬스터 사망 시
- `PlayerHit`: 플레이어 피격 시
- `ItemDrop`: 아이템 드랍 시

### StateTree는 선택적

- High LOD Actor에서만 사용
- 복잡한 패턴(보스 등)에 유용
- 일반 잡몹은 Processor만으로 충분

---

## 9. 다음 단계

행동 로직 시스템을 이해했다면, 다음 문서에서 Ability System 통합을 살펴보겠습니다:

- **다음**: [06_AbilitySystemIntegration.md](06_AbilitySystemIntegration.md) - GAS와 Mass AI 병행 사용 전략
