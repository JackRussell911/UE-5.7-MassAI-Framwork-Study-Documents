# 렌더링 및 LOD 시스템

> **문서 목적**: Mass AI의 시각적 표현 시스템과 LOD 최적화 이해

---

## 1. 표현 시스템 개요 (Representation System)

Mass AI는 3단계 표현 시스템을 통해 수천 개의 엔티티를 효율적으로 렌더링합니다.

### 표현 타입 (EMassRepresentationType)

```cpp
// MassRepresentationTypes.h
enum class EMassRepresentationType : uint8
{
    None,                    // 렌더링 안 함 (화면 밖)
    StaticMeshInstance,      // ISM 렌더링 (가장 효율적)
    LowResSpawnedActor,      // 간소화된 Actor
    HighResSpawnedActor      // 풀 기능 Actor
};
```

### 거리별 표현 전략

```
┌────────────────────────────────────────────────────────────────┐
│                        카메라                                   │
│                          ●                                      │
│                          │                                      │
│   0m ─────────────────── │ ───────────────────────────── ∞     │
│         │                │                │                     │
│         ▼                ▼                ▼                     │
│   ┌──────────┐    ┌──────────┐    ┌──────────────┐             │
│   │HighRes   │    │ LowRes   │    │ ISM          │             │
│   │Actor     │    │ Actor    │    │ Instance     │             │
│   ├──────────┤    ├──────────┤    ├──────────────┤             │
│   │0-50m     │    │50-200m   │    │200m+         │             │
│   │~100개    │    │~500개    │    │나머지 전부   │             │
│   │풀 기능   │    │간소화    │    │최소 기능     │             │
│   └──────────┘    └──────────┘    └──────────────┘             │
└────────────────────────────────────────────────────────────────┘
```

---

## 2. ISM (Instanced Static Mesh) 렌더링

ISM은 Mass AI의 **핵심 렌더링 최적화** 기법입니다.

### 소스 위치
```
C:\Program Files\Epic Games\UE_5.7.1\UE_5.7\Engine\Plugins\Runtime\MassGameplay\Source\MassRepresentation\Public\MassRepresentationTypes.h
```

### ISM의 이점

| 항목 | 개별 Actor 렌더링 | ISM 렌더링 |
|------|------------------|------------|
| 드로우 콜 | 엔티티당 1회 | 메시 타입당 1회 |
| CPU 오버헤드 | 높음 | 매우 낮음 |
| GPU 배칭 | 불가능 | 자동 배칭 |
| 1000개 드로우 콜 | 1000회 | 1-10회 |

### ISM 데이터 구조

```cpp
// ISM 공유 데이터
struct FMassISMCSharedData
{
    // ISM 컴포넌트 관리
    TArray<UInstancedStaticMeshComponent*> ISMComponents;

    // 인스턴스 ID 추적
    bool bRequiresExternalInstanceIDTracking;

    // 배치 트랜스폼 업데이트
    void BatchUpdateTransforms(const TArray<FTransform>& Transforms);
};

// ISM 메시 설명
struct FStaticMeshInstanceVisualizationMeshDesc
{
    UPROPERTY()
    UStaticMesh* Mesh;

    UPROPERTY()
    TArray<UMaterialInterface*> MaterialOverrides;

    UPROPERTY()
    FTransform LocalTransform;

    // LOD 범위
    UPROPERTY()
    float MinLODSignificance = 0.0f;

    UPROPERTY()
    float MaxLODSignificance = 3.0f;

    UPROPERTY()
    bool bCastShadow = true;

    // 인스턴스별 커스텀 데이터 (셰이더용)
    UPROPERTY()
    TArray<float> CustomDataFloats;
};
```

### ISM 설정 예시

```cpp
// Visualization Trait에서 ISM 설정
UCLASS()
class UMonsterVisualizationTrait : public UMassVisualizationTrait
{
    GENERATED_BODY()

public:
    virtual void BuildTemplate(FMassEntityTemplateBuildContext& BuildContext,
                               const UWorld& World) const override
    {
        Super::BuildTemplate(BuildContext, World);

        // ISM 메시 설명 추가
        FStaticMeshInstanceVisualizationMeshDesc MeshDesc;
        MeshDesc.Mesh = MonsterStaticMesh;
        MeshDesc.bCastShadow = false;  // 성능을 위해 그림자 비활성화
        MeshDesc.MinLODSignificance = 2.0f;  // Low LOD부터 사용
        MeshDesc.MaxLODSignificance = 3.0f;

        // 커스텀 셰이더 데이터 (예: 색상 변형)
        MeshDesc.CustomDataFloats.Add(FMath::RandRange(0.0f, 1.0f));  // Hue

        BuildContext.AddStaticMeshVisualization(MeshDesc);
    }

    UPROPERTY(EditAnywhere)
    UStaticMesh* MonsterStaticMesh;
};
```

---

## 3. LOD 시스템

### 소스 위치
```
C:\Program Files\Epic Games\UE_5.7.1\UE_5.7\Engine\Plugins\Runtime\MassGameplay\Source\MassLOD\Public\MassLODFragments.h
```

### LOD 레벨

```cpp
namespace EMassLOD
{
    enum Type : uint8
    {
        High = 0,      // 가장 가까움, 풀 시뮬레이션
        Medium = 1,    // 중간 거리
        Low = 2,       // 먼 거리
        Off = 3        // 화면 밖, 최소 처리
    };
}
```

### LOD Fragment

```cpp
// 표현 LOD Fragment
USTRUCT()
struct FMassRepresentationLODFragment : public FMassFragment
{
    GENERATED_BODY()

    // 현재 LOD
    EMassLOD::Type LOD = EMassLOD::High;

    // 이전 프레임 LOD (전환 감지용)
    EMassLOD::Type PrevLOD = EMassLOD::High;

    // 가시성 상태
    EMassVisibility Visibility = EMassVisibility::CanBeSeen;

    // LOD 중요도 (0.0 = High, 3.0 = Off)
    float LODSignificance = 0.0f;
};

// 뷰어 정보 Fragment
USTRUCT()
struct FMassViewerInfoFragment : public FMassFragment
{
    GENERATED_BODY()

    // 가장 가까운 뷰어까지 거리 제곱
    float ClosestViewerDistanceSq = 0.0f;

    // 프러스텀까지 거리
    float ClosestDistanceToFrustum = 0.0f;
};
```

### LOD 파라미터 설정

```cpp
// MassVisualizationLODProcessor.h
struct FMassVisualizationLODParameters
{
    // LOD별 기준 거리 (cm)
    float BaseLODDistance[4] = {
        0.0f,       // High: 0m부터
        1000.0f,    // Medium: 10m부터
        2500.0f,    // Low: 25m부터
        10000.0f    // Off: 100m부터
    };

    // 가시 범위 거리
    float VisibleLODDistance[4] = {
        0.0f,
        2000.0f,    // Medium까지 보임: 20m
        4000.0f,    // Low까지 보임: 40m
        15000.0f    // Off까지 보임: 150m
    };

    // LOD별 최대 개수 제한
    int32 LODMaxCount[4] = {
        50,         // High: 최대 50개
        100,        // Medium: 최대 100개
        500,        // Low: 최대 500개
        MAX_int32   // Off: 무제한
    };

    // 히스테리시스 (떨림 방지)
    float BufferHysteresisOnDistancePercentage = 10.0f;
};
```

### 1000-5000 마리 규모 권장 LOD 설정

```cpp
FMassVisualizationLODParameters OptimizedParams;

// 거리 설정 (cm 단위)
OptimizedParams.BaseLODDistance[EMassLOD::High] = 0.0f;
OptimizedParams.BaseLODDistance[EMassLOD::Medium] = 5000.0f;   // 50m
OptimizedParams.BaseLODDistance[EMassLOD::Low] = 20000.0f;     // 200m
OptimizedParams.BaseLODDistance[EMassLOD::Off] = 50000.0f;     // 500m

// 최대 개수 제한
OptimizedParams.LODMaxCount[EMassLOD::High] = 100;    // Actor 100개 제한
OptimizedParams.LODMaxCount[EMassLOD::Medium] = 500;  // Low Actor 500개
OptimizedParams.LODMaxCount[EMassLOD::Low] = 5000;    // ISM 5000개
OptimizedParams.LODMaxCount[EMassLOD::Off] = MAX_int32;

// 히스테리시스 (LOD 전환 떨림 방지)
OptimizedParams.BufferHysteresisOnDistancePercentage = 15.0f;
```

---

## 4. 표현 전환 (Representation Switching)

### 표현 파라미터

```cpp
// MassRepresentationFragments.h
struct FMassRepresentationParameters
{
    // LOD별 표현 타입
    EMassRepresentationType LODRepresentation[4] = {
        EMassRepresentationType::HighResSpawnedActor,  // High: 풀 Actor
        EMassRepresentationType::LowResSpawnedActor,   // Medium: 간소화 Actor
        EMassRepresentationType::StaticMeshInstance,   // Low: ISM
        EMassRepresentationType::None                  // Off: 렌더링 안 함
    };

    // 화면 밖 엔티티 업데이트 주기 (프레임)
    int32 NotVisibleUpdateRate = 4;

    // Actor 유지 옵션
    bool bKeepLowResActors = false;
    bool bKeepActorExtraFrame = true;
};
```

### 표현 Fragment

```cpp
USTRUCT()
struct FMassRepresentationFragment : public FMassFragment
{
    GENERATED_BODY()

    // 현재 표현 타입
    EMassRepresentationType CurrentRepresentation =
        EMassRepresentationType::None;

    // Actor 템플릿 인덱스
    int16 HighResTemplateActorIndex = INDEX_NONE;
    int16 LowResTemplateActorIndex = INDEX_NONE;

    // ISM 핸들
    FStaticMeshInstanceVisualizationDescHandle StaticMeshDescHandle;

    // LOD 중요도
    float LODSignificance = 0.0f;
};
```

### 전환 프로세서

```cpp
// MassRepresentationProcessor가 처리
// 1. LOD 계산 (거리, 가시성 기반)
// 2. 표현 타입 결정
// 3. 필요시 Actor 스폰/디스폰
// 4. ISM 인스턴스 추가/제거
```

---

## 5. Visualization Component

### 소스 위치
```
C:\Program Files\Epic Games\UE_5.7.1\UE_5.7\Engine\Plugins\Runtime\MassGameplay\Source\MassRepresentation\Public\MassVisualizationComponent.h
```

### 주요 기능

```cpp
UCLASS()
class UMassVisualizationComponent : public UActorComponent
{
    GENERATED_BODY()

public:
    // ISM 메시 등록
    FStaticMeshInstanceVisualizationDescHandle FindOrAddVisualDesc(
        const FStaticMeshInstanceVisualizationMeshDesc& Desc);

    // ISM 컴포넌트와 연결
    void AddVisualDescWithISMComponent(
        const FStaticMeshInstanceVisualizationDescHandle& Handle,
        UInstancedStaticMeshComponent* ISMComponent);

    // 비주얼 정보 접근
    TArray<FMassInstancedStaticMeshInfo>& GetMutableVisualInfos();

    // 배치 업데이트
    void BeginVisualChanges();
    void EndVisualChanges();

    // 강제 새로고침
    void DirtyVisuals();
};
```

---

## 6. Actor 스폰 관리

### Representation Subsystem

```cpp
// MassRepresentationSubsystem.h
UCLASS()
class UMassRepresentationSubsystem : public UWorldSubsystem
{
    GENERATED_BODY()

public:
    // Actor 템플릿 등록
    int16 FindOrAddTemplateActor(TSubclassOf<AActor> ActorClass);

    // Actor 스폰 요청 (풀링됨)
    AActor* SpawnOrReuseActor(
        int16 TemplateIndex,
        const FTransform& Transform);

    // Actor 반환 (풀로)
    void ReleaseActor(AActor* Actor, bool bImmediate = false);

    // Actor 풀 관리
    void SetActorPoolSize(int16 TemplateIndex, int32 PoolSize);
};
```

### Actor 풀링

```cpp
// 풀 크기 설정 (시작 시)
void AMyGameMode::BeginPlay()
{
    Super::BeginPlay();

    UMassRepresentationSubsystem* RepSubsystem =
        GetWorld()->GetSubsystem<UMassRepresentationSubsystem>();

    // 몬스터 Actor 풀 준비
    int16 HighResIndex = RepSubsystem->FindOrAddTemplateActor(HighResMonsterClass);
    int16 LowResIndex = RepSubsystem->FindOrAddTemplateActor(LowResMonsterClass);

    RepSubsystem->SetActorPoolSize(HighResIndex, 100);  // 100개 풀
    RepSubsystem->SetActorPoolSize(LowResIndex, 500);   // 500개 풀
}
```

---

## 7. Visualization Trait 설정

### 기본 Trait

```cpp
// MassVisualizationTrait.h
UCLASS()
class UMassVisualizationTrait : public UMassEntityTraitBase
{
    GENERATED_BODY()

public:
    // High LOD Actor 클래스
    UPROPERTY(EditAnywhere, Category = "Visualization")
    TSubclassOf<AActor> HighResTemplateActor;

    // Low LOD Actor 클래스
    UPROPERTY(EditAnywhere, Category = "Visualization")
    TSubclassOf<AActor> LowResTemplateActor;

    // ISM 메시 설명
    UPROPERTY(EditAnywhere, Category = "Visualization")
    FStaticMeshInstanceVisualizationDesc StaticMeshInstanceDesc;

    // LOD 파라미터
    UPROPERTY(EditAnywhere, Category = "LOD")
    FMassVisualizationLODParameters LODParams;

    // 표현 파라미터
    UPROPERTY(EditAnywhere, Category = "Representation")
    FMassRepresentationParameters RepresentationParams;
};
```

### 커스텀 설정 예시

```cpp
// 에디터에서 설정 가능한 값들:

// 1. HighResTemplateActor
//    - BP_Monster_HighRes (풀 스켈레탈 메시 + 애니메이션)

// 2. LowResTemplateActor
//    - BP_Monster_LowRes (간소화된 메시, 기본 애니메이션)

// 3. StaticMeshInstanceDesc
//    - Mesh: SM_Monster_Billboard 또는 SM_Monster_LowPoly
//    - bCastShadow: false (성능)
//    - CustomDataFloats: [ColorVariation]

// 4. LODParams
//    - BaseLODDistance: [0, 5000, 20000, 50000]
//    - LODMaxCount: [100, 500, 5000, MAX]

// 5. RepresentationParams
//    - LODRepresentation: [HighRes, LowRes, ISM, None]
//    - NotVisibleUpdateRate: 4
```

---

## 8. 성능 최적화 팁

### 8.1 ISM 최적화

```cpp
// 1. 그림자 비활성화 (원거리)
MeshDesc.bCastShadow = false;

// 2. 단순화된 메시 사용
// - 삼각형 수: 100-500개 권장
// - 텍스처: 아틀라스 사용

// 3. 머티리얼 인스턴스 공유
// - 모든 몬스터가 같은 머티리얼 인스턴스 사용
// - CustomData로 변형

// 4. LOD 메시 활용
// - UStaticMesh의 LOD 레벨 사용
// - ISM이 자동으로 LOD 전환
```

### 8.2 Actor 풀링 최적화

```cpp
// 1. 풀 크기 사전 계산
int32 EstimatedHighResCount = 100;  // 화면에 보일 최대 개수
int32 PoolBuffer = 20;              // 버퍼
RepSubsystem->SetActorPoolSize(HighResIndex, EstimatedHighResCount + PoolBuffer);

// 2. 비활성화 대신 풀 반환
// 직접 Destroy하지 말고 ReleaseActor 사용
RepSubsystem->ReleaseActor(Actor, false);

// 3. 컴포넌트 최소화
// High/Low Res Actor에 필수 컴포넌트만 포함
```

### 8.3 LOD 전환 최적화

```cpp
// 1. 히스테리시스 설정
LODParams.BufferHysteresisOnDistancePercentage = 15.0f;

// 2. 최대 개수 제한
LODParams.LODMaxCount[EMassLOD::High] = 100;

// 3. 업데이트 주기 조절
RepresentationParams.NotVisibleUpdateRate = 8;  // 화면 밖은 8프레임마다
```

---

## 9. 디버깅

### 콘솔 명령어

```
// ISM 통계 표시
stat SceneRendering

// Mass Entity 디버그
Mass.Debug.Representation 1

// LOD 시각화
Mass.Debug.LOD 1
```

### 디버그 코드

```cpp
#if WITH_MASSENTITY_DEBUG
void DebugDrawLOD(const FMassEntityManager& EntityManager)
{
    FMassEntityQuery DebugQuery;
    DebugQuery.AddRequirement<FTransformFragment>(EMassFragmentAccess::ReadOnly);
    DebugQuery.AddRequirement<FMassRepresentationLODFragment>(EMassFragmentAccess::ReadOnly);

    DebugQuery.ForEachEntityChunk(EntityManager, Context,
        [](FMassExecutionContext& Context)
        {
            auto Transforms = Context.GetFragmentView<FTransformFragment>();
            auto LODs = Context.GetFragmentView<FMassRepresentationLODFragment>();

            for (int32 i = 0; i < Context.GetNumEntities(); ++i)
            {
                FColor Color;
                switch (LODs[i].LOD)
                {
                    case EMassLOD::High: Color = FColor::Green; break;
                    case EMassLOD::Medium: Color = FColor::Yellow; break;
                    case EMassLOD::Low: Color = FColor::Red; break;
                    default: Color = FColor::Black; break;
                }

                DrawDebugSphere(GetWorld(),
                    Transforms[i].Transform.GetLocation(),
                    50.0f, 8, Color);
            }
        });
}
#endif
```

---

## 10. 다음 단계

렌더링과 LOD 시스템을 이해했다면, 다음 문서에서 애니메이션 통합을 살펴보겠습니다:

- **다음**: [04_AnimationIntegration.md](04_AnimationIntegration.md) - 스켈레탈 애니메이션 통합 및 거리별 애니메이션 전략
