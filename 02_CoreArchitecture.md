# 코어 아키텍처 상세 분석

> **문서 목적**: Mass AI의 핵심 구조인 Entity, Fragment, Processor, Archetype 시스템 이해
>
> **대상 독자**: 블루프린트 개발자부터 C++ 개발자까지

---

## 1. Entity Manager - "모든 것의 본부"

### 이게 뭐예요?

**블루프린트 비유**: World에서 `Get All Actors of Class`로 모든 Actor를 관리하는 것처럼, Entity Manager는 모든 Mass Entity를 관리하는 "본부"예요.

```
블루프린트에서는...                    Mass AI에서는...
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Spawn Actor                    →      CreateEntity()
Destroy Actor                  →      DestroyEntity()
Get All Actors of Class        →      EntityQuery로 검색
Actor 변수 저장                →      FMassEntityHandle
```

### 핵심 포인트

Entity Manager는 **FMassEntityManager** 클래스인데, 직접 접근하려면 이렇게 해요:

```cpp
// 1. Entity Subsystem 가져오기
UMassEntitySubsystem* EntitySubsystem = GetWorld()->GetSubsystem<UMassEntitySubsystem>();

// 2. Entity Manager 접근
FMassEntityManager& EntityManager = EntitySubsystem->GetMutableEntityManager();
```

### 엔티티 생성하기 - 세 가지 방법

**방법 1: 한 개씩 만들기** (간단하지만 느림)
```cpp
FMassEntityHandle Monster = EntityManager.CreateEntity(MonsterArchetype);
```

**방법 2: 배치로 만들기** (권장!)
```cpp
TArray<FMassEntityHandle> Monsters;
EntityManager.BatchCreateEntities(MonsterArchetype, 1000, Monsters);
// 1000마리를 한 번에 만들어요!
```

**방법 3: 2단계 생성** (고급 - 성능 최적화용)
```cpp
// 1단계: 핸들만 먼저 예약
FMassEntityHandle Monster = EntityManager.ReserveEntity();

// 2단계: 나중에 실제 데이터 채우기
EntityManager.BuildEntity(Monster, MonsterArchetype);
```

> **왜 2단계 생성을 쓰나요?**
> 엔티티를 만들기 전에 핸들이 필요할 때 써요. 예를 들어, A 엔티티가 B 엔티티를 참조해야 하는데, 둘 다 아직 안 만들어진 경우에 유용해요.

### 실전 예시: 몬스터 웨이브 스폰

```cpp
void UMonsterSpawner::SpawnMonsterWave(int32 Count)
{
    // 1. Entity Manager 접근
    UMassEntitySubsystem* EntitySubsystem = GetWorld()->GetSubsystem<UMassEntitySubsystem>();
    FMassEntityManager& EntityManager = EntitySubsystem->GetMutableEntityManager();

    // 2. 1000마리 배치 생성
    TArray<FMassEntityHandle> NewMonsters;
    EntityManager.BatchCreateEntities(MonsterArchetype, Count, NewMonsters);

    // 3. 각 몬스터의 위치 설정
    for (int32 i = 0; i < NewMonsters.Num(); i++)
    {
        FTransformFragment* Transform =
            EntityManager.GetFragmentDataPtr<FTransformFragment>(NewMonsters[i]);

        // 원형으로 배치
        float Angle = (2.0f * PI * i) / Count;
        float Radius = 1000.0f;
        FVector SpawnLocation(
            FMath::Cos(Angle) * Radius,
            FMath::Sin(Angle) * Radius,
            0.0f
        );
        Transform->Transform.SetLocation(SpawnLocation);
    }
}
```

---

## 2. Fragment 시스템 - "데이터 카드"

### 이게 뭐예요?

Fragment는 **순수 데이터**예요. 함수 없이 변수만 있어요!

**블루프린트 비유**: Actor Component에서 변수만 뽑아낸 거라고 생각하면 돼요.

```
블루프린트 Component            Mass AI Fragment
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Character Movement Component  →  FMassVelocityFragment (속도만)
                                 FMassMovementParameters (이동 설정만)

Health Component              →  FHealthFragment (체력 값만)

Scene Component               →  FTransformFragment (위치/회전만)
```

### Fragment 종류 - 5가지가 있어요

| 종류 | 용도 | 비유 |
|------|------|------|
| **FMassFragment** | 엔티티별 고유 데이터 | Actor 인스턴스 변수 |
| **FMassTag** | 데이터 없는 마커 | Actor Tag |
| **FMassChunkFragment** | 청크 내 공유 데이터 | 같은 방의 NPC들이 공유하는 설정 |
| **FMassSharedFragment** | 여러 엔티티가 공유 | 같은 종류 몬스터의 공통 스탯 |
| **FMassConstSharedFragment** | 공유 + 읽기 전용 | 절대 안 바뀌는 설정값 |

### 자주 쓰는 Fragment들

**위치 관련**
```cpp
// FTransformFragment - 위치, 회전, 스케일
struct FTransformFragment : public FMassFragment
{
    FTransform Transform;  // GetActorTransform()과 같은 역할
};

// FAgentRadiusFragment - 충돌 반경
struct FAgentRadiusFragment : public FMassFragment
{
    float Radius = 40.0f;  // Capsule 반경과 비슷
};
```

**이동 관련**
```cpp
// FMassVelocityFragment - 현재 속도
struct FMassVelocityFragment : public FMassFragment
{
    FVector Value;  // GetVelocity()와 같은 역할
};

// FMassMovementParameters - 이동 설정 (공유됨)
struct FMassMovementParameters : public FMassSharedFragment
{
    float MaxSpeed = 400.0f;      // Character Movement의 MaxWalkSpeed
    float Acceleration = 800.0f;  // 가속도
};
```

### 커스텀 Fragment 만들기

**예시: 몬스터 전용 Fragment**

```cpp
// 1. 체력 Fragment
USTRUCT()
struct FMonsterHealthFragment : public FMassFragment
{
    GENERATED_BODY()

    UPROPERTY()
    float CurrentHealth = 100.0f;  // 현재 체력

    UPROPERTY()
    float MaxHealth = 100.0f;      // 최대 체력
};

// 2. 공격 대상 Fragment
USTRUCT()
struct FTargetFragment : public FMassFragment
{
    GENERATED_BODY()

    UPROPERTY()
    FVector TargetLocation;  // 타겟 위치

    UPROPERTY()
    FMassEntityHandle TargetEntity;  // 타겟 엔티티 (다른 Mass Entity를 타겟으로)
};

// 3. 몬스터 태그 (데이터 없음, 식별용)
USTRUCT()
struct FMonsterTag : public FMassTag
{
    GENERATED_BODY()
    // 비어있음! "이 엔티티는 몬스터다"라는 표시만 하는 거예요
};

// 4. 죽음 태그
USTRUCT()
struct FDeadTag : public FMassTag
{
    GENERATED_BODY()
    // 이 태그가 있으면 "죽은 몬스터"로 인식
};
```

### Tag는 언제 쓰나요?

Tag는 **데이터가 필요 없는 분류**에 써요:

```cpp
// 예시: 몬스터 타입 분류
struct FMeleeMonsterTag : public FMassTag {};   // 근접 몬스터
struct FRangedMonsterTag : public FMassTag {};  // 원거리 몬스터
struct FBossMonsterTag : public FMassTag {};    // 보스 몬스터

// 예시: 상태 표시
struct FStunnedTag : public FMassTag {};        // 기절 상태
struct FDeadTag : public FMassTag {};           // 죽음 상태
struct FInvincibleTag : public FMassTag {};     // 무적 상태
```

---

## 3. Processor 시스템 - "전문 일꾼"

### 이게 뭐예요?

Processor는 **특정 작업을 전담하는 일꾼**이에요.

**블루프린트 비유**: Actor의 Tick 이벤트에서 하던 일을 **분리해서 전문화**한 거예요.

```
블루프린트 Actor Tick              Mass AI Processor
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Event Tick
├─ 플레이어 찾기          →       UTargetFindProcessor (타겟 찾기 전담)
├─ 방향 계산             →       UMovementProcessor (이동 전담)
├─ 이동 실행
├─ 공격 체크             →       UCombatProcessor (전투 전담)
└─ 애니메이션 업데이트    →       UAnimationProcessor (애니 전담)
```

### 왜 이렇게 분리하나요?

1. **캐시 효율**: 같은 종류의 데이터를 연속으로 처리
2. **병렬화 가능**: 서로 독립적인 Processor는 동시에 실행 가능
3. **재사용**: 다른 엔티티 타입에서도 같은 Processor 사용 가능

### Processor 만들기 - 단계별 가이드

**1단계: 클래스 선언**

```cpp
UCLASS()
class UMonsterChaseProcessor : public UMassProcessor
{
    GENERATED_BODY()

public:
    UMonsterChaseProcessor();

protected:
    // 필수 구현: 어떤 Fragment를 처리할지 설정
    virtual void ConfigureQueries() override;

    // 필수 구현: 실제 로직
    virtual void Execute(FMassEntityManager& EntityManager,
                         FMassExecutionContext& Context) override;

private:
    // 플레이어 캐릭터 캐시
    UPROPERTY(Transient)
    APawn* CachedPlayer;
};
```

**2단계: 생성자 - 언제 실행될지 설정**

```cpp
UMonsterChaseProcessor::UMonsterChaseProcessor()
{
    // 물리 시뮬레이션 전에 실행
    ProcessingPhase = EMassProcessingPhase::PrePhysics;

    // 다른 Processor 다음에 실행 (의존성 설정)
    ExecutionOrder.ExecuteAfter.Add(UMassApplyMovementProcessor::StaticClass());

    // 게임 쓰레드에서 실행 (기본값)
    bRequiresGameThreadExecution = true;
}
```

**3단계: ConfigureQueries - 처리할 엔티티 조건 설정**

```cpp
void UMonsterChaseProcessor::ConfigureQueries()
{
    // "이 Processor는 이런 Fragment를 가진 엔티티만 처리할 거예요"

    // 필수 Fragment - 읽기/쓰기
    EntityQuery.AddRequirement<FTransformFragment>(EMassFragmentAccess::ReadOnly);
    EntityQuery.AddRequirement<FMassVelocityFragment>(EMassFragmentAccess::ReadWrite);

    // 필수 Tag - 몬스터여야 함
    EntityQuery.AddRequirement<FMonsterTag>(EMassFragmentPresence::All);

    // 제외 조건 - 죽은 몬스터는 제외
    EntityQuery.AddRequirement<FDeadTag>(EMassFragmentPresence::None);
}
```

**4단계: Execute - 실제 로직**

```cpp
void UMonsterChaseProcessor::Execute(FMassEntityManager& EntityManager,
                                      FMassExecutionContext& Context)
{
    // 플레이어 찾기 (매 프레임 갱신)
    if (!CachedPlayer || !CachedPlayer->IsValidLowLevel())
    {
        CachedPlayer = UGameplayStatics::GetPlayerPawn(GetWorld(), 0);
    }

    if (!CachedPlayer) return;

    const FVector PlayerLocation = CachedPlayer->GetActorLocation();

    // 모든 해당 엔티티를 청크 단위로 처리
    EntityQuery.ForEachEntityChunk(EntityManager, Context,
        [this, &PlayerLocation](FMassExecutionContext& Context)
        {
            // Fragment 데이터 배열 가져오기
            auto Transforms = Context.GetFragmentView<FTransformFragment>();
            auto Velocities = Context.GetMutableFragmentView<FMassVelocityFragment>();

            const int32 NumEntities = Context.GetNumEntities();

            // 모든 몬스터 순회
            for (int32 i = 0; i < NumEntities; ++i)
            {
                // 플레이어 방향으로 속도 설정
                FVector MonsterLocation = Transforms[i].Transform.GetLocation();
                FVector Direction = (PlayerLocation - MonsterLocation).GetSafeNormal();

                Velocities[i].Value = Direction * 400.0f;  // 속도 400으로 추적
            }
        });
}
```

### Processor 실행 순서

Processor들은 **Processing Phase**와 **ExecutionOrder**로 순서가 정해져요:

```
┌─────────────────────────────────────────────────────────────────┐
│                        매 프레임 실행 순서                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  [PrePhysics Phase]                                             │
│    ├─ TargetFindProcessor        ← 타겟 찾기                    │
│    ├─ ChaseProcessor             ← 추적 (타겟 필요)             │
│    └─ MovementProcessor          ← 이동 적용                    │
│                                                                  │
│  [DuringPhysics Phase]                                          │
│    └─ CollisionProcessor         ← 충돌 처리                    │
│                                                                  │
│  [PostPhysics Phase]                                            │
│    └─ AnimationProcessor         ← 애니메이션 업데이트          │
│                                                                  │
│  [FrameEnd Phase]                                               │
│    └─ CleanupProcessor           ← 정리 작업                    │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## 4. Archetype 시스템 - "엔티티 분류함"

### 이게 뭐예요?

Archetype은 **같은 Fragment 조합을 가진 엔티티들의 그룹**이에요.

**비유**: 학교에서 반을 나누는 것과 비슷해요!

```
1반 (수학반):    [수학책, 노트, 계산기]를 가진 학생들
2반 (과학반):    [과학책, 노트, 실험도구]를 가진 학생들
3반 (체육반):    [운동복, 물통]을 가진 학생들
```

Mass AI에서는:

```
Archetype A (일반 몬스터):
  [Transform, Velocity, Health] → Monster1, Monster2, Monster3...

Archetype B (보스 몬스터):
  [Transform, Velocity, Health, Shield, BossAI] → Boss1, Boss2...

Archetype C (투사체):
  [Transform, Velocity, Damage] → Bullet1, Bullet2, Bullet3...
```

### 왜 Archetype으로 분류하나요?

1. **메모리 연속 배치**: 같은 Archetype의 엔티티가 메모리에 연속으로 저장됨
2. **빠른 쿼리**: Fragment 조합으로 바로 필터링 가능
3. **청크 처리**: 같은 Archetype을 한 번에 배치 처리

### Archetype과 청크(Chunk)

```
┌─────────────────────────────────────────────────────────────────┐
│                    Archetype A (일반 몬스터)                      │
│                    [Transform, Velocity, Health]                 │
├─────────────────────────────────────────────────────────────────┤
│  Chunk 1 (최대 64개)                                            │
│  ┌─────┬─────┬─────┬─────┬─────┬─────┐                          │
│  │ E1  │ E2  │ E3  │ E4  │ ... │ E64 │  ← 연속 메모리!          │
│  └─────┴─────┴─────┴─────┴─────┴─────┘                          │
│                                                                  │
│  Chunk 2 (최대 64개)                                            │
│  ┌─────┬─────┬─────┬─────┬─────┬─────┐                          │
│  │ E65 │ E66 │ E67 │ E68 │ ... │E128 │  ← 다음 연속 메모리       │
│  └─────┴─────┴─────┴─────┴─────┴─────┘                          │
│                                                                  │
│  ... (더 많은 청크)                                              │
└─────────────────────────────────────────────────────────────────┘
```

> **Chunk(청크)란?**
> 같은 Archetype의 엔티티들을 64개씩 묶은 단위예요. Processor는 청크 단위로 처리해서 캐시 효율을 극대화해요.

### Archetype 변경 시 주의사항

엔티티에 Fragment를 추가/제거하면 **Archetype이 바뀌어요**!

```cpp
// 원래 상태
Monster → Archetype A [Transform, Velocity, Health]

// Shield Fragment 추가
Context.Defer().AddFragment<FShieldFragment>(Monster);

// 결과: 다른 Archetype으로 이동!
Monster → Archetype B [Transform, Velocity, Health, Shield]
```

이 과정에서 메모리 이동이 발생하므로, **자주 바뀌는 상태는 Tag 대신 Fragment 값으로** 관리하는 게 좋아요.

---

## 5. Entity Query - "엔티티 검색 시스템"

### 이게 뭐예요?

Query는 **조건에 맞는 엔티티를 찾는 검색 시스템**이에요.

**블루프린트 비유**: `Get All Actors of Class`보다 훨씬 세밀한 필터링!

```
블루프린트                        Mass AI Query
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Get All Actors of Class      →   Tag로 타입 필터링
Actor Has Tag                →   Tag 존재 여부 확인
Component 존재 확인           →   Fragment 존재 여부 확인
다중 조건 AND/OR             →   Query에 여러 조건 추가
```

### Query 설정하기

```cpp
FMassEntityQuery MonsterQuery;

// === 필수 Fragment ===
// "Transform과 Velocity가 있어야 해요"
MonsterQuery.AddRequirement<FTransformFragment>(EMassFragmentAccess::ReadOnly);
MonsterQuery.AddRequirement<FMassVelocityFragment>(EMassFragmentAccess::ReadWrite);

// === 필수 Tag ===
// "Monster 태그가 있어야 해요"
MonsterQuery.AddRequirement<FMonsterTag>(EMassFragmentPresence::All);

// === 선택적 Fragment ===
// "Target Fragment가 있으면 쓰고, 없어도 괜찮아요"
MonsterQuery.AddRequirement<FTargetFragment>(EMassFragmentPresence::Optional);

// === 제외 조건 ===
// "Dead 태그가 있으면 제외해요"
MonsterQuery.AddRequirement<FDeadTag>(EMassFragmentPresence::None);
```

### Fragment 접근 모드

| 모드 | 의미 | 언제 쓰나요? |
|------|------|------------|
| `ReadOnly` | 읽기만 | 다른 Processor와 병렬 처리 가능 |
| `ReadWrite` | 읽기/쓰기 | 값을 수정할 때 |

### Fragment 존재 조건

| 조건 | 의미 | 예시 |
|------|------|------|
| `All` | 반드시 있어야 함 | 몬스터라면 Health 필수 |
| `Optional` | 있으면 사용, 없어도 OK | Shield가 있으면 처리 |
| `None` | 없어야 함 (제외) | 죽은 몬스터 제외 |
| `Any` | 하나라도 있으면 됨 | 여러 타입 중 하나 |

### Query 실행하기

**권장: 청크 단위 처리**

```cpp
Query.ForEachEntityChunk(EntityManager, Context,
    [](FMassExecutionContext& Context)
    {
        // Fragment 배열 가져오기
        auto Transforms = Context.GetMutableFragmentView<FTransformFragment>();
        auto Velocities = Context.GetFragmentView<FMassVelocityFragment>();

        // 청크 내 모든 엔티티 순회
        for (int32 i = 0; i < Context.GetNumEntities(); ++i)
        {
            // 처리 로직
            Transforms[i].Transform.AddToTranslation(
                Velocities[i].Value * Context.GetDeltaTimeSeconds()
            );
        }
    });
```

**비권장: 개별 엔티티 처리** (특수한 경우에만)

```cpp
Query.ForEachEntity(EntityManager, Context,
    [](FMassEntityHandle Entity, FMassExecutionContext& Context)
    {
        // 개별 엔티티 처리 (느림!)
    });
```

---

## 6. Trait 시스템 - "엔티티 레시피"

### 이게 뭐예요?

Trait는 **재사용 가능한 Fragment 조합**이에요.

**블루프린트 비유**: Actor Blueprint에서 Component를 미리 추가해두는 것과 비슷해요.

```
블루프린트                        Mass AI
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Monster Blueprint               UMonsterTrait
├─ CharacterMovement Component  →  FMassVelocityFragment
├─ Health Component             →  FHealthFragment
└─ CapsuleComponent             →  FAgentRadiusFragment
```

### Trait 만들기

```cpp
UCLASS(meta = (DisplayName = "Monster Base Trait"))
class UMonsterBaseTrait : public UMassEntityTraitBase
{
    GENERATED_BODY()

public:
    // 에디터에서 설정할 수 있는 값들
    UPROPERTY(EditAnywhere, Category = "Stats")
    float MaxHealth = 100.0f;

    UPROPERTY(EditAnywhere, Category = "Movement")
    float MoveSpeed = 400.0f;

    UPROPERTY(EditAnywhere, Category = "Collision")
    float CollisionRadius = 40.0f;

    // Template 빌드 - Fragment들을 추가
    virtual void BuildTemplate(FMassEntityTemplateBuildContext& BuildContext,
                               const UWorld& World) const override
    {
        // 1. 기본 Fragment 추가
        BuildContext.AddFragment<FTransformFragment>();
        BuildContext.AddFragment<FMassVelocityFragment>();
        BuildContext.AddFragment<FAgentRadiusFragment>();

        // 2. 초기값 설정이 필요한 Fragment
        FMonsterHealthFragment& Health = BuildContext.AddFragment_GetRef<FMonsterHealthFragment>();
        Health.MaxHealth = MaxHealth;
        Health.CurrentHealth = MaxHealth;

        // 3. Shared Fragment (모든 같은 타입 엔티티가 공유)
        FMassMovementParameters MovementParams;
        MovementParams.MaxSpeed = MoveSpeed;
        BuildContext.AddSharedFragment(MovementParams);

        // 4. Tag 추가
        BuildContext.AddTag<FMonsterTag>();
    }
};
```

### 에픽게임즈가 제공하는 기본 Trait들

| Trait | 하는 일 | 추가되는 Fragment/Tag |
|-------|--------|---------------------|
| **AssortedFragmentsTrait** | 기본 Fragment 모음 | Transform, AgentRadius 등 |
| **VisualizationTrait** | 시각적 표현 | Representation, LOD 관련 |
| **MovementTrait** | 이동 관련 | Velocity, Movement Parameters |
| **StateTreeTrait** | StateTree AI | StateTree 관련 |
| **SmartObjectTrait** | Smart Object 상호작용 | SmartObject 관련 |

---

## 7. Entity Config Asset - "에디터에서 엔티티 설계"

### 이게 뭐예요?

MassEntityConfigAsset은 **에디터에서 만드는 엔티티 블루프린트**예요.

### 만드는 방법 (단계별)

**Step 1: Data Asset 생성**
1. Content Browser에서 **우클릭**
2. **Miscellaneous → Data Asset** 선택
3. 목록에서 **MassEntityConfigAsset** 선택
4. 이름 지정 (예: `DA_Monster_Goblin`)

**Step 2: Trait 추가**
1. 생성된 에셋 더블클릭
2. **Traits** 배열에서 **+** 클릭
3. 필요한 Trait 선택해서 추가:
   - `AssortedFragmentsTrait` (기본)
   - `MassVisualizationTrait` (시각적 표현)
   - `MassMovementTrait` (이동)
   - 커스텀 Trait (직접 만든 것)

**Step 3: Trait 설정**
각 Trait를 펼쳐서 값 설정:
```
[Traits]
├─ [0] AssortedFragmentsTrait
│     └─ (기본값 사용)
├─ [1] MassVisualizationTrait
│     ├─ High Res Actor Class: BP_Monster_Goblin
│     ├─ Low Res Actor Class: None
│     └─ Static Mesh: SM_Monster_Goblin
├─ [2] MassMovementTrait
│     ├─ Max Speed: 400
│     └─ Acceleration: 800
└─ [3] MonsterBaseTrait (커스텀)
      ├─ Max Health: 100
      └─ Attack Damage: 10
```

### 상속 활용하기

Config Asset은 **Parent**를 설정해서 상속할 수 있어요:

```
DA_Monster_Base (기본 몬스터)
├─ DA_Monster_Goblin (고블린 - 빠름)
├─ DA_Monster_Orc (오크 - 강함)
└─ DA_Monster_Dragon (드래곤 - 비행 추가)
```

```cpp
// DA_Monster_Base
Traits:
- AssortedFragmentsTrait
- MassVisualizationTrait
- MassMovementTrait

// DA_Monster_Goblin
Parent: DA_Monster_Base  // 위의 모든 Trait 상속!
Traits:
- GoblinSpecificTrait    // 고블린 전용 추가
```

---

## 8. Command Buffer - "나중에 처리해 주세요"

### 이게 뭐예요?

Processor 실행 중에는 **엔티티 구조를 직접 바꿀 수 없어요**. Command Buffer를 통해 "나중에 처리해 주세요"라고 요청하는 거예요.

**왜 필요한가요?**
- Processor가 청크를 처리하는 도중에 엔티티를 삭제하면 배열 인덱스가 꼬여요
- Fragment를 추가하면 Archetype이 바뀌어서 메모리가 이동해요
- 그래서 "처리 끝나고 나서 해줘"라고 예약하는 거예요

### 사용 예시: 몬스터 죽음 처리

```cpp
void UDamageProcessor::Execute(FMassEntityManager& EntityManager,
                                FMassExecutionContext& Context)
{
    EntityQuery.ForEachEntityChunk(EntityManager, Context,
        [](FMassExecutionContext& Context)
        {
            auto HealthFragments = Context.GetMutableFragmentView<FMonsterHealthFragment>();

            for (int32 i = 0; i < Context.GetNumEntities(); ++i)
            {
                if (HealthFragments[i].CurrentHealth <= 0.0f)
                {
                    // 직접 삭제 불가! Command Buffer 사용
                    FMassEntityHandle Entity = Context.GetEntity(i);

                    // 옵션 1: 완전히 삭제
                    Context.Defer().DestroyEntity(Entity);

                    // 옵션 2: 죽음 태그 추가 (나중에 처리)
                    // Context.Defer().AddTag<FDeadTag>(Entity);
                }
            }
        });
}
```

### 주요 Defer 명령들

```cpp
FMassCommandBuffer& Defer = Context.Defer();

// 엔티티 삭제
Defer.DestroyEntity(Entity);

// Fragment 추가/제거
Defer.AddFragment<FShieldFragment>(Entity);
Defer.RemoveFragment<FShieldFragment>(Entity);

// Tag 추가/제거
Defer.AddTag<FBurningTag>(Entity);
Defer.RemoveTag<FBurningTag>(Entity);

// 복잡한 수정 (콜백으로)
Defer.PushCommand<FMassCommandChangeFragment>(
    Entity,
    [](FMassExecutionContext& Context, FMassEntityHandle Entity)
    {
        // 복잡한 수정 로직
    });
```

---

## 9. 전체 아키텍처 요약

```
┌─────────────────────────────────────────────────────────────────────┐
│                          Mass AI 전체 흐름                           │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  [1] Entity Config Asset (에디터에서 설계)                          │
│      └─ Trait들이 Fragment 조합 정의                                │
│                     │                                                │
│                     ▼                                                │
│  [2] Mass Spawner (엔티티 생성)                                     │
│      └─ Config를 기반으로 Entity + Archetype 생성                   │
│                     │                                                │
│                     ▼                                                │
│  [3] Entity Manager (중앙 관리)                                     │
│      ├─ Archetype별로 엔티티 그룹화                                 │
│      └─ 청크(Chunk) 단위로 메모리 배치                              │
│                     │                                                │
│                     ▼                                                │
│  [4] Processor (매 프레임 처리)                                     │
│      ├─ Query로 처리할 엔티티 필터링                                │
│      ├─ 청크 단위로 배치 처리                                       │
│      └─ Command Buffer로 지연 명령                                  │
│                     │                                                │
│                     ▼                                                │
│  [5] 결과                                                           │
│      └─ Fragment 데이터 업데이트, 렌더링, 게임플레이                │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 10. 다음 단계

코어 아키텍처를 이해했다면, 다음 문서에서 렌더링과 LOD 시스템을 살펴보겠습니다:

- **다음**: [03_RenderingAndLOD.md](03_RenderingAndLOD.md) - ISM 렌더링, LOD 전환, 시각적 표현 시스템

### 이 문서에서 배운 것

1. **Entity Manager**: 모든 엔티티의 중앙 관리자
2. **Fragment**: 순수 데이터 (행동 없음)
3. **Processor**: 행동 로직 담당 (배치 처리)
4. **Archetype**: 같은 Fragment 조합의 엔티티 그룹
5. **Query**: 조건으로 엔티티 필터링
6. **Trait**: 재사용 가능한 Fragment 조합 레시피
7. **Config Asset**: 에디터에서 엔티티 설계
8. **Command Buffer**: 지연 실행 명령
