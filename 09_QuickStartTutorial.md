# Quick Start Tutorial: 10분 만에 1000마리 몬스터 스폰하기

> **문서 목적**: Mass AI로 대량 몬스터 시스템 구축하는 실습 가이드
>
> **난이도**: ★★☆☆☆ (초급-중급)
>
> **예상 소요 시간**: 30-60분

---

## 들어가기 전에

### 이 튜토리얼에서 만들 것

```
결과물:
├── 1000마리 몬스터가 플레이어를 추격
├── 거리에 따라 LOD 자동 전환
├── ISM 렌더링으로 60fps 유지
└── 기본적인 피격/사망 처리
```

### 준비물

- Unreal Engine 5.7
- 빈 프로젝트 또는 기존 프로젝트
- C++ 프로젝트 (Blueprint만으로는 커스텀 Processor 제한)

---

## Step 1: 플러그인 활성화 (2분)

### 1.1 필요한 플러그인

Edit → Plugins에서 다음을 활성화:

```
□ MassEntity          ← 핵심!
□ MassGameplay        ← 게임플레이 기능
□ MassAI             ← AI 행동 (선택)
□ StructUtils        ← 구조체 유틸리티
□ StateTree          ← 행동 로직 (선택)
```

### 1.2 에디터 재시작

플러그인 활성화 후 **반드시 에디터 재시작!**

---

## Step 2: Build.cs 설정 (3분)

### 2.1 모듈 의존성 추가

`Source/YourProject/YourProject.Build.cs` 열기:

```csharp
using UnrealBuildTool;

public class YourProject : ModuleRules
{
    public YourProject(ReadOnlyTargetRules Target) : base(Target)
    {
        PCHUsage = PCHUsageMode.UseExplicitOrSharedPCHs;

        PublicDependencyModuleNames.AddRange(new string[]
        {
            "Core",
            "CoreUObject",
            "Engine",
            "InputCore",

            // Mass AI 관련 추가!
            "MassEntity",
            "MassCommon",
            "MassActors",
            "MassRepresentation",
            "MassLOD",
            "MassMovement",
            "MassSpawner",
            "MassSignals",
            "StructUtils"
        });
    }
}
```

### 2.2 빌드 확인

프로젝트 빌드 (Ctrl+Shift+B 또는 F5)
에러가 나면 플러그인 활성화 확인!

---

## Step 3: 몬스터용 Static Mesh 준비 (2분)

### 3.1 간단한 메시 사용

테스트용으로 엔진 기본 메시를 사용해도 돼요:

```
콘텐츠 브라우저:
Engine Content → BasicShapes → Cone 또는 Sphere

또는 기존 캐릭터 메시 사용
```

### 3.2 저폴리 버전 만들기 (선택)

ISM 렌더링용 저폴리 메시가 있으면 더 좋아요:
- 500 삼각형 이하 권장
- 단순한 머티리얼

---

## Step 4: Fragment 정의 (5분)

### 4.1 헤더 파일 생성

`Source/YourProject/Mass/MonsterFragments.h` 생성:

```cpp
#pragma once

#include "CoreMinimal.h"
#include "MassEntityTypes.h"
#include "MonsterFragments.generated.h"

//==================================================================
// 몬스터 체력 Fragment
//==================================================================
USTRUCT()
struct YOURPROJECT_API FMonsterHealthFragment : public FMassFragment
{
    GENERATED_BODY()

    float CurrentHealth = 100.0f;
    float MaxHealth = 100.0f;

    bool IsDead() const { return CurrentHealth <= 0.0f; }
};

//==================================================================
// 몬스터 상태 태그
//==================================================================
USTRUCT()
struct YOURPROJECT_API FMonsterAliveTag : public FMassTag
{
    GENERATED_BODY()
};

USTRUCT()
struct YOURPROJECT_API FMonsterDeadTag : public FMassTag
{
    GENERATED_BODY()
};

//==================================================================
// 몬스터 타입 태그 (필터링용)
//==================================================================
USTRUCT()
struct YOURPROJECT_API FMonsterTag : public FMassTag
{
    GENERATED_BODY()
};
```

---

## Step 5: 추적 Processor 만들기 (10분)

### 5.1 Processor 헤더

`Source/YourProject/Mass/MonsterChaseProcessor.h`:

```cpp
#pragma once

#include "CoreMinimal.h"
#include "MassProcessor.h"
#include "MonsterChaseProcessor.generated.h"

UCLASS()
class YOURPROJECT_API UMonsterChaseProcessor : public UMassProcessor
{
    GENERATED_BODY()

public:
    UMonsterChaseProcessor();

protected:
    virtual void ConfigureQueries() override;
    virtual void Execute(FMassEntityManager& EntityManager,
                         FMassExecutionContext& Context) override;

private:
    FMassEntityQuery EntityQuery;

    // 캐시
    FVector CachedPlayerLocation;
    float CachedDeltaTime;

    void CacheFrameData(const UWorld* World, float DeltaTime);
};
```

### 5.2 Processor 구현

`Source/YourProject/Mass/MonsterChaseProcessor.cpp`:

```cpp
#include "MonsterChaseProcessor.h"
#include "MassCommonFragments.h"
#include "MassMovementFragments.h"
#include "MassExecutionContext.h"
#include "MonsterFragments.h"
#include "Kismet/GameplayStatics.h"

UMonsterChaseProcessor::UMonsterChaseProcessor()
{
    // Processor 실행 순서 설정
    ExecutionOrder.ExecuteInGroup = UE::Mass::ProcessorGroupNames::Movement;
}

void UMonsterChaseProcessor::ConfigureQueries()
{
    // 어떤 엔티티를 처리할지 정의
    EntityQuery.AddRequirement<FTransformFragment>(EMassFragmentAccess::ReadOnly);
    EntityQuery.AddRequirement<FMassVelocityFragment>(EMassFragmentAccess::ReadWrite);
    EntityQuery.AddTagRequirement<FMonsterTag>(EMassFragmentPresence::All);
    EntityQuery.AddTagRequirement<FMonsterAliveTag>(EMassFragmentPresence::All);
}

void UMonsterChaseProcessor::Execute(FMassEntityManager& EntityManager,
                                      FMassExecutionContext& Context)
{
    // 프레임 데이터 캐싱
    CacheFrameData(EntityManager.GetWorld(), Context.GetDeltaTimeSeconds());

    // 모든 몬스터 처리
    EntityQuery.ForEachEntityChunk(
        EntityManager,
        Context,
        [this](FMassExecutionContext& ChunkContext)
        {
            // Fragment 뷰 획득
            const auto Transforms = ChunkContext.GetFragmentView<FTransformFragment>();
            auto Velocities = ChunkContext.GetMutableFragmentView<FMassVelocityFragment>();

            const int32 NumEntities = ChunkContext.GetNumEntities();
            const float ChaseSpeed = 400.0f;  // 설정 가능하게 변경 가능

            for (int32 i = 0; i < NumEntities; ++i)
            {
                // 현재 위치
                FVector MyLocation = Transforms[i].GetTransform().GetLocation();

                // 플레이어 방향 계산
                FVector Direction = (CachedPlayerLocation - MyLocation).GetSafeNormal();

                // 이동 속도 설정
                Velocities[i].Value = Direction * ChaseSpeed;
            }
        });
}

void UMonsterChaseProcessor::CacheFrameData(const UWorld* World, float DeltaTime)
{
    CachedDeltaTime = DeltaTime;

    // 플레이어 위치 캐싱
    if (World)
    {
        if (APawn* PlayerPawn = UGameplayStatics::GetPlayerPawn(World, 0))
        {
            CachedPlayerLocation = PlayerPawn->GetActorLocation();
        }
    }
}
```

---

## Step 6: Trait 정의 (5분)

### 6.1 Trait 헤더

`Source/YourProject/Mass/MonsterTrait.h`:

```cpp
#pragma once

#include "CoreMinimal.h"
#include "MassEntityTraitBase.h"
#include "MonsterTrait.generated.h"

UCLASS(meta = (DisplayName = "Monster Trait"))
class YOURPROJECT_API UMonsterTrait : public UMassEntityTraitBase
{
    GENERATED_BODY()

public:
    // 설정 가능한 값들
    UPROPERTY(EditAnywhere, Category = "Monster")
    float InitialHealth = 100.0f;

    UPROPERTY(EditAnywhere, Category = "Monster")
    float MoveSpeed = 400.0f;

protected:
    virtual void BuildTemplate(
        FMassEntityTemplateBuildContext& BuildContext,
        const UWorld& World) const override;
};
```

### 6.2 Trait 구현

`Source/YourProject/Mass/MonsterTrait.cpp`:

```cpp
#include "MonsterTrait.h"
#include "MassEntityTemplateRegistry.h"
#include "MonsterFragments.h"

void UMonsterTrait::BuildTemplate(
    FMassEntityTemplateBuildContext& BuildContext,
    const UWorld& World) const
{
    // Fragment 추가
    BuildContext.AddFragment<FMonsterHealthFragment>();

    // 초기값 설정
    FMonsterHealthFragment& Health = BuildContext.GetMutableFragment<FMonsterHealthFragment>();
    Health.CurrentHealth = InitialHealth;
    Health.MaxHealth = InitialHealth;

    // 태그 추가
    BuildContext.AddTag<FMonsterTag>();
    BuildContext.AddTag<FMonsterAliveTag>();
}
```

---

## Step 7: Entity Config 에셋 생성 (5분)

### 7.1 에셋 생성

```
콘텐츠 브라우저에서:
우클릭 → Miscellaneous → Mass Entity Config

이름: DA_MonsterConfig
```

### 7.2 Trait 설정

`DA_MonsterConfig` 더블클릭하여 편집:

```
Traits:
├── + Add Trait
│   ├── Transform Trait          ← 위치/회전
│   ├── Movement Trait           ← 이동
│   ├── Visualization Trait      ← 렌더링
│   │   ├── High Res Actor: (없음 또는 캐릭터 블루프린트)
│   │   └── Low Res Actor: (없음)
│   │   └── Static Mesh: SM_Cone (테스트용)
│   └── Monster Trait            ← 우리가 만든 것!
│       └── Initial Health: 100
```

### 7.3 Visualization Trait 상세 설정

```
Visualization Trait 설정:

LOD 설정:
├── Base LOD Distance:
│   ├── High: 0
│   ├── Medium: 5000 (50m)
│   ├── Low: 15000 (150m)
│   └── Off: 30000 (300m)
│
├── LOD Max Count:
│   ├── High: 100
│   ├── Medium: 400
│   └── Low: 5000
│
└── Static Mesh Instance Desc:
    ├── Mesh: SM_Cone (또는 저폴리 몬스터 메시)
    ├── Material: M_SimpleMaterial
    └── bCastShadow: false
```

---

## Step 8: Spawner 설정 (5분)

### 8.1 Mass Spawner Actor 배치

```
1. Place Actors 패널에서 "Mass Spawner" 검색
2. 레벨에 배치
3. 위치를 플레이어 스폰 근처로 이동
```

### 8.2 Spawner 설정

Mass Spawner Actor 선택 후 Details:

```
Mass Spawner 설정:

Entity Config: DA_MonsterConfig

Spawning:
├── Count: 1000              ← 스폰할 수
├── Spacing: 100             ← 간격 (cm)
├── Spawn Shape: Ring        ← 원형 분포
│   ├── Inner Radius: 500    ← 내부 반경
│   └── Outer Radius: 3000   ← 외부 반경
└── Auto Spawn On Begin Play: true
```

---

## Step 9: 테스트 실행 (2분)

### 9.1 플레이

Play 버튼 클릭!

### 9.2 예상 결과

```
정상 작동 시:
- 1000개의 콘/메시가 플레이어 주변에 원형으로 스폰
- 모두 플레이어를 향해 이동
- 가까운 것은 High LOD, 먼 것은 ISM으로 렌더링
- 60fps 유지 (또는 근접)
```

### 9.3 디버그 확인

콘솔 명령어:

```
stat MassEntity          # Entity 수 확인
stat MassRepresentation  # 렌더링 확인
stat fps                 # FPS 확인
```

---

## Step 10: 문제 해결

### 10.1 아무것도 안 보여요

```
체크리스트:
□ Entity Config가 Spawner에 설정되어 있나?
□ Visualization Trait에 메시가 설정되어 있나?
□ 플러그인이 활성화되어 있나?
□ 빌드 에러가 없나?
```

### 10.2 움직이지 않아요

```
체크리스트:
□ Movement Trait가 추가되어 있나?
□ MonsterChaseProcessor가 컴파일되었나?
□ 플레이어 Pawn이 레벨에 있나?
```

### 10.3 FPS가 너무 낮아요

```
체크리스트:
□ LODMaxCount가 설정되어 있나? (High: 100)
□ ISM 메시가 너무 복잡하진 않나? (<500 tris)
□ 그림자가 꺼져 있나?
```

### 10.4 크래시 발생

```
체크리스트:
□ 모든 Fragment가 GENERATED_BODY() 있나?
□ Trait의 BuildTemplate에서 Fragment 추가했나?
□ Processor Query 설정이 올바른가?
```

---

## 다음 단계

### 기능 추가하기

1. **피격 처리 추가**
   - FPendingDamageFragment 만들기
   - DamageProcessor 만들기
   - 플레이어 공격과 연동

2. **사망 처리 추가**
   - DeathProcessor 만들기
   - Dead Tag 추가/제거
   - 사망 이펙트

3. **애니메이션 추가**
   - High LOD Actor에 AnimBP 연결
   - Velocity → Walk/Run 전환

4. **StateTree 연동**
   - 복잡한 행동 패턴
   - Idle/Chase/Attack 상태

### 성능 튜닝

1. **LOD 거리 조정**
   - 게임에 맞게 거리 조절

2. **Processor 최적화**
   - 캐싱 추가
   - LOD별 처리 분리

3. **프로파일링**
   - Unreal Insights 사용
   - 병목 지점 확인

---

## 전체 코드 요약

### 파일 구조

```
Source/YourProject/
├── Mass/
│   ├── MonsterFragments.h
│   ├── MonsterTrait.h
│   ├── MonsterTrait.cpp
│   ├── MonsterChaseProcessor.h
│   └── MonsterChaseProcessor.cpp
└── YourProject.Build.cs

Content/
├── Mass/
│   └── DA_MonsterConfig.uasset
└── Maps/
    └── TestLevel.umap (Mass Spawner 포함)
```

### 체크리스트

```
설정 완료 체크리스트:

□ Step 1: 플러그인 활성화
□ Step 2: Build.cs 의존성 추가
□ Step 3: 메시 준비
□ Step 4: Fragment 정의
□ Step 5: Processor 구현
□ Step 6: Trait 정의
□ Step 7: Entity Config 생성
□ Step 8: Spawner 배치
□ Step 9: 테스트 실행
□ Step 10: 문제 해결 (필요시)
```

---

## 참고 문서

- [01_SystemOverview.md](01_SystemOverview.md) - Mass AI 개요
- [02_CoreArchitecture.md](02_CoreArchitecture.md) - 아키텍처 상세
- [03_RenderingAndLOD.md](03_RenderingAndLOD.md) - LOD 시스템
- [07_OptimizationGuide.md](07_OptimizationGuide.md) - 성능 최적화
