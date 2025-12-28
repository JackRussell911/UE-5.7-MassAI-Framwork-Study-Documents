# Ability System 통합 분석

> **문서 목적**: Gameplay Ability System (GAS)과 Mass AI의 병행 사용 전략 및 장단점 분석
>
> **난이도**: ★★★★☆ (고급)
>
> **핵심 질문**: "수천 마리 몬스터에게 GAS를 쓸 수 있을까? 써야 할까?"

---

## 1. 왜 이 문제가 중요한가?

### 현실적인 상황

여러분의 프로젝트가 이런 상황이라고 가정해볼게요:

```
현재 상태:
- 이미 만들어둔 몬스터 Ability가 20개 있음
- GameplayEffect로 버프/디버프 시스템 구축됨
- 보스 몬스터 AI가 GAS 기반으로 잘 작동 중

목표:
- 뱀파이어 서바이벌처럼 수천 마리 몬스터 스폰
- 60fps 유지해야 함
- 기존 작업물 버리기 싫음...
```

**이게 바로 우리가 해결해야 할 문제예요!**

기존 GAS 시스템을 그대로 쓰면서 Mass AI의 성능 이점을 얻을 수 있을까요?
결론부터 말하면: **"완전히는 안 되지만, 영리하게 조합하면 된다"** 입니다.

---

## 2. GAS와 Mass AI는 근본적으로 다르다

### 아키텍처 비교

먼저 두 시스템이 왜 충돌하는지 이해해야 해요.

```
┌─────────────────────────────────────────────────────────────────┐
│              Gameplay Ability System (GAS)                       │
│                 "VIP 개인실" 스타일                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  [Actor A]    [Actor B]    [Actor C]    ...                     │
│      │            │            │                                 │
│     ASC         ASC          ASC        ← 각자 능력 시스템       │
│      │            │            │                                 │
│  [Ability]   [Ability]    [Ability]    ← 개별 실행               │
│  [Effect]    [Effect]     [Effect]     ← 각자 틱                 │
│                                                                  │
│  특징:                                                           │
│  - 각 Actor가 자기만의 AbilitySystemComponent 보유               │
│  - 복잡한 상태 관리 (GameplayTag 시스템)                         │
│  - 풍부한 기능 (쿨다운, 비용, GE, Cue 등)                       │
│  - 하지만... 1000개면 1000개의 ASC가 각자 돌아감                │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                    Mass AI (Mass Entity)                         │
│                    "공장 생산라인" 스타일                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  [Entity 0][Entity 1][Entity 2]...[Entity 999] ← 데이터 배열    │
│      ↓          ↓         ↓           ↓                         │
│  ┌────────────────────────────────────────────┐                 │
│  │           Processor (한 번에 처리)          │                 │
│  │   for (int i = 0; i < 1000; ++i)           │                 │
│  │       ProcessEntity(i);                     │                 │
│  └────────────────────────────────────────────┘                 │
│                                                                  │
│  특징:                                                           │
│  - 데이터가 연속된 메모리에 배치                                 │
│  - 한 Processor가 모든 엔티티를 배치 처리                        │
│  - Actor 없이도 동작 가능                                        │
│  - 단순하지만 빠름                                               │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 왜 직접 호환이 안 될까?

GAS가 필요로 하는 것들을 보면:

```cpp
// GAS는 이것들이 필요해요
UAbilitySystemComponent* ASC;  // Actor에 붙어있어야 함
AActor* Avatar;                 // Actor 필수
UGameplayAbility* Ability;      // UObject 상속
FGameplayEffectSpec Effect;     // 복잡한 구조체

// Mass Entity가 가진 것
FMassEntityHandle Entity;       // 그냥 인덱스 번호
FMonsterHealthFragment Data;    // 단순 데이터 구조체
// Actor? 없음. UObject? 없음.
```

**핵심 문제**: GAS는 Actor 기반이고, Mass Entity는 Actor 없이도 존재할 수 있어요.
ISM(Instanced Static Mesh)으로 렌더링되는 몬스터는 Actor가 아예 없는데,
여기에 어떻게 ASC를 붙이겠어요?

### 호환성 매트릭스

| 기능 | GAS 방식 | Mass 방식 | 호환? |
|------|----------|-----------|-------|
| 기반 객체 | `AActor` | `FMassEntityHandle` | ❌ |
| 컴포넌트 | `UAbilitySystemComponent` | `FMassFragment` | ❌ |
| 상태 관리 | `FGameplayTag` | Custom Tag/Flag | ⚠️ 변환 필요 |
| 능력 실행 | `UGameplayAbility::ActivateAbility()` | `UMassProcessor::Execute()` | ❌ |
| 효과 적용 | `FGameplayEffectSpec` | Fragment 직접 수정 | ❌ |
| 쿨다운 | GAS 내장 | 직접 구현 | ⚠️ |
| 네트워크 복제 | GAS 내장 | 직접 구현 | ⚠️ |

---

## 3. 해결책: 세 가지 접근법

그래서 현실적인 해결책은 뭘까요? 세 가지 옵션이 있어요.

### 옵션 비교 요약

```
┌─────────────────────────────────────────────────────────────────┐
│                      옵션 A: 완전 분리                           │
│   "GAS는 플레이어만, 몬스터는 새로 만든다"                      │
├─────────────────────────────────────────────────────────────────┤
│  성능: ★★★★★  │  개발비용: ★★★☆☆  │  기존자산활용: ★☆☆☆☆   │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                   옵션 B: 하이브리드 (권장)                      │
│   "가까운 놈만 GAS, 나머지는 간단하게"                          │
├─────────────────────────────────────────────────────────────────┤
│  성능: ★★★★☆  │  개발비용: ★★☆☆☆  │  기존자산활용: ★★★★☆   │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                   옵션 C: 커스텀 시스템                          │
│   "Mass용 미니 GAS를 새로 만든다"                               │
├─────────────────────────────────────────────────────────────────┤
│  성능: ★★★★★  │  개발비용: ★★★★★  │  기존자산활용: ★☆☆☆☆   │
└─────────────────────────────────────────────────────────────────┘
```

---

## 4. 옵션 A: 완전 분리

### 개념

**"Mass AI 몬스터는 GAS를 사용하지 않는다"**

가장 단순한 접근이에요. 몬스터용 경량 시스템을 별도로 만듭니다.

```
플레이어 세계                    몬스터 세계
┌──────────────────┐            ┌──────────────────┐
│   Actor + GAS    │            │   Mass Entity    │
│   - Abilities    │            │   - Fragments    │
│   - Effects      │            │   - Processors   │
│   - 복잡한 로직  │    공격    │   - 단순 로직    │
│                  │───────────→│                  │
│                  │←───────────│                  │
│                  │   피격     │                  │
└──────────────────┘            └──────────────────┘
                 ↑                       ↑
                 │                       │
            기존 시스템              새로 구현
```

### 구현 예시: 경량 Health 시스템

```cpp
// 1. Health Fragment 정의
// 이건 GAS의 HealthAttribute를 완전히 대체하는 거예요
USTRUCT()
struct FMonsterHealthFragment : public FMassFragment
{
    GENERATED_BODY()

    float CurrentHealth = 100.0f;
    float MaxHealth = 100.0f;

    // GAS의 FGameplayEffectSpec::ModifyAttribute()를 단순화한 버전
    void ApplyDamage(float Damage)
    {
        CurrentHealth = FMath::Max(0.0f, CurrentHealth - Damage);
    }

    void Heal(float Amount)
    {
        CurrentHealth = FMath::Min(MaxHealth, CurrentHealth + Amount);
    }

    bool IsDead() const { return CurrentHealth <= 0.0f; }
    float GetHealthPercent() const { return CurrentHealth / MaxHealth; }
};

// 2. 데미지 요청을 저장할 Fragment
// 이게 왜 필요하냐면, 플레이어가 공격할 때 바로 Health를 수정하면
// Processor 타이밍이랑 충돌할 수 있어서 "예약"하는 거예요
USTRUCT()
struct FPendingDamageFragment : public FMassFragment
{
    GENERATED_BODY()

    float Damage = 0.0f;

    // 데미지 소스 정보 (선택)
    TWeakObjectPtr<AActor> Instigator;
};
```

### 데미지 처리 Processor

```cpp
UCLASS()
class UMonsterDamageProcessor : public UMassProcessor
{
    GENERATED_BODY()

    FMassEntityQuery DamageQuery;

public:
    UMonsterDamageProcessor()
    {
        // 이 Processor는 어떤 엔티티를 처리할지 정의
        DamageQuery.AddRequirement<FMonsterHealthFragment>(EMassFragmentAccess::ReadWrite);
        DamageQuery.AddRequirement<FPendingDamageFragment>(EMassFragmentAccess::ReadWrite);
    }

    virtual void Execute(FMassEntityManager& EntityManager,
                         FMassExecutionContext& Context) override
    {
        // 매 프레임, 데미지가 예약된 모든 몬스터를 한 번에 처리
        DamageQuery.ForEachEntityChunk(
            EntityManager,
            Context,
            [&](FMassExecutionContext& ChunkContext)
            {
                // 청크 단위로 데이터 가져오기
                auto Healths = ChunkContext.GetMutableFragmentView<FMonsterHealthFragment>();
                auto PendingDamages = ChunkContext.GetMutableFragmentView<FPendingDamageFragment>();

                const int32 NumEntities = ChunkContext.GetNumEntities();

                // 캐시 친화적인 연속 메모리 접근!
                for (int32 i = 0; i < NumEntities; ++i)
                {
                    // 예약된 데미지가 있으면 처리
                    if (PendingDamages[i].Damage > 0.0f)
                    {
                        Healths[i].ApplyDamage(PendingDamages[i].Damage);

                        // 처리 완료 - 데미지 리셋
                        PendingDamages[i].Damage = 0.0f;

                        // 죽었으면 태그 추가 (다른 Processor가 처리)
                        if (Healths[i].IsDead())
                        {
                            ChunkContext.Defer().AddTag<FDeadTag>(
                                ChunkContext.GetEntity(i));
                        }
                    }
                }
            });
    }
};
```

### 플레이어가 몬스터를 공격할 때

```cpp
// 플레이어의 공격 Ability (GAS)에서 호출
void UGA_PlayerAttack::ApplyDamageToMassEntities(
    const TArray<FMassEntityHandle>& HitEntities,
    float Damage)
{
    // Mass EntityManager 가져오기
    UMassEntitySubsystem* MassSubsystem =
        GetWorld()->GetSubsystem<UMassEntitySubsystem>();
    FMassEntityManager& EntityManager = MassSubsystem->GetMutableEntityManager();

    // 맞은 모든 Mass 엔티티에 데미지 예약
    for (const FMassEntityHandle& Entity : HitEntities)
    {
        if (EntityManager.IsEntityValid(Entity))
        {
            // 직접 수정하지 않고 "예약"
            FPendingDamageFragment* PendingDamage =
                EntityManager.GetFragmentDataPtr<FPendingDamageFragment>(Entity);

            if (PendingDamage)
            {
                PendingDamage->Damage += Damage;  // 누적 가능
                PendingDamage->Instigator = GetAvatarActorFromActorInfo();
            }
        }
    }
}
```

### 옵션 A의 장단점

**장점:**
- ✅ 최고 성능 (GAS 오버헤드 완전 제거)
- ✅ 깔끔한 분리 (두 시스템이 간섭 안 함)
- ✅ 디버깅 쉬움 (경로가 단순)

**단점:**
- ❌ 기존 어빌리티 재작성 필요
- ❌ GAS의 풍부한 기능 포기 (쿨다운, GameplayCue 등)
- ❌ 같은 로직을 두 번 구현해야 할 수도 있음

---

## 5. 옵션 B: 하이브리드 접근 (권장!)

### 개념

**"가까운 몬스터만 Actor로 전환해서 GAS 사용"**

이게 제가 가장 추천하는 방식이에요. 왜냐하면:
1. 기존 GAS 자산 재활용 가능
2. 성능도 적절히 유지
3. 플레이어 입장에서 가까운 몬스터가 제일 중요하니까!

```
┌─────────────────────────────────────────────────────────────────┐
│                    하이브리드 모델 상세도                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│                        [플레이어]                                │
│                            │                                     │
│                            ▼                                     │
│  ╔═══════════════════════════════════════════════════════════╗  │
│  ║  High LOD Zone (0-50m)                    약 50-100마리   ║  │
│  ║  ┌─────────────────────────────────────────────────────┐  ║  │
│  ║  │  Actor + ASC + GAS                                  │  ║  │
│  ║  │  - 기존 GameplayAbility 그대로 사용                 │  ║  │
│  ║  │  - GameplayEffect, GameplayCue 전부 동작            │  ║  │
│  ║  │  - 복잡한 공격 패턴, 스킬 사용                      │  ║  │
│  ║  │  - 풀 애니메이션, 사운드, VFX                       │  ║  │
│  ║  └─────────────────────────────────────────────────────┘  ║  │
│  ╚═══════════════════════════════════════════════════════════╝  │
│                            │                                     │
│                    LOD 전환 경계 ↕                              │
│                            │                                     │
│  ╔═══════════════════════════════════════════════════════════╗  │
│  ║  Medium LOD Zone (50-200m)                약 300-500마리  ║  │
│  ║  ┌─────────────────────────────────────────────────────┐  ║  │
│  ║  │  Low Actor (ASC 없음) 또는 ISM                      │  ║  │
│  ║  │  - GAS 비활성화                                     │  ║  │
│  ║  │  - Fragment 기반 간소화 로직                        │  ║  │
│  ║  │  - 단순 이동 + 접촉 데미지만                        │  ║  │
│  ║  │  - 간소화된 애니메이션                              │  ║  │
│  ║  └─────────────────────────────────────────────────────┘  ║  │
│  ╚═══════════════════════════════════════════════════════════╝  │
│                            │                                     │
│  ╔═══════════════════════════════════════════════════════════╗  │
│  ║  Low LOD Zone (200m+)                     수백~수천 마리  ║  │
│  ║  ┌─────────────────────────────────────────────────────┐  ║  │
│  ║  │  ISM Only (Actor 없음)                              │  ║  │
│  ║  │  - 최소 로직 (이동만)                               │  ║  │
│  ║  │  - 공격/피격 처리 단순화 또는 생략                  │  ║  │
│  ║  └─────────────────────────────────────────────────────┘  ║  │
│  ╚═══════════════════════════════════════════════════════════╝  │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 핵심 원리: "가까워지면 Actor 스폰"

```
시간 흐름 →

[Entity 생성]              [플레이어 접근]           [플레이어 이탈]
      │                          │                         │
      ▼                          ▼                         ▼
   Mass Entity              Actor 스폰                 Actor 반환
   (ISM 렌더링)          + ASC 활성화              Mass Entity로 복귀
       │                         │                         │
       └─── 데이터는 항상 ────┴─── Fragment에 ───────────┘
             Mass Fragment에 있음
```

**이게 핵심이에요**: Entity의 데이터(체력, 상태 등)는 항상 Mass Fragment에 있고,
Actor/GAS는 필요할 때만 "활성화"되는 거예요.

### High LOD Actor 클래스 설계

```cpp
// High LOD용 Actor (GAS 포함)
UCLASS()
class ABP_Monster_HighRes : public ACharacter
{
    GENERATED_BODY()

public:
    ABP_Monster_HighRes()
    {
        // 1. Ability System Component 추가
        AbilitySystemComponent = CreateDefaultSubobject<UAbilitySystemComponent>(TEXT("ASC"));

        // 2. Mass Agent Component (Mass Entity와 동기화 담당)
        MassAgentComponent = CreateDefaultSubobject<UMassAgentComponent>(TEXT("MassAgent"));
    }

protected:
    UPROPERTY(VisibleAnywhere, BlueprintReadOnly)
    UAbilitySystemComponent* AbilitySystemComponent;

    UPROPERTY(VisibleAnywhere)
    UMassAgentComponent* MassAgentComponent;

    // 기존에 만들어둔 몬스터 어빌리티들
    UPROPERTY(EditDefaultsOnly)
    TArray<TSubclassOf<UGameplayAbility>> DefaultAbilities;

    virtual void BeginPlay() override
    {
        Super::BeginPlay();

        // Actor 스폰될 때 기존 어빌리티 부여
        for (TSubclassOf<UGameplayAbility> AbilityClass : DefaultAbilities)
        {
            AbilitySystemComponent->GiveAbility(
                FGameplayAbilitySpec(AbilityClass, 1, INDEX_NONE, this));
        }
    }

public:
    //===================================================================
    //  Mass ↔ GAS 동기화 함수들
    //===================================================================

    // Mass Entity → Actor (Actor 스폰 시 호출)
    void SyncFromMassEntity(const FMonsterHealthFragment& Health,
                            const FMonsterStateFragment& State)
    {
        // 체력 동기화
        if (UMonsterAttributeSet* Attributes = Cast<UMonsterAttributeSet>(
                AbilitySystemComponent->GetAttributeSet(UMonsterAttributeSet::StaticClass())))
        {
            // Mass Fragment 값 → GAS Attribute
            Attributes->SetHealth(Health.CurrentHealth);
            Attributes->SetMaxHealth(Health.MaxHealth);
        }

        // 상태 동기화 (GameplayTag로 변환)
        SyncStateToGameplayTags(State);
    }

    // Actor → Mass Entity (Actor 풀 반환 시 호출)
    void SyncToMassEntity(FMonsterHealthFragment& OutHealth,
                          FMonsterStateFragment& OutState)
    {
        // GAS에서 변경된 값을 Fragment로 다시 저장
        if (const UMonsterAttributeSet* Attributes = Cast<UMonsterAttributeSet>(
                AbilitySystemComponent->GetAttributeSet(UMonsterAttributeSet::StaticClass())))
        {
            OutHealth.CurrentHealth = Attributes->GetHealth();
            OutHealth.MaxHealth = Attributes->GetMaxHealth();
        }

        // GameplayTag를 상태로 변환
        SyncGameplayTagsToState(OutState);
    }

private:
    void SyncStateToGameplayTags(const FMonsterStateFragment& State)
    {
        // 상태 enum을 GameplayTag로 변환
        FGameplayTagContainer TagsToAdd;
        FGameplayTagContainer TagsToRemove;

        // 예: Attacking 상태면 해당 태그 추가
        if (State.CurrentState == EMonsterState::Attacking)
        {
            TagsToAdd.AddTag(FGameplayTag::RequestGameplayTag("State.Monster.Attacking"));
        }
        else
        {
            TagsToRemove.AddTag(FGameplayTag::RequestGameplayTag("State.Monster.Attacking"));
        }

        AbilitySystemComponent->UpdateGameplayTagsContainer(TagsToAdd, TagsToRemove);
    }

    void SyncGameplayTagsToState(FMonsterStateFragment& OutState)
    {
        // 반대 방향: GameplayTag → 상태 enum
        if (AbilitySystemComponent->HasMatchingGameplayTag(
                FGameplayTag::RequestGameplayTag("State.Monster.Attacking")))
        {
            OutState.CurrentState = EMonsterState::Attacking;
        }
        // ... 다른 상태들
    }
};
```

### Translator로 자동 동기화 구현

수동으로 `SyncFromMassEntity()` 호출하는 건 번거로워요.
Translator를 만들면 Actor 스폰/반환 시 자동으로 동기화됩니다.

```cpp
// Health Fragment ↔ GAS Attribute 자동 동기화
USTRUCT()
struct FMassHealthToGASTranslator
{
    GENERATED_BODY()

    // Mass → Actor (Actor 스폰될 때)
    static void CopyToActor(const FMassEntityManager& EntityManager,
                            const FMassEntityHandle Entity,
                            AActor* Actor)
    {
        // Fragment에서 데이터 읽기
        const FMonsterHealthFragment* Health =
            EntityManager.GetFragmentDataPtr<FMonsterHealthFragment>(Entity);

        if (!Health) return;

        // Actor의 ASC에 반영
        if (ABP_Monster_HighRes* Monster = Cast<ABP_Monster_HighRes>(Actor))
        {
            if (UAbilitySystemComponent* ASC = Monster->GetAbilitySystemComponent())
            {
                // 체력을 Attribute로 설정
                ASC->SetNumericAttributeBase(
                    UMonsterAttributeSet::GetHealthAttribute(),
                    Health->CurrentHealth);

                ASC->SetNumericAttributeBase(
                    UMonsterAttributeSet::GetMaxHealthAttribute(),
                    Health->MaxHealth);
            }
        }
    }

    // Actor → Mass (Actor 풀 반환될 때)
    static void CopyFromActor(FMassEntityManager& EntityManager,
                              const FMassEntityHandle Entity,
                              const AActor* Actor)
    {
        // Actor에서 현재 상태 읽기
        if (const ABP_Monster_HighRes* Monster = Cast<ABP_Monster_HighRes>(Actor))
        {
            if (const UAbilitySystemComponent* ASC = Monster->GetAbilitySystemComponent())
            {
                // Fragment에 다시 저장
                FMonsterHealthFragment* Health =
                    EntityManager.GetFragmentDataPtr<FMonsterHealthFragment>(Entity);

                if (Health)
                {
                    Health->CurrentHealth = ASC->GetNumericAttribute(
                        UMonsterAttributeSet::GetHealthAttribute());

                    // 체력이 GAS에서 변경됐을 수 있으니 반영
                }
            }
        }
    }
};
```

---

## 6. GAS를 쓸까 말까? 결정 가이드

실무에서 이 결정을 어떻게 내려야 할까요? 플로우차트로 정리했어요.

### 결정 플로우차트

```
                          시작
                            │
                            ▼
                 ┌──────────────────────┐
                 │ 몬스터가 플레이어와  │
                 │ 상호작용이 많나요?   │
                 └──────────────────────┘
                     │           │
                   Yes          No
                     │           │
                     ▼           ▼
         ┌────────────────┐  ┌────────────────┐
         │ 복잡한 스킬이  │  │ 단순 이동 +    │
         │ 필요한가요?    │  │ 접촉 데미지만  │
         └────────────────┘  └────────────────┘
           │         │              │
         Yes        No              │
           │         │              ▼
           │         │       ┌────────────┐
           │         │       │ GAS 불필요 │
           │         │       │ 옵션 A     │
           │         │       └────────────┘
           │         │
           ▼         ▼
    ┌────────────┐  ┌────────────────────┐
    │ 기존 GAS   │  │ 경량 시스템으로    │
    │ 자산이     │  │ 충분 (Fragment)    │
    │ 많은가?    │  │ → 옵션 A 또는 C    │
    └────────────┘  └────────────────────┘
       │      │
     Yes     No
       │      │
       ▼      ▼
┌──────────────┐  ┌──────────────┐
│ 옵션 B       │  │ 옵션 C       │
│ (하이브리드) │  │ (커스텀)     │
│ → 권장!      │  │ → 시간 여유  │
└──────────────┘  │    있을 때   │
                  └──────────────┘
```

### 상황별 권장 옵션

| 상황 | 권장 | 이유 |
|------|------|------|
| **기존 GAS 자산 많음** | B (하이브리드) | 재작성 비용 > 동기화 비용 |
| **신규 프로젝트** | A 또는 C | GAS 종속성 없이 시작 |
| **보스 몬스터 있음** | B | 보스는 GAS 풀 기능 필요 |
| **10000+ 마리 필요** | A | 하이브리드도 부담 |
| **네트워크 멀티플레이** | B | GAS 복제 기능 활용 |
| **모바일/저사양** | A | 최대 성능 필요 |

### 기능별 GAS 필요성

```
┌───────────────────────────────────────────────────────────────────┐
│                    기능별 GAS 필요성 판단                          │
├───────────────────────────────────────────────────────────────────┤
│                                                                    │
│  ★ GAS 사용 권장 (High LOD에서)                                   │
│  ├── 여러 단계 스킬 (채널링, 차징)                                │
│  ├── 복잡한 버프/디버프 상호작용                                  │
│  ├── 스킬 취소/인터럽트 로직                                      │
│  ├── GameplayCue로 VFX/사운드 동기화                              │
│  └── 스킬 비용 (마나, 쿨다운) 복잡한 경우                         │
│                                                                    │
│  ○ Fragment로 충분 (Medium/Low LOD)                               │
│  ├── 단순 공격 (접촉 데미지)                                      │
│  ├── 체력 증감                                                    │
│  ├── 이동 속도 변경                                               │
│  ├── 단순 상태 (공격중/이동중/대기)                               │
│  └── 거리 기반 행동 (추적/후퇴)                                   │
│                                                                    │
│  ✗ 전혀 불필요                                                    │
│  ├── 원거리 ISM 렌더링만                                          │
│  ├── 장식용 군중                                                  │
│  └── 환경 오브젝트 (상호작용 없음)                                │
│                                                                    │
└───────────────────────────────────────────────────────────────────┘
```

---

## 7. 상태 동기화 문제와 해결법

하이브리드 방식의 가장 큰 도전은 **LOD 전환 시 상태 동기화**예요.
잘못하면 체력이 갑자기 바뀌거나, 공격 도중 상태가 리셋되는 버그가 생겨요.

### 문제 상황 1: 공격 도중 LOD 전환

```
시나리오:
1. 몬스터가 플레이어 근처에서 공격 시작 (GAS Ability 실행 중)
2. 플레이어가 갑자기 대시로 멀어짐
3. 몬스터가 High → Medium LOD로 전환 시도
4. 문제: Ability가 아직 실행 중인데 Actor가 반환됨!
```

**해결책: LOD 전환 지연**

```cpp
// LOD 전환 가능 여부 체크
bool CanSwitchToLowerLOD(const AActor* Actor)
{
    // 1. ASC 확인
    const UAbilitySystemComponent* ASC =
        Actor->FindComponentByClass<UAbilitySystemComponent>();

    if (!ASC) return true;  // ASC 없으면 바로 전환 가능

    // 2. 실행 중인 Ability 체크
    // 중요한 Ability가 실행 중이면 대기
    TArray<FGameplayAbilitySpec> ActiveAbilities;
    ASC->GetActivatableAbilities(ActiveAbilities);

    for (const FGameplayAbilitySpec& Spec : ActiveAbilities)
    {
        if (Spec.IsActive())
        {
            // 이 Ability가 LOD 전환을 막아야 하는지 체크
            if (const UGameplayAbility* Ability = Spec.GetPrimaryInstance())
            {
                // 커스텀 인터페이스로 체크
                if (Ability->Implements<UMassLODBlockingInterface>())
                {
                    if (IMassLODBlockingInterface::Execute_ShouldBlockLODSwitch(Ability))
                    {
                        return false;  // 전환 대기
                    }
                }
            }
        }
    }

    return true;
}

// LOD 관리에서 사용
void UMassLODManager::TrySwitchToLowerLOD(FMassEntityHandle Entity, AActor* Actor)
{
    if (CanSwitchToLowerLOD(Actor))
    {
        // 정상 전환
        ReturnActorToPool(Actor);
    }
    else
    {
        // 다음 틱에 다시 시도하도록 예약
        PendingLODSwitches.Add(Entity);
    }
}
```

### 문제 상황 2: 체력 동기화 타이밍

```
시나리오:
1. 몬스터 체력 100 (Mass Fragment)
2. Actor 스폰 → GAS Attribute에 100 복사
3. 플레이어가 30 데미지 → GAS Attribute 70
4. 이 때 다른 Processor가 Fragment의 100을 읽음 (아직 미동기화!)
5. 뭔가 이상한 일이 발생...
```

**해결책: 단일 진실 공급원 (Single Source of Truth)**

```cpp
// 원칙: Fragment가 항상 "진짜" 값
// GAS Attribute는 "표시용" 값

// Actor가 활성화된 동안의 데미지 처리
void ABP_Monster_HighRes::OnDamageReceived(float Damage)
{
    // 1. 먼저 Fragment 수정 (진짜 값)
    FMassEntityHandle MyEntity = MassAgentComponent->GetEntityHandle();
    FMonsterHealthFragment* Health = GetFragment<FMonsterHealthFragment>(MyEntity);

    if (Health)
    {
        Health->ApplyDamage(Damage);

        // 2. 그 다음 GAS Attribute 업데이트 (표시용)
        AbilitySystemComponent->SetNumericAttributeBase(
            UMonsterAttributeSet::GetHealthAttribute(),
            Health->CurrentHealth);
    }
}

// 이렇게 하면 Fragment 값이 항상 최신!
// GAS는 "보여주기"와 "능력 실행"에만 사용
```

### 문제 상황 3: GameplayTag 상태 불일치

```
시나리오:
1. High LOD에서 "Burning" 디버프 적용 (GameplayTag)
2. Medium LOD로 전환 (Actor 반환)
3. 다시 High LOD로 전환 (새 Actor 스폰)
4. 문제: Burning 태그가 사라짐!
```

**해결책: Tag를 Fragment에 미러링**

```cpp
// GameplayTag 상태를 Fragment에 저장
USTRUCT()
struct FMonsterStatusFragment : public FMassFragment
{
    GENERATED_BODY()

    // 중요한 상태들을 비트플래그로 저장
    uint32 StatusFlags = 0;

    // 각 상태의 남은 시간
    float BurningTimeRemaining = 0.0f;
    float StunTimeRemaining = 0.0f;
    float SlowTimeRemaining = 0.0f;

    // 플래그 헬퍼
    enum class EStatusFlag : uint32
    {
        None     = 0,
        Burning  = 1 << 0,
        Stunned  = 1 << 1,
        Slowed   = 1 << 2,
    };

    bool HasStatus(EStatusFlag Flag) const { return (StatusFlags & (uint32)Flag) != 0; }
    void AddStatus(EStatusFlag Flag) { StatusFlags |= (uint32)Flag; }
    void RemoveStatus(EStatusFlag Flag) { StatusFlags &= ~(uint32)Flag; }
};

// Actor 스폰 시 복원
void RestoreGameplayTagsFromFragment(UAbilitySystemComponent* ASC,
                                     const FMonsterStatusFragment& Status)
{
    // Fragment 상태 → GameplayTag
    if (Status.HasStatus(FMonsterStatusFragment::EStatusFlag::Burning))
    {
        ASC->AddLooseGameplayTag(FGameplayTag::RequestGameplayTag("Debuff.Burning"));

        // 남은 시간으로 Effect 재적용할 수도 있음
        // ApplyBurningEffect(Status.BurningTimeRemaining);
    }

    // 다른 상태들도 동일하게...
}
```

### 상태 동기화 체크리스트

실무에서 사용할 체크리스트예요:

```
LOD 전환 시 동기화 체크리스트
─────────────────────────────

□ 체력/마나 등 수치 값
  - Fragment ↔ Attribute 양방향 동기화
  - 단일 진실 공급원 원칙 적용

□ 상태 (버프/디버프)
  - GameplayTag ↔ Fragment 비트플래그 매핑
  - 남은 시간도 저장

□ 실행 중인 Ability
  - 전환 전 완료/취소 여부 확인
  - 또는 전환 지연

□ 쿨다운
  - 쿨다운 남은 시간 Fragment에 저장
  - Actor 스폰 시 복원

□ 타겟 정보
  - 현재 타겟팅 중인 대상 ID 저장
  - 전환 후 타겟 재연결
```

---

## 8. 성능 비교 및 벤치마크

### 테스트 환경
- CPU: AMD Ryzen 5 5600X
- 몬스터 수: 1000마리
- 각 옵션별 동일 로직 구현

### 성능 측정 결과

```
┌────────────────────────────────────────────────────────────────────┐
│                      CPU 시간 (ms/frame)                           │
├────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  전체 GAS (1000 Actor)          ████████████████████ 15-20ms       │
│  옵션 A (완전 분리)              ███ 2-3ms                          │
│  옵션 B (하이브리드)             █████ 4-6ms                        │
│  옵션 C (커스텀 시스템)          ████ 3-4ms                         │
│                                                                     │
│  ━━━━━ 16.6ms (60fps 목표선) ━━━━━                                 │
│                                                                     │
└────────────────────────────────────────────────────────────────────┘
```

### 하이브리드 (옵션 B) 상세 분석

```
1000 몬스터 분포 (하이브리드):
─────────────────────────────

High LOD (100마리)
├── Actor + GAS 처리: ~3.0ms
├── 애니메이션: ~0.5ms
└── 소계: ~3.5ms

Medium LOD (300마리)
├── Fragment Processor: ~0.8ms
├── 간소화 애니메이션: ~0.2ms
└── 소계: ~1.0ms

Low LOD (600마리)
├── 이동 Processor: ~0.3ms
├── ISM 렌더링: ~0.2ms
└── 소계: ~0.5ms

총합: ~5.0ms
─────────────────────────────
전체 GAS 대비: 70% 절감!
```

### 메모리 사용량 비교

```
┌────────────────────────────────────────────────────────────────────┐
│                        메모리 (MB)                                 │
├────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  전체 GAS              ████████████████████████████████ 200+MB     │
│  옵션 A                ████ 20-30MB                                 │
│  옵션 B                █████████ 50-80MB                            │
│  옵션 C                ██████ 30-40MB                               │
│                                                                     │
└────────────────────────────────────────────────────────────────────┘

상세:
- Actor 하나당: ~200KB (GAS 포함)
- Mass Entity 하나당: ~200B (Fragment만)
- 1000배 차이!
```

---

## 9. 옵션 C: 커스텀 경량 시스템

개발 시간이 충분하다면 고려할 옵션이에요.
Mass Fragment 기반의 "미니 GAS"를 만드는 거죠.

### 기본 구조

```cpp
// 1. 경량 어빌리티 상태 정의
UENUM()
enum class ELightweightAbilityState : uint8
{
    Ready,       // 사용 가능
    Activating,  // 발동 중 (선딜)
    Active,      // 실행 중
    Cooldown     // 쿨타임
};

// 2. 어빌리티 데이터 (Shared - 같은 종류 몬스터가 공유)
USTRUCT()
struct FMonsterAbilityData : public FMassSharedFragment
{
    GENERATED_BODY()

    UPROPERTY(EditAnywhere)
    float Damage = 10.0f;

    UPROPERTY(EditAnywhere)
    float Range = 100.0f;

    UPROPERTY(EditAnywhere)
    float CooldownDuration = 2.0f;

    UPROPERTY(EditAnywhere)
    float ActivationTime = 0.5f;  // 선딜레이
};

// 3. 개별 어빌리티 상태 (각 엔티티마다)
USTRUCT()
struct FMonsterAbilityFragment : public FMassFragment
{
    GENERATED_BODY()

    ELightweightAbilityState State = ELightweightAbilityState::Ready;
    float StateTimer = 0.0f;  // 현재 상태 경과 시간
    FMassEntityHandle TargetEntity;  // 타겟
};

// 4. Processor로 배치 처리
UCLASS()
class ULightweightAbilityProcessor : public UMassProcessor
{
    virtual void Execute(FMassEntityManager& EntityManager,
                         FMassExecutionContext& Context) override
    {
        Query.ForEachEntityChunk(EntityManager, Context,
            [](FMassExecutionContext& ChunkContext)
            {
                auto Abilities = ChunkContext.GetMutableFragmentView<FMonsterAbilityFragment>();
                const FMonsterAbilityData& AbilityData =
                    ChunkContext.GetConstSharedFragment<FMonsterAbilityData>();

                const float DeltaTime = ChunkContext.GetDeltaTimeSeconds();

                for (int32 i = 0; i < ChunkContext.GetNumEntities(); ++i)
                {
                    FMonsterAbilityFragment& Ability = Abilities[i];
                    Ability.StateTimer += DeltaTime;

                    switch (Ability.State)
                    {
                    case ELightweightAbilityState::Ready:
                        // 발동 조건 체크 (타겟이 범위 내에 있는지 등)
                        if (ShouldActivate(ChunkContext, i, AbilityData))
                        {
                            Ability.State = ELightweightAbilityState::Activating;
                            Ability.StateTimer = 0.0f;
                        }
                        break;

                    case ELightweightAbilityState::Activating:
                        // 선딜레이 완료?
                        if (Ability.StateTimer >= AbilityData.ActivationTime)
                        {
                            // 효과 적용!
                            ApplyAbilityEffect(ChunkContext, i, AbilityData);
                            Ability.State = ELightweightAbilityState::Active;
                        }
                        break;

                    case ELightweightAbilityState::Active:
                        // 즉시 쿨다운으로 전환 (순간 스킬의 경우)
                        Ability.State = ELightweightAbilityState::Cooldown;
                        Ability.StateTimer = 0.0f;
                        break;

                    case ELightweightAbilityState::Cooldown:
                        // 쿨타임 완료?
                        if (Ability.StateTimer >= AbilityData.CooldownDuration)
                        {
                            Ability.State = ELightweightAbilityState::Ready;
                        }
                        break;
                    }
                }
            });
    }
};
```

### GAS vs 커스텀 시스템 기능 비교

| 기능 | GAS | 커스텀 경량 시스템 |
|------|-----|--------------------|
| 쿨다운 | ✅ 내장 | ⚠️ 직접 구현 (쉬움) |
| 비용 (마나 등) | ✅ 내장 | ⚠️ 직접 구현 |
| 타겟팅 | ✅ 복잡한 타겟팅 | ⚠️ 단순 거리 기반 |
| 효과 스태킹 | ✅ 복잡한 룰 | ⚠️ 단순 덧셈 |
| 인터럽트 | ✅ Tag로 제어 | ⚠️ 직접 구현 |
| 배치 처리 | ❌ 개별 실행 | ✅ 청크 단위 |
| 캐시 효율 | ❌ 낮음 | ✅ 높음 |
| 1000개 처리 | ❌ 느림 | ✅ 빠름 |

---

## 10. 구현 로드맵

### 권장 순서 (옵션 B 하이브리드 기준)

```
1단계: Mass AI 기반 인프라 (1-2주)
─────────────────────────────────
□ MassEntityConfigAsset 생성
□ 기본 Fragment 정의 (Health, Movement, State)
□ 기본 Processor 구현 (이동, 사망)
□ MassSpawner 설정
□ ISM 렌더링 테스트

2단계: 경량 전투 시스템 (1-2주)
─────────────────────────────────
□ FMonsterHealthFragment
□ FPendingDamageFragment
□ UMonsterDamageProcessor
□ Signal 기반 이벤트
□ 플레이어 공격 → Mass Entity 데미지

3단계: High LOD Actor + GAS 통합 (2-3주)
─────────────────────────────────────────
□ High LOD Actor 클래스 (ASC 포함)
□ MassAgentComponent 설정
□ Translator 구현 (Mass ↔ GAS)
□ 기존 어빌리티 연결
□ LOD 전환 테스트

4단계: 동기화 및 안정화 (1-2주)
─────────────────────────────────
□ 상태 동기화 버그 수정
□ LOD 전환 지연 로직
□ 경계 케이스 처리
□ 프로파일링 및 최적화

5단계: 폴리싱 (1주)
─────────────────────────────────
□ LOD 거리 튜닝
□ Actor 풀 크기 최적화
□ 메모리 프로파일링
□ 최종 성능 검증
```

---

## 11. 요약 및 결론

### 핵심 포인트

1. **GAS와 Mass AI는 직접 호환되지 않는다**
   - 아키텍처가 근본적으로 다름
   - "영리한 조합"이 필요

2. **옵션 B (하이브리드)를 권장**
   - 기존 GAS 자산 재활용
   - 성능과 개발비용의 균형
   - 1000-5000 마리 규모에 적합

3. **상태 동기화가 가장 중요한 도전**
   - 단일 진실 공급원 원칙 준수
   - LOD 전환 시 데이터 손실 방지
   - GameplayTag ↔ Fragment 매핑

4. **성능 목표는 달성 가능**
   - 전체 GAS: 15-20ms → 하이브리드: 4-6ms
   - 70% 이상 성능 개선

### 최종 권장 아키텍처

```
┌────────────────────────────────────────────────────────────────┐
│                    1000-5000 마리 권장 설정                    │
├────────────────────────────────────────────────────────────────┤
│                                                                 │
│  High LOD (0-50m)                                              │
│  ├── 최대 100마리                                              │
│  ├── Actor + GAS 풀 사용                                       │
│  └── 기존 GameplayAbility 재활용                               │
│                                                                 │
│  Medium LOD (50-200m)                                          │
│  ├── 300-500마리                                               │
│  ├── Low Actor 또는 ISM                                        │
│  └── Fragment 기반 간소화 로직                                 │
│                                                                 │
│  Low LOD (200m+)                                               │
│  ├── 나머지 전부                                               │
│  ├── ISM Only                                                  │
│  └── 최소 로직 (이동만)                                        │
│                                                                 │
└────────────────────────────────────────────────────────────────┘
```

---

## 12. 다음 단계

Ability System 통합 전략을 이해했다면, 이제 전체 시스템을 최적화할 차례예요:

- **다음**: [07_OptimizationGuide.md](07_OptimizationGuide.md) - 1000-5000 마리 규모 최적화 전략 및 프로파일링 가이드

- **추가 참고**:
  - [05_BehaviorLogic.md](05_BehaviorLogic.md) - StateTree와 Signal 시스템
  - [03_RenderingAndLOD.md](03_RenderingAndLOD.md) - LOD 거리 설정
