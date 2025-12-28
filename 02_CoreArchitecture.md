# 코어 아키텍처 상세 분석

> **문서 목적**: Mass AI의 핵심 구조인 Entity, Fragment, Processor, Archetype 시스템 이해

---

## 1. Entity Manager (FMassEntityManager)

Entity Manager는 Mass AI 시스템의 **중앙 관리자**입니다. 모든 엔티티의 생성, 삭제, 쿼리를 담당합니다.

### 소스 위치
```
C:\Program Files\Epic Games\UE_5.7.1\UE_5.7\Engine\Source\Runtime\MassEntity\Public\MassEntityManager.h
```

### 주요 기능

```cpp
class FMassEntityManager
{
public:
    // === 엔티티 생성 ===
    FMassEntityHandle CreateEntity(const FMassArchetypeHandle& Archetype);
    void BatchCreateEntities(const FMassArchetypeHandle& Archetype,
                             int32 Count,
                             TArray<FMassEntityHandle>& OutEntities);

    // === 2단계 생성 (최적화) ===
    FMassEntityHandle ReserveEntity();           // 1단계: 핸들 예약
    void BuildEntity(FMassEntityHandle Entity,   // 2단계: 실제 생성
                     const FMassArchetypeHandle& Archetype);

    // === 엔티티 삭제 ===
    void DestroyEntity(FMassEntityHandle Entity);
    void BatchDestroyEntities(TArrayView<FMassEntityHandle> Entities);

    // === Fragment 접근 ===
    template<typename T>
    T* GetFragmentDataPtr(FMassEntityHandle Entity);

    template<typename T>
    void AddFragmentToEntity(FMassEntityHandle Entity);

    // === 쿼리 실행 ===
    void ExecuteEntityQuery(const FMassEntityQuery& Query,
                            FMassExecutionContext& Context);
};
```

### 사용 예시

```cpp
// Entity Manager 접근
UMassEntitySubsystem* EntitySubsystem = GetWorld()->GetSubsystem<UMassEntitySubsystem>();
FMassEntityManager& EntityManager = EntitySubsystem->GetMutableEntityManager();

// 배치 엔티티 생성
TArray<FMassEntityHandle> Monsters;
EntityManager.BatchCreateEntities(MonsterArchetype, 1000, Monsters);

// Fragment 데이터 접근
FTransformFragment* Transform = EntityManager.GetFragmentDataPtr<FTransformFragment>(Monsters[0]);
Transform->Transform.SetLocation(FVector(100, 200, 0));
```

---

## 2. Fragment 시스템

Fragment는 **순수 데이터 구조체**입니다. 행동 로직 없이 상태만 저장합니다.

### 소스 위치
```
C:\Program Files\Epic Games\UE_5.7.1\UE_5.7\Engine\Source\Runtime\MassEntity\Public\MassEntityElementTypes.h
```

### Fragment 타입들

```cpp
// 1. 기본 Fragment - 엔티티별 고유 데이터
USTRUCT()
struct FMassFragment
{
    GENERATED_BODY()
    // 상속하여 사용
};

// 2. Tag - 데이터 없는 마커 (플래그)
USTRUCT()
struct FMassTag
{
    GENERATED_BODY()
    // 멤버 변수 없음!
};

// 3. Chunk Fragment - 청크 내 공유 데이터
USTRUCT()
struct FMassChunkFragment
{
    GENERATED_BODY()
    // 같은 청크의 모든 엔티티가 공유
};

// 4. Shared Fragment - 여러 엔티티가 공유 (수정 가능)
USTRUCT()
struct FMassSharedFragment
{
    GENERATED_BODY()
};

// 5. Const Shared Fragment - 여러 엔티티가 공유 (읽기 전용)
USTRUCT()
struct FMassConstSharedFragment
{
    GENERATED_BODY()
};
```

### 자주 사용되는 Fragment들

**MassCommon 모듈** (`MassCommonFragments.h`)
```cpp
// 위치/회전 정보
USTRUCT()
struct FTransformFragment : public FMassFragment
{
    GENERATED_BODY()
    FTransform Transform;
};

// 충돌 반경
USTRUCT()
struct FAgentRadiusFragment : public FMassFragment
{
    GENERATED_BODY()
    float Radius = 40.0f;
};
```

**MassMovement 모듈** (`MassMovementFragments.h`)
```cpp
// 현재 속도
USTRUCT()
struct FMassVelocityFragment : public FMassFragment
{
    GENERATED_BODY()
    FVector Value = FVector::ZeroVector;
};

// 원하는 이동 방향/속도
USTRUCT()
struct FMassDesiredMovementFragment : public FMassFragment
{
    GENERATED_BODY()
    FVector DesiredVelocity = FVector::ZeroVector;
    FRotator DesiredFacing = FRotator::ZeroRotator;
};

// 이동 파라미터
USTRUCT()
struct FMassMovementParameters : public FMassSharedFragment
{
    GENERATED_BODY()
    float MaxSpeed = 400.0f;
    float Acceleration = 800.0f;
};
```

### 커스텀 Fragment 정의 예시

```cpp
// 몬스터 체력 Fragment
USTRUCT()
struct FMonsterHealthFragment : public FMassFragment
{
    GENERATED_BODY()

    UPROPERTY()
    float CurrentHealth = 100.0f;

    UPROPERTY()
    float MaxHealth = 100.0f;
};

// 몬스터 타입 태그
USTRUCT()
struct FMonsterTag : public FMassTag
{
    GENERATED_BODY()
};

// 공격 대상 Fragment
USTRUCT()
struct FTargetFragment : public FMassFragment
{
    GENERATED_BODY()

    UPROPERTY()
    FMassEntityHandle TargetEntity;

    UPROPERTY()
    FVector TargetLocation = FVector::ZeroVector;
};
```

---

## 3. Processor 시스템

Processor는 **행동 로직**을 담당합니다. Fragment 데이터를 읽고 수정합니다.

### 소스 위치
```
C:\Program Files\Epic Games\UE_5.7.1\UE_5.7\Engine\Source\Runtime\MassEntity\Public\MassProcessor.h
```

### 기본 구조

```cpp
UCLASS()
class UMassProcessor : public UObject
{
    GENERATED_BODY()

public:
    // 쿼리 설정 (어떤 Fragment를 가진 엔티티를 처리할지)
    virtual void ConfigureQueries() PURE_VIRTUAL;

    // 초기화
    virtual void InitializeInternal(UObject& Owner);

    // 매 프레임 실행
    virtual void Execute(FMassEntityManager& EntityManager,
                         FMassExecutionContext& Context) PURE_VIRTUAL;

protected:
    // 처리 단계 (PrePhysics, Physics, PostPhysics, FrameEnd)
    UPROPERTY()
    EMassProcessingPhase ProcessingPhase = EMassProcessingPhase::PrePhysics;

    // 실행 순서
    UPROPERTY()
    FMassProcessorExecutionOrder ExecutionOrder;

    // 엔티티 쿼리
    FMassEntityQuery EntityQuery;
};
```

### Processor 구현 예시

```cpp
// 몬스터 이동 Processor
UCLASS()
class UMonsterMovementProcessor : public UMassProcessor
{
    GENERATED_BODY()

public:
    UMonsterMovementProcessor()
    {
        // PrePhysics 단계에서 실행
        ProcessingPhase = EMassProcessingPhase::PrePhysics;

        // 다른 이동 프로세서 이후 실행
        ExecutionOrder.ExecuteAfter.Add(UMassApplyMovementProcessor::StaticClass());
    }

    virtual void ConfigureQueries() override
    {
        // 필요한 Fragment 지정
        EntityQuery.AddRequirement<FTransformFragment>(EMassFragmentAccess::ReadWrite);
        EntityQuery.AddRequirement<FMassVelocityFragment>(EMassFragmentAccess::ReadOnly);
        EntityQuery.AddRequirement<FMonsterTag>(EMassFragmentPresence::All);

        // 선택적 Fragment
        EntityQuery.AddRequirement<FTargetFragment>(EMassFragmentPresence::Optional);
    }

    virtual void Execute(FMassEntityManager& EntityManager,
                         FMassExecutionContext& Context) override
    {
        // 청크 단위 처리
        EntityQuery.ForEachEntityChunk(EntityManager, Context,
            [this](FMassExecutionContext& Context)
            {
                // Fragment 뷰 획득
                auto Transforms = Context.GetMutableFragmentView<FTransformFragment>();
                auto Velocities = Context.GetFragmentView<FMassVelocityFragment>();
                const float DeltaTime = Context.GetDeltaTimeSeconds();

                // 모든 엔티티 순회
                const int32 NumEntities = Context.GetNumEntities();
                for (int32 i = 0; i < NumEntities; ++i)
                {
                    // 위치 업데이트
                    FVector NewLocation = Transforms[i].Transform.GetLocation()
                                        + Velocities[i].Value * DeltaTime;
                    Transforms[i].Transform.SetLocation(NewLocation);
                }
            });
    }
};
```

### 처리 단계 (Processing Phase)

```cpp
enum class EMassProcessingPhase : uint8
{
    PrePhysics,      // 물리 시뮬레이션 전
    StartPhysics,    // 물리 시작
    DuringPhysics,   // 물리 중
    EndPhysics,      // 물리 종료
    PostPhysics,     // 물리 후
    FrameEnd         // 프레임 끝
};
```

---

## 4. Archetype 시스템

Archetype은 **동일한 Fragment 조합**을 가진 엔티티들의 그룹입니다.

### 개념

```
Archetype A: [Transform, Velocity, Health]
  → Monster 1, Monster 2, Monster 3... (같은 조합)

Archetype B: [Transform, Velocity, Health, Shield]
  → ShieldedMonster 1, ShieldedMonster 2... (Shield 추가)

Archetype C: [Transform, ProjectileData]
  → Bullet 1, Bullet 2, Bullet 3... (다른 조합)
```

### Archetype의 이점

1. **메모리 효율**: 같은 타입의 엔티티가 연속 메모리에 배치
2. **쿼리 최적화**: Fragment 조합으로 빠르게 필터링
3. **청크 처리**: 같은 Archetype의 엔티티를 배치 처리

### 소스 위치
```
C:\Program Files\Epic Games\UE_5.7.1\UE_5.7\Engine\Source\Runtime\MassEntity\Public\MassArchetypeTypes.h
```

### 주요 클래스

```cpp
// Archetype 구성 정의
struct FMassArchetypeCompositionDescriptor
{
    FMassFragmentBitSet Fragments;        // 포함된 Fragment들
    FMassTagBitSet Tags;                  // 포함된 Tag들
    FMassChunkFragmentBitSet ChunkFragments;
    FMassSharedFragmentBitSet SharedFragments;
};

// Archetype 핸들
struct FMassArchetypeHandle
{
    // Archetype 데이터에 대한 참조
    TSharedPtr<FMassArchetypeData> DataPtr;

    bool IsValid() const;
};
```

### Archetype 생성

```cpp
// 직접 생성
FMassArchetypeCompositionDescriptor Descriptor;
Descriptor.Fragments.Add<FTransformFragment>();
Descriptor.Fragments.Add<FMassVelocityFragment>();
Descriptor.Fragments.Add<FMonsterHealthFragment>();
Descriptor.Tags.Add<FMonsterTag>();

FMassArchetypeHandle MonsterArchetype = EntityManager.CreateArchetype(Descriptor);

// 또는 Template 사용 (권장)
// MassEntityConfigAsset에서 정의된 템플릿 활용
```

---

## 5. Entity Query 시스템

Query는 **특정 조건의 엔티티**를 필터링합니다.

### 소스 위치
```
C:\Program Files\Epic Games\UE_5.7.1\UE_5.7\Engine\Source\Runtime\MassEntity\Public\MassEntityQuery.h
```

### Query 구성

```cpp
FMassEntityQuery Query;

// 필수 Fragment (읽기/쓰기 모드 지정)
Query.AddRequirement<FTransformFragment>(EMassFragmentAccess::ReadWrite);
Query.AddRequirement<FMassVelocityFragment>(EMassFragmentAccess::ReadOnly);

// 필수 Tag (존재해야 함)
Query.AddRequirement<FMonsterTag>(EMassFragmentPresence::All);

// 선택적 Fragment (있으면 처리, 없으면 무시)
Query.AddRequirement<FTargetFragment>(EMassFragmentPresence::Optional);

// 제외 조건 (이 Fragment가 있으면 제외)
Query.AddRequirement<FDeadTag>(EMassFragmentPresence::None);
```

### Fragment 접근 모드

```cpp
enum class EMassFragmentAccess : uint8
{
    None,       // 접근 안 함
    ReadOnly,   // 읽기만
    ReadWrite   // 읽기/쓰기
};

enum class EMassFragmentPresence : uint8
{
    All,        // 반드시 있어야 함
    Any,        // 하나라도 있으면 됨
    Optional,   // 있으면 처리, 없어도 됨
    None        // 없어야 함 (제외 조건)
};
```

### Query 실행

```cpp
// 청크 단위 실행 (권장)
Query.ForEachEntityChunk(EntityManager, Context,
    [](FMassExecutionContext& Context)
    {
        // 청크 내 모든 엔티티 처리
        auto Transforms = Context.GetMutableFragmentView<FTransformFragment>();
        for (int32 i = 0; i < Context.GetNumEntities(); ++i)
        {
            // 처리 로직
        }
    });

// 개별 엔티티 실행 (느림, 특수 경우만 사용)
Query.ForEachEntity(EntityManager, Context,
    [](FMassEntityHandle Entity, FMassExecutionContext& Context)
    {
        // 개별 엔티티 처리
    });
```

---

## 6. Trait 시스템

Trait은 **Fragment 조합을 정의하는 에셋**입니다. 재사용 가능한 엔티티 구성을 만듭니다.

### 소스 위치
```
C:\Program Files\Epic Games\UE_5.7.1\UE_5.7\Engine\Plugins\Runtime\MassGameplay\Source\MassSpawner\Public\MassEntityTraitBase.h
```

### 기본 구조

```cpp
UCLASS(Abstract, BlueprintType, EditInlineNew)
class UMassEntityTraitBase : public UObject
{
    GENERATED_BODY()

public:
    // 템플릿에 Fragment/Tag 추가
    virtual void BuildTemplate(FMassEntityTemplateBuildContext& BuildContext,
                               const UWorld& World) const PURE_VIRTUAL;

    // 유효성 검사
    virtual void ValidateTemplate(FMassEntityTemplateBuildContext& BuildContext,
                                  const UWorld& World) const;

    // 정리
    virtual void DestroyTemplate() const;
};
```

### Trait 구현 예시

```cpp
// 몬스터 기본 Trait
UCLASS(meta = (DisplayName = "Monster Base Trait"))
class UMonsterBaseTrait : public UMassEntityTraitBase
{
    GENERATED_BODY()

public:
    UPROPERTY(EditAnywhere)
    float MaxHealth = 100.0f;

    UPROPERTY(EditAnywhere)
    float MoveSpeed = 400.0f;

    virtual void BuildTemplate(FMassEntityTemplateBuildContext& BuildContext,
                               const UWorld& World) const override
    {
        // Fragment 추가
        BuildContext.AddFragment<FTransformFragment>();
        BuildContext.AddFragment<FMassVelocityFragment>();

        // 초기값 설정
        FMonsterHealthFragment& Health = BuildContext.AddFragment<FMonsterHealthFragment>();
        Health.MaxHealth = MaxHealth;
        Health.CurrentHealth = MaxHealth;

        // Shared Fragment (이동 파라미터)
        FMassMovementParameters MovementParams;
        MovementParams.MaxSpeed = MoveSpeed;
        BuildContext.AddSharedFragment(MovementParams);

        // Tag 추가
        BuildContext.AddTag<FMonsterTag>();
    }
};
```

---

## 7. Entity Template & Config Asset

### Entity Config Asset

에디터에서 엔티티 구성을 정의하는 데이터 에셋입니다.

```cpp
// MassEntityConfigAsset.h
UCLASS(BlueprintType)
class UMassEntityConfigAsset : public UDataAsset
{
    GENERATED_BODY()

public:
    // Trait 목록
    UPROPERTY(EditAnywhere, Instanced)
    TArray<UMassEntityTraitBase*> Traits;

    // 부모 Config (상속)
    UPROPERTY(EditAnywhere)
    UMassEntityConfigAsset* Parent;
};
```

### 에디터에서 생성

1. Content Browser에서 우클릭
2. Miscellaneous → Data Asset 선택
3. `MassEntityConfigAsset` 선택
4. Traits 배열에 필요한 Trait 추가

### Template 빌드

```cpp
// Template 레지스트리에서 템플릿 생성
FMassEntityTemplateRegistry& Registry =
    UMassEntitySubsystem::Get(World).GetTemplateRegistry();

const FMassEntityTemplate* Template = Registry.FindOrBuildStructTemplate(
    *MonsterConfigAsset);

// 템플릿으로 엔티티 생성
FMassEntityHandle Monster = EntityManager.CreateEntity(Template->GetArchetype());
```

---

## 8. Command Buffer (지연 실행)

Processor 실행 중에는 엔티티 구조를 직접 변경할 수 없습니다. Command Buffer를 통해 지연 실행합니다.

### 소스 위치
```
C:\Program Files\Epic Games\UE_5.7.1\UE_5.7\Engine\Source\Runtime\MassEntity\Public\MassCommandBuffer.h
```

### 사용 예시

```cpp
void UDamageProcessor::Execute(FMassEntityManager& EntityManager,
                                FMassExecutionContext& Context)
{
    EntityQuery.ForEachEntityChunk(EntityManager, Context,
        [&](FMassExecutionContext& Context)
        {
            auto HealthFragments = Context.GetMutableFragmentView<FMonsterHealthFragment>();

            for (int32 i = 0; i < Context.GetNumEntities(); ++i)
            {
                if (HealthFragments[i].CurrentHealth <= 0.0f)
                {
                    // 직접 삭제 불가! Command Buffer 사용
                    FMassEntityHandle Entity = Context.GetEntity(i);

                    // 지연 삭제 명령
                    Context.Defer().DestroyEntity(Entity);

                    // 또는 Fragment 추가
                    Context.Defer().AddTag<FDeadTag>(Entity);
                }
            }
        });
}
```

### 주요 Defer 명령

```cpp
FMassCommandBuffer& Defer = Context.Defer();

// 엔티티 삭제
Defer.DestroyEntity(Entity);

// Fragment 추가/제거
Defer.AddFragment<FNewFragment>(Entity);
Defer.RemoveFragment<FOldFragment>(Entity);

// Tag 추가/제거
Defer.AddTag<FNewTag>(Entity);
Defer.RemoveTag<FOldTag>(Entity);

// Fragment 데이터 수정
Defer.PushCommand<FMassCommandChangeFragment>(
    Entity,
    [](FMassExecutionContext& Context, FMassEntityHandle Entity)
    {
        // 데이터 수정 로직
    });
```

---

## 9. 아키텍처 다이어그램

```
┌─────────────────────────────────────────────────────────────────┐
│                      FMassEntityManager                          │
│         (엔티티 생성/삭제/쿼리의 중앙 허브)                     │
└────────────────────────────┬────────────────────────────────────┘
                             │
        ┌────────────────────┼────────────────────┐
        ▼                    ▼                    ▼
┌───────────────┐   ┌───────────────┐   ┌───────────────────────┐
│ Archetype A   │   │ Archetype B   │   │ Archetype C           │
│ [Pos,Vel,HP]  │   │ [Pos,Vel,HP,  │   │ [Pos,ProjData]       │
│               │   │  Shield]      │   │                       │
├───────────────┤   ├───────────────┤   ├───────────────────────┤
│ Chunk 1       │   │ Chunk 1       │   │ Chunk 1               │
│ E1,E2,E3...   │   │ E10,E11...    │   │ E100,E101...          │
├───────────────┤   └───────────────┘   └───────────────────────┘
│ Chunk 2       │
│ E4,E5,E6...   │
└───────────────┘
        ▲                    ▲                    ▲
        │                    │                    │
        └────────────────────┼────────────────────┘
                             │
┌────────────────────────────┼────────────────────────────────────┐
│                      FMassEntityQuery                            │
│         (Fragment 조건으로 Archetype/Chunk 필터링)              │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│                       UMassProcessor                             │
│         (Query로 필터링된 엔티티들을 배치 처리)                 │
│                                                                  │
│  ForEachEntityChunk() → [Chunk1] → [Chunk2] → [Chunk3] ...      │
└─────────────────────────────────────────────────────────────────┘
```

---

## 10. 다음 단계

코어 아키텍처를 이해했다면, 다음 문서에서 렌더링과 LOD 시스템을 살펴보겠습니다:

- **다음**: [03_RenderingAndLOD.md](03_RenderingAndLOD.md) - ISM 렌더링, LOD 전환, 시각적 표현 시스템
