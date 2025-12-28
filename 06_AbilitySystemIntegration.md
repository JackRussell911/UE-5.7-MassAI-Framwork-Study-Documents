# Ability System 통합 분석

> **문서 목적**: Gameplay Ability System (GAS)과 Mass AI의 병행 사용 전략 및 장단점 분석

---

## 1. 문제 정의

### 현재 상황

기존 시스템:
- 몬스터 행동 패턴을 Ability System Component로 처리
- Actor 기반, 개별 틱, 객체 지향 설계

목표:
- 수천 마리의 몬스터를 Mass AI로 최적화
- 기존 어빌리티 자산 재활용 가능성 검토

### 핵심 질문

**"Mass AI 몬스터가 Ability System을 사용할 수 있는가?"**

---

## 2. GAS와 Mass AI의 아키텍처 비교

```
┌─────────────────────────────────────────────────────────────────┐
│                  Gameplay Ability System                         │
├─────────────────────────────────────────────────────────────────┤
│  • Actor 기반 (AActor 상속 필수)                                │
│  • UAbilitySystemComponent 필요                                  │
│  • 객체 지향 설계                                                │
│  • 개별 틱 (Ability마다 틱)                                     │
│  • 상태 머신 기반 (GameplayTag)                                 │
│  • 풍부한 기능 (쿨다운, 비용, 효과, 복제)                       │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                      Mass AI (Mass Entity)                       │
├─────────────────────────────────────────────────────────────────┤
│  • Entity 기반 (Actor 불필요)                                    │
│  • Fragment 데이터만 사용                                        │
│  • 데이터 지향 설계                                              │
│  • 배치 처리 (Processor)                                         │
│  • 단순 데이터 구조 (태그, 플래그)                               │
│  • 경량화된 기능                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 호환성 문제

| 항목 | GAS | Mass AI | 호환성 |
|------|-----|---------|--------|
| 기반 | AActor | FMassEntity | ❌ 불가 |
| 컴포넌트 | UAbilitySystemComponent | Fragment | ❌ 불가 |
| 상태 관리 | GameplayTag | Tag/Fragment | △ 변환 필요 |
| 이펙트 | GameplayEffect | 직접 구현 | ❌ 불가 |
| 큐 시스템 | GameplayCue | 직접 구현 | △ 부분 가능 |

---

## 3. 통합 옵션 분석

### 옵션 A: 완전 분리

Mass AI 몬스터는 GAS를 사용하지 않고 별도 시스템 구현

```
┌─────────────────────────────────────────────────────────────────┐
│                        완전 분리 모델                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  플레이어 (Actor + GAS)                                         │
│       │                                                          │
│       │ 공격/피격                                                │
│       ▼                                                          │
│  Mass AI 몬스터 (Fragment 기반)                                 │
│       │                                                          │
│       │ Fragment 직접 수정                                       │
│       ▼                                                          │
│  경량화된 커스텀 시스템                                          │
│  - FMonsterHealthFragment                                        │
│  - FMonsterCombatFragment                                        │
│  - Signal 기반 이벤트                                            │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

**장점:**
- ✅ 최대 성능 (GAS 오버헤드 없음)
- ✅ 단순한 아키텍처
- ✅ 데이터 지향 설계 유지
- ✅ 캐시 효율성 극대화

**단점:**
- ❌ 기존 어빌리티 재작성 필요
- ❌ GAS 기능 직접 구현 필요
- ❌ 두 시스템 동시 관리

**구현 예시:**

```cpp
// 경량화된 데미지 Fragment
USTRUCT()
struct FMonsterHealthFragment : public FMassFragment
{
    GENERATED_BODY()

    float CurrentHealth = 100.0f;
    float MaxHealth = 100.0f;

    // 간단한 데미지 적용
    void ApplyDamage(float Damage)
    {
        CurrentHealth = FMath::Max(0.0f, CurrentHealth - Damage);
    }

    bool IsDead() const { return CurrentHealth <= 0.0f; }
};

// 데미지 처리 Processor
UCLASS()
class UMonsterDamageProcessor : public UMassProcessor
{
    virtual void Execute(...) override
    {
        EntityQuery.ForEachEntityChunk(...,
            [](FMassExecutionContext& Context)
            {
                auto Healths = Context.GetMutableFragmentView<FMonsterHealthFragment>();
                auto PendingDamages = Context.GetMutableFragmentView<FPendingDamageFragment>();

                for (int32 i = 0; i < Context.GetNumEntities(); ++i)
                {
                    if (PendingDamages[i].Damage > 0.0f)
                    {
                        Healths[i].ApplyDamage(PendingDamages[i].Damage);
                        PendingDamages[i].Damage = 0.0f;

                        if (Healths[i].IsDead())
                        {
                            // 사망 처리
                            Context.Defer().AddTag<FDeadTag>(Context.GetEntity(i));
                        }
                    }
                }
            });
    }
};
```

---

### 옵션 B: 하이브리드 접근 (권장)

가까운 몬스터(High LOD)만 Actor 전환 시 GAS 활성화

```
┌─────────────────────────────────────────────────────────────────┐
│                      하이브리드 모델                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  거리        표현              어빌리티 시스템                   │
│  ─────       ────              ──────────────                    │
│                                                                  │
│  0-50m       HighResActor      GAS 활성화 (풀 기능)             │
│              + ASC             - GameplayAbility                 │
│                                - GameplayEffect                  │
│                                - GameplayCue                     │
│                                                                  │
│  50-200m     LowResActor       GAS 비활성화                      │
│              (ASC 없음)        Fragment 기반 처리               │
│                                                                  │
│  200m+       ISM               Fragment만                        │
│              (Actor 없음)      최소 로직                         │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

**장점:**
- ✅ 기존 어빌리티 재사용 가능
- ✅ 근거리 몬스터만 복잡한 로직 적용
- ✅ 멀리 있는 몬스터는 성능 절약
- ✅ 점진적 마이그레이션 가능

**단점:**
- △ 표현 전환 시 상태 동기화 필요
- △ LOD 경계에서 행동 일관성 유지 어려움
- △ 두 시스템 모두 이해 필요

**구현 예시:**

```cpp
// High LOD Actor (GAS 포함)
UCLASS()
class ABP_Monster_HighRes : public ACharacter
{
    GENERATED_BODY()

public:
    ABP_Monster_HighRes()
    {
        // Ability System Component 추가
        AbilitySystemComponent = CreateDefaultSubobject<UAbilitySystemComponent>(TEXT("ASC"));

        // Mass Agent (Mass Entity와 동기화)
        MassAgent = CreateDefaultSubobject<UMassAgentComponent>(TEXT("MassAgent"));
    }

    UPROPERTY(VisibleAnywhere)
    UAbilitySystemComponent* AbilitySystemComponent;

    UPROPERTY(VisibleAnywhere)
    UMassAgentComponent* MassAgent;

    // Mass → Actor 상태 동기화
    void SyncFromMassEntity(const FMonsterHealthFragment& Health,
                            const FMonsterCombatFragment& Combat)
    {
        // Health를 GAS Attribute로 동기화
        if (UAttributeSet* Attributes = AbilitySystemComponent->GetAttributeSet())
        {
            // 속성 설정
        }
    }

    // Actor → Mass 상태 동기화
    void SyncToMassEntity(FMonsterHealthFragment& OutHealth,
                          FMonsterCombatFragment& OutCombat)
    {
        // GAS Attribute를 Fragment로 동기화
    }
};
```

**상태 동기화 Translator:**

```cpp
// GAS ↔ Mass 동기화 Translator
USTRUCT()
struct FMassGASTranslator : public FMassTranslator
{
    GENERATED_BODY()

    // Actor 스폰 시: Mass → GAS
    virtual void CopyToActor(const FMassEntityManager& EntityManager,
                             FMassEntityHandle Entity,
                             AActor* Actor) const override
    {
        const FMonsterHealthFragment* Health =
            EntityManager.GetFragmentDataPtr<FMonsterHealthFragment>(Entity);

        if (ABP_Monster_HighRes* Monster = Cast<ABP_Monster_HighRes>(Actor))
        {
            if (UAbilitySystemComponent* ASC = Monster->AbilitySystemComponent)
            {
                // Fragment → GAS Attribute
                ASC->SetNumericAttributeBase(
                    UMonsterAttributeSet::GetHealthAttribute(),
                    Health->CurrentHealth);
            }
        }
    }

    // Actor 반환 시: GAS → Mass
    virtual void CopyFromActor(FMassEntityManager& EntityManager,
                               FMassEntityHandle Entity,
                               const AActor* Actor) const override
    {
        FMonsterHealthFragment* Health =
            EntityManager.GetFragmentDataPtr<FMonsterHealthFragment>(Entity);

        if (const ABP_Monster_HighRes* Monster = Cast<ABP_Monster_HighRes>(Actor))
        {
            if (const UAbilitySystemComponent* ASC = Monster->AbilitySystemComponent)
            {
                // GAS Attribute → Fragment
                Health->CurrentHealth = ASC->GetNumericAttribute(
                    UMonsterAttributeSet::GetHealthAttribute());
            }
        }
    }
};
```

---

### 옵션 C: 간소화된 커스텀 시스템

Mass Fragment 기반의 경량 어빌리티 시스템 구현

```
┌─────────────────────────────────────────────────────────────────┐
│                    커스텀 어빌리티 시스템                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  FMonsterAbilityFragment                                  │   │
│  │  - AbilityState (enum)                                   │   │
│  │  - CooldownRemaining                                     │   │
│  │  - AbilityData (shared)                                  │   │
│  └──────────────────────────────────────────────────────────┘   │
│                           │                                      │
│                           ▼                                      │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  UMonsterAbilityProcessor                                │   │
│  │  - 상태 전이                                             │   │
│  │  - 쿨다운 처리                                           │   │
│  │  - 효과 적용                                             │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

**장점:**
- ✅ 데이터 지향 설계로 캐시 효율성 극대화
- ✅ Mass AI와 완전 통합
- ✅ 필요한 기능만 구현 (경량화)
- ✅ 배치 처리 가능

**단점:**
- ❌ 개발 시간 투자 필요
- ❌ GAS의 풍부한 기능 부재
- ❌ 기존 어빌리티 재작성 필요

**구현 예시:**

```cpp
// 경량 어빌리티 상태
UENUM()
enum class ELightweightAbilityState : uint8
{
    Ready,
    Activating,
    Active,
    Cooldown
};

// 어빌리티 데이터 (Shared Fragment)
USTRUCT()
struct FMonsterAbilityData : public FMassSharedFragment
{
    GENERATED_BODY()

    UPROPERTY()
    float Damage = 10.0f;

    UPROPERTY()
    float Range = 100.0f;

    UPROPERTY()
    float CooldownDuration = 2.0f;

    UPROPERTY()
    float ActivationTime = 0.5f;
};

// 어빌리티 상태 Fragment
USTRUCT()
struct FMonsterAbilityFragment : public FMassFragment
{
    GENERATED_BODY()

    ELightweightAbilityState State = ELightweightAbilityState::Ready;
    float StateTimer = 0.0f;
};

// 어빌리티 Processor
UCLASS()
class ULightweightAbilityProcessor : public UMassProcessor
{
    virtual void Execute(...) override
    {
        EntityQuery.ForEachEntityChunk(...,
            [](FMassExecutionContext& Context)
            {
                auto Abilities = Context.GetMutableFragmentView<FMonsterAbilityFragment>();
                const FMonsterAbilityData& AbilityData =
                    Context.GetConstSharedFragment<FMonsterAbilityData>();
                const float DeltaTime = Context.GetDeltaTimeSeconds();

                for (int32 i = 0; i < Context.GetNumEntities(); ++i)
                {
                    Abilities[i].StateTimer += DeltaTime;

                    switch (Abilities[i].State)
                    {
                        case ELightweightAbilityState::Ready:
                            // 트리거 조건 체크
                            if (ShouldActivate(i))
                            {
                                Abilities[i].State = ELightweightAbilityState::Activating;
                                Abilities[i].StateTimer = 0.0f;
                            }
                            break;

                        case ELightweightAbilityState::Activating:
                            if (Abilities[i].StateTimer >= AbilityData.ActivationTime)
                            {
                                Abilities[i].State = ELightweightAbilityState::Active;
                                // 어빌리티 효과 적용
                                ApplyAbilityEffect(i, AbilityData);
                            }
                            break;

                        case ELightweightAbilityState::Active:
                            Abilities[i].State = ELightweightAbilityState::Cooldown;
                            Abilities[i].StateTimer = 0.0f;
                            break;

                        case ELightweightAbilityState::Cooldown:
                            if (Abilities[i].StateTimer >= AbilityData.CooldownDuration)
                            {
                                Abilities[i].State = ELightweightAbilityState::Ready;
                            }
                            break;
                    }
                }
            });
    }
};
```

---

## 4. 권장 사항

### 1000-5000 마리 규모에서의 권장: 옵션 B (하이브리드)

```
┌─────────────────────────────────────────────────────────────────┐
│                      권장 아키텍처                               │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  High LOD (50-100개)                                            │
│  ├── Actor + GAS                                                │
│  ├── 기존 GameplayAbility 재사용                                │
│  ├── 복잡한 공격 패턴                                           │
│  └── 풀 시각/사운드 피드백                                      │
│                                                                  │
│  Medium/Low LOD (나머지)                                        │
│  ├── Mass Fragment만                                            │
│  ├── 경량화된 커스텀 로직                                       │
│  ├── 단순 공격 (접촉 데미지)                                    │
│  └── 최소 피드백                                                │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 구현 우선순위

1. **1단계**: Mass AI 기본 인프라 구축
   - Entity Config, Trait, Spawner 설정
   - 기본 이동 Processor 구현

2. **2단계**: 경량 전투 시스템 구현
   - FMonsterHealthFragment
   - FMonsterCombatFragment
   - Signal 기반 데미지 시스템

3. **3단계**: High LOD Actor + GAS 통합
   - 기존 어빌리티 재사용
   - Translator로 상태 동기화

4. **4단계**: 최적화 및 튜닝
   - LOD 거리 조정
   - Actor 풀 크기 최적화
   - 프로파일링

---

## 5. 상태 동기화 전략

### Mass ↔ GAS 상태 매핑

| Mass Fragment | GAS Equivalent |
|---------------|----------------|
| `FMonsterHealthFragment::CurrentHealth` | `UAttributeSet::Health` |
| `FMonsterCombatFragment::AttackDamage` | `UAttributeSet::AttackPower` |
| `FMonsterStateFragment::CurrentState` | `GameplayTag` |
| `FDeadTag` | `GameplayTag.Status.Dead` |

### 동기화 시점

```
LOD 전환 시:

High → Medium (Actor 반환):
1. GAS Attribute 읽기
2. Mass Fragment에 저장
3. Actor 풀로 반환

Medium → High (Actor 스폰):
1. Mass Fragment 읽기
2. Actor 스폰
3. GAS Attribute 설정
4. 필요시 Ability 활성화
```

### 문제 해결

**Q: LOD 전환 중 Ability가 실행 중이면?**

A: 두 가지 전략:
1. **강제 완료**: LOD 전환 전 Ability 즉시 완료/취소
2. **전환 지연**: Ability 완료까지 LOD 전환 대기

```cpp
// 전환 지연 방식
bool CanSwitchToLowerLOD(const AActor* Actor)
{
    if (UAbilitySystemComponent* ASC = Actor->FindComponentByClass<UAbilitySystemComponent>())
    {
        // 실행 중인 Ability가 있으면 전환 대기
        return !ASC->HasAnyActiveAbilities();
    }
    return true;
}
```

---

## 6. 성능 비교

### 테스트 시나리오: 1000 몬스터

| 옵션 | CPU 시간 (ms) | 메모리 (MB) | 비고 |
|------|--------------|-------------|------|
| 전체 GAS | 15-20 | 200+ | 기존 방식 |
| 옵션 A (완전 분리) | 2-3 | 20-30 | 최고 성능 |
| 옵션 B (하이브리드) | 4-6 | 50-80 | 권장 |
| 옵션 C (커스텀) | 3-4 | 30-40 | 개발 비용 높음 |

### 하이브리드 상세 분석

```
1000 몬스터 중:
- High LOD (100개): GAS 사용, ~3ms
- Medium LOD (300개): Fragment, ~1ms
- Low LOD (600개): 최소 처리, ~0.5ms
총: ~4.5ms (vs 전체 GAS 15-20ms)
```

---

## 7. 마이그레이션 가이드

### 기존 Ability를 Mass AI로 이전

**1단계: Ability 분석**
```
기존 Ability 분류:
- 복잡 (보스 패턴): GAS 유지 → High LOD에서만
- 단순 (근접 공격): Fragment 기반으로 재구현
- 버프/디버프: GameplayEffect → Fragment 수정
```

**2단계: Fragment 설계**
```cpp
// 기존 GAS Attribute를 Fragment로 변환
// Before (GAS):
UPROPERTY(BlueprintReadOnly)
FGameplayAttributeData Health;

// After (Mass):
USTRUCT()
struct FMonsterHealthFragment : public FMassFragment
{
    float CurrentHealth;
    float MaxHealth;
};
```

**3단계: Processor 구현**
```cpp
// 기존 GameplayAbility::ActivateAbility()를
// Processor::Execute()로 변환
```

---

## 8. 결론

### 옵션별 권장 상황

| 상황 | 권장 옵션 |
|------|----------|
| 기존 GAS 자산 많음 | B (하이브리드) |
| 신규 프로젝트 | A 또는 C |
| 복잡한 보스 AI 필요 | B |
| 극한 성능 필요 | A |
| 개발 시간 충분 | C |

### 1000-5000 마리 규모 최종 권장

**옵션 B (하이브리드)** + **옵션 C 요소 일부 도입**

- High LOD: 기존 GAS 어빌리티 재사용
- Medium/Low LOD: 경량 Fragment 시스템
- 단계적 마이그레이션 가능

---

## 9. 다음 단계

Ability System 통합을 이해했다면, 다음 문서에서 전체 최적화 전략을 살펴보겠습니다:

- **다음**: [07_OptimizationGuide.md](07_OptimizationGuide.md) - 1000-5000 마리 규모 최적화 전략 및 실전 구현 가이드
