# 최적화 전략 및 구현 가이드

> **문서 목적**: 1000-5000 마리 규모 몬스터 시스템의 실전 최적화 전략 및 뱀파이어 서바이벌 스타일 구현 가이드

---

## 1. 성능 목표 설정

### 목표 지표

| 항목 | 목표치 | 비고 |
|------|--------|------|
| 몬스터 수 | 1000-5000 | 동시 활성 |
| 프레임 레이트 | 60 FPS | 최소 30 FPS |
| CPU 시간 (Mass AI) | < 5ms | 프레임당 |
| 메모리 | < 100MB | 몬스터 데이터 |
| 드로우 콜 | < 100 | ISM 배칭 |

### 프로파일링 기준

```
게임 스레드 예산 (60 FPS = 16.67ms):
├── 렌더링 준비: 3-4ms
├── 게임 로직: 5-6ms
│   └── Mass AI: < 3ms (목표)
├── 물리: 2-3ms
└── 기타: 3-4ms
```

---

## 2. LOD 최적화 설정

### 권장 LOD 구성

```cpp
// 1000-5000 마리 규모 최적화 LOD 설정
FMassVisualizationLODParameters GetOptimizedLODParams()
{
    FMassVisualizationLODParameters Params;

    // 거리 설정 (cm)
    Params.BaseLODDistance[EMassLOD::High] = 0.0f;        // 0m
    Params.BaseLODDistance[EMassLOD::Medium] = 5000.0f;   // 50m
    Params.BaseLODDistance[EMassLOD::Low] = 15000.0f;     // 150m
    Params.BaseLODDistance[EMassLOD::Off] = 30000.0f;     // 300m

    // 최대 개수 제한 (핵심!)
    Params.LODMaxCount[EMassLOD::High] = 100;     // Actor 100개
    Params.LODMaxCount[EMassLOD::Medium] = 400;   // Low Actor 400개
    Params.LODMaxCount[EMassLOD::Low] = 5000;     // ISM 무제한
    Params.LODMaxCount[EMassLOD::Off] = INT32_MAX;

    // 히스테리시스 (LOD 떨림 방지)
    Params.BufferHysteresisOnDistancePercentage = 15.0f;

    return Params;
}
```

### LOD별 처리 비용

| LOD | 개수 | 처리 비용/엔티티 | 총 비용 |
|-----|------|-----------------|---------|
| High | 100 | 0.05ms | 5.0ms |
| Medium | 400 | 0.005ms | 2.0ms |
| Low | 4500 | 0.0005ms | 2.25ms |
| Off | - | ~0 | ~0 |

---

## 3. Processor 최적화

### 3.1 배치 처리 최적화

```cpp
// 최적화된 Processor 구조
UCLASS()
class UOptimizedMonsterProcessor : public UMassProcessor
{
public:
    virtual void Execute(FMassEntityManager& EntityManager,
                         FMassExecutionContext& Context) override
    {
        // 1. 프레임 시작 시 공통 데이터 캐싱
        CacheFrameData(Context);

        // 2. 청크 단위 병렬 처리
        EntityQuery.ForEachEntityChunk(EntityManager, Context,
            [this](FMassExecutionContext& Context)
            {
                // 3. Fragment 뷰 한 번만 획득
                auto Transforms = Context.GetMutableFragmentView<FTransformFragment>();
                auto Movements = Context.GetMutableFragmentView<FMassDesiredMovementFragment>();

                // 4. 루프 최적화 (SIMD 친화적)
                const int32 NumEntities = Context.GetNumEntities();

                // 5. 분기 최소화
                for (int32 i = 0; i < NumEntities; ++i)
                {
                    ProcessEntity(i, Transforms[i], Movements[i]);
                }
            });
    }

private:
    // 프레임당 한 번만 계산
    FVector CachedPlayerLocation;
    float CachedDeltaTime;

    void CacheFrameData(const FMassExecutionContext& Context)
    {
        CachedDeltaTime = Context.GetDeltaTimeSeconds();
        CachedPlayerLocation = GetPlayerLocation();
    }

    FORCEINLINE void ProcessEntity(int32 Index,
                                   FTransformFragment& Transform,
                                   FMassDesiredMovementFragment& Movement)
    {
        // 인라인 처리로 함수 호출 오버헤드 제거
        FVector Direction = (CachedPlayerLocation -
                            Transform.Transform.GetLocation()).GetSafeNormal();
        Movement.DesiredVelocity = Direction * 400.0f;
    }
};
```

### 3.2 LOD 기반 처리 분기

```cpp
// LOD별 다른 처리
UCLASS()
class ULODBasedProcessor : public UMassProcessor
{
    virtual void Execute(FMassEntityManager& EntityManager,
                         FMassExecutionContext& Context) override
    {
        // High LOD 전용 쿼리
        HighLODQuery.ForEachEntityChunk(EntityManager, Context,
            [](FMassExecutionContext& Context)
            {
                // 복잡한 처리
                ProcessHighLOD(Context);
            });

        // Low LOD 전용 쿼리 (간소화)
        LowLODQuery.ForEachEntityChunk(EntityManager, Context,
            [](FMassExecutionContext& Context)
            {
                // 단순 처리
                ProcessLowLOD(Context);
            });
    }

    void ProcessHighLOD(FMassExecutionContext& Context)
    {
        // StateTree 연동, GAS 동기화 등
    }

    void ProcessLowLOD(FMassExecutionContext& Context)
    {
        // 방향 계산만
    }
};
```

### 3.3 업데이트 주기 최적화

```cpp
// 가변 틱 Fragment
USTRUCT()
struct FMassVariableTickFragment : public FMassChunkFragment
{
    GENERATED_BODY()

    float TimeUntilNextTick = 0.0f;
    float TickInterval = 0.1f;  // 100ms

    bool ShouldTickThisFrame(float DeltaTime)
    {
        TimeUntilNextTick -= DeltaTime;
        if (TimeUntilNextTick <= 0.0f)
        {
            TimeUntilNextTick = TickInterval;
            return true;
        }
        return false;
    }
};

// 가변 틱 Processor
UCLASS()
class UVariableTickProcessor : public UMassProcessor
{
    virtual void Execute(FMassEntityManager& EntityManager,
                         FMassExecutionContext& Context) override
    {
        const float DeltaTime = Context.GetDeltaTimeSeconds();

        EntityQuery.ForEachEntityChunk(EntityManager, Context,
            [DeltaTime](FMassExecutionContext& Context)
            {
                // 청크 Fragment로 틱 체크
                FMassVariableTickFragment& TickFragment =
                    Context.GetMutableChunkFragment<FMassVariableTickFragment>();

                if (!TickFragment.ShouldTickThisFrame(DeltaTime))
                {
                    return;  // 이 청크 전체 스킵
                }

                // 처리 진행
                // ...
            });
    }
};
```

---

## 4. 메모리 최적화

### 4.1 Fragment 크기 최소화

```cpp
// 나쁜 예: 불필요하게 큰 Fragment
USTRUCT()
struct FBadMonsterFragment : public FMassFragment
{
    FVector Position;           // 24 bytes
    FRotator Rotation;          // 12 bytes
    FString Name;               // 16+ bytes (동적 할당)
    TArray<FVector> Path;       // 16+ bytes (동적 할당)
    UObject* SomeObject;        // 8 bytes (GC 추적)
};  // 총 76+ bytes, 동적 할당 포함

// 좋은 예: 최소화된 Fragment
USTRUCT()
struct FGoodMonsterFragment : public FMassFragment
{
    FVector Position;           // 24 bytes
    FQuat Rotation;             // 16 bytes (FRotator보다 작음)
    uint8 NameIndex;            // 1 byte (룩업 테이블 사용)
    uint8 PathIndex;            // 1 byte (공유 경로 참조)
};  // 총 42 bytes, 동적 할당 없음
```

### 4.2 Shared Fragment 활용

```cpp
// 모든 몬스터가 공유하는 설정
USTRUCT()
struct FMonsterSharedConfig : public FMassConstSharedFragment
{
    GENERATED_BODY()

    float MoveSpeed = 400.0f;
    float AttackRange = 100.0f;
    float AttackDamage = 10.0f;
    float AttackCooldown = 1.5f;
};

// 몬스터 타입별 설정 (수십 개만 존재)
// vs
// 엔티티별 Fragment (수천 개 존재)
```

### 4.3 메모리 풀링

```cpp
// Actor 풀 설정
void SetupActorPools()
{
    UMassRepresentationSubsystem* RepSubsystem = GetRepSubsystem();

    // High Res Actor 풀
    int16 HighResIndex = RepSubsystem->FindOrAddTemplateActor(HighResActorClass);
    RepSubsystem->SetActorPoolSize(HighResIndex, 120);  // LODMaxCount + 버퍼

    // Low Res Actor 풀
    int16 LowResIndex = RepSubsystem->FindOrAddTemplateActor(LowResActorClass);
    RepSubsystem->SetActorPoolSize(LowResIndex, 450);
}
```

---

## 5. 렌더링 최적화

### 5.1 ISM 최적화

```cpp
// ISM 설정
FStaticMeshInstanceVisualizationMeshDesc GetOptimizedISMDesc()
{
    FStaticMeshInstanceVisualizationMeshDesc Desc;

    // 저폴리 메시 사용
    Desc.Mesh = LowPolyMonsterMesh;  // < 500 triangles

    // 그림자 비활성화 (원거리)
    Desc.bCastShadow = false;

    // 단순 머티리얼
    Desc.MaterialOverrides.Add(SimpleMaterial);

    // LOD 범위 설정
    Desc.MinLODSignificance = 2.0f;  // Low LOD부터
    Desc.MaxLODSignificance = 3.0f;

    return Desc;
}
```

### 5.2 그림자 최적화

```cpp
// LOD별 그림자 설정
// High LOD: 그림자 ON
// Medium LOD: 그림자 OFF (또는 단순화)
// Low LOD: 그림자 OFF
// Off LOD: 렌더링 없음

void ConfigureShadows(AActor* Actor, EMassLOD::Type LOD)
{
    if (UMeshComponent* Mesh = Actor->FindComponentByClass<UMeshComponent>())
    {
        bool bCastShadow = (LOD == EMassLOD::High);
        Mesh->SetCastShadow(bCastShadow);
    }
}
```

### 5.3 컬링 최적화

```cpp
// 프러스텀 컬링 최적화
// MassRepresentationProcessor가 자동 처리

// 추가 최적화: 오클루전 컬링
// - 큰 오브젝트 뒤의 몬스터 제외
// - ISM은 자동 하드웨어 오클루전 지원
```

---

## 6. 뱀파이어 서바이벌 스타일 구현

### 6.1 스폰 시스템

```cpp
// 웨이브 기반 스폰
UCLASS()
class UMonsterWaveSpawner : public UObject
{
public:
    void SpawnWave(int32 WaveNumber)
    {
        // 웨이브별 스폰 수 계산
        int32 SpawnCount = CalculateWaveSize(WaveNumber);

        // 플레이어 주변 스폰
        TArray<FTransform> SpawnTransforms;
        GenerateSpawnLocations(SpawnCount, SpawnTransforms);

        // Mass Spawner로 대량 스폰
        UMassSpawnerSubsystem* Spawner = GetSpawnerSubsystem();
        Spawner->SpawnEntities(MonsterConfig, SpawnTransforms);
    }

private:
    void GenerateSpawnLocations(int32 Count, TArray<FTransform>& OutTransforms)
    {
        FVector PlayerPos = GetPlayerLocation();

        for (int32 i = 0; i < Count; ++i)
        {
            // 화면 밖 원형 분포
            float Angle = FMath::RandRange(0.0f, 2.0f * PI);
            float Distance = FMath::RandRange(SpawnMinDistance, SpawnMaxDistance);

            FVector SpawnPos = PlayerPos + FVector(
                FMath::Cos(Angle) * Distance,
                FMath::Sin(Angle) * Distance,
                0.0f);

            OutTransforms.Add(FTransform(SpawnPos));
        }
    }

    int32 CalculateWaveSize(int32 WaveNumber)
    {
        // 웨이브 진행에 따라 증가
        return FMath::Min(BaseWaveSize + WaveNumber * WaveGrowth, MaxMonstersPerWave);
    }

    UPROPERTY(EditAnywhere)
    int32 BaseWaveSize = 50;

    UPROPERTY(EditAnywhere)
    int32 WaveGrowth = 10;

    UPROPERTY(EditAnywhere)
    int32 MaxMonstersPerWave = 200;

    UPROPERTY(EditAnywhere)
    float SpawnMinDistance = 1500.0f;  // 15m

    UPROPERTY(EditAnywhere)
    float SpawnMaxDistance = 3000.0f;  // 30m
};
```

### 6.2 플레이어 추적 + 군집 회피

```cpp
UCLASS()
class USwarmMovementProcessor : public UMassProcessor
{
    GENERATED_BODY()

public:
    UPROPERTY(EditAnywhere)
    float ChaseSpeed = 350.0f;

    UPROPERTY(EditAnywhere)
    float SeparationRadius = 80.0f;

    UPROPERTY(EditAnywhere)
    float SeparationWeight = 0.3f;

    virtual void Execute(FMassEntityManager& EntityManager,
                         FMassExecutionContext& Context) override
    {
        const FVector PlayerPos = GetCachedPlayerLocation();

        // 공간 해시 그리드 (이웃 탐색 최적화)
        FSpatialHashGrid Grid;
        BuildSpatialGrid(EntityManager, Grid);

        EntityQuery.ForEachEntityChunk(EntityManager, Context,
            [=, &Grid](FMassExecutionContext& Context)
            {
                auto Transforms = Context.GetFragmentView<FTransformFragment>();
                auto Movements = Context.GetMutableFragmentView<FMassDesiredMovementFragment>();

                for (int32 i = 0; i < Context.GetNumEntities(); ++i)
                {
                    FVector MyPos = Transforms[i].Transform.GetLocation();

                    // 1. 플레이어 추적
                    FVector ChaseDir = (PlayerPos - MyPos).GetSafeNormal();

                    // 2. 군집 분리 (간소화 버전)
                    FVector SeparationDir = CalculateSeparation(
                        MyPos, Grid, SeparationRadius);

                    // 3. 합성
                    FVector FinalDir = (ChaseDir + SeparationDir * SeparationWeight).GetSafeNormal();
                    Movements[i].DesiredVelocity = FinalDir * ChaseSpeed;
                }
            });
    }

private:
    FVector CalculateSeparation(const FVector& MyPos,
                                const FSpatialHashGrid& Grid,
                                float Radius)
    {
        FVector SeparationForce = FVector::ZeroVector;

        // 그리드에서 근처 엔티티만 검사
        TArray<FVector> Neighbors;
        Grid.GetNeighbors(MyPos, Radius, Neighbors);

        for (const FVector& OtherPos : Neighbors)
        {
            FVector Diff = MyPos - OtherPos;
            float Dist = Diff.Size();
            if (Dist > 0.0f && Dist < Radius)
            {
                SeparationForce += Diff.GetSafeNormal() * (1.0f - Dist / Radius);
            }
        }

        return SeparationForce.GetSafeNormal();
    }
};
```

### 6.3 접촉 데미지

```cpp
UCLASS()
class UContactDamageProcessor : public UMassProcessor
{
    GENERATED_BODY()

public:
    UPROPERTY(EditAnywhere)
    float ContactRadius = 50.0f;

    UPROPERTY(EditAnywhere)
    float DamagePerSecond = 10.0f;

    virtual void Execute(FMassEntityManager& EntityManager,
                         FMassExecutionContext& Context) override
    {
        const FVector PlayerPos = GetCachedPlayerLocation();
        const float ContactRadiusSq = FMath::Square(ContactRadius);
        const float DeltaTime = Context.GetDeltaTimeSeconds();

        float TotalDamage = 0.0f;

        EntityQuery.ForEachEntityChunk(EntityManager, Context,
            [=, &TotalDamage](FMassExecutionContext& Context)
            {
                auto Transforms = Context.GetFragmentView<FTransformFragment>();

                for (int32 i = 0; i < Context.GetNumEntities(); ++i)
                {
                    float DistSq = FVector::DistSquared(
                        Transforms[i].Transform.GetLocation(),
                        PlayerPos);

                    if (DistSq <= ContactRadiusSq)
                    {
                        // 접촉 데미지 누적
                        TotalDamage += DamagePerSecond * DeltaTime;
                    }
                }
            });

        // 플레이어에게 누적 데미지 적용
        if (TotalDamage > 0.0f)
        {
            ApplyDamageToPlayer(TotalDamage);
        }
    }
};
```

### 6.4 영역 공격 (플레이어 무기)

```cpp
// 플레이어 공격이 Mass 몬스터에게 데미지
void ApplyAreaDamage(const FVector& Center, float Radius, float Damage)
{
    UMassEntitySubsystem* EntitySubsystem = GetEntitySubsystem();
    FMassEntityManager& EntityManager = EntitySubsystem->GetMutableEntityManager();

    FMassEntityQuery DamageQuery;
    DamageQuery.AddRequirement<FTransformFragment>(EMassFragmentAccess::ReadOnly);
    DamageQuery.AddRequirement<FMonsterHealthFragment>(EMassFragmentAccess::ReadWrite);
    DamageQuery.AddRequirement<FMonsterTag>(EMassFragmentPresence::All);
    DamageQuery.AddRequirement<FDeadTag>(EMassFragmentPresence::None);

    const float RadiusSq = FMath::Square(Radius);

    DamageQuery.ForEachEntityChunk(EntityManager, Context,
        [=](FMassExecutionContext& Context)
        {
            auto Transforms = Context.GetFragmentView<FTransformFragment>();
            auto Healths = Context.GetMutableFragmentView<FMonsterHealthFragment>();

            for (int32 i = 0; i < Context.GetNumEntities(); ++i)
            {
                float DistSq = FVector::DistSquared(
                    Transforms[i].Transform.GetLocation(),
                    Center);

                if (DistSq <= RadiusSq)
                {
                    Healths[i].CurrentHealth -= Damage;

                    if (Healths[i].CurrentHealth <= 0.0f)
                    {
                        // 사망 처리
                        Context.Defer().AddTag<FDeadTag>(Context.GetEntity(i));

                        // 아이템 드랍 (확률)
                        if (FMath::RandRange(0.0f, 1.0f) < DropChance)
                        {
                            QueueItemDrop(Transforms[i].Transform.GetLocation());
                        }
                    }
                }
            }
        });
}
```

---

## 7. 프로파일링 및 디버깅

### 7.1 콘솔 명령어

```
// Mass Entity 통계
stat MassEntity

// 렌더링 통계
stat SceneRendering
stat GPU

// Mass 디버그
Mass.Debug.Entities 1
Mass.Debug.Processors 1
Mass.Debug.LOD 1
Mass.Debug.Representation 1
```

### 7.2 커스텀 프로파일링

```cpp
// Processor에 프로파일링 추가
UCLASS()
class UProfiledProcessor : public UMassProcessor
{
    virtual void Execute(FMassEntityManager& EntityManager,
                         FMassExecutionContext& Context) override
    {
        SCOPE_CYCLE_COUNTER(STAT_MonsterMovement);

        // 처리 로직
    }
};

// 통계 정의
DECLARE_STATS_GROUP(TEXT("MassMonsters"), STATGROUP_MassMonsters, STATCAT_Advanced);
DECLARE_CYCLE_STAT(TEXT("Monster Movement"), STAT_MonsterMovement, STATGROUP_MassMonsters);
```

### 7.3 시각적 디버깅

```cpp
#if WITH_MASSENTITY_DEBUG
void DrawDebugInfo(const FMassEntityManager& EntityManager)
{
    // LOD별 색상 표시
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
                FColor Color = GetLODColor(LODs[i].LOD);
                DrawDebugPoint(GetWorld(),
                    Transforms[i].Transform.GetLocation(),
                    10.0f, Color);
            }
        });
}
#endif
```

---

## 8. 최적화 체크리스트

### 설정 단계

- [ ] 플러그인 활성화 (MassEntity, MassGameplay, StateTree)
- [ ] 모듈 의존성 추가 (Build.cs)
- [ ] Entity Config Asset 생성
- [ ] Visualization Trait 설정
- [ ] LOD 파라미터 조정

### Processor 단계

- [ ] 커스텀 Processor 구현
- [ ] Fragment 크기 최소화
- [ ] Shared Fragment 활용
- [ ] 배치 처리 최적화
- [ ] LOD 기반 처리 분기

### 렌더링 단계

- [ ] ISM 메시 최적화 (< 500 triangles)
- [ ] 그림자 비활성화 (원거리)
- [ ] Actor 풀 크기 설정
- [ ] 머티리얼 인스턴싱

### 테스트 단계

- [ ] 1000개 몬스터 테스트
- [ ] 3000개 몬스터 테스트
- [ ] 5000개 몬스터 테스트
- [ ] 프로파일링 및 병목 확인
- [ ] 메모리 사용량 확인

---

## 9. 성능 튜닝 가이드

### CPU 병목 해결

| 증상 | 원인 | 해결책 |
|------|------|--------|
| Processor 시간 높음 | 복잡한 로직 | LOD별 처리 분기 |
| 분기 예측 실패 | if문 과다 | 데이터 기반 처리 |
| 캐시 미스 | Fragment 크기 | Fragment 최소화 |
| 함수 호출 오버헤드 | 많은 함수 호출 | FORCEINLINE |

### GPU 병목 해결

| 증상 | 원인 | 해결책 |
|------|------|--------|
| 드로우 콜 과다 | Actor 너무 많음 | LODMaxCount 조정 |
| 버텍스 처리 느림 | 메시 복잡 | LOD 메시 사용 |
| 픽셀 오버드로 | 겹치는 렌더링 | 오클루전 컬링 |

### 메모리 병목 해결

| 증상 | 원인 | 해결책 |
|------|------|--------|
| GC 스파이크 | UObject 과다 | Fragment 사용 |
| 메모리 단편화 | 동적 할당 | 풀링, 정적 배열 |
| 캐시 스래싱 | 데이터 분산 | Archetype 최적화 |

---

## 10. 마무리

### 핵심 요약

1. **LOD가 핵심**: 적절한 LOD 설정이 성능의 80%
2. **배치 처리**: 개별 처리 대신 청크 단위 처리
3. **데이터 지향**: Fragment 최소화, Shared Fragment 활용
4. **ISM 활용**: 원거리 렌더링 최적화
5. **프로파일링**: 지속적인 측정과 튜닝

### 예상 성과

올바르게 구현 시:
- 1000-5000 몬스터 60 FPS 유지
- CPU 시간 < 5ms
- 메모리 < 100MB
- 기존 Actor 방식 대비 10-20배 성능 향상

### 다음 단계

이 문서들을 바탕으로:
1. 간단한 프로토타입 구현
2. 기본 스폰/이동 테스트
3. 점진적 기능 추가
4. 프로파일링 및 최적화

---

## 부록: 참조 소스 경로

```
엔진 코어:
C:\Program Files\Epic Games\UE_5.7.1\UE_5.7\Engine\Source\Runtime\MassEntity\

MassGameplay 플러그인:
C:\Program Files\Epic Games\UE_5.7.1\UE_5.7\Engine\Plugins\Runtime\MassGameplay\

StateTree 플러그인:
C:\Program Files\Epic Games\UE_5.7.1\UE_5.7\Engine\Plugins\Runtime\GameplayStateTree\
```

---

**문서 작성 완료** - Mass AI 프레임워크 스터디
