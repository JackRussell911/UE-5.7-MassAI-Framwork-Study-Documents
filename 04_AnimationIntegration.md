# 애니메이션 통합 전략

> **문서 목적**: Mass AI에서 기존 애니메이션 리소스를 활용하는 방법 이해

---

## 1. Mass AI 애니메이션 한계

### 핵심 제약

**Mass AI 코어는 스켈레탈 애니메이션을 직접 지원하지 않습니다.**

이유:
- Mass Entity는 순수 데이터 구조체 (Fragment)만 사용
- 스켈레탈 메시는 USkeletalMeshComponent 필요
- 애니메이션 블루프린트는 AActor 기반

### 해결 방안

```
┌─────────────────────────────────────────────────────────────────┐
│                      애니메이션 지원 방식                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  거리      표현 타입           애니메이션 방식                  │
│  ─────     ──────────          ──────────────                   │
│  가까움    HighResActor        풀 스켈레탈 애니메이션           │
│  중간      LowResActor         간소화된 애니메이션              │
│  멀리      ISM                 애니메이션 없음/셰이더 기반      │
│  화면 밖   None                처리 안 함                       │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## 2. Actor 기반 애니메이션

### High LOD Actor 설정

Mass 엔티티가 High LOD일 때 스폰되는 Actor에 애니메이션을 설정합니다.

```cpp
// BP_Monster_HighRes (Actor Blueprint)
UCLASS()
class ABP_Monster_HighRes : public AActor
{
    GENERATED_BODY()

public:
    ABP_Monster_HighRes()
    {
        // 스켈레탈 메시 컴포넌트
        SkeletalMesh = CreateDefaultSubobject<USkeletalMeshComponent>(TEXT("Mesh"));
        RootComponent = SkeletalMesh;

        // 애니메이션 블루프린트 설정
        SkeletalMesh->SetAnimClass(UMonsterAnimInstance::StaticClass());
    }

    // Mass Agent 컴포넌트 (Mass Entity와 동기화)
    UPROPERTY(VisibleAnywhere)
    UMassAgentComponent* MassAgent;

    UPROPERTY(VisibleAnywhere)
    USkeletalMeshComponent* SkeletalMesh;
};
```

### 애니메이션 블루프린트 (AnimBP)

```cpp
// UMonsterAnimInstance
UCLASS()
class UMonsterAnimInstance : public UAnimInstance
{
    GENERATED_BODY()

public:
    // Mass Entity로부터 전달받을 데이터
    UPROPERTY(BlueprintReadOnly, Category = "Animation")
    float Speed = 0.0f;

    UPROPERTY(BlueprintReadOnly, Category = "Animation")
    bool bIsAttacking = false;

    UPROPERTY(BlueprintReadOnly, Category = "Animation")
    FVector MoveDirection = FVector::ZeroVector;

    virtual void NativeUpdateAnimation(float DeltaSeconds) override
    {
        Super::NativeUpdateAnimation(DeltaSeconds);

        if (AActor* Owner = TryGetPawnOwner())
        {
            // MassAgent로부터 속도 정보 가져오기
            if (UMassAgentComponent* Agent = Owner->FindComponentByClass<UMassAgentComponent>())
            {
                // Fragment 데이터 접근
                // (Translator가 이미 동기화했다면 Actor 컴포넌트에서 가져오기)
            }

            // 또는 Actor의 속도 직접 사용
            Speed = Owner->GetVelocity().Size();
        }
    }
};
```

---

## 3. Translator 시스템

Translator는 Mass Entity의 Fragment 데이터를 Actor 컴포넌트와 **동기화**합니다.

### 소스 위치
```
C:\Program Files\Epic Games\UE_5.7.1\UE_5.7\Engine\Plugins\Runtime\MassGameplay\Source\MassActors\Public\Translators\
```

### 내장 Translator들

```cpp
// 이동 정보 동기화
MassCharacterMovementTranslators.h
  → FMassVelocityFragment ↔ CharacterMovementComponent

// 위치/회전 동기화
MassSceneComponentLocationTranslator.h
  → FTransformFragment ↔ SceneComponent::Transform

// 속도 동기화
MassSceneComponentVelocityTranslator.h
  → FMassVelocityFragment ↔ SceneComponent::Velocity
```

### 커스텀 Translator 구현

```cpp
// 애니메이션 상태 Translator
USTRUCT()
struct FMassAnimationStateTranslator : public FMassTranslator
{
    GENERATED_BODY()

    // Mass → Actor 방향 동기화
    virtual void CopyToActor(const FMassEntityManager& EntityManager,
                             FMassEntityHandle Entity,
                             AActor* Actor) const override
    {
        // Fragment에서 데이터 읽기
        const FMonsterAnimStateFragment* AnimState =
            EntityManager.GetFragmentDataPtr<FMonsterAnimStateFragment>(Entity);

        if (!AnimState) return;

        // Actor의 AnimInstance에 전달
        if (USkeletalMeshComponent* Mesh = Actor->FindComponentByClass<USkeletalMeshComponent>())
        {
            if (UMonsterAnimInstance* AnimInst = Cast<UMonsterAnimInstance>(Mesh->GetAnimInstance()))
            {
                AnimInst->Speed = AnimState->CurrentSpeed;
                AnimInst->bIsAttacking = AnimState->bIsAttacking;
                AnimInst->MoveDirection = AnimState->MoveDirection;
            }
        }
    }

    // Actor → Mass 방향 동기화 (필요시)
    virtual void CopyFromActor(FMassEntityManager& EntityManager,
                               FMassEntityHandle Entity,
                               const AActor* Actor) const override
    {
        // Root Motion 등의 경우 Actor에서 Mass로 데이터 복사
    }
};
```

### 애니메이션 상태 Fragment

```cpp
// 애니메이션 상태를 저장하는 Fragment
USTRUCT()
struct FMonsterAnimStateFragment : public FMassFragment
{
    GENERATED_BODY()

    UPROPERTY()
    float CurrentSpeed = 0.0f;

    UPROPERTY()
    FVector MoveDirection = FVector::ZeroVector;

    UPROPERTY()
    bool bIsAttacking = false;

    UPROPERTY()
    bool bIsHit = false;

    UPROPERTY()
    bool bIsDead = false;

    // 애니메이션 몽타주 인덱스 (가벼운 참조)
    UPROPERTY()
    uint8 CurrentMontageIndex = 0;
};
```

---

## 4. 거리별 애니메이션 전략

### High LOD (0-50m): 풀 애니메이션

```cpp
// 풀 스켈레탈 메시 + 애니메이션 블루프린트
// - 모든 본 애니메이션
// - 블렌드 스페이스
// - 애니메이션 몽타주
// - IK, 물리 시뮬레이션

class ABP_Monster_HighRes
{
    USkeletalMeshComponent* Mesh;       // 풀 스켈레톤
    UAnimInstance* AnimInstance;        // 애니메이션 BP
    // 약 50-100개 제한 권장
};
```

### Medium LOD (50-200m): 간소화 애니메이션

```cpp
// 간소화된 스켈레탈 메시 + 단순 애니메이션
// - 줄어든 본 수 (주요 본만)
// - 단순 블렌드
// - 몽타주 없음
// - IK 없음

class ABP_Monster_LowRes
{
    USkeletalMeshComponent* SimpleMesh;  // 간소화 스켈레톤 (20-30개 본)
    UAnimInstance* SimpleAnimInstance;   // 단순 스테이트 머신
    // 약 500개까지 가능
};
```

### Low LOD (200m+): ISM (애니메이션 없음)

```cpp
// Static Mesh Instance
// - 애니메이션 불가
// - 셰이더 기반 가짜 움직임 가능

// 셰이더에서 월드 포지션 오프셋으로 흔들림 효과
// Material Graph:
// WorldPositionOffset = sin(Time + VertexPosition.z) * SwayAmount
```

---

## 5. 애니메이션 최적화 기법

### 5.1 애니메이션 LOD

```cpp
// USkeletalMeshComponent 설정
SkeletalMesh->SetEnableAnimationLOD(true);
SkeletalMesh->SetAnimationLODThresholds({
    0.8f,   // LOD0 -> LOD1 전환
    0.5f,   // LOD1 -> LOD2 전환
    0.2f    // LOD2 -> LOD3 전환
});

// 또는 에디터에서:
// Skeletal Mesh Asset > LOD Settings > Animation LOD
```

### 5.2 업데이트 주기 최적화

```cpp
// 거리에 따른 업데이트 주기 조절
SkeletalMesh->SetComponentTickInterval(CalculateTickInterval(Distance));

float CalculateTickInterval(float Distance)
{
    if (Distance < 1000.0f) return 0.0f;      // 매 프레임
    if (Distance < 3000.0f) return 0.033f;    // 30fps
    if (Distance < 5000.0f) return 0.066f;    // 15fps
    return 0.1f;                               // 10fps
}
```

### 5.3 URO (Update Rate Optimization)

```cpp
// AnimInstance에서 URO 설정
UCLASS()
class UMonsterAnimInstance : public UAnimInstance
{
    virtual void NativeInitializeAnimation() override
    {
        // URO 활성화
        GetSkelMeshComponent()->SetEnableUpdateRateOptimizations(true);

        // 화면 밖에서 업데이트 건너뛰기
        GetSkelMeshComponent()->VisibilityBasedAnimTickOption =
            EVisibilityBasedAnimTickOption::OnlyTickPoseWhenRendered;
    }
};
```

### 5.4 애니메이션 공유

```cpp
// 같은 애니메이션을 재생하는 엔티티들은 포즈 공유 가능
// Leader-Follower 패턴

class USharedAnimationProcessor : public UMassProcessor
{
    // 그룹 내 리더 엔티티만 전체 애니메이션 계산
    // 나머지는 리더의 포즈 복사 (약간의 오프셋)
};
```

---

## 6. 실전 구현 예시

### 몬스터 시각화 Trait 설정

```cpp
UCLASS()
class UMonsterVisualizationTrait : public UMassVisualizationTrait
{
    GENERATED_BODY()

public:
    // High LOD: 풀 애니메이션 Actor
    UPROPERTY(EditAnywhere, Category = "High LOD")
    TSubclassOf<AActor> HighResMonsterActor = ABP_Monster_HighRes::StaticClass();

    // Medium LOD: 간소화 Actor
    UPROPERTY(EditAnywhere, Category = "Medium LOD")
    TSubclassOf<AActor> LowResMonsterActor = ABP_Monster_LowRes::StaticClass();

    // Low LOD: ISM 메시
    UPROPERTY(EditAnywhere, Category = "Low LOD")
    UStaticMesh* LowPolyMesh;

    virtual void BuildTemplate(FMassEntityTemplateBuildContext& BuildContext,
                               const UWorld& World) const override
    {
        Super::BuildTemplate(BuildContext, World);

        // High/Low Res Actor 설정
        FMassRepresentationParameters& RepParams =
            BuildContext.AddFragment<FMassRepresentationParameters>();

        RepParams.LODRepresentation[EMassLOD::High] =
            EMassRepresentationType::HighResSpawnedActor;
        RepParams.LODRepresentation[EMassLOD::Medium] =
            EMassRepresentationType::LowResSpawnedActor;
        RepParams.LODRepresentation[EMassLOD::Low] =
            EMassRepresentationType::StaticMeshInstance;
        RepParams.LODRepresentation[EMassLOD::Off] =
            EMassRepresentationType::None;

        // ISM 메시 설정
        FStaticMeshInstanceVisualizationMeshDesc MeshDesc;
        MeshDesc.Mesh = LowPolyMesh;
        MeshDesc.bCastShadow = false;
        BuildContext.AddStaticMeshVisualization(MeshDesc);

        // 애니메이션 상태 Fragment 추가
        BuildContext.AddFragment<FMonsterAnimStateFragment>();
    }
};
```

### 애니메이션 상태 업데이트 Processor

```cpp
UCLASS()
class UMonsterAnimStateProcessor : public UMassProcessor
{
    GENERATED_BODY()

public:
    UMonsterAnimStateProcessor()
    {
        ProcessingPhase = EMassProcessingPhase::PrePhysics;
    }

    virtual void ConfigureQueries() override
    {
        EntityQuery.AddRequirement<FMassVelocityFragment>(EMassFragmentAccess::ReadOnly);
        EntityQuery.AddRequirement<FMonsterAnimStateFragment>(EMassFragmentAccess::ReadWrite);
        EntityQuery.AddRequirement<FMonsterTag>(EMassFragmentPresence::All);
    }

    virtual void Execute(FMassEntityManager& EntityManager,
                         FMassExecutionContext& Context) override
    {
        EntityQuery.ForEachEntityChunk(EntityManager, Context,
            [](FMassExecutionContext& Context)
            {
                auto Velocities = Context.GetFragmentView<FMassVelocityFragment>();
                auto AnimStates = Context.GetMutableFragmentView<FMonsterAnimStateFragment>();

                const int32 NumEntities = Context.GetNumEntities();
                for (int32 i = 0; i < NumEntities; ++i)
                {
                    // 속도로부터 애니메이션 상태 계산
                    const FVector& Velocity = Velocities[i].Value;
                    AnimStates[i].CurrentSpeed = Velocity.Size();
                    AnimStates[i].MoveDirection = Velocity.GetSafeNormal();
                }
            });
    }
};
```

---

## 7. ISM 기반 가짜 애니메이션

원거리 몬스터는 ISM으로 렌더링되어 실제 애니메이션이 불가능합니다.
셰이더를 사용한 가짜 움직임으로 생동감을 줄 수 있습니다.

### 머티리얼 셰이더 예시

```
// Material Graph (Blueprint)

// 1. 흔들림 효과 (World Position Offset)
Time = Time * Speed
VerticalOffset = sin(Time + ObjectPosition.x * Frequency) * Amplitude
WorldPositionOffset = (0, 0, VerticalOffset)

// 2. 걷기 효과 (다리 움직임 시뮬레이션)
LegOffset = sin(Time * WalkSpeed + VertexPosition.x) * LegSwing
// UV 기반으로 다리 부분만 적용

// 3. 색상 변형 (CustomData 활용)
CustomData0 = PerInstanceCustomData[0]  // Hue Shift
FinalColor = HSVToRGB(BaseHue + CustomData0, Saturation, Value)
```

### ISM CustomData 설정

```cpp
// ISM 생성 시 커스텀 데이터 설정
MeshDesc.CustomDataFloats.Add(FMath::RandRange(0.0f, 1.0f));  // 색상 변형
MeshDesc.CustomDataFloats.Add(FMath::RandRange(0.0f, 2.0f));  // 애니메이션 오프셋
MeshDesc.CustomDataFloats.Add(Scale);                          // 크기 변형
```

---

## 8. 기존 애니메이션 리소스 활용 체크리스트

### 준비물

- [ ] 스켈레탈 메시 (High/Low LOD 버전)
- [ ] 애니메이션 블루프린트
- [ ] Low Poly 스태틱 메시 (ISM용)
- [ ] ISM용 머티리얼 (World Position Offset 포함)

### 설정 단계

1. [ ] Entity Config Asset 생성
2. [ ] Visualization Trait 추가 및 설정
3. [ ] High/Low Res Actor Blueprint 생성
4. [ ] Translator 설정 (필요시 커스텀)
5. [ ] LOD 거리 파라미터 조정
6. [ ] Actor 풀 크기 설정
7. [ ] 테스트 및 프로파일링

---

## 9. 성능 권장 사항

### 1000-5000 마리 규모

| LOD | 개수 | 애니메이션 | 비고 |
|-----|------|-----------|------|
| High | 50-100 | 풀 스켈레탈 | ~50본, AnimBP |
| Medium | 300-500 | 간소화 | ~20본, 단순 SM |
| Low | 나머지 | ISM 셰이더 | Static Mesh |
| Off | - | 없음 | 틱만 처리 |

### 권장 스켈레톤 복잡도

| LOD | 본 개수 | 트라이앵글 | 텍스처 |
|-----|---------|-----------|--------|
| High | 40-60 | 5000-10000 | 2048x2048 |
| Medium | 15-25 | 1000-3000 | 512x512 |
| Low (ISM) | - | 100-500 | 256x256 |

---

## 10. 다음 단계

애니메이션 통합을 이해했다면, 다음 문서에서 행동 로직 시스템을 살펴보겠습니다:

- **다음**: [05_BehaviorLogic.md](05_BehaviorLogic.md) - StateTree, Signal, Smart Objects를 활용한 몬스터 행동 구현
